/// 籌碼強度分析結果
///
/// 綜合法人進出、外資持股比例、融資融券、當沖比例、
/// 持股集中度、內部人持股等面向計算。
class ChipStrengthResult {
  const ChipStrengthResult({
    required this.score,
    required this.rating,
    required this.attitude,
    required this.measuredDomains,
  });

  /// 評級所需的最少有資料域數
  ///
  /// score 從 0 起算、六個輸入全空時各調整項回 0——0 分會被 [ChipRating
  /// .fromScore] 判成 weak（極弱）。「沒被量測」與「實測極弱」在 UI 上
  /// 逐 pixel 相同；上櫃股的持股／當沖／融資覆蓋系統性稀疏，正是會被
  /// 系統性誤標的那批。低於此門檻時 UI 顯示「資料不足」而非評級徽章。
  static const int minMeasuredDomains = 2;

  /// 六個輸入域（法人／外資持股／融資券／當沖／集中度／內部人）中
  /// 實際有資料的域數（0–6）
  final int measuredDomains;

  /// 資料不足以評級——見 [minMeasuredDomains]
  bool get isInsufficient => measuredDomains < minMeasuredDomains;

  /// 籌碼強度總分（0-100）
  final int score;

  /// 依分數判定的評級
  final ChipRating rating;

  /// 法人態度摘要
  final InstitutionalAttitude attitude;
}

/// 籌碼強度評級
///
/// 基底分為 0，評級邊界配合 0-based 分佈調整。
enum ChipRating {
  strong, // 70-100
  bullish, // 50-69
  neutral, // 25-49
  bearish, // 10-24
  weak; // 0-9

  String get i18nKey => switch (this) {
    ChipRating.strong => 'chip.ratingStrong',
    ChipRating.bullish => 'chip.ratingBullish',
    ChipRating.neutral => 'chip.ratingNeutral',
    ChipRating.bearish => 'chip.ratingBearish',
    ChipRating.weak => 'chip.ratingWeak',
  };

  static ChipRating fromScore(int score) {
    if (score >= 70) return ChipRating.strong;
    if (score >= 50) return ChipRating.bullish;
    if (score >= 25) return ChipRating.neutral;
    if (score >= 10) return ChipRating.bearish;
    return ChipRating.weak;
  }
}

/// 法人態度：根據近期買賣超模式判定
enum InstitutionalAttitude {
  aggressiveBuy,
  moderateBuy,
  neutral,
  moderateSell,
  aggressiveSell;

  String get i18nKey => switch (this) {
    InstitutionalAttitude.aggressiveBuy => 'chip.attitudeAggressiveBuy',
    InstitutionalAttitude.moderateBuy => 'chip.attitudeModerateBuy',
    InstitutionalAttitude.neutral => 'chip.attitudeNeutral',
    InstitutionalAttitude.moderateSell => 'chip.attitudeModerateSell',
    InstitutionalAttitude.aggressiveSell => 'chip.attitudeAggressiveSell',
  };
}
