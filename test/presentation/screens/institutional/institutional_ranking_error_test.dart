// 法人排行:DB 錯誤不得畫成「暫無資料」(2026-08-29 靜默稽核 #9)
//
// provider 有把 error 寫進 state,但畫面沒讀——`ranking == null` 一律
// 渲染 EmptyState('instRanking.empty'),且該分支在 RefreshIndicator 之外
// 連下拉重試都沒有。同批的 revenue_overview_screen 有正確的 error 分支,
// 唯獨這頁漏。
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/presentation/providers/institutional_ranking_provider.dart';
import 'package:daredevil/presentation/screens/institutional/institutional_ranking_screen.dart';

import '../../../helpers/widget_test_helpers.dart';

class _FakeNotifier extends InstitutionalRankingNotifier {
  _FakeNotifier(this.initial);
  final InstitutionalRankingState initial;
  int loadCalls = 0;

  @override
  InstitutionalRankingState build() => initial;

  @override
  Future<void> loadData() async {
    loadCalls++;
  }
}

void main() {
  setUpAll(() async {
    await setupTestLocalization();
  });

  testWidgets('🚨 讀取失敗 → 顯示錯誤與重試,不得偽裝成「暫無資料」', (tester) async {
    final fake = _FakeNotifier(
      const InstitutionalRankingState(error: 'DB 爆炸', ranking: null),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [institutionalRankingProvider.overrideWith(() => fake)],
        child: buildTestApp(const InstitutionalRankingScreen()),
      ),
    );
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('DB 爆炸'), findsOneWidget, reason: '錯誤要說出來');
    expect(
      find.text('instRanking.empty'),
      findsNothing,
      reason: '「查詢失敗」與「今天沒資料」不得逐 pixel 相同',
    );

    // 錯誤分支要有重試入口(原本 EmptyState 在 RefreshIndicator 外,
    // 連下拉都不可達)
    final retry = find.text('common.retry');
    expect(retry, findsOneWidget);
    await tester.tap(retry);
    expect(fake.loadCalls, greaterThanOrEqualTo(1));
  });

  testWidgets('真的無資料(無錯誤)→ 照常顯示空狀態(對照組)', (tester) async {
    final fake = _FakeNotifier(const InstitutionalRankingState());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [institutionalRankingProvider.overrideWith(() => fake)],
        child: buildTestApp(const InstitutionalRankingScreen()),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('instRanking.empty'), findsOneWidget);
  });
}
