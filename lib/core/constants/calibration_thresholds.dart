/// Calibration pipeline canonical thresholds（**唯一 source of truth**）
///
/// 為什麼需要這個檔：
/// rule_accuracy_service（app runtime）、replay_calibrator（tool）、
/// recalibrate（tool）三個 writer 都會用到「success / cut」門檻決定：
///
/// - 某次推薦的 returnRate 算不算「命中」(`successThresholds`)
/// - 一條 rule 在 calibration 時要不要被砍 (`hitRateCutThreshold`,
///   `tStatCutThreshold`, `sampleSizeCutThreshold`)
///
/// 這些常數**過去散在三個檔案**，且註解寫「對齊 X」但值不同 →
/// rule_accuracy 表會被先後寫入用不同門檻的統計，造成 calibration
/// 不可重現。
///
/// 統一來源 = 只有這一份；所有 writer 與 calibrator 都 import 這裡。
///
/// ## 選值依據
///
/// 5D / 60D **採用實證 calibration 校正值**，10D / 20D 仍走 Stage 2 LEAN
/// scoring overhaul plan 鎖定的設計值（`docs/plans/2026-04-11-scoring-stage2-design.md`）。
///
/// **5D / 60D 實證背景（2026-06）**：
/// plan 原設計 5D=3%、60D=12%。2 年市場資料下 recalibrate 結果幾乎全 cut
/// （40 條 rule short 0 / long 1 active），分布顯示：
///   - sample 充足的 5D rule 最高 avg_return 僅 2.38%（< 3%）
///   - 60D 多數 rule avg_return 3-6%（遠 < 12%）
/// 3.0/12.0 屬於設計拍腦袋值，沒有實證根據。修訂為 1.5/8.0，對應約
/// 「1 sigma above market noise」（台股 5D std ≈ 0.5-1%、60D std ≈ 2-3%），
/// 也與 fd693e1 前 production runtime 隱式使用值一致。
///
/// **已知 monotone violation**：修訂後 [20]=8.0, [60]=8.0 — 中線 [10]/[20]
/// 服務於 rule_accuracy_service 內部統計（非 calibrated_scores），是否同步
/// 降值留作 follow-up（不阻擋 ship）。
///
/// - **Success threshold**：5D ≥ 1.5%、60D ≥ 8%、10D ≥ 5%、20D ≥ 8%。
/// - **Hit rate cut**：< 55% 砍（比隨機 +5% 才有 alpha）
/// - **t-stat cut**：< 1.5 砍（信賴度門檻）
/// - **Sample size cut**：< 30 砍（統計顯著性下限）
///
/// 修改任何常數請同步更新 plan 與此 docstring。
abstract final class CalibrationThresholds {
  /// 每個 holding period 對應的「成功」門檻（returnRate %）
  ///
  /// `returnRate >= threshold` 算命中。
  ///
  /// - **1D / 3D**：未列出 → fallback 至 [defaultSuccessThreshold]
  ///   （短線雜訊大，門檻嚴反而測不出真訊號）
  /// - **5D**：1.5%（實證 ≈ 1σ above 5D market noise；calibration evidence-based）
  /// - **10D**：5%（中線合理目標；plan-based，待實證 follow-up）
  /// - **20D**：8%（中線強勁目標；plan-based，待實證 follow-up）
  /// - **60D**：8%（實證 ≈ 1σ above 60D market noise；calibration evidence-based）
  static const Map<int, double> successThresholds = {
    5: 1.5,
    10: 5.0,
    20: 8.0,
    60: 8.0,
  };

  /// 未明確設定 threshold 的 period 使用的 fallback（非負即算命中）
  static const double defaultSuccessThreshold = 0.0;

