/// 一次除權除息的還原資料：交易所列表的除權息前收盤價與除權息參考價
class DividendPriceEvent {
  const DividendPriceEvent({
    required this.exDate,
    required this.closeBefore,
    required this.referencePrice,
  });

  /// 除權息日
  final DateTime exDate;

  /// 除權息前收盤價（> 0）
  final double closeBefore;

  /// 除權息參考價（> 0）
  final double referencePrice;

  /// 還原因子＝除權息參考價 ÷ 除權息前收盤價：交易所的除權息調整比例，涵蓋
  /// 現金股利、配股與現金增資（認購價高於市價的現金增資會大於 1）
  double get factor => referencePrice / closeBefore;
}

/// 用到還原價的規則（52 週新高／新低）所需的股利情境。
///
/// 不以 null 表示：「資料不完整」與「完整、窗口內沒有除權除息」必須分得開，
/// 前者規則不觸發，後者照原始價格判斷。
sealed class DividendContext {
  const DividendContext();

  /// 窗口內除權除息資料不完整（含缺價格）：用到還原價的規則不觸發
  const factory DividendContext.incomplete() = DividendIncomplete;

  /// 窗口內除權除息資料完整；[events] 是除權息日在窗口首日之後、評分日以前（含）的
  /// 全部事件
  const factory DividendContext.complete(List<DividendPriceEvent> events) =
      DividendComplete;

  /// 完整、窗口內沒有除權除息
  static const DividendContext noEvents = DividendComplete([]);
}

/// 見 [DividendContext.incomplete]
final class DividendIncomplete extends DividendContext {
  const DividendIncomplete();
}

/// 見 [DividendContext.complete]
final class DividendComplete extends DividendContext {
  const DividendComplete(this.events);

  final List<DividendPriceEvent> events;
}
