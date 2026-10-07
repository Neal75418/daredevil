import 'package:flutter/material.dart';

import 'package:daredevil/core/constants/live_quote_params.dart';
import 'package:daredevil/core/theme/design_tokens.dart';
import 'package:daredevil/core/theme/semantic_colors.dart';
import 'package:daredevil/domain/models/live_quote.dart';

/// 現價的閃色(盤中即時報價變動時;2026-10-06,2026-10-07 實機後改成券商
/// 看盤軟體的做法)。
///
/// 價格那一格整塊變成實心紅／綠、數字改成 [PriceColors.onFlash],維持
/// [LiveQuoteParams.flashDuration] 後一次收掉。色塊左右比 [child] 寬
/// [LiveQuoteParams.flashChipPadH]、上下與 [child] 同高,畫在 [child] 後面、
/// 不推動版面。
///
/// 只在收到新的閃色事件([flash] 的 id 變了)時閃。第一次建立時把現有的
/// id 當作已看過——清單捲回來重建卡片時不補閃。以下任一成立就不閃、只換
/// 數字:
/// - [enabled] 為 false(設定頁「價格閃色」);
/// - 系統要求停用動畫(`MediaQuery.disableAnimations`);
/// - iOS「減少動態效果」(`accessibilityFeatures.reduceMotion`)。
///
/// macOS 不回報系統的減少動態效果,只能靠設定頁的開關。
class PriceFlash extends StatefulWidget {
  const PriceFlash({
    super.key,
    required this.flash,
    required this.enabled,
    required this.child,
  });

  /// 閃色底色那一層的 key(測試讀實際渲染的顏色用)
  static const Key tintKey = ValueKey('priceFlashTint');

  final LiveQuoteFlash? flash;
  final bool enabled;
  final Widget child;

  @override
  State<PriceFlash> createState() => _PriceFlashState();
}

class _PriceFlashState extends State<PriceFlash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: LiveQuoteParams.flashDuration,
  );
  int? _seenId;
  bool _up = true;

  @override
  void initState() {
    super.initState();
    _seenId = widget.flash?.id;
  }

  @override
  void didUpdateWidget(PriceFlash oldWidget) {
    super.didUpdateWidget(oldWidget);
    final flash = widget.flash;
    if (flash == null || flash.id == _seenId) return;
    _seenId = flash.id;
    if (!_motionAllowed) return;
    _up = flash.up;
    _controller.forward(from: 0);
  }

  bool get _motionAllowed =>
      widget.enabled &&
      !MediaQuery.disableAnimationsOf(context) &&
      !View.of(context).platformDispatcher.accessibilityFeatures.reduceMotion;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = PriceColors.forChange(
      _up ? 1 : -1,
      Theme.of(context).brightness,
    );
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        // value 到 1 就收:elapsed 剛好等於 duration 的那一拍 value 已是 1、
        // 控制器還沒標記完成(isDone 是嚴格大於),只看 isAnimating 會多亮那一拍
        final flashing = _controller.isAnimating && _controller.value < 1;
        return Stack(
          // passthrough:外層約束原樣交給數字(固定寬、靠右對齊照舊),Stack
          // 永遠與數字同大,色塊才會剛好是數字左右各寬一圈
          fit: StackFit.passthrough,
          clipBehavior: Clip.none,
          children: [
            // 色塊用 Positioned 往左右擴:比數字寬一圈、又不推動版面
            Positioned(
              left: -LiveQuoteParams.flashChipPadH,
              right: -LiveQuoteParams.flashChipPadH,
              top: 0,
              bottom: 0,
              child: DecoratedBox(
                key: PriceFlash.tintKey,
                decoration: BoxDecoration(
                  color: flashing
                      ? base.withValues(alpha: LiveQuoteParams.flashTintAlpha)
                      : null,
                  borderRadius: BorderRadius.circular(DesignTokens.radiusXs),
                ),
              ),
            ),
            // 閃色時數字反色:深色主題的一般文字色疊在實心紅綠上對比不夠
            if (flashing)
              ColorFiltered(
                colorFilter: const ColorFilter.mode(
                  PriceColors.onFlash,
                  BlendMode.srcIn,
                ),
                child: child,
              )
            else
              child!,
          ],
        );
      },
    );
  }
}
