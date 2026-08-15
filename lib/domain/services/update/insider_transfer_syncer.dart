import 'package:drift/drift.dart';

import 'package:daredevil/core/exceptions/app_exception.dart';
import 'package:daredevil/core/utils/logger.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/data/remote/tpex_client.dart';
import 'package:daredevil/data/remote/twse_client.dart';

/// 內部人股權轉讓同步器
///
/// 從 TWSE(t187ap12_L)與 TPEX(ap12_O)取得董監事/經理人/大股東的
/// 股權轉讓申報記錄,寫入 InsiderTransfer 表。
///
/// 2026-08-05 補接上市源:原本只有上櫃,面板左欄(上市)永遠空白——
/// 空白被誤讀成「今天沒異動」比缺功能更糟。雙源 per-source 隔離
/// (單側連線故障不砍另一側;同日 TPEx 大檔曾三連斷線的實例)。
///
/// - 資料來源為「最新」全市場轉讓申報（非歷史）
/// - 使用 InsertOrReplace 避免重複
/// - 僅寫入 StockMaster 中存在的股票（FK constraint）
class InsiderTransferSyncer {
  const InsiderTransferSyncer({
    required AppDatabase database,
    TpexClient? tpexClient,
    TwseClient? twseClient,
  }) : _db = database,
       _tpex = tpexClient,
       _twse = twseClient;

  final AppDatabase _db;

  /// 兩源可各自為 null(測試/降級 harness);生產接線(factory/providers)
  /// 恆為雙源。null 源逐一跳過並記 debug,不靜默:單側缺席在 log 可見。
  final TpexClient? _tpex;
  final TwseClient? _twse;

  /// 同步內部人轉讓資料
  ///
  /// 回傳寫入的筆數。
  Future<int> sync() async {
    try {
      // 雙源 per-source 隔離:單側故障記 warning、另一側照常;
      // 兩側都掛才往上拋(RateLimitException 一律直接 rethrow)
      final transfers = <TpexInsiderTransfer>[];
      Object? firstError;
      final fetchers = <String, Future<List<TpexInsiderTransfer>> Function()>{
        if (_twse != null) '上市': _twse.getInsiderTransfers,
        if (_tpex != null) '上櫃': _tpex.getInsiderTransfers,
      };
      if (fetchers.length < 2) {
        AppLogger.debug(
          'InsiderTransferSyncer',
          '僅 ${fetchers.keys.join()} 源可用(另一側未接線)',
        );
      }
      for (final entry in fetchers.entries) {
        try {
          transfers.addAll(await entry.value());
        } on RateLimitException {
          rethrow;
        } catch (e) {
          AppLogger.warning(
            'InsiderTransferSyncer',
            '${entry.key}源失敗,另一側照常',
            e,
          );
          firstError ??= e;
        }
      }
      if (transfers.isEmpty) {
        if (firstError != null) throw firstError;
        AppLogger.debug('InsiderTransferSyncer', 'API 回傳空資料');
        return 0;
      }

      // 取得 DB 中所有已知股票（FK constraint）
      final knownStocks = await _db.getAllActiveStocks();
      final knownSymbols = knownStocks.map((s) => s.symbol).toSet();

      final companions = <InsiderTransferCompanion>[];
      for (final t in transfers) {
        if (!knownSymbols.contains(t.symbol)) continue;

        companions.add(
          InsiderTransferCompanion(
            symbol: Value(t.symbol),
            reportDate: Value(t.reportDate),
            identity: Value(t.identity),
            name: Value(t.name),
            transferMethod: Value(t.transferMethod),
            transferShares: Value(t.transferShares),
            currentHolding: Value(t.currentHolding),
            validPeriodStart: Value(t.validPeriodStart),
            validPeriodEnd: Value(t.validPeriodEnd),
          ),
        );
      }

      if (companions.isEmpty) {
        AppLogger.debug('InsiderTransferSyncer', '無可寫入的轉讓資料');
        return 0;
      }

      // PK 碰撞偵測哨(2026-08-05 加,2026-08-16 更新語意):原本 PK 不含
      // 轉讓方式,此哨把「無實證」變成「發生即留痕」——2026-08-14 留到痕了
      // (2442 一位經理人未成年子女同日三筆,7 筆進 5 筆出),於是 PK 補上
      // transfer_method。哨子保留:現在它偵測的是**完全相同的重複申報**,
      // 那代表上游資料本身有問題,不再是 schema 的鍋。
      final pkSeen = <String>{};
      for (final c in companions) {
        final pk =
            '${c.symbol.value}|${c.reportDate.value}'
            '|${c.identity.value}|${c.name.value}|${c.transferMethod.value}';
        if (!pkSeen.add(pk)) {
          AppLogger.warning(
            'InsiderTransferSyncer',
            'PK 碰撞:$pk 完全相同的申報重複出現,將塌縮成一筆——'
                '轉讓方式已納入 PK(2026-08-16),此處剩下的碰撞代表上游資料重複',
          );
        }
      }

      await _db.insertInsiderTransfers(companions);

      // 報**實際寫入列數**而非輸入陣列長度(2026-08-16):insertOrReplace 會
      // 把同 PK 的多筆併成一列,而 `pkSeen` 正是去重後的 PK 集合。2026-08-14
      // 實機收到 7 筆、DB 只有 5 筆,日誌卻報 7 —— 資料少了兩筆而宣稱完整,
      // 那比少兩筆本身更危險。回傳值同樣要修:UpdateService 也吃這個數字。
      AppLogger.info(
        'InsiderTransferSyncer',
        '同步完成: ${pkSeen.length} 筆轉讓申報'
            '${pkSeen.length == companions.length ? '' : '(來源 ${companions.length} 筆,'
                      '去重 ${companions.length - pkSeen.length} 筆)'}',
      );
      return pkSeen.length;
    } on RateLimitException {
      rethrow;
    } on NetworkException {
      rethrow;
    } catch (e) {
      AppLogger.warning('InsiderTransferSyncer', '同步失敗', e);
      rethrow;
    }
  }
}
