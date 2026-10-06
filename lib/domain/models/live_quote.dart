import 'package:meta/meta.dart';

/// 即時報價的顯示價取自哪裡(依序判斷,見 `LiveQuoteBook`)
enum LiveDisplaySource {
  /// 本輪成交價 z
  trade,

  /// 最後一筆成交:本輪的 trade.z,或報價中心今天記住的成交價／鎖住價
  lastTrade,

  /// 漲跌停鎖住:漲停價或跌停價
  locked,

  /// 試撮價或五檔價(今天還沒有任何成交可用)
  trialOrBook,
}

/// 某一檔最近一次被請求的結果(卡片上的例外標示用)
enum LiveSymbolStatus {
  /// 拿到今天的報價
  ok,

  /// 有回應但沒有可用報價(暫停交易、整天無成交無五檔、日期不是今天)
  noQuote,

  /// 所在批次失敗(網路、rtcode、格式)
  batchFailed,
}

/// 閃色事件:[id] 每次閃色都不同,畫面據此判斷是不是新的事件
@immutable
class LiveQuoteFlash {
  const LiveQuoteFlash({required this.id, required this.up});

  final int id;

  /// 方向比上一輪(不比昨收)
  final bool up;
}

/// 報價中心對某一檔的顯示結果(只存在記憶體,不寫資料庫)
@immutable
class LiveQuoteEntry {
  const LiveQuoteEntry({
    required this.symbol,
    required this.date,
    required this.price,
    required this.displaySource,
    required this.previousClose,
    required this.quoteTime,
    required this.isClosingQuote,
    this.open,
    this.high,
    this.low,
    this.volumeLots,
    this.limitUp,
    this.limitDown,
    this.isLimitUpLocked = false,
    this.isLimitDownLocked = false,
    this.flash,
  });

  final String symbol;

  /// 報價日期(MIS d);只有等於今天才可顯示,見 `LiveQuoteMerge`
  final DateTime date;
  final double price;
  final LiveDisplaySource displaySource;

  /// MIS 昨收 y(除權息日為參考價)
  final double previousClose;

  /// 顯示價對應的時間 HH:mm:ss:最後成交用 trade.t 或記住的時間,其餘用本輪 t
  final String? quoteTime;

  /// 收盤報價(見 `LiveQuoteSchedule.isClosingQuote`)
  final bool isClosingQuote;
  final double? open;
  final double? high;
  final double? low;

  /// 累計成交量(張,MIS v)
  final int? volumeLots;
  final double? limitUp;
  final double? limitDown;
  final bool isLimitUpLocked;
  final bool isLimitDownLocked;

  /// 本輪的閃色事件,沒有為 null;只活一輪。畫面第一次建立時把現有的
  /// id 當作已看過,不補閃
  final LiveQuoteFlash? flash;

  /// 同一筆、拿掉閃色
  LiveQuoteEntry withoutFlash() => LiveQuoteEntry(
    symbol: symbol,
    date: date,
    price: price,
    displaySource: displaySource,
    previousClose: previousClose,
    quoteTime: quoteTime,
    isClosingQuote: isClosingQuote,
    open: open,
    high: high,
    low: low,
    volumeLots: volumeLots,
    limitUp: limitUp,
    limitDown: limitDown,
    isLimitUpLocked: isLimitUpLocked,
    isLimitDownLocked: isLimitDownLocked,
  );
}
