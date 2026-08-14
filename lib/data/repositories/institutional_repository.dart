import 'package:drift/drift.dart';

import 'package:daredevil/core/constants/data_freshness.dart';
import 'package:daredevil/core/constants/rule_params.dart';
import 'package:daredevil/core/utils/clock.dart';
import 'package:daredevil/core/utils/date_context.dart';
import 'package:daredevil/core/exceptions/app_exception.dart';
import 'package:daredevil/core/utils/logger.dart';
import 'package:daredevil/core/utils/safe_execution.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/data/models/extensions/dto_extensions.dart';
import 'package:daredevil/data/remote/finmind_client.dart';
import 'package:daredevil/data/remote/tpex_client.dart';
import 'package:daredevil/data/remote/twse_client.dart';
import 'package:daredevil/domain/repositories/institutional_repository.dart';

/// 三大法人買賣超資料 Repository
class InstitutionalRepository implements IInstitutionalRepository {
  InstitutionalRepository({
    required AppDatabase database,
    required FinMindClient finMindClient,
    required TwseClient twseClient,
    required TpexClient tpexClient,
    AppClock clock = const SystemClock(),
  }) : _db = database,
       _client = finMindClient,
       _twseClient = twseClient,
       _tpexClient = tpexClient,
       _clock = clock;

  final AppDatabase _db;
  final FinMindClient _client;
  final TwseClient _twseClient;
  final TpexClient _tpexClient;
  final AppClock _clock;

  /// 取得法人資料歷史供分析使用
  ///
  /// 若可用，回傳 [RuleParams.lookbackPrice] 天的資料
  @override
  Future<List<DailyInstitutionalEntry>> getInstitutionalHistory(
    String symbol, {
    int? days,
  }) async {
    final lookback = days ?? RuleParams.lookbackPrice;
    final startDate = _clock.now().subtract(Duration(days: lookback + 30));

    return _db.getInstitutionalHistory(symbol, startDate: startDate);
  }

  /// 同步單檔股票的法人資料（FinMind per-symbol 路徑）
  ///
  /// ⚠️ landmine：此路徑**目前未接入 daily 更新流程**（daily 走
  /// [syncAllMarketInstitutional] 的 TWSE/TPEx 整批）。它經 FinMind 的
  /// FinMindInstitutionalExt.toDatabaseCompanion
  /// (dto_extensions.dart) 寫入，而該 companion **不寫
  /// dealer_self_net（會留 NULL）**，且 FinMind 的 dealer_net 是
  /// 「自行+避險」buy−sell 衍生、與 TWSE row[11] 口徑不完全等價。
  /// **若日後要把它重新接到 daily_institutional 寫入流程，必須先補
  /// dealer_self_net + 對齊口徑**，否則會製造 NULL self_net + 異口徑髒資料。
  @override
  Future<int> syncInstitutionalData(
    String symbol, {
    required DateTime startDate,
    DateTime? endDate,
  }) async {
    try {
      final data = await _client.getInstitutionalData(
        stockId: symbol,
        startDate: DateContext.formatYmd(startDate),
        endDate: endDate != null ? DateContext.formatYmd(endDate) : null,
      );

      final entries = data.map((item) {
        // 正規化日期，確保時間部分為 00:00:00（避免同日重複）
        final parsed = DateTime.parse(item.date);
        final normalizedDate = DateContext.normalize(parsed);
        return item.toDatabaseCompanion(normalizedDate);
      }).toList();

      await _db.insertInstitutionalData(entries);

      return entries.length;
    } on RateLimitException catch (e) {
      AppLogger.warning('InstitutionalRepo', '$symbol: 法人資料同步觸發 API 速率限制', e);
      rethrow;
    } on NetworkException {
      rethrow;
    } catch (e) {
      throw DatabaseException(
        'Failed to sync institutional data for $symbol',
        e,
      );
    }
  }

