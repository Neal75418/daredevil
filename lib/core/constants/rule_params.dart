export 'package:daredevil/core/constants/reason_type.dart';
export 'package:daredevil/core/constants/rule_enums.dart';
export 'package:daredevil/core/constants/rule_params_alert.dart';
export 'package:daredevil/core/constants/rule_params_fundamental.dart';
export 'package:daredevil/core/constants/rule_params_indicator.dart';
export 'package:daredevil/core/constants/rule_params_institutional.dart';
export 'package:daredevil/core/constants/rule_params_pattern.dart';
export 'package:daredevil/core/constants/rule_params_pullback.dart';
export 'package:daredevil/core/constants/rule_params_sector.dart';
export 'package:daredevil/core/constants/rule_params_trend.dart';
export 'package:daredevil/core/constants/rule_scores.dart';

/// 規則引擎通用參數
///
/// 跨類別的通用常數（回溯天數、候選篩選、評分輸出、新聞關鍵字等）。
/// 領域特定參數已拆至：
/// - [TrendParams] — 趨勢 / 反轉 / 支撐壓力 / 價量背離
/// - [IndicatorParams] — RSI / KD / 均線 / 52 週高低點
/// - [InstitutionalParams] — 法人動向 / 籌碼面
/// - [FundamentalParams] — 基本面 / EPS / ROE / 估值 / 董監持股
/// - [PatternParams] — K 線型態
/// - [PullbackParams] — 強股回檔進場（Mode C v2）
/// - [SectorParams] — 族群強度 / 產業輪動
/// - [AlertParams] — 警示系統
///
/// ### 數值慣例
/// - **比例值**（0.0~1.0）：用於乘法運算，如 `price * (1 + ratio)`
///   例：`breakoutBuffer = 0.03`（3%）、`maDeviationThreshold = 0.05`（5%）
/// - **百分比值**（0~100）：用於直接比較，如 `if (rsi >= threshold)`
///   例：`scanRsiOverboughtThreshold = 75.0`、`dayTradingHighThreshold = 50.0`
/// - **倍數值**：用於量能比較，如 `volume >= avg * multiplier`
///   例：`volumeSpikeMult = 4.0`、`priceSpikeVolumeMult = 1.5`
abstract final class RuleParams {
  // ==================================================
  // 回溯與歷史資料
  // ==================================================

  /// 分析回溯天數（日曆日）
  ///
  /// 需足夠涵蓋 52 週（約 250 交易日）。
  /// 250 交易日 ÷ 0.71（扣除週末假日比例）≈ 352 日曆日。
  /// 使用 370 日曆日確保有足夠緩衝。
  static const int lookbackPrice = 370;

  /// 歷史資料緩衝天數（確保分析邊界情況有足夠資料）
  static const int historyBufferDays = 30;

  /// 所需歷史資料總天數（lookbackPrice + buffer）
  static const int historyRequiredDays = lookbackPrice + historyBufferDays;

  /// 候選股篩選時提前載入的緩衝天數
  ///
  /// 確保技術指標計算時有足夠的歷史資料。
  /// 與 [historyBufferDays] 區分：此值用於候選篩選，後者用於分析邊界。
  static const int historyLoadBuffer = 20;

  /// 成交量均線天數
  static const int volMa = 20;

  /// 成交量均線最低有效交易日比例
  ///
  /// 計算 `volMa` 均量時要求至少此比例的窗口期內有有效成交量
  /// （`volume > 0`，過濾停牌日），避免復牌後因基期過低產生
  /// 假訊號。0.8 = 20 日中至少 16 日。
  static const double volMaMinValidDayRatio = 0.8;

  /// 壓力/支撐偵測回溯天數
  static const int rangeLookback = 60;

  /// 波段高低點偵測視窗
  static const int swingWindow = 20;

  // ==================================================
  // 候選股篩選
  // ==================================================

  /// 候選股最低成交額（3000 萬台幣）
  ///
  /// 過濾低流動性股票，確保候選池品質。`LiquidityChecker` 在 scoring 層
  /// 對**最新單日**套用；候選層另有 20 日中位數版
  /// [liquidityMinMedianTurnoverNtd]（防單日爆量假通過），兩者互補。
  static const double minCandidateTurnover = 30000000;

  /// 高當沖規則最低成交量（10,000 張 = 10,000,000 股）
  static const double minDayTradingVolumeShares = 10000000;

