import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'package:daredevil/core/constants/market_codes.dart';
import 'package:daredevil/core/theme/app_theme.dart';
import 'package:daredevil/core/theme/semantic_colors.dart';
import 'package:daredevil/core/theme/design_tokens.dart';
import 'package:daredevil/domain/services/market_sentiment_service.dart';

/// 市場情緒儀表板
///
/// 顯示市場情緒分數 (0-100)、等級、漸層 bar 指標位置。子指標預設收摺
/// （CNN Fear&Greed 範式：總分為主、細項按需展開），避免一次塞 5 個
/// 看不懂的子分數造成認知過載。
class SentimentGaugeSection extends StatefulWidget {
  const SentimentGaugeSection({
    super.key,
    required this.sentiment,
    required this.market,
    this.sentimentHistory = const [],
  });

  final MarketSentiment sentiment;

  /// 市場代碼（[MarketCode.twse] / [MarketCode.tpex]）
  ///
  /// 用於內建標題列標示「上市 市場情緒」／「上櫃 市場情緒」。桌面版
  /// dashboard 並排顯示兩個市場的儀表，若不標示會呈現兩個完全相同的
  /// 「市場情緒」標題、無法區分（單一市場資料不足優雅降級時尤其模糊）。
  final String market;

  /// 歷史情緒分數（oldest→newest）
  ///
  /// 視覺 pass 移除趨勢 sparkline 後本欄暫不渲染，保留參數與上游計算
  /// （market_dashboard.dart 的 `_computeSentimentHistory`）不變，避免牽動
  /// 資料層。
  final List<double> sentimentHistory;

  @override
  State<SentimentGaugeSection> createState() => _SentimentGaugeSectionState();
}

class _SentimentGaugeSectionState extends State<SentimentGaugeSection> {
  /// 子指標細項是否展開（預設收摺）
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sentiment = widget.sentiment;
    final color = _levelColor(sentiment.level, theme.brightness);
    final levelText = _levelText(sentiment.level);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 標題行：標示市場（上市/上櫃），桌面版並排雙欄時避免兩側標題相同
        Text(
          '${_marketLabel(widget.market)} ${'marketOverview.sentiment.title'.tr()}',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: DesignTokens.spacing10),

