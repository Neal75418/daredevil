/// 籌碼分析參數配置
///
/// 提取自 [ChipAnalysisService] 以便於調整策略權重。
///
/// 基底分為 [baselineScore]（50），各項信號累加後 clamp(0, 100)。
/// 正面信號合計最大約 +95、負面約 −90，兩側在 clamp 邊界附近才飽和。
class ChipScoringParams {
  ChipScoringParams._();

  /// 基底分——六個調整項是有正負號的雙向訊號,必須從中點起算。
  ///
  /// 從 0 起算再 clamp(0,100) 等於砍掉負半軸:「法人連賣的極弱股」與
  /// 「毫無訊號的中性股」都被壓成 0 分、同一顆「極弱」徽章
  /// (2026-08-29 review)。50 為中點:正面訊號合計最大約 +95、負面約
  /// −90,兩側在 clamp 邊界附近才飽和。
  static const int baselineScore = 50;

  // ==================================================
  // 1. Institutional (三大法人)
  // ==================================================

  /// 法人連續買賣「大門檻」天數
  static const int instStreakLargeDays = 4;

  /// 法人連續買賣「小門檻」天數
  static const int instStreakSmallDays = 2;

  /// 法人連買 >= [instStreakLargeDays] 加分
  static const int instBuyStreakLargeBonus = 30;

  /// 法人連買 >= [instStreakSmallDays] 加分
  static const int instBuyStreakSmallBonus = 15;

  /// 法人連賣 >= [instStreakLargeDays] 扣分
  static const int instSellStreakLargePenalty = -25;

  /// 法人連賣 >= [instStreakSmallDays] 扣分
  static const int instSellStreakSmallPenalty = -12;

  // ==================================================
  // 2. Foreign Shareholding (外資持股)
  // ==================================================

  /// 外資持股比變動「大門檻」百分比（正向為增、負向為減）
  static const double foreignDiffLargePct = 0.5;

  /// 外資持股比變動「小門檻」百分比（正向為增、負向為減）
  static const double foreignDiffSmallPct = 0.2;

  /// 外資持股比增加 >= [foreignDiffLargePct] 加分
  static const int foreignIncreaseLargeBonus = 25;

  /// 外資持股比增加 >= [foreignDiffSmallPct] 加分
  static const int foreignIncreaseSmallBonus = 12;

  /// 外資持股比減少 <= -[foreignDiffLargePct] 扣分
  static const int foreignDecreaseLargePenalty = -15;

  /// 外資持股比減少 <= -[foreignDiffSmallPct] 扣分
  static const int foreignDecreaseSmallPenalty = -8;

  // ==================================================
  // 3. Margin Trading (信用交易)
  // ==================================================

  /// 融資/融券判定回溯天數（最多比對最近 5 個 pair）
  static const int marginLookbackPairs = 5;

  /// 融資/融券連增判定天數（連續 >= 此值觸發加/扣分）
  static const int marginStreakDays = 4;

  /// 融資連增 >= [marginStreakDays] 扣分 (散戶追高)
  static const int marginIncreasePenalty = -12;

  /// 融券連增 >= [marginStreakDays] 加分 (軋空潛力)
  static const int shortIncreaseBonus = 8;

  /// 券資比高於此值視為軋空潛力大 (%)
  static const double highShortMarginRatio = 30.0;

  /// 券資比低於此值視為新空單建立 (%)
  static const double lowShortMarginRatio = 10.0;

  /// 低券資比下融券連增的扣分
  static const int shortIncreaseLowRatioPenalty = -3;

  // ==================================================
  // 4. Day Trading (當沖)
  // ==================================================

