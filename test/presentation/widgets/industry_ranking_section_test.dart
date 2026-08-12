import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/domain/models/industry_ranking.dart';
import 'package:daredevil/presentation/providers/industry_ranking_provider.dart';
import 'package:daredevil/presentation/widgets/industry_ranking_section.dart';

import '../../helpers/widget_test_helpers.dart';

void main() {
  setUpAll(() async {
    await setupTestLocalization();
  });

  void widenViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(5000, 4000);
    addTearDown(() => tester.view.resetPhysicalSize());
  }

  Widget buildSection(Map<RankingWindow, List<IndustryRanking>> byWindow) {
    return ProviderScope(
      overrides: [
        industryRankingProvider.overrideWith(
          (ref, window) async => byWindow[window] ?? const [],
        ),
      ],
      child: buildTestApp(
        const SingleChildScrollView(child: IndustryRankingSection()),
      ),
    );
  }

  const semis = IndustryRanking(
    industry: '半導體業',
    momentumPct: 12.3,
    memberCount: 42,
    institutionalNetShares: 5000000, // +5,000 張
    // 2026-07-27 新增的正規化指標：超額（vs 大盤同窗）、法人佔成交量比、上漲佔比
    excessPct: 14.4,
    institutionalVolumeRatio: 0.12,
    advancingRatio: 0.73,
    topMembers: [
      IndustryMember(symbol: '2330', name: '台積電', retPct: 15.0),
      IndustryMember(symbol: '2454', name: '聯發科', retPct: 10.0),
    ],
  );
  const textiles = IndustryRanking(
    industry: '紡織業',
    momentumPct: -2.5,
    memberCount: 12,
    institutionalNetShares: -800000,
    excessPct: -0.4,
    institutionalVolumeRatio: -0.05,
    advancingRatio: 0.33,
    topMembers: [],
  );
  const financials = IndustryRanking(
    industry: '金融保險',
    momentumPct: 3.0,
    memberCount: 32,
    institutionalNetShares: 351542596,
    excessPct: 5.1,
    institutionalVolumeRatio: 0.124,
    advancingRatio: 0.69,
    topMembers: [],
  );

  group('IndustryRankingSection', () {
    testWidgets('顯示產業卡：名稱、動能百分比、名次（預設 今日）', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(
        buildSection(const {
          RankingWindow.d1: [semis, textiles],
        }),
      );
      await tester.pumpAndSettle(); // SectionHeader 動畫跑完（避免 pending timer）

      expect(find.text('半導體業'), findsOneWidget);
      expect(find.text('+12.3%'), findsOneWidget);
      expect(find.text('紡織業'), findsOneWidget);
      expect(find.text('-2.5%'), findsOneWidget);
      expect(find.text('1'), findsOneWidget); // 名次
      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('🚨 預設分頁=今日(2026-08-13 定案),切 5日 → 換視窗資料', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(
        buildSection(const {
          RankingWindow.d1: [financials],
          RankingWindow.d5: [semis],
          RankingWindow.d20: [textiles],
        }),
      );
      await tester.pumpAndSettle();

      // 未點任何 tab:顯示的是 d1 的資料——這就是「預設今日」的守門
      expect(find.text('金融保險'), findsOneWidget);
      expect(find.text('半導體業'), findsNothing);
      expect(find.text('紡織業'), findsNothing, reason: '20日資料不得出現,否則預設仍是 d20');

      await tester.tap(find.text('today.industryWindow5d'));
      await tester.pumpAndSettle();

      // 5日視角：半導體反彈進榜
      expect(find.text('半導體業'), findsOneWidget);
      expect(find.text('金融保險'), findsNothing);
    });

    testWidgets('空排行 → 整段收起', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(buildSection(const {}));
      await tester.pumpAndSettle();

      expect(find.text('today.industryRanking'), findsNothing);
      expect(find.byType(Card), findsNothing);
    });

    testWidgets('點卡片開領漲成員 sheet', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(
        buildSection(const {
          RankingWindow.d1: [semis],
        }),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('半導體業'));
      await tester.pumpAndSettle();

      expect(find.text('台積電'), findsOneWidget);
      expect(find.text('2330'), findsOneWidget);
      expect(find.text('+15.0%'), findsOneWidget);
      expect(find.text('聯發科'), findsOneWidget);
    });
  });
}
