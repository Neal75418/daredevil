import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/presentation/providers/scan_provider.dart';
import 'package:daredevil/presentation/providers/settings_provider.dart';
import 'package:daredevil/presentation/screens/scan/scan_screen.dart';

import '../../../helpers/phone_layout_helpers.dart';
import '../../../helpers/provider_test_helpers.dart';
import '../../../helpers/widget_test_helpers.dart';

// 掃描頁「篩選無結果（附條件說明）」以真實 zh-TW 翻譯驗版面：卡片含水平
// 排列的標籤列，key 字串比中文長會假性溢位。真實翻譯寫入全域
// Localization.instance、會污染同檔其他測試，故獨立成檔。

class _FakeScanNotifier extends ScanNotifier {
  _FakeScanNotifier(this.initial);

  final ScanState initial;
  int loadDataCalls = 0;

  @override
  ScanState build() => initial;

  @override
  Future<void> loadData() async => loadDataCalls++;
}

class _FakeSettingsNotifier extends SettingsNotifier {
  @override
  SettingsState build() => const SettingsState();
}

void main() {
  setUpAll(() async {
    await setupTestLocalization();
  });

  final withMeta = ScanState(
    dataDate: DateTime(2026, 9, 18),
    totalAnalyzedCount: 1972,
    filter: ScanFilter.values.firstWhere((f) => f != ScanFilter.all),
  );

  late _FakeScanNotifier notifier;

  Future<void> pumpWithMeta(WidgetTester tester, PhoneScenario s) async {
    applyPhoneScenario(tester, s);
    notifier = _FakeScanNotifier(withMeta);
    await tester.pumpWidget(
      buildProviderTestApp(
        inPhoneShell(const ScanScreen()),
        overrides: [
          scanProvider.overrideWith(() => notifier),
          settingsProvider.overrideWith(_FakeSettingsNotifier.new),
        ],
        zhTranslations: true,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('觸發條件'), findsOneWidget, reason: '前提：真實翻譯已載入');
  }

  for (final scenario in phoneScenarios) {
    testWidgets('$scenario 不溢位、清除篩選按鈕不被導覽列蓋住', (tester) async {
      await pumpWithMeta(tester, scenario);

      expect(tester.takeException(), isNull);
      await expectAboveNavBar(tester, find.byType(FilledButton).last);
    });

    testWidgets('$scenario 展開「更多詳情」後不溢位', (tester) async {
      await pumpWithMeta(tester, scenario);

      await tester.ensureVisible(find.text('更多詳情'));
      await tester.pump();
      await tester.tap(find.text('更多詳情'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(
        find.textContaining('1,972'),
        findsOneWidget,
        reason: '前提：已展開（掃描檔數顯示在展開區）',
      );
      expect(tester.takeException(), isNull);
      await expectAboveNavBar(tester, find.byType(FilledButton).last);
    });
  }

  testWidgets('從內容上方的空白處也能下拉重新整理', (tester) async {
    // 390×844、字級 1.0：內容放得下，上方留有空白
    await pumpWithMeta(
      tester,
      const PhoneScenario(
        '390×844、字級 1.0',
        Size(390, 844),
        dpr: 3,
        textScale: 1.0,
        paddingTop: 47,
        paddingBottom: 34,
      ),
    );
    final before = notifier.loadDataCalls;

    final area = tester.getRect(find.byType(CustomScrollView).last);
    final start = Offset(area.center.dx, area.top + 8);
    // 內容最上方是 100×100 的圓形圖示容器
    final contentTop = tester
        .getRect(
          find
              .ancestor(
                of: find
                    .descendant(
                      of: find.byType(CustomScrollView).last,
                      matching: find.byType(Icon),
                    )
                    .first,
                matching: find.byWidgetPredicate(
                  (w) =>
                      w is Container &&
                      w.constraints?.maxWidth == 100 &&
                      w.constraints?.maxHeight == 100,
                ),
              )
              .first,
        )
        .top;
    expect(start.dy, lessThan(contentTop - 24), reason: '前提：起點落在內容上方的空白處');

    await tester.flingFrom(start, const Offset(0, 400), 1000);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(notifier.loadDataCalls, greaterThan(before));
  });
}
