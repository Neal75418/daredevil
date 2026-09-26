import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/constants/market_codes.dart';
import 'package:daredevil/core/constants/market_dataset.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/data/repositories/market_day_fetch_ledger.dart';

void main() {
  late AppDatabase db;
  late MarketDayFetchLedger ledger;
  final day = DateTime(2026, 9, 24);
  final runStart = DateTime(2026, 9, 25, 15, 30);

  setUp(() async {
    db = AppDatabase.forTesting();
    // 上市 4 檔 → 門檻 ceil(4 × 0.5) = 2
    await db.upsertStocks([
      for (final s in ['1101', '1102', '1103', '1104'])
        StockMasterCompanion.insert(
          symbol: s,
          name: s,
          market: MarketCode.twse,
        ),
    ]);
    ledger = MarketDayFetchLedger(database: db, fetchedAt: runStart);
  });

  tearDown(() => db.close());

  Future<MarketDayFetchEntry?> row(MarketDataset ds) =>
      db.getMarketDayFetch(ds.code, MarketCode.twse, day);

  test('列數達門檻：記錄，fetchedAt 取本輪開始時間', () async {
    final ok = await ledger.report(
      dataset: MarketDataset.prices,
      market: MarketCode.twse,
      date: day,
      rows: 2,
    );
    expect(ok, isTrue);
    final r = await row(MarketDataset.prices);
    expect(r!.fetchedAt, runStart);
    expect(r.rowCount, 2);
    expect(ledger.recorded.single.dataset, MarketDataset.prices);
  });

  test('列數未達門檻：不記錄（尚未發布或抓取不完整）', () async {
    final ok = await ledger.report(
      dataset: MarketDataset.prices,
      market: MarketCode.twse,
      date: day,
      rows: 1,
    );
    expect(ok, isFalse);
    expect(await row(MarketDataset.prices), isNull);
    expect(ledger.recorded, isEmpty);
  });

  test('該市場沒有在市股票：不記錄', () async {
    final ok = await ledger.report(
      dataset: MarketDataset.prices,
      market: MarketCode.tpex,
      date: day,
      rows: 900,
    );
    expect(ok, isFalse);
  });

  test('當沖：價格覆蓋不足時即使當沖列數夠也不記錄', () async {
    final ok = await ledger.report(
      dataset: MarketDataset.dayTrading,
      market: MarketCode.twse,
      date: day,
      rows: 4,
    );
    expect(ok, isFalse, reason: '分母缺失時比例全是 0，記成定案就永遠不會重抓');
    expect(await row(MarketDataset.dayTrading), isNull);
  });

  test('當沖：價格覆蓋達門檻才記錄', () async {
    await db.insertPrices([
      for (final s in ['1101', '1102'])
        DailyPriceCompanion.insert(
          symbol: s,
          date: day,
          close: const Value(10),
          volume: const Value(1000),
        ),
    ]);
    final ok = await ledger.report(
      dataset: MarketDataset.dayTrading,
      market: MarketCode.twse,
      date: day,
      rows: 2,
    );
    expect(ok, isTrue);
  });

  group('MarketDayFetchLedger.isNearMiss', () {
    test(
      'rows 達 need 的 finalityNearMissWarnRatio 以上（但仍 < need）→ near miss',
      () {
        // 設計文件舉例：上櫃法人／當沖 738–748 列 vs 門檻 664（headroom 約 1.1×）
        expect(MarketDayFetchLedger.isNearMiss(738, 664), isTrue);
      },
    );

    test('rows 恰為 need 的 finalityNearMissWarnRatio 倍數 → near miss（邊界含）', () {
      expect(MarketDayFetchLedger.isNearMiss(80, 100), isTrue);
    });

    test('rows 遠低於 need（例如未發布時的 0 列）→ 不是 near miss', () {
      expect(MarketDayFetchLedger.isNearMiss(0, 664), isFalse);
    });

    test('rows 略低於門檻的 near-miss 判斷邊界', () {
      expect(MarketDayFetchLedger.isNearMiss(79, 100), isFalse);
    });
  });
}
