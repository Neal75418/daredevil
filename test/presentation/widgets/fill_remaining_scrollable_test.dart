import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/presentation/widgets/fill_remaining_scrollable.dart';

void main() {
  // 固定高度的方塊代表空狀態內容
  const block = SizedBox(key: Key('block'), width: 100, height: 300);

  Widget host(Widget child, {double height = 600}) => MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.topCenter,
        child: SizedBox(width: 400, height: height, child: child),
      ),
    ),
  );

  testWidgets('空間足夠：撐滿並垂直置中', (tester) async {
    await tester.pumpWidget(host(const FillRemainingScrollable(child: block)));

    final box = tester.getRect(find.byKey(const Key('block')));
    expect(box.height, 300, reason: '內容維持自身高度，不被撐大');
    expect(box.center.dy, closeTo(300, 0.5));
  });

  testWidgets('內容高於可用空間：不溢位、可捲到底', (tester) async {
    // 與 EmptyState 相同的 Column 結構：放不下時會回報 RenderFlex overflow
    await tester.pumpWidget(
      host(
        const FillRemainingScrollable(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [block],
          ),
        ),
        height: 200,
      ),
    );
    expect(tester.takeException(), isNull);

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -500));
    await tester.pump();
    final box = tester.getRect(find.byKey(const Key('block')));
    expect(box.bottom, closeTo(200, 0.5), reason: '捲到底後內容底邊貼齊可視區底');
  });

  testWidgets('放在 RefreshIndicator 內、內容未滿版時仍可下拉', (tester) async {
    var refreshed = 0;
    await tester.pumpWidget(
      host(
        RefreshIndicator(
          onRefresh: () async => refreshed++,
          child: const FillRemainingScrollable(child: block),
        ),
      ),
    );

    await tester.fling(
      find.byType(CustomScrollView),
      const Offset(0, 400),
      1000,
    );
    await tester.pumpAndSettle();
    expect(refreshed, 1);
  });

  testWidgets('傳入 controller 時、內容未滿版仍可下拉（不依賴 primary 預設）', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    var refreshed = 0;
    await tester.pumpWidget(
      host(
        RefreshIndicator(
          onRefresh: () async => refreshed++,
          child: FillRemainingScrollable(controller: controller, child: block),
        ),
      ),
    );

    await tester.fling(
      find.byType(CustomScrollView),
      const Offset(0, 400),
      1000,
    );
    await tester.pumpAndSettle();
    expect(refreshed, 1);
  });

  testWidgets('底部讓出 MediaQuery.padding.bottom（疊在上方的導覽列）', (tester) async {
    // 高 500：置中在整個 600 高 body 會壓到導覽列；讓出導覽列後才放得下
    const tall = SizedBox(key: Key('block'), width: 100, height: 500);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          extendBody: true,
          body: const FillRemainingScrollable(child: tall),
          bottomNavigationBar: NavigationBar(
            destinations: const [
              NavigationDestination(icon: Icon(Icons.home), label: 'a'),
              NavigationDestination(icon: Icon(Icons.list), label: 'b'),
            ],
          ),
        ),
      ),
    );

    final nav = tester.getRect(find.byType(NavigationBar));
    final box = tester.getRect(find.byKey(const Key('block')));
    expect(box.bottom, lessThanOrEqualTo(nav.top));
    expect(box.center.dy, closeTo(nav.top / 2, 0.5), reason: '在導覽列上方的空間置中');
  });

  testWidgets('頂部讓出 MediaQuery.padding.top（無 AppBar 頁的狀態列）', (tester) async {
    // 內容高於可用空間時從頂端排起，不得被狀態列蓋住
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: Size(800, 600),
            padding: EdgeInsets.only(top: 47),
          ),
          child: Scaffold(
            body: FillRemainingScrollable(
              child: SizedBox(key: Key('block'), width: 100, height: 700),
            ),
          ),
        ),
      ),
    );

    expect(tester.getRect(find.byKey(const Key('block'))).top, 47);
  });

  testWidgets('有 AppBar 時頂部不重複讓出狀態列', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(800, 600),
            padding: EdgeInsets.only(top: 47),
          ),
          child: Scaffold(
            appBar: AppBar(),
            body: const FillRemainingScrollable(
              child: SizedBox(key: Key('block'), width: 100, height: 700),
            ),
          ),
        ),
      ),
    );

    final appBarBottom = tester.getRect(find.byType(AppBar)).bottom;
    expect(tester.getRect(find.byKey(const Key('block'))).top, appBarBottom);
  });
}