  /// 當沖率高門檻（%）— **2026-07-18 由 35.0 改為 60.0**
  ///
  /// ### 定位：波動/投機旗標，**不是報酬預測指標**
  /// 高當沖率代表籌碼換手快、隔日波動大、參與者以短線投機為主。
  /// TWSE 將「當沖比率明顯過高」列為**注意交易資訊**異常標準（風險揭露），
  /// 而非報酬指標；自有資料亦顯示它對次日報酬無穩健預測力
  /// （效應在 29 天樣本前半／後半符號反轉、控制成交值後係數砍半）。
  /// 故此扣分應解讀為「**投機性偏高、波動風險**」，不宣稱「會跌」。
  ///
  /// ### 為何 35% 站不住腳
  /// 35% 是**市場平均**，且在規則實際評估的流動股池裡正好是**中位數（p52）**、
  /// 全樣本 p76.2 —— 觸發率 **23.83%**，等於每 4 個股票日就扣 1 次。
  /// 把中位數叫「過熱」在語意上站不住腳，也稀釋了警示的意義。
  ///
  /// ### 60% 的依據：與監管同基準、同數值
  /// TWSE《公布或通知注意交易資訊暨處置作業要點》第 4 條異常標準：
  /// 「當日沖銷**成交量**占**總成交量**比率」連續 6 營業日平均 > 60%
  /// 且前一營業日亦 > 60% → 列注意股。
  ///
  /// **分母基準已核對一致（此為採用 60 這個數字的前提）**：
  /// 本 app 的 `day_trading.day_trading_ratio` 由
  /// `TradingRepository` 以 `當沖成交股數 / 當日總成交股數 × 100` 計算
  /// （TWTB4U 第 4 欄「當沖成交股數」÷ `daily_price.volume`），
  /// 即**成交量（股數）基準**，與上述監管定義同一基準，故 60% 可直接套用、
  /// 無需換算。
  ///
  /// 補充實證（production DB 32,097 筆、2026-06-05 ~ 07-17）：
  /// 個股層級的**股數基準與成交值基準幾乎相同**
  /// （p50 23.63 vs 23.67、p90 45.45 vs 45.57、p99 63.15 vs 63.86），
  /// 因為同一檔股票當日的當沖均價 ≈ 全體成交均價。
  /// 常見的「市場當沖比重約 37%」是**全市場加總**口徑（本資料為
  /// 股數 36.59% / 成交值 39.70%），與**個股中位數 23%** 的差異來自
  /// 「等權中位數 vs 成交量加權加總」，**不是基準差異**。
  ///
  /// 60% 在本資料為 p98.4、觸發率 **1.64%** —— 稀有且名副其實。
  ///
  /// ### 未採用監管的流動性除外條件（有意識的取捨）
  /// 監管另排除：週轉率 ≤ 5%、成交金額 ≤ 5 億、當沖量 ≤ 5,000 張、ETF、
  /// 無漲跌幅限制之初上市股。本處**不實作**，理由：
  /// 1. 除「當沖量」外，其餘三項所需資料（發行股數／收盤價／證券類型）
  ///    都不在 [DayTradingEntry] 內，需為了一個**顯示用**分項調整
  ///    跨表拉資料進 [ChipAnalysisService]，成本與收益不成比例；
  /// 2. 監管的除外條件是為了「限制交易」（處置股禁當沖）這種有實質經濟
  ///    後果的處分做比例原則調整；此處僅是籌碼分數 −8 的顯示性調整；
  /// 3. 已量測影響面：≥60% 的 526 筆中有 180 筆（**34.2%**）當沖量
  ///    < 5,000 張。若日後要收斂誤報，這是**第一個**該加的條件
  ///    （`tradeVolume` 已在手、0 筆 null），但應連同 rule engine 的
  ///    [RuleParams.minDayTradingVolumeShares] 一併對齊 —— 目前規則引擎
  ///    有 1 萬張下限、本籌碼路徑沒有，兩者本就不一致。
  static const double dayTradingHighThresholdPct = 60.0;

  /// 當沖率 >= [dayTradingHighThresholdPct] 扣分（投機/波動風險揭露）
  static const int dayTradingHighPenalty = -8;

  // ==================================================
  // 5. Holding Concentration (股權分散)
  // ==================================================

  /// 大戶持股集中度高門檻（%）
  static const double concentrationHighThresholdPct = 60.0;

