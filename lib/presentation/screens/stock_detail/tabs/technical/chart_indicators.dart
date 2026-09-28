/// K 線圖指標的 app 端列舉。
///
/// 2026-08-03 隨 `k_chart_plus` 1.0.3→1.0.4 升級新增:套件把
/// `MainState` / `SecondaryState` enum 換成 indicator **class 實例**
/// (`MAIndicator` / `MACDIndicator`…),而 `Set.contains` 對 class 實例
/// 走 identity 比較——原本 `Set<MainState>` 的選取狀態模型無法平移。
///
/// 在 app 端保留自己的 enum,好處不只是能平移:選擇器 UI 與其測試從此
/// 不綁套件型別,下次套件再改 API 時,受影響面止於 stock_detail/widgets 下
/// 直接 import 套件的三個圖表檔(k_line_chart_widget、chart_indicator_styles、
/// k_chart_detail_popup)。
library;

/// K 線圖的均線天數(單一宣告點)。
///
/// 順序與 `IndicatorColors.maColorsFor` 的回傳一一對應——守門測試斷言
/// 「色數 ≥ 天數」,否則 1.0.4 的 `getMAColor` 會 `% maColors.length`
/// wrap 而靜默撞色。
const kTechnicalMaDayList = [5, 10, 20, 60];

/// 主圖指標(疊在 K 線上)
enum ChartMainIndicator { ma, boll, sar }

/// 副圖指標(獨立子圖)
enum ChartSecondaryIndicator { macd, kdj, rsi, wr, cci }
