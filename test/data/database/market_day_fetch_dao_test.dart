import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/constants/market_codes.dart';
import 'package:daredevil/core/constants/market_dataset.dart';
import 'package:daredevil/data/database/app_database.dart';

void main() {
  late AppDatabase db;
  final day = DateTime(2026, 9, 24);

  setUp(() => db = AppDatabase.forTesting());
  tearDown(() => db.close());

  Future<void> record(DateTime fetchedAt, {int rows = 1200}) =>
      db.upsertMarketDayFetch(
        dataset: MarketDataset.prices.code,
        market: MarketCode.twse,
        date: day,
        fetchedAt: fetchedAt,
        rowCount: rows,
      );

  test('沒有狀態列時不算定案', () async {
    expect(
      await db.isMarketDayFinal(
        dataset: MarketDataset.prices,
        market: MarketCode.twse,
        date: day,
      ),
      isFalse,
    );
  });

  test('隔天抓的算定案，同日抓的不算', () async {
    await record(DateTime(2026, 9, 24, 21, 30));
    expect(
      await db.isMarketDayFinal(
        dataset: MarketDataset.prices,
        market: MarketCode.twse,
        date: day,
      ),
      isFalse,
    );
    await record(DateTime(2026, 9, 25, 15, 30));
    expect(
      await db.isMarketDayFinal(
        dataset: MarketDataset.prices,
        market: MarketCode.twse,
        date: day,
      ),
      isTrue,
    );
  });

  test('last-writer-wins：較晚寫入的同日初值讓該列回到未定案', () async {
    await record(DateTime(2026, 9, 25, 15, 30));
    await record(DateTime(2026, 9, 24, 23, 50));
    final row = await db.getMarketDayFetch(
      MarketDataset.prices.code,
      MarketCode.twse,
      day,
    );
    expect(row!.fetchedAt, DateTime(2026, 9, 24, 23, 50));
    expect(
      await db.isMarketDayFinal(
        dataset: MarketDataset.prices,
        market: MarketCode.twse,
        date: day,
      ),
      isFalse,
    );
  });

  test('分市場、分資料集各自獨立', () async {
    await record(DateTime(2026, 9, 25));
    expect(
      await db.isMarketDayFinal(
        dataset: MarketDataset.prices,
        market: MarketCode.tpex,
        date: day,
      ),
      isFalse,
    );
    expect(
      await db.isMarketDayFinal(
        dataset: MarketDataset.margin,
        market: MarketCode.twse,
        date: day,
      ),
      isFalse,
    );
  });

  test('getMarketDayFetchesSince 只回起始日（含）以後', () async {
    await record(DateTime(2026, 9, 25));
    await db.upsertMarketDayFetch(
      dataset: MarketDataset.prices.code,
      market: MarketCode.twse,
      date: DateTime(2026, 9, 22),
      fetchedAt: DateTime(2026, 9, 23),
      rowCount: 1200,
    );
    final rows = await db.getMarketDayFetchesSince(DateTime(2026, 9, 23));
    expect(rows.map((r) => r.date), [day]);
  });

  test('getOrInitSetting：第一次寫入，之後不覆寫', () async {
    expect(
      await db.getOrInitSetting('finality_tracking_since', '2026-09-29'),
      '2026-09-29',
    );
    expect(
      await db.getOrInitSetting('finality_tracking_since', '2026-10-01'),
      '2026-09-29',
    );
  });
}
