// 共用底部面板：一律開在最上層導覽器，蓋住底部導覽列（2026-09-26 定案）。
//
// 分頁內的面板若開在分頁自己的導覽器，導覽列不被遮住、開著也能切分頁，
// 切回來時面板還開著（被留在那個分頁的導覽器裡）。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:daredevil/core/theme/breakpoints.dart';
import 'package:daredevil/presentation/widgets/app_bottom_sheet.dart';

void main() {
  testWidgets('從內層導覽器開啟時，面板開在最上層導覽器', (tester) async {
    final innerKey = GlobalKey<NavigatorState>();
    final rootKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: rootKey,
        home: Scaffold(
          body: Navigator(
            key: innerKey,
            onGenerateRoute: (_) => MaterialPageRoute<void>(
              builder: (context) => Center(
                child: TextButton(
                  onPressed: () => showAppBottomSheet<void>(
                    context: context,
                    builder: (_) => const Text('sheet'),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
          bottomNavigationBar: const SizedBox(height: 80, child: Text('nav')),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('sheet'), findsOneWidget);
    expect(innerKey.currentState!.canPop(), isFalse);
    expect(rootKey.currentState!.canPop(), isTrue);
    // 遮罩延伸到畫面最底（此簡化版面下，開在內層導覽器時只到導覽列上方；
    // 實際 AppShell 用 extendBody，兩者都到底，由下一個測試驗使用者症狀）
    final screenHeight =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;
    final barrier = tester.getRect(find.byType(ModalBarrier).last);
    expect(barrier.bottom, screenHeight);
  });

  // 與 AppShell 相同結構（go_router 分頁殼層＋extendBody）：面板開著時點
  // 導覽列不會切分頁（遮罩吃掉點擊、只關面板）。開在分頁導覽器時會切走，
  // 切回來面板還開著——這就是要消除的症狀
  testWidgets('分頁殼層下，面板開著時點導覽列不切分頁、只關面板', (tester) async {
    final selected = <int>[];
    final router = GoRouter(
      initialLocation: '/a',
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (context, state, shell) => Scaffold(
            extendBody: true,
            body: shell,
            bottomNavigationBar: NavigationBar(
              selectedIndex: shell.currentIndex,
              onDestinationSelected: (i) {
                selected.add(i);
                shell.goBranch(i);
              },
              destinations: const [
                NavigationDestination(icon: Icon(Icons.home), label: 'A'),
                NavigationDestination(icon: Icon(Icons.search), label: 'B'),
              ],
            ),
          ),
          branches: [
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/a',
                  builder: (context, _) => Center(
                    child: TextButton(
                      onPressed: () => showAppBottomSheet<void>(
                        context: context,
                        builder: (_) => const Text('sheet'),
                      ),
                      child: const Text('open'),
                    ),
                  ),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(path: '/b', builder: (_, _) => const Text('page B')),
              ],
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('B'), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(selected, isEmpty);
    expect(find.text('sheet'), findsNothing); // 點遮罩關掉了面板
    expect(find.text('open'), findsOneWidget); // 仍在原分頁
  });

  testWidgets('寬視窗下限寬（桌面不撐滿全寬）', (tester) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        // 主題不限寬：Material 3 預設就限 640，不拿掉會驗不到本函式自己的限寬
        theme: ThemeData(
          bottomSheetTheme: const BottomSheetThemeData(
            constraints: BoxConstraints(),
          ),
        ),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showAppBottomSheet<void>(
              context: context,
              builder: (_) =>
                  const SizedBox(width: double.infinity, child: Text('sheet')),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // 內容想撐滿寬度（width: infinity），實際拿到的寬度就是面板寬
    final content = find.ancestor(
      of: find.text('sheet'),
      matching: find.byType(SizedBox),
    );
    expect(tester.getSize(content.first).width, Breakpoints.sheetMaxWidth);
  });

  testWidgets('其餘參數照原樣轉交', (tester) async {
    late BuildContext sheetContext;
    const shape = RoundedRectangleBorder();
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showAppBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              useSafeArea: true,
              showDragHandle: true,
              backgroundColor: Colors.teal,
              shape: shape,
              builder: (c) {
                sheetContext = c;
                return const Text('sheet');
              },
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final route = ModalRoute.of(sheetContext)! as ModalBottomSheetRoute<void>;
    expect(route.isScrollControlled, isTrue);
    expect(route.useSafeArea, isTrue);
    expect(route.showDragHandle, isTrue);
    expect(route.backgroundColor, Colors.teal);
    expect(route.shape, shape);
  });

  // 守門：新增面板若直接呼叫原生 API，會繞過上面兩條規則
  test('lib/ 只有共用函式直接呼叫 showModalBottomSheet', () {
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();
    expect(files.length, greaterThan(100)); // 列舉失敗時不空轉通過
    // 去掉註解再比對：抓呼叫、tear-off 與直接建 route，註解提到名稱不算
    final pattern = RegExp(r'\b(showModalBottomSheet|ModalBottomSheetRoute)\b');
    String code(File f) => f
        .readAsLinesSync()
        .map((l) => l.replaceFirst(RegExp(r'//.*'), ''))
        .join('\n');
    final offenders = [
      for (final f in files)
        if (f.path != 'lib/presentation/widgets/app_bottom_sheet.dart' &&
            pattern.hasMatch(code(f)))
          f.path,
    ];
    expect(offenders, isEmpty);
  });
}
