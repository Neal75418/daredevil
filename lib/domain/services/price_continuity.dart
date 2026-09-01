import 'package:daredevil/core/constants/rule_params.dart';
import 'package:daredevil/data/database/app_database.dart';

/// 價格序列的**水位斷點**偵測（2026-08-29 領域稽核 C3）
///
/// 本專案的 `daily_price` 存的是交易所原始收盤價，**未還原除權息／減資／
/// 分割**。於是同一個 symbol 的序列可能包含一個永久性的水位位移，而跨越它
/// 的長窗指標會產出物理上不可能的數字：
///
/// - 5904 寶雅 2026-07-29 收 720.0 → 2026-08-10 收 79.2（約 9.1 倍，中間停牌
///   12 個日曆天）。其 `daily_reason` 在 2026-08-27 存著
///   `MA_ALIGNMENT_BEARISH {"ma20":253.84,"ma60":506.18}`——而當天股價是 74.10。
/// - 同一檔在 8/10–8/28 的 15 個交易日裡有 **12 天**發出
///   `RSI_EXTREME_OVERSOLD {"rsi":17.4}`（+10 的買進理由；跳過 8/19、8/21、
///   8/26，不是連續）；以斷點後的資料重算 RSI 約在 60。
///
/// **套在 `AnalysisCoordinatorService.calculateTechnicalIndicators` 內**——
/// 刻意**不**放在價格入口（`batch_data_loader`）。
///
/// 入口截斷曾實作過又撤回（2026-08-30）：它會讓 `prices.length` 本身變短，
/// 踩到下游一連串**長度**閘。實測 165 檔被截斷者中：
///
/// | 掉到 | 檔數 | 後果 |
/// |:--|--:|:--|
/// | < 21 根 | 17 | 連 `daily_analysis` 列都不寫（自選股空白卡） |
/// | < 60 根 | 52 | 整個 indicator 區塊 null（`buildContext` 的閘門） |
/// | < 250 根 | **142** | **52 週規則永不觸發** |
///
/// 最後一項是決定性的：52 週規則**本來就正確處理除息**
/// （`_sumDividendsInPeriod` 把窗內現金股利從極值扣掉，見 evidence 的
/// `adjustedHigh`/`dividendAdjustment`）——入口截斷等於用一個粗糙的工具
/// 破壞一條已經解好的規則。
///
/// 套在指標層則外層閘門仍看完整歷史，只有指標值改用斷點後的序列。分桶會隨
/// 時間漂移（斷點後的根數天天增加），重算方式見本檔的 `contiguousSuffix`；
/// 2026-09-01 口徑：166 檔有斷點，其中 35 檔只失去 MA60、3 檔連 MA20 都算不
/// 出、14 檔（斷點後不足 RSI 窗 16 根）整組為 null。
/// **52 週規則與 `daily_analysis` 列全部不受影響。**
///
/// ✅ **生產驗證（2026-08-31、09-01 兩個交易日）**：
/// - 5904（斷點後 17 根）：8/27 舊碼發出
///   `MA_ALIGNMENT_BEARISH {"ma20":253.84,"ma60":506.18}` 與
///   `RSI_EXTREME_OVERSOLD {"rsi":17.43}`；新碼下**兩條都不再出現**，
///   只剩不依賴長窗均線的 `WEEK_52_LOW`／`CONCENTRATION_HIGH` 等。
/// - 2603（斷點後 53 根）：仍正常發出依賴 **MA20** 的
///   `PE_UNDERVALUED {"ma20":228.4}`，而依賴 MA60 的規則不觸發——
///   正是這個定位要的結果（入口截斷會連 MA20 與 52 週一起拿走）。
///
/// ⚠️ 殘留：`analyzeStock` 的趨勢迴歸與支撐壓力仍用完整歷史（截斷它會讓短
/// 序列連分析列都不寫）。受影響的是「斷點落在最近 20 根內」的 17 檔。
///
/// **門檻不是發明的**：台股日漲跌幅上限 ±10%，跳動單位四捨五入使實測分布
/// 延伸到約 11%，之後出現斷崖——本機 DB（2025-06-10～2026-08-28，300 個
/// 交易日）實測：
///
/// | 區間 | 筆數 |
/// |:--|--:|
/// | 9–10% | 15,259 |
/// | 10–11% | 1,298 |
/// | **11–12%** | **62** |
/// | 12–15% | 82 |
/// | >15% | 107 |
///
/// 1,298 → 62 是 20 倍的落差，[RuleParams.priceDiscontinuityRatio] 取在斷崖
/// 之後。全庫 ≥12% 的移動共 189 筆、涉及 165 檔，其中 8 檔是 `00` 開頭的
/// ETF——但**不是全部都算誤判**：0052 富邦科技是國內 ETF、有 ±10% 限制，
/// 它 2025-11-18 的 245.30 → 35.35 是約 1:7 的分割，正是本工具該抓的真實
/// 公司行動。真正的誤判面是無漲跌幅限制的國外連結 ETF，少於 8 檔。
extension PriceContinuity on List<DailyPriceEntry> {
  /// 回傳**最後一個水位斷點之後**的連續區段（含斷點後的第一根）。
  ///
  /// 沒有斷點時回傳自身。比較的是相鄰的兩個**有效收盤**（跳過停牌列），
  /// 所以停牌本身不會被誤判為斷點。
  ///
  /// **為什麼不能改用缺口偵測**：在本門檻（>12%）下實測 176 筆永久水位位移，
  /// 只有 **35%** 中間有交易日缺席——近三分之二的位移（除權息、除權）當天
  /// 照常交易。（把門檻放寬到 >15% 是 95 筆 / 47%，比例較高但仍不到一半。）
  List<DailyPriceEntry> contiguousSuffix() {
    // 由新到舊找最近的斷點：只要找到一個就可以停，更舊的不影響結果。
    double? nextClose;
    var nextValidIndex = -1;
    for (var i = length - 1; i >= 0; i--) {
      final close = this[i].close;
      if (close == null || close <= 0) continue;
      if (nextClose != null) {
        final ratio = (nextClose / close - 1).abs();
        if (ratio > RuleParams.priceDiscontinuityRatio) {
          // 從**新水位的第一根有效列**起算，而不是舊水位那根的下一列
          // ——斷點跨停牌時，中間那幾根 null 屬於舊水位那一側。
          return sublist(nextValidIndex);
        }
      }
      nextClose = close;
      nextValidIndex = i;
    }
    return this;
  }
}
