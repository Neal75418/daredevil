import 'package:flutter/material.dart';

/// 整頁空狀態／錯誤頁的容器：以剩餘空間撐開並置中，空間不足（小螢幕、
/// 放大字級）時改為可捲動，不會溢位；放在 RefreshIndicator 內可下拉重新
/// 整理。空狀態所需高度隨字級與螢幕尺寸變動，不可用固定高度或裸放在
/// Expanded／Center 裡。
///
/// - 上下讓出 `MediaQuery.padding`：主分頁的底部導覽列以 `extendBody`
///   疊在內容上，Scaffold 會把導覽列高度併入 bottom；沒有 AppBar 的頁面
///   （今日）top 是狀態列高度，有 AppBar 時為 0。
/// - physics 明寫 AlwaysScrollable：未指定 controller 的垂直 ScrollView
///   本就預設如此，但傳入 [controller]（例如 DraggableScrollableSheet
///   的 controller）後不再套用該預設，內容未滿版時就無法拖動或下拉。
class FillRemainingScrollable extends StatelessWidget {
  const FillRemainingScrollable({
    super.key,
    required this.child,
    this.controller,
  });

  final Widget child;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      controller: controller,
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Padding(
            padding: EdgeInsets.only(
              top: MediaQuery.paddingOf(context).top,
              bottom: MediaQuery.paddingOf(context).bottom,
            ),
            child: Center(child: child),
          ),
        ),
      ],
    );
  }
}
