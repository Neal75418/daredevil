/// UI 層共用常數
///
/// 集中管理動畫時間、捲動閾值等 UI 相關數值，
/// 避免散落在各 Widget 中的 magic numbers。
abstract final class UiConstants {
  /// Grid 卡片交錯動畫延遲（每張卡片間隔毫秒）
  static const int gridAnimationDelayMs = 30;

  /// List 卡片交錯動畫延遲（每張卡片間隔毫秒）
  static const int listAnimationDelayMs = 50;

  /// Grid 卡片動畫時長（毫秒）
  static const int gridAnimationDurationMs = 300;

  /// List 卡片動畫時長（毫秒）
  static const int listAnimationDurationMs = 400;

  /// 無限捲動觸發距離（像素）
  static const double infiniteScrollThresholdPx = 300.0;

  /// 卡片寬度低於此值時切換為緊湊佈局（像素）
  static const double compactCardBreakpoint = 320.0;

  /// 卡片寬度達此值時才顯示迷你走勢圖（像素）
  ///
  /// 走勢圖佔 78px (70+8)，需要比 compact 門檻更多空間，
  /// 避免 320-400px 邊界寬度的水平溢出。
  static const double sparklineMinWidth = 400.0;

  /// 自訂篩選捲動載入觸發距離（像素）
  static const double scrollLoadMoreThreshold = 200.0;
}
