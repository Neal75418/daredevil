import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'package:daredevil/core/theme/breakpoints.dart';
import 'package:daredevil/core/theme/design_tokens.dart';

/// BuildContext 響應式擴展
///
/// 提供便捷的方法來判斷設備類型和取得響應式值。
///
/// 使用範例：
/// ```dart
/// // 判斷設備類型
/// if (context.deviceType == DeviceType.mobile) { ... }
/// if (context.isDesktop) { ... }
///
/// // 根據設備類型返回不同值
/// final padding = context.responsive(
///   mobile: 16.0,
///   tablet: 24.0,
///   desktop: 32.0,
/// );
/// ```
extension ResponsiveHelper on BuildContext {
  /// 螢幕寬度
  double get screenWidth => MediaQuery.sizeOf(this).width;

  /// 設備類型
  DeviceType get deviceType {
    final width = screenWidth;
    if (width < Breakpoints.mobile) return DeviceType.mobile;
    if (width < Breakpoints.tablet) return DeviceType.tablet;
    return DeviceType.desktop;
  }

  /// 是否為桌面
  bool get isDesktop => deviceType == DeviceType.desktop;

  /// 是否應顯示 NavigationRail（側邊導航）
  bool get shouldShowNavigationRail =>
      screenWidth >= Breakpoints.navigationRailBreakpoint;

  /// 根據設備類型返回對應值
  ///
  /// [mobile] 手機時的值（必填）
  /// [tablet] 平板時的值（可選，預設使用 mobile）
  /// [desktop] 桌面時的值（可選，預設使用 tablet 或 mobile）
  T responsive<T>({required T mobile, T? tablet, T? desktop}) {
    return switch (deviceType) {
      DeviceType.desktop => desktop ?? tablet ?? mobile,
      DeviceType.tablet => tablet ?? mobile,
      DeviceType.mobile => mobile,
    };
  }

  /// 響應式水平邊距
  double get responsiveHorizontalPadding {
    return responsive(mobile: 16.0, tablet: 24.0, desktop: 32.0);
  }

  /// 響應式卡片間距
  double get responsiveCardSpacing {
    return responsive(mobile: 8.0, tablet: 12.0, desktop: 16.0);
  }

  /// 響應式 GridView 列數
  ///
  /// 基於最小卡片寬度計算，確保卡片不會過窄。
  /// 計算公式：(可用寬度 + 間距) / (最小卡片寬度 + 間距)
  int get responsiveGridColumns {
    final padding = responsiveHorizontalPadding;
    final spacing = responsiveCardSpacing;
    final availableWidth = screenWidth - (padding * 2);
    const minCardWidth = DesignTokens.stockCardMinWidth;

    // 計算可容納的欄數
    // 公式：(可用寬度 + 間距) / (最小卡片寬度 + 間距)
    final maxColumns = ((availableWidth + spacing) / (minCardWidth + spacing))
        .floor();

    // 限制在 1-4 欄之間
    return math.max(1, math.min(maxColumns, 4));
  }
}