  /// 同步指定日期的全市場法人資料
  ///
  /// 使用 TWSE T86 API + TPEX API（免費、全市場）。
  /// 可分析非自選股的法人動向。
  @override
  Future<int> syncAllMarketInstitutional(
    DateTime date, {
    bool force = false,
  }) async {
    try {
      // 提高閾值以涵蓋上市+上櫃股票。
      //
      // ⚠️ 合併門檻的已知取捨（2026-07-15 review）：單邊最高 ~1,214 筆
      // < 1,500，故「單市場缺漏卻被判完整」不會發生（安全方向成立）；
      // 但某市場**持續**失敗的日子會每輪重抓（TWSE 健康側白抓一次）。
      // 接受不改 per-market 的理由：與缺漏日回補（margin）不同，此迴圈
      // 無 per-run 上限、不會被幽靈缺漏日餓死，且視窗滾動（日常 15 天）
      // 會讓壞日自然過期——代價是有界的免費呼叫，不是收斂性問題。
      // 若 TWSE 上市家數成長逼近 1,500，此假設失效，屆時改
      // per-market（照 countMarginTradingByDateAndMarket 模式）。
      if (!force) {
        final existingCount = await _db.getInstitutionalCountForDate(date);
        if (existingCount > DataFreshness.fullMarketThreshold) {
          return existingCount;
        }
      }

      // 並行取得上市與上櫃法人資料（錯誤隔離，允許部分成功）
      // safeAwait 立即包裹原始 Future，避免 unhandled async error
      final (twseData, tpexData) = await safeAwaitPair(
        _twseClient.getAllInstitutionalData(date: date),
        _tpexClient.getAllInstitutionalData(date: date),
        firstDefault: <TwseInstitutional>[],
        secondDefault: <TpexInstitutional>[],
        tag: 'InstitutionalRepo',
        firstDescription: '上市法人資料取得失敗，繼續處理上櫃',
        secondDescription: '上櫃法人資料取得失敗，繼續處理上市',
      );

      if (twseData.isEmpty && tpexData.isEmpty) return 0;

      // 取得有效股票代碼以避免 Foreign Key 錯誤
      final stockList = await _db.getAllActiveStocks();
      final validSymbols = stockList.map((s) => s.symbol).toSet();

      // 過濾上市法人資料
      final validTwseData = twseData
          .where(
            (item) =>
                validSymbols.contains(item.code) &&
                (item.totalNet != 0 ||
                    item.foreignNet != 0 ||
                    item.investmentTrustNet != 0),
          )
          .toList();

      // 過濾上櫃法人資料
      final validTpexData = tpexData
          .where(
            (item) =>
                validSymbols.contains(item.code) &&
                (item.totalNet != 0 ||
                    item.foreignNet != 0 ||
                    item.investmentTrustNet != 0),
          )
          .toList();

      // TWSE/TPEX API 回傳股數，直接儲存（規則參數單位為股）
      // dealerSelfNet 與 dealerNet 採同一單位轉換（兩者皆直接存原值）
      final twseEntries = _toInstitutionalEntries(
        validTwseData,
        (i) => (
          code: i.code,
          date: i.date,
          foreignNet: i.foreignNet.toDouble(),
          investmentTrustNet: i.investmentTrustNet.toDouble(),
          dealerNet: i.dealerNet.toDouble(),
          dealerSelfNet: i.dealerSelfNet.toDouble(),
        ),
      );
      final tpexEntries = _toInstitutionalEntries(
        validTpexData,
        (i) => (
          code: i.code,
          date: i.date,
          foreignNet: i.foreignNet.toDouble(),
          investmentTrustNet: i.investmentTrustNet.toDouble(),
          dealerNet: i.dealerNet.toDouble(),
          dealerSelfNet: i.dealerSelfNet.toDouble(),
        ),
      );

      // 合併並寫入
      final allEntries = [...twseEntries, ...tpexEntries];
      await _db.insertInstitutionalData(allEntries);

      AppLogger.info(
        'InstitutionalRepo',
        '法人同步: ${allEntries.length} 筆 (上市 ${twseEntries.length}, 上櫃 ${tpexEntries.length})',
      );

      return allEntries.length;
    } on RateLimitException {
      rethrow;
    } on NetworkException {
      rethrow;
    } catch (e) {
      throw DatabaseException('Failed to sync all institutional data', e);
    }
  }

