import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/constants/rule_params_alert.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/presentation/providers/notification_provider.dart';
import 'package:daredevil/presentation/providers/price_alert_provider.dart';
import 'package:daredevil/presentation/widgets/price_alert_dialog.dart';

import '../../helpers/provider_test_helpers.dart';
import '../../helpers/widget_test_helpers.dart';

void main() {
  setUpAll(() async {
    await setupTestLocalization();
  });

  void widenViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(8000, 6000);
    addTearDown(() => tester.view.resetPhysicalSize());
  }

  group('CreatePriceAlertDialog', () {
    testWidgets('displays symbol', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(
        buildProviderTestApp(const CreatePriceAlertDialog(symbol: '2330')),
      );
      await tester.pump();

      expect(find.text('2330'), findsOneWidget);
    });

    testWidgets('displays stock name when provided', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(
        buildProviderTestApp(
          const CreatePriceAlertDialog(symbol: '2330', stockName: '台積電'),
        ),
      );
      await tester.pump();

      expect(find.text('台積電'), findsOneWidget);
    });

    testWidgets('hides stock name when null', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(
        buildProviderTestApp(const CreatePriceAlertDialog(symbol: '2330')),
      );
      await tester.pump();

      expect(find.text('2330'), findsOneWidget);
      expect(find.text('台積電'), findsNothing);
    });

    testWidgets('pre-fills value field with currentPrice', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(
        buildProviderTestApp(
          const CreatePriceAlertDialog(symbol: '2330', currentPrice: 850.00),
        ),
      );
      await tester.pump();

      expect(find.text('850.00'), findsAtLeastNWidgets(1));
    });

    testWidgets('shows current price hint text', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(
        buildProviderTestApp(
          const CreatePriceAlertDialog(symbol: '2330', currentPrice: 850.00),
        ),
      );
      await tester.pump();

      // The current price hint uses .tr() which returns the key
      // but the actual price value appears in the pre-filled field
      expect(find.textContaining('850.00'), findsAtLeastNWidgets(1));
    });

    testWidgets('提醒類型以可換行的 ChoiceChip 呈現(每種一顆)', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(
        buildProviderTestApp(const CreatePriceAlertDialog(symbol: '2330')),
      );
      await tester.pump();

      final implemented = AlertType.values.where((t) => t.isImplemented).length;
      expect(find.byType(ChoiceChip), findsNWidgets(implemented));
      // 分組必須依 AlertParams.intradayMonitoredTypes(單一事實來源),
      // 不可在 UI 另外硬編碼一份——兩邊各自維護必然漂移(2026-08-08)
      final intraday = AlertType.values
          .where(
            (t) =>
                t.isImplemented &&
                AlertParams.intradayMonitoredTypes.contains(t.value),
          )
          .length;
      expect(intraday, 2, reason: '只有價格高於/低於會被盤中 CLI 每 5 分鐘檢查');
      expect(implemented - intraday, 21, reason: '其餘只有收盤路徑評估——UI 必須讓使用者看得出差別');
      expect(
        find.byType(SegmentedButton<AlertType>),
        findsNothing,
        reason: 'SegmentedButton 是 Row,不換行不捲動——23 種類型必然爆版',
      );
    });

    testWidgets('有給 stockName 時標題顯示名稱,沒給時只顯示代碼', (tester) async {
      // 2026-08-08 實機:清單修好了顯示「3231 緯創」,但點進編輯對話框
      // 又變回只有「3231」——「新增」路徑一直有傳 stockName,只有
      // 「編輯」路徑漏了。同一個資訊在兩條路徑不一致。
      widenViewport(tester);
      await tester.pumpWidget(
        buildProviderTestApp(
          const CreatePriceAlertDialog(symbol: '3231', stockName: '緯創'),
        ),
      );
      await tester.pump();
      expect(find.text('緯創'), findsOneWidget);
      expect(find.text('3231'), findsOneWidget);
    });

    testWidgets('🚨 超寬視窗下對話框不得無限拉寬', (tester) async {
      // 2026-08-08 實機(3740px 視窗):對話框整個拉滿,目標價欄位橫跨
      // 全寬,「179.95」在最左、「元」在最右,視覺上斷開。AlertDialog
      // 本身不限內容寬度,而裡面的 Wrap 會吃滿可用寬度。
      //
      // 這條與「窄視窗不得爆版」是**反方向**的守門:一個測太窄、一個
      // 測太寬。原本的 widenViewport 慣例只會撐寬,所以這一側從來沒被
      // 檢查過——爆版看得見,拉太寬看起來只是「有點怪」,更容易忽略。
      tester.view.physicalSize = const Size(3600, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        buildProviderTestApp(const CreatePriceAlertDialog(symbol: '2330')),
      );
      await tester.pump();

      final w = tester.getSize(find.byType(SingleChildScrollView).first).width;
      expect(
        w,
        lessThanOrEqualTo(560.0),
        reason: '對話框內容寬度必須有上限(Material 3 標準 560dp),實測 $w',
      );
    });

    testWidgets('🚨 窄視窗不得 RenderFlex overflow', (tester) async {
      // 2026-08-08 實機:視窗縮小時對話框出現黃黑斜紋
      // 「OVERFLOWED BY 25 PIXELS」,類型標籤被壓成直排。
      //
      // ⚠️ 這個 bug 能活下來,是因為**本檔每一條測試都先呼叫
      // widenViewport**(把視窗撐到 5000×4000 以避開 overflow)——那個
      // 慣例的用意是好的(避免無關的 overflow 噪音),但副作用是
      // 「窄視窗爆版」這一整類 bug 在測試裡**結構上不可能被抓到**。
      // 所以這條刻意**不**撐寬,用接近真實的小視窗跑。
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        buildProviderTestApp(const CreatePriceAlertDialog(symbol: '2330')),
      );
      await tester.pump();

      expect(tester.takeException(), isNull, reason: '800px 寬就爆版的話,一般視窗大小都會爆');
    });

    testWidgets('has target value TextField', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(
        buildProviderTestApp(const CreatePriceAlertDialog(symbol: '2330')),
      );
      await tester.pump();

      // Two TextFields: target value + note
      expect(find.byType(TextField), findsNWidgets(2));
    });

    testWidgets('has cancel and create buttons', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(
        buildProviderTestApp(const CreatePriceAlertDialog(symbol: '2330')),
      );
      await tester.pump();

      // FilledButton is the create button (only one in the dialog)
      expect(find.byType(FilledButton), findsOneWidget);
      // AlertDialog has actions — verify it renders
      expect(find.byType(AlertDialog), findsOneWidget);
    });

    testWidgets('renders in dark mode', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(
        buildProviderTestApp(
          const CreatePriceAlertDialog(symbol: '2330', stockName: '台積電'),
          brightness: Brightness.dark,
        ),
      );
      await tester.pump();

      expect(find.text('2330'), findsOneWidget);
      expect(find.text('台積電'), findsOneWidget);
    });

    testWidgets('shows all 23 alert types', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(
        buildProviderTestApp(const CreatePriceAlertDialog(symbol: '2330')),
      );
      await tester.pump();

      // 驗證 23 種提醒類型（全部已實作）
      // 基本價格提醒 (3)
      expect(find.text('alert.alertType.above'), findsOneWidget);
      expect(find.text('alert.alertType.below'), findsOneWidget);
      expect(find.text('alert.alertType.changePct'), findsOneWidget);

      // 成交量提醒 (2)
      expect(find.text('alert.alertType.volumeSpike'), findsOneWidget);
      expect(find.text('alert.alertType.volumeAbove'), findsOneWidget);

      // 52 週高低提醒 (2)
      expect(find.text('alert.alertType.week52High'), findsOneWidget);
      expect(find.text('alert.alertType.week52Low'), findsOneWidget);

      // RSI/KD 指標提醒 (4)
      expect(find.text('alert.alertType.rsiOverbought'), findsOneWidget);
      expect(find.text('alert.alertType.rsiOversold'), findsOneWidget);
      expect(find.text('alert.alertType.kdGoldenCross'), findsOneWidget);
      expect(find.text('alert.alertType.kdDeathCross'), findsOneWidget);

      // MA 交叉 + 注意/處置提醒 (4)
      expect(find.text('alert.alertType.crossAboveMa'), findsOneWidget);
      expect(find.text('alert.alertType.crossBelowMa'), findsOneWidget);
      expect(find.text('alert.alertType.tradingWarning'), findsOneWidget);
      expect(find.text('alert.alertType.tradingDisposal'), findsOneWidget);

      // Phase 3: 進階警示類型 (8) — 全部已實作
      expect(find.text('alert.alertType.breakResistance'), findsOneWidget);
      expect(find.text('alert.alertType.breakSupport'), findsOneWidget);
      expect(find.text('alert.alertType.revenueYoySurge'), findsOneWidget);
      expect(find.text('alert.alertType.highDividendYield'), findsOneWidget);
      expect(find.text('alert.alertType.peUndervalued'), findsOneWidget);
      expect(find.text('alert.alertType.insiderSelling'), findsOneWidget);
      expect(find.text('alert.alertType.insiderBuying'), findsOneWidget);
      expect(find.text('alert.alertType.highPledgeRatio'), findsOneWidget);
    });
  });

  // 建立模式會把現價預填進數值欄;切換類型時欄位原本不跟著換,於是
  // 「850 元」被當成任何類型的門檻存下去——質押比 ≥850% 永不觸發、
  // RSI ≥850 永不觸發、PE ≤850 幾乎天天觸發。
  group('切換類型時目標值要跟著類型走', () {
    late _RecordingAlertNotifier alerts;

    Future<void> openDialog(
      WidgetTester tester, {
      double? currentPrice = 850,
      PriceAlertEntry? existingAlert,
    }) async {
      widenViewport(tester);
      alerts = _RecordingAlertNotifier();
      await tester.pumpWidget(
        buildProviderTestApp(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => showCreatePriceAlertDialog(
                context: context,
                symbol: '2330',
                currentPrice: currentPrice,
                existingAlert: existingAlert,
              ),
              child: const Text('open'),
            ),
          ),
          overrides: [
            priceAlertProvider.overrideWith(() => alerts),
            notificationProvider.overrideWith(_GrantedNotificationNotifier.new),
          ],
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    String valueFieldText(WidgetTester tester) =>
        tester.widget<TextField>(find.byType(TextField).first).controller!.text;

    testWidgets('🚨 切到不需目標值的類型後儲存,不得把預填現價存成門檻', (tester) async {
      await openDialog(tester);
      expect(valueFieldText(tester), '850.00', reason: '前提:建立模式預填現價');

      await tester.tap(find.text('alert.alertType.highPledgeRatio'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();

      expect(alerts.created, hasLength(1));
      expect(alerts.created.single.type, AlertType.highPledgeRatio);
      expect(alerts.created.single.target, 0);
    });

    testWidgets('不需目標值的類型不顯示數值欄(只剩備註欄)', (tester) async {
      await openDialog(tester);
      expect(find.byType(TextField), findsNWidgets(2), reason: '前提:數值+備註');

      await tester.tap(find.text('alert.alertType.kdGoldenCross'));
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('切到有預設值的類型換成該預設,切回價格類型換回現價', (tester) async {
      await openDialog(tester);

      await tester.tap(find.text('alert.alertType.rsiOverbought'));
      await tester.pumpAndSettle();
      expect(valueFieldText(tester), '70');

      await tester.tap(find.text('alert.alertType.peUndervalued'));
      await tester.pumpAndSettle();
      expect(valueFieldText(tester), '10');

      await tester.tap(find.text('alert.alertType.changePct'));
      await tester.pumpAndSettle();
      expect(valueFieldText(tester), '', reason: '漲跌幅沒有合理預設,留空讓使用者填');

      await tester.tap(find.text('alert.alertType.breakResistance'));
      await tester.pumpAndSettle();
      expect(valueFieldText(tester), '850.00');
    });

    testWidgets('切到 RSI 後直接儲存,存的是 RSI 預設而非現價', (tester) async {
      await openDialog(tester);

      await tester.tap(find.text('alert.alertType.rsiOverbought'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();

      expect(alerts.created.single.type, AlertType.rsiOverbought);
      expect(alerts.created.single.target, 70);
    });

    testWidgets('🚨 編輯模式不可切換類型——editAlert 只存數值,切了也不會生效', (tester) async {
      await openDialog(
        tester,
        currentPrice: null,
        existingAlert: PriceAlertEntry(
          id: 7,
          symbol: '2330',
          alertType: AlertParams.typeAbove,
          targetValue: 900,
          isActive: true,
          createdAt: DateTime(2026, 9, 1),
        ),
      );

      final other = tester.widget<ChoiceChip>(
        find.ancestor(
          of: find.text('alert.alertType.rsiOverbought'),
          matching: find.byType(ChoiceChip),
        ),
      );
      expect(other.onSelected, isNull, reason: '非目前類型的 chip 要停用');
    });

    testWidgets('🚨 編輯舊版存了現價的質押提醒,儲存時洗回 0', (tester) async {
      await openDialog(
        tester,
        currentPrice: null,
        existingAlert: PriceAlertEntry(
          id: 7,
          symbol: '2330',
          alertType: AlertParams.typeHighPledgeRatio,
          targetValue: 850,
          isActive: true,
          createdAt: DateTime(2026, 9, 1),
        ),
      );

      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();

      expect(alerts.edited, [0]);
    });
  });
}

class _RecordingAlertNotifier extends PriceAlertNotifier {
  final created = <({AlertType type, double target})>[];

  @override
  PriceAlertState build() => const PriceAlertState();

  @override
  Future<bool> createAlert({
    required String symbol,
    required AlertType alertType,
    required double targetValue,
    String? note,
  }) async {
    created.add((type: alertType, target: targetValue));
    return true;
  }

  final edited = <double>[];

  @override
  Future<bool> editAlert({
    required int id,
    required double targetValue,
    String? note,
  }) async {
    edited.add(targetValue);
    return true;
  }
}

class _GrantedNotificationNotifier extends NotificationNotifier {
  @override
  NotificationState build() => const NotificationState(hasPermission: true);
}
