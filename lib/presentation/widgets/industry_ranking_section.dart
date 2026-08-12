import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:daredevil/core/constants/app_routes.dart';
import 'package:daredevil/core/theme/app_theme.dart';
import 'package:daredevil/core/theme/design_tokens.dart';
import 'package:daredevil/core/utils/number_formatter.dart';
import 'package:daredevil/domain/models/industry_ranking.dart';
import 'package:daredevil/presentation/providers/industry_ranking_provider.dart';
import 'package:daredevil/presentation/providers/stock_browsing_context_provider.dart';
import 'package:daredevil/presentation/widgets/section_header.dart';

/// 今日頁族群排行 section（使用者選股法則 L1：族群決定 80%）
///
/// 橫向卡片列出動能前段產業：選定視窗（20日輪動／5日轉折）動能中位數、
/// 外資+投信近 3 日方向、成員數。點卡片開 bottom sheet 看領漲成員、
/// 可再點進個股詳情。
class IndustryRankingSection extends ConsumerStatefulWidget {
  const IndustryRankingSection({super.key});

  @override
  ConsumerState<IndustryRankingSection> createState() =>
      _IndustryRankingSectionState();
}

class _IndustryRankingSectionState
    extends ConsumerState<IndustryRankingSection> {
  _RankMode _mode = _RankMode.d20;

  /// 20日/5日 是**水準值**,轉向是**變化率**——語意不同但共用一組按鈕,
  /// 因為使用者的心智模型是「換一種看法」,不是「換一個資料來源」。
  RankingWindow get _window => switch (_mode) {
    _RankMode.d1 => RankingWindow.d1,
    _RankMode.d5 => RankingWindow.d5,
    _RankMode.d20 || _RankMode.rotation => RankingWindow.d20,
  };

  String _modeLabel(_RankMode m) => switch (m) {
    _RankMode.d1 => 'today.industryWindow1d'.tr(),
    _RankMode.d20 => 'today.industryWindow20d'.tr(),
    _RankMode.d5 => 'today.industryWindow5d'.tr(),
    _RankMode.rotation => 'today.industryRotation'.tr(),
  };

  /// 口徑字幕(排行與轉向共用):中位數・合併市場——與市值加權官方類指數
  /// 不同,這行是防止「數字對不上=壞掉」誤解的唯一防線
  Widget _scopeCaption(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      DesignTokens.spacing16,
      0,
      DesignTokens.spacing16,
      DesignTokens.spacing8,
    ),
    child: Text(
      'today.industryRankingScope'.tr(),
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );

  String _windowLabel(RankingWindow w) => switch (w) {
    RankingWindow.d1 => 'today.industryWindow1d'.tr(),
    RankingWindow.d20 => 'today.industryWindow20d'.tr(),
    RankingWindow.d5 => 'today.industryWindow5d'.tr(),
  };

  @override
  Widget build(BuildContext context) {
    if (_mode == _RankMode.rotation) return _buildRotation(context, ref);
    final asyncRankings = ref.watch(industryRankingProvider(_window));
    return asyncRankings.when(
      // 輔助發現層：loading / error / 空資料（fresh DB、歷史回補中）都整段
      // 收起，不佔版面、不擋今日頁主線（推薦清單）。資料層錯誤已由上方
      // MarketDashboard / 更新錯誤橫幅承接，這裡不重複報錯。
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (rankings) {
        if (rankings.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(
              title: 'today.industryRanking'.tr(),
              icon: Icons.workspaces_outline,
              // 20日＝輪動主視角、5日＝轉折視角（20日弱但正在翻強的族群
              // 只有 5日排序才進得了前八——2026-07-22 實機回饋）
              trailing: SegmentedButton<_RankMode>(
                style: const ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                showSelectedIcon: false,
                segments: [
                  for (final m in _RankMode.values)
                    ButtonSegment(value: m, label: Text(_modeLabel(m))),
                ],
                selected: {_mode},
                onSelectionChanged: (set) {
                  HapticFeedback.selectionClick();
                  setState(() => _mode = set.first);
                },
              ),
            ),
            _scopeCaption(context),
            SizedBox(
              height: 108,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(
                  horizontal: DesignTokens.spacing16,
                ),
                scrollDirection: Axis.horizontal,
                itemCount: rankings.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(width: DesignTokens.spacing8),
                itemBuilder: (context, index) => _IndustryCard(
                  ranking: rankings[index],
                  rank: index + 1,
                  windowLabel: _windowLabel(_window),
                ),
              ),
            ),
            const SizedBox(height: DesignTokens.spacing8),
          ],
        );
      },
    );
  }

  /// 轉向模式:比較 20日 與 5日 的**名次**,而非水準值。
  ///
  /// 排序鍵是躍升名次;強者榜 0 檔的卡片整張淡化——**點進去也沒東西可買**,
  /// 躍升再多都是死路(2026-08-10 化學工業躍升 +23 但強者榜 0 檔)。
  Widget _buildRotation(BuildContext context, WidgetRef ref) {
    final async = ref.watch(industryRotationProvider);
    return async.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (rows) {
        if (rows.isEmpty) return const SizedBox.shrink();
        // 只顯示有方向性的:neutral 在轉向視角下沒有資訊
        final shown = rows
            .where((r) => r.category != RotationCategory.neutral)
            .toList();
        final hasSustained = shown.any(
          (r) => r.category == RotationCategory.sustained,
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(
              title: 'today.industryRanking'.tr(),
              icon: Icons.workspaces_outline,
              trailing: SegmentedButton<_RankMode>(
                style: const ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                showSelectedIcon: false,
                segments: [
                  for (final m in _RankMode.values)
                    ButtonSegment(value: m, label: Text(_modeLabel(m))),
                ],
                selected: {_mode},
                onSelectionChanged: (set) {
                  HapticFeedback.selectionClick();
                  setState(() => _mode = set.first);
                },
              ),
            ),
            _scopeCaption(context),
            SizedBox(
              height: 132,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(
                  horizontal: DesignTokens.spacing16,
                ),
                scrollDirection: Axis.horizontal,
                // +1 給「持續強勢:目前無」的說明卡。**不可隱藏**:
                // 「沒有任何族群持續強勢」本身就是市場狀態,藏起來會讓
                // 使用者以為功能壞了(2026-08-10 崩跌後實測為 0 個)
                itemCount: shown.length + (hasSustained ? 0 : 1),
                separatorBuilder: (_, _) =>
                    const SizedBox(width: DesignTokens.spacing8),
                itemBuilder: (context, index) => index < shown.length
                    ? _RotationCard(rotation: shown[index], rank: index + 1)
                    : const _NoSustainedCard(),
              ),
            ),
            const SizedBox(height: DesignTokens.spacing8),
          ],
        );
      },
    );
  }
}

