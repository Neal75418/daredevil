import 'package:daredevil/core/constants/rule_params_alert.dart';
import 'package:daredevil/core/utils/logger.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/data/models/twse/intraday_quote.dart';
import 'package:daredevil/data/remote/intraday_quote_client.dart';

/// 一輪檢查的結果。
///
/// [quotesFetched]/[symbolsWanted] 是診斷關鍵:「本輪無觸價」可能是
/// 沒到價(正常),也可能是報價全數失敗(要修)——沒有這兩個數字就
/// 分不出來,而兩者的處置完全不同。
///
/// [quoteErrors] 是失敗批次的型別+訊息摘要——AOT CLI 裡 AppLogger 靜默,
/// 錯誤必須走結果鏈才進得了日誌(2026-08-12 早盤盲區調查)。
typedef MonitorResult = ({
  List<TriggeredAlert> fired,
  int quotesFetched,
  int symbolsWanted,
  List<String> quoteErrors,
});

/// 一筆被觸價的提醒 + 當下報價(通知與後續觀察的素材)
class TriggeredAlert {
  const TriggeredAlert({
    required this.alert,
    required this.quote,
    required this.claimStamp,
  });

  final PriceAlertEntry alert;
  final IntradayQuote quote;

  /// 本次認領寫進 DB 的時戳——釋放時必須帶著它比對。
  ///
  /// ⚠️ **不可用 `alert.triggeredAt`**(2026-08-08 四次審查):`alert` 是
  /// 認領**之前**讀到的 entry,它的 `triggeredAt` 必為 null(那正是它被
  /// 選為 pending 的條件)。拿它當 stamp 等於退回無條件釋放,會把別人剛
  /// 寫進去的認領一起抹掉。
  final DateTime claimStamp;
}

/// 盤中提醒監控(2026-08-08)。
///
/// 觸價的語意是「**開始觀察**」不是下單——所以同一筆提醒**只叫一次**
/// (觸發即標記,不再重複嗶),叫的時候把當下報價一起帶出來,讓使用者
/// 有東西可判斷而不只是知道「到了」。
///
/// 只處理價格型(ABOVE/BELOW)。其餘型別(RSI/量能/KD…)需要指標與歷史,
/// 留在盤後的每日更新流程算——盤中反覆重算指標既慢又會與收盤值不一致。
class IntradayAlertMonitor {
  const IntradayAlertMonitor({
    required AppDatabase database,
    required IntradayQuoteClient client,
  }) : _db = database,
       _client = client;

  final AppDatabase _db;
  final IntradayQuoteClient _client;

  /// 檢查一輪。回傳本輪新觸發的提醒;沒有待監控項目時**完全不打 API**。
  Future<MonitorResult> check({DateTime? now}) async {
    final pending = (await _db.getActiveAlerts())
        .where((a) => a.triggeredAt == null)
        // 用共享常數而非就地硬編碼:UI 的分組依同一份清單,兩邊各自
        // 維護必然漂移(2026-08-08)
        .where((a) => AlertParams.intradayMonitoredTypes.contains(a.alertType))
        .toList();
    if (pending.isEmpty) {
      return (
        fired: const <TriggeredAlert>[],
        quotesFetched: 0,
        symbolsWanted: 0,
        quoteErrors: const <String>[],
      );
    }

    // 市場別一律查主檔,不從代號猜(2026-08-07 實測:大量 3167 是上市)
    final stocks = await _db.getAllActiveStocks();
    final marketBySymbol = {for (final s in stocks) s.symbol: s.market};
    final wanted = <String, String>{};
    for (final a in pending) {
      final market = marketBySymbol[a.symbol];
      if (market != null) wanted[a.symbol] = market;
    }
    if (wanted.isEmpty) {
      return (
        fired: const <TriggeredAlert>[],
        quotesFetched: 0,
        symbolsWanted: 0,
        quoteErrors: const <String>[],
      );
    }

    final (:quotes, :errors) = await _client.fetchQuotes(wanted);
    final fired = <TriggeredAlert>[];
    final stamp = now ?? DateTime.now();

    for (final a in pending) {
      final q = quotes[a.symbol];
      // 報價缺該檔(停牌/API 漏)→ 略過。**缺報價不是觸發**
      if (q == null) continue;
      final hit = a.alertType == AlertParams.typeAbove
          ? q.price >= a.targetValue
          : q.price <= a.targetValue;
      if (!hit) continue;

      // 原子認領:app 內輪詢與 launchd CLI 是兩個 process,同時看到同一筆
      // pending 時只有搶到的那個才通知(2026-08-08 code review)
      final claimed = await _db.claimAlertTrigger(a.id, now: stamp);
      if (!claimed) continue;
      fired.add(TriggeredAlert(alert: a, quote: q, claimStamp: stamp));
    }

    if (fired.isNotEmpty) {
      AppLogger.info(
        'IntradayAlertMonitor',
        '盤中觸價 ${fired.length} 筆: '
            '${fired.map((f) => '${f.alert.symbol}@${f.quote.price}').join(', ')}',
      );
    }
    return (
      fired: fired,
      quotesFetched: quotes.length,
      symbolsWanted: wanted.length,
      quoteErrors: errors,
    );
  }
}
