import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';

/// 讓滑鼠與觸控板也能拖曳捲動。
///
/// 🚨 **為什麼需要**(2026-08-11 實機):Flutter 桌面的預設 `dragDevices`
/// **不含 mouse**,於是橫向清單在 macOS 上既不能用滑鼠拖、也不吃垂直滾輪
/// ——內容一超出視窗寬度就再也看不到。
///
/// 實機現象:族群排行切到「轉向」後有 11+ 張卡片,超出寬度的那幾張完全
/// 滑不到。
///
/// **為什麼設在 MaterialApp 而非個別清單**:全專案有 8 處
/// `scrollDirection: Axis.horizontal`,而先前只有 `upcoming_events_section`
/// 自己包了一層 ScrollConfiguration ——**修一處等於留七個同樣的坑**。
class DesktopDragScrollBehavior extends MaterialScrollBehavior {
  const DesktopDragScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => const {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.stylus,
    PointerDeviceKind.invertedStylus,
  };
}
