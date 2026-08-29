import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:daredevil/core/exceptions/app_exception.dart';
import 'package:daredevil/core/utils/clock.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/data/remote/finmind_client.dart';
import 'package:daredevil/data/loaders/stock_fundamentals_loader.dart';

// ==========================================
// Mocks
// ==========================================

class MockAppDatabase extends Mock implements AppDatabase {}

class MockFinMindClient extends Mock implements FinMindClient {}

class _FakeClock implements AppClock {
  @override
  DateTime now() => DateTime(2026, 2, 15, 14, 0);
}

// ==========================================
// Test Helpers
// ==========================================

StockValuationEntry createValuation({
  String symbol = '2330',
  DateTime? date,
  double? per = 25.0,
  double? pbr = 6.0,
  double? dividendYield = 2.0,
}) {
  return StockValuationEntry(
    symbol: symbol,
    date: date ?? DateTime(2026, 2, 13),
    per: per,
    pbr: pbr,
    dividendYield: dividendYield,
  );
}

MonthlyRevenueEntry createRevenue({
  String symbol = '2330',
  DateTime? date,
  int revenueYear = 2025,
  int revenueMonth = 12,
  double revenue = 200000000,
  double? momGrowth,
  double? yoyGrowth,
}) {
  return MonthlyRevenueEntry(
    symbol: symbol,
    date: date ?? DateTime(2025, 12, 10),
    revenueYear: revenueYear,
    revenueMonth: revenueMonth,
    revenue: revenue,
    momGrowth: momGrowth,
    yoyGrowth: yoyGrowth,
  );
}

FinancialDataEntry createEps({
  String symbol = '2330',
  DateTime? date,
  String dataType = 'EPS',
  double? value = 5.0,
}) {
  return FinancialDataEntry(
    symbol: symbol,
    date: date ?? DateTime(2025, 11, 14),
    statementType: 'INCOME',
    dataType: dataType,
    value: value,
  );
}

// ==========================================
// Tests
// ==========================================

