// 當沖 / 融資融券缺漏日回補（MarketDataUpdater phase 0）
//
// 背景（2026-07-14 production）：這兩類資料台交所約 21:00 後才發布，使用者
// 在那之前更新就抓不到；而 syncer 只抓「更新當下那一天」、沒有回補迴圈，
// 錯過即永久缺漏（近 30 交易日：當沖缺 12 天、融資缺 10 天；法人因有回補
// 迴圈而 0 缺漏）。此處補上同型機制。
//
// 端點行為 2026-07-14 活體驗證：TWSE TWTB4U / MI_MARGN 與 TPEx
// margin_bal_result 皆正確回應歷史日期。
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:daredevil/core/constants/api_config.dart';
import 'package:daredevil/core/constants/data_freshness.dart';
import 'package:daredevil/core/constants/market_codes.dart';
import 'package:daredevil/core/exceptions/app_exception.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/data/repositories/insider_repository.dart';
import 'package:daredevil/data/repositories/shareholding_repository.dart';
import 'package:daredevil/data/repositories/trading_repository.dart';
import 'package:daredevil/data/repositories/warning_repository.dart';
import 'package:daredevil/domain/services/update/market_data_updater.dart';

class MockAppDatabase extends Mock implements AppDatabase {}

class MockTradingRepository extends Mock implements TradingRepository {}

class MockShareholdingRepository extends Mock
    implements ShareholdingRepository {}

class MockWarningRepository extends Mock implements WarningRepository {}

class MockInsiderRepository extends Mock implements InsiderRepository {}