        Container(
          padding: const EdgeInsets.all(DesignTokens.spacing14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(DesignTokens.radiusXl),
            color: theme.colorScheme.surfaceContainerLowest,
          ),
          child: Column(
            children: [
              // 大數字 + 等級標籤
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    sentiment.score.toStringAsFixed(0),
                    style: theme.textTheme.headlineLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                      // 色彩語意：red/green 僅供價格方向使用，情緒分數非漲跌
                      // 判斷 — 數字改中性色，與三角指標（已用 onSurface）
                      // 一致；等級徽章（levelText）仍用 color 標示 fear/greed。
                      color: theme.colorScheme.onSurface,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(width: DesignTokens.spacing10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: DesignTokens.spacing8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(
                        DesignTokens.radiusSm,
                      ),
                    ),
                    child: Text(
                      levelText,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: _levelOnTint(sentiment.level, theme.brightness),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: DesignTokens.spacing12),

              // 漸層 bar + 三角形指標
              _GradientBar(score: sentiment.score),

              // 子指標缺席註記（靜默稽核 #7 附帶效應）：缺席者不計入
              // 有效權重分母，gauge 外觀與完整計算**完全相同**——例如法人
              // 歷史查詢失敗時 25% 分量憑空消失而指針照樣穩穩指著。
              if (sentiment.subScores.isNotEmpty &&
                  sentiment.subScores.length < subScoreWeights.length) ...[
                const SizedBox(height: DesignTokens.spacing4),
                Text(
                  'marketOverview.sentimentPartial'.tr(
                    namedArgs: {
                      'count':
                          '${subScoreWeights.length - sentiment.subScores.length}',
                    },
                  ),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.brightness == Brightness.light
                        ? WarningColors.warningOnLight
                        : WarningColors.warning,
                  ),
                ),
              ],

              // 子指標：預設收摺，點「細項」展開（CNN Fear&Greed 範式）
              if (sentiment.subScores.isNotEmpty) ...[
                const SizedBox(height: DesignTokens.spacing8),
                _SubScoresToggle(
                  expanded: _expanded,
                  onTap: () => setState(() => _expanded = !_expanded),
                ),
                // ⚠️ 並排(IntrinsicHeight)視圖下,容器高度由 intrinsic 一步
                // 到位(取目標尺寸),只有內容在 180ms 內長出——「動畫不順」
                // 是機制不是 bug,別試圖在這裡修(2026-08-13 審查 5 實測)
                AnimatedSize(
                  duration: const Duration(milliseconds: 180),
                  alignment: Alignment.topCenter,
                  child: _expanded
                      ? Padding(
                          padding: const EdgeInsets.only(
                            top: DesignTokens.spacing10,
                          ),
                          child: _SubScoresGrid(subScores: sentiment.subScores),
                        )
                      : const SizedBox(width: double.infinity),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  static Color _levelColor(SentimentLevel level, Brightness brightness) {
    return switch (level) {
      SentimentLevel.extremeFear => const Color(0xFF1B5E20),
      SentimentLevel.fear => PriceColors.downFor(brightness),
      SentimentLevel.neutral => PriceColors.flatFor(brightness),
      SentimentLevel.greed => AppTheme.upColor,
      SentimentLevel.extremeGreed => const Color(0xFFB71C1C),
    };
  }

  /// 徽章文字色——tint（[_levelColor] @0.12）上不得用本色：深色主題
  /// greed 3.91、extremeGreed 僅 2.17:1。淺色維持本色（deferred，
  /// 見 PriceColors.upOnTintFor 說明）。
  static Color _levelOnTint(SentimentLevel level, Brightness brightness) {
    if (brightness != Brightness.dark) return _levelColor(level, brightness);
    return switch (level) {
      SentimentLevel.extremeFear => PriceColors.chipBearish,
      SentimentLevel.fear => PriceColors.down,
      SentimentLevel.neutral => PriceColors.flatOnTintDark,
      SentimentLevel.greed => PriceColors.chipBullish,
      SentimentLevel.extremeGreed => PriceColors.chipBullish,
    };
  }

  static String _levelText(SentimentLevel level) {
    final key = switch (level) {
      SentimentLevel.extremeFear => 'marketOverview.sentiment.extremeFear',
      SentimentLevel.fear => 'marketOverview.sentiment.fear',
      SentimentLevel.neutral => 'marketOverview.sentiment.neutral',
      SentimentLevel.greed => 'marketOverview.sentiment.greed',
      SentimentLevel.extremeGreed => 'marketOverview.sentiment.extremeGreed',
    };
    return key.tr();
  }

  /// 市場代碼 → 顯示標籤（「上市」／「上櫃」）
  ///
  /// key 判斷邏輯共用 [marketLabelKey]（與 `MarketDashboard` 內部
  /// `_buildMarketHeader` 同一份，避免兩處各自維護一份三元判斷）。
  static String _marketLabel(String market) => marketLabelKey(market).tr();
}

/// 子指標展開/收摺切換列
class _SubScoresToggle extends StatelessWidget {
  const _SubScoresToggle({required this.expanded, required this.onTap});

  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mutedColor = theme.colorScheme.onSurfaceVariant;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: DesignTokens.spacing4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'marketOverview.sentiment.details'.tr(),
              style: theme.textTheme.labelSmall?.copyWith(
                color: mutedColor,
                fontSize: DesignTokens.fontSizeXs,
              ),
            ),
            const SizedBox(width: DesignTokens.spacing4),
            Icon(
              expanded ? Icons.expand_less : Icons.expand_more,
              size: 14,
              color: mutedColor,
            ),
          ],
        ),
      ),
    );
  }
}

/// 漸層 bar (綠→灰→紅) + 三角形指標
class _GradientBar extends StatelessWidget {
  const _GradientBar({required this.score});

