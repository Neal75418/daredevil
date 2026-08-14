import 'package:drift/drift.dart';

import 'package:daredevil/core/constants/data_freshness.dart';
import 'package:daredevil/core/constants/market_codes.dart';
import 'package:daredevil/core/constants/rule_params.dart';
import 'package:daredevil/core/utils/clock.dart';
import 'package:daredevil/core/utils/safe_execution.dart';
import 'package:daredevil/core/utils/date_context.dart';
import 'package:daredevil/core/exceptions/app_exception.dart';
import 'package:daredevil/core/utils/logger.dart';
import 'package:daredevil/core/utils/taiwan_calendar.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/data/remote/tpex_client.dart';
import 'package:daredevil/data/remote/twse_client.dart';

/// 注意股票/處置股票資料 Repository
///
/// 提供警示資料的存取與同步功能，用於風險控管。
/// 支援上市 (TWSE) 和上櫃 (TPEX) 警示資料。
class WarningRepository {
  WarningRepository({
    required AppDatabase database,
    required TpexClient tpexClient,
    required TwseClient twseClient,
    AppClock clock = const SystemClock(),
  }) : _db = database,
       _tpexClient = tpexClient,
       _twseClient = twseClient,
       _clock = clock;

  final AppDatabase _db;
  final TpexClient _tpexClient;
  final TwseClient _twseClient;
  final AppClock _clock;

  /// 取得所有目前生效的警示（全市場）
  Future<List<TradingWarningEntry>> getAllActiveWarnings() {
    return _db.getAllActiveWarnings();
  }

  /// 批次檢查多檔股票是否為處置股
  Future<Set<String>> getDisposalStocksBatch(List<String> symbols) {
    return _db.getDisposalStocksBatch(symbols);
  }

