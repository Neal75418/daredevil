import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/data/database/app_database.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting();
  });

  tearDown(() async {
    await db.close();
  });

  group('Volume Alerts', () {
    setUp(() async {
      // 插入股票主檔
      await db.upsertStocks([
        StockMasterCompanion.insert(
          symbol: '2330',
          name: '台積電',
          market: 'TWSE',
        ),
      ]);

      // 插入 20 天歷史價格（平均成交量 = 10000）
      final now = DateTime.now();
      final prices = <DailyPriceCompanion>[];
      for (int i = 0; i < 20; i++) {
        prices.add(
          DailyPriceCompanion.insert(
            symbol: '2330',
            date: now.subtract(Duration(days: 20 - i)),
            open: const Value(500.0),
            high: const Value(510.0),
            low: const Value(490.0),
            close: const Value(500.0),
            volume: const Value(10000.0),
          ),
        );
      }
      await db.insertPrices(prices);
    });

    test(
      'VOLUME_SPIKE triggers when volume >= 4x average and price change >= 1.5%',
      () async {
        // 新增最新一天成交量 40000 (4x)
        await db.insertPrices([
          DailyPriceCompanion.insert(
            symbol: '2330',
            date: DateTime.now(),
            close: const Value(510.0),
            volume: const Value(40000.0),
          ),
        ]);

        // 建立 VOLUME_SPIKE 警示
        final alertId = await db.createPriceAlert(
          symbol: '2330',
          alertType: 'VOLUME_SPIKE',
          targetValue: 2.0, // 這個值對 VOLUME_SPIKE 不重要
        );

        // 檢查警示 - 成交量 40000 (4x)、價格變動 2%
        final triggered = await db.checkAlerts(
          {'2330': 510.0},
          {'2330': 2.0}, // 2% 價格變動
        );

        expect(triggered.length, 1);
        expect(triggered.first.id, alertId);
      },
    );

    test('VOLUME_SPIKE doesn\'t trigger when volume < 4x average', () async {
      // 成交量 30000 (3x) - 不足 4x
      await db.insertPrices([
        DailyPriceCompanion.insert(
          symbol: '2330',
          date: DateTime.now(),
          close: const Value(510.0),
          volume: const Value(30000.0),
        ),
      ]);

      await db.createPriceAlert(
        symbol: '2330',
        alertType: 'VOLUME_SPIKE',
        targetValue: 2.0,
      );

      final triggered = await db.checkAlerts({'2330': 510.0}, {'2330': 2.0});

      expect(triggered, isEmpty);
    });

    test('VOLUME_SPIKE doesn\'t trigger when price change < 1.5%', () async {
      // 成交量 40000 (4x) 但價格變動只有 1%
      await db.insertPrices([
        DailyPriceCompanion.insert(
          symbol: '2330',
          date: DateTime.now(),
          close: const Value(505.0),
          volume: const Value(40000.0),
        ),
      ]);

      await db.createPriceAlert(
        symbol: '2330',
        alertType: 'VOLUME_SPIKE',
        targetValue: 2.0,
      );

      final triggered = await db.checkAlerts(
        {'2330': 505.0},
        {'2330': 1.0}, // 只有 1% 價格變動
      );

      expect(triggered, isEmpty);
    });

    // targetValue 單位是張（UI：「成交量高於 {value} 張」），DB volume 是股
    test('VOLUME_ABOVE triggers when current volume >= target', () async {
      // 最新一天成交量 2 萬張（2000 萬股）>= 1.5 萬張
      await db.insertPrices([
        DailyPriceCompanion.insert(
          symbol: '2330',
          date: DateTime.now(),
          close: const Value(510.0),
          volume: const Value(20000000.0),
        ),
      ]);

      // 建立 VOLUME_ABOVE 警示（目標 15000 張）
      final alertId = await db.createPriceAlert(
        symbol: '2330',
        alertType: 'VOLUME_ABOVE',
        targetValue: 15000.0,
      );

      final triggered = await db.checkAlerts({'2330': 510.0}, {'2330': 2.0});

      expect(triggered.length, 1);
      expect(triggered.first.id, alertId);
    });

    test(
      'VOLUME_ABOVE doesn\'t trigger when current volume < target',
      () async {
        // 最新一天 2 萬張（2000 萬股）< 2.5 萬張。
        // 🚨 股數本身大於 25000：若誤把股數直接比張數會觸發
        await db.insertPrices([
          DailyPriceCompanion.insert(
            symbol: '2330',
            date: DateTime.now(),
            close: const Value(510.0),
            volume: const Value(20000000.0),
          ),
        ]);

        await db.createPriceAlert(
          symbol: '2330',
          alertType: 'VOLUME_ABOVE',
          targetValue: 25000.0, // 目標 25000 張
        );

        final triggered = await db.checkAlerts({'2330': 510.0}, {'2330': 2.0});

        expect(triggered, isEmpty);
      },
    );

    test('VOLUME_ABOVE doesn\'t trigger with insufficient data', () async {
      // 建立新股票但沒有價格資料
      await db.upsertStocks([
        StockMasterCompanion.insert(
          symbol: '2331',
          name: '測試股票',
          market: 'TWSE',
        ),
      ]);

      await db.createPriceAlert(
        symbol: '2331',
        alertType: 'VOLUME_ABOVE',
        targetValue: 10000.0,
      );

      final triggered = await db.checkAlerts({'2331': 100.0}, {'2331': 2.0});

      expect(triggered, isEmpty);
    });
  });

  group('52-Week Alerts', () {
    setUp(() async {
      // 插入股票主檔
      await db.upsertStocks([
        StockMasterCompanion.insert(
          symbol: '2330',
          name: '台積電',
          market: 'TWSE',
        ),
      ]);

      // 插入 52 週歷史價格（最高 600，最低 380）
      final now = DateTime.now();
      final prices = <DailyPriceCompanion>[];
      for (int i = 0; i < 52; i++) {
        // 模擬波動：380-600 之間
        final week = i;
        final high = 400.0 + (week % 10) * 20.0; // 最高 580
        final low = 380.0 + (week % 10) * 20.0; // 最低 380
        prices.add(
          DailyPriceCompanion.insert(
            symbol: '2330',
            date: now.subtract(Duration(days: 52 * 7 - week * 7)), // 每週一筆
            open: const Value(500.0),
            high: Value(high),
            low: Value(low),
            close: const Value(500.0),
          ),
        );
      }
      await db.insertPrices(prices);
    });

    test('WEEK_52_HIGH triggers when current price >= 52-week high', () async {
      final alertId = await db.createPriceAlert(
        symbol: '2330',
        alertType: 'WEEK_52_HIGH',
        targetValue: 0.0, // 這個值對 WEEK_52_HIGH 不重要
      );

      // 當前價格 590 >= 52 週最高 580
      final triggered = await db.checkAlerts({'2330': 590.0}, {'2330': 2.0});

      expect(triggered.length, 1);
      expect(triggered.first.id, alertId);
    });

    test(
      'WEEK_52_HIGH doesn\'t trigger when current price < 52-week high',
      () async {
        await db.createPriceAlert(
          symbol: '2330',
          alertType: 'WEEK_52_HIGH',
          targetValue: 0.0,
        );

        // 當前價格 570 < 52 週最高 580
        final triggered = await db.checkAlerts({'2330': 570.0}, {'2330': 2.0});

        expect(triggered, isEmpty);
      },
    );

    test('WEEK_52_HIGH doesn\'t trigger with insufficient data', () async {
      // 建立新股票但沒有價格資料
      await db.upsertStocks([
        StockMasterCompanion.insert(
          symbol: '2331',
          name: '測試股票',
          market: 'TWSE',
        ),
      ]);

      await db.createPriceAlert(
        symbol: '2331',
        alertType: 'WEEK_52_HIGH',
        targetValue: 0.0,
      );

      final triggered = await db.checkAlerts({'2331': 100.0}, {'2331': 2.0});

      expect(triggered, isEmpty);
    });

    test('WEEK_52_LOW triggers when current price <= 52-week low', () async {
      final alertId = await db.createPriceAlert(
        symbol: '2330',
        alertType: 'WEEK_52_LOW',
        targetValue: 0.0, // 這個值對 WEEK_52_LOW 不重要
      );

      // 當前價格 375 <= 52 週最低 380
      final triggered = await db.checkAlerts({'2330': 375.0}, {'2330': -2.0});

      expect(triggered.length, 1);
      expect(triggered.first.id, alertId);
    });

    test(
      'WEEK_52_LOW doesn\'t trigger when current price > 52-week low',
      () async {
        await db.createPriceAlert(
          symbol: '2330',
          alertType: 'WEEK_52_LOW',
          targetValue: 0.0,
        );

        // 當前價格 385 > 52 週最低 380
        final triggered = await db.checkAlerts({'2330': 385.0}, {'2330': -1.0});

        expect(triggered, isEmpty);
      },
    );

    test('WEEK_52_LOW doesn\'t trigger with insufficient data', () async {
      // 建立新股票但沒有價格資料
      await db.upsertStocks([
        StockMasterCompanion.insert(
          symbol: '2332',
          name: '測試股票2',
          market: 'TWSE',
        ),
      ]);

      await db.createPriceAlert(
        symbol: '2332',
        alertType: 'WEEK_52_LOW',
        targetValue: 0.0,
      );

      final triggered = await db.checkAlerts({'2332': 100.0}, {'2332': -2.0});

      expect(triggered, isEmpty);
    });
  });
}
