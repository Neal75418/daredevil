# 今日頁資訊層次重排＋獨立大盤頁 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 今日頁第一屏改為「條件式提示 → 兩行大盤摘要 → 今日訊號」，完整大盤儀表板搬到新的 `/market` 頁。

**Architecture:** 先把儀表板內部的情緒／主指數計算抽成共用 selector（行為不變），摘要條與儀表板共用同一份；新增 `MarketSummaryStrip` 與 `MarketOverviewScreen` 兩個讀取 `marketOverviewProvider` 的元件，不新增任何載入；最後重排 `today_screen.dart` 的 sliver 順序。

**Tech Stack:** Flutter／Dart 3、Riverpod 3、GoRouter 17、easy_localization、flutter_test（golden 走既有 `test/presentation/screens/golden/`）

**Spec:** `docs/plans/2026-09-25-today-hierarchy-market-page-design.md`

## Global Constraints

- 量化標準：390×844 視窗、條件式提示不超過兩條時，「今日訊號」標題不需捲動即可見（扣掉底部導覽約 80pt）
- 大盤仍在訊號之前（摘要條），族群排行、月營收入口、季報入口移到訊號之後
- `MarketDashboard` 內容與排版不改；上市／上櫃切換、寬螢幕並排雙欄保留
- 不新增 provider、不新增 API 呼叫；摘要條與大盤頁只讀 `marketOverviewProvider`
- 缺的欄位顯示「—」、部分區塊失敗要有訊號，不靜默省略
- 所有閾值／字串走常數與 i18n（zh-TW、en 兩份都要加）；路由用 `AppRoutes` 常數
- Widget 測試需 `await setupTestLocalization()`；測試環境 `.tr()` 回傳 key 本身
- commit 由 user 說「提交」才做；每個 Task 結束先送 code-reviewer，通過才進下一個 Task

## Review Focus

- 部分區塊失敗（`failedSections` 非空）但主指數仍在：摘要條要同時顯示數字與失敗警示，不能只顯示其一 → Task 2 測試
- 主指數是資料庫備援值（`indexStaleNames`）：摘要條要標「非即時(日期)」，否則會把昨天收盤當即時值 → Task 2 測試
- 情緒資料不足（漲跌家數有、歷史不足）：情緒欄顯示「—」而不是 50 或 0 → Task 2 測試
- 推薦清單為空／錯誤時（`SliverFillRemaining`）族群排行仍在頁面上、只是被推到下方，不可消失 → Task 4 測試
- 從今日頁進大盤頁不重新載入（讀已在的 state）；在大盤頁下拉才 `loadData()` → Task 3 測試

---

### Task 1: 抽出共用 selector（行為不變）

**Files:**
- Create: `lib/presentation/widgets/market_dashboard/market_overview_selectors.dart`
- Modify: `lib/presentation/widgets/market_dashboard/market_dashboard.dart`（`_indexChangePercent` 約 288-296 行、`_computeSentiment` 約 329-352 行）
- Modify: `lib/presentation/widgets/market_dashboard/sentiment_gauge_section.dart`（`_levelText` 約 194-203 行）
- Test: `test/presentation/widgets/market_dashboard/market_overview_selectors_test.dart`

**Interfaces:**
- Produces:
  - `String heroIndexName(String marketKey)`
  - `TwseMarketIndex? heroIndexOf(MarketOverviewState state, String marketKey)`
  - `MarketSentiment? computeMarketSentiment(MarketOverviewState state, String marketKey)`
  - `String sentimentLevelText(SentimentLevel level)`

- [ ] **Step 1: 寫失敗測試**

