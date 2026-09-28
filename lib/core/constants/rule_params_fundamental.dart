/// 基本面分析參數（營收 / EPS / ROE / 估值 / 董監持股 / 警示）
abstract final class FundamentalParams {
  // ==================================================
  // 營收
  // ==================================================

  /// 營收年增率暴增門檻（%）
  ///
  /// 30% 在品質與數量間取得平衡。
  static const double revenueYoySurgeThreshold = 30.0;

  /// 營收年減率衰退門檻（%）
  static const double revenueYoyDeclineThreshold = 20.0;

  /// 營收月增連續成長月數
  ///
  /// 設為 1 以偵測單月暴增。
  static const int revenueMomConsecutiveMonths = 1;

  /// 營收月增率門檻（%）
  ///
  /// 10% 視為有意義的成長。
  static const double revenueMomGrowthThreshold = 10.0;

  // ==================================================
  // 估值（PE / PBR / 殖利率）
  // ==================================================

  /// 高殖利率門檻（%）
  ///
  /// 台股平均 4-6%，5.5% 可篩選出真正高殖利率股。
  static const double highDividendYieldThreshold = 5.5;

  /// 本益比低估門檻
  ///
  /// 本益比低於此值（且 > 0）視為低估。
  static const double peUndervaluedThreshold = 10.0;

  /// 本益比高估門檻
  ///
  /// 60 以聚焦泡沫區域。
  static const double peOvervaluedThreshold = 60.0;

  /// 股價淨值比低估門檻
  ///
  /// 股價淨值比低於 0.8 代表有意義的折價。
  static const double pbrUndervaluedThreshold = 0.8;

  /// 估值資料最大過期天數
  ///
  /// TWSE 並非每日更新所有股票的估值資料，超過此天數的資料視為過時。
  /// 7 天確保資料在合理時效內，避免用舊資料觸發規則。
  static const int valuationMaxStaleDays = 7;

  // ==================================================
  // Killer Features（董監持股 / 注意處置股）
  // ==================================================

  /// 董監連續減持月數門檻
  ///
  /// 連續 3 個月以上減持視為強賣訊號。
  static const int insiderSellingStreakMonths = 3;

  /// 董監顯著增持門檻（%）
  ///
  /// 單月持股比例增加 5% 以上視為買進訊號。
  static const double insiderSignificantBuyingThreshold = 5.0;

  /// 高質押比例門檻（%）— v1 正式值（2026-07-15 定案，非 placeholder）
  ///
  /// 70% 是經驗法則的高風險邊界（家族企業常態高質押多在 30-50%、地雷股
  /// 事發時質押比通常 80%+）。50% 是 TWSE 法規分界（質押比 ≥ 1/2 不計入
  /// 董事改選選舉權），不是統計顯著的轉折點，誤觸發太多；70 同時避免
  /// 富邦金、國泰金等家族長期高質押被當風險訊號。
  ///
  /// backtest 校準目前**不可行**：pledge_ratio 快照僅自 2026-03 起、
  /// 6 個時間點，不足以做門檻掃描 × forward returns。累積約一年後併入
  /// calibration batch 重驗（屆時同時釐清 neutral 警訊的 -18 分是否
  /// 參與計分，再決定調整或砍 rule）。
  ///
  /// ⚠️ 消費者不只 rule 一處：[HighPledgeRatioRule]（風險警示徽章，
  /// ScoringMode.neutral）、ChipAnomalyService 質押飆升警示、
  /// InsiderRepository 的高質押判定（供自選清單警示）、個股詳情頁兩處
  /// UI 指標等——調整前先 `grep -rn highPledgeRatioThreshold lib/`
  /// 盤點全部呼叫點，別依賴此清單（會過期）。
  static const double highPledgeRatioThreshold = 70.0;

