import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/constants/market_codes.dart';
import 'package:daredevil/core/constants/market_index_names.dart';
import 'package:daredevil/core/constants/transaction_types.dart';
import 'package:daredevil/core/utils/date_context.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/domain/services/close_summary/close_summary_builder.dart';
import 'package:daredevil/domain/services/close_summary/close_summary_loader.dart';
import 'package:daredevil/domain/services/close_summary/price_checks.dart';

/// 資料日：2026-11-19（四）
final _d = DateTime(2026, 11, 19);
final _prev = DateTime(2026, 11, 18);
final _now = DateTime(2026, 11, 19, 17);

/// 從 [end] 往回 [count] 個平日（含 end），升冪
List<DateTime> _weekdays(DateTime end, int count) {
  final out = <DateTime>[];
  var d = end;
  while (out.length < count) {
    if (d.weekday != DateTime.saturday && d.weekday != DateTime.sunday) {
      out.add(d);
    }
    d = d.subtract(const Duration(days: 1));
  }
  return out.reversed.toList();
}

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting());
  tearDown(() => db.close());

  Future<void> seedStocks() => db.upsertStocks([
    StockMasterCompanion.insert(symbol: '2330', name: '台積電', market: 'TWSE'),
    StockMasterCompanion.insert(symbol: '6488', name: '環球晶', market: 'TPEx'),
  ]);

  Future<void> seedPrices(String symbol, List<DateTime> days) =>
      db.insertPrices([
        for (final d in days)
          DailyPriceCompanion.insert(
            symbol: symbol,
            date: d,
            open: const Value(100),
            high: const Value(102),
            low: const Value(98),
            close: const Value(100),
            volume: const Value(5000000),
          ),
      ]);

  Future<void> seedInstitutional(String symbol, List<DateTime> days) =>
      db.insertInstitutionalData([
        for (final d in days)
          DailyInstitutionalCompanion.insert(
            symbol: symbol,
            date: d,
            foreignNet: const Value(1000),
          ),
      ]);

  Future<void> seedTaiex(List<DateTime> days) => db.upsertMarketIndices([
    for (final d in days)
      MarketIndexCompanion.insert(
        date: d,
        name: MarketIndexNames.taiex,
        close: 30000,
        change: 0,
        changePercent: 0,
      ),
  ]);

  test('指定 asOf：價格、法人、指數都只讀到那天為止', () async {
    await seedStocks();
    await db.addToWatchlist('2330');
    await seedPrices('2330', _weekdays(_d, 30));
    await seedInstitutional('2330', [_prev, _d]);
    await seedTaiex([_prev, _d]);

    final input = (await loadCloseSummaryInput(db, now: _now, asOf: _prev))!;
    expect(input.dataDate, _prev);
    expect(input.prices['2330']!.last.date, _prev);
    expect(input.institutional['2330']!.last.date, _prev);
    expect(input.taiex.last.date, _prev);
    expect(input.now, _now);
    expect(
      input.institutionalReadyByMarket[MarketCode.twse],
      isTrue,
      reason: '看的是 asOf 那天有沒有列，不是全表最新日',
    );
  });

  test('上櫃價格到了、法人只到前一天 → 上櫃法人未到，上市已到', () async {
    await seedStocks();
    await db.addToWatchlist('2330');
    await db.addToWatchlist('6488');
    await seedPrices('2330', _weekdays(_d, 5));
    await seedPrices('6488', _weekdays(_d, 5));
    await seedInstitutional('2330', [_prev, _d]);
    await seedInstitutional('6488', [_prev]);

    final input = (await loadCloseSummaryInput(db, now: _now))!;
    expect(input.dataDate, _d);
    expect(input.priceReadyByMarket, {
      MarketCode.twse: true,
      MarketCode.tpex: true,
    });
    expect(input.institutionalReadyByMarket, {
      MarketCode.twse: true,
      MarketCode.tpex: false,
    });
  });

  test('上櫃行情沒寫入 → 上櫃價格未到', () async {
    await seedStocks();
    await db.addToWatchlist('6488');
    await seedPrices('2330', _weekdays(_d, 5));
    await seedPrices('6488', _weekdays(_prev, 5));

    final input = (await loadCloseSummaryInput(db, now: _now))!;
    expect(input.priceReadyByMarket[MarketCode.tpex], isFalse);
  });

  test('持股進場在 200 天前 → 讀到的價格涵蓋進場日之前 21 根，算得出成本守門價', () async {
    await seedStocks();
    final entry = DateContext.normalize(_d.subtract(const Duration(days: 200)));
    final entryDay = _weekdays(entry, 1).single;
    await seedPrices('2330', _weekdays(_d, 200));
    await db.insertTransaction(
      PortfolioTransactionCompanion.insert(
        symbol: '2330',
        txType: TransactionTypes.buy,
        date: entryDay,
        quantity: 1000,
        price: 100,
      ),
    );
    await db.upsertPortfolioPosition(
      PortfolioPositionCompanion.insert(
        symbol: '2330',
        quantity: const Value(1000),
        avgCost: const Value(100),
      ),
    );

    final input = (await loadCloseSummaryInput(db, now: _now))!;
    final prices = input.prices['2330']!;
    final beforeEntry = prices.where((p) => !p.date.isAfter(entryDay)).length;
    expect(beforeEntry, greaterThanOrEqualTo(21));

    final row = buildCloseSummary(input).sections.single.rows.single;
    expect(row.holding, isNotNull);
    expect(row.holding!.stopPrice, isNotNull);
  });

  test('兩筆舊持股進場日不同 → 從較早那筆往前讀，兩筆都算得出成本守門價', () async {
    await seedStocks();
    for (final (symbol, daysAgo) in [('2330', 200), ('6488', 300)]) {
      final entryDay = _weekdays(
        _d.subtract(Duration(days: daysAgo)),
        1,
      ).single;
      await seedPrices(symbol, _weekdays(_d, 240));
      await db.insertTransaction(
        PortfolioTransactionCompanion.insert(
          symbol: symbol,
          txType: TransactionTypes.buy,
          date: entryDay,
          quantity: 1000,
          price: 100,
        ),
      );
      await db.upsertPortfolioPosition(
        PortfolioPositionCompanion.insert(
          symbol: symbol,
          quantity: const Value(1000),
          avgCost: const Value(100),
        ),
      );
    }

    final input = (await loadCloseSummaryInput(db, now: _now))!;
    final rows = buildCloseSummary(input).sections.single.rows;
    expect(rows.map((r) => r.symbol).toSet(), {'2330', '6488'});
    for (final row in rows) {
      expect(row.holding!.stopPrice, isNotNull, reason: row.symbol);
    }
  });

  test('只有進場早的持股往前讀；其他自選照 130 天', () async {
    await seedStocks();
    await db.addToWatchlist('6488');
    final entryDay = _weekdays(
      _d.subtract(const Duration(days: 200)),
      1,
    ).single;
    await seedPrices('2330', _weekdays(_d, 200));
    await seedPrices('6488', _weekdays(_d, 200));
    await db.insertTransaction(
      PortfolioTransactionCompanion.insert(
        symbol: '2330',
        txType: TransactionTypes.buy,
        date: entryDay,
        quantity: 1000,
        price: 100,
      ),
    );
    await db.upsertPortfolioPosition(
      PortfolioPositionCompanion.insert(
        symbol: '2330',
        quantity: const Value(1000),
        avgCost: const Value(100),
      ),
    );

    final input = (await loadCloseSummaryInput(db, now: _now))!;
    final lookbackStart = _d.subtract(const Duration(days: 130));
    expect(input.prices['2330']!.first.date.isBefore(lookbackStart), isTrue);
    expect(input.prices['6488']!.first.date.isBefore(lookbackStart), isFalse);
  });

  test('讀取區間：價格夠 61 根、法人同一起點、指數夠 21 筆、營收夠 3 個月', () async {
    await seedStocks();
    await db.addToWatchlist('2330');
    final days = _weekdays(_d, 100);
    await seedPrices('2330', days);
    await seedInstitutional('2330', days);
    await seedTaiex(days);
    await db.insertMonthlyRevenue([
      for (var m = 7; m <= 10; m++)
        MonthlyRevenueCompanion.insert(
          symbol: '2330',
          date: DateTime(2026, m),
          revenueYear: 2026,
          revenueMonth: m,
          revenue: 1000,
          yoyGrowth: const Value(50),
        ),
    ]);

    final input = (await loadCloseSummaryInput(db, now: _now))!;
    final prices = input.prices['2330']!;
    expect(prices.length, greaterThanOrEqualTo(61));
    expect(input.institutional['2330']!.first.date, prices.first.date);
    expect(input.taiex.length, greaterThanOrEqualTo(21));
    expect(input.revenues['2330']!.length, greaterThanOrEqualTo(3));

    final summary = buildCloseSummary(input);
    final row = summary.sections.single.rows.single;
    expect(row.prerequisites!.moving, isNot(CheckOutcome.insufficient));
    expect(row.prerequisites!.revenue, isNot(CheckOutcome.insufficient));
    expect(summary.throttle, isNotNull);
  });

  test('資料庫沒有任何價格 → null', () async {
    expect(await loadCloseSummaryInput(db, now: _now), isNull);
  });

  test('有價格但沒有自選也沒有持股 → 有輸入、清單都空', () async {
    await seedStocks();
    await seedPrices('2330', _weekdays(_d, 5));
    final input = (await loadCloseSummaryInput(db, now: _now))!;
    expect(input.watchlist, isEmpty);
    expect(input.positions, isEmpty);
    expect(input.prices, isEmpty);
    expect(buildCloseSummary(input).sections, isEmpty);
  });
}