class _IndustryCard extends ConsumerWidget {
  const _IndustryCard({
    required this.ranking,
    required this.rank,
    required this.windowLabel,
  });

  final IndustryRanking ranking;
  final int rank;
  final String windowLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final momentumColor = AppTheme.getPriceColor(
      ranking.momentumPct,
      theme.brightness,
    );
    final netColor = AppTheme.getPriceColor(
      ranking.institutionalNetShares,
      theme.brightness,
    );

    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
        onTap: () {
          HapticFeedback.selectionClick();
          _showMembersSheet(context, ref);
        },
        child: Padding(
          padding: const EdgeInsets.all(DesignTokens.spacing12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Text(
                    '$rank',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.outline,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: DesignTokens.spacing4),
                  Text(
                    ranking.industry,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: DesignTokens.spacing4),
                  Text(
                    'today.industryMemberCount'.tr(
                      args: ['${ranking.memberCount}'],
                    ),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              // 動能（排序鍵）＋ 超額：絕對報酬在多空市場的語意完全不同，
              // 大盤 -2.10% 時 +0.23% 是跑贏 2.3pp 而非「幾乎沒動」
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    AppNumberFormat.signedPercent(
                      ranking.momentumPct,
                      decimals: 1,
                    ),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: momentumColor,
                    ),
                  ),
                  if (ranking.excessPct != null) ...[
                    const SizedBox(width: DesignTokens.spacing4),
                    Text(
                      'today.industryExcess'.tr(
                        args: [
                          AppNumberFormat.signedPercent(
                            ranking.excessPct!,
                            decimals: 1,
                          ),
                        ],
                      ),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: AppTheme.getPriceColor(
                          ranking.excessPct!,
                          theme.brightness,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              // 廣度＋法人佔比：中位數不揭露「整族在動」還是「少數撐盤」；
              // 法人絕對張數主要反映族群規模，佔成交量比才是態度
              Row(
                children: [
                  Text(
                    'today.industryAdvancing'.tr(
                      args: ['${(ranking.advancingRatio * 100).round()}%'],
                    ),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: DesignTokens.spacing8),
                  if (ranking.institutionalVolumeRatio != null)
                    Text(
                      'today.industryInstitutionalRatio'.tr(
                        args: [
                          AppNumberFormat.signedPercent(
                            ranking.institutionalVolumeRatio! * 100,
                            decimals: 1,
                          ),
                        ],
                      ),
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: netColor,
                      ),
                    )
                  else
                    Text(
                      'today.industryInstitutional'.tr(),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showMembersSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: DesignTokens.spacing16,
                ),
                child: Text(
                  'today.industryTopMembers'.tr(
                    args: [ranking.industry, windowLabel],
                  ),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: DesignTokens.spacing8),
              ...ranking.topMembers.map(
                (m) => ListTile(
                  dense: true,
                  title: Text(m.name.isEmpty ? m.symbol : m.name),
                  subtitle: Text(m.symbol),
                  trailing: Text(
                    AppNumberFormat.signedPercent(m.retPct, decimals: 1),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppTheme.getPriceColor(m.retPct, theme.brightness),
                    ),
                  ),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    ref.read(stockBrowsingContextProvider.notifier).set([
                      for (final t in ranking.topMembers) t.symbol,
                    ]);
                    context.push(AppRoutes.stockDetail(m.symbol));
                  },
                ),
              ),
              const SizedBox(height: DesignTokens.spacing8),
            ],
          ),
        );
      },
    );
  }
}