```dart
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/constants/market_codes.dart';
import 'package:daredevil/data/models/twse/twse_market_index.dart';
import 'package:daredevil/domain/services/market_sentiment_service.dart';
import 'package:daredevil/presentation/providers/market_overview_provider.dart';
import 'package:daredevil/presentation/widgets/market_dashboard/market_overview_selectors.dart';

import '../../../helpers/widget_test_helpers.dart';

TwseMarketIndex _index(String name, double close, double pct) => TwseMarketIndex(
  date: DateTime(2026, 9, 24),
  name: name,
  close: close,
  change: close * pct / 100,
  changePercent: pct,
);

List<DatedValue> _series(List<double> values) => [
  for (var i = 0; i < values.length; i++)
    (date: DateTime(2026, 9, 1 + i), value: values[i]),
];

void main() {
  setUpAll(() async => setupTestLocalization());

  group('heroIndexOf', () {
    const state = MarketOverviewState();
    test('上市取加權、上櫃取櫃買', () {
      final s = state.copyWith(
        indices: [
          _index(MarketIndexNames.taiex, 48024.6, -0.28),
          _index(MarketIndexNames.tpexIndex, 285.3, 0.1),
        ],
      );
      expect(heroIndexOf(s, MarketCode.twse)!.close, 48024.6);
      expect(heroIndexOf(s, MarketCode.tpex)!.close, 285.3);
    });
    test('查無主指數回 null', () {
      expect(heroIndexOf(state, MarketCode.twse), isNull);
    });
  });

  group('computeMarketSentiment', () {
    const ad = AdvanceDecline(advance: 408, decline: 667, unchanged: 149);
    test('沒有漲跌家數 → null', () {
      expect(computeMarketSentiment(const MarketOverviewState(), MarketCode.twse), isNull);
    });
    test('漲跌家數為 0 → null', () {
      final s = const MarketOverviewState().copyWith(
        advanceDeclineByMarket: {MarketCode.twse: const AdvanceDecline()},
        historyTrends: HistoryTrends(turnover: {MarketCode.twse: _series([1, 2])}),
      );
      expect(computeMarketSentiment(s, MarketCode.twse), isNull);
    });
    test('法人 <5 筆且成交額 <2 筆 → null', () {
      final s = const MarketOverviewState().copyWith(
        advanceDeclineByMarket: {MarketCode.twse: ad},
        historyTrends: HistoryTrends(
          institutionalTotalNet: {MarketCode.twse: _series([1, 2, 3, 4])},
          turnover: {MarketCode.twse: _series([1])},
        ),
      );
      expect(computeMarketSentiment(s, MarketCode.twse), isNull);
    });
    test('資料足夠時與 MarketSentimentService.calculate 同值', () {
      final turnover = [100.0, 120.0, 90.0];
      final s = const MarketOverviewState().copyWith(
        advanceDeclineByMarket: {MarketCode.twse: ad},
        historyTrends: HistoryTrends(turnover: {MarketCode.twse: _series(turnover)}),
      );
      final expected = MarketSentimentService.calculate(
        advanceDecline: ad,
        institutionalNetHistory: const [],
        turnoverHistory: turnover,
        marginBalanceHistory: const [],
      );
      expect(computeMarketSentiment(s, MarketCode.twse)!.score, expected.score);
    });
  });

  test('sentimentLevelText 對應既有 i18n key', () {
    expect(sentimentLevelText(SentimentLevel.fear), 'marketOverview.sentiment.fear');
    expect(sentimentLevelText(SentimentLevel.extremeGreed), 'marketOverview.sentiment.extremeGreed');
  });
}
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `flutter test test/presentation/widgets/market_dashboard/market_overview_selectors_test.dart`
Expected: 編譯失敗，`market_overview_selectors.dart` 不存在

- [ ] **Step 3: 建立 selector 檔**

```dart
import 'package:easy_localization/easy_localization.dart';

import 'package:daredevil/core/constants/market_codes.dart';
import 'package:daredevil/data/models/twse/twse_market_index.dart';
import 'package:daredevil/domain/services/market_sentiment_service.dart';
import 'package:daredevil/presentation/providers/market_overview_provider.dart';

/// 市場主指數名稱：上市取加權指數、上櫃取櫃買指數
String heroIndexName(String marketKey) => marketKey == MarketCode.twse
    ? MarketIndexNames.taiex
    : MarketIndexNames.tpexIndex;

/// 該市場的主指數；查無回 null
TwseMarketIndex? heroIndexOf(MarketOverviewState state, String marketKey) {
  final name = heroIndexName(marketKey);
  for (final idx in state.indices) {
    if (idx.name == name) return idx;
  }
  return null;
}

/// 指定市場的今日情緒分數；資料不足回 null（儀表板與今日頁摘要條共用）
///
/// 今日情緒：各子指標各自用「自己的」完整序列獨立計算，不跨序列對齊，
/// 故僅取各序列的 `.value` 即可。
MarketSentiment? computeMarketSentiment(
  MarketOverviewState state,
  String marketKey,
) {
  final ad = state.advanceDeclineByMarket[marketKey];
  final trends = state.historyTrends;
  final instHist = trends.institutionalTotalNet[marketKey];
  final turnHist = trends.turnover[marketKey];
  final marginHist = trends.marginBalance[marketKey];
  final industries = state.industrySummaryByMarket[marketKey];

  // 至少需要漲跌家數 + 一項歷史資料
  if (ad == null || ad.total == 0) return null;
  if ((instHist == null || instHist.length < 5) &&
      (turnHist == null || turnHist.length < 2)) {
    return null;
  }

  return MarketSentimentService.calculate(
    advanceDecline: ad,
    institutionalNetHistory: _values(instHist) ?? const [],
    turnoverHistory: _values(turnHist) ?? const [],
    marginBalanceHistory: _values(marginHist) ?? const [],
    industries: industries ?? [],
  );
}

/// 情緒等級的顯示文字
String sentimentLevelText(SentimentLevel level) {
  final key = switch (level) {
    SentimentLevel.extremeFear => 'marketOverview.sentiment.extremeFear',
    SentimentLevel.fear => 'marketOverview.sentiment.fear',
    SentimentLevel.neutral => 'marketOverview.sentiment.neutral',
    SentimentLevel.greed => 'marketOverview.sentiment.greed',
    SentimentLevel.extremeGreed => 'marketOverview.sentiment.extremeGreed',
  };
  return key.tr();
}

List<double>? _values(List<DatedValue>? series) =>
    series?.map((e) => e.value).toList();