void main() {
  late MockAppDatabase mockDb;
  late MockTradingRepository mockTradingRepo;
  late MarketDataUpdater updater;

  // 2026-07-14（週二）。窗內鄰近交易日：7/13(一)、7/10(五，颱風休市，
  // TaiwanCalendar 已知)、7/9(四)、7/8(三)…；7/11-12 為週末。
  final today = DateTime(2026, 7, 14);
  final d13 = DateTime(2026, 7, 13);
  final d9 = DateTime(2026, 7, 9);
  final d8 = DateTime(2026, 7, 8);
  final sat = DateTime(2026, 7, 11);
  final typhoon = DateTime(2026, 7, 10);

  setUpAll(() {
    registerFallbackValue(DateTime(2020));
  });

  /// 每日路徑（今日同步）預設成功，讓測試專注在回補
  void stubTodaySync() {
    when(
      () =>
          mockTradingRepo.syncAllDayTradingFromTpex(force: any(named: 'force')),
    ).thenAnswer((_) async => 0);
    when(
      () => mockTradingRepo.syncAllDayTradingFromTwse(
        date: any(named: 'date'),
        force: any(named: 'force'),
      ),
    ).thenAnswer((_) async => 1000);
    when(
      () => mockTradingRepo.syncAllMarginTrading(
        date: any(named: 'date'),
        force: any(named: 'force'),
      ),
    ).thenAnswer((_) async => 1900);
  }

  /// 市場規模：上市 1000 檔、上櫃 800 檔 → 覆蓋門檻各 500 / 400
  /// （`historicalMarketDayMinCoverageRatio` = 0.5）
  const twseStocks = 1000;
  const tpexStocks = 800;
  const twseThreshold = 500;
  const tpexThreshold = 400;

  /// DB 覆蓋率回應。融資為 **per-market**：[missingTwseMargin] /
  /// [missingTpexMargin] 內的日子該市場回 0。價格預設充足。
  void stubCoverage({
    Set<DateTime> missingDayTrading = const {},
    Set<DateTime> missingTwseMargin = const {},
    Set<DateTime> missingTpexMargin = const {},
    Map<DateTime, int> priceCounts = const {},
  }) {
    when(
      () => mockDb.getDayTradingCountForDateAndMarket(any(), any()),
    ).thenAnswer((inv) async {
      final d = inv.positionalArguments[0] as DateTime;
      return missingDayTrading.contains(d)
          ? 0
          : DataFreshness.twseBatchThreshold + 1;
    });
    when(
      () => mockDb.countMarginTradingByDateAndMarket(any(), any()),
    ).thenAnswer((inv) async {
      final d = inv.positionalArguments[0] as DateTime;
      final m = inv.positionalArguments[1] as String;
      if (m == MarketCode.twse) {
        return missingTwseMargin.contains(d) ? 0 : twseThreshold + 1;
      }
      return missingTpexMargin.contains(d) ? 0 : tpexThreshold + 1;
    });
    when(() => mockDb.countPricesByDateAndMarket(any(), any())).thenAnswer((
      inv,
    ) async {
      final d = inv.positionalArguments[0] as DateTime;
      return priceCounts[d] ?? 900;
    });
  }

  /// 回補回傳**逐市場**筆數。預設兩邊都足額（跨過門檻＝有進度）。
  void stubBackfillMargin({int twseRows = 900, int tpexRows = 700}) {
    when(
      () => mockTradingRepo.backfillMarginTradingByDate(
        date: any(named: 'date'),
        markets: any(named: 'markets'),
      ),
    ).thenAnswer((_) async => (twseRows: twseRows, tpexRows: tpexRows));
  }

  setUp(() {
    mockDb = MockAppDatabase();
    mockTradingRepo = MockTradingRepository();
    updater = MarketDataUpdater(
      database: mockDb,
      tradingRepository: mockTradingRepo,
      shareholdingRepository: MockShareholdingRepository(),
      warningRepository: MockWarningRepository(),
      insiderRepository: MockInsiderRepository(),
      backfillCallDelay: Duration.zero,
    );
    when(
      () => mockDb.countStocksByMarket(MarketCode.twse),
    ).thenAnswer((_) async => twseStocks);
    when(
      () => mockDb.countStocksByMarket(MarketCode.tpex),
    ).thenAnswer((_) async => tpexStocks);
    stubTodaySync();
    stubCoverage();
    stubBackfillMargin();
  });

  group('syncMarketWideData — 缺漏日回補', () {
    test('無缺漏 → 完全不回補', () async {
      final result = await updater.syncMarketWideData(date: today);

      verifyNever(
        () => mockTradingRepo.backfillMarginTradingByDate(
          date: any(named: 'date'),
          markets: any(named: 'markets'),
        ),
      );
      // 今日同步仍照跑（date = today）
      verify(
        () => mockTradingRepo.syncAllDayTradingFromTwse(
          date: today,
          force: any(named: 'force'),
        ),
      ).called(1);
      expect(result.backfilledDays, 0);
    });

    test('缺漏日各自回補（當沖走 syncAllDayTrading、融資走 backfill）', () async {
      stubCoverage(
        missingDayTrading: {d13, d9},
        missingTwseMargin: {d13},
        missingTpexMargin: {d13},
      );

      final result = await updater.syncMarketWideData(date: today);

      // 當沖：兩個缺漏日各補一次（force: true 略過新鮮度檢查）
      verify(
        () => mockTradingRepo.syncAllDayTradingFromTwse(date: d13, force: true),
      ).called(1);
      verify(
        () => mockTradingRepo.syncAllDayTradingFromTwse(date: d9, force: true),
      ).called(1);
      // 融資：只有 7/13 缺
      verify(
        () => mockTradingRepo.backfillMarginTradingByDate(
          date: d13,
          markets: any(named: 'markets'),
        ),
      ).called(1);
      verifyNever(
        () => mockTradingRepo.backfillMarginTradingByDate(
          date: d9,
          markets: any(named: 'markets'),
        ),
      );
      expect(result.backfilledDays, 2, reason: '7/13 與 7/9 各算一天');
    });

    test('新→舊順序：最近的缺漏日先補', () async {
      stubCoverage(missingDayTrading: {d8, d13, d9});

      await updater.syncMarketWideData(date: today);

      final dates = verify(
        () => mockTradingRepo.syncAllDayTradingFromTwse(
          date: captureAny(named: 'date'),
          force: true,
        ),
      ).captured.cast<DateTime>();
      expect(dates, [d13, d9, d8]);
    });

    test('非交易日不檢查（週末、行事曆已知休市日）', () async {
      stubCoverage(missingDayTrading: {sat, typhoon, d13});

      await updater.syncMarketWideData(date: today);

      verifyNever(() => mockDb.getDayTradingCountForDateAndMarket(sat, any()));
      verifyNever(
        () => mockDb.getDayTradingCountForDateAndMarket(typhoon, any()),
      );
      verify(
        () => mockDb.getDayTradingCountForDateAndMarket(d13, any()),
      ).called(1);
    });

    test('今日不列入回補（由每日路徑負責）', () async {
      stubCoverage(missingDayTrading: {today});

      await updater.syncMarketWideData(date: today);

      // 今日只由每日路徑同步一次（force 由 caller 決定），不會再被回補打一次
      verifyNever(
        () =>
            mockTradingRepo.syncAllDayTradingFromTwse(date: today, force: true),
      );
      verifyNever(
        () => mockDb.getDayTradingCountForDateAndMarket(today, any()),
      );
    });

    test('無價格資料的日子不補當沖（比例算不出來會寫出全 0 的假資料）', () async {
      stubCoverage(missingDayTrading: {d13}, priceCounts: {d13: 0});

      final result = await updater.syncMarketWideData(date: today);

      verifyNever(
        () => mockTradingRepo.syncAllDayTradingFromTwse(date: d13, force: true),
      );
      expect(result.backfilledDays, 0);
      verify(
        () => mockDb.countPricesByDateAndMarket(d13, MarketCode.twse),
      ).called(1);
    });

    test('單次回補天數受上限保護', () async {
      // 窗內所有交易日全缺
      when(
        () => mockDb.getDayTradingCountForDateAndMarket(any(), any()),
      ).thenAnswer((_) async => 0);
      when(
        () => mockDb.countMarginTradingByDateAndMarket(any(), any()),
      ).thenAnswer((_) async => 0);
      when(
        () => mockDb.countPricesByDateAndMarket(any(), any()),
      ).thenAnswer((_) async => 900);

      final result = await updater.syncMarketWideData(date: today);

      expect(
        result.backfilledDays,
        ApiConfig.tradingBackfillMaxDaysPerRun,
        reason: '上限保護：單次更新最多補 N 天',
      );
    });

    test('連續零筆中止（端點失效防護）', () async {
      when(
        () => mockDb.getDayTradingCountForDateAndMarket(any(), any()),
      ).thenAnswer((_) async => 0);
      when(
        () => mockDb.countMarginTradingByDateAndMarket(any(), any()),
      ).thenAnswer((_) async => 0);
      when(
        () => mockDb.countPricesByDateAndMarket(any(), any()),
      ).thenAnswer((_) async => 900);
      // 兩邊都回 0 筆
      when(
        () => mockTradingRepo.syncAllDayTradingFromTwse(
          date: any(named: 'date'),
          force: true,
        ),
      ).thenAnswer((_) async => 0);
      stubBackfillMargin(twseRows: 0, tpexRows: 0);

      final result = await updater.syncMarketWideData(date: today);

      expect(result.backfilledDays, 0);
      verify(
        () => mockTradingRepo.backfillMarginTradingByDate(
          date: any(named: 'date'),
          markets: any(named: 'markets'),
        ),
      ).called(ApiConfig.tradingBackfillMaxConsecutiveZeroDays);
    });

    test('RateLimit 往上拋（pipeline 需知道並中止後續 TWSE 呼叫）', () async {
      stubCoverage(missingTwseMargin: {d13}, missingTpexMargin: {d13});
      when(
        () => mockTradingRepo.backfillMarginTradingByDate(
          date: any(named: 'date'),
          markets: any(named: 'markets'),
        ),
      ).thenThrow(const RateLimitException());

      expect(
        () => updater.syncMarketWideData(date: today),
        throwsA(isA<RateLimitException>()),
      );
    });

    test('單日失敗（一般錯誤）不中斷後續日子', () async {
      stubCoverage(missingTwseMargin: {d13, d9}, missingTpexMargin: {d13, d9});
      var call = 0;
      when(
        () => mockTradingRepo.backfillMarginTradingByDate(
          date: any(named: 'date'),
          markets: any(named: 'markets'),
        ),
      ).thenAnswer((_) async {
        call++;
        if (call == 1) throw Exception('7/13 失敗');
        return (twseRows: 900, tpexRows: 700);
      });

      final result = await updater.syncMarketWideData(date: today);

      verify(
        () => mockTradingRepo.backfillMarginTradingByDate(
          date: any(named: 'date'),
          markets: any(named: 'markets'),
        ),
      ).called(2);
      expect(result.backfilledDays, 1, reason: '7/9 成功那天仍計入');
    });

    test('今日同步失敗不阻擋回補（獨立錯誤隔離）', () async {
      when(
        () => mockTradingRepo.syncAllDayTradingFromTwse(
          date: today,
          force: any(named: 'force'),
        ),
      ).thenAnswer((_) async => throw Exception('今日當沖尚未發布'));
      stubCoverage(missingTwseMargin: {d13}, missingTpexMargin: {d13});

      final result = await updater.syncMarketWideData(date: today);

      verify(
        () => mockTradingRepo.backfillMarginTradingByDate(
          date: d13,
          markets: any(named: 'markets'),
        ),
      ).called(1);
      expect(result.backfilledDays, 1);
    });

    test('融資單邊缺漏 → 只抓缺的那個市場（避免重寫已存在市場＝假進度）', () async {
      stubCoverage(missingTpexMargin: {d13});

      await updater.syncMarketWideData(date: today);

      final markets =
          verify(
                () => mockTradingRepo.backfillMarginTradingByDate(
                  date: d13,
                  markets: captureAny(named: 'markets'),
                ),
              ).captured.single
              as Set<String>;
      expect(markets, {MarketCode.tpex}, reason: '上市已足額，重抓它會讓 rows>0 誤判為有進度');
    });

    test('單一市場端點永久失效 → 斷路器收斂（不會每次吃光上限）', () async {
      // 上櫃永遠缺、且回補永遠回 0（端點壞掉）
      when(
        () => mockDb.countMarginTradingByDateAndMarket(any(), any()),
      ).thenAnswer((inv) async {
        final m = inv.positionalArguments[1] as String;
        return m == MarketCode.tpex ? 0 : twseThreshold + 1;
      });
      stubBackfillMargin(twseRows: 0, tpexRows: 0);

      final result = await updater.syncMarketWideData(date: today);

      expect(result.backfilledDays, 0, reason: '沒有真進度就不能算天數');
      verify(
        () => mockTradingRepo.backfillMarginTradingByDate(
          date: any(named: 'date'),
          markets: any(named: 'markets'),
        ),
      ).called(ApiConfig.tradingBackfillMaxConsecutiveZeroDays);
    });

    test('價格半覆蓋（< 50%）不補當沖——會寫出整天假的 0% 比例且永久鎖定', () async {
      // 上市 1000 檔、門檻 500；該日只有 400 檔有價格
      stubCoverage(missingDayTrading: {d13}, priceCounts: {d13: 400});

      final result = await updater.syncMarketWideData(date: today);

      verifyNever(
        () => mockTradingRepo.syncAllDayTradingFromTwse(date: d13, force: true),
      );
      expect(result.backfilledDays, 0);
    });

    test('價格覆蓋達門檻 → 照補', () async {
      stubCoverage(missingDayTrading: {d13}, priceCounts: {d13: 500});

      await updater.syncMarketWideData(date: today);

      verify(
        () => mockTradingRepo.syncAllDayTradingFromTwse(date: d13, force: true),
      ).called(1);
    });

    test('零價格日視為非交易日直接跳過（行事曆謊報的未知休市，不吃斷路器額度）', () async {
      // 行事曆說 7/13 是交易日，但價格表一筆都沒有 → 實際休市
      stubCoverage(
        missingDayTrading: {d13, d9},
        missingTwseMargin: {d13, d9},
        missingTpexMargin: {d13, d9},
        priceCounts: {d13: 0},
      );

      final result = await updater.syncMarketWideData(date: today);

      // 7/13 完全不打 API（連融資都不打——那天根本沒開市）
      verifyNever(
        () => mockTradingRepo.syncAllDayTradingFromTwse(date: d13, force: true),
      );
      verifyNever(
        () => mockTradingRepo.backfillMarginTradingByDate(
          date: d13,
          markets: any(named: 'markets'),
        ),
      );
      // 更舊的 7/9 仍然補得到（斷路器沒被空抓吃掉）
      verify(
        () => mockTradingRepo.backfillMarginTradingByDate(
          date: d9,
          markets: any(named: 'markets'),
        ),
      ).called(1);
      expect(result.backfilledDays, 1);
    });

    test('單一來源永久失效不餓死掃描：dead 後其他日子照補（finding A）', () async {
      // 上櫃融資永久失效；當沖在 d13/d9/d8 已足額、但更舊的 d7/d6 缺
      final d7 = DateTime(2026, 7, 7);
      final d6 = DateTime(2026, 7, 6);
      when(
        () => mockDb.countMarginTradingByDateAndMarket(any(), any()),
      ).thenAnswer((inv) async {
        final m = inv.positionalArguments[1] as String;
        return m == MarketCode.tpex ? 0 : twseThreshold + 1; // 上櫃全缺
      });
      when(
        () => mockDb.getDayTradingCountForDateAndMarket(any(), any()),
      ).thenAnswer((inv) async {
        final d = inv.positionalArguments[0] as DateTime;
        return (d == d7 || d == d6) ? 0 : DataFreshness.twseBatchThreshold + 1;
      });
      when(
        () => mockDb.countPricesByDateAndMarket(any(), any()),
      ).thenAnswer((_) async => 900);
      stubBackfillMargin(twseRows: 0, tpexRows: 0); // 上櫃永遠回 0

      final result = await updater.syncMarketWideData(date: today);

      // 上櫃連 3 天無進度 → dead → 不再阻擋掃描 → 更舊的當沖缺漏日補得到
      verify(
        () => mockTradingRepo.syncAllDayTradingFromTwse(date: d7, force: true),
      ).called(1);
      verify(
        () => mockTradingRepo.syncAllDayTradingFromTwse(date: d6, force: true),
      ).called(1);
      expect(result.backfilledDays, 2, reason: '兩個當沖缺漏日都該補到');
    });

    test('只有上櫃股票（上市主檔為空）→ 回補仍運作（finding B）', () async {
      when(
        () => mockDb.countStocksByMarket(MarketCode.twse),
      ).thenAnswer((_) async => 0);
      // 上市價格恆 0（沒股票），但上櫃有價格 → 該日仍是交易日
      when(() => mockDb.countPricesByDateAndMarket(any(), any())).thenAnswer((
        inv,
      ) async {
        final m = inv.positionalArguments[1] as String;
        return m == MarketCode.twse ? 0 : 700;
      });
      stubCoverage(missingTpexMargin: {d13});

      final result = await updater.syncMarketWideData(date: today);

      final markets =
          verify(
                () => mockTradingRepo.backfillMarginTradingByDate(
                  date: d13,
                  markets: captureAny(named: 'markets'),
                ),
              ).captured.single
              as Set<String>;
      expect(markets, {MarketCode.tpex}, reason: '上市無股票就不該被列入');
      expect(result.backfilledDays, 1, reason: '不該因上市無價格而整個 no-op');
    });

    test('端點持續回「非零但不足額」→ 判定無進度、斷路（finding C）', () async {
      // 4 個缺漏日：上市在前 3 天各失敗一次 → 第 3 天後 dead → 第 4 天不再帶它
      final d7 = DateTime(2026, 7, 7);
      stubCoverage(
        missingTwseMargin: {d13, d9, d8, d7},
        missingTpexMargin: {d13, d9, d8, d7},
      );
      // 上市只回 100 筆（< 門檻 500）→ 不算進度
      stubBackfillMargin(twseRows: 100, tpexRows: 700);

      final result = await updater.syncMarketWideData(date: today);

      // 上櫃每天都足額 → 有進度；上市每天不足額 → 3 次後 dead
      expect(result.backfilledDays, greaterThan(0), reason: '上櫃仍有進度');
      final calls = verify(
        () => mockTradingRepo.backfillMarginTradingByDate(
          date: any(named: 'date'),
          markets: captureAny(named: 'markets'),
        ),
      ).captured.cast<Set<String>>();
      expect(
        calls.last.contains(MarketCode.twse),
        isFalse,
        reason: '上市連 3 天不足額後應被標記 dead、不再嘗試',
      );
    });
  });
}
