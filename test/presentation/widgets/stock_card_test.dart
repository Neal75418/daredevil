import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/theme/app_theme.dart';
import 'package:daredevil/core/theme/semantic_colors.dart';
import 'package:daredevil/presentation/widgets/stock_card.dart';

import '../../helpers/widget_test_helpers.dart';

/// 取趨勢箭頭的顏色（守門用：形狀可留，顏色不得是股價紅綠）
Color? _trendIconColor(WidgetTester tester) {
  final icons = tester
      .widgetList<Icon>(find.byType(Icon))
      .where(
        (i) =>
            i.icon == Icons.trending_up_rounded ||
            i.icon == Icons.trending_down_rounded ||
            i.icon == Icons.trending_flat_rounded,
      );
  return icons.single.color;
}

void main() {
  setUpAll(() async {
    await setupTestLocalization();
  });

  group('StockCard', () {
    testWidgets('displays symbol', (tester) async {
      await tester.pumpWidget(buildTestApp(const StockCard(symbol: '2330')));

      expect(find.text('2330'), findsOneWidget);
    });

    testWidgets('displays stock name when provided', (tester) async {
      await tester.pumpWidget(
        buildTestApp(const StockCard(symbol: '2330', stockName: '台積電')),
      );

      expect(find.text('台積電'), findsOneWidget);
    });

    testWidgets('hides stock name when null', (tester) async {
      await tester.pumpWidget(buildTestApp(const StockCard(symbol: '2330')));

      // Only symbol text should be present
      expect(find.text('2330'), findsOneWidget);
    });

    testWidgets('displays TPEx market label', (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          const StockCard(symbol: '6488', stockName: '環球晶', market: 'TPEx'),
        ),
      );

      expect(find.text('櫃'), findsOneWidget);
    });

    testWidgets('does not display market label for TWSE', (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          const StockCard(symbol: '2330', stockName: '台積電', market: 'TWSE'),
        ),
      );

      expect(find.text('櫃'), findsNothing);
    });

    // 配色與文字必須同時中性 —— flat-value sign/color 缺陷類第三輪
    //
    // 卡片的 priceColor 由 StockCard 算好後傳進 StockCardPriceSection，
    // 原本直接吃未捨入的 priceChange：文字顯示 0.00% 但整塊仍著跌色（綠），
    // 文字與配色互相矛盾。修正後與 stock_preview_sheet 同一慣例——先捨入
    // 到顯示精度再取色。
    testWidgets('微負值 -0.004：漲跌區塊用中性色（不著跌色）', (tester) async {
      tester.view.physicalSize = const Size(3000, 2400);
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        buildTestApp(
          const StockCard(
            symbol: '2330',
            latestClose: 100,
            priceChange: -0.004,
          ),
        ),
      );
      await tester.pump();

      final changeText = tester.widget<Text>(find.textContaining('0.00%'));
      expect(changeText.style?.color, AppTheme.getFlatColor(Brightness.light));
    });

    testWidgets('真實下跌仍著跌色（未過度中性化）', (tester) async {
      tester.view.physicalSize = const Size(3000, 2400);
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        buildTestApp(
          const StockCard(symbol: '2330', latestClose: 97, priceChange: -3.0),
        ),
      );
      await tester.pump();

      final changeText = tester.widget<Text>(find.textContaining('-3.00%'));
      expect(
        changeText.style?.color,
        isNot(AppTheme.getFlatColor(Brightness.light)),
      );
    });

    testWidgets('極窄卡片下雙 score 徽章等比縮小不溢位', (tester) async {
      // 迴歸：header 的分數徽章原為剛性寬度，卡片被格狀清單擠窄時
      // RenderFlex overflow（production log 2026-07-13：header
      // constraints w<=72.4, overflow 0.65~4.7px）。修正後徽章以
      // Flexible+FittedBox 等比縮小。
      // 註：價格區塊（StockCardPriceSection）的剛性寬度在窄卡片是
      // 既有的獨立問題，不在本迴歸範圍。
      await tester.pumpWidget(
        buildTestApp(
          const Center(
            child: SizedBox(
              width: 100,
              child: StockCard(symbol: '2330', dualScore: (62, 62)),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('極窄卡片下單一 score 徽章分支同樣不溢位', (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          const Center(
            child: SizedBox(
              width: 100,
              child: StockCard(symbol: '2330', score: 62),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('窄卡片下徽章+剛性釘選鈕共存不溢位', (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          Center(
            child: SizedBox(
              width: 140,
              child: StockCard(
                symbol: '2330',
                dualScore: const (62, 62),
                pinned: false,
                onPinToggle: () {},
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('正常寬度下釘選鈕貼齊 header 右緣', (tester) async {
      // 迴歸鎖：pin 若被包進 loose Flexible，用不完的 flex 配額會變成
      // 尾端留白（不回填 Spacer），pin 會往左漂數十 px——pin 必須
      // 維持剛性（stock_card.dart header 註解）。
      await tester.pumpWidget(
        buildTestApp(
          Center(
            child: SizedBox(
              width: 400,
              child: StockCard(
                symbol: '2330',
                stockName: '台積電',
                dualScore: const (62, 62),
                pinned: false,
                onPinToggle: () {},
              ),
            ),
          ),
        ),
      );

      final pin = find.byIcon(Icons.push_pin_outlined);
      // 祖先 Row 有兩層（header Row 與卡片外層 Row），取最窄者 = header
      final headerRect = find
          .ancestor(of: pin, matching: find.byType(Row))
          .evaluate()
          .map((e) => tester.getRect(find.byWidget(e.widget)))
          .reduce((a, b) => a.width <= b.width ? a : b);
      final pinRect = tester.getRect(pin);
      // 剛性 pin：icon 右緣距 header 右緣僅 InkWell padding（2px）；
      // 漂移 bug 下會拉開數十 px
      expect(
        headerRect.right - pinRect.right,
        lessThan(8),
        reason: 'pin 應貼齊 header 右緣，而非漂在 Flexible 配額留白左側',
      );
    });

    testWidgets('calls onTap callback when tapped', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        buildTestApp(StockCard(symbol: '2330', onTap: () => tapped = true)),
      );

      await tester.tap(find.byType(InkWell));
      expect(tapped, true);
    });

    testWidgets('calls onLongPress callback', (tester) async {
      var longPressed = false;
      await tester.pumpWidget(
        buildTestApp(
          StockCard(symbol: '2330', onLongPress: () => longPressed = true),
        ),
      );

      await tester.longPress(find.byType(InkWell));
      expect(longPressed, true);
    });

    testWidgets('shows watchlist button when onWatchlistTap provided', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildTestApp(StockCard(symbol: '2330', onWatchlistTap: () {})),
      );

      expect(find.byIcon(Icons.star_outline_rounded), findsOneWidget);
    });

    testWidgets('shows filled star when in watchlist', (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          StockCard(symbol: '2330', isInWatchlist: true, onWatchlistTap: () {}),
        ),
      );

      expect(find.byIcon(Icons.star_rounded), findsOneWidget);
    });

    testWidgets('calls onWatchlistTap when star tapped', (tester) async {
      var watchlistTapped = false;
      await tester.pumpWidget(
        buildTestApp(
          StockCard(
            symbol: '2330',
            onWatchlistTap: () => watchlistTapped = true,
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.star_outline_rounded));
      expect(watchlistTapped, true);
    });

    testWidgets('hides watchlist button when onWatchlistTap is null', (
      tester,
    ) async {
      await tester.pumpWidget(buildTestApp(const StockCard(symbol: '2330')));

      expect(find.byIcon(Icons.star_outline_rounded), findsNothing);
      expect(find.byIcon(Icons.star_rounded), findsNothing);
    });

    testWidgets('shows trend icon for UP state', (tester) async {
      await tester.pumpWidget(
        buildTestApp(const StockCard(symbol: '2330', trendState: 'UP')),
      );

      // 2026-08-16:趨勢圖示**改色不改形**。原本配股價紅綠,與同一張卡右側的
      // 「當日漲跌」撞成同一種視覺語言——實測 36 檔自選股有 13 檔兩者方向
      // 相反(仁寶趨勢 DOWN 卻漲停 +9.92%)。中間曾改成文字標籤,但 24px 窄欄
      // 擠兩個中文字實機很醜(使用者回報),故保留形狀、只去掉顏色。
      expect(find.byIcon(Icons.trending_up_rounded), findsOneWidget);
      expect(
        _trendIconColor(tester),
        isNot(AppTheme.upColor),
        reason: '形狀可以保留,顏色不得再宣稱漲跌',
      );
    });

    testWidgets('shows trend icon for DOWN state', (tester) async {
      await tester.pumpWidget(
        buildTestApp(const StockCard(symbol: '2330', trendState: 'DOWN')),
      );

      expect(find.byIcon(Icons.trending_down_rounded), findsOneWidget);
      expect(
        _trendIconColor(tester),
        isNot(PriceColors.downFor(Brightness.light)),
        reason: '形狀可以保留,顏色不得再宣稱漲跌',
      );
    });

    testWidgets('null trendState 不顯示趨勢 icon(2026-08-01 語意翻轉:未評分不得宣稱持平)', (
      tester,
    ) async {
      await tester.pumpWidget(buildTestApp(const StockCard(symbol: '2330')));

      expect(find.byIcon(Icons.trending_flat_rounded), findsNothing);
    });

    testWidgets('displays close price and positive change', (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          const StockCard(symbol: '2330', latestClose: 580.0, priceChange: 3.5),
        ),
      );

      expect(find.text('580.00'), findsOneWidget);
      // 格式包含絕對漲跌金額："+19.61 (+3.50%)"
      expect(find.textContaining('+3.50%'), findsOneWidget);
    });

    testWidgets('displays negative change', (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          const StockCard(
            symbol: '2330',
            latestClose: 580.0,
            priceChange: -2.5,
          ),
        ),
      );

      expect(find.textContaining('-2.50%'), findsOneWidget);
    });

    testWidgets('displays reasons as tags', (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          const StockCard(
            symbol: '2330',
            reasons: ['REVERSAL_W2S', 'VOLUME_SPIKE'],
          ),
        ),
      );

      // 測試環境未載入翻譯資源，.tr() 回傳原始 key
      expect(find.text('reasons.reversalW2S'), findsOneWidget);
      expect(find.text('reasons.volumeSpike'), findsOneWidget);
    });

    testWidgets('limits displayed reasons to 2', (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          const StockCard(
            symbol: '2330',
            reasons: ['REVERSAL_W2S', 'VOLUME_SPIKE', 'TECH_BREAKOUT'],
          ),
        ),
      );

      expect(find.text('reasons.reversalW2S'), findsOneWidget);
      expect(find.text('reasons.volumeSpike'), findsOneWidget);
      expect(find.text('reasons.breakout'), findsNothing);
    });

    group('score tier badge（評分改進 #5：分級為主視覺、數字退小字）', () {
      /// 取徽章標籤文字（.tr() 在測試環境回傳 i18n key）的實際顏色
      Color? tierLabelColor(WidgetTester tester, String key) {
        return tester.widget<Text>(find.text(key)).style?.color;
      }

      testWidgets('score >= 45 → 「強」徽章（ScoreTierBadge 強色）', (tester) async {
        await tester.pumpWidget(
          buildTestApp(const StockCard(symbol: '2330', score: 55.0)),
        );
        expect(
          tierLabelColor(tester, 'score.tier.strong'),
          // ScoreTier 色階為 ScoreTierBadge 私有常數（與籌碼評等/漲跌
          // 語意無關，見 score_tier_badge.dart 內註解），故以字面值比對。
          const Color(0xFF4CAF50),
        );
        // 確切分數退為小字、中性色（不再暗示假精確度）
        expect(find.text('55'), findsOneWidget);
      });

      testWidgets('score [25,45) → 「中」徽章', (tester) async {
        await tester.pumpWidget(
          buildTestApp(const StockCard(symbol: '2330', score: 40.0)),
        );
        expect(
          tierLabelColor(tester, 'score.tier.medium'),
          const Color(0xFF8BC34A),
        );
      });

      testWidgets('score [12,25) → 「弱」徽章', (tester) async {
        await tester.pumpWidget(
          buildTestApp(const StockCard(symbol: '2330', score: 15.0)),
        );
        expect(
          tierLabelColor(tester, 'score.tier.weak'),
          const Color(0xFFFFC107),
        );
      });

      testWidgets('score < 12 → 「觀察」徽章（觀察區列）', (tester) async {
        await tester.pumpWidget(
          buildTestApp(const StockCard(symbol: '2330', score: 9.0)),
        );
        expect(find.text('score.tier.observation'), findsOneWidget);
      });
    });
  });

  group('釘選鈕（出場層 Phase 2）', () {
    testWidgets('onPinToggle 提供時顯示 outline 圖示、點擊觸發 callback', (tester) async {
      var toggled = 0;
      await tester.pumpWidget(
        buildTestApp(
          StockCard(
            symbol: '2330',
            score: 30.0,
            pinned: false,
            onPinToggle: () => toggled++,
          ),
        ),
      );
      expect(find.byIcon(Icons.push_pin_outlined), findsOneWidget);
      await tester.tap(find.byIcon(Icons.push_pin_outlined));
      expect(toggled, 1);
    });

    testWidgets('pinned = true 顯示實心圖示', (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          StockCard(
            symbol: '2330',
            score: 30.0,
            pinned: true,
            onPinToggle: () {},
          ),
        ),
      );
      expect(find.byIcon(Icons.push_pin), findsOneWidget);
    });

    testWidgets('未提供 onPinToggle → 不顯示釘選鈕（scan 頁不受影響）', (tester) async {
      await tester.pumpWidget(
        buildTestApp(const StockCard(symbol: '2330', score: 30.0)),
      );
      expect(find.byIcon(Icons.push_pin_outlined), findsNothing);
      expect(find.byIcon(Icons.push_pin), findsNothing);
    });
  });

  group('未評分股票的趨勢指示(2026-08-01 複審 sweep)', () {
    testWidgets('trendState null → 不渲染任何趨勢 icon(沒評分不得宣稱持平)', (tester) async {
      await tester.pumpWidget(
        buildTestApp(const StockCard(symbol: '9999', stockName: '未評分股')),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(find.byIcon(Icons.trending_flat_rounded), findsNothing);
      expect(find.byIcon(Icons.trending_up_rounded), findsNothing);
      expect(find.byIcon(Icons.trending_down_rounded), findsNothing);
    });

    testWidgets('trendState UP → 正常顯示趨勢 icon(guard 不誤傷)', (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          const StockCard(symbol: '2330', stockName: '台積電', trendState: 'UP'),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(find.byIcon(Icons.trending_up_rounded), findsOneWidget);
    });
  });
}
