// Integration test: 資料庫完整流程驗證
//
// 驗證從股票主檔寫入 → 價格寫入 → 分析寫入 → 理由寫入 → 查詢
// 的完整資料流程。使用真實 in-memory SQLite 資料庫。
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

  group('Database Flow Integration', () {
    test(
      'full pipeline: stocks → prices → analysis → reasons → query',
      () async {
        // Step 1: 寫入股票主檔
        await db.upsertStocks([
          StockMasterCompanion.insert(
            symbol: '2330',
            name: '台積電',
            market: 'TWSE',
          ),
          StockMasterCompanion.insert(
            symbol: '2317',
            name: '鴻海',
            market: 'TWSE',
          ),
          StockMasterCompanion.insert(
            symbol: '2454',
            name: '聯發科',
            market: 'TWSE',
          ),
        ]);

        // 驗證股票寫入
        final stock = await db.getStock('2330');
        expect(stock, isNotNull);
        expect(stock!.name, '台積電');

        // Step 2: 寫入歷史價格（30 天）
        final baseDate = DateTime(2026, 3, 1);
        for (final symbol in ['2330', '2317', '2454']) {
          final prices = <DailyPriceCompanion>[];
          for (int i = 0; i < 30; i++) {
            prices.add(
              DailyPriceCompanion.insert(
                symbol: symbol,
                date: baseDate.subtract(Duration(days: 30 - i)),
                open: Value(500.0 + i),
                high: Value(510.0 + i),
                low: Value(490.0 + i),
                close: Value(505.0 + i),
                volume: Value(50000.0 + i * 1000),
              ),
            );
          }
          await db.insertPrices(prices);
        }

        // 驗證價格寫入
        final priceHistory = await db.getPriceHistory(
          '2330',
          startDate: baseDate.subtract(const Duration(days: 30)),
          endDate: baseDate,
        );
        expect(priceHistory.length, 30);

        // Step 3: 寫入分析結果
        final analysisDate = baseDate;
        for (final entry in [
          ('2330', 85.0, 'UP'),
          ('2317', 72.0, 'UP'),
          ('2454', 60.0, 'DOWN'),
        ]) {
          await db.insertAnalysis(
            DailyAnalysisCompanion.insert(
              symbol: entry.$1,
              date: analysisDate,
              trendState: entry.$3,
              scoreShort: Value(entry.$2),
              scoreLong: Value(entry.$2),
            ),
          );
        }

        // 驗證分析寫入
        final analysis = await db.getAnalysis('2330', analysisDate);
        expect(analysis, isNotNull);
        expect(analysis!.scoreShort, 85.0);
        expect(analysis.trendState, 'UP');

        // Step 4: 寫入分析原因
        await db.insertReasons([
          DailyReasonCompanion.insert(
            symbol: '2330',
            date: analysisDate,
            rank: 1,
            reasonType: 'GOLDEN_CROSS',
            evidenceJson: '{"period": 20}',
            ruleScoreShort: const Value(25.0),
            ruleScoreLong: const Value(25.0),
          ),
          DailyReasonCompanion.insert(
            symbol: '2330',
            date: analysisDate,
            rank: 2,
            reasonType: 'VOLUME_SPIKE',
            evidenceJson: '{"ratio": 4.5}',
            ruleScoreShort: const Value(22.0),
            ruleScoreLong: const Value(22.0),
          ),
        ]);

        // Step 5: 查詢股票的完整資料鏈
        final recStock = await db.getStock('2330');
        expect(recStock!.name, '台積電');

        final recAnalysis = await db.getAnalysis('2330', analysisDate);
        expect(recAnalysis!.trendState, 'UP');

        final recReasons = await db.getReasons('2330', analysisDate);
        expect(recReasons.length, 2);
        expect(recReasons.first.reasonType, 'GOLDEN_CROSS');
      },
    );

    test('watchlist CRUD operations', () async {
      // 寫入股票主檔
      await db.upsertStocks([
        StockMasterCompanion.insert(
          symbol: '2330',
          name: '台積電',
          market: 'TWSE',
        ),
        StockMasterCompanion.insert(symbol: '2317', name: '鴻海', market: 'TWSE'),
      ]);

      // 加入自選
      await db.addToWatchlist('2330');
      await db.addToWatchlist('2317');

      // 驗證自選清單
      var watchlist = await db.getWatchlist();
      expect(watchlist.length, 2);

      // 移除自選
      await db.removeFromWatchlist('2317');
      watchlist = await db.getWatchlist();
      expect(watchlist.length, 1);
      expect(watchlist.first.symbol, '2330');

      // 檢查是否在自選
      expect(await db.isInWatchlist('2330'), isTrue);
      expect(await db.isInWatchlist('2317'), isFalse);
    });

    test('price alert lifecycle: create → check → trigger', () async {
      // 寫入股票主檔
      await db.upsertStocks([
        StockMasterCompanion.insert(
          symbol: '2330',
          name: '台積電',
          market: 'TWSE',
        ),
      ]);

      // 建立價格警示（上方突破 600）
      final alertId = await db.createPriceAlert(
        symbol: '2330',
        alertType: 'ABOVE',
        targetValue: 600.0,
      );
      expect(alertId, greaterThan(0));

      // 檢查警示 — 價格低於目標，不應觸發
      var triggered = await db.checkAlerts({'2330': 590.0}, {'2330': -1.0});
      expect(triggered, isEmpty);

      // 價格突破目標，應觸發
      triggered = await db.checkAlerts({'2330': 610.0}, {'2330': 2.0});
      expect(triggered.length, 1);
      expect(triggered.first.id, alertId);

      // 標記為已觸發後，不再觸發
      await db.triggerAlert(alertId);
      triggered = await db.checkAlerts({'2330': 620.0}, {'2330': 3.0});
      expect(triggered, isEmpty);
    });

    test('update run tracking', () async {
      // 記錄更新開始
      final runId = await db.createUpdateRun(DateTime.now(), 'running');
      expect(runId, greaterThan(0));

      // 查詢最新執行記錄
      var latestRun = await db.getLatestUpdateRun();
      expect(latestRun, isNotNull);
      expect(latestRun!.id, runId);
      expect(latestRun.finishedAt, isNull);

      // 標記更新完成
      await db.finishUpdateRun(runId, 'completed');

      // 驗證完成記錄
      latestRun = await db.getLatestUpdateRun();
      expect(latestRun!.finishedAt, isNotNull);
      expect(latestRun.status, 'completed');
    });
  });
}
