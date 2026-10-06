import 'package:flutter/foundation.dart' show immutable;

import 'package:daredevil/domain/models/live_quote.dart';

/// 卡片上與盤中即時報價有關的資料。只有自選清單會傳;掃描、今日訊號不傳,
/// 行為維持盤後。
@immutable
class StockCardLive {
  const StockCardLive({
    this.limitUp,
    this.limitDown,
    this.limitUpLocked = false,
    this.limitDownLocked = false,
    this.flash,
    this.flashEnabled = true,
    this.caption,
  });

  /// 交易所的漲跌停價(用即時報價時才有);有值時漲跌停以價格精確判斷
  final double? limitUp;
  final double? limitDown;
  final bool limitUpLocked;
  final bool limitDownLocked;

  /// 本輪的閃色事件(見 [LiveQuoteFlash])
  final LiveQuoteFlash? flash;

  /// 設定頁「價格閃色」
  final bool flashEnabled;

  /// 卡片上的例外標示(已翻譯):報價暫停／無報價／最後報價 HH:MM:SS
  final String? caption;
}
