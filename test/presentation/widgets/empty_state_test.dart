import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/l10n/app_strings.dart';
import 'package:daredevil/core/theme/app_theme.dart';
import 'package:daredevil/presentation/widgets/empty_state.dart';

import '../../helpers/widget_test_helpers.dart';

void main() {
  setUpAll(() async {
    await setupTestLocalization();
  });

  void widenViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(5000, 8000);
    addTearDown(() => tester.view.resetPhysicalSize());
  }

  group('EmptyState', () {
    // 精簡版給放在頁面中段的空狀態（今日頁分頁沒訊號時）：完整版約 336 高，
    // 會把後面的區塊推出第一屏。內容不能少，只縮圖示與間距。
    testWidgets('精簡版比完整版矮，標題、說明、按鈕都保留', (tester) async {
      Future<double> heightOf({required bool compact}) async {
        await tester.pumpWidget(
          buildTestApp(
            // 放在清單裡（不限高度）量：與今日頁的用法一致，EmptyState
            // 依內容決定高度
            ListView(
              children: [
                EmptyState(
                  icon: Icons.inbox_outlined,
                  title: 'T',
                  subtitle: 'S',
                  actionLabel: 'A',
                  onAction: () {},
                  compact: compact,
                ),
              ],
            ),
          ),
        );
        await tester.pump(const Duration(seconds: 1));
        expect(find.text('T'), findsOneWidget);
        expect(find.text('S'), findsOneWidget);
        expect(find.text('A'), findsOneWidget);
        return tester.getSize(find.byType(EmptyState)).height;
      }

      final full = await heightOf(compact: false);
      final compact = await heightOf(compact: true);
      // 差值與字型無關：底圈 56＋上下內距 32＋兩處間距各 12
      expect(full - compact, moreOrLessEquals(112, epsilon: 0.5));
      // 圖示底圈仍是正圓（寬高同步縮）
      expect(
        tester.getSize(
          find
              .ancestor(
                of: find.byIcon(Icons.inbox_outlined),
                matching: find.byType(Container),
              )
              .first,
        ),
        const Size(64, 64),
      );
      expect(tester.widget<Icon>(find.byIcon(Icons.inbox_outlined)).size, 32);
    });

    testWidgets('displays icon and title', (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          const EmptyState(icon: Icons.inbox_outlined, title: 'No Data'),
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.byIcon(Icons.inbox_outlined), findsOneWidget);
      expect(find.text('No Data'), findsOneWidget);
    });

    testWidgets('displays subtitle when provided', (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          const EmptyState(
            icon: Icons.inbox_outlined,
            title: 'Empty',
            subtitle: 'Try again later',
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('Try again later'), findsOneWidget);
    });

    testWidgets('does not display subtitle when null', (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          const EmptyState(icon: Icons.inbox_outlined, title: 'Empty'),
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      // 只有 title，沒有多餘的 Text widget
      expect(find.text('Empty'), findsOneWidget);
    });

    testWidgets('shows action button when both label and callback provided', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildTestApp(
          EmptyState(
            icon: Icons.refresh,
            title: 'Error',
            actionLabel: 'Retry',
            onAction: () {},
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('Retry'), findsOneWidget);
      expect(find.byType(FilledButton), findsOneWidget);
    });

    testWidgets('does not show button when actionLabel is null', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildTestApp(
          EmptyState(icon: Icons.refresh, title: 'Error', onAction: () {}),
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(FilledButton), findsNothing);
    });

    testWidgets('does not show button when onAction is null', (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          const EmptyState(
            icon: Icons.refresh,
            title: 'Error',
            actionLabel: 'Retry',
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(FilledButton), findsNothing);
    });

    testWidgets('action button triggers callback', (tester) async {
      var callbackInvoked = false;

      await tester.pumpWidget(
        buildTestApp(
          EmptyState(
            icon: Icons.refresh,
            title: 'Error',
            actionLabel: 'Retry',
            onAction: () => callbackInvoked = true,
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      await tester.tap(find.text('Retry'));
      expect(callbackInvoked, isTrue);
    });

    testWidgets('has accessibility semantics wrapper', (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          const EmptyState(
            icon: Icons.inbox_outlined,
            title: 'No Data',
            subtitle: 'Check back later',
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(
        find.bySemanticsLabel('No Data, Check back later'),
        findsOneWidget,
      );
    });

    testWidgets('renders in dark mode', (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          const EmptyState(icon: Icons.inbox_outlined, title: 'Dark Mode Test'),
          brightness: Brightness.dark,
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('Dark Mode Test'), findsOneWidget);
    });

    testWidgets('applies custom iconColor', (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          const EmptyState(
            icon: Icons.star,
            title: 'Custom Color',
            iconColor: Colors.amber,
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.byIcon(Icons.star), findsOneWidget);
    });
  });

  group('EmptyStates factory methods', () {
    testWidgets('noRecommendations shows correct icon and title', (
      tester,
    ) async {
      await tester.pumpWidget(buildTestApp(EmptyStates.noRecommendations()));
      await tester.pump(const Duration(seconds: 1));

      expect(find.byIcon(Icons.inbox_outlined), findsOneWidget);
      expect(find.text(S.emptyNoRecommendations), findsOneWidget);
    });

    testWidgets('noRecommendations with onRefresh shows button', (
      tester,
    ) async {
      var refreshed = false;
      await tester.pumpWidget(
        buildTestApp(
          EmptyStates.noRecommendations(onRefresh: () => refreshed = true),
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.text(S.refresh), findsOneWidget);
      await tester.tap(find.text(S.refresh));
      expect(refreshed, isTrue);
    });

    testWidgets('noFilterResults shows search_off icon', (tester) async {
      await tester.pumpWidget(buildTestApp(EmptyStates.noFilterResults()));
      await tester.pump(const Duration(seconds: 1));

      expect(find.byIcon(Icons.search_off_outlined), findsOneWidget);
      expect(find.text(S.emptyNoFilterResults), findsOneWidget);
    });

    testWidgets('emptyWatchlist shows star icon', (tester) async {
      await tester.pumpWidget(buildTestApp(EmptyStates.emptyWatchlist()));
      await tester.pump(const Duration(seconds: 1));

      expect(find.byIcon(Icons.star_outline_rounded), findsOneWidget);
      expect(find.text(S.emptyNoWatchlist), findsOneWidget);
    });

    testWidgets('noNews shows article icon', (tester) async {
      await tester.pumpWidget(buildTestApp(EmptyStates.noNews()));
      await tester.pump(const Duration(seconds: 1));

      expect(find.byIcon(Icons.article_outlined), findsOneWidget);
      expect(find.text(S.emptyNoNews), findsOneWidget);
    });

    testWidgets('error shows error icon and message', (tester) async {
      await tester.pumpWidget(
        buildTestApp(EmptyStates.error(message: 'Something went wrong')),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
      expect(find.text(S.emptyError), findsOneWidget);
      expect(find.text('Something went wrong'), findsOneWidget);
    });

    testWidgets('error with onRetry shows retry button', (tester) async {
      var retried = false;
      await tester.pumpWidget(
        buildTestApp(
          EmptyStates.error(message: 'Oops', onRetry: () => retried = true),
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.text(S.retry), findsOneWidget);
      await tester.tap(find.text(S.retry));
      expect(retried, isTrue);
    });

    testWidgets('networkError shows wifi_off icon', (tester) async {
      await tester.pumpWidget(buildTestApp(EmptyStates.networkError()));
      await tester.pump(const Duration(seconds: 1));

      expect(find.byIcon(Icons.wifi_off_rounded), findsOneWidget);
      expect(find.text(S.emptyNetworkError), findsOneWidget);
    });
  });

  group('EmptyStateWithMeta', () {
    testWidgets('shows filter icon and condition description', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(
        buildTestApp(
          EmptyStates.noFilterResultsWithMeta(
            filterName: 'Test Filter',
            conditionDescription: 'Score > 80',
            dataRequirements: ['收盤價'],
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.byIcon(Icons.filter_alt_off_outlined), findsOneWidget);
      expect(find.text('Score > 80'), findsOneWidget);
    });

    testWidgets('淺色主題資料需求標籤文字色為 onSurface（非 onSecondaryContainer）', (
      tester,
    ) async {
      // 底色是 secondaryContainer 疊 60% alpha，非實心；onSecondaryContainer
      // 對這個合成色只有 3.09:1，不合格，故改用 onSurface（5.52:1）。
      await tester.pumpWidget(
        buildTestApp(
          EmptyStates.noFilterResultsWithMeta(
            filterName: 'Test Filter',
            conditionDescription: 'Score > 80',
            dataRequirements: ['收盤價'],
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      final tagText = tester.widget<Text>(find.text('收盤價'));
      expect(tagText.style?.color, AppTheme.lightTheme.colorScheme.onSurface);
      expect(
        tagText.style?.color,
        isNot(AppTheme.lightTheme.colorScheme.onSecondaryContainer),
      );
    });

    testWidgets('深色主題資料需求標籤文字色維持 onSecondaryContainer', (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          EmptyStates.noFilterResultsWithMeta(
            filterName: 'Test Filter',
            conditionDescription: 'Score > 80',
            dataRequirements: ['收盤價'],
          ),
          brightness: Brightness.dark,
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      final tagText = tester.widget<Text>(find.text('收盤價'));
      expect(
        tagText.style?.color,
        AppTheme.darkTheme.colorScheme.onSecondaryContainer,
      );
    });

    testWidgets('shows threshold info when provided', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(
        buildTestApp(
          EmptyStates.noFilterResultsWithMeta(
            filterName: 'Volume',
            conditionDescription: 'Volume > average',
            dataRequirements: [],
            thresholdInfo: '> 1,000,000',
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('> 1,000,000'), findsOneWidget);
    });

    testWidgets('hides threshold info when null', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(
        buildTestApp(
          EmptyStates.noFilterResultsWithMeta(
            filterName: 'Score',
            conditionDescription: 'High score',
            dataRequirements: [],
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('High score'), findsOneWidget);
    });

    testWidgets('shows expand button when hasDetails', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(
        buildTestApp(
          EmptyStates.noFilterResultsWithMeta(
            filterName: 'Test',
            conditionDescription: 'Test condition',
            dataRequirements: ['Price data'],
            totalScanned: 1500,
            dataDate: DateTime(2026, 2, 13),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.byIcon(Icons.expand_more), findsOneWidget);
    });

    testWidgets('expand reveals diagnostic icons', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(
        buildTestApp(
          EmptyStates.noFilterResultsWithMeta(
            filterName: 'Test',
            conditionDescription: 'Test',
            dataRequirements: ['Price'],
            totalScanned: 1500,
            dataDate: DateTime(2026, 2, 13),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      await tester.tap(find.byIcon(Icons.expand_more));
      await tester.pump(const Duration(seconds: 1));

      expect(find.byIcon(Icons.calendar_today_outlined), findsOneWidget);
      expect(find.byIcon(Icons.analytics_outlined), findsOneWidget);
    });

    testWidgets('expand reveals data requirements chips', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(
        buildTestApp(
          EmptyStates.noFilterResultsWithMeta(
            filterName: 'Test',
            conditionDescription: 'Test',
            dataRequirements: ['收盤價', '成交量'],
            totalScanned: 1000,
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      await tester.tap(find.byIcon(Icons.expand_more));
      await tester.pump(const Duration(seconds: 1));

      expect(find.byIcon(Icons.storage_outlined), findsOneWidget);
      expect(find.text('收盤價'), findsOneWidget);
      expect(find.text('成交量'), findsOneWidget);
    });

    testWidgets('shows clear filter button when callback provided', (
      tester,
    ) async {
      widenViewport(tester);
      var cleared = false;
      await tester.pumpWidget(
        buildTestApp(
          EmptyStates.noFilterResultsWithMeta(
            filterName: 'Test',
            conditionDescription: 'Test',
            dataRequirements: [],
            onClearFilter: () => cleared = true,
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(FilledButton), findsOneWidget);
      await tester.tap(find.byType(FilledButton));
      expect(cleared, isTrue);
    });

    testWidgets('hides clear filter button when no callback', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(
        buildTestApp(
          EmptyStates.noFilterResultsWithMeta(
            filterName: 'Test',
            conditionDescription: 'Test',
            dataRequirements: [],
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(FilledButton), findsNothing);
    });

    testWidgets('renders in dark mode', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(
        buildTestApp(
          EmptyStates.noFilterResultsWithMeta(
            filterName: 'Dark Filter',
            conditionDescription: 'Dark condition',
            dataRequirements: ['Data'],
            thresholdInfo: '> 100',
            totalScanned: 500,
            dataDate: DateTime(2026, 2, 13),
            onClearFilter: () {},
          ),
          brightness: Brightness.dark,
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.byIcon(Icons.filter_alt_off_outlined), findsOneWidget);
    });
  });

  group('圖示色主題盲守門（C5）', () {
    // EmptyState 的 56px 圖示以 alpha 0.7 疊在自身 alpha 0.1 漸層底之上，
    // 該底又疊在 scaffold（淺色 #FFFFFF）之上。iconColor 曾寫死
    // AppTheme.primaryColor（#A78BFA）——實際畫出來的圖示合成色對頁面白底
    // 只有 2.02:1，比改動前的 #2196F3（2.28:1）更差。改為不傳 iconColor、
    // 由 build 落回 theme.colorScheme.primary 後，淺色解析為 #6D28D9，
    // 合成後 4.10:1。
    //
    // 斷言對象是「Icon 實際拿到的 color」是否等於主題解析值，這條會在
    // 有人把寫死的常數放回 iconColor 時變紅。
    Future<Color> iconColorOf(
      WidgetTester tester,
      Widget widget,
      IconData icon,
      Brightness brightness,
    ) async {
      widenViewport(tester);
      await tester.pumpWidget(buildTestApp(widget, brightness: brightness));
      await tester.pump(const Duration(seconds: 1));
      return tester.widget<Icon>(find.byIcon(icon)).color!;
    }

    for (final brightness in Brightness.values) {
      testWidgets('品牌類空狀態圖示取自主題 primary（$brightness）', (tester) async {
        final expected =
            (brightness == Brightness.light
                    ? AppTheme.lightTheme
                    : AppTheme.darkTheme)
                .colorScheme
                .primary;

        for (final w in [
          EmptyStates.noRecommendations(),
          EmptyStates.noNews(),
        ]) {
          final c = await iconColorOf(
            tester,
            w,
            w is EmptyState ? w.icon : Icons.inbox_outlined,
            brightness,
          );
          expect(
            c.withValues(alpha: 1.0),
            expected,
            reason: '空狀態圖示不得寫死主題盲的 AppTheme.primaryColor',
          );
        }
      });

      testWidgets('中性類空狀態圖示取自依主題解析的平盤灰（$brightness）', (tester) async {
        final c = await iconColorOf(
          tester,
          EmptyStates.noFilterResults(),
          Icons.search_off_outlined,
          brightness,
        );
        expect(
          c.withValues(alpha: 1.0),
          AppTheme.getFlatColor(brightness),
          reason: '「無篩選結果」圖示應為依主題解析的平盤灰，非固定深色值',
        );
      });
    }
  });
}
