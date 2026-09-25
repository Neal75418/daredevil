import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:daredevil/core/constants/market_codes.dart';
import 'package:daredevil/core/theme/app_theme.dart';
import 'package:daredevil/core/theme/semantic_colors.dart';
import 'package:daredevil/data/models/twse/twse_market_index.dart';
import 'package:daredevil/presentation/providers/market_overview_provider.dart';
import 'package:daredevil/presentation/screens/today/widgets/market_summary_strip.dart';
import 'package:daredevil/presentation/widgets/market_dashboard/market_overview_selectors.dart';
import 'package:daredevil/presentation/widgets/shimmer_loading.dart';

/// 供給預先讀好的翻譯 map（避開 rootBundle 在 fake async 下不 resolve）
class _PreloadedAssetLoader extends AssetLoader {
  const _PreloadedAssetLoader(this.data);

  final Map<String, dynamic> data;

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async => data;
}

TwseMarketIndex _index(String name, double close, double change, double pct) =>
    TwseMarketIndex(
      date: DateTime(2026, 9, 24),
      name: name,
      close: close,
      change: change,
      changePercent: pct,
    );

final _withData = MarketOverviewState(
  indices: [
    _index(MarketIndexNames.taiex, 48024.6, -132.69, -0.28),
    _index(MarketIndexNames.tpexIndex, 285.3, 0.28, 0.1),
  ],
  advanceDeclineByMarket: const {
    MarketCode.twse: AdvanceDecline(advance: 408, decline: 667, unchanged: 149),
  },
  historyTrends: HistoryTrends(
    turnover: {
      MarketCode.twse: [
        (date: DateTime(2026, 9, 23), value: 100.0),
        (date: DateTime(2026, 9, 24), value: 90.0),
      ],
    },
  ),
);

