/// 響應式斷點定義
///
/// 用於統一管理不同設備尺寸的斷點閾值。
/// 參考 Material Design 3 斷點建議：
/// - Compact (手機): < 600dp
/// - Medium (平板): 600-839dp
/// - Expanded (大平板/桌面): >= 840dp
abstract final class Breakpoints {
  /// 手機最大寬度（< 600px 為手機）
  static const double mobile = 600;

  /// 平板最大寬度（600-1024px 為平板）
  static const double tablet = 1024;

  /// 導航欄收合斷點（低於此寬度使用 BottomNav）
  static const double navigationRailBreakpoint = 600;

  /// 全頁內容欄最大寬度（桌面）。
  ///
  /// 手機優先的頁面（行事曆等）直接鋪滿桌面視窗時，格線被拉到極寬、
  /// 資訊密度崩壞；以 `Center + ConstrainedBox(maxWidth: 此值)` 收斂。
  /// 1000 介於 M3 expanded pane（840）與雙欄佈局之間：7 欄月曆格
  /// 每格仍有 ~140dp、清單行寬也不至於一行拉太長。
  static const double contentMaxWidth = 1000;

  /// 單欄數值表格最大寬度(桌面)。
  ///
  /// 「名稱+少數右對齊數字欄」的清單(營收總覽等)用 [contentMaxWidth]
  /// (1000,為 7 欄月曆設計)仍會在名稱與數字之間留大段空白;720 讓
  /// 名稱欄 ~420dp、數字欄緊湊靠攏,讀起來才像表格。
  static const double tableMaxWidth = 720;

  /// Modal bottom sheet 最大寬度。
  ///
  /// 底部面板的最大寬度（[showAppBottomSheet] 使用）。Material 3 預設亦為
  /// 640；明寫以免依賴主題預設。窄視窗（< 此值）仍滿寬。
  static const double sheetMaxWidth = 640;
}

/// 設備類型枚舉
enum DeviceType {
  /// 手機（< 600px）
  mobile,

  /// 平板（600-1024px）
  tablet,

  /// 桌面（>= 1024px）
  desktop,
}
