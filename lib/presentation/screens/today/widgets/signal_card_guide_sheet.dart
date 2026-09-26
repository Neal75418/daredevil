import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'package:daredevil/core/constants/rule_params.dart';
import 'package:daredevil/core/theme/design_tokens.dart';
import 'package:daredevil/presentation/widgets/score_tier_badge.dart';
import 'package:daredevil/presentation/widgets/stock_card_sparkline.dart';
import 'package:daredevil/presentation/widgets/app_bottom_sheet.dart';

/// 「訊號卡怎麼看」說明（今日訊號標題旁的 ⓘ 進入）。
///
/// 門檻與天數由程式常數帶入，常數改了說明跟著改；附三個級距的實際徽章
/// 樣式（強／中／弱／觀察），看到的就是卡片上的樣子。
class SignalCardGuideSheet extends StatelessWidget {
  const SignalCardGuideSheet({super.key});

  static Future<void> show(BuildContext context) => showAppBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const SignalCardGuideSheet(),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const strong = RuleParams.tierStrongThreshold;
    const medium = RuleParams.tierMediumThreshold;
    const weak = RuleParams.minScoreThreshold;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          DesignTokens.spacing20,
          0,
          DesignTokens.spacing20,
          DesignTokens.spacing24,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'today.cardGuide.title'.tr(),
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            _Section(
              title: 'today.cardGuide.tierTitle'.tr(),
              body: 'today.cardGuide.tierBody'.tr(
                namedArgs: {
                  'strong': '$strong',
                  'medium': '$medium',
                  'mediumMax': '${strong - 1}',
                  'weak': '$weak',
                  'weakMax': '${medium - 1}',
                },
              ),
              extra: const Wrap(
                spacing: DesignTokens.spacing12,
                runSpacing: DesignTokens.spacing8,
                children: [
                  ScoreTierBadge(score: strong * 1.0),
                  ScoreTierBadge(score: medium * 1.0),
                  ScoreTierBadge(score: weak * 1.0),
                  ScoreTierBadge(score: weak - 1.0),
                ],
              ),
            ),
            _Section(
              title: 'today.cardGuide.pullbackTitle'.tr(),
              body: 'today.cardGuide.pullbackBody'.tr(),
            ),
            _Section(
              title: 'today.cardGuide.horizonTitle'.tr(),
              body: 'today.cardGuide.horizonBody'.tr(),
            ),
            _Section(
              title: 'today.cardGuide.numberTitle'.tr(),
              body: 'today.cardGuide.numberBody'.tr(),
            ),
            _Section(
              title: 'today.cardGuide.elementsTitle'.tr(),
              body: 'today.cardGuide.elementsBody'.tr(
                namedArgs: {'days': '${MiniSparkline.maxDataPoints}'},
              ),
            ),
            const SizedBox(height: DesignTokens.spacing16),
            Text(
              'disclaimer.short'.tr(),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.body, this.extra});

  final String title;
  final String body;
  final Widget? extra;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: DesignTokens.spacing16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: DesignTokens.spacing4),
          if (extra != null) ...[
            extra!,
            const SizedBox(height: DesignTokens.spacing8),
          ],
          Text(body, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}
