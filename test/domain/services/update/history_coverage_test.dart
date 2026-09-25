import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:daredevil/core/constants/api_config.dart';
import 'package:daredevil/core/constants/market_codes.dart';
import 'package:daredevil/core/constants/rule_params.dart';
import 'package:daredevil/core/utils/date_context.dart';
import 'package:daredevil/core/utils/taiwan_calendar.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/domain/services/update/history_coverage.dart';

/// 「歷史資料補齊」的定義只能有一份：回補（HistoricalPriceSyncer）決定要
/// 補哪些（日, 市場），今日頁的建置進度也要用同一份判斷，兩邊才不會一個說
/// 補齊了、另一個還在補。
class MockAppDatabase extends Mock implements AppDatabase {}

StockMasterEntry _stock(String symbol, String market) => StockMasterEntry(
  symbol: symbol,
  name: symbol,
  market: market,
  isActive: true,
  updatedAt: DateTime(2026, 9, 1),
);

void main() {
  final endDay = DateTime(2026, 9, 18); // 週五
  const thresholds = {MarketCode.twse: 500, MarketCode.tpex: 400};

  /// 回補窗內所有交易日（新→舊），不含 endDay 當天
  List<DateTime> tradingDaysInWindow() {
    final start = endDay.subtract(
      const Duration(days: RuleParams.historyRequiredDays),
    );
    return [
      for (
        var d = endDay.subtract(const Duration(days: 1));
        !d.isBefore(start);
        d = d.subtract(const Duration(days: 1))
      )
        if (TaiwanCalendar.isTradingDay(d)) d,
    ];
  }

  Map<String, Map<String, int>> countsFor(
    Iterable<DateTime> days, {
    int twse = 900,
    int tpex = 800,
  }) => {
    MarketCode.twse: {for (final d in days) DateContext.formatYmd(d): twse},
    MarketCode.tpex: {for (final d in days) DateContext.formatYmd(d): tpex},
  };

  group('findMissingMarketDays', () {
    test('全缺（新安裝）→ 由新到舊、每天依市場排入', () {
      final missing = findMissingMarketDays(
        endDay: endDay,
        thresholds: thresholds,
        dayCounts: const {},
      );
      final days = tradingDaysInWindow();
      expect(missing.length, days.length * 2);
      expect(missing.first, (days.first, MarketCode.twse));
      expect(missing[1], (days.first, MarketCode.tpex));
      expect(missing.last.$1, days.last);
    });

    test('limit 只取最新的 N 個（回補單次上限）', () {
      final missing = findMissingMarketDays(
        endDay: endDay,
        thresholds: thresholds,
        dayCounts: const {},
        limit: ApiConfig.historicalMarketDayMaxCallsPerRun,
      );
      expect(missing.length, ApiConfig.historicalMarketDayMaxCallsPerRun);
      expect(missing.first.$1, tradingDaysInWindow().first);
    });

    test('筆數未達門檻才算缺漏；當天（endDay）不算', () {
      final days = tradingDaysInWindow();
      final counts = countsFor(days);
      counts[MarketCode.tpex]![DateContext.formatYmd(days[3])] = 399;
      final missing = findMissingMarketDays(
        endDay: endDay,
        thresholds: thresholds,
        dayCounts: counts,
      );
      expect(missing, [(days[3], MarketCode.tpex)]);
    });

    test('只看有門檻的市場（股票主檔為空的市場略過）', () {
      final missing = findMissingMarketDays(
        endDay: endDay,
        thresholds: const {MarketCode.twse: 500},
        dayCounts: const {},
      );
      expect(missing.every((m) => m.$2 == MarketCode.twse), isTrue);
    });
  });

  group('HistoryCoverage', () {
    test('全缺 → 0%，約需「缺漏數 ÷ 單次上限」次更新', () {
      final c = HistoryCoverage.from(
        endDay: endDay,
        thresholds: thresholds,
        dayCounts: const {},
      );
      final total = tradingDaysInWindow().length * 2;
      expect(c.total, total);
      expect(c.covered, 0);
      expect(c.isComplete, isFalse);
      expect(
        c.remainingRuns,
        (total / ApiConfig.historicalMarketDayMaxCallsPerRun).ceil(),
      );
    });

    test('全部補齊 → 完成、剩 0 次', () {
      final c = HistoryCoverage.from(
        endDay: endDay,
        thresholds: thresholds,
        dayCounts: countsFor(tradingDaysInWindow()),
      );
      expect(c.isComplete, isTrue);
      expect(c.remainingRuns, 0);
      expect(c.percent, 100);
    });

    test('百分比無條件捨去：差一點補齊時不會顯示成 100%', () {
      final days = tradingDaysInWindow();
      final counts = countsFor(days);
      counts[MarketCode.twse]![DateContext.formatYmd(days.last)] = 0;
      final c = HistoryCoverage.from(
        endDay: endDay,
        thresholds: thresholds,
        dayCounts: counts,
      );
      expect(c.isComplete, isFalse);
      expect(c.percent, 99);
      expect(c.remainingRuns, 1);
    });

    // 日曆漏標的臨時停市日（颱風；2026-07-13 一次補進 4 天），官方端點回
    // 0 筆，那個（日, 市場）永遠補不齊。不容忍的話已補齊的使用者會常駐看到
    // 「99%（約再 1 次更新）」長達 13 個月。容忍量＝一輪回補上限：新安裝時
    // 缺上百個照樣顯示；零星幾天不顯示。
    test('🚨 缺漏在一輪回補上限內 → 不算建置中（容忍日曆漏標的停市日）', () {
      const limit = ApiConfig.historicalMarketDayMaxCallsPerRun;
      expect(
        const HistoryCoverage(covered: 540 - limit, total: 540).isBuilding,
        isFalse,
      );
      expect(
        const HistoryCoverage(covered: 540 - limit - 1, total: 540).isBuilding,
        isTrue,
      );
      expect(const HistoryCoverage(covered: 0, total: 0).isBuilding, isFalse);
    });

    test('沒有任何市場（股票主檔尚未同步）→ 視為 0/0，未完成', () {
      final c = HistoryCoverage.from(
        endDay: endDay,
        thresholds: const {},
        dayCounts: const {},
      );
      expect(c.total, 0);
      expect(c.isComplete, isFalse, reason: '主檔都還沒有，不能說「已補齊」');
    });
  });

  group('coverageThreshold（回補與進度共用的門檻公式）', () {
    test('市場股數 × 比例，無條件進位', () {
      expect(
        coverageThreshold(3),
        (3 * ApiConfig.historicalMarketDayMinCoverageRatio).ceil(),
      );
      expect(coverageThreshold(0), 0);
    });
  });

  group('loadHistoryCoverage（從 DB 算進度）', () {
    late MockAppDatabase db;
    setUp(() {
      db = MockAppDatabase();
      registerFallbackValue(DateTime(2000));
    });

    test('上櫃主檔為空 → 只算上市；以股數門檻判斷每日是否補齊', () async {
      when(() => db.getStocksByMarket(MarketCode.twse)).thenAnswer(
        (_) async => [
          _stock('2330', MarketCode.twse),
          _stock('2317', MarketCode.twse),
        ],
      );
      when(
        () => db.getStocksByMarket(MarketCode.tpex),
      ).thenAnswer((_) async => []);
      final days = tradingDaysInWindow();
      when(
        () => db.getPriceCountsByDayAndMarket(
          startDate: any(named: 'startDate'),
          endDate: any(named: 'endDate'),
        ),
      ).thenAnswer(
        (_) async => {
          MarketCode.twse: {
            // 2 檔股票 → 門檻 1：最新一天有 1 筆算補齊，其餘缺
            DateContext.formatYmd(days.first): 1,
          },
        },
      );

      final c = await loadHistoryCoverage(
        db,
        DateTime(2026, 9, 18, 17),
        dataDate: DateTime(2026, 9, 17),
      );

      expect(c.total, days.length);
      expect(c.covered, 1);
    });

    // 資料是當天的（收盤後已更新）時，窗口仍與回補一致、右端是今天：
    // 回補還會去補的最舊那天，進度也得算它缺。
    test('資料是當天的 → 窗口右端仍是今天（與回補同一個窗）', () async {
      when(
        () => db.getStocksByMarket(MarketCode.twse),
      ).thenAnswer((_) async => [_stock('2330', MarketCode.twse)]);
      when(
        () => db.getStocksByMarket(MarketCode.tpex),
      ).thenAnswer((_) async => []);
      final today = DateTime(2026, 9, 18);
      final oldest = today.subtract(
        const Duration(days: RuleParams.historyRequiredDays),
      );
      expect(TaiwanCalendar.isTradingDay(oldest), isTrue, reason: '前提');
      // 今天與窗內都齊，只缺回補窗最舊那天
      final counts = <String, int>{
        for (
          var d = today;
          d.isAfter(oldest);
          d = d.subtract(const Duration(days: 1))
        )
          DateContext.formatYmd(d): 1,
      };
      when(
        () => db.getPriceCountsByDayAndMarket(
          startDate: any(named: 'startDate'),
          endDate: any(named: 'endDate'),
        ),
      ).thenAnswer((_) async => {MarketCode.twse: counts});

      final c = await loadHistoryCoverage(
        db,
        DateTime(2026, 9, 18, 17),
        dataDate: today,
      );

      expect(c.missing, 1);
    });

    // 資料只是落後幾天（更新失敗／尚未跑）時，最近幾天的 0 筆不是「歷史沒
    // 補齊」——那是落後提示的事。窗口右端取資料日，建置進度只管歷史深度。
    test('🚨 窗口以資料日為右端：資料落後的近幾天不算歷史缺漏', () async {
      when(
        () => db.getStocksByMarket(MarketCode.twse),
      ).thenAnswer((_) async => [_stock('2330', MarketCode.twse)]);
      when(
        () => db.getStocksByMarket(MarketCode.tpex),
      ).thenAnswer((_) async => []);
      // 資料停在 9/17，舊日子全齊
      final start = DateTime(
        2026,
        9,
        17,
      ).subtract(const Duration(days: RuleParams.historyRequiredDays));
      final counts = <String, int>{
        for (
          var d = DateTime(2026, 9, 17);
          !d.isBefore(start);
          d = d.subtract(const Duration(days: 1))
        )
          DateContext.formatYmd(d): 1,
      };
      when(
        () => db.getPriceCountsByDayAndMarket(
          startDate: any(named: 'startDate'),
          endDate: any(named: 'endDate'),
        ),
      ).thenAnswer((_) async => {MarketCode.twse: counts});

      // 現在已是 9/25：9/18～9/24 沒資料，但那是「落後」不是「歷史缺漏」
      final c = await loadHistoryCoverage(
        db,
        DateTime(2026, 9, 25, 17),
        dataDate: DateTime(2026, 9, 17),
      );

      expect(c.isComplete, isTrue);
    });
  });
}
