// 評分批次的股利情境（52 週規則用）：載入器讀完整度事實與價格窗內的
// 除權除息，以「價格窗首日～評分日」判斷每檔是否完整
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:daredevil/core/constants/market_codes.dart';
import 'package:daredevil/core/utils/calendar_month.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/data/repositories/news_repository.dart';
import 'package:daredevil/domain/models/dividend_context.dart';
import 'package:daredevil/domain/services/update/batch_data_loader.dart';

class _MockNewsRepo extends Mock implements NewsRepository {}

void main() {
  late AppDatabase db;
  late BatchDataLoader loader;
  final date = DateTime(2026, 10, 2);

  setUp(() async {
    db = AppDatabase.forTesting();
    final news = _MockNewsRepo();
    when(
      () => news.getNewsForStocksBatch(any(), days: any(named: 'days')),
    ).thenAnswer((_) async => {});
    loader = BatchDataLoader(database: db, newsRepository: news);
    await db.upsertStocks([
      for (final s in ['2330', '2836', '6669'])
        StockMasterCompanion.insert(symbol: s, name: s, market: 'TWSE'),
    ]);
  });

  tearDown(() => db.close());

  /// [first]～評分日逐日一根：價格窗首日＝[first]
  Future<void> seedPrices(String symbol, DateTime first) => db.insertPrices([
    for (
      var d = first;
      !d.isAfter(date);
      d = DateTime(d.year, d.month, d.day + 1)
    )
      DailyPriceCompanion.insert(
        symbol: symbol,
        date: d,
        close: const Value(100),
        volume: const Value(1000),
      ),
  ]);

  /// 兩市場 2025-09～2026-09 完成，10 月列到 [octThrough]
  Future<void> seedFacts({required DateTime octThrough}) async {
    for (final market in [MarketCode.twse, MarketCode.tpex]) {
      for (final m in CalendarMonth.descending(
        from: const CalendarMonth(2025, 9),
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
        to: octThrough,
        listedThrough: octThrough,
        listedKnownKeys: const {},
        notInMasterKeys: const {},
        recordedAt: DateTime(2026, 10, 2, 15),
      );
    }
  }

  test('窗口完整且有價格：complete，帶窗內事件', () async {
    await seedPrices('2330', DateTime(2025, 9, 1));
    await seedFacts(octThrough: date);
    await db.upsertDividendDistributions([
      DividendDistributionCompanion.insert(
        symbol: '2330',
        exDate: DateTime(2026, 9, 16),
        cashDividend: 7,
        stockSharesPerThousand: 0,
        closeBefore: const Value(2385),
        referencePrice: const Value(2377.99),
      ),
    ]);

    final batch = await loader.loadBatchData(date, ['2330']);

    final context = batch.dividendContexts['2330'];
    expect(context, isA<DividendComplete>());
    final event = (context as DividendComplete).events.single;
    expect(event.exDate, DateTime(2026, 9, 16));
    expect(event.factor, closeTo(2377.99 / 2385, 1e-12));
  });

  test('🚨 只有現金增資的 0/0 列（帶兩欄價格）也是還原事件：畫面用的查詢會濾掉它，這裡不可以', () async {
    await seedPrices('2330', DateTime(2025, 9, 1));
    await seedFacts(octThrough: date);
    await db.upsertDividendDistributions([
      DividendDistributionCompanion.insert(
        symbol: '2330',
        exDate: DateTime(2026, 7, 17),
        cashDividend: 0,
        stockSharesPerThousand: 0,
        closeBefore: const Value(93.5),
        referencePrice: const Value(86.68),
      ),
    ]);

    final batch = await loader.loadBatchData(date, ['2330']);

    final context = batch.dividendContexts['2330'];
    expect(context, isA<DividendComplete>());
    final event = (context as DividendComplete).events.single;
    expect(event.exDate, DateTime(2026, 7, 17));
    expect(event.factor, closeTo(86.68 / 93.5, 1e-12));
  });

  test('價格窗首日早於完整範圍（價格比事實早幾天）→ incomplete：完整度看整個價格窗', () async {
    await seedPrices('6669', DateTime(2025, 8, 29));
    await seedFacts(octThrough: date);

    final batch = await loader.loadBatchData(date, ['6669']);

    expect(batch.dividendContexts['6669'], isA<DividendIncomplete>());
  });

  test('🚨 本月列表日落後評分日（本月同步沒跑成的那一輪）→ incomplete', () async {
    await seedPrices('2330', DateTime(2025, 9, 1));
    await seedFacts(octThrough: DateTime(2026, 10, 1));

    final batch = await loader.loadBatchData(date, ['2330']);

    expect(batch.dividendContexts['2330'], isA<DividendIncomplete>());
  });

  test('窗內有缺價格的列 → incomplete；沒有價格的代號不列入', () async {
    await seedPrices('2836', DateTime(2025, 9, 1));
    await seedFacts(octThrough: date);
    await db.upsertDividendDistributions([
      DividendDistributionCompanion.insert(
        symbol: '2836',
        exDate: DateTime(2026, 9, 17),
        cashDividend: 0.15,
        stockSharesPerThousand: 45,
      ),
    ]);

    final batch = await loader.loadBatchData(date, ['2836', '2330']);

    expect(batch.dividendContexts['2836'], isA<DividendIncomplete>());
    expect(batch.dividendContexts.containsKey('2330'), isFalse);
  });
}
