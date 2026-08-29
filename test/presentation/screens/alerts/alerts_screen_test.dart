import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/theme/app_theme.dart';
import 'package:daredevil/core/theme/semantic_colors.dart';

import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/presentation/providers/price_alert_provider.dart';
import 'package:daredevil/presentation/screens/alerts/alerts_screen.dart';
import 'package:daredevil/presentation/widgets/empty_state.dart';
import 'package:daredevil/presentation/widgets/shimmer_loading.dart';

import '../../../helpers/provider_test_helpers.dart';
import '../../../helpers/widget_test_helpers.dart';

// ==========================================
// Fake Notifier
// ==========================================

class FakePriceAlertNotifier extends PriceAlertNotifier {
  PriceAlertState initialState = const PriceAlertState();

  @override
  PriceAlertState build() => initialState;

  @override
  Future<void> loadAlerts() async {}

  @override
  Future<void> deleteAlert(int id) async {}

  @override
  Future<void> toggleAlert(int id, bool isActive) async {}

  @override
  Future<bool> createAlert({
    required String symbol,
    required AlertType alertType,
    required double targetValue,
    String? note,
  }) async => true;
}

// ==========================================
// Test Helpers
// ==========================================

PriceAlertEntry createAlert({
  int id = 1,
  String symbol = '2330',
  String alertType = 'ABOVE',
  double targetValue = 900.0,
  bool isActive = true,
  DateTime? triggeredAt,
  String? note,
  String? managedBy,
}) {
  return PriceAlertEntry(
    id: id,
    symbol: symbol,
    alertType: alertType,
    targetValue: targetValue,
    isActive: isActive,
    triggeredAt: triggeredAt,
    note: note,
    managedBy: managedBy,
    createdAt: DateTime(2026, 2, 13),
  );
}

// ==========================================
// Tests
// ==========================================

