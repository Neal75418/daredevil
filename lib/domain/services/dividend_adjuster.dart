import 'package:drift/drift.dart' show Value;

import 'package:daredevil/core/utils/date_context.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/domain/models/dividend_context.dart';

/// 除權息還原：以交易所的除權息調整比例（[DividendPriceEvent.factor]）把
/// 歷史價格換算到評分日的價格水位，涵蓋現金股利、配股與現金增資。
///
/// 目前只有 52 週新高／新低規則使用；均線、RSI 等指標仍用原始價格（另案）。
/// 分割、減資、面額變更不在除權除息列表內，還原後仍會留下水位斷點，由呼叫端
/// 以 `contiguousSuffix` 偵測。
abstract final class DividendAdjuster {
  /// [prices] 為升冪價格序列；回傳同長度、同順序的序列：日期 d 的開高低收
  /// 乘上所有 d < 除權息日 ≤ [asOf] 事件的因子（皆以日期比較）。
  ///
  /// - 除權息當天的價格已是除權息後，不調整；[asOf] 之後的事件不套用，避免
  ///   換日回退時的前視
  /// - 成交量與漲跌價差不動，缺值維持 null
  /// - 不受任何事件影響的日子沿用原物件；沒有要套用的事件時回傳 [prices] 本身
  static List<DailyPriceEntry> adjust(
    List<DailyPriceEntry> prices,
    List<DividendPriceEvent> events, {
    required DateTime asOf,
  }) {
    final cutoff = DateContext.normalize(asOf);
    // 由新到舊排：由新到舊走價格時，「除權息日晚於這一天」的事件恰是清單前綴
    final applicable = [
      for (final e in events)
        if (!DateContext.normalize(e.exDate).isAfter(cutoff))
          (exDate: DateContext.normalize(e.exDate), factor: e.factor),
    ]..sort((a, b) => b.exDate.compareTo(a.exDate));
    if (applicable.isEmpty) return prices;

    final adjusted = List<DailyPriceEntry>.of(prices);
    var factor = 1.0;
    var next = 0;
    for (var i = prices.length - 1; i >= 0; i--) {
      final day = DateContext.normalize(prices[i].date);
      while (next < applicable.length &&
          day.isBefore(applicable[next].exDate)) {
        factor *= applicable[next].factor;
        next++;
      }
      if (next > 0) adjusted[i] = _scale(prices[i], factor);
    }
    return adjusted;
  }

  static DailyPriceEntry _scale(DailyPriceEntry p, double factor) {
    double? scale(double? value) => value == null ? null : value * factor;
    return p.copyWith(
      open: Value(scale(p.open)),
      high: Value(scale(p.high)),
      low: Value(scale(p.low)),
      close: Value(scale(p.close)),
    );
  }
}
