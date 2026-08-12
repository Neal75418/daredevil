// 管理分組 sheet 的預設分組星標(2026-08-12)
//
// 星標是預設分組功能**唯一的 UI 入口**:DAO 與 provider 各自有測試,但
// 「tap → setDefaultGroup(null/id) 的 toggle 判斷」這段線頭沒人接——
// 反轉了照樣全綠,正是「全套綠≠可用」的形狀。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/presentation/providers/watchlist_provider.dart';
import 'package:daredevil/presentation/screens/watchlist/watchlist_group_sheets.dart';

import '../../../helpers/provider_test_helpers.dart';
import '../../../helpers/widget_test_helpers.dart';

/// 記錄 setDefaultGroup 呼叫,並模擬真 notifier 的 _reloadGroups(更新旗標)
class RecordingWatchlistNotifier extends WatchlistNotifier {
  WatchlistState initialState = WatchlistState();
  final List<int?> setDefaultCalls = [];

  @override
  WatchlistState build() => initialState;

  @override
  Future<void> loadData() async {}

  @override
  Future<void> setDefaultGroup(int? id) async {
    setDefaultCalls.add(id);
    state = state.copyWith(
      groups: [for (final g in state.groups) g.copyWith(isDefault: g.id == id)],
    );
  }
}

WatchlistGroupEntry groupEntry(int id, String name, {bool isDefault = false}) =>
    WatchlistGroupEntry(
      id: id,
      name: name,
      sortOrder: id,
      isDefault: isDefault,
      createdAt: DateTime(2026, 8, 1),
    );

void main() {
  setUpAll(() async => setupTestLocalization());

  late RecordingWatchlistNotifier notifier;

  Widget app(List<WatchlistGroupEntry> groups) => buildProviderTestApp(
    Consumer(
      builder: (context, ref, _) => Center(
        child: ElevatedButton(
          onPressed: () => showManageGroupsSheet(context: context, ref: ref),
          child: const Text('open'),
        ),
      ),
    ),
    overrides: [
      watchlistProvider.overrideWith(() {
        notifier = RecordingWatchlistNotifier()
          ..initialState = WatchlistState(groups: groups);
        return notifier;
      }),
    ],
  );

  Future<void> openSheet(WidgetTester tester) async {
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('未設預設:全部空心星、無 folder_special、無提示字', (tester) async {
    await tester.pumpWidget(app([groupEntry(1, '強者榜'), groupEntry(2, '備取觀察')]));
    await openSheet(tester);

    expect(find.byIcon(Icons.star_outline), findsNWidgets(2));
    expect(find.byIcon(Icons.star), findsNothing);
    expect(find.byIcon(Icons.folder_special), findsNothing);
    expect(find.text('watchlist.defaultGroupHint'), findsNothing);
  });

  testWidgets('🚨 點空心星 → setDefaultGroup(該組 id),UI 立即實星+提示', (tester) async {
    await tester.pumpWidget(app([groupEntry(1, '強者榜'), groupEntry(2, '備取觀察')]));
    await openSheet(tester);

    // 兩顆空心星依 ListView 順序排:第一顆屬於「強者榜」(id=1)
    await tester.tap(find.byIcon(Icons.star_outline).first);
    await tester.pumpAndSettle();

    expect(notifier.setDefaultCalls, [1], reason: '必須帶該組 id,不是 null');
    expect(find.byIcon(Icons.star), findsOneWidget, reason: '設定後立即反映');
    expect(find.byIcon(Icons.star_outline), findsOneWidget);
    expect(find.byIcon(Icons.folder_special), findsOneWidget);
    // 測試環境不載入翻譯,.tr() 渲染原始 key
    expect(find.text('watchlist.defaultGroupHint'), findsOneWidget);
  });

  testWidgets('🚨 點已預設的實星 → setDefaultGroup(null) 取消', (tester) async {
    await tester.pumpWidget(
      app([groupEntry(1, '強者榜', isDefault: true), groupEntry(2, '備取觀察')]),
    );
    await openSheet(tester);

    await tester.tap(find.byIcon(Icons.star));
    await tester.pumpAndSettle();

    expect(notifier.setDefaultCalls, [
      null,
    ], reason: '再點一次是「取消預設」——傳回原 id 會變成 no-op 的假 toggle');
    expect(find.byIcon(Icons.star), findsNothing);
    expect(find.byIcon(Icons.star_outline), findsNWidgets(2));
    expect(find.text('watchlist.defaultGroupHint'), findsNothing);
  });
}