  /// 同步全市場警示資料
  ///
  /// 從 TWSE 和 TPEX 取得最新的注意股票和處置股票資料。
  /// 各 API 獨立呼叫，部分失敗不影響其他來源。
  ///
  /// [force] - 若為 true，則無視新鮮度檢查強制同步
  Future<int> syncAllMarketWarnings({bool force = false}) async {
    try {
      final today = _clock.now();
      final normalizedDate = DateContext.normalize(today);

      // 新鮮度檢查：檢查今日是否已有資料且最近 6 小時內同步過
      if (!force) {
        final lastSync = await _db.getLatestWarningSyncTime();
        if (lastSync != null) {
          final hoursSinceLastSync = today.difference(lastSync).inHours;
          if (hoursSinceLastSync < DataFreshness.warningSyncFreshnessHours) {
            final existingCount = await _db.getWarningCountForDate(
              normalizedDate,
            );
            if (existingCount > 0) {
              AppLogger.info(
                'WarningRepo',
                '警示資料已是最新 ($existingCount 筆，${hoursSinceLastSync}h 前同步)',
              );
              return existingCount;
            }
          }
        }
      }

      // TWSE 公告 API 在非交易日整個端點不可用（回傳 404），
      // 即使傳入上一交易日日期也無效，因此非交易日直接跳過。
      final isTradingDay = TaiwanCalendar.isTradingDay(today);

      // 逐一取得警示資料（TPEX 伺服器對併行請求敏感，序列化避免 Connection reset）
      // TWSE 和 TPEX 使用不同伺服器，可分組並行；同一伺服器內序列化
      List<TpexTradingWarning> tpexWarnings = [];
      List<TpexTradingWarning> tpexDisposals = [];
      List<TwseTradingWarning> twseWarnings = [];
      List<TwseTradingWarning> twseDisposals = [];
      var failCount = 0;

      // 注意股是逐日名單，需 full-refresh；但只能清「本輪確實取得新名單」的
      // 市場，否則某市場失敗/跳過時會誤殺該市場全部注意股（表無 market 欄，
      // 市場歸屬由 stock_master 推導）。
      var twseAttentionSynced = false;
      var tpexAttentionSynced = false;

      // TWSE 請求（僅交易日，兩個 TWSE 請求可並行——TWSE 伺服器穩定）。
      // awaitPairSettled(2026-07-30 審查):舊寫法先啟動兩個 future 再逐一
      // await——第一個 rethrow(限流/斷網)時第二個 future 的 rejection 無人
      // 監聽 → zone unhandled(雙來源同時失敗是高相關性情境)。settled 版
      // 啟動當下掛好兩邊 listener;rethrow 優先語意不變、per-source
      // 成敗旗標(failCount/attentionSynced)保留。
      if (isTradingDay) {
        final (wRes, dRes) = await awaitPairSettled(
          _twseClient.getTradingWarnings(date: today),
          _twseClient.getDisposalInfo(date: today),
        );
        for (final e in [wRes.error, dRes.error]) {
          if (e is RateLimitException) throw e;
        }
        for (final e in [wRes.error, dRes.error]) {
          if (e is NetworkException) throw e;
        }
        if (wRes.error == null) {
          twseWarnings = wRes.value!;
          twseAttentionSynced = true;
        } else {
          failCount++;
          AppLogger.warning('WarningRepo', '上市注意股票取得失敗', wRes.error);
        }
        if (dRes.error == null) {
          twseDisposals = dRes.value!;
        } else {
          failCount++;
          AppLogger.warning('WarningRepo', '上市處置股票取得失敗', dRes.error);
        }
      } else {
        AppLogger.debug('WarningRepo', '非交易日，跳過 TWSE 注意/處置股票 API');
      }

      // TPEX 請求（序列化——TPEX OpenAPI 對併行連線敏感）
      try {
        tpexWarnings = await _tpexClient.getTradingWarnings();
        tpexAttentionSynced = true;
      } on RateLimitException {
        rethrow;
      } on NetworkException {
        rethrow;
      } catch (e) {
        failCount++;
        AppLogger.warning('WarningRepo', '上櫃注意股票取得失敗', e);
      }
      try {
        tpexDisposals = await _tpexClient.getDisposalInfo();
      } on RateLimitException {
        rethrow;
      } on NetworkException {
        rethrow;
      } catch (e) {
        failCount++;
        AppLogger.warning('WarningRepo', '上櫃處置股票取得失敗', e);
      }

      // 全部可用來源都失敗時拋出例外，讓呼叫端知道非「合法的 0 筆」
      final totalSources = isTradingDay ? 4 : 2;
      if (failCount == totalSources) {
        throw const NetworkException('所有警示資料來源均失敗', null);
      }

      // 使用 transaction 確保原子性，避免 FK 驗證與插入之間的 race condition
      return await _db.transaction(() async {
        // 取得有效股票代碼以避免 Foreign Key 錯誤
        final stockList = await _db.getAllActiveStocks();
        final validSymbols = stockList.map((s) => s.symbol).toSet();

        final entries = <TradingWarningCompanion>[];

        // 轉換 TWSE 注意股票 (上市)
        for (final item in twseWarnings) {
          if (!validSymbols.contains(item.code)) continue;
          entries.add(
            _createWarningEntry(
              symbol: item.code,
              date: normalizedDate,
              referenceNow: today,
              warningType: 'ATTENTION',
              reasonCode: item.reasonCode,
              reasonDescription: item.reasonDescription,
            ),
          );
        }

        // 轉換 TWSE 處置股票
        for (final item in twseDisposals) {
          if (!validSymbols.contains(item.code)) continue;
          entries.add(
            _createWarningEntry(
              symbol: item.code,
              date: normalizedDate,
              referenceNow: today,
              warningType: 'DISPOSAL',
              reasonCode: item.reasonCode,
              reasonDescription: item.reasonDescription,
              disposalMeasures: item.disposalMeasures,
              disposalStartDate: item.disposalStartDate,
              disposalEndDate: item.disposalEndDate,
            ),
          );
        }

        // 轉換 TPEX 注意股票 (上櫃)
        for (final item in tpexWarnings) {
          if (!validSymbols.contains(item.code)) continue;
          entries.add(
            _createWarningEntry(
              symbol: item.code,
              date: normalizedDate,
              referenceNow: today,
              warningType: 'ATTENTION',
              reasonCode: item.reasonCode,
              reasonDescription: item.reasonDescription,
            ),
          );
        }

        // 轉換 TPEX 處置股票
        for (final item in tpexDisposals) {
          if (!validSymbols.contains(item.code)) continue;
          entries.add(
            _createWarningEntry(
              symbol: item.code,
              date: normalizedDate,
              referenceNow: today,
              warningType: 'DISPOSAL',
              reasonCode: item.reasonCode,
              reasonDescription: item.reasonDescription,
              disposalMeasures: item.disposalMeasures,
              disposalStartDate: item.disposalStartDate,
              disposalEndDate: item.disposalEndDate,
            ),
          );
        }

        // 寫入資料庫（entries 為空是合法狀態——今日確實沒有任何警示；
        // 「所有來源都失敗」已在上方 throw，不會走到這裡）
        if (entries.isNotEmpty) {
          await _db.insertWarningData(entries);
        }

        // 注意股 full-refresh：不在今日名單者失效。必須在 insert 之後，
        // 且只清本輪確實取得名單的市場。
        // ⚠️ 只有「取得非空名單」才算取得權威名單。client 在解析失敗或
        // stat != 'OK' 時是 return [] 而非拋例外（twse_client.dart:1297-1300），
        // 空清單無法與「今日真的沒有注意股」區分——把它當名單會清空整個市場。
        final syncedAttentionMarkets = <String>{
          if (twseAttentionSynced && twseWarnings.isNotEmpty) MarketCode.twse,
          if (tpexAttentionSynced && tpexWarnings.isNotEmpty) MarketCode.tpex,
        };
        final currentAttentionSymbols = <String>{
          if (twseAttentionSynced) ...twseWarnings.map((w) => w.code),
          if (tpexAttentionSynced) ...tpexWarnings.map((w) => w.code),
        };
        final deactivated = await _db.deactivateStaleAttentionWarnings(
          currentSymbols: currentAttentionSymbols,
          syncedMarkets: syncedAttentionMarkets,
          syncDate: normalizedDate,
        );

        // 更新過期的處置股（移出 entries.isEmpty 早退分支——過去 0 筆的日子
        // 連 DISPOSAL 過期都不會被清理）
        await _db.updateExpiredWarnings(now: today);

        if (entries.isEmpty && deactivated == 0) {
          AppLogger.info('WarningRepo', '無新警示資料');
          return 0;
        }

        AppLogger.info(
          'WarningRepo',
          '警示同步: ${entries.length} 筆 '
              '(上市注意 ${twseWarnings.length}, 上市處置 ${twseDisposals.length}, '
              '上櫃注意 ${tpexWarnings.length}, 上櫃處置 ${tpexDisposals.length})',
        );

        return entries.length;
      });
    } on RateLimitException {
      rethrow;
    } on NetworkException {
      rethrow;
    } catch (e) {
      throw DatabaseException('Failed to sync warning data', e);
    }
  }

