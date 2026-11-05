import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/constants/market_codes.dart';
import 'package:daredevil/core/utils/date_context.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/data/repositories/heatmap_repository.dart';
import 'package:daredevil/domain/models/heatmap.dart';
import 'package:daredevil/domain/services/heatmap/heatmap_grouping.dart';

final _d1001 = DateContext.normalize(DateTime(2026, 10, 1));
final _d1005 = DateContext.normalize(DateTime(2026, 10, 5));
final _d1006 = DateContext.normalize(DateTime(2026, 10, 6));
final _d1007 = DateContext.normalize(DateTime(2026, 10, 7));

void main() {
  late AppDatabase db;
  late HeatmapRepository repo;

  setUp(() async {
    db = AppDatabase.forTesting();
    repo = HeatmapRepository(db);
    await db.upsertStocks([
      for (final s in ['9911', '9912', '9913', '9914'])
        StockMasterCompanion.insert(
          symbol: s,
          name: '測試$s',
          market: MarketCode.tpex,
          industry: const Value('測試業'),
        ),
    ]);
    for (final s in ['9911', '9912', '9913', '9914']) {
      await db
          .into(db.dailyPrice)
          .insert(
            DailyPriceCompanion.insert(
              symbol: s,
              date: _d1007,
              close: const Value(50),
              priceChange: const Value(1),
            ),
          );
    }
  });

  tearDown(() => db.close());

  Future<void> foreign(String symbol, DateTime date, double? shares) =>
      db.insertShareholdingData([
        ShareholdingCompanion.insert(
          symbol: symbol,
          date: date,
          sharesIssued: Value(shares),
        ),
      ]);

  Future<void> insider(String symbol, DateTime date, double? shares) =>
      db.insertInsiderHoldingData([
        InsiderHoldingCompanion.insert(
          symbol: symbol,
          date: date,
          sharesIssued: Value(shares),
        ),
      ]);

  HeatmapStockInput stockOf(HeatmapMarketInput input, String symbol) =>
      input.stocks.firstWhere((s) => s.symbol == symbol);

  test('loadInput 帶入價格與兩個股數來源最新一筆與日期', () async {
    await foreign('9911', _d1001, 1000);
    await foreign('9911', _d1006, 1100);
    await insider('9911', _d1005, 1050);

    final input = await repo.loadInput(MarketCode.tpex, _d1007);

    expect(input.market, MarketCode.tpex);
    expect(input.dataDate, _d1007);
    expect(input.stocks.map((s) => s.symbol), ['9911', '9912', '9913', '9914']);
    final s = stockOf(input, '9911');
    expect(s.name, '測試9911');
    expect(s.industry, '測試業');
    expect(s.close, 50);
    expect(s.priceChange, 1);
    expect(s.foreign, (shares: 1100.0, date: _d1006));
    expect(s.insider, (shares: 1050.0, date: _d1005));
  });

  test('股數欄位為 null 的來源不帶', () async {
    await foreign('9912', _d1006, null);
    final input = await repo.loadInput(MarketCode.tpex, _d1007);
    expect(stockOf(input, '9912').foreign, isNull);
    expect(stockOf(input, '9912').insider, isNull);
  });

  test('自選與持股都算 mine，持股數量 0 的不算', () async {
    await db.addToWatchlist('9911');
    await db.upsertPortfolioPosition(
      PortfolioPositionCompanion.insert(
        symbol: '9912',
        quantity: const Value(1000),
      ),
    );
    await db.upsertPortfolioPosition(
      PortfolioPositionCompanion.insert(
        symbol: '9913',
        quantity: const Value(0),
      ),
    );
    final input = await repo.loadInput(MarketCode.tpex, _d1007);
    expect(input.mine, {'9911', '9912'});
  });

  test('兩個股數來源同一天，經 DB 讀回後選到外資', () async {
    await foreign('9914', _d1006, 1000);
    await insider('9914', _d1006, 1050);
    final s = stockOf(await repo.loadInput(MarketCode.tpex, _d1007), '9914');
    expect(
      resolveHeatmapShares(
        market: MarketCode.tpex,
        foreign: s.foreign,
        insider: s.insider,
      ),
      const SharesOk(1000),
    );
  });

  test('fingerprint 轉呼叫 DAO：沒有正式資料日回 null', () async {
    expect(await repo.fingerprint(MarketCode.tpex), isNull);
  });
}
