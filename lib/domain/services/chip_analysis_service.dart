import 'package:daredevil/core/constants/chip_scoring_params.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/core/constants/chip_strength.dart';

/// 籌碼強度計算服務
///
/// 依據法人進出、外資持股、融資融券、當沖比例、
/// 持股集中度、內部人持股等面向，計算 0-100 的籌碼強度分數。
class ChipAnalysisService {
  const ChipAnalysisService();

  ChipStrengthResult compute({
    required List<DailyInstitutionalEntry> institutionalHistory,
    required List<ShareholdingEntry> shareholdingHistory,
    required List<MarginTradingEntry> marginHistory,
    required List<DayTradingEntry> dayTradingHistory,
    required List<HoldingDistributionEntry> holdingDistribution,
    required List<InsiderHoldingEntry> insiderHistory,
  }) {
    // 統一在入口處排序（依日期升冪），避免各子方法重複排序
    final sortedInst = List<DailyInstitutionalEntry>.from(institutionalHistory)
      ..sort((a, b) => a.date.compareTo(b.date));
    final sortedShareholding = List<ShareholdingEntry>.from(shareholdingHistory)
      ..sort((a, b) => a.date.compareTo(b.date));
    final sortedMargin = List<MarginTradingEntry>.from(marginHistory)
      ..sort((a, b) => a.date.compareTo(b.date));
    final sortedDayTrading = List<DayTradingEntry>.from(dayTradingHistory)
      ..sort((a, b) => a.date.compareTo(b.date));
    final sortedInsider = List<InsiderHoldingEntry>.from(insiderHistory)
      ..sort((a, b) => a.date.compareTo(b.date));

    int score = 0;

    // 1. 法人連續買賣超
    final instAdj = _institutionalAdjustment(sortedInst);
    score += instAdj;

    // 2. 外資持股趨勢
    score += _shareholdingAdjustment(sortedShareholding);

    // 3. 融資融券訊號
    score += _marginAdjustment(sortedMargin);

    // 4. 當沖比例
    score += _dayTradingAdjustment(sortedDayTrading);

    // 5. 持股集中度
    score += _concentrationAdjustment(holdingDistribution);

    // 6. 內部人持股
    score += _insiderAdjustment(sortedInsider);

    score = score.clamp(0, 100);

    final attitude = _deriveAttitude(sortedInst);

    // 「已量測」= 該域資料量足以讓對應 adjustment **可能**吐出非零值。
    // isNotEmpty 不夠(2026-08-29 review 實測):一列融資湊不出 pair、
    // 一列持股沒有 diff——貢獻是**結構上保證為 0**,不是「量測結果中性」。
    // 把孤列算成已量測,兩列孤資料的上櫃稀疏股照樣渲染「偏弱 0/100」,
    // 正是這個門檻要消滅的東西。各域下限對應各自計分路徑的最低需求;
    // day/holding/insider 走 last/加總,單列即可。
    final measuredDomains = [
      institutionalHistory.length >= ChipScoringParams.instStreakSmallDays,
      shareholdingHistory.length >= 2, // 同 _shareholdingAdjustment 守衛:頭尾才有 diff
      // 連增判定需 marginStreakDays 個連續 pair → 至少 streak+1 列
      marginHistory.length >= ChipScoringParams.marginStreakDays + 1,
      dayTradingHistory.isNotEmpty,
      holdingDistribution.isNotEmpty,
      insiderHistory.isNotEmpty,
    ].where((has) => has).length;

    return ChipStrengthResult(
      score: score,
      rating: ChipRating.fromScore(score),
      attitude: attitude,
      measuredDomains: measuredDomains,
    );
  }

  // ==================================================
  // 1. 法人進出
  // ==================================================

