import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/presentation/providers/event_calendar_provider.dart';
import 'package:daredevil/presentation/screens/calendar/event_calendar_screen.dart';
import 'package:daredevil/presentation/widgets/empty_state.dart';

import '../../../helpers/phone_layout_helpers.dart';
import '../../../helpers/provider_test_helpers.dart';
import '../../../helpers/widget_test_helpers.dart';

// 行事曆錯誤頁以真實 zh-TW 翻譯驗版面：頁首有多個水平排列的標籤，key 字串
// 比中文長會假性水平溢位。真實翻譯寫入全域 Localization.instance、會污染
// 同檔其他測試，故獨立成檔。

class _FakeEventCalendarNotifier extends EventCalendarNotifier {
  _FakeEventCalendarNotifier(this.initial);

  final EventCalendarState initial;

  @override
  EventCalendarState build() => initial;

  @override
  Future<void> init() async {}

  @override
  Future<bool> loadMonthEvents(DateTime month) async => true;

  @override
  void selectDate(DateTime date) {}
}

void main() {
  setUpAll(() async {
    await setupTestLocalization();
  });

  // 390×844 字級 1.0／2.0 走「月曆下方 Expanded」路徑；iPhone SE 各字級因
  // 高度不足走「整頁捲動」退路
  const expandedPath = [
    PhoneScenario(
      '390×844、字級 1.0',
      Size(390, 844),
      dpr: 3,
      textScale: 1.0,
      paddingTop: 47,
      paddingBottom: 34,
    ),
    PhoneScenario(
      '390×844、字級 2.0',
      Size(390, 844),
      dpr: 3,
      textScale: 2.0,
      paddingTop: 47,
      paddingBottom: 34,
    ),
  ];

  Future<void> pumpCalendar(
    WidgetTester tester,
    PhoneScenario scenario,
    String error,
  ) async {
    applyPhoneScenario(tester, scenario);
    await tester.pumpWidget(
      buildProviderTestApp(
        EventCalendarScreen(initialFocusedDay: DateTime(2026, 9, 18)),
        overrides: [
          eventCalendarProvider.overrideWith(
            () => _FakeEventCalendarNotifier(EventCalendarState(error: error)),
          ),
        ],
        zhTranslations: true,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  for (final error in ['Database error', 'Network error']) {
    for (final scenario in [...phoneScenarios, ...expandedPath]) {
      // 390×844 字級 3.0：行事曆頁本身（非錯誤頁）就溢位——窄版以固定高度
      // 常數判斷是否轉捲動，未計入字級放大；無錯誤的正常狀態同樣溢位 117px
      final pageOverflowsRegardless =
          scenario.size.height == 844 && scenario.textScale == 3.0;
      testWidgets('$error：$scenario 錯誤頁不溢位', skip: pageOverflowsRegardless, (
        tester,
      ) async {
        await pumpCalendar(tester, scenario, error);

        expect(tester.takeException(), isNull);
        expect(find.byType(EmptyState), findsOneWidget);
      });
    }
  }

  testWidgets('整頁捲動退路：錯誤頁以自然高度排入，不再包一層捲動區', (tester) async {
    await pumpCalendar(tester, phoneScenarios.first, 'Database error');

    final errorView = find.byType(EmptyState);
    expect(errorView, findsOneWidget);
    expect(
      find.ancestor(of: errorView, matching: find.byType(CustomScrollView)),
      findsNothing,
      reason: '外層已可捲動，內嵌固定高的捲動小窗會讓錯誤頁擠在裡面',
    );
    await tester.ensureVisible(find.text('重試'));
    expect(tester.takeException(), isNull);
  });
}
