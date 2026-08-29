import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';

import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/presentation/providers/providers.dart';
import 'package:daredevil/presentation/providers/price_alert_provider.dart';

// ==========================================
// Mocks
// ==========================================

class MockAppDatabase extends Mock implements AppDatabase {}

// ==========================================
// Test Helpers
// ==========================================

final _now = DateTime(2026, 2, 13);

PriceAlertEntry createAlert({
  int id = 1,
  String symbol = '2330',
  String alertType = 'ABOVE',
  double targetValue = 600.0,
  bool isActive = true,
  DateTime? triggeredAt,
  String? note,
  DateTime? createdAt,
}) {
  return PriceAlertEntry(
    id: id,
    symbol: symbol,
    alertType: alertType,
    targetValue: targetValue,
    isActive: isActive,
    triggeredAt: triggeredAt,
    note: note,
    createdAt: createdAt ?? _now,
  );
}

// ==========================================
// Tests
// ==========================================

void main() {
  late MockAppDatabase mockDb;
  late ProviderContainer container;

  setUpAll(() {
    registerFallbackValue(const PriceAlertCompanion());
  });

  setUp(() {
    mockDb = MockAppDatabase();
    container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(mockDb)],
    );
  });

  tearDown(() {
    container.dispose();
  });

  // ==========================================
  // AlertType
  // ==========================================

  group('AlertType', () {
    test('fromValue parses valid value', () {
      expect(AlertType.fromValue('ABOVE'), AlertType.above);
      expect(AlertType.fromValue('BELOW'), AlertType.below);
      expect(AlertType.fromValue('CHANGE_PCT'), AlertType.changePct);
    });

    test('fromValue throws for invalid value', () {
      expect(
        () => AlertType.fromValue('INVALID'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('tryFromValue returns null for invalid value', () {
      expect(AlertType.tryFromValue('INVALID'), isNull);
    });

    test('tryFromValue returns AlertType for valid value', () {
      expect(AlertType.tryFromValue('ABOVE'), AlertType.above);
    });

    test('requiresTargetValue is correct for price types', () {
      expect(AlertType.above.requiresTargetValue, isTrue);
      expect(AlertType.below.requiresTargetValue, isTrue);
      expect(AlertType.changePct.requiresTargetValue, isTrue);
    });

    test('requiresTargetValue is false for auto-trigger types', () {
      expect(AlertType.volumeSpike.requiresTargetValue, isFalse);
      expect(AlertType.kdGoldenCross.requiresTargetValue, isFalse);
      expect(AlertType.week52High.requiresTargetValue, isFalse);
      expect(AlertType.tradingWarning.requiresTargetValue, isFalse);
      expect(AlertType.insiderSelling.requiresTargetValue, isFalse);
    });

    test('defaultTargetValue returns expected values', () {
      expect(AlertType.rsiOverbought.defaultTargetValue, 70.0);
      expect(AlertType.rsiOversold.defaultTargetValue, 30.0);
      expect(AlertType.crossAboveMa.defaultTargetValue, 20.0);
      expect(AlertType.above.defaultTargetValue, isNull);
    });
  });

  // ==========================================
  // PriceAlertState
  // ==========================================

  group('PriceAlertState', () {
    test('has correct default values', () {
      const state = PriceAlertState();

      expect(state.alerts, isEmpty);
      expect(state.isLoading, isFalse);
      expect(state.error, isNull);
    });

    test('copyWith preserves unset values', () {
      final state = PriceAlertState(alerts: [createAlert()], isLoading: true);

      final copied = state.copyWith();
      expect(copied.alerts, hasLength(1));
      expect(copied.isLoading, isTrue);
      // Note: error is always set to null when not passed (no sentinel)
      expect(copied.error, isNull);
    });

    test('copyWith updates individual fields', () {
      const state = PriceAlertState();
      final updated = state.copyWith(isLoading: true, error: 'some error');
      expect(updated.isLoading, isTrue);
      expect(updated.error, 'some error');
    });
  });

  // ==========================================
  // PriceAlertNotifier.loadAlerts
  // ==========================================

  group('PriceAlertNotifier.loadAlerts', () {
    test('loads all alerts from DB', () async {
      final alerts = [
        createAlert(id: 1, symbol: '2330'),
        createAlert(id: 2, symbol: '2317'),
      ];
      when(() => mockDb.getAllAlerts()).thenAnswer((_) async => alerts);

      final notifier = container.read(priceAlertProvider.notifier);
      await notifier.loadAlerts();

      final state = container.read(priceAlertProvider);
      expect(state.alerts, hasLength(2));
      expect(state.isLoading, isFalse);
    });

    test('handles error gracefully', () async {
      when(() => mockDb.getAllAlerts()).thenThrow(Exception('DB error'));

      final notifier = container.read(priceAlertProvider.notifier);
      await notifier.loadAlerts();

      final state = container.read(priceAlertProvider);
      expect(state.isLoading, isFalse);
      expect(state.error, isNotNull);
    });

    test('🚨 標出主檔查不到/已下市的代碼——這些提醒永遠不會觸發', () async {
      // 判準必須與 IntradayAlertMonitor 的 getAllActiveStocks 等價:
      // 無 row(9999)或 isActive=false(1234)都算 unmonitorable。
      // 名稱是另一回事:1234 有 row 就該顯示名稱(裝飾不受監控性影響)。
      StockMasterEntry stockRow(String symbol, {required bool isActive}) =>
          StockMasterEntry(
            symbol: symbol,
            name: '測試$symbol',
            market: 'TWSE',
            industry: '測試',
            isActive: isActive,
            updatedAt: _now,
          );
      when(() => mockDb.getAllAlerts()).thenAnswer(
        (_) async => [
          createAlert(id: 1, symbol: '2330'),
          createAlert(id: 2, symbol: '9999'),
          createAlert(id: 3, symbol: '1234'),
        ],
      );
      when(
        () => mockDb.getStock('2330'),
      ).thenAnswer((_) async => stockRow('2330', isActive: true));
      when(() => mockDb.getStock('9999')).thenAnswer((_) async => null);
      when(
        () => mockDb.getStock('1234'),
      ).thenAnswer((_) async => stockRow('1234', isActive: false));

      final notifier = container.read(priceAlertProvider.notifier);
      await notifier.loadAlerts();

      final state = container.read(priceAlertProvider);
      expect(state.unmonitorableSymbols, {'9999', '1234'});
      expect(state.stockNames, {'2330': '測試2330', '1234': '測試1234'});
    });
  });

  // ==========================================
  // PriceAlertNotifier.createAlert
  // ==========================================

  group('PriceAlertNotifier.createAlert', () {
    test('creates alert and adds to state', () async {
      final newAlert = createAlert(id: 99);
      when(
        () => mockDb.createPriceAlert(
          symbol: any(named: 'symbol'),
          alertType: any(named: 'alertType'),
          targetValue: any(named: 'targetValue'),
          note: any(named: 'note'),
        ),
      ).thenAnswer((_) async => 99);
      when(() => mockDb.getAlertById(99)).thenAnswer((_) async => newAlert);

      final notifier = container.read(priceAlertProvider.notifier);
      final result = await notifier.createAlert(
        symbol: '2330',
        alertType: AlertType.above,
        targetValue: 600.0,
      );

      expect(result, isTrue);
      final state = container.read(priceAlertProvider);
      expect(state.alerts, hasLength(1));
      expect(state.alerts.first.id, 99);
    });

    test('returns false on error', () async {
      when(
        () => mockDb.createPriceAlert(
          symbol: any(named: 'symbol'),
          alertType: any(named: 'alertType'),
          targetValue: any(named: 'targetValue'),
          note: any(named: 'note'),
        ),
      ).thenThrow(Exception('DB error'));

      final notifier = container.read(priceAlertProvider.notifier);
      final result = await notifier.createAlert(
        symbol: '2330',
        alertType: AlertType.above,
        targetValue: 600.0,
      );

      expect(result, isFalse);
      final state = container.read(priceAlertProvider);
      expect(state.error, isNotNull);
    });
  });

  // ==========================================
  // PriceAlertNotifier.deleteAlert
  // ==========================================

  group('PriceAlertNotifier.deleteAlert', () {
    test('removes alert from state optimistically', () async {
      final alerts = [createAlert(id: 1), createAlert(id: 2)];
      when(() => mockDb.getAllAlerts()).thenAnswer((_) async => alerts);
      when(() => mockDb.deletePriceAlert(1)).thenAnswer((_) async {});

      final notifier = container.read(priceAlertProvider.notifier);
      await notifier.loadAlerts();
      await notifier.deleteAlert(1);

      final state = container.read(priceAlertProvider);
      expect(state.alerts, hasLength(1));
      expect(state.alerts.first.id, 2);
    });

    test('rolls back on error', () async {
      final alerts = [createAlert(id: 1)];
      when(() => mockDb.getAllAlerts()).thenAnswer((_) async => alerts);
      when(() => mockDb.deletePriceAlert(1)).thenThrow(Exception('DB error'));

      final notifier = container.read(priceAlertProvider.notifier);
      await notifier.loadAlerts();
      await notifier.deleteAlert(1);

      final state = container.read(priceAlertProvider);
      // Should roll back
      expect(state.alerts, hasLength(1));
      expect(state.error, isNotNull);
    });
  });

  // ==========================================
  // PriceAlertNotifier.toggleAlert
  // ==========================================

  group('PriceAlertNotifier.toggleAlert', () {
    test('toggles isActive optimistically', () async {
      final alerts = [createAlert(id: 1, isActive: true)];
      when(() => mockDb.getAllAlerts()).thenAnswer((_) async => alerts);
      when(
        () => mockDb.updatePriceAlert(any(), any()),
      ).thenAnswer((_) async => 1);

      final notifier = container.read(priceAlertProvider.notifier);
      await notifier.loadAlerts();
      await notifier.toggleAlert(1, false);

      final state = container.read(priceAlertProvider);
      expect(state.alerts.first.isActive, isFalse);
    });

    test('rolls back on error', () async {
      final alerts = [createAlert(id: 1, isActive: true)];
      when(() => mockDb.getAllAlerts()).thenAnswer((_) async => alerts);
      when(
        () => mockDb.updatePriceAlert(any(), any()),
      ).thenThrow(Exception('DB error'));

      final notifier = container.read(priceAlertProvider.notifier);
      await notifier.loadAlerts();
      await notifier.toggleAlert(1, false);

      final state = container.read(priceAlertProvider);
      // Should roll back to original
      expect(state.alerts.first.isActive, isTrue);
      expect(state.error, isNotNull);
    });
  });

  // ==========================================
  // Provider declaration
  // ==========================================

  group('priceAlertProvider', () {
    test('has correct initial state', () {
      final state = container.read(priceAlertProvider);
      expect(state.alerts, isEmpty);
      expect(state.isLoading, isFalse);
    });
  });

  // ==========================================
  // getAlertDescription — top-level function
  // ==========================================

  group('getAlertDescription', () {
    for (final alertType in AlertType.values) {
      test('returns non-empty description for ${alertType.name}', () {
        final alert = createAlert(
          alertType: alertType.value,
          targetValue: 100.0,
        );
        final description = getAlertDescription(alert, alertType);
        expect(description, isNotEmpty);
      });
    }

    test('above returns non-empty string', () {
      final alert = createAlert(alertType: 'ABOVE', targetValue: 900.50);
      final desc = getAlertDescription(alert, AlertType.above);
      expect(desc, isNotEmpty);
    });

    test('below returns non-empty string', () {
      final alert = createAlert(alertType: 'BELOW', targetValue: 700.25);
      final desc = getAlertDescription(alert, AlertType.below);
      expect(desc, isNotEmpty);
    });

    test('changePct returns non-empty string', () {
      final alert = createAlert(alertType: 'CHANGE_PCT', targetValue: 5.0);
      final desc = getAlertDescription(alert, AlertType.changePct);
      expect(desc, isNotEmpty);
    });
  });

  // ==========================================
  // checkAndTriggerAlerts — legacy alert auto-disable sync
  // ==========================================

  group('PriceAlertNotifier.checkAndTriggerAlerts', () {
    test('syncs auto-disabled legacy alerts to in-memory state', () async {
      // 先載入含有一筆 legacy 未實作類型的 alerts
      final legacyAlert = createAlert(
        id: 99,
        symbol: '2330',
        alertType: 'LEGACY_UNKNOWN_TYPE',
        isActive: true,
      );
      final normalAlert = createAlert(
        id: 1,
        symbol: '2330',
        alertType: 'ABOVE',
        targetValue: 600.0,
        isActive: true,
      );
      when(
        () => mockDb.getAllAlerts(),
      ).thenAnswer((_) async => [normalAlert, legacyAlert]);

      final notifier = container.read(priceAlertProvider.notifier);
      await notifier.loadAlerts();

      // 確認初始 state 兩筆都是 isActive
      expect(container.read(priceAlertProvider).alerts, hasLength(2));
      expect(
        container.read(priceAlertProvider).alerts.every((a) => a.isActive),
        isTrue,
      );

      // Mock checkAlerts 回傳空（無觸發），DAO 內部已停用 legacy
      when(
        () => mockDb.checkAlerts(
          any(),
          any(),
          evaluationService: any(named: 'evaluationService'),
        ),
      ).thenAnswer((_) async => <PriceAlertEntry>[]);

      await notifier.checkAndTriggerAlerts({'2330': 500.0}, {'2330': 0.0});

      final state = container.read(priceAlertProvider);
      // legacy alert 應被同步為 isActive: false
      final legacy = state.alerts.firstWhere((a) => a.id == 99);
      expect(legacy.isActive, isFalse);

      // 正常 alert 不受影響
      final normal = state.alerts.firstWhere((a) => a.id == 1);
      expect(normal.isActive, isTrue);
    });
  });

  // ==========================================
  // PriceAlertNotifier.toggleAlert — rapid toggle (last-intent-wins)
  // ==========================================

  group('PriceAlertNotifier.toggleAlert rapid toggle', () {
    test('last intent wins when toggling same alert twice quickly', () async {
      final alerts = [createAlert(id: 1, isActive: true)];
      when(() => mockDb.getAllAlerts()).thenAnswer((_) async => alerts);

      // 第一次 toggle: off → 用 Completer 控制完成時機
      final firstCompleter = Completer<void>();
      var callCount = 0;
      when(() => mockDb.updatePriceAlert(any(), any())).thenAnswer((_) {
        callCount++;
        if (callCount == 1) return firstCompleter.future;
        // 第二次 toggle: on → 立即完成
        return Future<void>.value();
      });

      final notifier = container.read(priceAlertProvider.notifier);
      await notifier.loadAlerts();

      // 快速連點：先 off 再 on，不 await 第一次
      final first = notifier.toggleAlert(1, false);
      final second = notifier.toggleAlert(1, true);

      // 讓第一次完成
      firstCompleter.complete();
      await first;
      await second;

      final state = container.read(priceAlertProvider);
      // 最後一次意圖是 on → isActive 應為 true
      expect(state.alerts.first.isActive, isTrue);
      // DB 應該被呼叫兩次（序列化執行）
      expect(callCount, 2);
    });
  });
}
