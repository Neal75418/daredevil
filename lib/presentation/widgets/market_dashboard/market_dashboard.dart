import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';

import 'package:daredevil/core/constants/animations.dart';
import 'package:daredevil/core/constants/market_codes.dart';
import 'package:daredevil/core/constants/app_routes.dart';
import 'package:daredevil/core/theme/breakpoints.dart';
import 'package:daredevil/presentation/providers/market_overview_provider.dart';
import 'package:daredevil/presentation/widgets/market_dashboard/advance_decline_gauge.dart';
import 'package:daredevil/presentation/widgets/market_dashboard/breadth_trend_row.dart';
import 'package:daredevil/presentation/widgets/market_dashboard/hero_index_section.dart';
import 'package:daredevil/presentation/widgets/market_dashboard/institutional_flow_chart.dart';
import 'package:daredevil/presentation/widgets/market_dashboard/margin_compact_row.dart';
import 'package:daredevil/presentation/widgets/market_dashboard/chip_anomaly_row.dart';
import 'package:daredevil/presentation/widgets/market_dashboard/market_reading_line.dart';
import 'package:daredevil/presentation/widgets/market_dashboard/trading_turnover_row.dart';
import 'package:daredevil/presentation/widgets/market_dashboard/sentiment_gauge_section.dart';
import 'package:daredevil/core/theme/design_tokens.dart';
import 'package:daredevil/core/theme/semantic_colors.dart';
import 'package:daredevil/core/utils/date_context.dart';
import 'package:daredevil/core/utils/taiwan_calendar.dart';
import 'package:daredevil/domain/services/market_reading_service.dart';
import 'package:daredevil/domain/services/market_sentiment_service.dart';

/// 大盤總覽 Dashboard
///
/// 組合多個 section 子 widget（Hero 指數、情緒、漲跌家數、量能、
/// 法人動向、融資融券、籌碼異常、產業表現、綜合判讀等），取代舊的
/// MarketOverviewCard。
/// 支援上市/上櫃市場切換，手機使用 Tab，平板/桌面並排顯示。
class MarketDashboard extends StatefulWidget {
  const MarketDashboard({super.key, required this.state});

  final MarketOverviewState state;

  @override
  State<MarketDashboard> createState() => _MarketDashboardState();
}

/// 並排雙欄 view 的寬度門檻
///
/// `Breakpoints.mobile`（600px）作為「mobile 單欄+Tab」與其他的 binary
/// 切換太低 — 601-1023px 區間（iPad portrait、split-screen macOS、小 dev
/// window）會被切到 parallel 雙欄，每欄僅 ~300px 比 phone 還窄但用 desktop
/// 排版。改在 1024px（與 [Breakpoints.tablet] 對齊）才進入並排，medium
/// 寬度維持 tabbed 單欄，閱讀體驗一致。
const double _kParallelViewMinWidth = Breakpoints.tablet;

/// 市場區段（避免使用 magic string）
enum _MarketSegment {
  // ignore: constant_identifier_names
  TWSE,
  // ignore: constant_identifier_names
  TPEx;

  /// 對應 state map 的 key
  String get key => name;
}

class _MarketDashboardState extends State<MarketDashboard> {
  _MarketSegment _selectedMarket = _MarketSegment.TWSE;

