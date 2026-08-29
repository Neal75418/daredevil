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
/// - 同一檔的 `RSI_EXTREME_OVERSOLD {"rsi":17.4}` 連續 **12 個交易日**發出
///   +10 的買進理由；以斷點後的資料重算 RSI 約在 60。
///
/// 🚧 **本工具目前未接進評分鏈——等一個設計決策**（2026-08-29）
///
/// 原本要接在 `batch_data_loader` 組 `pricesMap` 的單一入口（兩條評分路徑
/// 都經過那裡）。實測後撤回：截斷會讓 165 檔（7.7%）掉列、其中 **17 檔剩
/// 不到 20 列**，而 `classifyCandidate` 對這種長度回 `insufficientData` 並
/// 在自選股補列**之前**就 `continue`——那正是「自選股空白卡」，是先前已經
/// 明確修掉的症狀。5283 禾聯碩 8/28 除息 −15.1% 後只剩 1 列，會空白約一個月。
///
/// 三種設計，成本各不同：
///   (a) 本檔的截斷——最簡單、最誠實，但會重現空白卡
///   (b) 標記斷點、讓**跨越它的長窗指標**回 null（MA60 null 但 MA5 照算、
///       `daily_analysis` 列照寫、不空白）——沒有空白卡，但要改動多個指標函式
///   (c) 用 DB 裡既有的股利資料真正還原價格——最正確，工程量最大
///
/// **為什麼截斷優於「完整還原」的第一直覺**：完整還原需要一份完整、可信的
/// 公司行動資料源，錯了會靜默污染整段歷史；截斷則讓 MA60 變成 **null**，而
/// null 是誠實的、錯的數字不是。專案各處早已處理得了 null 指標。
/// 但上面那個空白卡的代價使 (a) 不能單獨成立。
///
/// **門檻不是發明的**：台股日漲跌幅上限 ±10%，跳動單位四捨五入使實測分布
/// 延伸到約 11%，之後出現斷崖——本機 DB 九年資料實測：
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
/// 之後。全庫 ≥12% 的移動共 189 筆、涉及 165 檔（其中 8 檔是無漲跌幅限制的
/// 國外連結 ETF，屬已知的 5% 誤判面）。
extension PriceContinuity on List<DailyPriceEntry> {
  /// 回傳**最後一個水位斷點之後**的連續區段（含斷點後的第一根）。
  ///
  /// 沒有斷點時回傳自身。比較的是相鄰的兩個**有效收盤**（跳過停牌列），
  /// 所以停牌本身不會被誤判為斷點——實測 95 筆永久水位位移裡只有 47%
  /// 伴隨停牌，靠缺口偵測抓不到另外一半（除權息不停牌）。
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