  /// 用 TWSE + TPEx batch endpoint 回補單一交易日**指定股票**的法人資料
  ///
  /// 詳細語意見 [IInstitutionalRepository.backfillInstitutionalByDate]。
  ///
  /// 實作走 [TwseClient.getAllInstitutionalData] + [TpexClient.getAllInstitutionalData]
  /// （兩個都是該市場官方免費 daily batch endpoint），用 [safeAwait] 隔離
  /// 兩個 source 的失敗，再依 [targetSymbols] 過濾後 batch insert。
  @override
  Future<int> backfillInstitutionalByDate({
    required DateTime date,
    required Set<String> targetSymbols,
  }) async {
    try {
      // 並行抓 TWSE + TPEx 法人資料。任一失敗回空 list 不阻斷另一個。
      final (twseData, tpexData) = await safeAwaitPair(
        _twseClient.getAllInstitutionalData(date: date),
        _tpexClient.getAllInstitutionalData(date: date),
        firstDefault: <TwseInstitutional>[],
        secondDefault: <TpexInstitutional>[],
        tag: 'InstitutionalRepo',
        firstDescription:
            '上市法人 backfill 失敗 (${DateContext.formatYmd(date)})，繼續處理上櫃',
        secondDescription:
            '上櫃法人 backfill 失敗 (${DateContext.formatYmd(date)})，繼續處理上市',
      );

      if (twseData.isEmpty && tpexData.isEmpty) return 0;

      // 用 targetSymbols 過濾 + 跳過全 0 行（與 syncAllMarketInstitutional
      // 同邏輯：節省 DB 空間，0 0 0 對 rule engine 沒有訊號）
      final validTwseData = twseData
          .where(
            (item) =>
                targetSymbols.contains(item.code) &&
                (item.totalNet != 0 ||
                    item.foreignNet != 0 ||
                    item.investmentTrustNet != 0),
          )
          .toList();

      final validTpexData = tpexData
          .where(
            (item) =>
                targetSymbols.contains(item.code) &&
                (item.totalNet != 0 ||
                    item.foreignNet != 0 ||
                    item.investmentTrustNet != 0),
          )
          .toList();

      final twseEntries = _toInstitutionalEntries(
        validTwseData,
        (i) => (
          code: i.code,
          date: i.date,
          foreignNet: i.foreignNet.toDouble(),
          investmentTrustNet: i.investmentTrustNet.toDouble(),
          dealerNet: i.dealerNet.toDouble(),
          dealerSelfNet: i.dealerSelfNet.toDouble(),
        ),
      );
      final tpexEntries = _toInstitutionalEntries(
        validTpexData,
        (i) => (
          code: i.code,
          date: i.date,
          foreignNet: i.foreignNet.toDouble(),
          investmentTrustNet: i.investmentTrustNet.toDouble(),
          dealerNet: i.dealerNet.toDouble(),
          dealerSelfNet: i.dealerSelfNet.toDouble(),
        ),
      );

      final allEntries = [...twseEntries, ...tpexEntries];
      if (allEntries.isEmpty) return 0;

      await _db.insertInstitutionalData(allEntries);
      return allEntries.length;
    } on RateLimitException {
      rethrow;
    } on NetworkException {
      rethrow;
    } catch (e) {
      throw DatabaseException(
        'Failed to backfill institutional for ${DateContext.formatYmd(date)}',
        e,
      );
    }
  }

  /// 清除所有法人資料
  ///
  /// 用於單位修正後強制重新同步，避免新舊資料單位混用
  @override
  Future<int> clearAllData() => _db.clearAllInstitutionalData();

  /// 該日法人資料是否已達完整門檻
  ///
  /// 與 [syncAllMarketInstitutional] 內部的新鮮度檢查同一判準（合併門檻的
  /// 取捨見該處註解）。獨立成方法是讓回補迴圈能在 1 秒節流**之前**預檢：
  /// 穩態下回補窗全完整，原本每輪白睡 ~10 秒（force 深回補 ~62 秒）、
  /// 一次 API 都沒打。
  @override
  Future<bool> isDayComplete(DateTime date) async {
    final count = await _db.getInstitutionalCountForDate(date);
    return count > DataFreshness.fullMarketThreshold;
  }

