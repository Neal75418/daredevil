import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/domain/services/chip_anomaly_service.dart';

void main() {
  late AppDatabase db;
  late ChipAnomalyService service;

  final today = DateTime.utc(2025, 6, 15);

  setUp(() {
    db = AppDatabase.forTesting();
    service = ChipAnomalyService(database: db);
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

  group('ChipAnomalyService', () {
    setUp(() async {
      await insertTestStocks();
    });

    // ─────────────────────────────────────────────────────────────────────────
    // 高質押率
    // ─────────────────────────────────────────────────────────────────────────

    group('高質押率偵測（變動觸發：跨門檻或 Δ>=5pp 才計入，防警示疲勞）', () {
      test('跨門檻（前次 < 70、最新 >= 70）應被偵測', () async {
        await db.insertInsiderHoldingData([
          InsiderHoldingCompanion.insert(
            symbol: '2330',
            date: today.subtract(const Duration(days: 30)),
            pledgeRatio: const Value(65.0), // 前次 < 70
          ),
          InsiderHoldingCompanion.insert(
            symbol: '2330',
            date: today,
            pledgeRatio: const Value(75.5), // 最新 >= 70
          ),
        ]);

        final result = (await service.detectAnomaliesByMarket(today)).byMarket;

        expect(
          result['TWSE']!.any(
            (a) => a.type == ChipAnomalyType.highPledge && a.symbol == '2330',
          ),
          isTrue,
        );
      });

      test('pledge_ratio < 70 不應被偵測（即使有前次資料）', () async {
        await db.insertInsiderHoldingData([
          InsiderHoldingCompanion.insert(
            symbol: '2330',
            date: today.subtract(const Duration(days: 30)),
            pledgeRatio: const Value(20.0),
          ),
          InsiderHoldingCompanion.insert(
            symbol: '2330',
            date: today,
            pledgeRatio: const Value(45.0),
          ),
        ]);

        final result = (await service.detectAnomaliesByMarket(today)).byMarket;

        expect(
          result['TWSE']!.any((a) => a.type == ChipAnomalyType.highPledge),
          isFalse,
        );
      });

      test('keyValue 格式化為最新質押率的百分比字串', () async {
        await db.insertInsiderHoldingData([
          InsiderHoldingCompanion.insert(
            symbol: '2330',
            date: today.subtract(const Duration(days: 30)),
            pledgeRatio: const Value(60.0),
          ),
          InsiderHoldingCompanion.insert(
            symbol: '2330',
            date: today,
            pledgeRatio: const Value(75.5),
          ),
        ]);

        final result = (await service.detectAnomaliesByMarket(today)).byMarket;
        final anomaly = result['TWSE']!.firstWhere(
          (a) => a.type == ChipAnomalyType.highPledge,
        );

        expect(anomaly.keyValue, '75.5%');
        expect(anomaly.severity, ChipSeverity.high);
      });

      test('使用最新一筆資料判定門檻（MAX(date) 為 latest，跨門檻情境）', () async {
        // 舊資料低於門檻，新資料超過門檻
        await db.insertInsiderHoldingData([
          InsiderHoldingCompanion.insert(
            symbol: '2330',
            date: today.subtract(const Duration(days: 30)),
            pledgeRatio: const Value(30.0),
          ),
          InsiderHoldingCompanion.insert(
            symbol: '2330',
            date: today,
            pledgeRatio: const Value(80.0),
          ),
        ]);

        final result = (await service.detectAnomaliesByMarket(today)).byMarket;

        expect(
          result['TWSE']!.any((a) => a.type == ChipAnomalyType.highPledge),
          isTrue,
        );
      });

      test('首次快照（無前次資料）即使 >= 70 也不應偵測（防首次同步洗版）', () async {
        await db.insertInsiderHoldingData([
          InsiderHoldingCompanion.insert(
            symbol: '2330',
            date: today,
            pledgeRatio: const Value(75.5),
          ),
        ]);

        final result = (await service.detectAnomaliesByMarket(today)).byMarket;

        expect(
          result['TWSE']!.any((a) => a.type == ChipAnomalyType.highPledge),
          isFalse,
        );
      });

      test('持續高於門檻但變動 < 5pp 不應偵測（警示疲勞防制）', () async {
        await db.insertInsiderHoldingData([
          InsiderHoldingCompanion.insert(
            symbol: '2330',
            date: today.subtract(const Duration(days: 30)),
            pledgeRatio: const Value(75.0), // 前次已 >= 70
          ),
          InsiderHoldingCompanion.insert(
            symbol: '2330',
            date: today,
            pledgeRatio: const Value(76.5), // Δ = 1.5pp < 5pp
          ),
        ]);

        final result = (await service.detectAnomaliesByMarket(today)).byMarket;

        expect(
          result['TWSE']!.any((a) => a.type == ChipAnomalyType.highPledge),
          isFalse,
        );
      });

      test('持續高於門檻但 Δ >= 5pp 應偵測（即使早已跨過門檻）', () async {
        await db.insertInsiderHoldingData([
          InsiderHoldingCompanion.insert(
            symbol: '2330',
            date: today.subtract(const Duration(days: 30)),
            pledgeRatio: const Value(72.0), // 前次已 >= 70
          ),
          InsiderHoldingCompanion.insert(
            symbol: '2330',
            date: today,
            pledgeRatio: const Value(78.0), // Δ = 6pp >= 5pp
          ),
        ]);

        final result = (await service.detectAnomaliesByMarket(today)).byMarket;

        expect(
          result['TWSE']!.any((a) => a.type == ChipAnomalyType.highPledge),
          isTrue,
        );
      });

      test('Δ 恰為 5pp（inclusive）應偵測', () async {
        await db.insertInsiderHoldingData([
          InsiderHoldingCompanion.insert(
            symbol: '2330',
            date: today.subtract(const Duration(days: 30)),
            pledgeRatio: const Value(70.0),
          ),
          InsiderHoldingCompanion.insert(
            symbol: '2330',
            date: today,
            pledgeRatio: const Value(75.0), // Δ = 5.0pp
          ),
        ]);

        final result = (await service.detectAnomaliesByMarket(today)).byMarket;

        expect(
          result['TWSE']!.any((a) => a.type == ChipAnomalyType.highPledge),
          isTrue,
        );
      });

      test('前次略低於門檻、最新略高於門檻（小幅跨越）仍應偵測', () async {
        await db.insertInsiderHoldingData([
          InsiderHoldingCompanion.insert(
            symbol: '2330',
            date: today.subtract(const Duration(days: 30)),
            pledgeRatio: const Value(69.9),
          ),
          InsiderHoldingCompanion.insert(
            symbol: '2330',
            date: today,
            pledgeRatio: const Value(70.1), // Δ 僅 0.2pp，但屬跨門檻
          ),
        ]);

        final result = (await service.detectAnomaliesByMarket(today)).byMarket;

        expect(
          result['TWSE']!.any((a) => a.type == ChipAnomalyType.highPledge),
          isTrue,
        );
      });

      test('質押率下降但仍 >= 70 不應偵測（非跨門檻也非 Δ>=+5pp）', () async {
        await db.insertInsiderHoldingData([
          InsiderHoldingCompanion.insert(
            symbol: '2330',
            date: today.subtract(const Duration(days: 30)),
            pledgeRatio: const Value(90.0),
          ),
          InsiderHoldingCompanion.insert(
            symbol: '2330',
            date: today,
            pledgeRatio: const Value(85.0),
          ),
        ]);

        final result = (await service.detectAnomaliesByMarket(today)).byMarket;

        expect(
          result['TWSE']!.any((a) => a.type == ChipAnomalyType.highPledge),
          isFalse,
        );
      });
    });

    // ─────────────────────────────────────────────────────────────────────────
    // 內部人轉讓
    // ─────────────────────────────────────────────────────────────────────────

    group('內部人轉讓偵測', () {
      test('近 30 天內轉讓應被偵測', () async {
        await db.insertInsiderTransfers([
          InsiderTransferCompanion.insert(
            symbol: '2330',
            reportDate: today.subtract(const Duration(days: 10)),
            identity: '董事',
            name: '測試人',
            transferMethod: '一般',
            transferShares: 50000,
            currentHolding: 1000000,
          ),
        ]);

        final result = (await service.detectAnomaliesByMarket(today)).byMarket;

        expect(
          result['TWSE']!.any(
            (a) =>
                a.type == ChipAnomalyType.insiderTransfer && a.symbol == '2330',
          ),
          isTrue,
        );
      });

      test('超過 30 天前的轉讓不應被偵測', () async {
        await db.insertInsiderTransfers([
          InsiderTransferCompanion.insert(
            symbol: '2330',
            reportDate: today.subtract(const Duration(days: 31)),
            identity: '董事',
            name: '測試人',
            transferMethod: '一般',
            transferShares: 50000,
            currentHolding: 1000000,
          ),
        ]);

        final result = (await service.detectAnomaliesByMarket(today)).byMarket;

        expect(
          result['TWSE']!.any((a) => a.type == ChipAnomalyType.insiderTransfer),
          isFalse,
        );
      });

      test('transferShares = 0 回傳 kZeroInsiderTransfer（"0張"）', () async {
        await db.insertInsiderTransfers([
          InsiderTransferCompanion.insert(
            symbol: '2330',
            reportDate: today,
            identity: '董事',
            name: '測試人',
            transferMethod: '一般',
            transferShares: 0,
            currentHolding: 1000000,
          ),
        ]);

        final result = (await service.detectAnomaliesByMarket(today)).byMarket;
        final anomaly = result['TWSE']!.firstWhere(
          (a) => a.type == ChipAnomalyType.insiderTransfer,
        );

        expect(anomaly.keyValue, kZeroInsiderTransfer);
      });

      test('transferShares 1–999 顯示 "<1張"（不四捨五入為零）', () async {
        await db.insertInsiderTransfers([
          InsiderTransferCompanion.insert(
            symbol: '2330',
            reportDate: today,
            identity: '董事',
            name: '測試人',
            transferMethod: '一般',
            transferShares: 500,
            currentHolding: 1000000,
          ),
        ]);

        final result = (await service.detectAnomaliesByMarket(today)).byMarket;
        final anomaly = result['TWSE']!.firstWhere(
          (a) => a.type == ChipAnomalyType.insiderTransfer,
        );

        expect(anomaly.keyValue, '<1張');
      });

      test('transferShares >= 1000 以張數顯示（股 / 1000）', () async {
        await db.insertInsiderTransfers([
          InsiderTransferCompanion.insert(
            symbol: '2330',
            reportDate: today,
            identity: '董事',
            name: '測試人',
            transferMethod: '一般',
            transferShares: 5000, // 5 張
            currentHolding: 1000000,
          ),
        ]);

        final result = (await service.detectAnomaliesByMarket(today)).byMarket;
        final anomaly = result['TWSE']!.firstWhere(
          (a) => a.type == ChipAnomalyType.insiderTransfer,
        );

        expect(anomaly.keyValue, '5張');
      });
    });

    // ─────────────────────────────────────────────────────────────────────────
    // 外資逼近上限
    // ─────────────────────────────────────────────────────────────────────────

    group('外資逼近上限偵測', () {
      test('持股比 >= 上限 90% 應被偵測', () async {
        await db.insertShareholdingData([
          ShareholdingCompanion.insert(
            symbol: '2330',
            date: today,
            foreignSharesRatio: const Value(72.0), // 72/80 = 90%
            foreignUpperLimitRatio: const Value(80.0),
          ),
        ]);

        final result = (await service.detectAnomaliesByMarket(today)).byMarket;

        expect(
          result['TWSE']!.any(
            (a) =>
                a.type == ChipAnomalyType.foreignNearLimit &&
                a.symbol == '2330',
          ),
          isTrue,
        );
      });

      test('持股比 < 上限 90% 不應被偵測', () async {
        await db.insertShareholdingData([
          ShareholdingCompanion.insert(
            symbol: '2330',
            date: today,
            foreignSharesRatio: const Value(60.0), // 60/80 = 75%
            foreignUpperLimitRatio: const Value(80.0),
          ),
        ]);

        final result = (await service.detectAnomaliesByMarket(today)).byMarket;

        expect(
          result['TWSE']!.any(
            (a) => a.type == ChipAnomalyType.foreignNearLimit,
          ),
          isFalse,
        );
      });

      test('keyValue 顯示持股佔上限比例（百分比）', () async {
        await db.insertShareholdingData([
          ShareholdingCompanion.insert(
            symbol: '2330',
            date: today,
            foreignSharesRatio: const Value(76.0), // 76/80 = 95.0%
            foreignUpperLimitRatio: const Value(80.0),
          ),
        ]);

        final result = (await service.detectAnomaliesByMarket(today)).byMarket;
        final anomaly = result['TWSE']!.firstWhere(
          (a) => a.type == ChipAnomalyType.foreignNearLimit,
        );

        expect(anomaly.keyValue, '95.0%');
      });
    });

    // ─────────────────────────────────────────────────────────────────────────
    // 融券暴增
    // ─────────────────────────────────────────────────────────────────────────

    group('融券暴增偵測', () {
      /// 插入 5 天歷史 + 當日融券資料
      Future<void> insertShortSurgeData({
        required double todayShortSell,
        double historyShortSell = 100.0,
      }) async {
        final historyDays = List.generate(
          5,
          (i) => today.subtract(Duration(days: i + 1)),
        );
        await db.insertMarginTradingData([
          for (final d in historyDays)
            MarginTradingCompanion.insert(
              symbol: '2330',
              date: d,
              shortSell: Value(historyShortSell),
            ),
          MarginTradingCompanion.insert(
            symbol: '2330',
            date: today,
            shortSell: Value(todayShortSell),
          ),
        ]);
      }

      test('當日融券 > 5 日均量 × 3 應被偵測', () async {
        // avg5d = 100，today = 400 > 100 × 3 = 300 ✓
        await insertShortSurgeData(todayShortSell: 400.0);

        final result = (await service.detectAnomaliesByMarket(today)).byMarket;

        expect(
          result['TWSE']!.any(
            (a) => a.type == ChipAnomalyType.shortSurge && a.symbol == '2330',
          ),
          isTrue,
        );
      });

      test('當日融券 <= 5 日均量 × 3 不應被偵測', () async {
        // avg5d = 100，today = 250 <= 100 × 3 = 300 ✗
        await insertShortSurgeData(todayShortSell: 250.0);

        final result = (await service.detectAnomaliesByMarket(today)).byMarket;

        expect(
          result['TWSE']!.any((a) => a.type == ChipAnomalyType.shortSurge),
          isFalse,
        );
      });

      test('keyValue 格式為「N.N倍」', () async {
        // avg5d = 100，today = 400，ratio = 4.0
        await insertShortSurgeData(todayShortSell: 400.0);

        final result = (await service.detectAnomaliesByMarket(today)).byMarket;
        final anomaly = result['TWSE']!.firstWhere(
          (a) => a.type == ChipAnomalyType.shortSurge,
        );

        expect(anomaly.keyValue, '4.0倍');
      });

      test('近零基期高倍率被絕對量下限濾除', () async {
        // avg5d = 0.333 張（< 均量下限 10），today = 229 張
        // 倍率 687 倍但基期過低 → 應被濾除（模擬 3528 安馳案例）
        await insertShortSurgeData(
          todayShortSell: 229.0,
          historyShortSell: 0.333,
        );

        final result = (await service.detectAnomaliesByMarket(today)).byMarket;

        expect(
          result['TWSE']!.any((a) => a.type == ChipAnomalyType.shortSurge),
          isFalse,
          reason: '均量基期 < 10 張應被下限濾除，避免假性高倍率',
        );
      });

      test('當日量低於下限被濾除', () async {
        // avg5d = 1 張、today = 40 張（< 當日下限 50），倍率 40 倍
        // 雖達倍率但當日絕對量過低 → 應被濾除
        await insertShortSurgeData(todayShortSell: 40.0, historyShortSell: 1.0);

        final result = (await service.detectAnomaliesByMarket(today)).byMarket;

        expect(
          result['TWSE']!.any((a) => a.type == ChipAnomalyType.shortSurge),
          isFalse,
          reason: '當日量 < 50 張應被下限濾除',
        );
      });

      test('真實高基期暴增仍應偵測（和桐案例）', () async {
        // avg5d = 87.33 張（≥ 均量下限 10）、today = 2833 張（≥ 當日下限 50）
        // 倍率約 32 倍 → 真實暴增應正常回報
        await insertShortSurgeData(
          todayShortSell: 2833.0,
          historyShortSell: 87.33,
        );

        final result = (await service.detectAnomaliesByMarket(today)).byMarket;

        expect(
          result['TWSE']!.any(
            (a) => a.type == ChipAnomalyType.shortSurge && a.symbol == '2330',
          ),
          isTrue,
          reason: '高基期真實暴增不應被下限誤殺',
        );
      });

      test('冷基期突發建空高量豁免（堡達案例）', () async {
        // avg5d = 5 張（< 標準均量下限 10、但 ≥ 高量豁免下限 3）
        // today = 130 張（≥ 高量下限 100），倍率 26 倍、最早期軋空前兆
        await insertShortSurgeData(
          todayShortSell: 130.0,
          historyShortSell: 5.0,
        );

        final result = (await service.detectAnomaliesByMarket(today)).byMarket;

        expect(
          result['TWSE']!.any(
            (a) => a.type == ChipAnomalyType.shortSurge && a.symbol == '2330',
          ),
          isTrue,
          reason: '今日 ≥ 100 張且均量 ≥ 3 張，冷基期突發建空應被高量豁免救回',
        );
      });

      test('高量但均量低於豁免下限仍被濾除', () async {
        // avg5d = 2 張（< 高量豁免下限 3），today = 130 張（≥ 高量下限 100）
        // 即使當日量高，近零基期仍應濾除（避免 8476/3528 型噪訊）
        await insertShortSurgeData(
          todayShortSell: 130.0,
          historyShortSell: 2.0,
        );

        final result = (await service.detectAnomaliesByMarket(today)).byMarket;

        expect(
          result['TWSE']!.any((a) => a.type == ChipAnomalyType.shortSurge),
          isFalse,
          reason: '均量 < 3 張即使當日量高仍應濾除（近零基期噪訊）',
        );
      });
    });

    // ─────────────────────────────────────────────────────────────────────────
    // 法人集中買賣
    // ─────────────────────────────────────────────────────────────────────────

    group('法人集中買賣偵測', () {
      /// 插入法人資料：historyDays 天歷史 + 當日
      ///
      /// 偵測需 COUNT(*) >= 10（rn 2..31 至少 10 筆）
      Future<void> insertInstitutionalData({
        required double todayNet,
        double historyNet = 1000000.0,
        int historyDays = 11, // ≥ 10 才觸發 HAVING COUNT(*) >= 10
      }) async {
        for (var i = 1; i <= historyDays; i++) {
          await db.insertInstitutionalData([
            DailyInstitutionalCompanion.insert(
              symbol: '2330',
              date: today.subtract(Duration(days: i)),
              foreignNet: Value(historyNet),
              investmentTrustNet: const Value(0.0),
              dealerNet: const Value(0.0),
            ),
          ]);
        }
        await db.insertInstitutionalData([
          DailyInstitutionalCompanion.insert(
            symbol: '2330',
            date: today,
            foreignNet: Value(todayNet),
            investmentTrustNet: const Value(0.0),
            dealerNet: const Value(0.0),
          ),
        ]);
      }

      test('單日淨額 > 30 日均量 × 5 應被偵測', () async {
        // historyAvg = 1,000,000，today = 6,000,000 > 5,000,000 ✓
        await insertInstitutionalData(todayNet: 6000000.0);

        final result = (await service.detectAnomaliesByMarket(today)).byMarket;

        expect(
          result['TWSE']!.any(
            (a) =>
                a.type == ChipAnomalyType.institutionalSurge &&
                a.symbol == '2330',
          ),
          isTrue,
        );
      });

      test('處置股(DISPOSAL)從法人集中排除', () async {
        await insertInstitutionalData(todayNet: 6000000.0);
        // 2330 觸發 surge，但近期有 DISPOSAL 處置 → 應被排除
        await db.insertWarningData([
          TradingWarningCompanion.insert(
            symbol: '2330',
            date: today.subtract(const Duration(days: 5)),
            warningType: 'DISPOSAL',
          ),
        ]);

        final result = (await service.detectAnomaliesByMarket(today)).byMarket;

        expect(
          result['TWSE']!.any(
            (a) =>
                a.type == ChipAnomalyType.institutionalSurge &&
                a.symbol == '2330',
          ),
          isFalse,
          reason: '處置股的法人大賣為 distress 症狀，應從機會型訊號排除',
        );
      });

      test('注意股(ATTENTION)不從法人集中排除（避免誤殺高波動股）', () async {
        await insertInstitutionalData(todayNet: 6000000.0);
        await db.insertWarningData([
          TradingWarningCompanion.insert(
            symbol: '2330',
            date: today.subtract(const Duration(days: 5)),
            warningType: 'ATTENTION',
          ),
        ]);

        final result = (await service.detectAnomaliesByMarket(today)).byMarket;

        expect(
          result['TWSE']!.any(
            (a) =>
                a.type == ChipAnomalyType.institutionalSurge &&
                a.symbol == '2330',
          ),
          isTrue,
          reason: '注意股非處置，不應被排除',
        );
      });

      test('單日淨額 <= 30 日均量 × 5 不應被偵測', () async {
        // historyAvg = 1,000,000，today = 4,000,000 <= 5,000,000 ✗
        await insertInstitutionalData(todayNet: 4000000.0);

        final result = (await service.detectAnomaliesByMarket(today)).byMarket;

        expect(
          result['TWSE']!.any(
            (a) => a.type == ChipAnomalyType.institutionalSurge,
          ),
          isFalse,
        );
      });

      test('大買顯示正號（+）', () async {
        await insertInstitutionalData(todayNet: 6000000.0);

        final result = (await service.detectAnomaliesByMarket(today)).byMarket;
        final anomaly = result['TWSE']!.firstWhere(
          (a) => a.type == ChipAnomalyType.institutionalSurge,
        );

        expect(anomaly.keyValue, startsWith('+'));
      });

      test('大賣顯示負號（-）', () async {
        await insertInstitutionalData(todayNet: -6000000.0);

        final result = (await service.detectAnomaliesByMarket(today)).byMarket;
        final anomaly = result['TWSE']!.firstWhere(
          (a) => a.type == ChipAnomalyType.institutionalSurge,
        );

        expect(anomaly.keyValue, startsWith('-'));
      });

      test('keyValue 以張為單位（÷ 1000），非以股為單位', () async {
        // 6,000,000 股 = 6,000 張，不應顯示 6000000
        await insertInstitutionalData(todayNet: 6000000.0);

        final result = (await service.detectAnomaliesByMarket(today)).byMarket;
        final anomaly = result['TWSE']!.firstWhere(
          (a) => a.type == ChipAnomalyType.institutionalSurge,
        );

        expect(anomaly.keyValue, contains('6000張'));
        expect(anomaly.keyValue, isNot(contains('6000000')));
      });

      test('歷史筆數不足 10 筆時不觸發（HAVING COUNT(*) >= 10）', () async {
        // 9 天歷史 → COUNT = 9 < 10 → 不觸發
        await insertInstitutionalData(todayNet: 6000000.0, historyDays: 9);

        final result = (await service.detectAnomaliesByMarket(today)).byMarket;

        expect(
          result['TWSE']!.any(
            (a) => a.type == ChipAnomalyType.institutionalSurge,
          ),
          isFalse,
        );
      });
    });

    // ─────────────────────────────────────────────────────────────────────────
    // 市場分組
    // ─────────────────────────────────────────────────────────────────────────

    group('市場分組', () {
      test('TWSE 與 TPEx 異動分別歸入各自市場', () async {
        await db.insertInsiderHoldingData([
          InsiderHoldingCompanion.insert(
            symbol: '2330', // TWSE
            date: today.subtract(const Duration(days: 30)),
            pledgeRatio: const Value(50.0), // 前次 < 70（跨門檻情境，需前次快照才會被偵測）
          ),
          InsiderHoldingCompanion.insert(
            symbol: '2330',
            date: today,
            pledgeRatio: const Value(80.0),
          ),
          InsiderHoldingCompanion.insert(
            symbol: '6488', // TPEx
            date: today.subtract(const Duration(days: 30)),
            pledgeRatio: const Value(50.0),
          ),
          InsiderHoldingCompanion.insert(
            symbol: '6488',
            date: today,
            pledgeRatio: const Value(75.0),
          ),
        ]);

        final result = (await service.detectAnomaliesByMarket(today)).byMarket;

        expect(result['TWSE']!.any((a) => a.symbol == '2330'), isTrue);
        expect(result['TPEx']!.any((a) => a.symbol == '6488'), isTrue);
        expect(result['TWSE']!.any((a) => a.symbol == '6488'), isFalse);
        expect(result['TPEx']!.any((a) => a.symbol == '2330'), isFalse);
      });

      test('無資料時回傳空列表', () async {
        final result = (await service.detectAnomaliesByMarket(today)).byMarket;

        expect(result['TWSE'], isEmpty);
        expect(result['TPEx'], isEmpty);
      });
    });

    // ─────────────────────────────────────────────────────────────────────────
    // ETF 排除（宇宙定義過濾——同三模式 mode_recommendation_provider 的
    // droppedEtf 理由：規則設計皆針對個股行為，ETF 非適用對象）
    // ─────────────────────────────────────────────────────────────────────────

    group('ETF 排除（籌碼異動宇宙定義過濾）', () {
      Future<void> insertEtfStock(String symbol) async {
        await db.upsertStocks([
          StockMasterCompanion.insert(
            symbol: symbol,
            name: 'ETF測試標的',
            market: 'TWSE',
            industry: const Value('ETF'),
          ),
        ]);
      }

      test('法人集中大買（institutionalSurge）：ETF 應排除、非 ETF 同資料仍偵測', () async {
        // 006203（元大MSCI台灣）為真實線上案例：ETF 不應出現在法人集中買賣
        await insertEtfStock('006203');

        Future<void> insertSurgeData(String symbol) async {
          for (var i = 1; i <= 11; i++) {
            await db.insertInstitutionalData([
              DailyInstitutionalCompanion.insert(
                symbol: symbol,
                date: today.subtract(Duration(days: i)),
                foreignNet: const Value(1000000.0),
                investmentTrustNet: const Value(0.0),
                dealerNet: const Value(0.0),
              ),
            ]);
          }
          await db.insertInstitutionalData([
            DailyInstitutionalCompanion.insert(
              symbol: symbol,
              date: today,
              foreignNet: const Value(6000000.0), // > 30日均(100萬) × 5 門檻
              investmentTrustNet: const Value(0.0),
              dealerNet: const Value(0.0),
            ),
          ]);
        }

        // 2330（setUp 已建、非 ETF）與 006203（ETF）給同一組法人大買資料
        await insertSurgeData('2330');
        await insertSurgeData('006203');

        final result = (await service.detectAnomaliesByMarket(today)).byMarket;
        final twse = result['TWSE']!;

        expect(
          twse.any(
            (a) =>
                a.type == ChipAnomalyType.institutionalSurge &&
                a.symbol == '006203',
          ),
          isFalse,
          reason: 'ETF（006203）應從籌碼異動排除，同三模式宇宙定義過濾理由',
        );
        expect(
          twse.any(
            (a) =>
                a.type == ChipAnomalyType.institutionalSurge &&
                a.symbol == '2330',
          ),
          isTrue,
          reason: '非 ETF 個股同資料應正常偵測（驗證過濾未誤殺其他標的）',
        );
      });

      test('融券暴增（shortSurge）：ETF 應排除、非 ETF 同資料仍偵測', () async {
        // 00940（元大台灣價值高息）為真實線上案例：ETF 不應出現在融券暴增
        await insertEtfStock('00940');

        Future<void> insertShortSurgeData(String symbol) async {
          final historyDays = List.generate(
            5,
            (i) => today.subtract(Duration(days: i + 1)),
          );
          await db.insertMarginTradingData([
            for (final d in historyDays)
              MarginTradingCompanion.insert(
                symbol: symbol,
                date: d,
                shortSell: const Value(100.0),
              ),
            MarginTradingCompanion.insert(
              symbol: symbol,
              date: today,
              shortSell: const Value(400.0), // > 5日均(100) × 3 門檻
            ),
          ]);
        }

        await insertShortSurgeData('2330');
        await insertShortSurgeData('00940');

        final result = (await service.detectAnomaliesByMarket(today)).byMarket;
        final twse = result['TWSE']!;

        expect(
          twse.any(
            (a) => a.type == ChipAnomalyType.shortSurge && a.symbol == '00940',
          ),
          isFalse,
          reason: 'ETF（00940）應從籌碼異動排除，同三模式宇宙定義過濾理由',
        );
        expect(
          twse.any(
            (a) => a.type == ChipAnomalyType.shortSurge && a.symbol == '2330',
          ),
          isTrue,
          reason: '非 ETF 個股同資料應正常偵測（驗證過濾未誤殺其他標的）',
        );
      });
    });
  });

  group('per-detector 失敗列名(2026-08-29 靜默稽核 #4)', () {
    test('🚨 單一偵測器故障 → 列名,其餘類別照常', () async {
      // 真實故障注入:drop 內部人轉讓表 → 該 detector 的 SQL 當場炸,
      // 其他 detector 不受影響
      await db.customStatement('DROP TABLE insider_transfer');
      final result = await service.detectAnomaliesByMarket(today);
      expect(result.failedDetectors, ['insiderTransfer']);
      expect(result.byMarket, isNotEmpty, reason: '其餘偵測結果照常回傳');
    });

    test('全部正常 → failedDetectors 為空(不誤報)', () async {
      final result = await service.detectAnomaliesByMarket(today);
      expect(result.failedDetectors, isEmpty);
    });
  });
}
