import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/core/utils/device_time.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting();
  });

  tearDown(() async {
    await db.close();
  });

  group('RSI Alerts', () {
    setUp(() async {
      // 插入股票主檔
      await db.upsertStocks([
        StockMasterCompanion.insert(
          symbol: '2330',
          name: '台積電',
          market: 'TWSE',
        ),
      ]);

      // 插入 30 天歷史價格（模擬 RSI 從低到高）
      final now = DeviceTime.now();
      final prices = <DailyPriceCompanion>[];
      for (int i = 0; i < 30; i++) {
        final closePrice = 500.0 + i * 2.0; // 逐漸上漲，RSI 會偏高
        prices.add(
          DailyPriceCompanion.insert(
            symbol: '2330',
            date: now.subtract(Duration(days: 30 - i)),
            open: Value(closePrice - 1.0),
            high: Value(closePrice + 1.0),
            low: Value(closePrice - 1.0),
            close: Value(closePrice),
          ),
        );
      }
      await db.insertPrices(prices);
    });

    test('RSI_OVERBOUGHT triggers when RSI >= target', () async {
      final alertId = await db.createPriceAlert(
        symbol: '2330',
        alertType: 'RSI_OVERBOUGHT',
        targetValue: 70.0, // RSI 超過 70 觸發
      );

      final triggered = await db.checkAlerts({'2330': 560.0}, {'2330': 2.0});

      expect(triggered.length, 1);
      expect(triggered.first.id, alertId);
    });

    test('RSI_OVERBOUGHT doesn\'t trigger when RSI < target', () async {
      // 插入股票主檔（新股票）
      await db.upsertStocks([
        StockMasterCompanion.insert(
          symbol: '2331',
          name: '測試股票',
          market: 'TWSE',
        ),
      ]);

      // 插入橫盤資料（RSI 會在 50 左右）
      final now = DeviceTime.now();
      final prices = <DailyPriceCompanion>[];
      for (int i = 0; i < 30; i++) {
        prices.add(
          DailyPriceCompanion.insert(
            symbol: '2331',
            date: now.subtract(Duration(days: 30 - i)),
            close: const Value(500.0), // 橫盤
          ),
        );
      }
      await db.insertPrices(prices);

      await db.createPriceAlert(
        symbol: '2331',
        alertType: 'RSI_OVERBOUGHT',
        targetValue: 70.0,
      );

      final triggered = await db.checkAlerts({'2331': 500.0}, {'2331': 0.0});

      expect(triggered, isEmpty);
    });

    test('RSI_OVERBOUGHT doesn\'t trigger with insufficient data', () async {
      await db.upsertStocks([
        StockMasterCompanion.insert(
          symbol: '2332',
          name: '測試股票2',
          market: 'TWSE',
        ),
      ]);

      await db.createPriceAlert(
        symbol: '2332',
        alertType: 'RSI_OVERBOUGHT',
        targetValue: 70.0,
      );

      final triggered = await db.checkAlerts({'2332': 500.0}, {'2332': 2.0});

      expect(triggered, isEmpty);
    });

    test('RSI_OVERSOLD triggers when RSI <= target', () async {
      // 插入股票主檔（新股票）
      await db.upsertStocks([
        StockMasterCompanion.insert(
          symbol: '2333',
          name: '測試股票3',
          market: 'TWSE',
        ),
      ]);

      // 插入下跌資料（RSI 會偏低）
      final now = DeviceTime.now();
      final prices = <DailyPriceCompanion>[];
      for (int i = 0; i < 30; i++) {
        final closePrice = 500.0 - i * 2.0; // 逐漸下跌，RSI 會偏低
        prices.add(
          DailyPriceCompanion.insert(
            symbol: '2333',
            date: now.subtract(Duration(days: 30 - i)),
            open: Value(closePrice + 1.0),
            high: Value(closePrice + 1.0),
            low: Value(closePrice - 1.0),
            close: Value(closePrice),
          ),
        );
      }
      await db.insertPrices(prices);

      final alertId = await db.createPriceAlert(
        symbol: '2333',
        alertType: 'RSI_OVERSOLD',
        targetValue: 30.0, // RSI 低於 30 觸發
      );

      final triggered = await db.checkAlerts({'2333': 442.0}, {'2333': -2.0});

      expect(triggered.length, 1);
      expect(triggered.first.id, alertId);
    });

    test('RSI_OVERSOLD doesn\'t trigger when RSI > target', () async {
      await db.createPriceAlert(
        symbol: '2330', // 使用 setUp 中的上漲股票，RSI 偏高
        alertType: 'RSI_OVERSOLD',
        targetValue: 30.0,
      );

      final triggered = await db.checkAlerts({'2330': 560.0}, {'2330': 2.0});

      expect(triggered, isEmpty);
    });

    test('RSI_OVERSOLD doesn\'t trigger with insufficient data', () async {
      await db.upsertStocks([
        StockMasterCompanion.insert(
          symbol: '2334',
          name: '測試股票4',
          market: 'TWSE',
        ),
      ]);

      await db.createPriceAlert(
        symbol: '2334',
        alertType: 'RSI_OVERSOLD',
        targetValue: 30.0,
      );

      final triggered = await db.checkAlerts({'2334': 500.0}, {'2334': -2.0});

      expect(triggered, isEmpty);
    });
  });

  group('KD Alerts', () {
    setUp(() async {
      // 插入股票主檔
      await db.upsertStocks([
        StockMasterCompanion.insert(
          symbol: '2330',
          name: '台積電',
          market: 'TWSE',
        ),
      ]);

      // 插入 30 天歷史價格（模擬 KD 黃金交叉在最後幾天發生）
      final now = DeviceTime.now();
      final prices = <DailyPriceCompanion>[];
      for (int i = 0; i < 30; i++) {
        final day = i;
        double closePrice;
        if (day < 26) {
          // 前 26 天橫盤震盪（製造 K/D 接近且 K 略 < D 的狀態）
          closePrice = 500.0 + (day % 3 - 1) * 0.2;
        } else if (day == 26 || day == 27) {
          // Day 26-27 微幅下跌（保持 K < D）
          closePrice = 499.5 - (day - 26) * 0.1;
        } else {
          // Day 28-29 快速上漲（觸發黃金交叉）
          closePrice = 499.3 + (day - 27) * 2.5;
        }
        prices.add(
          DailyPriceCompanion.insert(
            symbol: '2330',
            date: now.subtract(Duration(days: 30 - i)),
            open: Value(closePrice - 0.3),
            high: Value(closePrice + 0.5),
            low: Value(closePrice - 0.5),
            close: Value(closePrice),
          ),
        );
      }
      await db.insertPrices(prices);
    });

    test(
      'KD_GOLDEN_CROSS triggers when K crosses above D in low zone',
      () async {
        final alertId = await db.createPriceAlert(
          symbol: '2330',
          alertType: 'KD_GOLDEN_CROSS',
          targetValue: 0.0, // 這個值對 KD_GOLDEN_CROSS 不重要
        );

        final triggered = await db.checkAlerts({'2330': 500.0}, {'2330': 1.0});

        expect(triggered.length, 1);
        expect(triggered.first.id, alertId);
      },
    );

    test('KD_GOLDEN_CROSS doesn\'t trigger when K is in high zone', () async {
      // 插入新股票（高檔震盪）
      await db.upsertStocks([
        StockMasterCompanion.insert(
          symbol: '2331',
          name: '測試股票',
          market: 'TWSE',
        ),
      ]);

      final now = DeviceTime.now();
      final prices = <DailyPriceCompanion>[];
      for (int i = 0; i < 20; i++) {
        prices.add(
          DailyPriceCompanion.insert(
            symbol: '2331',
            date: now.subtract(Duration(days: 20 - i)),
            open: const Value(595.0),
            high: const Value(600.0),
            low: const Value(590.0),
            close: const Value(598.0), // 高檔震盪
          ),
        );
      }
      await db.insertPrices(prices);

      await db.createPriceAlert(
        symbol: '2331',
        alertType: 'KD_GOLDEN_CROSS',
        targetValue: 0.0,
      );

      final triggered = await db.checkAlerts({'2331': 598.0}, {'2331': 0.0});

      expect(triggered, isEmpty);
    });

    test('KD_GOLDEN_CROSS doesn\'t trigger with insufficient data', () async {
      await db.upsertStocks([
        StockMasterCompanion.insert(
          symbol: '2332',
          name: '測試股票2',
          market: 'TWSE',
        ),
      ]);

      await db.createPriceAlert(
        symbol: '2332',
        alertType: 'KD_GOLDEN_CROSS',
        targetValue: 0.0,
      );

      final triggered = await db.checkAlerts({'2332': 500.0}, {'2332': 1.0});

      expect(triggered, isEmpty);
    });

    test(
      'KD_DEATH_CROSS triggers when K crosses below D in high zone',
      () async {
        // 插入新股票（高檔反轉）
        await db.upsertStocks([
          StockMasterCompanion.insert(
            symbol: '2333',
            name: '測試股票3',
            market: 'TWSE',
          ),
        ]);

        final now = DeviceTime.now();
        final prices = <DailyPriceCompanion>[];
        for (int i = 0; i < 30; i++) {
          final day = i;
          double closePrice;
          if (day < 26) {
            // 前 26 天橫盤震盪（製造 K/D 接近且 K 略 > D 的狀態）
            closePrice = 500.0 + (day % 3 - 1) * 0.2;
          } else if (day == 26 || day == 27) {
            // Day 26-27 微幅上漲（保持 K > D）
            closePrice = 500.5 + (day - 26) * 0.1;
          } else {
            // Day 28-29 快速下跌（觸發死亡交叉）
            closePrice = 500.7 - (day - 27) * 2.5;
          }
          prices.add(
            DailyPriceCompanion.insert(
              symbol: '2333',
              date: now.subtract(Duration(days: 30 - i)),
              open: Value(closePrice + 0.3),
              high: Value(closePrice + 0.5),
              low: Value(closePrice - 0.5),
              close: Value(closePrice),
            ),
          );
        }
        await db.insertPrices(prices);

        final alertId = await db.createPriceAlert(
          symbol: '2333',
          alertType: 'KD_DEATH_CROSS',
          targetValue: 0.0, // 這個值對 KD_DEATH_CROSS 不重要
        );

        final triggered = await db.checkAlerts({'2333': 500.0}, {'2333': -1.0});

        expect(triggered.length, 1);
        expect(triggered.first.id, alertId);
      },
    );

    test('KD_DEATH_CROSS doesn\'t trigger when K is in low zone', () async {
      // 使用 setUp 中的低檔反彈股票
      await db.createPriceAlert(
        symbol: '2330',
        alertType: 'KD_DEATH_CROSS',
        targetValue: 0.0,
      );

      final triggered = await db.checkAlerts({'2330': 500.0}, {'2330': 1.0});

      expect(triggered, isEmpty);
    });

    test('KD_DEATH_CROSS doesn\'t trigger with insufficient data', () async {
      await db.upsertStocks([
        StockMasterCompanion.insert(
          symbol: '2334',
          name: '測試股票4',
          market: 'TWSE',
        ),
      ]);

      await db.createPriceAlert(
        symbol: '2334',
        alertType: 'KD_DEATH_CROSS',
        targetValue: 0.0,
      );

      final triggered = await db.checkAlerts({'2334': 500.0}, {'2334': -1.0});

      expect(triggered, isEmpty);
    });
  });

  group('MA Cross Alerts', () {
    setUp(() async {
      // 插入股票主檔
      await db.upsertStocks([
        StockMasterCompanion.insert(
          symbol: '2330',
          name: '台積電',
          market: 'TWSE',
        ),
      ]);

      // 插入 30 天歷史價格（模擬均線交叉）
      final now = DeviceTime.now();
      final prices = <DailyPriceCompanion>[];
      for (int i = 0; i < 30; i++) {
        final day = i;
        double closePrice;
        if (day < 26) {
          // 前 26 天橫盤於均線下方（價格 = 495）
          closePrice = 495.0 + (day % 2) * 0.5;
        } else if (day == 26 || day == 27) {
          // Day 26-27 微幅下跌（保持在均線下方）
          closePrice = 495.0 - (day - 26) * 0.2;
        } else {
          // Day 28-29 快速上漲突破 20 日均線
          closePrice = 494.6 + (day - 27) * 3.0;
        }
        prices.add(
          DailyPriceCompanion.insert(
            symbol: '2330',
            date: now.subtract(Duration(days: 30 - i)),
            open: Value(closePrice - 0.5),
            high: Value(closePrice + 0.5),
            low: Value(closePrice - 0.5),
            close: Value(closePrice),
          ),
        );
      }
      await db.insertPrices(prices);
    });

    test('CROSS_ABOVE_MA triggers when price crosses above MA', () async {
      final alertId = await db.createPriceAlert(
        symbol: '2330',
        alertType: 'CROSS_ABOVE_MA',
        targetValue: 20.0, // 20 日均線
      );

      final triggered = await db.checkAlerts({'2330': 500.0}, {'2330': 2.0});

      expect(triggered.length, 1);
      expect(triggered.first.id, alertId);
    });

    test('CROSS_ABOVE_MA doesn\'t trigger when price stays below MA', () async {
      // 插入新股票，價格一直低於均線
      await db.upsertStocks([
        StockMasterCompanion.insert(
          symbol: '2335',
          name: '測試股票5',
          market: 'TWSE',
        ),
      ]);

      final now = DeviceTime.now();
      final prices = <DailyPriceCompanion>[];
      for (int i = 0; i < 30; i++) {
        prices.add(
          DailyPriceCompanion.insert(
            symbol: '2335',
            date: now.subtract(Duration(days: 30 - i)),
            open: const Value(490.0),
            high: const Value(492.0),
            low: const Value(488.0),
            close: const Value(490.0), // 一直橫盤於 490
          ),
        );
      }
      await db.insertPrices(prices);

      await db.createPriceAlert(
        symbol: '2335',
        alertType: 'CROSS_ABOVE_MA',
        targetValue: 20.0, // 20 日均線會在 490 附近
      );

      final triggered = await db.checkAlerts(
        {'2335': 490.0}, // 價格沒有突破均線
        {'2335': 0.0},
      );

      expect(triggered, isEmpty);
    });

    test('CROSS_ABOVE_MA doesn\'t trigger with insufficient data', () async {
      await db.upsertStocks([
        StockMasterCompanion.insert(
          symbol: '2331',
          name: '測試股票',
          market: 'TWSE',
        ),
      ]);

      await db.createPriceAlert(
        symbol: '2331',
        alertType: 'CROSS_ABOVE_MA',
        targetValue: 20.0,
      );

      final triggered = await db.checkAlerts({'2331': 500.0}, {'2331': 2.0});

      expect(triggered, isEmpty);
    });

    test('CROSS_BELOW_MA triggers when price crosses below MA', () async {
      // 插入新股票（高檔跌破均線）
      await db.upsertStocks([
        StockMasterCompanion.insert(
          symbol: '2332',
          name: '測試股票2',
          market: 'TWSE',
        ),
      ]);

      final now = DeviceTime.now();
      final prices = <DailyPriceCompanion>[];
      // 先 20 天橫盤於 510（建立均線基準）
      for (int i = 0; i < 20; i++) {
        prices.add(
          DailyPriceCompanion.insert(
            symbol: '2332',
            date: now.subtract(Duration(days: 29 - i)),
            open: const Value(509.5),
            high: const Value(511.0),
            low: const Value(509.0),
            close: const Value(510.0),
          ),
        );
      }
      // Day 20-27 微幅上漲但維持在均線上方
      for (int i = 20; i < 28; i++) {
        prices.add(
          DailyPriceCompanion.insert(
            symbol: '2332',
            date: now.subtract(Duration(days: 29 - i)),
            open: Value(510.5 + (i - 20) * 0.1),
            high: Value(511.0 + (i - 20) * 0.1),
            low: Value(510.0 + (i - 20) * 0.1),
            close: Value(510.5 + (i - 20) * 0.1),
          ),
        );
      }
      // Day 28: 微幅上漲，保持在均線上方
      prices.add(
        DailyPriceCompanion.insert(
          symbol: '2332',
          date: now.subtract(const Duration(days: 1)),
          open: const Value(511.3),
          high: const Value(512.0),
          low: const Value(511.0),
          close: const Value(511.5), // 在均線上方
        ),
      );
      // Day 29: 快速下跌跌破 20 日均線
      prices.add(
        DailyPriceCompanion.insert(
          symbol: '2332',
          date: now,
          open: const Value(511.0),
          high: const Value(511.5),
          low: const Value(506.0),
          close: const Value(507.0), // 快速跌破均線
        ),
      );
      await db.insertPrices(prices);

      final alertId = await db.createPriceAlert(
        symbol: '2332',
        alertType: 'CROSS_BELOW_MA',
        targetValue: 20.0, // 20 日均線
      );

      final triggered = await db.checkAlerts({'2332': 500.0}, {'2332': -2.0});

      expect(triggered.length, 1);
      expect(triggered.first.id, alertId);
    });

    test('CROSS_BELOW_MA doesn\'t trigger when price stays above MA', () async {
      await db.createPriceAlert(
        symbol: '2330', // 使用 setUp 中的低檔股票
        alertType: 'CROSS_BELOW_MA',
        targetValue: 5.0, // 5 日均線（價格會高於此均線）
      );

      final triggered = await db.checkAlerts({'2330': 500.0}, {'2330': 2.0});

      expect(triggered, isEmpty);
    });

    test('CROSS_BELOW_MA doesn\'t trigger with insufficient data', () async {
      await db.upsertStocks([
        StockMasterCompanion.insert(
          symbol: '2333',
          name: '測試股票3',
          market: 'TWSE',
        ),
      ]);

      await db.createPriceAlert(
        symbol: '2333',
        alertType: 'CROSS_BELOW_MA',
        targetValue: 20.0,
      );

      final triggered = await db.checkAlerts({'2333': 500.0}, {'2333': -2.0});

      expect(triggered, isEmpty);
    });
  });
}