  /// 極高當沖規則最低成交量（30,000 張 = 30,000,000 股）
  static const double minDayTradingExtremeVolumeShares = 30000000;

  /// 候選股快篩最低成交量（100 張 = 100,000 股）
  ///
  /// 過濾極低成交量冷門股，確保分析品質。
  static const double minQuickFilterVolumeShares = 100000;

  // ==================================================
  // 新聞規則關鍵字
  // ==================================================

  /// 新聞情緒分析正面關鍵字
  ///
  /// 每個詞須足夠具體以避免誤判。避免單字詞（如「訂單」「突破」）
  /// 因在中文語境中常出現在無關或相反的上下文中。
  ///
  /// **2026-07-18 移除「法說會」**（audit 真實案例：0050 利空標題
  /// 「外資提款…遭大砍」僅因含「法說會」被判定利多，score +8）。
  /// 法說會是中性事件詞——公司不論要公布好消息或壞消息都會召開法說會，
  /// 詞本身不帶方向性，不該單獨計分（見 [newsNegativeKeywords] 同步
  /// 移除「減資」的說明，同一失效模式）。
  static const List<String> newsPositiveKeywords = [
    // 營收相關
    '營收創新高',
    '營收成長',
    '業績亮眼',
    '獲利創高',
    '毛利率上升',
    // 訂單/產能（具體化，避免「訂單」「大單」「拿下」等單字詞）
    '接獲訂單',
    '拿下訂單',
    '接獲大單',
    '擴產',
    '產能滿載',
    // 法人動態
    '外資買超',
    '投信買超',
    // 市場動態（具體化，避免「突破」「看好」等單字詞）
    '利多',
    '漲停',
    '調升目標價',
    '目標價調升',
    '前景看好',
  ];

  /// 新聞情緒分析負面關鍵字
  ///
  /// 「庫存」單獨出現容易誤判（如「庫存回補」是正面訊號），
  /// 改用更具體的組合。
  ///
  /// **2026-07-18 移除「減資」**：字面同時涵蓋「虧損減資」（利空，公司用
  /// 減資彌補累積虧損）與「現金減資」（市場常視為利多，等同退還股東
  /// 現金、與特別股息類似），詞本身不帶方向性——跟
  /// [newsPositiveKeywords] 移除「法說會」同一失效模式（中性事件/動作詞
  /// 被當成有方向性的情緒詞）。真正利空的減資會同時出現「虧損」等詞，
  /// 已由既有關鍵字涵蓋。
  static const List<String> newsNegativeKeywords = [
    // 營收相關
    '營收衰退',
    '營收下滑',
    '獲利下滑',
    '虧損',
    '毛利率下降',
    // 訂單/產能（「庫存」改為具體化）
    '砍單',
    '減產',
    '庫存偏高',
    '庫存壓力',
    '去化壓力',
    // 市場動態
    '利空',
    '跌停',
    '調降目標價',
    '目標價下修',
    // 公司治理
    '違約',
    '掏空',
    '解任',
  ];

  // ==================================================
  // 評分與輸出
  // ==================================================

  /// 每檔股票最多理由數（資料庫儲存用，供篩選功能使用）
  ///
  /// **上限怎麼算的**（2026-08-23 修正推導）：舊註解寫「64 條規則 → 上限 64」，
  /// 但現在有 72 種 `ReasonType`。真正的上限是 **72 扣掉互斥收斂**——
  /// `RuleEngine._mutexGroups` 6 組涵蓋 16 條、每組只留 1 條，省下 11 條，
  /// 所以單股理論最大 61 條，64 仍有餘裕。
  ///
  /// ⚠️ 這個餘裕會隨規則集變動。新增規則後若 `ReasonType.values.length` 減去
  /// 互斥收斂數超過 64，`saveReasons` 的 `take()` 會**靜默截斷**——沒有錯誤、
  /// 沒有日誌，只是有些理由不見了。
  ///
  /// UI 顯示時會用 `.take(2)` / `.take(3)`（卡片 compact 佈局只顯示 1 條）。
  static const int maxReasonsPerStock = 64;

