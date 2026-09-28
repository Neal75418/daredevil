import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 全 app 通知「資料已寫入新一輪」的單調遞增 epoch counter。
///
/// 用途：每一輪更新完成後 bump（呼叫端見 [DataUpdateEpoch.bump]），依賴
/// `daily_analysis` / `daily_reason` / `daily_price` 的 provider
/// （scan, watchlist, industryEps, stockDetail）
/// 用 `ref.listen` 監聽，收到任意值變動就觸發各自的 `loadData()` reload；
/// 另有 modeRecommendation、pinnedThesis 等以 `ref.watch` 隨 epoch 重建。
///
/// 過去 `runUpdate` 完成後只 imperative 呼叫 `todayProvider.loadData()` 與
/// `marketOverviewProvider.loadData()`，其他畫面開著就看不到新資料；尤其
/// 背景 `BackgroundUpdateService` 也是 silent — 沒有任何 UI signal 可掛。
///
/// counter 的具體值無語意，只用「變動」事件本身 trigger reload。整數
/// wrap-around 不會發生（單一 session 增加 2^63 次需要 9000 年）。
///
/// ## 注意
///
/// 1. **只有 bump 後才會觸發 listener**：第一次啟動畫面時不會自動觸發，
///    consumer 仍需在 `build()` 內主動 `loadData()`（既有行為不變）。
/// 2. **listener 應該無腦呼叫自己的 loadData**：不要在 listener 內加條件
///    判斷，否則容易漏 reload。靠 notifier 自身的 generation / 早退 guard
///    避免多重 reload race（既有 pattern）。
/// 3. **過度頻繁 bump 風險**：只在「一輪更新完成」的時點 bump（見 [DataUpdateEpoch.bump]
///    的三個呼叫端），避免每筆寫入都 bump。若未來細粒度寫入也想觸發 reload，建議分拆
///    multiple epoch（如 `recommendationsEpoch`、`pricesEpoch`）而非全 app
///    一條。
final dataUpdateEpochProvider = NotifierProvider<DataUpdateEpoch, int>(
  DataUpdateEpoch.new,
);

class DataUpdateEpoch extends Notifier<int> {
  @override
  int build() => 0;

  /// 通知所有 listener「資料已寫入新一輪」。
  ///
  /// 呼叫端（皆在 today_provider），都不看該輪成敗：
  /// - `runUpdate` 等到底層更新回傳後（含 success=false 的失敗輪）
  /// - 逾時後底層更新遲到回傳
  /// - 回前景時偵測到 App 外（launchd CLI 或背景任務）完成的更新——背景
  ///   isolate 的更新當下不經 provider 樹、不會 bump，要等回前景由這裡補
  void bump() {
    state = state + 1;
  }
}