void main() {
  setUpAll(() async {
    await setupTestLocalization();
  });

  void widenViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(5000, 8000);
    addTearDown(() => tester.view.resetPhysicalSize());
  }

  Widget buildTestWidget({
    PriceAlertState? alertState,
    Brightness brightness = Brightness.light,
  }) {
    final state = alertState ?? const PriceAlertState();
    return buildProviderTestApp(
      const AlertsScreen(),
      overrides: [
        priceAlertProvider.overrideWith(() {
          final n = FakePriceAlertNotifier();
          n.initialState = state;
          return n;
        }),
      ],
      brightness: brightness,
    );
  }

  group('AlertsScreen', () {
    testWidgets('🚨 清單項目不得有 entrance 動畫——捲動會重播(2026-08-16 實機)', (tester) async {
      // ListView.builder 的 itemBuilder 在項目捲進畫面時才建構,把
      // `.animate().fadeIn(delay: 50ms * index)` 寫在裡面等於**每次捲動都
      // 重跑一次淡入**,而且越後面延遲越長(第 36 筆是 1750ms)。使用者實機
      // 回報「下捲很不順暢」。自選股清單沒有這個寫法,所以只有警示頁會卡。
      widenViewport(tester);
      await tester.pumpWidget(
        buildTestWidget(
          alertState: PriceAlertState(
            alerts: [
              for (var i = 0; i < 12; i++)
                createAlert(
                  id: i + 1,
                  symbol: '23${i.toString().padLeft(2, '0')}',
                ),
            ],
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(
        find.descendant(
          of: find.byType(ListView),
          matching: find.byType(Animate),
        ),
        findsNothing,
        reason: '捲動清單的 item 不該有進場動畫——builder 重建即重播',
      );
    });

    testWidgets('每日自動的提醒要標示出來,手動的不標', (tester) async {
      // 使用者問「他又是怎麼判斷誰是手動的」——那正是因為畫面上看不出來
      widenViewport(tester);
      await tester.pumpWidget(
        buildTestWidget(
          alertState: PriceAlertState(
            alerts: [
              createAlert(id: 1, symbol: '2330', managedBy: 'TRAILING_MA'),
              createAlert(id: 2, symbol: '2317'),
            ],
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      // setupTestLocalization 不載入翻譯檔,`.tr()` 回傳原始 key
      // ——既有測試因此一律避開翻譯後文字的斷言
      expect(
        find.text('alert.trailingManaged'),
        findsOneWidget,
        reason: '兩筆裡只有一筆是自動的,手動那筆不得有標示',
      );
    });

    testWidgets('shows shimmer loading state', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(
        buildTestWidget(alertState: const PriceAlertState(isLoading: true)),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(GenericListShimmer), findsOneWidget);
    });

    testWidgets('shows empty state when no alerts', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(buildTestWidget());
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(EmptyState), findsOneWidget);
      expect(find.byIcon(Icons.notifications_off_outlined), findsOneWidget);
    });

    testWidgets('shows error state', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(
        buildTestWidget(
          alertState: const PriceAlertState(error: 'Network error'),
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(EmptyState), findsOneWidget);
    });

    testWidgets('shows app bar with title', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(buildTestWidget());
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(AppBar), findsOneWidget);
    });

    testWidgets('shows FAB with add icon', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(buildTestWidget());
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(FloatingActionButton), findsOneWidget);
      expect(find.byIcon(Icons.add), findsOneWidget);
    });

    testWidgets('shows grouped alert cards', (tester) async {
      widenViewport(tester);
      final alerts = [
        createAlert(id: 1, symbol: '2330', alertType: 'ABOVE'),
        createAlert(id: 2, symbol: '2330', alertType: 'BELOW'),
      ];
      await tester.pumpWidget(
        buildTestWidget(alertState: PriceAlertState(alerts: alerts)),
      );
      await tester.pump(const Duration(seconds: 1));

      // One Card group for symbol 2330
      expect(find.byType(Card), findsOneWidget);
      // Two alert tiles
      expect(find.byType(ListTile), findsNWidgets(2));
    });

    testWidgets('shows symbol badge in group header', (tester) async {
      widenViewport(tester);
      final alerts = [createAlert(symbol: '2330')];
      await tester.pumpWidget(
        buildTestWidget(alertState: PriceAlertState(alerts: alerts)),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('2330'), findsAtLeastNWidgets(1));
    });

    testWidgets('shows switch for active alert', (tester) async {
      widenViewport(tester);
      final alerts = [createAlert(isActive: true)];
      await tester.pumpWidget(
        buildTestWidget(alertState: PriceAlertState(alerts: alerts)),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(Switch), findsOneWidget);
    });

    testWidgets('shows note text', (tester) async {
      widenViewport(tester);
      final alerts = [createAlert(note: 'My note')];
      await tester.pumpWidget(
        buildTestWidget(alertState: PriceAlertState(alerts: alerts)),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('My note'), findsOneWidget);
    });

    testWidgets('🚨 主檔查不到的啟用中提醒要標「無法監控」', (tester) async {
      // release build 的 AppLogger 全等級靜默,monitor 的 warning 到不了
      // GUI 使用者——這顆徽章是「提醒掛在下市代號上永遠不會響」唯一的
      // 可見訊號,而唯一能修的人就是看這個畫面的人(2026-08-29 review)
      widenViewport(tester);
      final alerts = [createAlert(symbol: '9999', isActive: true)];
      await tester.pumpWidget(
        buildTestWidget(
          alertState: PriceAlertState(
            alerts: alerts,
            unmonitorableSymbols: const {'9999'},
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('alert.unmonitorable'), findsOneWidget);
    });

    testWidgets('已停用的提醒不標「無法監控」——它本來就不在監控隊列', (tester) async {
      widenViewport(tester);
      final alerts = [createAlert(symbol: '9999', isActive: false)];
      await tester.pumpWidget(
        buildTestWidget(
          alertState: PriceAlertState(
            alerts: alerts,
            unmonitorableSymbols: const {'9999'},
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('alert.unmonitorable'), findsNothing);
    });

    testWidgets('主檔查得到的提醒不標「無法監控」', (tester) async {
      widenViewport(tester);
      final alerts = [createAlert(symbol: '2330', isActive: true)];
      await tester.pumpWidget(
        buildTestWidget(alertState: PriceAlertState(alerts: alerts)),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('alert.unmonitorable'), findsNothing);
    });

    testWidgets('shows triggered alert with special styling', (tester) async {
      widenViewport(tester);
      final alerts = [
        createAlert(
          isActive: false,
          triggeredAt: DateTime(2026, 2, 14, 10, 30),
        ),
      ];
      await tester.pumpWidget(
        buildTestWidget(alertState: PriceAlertState(alerts: alerts)),
      );
      await tester.pump(const Duration(seconds: 1));

      // Triggered alert shows time: "2/14 10:30"
      expect(find.textContaining('2/14'), findsAtLeastNWidgets(1));
    });

    testWidgets('multiple symbol groups', (tester) async {
      widenViewport(tester);
      final alerts = [
        createAlert(id: 1, symbol: '2330'),
        createAlert(id: 2, symbol: '2317'),
      ];
      await tester.pumpWidget(
        buildTestWidget(alertState: PriceAlertState(alerts: alerts)),
      );
      await tester.pump(const Duration(seconds: 1));

      // Two Card groups
      expect(find.byType(Card), findsNWidgets(2));
    });

    // 圖示語意(2026-08-16 實機):`above`/`below` 原本是 Icons.trending_up /
    // trending_down 配股價紅綠,而自選股卡片的**趨勢狀態**用的是
    // Icons.trending_up_rounded 配同一組紅綠——兩個 20px 下分不出來的圖示,
    // 表達的卻是完全不同的事(提醒方向 vs 股票趨勢)。
    //
    // 均線階梯上線後矛盾天天出現:每檔強勢股都掛 BELOW,於是仁寶漲停 +9.92%
    // 在自選股頁是紅色上箭頭、在警示頁是綠色下箭頭。改用「穿越門檻線」的
    // 中性圖示 + 中性色,把紅綠趨勢箭頭留給股價專用。
    testWidgets('ABOVE 用穿越門檻線的中性圖示,不得借用趨勢箭頭', (tester) async {
      widenViewport(tester);
      final alerts = [createAlert(alertType: 'ABOVE')];
      await tester.pumpWidget(
        buildTestWidget(alertState: PriceAlertState(alerts: alerts)),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.byIcon(Icons.vertical_align_top), findsOneWidget);
      expect(
        find.byIcon(Icons.trending_up),
        findsNothing,
        reason: '趨勢箭頭是股價趨勢專用,不得用來表達提醒方向',
      );
    });

    testWidgets('🚨 提醒圖示不得使用股價紅綠(專案色彩規則:紅綠專屬股價)', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(
        buildTestWidget(
          alertState: PriceAlertState(
            alerts: [
              createAlert(id: 1, symbol: '2330', alertType: 'ABOVE'),
              createAlert(id: 2, symbol: '2317', alertType: 'BELOW'),
            ],
          ),
          brightness: Brightness.dark,
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      final icons = tester
          .widgetList<Icon>(find.byType(Icon))
          .where(
            (i) =>
                i.icon == Icons.vertical_align_top ||
                i.icon == Icons.vertical_align_bottom,
          )
          .toList();
      expect(icons, hasLength(2), reason: '前提:兩筆提醒的圖示都找得到');
      for (final icon in icons) {
        expect(
          icon.color,
          isNot(AppTheme.upColor),
          reason: '${icon.icon} 用了股價漲色',
        );
        expect(
          icon.color,
          isNot(PriceColors.downFor(Brightness.dark)),
          reason: '${icon.icon} 用了股價跌色',
        );
      }
    });

    testWidgets('BELOW 用穿越門檻線的中性圖示,不得借用趨勢箭頭', (tester) async {
      widenViewport(tester);
      final alerts = [createAlert(alertType: 'BELOW')];
      await tester.pumpWidget(
        buildTestWidget(alertState: PriceAlertState(alerts: alerts)),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.byIcon(Icons.vertical_align_bottom), findsOneWidget);
      expect(
        find.byIcon(Icons.trending_down),
        findsNothing,
        reason: '趨勢箭頭是股價趨勢專用,不得用來表達提醒方向',
      );
    });

    testWidgets(
      'shows percent icon for CHANGE_PCT alert（2026-07-23 稽核：兩處 switch 統一為 AlertTypeIcon extension）',
      (tester) async {
        widenViewport(tester);
        final alerts = [createAlert(alertType: 'CHANGE_PCT')];
        await tester.pumpWidget(
          buildTestWidget(alertState: PriceAlertState(alerts: alerts)),
        );
        await tester.pump(const Duration(seconds: 1));

        expect(find.byIcon(Icons.percent), findsOneWidget);
      },
    );

    testWidgets('shows bar_chart icon for VOLUME_SPIKE alert', (tester) async {
      widenViewport(tester);
      final alerts = [createAlert(alertType: 'VOLUME_SPIKE')];
      await tester.pumpWidget(
        buildTestWidget(alertState: PriceAlertState(alerts: alerts)),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.byIcon(Icons.bar_chart), findsOneWidget);
    });

    testWidgets('shows arrow icons for RSI alerts', (tester) async {
      widenViewport(tester);
      final alerts = [
        createAlert(id: 1, alertType: 'RSI_OVERBOUGHT'),
        createAlert(id: 2, alertType: 'RSI_OVERSOLD', symbol: '2317'),
      ];
      await tester.pumpWidget(
        buildTestWidget(alertState: PriceAlertState(alerts: alerts)),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.byIcon(Icons.arrow_upward), findsOneWidget);
      expect(find.byIcon(Icons.arrow_downward), findsOneWidget);
    });

    testWidgets('shows circle icons for KD alerts', (tester) async {
      widenViewport(tester);
      final alerts = [
        createAlert(id: 1, alertType: 'KD_GOLDEN_CROSS'),
        createAlert(id: 2, alertType: 'KD_DEATH_CROSS', symbol: '2317'),
      ];
      await tester.pumpWidget(
        buildTestWidget(alertState: PriceAlertState(alerts: alerts)),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.byIcon(Icons.add_circle_outline), findsOneWidget);
      expect(find.byIcon(Icons.remove_circle_outline), findsOneWidget);
    });

    testWidgets('shows directional icons for support/resistance', (
      tester,
    ) async {
      widenViewport(tester);
      final alerts = [
        createAlert(id: 1, alertType: 'BREAK_RESISTANCE'),
        createAlert(id: 2, alertType: 'BREAK_SUPPORT', symbol: '2317'),
      ];
      await tester.pumpWidget(
        buildTestWidget(alertState: PriceAlertState(alerts: alerts)),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.byIcon(Icons.north_east), findsOneWidget);
      expect(find.byIcon(Icons.south_east), findsOneWidget);
    });

    testWidgets('shows emoji_events icon for 52-week high', (tester) async {
      widenViewport(tester);
      final alerts = [createAlert(alertType: 'WEEK_52_HIGH')];
      await tester.pumpWidget(
        buildTestWidget(alertState: PriceAlertState(alerts: alerts)),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.byIcon(Icons.emoji_events), findsOneWidget);
    });

    testWidgets('shows timeline icon for MA cross alerts', (tester) async {
      widenViewport(tester);
      final alerts = [createAlert(alertType: 'CROSS_ABOVE_MA')];
      await tester.pumpWidget(
        buildTestWidget(alertState: PriceAlertState(alerts: alerts)),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.byIcon(Icons.timeline), findsOneWidget);
    });

    testWidgets('shows analytics icon for fundamental alerts', (tester) async {
      widenViewport(tester);
      final alerts = [createAlert(alertType: 'REVENUE_YOY_SURGE')];
      await tester.pumpWidget(
        buildTestWidget(alertState: PriceAlertState(alerts: alerts)),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.byIcon(Icons.analytics), findsOneWidget);
    });

    testWidgets('shows warning icon for trading warning', (tester) async {
      widenViewport(tester);
      final alerts = [createAlert(alertType: 'TRADING_WARNING')];
      await tester.pumpWidget(
        buildTestWidget(alertState: PriceAlertState(alerts: alerts)),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.byIcon(Icons.warning_amber), findsOneWidget);
    });

    testWidgets('shows person icons for insider alerts', (tester) async {
      widenViewport(tester);
      final alerts = [
        createAlert(id: 1, alertType: 'INSIDER_SELLING'),
        createAlert(id: 2, alertType: 'INSIDER_BUYING', symbol: '2317'),
      ];
      await tester.pumpWidget(
        buildTestWidget(alertState: PriceAlertState(alerts: alerts)),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.byIcon(Icons.person_remove), findsOneWidget);
      expect(find.byIcon(Icons.person_add), findsOneWidget);
    });

    testWidgets('shows lock icon for high pledge ratio', (tester) async {
      widenViewport(tester);
      final alerts = [createAlert(alertType: 'HIGH_PLEDGE_RATIO')];
      await tester.pumpWidget(
        buildTestWidget(alertState: PriceAlertState(alerts: alerts)),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.byIcon(Icons.lock), findsOneWidget);
    });

    testWidgets('shows inactive alert without triggered state', (tester) async {
      widenViewport(tester);
      final alerts = [createAlert(isActive: false)];
      await tester.pumpWidget(
        buildTestWidget(alertState: PriceAlertState(alerts: alerts)),
      );
      await tester.pump(const Duration(seconds: 1));

      // Inactive non-triggered alert has a switch
      expect(find.byType(Switch), findsOneWidget);
    });
  });
}