```

- [ ] **Step 4: 儀表板與情緒區塊改呼叫 selector**

`market_dashboard.dart`：
- `_indexChangePercent(String marketKey)` 本體換成 `=> heroIndexOf(widget.state, marketKey)?.changePercent;`（保留方法與其上方註解）
- `_computeSentiment(String marketKey)` 本體換成 `=> computeMarketSentiment(widget.state, marketKey);`
- 保留 `_values`：儀表板其他區塊（約 488、805、850 行）仍在使用
- 加 import `market_overview_selectors.dart`

`sentiment_gauge_section.dart`：`_levelText(sentiment.level)` 改 `sentimentLevelText(sentiment.level)`，刪除 `_levelText`，加 import。

- [ ] **Step 5: 跑測試**

Run: `flutter test test/presentation/widgets/market_dashboard/ && flutter analyze --no-fatal-infos lib`
Expected: 全綠（含既有 `market_dashboard_test.dart`、`sentiment_gauge_section_test.dart` 不變綠）；analyze 0 issue

- [ ] **Step 6: mutation 驗收**

逐一套用、確認對應測試變紅後還原（用 scratchpad 的 `mutate.sh`，禁止 `git checkout` 還原）：
- `ad.total == 0` → `ad.total < 0`
- `instHist.length < 5` → `instHist.length < 4`
- `turnHist.length < 2` → `turnHist.length < 1`
- `heroIndexName` 的三元兩側對調

- [ ] **Step 7: 送 code-reviewer 審查本 Task，通過後進 Task 2**

---

### Task 2: `MarketSummaryStrip`

**Files:**
- Create: `lib/presentation/screens/today/widgets/market_summary_strip.dart`
- Modify: `assets/translations/zh-TW.json`、`assets/translations/en.json`（`marketOverview` 下新增 `summary` 物件）
- Test: `test/presentation/screens/today/widgets/market_summary_strip_test.dart`

**Interfaces:**
- Consumes: `heroIndexOf`、`computeMarketSentiment`、`sentimentLevelText`（Task 1）
- Produces: `MarketSummaryStrip({required MarketOverviewState state, required VoidCallback onTap, required VoidCallback onRetry})`

- [ ] **Step 1: 加 i18n key**

zh-TW `marketOverview` 內：
```json
"summary": {
  "taiex": "加權",
  "tpex": "櫃買",
  "sentiment": "情緒",
  "advance": "漲",
  "decline": "跌",
  "sectionsFailedShort": "{count} 區塊載入失敗",
  "semantics": "大盤摘要，點擊查看完整大盤"
},
"pageEmpty": "尚無大盤資料，完成一次更新後即可查看"
```
en 對應：`"TAIEX"`、`"TPEx"`、`"Sentiment"`、`"Up"`、`"Down"`、`"{count} sections failed"`、`"Market summary, tap for the full market overview"`、`"No market data yet. Run an update to see it."`

- [ ] **Step 2: 寫失敗測試**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/constants/market_codes.dart';
import 'package:daredevil/core/constants/market_index_names.dart';
import 'package:daredevil/data/models/twse/twse_market_index.dart';
import 'package:daredevil/domain/models/market_overview_models.dart';
import 'package:daredevil/presentation/providers/market_overview_provider.dart';
import 'package:daredevil/presentation/screens/today/widgets/market_summary_strip.dart';
import 'package:daredevil/presentation/widgets/shimmer_loading.dart';

import '../../../../helpers/widget_test_helpers.dart';

TwseMarketIndex _index(String name, double close, double pct) => TwseMarketIndex(
  date: DateTime(2026, 9, 24),
  name: name,
  close: close,
  change: close * pct / 100,
  changePercent: pct,
);

final _withData = MarketOverviewState(
  indices: [
    _index(MarketIndexNames.taiex, 48024.6, -0.28),
    _index(MarketIndexNames.tpexIndex, 285.3, 0.1),
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

void main() {
  setUpAll(() async => setupTestLocalization());

  Future<void> pump(
    WidgetTester tester,
    MarketOverviewState state, {
    VoidCallback? onTap,
    VoidCallback? onRetry,
  }) async {
    await tester.pumpWidget(
      buildTestApp(
        MarketSummaryStrip(
          state: state,
          onTap: onTap ?? () {},
          onRetry: onRetry ?? () {},
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('有資料：兩個主指數、漲跌家數、情緒分數', (tester) async {
    await pump(tester, _withData);
    expect(find.text('48,024.60'), findsOneWidget);
    expect(find.text('-0.28%'), findsOneWidget);
    expect(find.text('285.30'), findsOneWidget);
    expect(find.text('+0.10%'), findsOneWidget);
    expect(find.text('408'), findsOneWidget);
    expect(find.text('667'), findsOneWidget);
    expect(find.text('marketOverview.summary.sentiment'), findsOneWidget);
    expect(find.text('—'), findsNothing);
  });

  testWidgets('主指數是資料庫備援值 → 標「非即時」', (tester) async {
    await pump(
      tester,
      _withData.copyWith(indexStaleNames: {MarketIndexNames.taiex}),
    );
    expect(find.text('marketOverview.indexStale'), findsOneWidget);
  });

  testWidgets('部分區塊失敗 → 數字照顯示並附失敗警示', (tester) async {
    await pump(tester, _withData.copyWith(failedSections: {'margin', 'chip'}));
    expect(find.text('48,024.60'), findsOneWidget);
    expect(find.text('marketOverview.summary.sectionsFailedShort'), findsOneWidget);
  });

  testWidgets('情緒資料不足 → 情緒欄顯示「—」', (tester) async {
    await pump(tester, _withData.copyWith(historyTrends: const HistoryTrends()));
    expect(find.text('—'), findsOneWidget);
    expect(find.text('408'), findsOneWidget);
  });

  testWidgets('上櫃指數缺席 → 該指數顯示「—」', (tester) async {
    await pump(
      tester,
      _withData.copyWith(indices: [_index(MarketIndexNames.taiex, 48024.6, -0.28)]),
    );
    expect(find.text('—'), findsOneWidget);
  });

  testWidgets('載入中且無資料 → 骨架', (tester) async {
    await pump(tester, const MarketOverviewState(isLoading: true));
    expect(find.byType(ShimmerContainer), findsOneWidget);
  });

  testWidgets('無資料有錯誤 → 錯誤列可重試', (tester) async {
    var retried = 0;
    await pump(
      tester,
      const MarketOverviewState(error: '網路錯誤'),
      onRetry: () => retried++,
    );
    await tester.tap(find.text('common.retry'));
    expect(retried, 1);
  });

  testWidgets('無資料無錯誤非載入 → 不渲染', (tester) async {
    await pump(tester, const MarketOverviewState());
    expect(find.byType(InkWell), findsNothing);
  });

  testWidgets('點擊整條 → onTap', (tester) async {
    var taps = 0;
    await pump(tester, _withData, onTap: () => taps++);
    await tester.tap(find.byType(MarketSummaryStrip));
    expect(taps, 1);
  });
}
```


