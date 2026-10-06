import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/presentation/providers/news_fetch_provider.dart';
import 'package:daredevil/presentation/widgets/news/news_widgets.dart';

import '../../../helpers/time_zone_helpers.dart';
import '../../../helpers/widget_test_helpers.dart';

NewsItemEntry item(String id) => NewsItemEntry(
  id: id,
  source: '鉅亨網',
  title: '標題$id',
  url: 'https://example.com/$id',
  category: 'OTHER',
  publishedAt: DateTime.now(),
  fetchedAt: DateTime.now(),
);

void main() {
  setUpAll(() async => setupTestLocalization());

  testWidgets('股票標籤最多 3 個，其餘收成 +N；點標籤回呼代碼', (tester) async {
    final tapped = <String>[];
    await tester.pumpWidget(
      buildTestApp(
        NewsListItem(
          item: item('n1'),
          relatedStocks: const ['9901', '9902', '9903', '9904', '9905'],
          onTap: (_, _) {},
          onStockTap: tapped.add,
        ),
      ),
    );

    expect(find.text('9903'), findsOneWidget);
    expect(find.text('9904'), findsNothing);
    expect(find.text('+2'), findsOneWidget);
    await tester.tap(find.text('9902'));
    expect(tapped, ['9902']);
  });

  final now = DateTime.now();
  final old = now.subtract(const Duration(days: 10));
  final crossOld = crossDayLocal(old.year, old.month, old.day);

  testWidgets(
    '超過 7 天的列表日期用本地日期（個股頁 30 天清單會碰到）',
    (tester) async {
      final at = crossOld!.toUtc();
      await tester.pumpWidget(
        buildTestApp(
          NewsListItem(
            item: NewsItemEntry(
              id: 'o',
              source: '鉅亨網',
              title: '舊聞',
              url: 'https://example.com/o',
              category: 'OTHER',
              publishedAt: at,
              fetchedAt: at,
            ),
            relatedStocks: const [],
            onTap: (_, _) {},
            onStockTap: (_) {},
          ),
        ),
      );
      final expected = old.year == now.year
          ? '${old.month}/${old.day}'
          : '${old.year}/${old.month}/${old.day}';
      expect(find.text(expected), findsOneWidget);
    },
    skip: crossOld == null, // UTC 時區驗不到跨日（testWidgets 的 skip 只收 bool）
  );

  Future<SnackBar?> feedbackOf(
    WidgetTester tester,
    NewsFetchOutcome outcome,
  ) async {
    await tester.pumpWidget(
      buildTestApp(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showNewsFetchFeedback(
              ScaffoldMessenger.of(context),
              outcome,
              errorColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('go'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pump();
    final bars = tester.widgetList<SnackBar>(find.byType(SnackBar));
    return bars.isEmpty ? null : bars.single;
  }

  testWidgets('部分來源失敗：一般樣式提示失敗來源數', (tester) async {
    final bar = await feedbackOf(
      tester,
      const NewsFetchOutcome(totalSources: 5, failedSources: 2),
    );
    expect(bar, isNotNull);
    expect(find.text('news.fetchPartialFailed'), findsOneWidget);
    expect(bar!.backgroundColor, isNull);
  });

  testWidgets('全部來源失敗：錯誤樣式提示', (tester) async {
    final bar = await feedbackOf(
      tester,
      const NewsFetchOutcome(totalSources: 5, failedSources: 5),
    );
    expect(find.text('news.fetchAllFailed'), findsOneWidget);
    expect(bar!.backgroundColor, isNotNull);
  });

  testWidgets('抓取全部成功時不跳提示', (tester) async {
    await tester.pumpWidget(
      buildTestApp(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showNewsFetchFeedback(
              ScaffoldMessenger.of(context),
              const NewsFetchOutcome(totalSources: 5, failedSources: 0),
              errorColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('go'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pump();
    expect(find.byType(SnackBar), findsNothing);
  });
}
