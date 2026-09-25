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
///
/// 每組（一個指數、情緒、漲跌家數）是一個 [Text.rich]：換行只發生在組與
/// 組之間，標籤不會和數值拆到不同行。
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
  static const _outerPadding = EdgeInsets.symmetric(
    horizontal: DesignTokens.spacing16,
    vertical: DesignTokens.spacing4,
  );
  static const _innerPadding = EdgeInsets.symmetric(
    horizontal: DesignTokens.spacing12,
    vertical: DesignTokens.spacing8,
  );

  @override
  Widget build(BuildContext context) {
    // 重新整理時 provider 保留舊資料（isLoading 與資料並存），照顯示資料，
    // 只有「完全沒資料」才看載入中／錯誤
    if (!state.hasData) {
      if (state.isLoading) return _skeleton();
      if (state.error != null) return _errorRow(context);
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final strong = theme.textTheme.bodyMedium?.copyWith(
      fontWeight: FontWeight.w600,
    );
    final warningColor = theme.brightness == Brightness.light
        ? WarningColors.warningOnLight
        : WarningColors.warning;
    final failed = state.failedSections.length;
    final separator = ExcludeSemantics(child: Text('・', style: muted));

    return Padding(
      padding: _outerPadding,
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: Semantics(
          button: true,
          label: 'marketOverview.summary.semantics'.tr(),
          onTapHint: 'marketOverview.summary.tapHint'.tr(),
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: _innerPadding,
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: DesignTokens.spacing6,
                          runSpacing: DesignTokens.spacing2,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            _indexGroup(
                              context,
                              'marketOverview.summary.taiex'.tr(),
                              heroIndexOf(state, MarketCode.twse),
                              muted: muted,
                              strong: strong,
                              warningColor: warningColor,
                            ),
                            separator,
                            _indexGroup(
                              context,
                              'marketOverview.summary.tpex'.tr(),
                              heroIndexOf(state, MarketCode.tpex),
                              muted: muted,
                              strong: strong,
                              warningColor: warningColor,
                            ),
                          ],
                        ),
                        const SizedBox(height: DesignTokens.spacing4),
                        Wrap(
                          spacing: DesignTokens.spacing6,
                          runSpacing: DesignTokens.spacing2,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            _sentimentGroup(muted: muted, strong: strong),
                            separator,
                            _breadthGroup(
                              context,
                              muted: muted,
                              strong: strong,
                            ),
                          ],
                        ),
                        // 已有資料但重新整理失敗：舊數字照顯示，附錯誤讓人知道可能
                        // 過時（與大盤頁儀表板頂端同一條警示）
                        if (state.error != null) ...[
                          const SizedBox(height: DesignTokens.spacing4),
                          Row(
                            children: [
                              Icon(
                                Icons.warning_amber,
                                size: 14,
                                color: theme.colorScheme.error,
                              ),
                              const SizedBox(width: DesignTokens.spacing4),
                              Flexible(
                                child: Text(
                                  state.error!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: muted?.copyWith(
                                    color: theme.colorScheme.error,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                        // 部分區塊失敗：獨立一行（可換行），不跟數字搶同一列寬度
                        if (failed > 0) ...[
                          const SizedBox(height: DesignTokens.spacing4),
                          Row(
                            children: [
                              Icon(
                                Icons.warning_amber,
                                size: 14,
                                color: warningColor,
                              ),
                              const SizedBox(width: DesignTokens.spacing4),
                              Flexible(
                                child: Text(
                                  'marketOverview.summary.sectionsFailedShort'
                                      .tr(namedArgs: {'count': '$failed'}),
                                  style: muted?.copyWith(color: warningColor),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 「加權 48,024.60 -0.28%」＋（備援值時）「非即時(9/24)」
  Widget _indexGroup(
    BuildContext context,
    String label,
    TwseMarketIndex? index, {
    required TextStyle? muted,
    required TextStyle? strong,
    required Color warningColor,
  }) {
    if (index == null) {
      return Text.rich(
        TextSpan(
          children: [
            TextSpan(text: '$label ', style: muted),
            TextSpan(text: _placeholder, style: strong),
          ],
        ),
      );
    }
    final isStale = state.indexStaleNames.contains(index.name);
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: '$label ', style: muted),
          TextSpan(
            text: NumberFormat('#,##0.00').format(index.close),
            style: strong,
          ),
          const TextSpan(text: ' '),
          TextSpan(
            text: indexChangePercentText(index),
            style: strong?.copyWith(color: context.priceColor(index.change)),
          ),
          // 與大盤頁 hero 同一個警示色：備援值不得與即時值同貌
          if (isStale) ...[
            const TextSpan(text: ' '),
            TextSpan(
              text: 'marketOverview.indexStale'.tr(
                namedArgs: {'date': '${index.date.month}/${index.date.day}'},
              ),
              style: muted?.copyWith(color: warningColor),
            ),
          ],
        ],
      ),
    );
  }

  /// 「上市 情緒 33 恐懼」；資料不足時「上市 情緒 —」
  Widget _sentimentGroup({
    required TextStyle? muted,
    required TextStyle? strong,
  }) {
    final sentiment = computeMarketSentiment(state, MarketCode.twse);
    final prefix =
        '${'marketOverview.twse'.tr()} ${'marketOverview.summary.sentiment'.tr()} ';
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: prefix, style: muted),
          if (sentiment == null)
            TextSpan(text: _placeholder, style: strong)
          else ...[
            TextSpan(text: sentiment.score.round().toString(), style: strong),
            TextSpan(
              text: ' ${sentimentLevelText(sentiment.level)}',
              style: muted,
            ),
          ],
        ],
      ),
    );
  }

  /// 「漲 408 跌 667」；缺漲跌家數（含全為 0）時「漲 — 跌 —」
  Widget _breadthGroup(
    BuildContext context, {
    required TextStyle? muted,
    required TextStyle? strong,
  }) {
    final ad = state.advanceDeclineByMarket[MarketCode.twse];
    final hasAd = ad != null && ad.total > 0;
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '${'marketOverview.summary.advance'.tr()} ',
            style: muted,
          ),
          TextSpan(
            text: hasAd ? '${ad.advance}' : _placeholder,
            style: hasAd
                ? strong?.copyWith(color: context.priceColor(1))
                : strong,
          ),
          TextSpan(
            text: ' ${'marketOverview.summary.decline'.tr()} ',
            style: muted,
          ),
          TextSpan(
            text: hasAd ? '${ad.decline}' : _placeholder,
            style: hasAd
                ? strong?.copyWith(color: context.priceColor(-1))
                : strong,
          ),
        ],
      ),
    );
  }

  /// 與資料態同結構（兩行、同內距），載入完成時版面不跳
  Widget _skeleton() {
    return const Padding(
      padding: _outerPadding,
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: _innerPadding,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ShimmerContainer(width: 260, height: 20),
              SizedBox(height: DesignTokens.spacing4),
              ShimmerContainer(width: 200, height: 18),
            ],
          ),
        ),
      ),
    );
  }

  Widget _errorRow(BuildContext context) {
    return Padding(
      padding: _outerPadding,
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
}