  /// 傳入的 [history] 須已按日期升冪排序
  int _institutionalAdjustment(List<DailyInstitutionalEntry> history) {
    if (history.isEmpty) return 0;

    // 取最近 N 日（N = marginLookbackPairs，與融資融券判定窗口共用）
    const window = ChipScoringParams.marginLookbackPairs;
    final recent = history.length > window
        ? history.sublist(history.length - window)
        : history;

    int consecutiveBuy = 0;
    int consecutiveSell = 0;

    for (final entry in recent.reversed) {
      final netTotal =
          (entry.foreignNet ?? 0) + (entry.investmentTrustNet ?? 0);
      if (netTotal > 0) {
        consecutiveBuy++;
        if (consecutiveSell > 0) break;
      } else if (netTotal < 0) {
        consecutiveSell++;
        if (consecutiveBuy > 0) break;
      } else {
        break; // neutral day 中斷連續天數
      }
    }

    if (consecutiveBuy >= ChipScoringParams.instStreakLargeDays) {
      return ChipScoringParams.instBuyStreakLargeBonus;
    }
    if (consecutiveBuy >= ChipScoringParams.instStreakSmallDays) {
      return ChipScoringParams.instBuyStreakSmallBonus;
    }
    if (consecutiveSell >= ChipScoringParams.instStreakLargeDays) {
      return ChipScoringParams.instSellStreakLargePenalty;
    }
    if (consecutiveSell >= ChipScoringParams.instStreakSmallDays) {
      return ChipScoringParams.instSellStreakSmallPenalty;
    }
    return 0;
  }

  // ==================================================
  // 2. 外資持股
  // ==================================================

  /// 傳入的 [history] 須已按日期升冪排序
  int _shareholdingAdjustment(List<ShareholdingEntry> history) {
    if (history.length < 2) return 0;

    final oldest = history.first.foreignSharesRatio ?? 0;
    final latest = history.last.foreignSharesRatio ?? 0;
    final diff = latest - oldest;

    if (diff >= ChipScoringParams.foreignDiffLargePct) {
      return ChipScoringParams.foreignIncreaseLargeBonus;
    }
    if (diff >= ChipScoringParams.foreignDiffSmallPct) {
      return ChipScoringParams.foreignIncreaseSmallBonus;
    }
    if (diff <= -ChipScoringParams.foreignDiffLargePct) {
      return ChipScoringParams.foreignDecreaseLargePenalty;
    }
    if (diff <= -ChipScoringParams.foreignDiffSmallPct) {
      return ChipScoringParams.foreignDecreaseSmallPenalty;
    }
    return 0;
  }

  // ==================================================
  // 3. 融資融券
  // ==================================================

  /// 傳入的 [history] 須已按日期升冪排序
  int _marginAdjustment(List<MarginTradingEntry> history) {
    if (history.length < 2) return 0;

    // 融資餘額趨勢（持續增加 = 散戶追漲 = 偏空訊號）
    int marginIncreasingDays = 0;
    int shortIncreasingDays = 0;

    final pairCount = (history.length - 1).clamp(
      0,
      ChipScoringParams.marginLookbackPairs,
    );
    for (int i = 0; i < pairCount; i++) {
      final curr = history[history.length - 1 - i];
      final prev = history[history.length - 2 - i];
      if ((curr.marginBalance ?? 0) > (prev.marginBalance ?? 0)) {
        marginIncreasingDays++;
      }
      if ((curr.shortBalance ?? 0) > (prev.shortBalance ?? 0)) {
        shortIncreasingDays++;
      }
    }

    int adj = 0;
    // 融資餘額連續增加 = 散戶追漲 = 偏空訊號
    if (marginIncreasingDays >= ChipScoringParams.marginStreakDays) {
      adj += ChipScoringParams.marginIncreasePenalty;
    }

    // 融券方向：依券資比判斷多空意涵
    if (shortIncreasingDays >= ChipScoringParams.marginStreakDays) {
      final latest = history.last;
      final margin = latest.marginBalance ?? 0;
      final short = latest.shortBalance ?? 0;
      final shortMarginRatio = margin > 0 ? (short / margin * 100) : 0.0;

      if (shortMarginRatio > ChipScoringParams.highShortMarginRatio) {
        // 券資比高：融券高且持續增加 → 軋空潛力大
        adj += ChipScoringParams.shortIncreaseBonus;
      } else if (shortMarginRatio < ChipScoringParams.lowShortMarginRatio) {
        // 券資比低：新空單建立居多 → 偏空
        adj += ChipScoringParams.shortIncreaseLowRatioPenalty;
      } else {
        // 中等券資比：方向不明，維持小幅加分
        adj += ChipScoringParams.shortIncreaseBonus ~/ 2;
      }
    }

    return adj;
  }

