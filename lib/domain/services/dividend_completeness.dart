import 'package:daredevil/core/utils/calendar_month.dart';
import 'package:daredevil/core/utils/date_context.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/domain/services/update/dividend_coverage.dart';

/// 除權除息資料的逐檔完整度：讀取端（52 週規則、個股頁股利表、ETF 近一年
/// 殖利率）判斷「某檔在某段期間的除權除息是否都在庫」的唯一定義。
///
/// **不帶市場參數、兩個市場都查**：配發表沒有市場欄，上櫃轉上市的代號在
/// 期間內會出現在兩個市場的列表，股票主檔的市場在轉板當天也可能還沒更新。
///
/// [isComplete] 為真的條件：
/// 1. 與期間重疊的每個月，兩個市場的有效列表日都 ≥ min(期間迄, 月底)；
///    有效列表日＝max(列表日, 完成紀錄在該月結束後寫下時的月底)——只寫
///    完成紀錄的舊版程式寫下的完成也算數
/// 2. 該代號在期間內沒有未解決的列（任一市場）
/// 3. 與期間重疊的完成紀錄，該代號不在當時略過的代號內
/// 4. `requirePrices` 時，該代號在期間內的配發列都有前收盤與除權息參考價
///
/// 回補範圍（[coverageStart] 起）以前的期間一律不完整。
class DividendCompleteness {
  DividendCompleteness._({
    required this.now,
    required this.coverageStart,
    required this.displayEnd,
    required Map<(String, CalendarMonth), DateTime> effective,
    required Map<String, List<DateTime>> unresolved,
    required Map<String, Set<CalendarMonth>> skipped,
    required Map<String, List<DateTime>> missingPrices,
  }) : _effective = effective,
       _unresolved = unresolved,
       _skipped = skipped,
       _missingPrices = missingPrices;

  factory DividendCompleteness.compute({
    required DateTime now,
    required Iterable<DividendListingEntry> listings,
    required Iterable<DividendMonthLedgerEntry> ledger,
    required Iterable<DividendUnresolvedEntry> unresolved,
    required Iterable<(String, DateTime)> missingPriceKeys,
  }) {
    final effective = <(String, CalendarMonth), DateTime>{};
    void raise(String market, CalendarMonth month, DateTime through) {
      final key = (market, month);
      final current = effective[key];
      if (current == null || through.isAfter(current)) {
        effective[key] = through;
      }
    }

    for (final e in listings) {
      raise(
        e.market,
        CalendarMonth(e.year, e.month),
        DateContext.normalize(e.listedThrough),
      );
    }
    final skipped = <String, Set<CalendarMonth>>{};
    for (final e in ledger) {
      if (e.calendarMonth.isBefore(CalendarMonth.of(e.completedAt))) {
        raise(e.market, e.calendarMonth, e.calendarMonth.lastDay);
      }
      for (final symbol in e.skippedSymbolSet) {
        skipped.putIfAbsent(symbol, () => {}).add(e.calendarMonth);
      }
    }
    final unresolvedBySymbol = <String, List<DateTime>>{};
    for (final u in unresolved) {
      unresolvedBySymbol
          .putIfAbsent(u.symbol, () => [])
          .add(DateContext.normalize(u.exDate));
    }
    final missing = <String, List<DateTime>>{};
    for (final (symbol, exDate) in missingPriceKeys) {
      missing.putIfAbsent(symbol, () => []).add(DateContext.normalize(exDate));
    }

    final target = dividendBackfillTarget(now);
    final today = DateContext.normalize(now);
    DateTime? displayEnd = today;
    for (final market in dividendMarkets) {
      DateTime? contiguous;
      for (
        var month = target.from;
        !month.isAfter(CalendarMonth.of(today));
        month = month.addMonths(1)
      ) {
        final through = effective[(market, month)];
        if (through == null) break;
        contiguous = through;
        if (through.isBefore(month.lastDay)) break;
      }
      if (contiguous == null) {
        displayEnd = null;
        break;
      }
      if (contiguous.isBefore(displayEnd!)) displayEnd = contiguous;
    }

    return DividendCompleteness._(
      now: now,
      coverageStart: target.from.firstDay,
      displayEnd: displayEnd,
      effective: effective,
      unresolved: unresolvedBySymbol,
      skipped: skipped,
      missingPrices: missing,
    );
  }

  final DateTime now;

  /// 回補範圍的第一天；更早的期間一律不完整
  final DateTime coverageStart;

  /// 畫面「截至 M/D」：min(今天, 兩個市場自回補範圍起點連續列過的最後
  /// 一天)。任一市場連回補起點的月份都沒列過時為 null（全部視為建置中）
  final DateTime? displayEnd;

  final Map<(String, CalendarMonth), DateTime> _effective;
  final Map<String, List<DateTime>> _unresolved;
  final Map<String, Set<CalendarMonth>> _skipped;
  final Map<String, List<DateTime>> _missingPrices;

  /// [symbol] 在 [from]～[to]（含頭尾，取日期）的除權除息是否都在庫。
  ///
  /// [requirePrices]：用到價格的讀取端（還原、ETF 殖利率）傳 true，另要求
  /// 每列都有前收盤與除權息參考價；只看金額的（股利表）傳 false。刻意必填：
  /// 漏傳 true 會讓還原拿到缺價格的事件
  bool isComplete(
    String symbol,
    DateTime from,
    DateTime to, {
    required bool requirePrices,
  }) {
    final start = DateContext.normalize(from);
    final end = DateContext.normalize(to);
    if (start.isBefore(coverageStart)) return false;
    for (
      var month = CalendarMonth.of(start);
      !month.isAfter(CalendarMonth.of(end));
      month = month.addMonths(1)
    ) {
      final needed = end.isBefore(month.lastDay) ? end : month.lastDay;
      for (final market in dividendMarkets) {
        final through = _effective[(market, month)];
        if (through == null || through.isBefore(needed)) return false;
      }
      if (_skipped[symbol]?.contains(month) ?? false) return false;
    }
    bool within(DateTime d) => !d.isBefore(start) && !d.isAfter(end);
    if (_unresolved[symbol]?.any(within) ?? false) return false;
    if (requirePrices && (_missingPrices[symbol]?.any(within) ?? false)) {
      return false;
    }
    return true;
  }
}

/// 從 DB 讀出完整度（兩張事實表、完成紀錄、缺價格的列）
Future<DividendCompleteness> loadDividendCompleteness(
  AppDatabase db, {
  required DateTime now,
}) async {
  // 依序讀：同一條連線本來就序列執行；record .wait 會把例外包成
  // ParallelWaitError，呼叫端的分型 catch 接不到
  final listings = await db.getDividendListings();
  final ledger = await db.getDividendMonthLedgerEntries();
  final unresolved = await db.getDividendUnresolved();
  final missing = await db.getDividendMissingPriceKeys();
  return DividendCompleteness.compute(
    now: now,
    listings: listings,
    ledger: ledger,
    unresolved: unresolved,
    missingPriceKeys: missing,
  );
}