  /// 高質押「變動觸發」判定的最小增幅（百分點，pp）
  ///
  /// 僅供 [ChipAnomalyService] 市場層級「今日異常」feed 判斷是否為**新**高
  /// 質押事件：前次快照 < [highPledgeRatioThreshold] 且最新 >= 門檻（跨門檻），
  /// 或兩次快照皆 >= 門檻但漲幅 >= 此值（持續惡化），才計入當日異常，避免
  /// 同一檔股票天天佔用「今日偵測到 N 項異常」名額造成警示疲勞。該股無前次
  /// 快照（僅 1 筆歷史）一律不計入，避免首次同步大量歷史資料時洗版。
  ///
  /// 個股層級的持續性風險顯示（[HighPledgeRatioRule] 徽章、
  /// `InsiderRepository` 的自選清單警示、股票詳情頁 UI 指標）不受本常數
  /// 影響，仍持續顯示——市場層級 feed 收斂為「新事件」，不代表風險消失。
  static const double kPledgeAlertDeltaPp = 5.0;

  /// 處置股結束日期寬限天數
  ///
  /// 判斷處置股是否仍生效時，在結束日期後加上此天數作為緩衝。
  /// 1 天確保結束當日仍視為生效狀態。
  static const int disposalEndDateGraceDays = 1;

  /// NULL endDate 的處置股最長保留天數
  ///
  /// endDate 解析失敗（TWSE 改格式/欄位位移/民國日期異常）會讓該欄為 null，
  /// 而 `disposal_end_date < now` 在 SQL 三值邏輯下對 NULL 恆不成立 →
  /// **-50 分 + 三模式硬排除永久生效**。台股處置期最長約 12 個交易日，
  /// 取 30 個日曆天為保守上界：真的還在處置中就保留、解析失敗則有限期自癒。
  static const int disposalNullEndDateMaxDays = 30;

  /// 外資持股集中度警示門檻（%）
  ///
  /// 外資持股超過 60% 且快速增加時觸發風險警示。
  static const double foreignConcentrationWarningThreshold = 60.0;

  /// 外資持股集中度危險門檻（%）
  ///
  /// 外資持股超過 70% 視為高度集中風險。
  static const double foreignConcentrationDangerThreshold = 70.0;

  /// 外資流出天數
  ///
  /// 追蹤連續 N 天的外資流出趨勢。
  static const int foreignExodusLookbackDays = 5;

  /// 外資流出門檻（%）
  ///
  /// N 天內外資持股減少超過此比例視為流出警示。
  static const double foreignExodusThreshold = -2.0;

  // ==================================================
  // EPS
  // ==================================================

  /// EPS 年增暴增門檻（%）
  static const double epsYoYSurgeThreshold = 50.0;

  /// EPS 季增成長門檻（%）
  static const double epsGrowthThreshold = 10.0;

  /// EPS 連續成長最少季數
  static const int epsConsecutiveQuarters = 2;

  /// EPS 由負轉正最低門檻（元）
  static const double epsTurnaroundThreshold = 0.3;

  /// EPS 衰退警示門檻（%）
  static const double epsDeclineThreshold = 20.0;

  // ==================================================
  // ROE
  // ==================================================

  /// ROE 優異門檻（%）
  static const double roeExcellentThreshold = 15.0;

  /// ROE 改善門檻（百分點）
  static const double roeImprovingThreshold = 5.0;

  /// ROE 衰退門檻（百分點）
  static const double roeDecliningThreshold = 5.0;

  /// ROE 趨勢最少季數
  static const int roeMinQuarters = 2;

  // ==================================================
  // 掃描規則專用
  // ==================================================

  /// 掃描用殖利率最低門檻（%）
  ///
  /// 低於此值不觸發殖利率相關診斷日誌。
  static const double scanDividendYieldMin = 4.0;

  /// 異常殖利率過濾上限（%）
  ///
  /// 超過此值通常為資料錯誤或特殊情況。
  static const double scanDividendYieldMax = 20.0;

  /// PE 高估確認 RSI 門檻
  static const double scanRsiOverboughtThreshold = 75.0;

  /// 動能確認 RSI 門檻（EPS 轉機搭配 RSI 正向確認）
  static const double scanRsiMomentumThreshold = 50.0;

  /// EPS 年度回溯筆數（找去年同季需要的最少歷史資料）
  static const int epsYearLookback = 5;

  /// EPS 同期季度偏移（降序排列下去年同季的起始 index）
  static const int epsQuarterOffset = 4;
}