  /// 建立警示資料 Companion
  ///
  /// [referenceNow] - 參考時間，用於判斷處置股是否仍生效，
  ///                  避免跨午夜同步時產生不一致的結果。
  TradingWarningCompanion _createWarningEntry({
    required String symbol,
    required DateTime date,
    required DateTime referenceNow,
    required String warningType,
    String? reasonCode,
    String? reasonDescription,
    String? disposalMeasures,
    DateTime? disposalStartDate,
    DateTime? disposalEndDate,
  }) {
    // 判斷是否生效（處置股檢查結束日期）
    bool isActive = true;
    if (warningType == 'DISPOSAL' && disposalEndDate != null) {
      isActive = referenceNow.isBefore(
        disposalEndDate.add(
          const Duration(days: FundamentalParams.disposalEndDateGraceDays),
        ),
      );
    }

    return TradingWarningCompanion.insert(
      symbol: symbol,
      date: date,
      warningType: warningType,
      reasonCode: Value(reasonCode),
      reasonDescription: Value(reasonDescription),
      disposalMeasures: Value(disposalMeasures),
      disposalStartDate: Value(disposalStartDate),
      disposalEndDate: Value(disposalEndDate),
      isActive: Value(isActive),
    );
  }

  /// 取得自選股中的警示股票
  ///
  /// 用於在自選股頁面顯示警示標記。
  Future<Map<String, TradingWarningEntry>> getWatchlistWarnings(
    List<String> watchlistSymbols,
  ) async {
    if (watchlistSymbols.isEmpty) return {};

    final warnings = await getAllActiveWarnings();
    final watchlistSet = watchlistSymbols.toSet();

    final result = <String, TradingWarningEntry>{};
    for (final warning in warnings) {
      if (watchlistSet.contains(warning.symbol)) {
        // 若已存在，處置股優先級高於注意股
        if (!result.containsKey(warning.symbol) ||
            warning.warningType == 'DISPOSAL') {
          result[warning.symbol] = warning;
        }
      }
    }

    return result;
  }
}
