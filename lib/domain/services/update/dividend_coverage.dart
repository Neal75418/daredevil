import 'package:daredevil/core/constants/api_config.dart';
import 'package:daredevil/core/constants/market_codes.dart';
import 'package:daredevil/core/utils/calendar_month.dart';
import 'package:daredevil/data/database/app_database.dart';

/// 除權除息的市場，依回補處理順序：同一個月先上櫃（1 次列表、不需明細），
/// 再上市。
const List<String> dividendMarkets = [MarketCode.tpex, MarketCode.twse];

/// 回補與完整度判斷的單位
typedef DividendMonthKey = ({String market, CalendarMonth month});

/// 回補目標：今年往前 [ApiConfig.dividendBackfillYears] 年的 1 月～上個月。
/// 本月永遠不在內（由每輪的本月同步處理）。
({CalendarMonth from, CalendarMonth to}) dividendBackfillTarget(DateTime now) =>
    (
      from: CalendarMonth(now.year - ApiConfig.dividendBackfillYears, 1),
      to: CalendarMonth.of(now).previous,
    );

/// 某（市場, 月）的完成紀錄是否仍涵蓋現況：有紀錄、月份早於本月、紀錄是
/// 在該月結束之後才寫的（月中寫的只涵蓋到寫入當下，下個月起不能當成整月；
/// 也涵蓋時鐘回撥）、當時略過的代號如今都不在 [knownSymbols]（在市主檔）內，
/// 而且完成時已以列表記錄各列的前收盤與除權息參考價（2026-10 以前的紀錄
/// 沒有，回補重開一次補價）。
bool isDividendMonthComplete(
  DividendMonthLedgerEntry? entry, {
  required Set<String> knownSymbols,
  required CalendarMonth currentMonth,
}) =>
    entry != null &&
    entry.pricesRecorded &&
    entry.calendarMonth.isBefore(currentMonth) &&
    entry.calendarMonth.isBefore(CalendarMonth.of(entry.completedAt)) &&
    !entry.skippedSymbolSet.any(knownSymbols.contains);

/// 是否在退避中：失敗達 [ApiConfig.dividendBackfillBackoffAfterFailures]
/// 次起，上次失敗後 [ApiConfig.dividendBackfillRetryIntervalDays] 天內不重試。
/// 上次失敗時間在未來（時鐘回撥）視同過期，避免永遠卡在退避。
bool isInRetryBackoff(DividendMonthFailureEntry failure, DateTime now) {
  if (failure.failCount < ApiConfig.dividendBackfillBackoffAfterFailures) {
    return false;
  }
  final last = failure.lastFailedAt;
  if (last.isAfter(now)) return false;
  return now.isBefore(
    last.add(const Duration(days: ApiConfig.dividendBackfillRetryIntervalDays)),
  );
}

/// 某市場本輪不回補的原因；在市主檔達門檻時回 null。
String? dividendMarketSkipReason(
  String market,
  int activeStocks, {
  int minStocks = ApiConfig.dividendBackfillMinActiveStocksPerMarket,
}) => activeStocks < minStocks
    ? '$market 在市主檔只有 $activeStocks 檔（門檻 $minStocks），本輪不回補'
    : null;

enum DividendUnitAction {
  /// 要處理
  process,

  /// 已完成，略過
  skipComplete,

  /// 退避中，略過
  skipBackoff,
}

/// 除權除息歷史的完整度：回補（排程與每輪摘要）與修復工具共用的唯一定義
///
/// 「完整」指完成紀錄的事實仍成立（[isDividendMonthComplete]），不是表裡
/// 有資料列。事實相對於現在的在市主檔：主檔新收進的代號會讓相關月份暫時
/// 變成未完成，直到回補重做。
///
/// 讀取端不用這裡的判定：逐檔完整度見 `DividendCompleteness`
/// （`lib/domain/services/dividend_completeness.dart`），它另外看列表日與
/// 未解決的列，兩個市場都查。
class DividendCoverage {
  DividendCoverage._({
    required this.now,
    required Map<DividendMonthKey, DividendMonthLedgerEntry> ledger,
    required Map<DividendMonthKey, DividendMonthFailureEntry> failures,
    required Set<String> knownSymbols,
  }) : _ledger = ledger,
       _failures = failures,
       _knownSymbols = knownSymbols;