  @override
  Widget build(BuildContext context) {
    if (widget.state.isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(
          horizontal: DesignTokens.spacing16,
          vertical: DesignTokens.spacing8,
        ),
        child: Card(
          child: SizedBox(
            height: 120,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
        ),
      );
    }

    if (!widget.state.hasData) return const SizedBox.shrink();

    final theme = Theme.of(context);

    // 有舊資料但最近一次 refresh 失敗時，在 dashboard 頂部顯示提示
    final refreshError = widget.state.error;
    final screenWidth = MediaQuery.of(context).size.width;
    // `isMobile` 涵蓋 phone + medium 螢幕（< 1024px）— 兩者都用 Tab 切換上市/
    // 上櫃單欄，避免 medium 螢幕被 600px 舊門檻塞進並排雙欄而各欄只有 ~300px。
    final isMobile = screenWidth < _kParallelViewMinWidth;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DesignTokens.radiusXl),
          side: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(DesignTokens.spacing16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // refresh 失敗提示（有舊資料仍顯示，但警告使用者資料可能過時）
              if (refreshError != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: DesignTokens.spacing8),
                  child: Row(
                    children: [
                      Icon(
                        Icons.warning_amber,
                        size: 14,
                        color: theme.colorScheme.error,
                      ),
                      const SizedBox(width: DesignTokens.spacing4),
                      Expanded(
                        child: Text(
                          refreshError,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),

              // 區塊載入失敗提示（靜默稽核 #7）
              //
              // 與上方 refreshError 的差別：那條是「整輪 load 拋例外」，
              // 這條是「主流程成功、但 N 個區塊各自 catch→空」——後者原本
              // 完全不可見，失敗區塊與「今天很平靜」逐 pixel 相同。
              // app-global 放標題上方（非 per-market），與失敗語意一致。
              if (widget.state.failedSections.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: DesignTokens.spacing8),
                  child: Row(
                    children: [
                      Icon(
                        Icons.warning_amber,
                        size: 14,
                        color: theme.brightness == Brightness.light
                            ? WarningColors.warningOnLight
                            : WarningColors.warning,
                      ),
                      const SizedBox(width: DesignTokens.spacing4),
                      Expanded(
                        child: Text(
                          'marketOverview.sectionsFailed'.tr(
                            namedArgs: {
                              'count': '${widget.state.failedSections.length}',
                            },
                          ),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.brightness == Brightness.light
                                ? WarningColors.warningOnLight
                                : WarningColors.warning,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),

              // 標題列（包含市場選擇器）
              _buildHeader(theme, isMobile),

              const SizedBox(height: DesignTokens.spacing16),

              // 主內容區域
              if (isMobile)
                _buildMobileView(theme)
              else
                _buildParallelView(theme),
            ],
          ),
        ),
      ),
    ).animate().fadeIn(duration: AnimDurations.standard);
  }

  /// 建構標題列
  Widget _buildHeader(ThemeData theme, bool isMobile) {
    final dataDate = widget.state.dataDate;
    final now = DateTime.now();
    final latestTradingDay = TaiwanCalendar.isTradingDay(now)
        ? DateContext.normalize(now)
        : TaiwanCalendar.getPreviousTradingDay(now);
    final isLatest =
        dataDate != null &&
        dataDate.year == latestTradingDay.year &&
        dataDate.month == latestTradingDay.month &&
        dataDate.day == latestTradingDay.day;

    return Row(
      children: [
        Icon(Icons.show_chart, size: 18, color: theme.colorScheme.primary),
        const SizedBox(width: DesignTokens.spacing8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'marketOverview.title'.tr(),
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            // 顯示近似資料日期：dashboard 各區塊可能來自不同日期
            // （by-market 回退、融資融券各市場最新值等），以 ≈ 標示
            if (dataDate != null)
              Text(
                '≈ ${DateFormat('MM/dd').format(dataDate)}${isLatest ? '' : ' ${'marketOverview.notToday'.tr()}'}',
                style: theme.textTheme.labelSmall?.copyWith(
                  // 舊值 withAlpha(178)≈0.7 對卡片僅 2.97~3.60:1，
                  // 「非今日」的區隔已由文案表達，不再犧牲可讀性
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
        const Spacer(),
        // 市場選擇器（手機顯示）
        if (isMobile) _buildMarketSelector(theme),
      ],
    );
  }

  /// 建構市場選擇器（SegmentedButton）
  Widget _buildMarketSelector(ThemeData theme) {
    return SegmentedButton<_MarketSegment>(
      segments: [
        ButtonSegment(
          value: _MarketSegment.TWSE,
          label: Text(
            'marketOverview.twse'.tr(),
            style: const TextStyle(fontSize: DesignTokens.fontSizeSm),
          ),
        ),
        ButtonSegment(
          value: _MarketSegment.TPEx,
          label: Text(
            'marketOverview.tpex'.tr(),
            style: const TextStyle(fontSize: DesignTokens.fontSizeSm),
          ),
        ),
      ],
      selected: {_selectedMarket},
      onSelectionChanged: (Set<_MarketSegment> newSelection) {
        setState(() {
          _selectedMarket = newSelection.first;
        });
      },
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        padding: WidgetStateProperty.all(
          const EdgeInsets.symmetric(
            horizontal: DesignTokens.spacing12,
            vertical: DesignTokens.spacing6,
          ),
        ),
      ),
    );
  }

  /// 取得指定市場 Hero 指數的漲跌幅（%）
  ///
  /// 供量價 / 籌碼槓桿判讀使用（TWSE→加權指數、TPEx→櫃買指數）。
  /// 找不到對應指數時回傳 null，判讀行不顯示。
  /// 籌碼槓桿判讀專用：取**融資資料那天**的指數漲跌幅。
  ///
  /// 不可改用 [_indexChangePercent]（最新值）——融資融券由 TWSE 約 21:00
  /// 發布，傍晚更新時常落後 1~3 天，兩者相配會讓因果陳述反轉：2026-07-27
  /// 實測櫃買 07-24 為 -3.69%、07-27 為 +0.12%，取後者會把「去槓桿中」
  /// 講成「籌碼洗清，相對健康」（方向相反且更樂觀）。
  /// 查不到對應日時回 null，判讀行不顯示。
  double? _marginIndexChangePercent(String marketKey) =>
      widget.state.marginIndexChangePercent[marketKey];

  double? _indexChangePercent(String marketKey) {
    final heroName = marketKey == MarketCode.twse
        ? MarketIndexNames.taiex
        : MarketIndexNames.tpexIndex;
    for (final idx in widget.state.indices) {
      if (idx.name == heroName) return idx.changePercent;
    }
    return null;
  }

  /// 綜合判讀行（top-level，見 [MarketReadingService.interpretCompositeSynthesis]）
  ///
  /// 顯示於各市場欄位頂部（Hero 指數下方），需指數漲跌幅 + 漲跌家數才有意義，
  /// 任一缺失時回傳 null（不顯示，避免用 0 家數誤判內部偏強/偏弱）。法人
  /// 合計缺資料時視為 0（[InstitutionalTotals] 預設值），僅影響背離規則是否
  /// 命中，不影響本行是否顯示。
  Widget? _buildCompositeSynthesisLine(String market) {
    final indexChangePercent = _indexChangePercent(market);
    final ad = widget.state.advanceDeclineByMarket[market];
    if (indexChangePercent == null || ad == null || ad.total <= 0) {
      return null;
    }
    final institutionalTotalNet =
        widget.state.institutionalByMarket[market]?.totalNet ?? 0;
    final reading = MarketReadingService.interpretCompositeSynthesis(
      market: market,
      indexChangePercent: indexChangePercent,
      advance: ad.advance,
      decline: ad.decline,
      unchanged: ad.unchanged,
      institutionalTotalNet: institutionalTotalNet,
    );
    // prominent: true — 升層為市場欄位頂部的視覺焦點，與其餘 per-section
    // 判讀行（維持預設 muted）區隔。
    return MarketReadingLine(reading: reading, prominent: true);
  }

  /// 計算指定市場的市場情緒分數
  ///
  /// 今日情緒：各子指標各自用「自己的」完整序列獨立計算，不跨序列對齊，
  /// 故僅取各序列的 `.value` 即可。
  MarketSentiment? _computeSentiment(String marketKey) {
    final ad = widget.state.advanceDeclineByMarket[marketKey];
    final trends = widget.state.historyTrends;
    final instHist = trends.institutionalTotalNet[marketKey];
    final turnHist = trends.turnover[marketKey];
    final marginHist = trends.marginBalance[marketKey];
    final industries = widget.state.industrySummaryByMarket[marketKey];

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

  /// 計算歷史情緒分數序列（供趨勢 sparkline）
  ///
  /// 將四個帶日期序列原樣傳入，由 [MarketSentimentService.calculateHistoricalScores]
  /// 依日期 inner-join 對齊（不同 coverage 來源日期集不同，不可按 index 拼接）。
  List<double> _computeSentimentHistory(String marketKey) {
    final trends = widget.state.historyTrends;
    final advRatioHist = trends.advanceRatio[marketKey];
    final instHist = trends.institutionalTotalNet[marketKey];
    final turnHist = trends.turnover[marketKey];
    final marginHist = trends.marginBalance[marketKey];

    if (advRatioHist == null ||
        instHist == null ||
        turnHist == null ||
        marginHist == null) {
      return [];
    }

    return MarketSentimentService.calculateHistoricalScores(
      advanceRatioHistory: advRatioHist,
      institutionalNetHistory: instHist,
      turnoverHistory: turnHist,
      marginBalanceHistory: marginHist,
    );
  }

  /// 取帶日期序列的「完整」值序列（供個別 sparkline / 今日情緒）。
  ///
  /// 個別 sparkline 必須保留各自完整序列，不可縮到四序列日期交集。
  static List<double>? _values(List<DatedValue>? series) =>
      series?.map((e) => e.value).toList();

  /// 建構手機單欄顯示
  Widget _buildMobileView(ThemeData theme) {
    final sections = <Widget>[];

    // Section 1: Hero 加權指數（僅 TWSE）
    if (_selectedMarket == _MarketSegment.TWSE) {
      final taiex = widget.state.indices
          .where((idx) => idx.name == MarketIndexNames.taiex)
          .toList();

      if (taiex.isNotEmpty) {
        sections.add(
          HeroIndexSection(
            index: taiex.first,
            isStale: widget.state.indexStaleNames.contains(taiex.first.name),
            historyData: widget.state.indexHistory[taiex.first.name] ?? [],
            stageHistory:
                widget.state.indexStageHistory[taiex.first.name] ?? [],
            totalReturnHistory:
                widget.state.indexHistory[MarketIndexNames.totalReturnIndex] ??
                [],
          ),
        );
      } else {
        // 上櫃分支與 parallel 檢視都有兜底文案,唯獨這裡沒有——指數全掛
        // 時 Hero 卡整張消失且零文案(2026-08-29 review)
        sections.add(
          Padding(
            padding: const EdgeInsets.all(DesignTokens.spacing16),
            child: Text(
              'marketOverview.noData'.tr(),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        );
      }
    } else {
      // 上櫃：顯示櫃買指數 Hero
      final tpexIdx = widget.state.indices
          .where((idx) => idx.name == MarketIndexNames.tpexIndex)
          .toList();

      if (tpexIdx.isNotEmpty) {
        sections.add(
          HeroIndexSection(
            index: tpexIdx.first,
            isStale: widget.state.indexStaleNames.contains(tpexIdx.first.name),
            historyData:
                widget.state.indexHistory[MarketIndexNames.tpexIndex] ?? [],
            stageHistory:
                widget.state.indexStageHistory[MarketIndexNames.tpexIndex] ??
                [],
          ),
        );
      } else {
        sections.add(
          Padding(
            padding: const EdgeInsets.all(DesignTokens.spacing16),
            child: Text(
              'marketOverview.tpexNoIndex'.tr(),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        );
      }
    }

    // Section: 綜合判讀（top-level，緊接 Hero 指數，見「top of column」定位）
    final synthesisLine = _buildCompositeSynthesisLine(_selectedMarket.key);
    if (synthesisLine != null) sections.add(synthesisLine);

    // Section: 市場情緒儀表板
    final marketKey = _selectedMarket.key;
    final sentiment = _computeSentiment(marketKey);
    if (sentiment != null) {
      sections.add(
        SentimentGaugeSection(
          sentiment: sentiment,
          market: marketKey,
          sentimentHistory: _computeSentimentHistory(marketKey),
        ),
      );
    }

    // Section 3+: 統計數據（依選擇的市場顯示）
    final instData = widget.state.institutionalByMarket[marketKey];
    final marginData = widget.state.marginByMarket[marketKey];
    final turnoverData = widget.state.turnoverByMarket[marketKey];
    final turnoverComparison =
        widget.state.turnoverComparisonByMarket[marketKey];
    final warningCounts = widget.state.warningCountsByMarket[marketKey];
    final instStreak = widget.state.institutionalStreakByMarket[marketKey];

    // 30日歷史趨勢
    //
    // 個別 sparkline 取各自「完整」序列（map 到 .value），不縮到情緒對齊交集；
    // shortBalance 本來就是純 double（不參與情緒對齊）。
    final trends = widget.state.historyTrends;
    final instNetHist = _values(trends.institutionalTotalNet[marketKey]);
    final turnoverHist = _values(trends.turnover[marketKey]);
    final marginHist = _values(trends.marginBalance[marketKey]);
    final shortHist = trends.shortBalance[marketKey];

    // 走共用 builder：含「漲跌家數為前一交易日 fallback」的明顯標示（手機與桌面一致）
    final adSection = _buildAdvanceDeclineSection(marketKey);
    if (adSection != null) sections.add(adSection);

    // 市場廣度趨勢（52 週新高新低 + AD 騰落線）— 緊接漲跌家數，廣度快照 + 趨勢同處
    final breadthTrend = _buildBreadthTrendSection(marketKey);
    if (breadthTrend != null) sections.add(breadthTrend);

    // 成交量統計
    if (turnoverData != null && turnoverData.totalTurnover > 0) {
      sections.add(
        TradingTurnoverRow(
          data: turnoverData,
          turnoverComparison: turnoverComparison,
          turnoverHistory: turnoverHist,
          indexChangePercent: _indexChangePercent(marketKey),
        ),
      );
    }

    if (instData != null &&
        (instData.totalNet != 0 ||
            instData.foreignNet != 0 ||
            instData.trustNet != 0 ||
            instData.dealerNet != 0)) {
      sections.add(
        _wrapWithDateIndicator(
          sectionKey: MarketOverviewState.kSectionInstitutional,
          child: InstitutionalFlowChart(
            data: instData,
            streak: instStreak,
            totalNetHistory: instNetHist,
          ),
        ),
      );
    }

    if (marginData != null &&
        (marginData.marginChange != 0 || marginData.shortChange != 0)) {
      sections.add(
        _wrapWithDateIndicator(
          sectionKey: MarketOverviewState.kSectionMargin,
          child: MarginCompactRow(
            data: marginData,
            marginBalanceHistory: marginHist,
            shortBalanceHistory: shortHist,
            indexChangePercent: _marginIndexChangePercent(marketKey),
          ),
        ),
      );
    }

    // 籌碼異動（標題列併入 注意/處置 徽章，取代原本獨立一列）
    final chipAnomalies = widget.state.chipAnomaliesByMarket[marketKey];
    final anomalyFails = widget.state.chipAnomalyFailedDetectors;
    final detectorFails = anomalyFails.where((k) => k != 'etfFilter').length;
    final etfFilterFailed = anomalyFails.contains('etfFilter');
    if ((chipAnomalies != null && chipAnomalies.isNotEmpty) ||
        (warningCounts != null && warningCounts.total > 0) ||
        anomalyFails.isNotEmpty) {
      sections.add(
        ChipAnomalyRow(
          anomalies: chipAnomalies ?? const [],
          warningCounts: warningCounts,
          failedDetectorCount: detectorFails,
          etfFilterUnavailable: etfFilterFailed,
          onStockTap: (symbol) => context.push(AppRoutes.stockDetail(symbol)),
        ),
      );
    }

    // 組合所有 sections
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < sections.length; i++) ...[
          if (i < 2)
            // Hero 與其後第一個 section 之間用較小間距，不加分隔線
            const SizedBox(height: DesignTokens.spacing10)
          else ...[
            const SizedBox(height: DesignTokens.spacing14),
            Divider(
              height: 1,
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.2),
            ),
            const SizedBox(height: DesignTokens.spacing14),
          ],
          sections[i],
        ],
      ],
    );
  }

  /// 建構平板/桌面並排顯示
  ///
  /// 使用跨欄配對方式，每個 section 型別左右配成一組 [IntrinsicHeight] + [Row]，
  /// 確保對應 section 水平對齊，避免左右高度差異導致後續 section 錯位。
  Widget _buildParallelView(ThemeData theme) {
    // 市場情緒（TWSE + TPEx 對稱計算，兩側各自資料是否足夠獨立判定）。
    // 2026-08-13 起與其他 section 一樣走 _buildPairedRow:原本因
    // SentimentGaugeSection 內部有 LayoutBuilder 而與 IntrinsicHeight 不相容,
    // 只能用固定 222px 分隔線(收摺實測 172,白吃 50px)——LayoutBuilder 已
    // 全數移除(_GradientBar→Align、_SubScoresGrid→Row+Expanded)。
    final twseSentiment = _buildSentimentSection(MarketCode.twse);
    final tpexSentiment = _buildSentimentSection(MarketCode.tpex);

    // 每個 section builder 返回 Widget?，null 表示該市場無此資料
    // （注意/處置已併入 _buildChipAnomalySection 標題列，無獨立 builder）
    final sectionBuilders = <Widget? Function(String)>[
      _buildAdvanceDeclineSection,
      _buildBreadthTrendSection,
      _buildTurnoverSection,
      _buildInstitutionalSection,
      _buildMarginSection,
      _buildChipAnomalySection,
    ];

    // 產生配對的 section rows（跳過兩側皆無資料的 section）
    final pairedRows = <Widget>[];
    for (final builder in sectionBuilders) {
      final twse = builder(MarketCode.twse);
      final tpex = builder(MarketCode.tpex);
      if (twse == null && tpex == null) continue;
      pairedRows.add(_buildPairedRow(theme, twse, tpex));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (twseSentiment != null || tpexSentiment != null) ...[
          _buildPairedRow(theme, twseSentiment, tpexSentiment),
          const SizedBox(height: DesignTokens.spacing14),
          Divider(
            height: 1,
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.2),
          ),
          const SizedBox(height: DesignTokens.spacing14),
        ],

        // 標題 + Hero 指數配對
        _buildPairedRow(
          theme,
          _buildMarketHeader(theme, MarketCode.twse),
          _buildMarketHeader(theme, MarketCode.tpex),
        ),

        // 資料 section 配對（每對等高對齊）
        for (final row in pairedRows) ...[
          const SizedBox(height: DesignTokens.spacing12),
          Divider(
            height: 1,
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.2),
          ),
          const SizedBox(height: DesignTokens.spacing12),
          row,
        ],
      ],
    );
  }

  /// 建構配對的跨欄 Row（左右等高）
  /// ⚠️ IntrinsicHeight 子樹的不變量(2026-08-13 展開細項實炸後定案):
  /// 不是「不得有 LayoutBuilder」,而是「LayoutBuilder 必須被 **tight 高度**
  /// 短路」——RenderConstrainedBox 對 tight 約束直接回傳、不下探 intrinsic
  /// (例:institutional_flow_chart 的 LayoutBuilder 安全,因為包在
  /// SizedBox(height: 4) 裡)。裸露的 LayoutBuilder 會在量 intrinsic 時
  /// 丟例外,而且**收摺路徑測不到**——守門:market_dashboard_test 的
  /// 展開探針。
  Widget _buildPairedRow(ThemeData theme, Widget? left, Widget? right) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: left ?? const SizedBox.shrink()),
          VerticalDivider(
            width: 32,
            thickness: 1,
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.2),
          ),
          Expanded(child: right ?? const SizedBox.shrink()),
        ],
      ),
    );
  }

  /// 建構市場標題 + Hero 指數
  Widget _buildMarketHeader(ThemeData theme, String market) {
    final heroName = market == MarketCode.twse
        ? MarketIndexNames.taiex
        : MarketIndexNames.tpexIndex;
    final heroIdx = widget.state.indices
        .where((idx) => idx.name == heroName)
        .toList();

    // TPEx 側保留與 TWSE badge 等高的空間
    final shouldReserveBadge =
        market == MarketCode.tpex &&
        (widget.state.indexHistory[MarketIndexNames.taiex]?.length ?? 0) >= 2 &&
        (widget.state.indexHistory[MarketIndexNames.totalReturnIndex]?.length ??
                0) >=
            2;

    // 綜合判讀（top-level，緊接 Hero 指數，位於欄位最上方）
    final synthesis = _buildCompositeSynthesisLine(market);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          marketLabelKey(market).tr(),
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.primary,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: DesignTokens.spacing12),
        if (heroIdx.isNotEmpty)
          HeroIndexSection(
            index: heroIdx.first,
            isStale: widget.state.indexStaleNames.contains(heroIdx.first.name),
            historyData: widget.state.indexHistory[heroName] ?? [],
            stageHistory: widget.state.indexStageHistory[heroName] ?? [],
            totalReturnHistory: market == MarketCode.twse
                ? widget.state.indexHistory[MarketIndexNames
                          .totalReturnIndex] ??
                      []
                : [],
            reserveBadgeSpace: shouldReserveBadge,
          )
        else
          Padding(
            padding: const EdgeInsets.all(DesignTokens.spacing16),
            child: Text(
              'marketOverview.noData'.tr(),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ?synthesis,
      ],
    );
  }

  // ==================================================
  // Section date indicator
  // ==================================================

  /// 若該區塊的實際資料日期比主日期舊，在右上角顯示小日期標籤
  Widget _wrapWithDateIndicator({
    required String sectionKey,
    required Widget child,
  }) {
    final sectionDate = widget.state.sectionDates[sectionKey];
    final mainDate = widget.state.dataDate;
    if (sectionDate == null || mainDate == null) return child;

    // 只在 section 日期比主日期舊時才顯示
    final sectionDay = DateTime(
      sectionDate.year,
      sectionDate.month,
      sectionDate.day,
    );
    final mainDay = DateTime(mainDate.year, mainDate.month, mainDate.day);
    if (!sectionDay.isBefore(mainDay)) return child;

    final theme = Theme.of(context);
    return Stack(
      children: [
        child,
        Positioned(
          top: 0,
          right: 0,
          child: Text(
            '${sectionDate.month}/${sectionDate.day}',
            style: theme.textTheme.labelSmall?.copyWith(
              fontSize: 10,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }

  // ==================================================
  // Section builders
  // ==================================================

  /// 市場情緒儀表板 section（TWSE / TPEx 對稱計算）
  ///
  /// [_computeSentiment] 本身即以 marketKey 參數化（無 TWSE 硬編碼），兩市場
  /// 走同一組 guard（漲跌家數 + 至少一項歷史資料，見該方法文件）。資料不足
  /// 時回傳 null，該市場欄位不顯示（與其餘 section 一致的優雅降級）。
  Widget? _buildSentimentSection(String market) {
    final sentiment = _computeSentiment(market);
    if (sentiment == null) return null;
    return SentimentGaugeSection(
      sentiment: sentiment,
      market: market,
      sentimentHistory: _computeSentimentHistory(market),
    );
  }

  Widget? _buildAdvanceDeclineSection(String market) {
    final adData = widget.state.advanceDeclineByMarket[market];
    if (adData == null || adData.total <= 0) return null;
    final gauge = AdvanceDeclineGauge(
      data: adData,
      limitUpDown: widget.state.limitUpDownByMarket[market],
      advanceRatioHistory: _values(
        widget.state.historyTrends.advanceRatio[market],
      ),
    );
    // 該市場漲跌家數為前一交易日 fallback（當日個股未釋出）時，明顯標示避免把
    // 舊日廣度誤讀成今日（per-market，與全域 sectionDates 不同口徑）。
    final staleDate = widget.state.advanceDeclineStaleDates[market];
    final mainDate = widget.state.dataDate;
    // 兩者都需在；mainDate 缺時（理論上不會，與 staleDates 同批由 _buildState 設定）
    // 退回純 gauge，避免標示出現空白日期。
    if (staleDate == null || mainDate == null) return gauge;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StaleBreadthBadge(dataDate: staleDate, mainDate: mainDate),
        const SizedBox(height: DesignTokens.spacing6),
        gauge,
      ],
    );
  }

  /// 市場廣度趨勢 section（52 週新高新低 + AD 騰落線）
  ///
  /// 兩項資料皆無時回傳 null（該市場不顯示此 section）。
  Widget? _buildBreadthTrendSection(String market) {
    final newHighLow = widget.state.newHighLowByMarket[market];
    final adLine = widget.state.adLineByMarket[market];

    final hasNewHighLow = newHighLow != null;
    final hasAdLine = adLine != null && adLine.length >= 2;
    if (!hasNewHighLow && !hasAdLine) return null;

    return BreadthTrendRow(
      newHighLow: newHighLow,
      adLine: adLine,
      indexChangePercent: _indexChangePercent(market),
    );
  }

  Widget? _buildTurnoverSection(String market) {
    final turnoverData = widget.state.turnoverByMarket[market];
    if (turnoverData == null || turnoverData.totalTurnover <= 0) return null;
    return TradingTurnoverRow(
      data: turnoverData,
      turnoverComparison: widget.state.turnoverComparisonByMarket[market],
      turnoverHistory: _values(widget.state.historyTrends.turnover[market]),
      indexChangePercent: _indexChangePercent(market),
    );
  }

  Widget? _buildInstitutionalSection(String market) {
    final instData = widget.state.institutionalByMarket[market];
    if (instData == null ||
        (instData.totalNet == 0 &&
            instData.foreignNet == 0 &&
            instData.trustNet == 0 &&
            instData.dealerNet == 0)) {
      return null;
    }
    return _wrapWithDateIndicator(
      sectionKey: MarketOverviewState.kSectionInstitutional,
      child: InstitutionalFlowChart(
        data: instData,
        streak: widget.state.institutionalStreakByMarket[market],
        totalNetHistory: _values(
          widget.state.historyTrends.institutionalTotalNet[market],
        ),
      ),
    );
  }

  Widget? _buildMarginSection(String market) {
    final marginData = widget.state.marginByMarket[market];
    if (marginData == null ||
        (marginData.marginChange == 0 && marginData.shortChange == 0)) {
      return null;
    }
    return _wrapWithDateIndicator(
      sectionKey: MarketOverviewState.kSectionMargin,
      child: MarginCompactRow(
        data: marginData,
        marginBalanceHistory: _values(
          widget.state.historyTrends.marginBalance[market],
        ),
        shortBalanceHistory: widget.state.historyTrends.shortBalance[market],
        indexChangePercent: _marginIndexChangePercent(market),
      ),
    );
  }

  /// 籌碼異動 section（標題列併入 注意/處置 徽章，取代原本獨立一列）
  Widget? _buildChipAnomalySection(String market) {
    final chipAnomalies = widget.state.chipAnomaliesByMarket[market];
    final warningCounts = widget.state.warningCountsByMarket[market];
    final anomalyFails = widget.state.chipAnomalyFailedDetectors;
    final detectorFails = anomalyFails.where((k) => k != 'etfFilter').length;
    final hasAnomalies = chipAnomalies != null && chipAnomalies.isNotEmpty;
    final hasWarnings = warningCounts != null && warningCounts.total > 0;
    if (!hasAnomalies && !hasWarnings && anomalyFails.isEmpty) return null;
    return ChipAnomalyRow(
      anomalies: chipAnomalies ?? const [],
      warningCounts: warningCounts,
      failedDetectorCount: detectorFails,
      etfFilterUnavailable: anomalyFails.contains('etfFilter'),
      onStockTap: (symbol) => context.push(AppRoutes.stockDetail(symbol)),
    );
  }
}

/// 漲跌家數使用前一交易日 fallback 時的明顯標示。
///
/// 當某市場當日個股資料未釋出，廣度回退到 [dataDate]（前一交易日）。此 badge
/// 點明「顯示的是哪天、哪天還沒釋出」，避免把舊日廣度誤讀成今日。
class _StaleBreadthBadge extends StatelessWidget {
  const _StaleBreadthBadge({required this.dataDate, required this.mainDate});

  final DateTime dataDate;
  final DateTime mainDate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final warning = DesignTokens.warningColor(theme);
    // tint 用 warning 識別色；文字/圖示走疊色專屬色（同色前景對
    // @0.118 合成底不足 4.5:1）
    final onTint = WarningColors.onTintFor(theme.brightness);
    final text = 'marketOverview.staleBreadth'.tr(
      namedArgs: {
        'dataDate': '${dataDate.month}/${dataDate.day}',
        'mainDate': '${mainDate.month}/${mainDate.day}',
      },
    );
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: DesignTokens.spacing8,
        vertical: DesignTokens.spacing4,
      ),
      decoration: BoxDecoration(
        color: warning.withAlpha(30),
        borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.history, size: 12, color: onTint),
          const SizedBox(width: DesignTokens.spacing4),
          Flexible(
            child: Text(
              text,
              style: theme.textTheme.labelSmall?.copyWith(
                fontSize: DesignTokens.fontSizeXs,
                color: onTint,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