void main() {
  late MockAppDatabase mockDb;
  late MockFinMindClient mockFinMind;
  late StockFundamentalsLoader loader;

  setUp(() {
    mockDb = MockAppDatabase();
    mockFinMind = MockFinMindClient();
    loader = StockFundamentalsLoader(
      db: mockDb,
      finMind: mockFinMind,
      clock: _FakeClock(),
    );
  });

  // ==========================================
  // loadAll — Valuation
  // ==========================================

  group('loadAll valuation', () {
    setUp(() {
      // Default stubs for other sub-methods
      when(
        () => mockDb.getMonthlyRevenueHistory(
          any(),
          startDate: any(named: 'startDate'),
        ),
      ).thenAnswer((_) async => <MonthlyRevenueEntry>[]);
      when(
        () => mockDb.getDividendHistory(any()),
      ).thenAnswer((_) async => <DividendHistoryEntry>[]);
      when(
        () => mockDb.getEPSHistory(any()),
      ).thenAnswer((_) async => <FinancialDataEntry>[]);
    });

    test('uses DB valuation when available', () async {
      when(
        () => mockDb.getValuationHistory(
          any(),
          startDate: any(named: 'startDate'),
        ),
      ).thenAnswer((_) async => [createValuation()]);

      final result = await loader.loadAll('2330');

      expect(result.latestPER, isNotNull);
      expect(result.latestPER!.per, 25.0);
      // Should NOT call API for valuation
      verifyNever(
        () => mockFinMind.getPERData(
          stockId: any(named: 'stockId'),
          startDate: any(named: 'startDate'),
          endDate: any(named: 'endDate'),
        ),
      );
    });

    test('falls back to API when DB has no valuation', () async {
      when(
        () => mockDb.getValuationHistory(
          any(),
          startDate: any(named: 'startDate'),
        ),
      ).thenAnswer((_) async => <StockValuationEntry>[]);

      const apiPer = FinMindPER(
        stockId: '2330',
        date: '2026-02-14',
        per: 20.0,
        pbr: 5.0,
        dividendYield: 3.0,
      );
      when(
        () => mockFinMind.getPERData(
          stockId: any(named: 'stockId'),
          startDate: any(named: 'startDate'),
          endDate: any(named: 'endDate'),
        ),
      ).thenAnswer((_) async => [apiPer]);

      final result = await loader.loadAll('2330');

      expect(result.latestPER, isNotNull);
      expect(result.latestPER!.dividendYield, 3.0);
    });

    test('returns null PER when both DB and API fail', () async {
      when(
        () => mockDb.getValuationHistory(
          any(),
          startDate: any(named: 'startDate'),
        ),
      ).thenThrow(Exception('DB error'));
      when(
        () => mockFinMind.getPERData(
          stockId: any(named: 'stockId'),
          startDate: any(named: 'startDate'),
          endDate: any(named: 'endDate'),
        ),
      ).thenThrow(Exception('API error'));

      final result = await loader.loadAll('2330');

      expect(result.latestPER, isNull);
    });
  });

  // ==========================================
  // loadAll — Revenue
  // ==========================================

  group('loadAll revenue', () {
    setUp(() {
      // Default stubs
      when(
        () => mockDb.getValuationHistory(
          any(),
          startDate: any(named: 'startDate'),
        ),
      ).thenAnswer((_) async => <StockValuationEntry>[]);
      when(
        () => mockFinMind.getPERData(
          stockId: any(named: 'stockId'),
          startDate: any(named: 'startDate'),
          endDate: any(named: 'endDate'),
        ),
      ).thenAnswer((_) async => <FinMindPER>[]);
      when(
        () => mockDb.getDividendHistory(any()),
      ).thenAnswer((_) async => <DividendHistoryEntry>[]);
      when(
        () => mockDb.getEPSHistory(any()),
      ).thenAnswer((_) async => <FinancialDataEntry>[]);
    });

    test('uses DB revenue when >= 6 months available', () async {
      final dbRevenues = List.generate(
        8,
        (i) => createRevenue(revenueMonth: i + 1),
      );
      when(
        () => mockDb.getMonthlyRevenueHistory(
          any(),
          startDate: any(named: 'startDate'),
        ),
      ).thenAnswer((_) async => dbRevenues);

      final result = await loader.loadAll('2330');

      expect(result.revenueData, hasLength(8));
      verifyNever(
        () => mockFinMind.getMonthlyRevenue(
          stockId: any(named: 'stockId'),
          startDate: any(named: 'startDate'),
          endDate: any(named: 'endDate'),
        ),
      );
    });

    test('uses API when DB has < 6 months', () async {
      // DB has only 3 entries
      final dbRevenues = List.generate(
        3,
        (i) => createRevenue(revenueMonth: i + 1),
      );
      when(
        () => mockDb.getMonthlyRevenueHistory(
          any(),
          startDate: any(named: 'startDate'),
        ),
      ).thenAnswer((_) async => dbRevenues);

      final apiRevenues = [
        FinMindRevenue(
          stockId: '2330',
          date: '2025-12-10',
          revenueYear: 2025,
          revenueMonth: 12,
          revenue: 200000000,
        ),
      ];
      when(
        () => mockFinMind.getMonthlyRevenue(
          stockId: any(named: 'stockId'),
          startDate: any(named: 'startDate'),
          endDate: any(named: 'endDate'),
        ),
      ).thenAnswer((_) async => apiRevenues);

      final result = await loader.loadAll('2330');

      expect(result.revenueData, hasLength(1)); // API data used
    });

    test('falls back to DB when API fails and DB has partial data', () async {
      final dbRevenues = [createRevenue()]; // Only 1 entry (< 6)
      when(
        () => mockDb.getMonthlyRevenueHistory(
          any(),
          startDate: any(named: 'startDate'),
        ),
      ).thenAnswer((_) async => dbRevenues);
      when(
        () => mockFinMind.getMonthlyRevenue(
          stockId: any(named: 'stockId'),
          startDate: any(named: 'startDate'),
          endDate: any(named: 'endDate'),
        ),
      ).thenThrow(Exception('API error'));

      final result = await loader.loadAll('2330');

      expect(result.revenueData, hasLength(1)); // DB fallback
    });

    test('returns empty when both DB and API fail', () async {
      when(
        () => mockDb.getMonthlyRevenueHistory(
          any(),
          startDate: any(named: 'startDate'),
        ),
      ).thenThrow(Exception('DB error'));
      when(
        () => mockFinMind.getMonthlyRevenue(
          stockId: any(named: 'stockId'),
          startDate: any(named: 'startDate'),
          endDate: any(named: 'endDate'),
        ),
      ).thenThrow(Exception('API error'));

      final result = await loader.loadAll('2330');

      expect(result.revenueData, isEmpty);
    });
  });

  // ==========================================
  // loadAll — EPS & quarter metrics
  // ==========================================

  group('loadAll EPS', () {
    setUp(() {
      when(
        () => mockDb.getValuationHistory(
          any(),
          startDate: any(named: 'startDate'),
        ),
      ).thenAnswer((_) async => <StockValuationEntry>[]);
      when(
        () => mockFinMind.getPERData(
          stockId: any(named: 'stockId'),
          startDate: any(named: 'startDate'),
          endDate: any(named: 'endDate'),
        ),
      ).thenAnswer((_) async => <FinMindPER>[]);
      when(
        () => mockDb.getMonthlyRevenueHistory(
          any(),
          startDate: any(named: 'startDate'),
        ),
      ).thenAnswer((_) async => <MonthlyRevenueEntry>[]);
      when(
        () => mockFinMind.getMonthlyRevenue(
          stockId: any(named: 'stockId'),
          startDate: any(named: 'startDate'),
          endDate: any(named: 'endDate'),
        ),
      ).thenAnswer((_) async => <FinMindRevenue>[]);
      when(
        () => mockDb.getDividendHistory(any()),
      ).thenAnswer((_) async => <DividendHistoryEntry>[]);
    });

    test('🚨 ROE 走 DAO 的唯一口徑,不得自己用「單季×4÷期末權益」', () async {
      // 2026-08-15 的數值稽核把 ROE 改成「近四季淨利 ÷ 平均權益」並在
      // financial_data_dao 註明舊口徑「量到的是台股獲利季節性而不是股東
      // 權益報酬率」——但只改了 DAO,個股詳情頁的 loader 沒跟上
      // (2026-08-29 DAO 稽核 H1)。實測 1,424 檔:中位差 3.59pp、p90
      // 15.07pp、**159 檔(11.2%)正負號相反**;最糟 4123 舊法 −243.58
      // vs DAO +6.00。使用者會看到 ROE_EXCELLENT 觸發、點進去卻是負的。
      when(
        () => mockDb.getEPSHistory(any()),
      ).thenAnswer((_) async => [createEps()]);
      when(
        () => mockDb.getLatestQuarterMetrics(any()),
      ).thenAnswer((_) async => {'IncomeAfterTaxes': 100.0});
      when(() => mockDb.getROEHistoryBatch(any())).thenAnswer(
        (_) async => {
          '2330': [
            FinancialDataEntry(
              symbol: '2330',
              date: DateTime(2026, 6, 30),
              statementType: 'ROE',
              dataType: 'ROE',
              value: 6.0, // DAO 口徑
              originName: null,
            ),
          ],
        },
      );

      final result = await loader.loadAll('2330');

      expect(result.quarterMetrics['ROE'], 6.0, reason: '詳情頁與評分引擎必須是同一個數字');
      verifyNever(() => mockDb.getEquityHistory(any()));
    });

    test('DAO 算不出 ROE(資料不齊)→ 不顯示,不用可得資料湊 ×4 頂替', () async {
      when(
        () => mockDb.getEPSHistory(any()),
      ).thenAnswer((_) async => [createEps()]);
      when(
        () => mockDb.getLatestQuarterMetrics(any()),
      ).thenAnswer((_) async => {'IncomeAfterTaxes': 100.0});
      when(
        () => mockDb.getROEHistoryBatch(any()),
      ).thenAnswer((_) async => <String, List<FinancialDataEntry>>{});

      final result = await loader.loadAll('2330');

      expect(
        result.quarterMetrics.containsKey('ROE'),
        isFalse,
        reason: '「資料不齊不產生該季 ROE」正是新口徑的設計,不得回退舊公式',
      );
    });

    test('loads EPS and quarter metrics', () async {
      final epsData = [createEps()];
      when(() => mockDb.getEPSHistory(any())).thenAnswer((_) async => epsData);
      when(
        () => mockDb.getLatestQuarterMetrics(any()),
      ).thenAnswer((_) async => {'GrossMargin': 50.0});

      final result = await loader.loadAll('2330');

      expect(result.epsData, hasLength(1));
      expect(result.quarterMetrics['GrossMargin'], 50.0);
    });

    test('skips quarter metrics when no EPS data', () async {
      when(
        () => mockDb.getEPSHistory(any()),
      ).thenAnswer((_) async => <FinancialDataEntry>[]);

      final result = await loader.loadAll('2330');

      expect(result.epsData, isEmpty);
      expect(result.quarterMetrics, isEmpty);
      verifyNever(() => mockDb.getLatestQuarterMetrics(any()));
    });

    test('DB 已有 ROE 時不覆寫(getLatestQuarterMetrics 先行)', () async {
      // 本測試原本斷言 `IncomeAfterTaxes × 4 ÷ Equity × 100 = 100.0`——
      // 那是舊口徑的**守護者**,把 2026-08-15 已判定為錯的公式釘死在
      // 測試裡(2026-08-29 DAO 稽核 H1)。ROE 現在一律由
      // getROEHistoryBatch 供應,這條改為釘「DB 已有值就不再取」。
      when(
        () => mockDb.getEPSHistory(any()),
      ).thenAnswer((_) async => [createEps(date: DateTime(2025, 11, 14))]);
      when(
        () => mockDb.getLatestQuarterMetrics(any()),
      ).thenAnswer((_) async => {'ROE': 18.5, 'IncomeAfterTaxes': 50000.0});

      final result = await loader.loadAll('2330');

      expect(result.quarterMetrics['ROE'], 18.5);
      verifyNever(() => mockDb.getROEHistoryBatch(any()));
    });

    test('handles EPS error gracefully', () async {
      when(() => mockDb.getEPSHistory(any())).thenThrow(Exception('DB error'));

      final result = await loader.loadAll('2330');

      expect(result.epsData, isEmpty);
      expect(result.quarterMetrics, isEmpty);
    });
  });

  // ==========================================
  // RateLimit rethrow 契約(2026-07-30 審查)
  // ==========================================
  //
  // 編碼標準:RateLimitException 必須 rethrow。限流是全域狀態——營收限流
  // 了,後面股利/估值的 API call 也會限流,繼續 fallback 只是燒重試;吞掉
  // 則 UI 顯示「部分基本面資料暫無法取得」的誤導文案。rethrow 後 caller
  // (stock_detail_provider)既有 catch 會把真實限流文案寫進
  // fundamentalsError,不影響整頁其他區塊。
  group('RateLimit rethrow 契約', () {
    setUp(() {
      when(
        () => mockDb.getValuationHistory(
          any(),
          startDate: any(named: 'startDate'),
        ),
      ).thenAnswer((_) async => [createValuation()]);
      when(
        () => mockDb.getDividendHistory(any()),
      ).thenAnswer((_) async => <DividendHistoryEntry>[]);
      when(
        () => mockDb.getEPSHistory(any()),
      ).thenAnswer((_) async => <FinancialDataEntry>[]);
      when(
        () => mockFinMind.getDividends(stockId: any(named: 'stockId')),
      ).thenAnswer((_) async => <FinMindDividend>[]);
    });

    test('營收 API 限流:rethrow 而非 fallback 吞掉', () async {
      when(
        () => mockDb.getMonthlyRevenueHistory(
          any(),
          startDate: any(named: 'startDate'),
        ),
      ).thenAnswer((_) async => [createRevenue()]); // <6 筆 → 走 API
      when(
        () => mockFinMind.getMonthlyRevenue(
          stockId: any(named: 'stockId'),
          startDate: any(named: 'startDate'),
          endDate: any(named: 'endDate'),
        ),
      ).thenThrow(const RateLimitException());

      await expectLater(
        loader.loadAll('2330'),
        throwsA(isA<RateLimitException>()),
      );
    });

    test('股利 API 限流:rethrow', () async {
      when(
        () => mockDb.getMonthlyRevenueHistory(
          any(),
          startDate: any(named: 'startDate'),
        ),
      ).thenAnswer(
        (_) async =>
            List.generate(6, (i) => createRevenue(revenueMonth: i + 1)),
      );
      when(
        () => mockFinMind.getDividends(stockId: any(named: 'stockId')),
      ).thenThrow(const RateLimitException());

      await expectLater(
        loader.loadAll('2330'),
        throwsA(isA<RateLimitException>()),
      );
    });

    test('非限流的 API 錯誤:維持 fallback 行為(回部分資料,不 throw)', () async {
      when(
        () => mockDb.getMonthlyRevenueHistory(
          any(),
          startDate: any(named: 'startDate'),
        ),
      ).thenAnswer((_) async => [createRevenue()]);
      when(
        () => mockFinMind.getMonthlyRevenue(
          stockId: any(named: 'stockId'),
          startDate: any(named: 'startDate'),
          endDate: any(named: 'endDate'),
        ),
      ).thenThrow(Exception('server 500'));

      final result = await loader.loadAll('2330');
      expect(result.revenueData, hasLength(1), reason: 'fallback 用 DB 部分資料');
    });
  });
}