  /// Proportion z-test 的 null hypothesis — 「隨機任一台股窗口達到 success
  /// threshold」的 baseline 機率。
  ///
  /// **為什麼需要**：之前 `Calibrator.computeTStat` 拿 `0.5`（隨機 50%）
  /// 當 baseline，但台股實證 baseline 跟 horizon + threshold 強相關：
  /// 例如 5D ≥1.5% 真實 baseline 是 ~34.6%，不是 50%。用 0.5 算 t-stat
  /// 會系統性低估 rule 的 alpha，導致幾乎全 cut（你 DB 觀察到「短線
  /// calibrated JSON 0 active rule」就是這個 bug）。
  ///
  /// **資料來源（2026-06-18）**：對個人 dev DB（daily_price ~230K 個
  /// windows）統計 per-(period, threshold) 命中率：
  ///   3D ≥ 0.0%  → 0.5547
  ///   5D ≥ 1.5%  → 0.3461
  ///   10D ≥ 5.0% → 0.2324
  ///   20D ≥ 8.0% → 0.2369
  ///   60D ≥ 8.0% → 0.3965
  ///
  /// **TODO**：硬編碼是過渡作法。理想是 `tool/recalibrate.dart` 跑時
  /// 從當下 daily_price 動態算 baseline（市場結構會變、敏感期的
  /// baseline 也不穩定）。先寫死避免每次 recalibrate 都重跑 SQL。
  static const Map<int, double> successProbabilityBaselines = {
    3: 0.5547,
    5: 0.3461,
    10: 0.2324,
    20: 0.2369,
    60: 0.3965,
  };

  /// 未列出 period 的 fallback baseline。0.5 = 對 fallback 走原來
  /// 「對隨機 50%」的行為（最保守、最不傷害向後相容）。
  static const double defaultBaselineProbability = 0.5;

  /// Calibration cut：hit_rate 必須 ≥ 此值才能保留
  ///
  /// **注意 2026-06-18**：以前語意是「比隨機 (0.50) 高 5pp」，配合
  /// 假定 baseline=0.5 才合理。實證 baseline 校正後（[successProbabilityBaselines]），
  /// 此 cut 跟 baseline 解耦 — 邏輯改成「絕對命中率 ≥ 55%」純粹是
  /// minimum effect size 過濾。已知缺陷：5D baseline 34.6% 下要求
  /// 55% 絕對命中率仍是「+20pp lift」門檻偏嚴（多數 rule 達不到）。
  /// 修正方向是改成 baseline-relative lift（`hitRate >= baseline + delta`），
  /// 但會跟現有 active rule 的 cut/active 判定產生 drift，所以這版只
  /// 修 t-stat 不動 hit-rate；hit-rate 改造留作 follow-up。
  static const double hitRateCutThreshold = 0.55;

  /// Calibration cut：proportion z-test 的 |t_stat| 必須 ≥ 此值才能保留
  ///
  /// 1.5 對應約 86.6% 信賴區間。低於此視為統計上不顯著。
  static const double tStatCutThreshold = 1.5;

  /// Calibration cut：sample 數必須 ≥ 此值才能保留
  ///
  /// 30 是統計顯著性實務常用下限。
  static const int sampleSizeCutThreshold = 30;

  // ==========================================================================
  // 超額模式（clustered 決策層）專用 — 見
  // docs/plans/2026-07-10-excess-decision-layer-clustered-tstat.md
  // ==========================================================================

  /// 超額模式的 canonical success 門檻（超額百分點）。
  ///
  /// 0 = 「贏過當日大盤平均即命中」。replay（`ReplayConfig.excessSuccessThreshold`
  /// 預設）與 app loader 的 drift guard（excess JSON 的
  /// `success_threshold_pct` 比對基準）共用此值 —— 三個 writer/reader
  /// 不得各自寫死。
  static const double excessSuccessThreshold = 0.0;

  /// 負證據歸零的 t-statistic 門檻（2026-07-29 三態 lookup）。
  ///
  /// 校準 cut 到 0 的規則中，`avg_return < 0 且 t_stat <= 此值` 者視為
  /// 「有決定性負面證據」——lookup 回 0（歸零生效），不再 fallback 到
  /// hardcoded 正分。其餘 cut（hit_rate 不足但 t 為正、樣本不足、缺
  /// metadata）維持 fallback：它們是「證據不足」不是「證據為負」。
  ///
  /// -1.5 與離線重放（2026-07-29，10 交易日）採用的判準一致：該重放實測
  /// 被歸零除名的股票 5 日超額報酬 -1.68%（vs 兩版皆留 -0.10%），
  /// 支持歸零方向。門檻本身沿用 clustered 校準的顯著性慣例，非最佳化參數。
  static const double negativeEvidenceTStatMax = -1.5;

