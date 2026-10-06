import 'package:meta/meta.dart';

import 'package:daredevil/core/utils/date_context.dart';
import 'package:daredevil/domain/models/live_quote.dart';
import 'package:daredevil/domain/services/live_quote/live_quote_schedule.dart';

/// 畫面原本要顯示的那筆正式資料(盤後):
/// - 自選:綁分析日期的那筆。
/// - 個股頁:對齊法人日期的那筆。
/// - 投資組合:最新一筆。
/// - 指數:`MarketOverviewState` 的該指數;在 `staleNames` 裡時呼叫端把
///   [date] 傳 null。
@immutable
class OfficialPrice {
  const OfficialPrice({
    required this.date,
    required this.close,
    this.priceChange,
  });

  final DateTime? date;
  final double? close;

  /// 交易所漲跌價差;昨收 = 收盤 − 價差(除權息日即為參考價)
  final double? priceChange;

  @override
  bool operator ==(Object other) =>
      other is OfficialPrice &&
      other.date == date &&
      other.close == close &&
      other.priceChange == priceChange;

  @override
  int get hashCode => Object.hash(date, close, priceChange);
}

enum MergedPriceKind {
  /// 畫面原本的資料是今天且有收盤價
  official,

  /// 今天的有效即時報價
  live,

  /// 都沒有:畫面原本的資料(不改變現行行為)
  fallback,
}

/// 用即時報價時的標示
enum LiveQuoteLabel {
  /// 盤中:報價時間
  quoteTime,

  /// 收盤報價:「今日收盤・待盤後更新」
  closingPending,

  /// 收盤後但不是收盤報價:「最後報價 HH:MM:SS」
  lastQuote,
}

@immutable
class MergedPrice {
  const MergedPrice._({
    required this.kind,
    required this.price,
    required this.previousClose,
    this.label,
    this.live,
  });

  final MergedPriceKind kind;
  final double? price;

  /// 漲跌幅與今日損益的基準:即時為 MIS 的 y;正式與原樣為「收盤 −
  /// priceChange」,priceChange 為 null 時為 null(呼叫端退回前一交易日收盤)
  final double? previousClose;
  final LiveQuoteLabel? label;

  /// 用即時報價時的那一筆(鎖住、開高低量等)
  final LiveQuoteEntry? live;

  String? get quoteTime => live?.quoteTime;

  /// 以 [previousClose] 計的漲跌幅(%);沒有昨收為 null
  double? get changePercent {
    final p = price;
    final prev = previousClose;
    if (p == null || prev == null || prev <= 0) return null;
    return (p / prev - 1) * 100;
  }
}

/// 顯示合併規則(純函式,2026-10-06)。
///
/// 每檔、每個指數以「該畫面原本要顯示的那筆資料」為基準:部分寫入時
/// (價格已到、分析或法人還沒到)畫面繼續用即時報價,直到它自己的資料
/// 到齊,不會出現「判定已有今天資料、實際卻顯示昨天」。
abstract final class LiveQuoteMerge {
  static MergedPrice merge({
    required OfficialPrice? official,
    required LiveQuoteEntry? live,
    required DateTime now,
  }) {
    final officialDate = official?.date;
    final officialClose = official?.close;
    final officialChange = official?.priceChange;
    final officialPrevious = officialClose != null && officialChange != null
        ? officialClose - officialChange
        : null;

    if (officialDate != null &&
        officialClose != null &&
        DateContext.isSameDay(officialDate, now)) {
      return MergedPrice._(
        kind: MergedPriceKind.official,
        price: officialClose,
        previousClose: officialPrevious,
      );
    }
    if (live != null && DateContext.isSameDay(live.date, now)) {
      final label = switch (LiveQuoteSchedule.phaseAt(now)) {
        MarketPhase.open => LiveQuoteLabel.quoteTime,
        _ when live.isClosingQuote => LiveQuoteLabel.closingPending,
        _ => LiveQuoteLabel.lastQuote,
      };
      return MergedPrice._(
        kind: MergedPriceKind.live,
        price: live.price,
        previousClose: live.previousClose,
        label: label,
        live: live,
      );
    }
    return MergedPrice._(
      kind: MergedPriceKind.fallback,
      price: officialClose,
      previousClose: officialPrevious,
    );
  }
}
