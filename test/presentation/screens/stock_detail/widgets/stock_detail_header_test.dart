import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/theme/app_theme.dart';
import 'package:daredevil/core/theme/color_contrast.dart';
import 'package:daredevil/core/utils/price_limit.dart';
import 'package:daredevil/domain/models/live_quote.dart';
import 'package:daredevil/presentation/screens/stock_detail/tabs/chip/chip_helpers.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/presentation/providers/stock_detail_state.dart';
import 'package:daredevil/presentation/screens/stock_detail/widgets/stock_detail_header.dart';

import '../../../../helpers/price_flash_helpers.dart';
import '../../../../helpers/phone_layout_helpers.dart';
import '../../../../helpers/widget_test_helpers.dart';

void main() {
  setUpAll(() async {
    await setupTestLocalization();
  });

  void widenViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(5000, 4000);
    addTearDown(() => tester.view.resetPhysicalSize());
  }

  final defaultDate = DateTime(2026, 2, 13);

  StockMasterEntry createStock({
    String symbol = '2330',
    String name = '台積電',
    String market = 'TWSE',
    String? industry,
  }) {
    return StockMasterEntry(
      symbol: symbol,
      name: name,
      market: market,
      industry: industry ?? '半導體',
      isActive: true,
      updatedAt: defaultDate,
    );
  }

  DailyPriceEntry createPrice({
    String symbol = '2330',
    double close = 600.0,
    DateTime? date,
  }) {
    final d = date ?? defaultDate;
    return DailyPriceEntry(
      symbol: symbol,
      date: d,
      open: close * 0.99,
      high: close * 1.02,
      low: close * 0.98,
      close: close,
      volume: 50000,
    );
  }

  DailyAnalysisEntry createAnalysis({
    String symbol = '2330',
    double score = 75.0,
    String trend = 'BULLISH',
    String reversal = '',
    double? supportLevel,
    double? resistanceLevel,
  }) {
    return DailyAnalysisEntry(
      symbol: symbol,
      date: defaultDate,
      scoreShort: score,
      scoreLong: score,
      trendState: trend,
      reversalState: reversal,
      supportLevel: supportLevel,
      resistanceLevel: resistanceLevel,
      computedAt: defaultDate,
    );
  }

  StockHeaderData createHeaderData({
    StockMasterEntry? stock,
    DailyPriceEntry? latestPrice,
    DailyAnalysisEntry? analysis,
    List<String>? reasons,
    DateTime? dataDate,
  }) {
    final s = stock ?? createStock();
    final lp = latestPrice ?? createPrice();
    final a = analysis ?? createAnalysis();

    return StockHeaderData(
      stockName: s.name,
      stockMarket: s.market,
      stockIndustry: s.industry,
      latestClose: lp.close,
      priceChange: lp.close != null
          ? ((lp.close! - 594.0) / 594.0 * 100) // vs yesterday 594.0
          : null,
      trendState: a.trendState,
      support: a.supportLevel,
      resistance: a.resistanceLevel,
      reasons: reasons ?? const [],
      dataDate: dataDate ?? defaultDate,
    );
  }

  group('StockDetailHeader 校準背書標記', () {
    testWidgets('背書的 reason 顯示 verified 標記、未背書的不顯示', (tester) async {
      widenViewport(tester);
      final state = createHeaderData(
        reasons: const ['WEEK_52_HIGH', 'KD_GOLDEN_CROSS'],
      );
      await tester.pumpWidget(
        buildTestApp(
          StockDetailHeader(
            data: state,
            symbol: '2330',
            isCalibrationBacked: (code) => code == 'WEEK_52_HIGH',
          ),
        ),
      );
      expect(find.byIcon(Icons.verified_outlined), findsOneWidget);
    });
  });

  group('StockDetailHeader', () {
    testWidgets('displays stock name', (tester) async {
      widenViewport(tester);
      final state = createHeaderData();

      await tester.pumpWidget(
        buildTestApp(StockDetailHeader(data: state, symbol: '2330')),
      );

      expect(find.text('台積電'), findsOneWidget);
    });

    testWidgets('displays close price', (tester) async {
      widenViewport(tester);
      final state = createHeaderData();

      await tester.pumpWidget(
        buildTestApp(StockDetailHeader(data: state, symbol: '2330')),
      );

      expect(find.text('600.00'), findsOneWidget);
    });

    testWidgets('shows TPEx badge for OTC stocks', (tester) async {
      widenViewport(tester);
      final state = createHeaderData(stock: createStock(market: 'TPEx'));

      await tester.pumpWidget(
        buildTestApp(StockDetailHeader(data: state, symbol: '2330')),
      );

      // Should find the OTC badge text
      expect(find.textContaining('stockDetail.otcBadge'), findsOneWidget);
    });

    testWidgets('shows industry badge', (tester) async {
      widenViewport(tester);
      final state = createHeaderData(stock: createStock(industry: '半導體'));

      await tester.pumpWidget(
        buildTestApp(StockDetailHeader(data: state, symbol: '2330')),
      );

      expect(find.text('半導體'), findsOneWidget);
    });

    testWidgets('shows support and resistance levels', (tester) async {
      widenViewport(tester);
      final state = createHeaderData(
        analysis: createAnalysis(supportLevel: 580.0, resistanceLevel: 620.0),
      );

      await tester.pumpWidget(
        buildTestApp(StockDetailHeader(data: state, symbol: '2330')),
      );

      expect(find.textContaining('580.0'), findsOneWidget);
      expect(find.textContaining('620.0'), findsOneWidget);
    });

    testWidgets('renders in dark mode', (tester) async {
      widenViewport(tester);
      final state = createHeaderData();

      await tester.pumpWidget(
        buildTestApp(
          StockDetailHeader(data: state, symbol: '2330'),
          brightness: Brightness.dark,
        ),
      );

      expect(find.text('台積電'), findsOneWidget);
      expect(find.text('600.00'), findsOneWidget);
    });
  });

  group('資料完整度提示（評分改進 #8）', () {
    testWidgets('有缺漏 domain → 顯示 dataMissing 提示（含缺漏項）', (tester) async {
      widenViewport(tester);
      final state = createHeaderData().copyWithMissing(const [
        'stockDetail.domain.revenue',
        'stockDetail.domain.eps',
      ]);

      await tester.pumpWidget(
        buildTestApp(StockDetailHeader(data: state, symbol: '2330')),
      );

      // 測試環境 .tr() 回 key：提示文字以 dataMissing key 呈現
      expect(
        find.textContaining('stockDetail.dataMissing'),
        findsOneWidget,
        reason: '缺漏時要提示使用者「分數偏低可能因資料缺漏、非真的弱」',
      );
    });

    test('fromState：ETF（00 開頭）豁免財報類 domain（ETF 無財報非缺漏）', () {
      final state = StockDetailState(
        price: StockPriceState(
          stock: StockMasterEntry(
            symbol: '0050',
            name: '元大台灣50',
            market: 'TWSE',
            isActive: true,
            updatedAt: defaultDate,
          ),
          priceHistory: [
            DailyPriceEntry(symbol: '0050', date: defaultDate, close: 180.0),
          ],
        ),
        // fundamentals 全空 —— 對 ETF 是常態、不是缺漏
      );

      final data = StockHeaderData.fromState(state);
      expect(
        data.missingDomains,
        isNot(contains('stockDetail.domain.revenue')),
      );
      expect(data.missingDomains, isNot(contains('stockDetail.domain.eps')));
      expect(
        data.missingDomains,
        isNot(contains('stockDetail.domain.valuation')),
      );
      // 非財報 domain 照常判定
      expect(data.missingDomains, contains('stockDetail.domain.institutional'));
    });

    testWidgets('資料齊全 → 不顯示提示（零噪音）', (tester) async {
      widenViewport(tester);
      final state = createHeaderData(); // missingDomains 預設空

      await tester.pumpWidget(
        buildTestApp(StockDetailHeader(data: state, symbol: '2330')),
      );

      expect(find.textContaining('stockDetail.dataMissing'), findsNothing);
    });
  });

  group('平盤/微負值：不得顯示上漲箭頭或漲色（flagship 色彩語意）', () {
    StockHeaderData headerWithChange(double pc) => StockHeaderData(
      stockName: '台積電',
      stockMarket: 'TWSE',
      stockIndustry: '半導體',
      latestClose: 600.0,
      priceChange: pc,
      trendState: 'BULLISH', // 讓趨勢 chip 用非 flat 圖示，避免與價格箭頭混淆
      dataDate: defaultDate,
    );

    testWidgets('平盤（priceChange==0）→ 中性色 0.00%、無北向(上漲)箭頭', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(
        buildTestApp(
          StockDetailHeader(data: headerWithChange(0.0), symbol: '2330'),
        ),
      );

      expect(find.byIcon(Icons.north), findsNothing, reason: '平盤不得顯示上漲箭頭');
      expect(find.text('+0.00%'), findsNothing, reason: '平盤不得帶 + 號');
      expect(find.text('0.00%'), findsOneWidget);
      final pctText = tester.widget<Text>(find.text('0.00%'));
      expect(
        pctText.style?.color,
        AppTheme.getFlatColor(Brightness.light),
        reason: '平盤數字顯示中性色，箭頭/漸層須與之一致',
      );
    });

    testWidgets('微負值（-0.004）捨入歸零 → 0.00%（非 -0.00%）、無南向(下跌)箭頭', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(
        buildTestApp(
          StockDetailHeader(data: headerWithChange(-0.004), symbol: '2330'),
        ),
      );

      expect(find.byIcon(Icons.south), findsNothing, reason: '捨入歸零不得顯示下跌箭頭');
      expect(
        find.textContaining('-0.00'),
        findsNothing,
        reason: '不得出現負零 -0.00%',
      );
      expect(find.text('0.00%'), findsOneWidget);
      final pctText = tester.widget<Text>(find.text('0.00%'));
      expect(pctText.style?.color, AppTheme.getFlatColor(Brightness.light));
    });
  });

  group('盤中即時報價與開高低量', () {
    const en = Locale('en', 'US');

    // 開高低量放在右側價格欄會把整列撐爆(右欄寬度不受限、左側股名欄被擠掉);
    // 改成自己一列、逐項換行。key 字串比中文長,比真實版面更嚴。只跑字級
    // 1.0:字級 2、3 時股名/價格那一列本來就溢位(與本列無關)
    for (final scenario in phoneScenarios.where((s) => s.textScale == 1.0)) {
      testWidgets('🚨 手機版面 $scenario:開高低量列不溢位', (tester) async {
        applyPhoneScenario(tester, scenario);
        await tester.pumpWidget(
          buildTestApp(
            const StockDetailHeader(
              data: StockHeaderData(
                stockName: '台積電',
                latestClose: 1000,
                priceChange: 1,
              ),
              symbol: '2330',
              live: StockHeaderLive(
                price: 1005,
                changePercent: 1.5,
                change: 15,
                statusText: 'liveQuote.quoteTime',
                open: 1000,
                high: 1010,
                low: 995.5,
                volumeLots: 123456,
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('🚨 盤後:開高低量列,成交量股數除以 1,000 以「張」顯示', (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          StockDetailHeader(
            data: StockHeaderData(
              stockName: '台積電',
              latestClose: 100,
              priceChange: 1,
              dataDate: DateTime(2026, 10, 5),
              open: 99,
              high: 101,
              low: 98.5,
              volumeShares: 1234000,
            ),
            symbol: '2330',
          ),
        ),
      );
      expect(find.textContaining('stockDetail.open'), findsOneWidget);
      expect(find.textContaining('98.50'), findsOneWidget);
      expect(find.textContaining(formatLots(1234, en)), findsOneWidget);
      // 資料日期標示(今日/昨日/M/D 資料)照常顯示——下一條的對照組
      expect(find.textContaining('stockDetail.data'), findsOneWidget);
    });

    testWidgets('🚨 即時:現價、漲跌、狀態取代資料日期;成交量直接用 MIS 張數', (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          StockDetailHeader(
            data: StockHeaderData(
              stockName: '台積電',
              latestClose: 100,
              priceChange: -1,
              dataDate: DateTime(2026, 10, 5),
            ),
            symbol: '2330',
            live: const StockHeaderLive(
              price: 103,
              changePercent: 3,
              change: 3,
              statusText: 'liveQuote.quoteTime',
              open: 100,
              high: 104,
              low: 99.5,
              volumeLots: 5678,
            ),
          ),
        ),
      );
      expect(find.text('103.00'), findsOneWidget);
      expect(find.textContaining('+3.00'), findsOneWidget);
      expect(find.text('liveQuote.quoteTime'), findsOneWidget);
      // 不寫死今日/昨日:`_formatDataDate` 依執行當天判斷,三種 key 都以
      // stockDetail.data 開頭(dataMissing 只在 missingDomains 非空時出現)
      expect(find.textContaining('stockDetail.data'), findsNothing);
      expect(find.textContaining(formatLots(5678, en)), findsOneWidget);
    });

    testWidgets('漲停鎖 → 徽章', (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          const StockDetailHeader(
            data: StockHeaderData(stockName: '測試', latestClose: 44),
            symbol: 'A',
            live: StockHeaderLive(
              price: 44,
              changePercent: 10,
              change: 4,
              statusText: 'liveQuote.quoteTime',
            ),
            limitStatus: PriceLimitStatus.limitUpLocked,
          ),
        ),
      );
      expect(find.text('price.limitUpLocked'), findsOneWidget);
    });

    for (final brightness in [Brightness.light, Brightness.dark]) {
      testWidgets('🚨 閃色最濃時 $brightness:現價對頁面漸層頂端的實際底色 ≥ 4.5', (tester) async {
        Widget header(int id) => buildTestApp(
          StockDetailHeader(
            data: const StockHeaderData(stockName: '測試', latestClose: 100),
            symbol: 'A',
            live: StockHeaderLive(
              price: 101,
              changePercent: 1,
              change: 1,
              statusText: 'liveQuote.quoteTime',
              flash: LiveQuoteFlash(id: id, up: true),
            ),
          ),
          brightness: brightness,
        );
        await tester.pumpWidget(header(1));
        await tester.pumpWidget(header(2));
        await tester.pump();

        final theme = brightness == Brightness.dark
            ? AppTheme.darkTheme
            : AppTheme.lightTheme;
        // 個股頁背景頂端是漲色 15% 疊在 surface 上(stock_detail_screen 的漸層)
        final pageTop = ColorContrast.compositeOver(
          AppTheme.upColor,
          theme.colorScheme.surface,
          0.15,
        );
        final tint = priceFlashTint(tester)!;
        final text = priceFlashTextColor(tester);
        expect(
          ColorContrast.ratio(
            text,
            ColorContrast.compositeOver(
              tint.withValues(alpha: 1),
              pageTop,
              tint.a,
            ),
          ),
          greaterThanOrEqualTo(4.5),
        );
      });
    }
  });
}

extension on StockHeaderData {
  /// 測試用：帶缺漏 domain 的複本
  StockHeaderData copyWithMissing(List<String> missing) => StockHeaderData(
    stockName: stockName,
    stockMarket: stockMarket,
    stockIndustry: stockIndustry,
    latestClose: latestClose,
    priceChange: priceChange,
    trendState: trendState,
    support: support,
    resistance: resistance,
    reasons: reasons,
    dataDate: dataDate,
    hasDataMismatch: hasDataMismatch,
    missingDomains: missing,
  );
}
