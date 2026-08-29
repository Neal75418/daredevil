import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:daredevil/core/constants/rule_params_fundamental.dart';
import 'package:daredevil/core/theme/app_theme.dart';
import 'package:daredevil/core/theme/design_tokens.dart';
import 'package:daredevil/core/theme/semantic_colors.dart';
import 'package:daredevil/domain/services/chip_anomaly_service.dart'
    show ChipAnomaly, ChipAnomalyType, ChipSeverity;
import 'package:daredevil/presentation/providers/market_overview_provider.dart'
    show WarningCounts;

/// 籌碼異動摘要列
///
/// 台股風格：摘要橫幅 + 各類型直接展開（最多顯示 3 檔），每檔一行
/// （代號＋名稱＋關鍵數值）。支援點擊個股導航至詳情頁。標題列可選擇性
/// 併入注意/處置股家數徽章（見 [warningCounts]），取代原本獨立的
/// 注意/處置摘要列。
class ChipAnomalyRow extends StatelessWidget {
  const ChipAnomalyRow({
    super.key,
    required this.anomalies,
    this.onStockTap,
    this.warningCounts,
    this.failedDetectorCount = 0,
    this.etfFilterUnavailable = false,
  });

  /// 偵測失敗的類別數(靜默稽核 #4,**不含** ETF 過濾)。>0 時標題下掛
  /// 「N 類未偵測」——「今天沒有該類異動」與「該類偵測壞了」不得逐
  /// pixel 相同。
  final int failedDetectorCount;

  /// ETF 清單載入失敗(review 更正 2026-08-29):方向與「未偵測」**相反**
  /// ——榜單是完整的,問題是過濾失效、可能**混入 ETF**。借用未偵測文案
  /// 會指向錯誤方向(且會出現「6 類未偵測」但總共只有 5 類的不可能數字),
  /// 故獨立文案。
  final bool etfFilterUnavailable;

  final List<ChipAnomaly> anomalies;

  /// 點擊個股時的回呼，傳入股票代號。由父層決定導航行為。
  final void Function(String symbol)? onStockTap;

  /// 注意/處置股家數；非 null 且 [WarningCounts.total] > 0 時於標題列顯示
  /// 徽章。原本獨立一列的注意/處置摘要併入本區塊標題（見類別文件）。
  final WarningCounts? warningCounts;

  @override
  Widget build(BuildContext context) {
    final hasAnomalies = anomalies.isNotEmpty;
    final warnings = warningCounts;
    final hasWarnings = warnings != null && warnings.total > 0;
    // 有偵測失敗時本區塊必須現身:安靜的市場與壞掉的偵測不可同貌
    if (!hasAnomalies &&
        !hasWarnings &&
        failedDetectorCount == 0 &&
        !etfFilterUnavailable) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);

    // 依類型分群
    final grouped = <ChipAnomalyType, List<ChipAnomaly>>{};
    for (final a in anomalies) {
      grouped.putIfAbsent(a.type, () => []).add(a);
    }

    // 依嚴重度排序（使用 index 比較，保留擴充彈性）
    final sortedTypes = grouped.keys.toList()
      ..sort((a, b) {
        final sa = grouped[a]!.first.severity;
        final sb = grouped[b]!.first.severity;
        if (sa == sb) return a.index.compareTo(b.index);
        return sa.index.compareTo(sb.index);
      });

    final hasHigh = anomalies.any((a) => a.severity == ChipSeverity.high);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 標題列：籌碼異動標題 + 注意/處置徽章（若有）
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(
                'marketOverview.chipAnomaly.title'.tr(),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (hasWarnings) ...[
              if (warnings.attention > 0)
                _WarningCountBadge(
                  label: 'marketOverview.attentionCount'.tr(
                    namedArgs: {'count': '${warnings.attention}'},
                  ),
                  color: Colors.orange,
                  textColor: WarningColors.onTintFor(theme.brightness),
                ),
              if (warnings.attention > 0 && warnings.disposal > 0)
                const SizedBox(width: DesignTokens.spacing6),
              if (warnings.disposal > 0)
                // 處置＝error 語意（同 WarningBadge.disposal），非股價紅
                _WarningCountBadge(
                  label: 'marketOverview.disposalCount'.tr(
                    namedArgs: {'count': '${warnings.disposal}'},
                  ),
                  // AppTheme.errorColor(#E74C3C)屬 ErrorColors onTint 實測家族
                  color: AppTheme.errorColor,
                  textColor: ErrorColors.onTintFor(theme.brightness),
                ),
            ],
          ],
        ),
        if (failedDetectorCount > 0)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              'marketOverview.chipAnomaly.partialFail'.tr(
                namedArgs: {'count': '$failedDetectorCount'},
              ),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.brightness == Brightness.light
                    ? WarningColors.warningOnLight
                    : WarningColors.warning,
              ),
            ),
          ),
        if (etfFilterUnavailable)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              'marketOverview.chipAnomaly.etfFilterFail'.tr(),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.brightness == Brightness.light
                    ? WarningColors.warningOnLight
                    : WarningColors.warning,
              ),
            ),
          ),

        if (hasAnomalies) ...[
          const SizedBox(height: DesignTokens.spacing8),

          // 摘要橫幅
          _SummaryBanner(count: anomalies.length, hasHigh: hasHigh),
          const SizedBox(height: DesignTokens.spacing12),

          // 各類型區塊（直接展開，不折疊）
          for (int i = 0; i < sortedTypes.length; i++) ...[
            if (i > 0) const SizedBox(height: DesignTokens.spacing8),
            _AnomalyTypeSection(
              // 用 type 當 key，確保 sort 順序變動（如 severity 升級導致重排）
              // 時 _isExpanded 狀態仍跟著正確的 type 走，不會誤掛到不同類別。
              key: ValueKey(sortedTypes[i]),
              type: sortedTypes[i],
              items: grouped[sortedTypes[i]]!,
              onStockTap: onStockTap,
            ),
          ],
        ],
      ],
    );
  }
}