  /// 負證據歸零的方向 gate 顯式排除集（2026-07-30）。
  ///
  /// 方向 gate 用「hardcoded > 0 = 多方宣稱」判定可歸零性，但個別規則的
  /// 正分是**空方訊號的顯示強度**而非多方宣稱——校準管線把所有規則當
  /// 多方評（success = 觸發後上漲），對它們 avg<0 是**預測正確**，
  /// 不是負證據。落進這個縫隙的規則在此顯式排除（不歸零 → lookup 回
  /// null → fallback hardcoded 顯示分）。
  ///
  /// **收錄判準**：hardcoded 為正、語意為空方/警示（觸發後預期下跌）、
  /// 且不參與多方 mode routing（neutral）。目前唯一命中：
  /// - `WEEK_52_LOW`（52 週新低，neutral 顯示分 +8；asset avg=-0.54
  ///   t=-5.5 正是弱勢股續弱的實證）
  ///
  /// 未來校準重跑若有新規則落縫隙，比照收錄並在
  /// calibrated_scores_test 的 e2e 斷言補上。
  static const Set<String> zeroingBearishDisplayExclusions = {'WEEK_52_LOW'};

  /// 超額模式 hit-rate cut：`hitRate ≥ 實證 universe baseline + 此 lift`。
  ///
  /// 取代絕對 0.55 門檻（上方 [hitRateCutThreshold] docstring 標註的
  /// known flaw）—— 絕對門檻的嚴格度隨 baseline 漂移（絕對模式 baseline
  /// 0.35–0.40 時是 +15–20pp、超額模式 ≈0.47 時只剩 +8pp），
  /// baseline-relative lift 才是固定 effect size。baseline 由 replay 對
  /// 全 universe stock-day 實測（存 `calibration_run_meta`），不硬編碼。
  static const double hitRateLiftThreshold = 0.05;

  /// Clustered t-stat 的觸發「日」數下限。
  ///
  /// pooled n（十萬級 firings）因同日橫斷面相關 + 持有窗重疊是偽重複，
  /// 有效樣本量級是「觸發日」數 —— clustered t 對日均值序列計算，樣本
  /// 下限也以日數計。
  static const int minDistinctDates = 30;

  // ==========================================================================
  // Survivorship bias（audit finding #7a，2026-07-18）
  // ==========================================================================

  /// Symbol 最新價格早於 dataset 自身 max date 這麼多「日曆天」，視為停止
  /// 提供新資料（下市 / 長停）—— 該 symbol 的**所有**訊號都從 rule_accuracy
  /// 統計排除，而非只排除算不出 exit return 的尾端 reason。
  ///
  /// **為什麼是「整個 symbol」而非「只排除算不出 return 的 reason」**：舊行為
  /// 只在缺 exit price 時 `continue`（單一 reason × period 粒度），只能排除
  /// 「剛好落在下市點附近」的訊號，卻保留該股下市前**仍算得出（較早、較
  /// 正常）**的訊號——恰是 winner 全留、崩盤前夕靜默消失的經典存活者偏差
  /// 樣式。整股排除才不會挑好留壞：與其呈現「已知不完整」的片面數字，
  /// 不如完全不採計。
  ///
  /// **30 天為保守閾值**：正常交易的股票最多幾天無成交（連假 + 緩衝），
  /// 30 天涵蓋任何可能的長假期，同時不會誤殺短暫停牌股。
  static const int stalePriceThresholdDays = 30;

  /// replay 資料多久之後，recalibrate 該對使用者示警（天）。
  ///
  /// **為什麼需要這個警告**：完整校準是 backfill → replay → recalibrate 三
  /// 階段（`scripts/calibrate.sh`），但只跑第三階段也會成功——exit code 0、
  /// candidate JSON 照常產出、無任何異常訊息，拿到的卻是基於舊 replay 樣本
  /// 的分數。與 launchd CLI 產物落後同屬「過期但三個訊號全正常」，同樣靠把
  /// 時間戳印出來解決。
  ///
  /// **為什麼是 30 天**：規則與資料的改動節奏以月計；一個月內的 replay 樣本
  /// 重算仍有意義，超過就該連 backfill 一起重跑。這是提示而非硬性阻擋——
  /// 刻意只重算末段是合法用法，警告只負責讓它變成有意識的選擇。
  static const int staleReplayWarnDays = 30;
}
