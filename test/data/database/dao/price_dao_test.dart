import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;

import 'package:daredevil/data/database/app_database.dart';

void main() {
  late AppDatabase db;

  final today = DateTime.utc(2025, 6, 15);
  final yesterday = DateTime.utc(2025, 6, 14);
  final twoDaysAgo = DateTime.utc(2025, 6, 13);
  final weekAgo = DateTime.utc(2025, 6, 8);

  setUp(() {
    db = AppDatabase.forTesting();
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> insertTestStocks() async {
    await db.upsertStocks([
      StockMasterCompanion.insert(symbol: '2330', name: '台積電', market: 'TWSE'),
      StockMasterCompanion.insert(symbol: '2317', name: '鴻海', market: 'TWSE'),
      StockMasterCompanion.insert(symbol: '6488', name: '環球晶', market: 'TPEx'),
    ]);
  }

  group('PriceDao', () {
    setUp(() async {
      await insertTestStocks();
    });

    group('getPriceHistory', () {
      test('returns prices in ascending date order', () async {
        await db.insertPrices([
          DailyPriceCompanion.insert(
            symbol: '2330',
            date: today,
            close: const Value(110.0),
          ),
          DailyPriceCompanion.insert(
            symbol: '2330',
            date: yesterday,
            close: const Value(100.0),
          ),
          DailyPriceCompanion.insert(
            symbol: '2330',
            date: twoDaysAgo,
            close: const Value(95.0),
          ),
        ]);

        final history = await db.getPriceHistory('2330', startDate: twoDaysAgo);

        expect(history.length, 3);
        expect(history[0].close, 95.0);
        expect(history[1].close, 100.0);
        expect(history[2].close, 110.0);
      });

      test('filters by date range', () async {
        await db.insertPrices([
          DailyPriceCompanion.insert(
            symbol: '2330',
            date: today,
            close: const Value(110.0),
          ),
          DailyPriceCompanion.insert(
            symbol: '2330',
            date: yesterday,
            close: const Value(100.0),
          ),
          DailyPriceCompanion.insert(
            symbol: '2330',
            date: twoDaysAgo,
            close: const Value(95.0),
          ),
        ]);

        final history = await db.getPriceHistory(
          '2330',
          startDate: yesterday,
          endDate: yesterday,
        );

        expect(history.length, 1);
        expect(history.first.close, 100.0);
      });

      test('returns empty list for non-existent symbol', () async {
        final history = await db.getPriceHistory('9999', startDate: weekAgo);

        expect(history, isEmpty);
      });
    });

    group('getLatestPrice', () {
      test('returns most recent price', () async {
        await db.insertPrices([
          DailyPriceCompanion.insert(
            symbol: '2330',
            date: yesterday,
            close: const Value(100.0),
          ),
          DailyPriceCompanion.insert(
            symbol: '2330',
            date: today,
            close: const Value(110.0),
          ),
        ]);

        final latest = await db.getLatestPrice('2330');

        expect(latest, isNotNull);
        expect(latest!.close, 110.0);
        expect(latest.date, today);
      });

      test('returns null for non-existent symbol', () async {
        final latest = await db.getLatestPrice('9999');

        expect(latest, isNull);
      });
    });

    group('getRecentPrices', () {
      test('returns N distinct-date prices in descending order', () async {
        await db.insertPrices([
          DailyPriceCompanion.insert(
            symbol: '2330',
            date: twoDaysAgo,
            close: const Value(95.0),
          ),
          DailyPriceCompanion.insert(
            symbol: '2330',
            date: yesterday,
            close: const Value(100.0),
          ),
          DailyPriceCompanion.insert(
            symbol: '2330',
            date: today,
            close: const Value(110.0),
          ),
        ]);

        final recent = await db.getRecentPrices('2330', count: 2);

        expect(recent.length, 2);
        expect(recent[0].close, 110.0);
        expect(recent[1].close, 100.0);
      });

      test('returns fewer than N if not enough data', () async {
        await db.insertPrices([
          DailyPriceCompanion.insert(
            symbol: '2330',
            date: today,
            close: const Value(110.0),
          ),
        ]);

        final recent = await db.getRecentPrices('2330', count: 5);

        expect(recent.length, 1);
      });
    });

    group('getPriceCountForDate', () {
      test('counts prices for a given date', () async {
        await db.insertPrices([
          DailyPriceCompanion.insert(
            symbol: '2330',
            date: today,
            close: const Value(110.0),
          ),
          DailyPriceCompanion.insert(
            symbol: '2317',
            date: today,
            close: const Value(50.0),
          ),
          DailyPriceCompanion.insert(
            symbol: '2330',
            date: yesterday,
            close: const Value(100.0),
          ),
        ]);

        final count = await db.getPriceCountForDate(today);

        expect(count, 2);
      });

      test('returns 0 for date with no data', () async {
        final count = await db.getPriceCountForDate(today);

        expect(count, 0);
      });
    });

    group('getPricesForDate', () {
      test('returns all prices for a date', () async {
        await db.insertPrices([
          DailyPriceCompanion.insert(
            symbol: '2330',
            date: today,
            close: const Value(110.0),
          ),
          DailyPriceCompanion.insert(
            symbol: '2317',
            date: today,
            close: const Value(50.0),
          ),
        ]);

        final prices = await db.getPricesForDate(today);

        expect(prices.length, 2);
      });
    });

    group('getLatestDataDate', () {
      test('returns the most recent date in daily_price', () async {
        await db.insertPrices([
          DailyPriceCompanion.insert(
            symbol: '2330',
            date: yesterday,
            close: const Value(100.0),
          ),
          DailyPriceCompanion.insert(
            symbol: '2330',
            date: today,
            close: const Value(110.0),
          ),
        ]);

        final latestDate = await db.getLatestDataDate();

        expect(latestDate, isNotNull);
        expect(latestDate, today);
      });

      test('returns null for empty table', () async {
        final latestDate = await db.getLatestDataDate();

        expect(latestDate, isNull);
      });
    });

    group('getLatestInstitutionalDate', () {
      test('returns the most recent date in daily_institutional', () async {
        await db.insertInstitutionalData([
          DailyInstitutionalCompanion.insert(
            symbol: '2330',
            date: yesterday,
            foreignNet: const Value(1000.0),
          ),
          DailyInstitutionalCompanion.insert(
            symbol: '2330',
            date: today,
            foreignNet: const Value(2000.0),
          ),
        ]);

        final latestDate = await db.getLatestInstitutionalDate();

        expect(latestDate, isNotNull);
        expect(latestDate, today);
      });

      test('returns null for empty table', () async {
        final latestDate = await db.getLatestInstitutionalDate();

        expect(latestDate, isNull);
      });
    });

    group('getLatestPricesBatch', () {
      test('returns latest price per symbol', () async {
        await db.insertPrices([
          DailyPriceCompanion.insert(
            symbol: '2330',
            date: yesterday,
            close: const Value(100.0),
          ),
          DailyPriceCompanion.insert(
            symbol: '2330',
            date: today,
            close: const Value(110.0),
          ),
          DailyPriceCompanion.insert(
            symbol: '2317',
            date: today,
            close: const Value(50.0),
          ),
        ]);

        final result = await db.getLatestPricesBatch(['2330', '2317']);

        expect(result.length, 2);
        expect(result['2330']!.close, 110.0);
        expect(result['2317']!.close, 50.0);
      });

      test('returns empty map for empty input', () async {
        final result = await db.getLatestPricesBatch([]);

        expect(result, isEmpty);
      });

      test('skips symbols with no data', () async {
        await db.insertPrices([
          DailyPriceCompanion.insert(
            symbol: '2330',
            date: today,
            close: const Value(110.0),
          ),
        ]);

        final result = await db.getLatestPricesBatch(['2330', '9999']);

        expect(result.length, 1);
        expect(result['2330'], isNotNull);
        expect(result['9999'], isNull);
      });

      test('帶 basePrice（手動組 entry 的欄位不可漏）', () async {
        await db.insertPrices([
          DailyPriceCompanion.insert(
            symbol: '2330',
            date: today,
            close: const Value(110.0),
            basePrice: const Value(105.0),
          ),
        ]);

        final result = await db.getLatestPricesBatch(['2330']);

        expect(result['2330']!.basePrice, 105.0);
      });
    });

    group('getPriceHistoryBatch', () {
      test('returns grouped price histories', () async {
        await db.insertPrices([
          DailyPriceCompanion.insert(
            symbol: '2330',
            date: yesterday,
            close: const Value(100.0),
          ),
          DailyPriceCompanion.insert(
            symbol: '2330',
            date: today,
            close: const Value(110.0),
          ),
          DailyPriceCompanion.insert(
            symbol: '2317',
            date: today,
            close: const Value(50.0),
          ),
        ]);

        final result = await db.getPriceHistoryBatch([
          '2330',
          '2317',
        ], startDate: weekAgo);

        expect(result['2330']?.length, 2);
        expect(result['2317']?.length, 1);
      });

      test('returns empty map for empty symbols', () async {
        final result = await db.getPriceHistoryBatch([], startDate: weekAgo);

        expect(result, isEmpty);
      });
    });

    group('getSymbolsWithSufficientData', () {
      test('returns symbols meeting minDays threshold', () async {
        // Insert 3 days for 2330 and 1 day for 2317
        await db.insertPrices([
          DailyPriceCompanion.insert(
            symbol: '2330',
            date: twoDaysAgo,
            close: const Value(95.0),
          ),
          DailyPriceCompanion.insert(
            symbol: '2330',
            date: yesterday,
            close: const Value(100.0),
          ),
          DailyPriceCompanion.insert(
            symbol: '2330',
            date: today,
            close: const Value(110.0),
          ),
          DailyPriceCompanion.insert(
            symbol: '2317',
            date: today,
            close: const Value(50.0),
          ),
        ]);

        final symbols = await db.getSymbolsWithSufficientData(
          minDays: 3,
          startDate: weekAgo,
          endDate: today,
        );

        expect(symbols, contains('2330'));
        expect(symbols, isNot(contains('2317')));
      });

      test('excludes inactive stocks', () async {
        // Make 2317 inactive
        await (db.update(db.stockMaster)..where((t) => t.symbol.equals('2317')))
            .write(const StockMasterCompanion(isActive: Value(false)));

        await db.insertPrices([
          DailyPriceCompanion.insert(
            symbol: '2330',
            date: today,
            close: const Value(110.0),
          ),
          DailyPriceCompanion.insert(
            symbol: '2317',
            date: today,
            close: const Value(50.0),
          ),
        ]);

        final symbols = await db.getSymbolsWithSufficientData(
          minDays: 1,
          startDate: weekAgo,
          endDate: today,
        );

        expect(symbols, contains('2330'));
        expect(symbols, isNot(contains('2317')));
      });

      test('returns empty list when no data', () async {
        final symbols = await db.getSymbolsWithSufficientData(
          minDays: 1,
          startDate: weekAgo,
          endDate: today,
        );

        expect(symbols, isEmpty);
      });
    });

    group('insertPrices', () {
      test('upserts on conflict', () async {
        await db.insertPrices([
          DailyPriceCompanion.insert(
            symbol: '2330',
            date: today,
            close: const Value(100.0),
          ),
        ]);
        await db.insertPrices([
          DailyPriceCompanion.insert(
            symbol: '2330',
            date: today,
            close: const Value(200.0),
          ),
        ]);

        final latest = await db.getLatestPrice('2330');

        expect(latest!.close, 200.0);
      });
    });

    group('getAllPricesInRange', () {
      test('returns all symbols grouped by symbol', () async {
        await db.insertPrices([
          DailyPriceCompanion.insert(
            symbol: '2330',
            date: today,
            close: const Value(110.0),
          ),
          DailyPriceCompanion.insert(
            symbol: '2317',
            date: today,
            close: const Value(50.0),
          ),
          DailyPriceCompanion.insert(
            symbol: '6488',
            date: today,
            close: const Value(600.0),
          ),
        ]);

        final result = await db.getAllPricesInRange(startDate: weekAgo);

        expect(result.keys.length, 3);
        expect(result['2330']?.length, 1);
      });

      test('respects endDate filter', () async {
        await db.insertPrices([
          DailyPriceCompanion.insert(
            symbol: '2330',
            date: yesterday,
            close: const Value(100.0),
          ),
          DailyPriceCompanion.insert(
            symbol: '2330',
            date: today,
            close: const Value(110.0),
          ),
        ]);

        final result = await db.getAllPricesInRange(
          startDate: weekAgo,
          endDate: yesterday,
        );

        expect(result['2330']?.length, 1);
        expect(result['2330']?.first.close, 100.0);
      });
    });

    group('getHistoricalDataProgress', () {
      test('counts active stocks with sufficient data', () async {
        // Insert enough prices for 2330 (2 days) and only 1 for 2317
        await db.insertPrices([
          DailyPriceCompanion.insert(
            symbol: '2330',
            date: yesterday,
            close: const Value(100.0),
          ),
          DailyPriceCompanion.insert(
            symbol: '2330',
            date: today,
            close: const Value(110.0),
          ),
          DailyPriceCompanion.insert(
            symbol: '2317',
            date: today,
            close: const Value(50.0),
          ),
        ]);

        final progress = await db.getHistoricalDataProgress();

        // total = 2 (both have price data), completed = 0 (neither has 200+ days)
        expect(progress.total, 2);
        expect(progress.completed, 0);
      });

      test('returns zeros for empty table', () async {
        final progress = await db.getHistoricalDataProgress();

        expect(progress.total, 0);
        expect(progress.completed, 0);
      });
    });

    group('cleanupInvalidStockCodes', () {
      test('removes 6-digit warrant codes but keeps ETFs', () async {
        await db.upsertStocks([
          StockMasterCompanion.insert(
            symbol: '080585',
            name: '權證A',
            market: 'TWSE',
          ),
          StockMasterCompanion.insert(
            symbol: '006208',
            name: '富邦台50',
            market: 'TWSE',
          ),
        ]);

        await db.insertPrices([
          DailyPriceCompanion.insert(
            symbol: '080585',
            date: today,
            close: const Value(1.0),
          ),
          DailyPriceCompanion.insert(
            symbol: '006208',
            date: today,
            close: const Value(80.0),
          ),
        ]);

        final results = await db.cleanupInvalidStockCodes();

        expect(results['daily_price'], 1);
        expect(results['stock_master'], 1);

        // ETF should still exist
        final etf = await db.getStock('006208');
        expect(etf, isNotNull);

        // Warrant should be gone
        final warrant = await db.getStock('080585');
        expect(warrant, isNull);
      });
    });
  });
}