// ==================================================
// 注意/處置徽章（併入標題列）
// ==================================================

/// 注意/處置股家數徽章
///
/// 樣式沿用原「注意/處置」獨立摘要列的徽章（2026-07-17 該列已併入本標題列後移除），
/// 僅搬移位置到本區塊標題列右側，視覺不變。
class _WarningCountBadge extends StatelessWidget {
  const _WarningCountBadge({
    required this.label,
    required this.color,
    required this.textColor,
  });

  final String label;

  /// tint 底色（identity 色，僅裝飾）。
  final Color color;

  /// 疊色底上的文字色——不得與 [color] 同色（合成後僅 ~2:1）。
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: DesignTokens.spacing8,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
        color: color.withValues(alpha: 0.1),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: textColor,
          fontWeight: FontWeight.w600,
          fontSize: DesignTokens.fontSizeXs,
        ),
      ),
    );
  }
}

// ==================================================
// 摘要橫幅
// ==================================================

class _SummaryBanner extends StatelessWidget {
  const _SummaryBanner({required this.count, required this.hasHigh});

  final int count;
  final bool hasHigh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = hasHigh ? AppTheme.errorColor : AppTheme.warningColor;
    final onTint = hasHigh
        ? ErrorColors.onTintFor(theme.brightness)
        : WarningColors.onTintFor(theme.brightness);
    final label = 'marketOverview.chipAnomaly.summary'.tr(
      namedArgs: {'count': count.toString()},
    );

    return Semantics(
      label: label,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: DesignTokens.spacing12,
          vertical: DesignTokens.spacing8,
        ),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            Icon(
              Icons.warning_amber_rounded,
              size: DesignTokens.iconSizeSm,
              color: onTint,
            ),
            const SizedBox(width: DesignTokens.spacing6),
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: onTint,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==================================================
// 單一類型區塊
// ==================================================

class _AnomalyTypeSection extends StatefulWidget {
  const _AnomalyTypeSection({
    super.key,
    required this.type,
    required this.items,
    this.onStockTap,
  });

  final ChipAnomalyType type;

  /// 該類型偵測到的所有個股（預設 collapsed 只顯示前 3 筆）
  final List<ChipAnomaly> items;

  final void Function(String symbol)? onStockTap;

  @override
  State<_AnomalyTypeSection> createState() => _AnomalyTypeSectionState();
}

/// 預設折疊時顯示的個股數
const int _kAnomalyCollapsedCount = 3;

class _AnomalyTypeSectionState extends State<_AnomalyTypeSection> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final meta = _typeMeta(widget.type);
    final totalCount = widget.items.length;
    final visibleItems = _isExpanded
        ? widget.items
        : widget.items.take(_kAnomalyCollapsedCount).toList();
    // severity / accent color 應反映**全部** items 的最高嚴重度，不是 visible
    // slice — 否則 collapsed 時 items[3+] 含 high 會被誤標成 medium，展開後才
    // 突然變紅，破壞「header color = section severity」的承諾。
    final isHigh = widget.items.any((a) => a.severity == ChipSeverity.high);
    final accentColor = isHigh ? AppTheme.errorColor : AppTheme.warningColor;
    // tint 底（@0.1/@0.12）上的圖示與數字不得用 accentColor 本色——
    // 合成後淺色主題僅 ~2:1。
    final accentOnTint = isHigh
        ? ErrorColors.onTintFor(theme.brightness)
        : WarningColors.onTintFor(theme.brightness);
    final hiddenCount = totalCount - visibleItems.length;
    final canExpand = totalCount > _kAnomalyCollapsedCount;