- [ ] **Step 3: 跑測試確認失敗**

Run: `flutter test test/presentation/screens/today/widgets/market_summary_strip_test.dart`
Expected: 編譯失敗，`market_summary_strip.dart` 不存在

- [ ] **Step 4: 實作**

```dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'package:daredevil/core/constants/market_codes.dart';
import 'package:daredevil/core/theme/app_theme.dart';
import 'package:daredevil/core/theme/design_tokens.dart';
import 'package:daredevil/core/theme/semantic_colors.dart';
import 'package:daredevil/data/models/twse/twse_market_index.dart';
import 'package:daredevil/presentation/providers/market_overview_provider.dart';
import 'package:daredevil/presentation/widgets/market_dashboard/market_overview_selectors.dart';
import 'package:daredevil/presentation/widgets/shimmer_loading.dart';

/// 今日頁的大盤摘要條：兩行關鍵數字，點擊進完整大盤頁。
///
/// 與完整儀表板讀同一份 [MarketOverviewState]、同一組 selector，兩處數字
/// 一致。缺的欄位顯示「—」、部分區塊失敗附警示，不靜默省略。
class MarketSummaryStrip extends StatelessWidget {
  const MarketSummaryStrip({
    super.key,
    required this.state,
    required this.onTap,
    required this.onRetry,
  });

  final MarketOverviewState state;
  final VoidCallback onTap;
  final VoidCallback onRetry;

  static const _placeholder = '—';
  static const _padding = EdgeInsets.symmetric(
    horizontal: DesignTokens.spacing16,
    vertical: DesignTokens.spacing4,
  );

  @override
  Widget build(BuildContext context) {
    if (!state.hasData) {
      if (state.isLoading) {
        return const Padding(
          padding: _padding,
          child: ShimmerContainer(width: double.infinity, height: 56),
        );
      }
      if (state.error != null) {
        return Padding(
          padding: _padding,
          child: Card(
            child: ListTile(
              leading: Icon(
                Icons.error_outline,
                color: Theme.of(context).colorScheme.error,
              ),
              title: Text(state.error!),
              trailing: TextButton(
                onPressed: onRetry,
                child: Text('common.retry'.tr()),
              ),
            ),
          ),
        );
      }
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final strong = theme.textTheme.bodyMedium?.copyWith(
      fontWeight: FontWeight.w600,
    );
    final ad = state.advanceDeclineByMarket[MarketCode.twse];
    final hasAd = ad != null && ad.total > 0;
    final sentiment = computeMarketSentiment(state, MarketCode.twse);
    final failed = state.failedSections.length;
    final warningColor = theme.brightness == Brightness.light
        ? WarningColors.warningOnLight
        : WarningColors.warning;

    return Padding(
      padding: _padding,
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: Semantics(
          button: true,
          label: 'marketOverview.summary.semantics'.tr(),
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: DesignTokens.spacing12,
                vertical: DesignTokens.spacing8,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: DesignTokens.spacing6,
                          runSpacing: DesignTokens.spacing2,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            ..._indexParts(
                              context,
                              'marketOverview.summary.taiex'.tr(),
                              heroIndexOf(state, MarketCode.twse),
                              muted,
                              strong,
                            ),
                            Text('・', style: muted),
                            ..._indexParts(
                              context,
                              'marketOverview.summary.tpex'.tr(),
                              heroIndexOf(state, MarketCode.tpex),
                              muted,
                              strong,
                            ),
                          ],
                        ),
                        const SizedBox(height: DesignTokens.spacing4),
                        Wrap(
                          spacing: DesignTokens.spacing6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text('marketOverview.twse'.tr(), style: muted),
                            Text('marketOverview.summary.sentiment'.tr(), style: muted),
                            Text(
                              sentiment == null
                                  ? _placeholder
                                  : sentiment.score.round().toString(),
                              style: strong,
                            ),
                            if (sentiment != null)
                              Text(sentimentLevelText(sentiment.level), style: muted),
                            Text('・', style: muted),
                            Text('marketOverview.summary.advance'.tr(), style: muted),
                            Text(
                              hasAd ? '${ad.advance}' : _placeholder,
                              style: strong?.copyWith(color: context.priceColor(1)),
                            ),
                            Text('marketOverview.summary.decline'.tr(), style: muted),
                            Text(
                              hasAd ? '${ad.decline}' : _placeholder,
                              style: strong?.copyWith(color: context.priceColor(-1)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (failed > 0) ...[
                    Icon(Icons.warning_amber_rounded, size: 16, color: warningColor),
                    const SizedBox(width: DesignTokens.spacing4),
                    Text(
                      'marketOverview.summary.sectionsFailedShort'.tr(
                        namedArgs: {'count': '$failed'},
                      ),
                      style: muted?.copyWith(color: warningColor),
                    ),
                  ],
                  Icon(Icons.chevron_right, color: theme.colorScheme.onSurfaceVariant),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _indexParts(
    BuildContext context,
    String label,
    TwseMarketIndex? index,
    TextStyle? muted,
    TextStyle? strong,
  ) {
    if (index == null) {
      return [Text(label, style: muted), Text(_placeholder, style: strong)];
    }
    final sign = index.changePercent >= 0 ? '+' : '';
    return [
      Text(label, style: muted),
      Text(NumberFormat('#,##0.00').format(index.close), style: strong),
      Text(
        '$sign${index.changePercent.toStringAsFixed(2)}%',
        style: strong?.copyWith(color: context.priceColor(index.change)),
      ),
      if (state.indexStaleNames.contains(index.name))
        Text(
          'marketOverview.indexStale'.tr(
            namedArgs: {'date': '${index.date.month}/${index.date.day}'},
          ),
          style: muted,
        ),
    ];
  }
}
```