/// 排行的四種看法。20日/5日 是**水準值**,轉向是**變化率**——語意不同,
/// 但共用一組按鈕,因為使用者的心智是「換一種看法」而非「換資料來源」。
enum _RankMode { d1, d20, d5, rotation }

/// 轉向卡片。
///
/// 主角是**躍升名次**(排序鍵),不是報酬率——那是這個模式存在的理由。
/// 強者榜 0 檔時整張淡化:點進去也沒東西可買,躍升再多都是死路。
class _RotationCard extends ConsumerWidget {
  const _RotationCard({required this.rotation, required this.rank});

  final IndustryRotation rotation;
  final int rank;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final dim = rotation.strongListCount == 0;
    final (label, color) = switch (rotation.category) {
      RotationCategory.sustained => (
        'today.rotationSustained'.tr(),
        AppTheme.getPriceColor(1, theme.brightness),
      ),
      RotationCategory.reboundFromDeep => (
        'today.rotationRebound'.tr(),
        theme.colorScheme.tertiary,
      ),
      RotationCategory.cooling => (
        'today.rotationCooling'.tr(),
        AppTheme.getPriceColor(-1, theme.brightness),
      ),
      RotationCategory.neutral => ('', theme.colorScheme.outline),
    };
    final jumpColor = AppTheme.getPriceColor(
      rotation.rankJump.toDouble(),
      theme.brightness,
    );

