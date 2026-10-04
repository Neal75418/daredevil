// 個股頁股利摘要的載入：只讀 DB（配發表、完整度事實、股票名稱），不打
// FinMind 股利 API；資料不完整是摘要裡的建置中，只有讀取失敗回 null
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:daredevil/core/constants/market_codes.dart';
import 'package:daredevil/core/utils/calendar_month.dart';
import 'package:daredevil/core/utils/clock.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/data/loaders/stock_fundamentals_loader.dart';
import 'package:daredevil/data/remote/finmind_client.dart';
import 'package:daredevil/domain/services/dividend_summary.dart';

class _MockFinMind extends Mock implements FinMindClient {}

class _MockDb extends Mock implements AppDatabase {}

class _Clock implements AppClock {
  @override
  DateTime now() => DateTime(2026, 10, 2, 21, 30);
}

void main() {
  late AppDatabase db;
  late _MockFinMind finMind;
  late StockFundamentalsLoader loader;

  setUp(() async {
    db = AppDatabase.forTesting();
    finMind = _MockFinMind();
    when(
      () => finMind.getMonthlyRevenue(
        stockId: any(named: 'stockId'),
        startDate: any(named: 'startDate'),
        endDate: any(named: 'endDate'),
      ),
    ).thenAnswer((_) async => []);
    when(
      () => finMind.getPERData(
        stockId: any(named: 'stockId'),
        startDate: any(named: 'startDate'),
        endDate: any(named: 'endDate'),
      ),
    ).thenAnswer((_) async => []);
    loader = StockFundamentalsLoader(db: db, finMind: finMind, clock: _Clock());
    await db.upsertStocks([
      StockMasterCompanion.insert(symbol: '2330', name: '台積電', market: 'TWSE'),
      StockMasterCompanion.insert(symbol: '5314', name: '世紀*', market: 'TPEx'),
    ]);
  });

  tearDown(() => db.close());

  /// 兩市場自回補起點 2021-01 到 2026-09 都完成、10 月列到 10/2（顯示終點
  /// 要從回補起點連續才算得出來）
  Future<void> seedFacts() async {
    for (final market in [MarketCode.twse, MarketCode.tpex]) {
      for (final m in CalendarMonth.descending(
        from: const CalendarMonth(2021, 1),
        to: const CalendarMonth(2026, 9),
      )) {
        await db.completeDividendMonth(
          market: market,
          month: m,
          rows: const [],
          expectedKeys: const {},
          listedRows: 0,
          skippedSymbols: const {},
          completedAt: DateTime(2026, 10, 1),
        );
      }
      await db.recordDividendListing(
        market: market,
        from: DateTime(2026, 10, 1),
        to: DateTime(2026, 10, 2),
        listedThrough: DateTime(2026, 10, 2),
        listedKnownKeys: const {},
        notInMasterKeys: const {},
        recordedAt: DateTime(2026, 10, 2, 15),
      );
    }
  }

  test('配發表＋完整度事實 → 摘要；不打 FinMind 股利 API', () async {
    await seedFacts();
    await db.upsertDividendDistributions([
      DividendDistributionCompanion.insert(
        symbol: '2330',
        exDate: DateTime(2025, 9, 16),
        cashDividend: 5,
        stockSharesPerThousand: 0,
        closeBefore: const Value(1200),
        referencePrice: const Value(1195),
      ),
    ]);

    final result = await loader.loadAll('2330');

    final summary = result.dividendSummary!;
    expect(summary.displayEnd, DateTime(2026, 10, 2));
    expect(summary.parValueTen, isTrue); // 名稱來自主檔「台積電」
    expect(summary.pastYears.first.status, DividendYearStatus.paid);
    expect(summary.pastYears.first.cash, 5);
    final average = summary.average as DividendAverageValue;
    expect(average.fromYear, 2025);
    expect(average.cash, 5);
    // 兩種呼叫形狀都驗：mocktail 依具名參數的組合比對
    verifyNever(() => finMind.getDividends(stockId: any(named: 'stockId')));
    verifyNever(
      () => finMind.getDividends(
        stockId: any(named: 'stockId'),
        startDate: any(named: 'startDate'),
      ),
    );
  });

  test('名稱帶 *：摘要不假設面額 10 元', () async {
    await seedFacts();
    final result = await loader.loadAll('5314');
    expect(result.dividendSummary!.parValueTen, isFalse);
  });

  test('🚨 尚無任何完整度事實（新安裝）：摘要全部建置中，不是讀取失敗', () async {
    final result = await loader.loadAll('2330');
    expect(result.dividendSummary, isNotNull);
    expect(result.dividendSummary!.allBuilding, isTrue);
  });

  test('讀取失敗：摘要為 null，不往外拋', () async {
    final brokenDb = _MockDb();
    // 事實照常讀到，第二段的 getStock 丟錯（事實先讀；沒 stub 的話第一個
    // 讀取就因 mock 回 null 失敗，走不到這裡）
    when(() => brokenDb.getDividendListings()).thenAnswer((_) async => []);
    when(
      () => brokenDb.getDividendMonthLedgerEntries(),
    ).thenAnswer((_) async => []);
    when(() => brokenDb.getDividendUnresolved()).thenAnswer((_) async => []);
    when(
      () => brokenDb.getDividendMissingPriceKeys(),
    ).thenAnswer((_) async => <(String, DateTime)>{});
    when(() => brokenDb.getStock(any())).thenThrow(Exception('db locked'));
    final brokenLoader = StockFundamentalsLoader(
      db: brokenDb,
      finMind: finMind,
      clock: _Clock(),
    );

    final result = await brokenLoader.loadAll('2330');

    expect(result.dividendSummary, isNull);
    verify(() => brokenDb.getStock('2330')).called(1);
  });

  test('🚨 先讀完整度事實、再讀配發列：更新「先寫列、再寫事實」時，夾在兩段讀取之間也不會把缺列當成完整', () async {
    // 反過來（先讀列）時：讀列 → 更新補上一筆原本未解決的列並推進事實 → 讀事實，
    // 該年被判完整卻少了那一筆（例：今年顯示「尚未除息」）
    final mockDb = _MockDb();
    when(() => mockDb.getStock(any())).thenAnswer((_) async => null);
    when(() => mockDb.getDividendListings()).thenAnswer((_) async => []);
    when(
      () => mockDb.getDividendMonthLedgerEntries(),
    ).thenAnswer((_) async => []);
    when(() => mockDb.getDividendUnresolved()).thenAnswer((_) async => []);
    when(
      () => mockDb.getDividendMissingPriceKeys(),
    ).thenAnswer((_) async => <(String, DateTime)>{});
    when(
      () => mockDb.getDividendDistributions(any()),
    ).thenAnswer((_) async => []);

    await StockFundamentalsLoader(
      db: mockDb,
      finMind: finMind,
      clock: _Clock(),
    ).loadAll('2330');

    verifyInOrder([
      () => mockDb.getDividendListings(),
      () => mockDb.getDividendMonthLedgerEntries(),
      () => mockDb.getDividendUnresolved(),
      () => mockDb.getDividendMissingPriceKeys(),
      () => mockDb.getDividendDistributions('2330'),
    ]);
  });
}
