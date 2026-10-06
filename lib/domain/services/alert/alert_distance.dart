/// 價位提醒的目標距現價多遠(2026-10-06,路線圖第 2 項;純函式)。
abstract final class AlertDistance {
  /// (目標 − 現價) ÷ 現價 × 100:股價要再漲(正)或跌(負)多少 % 才觸發。
  /// 以現價為分母,跟看漲跌幅的習慣一致。沒有現價或現價 ≤ 0 回 null
  static double? percent({required double target, required double? price}) {
    if (price == null || price <= 0) return null;
    return (target / price - 1) * 100;
  }

  /// 條件已成立:向上型現價 ≥ 目標,向下型現價 ≤ 目標
  static bool isReached({
    required bool upward,
    required double target,
    required double price,
  }) => upward ? price >= target : price <= target;
}
