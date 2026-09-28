import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/presentation/providers/industry_eps_provider.dart';
import 'package:daredevil/presentation/providers/news_provider.dart';
import 'package:daredevil/presentation/providers/short_sell_ranking_provider.dart';
import 'package:daredevil/presentation/screens/industry/industry_eps_screen.dart';
import 'package:daredevil/presentation/screens/news/news_screen.dart';
import 'package:daredevil/presentation/screens/short_sell/short_sell_ranking_screen.dart';
import 'package:daredevil/presentation/widgets/empty_state.dart';

import '../../helpers/phone_layout_helpers.dart';
import '../../helpers/provider_test_helpers.dart';
import '../../helpers/widget_test_helpers.dart';

class _FakeIndustryEpsNotifier extends IndustryEpsNotifier {
  static int loadDataCalls = 0;

  @override
  IndustryEpsState build() =>
      IndustryEpsState(fetchedAt: DateTime(2026, 9, 28));

  @override
  Future<void> loadData() async => loadDataCalls++;
}

class _FakeShortSellNotifier extends ShortSellRankingNotifier {
  static int loadDataCalls = 0;

  @override
  ShortSellRankingState build() =>
      ShortSellRankingState(fetchedAt: DateTime(2026, 9, 28));

  @override
  Future<void> loadData() async => loadDataCalls++;
}

class _ErrorIndustryEpsNotifier extends IndustryEpsNotifier {
  _ErrorIndustryEpsNotifier(this.error);

  final String error;

  @override
  IndustryEpsState build() => IndustryEpsState(error: error);

  @override
  Future<void> loadData() async {}
}

class _ErrorShortSellNotifier extends ShortSellRankingNotifier {
  _ErrorShortSellNotifier(this.error);

  final String error;

  @override
  ShortSellRankingState build() => ShortSellRankingState(error: error);

  @override
  Future<void> loadData() async {}
}

class _FakeNewsNotifier extends NewsNotifier {
  _FakeNewsNotifier(this.initial);

  static int refreshCalls = 0;
  final NewsState initial;

  @override
  NewsState build() => initial;

  @override
  Future<void> loadData({int days = 7}) async {}

  // 下拉走 refresh()；覆寫以免測試打到真的 RSS 同步
  @override
  Future<void> refresh({int days = 7}) async => refreshCalls++;
}

// 可下拉重新整理的空狀態：小螢幕或放大字級時不得溢位，且仍可下拉觸發
// 重新載入。
void main() {
  setUpAll(() async {
    await setupTestLocalization();
  });

  final screens = <String, Widget Function()>{
    '產業 EPS': () => buildProviderTestApp(
      const IndustryEpsScreen(),
      overrides: [
        industryEpsProvider.overrideWith(_FakeIndustryEpsNotifier.new),
      ],
    ),
    '融券排行': () => buildProviderTestApp(
      const ShortSellRankingScreen(),
      overrides: [
        shortSellRankingProvider.overrideWith(_FakeShortSellNotifier.new),
      ],
    ),
    for (final error in ['Database error', 'Network error']) ...{
      '產業 EPS（$error）': () => buildProviderTestApp(
        const IndustryEpsScreen(),
        overrides: [
          industryEpsProvider.overrideWith(
            () => _ErrorIndustryEpsNotifier(error),
          ),
        ],
      ),
      '融券排行（$error）': () => buildProviderTestApp(
        const ShortSellRankingScreen(),
        overrides: [
          shortSellRankingProvider.overrideWith(
            () => _ErrorShortSellNotifier(error),
          ),
        ],
      ),
    },
    '新聞（無資料）': () => buildProviderTestApp(
      const NewsScreen(),
      overrides: [
        newsProvider.overrideWith(() => _FakeNewsNotifier(NewsState())),
      ],
    ),
    '新聞（錯誤）': () => buildProviderTestApp(
      const NewsScreen(),
      overrides: [
        newsProvider.overrideWith(
          () => _FakeNewsNotifier(NewsState(error: 'Database error')),
        ),
      ],
    ),
  };

  for (final screen in screens.entries) {
    for (final scenario in phoneScenarios) {
      testWidgets('${screen.key}：$scenario 空狀態不溢位', (tester) async {
        applyPhoneScenario(tester, scenario);
        await tester.pumpWidget(screen.value());
        await tester.pump(const Duration(seconds: 1));

        expect(tester.takeException(), isNull);
        expect(find.byType(EmptyState), findsOneWidget);
      });
    }
  }

  group('空狀態仍可下拉重新整理', () {
    Future<void> pullDown(WidgetTester tester) async {
      await tester.fling(
        find.byType(CustomScrollView),
        const Offset(0, 400),
        1000,
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
    }

    testWidgets('產業 EPS', (tester) async {
      applyPhoneScenario(tester, phoneScenarios.first);
      await tester.pumpWidget(screens['產業 EPS']!());
      await tester.pump(const Duration(seconds: 1));
      final before = _FakeIndustryEpsNotifier.loadDataCalls;

      await pullDown(tester);
      expect(_FakeIndustryEpsNotifier.loadDataCalls, greaterThan(before));
    });

    testWidgets('融券排行', (tester) async {
      applyPhoneScenario(tester, phoneScenarios.first);
      await tester.pumpWidget(screens['融券排行']!());
      await tester.pump(const Duration(seconds: 1));
      final before = _FakeShortSellNotifier.loadDataCalls;

      await pullDown(tester);
      expect(_FakeShortSellNotifier.loadDataCalls, greaterThan(before));
    });

    testWidgets('新聞', (tester) async {
      applyPhoneScenario(tester, phoneScenarios.first);
      await tester.pumpWidget(screens['新聞（無資料）']!());
      await tester.pump(const Duration(seconds: 1));
      final before = _FakeNewsNotifier.refreshCalls;

      await pullDown(tester);
      expect(_FakeNewsNotifier.refreshCalls, greaterThan(before));
    });
  });
}
