import 'package:drift/drift.dart';

import 'package:daredevil/core/utils/clock.dart';
import 'package:daredevil/core/utils/date_context.dart';
import 'package:daredevil/core/utils/taiwan_calendar.dart';
import 'package:daredevil/core/exceptions/app_exception.dart';
import 'package:daredevil/core/utils/logger.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/data/remote/twse_client.dart';
import 'package:daredevil/data/remote/tpex_client.dart';
import 'package:daredevil/data/remote/finmind_client.dart';

/// 市場資料 Repository
///
/// 處理：財報同步
class MarketDataRepository {
  MarketDataRepository({
    required AppDatabase database,
    required FinMindClient finMindClient,
    TwseClient? twseClient,
    TpexClient? tpexClient,
    AppClock clock = const SystemClock(),
  }) : _db = database,
       _client = finMindClient,
       _twse = twseClient,
       _tpex = tpexClient,
       _clock = clock;

  final AppDatabase _db;
  final FinMindClient _client;

  /// 全市場資產負債表的兩個免費來源。nullable 是為了讓既有測試不必全改;
  /// 生產接線(update_service_factory)恆為雙源,單源缺席時該市場跳過。
  final TwseClient? _twse;
  final TpexClient? _tpex;
  final AppClock _clock;

  // ==================================================
  // 日期輔助方法
  // ==================================================

  /// 根據當前日期取得預期最新季度日期
  ///
  /// 財報通常在季度結束後約 45 天公布：
  /// - Q1（1-3月）→ 約 5 月中公布
  /// - Q2（4-6月）→ 約 8 月中公布
  /// - Q3（7-9月）→ 約 11 月中公布
  /// - Q4（10-12月）→ 約隔年 3 月中公布
  DateTime _getExpectedLatestQuarter() =>
      TaiwanCalendar.expectedLatestReportQuarter(_clock.now());

  // ==================================================
  // 財報資料
  // ==================================================

  /// 全市場資產負債表同步(TWSE t187ap07 + TPEx mopsfin_t187ap07,免費)
  ///
  /// **為什麼**:[syncBalanceSheet] 走 FinMind 逐檔,而財報是額度的唯一
  /// 瓶頸——129 檔待回填 = 258 次呼叫(損益+資負各一),佔小時額度 43%,
  /// 實測 2026-08-16 因額度保留只跑了 10 檔。本方法一次拿全市場
  /// (上市 968 檔 + 上櫃 859 檔),把其中一半的呼叫直接歸零。
  ///
  /// **只補最新一季**:免費端點只有當季,歷史仍靠 FinMind 回補。但
  /// [_syncFinancialStatement] 的新鮮度檢查是 per-statementType 的,寫入
  /// 之後 BALANCE 那條會提早 return、不打 API。
  ///
  /// ⚠️ 損益表**刻意不接**:官方端點是年度累計、FinMind 是單季,語意不同
  /// (見 [MarketWideFinancial] 的說明)。
  Future<int> syncMarketWideBalanceSheets({bool force = false}) async {
    try {
      final rows = <MarketWideFinancial>[];
      Object? firstError;
      for (final fetch in [
        if (_twse != null) _twse.getAllBalanceSheets,
        if (_tpex != null) _tpex.getAllBalanceSheets,
      ]) {
        try {
          rows.addAll(await fetch());
        } on RateLimitException {
          rethrow;
        } catch (e) {
          AppLogger.warning('MarketDataRepo', '單一市場資產負債表失敗,另一側照常', e);
          firstError ??= e;
        }
      }
      if (rows.isEmpty) {
        if (firstError != null) throw firstError;
        return 0;
      }

      // FK 過濾:官方名冊含尚未進 stock_master 的新標的
      final known = (await _db.getAllActiveStocks())
          .map((s) => s.symbol)
          .toSet();
      final entries = [
        for (final r in rows)
          if (known.contains(r.symbol))
            FinancialDataCompanion.insert(
              symbol: r.symbol,
              date: r.date,
              statementType: r.statementType,
              dataType: r.dataType,
              value: Value(r.value),
              originName: const Value('官方季報(t187ap07)'),
            ),
      ];
      if (entries.isEmpty) return 0;

      await _db.insertFinancialData(entries);
      AppLogger.info(
        'MarketDataRepo',
        '全市場資產負債表: ${entries.length} 筆 / '
            '${entries.map((e) => e.symbol.value).toSet().length} 檔'
            '(來源 ${rows.length} 筆)',
      );
      return entries.length;
    } on RateLimitException {
      rethrow;
    } on NetworkException {
      rethrow;
    } catch (e) {
      throw DatabaseException('Failed to sync market-wide balance sheets', e);
    }
  }

  /// 同步資產負債表資料
  Future<int> syncBalanceSheet(
    String symbol, {
    required DateTime startDate,
    DateTime? endDate,
  }) => _syncFinancialStatement(
    symbol,
    startDate: startDate,
    endDate: endDate,
    statementType: 'BALANCE',
    fetchFn: (id, start, end) =>
        _client.getBalanceSheet(stockId: id, startDate: start, endDate: end),
    extractFields: (item) => (
      stockId: item.stockId,
      date: item.date,
      type: item.type,
      value: item.value,
      origin: item.origin,
    ),
    logLabel: '資產負債表',
  );

  /// 財報同步共用邏輯
  ///
  /// 包含新鮮度檢查以避免不必要的 API 呼叫。
  /// 季度資料：若已有最新可用季度則跳過。
  Future<int> _syncFinancialStatement<T>(
    String symbol, {
    required DateTime startDate,
    DateTime? endDate,
    required String statementType,
    required Future<List<T>> Function(String stockId, String start, String? end)
    fetchFn,
    required ({
      String stockId,
      String date,
      String type,
      double value,
      String origin,
    })
    Function(T)
    extractFields,
    required String logLabel,
  }) async {
    try {
      final latestDate = await _db.getLatestFinancialDataDate(
        symbol,
        statementType,
      );
      final expectedQuarter = _getExpectedLatestQuarter();
      if (latestDate != null && !latestDate.isBefore(expectedQuarter)) {
        return 0;
      }

      final data = await fetchFn(
        symbol,
        DateContext.formatYmd(startDate),
        endDate != null ? DateContext.formatYmd(endDate) : null,
      );

      final entries = data.map((item) {
        final f = extractFields(item);
        return FinancialDataCompanion.insert(
          symbol: f.stockId,
          date: DateContext.parseQuarterDate(f.date),
          statementType: statementType,
          dataType: f.type,
          value: Value(f.value),
          originName: Value(f.origin),
        );
      }).toList();

      await _db.insertFinancialData(entries);
      return entries.length;
    } on RateLimitException {
      AppLogger.warning('MarketDataRepo', '$symbol: $logLabel同步觸發 API 速率限制');
      rethrow;
    } on NetworkException {
      rethrow;
    } catch (e) {
      throw DatabaseException('Failed to sync $statementType for $symbol', e);
    }
  }

  // ==================================================
  // 市場 / 同步狀態查詢
  // ==================================================

  Future<DateTime?> getLatestDataDate() => _db.getLatestDataDate();

  Future<DateTime?> getLatestInstitutionalDate() =>
      _db.getLatestInstitutionalDate();

  Future<UpdateRunEntry?> getLatestUpdateRun() => _db.getLatestUpdateRun();

  Future<UpdateRunEntry?> getLatestSuccessfulUpdateRun() =>
      _db.getLatestSuccessfulUpdateRun();

  Future<List<UpdateRunEntry>> getRecentUpdateRuns({int limit = 30}) =>
      _db.getRecentUpdateRuns(limit: limit);
}