- [ ] **Step 5: 跑測試**

Run: `flutter test test/presentation/screens/today/widgets/market_summary_strip_test.dart && flutter analyze --no-fatal-infos lib`
Expected: 全綠；analyze 0 issue

- [ ] **Step 6: mutation 驗收**（逐一改、確認變紅、還原）
- `failed > 0` → `failed > 5`
- `state.indexStaleNames.contains(index.name)` → `false`
- `sentiment == null ? _placeholder : …` → 永遠 `sentiment?.score.round().toString() ?? '0'`
- `hasAd ? '${ad.advance}'` → `'${ad?.advance ?? 0}'`
- `if (state.isLoading)` → `if (false)`
- `onPressed: onRetry` → `onPressed: () {}`

- [ ] **Step 7: 送 code-reviewer 審查本 Task，通過後進 Task 3**

---

### Task 3: `/market` 大盤總覽頁

**Files:**
- Create: `lib/presentation/screens/market/market_overview_screen.dart`
- Modify: `lib/core/constants/app_routes.dart`（新增 `static const market = '/market';`）
- Modify: `lib/app/router.dart`（`/industry` 那組 GoRoute 旁新增）
- Test: `test/presentation/screens/market/market_overview_screen_test.dart`
- Test: `test/app/router_market_route_test.dart`

**Interfaces:**
- Produces: `MarketOverviewScreen()`（無參數，自己 watch `marketOverviewProvider`）；`AppRoutes.market`

- [ ] **Step 1: 寫失敗測試（畫面）**

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/constants/market_codes.dart';
import 'package:daredevil/domain/models/market_overview_models.dart';
import 'package:daredevil/presentation/providers/market_overview_provider.dart';
import 'package:daredevil/presentation/screens/market/market_overview_screen.dart';
import 'package:daredevil/presentation/widgets/market_dashboard/market_dashboard.dart';

import '../../../helpers/provider_test_helpers.dart';
import '../../../helpers/widget_test_helpers.dart';

class _FakeMarket extends MarketOverviewNotifier {
  _FakeMarket(this._initial);
  final MarketOverviewState _initial;
  int loadCalls = 0;

  @override
  MarketOverviewState build() => _initial;

  @override
  Future<void> loadData() async => loadCalls++;
}

const _withData = MarketOverviewState(
  advanceDeclineByMarket: {
    MarketCode.twse: AdvanceDecline(advance: 408, decline: 667, unchanged: 149),
  },
);

