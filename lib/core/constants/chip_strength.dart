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
  /// 六個輸入全空時各調整項回 0 → 分數停在 baseline、會被判成「中性」——
  /// 比舊制的「極弱」溫和，但仍是把「沒被量測」謊報成「實測中性」；上櫃
  /// 股的持股／當沖／融資覆蓋系統性稀疏，正是會被系統性誤標的那批。
  /// 低於此門檻時 UI 顯示「資料不足」而非評級徽章。
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
/// 基底分為 [ChipScoringParams.baselineScore]（50），分帶以中點對稱:
/// 淨訊號 |±9| 內=中性（低於最小有意義訊號 ±10~12）、±10~29=偏多/偏空
/// （單一明確訊號起跳）、±30 起=極強/極弱（最強單一訊號 +30 或多重訊號）。
/// 舊制從 0 起算、要 +25 淨訊號才「中性」——那組邊界是跟著 0-based 病灶
/// 調的，一併重定（2026-08-29）。
enum ChipRating {
  strong, // 80-100（淨 +30 起）
  bullish, // 60-79（淨 +10~29）
  neutral, // 41-59（淨 ±9 內）
  bearish, // 21-40（淨 −10~−29）
  weak; // 0-20（淨 −30 起）

  String get i18nKey => switch (this) {
    ChipRating.strong => 'chip.ratingStrong',
    ChipRating.bullish => 'chip.ratingBullish',
    ChipRating.neutral => 'chip.ratingNeutral',
    ChipRating.bearish => 'chip.ratingBearish',
    ChipRating.weak => 'chip.ratingWeak',
  };

  static ChipRating fromScore(int score) {
    if (score >= 80) return ChipRating.strong;
    if (score >= 60) return ChipRating.bullish;
    if (score >= 41) return ChipRating.neutral;
    if (score >= 21) return ChipRating.bearish;
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
