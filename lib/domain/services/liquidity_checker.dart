import 'package:daredevil/core/constants/rule_params.dart';
import 'package:daredevil/data/database/app_database.dart';

/// 流動性檢查工具 - 統一候選股票的流動性過濾邏輯
///
/// **只看成交額，不看股數**（2026-08-29 領域稽核）：曾另有一道
/// `volume >= 1,000,000 股` 的門檻，與成交額門檻同時要求等於對股價 p 的
/// 股票要求 `量 ≥ max(100萬, 3000萬/p)`——p 超過 30 元之後綁定的永遠是股數
/// 那條，於是實際成交額門檻變成 `p × 100 萬`（15,630 元的信驊要 156 億）。
/// 同一個流動性概念，門檻在不同價位差 500 倍。
///
/// 實測它擋掉 68.9% 的 stock-day，其中 25.7% 已通過成交額門檻；而通過
/// 成交額的 236,105 筆裡最小成交量是 33,000 股，任何合理的股數地板都會
/// 擋掉 0 筆——所以整條移除而不是調低。
///
/// ⚠️ 同口徑的第二個履行點是 `MarketOverviewDaoMixin.getTradeableUniverseCount`
/// （掃描頁的「自 N 檔可交易股篩出」分母），兩處必須一起改。
abstract final class LiquidityChecker {
  /// 檢查股票是否滿足候選流動性要求
  ///
  /// 回傳 null 表示通過檢查，回傳 String 表示失敗原因
  static String? checkCandidateLiquidity(DailyPriceEntry latest) {
    if (latest.close == null || latest.volume == null) {
      return 'MISSING_DATA';
    }
    final turnover = latest.close! * latest.volume!;
    if (turnover < RuleParams.minCandidateTurnover) {
      return 'LOW_TURNOVER';
    }
    return null;
  }
}