  factory DividendCoverage.compute({
    required DateTime now,
    required Iterable<DividendMonthLedgerEntry> ledger,
    required Iterable<DividendMonthFailureEntry> failures,
    required Set<String> knownSymbols,
  }) => DividendCoverage._(
    now: now,
    ledger: {
      for (final e in ledger) (market: e.market, month: e.calendarMonth): e,
    },
    failures: {
      for (final f in failures) (market: f.market, month: f.calendarMonth): f,
    },
    knownSymbols: knownSymbols,
  );

  final DateTime now;
  final Map<DividendMonthKey, DividendMonthLedgerEntry> _ledger;
  final Map<DividendMonthKey, DividendMonthFailureEntry> _failures;
  final Set<String> _knownSymbols;

  CalendarMonth get currentMonth => CalendarMonth.of(now);

  bool isMonthComplete(DividendMonthKey key) => isDividendMonthComplete(
    _ledger[key],
    knownSymbols: _knownSymbols,
    currentMonth: currentMonth,
  );

  /// 未完成單位的失敗紀錄；已完成單位殘留的失敗列（並行時可能發生）一律
  /// 忽略。「完成」以 [isMonthComplete] 為準，重開的單位不算完成。
  DividendMonthFailureEntry? failureOf(DividendMonthKey key) =>
      isMonthComplete(key) ? null : _failures[key];

  /// [from]～[to]（含頭尾）的單位，由新到舊、同月依 [dividendMarkets] 順序
  List<DividendMonthKey> units({
    required CalendarMonth from,
    required CalendarMonth to,
    Set<String>? markets,
  }) => [
    for (final month in CalendarMonth.descending(from: from, to: to))
      for (final market in dividendMarkets)
        if (markets == null || markets.contains(market))
          (market: market, month: month),
  ];

  /// 未完成的單位，由新到舊
  List<DividendMonthKey> missing({
    required CalendarMonth from,
    required CalendarMonth to,
    Set<String>? markets,
  }) => [
    for (final key in units(from: from, to: to, markets: markets))
      if (!isMonthComplete(key)) key,
  ];

  int completedCount({
    required CalendarMonth from,
    required CalendarMonth to,
    Set<String>? markets,
  }) =>
      units(from: from, to: to, markets: markets).where(isMonthComplete).length;

  int unitCount({
    required CalendarMonth from,
    required CalendarMonth to,
    Set<String>? markets,
  }) => units(from: from, to: to, markets: markets).length;

  /// 回補計畫：預設範圍為 [dividendBackfillTarget]，由新到舊、同月先上櫃。
  /// [to] 一律夾在上個月以內：本月由本月同步處理，不能記為完成。
  /// [recheck] 讓已完成的單位也處理；[ignoreBackoff] 讓退避中的也處理
  /// （修復工具用）。
  List<({DividendMonthKey key, DividendUnitAction action})> plan({
    CalendarMonth? from,
    CalendarMonth? to,
    Set<String>? markets,
    bool recheck = false,
    bool ignoreBackoff = false,
  }) {
    final target = dividendBackfillTarget(now);
    final end = to == null || to.isAfter(target.to) ? target.to : to;
    return [
      for (final key in units(
        from: from ?? target.from,
        to: end,
        markets: markets,
      ))
        (key: key, action: _actionFor(key, recheck, ignoreBackoff)),
    ];
  }

  DividendUnitAction _actionFor(
    DividendMonthKey key,
    bool recheck,
    bool ignoreBackoff,
  ) {
    if (!recheck && isMonthComplete(key)) {
      return DividendUnitAction.skipComplete;
    }
    final failure = failureOf(key);
    if (!ignoreBackoff && failure != null && isInRetryBackoff(failure, now)) {
      return DividendUnitAction.skipBackoff;
    }
    return DividendUnitAction.process;
  }
}

/// 從 DB 讀出完整度（在市主檔＋兩張紀錄表）
Future<DividendCoverage> loadDividendCoverage(
  AppDatabase db, {
  required DateTime now,
}) async {
  // 依序讀：同一條連線本來就序列執行；record .wait 會把例外包成
  // ParallelWaitError，呼叫端的分型 catch 接不到
  final stocks = await db.getAllActiveStocks();
  final ledger = await db.getDividendMonthLedgerEntries();
  final failures = await db.getDividendMonthFailures();
  return DividendCoverage.compute(
    now: now,
    ledger: ledger,
    failures: failures,
    knownSymbols: {for (final s in stocks) s.symbol},
  );
}
