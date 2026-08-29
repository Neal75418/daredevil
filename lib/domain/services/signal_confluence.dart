import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/domain/models/signal_names.dart';

/// 訊號匯流模式定義
///
/// 當多個相關訊號同時觸發時，合成為一個更有洞察力的結論，
/// 而非獨立列出每條訊號。
class SignalConfluence {
  const SignalConfluence({
    required this.signalGroups,
    required this.summaryKey,
  });

  /// 訊號群組：每個群組中至少須匹配一個 reasonType
  ///
  /// 所有群組都必須被滿足，才算匹配此匯流模式。
  /// 例如 `[{'TECH_BREAKOUT'}, {'VOLUME_SPIKE'}]`
  /// 表示需要同時有突破 + 量能放大。
  final List<Set<String>> signalGroups;

  /// 匯流摘要的 localization key
  final String summaryKey;

  /// 檢查此模式是否被觸發
  ///
  /// 回傳匹配的 reasonType 集合（用於消耗已匹配的訊號），
  /// 若未匹配則回傳 null。
  Set<String>? match(Set<String> activeTypes) {
    final matched = <String>{};
    for (final group in signalGroups) {
      final hit = group.intersection(activeTypes);
      if (hit.isEmpty) return null; // 此群組無匹配 → 整體不匹配
      matched.addAll(hit);
    }
    return matched;
  }
}

/// 匯流偵測結果
class ConfluenceResult {
  const ConfluenceResult({
    required this.summaryKeys,
    required this.consumedTypes,
    required this.matchedCount,
  }) : assert(matchedCount == summaryKeys.length);

  /// 匯流摘要的 localization key 列表（由 presentation 層負責翻譯）
  final List<String> summaryKeys;

  /// 被匯流模式消耗的 reasonType 集合
  final Set<String> consumedTypes;

  /// 匹配到的匯流模式數量
  final int matchedCount;
}

/// 訊號匯流偵測器
class SignalConfluenceDetector {
  const SignalConfluenceDetector();

  /// 偵測匯流模式
  ///
  /// [reasons] 觸發的規則列表
  /// [bullish] true = 只偵測多頭模式，false = 只偵測空頭模式
  ConfluenceResult detect(
    List<DailyReasonEntry> reasons, {
    required bool bullish,
  }) {
    final activeTypes = reasons.map((r) => r.reasonType).toSet();
    final keys = <String>[];
    final consumed = <String>{};

    final patterns = bullish ? _bullishPatterns : _bearishPatterns;

    for (final pattern in patterns) {
      final remaining = activeTypes.difference(consumed);
      final matched = pattern.match(remaining);
      if (matched != null) {
        keys.add(pattern.summaryKey);
        consumed.addAll(matched);
      }
    }

    return ConfluenceResult(
      summaryKeys: keys,
      consumedTypes: consumed,
      matchedCount: keys.length,
    );
  }

  // ==================================================
  // 多頭匯流模式
  // ==================================================

  static const _bullishPatterns = [
    // 量價齊揚：突破 + 量能放大
    SignalConfluence(
      signalGroups: [
        {SignalName.techBreakout, SignalName.highVolumeBreakout},
        {SignalName.volumeSpike},
      ],
      summaryKey: 'summary.confluenceVolumeBreakout',
    ),

    // 法人認同：法人買超 + 技術面轉強
    SignalConfluence(
      signalGroups: [
        {SignalName.institutionalBuy, SignalName.institutionalBuyStreak},
        {
          SignalName.techBreakout,
          SignalName.reversalW2S,
          SignalName.maAlignmentBullish,
        },
      ],
      summaryKey: 'summary.confluenceInstitutional',
    ),

    // 底部反轉：弱轉強 + KD 黃金交叉
    SignalConfluence(
      signalGroups: [
        {SignalName.reversalW2S},
        {
          SignalName.kdGoldenCross,
          SignalName.patternHammer,
          SignalName.patternMorningStar,
          SignalName.rsiExtremeOversold,
        },
      ],
      summaryKey: 'summary.confluenceBottomReversal',
    ),

    // 基本面+技術面共振
    SignalConfluence(
      signalGroups: [
        {
          SignalName.revenueYoySurge,
          SignalName.epsYoySurge,
          SignalName.epsConsecutiveGrowth,
        },
        {
          SignalName.techBreakout,
          SignalName.reversalW2S,
          SignalName.maAlignmentBullish,
        },
      ],
      summaryKey: 'summary.confluenceFundamentalTechnical',
    ),

    // 高殖利率價值投資：低估 + 高殖利率
    SignalConfluence(
      signalGroups: [
        {SignalName.peUndervalued, SignalName.pbrUndervalued},
        {SignalName.highDividendYield},
      ],
      summaryKey: 'summary.confluenceValueInvestment',
    ),

    // 動能突破：突破 + 均線多頭排列
    // 排在「量價齊揚」模式之後：當同時有 VOLUME_SPIKE 時，量價齊揚
    // 優先消耗 TECH_BREAKOUT，此模式作為無量能放大時的 fallback。
    SignalConfluence(
      signalGroups: [
        {SignalName.techBreakout, SignalName.highVolumeBreakout},
        {SignalName.maAlignmentBullish},
      ],
      summaryKey: 'summary.confluenceMomentumBreakout',
    ),
  ];

  // ==================================================
  // 空頭匯流模式
  // ==================================================

  static const _bearishPatterns = [
    // 頭部反轉：強轉弱 + KD 死亡交叉
    SignalConfluence(
      signalGroups: [
        {SignalName.reversalS2W},
        {
          SignalName.kdDeathCross,
          SignalName.patternHangingMan,
          SignalName.patternEveningStar,
          SignalName.rsiExtremeOverbought,
        },
      ],
      summaryKey: 'summary.confluenceTopReversal',
    ),

    // 技術面崩跌：跌破支撐 + 空頭排列
    SignalConfluence(
      signalGroups: [
        {SignalName.techBreakdown},
        {SignalName.maAlignmentBearish, SignalName.kdDeathCross},
      ],
      summaryKey: 'summary.confluenceBearishBreakdown',
    ),

    // 低估陷阱：估值偏低但趨勢轉弱
    SignalConfluence(
      signalGroups: [
        {SignalName.peUndervalued, SignalName.pbrUndervalued},
        {
          SignalName.reversalS2W,
          SignalName.techBreakdown,
          SignalName.epsDeclineWarning,
          SignalName.maAlignmentBearish,
        },
      ],
      summaryKey: 'summary.confluenceValueTrap',
    ),

    // 法人棄守：法人賣超 + 外資減持
    SignalConfluence(
      signalGroups: [
        {SignalName.institutionalSell, SignalName.institutionalSellStreak},
        {SignalName.foreignExodus, SignalName.foreignShareholdingDecreasing},
      ],
      summaryKey: 'summary.confluenceInstitutionalExit',
    ),
  ];
}