  /// app_settings 的法人口徑版本 key
  static const String _dataVersionKey = 'institutional_data_version';
  static const String _deepBackfillPendingKey =
      'institutional_deep_backfill_pending';

  @override
  Future<bool> isDeepBackfillPending() async =>
      await _db.getSetting(_deepBackfillPendingKey) == '1';

  @override
  Future<void> markDeepBackfillComplete() =>
      _db.setSetting(_deepBackfillPendingKey, '0');

  /// 口徑版本檢核：**實際版本不符**才一次性清空重建
  ///
  /// 取代 force 同步每次 clearAllData 的破壞式全清——同來源資料以
  /// insertOrReplace upsert 即冪等，全清只在口徑版本變更時才必要
  /// （bump [DataFreshness.institutionalDataVersion] 觸發）。
  ///
  /// **null（無記錄）≠ 版本不符**：marker 引入前的既有 DB 都沒有記錄，
  /// 但其資料已是現行口徑——視為認養（grandfather），只補寫 marker 不清。
  /// 若把 null 當不符去清，升級後第一次日常更新就會把完整法人歷史砍到
  /// 15 天回補窗（surge baseline 60 日、streak 深度全毀）。fresh DB 兩種
  /// 語意等價（無資料可清）。
  ///
  /// 清空與 marker 寫入包在同一交易：兩者原子成立，不存在「清了但沒標記
  /// →下次又清掉剛寫的新資料」的重清窗口。
  ///
  /// 回傳是否執行了遷移（認養只蓋章、不算遷移）。
  @override
  Future<bool> ensureDataVersion() async {
    final stored = await _db.getSetting(_dataVersionKey);
    if (stored == DataFreshness.institutionalDataVersion) return false;

    if (stored == null) {
      await _db.setSetting(
        _dataVersionKey,
        DataFreshness.institutionalDataVersion,
      );
      AppLogger.info(
        'InstitutionalRepo',
        '法人口徑版本認養既有資料: (無記錄) → '
            '${DataFreshness.institutionalDataVersion}（不清空）',
      );
      return false;
    }

    var cleared = 0;
    await _db.transaction<void>(() async {
      cleared = await clearAllData();
      await _db.setSetting(
        _dataVersionKey,
        DataFreshness.institutionalDataVersion,
      );
      // 深回補 pending:清空後的 62 天深回補若被限流打斷,一次性的
      // migrated 回傳值救不了下一輪(版本已一致→false→退回 15 天窗,
      // 第 16~62 天永久缺失)。marker 讓「還沒補完」跨輪存活,由
      // syncer 在深回補完整跑完後蓋章(markDeepBackfillComplete)。
      await _db.setSetting(_deepBackfillPendingKey, '1');
    });
    AppLogger.info(
      'InstitutionalRepo',
      '法人口徑版本遷移: $stored → '
          '${DataFreshness.institutionalDataVersion}，已清除 $cleared 筆舊資料',
    );
    return true;
  }

  /// 將法人資料轉換為資料庫 entries（TWSE/TPEX 共用）
  List<DailyInstitutionalCompanion> _toInstitutionalEntries<T>(
    List<T> items,
    ({
      String code,
      DateTime date,
      double foreignNet,
      double investmentTrustNet,
      double dealerNet,
      double dealerSelfNet,
    })
    Function(T)
    extract,
  ) {
    return items.map((item) {
      final f = extract(item);
      return DailyInstitutionalCompanion.insert(
        symbol: f.code,
        date: DateContext.normalize(f.date),
        foreignNet: Value(f.foreignNet),
        investmentTrustNet: Value(f.investmentTrustNet),
        dealerNet: Value(f.dealerNet),
        dealerSelfNet: Value(f.dealerSelfNet),
      );
    }).toList();
  }
}