  final double score;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        // 指標三角形。Align 而非 LayoutBuilder(2026-08-13):Alignment.x 把
        // score 0–100 映射到 −1..+1,位置語意等價(差異 ≤ 半個三角形寬,且
        // 端點不再掛半顆出畫面)。拔掉 LayoutBuilder 後,情緒配對列才能用
        // IntrinsicHeight 撐開分隔線——原本的固定高度 hack(222px)在子指標
        // 收摺(預設)時白吃 50px 垂直空間。
        SizedBox(
          height: 8,
          width: double.infinity,
          child: Align(
            alignment: Alignment(score / 50 - 1, 1),
            child: CustomPaint(
              size: const Size(10, 6),
              painter: _TrianglePainter(color: theme.colorScheme.onSurface),
            ),
          ),
        ),
        // 漸層條
        ClipRRect(
          borderRadius: BorderRadius.circular(DesignTokens.radiusXs),
          child: Container(
            height: 8,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Color(0xFF1B5E20), // 極度恐懼
                  Color(0xFF4CAF50), // 恐懼
                  Color(0xFF9E9E9E), // 中性
                  Color(0xFFEF5350), // 貪婪
                  Color(0xFFB71C1C), // 極度貪婪
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: DesignTokens.spacing4),
        // 標籤行
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'marketOverview.sentiment.fearLabel'.tr(),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: DesignTokens.fontSizeXs,
              ),
            ),
            Text(
              'marketOverview.sentiment.greedLabel'.tr(),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: DesignTokens.fontSizeXs,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _TrianglePainter extends CustomPainter {
  _TrianglePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width / 2, size.height)
      ..lineTo(0, 0)
      ..lineTo(size.width, 0)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_TrianglePainter oldDelegate) =>
      color != oldDelegate.color;
}

/// 子指標 grid (2×3 排列)
class _SubScoresGrid extends StatelessWidget {
  const _SubScoresGrid({required this.subScores});

  final Map<String, double> subScores;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // 定義顯示順序與名稱
    const indicators = [
      ('advanceRatio', 'marketOverview.sentiment.advanceRatio'),
      ('institutional', 'marketOverview.sentiment.institutional'),
      ('volumeMomentum', 'marketOverview.sentiment.volumeMomentum'),
      ('marginChange', 'marketOverview.sentiment.marginChange'),
      ('industryBreadth', 'marketOverview.sentiment.industryBreadth'),
    ];

    final items = indicators
        .where((ind) => subScores.containsKey(ind.$1))
        .toList();

    // Row+Expanded 而非 LayoutBuilder+Wrap(2026-08-13):配對列改用
    // IntrinsicHeight 後,子樹裡任何 LayoutBuilder 在展開細項時都會丟
    // 「LayoutBuilder does not support returning intrinsic dimensions」
    // ——收摺(預設)不 build 本 widget,炸點藏在展開路徑,由
    // market_dashboard_test 的展開探針守。三等分語意不變:每列 3 格,
    // 尾列不足補空 Expanded 佔位。
    const columns = 3;
    const spacing = 8.0;

    Widget item((String, String) ind) {
      final score = subScores[ind.$1]!;
      final color = _scoreColor(score, theme.brightness);
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 4,
            height: 4,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: DesignTokens.spacing4),
          Flexible(
            child: Text(
              ind.$2.tr(),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: DesignTokens.fontSizeXs,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: DesignTokens.spacing4),
          Text(
            score.toStringAsFixed(0),
            style: theme.textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: DesignTokens.fontSizeXs,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        for (var i = 0; i < items.length; i += columns)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : DesignTokens.spacing6),
            child: Row(
              children: [
                for (var j = i; j < i + columns; j++) ...[
                  if (j > i) const SizedBox(width: spacing),
                  Expanded(
                    child: j < items.length
                        ? item(items[j])
                        : const SizedBox.shrink(),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }

  static Color _scoreColor(double score, Brightness brightness) {
    if (score < 30) return PriceColors.downFor(brightness);
    if (score > 70) return AppTheme.upColor;
    return PriceColors.flatFor(brightness);
  }
}