  // ==================================================
  // 4. 當沖
  // ==================================================

  /// 傳入的 [history] 須已按日期升冪排序
  int _dayTradingAdjustment(List<DayTradingEntry> history) {
    if (history.isEmpty) return 0;

    final latestRatio = history.last.dayTradingRatio ?? 0;

    // 當沖比例過高 = 投機性強 = 偏空
    if (latestRatio >= ChipScoringParams.dayTradingHighThresholdPct) {
      return ChipScoringParams.dayTradingHighPenalty;
    }
    return 0;
  }

  // ==================================================
  // 5. 持股集中度
  // ==================================================

  int _concentrationAdjustment(List<HoldingDistributionEntry> entries) {
    if (entries.isEmpty) return 0;

    // 大戶持股佔比加總
    double largeHolderPercent = 0;
    for (final entry in entries) {
      // 解析級距："1000以上" 或 "800-999" 等
      final level = entry.level;
      if (_isLargeHolder(level)) {
        largeHolderPercent += entry.percent ?? 0;
      }
    }

    if (largeHolderPercent >= ChipScoringParams.concentrationHighThresholdPct) {
      return ChipScoringParams.concentrationHighBonus;
    }
    if (largeHolderPercent >=
        ChipScoringParams.concentrationMediumThresholdPct) {
      return ChipScoringParams.concentrationMediumBonus;
    }
    return 0;
  }

  static final _levelRegExp = RegExp(r'(\d+)');

  bool _isLargeHolder(String level) {
    // 台灣持股分級中的大戶級距：400-600、600-800、800-1,000、1,000以上
    if (level.contains('以上')) return true;
    // 嘗試解析第一個數字
    final match = _levelRegExp.firstMatch(level.replaceAll(',', ''));
    if (match != null) {
      final num = int.tryParse(match.group(1)!) ?? 0;
      return num >= ChipScoringParams.largeHolderMinLot;
    }
    return false;
  }

  // ==================================================
  // 6. 內部人持股
  // ==================================================

  /// 傳入的 [history] 須已按日期升冪排序
  int _insiderAdjustment(List<InsiderHoldingEntry> history) {
    if (history.isEmpty) return 0;

    final latest = history.last;

    int adj = 0;

    // 質押比警示
    final pledge = latest.pledgeRatio ?? 0;
    if (pledge >= ChipScoringParams.pledgeHighThresholdPct) {
      adj += ChipScoringParams.insiderPledgePenalty;
    }

    // 持股變動
    final change = latest.sharesChange ?? 0;
    if (change > 0) {
      adj += ChipScoringParams.insiderBuyBonus; // 內部人買進
    } else if (change < 0) {
      adj += ChipScoringParams.insiderSellPenalty; // 內部人賣出
    }

    return adj;
  }

  // ==================================================
  // 法人態度判定
  // ==================================================

  /// 傳入的 [history] 須已按日期升冪排序
  InstitutionalAttitude _deriveAttitude(List<DailyInstitutionalEntry> history) {
    if (history.isEmpty) return InstitutionalAttitude.neutral;

    final recent = history.length > 5
        ? history.sublist(history.length - 5)
        : history;

    double totalNet = 0;
    int buyDays = 0;
    int sellDays = 0;

    for (final entry in recent) {
      final net = (entry.foreignNet ?? 0) + (entry.investmentTrustNet ?? 0);
      totalNet += net;
      if (net > 0) buyDays++;
      if (net < 0) sellDays++;
    }

    if (buyDays >= 4 && totalNet > 0) {
      return InstitutionalAttitude.aggressiveBuy;
    }
    if (buyDays >= 3 && totalNet > 0) return InstitutionalAttitude.moderateBuy;
    if (sellDays >= 4 && totalNet < 0) {
      return InstitutionalAttitude.aggressiveSell;
    }
    if (sellDays >= 3 && totalNet < 0) {
      return InstitutionalAttitude.moderateSell;
    }
    return InstitutionalAttitude.neutral;
  }
}