  /// 大戶持股集中度中門檻（%）
  static const double concentrationMediumThresholdPct = 40.0;

  /// 大戶判定最低張數（張）— 400 張以上視為大戶
  static const int largeHolderMinLot = 400;

  /// 大戶持股比例 >= concentrationHighThresholdPct 加分
  static const int concentrationHighBonus = 20;

  /// 大戶持股比例 >= concentrationMediumThresholdPct 加分
  static const int concentrationMediumBonus = 8;

  // ==================================================
  // 6. Insider Holding (內部人)
  // ==================================================

  /// 質押比高門檻（%）— 超過此比例視為高質押風險
  static const double pledgeHighThresholdPct = 30.0;

  /// 質押比 >= pledgeHighThresholdPct 扣分
  static const int insiderPledgePenalty = -15;

  /// 內部人增持加分
  static const int insiderBuyBonus = 12;

  /// 內部人減持扣分
  static const int insiderSellPenalty = -12;
}

/// 籌碼異動偵測參數
///
/// 集中管理 [ChipAnomalyService] 使用的篩選門檻與回溯天數。
class ChipAnomalyParams {
  ChipAnomalyParams._();

  /// 每種異動類型最多回傳筆數（避免大量結果淹沒 dashboard）
  static const int maxResultsPerType = 5;

  /// 內部人轉讓：回溯天數
  static const int insiderTransferLookbackDays = 30;

  /// 融券暴增：回溯天數
  static const int shortSurgeLookbackDays = 15;

  /// 融券暴增：當日融券賣出超過近期均量的倍率門檻
  static const double shortSurgeMultiplier = 3.0;

  /// 融券暴增：當日融券賣出絕對量下限（張）
  ///
  /// 純倍率門檻在近零基期會放大成假訊號（如當日 229 張 / 5 日均 0.333 張
  /// = 687 倍）。要求當日量達此下限才納入，過濾低量雜訊。
  static const double shortSurgeMinTodayLots = 50.0;

  /// 融券暴增：近 5 日均融券賣出絕對量下限（張）
  ///
  /// 與 [shortSurgeMinTodayLots] 搭配，要求均量基期達此下限才參與倍率比較，
  /// 避免極小基期（< 1 張）使倍率失真。
  static const double shortSurgeMinAvgLots = 10.0;

  /// 融券暴增：高量豁免的當日量下限（張）
  ///
  /// 「冷基期突發建空」（如某檔平時 4-7 張、今日突放 100+ 張）是最早期的軋空
  /// 前兆，但會被 [shortSurgeMinAvgLots]=10 的均量地板誤殺。故開高量豁免：當日
  /// 量達此下限時，均量地板放寬到 [shortSurgeHighVolMinAvgLots]，救回這類真訊號。
  static const double shortSurgeHighVolTodayLots = 100.0;

  /// 融券暴增：高量豁免時的均量下限（張）
  ///
  /// 高量豁免（當日 ≥ [shortSurgeHighVolTodayLots]）放寬的均量地板。仍須 ≥ 3 張
  /// 以排除近零基期爆值（如 3528 均 0.333 張的 687 倍噪音）。亦作為 avg5d 的
  /// HAVING 預過濾門檻（兩條路徑中最低的均量要求）。
  static const double shortSurgeHighVolMinAvgLots = 3.0;

  /// 法人集中大買/賣：回溯天數
  static const int institutionalSurgeLookbackDays = 60;

  /// 法人集中大買/賣：當日淨額超過近期均值的倍率門檻
  static const double institutionalSurgeMultiplier = 5.0;

  /// 機會型訊號（法人集中、融券暴增）排除「近期處置」股的回溯天數
  ///
  /// 處置/全額交割股的法人大賣、融券暴增多為 distress 症狀而非可操作訊號，
  /// 且會佔用 [maxResultsPerType] 席位擠掉真訊號。近此天數內有 DISPOSAL 警示者
  /// 從機會型類別排除（風險型「高質押」不排除）。
  static const int disposalExclusionLookbackDays = 30;
}
