import 'package:flutter/material.dart';

import 'package:daredevil/core/constants/live_quote_params.dart';
import 'package:daredevil/core/theme/design_tokens.dart';
import 'package:daredevil/core/theme/semantic_colors.dart';
import 'package:daredevil/domain/models/live_quote.dart';

/// 現價的閃色(盤中即時報價變動時,底色閃一下後淡出;2026-10-06)。
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
    duration: LiveQuoteParams.flashFade,
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
        final alpha = _controller.isAnimating
            ? LiveQuoteParams.flashTintAlpha * (1 - _controller.value)
            : 0.0;
        return DecoratedBox(
          key: PriceFlash.tintKey,
          decoration: BoxDecoration(
            color: alpha > 0 ? base.withValues(alpha: alpha) : null,
            borderRadius: BorderRadius.circular(DesignTokens.radiusXs),
          ),
          child: child,
        );
      },
    );
  }
}
