import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:daredevil/app/router.dart' show completeOnboarding;
import 'package:daredevil/core/constants/animations.dart';
import 'package:daredevil/core/constants/app_routes.dart';
import 'package:daredevil/core/theme/design_tokens.dart';
import 'package:daredevil/core/theme/semantic_colors.dart';

/// 首次使用引導頁面
///
/// 3 步驟介紹 Daredevil 核心功能，完成後標記已完成並導向主頁面。
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  /// SharedPreferences key，用於追蹤引導頁是否已完成
  static const String completedKey = 'onboarding_complete';

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _currentPage = 0;

  static const _totalPages = 3;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _completeOnboarding() async {
    await completeOnboarding();
    if (mounted) {
      context.go(AppRoutes.home);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // 略過按鈕
            Align(
              alignment: Alignment.topRight,
              child: TextButton(
                onPressed: _completeOnboarding,
                child: Text('onboarding.skip'.tr()),
              ),
            ),

            // 頁面內容
            Expanded(
              child: PageView(
                controller: _controller,
                onPageChanged: (page) => setState(() => _currentPage = page),
                children: [
                  _OnboardingPage(
                    icon: Icons.auto_awesome,
                    iconColor: theme.colorScheme.primary,
                    title: 'onboarding.step1Title'.tr(),
                    description: 'onboarding.step1Desc'.tr(),
                  ),
                  _OnboardingPage(
                    icon: Icons.analytics_outlined,
                    // 橘色圓 tint 保留識別，icon 走疊色文字色（淺色主題
                    // Colors.orange 對自身 tint 合成底僅 2.0:1）
                    iconColor: WarningColors.onTintFor(theme.brightness),
                    tintColor: Colors.orange,
                    title: 'onboarding.step2Title'.tr(),
                    description: 'onboarding.step2Desc'.tr(),
                  ),
                  _OnboardingPage(
                    icon: Icons.notifications_active_outlined,
                    // 主題感知(終審實測:theme-invariant 版對淺色自身
                    // tint 底僅 2.34:1,successLight 5.74:1)
                    iconColor: DesignTokens.successColor(theme),
                    title: 'onboarding.step3Title'.tr(),
                    description: 'onboarding.step3Desc'.tr(),
                  ),
                ],
              ),
            ),

            // 頁面指示圓點
            Padding(
              padding: const EdgeInsets.only(bottom: DesignTokens.spacing16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  _totalPages,
                  (i) => AnimatedContainer(
                    duration: AnimDurations.standard,
                    margin: const EdgeInsets.symmetric(
                      horizontal: DesignTokens.spacing4,
                    ),
                    width: i == _currentPage ? 24 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: i == _currentPage
                          ? theme.colorScheme.primary
                          : theme.colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(
                        DesignTokens.radiusXs,
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // 操作按鈕
            Padding(
              padding: const EdgeInsets.fromLTRB(
                DesignTokens.spacing24,
                0,
                DesignTokens.spacing24,
                DesignTokens.spacing32,
              ),
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: _currentPage == _totalPages - 1
                    ? FilledButton(
                        onPressed: _completeOnboarding,
                        child: Text('onboarding.getStarted'.tr()),
                      )
                    : FilledButton.tonal(
                        onPressed: () {
                          _controller.nextPage(
                            duration: AnimDurations.normal,
                            curve: AnimCurves.breathe,
                          );
                        },
                        child: Text('onboarding.next'.tr()),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnboardingPage extends StatelessWidget {
  const _OnboardingPage({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.description,
    this.tintColor,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String description;

  /// 背景圓 tint 色；未指定時沿用 [iconColor]。
  final Color? tintColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: DesignTokens.spacing32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: (tintColor ?? iconColor).withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 48, color: iconColor),
          ),
          const SizedBox(height: DesignTokens.spacing32),
          Text(
            title,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: DesignTokens.spacing16),
          Text(
            description,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.6,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
