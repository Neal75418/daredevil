import 'package:flutter/material.dart';

import 'package:daredevil/core/theme/breakpoints.dart';

/// App 內所有底部面板的唯一入口（守門：`test/presentation/widgets/app_bottom_sheet_test.dart`）。
///
/// - **一律開在最上層導覽器**（2026-09-26 定案）：分頁內的面板若開在分頁
///   自己的導覽器，底部導覽列不被遮住、開著也能切分頁，切回來時面板還開著。
///   面板內容都是看完或設定完就關的（預覽、篩選、說明），應是強制回應
/// - **寬視窗限寬**：Material 3 預設已限寬 640；明寫是為了不依賴主題預設
///   （將來改主題或切回 Material 2 時面板不會撐滿全寬）。窄視窗仍滿寬
///
/// 只轉交下列參數；需要其他原生參數（如 `isDismissible`）時先擴充本函式。
Future<T?> showAppBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = false,
  bool useSafeArea = false,
  bool? showDragHandle,
  Color? backgroundColor,
  ShapeBorder? shape,
}) => showModalBottomSheet<T>(
  context: context,
  builder: builder,
  useRootNavigator: true,
  constraints: const BoxConstraints(maxWidth: Breakpoints.sheetMaxWidth),
  isScrollControlled: isScrollControlled,
  useSafeArea: useSafeArea,
  showDragHandle: showDragHandle,
  backgroundColor: backgroundColor,
  shape: shape,
);
