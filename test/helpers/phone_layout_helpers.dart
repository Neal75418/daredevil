import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 真實手機版面情境。App 鎖定直放（lib/main.dart 的
/// `setPreferredOrientations`、iOS Info.plist），不測橫放；字級上限依
/// iOS 輔助使用大字（約 3 倍）。
class PhoneScenario {
  const PhoneScenario(
    this.name,
    this.size, {
    required this.dpr,
    required this.textScale,
    required this.paddingTop,
    required this.paddingBottom,
  });

  final String name;

  /// 邏輯尺寸
  final Size size;
  final double dpr;
  final double textScale;

  /// 狀態列／瀏海與 home indicator（邏輯像素）
  final double paddingTop;
  final double paddingBottom;

  @override
  String toString() => name;
}

const phoneScenarios = [
  PhoneScenario(
    'iPhone SE、字級 1.0',
    Size(375, 667),
    dpr: 2,
    textScale: 1.0,
    paddingTop: 20,
    paddingBottom: 0,
  ),
  PhoneScenario(
    'iPhone SE、字級 2.0',
    Size(375, 667),
    dpr: 2,
    textScale: 2.0,
    paddingTop: 20,
    paddingBottom: 0,
  ),
  PhoneScenario(
    'iPhone SE、字級 3.0',
    Size(375, 667),
    dpr: 2,
    textScale: 3.0,
    paddingTop: 20,
    paddingBottom: 0,
  ),
  PhoneScenario(
    '390×844、字級 3.0',
    Size(390, 844),
    dpr: 3,
    textScale: 3.0,
    paddingTop: 47,
    paddingBottom: 34,
  ),
];

/// 套用情境到測試 view，tearDown 時還原
void applyPhoneScenario(WidgetTester tester, PhoneScenario s) {
  tester.view
    ..devicePixelRatio = s.dpr
    ..physicalSize = s.size * s.dpr
    ..padding = FakeViewPadding(
      top: s.paddingTop * s.dpr,
      bottom: s.paddingBottom * s.dpr,
    );
  tester.platformDispatcher.textScaleFactorTestValue = s.textScale;
  addTearDown(() {
    tester.view
      ..resetDevicePixelRatio()
      ..resetPhysicalSize()
      ..resetPadding();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
  });
}

/// 比照 AppShell 的手機版面：底部導覽列以 extendBody 疊在分頁內容上
Widget inPhoneShell(Widget tab) => Scaffold(
  extendBody: true,
  body: tab,
  bottomNavigationBar: NavigationBar(
    destinations: const [
      NavigationDestination(icon: Icon(Icons.home), label: 'a'),
      NavigationDestination(icon: Icon(Icons.list), label: 'b'),
    ],
  ),
);

/// 捲到底後，[target] 必須完整位於底部導覽列上方（沒被疊住）
Future<void> expectAboveNavBar(WidgetTester tester, Finder target) async {
  final scrollable = find.ancestor(
    of: target,
    matching: find.byType(Scrollable),
  );
  if (scrollable.evaluate().isNotEmpty) {
    await tester.drag(scrollable.first, const Offset(0, -2000));
    // EmptyState 有循環動畫，pumpAndSettle 等不到靜止
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }
  final nav = tester.getRect(find.byType(NavigationBar));
  expect(tester.getRect(target).bottom, lessThanOrEqualTo(nav.top + 0.5));
}