    return Opacity(
      // 0 檔 → 淡化。用透明度而非隱藏:躍升本身仍是市場資訊,
      // 只是「這一格沒有可買的」——讓使用者掃過去自然跳過,不必讀數字
      opacity: dim ? 0.45 : 1.0,
      child: SizedBox(
        width: 210,
        child: Card(
          margin: EdgeInsets.zero,
          child: InkWell(
            borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
            onTap: () {
              HapticFeedback.selectionClick();
              _showMembersSheet(context, ref);
            },
            child: Padding(
              padding: const EdgeInsets.all(DesignTokens.spacing12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Text(
                        '$rank',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.outline,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: DesignTokens.spacing4),
                      Flexible(
                        child: Text(
                          rotation.industry,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  // 躍升是主角(排序鍵、也是這個模式唯一的新資訊);
                  // 分類標籤放同一行——族群名那行放不下兩者(190 寬實測
                  // 溢出 95px),而躍升字短,右邊剛好有空間
                  Row(
                    children: [
                      Text(
                        // Key 帶值:測試環境不載入翻譯,`.tr()` 不做參數
                        // 替換,用文字內容找不到「+33」(2026-08-11)
                        key: Key('rotationJump.${rotation.rankJump}'),
                        'today.rotationJump'.tr(
                          args: [
                            rotation.rankJump > 0
                                ? '+${rotation.rankJump}'
                                : '${rotation.rankJump}',
                          ],
                        ),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: jumpColor,
                        ),
                      ),
                      const SizedBox(width: DesignTokens.spacing8),
                      Flexible(
                        child: Text(
                          label,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: color,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  Text(
                    // 只放名次不放報酬率:190 寬的卡片裝不下(實測溢出
                    // 133px),而躍升本身已由名次差表達。報酬率移到 sheet
                    'today.rotationWindows'.tr(
                      args: ['${rotation.rank5d}', '${rotation.rank20d}'],
                    ),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    'today.rotationStrongList'.tr(
                      args: ['${rotation.strongListCount}'],
                    ),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: dim
                          ? theme.colorScheme.error
                          : theme.colorScheme.onSurfaceVariant,
                      fontWeight: dim ? FontWeight.w600 : null,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 成員依 **20 日報酬** 排序(見 IndustryRotation.topMembers),
  /// 過強者榜的標星——那是使用者點進來要找的東西。
  void _showMembersSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: DesignTokens.spacing16,
                ),
                child: Text(
                  'today.rotationMembers'.tr(args: [rotation.industry]),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: DesignTokens.spacing8),
              ...rotation.topMembers.map((m) {
                final strong = rotation.strongListSymbols.contains(m.symbol);
                return ListTile(
                  dense: true,
                  leading: strong
                      ? Icon(
                          Icons.star_rounded,
                          size: 18,
                          color: theme.colorScheme.primary,
                        )
                      : const SizedBox(width: 18),
                  title: Text(m.name.isEmpty ? m.symbol : m.name),
                  subtitle: Text(m.symbol),
                  trailing: Text(
                    AppNumberFormat.signedPercent(m.retPct, decimals: 1),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppTheme.getPriceColor(m.retPct, theme.brightness),
                    ),
                  ),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    ref.read(stockBrowsingContextProvider.notifier).set([
                      for (final t in rotation.topMembers) t.symbol,
                    ]);
                    context.push(AppRoutes.stockDetail(m.symbol));
                  },
                );
              }),
              const SizedBox(height: DesignTokens.spacing8),
            ],
          ),
        );
      },
    );
  }
}

/// 「持續強勢:目前無」說明卡。
///
/// **刻意不隱藏**:沒有任何族群在兩個窗口都排前段,本身就是市場狀態
/// (2026-08-10 崩跌後實測為 0 個)。藏起來會讓使用者以為功能壞了。
class _NoSustainedCard extends StatelessWidget {
  const _NoSustainedCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 210,
      child: Card(
        margin: EdgeInsets.zero,
        color: theme.colorScheme.surfaceContainerHighest,
        child: Padding(
          padding: const EdgeInsets.all(DesignTokens.spacing12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'today.rotationNoSustained'.tr(),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: DesignTokens.spacing4),
              Text(
                'today.rotationNoSustainedHint'.tr(),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
