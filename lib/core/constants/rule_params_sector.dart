/// 產業領導（sector rotation）選股參數
///
/// Used by: mode_recommendation_provider（排序 rank-blend）、SectorStrengthService
///
/// 設計：docs/plans/2026-06-28-sector-leadership-and-rs-design.md
abstract final class SectorParams {
  /// 產業領導 tilt 權重（rank-blend：finalScore = (1−W)·baseRank + W·sectorRank）。
  ///
  /// **0 = 停用（dormant）**。族群動能 tilt 在 `tool/calibration.db` **全期（2021-2026、
  /// 含 2022 空頭）backtest 無持續 edge**：上升 regime IC −0.008、全期 −0.012、逐年
  /// 2021~2025 皆 ≈0 或負。先前一度啟用 0.15 是因只用近期窗（2025-2026）的 +0.054，
  /// 事後證實那是 **2026 單年 outlier**（+0.127）。未過「全期要變好」gate → roll 回 0。
  ///
  /// 機制（rank-blend + 下方 regime gate）已建好並 dormant。**設正值前必過 calibration.db
  /// 全期 gate**（別只看近期窗 — 這就是當初誤啟用的教訓）。
  static const double tiltWeight = 0.0;

  /// regime gate 的市場趨勢回看天數：全市場 [regimeLookbackDays]D **中位數**
  /// 報酬 > 0 視為
  /// 上升 regime、才套 tilt。用長窗（120D）而非短窗：short window 會把空頭反彈誤判
  /// 為上升（backtest 實測短窗 leak 22 個空頭反彈日、長窗只 leak 4 個）。
  static const int regimeLookbackDays = 120;

  /// regime 判定的最少有效股數：載入 universe 中歷史足 [regimeLookbackDays]+1 的
  /// 股票不足此數視為資料不足（fresh DB / 回補中），不做 regime 判定。
  static const int regimeMinEligibleStocks = 50;

  // ── 族群轉向(2026-08-11)────────────────────────────────────────────
  //
  // 既有排行只有 20日/5日 兩個**水準值**,而資金轉向是**變化率**。
  // 2026-08-10 實測:半導體 20日排第 34、5日排第 1,單看任一窗口都看不出
  // 它正在變成主流;躍升 +33 名才是訊號。

  /// 分類用的分位門檻:名次落在前/後 [rotationTierFraction] 才算「強/弱」。
  ///
  /// 用**分位**而非固定名次:族群數會隨資料完整度變動(實測 34~39 個),
  /// 寫死「前 10 名」在族群變少時會把一半都算成強。
  static const double rotationTierFraction = 1 / 3;

  /// 強者榜門檻(v3.4 第 1 層):月漲幅。
  ///
  /// UI 用成員中通過此門檻的檔數決定卡片要不要淡化——**0 檔代表點進去也
  /// 沒東西可買**,躍升再多都是死路(2026-08-10:化學工業躍升 +24 名但
  /// 強者榜 0 檔)。
  static const double rotationStrongListRet20Pct = 15.0;

  /// 強者榜門檻:日均量(股)。3,000 張 = 3,000,000 股。
  static const double rotationStrongListDailyVolumeShares = 3_000_000;

  // ==================================================
  // 族群排行（今日頁顯示層，不進評分）
  //
  // 使用者選股法則 L1「族群決定 80%」的自動化：輪動前段＋法人方向。
  // tiltWeight dormant 是「評分因子無全期 edge」的結論，不影響資訊呈現。
  // ==================================================

  /// 排行顯示的產業數上限。初版 8（對齊產業表現卡的前後各 4 名量級），
  /// 2026-07-22 使用者放寬到 12——給轉折中的族群多些露出空間，橫向
  /// 滑動無版面代價。
  static const int rankingTopN = 12;

  /// 產業成員（有選定視窗報酬資料）少於此數不進排行——樣本太小、中位數無
  /// 代表性。實例：農業科技業 4 檔（+7.3/+6.3/-1.5/-5.0%）兩漲兩跌拼出
  /// +2.4% 中位數、法人卻是賣超，2026-07-22 使用者實機看到後定 5。
  static const int rankingMinMembers = 5;

  /// 每個產業展開顯示的領漲成員數上限
  static const int rankingTopMembersCount = 5;

  /// 法人方向的合計視窗（交易日）：外資+投信近 N 日淨買賣。對齊使用者
  /// 法則 L2「外資或投信近 3 日連買」的觀察窗。
  static const int rankingInstitutionalDays = 3;

  /// 族群排行載入價格歷史的回看日曆天數：最長視窗（20日）報酬需 21 個
  /// 交易日 ≈ 31 日曆天，+ 連假 margin（CNY 假期叢集可達 9 天）取 45；
  /// 5日視窗共用同一份載入。
  static const int rankingHistoryCalendarDays = 45;

  /// 法人方向載入的回看日曆天數：3 個交易日 + 連假 margin。10 天在 CNY
  /// 連假（9 日曆天）收假首日只涵蓋 1 個交易日——「法人3日」靜默變 1 日
  /// （審查發現），取 20 覆蓋最壞情境（守門測試用 2026 CNY 實際行事曆驗）。
  static const int rankingInstitutionalCalendarDays = 20;
}