    return Material(
      color: theme.colorScheme.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: DesignTokens.spacing12,
          vertical: DesignTokens.spacing8,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 類型標頭：icon + 名稱 + 實際總數徽章
            Row(
              children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
                  ),
                  child: Icon(
                    meta.icon,
                    size: DesignTokens.iconSizeSm,
                    color: accentOnTint,
                  ),
                ),
                const SizedBox(width: DesignTokens.spacing8),
                Text(
                  meta.label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: DesignTokens.spacing6),
                // 顯示實際偵測總數
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: DesignTokens.spacing4,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(DesignTokens.radiusXs),
                    color: accentColor.withValues(alpha: 0.1),
                  ),
                  child: Text(
                    '$totalCount',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: accentOnTint,
                      fontWeight: FontWeight.w700,
                      fontSize: DesignTokens.fontSizeXs,
                    ),
                  ),
                ),
              ],
            ),

            // 副標題（白話說明）
            const SizedBox(height: DesignTokens.spacing2),
            Text(
              meta.subtitle,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: DesignTokens.fontSizeXs,
              ),
            ),

            // 個股列表
            const SizedBox(height: DesignTokens.spacing6),
            Divider(
              height: 1,
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.25),
            ),
            const SizedBox(height: DesignTokens.spacing4),
            for (final item in visibleItems)
              _AnomalyItem(anomaly: item, onTap: widget.onStockTap),

            // 展開 / 收合按鈕（折疊時顯示「還有 N 檔」、展開時顯示「收合」）
            if (canExpand)
              Padding(
                padding: const EdgeInsets.only(top: DesignTokens.spacing4),
                child: TextButton(
                  onPressed: () => setState(() => _isExpanded = !_isExpanded),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: DesignTokens.spacing8,
                      vertical: DesignTokens.spacing4,
                    ),
                    minimumSize: const Size(0, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    foregroundColor: theme.colorScheme.primary,
                  ),
                  child: Text(
                    _isExpanded
                        ? 'marketOverview.chipAnomaly.collapse'.tr()
                        : 'marketOverview.chipAnomaly.moreItems'.tr(
                            namedArgs: {'count': hiddenCount.toString()},
                          ),
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      fontSize: DesignTokens.fontSizeXs,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ==================================================
// 單檔股票列
// ==================================================

class _AnomalyItem extends StatelessWidget {
  const _AnomalyItem({required this.anomaly, this.onTap});

  final ChipAnomaly anomaly;
  final void Function(String symbol)? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final valueColor = anomaly.severity == ChipSeverity.high
        ? AppTheme.errorColor
        : AppTheme.warningColor;

    // 單行：代號 + 名稱 + 關鍵數值。原本附帶的白話說明句已移除——分類
    // 標頭（[_TypeMeta.subtitle]）已解釋該類型異動的意義，逐檔重複同一句
    // 是低資訊密度的重複，壓縮成一行讓清單更快掃視。
    return MergeSemantics(
      child: InkWell(
        onTap: onTap != null
            ? () {
                HapticFeedback.lightImpact();
                onTap!(anomaly.symbol);
              }
            : null,
        borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: DesignTokens.spacing4),
          child: Row(
            children: [
              Text(
                anomaly.symbol,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: DesignTokens.spacing6),
              Expanded(
                child: Text(
                  anomaly.stockName,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurface,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (anomaly.keyValue != null)
                Text(
                  anomaly.keyValue!,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: valueColor,
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ==================================================
// 類型 metadata
// ==================================================

class _TypeMeta {
  const _TypeMeta({
    required this.icon,
    required this.label,
    required this.subtitle,
  });
  final IconData icon;
  final String label;
  final String subtitle;
}

_TypeMeta _typeMeta(ChipAnomalyType type) {
  switch (type) {
    case ChipAnomalyType.highPledge:
      return _TypeMeta(
        icon: Icons.lock_outline_rounded,
        label: 'marketOverview.chipAnomaly.highPledge'.tr(),
        subtitle: 'marketOverview.chipAnomaly.subtitleHighPledge'.tr(
          namedArgs: {
            'threshold': FundamentalParams.highPledgeRatioThreshold
                .toStringAsFixed(0),
          },
        ),
      );
    case ChipAnomalyType.insiderTransfer:
      return _TypeMeta(
        icon: Icons.swap_horiz_rounded,
        label: 'marketOverview.chipAnomaly.insiderTransfer'.tr(),
        subtitle: 'marketOverview.chipAnomaly.subtitleInsiderTransfer'.tr(),
      );
    case ChipAnomalyType.foreignNearLimit:
      return _TypeMeta(
        icon: Icons.flag_rounded,
        label: 'marketOverview.chipAnomaly.foreignNearLimit'.tr(),
        subtitle: 'marketOverview.chipAnomaly.subtitleForeignNearLimit'.tr(),
      );
    case ChipAnomalyType.shortSurge:
      return _TypeMeta(
        icon: Icons.trending_down_rounded,
        label: 'marketOverview.chipAnomaly.shortSurge'.tr(),
        subtitle: 'marketOverview.chipAnomaly.subtitleShortSurge'.tr(),
      );
    case ChipAnomalyType.institutionalSurge:
      return _TypeMeta(
        icon: Icons.flash_on_rounded,
        label: 'marketOverview.chipAnomaly.institutionalSurge'.tr(),
        subtitle: 'marketOverview.chipAnomaly.subtitleInstitutionalSurge'.tr(),
      );
  }
}
