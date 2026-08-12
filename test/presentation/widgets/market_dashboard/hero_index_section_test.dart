import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/data/remote/twse_client.dart';
import 'package:daredevil/presentation/widgets/market_dashboard/hero_index_section.dart';
import 'package:daredevil/presentation/screens/stock_detail/widgets/mini_trend_chart.dart';

import '../../../helpers/widget_test_helpers.dart';

void main() {
  setUpAll(() async {
    await setupTestLocalization();
  });

  TwseMarketIndex createIndex({
    double close = 22000.50,
    double change = 150.25,
    double changePercent = 0.69,
  }) {
    return TwseMarketIndex(
      date: DateTime(2026, 2, 15),
      name: '發行量加權股價指數',
      close: close,
      change: change,
      changePercent: changePercent,
    );
  }

  group('HeroIndexSection', () {
    testWidgets('displays formatted close price', (tester) async {
      await tester.pumpWidget(
        buildTestApp(HeroIndexSection(index: createIndex())),
      );

      // 22,000.50 should be displayed
      expect(find.text('22,000.50'), findsOneWidget);
    });

    testWidgets('shows positive sign for up market', (tester) async {
      await tester.pumpWidget(
        buildTestApp(HeroIndexSection(index: createIndex(change: 150.25))),
      );

      // +150.25 formatted
      expect(find.text('+150.25'), findsOneWidget);
    });

    testWidgets('shows no sign for down market', (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          HeroIndexSection(
            index: createIndex(change: -80.10, changePercent: -0.36),
          ),
        ),
      );

      expect(find.text('-80.10'), findsOneWidget);
    });

    group('market stage row', () {
      // 持續上升 80 點 → 多頭排列（close > MA20 > MA60）
      final bullishHistory = List.generate(80, (i) => 22000.0 + i.toDouble());

      testWidgets('renders stage chip with sufficient stage history', (
        tester,
      ) async {
        await tester.pumpWidget(
          buildTestApp(
            HeroIndexSection(
              index: createIndex(),
              historyData: bullishHistory,
              stageHistory: bullishHistory,
            ),
          ),
        );

        // 位階 chip + 距 20MA / 距 60MA 乖離率（無載入翻譯時 .tr() 回傳 key）
        expect(find.text('marketOverview.stage.bullish'), findsOneWidget);
        expect(find.textContaining('marketOverview.biasMa20'), findsOneWidget);
      });

      testWidgets('🚨 neutral 依子狀態換措辭:V 轉站回雙均線 → 待黃金交叉', (tester) async {
        // 2026-08-12 實況形狀:崩跌後 V 轉,收盤站上雙均線但 20MA<60MA。
        // 修前一律顯示「均線糾結」,與畫面上 +4.4% 的正乖離自相矛盾。
        final reclaimHistory = [
          ...List.filled(30, 22000.0),
          ...List.filled(25, 18000.0),
          ...List.filled(5, 23000.0),
        ];
        await tester.pumpWidget(
          buildTestApp(
            HeroIndexSection(
              index: createIndex(),
              historyData: reclaimHistory,
              stageHistory: reclaimHistory,
            ),
          ),
        );

        expect(
          find.text('marketOverview.stage.neutralReclaim'),
          findsOneWidget,
        );
        expect(find.text('marketOverview.stage.neutral'), findsNothing);
      });

      testWidgets('shows insufficient muted text when stage history is short', (
        tester,
      ) async {
        // 少於 MA60 所需筆數（<60）→ 位階資料不足
        final shortHistory = List.generate(30, (i) => 22000.0 + i.toDouble());

        await tester.pumpWidget(
          buildTestApp(
            HeroIndexSection(
              index: createIndex(),
              historyData: shortHistory,
              stageHistory: shortHistory,
            ),
          ),
        );

        expect(find.text('marketOverview.stage.insufficient'), findsOneWidget);
        // 資料不足時不顯示位階 chip
        expect(find.text('marketOverview.stage.bullish'), findsNothing);
      });

      // 2026-08-05 複審翻轉:原「無歷史→整行消失」正是雙欄並排時
      // sparkline 一高一低的最後一個異構源(單側指數歷史缺漏時,一側
      // 有位階行、一側整行沒有,高度差 ~30px)。新語意:任何狀態都
      // 渲染**同高**的位階行,無歷史顯示「資料不足」。
      testWidgets('no stage history → 仍渲染同高位階行(資料不足)', (tester) async {
        await tester.pumpWidget(
          buildTestApp(HeroIndexSection(index: createIndex())),
        );

        expect(find.text('marketOverview.stage.insufficient'), findsOneWidget);
        expect(find.text('marketOverview.stage.bullish'), findsNothing);
      });

      // 判讀層（P2）— 位階乖離判讀行

      // ==================================================
      // 並排對齊(2026-08-02 使用者實機抓到「一高一低」)
      //
      // bias 判讀原為獨立一行:一側超跌一側無判讀時,兩卡 sparkline 與
      // 其下所有內容垂直錯位。判讀併入位階資訊列(同一行)後,兩卡結構
      // 恆定——此測試鎖住「異構雙卡 sparkline 同高」的不變量。
      // ==================================================
      group('並排雙卡對齊', () {
        testWidgets('🚨 一側有 bias 判讀、一側沒有:sparkline 不得一高一低', (tester) async {
          tester.view.physicalSize = const Size(4000, 2400);
          addTearDown(() => tester.view.resetPhysicalSize());

          // 左:緩升多頭、乖離溫和 → 無判讀行
          final mild = List.generate(80, (i) => 22000.0 + i * 2);
          // 右:平盤後暴跌 → bearish + 距 MA60 -31% → 超跌判讀
          final oversold = [...List.generate(79, (_) => 22000.0), 15000.0];

          await tester.pumpWidget(
            buildTestApp(
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: HeroIndexSection(
                      index: createIndex(),
                      historyData: mild,
                      stageHistory: mild,
                    ),
                  ),
                  Expanded(
                    child: HeroIndexSection(
                      index: createIndex(close: 15000, change: -7000),
                      historyData: oversold,
                      stageHistory: oversold,
                    ),
                  ),
                ],
              ),
            ),
          );

          final tops = find
              .byType(MiniTrendChart)
              .evaluate()
              .map((e) => tester.getRect(find.byWidget(e.widget)).top)
              .toList();
          expect(tops, hasLength(2));
          expect(tops[0], tops[1], reason: 'bias 判讀行不得把單側 sparkline 往下推(一高一低)');
        });
      });

      testWidgets(
        'renders stage-bias interpretation line when bias is extreme',
        (tester) async {
          tester.view.physicalSize = const Size(3000, 2400);
          addTearDown(() => tester.view.resetPhysicalSize());

          // 前 79 天平盤在 22000，最後一天暴衝到 30000。
          // close=30000 > MA20 > MA60，且距 MA60 乖離遠大於 15% → overheated。
          final overheatedHistory = [
            ...List.generate(79, (_) => 22000.0),
            30000.0,
          ];

          await tester.pumpWidget(
            buildTestApp(
              HeroIndexSection(
                index: createIndex(),
                historyData: overheatedHistory,
                stageHistory: overheatedHistory,
              ),
            ),
          );

          // 判讀已併入位階資訊列(RichText 單行,2026-08-02 對齊修復)
          expect(
            find.textContaining(
              'marketOverview.reading.stageBias.overheated',
              findRichText: true,
            ),
            findsOneWidget,
          );
        },
      );

      testWidgets(
        'no stage-bias line when bias is mild (bullish but not hot)',
        (tester) async {
          // 線性緩升：close 距 MA60 乖離僅約 0.1%，遠低於 15% 門檻 → 無判讀行
          await tester.pumpWidget(
            buildTestApp(
              HeroIndexSection(
                index: createIndex(),
                historyData: bullishHistory,
                stageHistory: bullishHistory,
              ),
            ),
          );

          // 位階 chip 仍在，但不應出現乖離判讀行
          expect(find.text('marketOverview.stage.bullish'), findsOneWidget);
          expect(
            find.textContaining(
              'marketOverview.reading.stageBias',
              findRichText: true,
            ),
            findsNothing,
          );
        },
      );
    });
  });
}
