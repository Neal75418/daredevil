import 'package:daredevil/core/constants/rule_params.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/domain/services/alert_evaluation_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/price_data_generators.dart';

/// [AlertEvaluationService] 的 RSI/KD 警示檢查與 AnalysisCoordinatorService
/// 修復前重複同一份 gap-naive 擷取邏輯（sibling bug，同一 root cause）。
/// 此檔案原本沒有測試覆蓋，這裡補上聚焦於 gap-awareness 的迴歸測試。
void main() {
  group('skippedNoPrice(2026-08-29 靜默稽核 #10)', () {
    // 當日價格 map 缺 symbol(部分同步/停牌)時,已實作型別的警示原本
    // 靜默 continue——KD/量能類不必然依賴現價的也一併跳過,零訊號零
    // 計數。「提醒沒響」與「提醒沒被評估」不可分。
    test('🚨 缺現價的警示要計數,不得靜默消失', () {
      final service = AlertEvaluationService();
      final result = service.evaluateAlerts(
        [
          PriceAlertEntry(
            id: 1,
            symbol: 'NOPRICE',
            alertType: 'ABOVE',
            targetValue: 100,
            isActive: true,
            createdAt: DateTime(2026, 8, 20),
          ),
          PriceAlertEntry(
            id: 2,
            symbol: 'HASPRICE',
            alertType: 'ABOVE',
            targetValue: 100,
            isActive: true,
            createdAt: DateTime(2026, 8, 20),
          ),
        ],
        const AlertEvaluationContext(
          currentPrices: {'HASPRICE': 150},
          priceChanges: {},
          volumeDataMap: {},
          priceHistoryMap: {},
          indicatorDataMap: {},
          warningSymbols: {},
          disposalSymbols: {},
        ),
      );
      expect(result.skippedNoPrice, ['NOPRICE']);
      expect(result.triggered.map((a) => a.id), [2], reason: '有價的照常評估');
    });

    test('全部有價 → skippedNoPrice 為空(不誤報)', () {
      final service = AlertEvaluationService();
      final result = service.evaluateAlerts(
        [
          PriceAlertEntry(
            id: 1,
            symbol: 'A',
            alertType: 'BELOW',
            targetValue: 100,
            isActive: true,
            createdAt: DateTime(2026, 8, 20),
          ),
        ],
        const AlertEvaluationContext(
          currentPrices: {'A': 150},
          priceChanges: {},
          volumeDataMap: {},
          priceHistoryMap: {},
          indicatorDataMap: {},
          warningSymbols: {},
          disposalSymbols: {},
        ),
      );
      expect(result.skippedNoPrice, isEmpty);
    });
  });

  late AlertEvaluationService service;

  setUp(() {
    service = AlertEvaluationService();
  });

  PriceAlertEntry rsiOverboughtAlert({double targetValue = 70.0}) {
    return PriceAlertEntry(
      id: 1,
      symbol: 'TEST',
      alertType: AlertParams.typeRsiOverbought,
      targetValue: targetValue,
      isActive: true,
      createdAt: DateTime(2026, 1, 1),
    );
  }

  AlertEvaluationContext contextFor(List<DailyPriceEntry> indicatorData) {
    return AlertEvaluationContext(
      currentPrices: {'TEST': indicatorData.last.close ?? 0},
      priceChanges: const {},
      volumeDataMap: const {},
      priceHistoryMap: const {},
      indicatorDataMap: {'TEST': indicatorData},
      warningSymbols: const {},
      disposalSymbols: const {},
    );
  }

  group('RSI_OVERBOUGHT — gap-awareness', () {
    test(
      'does NOT fire on a phantom spike fabricated by bridging a halt gap',
      () {
        final now = DateTime(2026, 1, 1);
        final entries = <DailyPriceEntry>[
          for (int i = 0; i < 70; i++)
            createTestPrice(
              date: now.add(Duration(days: i)),
              close: 100.0 + (i.isEven ? 0.3 : -0.3),
              volume: 1000,
            ),
          // 兩日停牌
          createTestPrice(
            date: now.add(const Duration(days: 70)),
            close: null,
            volume: 0,
          ),
          createTestPrice(
            date: now.add(const Duration(days: 71)),
            close: null,
            volume: 0,
          ),
          // 復牌當日：若跨缺口價差被誤採計，會虛假觸發 RSI 超買警示
          createTestPrice(
            date: now.add(const Duration(days: 72)),
            close: 250.0,
            volume: 1000,
          ),
        ];

        final result = service.evaluateAlerts([
          rsiOverboughtAlert(),
        ], contextFor(entries));

        expect(result.triggered, isEmpty);
      },
    );

    test('still fires on a genuine (non-gapped) RSI overbought run', () {
      final now = DateTime(2026, 1, 1);
      final entries = List.generate(
        30,
        (i) => createTestPrice(
          date: now.add(Duration(days: i)),
          close: 100.0 + i * 2.0, // 持續上漲，無缺口 → 真正的 RSI 超買
          volume: 1000,
        ),
      );

      final result = service.evaluateAlerts([
        rsiOverboughtAlert(),
      ], contextFor(entries));

      expect(result.triggered, hasLength(1));
    });
  });

  // 提醒對話框原本會把預填現價當成任何類型的 targetValue 存下去(已修),
  // 但既有 DB 裡已經躺著這種資料。不需目標值的類型在評估時不得再讀它。
  group('不需目標值的類型不讀 targetValue(既有髒資料)', () {
    PriceAlertEntry pledgeAlert({required double targetValue}) =>
        PriceAlertEntry(
          id: 1,
          symbol: '2330',
          alertType: AlertParams.typeHighPledgeRatio,
          targetValue: targetValue,
          isActive: true,
          createdAt: DateTime(2026, 9, 1),
        );

    AlertEvaluationContext pledgeContext(double ratio) =>
        AlertEvaluationContext(
          currentPrices: const {'2330': 850},
          priceChanges: const {},
          volumeDataMap: const {},
          priceHistoryMap: const {},
          indicatorDataMap: const {},
          warningSymbols: const {},
          disposalSymbols: const {},
          pledgeRatioMap: {'2330': ratio},
        );

    test('🚨 質押提醒存了現價 850 當門檻,質押比 45% 仍要觸發', () {
      final result = AlertEvaluationService().evaluateAlerts([
        pledgeAlert(targetValue: 850),
      ], pledgeContext(45));
      expect(result.triggered, hasLength(1));
    });

    test('質押比低於固定門檻不觸發(不論 targetValue)', () {
      final result = AlertEvaluationService().evaluateAlerts([
        pledgeAlert(targetValue: 0),
      ], pledgeContext(AlertParams.highPledgeRatioPct - 1));
      expect(result.triggered, isEmpty);
    });
  });

  // UI 說明是「成交量高於 {value} 張」,DB 的 volume 是「股」——原本直接拿
  // 股數比張數,輸入 10000(一萬張)實際在比一萬股=10 張,幾乎天天觸發。
  group('成交量高於:targetValue 單位是張', () {
    PriceAlertEntry volumeAboveAlert(double lots) => PriceAlertEntry(
      id: 1,
      symbol: '2330',
      alertType: AlertParams.typeVolumeAbove,
      targetValue: lots,
      isActive: true,
      createdAt: DateTime(2026, 9, 1),
    );

    AlertEvaluationContext withLatestShares(double shares) {
      final day = DateTime(2026, 9, 1);
      return AlertEvaluationContext(
        currentPrices: const {'2330': 850},
        priceChanges: const {},
        volumeDataMap: {
          '2330': [
            createTestPrice(symbol: '2330', date: day, close: 850, volume: 1),
            createTestPrice(
              symbol: '2330',
              date: day.add(const Duration(days: 1)),
              close: 850,
              volume: shares,
            ),
          ],
        },
        priceHistoryMap: const {},
        indicatorDataMap: const {},
        warningSymbols: const {},
        disposalSymbols: const {},
      );
    }

    test('🚨 設 10000 張、今天成交 5000 張(500 萬股)不得觸發', () {
      final result = AlertEvaluationService().evaluateAlerts([
        volumeAboveAlert(10000),
      ], withLatestShares(5000000));
      expect(result.triggered, isEmpty);
    });

    test('設 10000 張、今天成交 12000 張(1200 萬股)要觸發', () {
      final result = AlertEvaluationService().evaluateAlerts([
        volumeAboveAlert(10000),
      ], withLatestShares(12000000));
      expect(result.triggered, hasLength(1));
    });
  });
}