  /// 最低評分門檻
  ///
  /// 過濾掉完全沒有真實 signal rule 的股票（如僅命中 CONCENTRATION_HIGH /
  /// REVENUE_NEW_HIGH 等 demote 為 0 分的 noise filter rule）。
  ///
  /// **2026-06-19 從 25 降至 12**（搭配 audit demote）：
  /// 之前 25 預期至少 1 個強訊號 (~22) 或 2 個中等訊號 (16+18=34)。但 audit
  /// 把 CONCENTRATION_HIGH 16 + REVENUE_NEW_HIGH 22 兩條最常觸發的 rule
  /// 降至 0，原本靠 16+22=38 過閾值的 ~17 檔股票全部被 skip 寫進
  /// daily_reason，導致 user 看到 top 20 只剩 2-3 檔。
  ///
  /// 新值 12 = 任 1 條真實 signal rule（PBR_UNDERVALUED 12 / PE_UNDERVALUED 15
  /// / EPS_TURNAROUND 15 / 反轉類更高）通過。
  /// 12 是當前 hardcoded scores 中「最弱但仍 actionable」的單條訊號值。
  /// 只命中 noise rule（CONCENTRATION_HIGH / REVENUE_NEW_HIGH 等 0 分項）
  /// 的股票仍被正確過濾掉。
  static const int minScoreThreshold = 12;

  /// 觀察門檻：分數 ≥ 此值但 < [minScoreThreshold] = 「接近觸發」，進掃描頁
  /// 「觀察區」（早期預警：盯著看但訊號尚未成立）。8 ≈ 走到訊號門檻 12 的
  /// 2/3，算真的在接近；低於此值僅雜訊、不持久化。任一 horizon ≥ 此值即保留。
  static const int observationScoreThreshold = 8;

  // ==================================================
  // 流動性加權排序
  // ==================================================

  /// 成交金額單位（1 億台幣）
  ///
  /// 用於計算流動性加成時的基準單位。
  static const double liquidityTurnoverUnit = 100000000;

  /// 每單位成交金額的加成分數
  ///
  /// 每 1 億成交金額加 2 分。
  static const double liquidityBonusPerUnit = 2.0;

  /// 流動性加成上限
  ///
  /// 最多 20 分（即 10 億成交金額達上限）。
  static const double liquidityBonusMax = 20;

  // ==================================================
  // 流動性下限（候選層硬門檻，2026-07 評分改進 #4）
  // ==================================================

  /// 市場候選股的最低 20 日中位成交值（NTD）。
  ///
  /// 訊號必須可交易：薄流動性股的滑價會吃掉 ~52% 勝率的 edge。
  /// 門檻依 2026-07-11 本機 DB 實測：全市場 P50 = 1,930 萬，3,000 萬
  /// 砍掉 56% 無效運算、訊號股僅損失 7%（被砍者皆為日成交千萬級以下）；
  /// 5,000 萬會誤傷 14% 訊號股（過嚴）。**自選清單豁免**（使用者主動追蹤）。
  ///
  /// 與 [minCandidateTurnover]（`LiquidityChecker`，scoring 層**單日**同額
  /// 門檻）互補而非重複：單日檢查擋不住「殭屍股單日爆量」（處置/新聞日
  /// 衝過 3,000 萬就進訊號區）——中位數窗正是補這個洞。兩者刻意同值。
  static const double liquidityMinMedianTurnoverNtd = 30000000;

  /// 中位成交值的計算窗（交易日）。中位數而非平均：單日爆量（處置、
  /// 新聞）不應讓殭屍股短暫通過門檻。
  static const int liquidityMedianWindowDays = 20;

  /// 判定流動性所需的最少有效資料天數。不足（新上市 / 資料缺漏）視為
  /// 無法判定 → permissive 放行（無資料 ≠ 低流動性）。
  static const int liquidityMinDataDays = 10;

  // ==================================================
  // 分數分級（呈現層，2026-07 評分改進 #5）
  // ==================================================

  /// 「強」級下限。分數 76 vs 79 無統計意義（score-報酬 IC ≈ 0.17），
  /// UI 以分級呈現、數字退為輔助。邊界依 2026-07-11 本機 DB 訊號區
  /// 分佈：P75 ≈ 41 → 45 取整，「強」≈ 訊號區前 ~19%。
  static const int tierStrongThreshold = 45;

  /// 「中」級下限（P50 ≈ 28 → 25 取整）。[minScoreThreshold, 此值) 為「弱」。
  static const int tierMediumThreshold = 25;

  // ==================================================
  // 雜項
  // ==================================================

  /// 1 張 = 1000 股
  static const int sheetToShares = 1000;

  /// 新聞回溯時間（小時）
  static const int newsLookbackHours = 120;
}
