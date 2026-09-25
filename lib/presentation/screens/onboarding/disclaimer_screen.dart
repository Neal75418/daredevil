import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'package:daredevil/core/theme/design_tokens.dart';

/// 免責聲明同意頁（引導之後、進入主畫面之前）
///
/// 沒有略過：按下同意才會呼叫 [onAccept]。刻意不攔返回鍵——此頁通常由
/// redirect 以 `go` 抵達、堆疊只有它，返回＝離開 App＝不同意，攔下來反而
/// 讓 Android 使用者離不開。（通知點擊的 `push` 被 redirect 時可能再疊一頁
/// 同意頁，返回只會退到下層同意頁、繞不過去；同意後的 `go` 會清掉整個堆疊。）
/// 同意狀態由 router 持有，這裡只負責呈現，
/// 避免畫面反向 import router（onboarding 已有這條循環）。
class DisclaimerScreen extends StatelessWidget {
  const DisclaimerScreen({super.key, required this.onAccept});

  /// SharedPreferences key。條款內容有實質變更時換新版本號，
  /// 讓所有人重新同意。
  static const String acceptedKey = 'disclaimer_accepted_v1';

  final VoidCallback onAccept;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bodyStyle = theme.textTheme.bodyLarge?.copyWith(height: 1.6);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              // 可捲動：大字級或窄螢幕時條款不得被截掉
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  DesignTokens.spacing24,
                  DesignTokens.spacing32,
                  DesignTokens.spacing24,
                  DesignTokens.spacing16,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 40,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(height: DesignTokens.spacing16),
                    Semantics(
                      header: true,
                      child: Text(
                        'disclaimer.title'.tr(),
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: DesignTokens.spacing16),
                    Text('disclaimer.intro'.tr(), style: bodyStyle),
                    const SizedBox(height: DesignTokens.spacing12),
                    for (final key in const [
                      'disclaimer.point1',
                      'disclaimer.point2',
                      'disclaimer.point3',
                      'disclaimer.point4',
                    ])
                      Padding(
                        padding: const EdgeInsets.only(
                          top: DesignTokens.spacing8,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ExcludeSemantics(
                              child: Text('•  ', style: bodyStyle),
                            ),
                            Expanded(child: Text(key.tr(), style: bodyStyle)),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                DesignTokens.spacing24,
                0,
                DesignTokens.spacing24,
                DesignTokens.spacing32,
              ),
              // 最小高度而非固定高度：系統大字級時按鈕文字不被截掉
              child: FilledButton(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed: onAccept,
                child: Text('disclaimer.accept'.tr()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