void main() {
  setUpAll(() async => setupTestLocalization());

  Future<_FakeMarket> pump(WidgetTester tester, MarketOverviewState s) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final fake = _FakeMarket(s);
    await tester.pumpWidget(
      buildProviderTestApp(
        const MarketOverviewScreen(),
        overrides: [marketOverviewProvider.overrideWith(() => fake)],
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    return fake;
  }

  testWidgets('有資料 → 渲染完整儀表板，進頁不重新載入', (tester) async {
    final fake = await pump(tester, _withData);
    expect(find.byType(MarketDashboard), findsOneWidget);
    expect(fake.loadCalls, 0);
  });

  testWidgets('下拉重新整理 → loadData', (tester) async {
    final fake = await pump(tester, _withData);
    await tester.fling(find.byType(MarketDashboard), const Offset(0, 400), 1000);
    await tester.pumpAndSettle();
    expect(fake.loadCalls, 1);
  });

  testWidgets('無資料有錯誤 → 錯誤可重試', (tester) async {
    final fake = await pump(tester, const MarketOverviewState(error: '網路錯誤'));
    await tester.tap(find.text('common.retry'));
    expect(fake.loadCalls, 1);
  });

  testWidgets('無資料無錯誤 → 空狀態說明', (tester) async {
    await pump(tester, const MarketOverviewState());
    expect(find.text('marketOverview.pageEmpty'), findsOneWidget);
  });
}
```

- [ ] **Step 2: 寫失敗測試（路由）**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:daredevil/app/router.dart';
import 'package:daredevil/core/constants/app_routes.dart';

void main() {
  test('/market 對應到 market 路由', () {
    final match = router.configuration.findMatch(Uri.parse(AppRoutes.market));
    expect((match.last.route as GoRoute).name, 'market');
  });
}
```

- [ ] **Step 3: 跑測試確認失敗**

Run: `flutter test test/presentation/screens/market/ test/app/router_market_route_test.dart`
Expected: 編譯失敗（screen 與 `AppRoutes.market` 不存在）

- [ ] **Step 4: 實作畫面**

```dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:daredevil/core/theme/design_tokens.dart';
import 'package:daredevil/presentation/providers/market_overview_provider.dart';
import 'package:daredevil/presentation/widgets/market_dashboard/market_dashboard.dart';

/// 完整大盤總覽（從今日頁摘要條進入）。
///
/// 讀今日頁已載入的同一份 state，進頁不重新載入；下拉才 [MarketOverviewNotifier.loadData]。
class MarketOverviewScreen extends ConsumerWidget {
  const MarketOverviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(marketOverviewProvider);
    final notifier = ref.read(marketOverviewProvider.notifier);
    return Scaffold(
      appBar: AppBar(title: Text('marketOverview.title'.tr())),
      body: RefreshIndicator(
        onRefresh: notifier.loadData,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(child: _content(context, state, notifier)),
            const SliverToBoxAdapter(
              child: SizedBox(height: DesignTokens.spacing24),
            ),
          ],
        ),
      ),
    );
  }

  Widget _content(
    BuildContext context,
    MarketOverviewState state,
    MarketOverviewNotifier notifier,
  ) {
    if (!state.hasData && !state.isLoading) {
      if (state.error != null) {
        return Padding(
          padding: const EdgeInsets.all(DesignTokens.spacing16),
          child: Card(
            child: ListTile(
              leading: Icon(
                Icons.error_outline,
                color: Theme.of(context).colorScheme.error,
              ),
              title: Text(state.error!),
              trailing: TextButton(
                onPressed: notifier.loadData,
                child: Text('common.retry'.tr()),
              ),
            ),
          ),
        );
      }
      return Padding(
        padding: const EdgeInsets.all(DesignTokens.spacing32),
        child: Text(
          'marketOverview.pageEmpty'.tr(),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    return MarketDashboard(state: state);
  }
}
```

- [ ] **Step 5: 路由**

`app_routes.dart` 新增 `static const market = '/market';`

`router.dart`（`/industry` 那組之後）：
```dart
    // 大盤總覽（全螢幕，Shell 外；今日頁摘要條進入）
    GoRoute(
      path: AppRoutes.market,
      name: 'market',
      builder: (context, state) => const MarketOverviewScreen(),
    ),
```
並 import `package:daredevil/presentation/screens/market/market_overview_screen.dart`。

- [ ] **Step 6: 跑測試**

Run: `flutter test test/presentation/screens/market/ test/app/router_market_route_test.dart && flutter analyze --no-fatal-infos lib`
Expected: 全綠；analyze 0 issue

- [ ] **Step 7: mutation 驗收**
- `onRefresh: notifier.loadData` → `onRefresh: () async {}`
- `onPressed: notifier.loadData` → `onPressed: () {}`
- `!state.hasData && !state.isLoading` → `false`
- 刪掉 router 的 `/market` GoRoute

- [ ] **Step 8: 送 code-reviewer 審查本 Task，通過後進 Task 4**

---

### Task 4: 今日頁重排

**Files:**
- Modify: `lib/presentation/screens/today/today_screen.dart`（大盤卡約 837-870 行；族群／營收／季報約 872-878 行；免責聲明前約 1051 行）
- Modify: `test/helpers/provider_test_helpers.dart`（`buildProviderTestApp` 加選用 `GoRouter? router`）
- Modify: `test/presentation/screens/today/today_screen_test.dart`（`buildTestWidget` 加 `GoRouter? router` 並往下傳；`FakeMarketOverviewNotifier` 加 `static int loadCalls`，`loadData` 內 `loadCalls++`）
- Modify: `test/presentation/screens/golden/today_screen_golden_test.dart`（重產 golden）
- Create: `test/presentation/screens/golden/market_overview_screen_golden_test.dart`

**Interfaces:**
- Consumes: `MarketSummaryStrip`（Task 2）、`AppRoutes.market`（Task 3）

- [ ] **Step 0: 讓測試 helper 可帶 router**

今日頁測試原本包在沒有 GoRouter 的 `MaterialApp(home:)` 裡，`context.push` 在測試中無法驗證。`provider_test_helpers.dart`：

```dart
Widget buildProviderTestApp(
  Widget child, {
  List<Override> overrides = const [],
  Brightness brightness = Brightness.light,
  GoRouter? router,
}) {
  final theme = brightness == Brightness.light
      ? AppTheme.lightTheme
      : AppTheme.darkTheme;
  return ProviderScope(
    overrides: [databaseProvider.overrideWithValue(_testDb), ...overrides],
    // （保留原有 retry 註解）
    retry: (_, _) => null,
    child: router == null
        ? MaterialApp(theme: theme, home: Scaffold(body: child))
        : MaterialApp.router(theme: theme, routerConfig: router),
  );
}
```

`today_screen_test.dart` 的 `buildTestWidget` 加參數 `GoRouter? router`，呼叫 `buildProviderTestApp(const TodayScreen(), overrides: [...], router: router)`。

Run: `flutter test test/presentation/`
Expected: 全綠（helper 改動不影響既有呼叫端）

- [ ] **Step 1: 寫失敗測試（today_screen_test.dart 新 group）**

```dart
  // 訊號是這個 App 的核心；原本大盤儀表板佔約 4.5 屏、訊號在第 6 屏
  group('資訊層次', () {
    MarketOverviewState marketWithData() => const MarketOverviewState(
      advanceDeclineByMarket: {
        MarketCode.twse: AdvanceDecline(advance: 408, decline: 667, unchanged: 149),
      },
    );

    Finder signalsHeader() =>
        find.widgetWithIcon(SectionHeader, Icons.trending_up);

    testWidgets('順序：摘要條 → 今日訊號 → 族群排行', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(
        buildTestWidget(
          todayState: TodayState(dataDate: DateTime(2026, 9, 24)),
          marketState: marketWithData(),
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      final stripY = tester.getTopLeft(find.byType(MarketSummaryStrip)).dy;
      final headerY = tester.getTopLeft(signalsHeader()).dy;
      final industryY = tester.getTopLeft(find.byType(IndustryRankingSection)).dy;
      expect(stripY, lessThan(headerY));
      expect(headerY, lessThan(industryY));
      expect(find.byType(MarketDashboard), findsNothing);
    });

    // 原大盤卡的「錯誤＋重試」接線從來沒有測試；搬到摘要條時補上
    testWidgets('大盤載入失敗可從摘要條重試', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(
        buildTestWidget(
          todayState: TodayState(dataDate: DateTime(2026, 9, 24)),
          marketState: const MarketOverviewState(error: '網路錯誤'),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      final before = FakeMarketOverviewNotifier.loadCalls;

      await tester.tap(find.text('common.retry'));
      await tester.pump();

      expect(FakeMarketOverviewNotifier.loadCalls, before + 1);
    });

    testWidgets('點摘要條 → 進 /market', (tester) async {
      widenViewport(tester);
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const Scaffold(body: TodayScreen()),
          ),
          GoRoute(
            path: AppRoutes.market,
            builder: (_, _) => const Text('market-page'),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        buildTestWidget(
          todayState: TodayState(dataDate: DateTime(2026, 9, 24)),
          marketState: marketWithData(),
          router: router,
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      await tester.tap(find.byType(MarketSummaryStrip));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('market-page'), findsOneWidget);
    });

    testWidgets('🚨 390×844、兩條提示時「今日訊號」標題在第一屏', (tester) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        buildTestWidget(
          // 資料落後 + 歷史建置中＝兩條條件式提示
          todayState: TodayState(
            dataDate: DateTime(2026, 9, 16),
            lastUpdate: DateTime(2026, 9, 16),
          ),
          clock: _FixedClock(DateTime(2026, 9, 18, 17)),
          coverage: const HistoryCoverage(covered: 120, total: 540),
          marketState: marketWithData(),
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('today.dataStale'), findsOneWidget);
      expect(find.text('today.historyBuilding'), findsOneWidget);
      // 底部導覽列約 80pt 會蓋住內容（測試裡沒有 Shell）
      expect(tester.getBottomLeft(signalsHeader()).dy, lessThanOrEqualTo(844 - 80));
    });

    testWidgets('推薦清單為空時族群排行仍在頁面上', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(
        buildTestWidget(
          todayState: TodayState(dataDate: DateTime(2026, 9, 24)),
          modeRecommendations: (ref, mode) => SynchronousFuture(const []),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      await tester.scrollUntilVisible(
        find.byType(IndustryRankingSection),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byType(IndustryRankingSection), findsOneWidget);
    });
  });
```

需 import：`package:go_router/go_router.dart`、`core/constants/app_routes.dart`、`screens/today/widgets/market_summary_strip.dart`、`widgets/industry_ranking_section.dart`、`widgets/market_dashboard/market_dashboard.dart`、`widgets/section_header.dart`、`core/constants/market_codes.dart`、`domain/models/market_overview_models.dart`。

資料日 9/16、時鐘 9/18 17:00 → 落後 2 個交易日（9/17、9/18），資料落後提示必定出現；`coverage` 120/540 → 歷史建置提示出現。

- [ ] **Step 2: 跑測試確認失敗**

Run: `flutter test test/presentation/screens/today/today_screen_test.dart --plain-name 資訊層次`
Expected: FAIL（`MarketSummaryStrip` 不在樹上、`MarketDashboard` 仍在、標題位置超出第一屏）

- [ ] **Step 3: 實作重排**

1. 大盤總覽卡整段（`// 大盤總覽卡片` 那個 `SliverToBoxAdapter`）換成：
```dart
        // 大盤摘要條：一眼看大盤、點進完整大盤頁。原本整張儀表板約佔
        // 4.5 屏、訊號要捲到第 6 屏；完整內容搬到 /market。
        SliverToBoxAdapter(
          child: Consumer(
            builder: (context, ref, _) => MarketSummaryStrip(
              state: ref.watch(marketOverviewProvider),
              onTap: () => context.push(AppRoutes.market),
              onRetry: () =>
                  ref.read(marketOverviewProvider.notifier).loadData(),
            ),
          ),
        ),
```
2. 把 `// 族群排行（L1…）` 的註解與三行 `IndustryRankingSection`、`RevenueFilingEntrySection`、`QuarterlyFilingEntrySection` 從原位置剪下，貼到「推薦清單 — async」那個 `Consumer(...)` 之後、「常駐短版免責聲明」之前，註解改為：
```dart
        // 族群排行與財報入口：原本在個股之前（「族群決定 80%」），自身約
        // 250px 會把訊號擠出第一屏，故移到訊號之後；內容不變。
```
3. 移除不再使用的 `market_dashboard.dart` import（analyze 會提示）；加 import `market_summary_strip.dart`。

- [ ] **Step 4: 跑今日頁全部測試**

Run: `flutter test test/presentation/screens/today/`
Expected: 全綠，含既有「🚨 要跑更新時不必先等大盤的網路載入」

- [ ] **Step 5: golden**

Run: `flutter test test/presentation/screens/golden/today_screen_golden_test.dart --update-goldens`
然後用 Read 工具打開 `goldens/today_screen_light.png`、`today_screen_dark.png`，確認版面是「摘要條 → 訊號」順序（golden 字型是方塊，只看結構）。

新增 `market_overview_screen_golden_test.dart`：比照 `today_screen_golden_test.dart` 的 setUp、字型與尺寸設定，渲染 `MarketOverviewScreen`（`marketOverviewProvider` 覆寫為含漲跌家數的 state），light／dark 各一張，`--update-goldens` 產生後一樣用 Read 檢查。

- [ ] **Step 6: mutation 驗收**
- 摘要條的 `onTap: () => context.push(AppRoutes.market)` → `onTap: () {}`（「點摘要條 → 進 /market」變紅）
- 今日頁傳給摘要條的 `onRetry` 改成 `() {}`（「大盤載入失敗可從摘要條重試」變紅）
- 把族群三行搬回訊號之前 → 順序測試變紅（主要守門）；第一屏測試需帶族群資料（`extraOverrides: withIndustry`）才會一併變紅，且差距部分來自測試字型把摘要條灌高

- [ ] **Step 7: 送 code-reviewer 審查本 Task**

---

### Task 5: 收尾

**Files:**
- Modify: `CHANGELOG.md`（`[Unreleased]` 新增 `### Changed`）

- [ ] **Step 1: CHANGELOG**

```markdown
### Changed

- 今日頁改為「提示 → 大盤摘要 → 今日訊號」：原本大盤儀表板約佔 4.5 屏、訊號要捲到第 6 屏。
  摘要條顯示加權／櫃買指數、上市情緒與漲跌家數，點擊進完整「大盤總覽」頁；族群排行與財報入口移到訊號之後
```

- [ ] **Step 2: 全套驗證**

Run:
```bash
flutter analyze --no-fatal-infos lib
dart compile kernel tool/daily_update.dart -o /tmp/dk.dill
flutter test
```
Expected: analyze 0 issue；CLI 可編譯（確認 presentation 改動沒被拉進純 Dart 鏈）；全套綠

- [ ] **Step 3: 實機確認**

`flutter build macos --debug` 後 `open build/macos/Build/Products/Debug/Daredevil.app`，視窗拉窄到手機寬度，請 user 截第一屏：確認訊號在第一屏、點摘要條進得去大盤頁、返回鍵回得來。

- [ ] **Step 4: 全部 diff 送 code-reviewer 做最後審查，通過後提供 commit 訊息，等 user 說「提交」**