/// 一般 widget 測試的 `.tr()` 只回 key、看不到參數；失敗區塊數與非即時
/// 日期要看得到，所以載入真實 zh-TW 翻譯斷言整組文字。
void main() {
  late Map<String, dynamic> zhTw;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    EasyLocalization.logger.enableLevels = [];
    zhTw =
        json.decode(await File('assets/translations/zh-TW.json').readAsString())
            as Map<String, dynamic>;
  });

  Future<void> pump(
    WidgetTester tester,
    MarketOverviewState state, {
    VoidCallback? onTap,
    VoidCallback? onRetry,
    double width = 390,
  }) async {
    tester.view.physicalSize = Size(width, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('zh', 'TW')],
        path: 'assets/translations',
        fallbackLocale: const Locale('zh', 'TW'),
        startLocale: const Locale('zh', 'TW'),
        assetLoader: _PreloadedAssetLoader(zhTw),
        child: Builder(
          builder: (context) => MaterialApp(
            locale: context.locale,
            supportedLocales: context.supportedLocales,
            localizationsDelegates: context.localizationDelegates,
            home: Scaffold(
              body: Align(
                alignment: Alignment.topCenter,
                child: MarketSummaryStrip(
                  state: state,
                  onTap: onTap ?? () {},
                  onRetry: onRetry ?? () {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  /// 在某組 Text.rich 裡找出某段文字的顏色
  Color? spanColor(WidgetTester tester, String group, String part) {
    final text = tester.widget<Text>(find.text(group));
    Color? found;
    text.textSpan!.visitChildren((span) {
      if (span is TextSpan && span.text == part) {
        found = span.style?.color;
        return false;
      }
      return true;
    });
    return found;
  }

  String sentimentGroup(MarketOverviewState s) {
    final sentiment = computeMarketSentiment(s, MarketCode.twse)!;
    return '上市 情緒 ${sentiment.score.round()} '
        '${sentimentLevelText(sentiment.level)}';
  }

  group('有資料', () {
    testWidgets('兩個主指數、上市情緒、漲跌家數', (tester) async {
      await pump(tester, _withData);
      expect(find.text('加權 48,024.60 -0.28%'), findsOneWidget);
      expect(find.text('櫃買 285.30 +0.10%'), findsOneWidget);
      // 與儀表板同一個 selector 算出的分數與等級
      expect(find.text(sentimentGroup(_withData)), findsOneWidget);
      expect(find.text('漲 408 跌 667'), findsOneWidget);
    });

    testWidgets('漲跌配色：漲幅／漲家數用漲色、跌幅／跌家數用跌色', (tester) async {
      await pump(tester, _withData);
      const light = Brightness.light;
      expect(
        spanColor(tester, '加權 48,024.60 -0.28%', '-0.28%'),
        AppTheme.getPriceColor(-132.69, light),
      );
      expect(
        spanColor(tester, '櫃買 285.30 +0.10%', '+0.10%'),
        AppTheme.getPriceColor(0.28, light),
      );
      expect(
        spanColor(tester, '漲 408 跌 667', '408'),
        AppTheme.getPriceColor(1, light),
      );
      expect(
        spanColor(tester, '漲 408 跌 667', '667'),
        AppTheme.getPriceColor(-1, light),
      );
    });

    // twse_client 在「方向 -、漲跌幅 0.00」時給 changePercent = -0.0
    testWidgets('跌 2 點、漲跌幅 -0.0 → -0.00%，不是 +-0.00%', (tester) async {
      await pump(
        tester,
        _withData.copyWith(
          indices: [
            _index(MarketIndexNames.taiex, 48022.6, -2, -0.0),
            _index(MarketIndexNames.tpexIndex, 285.3, 0.28, 0.1),
          ],
        ),
      );
      expect(find.text('加權 48,022.60 -0.00%'), findsOneWidget);
    });

    // 測試字型每個字元都是 1em 寬（比真實字型寬），整行一定比實機長，
    // 「兩個指數同一行」只能看實機；這裡驗的是分組本身：標籤不和數值拆行
    testWidgets('390 寬時每組各自單行（標籤不和數值拆開）', (tester) async {
      await pump(tester, _withData);
      final singleLine = tester.getSize(find.text('漲 408 跌 667')).height;
      for (final group in [
        '加權 48,024.60 -0.28%',
        '櫃買 285.30 +0.10%',
        sentimentGroup(_withData),
      ]) {
        expect(
          tester.getSize(find.text(group)).height,
          singleLine,
          reason: group,
        );
      }
    });

    testWidgets('重新整理中（isLoading 但已有資料）→ 照顯示資料，不閃成骨架', (tester) async {
      await pump(tester, _withData.copyWith(isLoading: true));
      expect(find.text('加權 48,024.60 -0.28%'), findsOneWidget);
      expect(find.byType(ShimmerContainer), findsNothing);
    });

    testWidgets('點擊整條 → onTap', (tester) async {
      var taps = 0;
      await pump(tester, _withData, onTap: () => taps++);
      await tester.tap(find.byType(MarketSummaryStrip));
      expect(taps, 1);
    });

    testWidgets('朗讀：整條是一個按鈕、有大盤摘要標籤，分隔點不唸', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester, _withData);
      final node = tester.getSemantics(find.byType(InkWell));
      final data = node.getSemanticsData();
      expect(data.label, startsWith('大盤摘要'));
      expect(data.label, isNot(contains('・')));
      expect(node.hintOverrides?.onTapHint, '查看完整大盤');
      handle.dispose();
    });
  });

  group('部分資料', () {
    testWidgets('主指數是資料庫備援值 → 標「非即時(日期)」並用警示色', (tester) async {
      await pump(
        tester,
        _withData.copyWith(indexStaleNames: {MarketIndexNames.taiex}),
      );
      const group = '加權 48,024.60 -0.28% 非即時(9/24)';
      expect(find.text(group), findsOneWidget);
      // 只標在備援的那個指數上，櫃買是即時值不得被連帶標記
      expect(find.text('櫃買 285.30 +0.10%'), findsOneWidget);
      expect(find.textContaining('非即時'), findsOneWidget);
      expect(
        spanColor(tester, group, '非即時(9/24)'),
        WarningColors.warningOnLight,
      );
    });

    testWidgets('1 個區塊失敗 → 數字照顯示並附「1 區塊載入失敗」', (tester) async {
      await pump(tester, _withData.copyWith(failedSections: {'margin'}));
      expect(find.text('加權 48,024.60 -0.28%'), findsOneWidget);
      expect(find.text('1 區塊載入失敗'), findsOneWidget);
    });

    // 已有資料但重新整理失敗（回前景／下拉時 loadData 拋錯）：舊數字照顯示，
    // 但要看得出資料可能過時——原本今日頁的整張儀表板頂端有這條警示
    testWidgets('有資料但重新整理失敗 → 數字照顯示並附錯誤訊息', (tester) async {
      await pump(tester, _withData.copyWith(error: '網路錯誤'));
      expect(find.text('加權 48,024.60 -0.28%'), findsOneWidget);
      expect(find.text('網路錯誤'), findsOneWidget);
    });

    testWidgets('沒有區塊失敗 → 不顯示失敗警示', (tester) async {
      await pump(tester, _withData);
      expect(find.textContaining('區塊載入失敗'), findsNothing);
    });

    testWidgets('情緒資料不足 → 情緒顯示「—」', (tester) async {
      await pump(
        tester,
        _withData.copyWith(historyTrends: const HistoryTrends()),
      );
      expect(find.text('上市 情緒 —'), findsOneWidget);
      expect(find.text('漲 408 跌 667'), findsOneWidget);
    });

    testWidgets('上櫃指數缺席 → 該指數顯示「—」', (tester) async {
      await pump(
        tester,
        _withData.copyWith(
          indices: [_index(MarketIndexNames.taiex, 48024.6, -132.69, -0.28)],
        ),
      );
      expect(find.text('櫃買 —'), findsOneWidget);
    });

    // 漲跌家數那段載入失敗、指數仍在：不可顯示成 0
    testWidgets('有指數但無漲跌家數 → 漲、跌、情緒都是「—」', (tester) async {
      await pump(tester, _withData.copyWith(advanceDeclineByMarket: const {}));
      expect(find.text('漲 — 跌 —'), findsOneWidget);
      expect(find.text('上市 情緒 —'), findsOneWidget);
    });

    testWidgets('漲跌家數全為 0 → 視同缺席，不顯示 0', (tester) async {
      await pump(
        tester,
        _withData.copyWith(
          advanceDeclineByMarket: const {MarketCode.twse: AdvanceDecline()},
        ),
      );
      expect(find.text('漲 — 跌 —'), findsOneWidget);
    });

    // 最窄的手機同時帶非即時與部分失敗：內容最多時也不能溢出
    testWidgets('320 寬、非即時＋部分失敗 → 不溢出', (tester) async {
      await pump(
        tester,
        _withData.copyWith(
          indexStaleNames: {MarketIndexNames.taiex, MarketIndexNames.tpexIndex},
          failedSections: {'margin', 'chip', 'turnover'},
        ),
        width: 320,
      );
      expect(tester.takeException(), isNull);
      expect(find.text('3 區塊載入失敗'), findsOneWidget);
    });
  });

  group('沒有資料', () {
    // 基準取「兩行都不換行」的資料態（1000 寬）：測試字型字元較寬，390 寬
    // 會多換幾行，那不是實機的高度
    testWidgets('載入中 → 骨架，高度與兩行資料態相近（載入完成版面不跳）', (tester) async {
      await pump(tester, _withData, width: 1000);
      final dataHeight = tester.getSize(find.byType(MarketSummaryStrip)).height;
      await pump(
        tester,
        const MarketOverviewState(isLoading: true),
        width: 1000,
      );
      expect(find.byType(ShimmerContainer), findsWidgets);
      final skeletonHeight = tester
          .getSize(find.byType(MarketSummaryStrip))
          .height;
      expect((skeletonHeight - dataHeight).abs(), lessThanOrEqualTo(4));
    });

    testWidgets('有錯誤 → 錯誤列可重試', (tester) async {
      var retried = 0;
      await pump(
        tester,
        const MarketOverviewState(error: '網路錯誤'),
        onRetry: () => retried++,
      );
      expect(find.text('網路錯誤'), findsOneWidget);
      await tester.tap(find.text('重試'));
      expect(retried, 1);
    });

    testWidgets('無錯誤、非載入中 → 什麼都不渲染', (tester) async {
      await pump(tester, const MarketOverviewState());
      expect(find.byType(Card), findsNothing);
      expect(find.byType(ShimmerContainer), findsNothing);
    });
  });
}
