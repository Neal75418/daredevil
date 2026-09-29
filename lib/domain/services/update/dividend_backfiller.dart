import 'package:daredevil/core/constants/api_config.dart';
import 'package:daredevil/core/constants/market_codes.dart';
import 'package:daredevil/core/exceptions/app_exception.dart';
import 'package:daredevil/core/utils/calendar_month.dart';
import 'package:daredevil/core/utils/logger.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/data/remote/tpex_client.dart';
import 'package:daredevil/data/remote/twse_client.dart';
import 'package:daredevil/domain/services/update/dividend_coverage.dart';
import 'package:daredevil/domain/services/update/dividend_syncer.dart';

/// 回補範圍（修復工具用；每輪更新用預設值＝整個回補目標）
class DividendBackfillScope {
  const DividendBackfillScope({
    this.markets,
    this.from,
    this.to,
    this.recheck = false,
    this.ignoreBackoff = false,
  });

  /// null＝兩個市場
  final Set<String>? markets;

  /// null＝回補目標的起點（今年往前 5 年的 1 月）
  final CalendarMonth? from;

  /// null＝上個月；不得是本月或未來月份
  final CalendarMonth? to;

  /// 已完成的月份也重做：重新列表，權／權息列一律重查明細
  final bool recheck;

  /// 退避中的月份也處理
  final bool ignoreBackoff;
}

/// 除權除息歷史回補：逐（市場, 月）把 TWT49U／exDailyQ 上在市主檔有的
/// 每一列寫進股利配發表，全部在庫後記完成紀錄（主檔沒有的代號記在完成紀錄
/// 的 skipped_symbols，之後進了主檔該月就重做）。
///
/// 與本月同步（DividendSyncer.syncDistributions）同在更新步驟 6.6，只用本月
/// 同步剩下的呼叫份額；修復工具以同一套邏輯、不設上限執行。
///
/// - 順序：[DividendCoverage.plan]，由新到舊、同月先上櫃；已完成與退避中的
///   單位跳過。
/// - 每次呼叫（列表或明細）前等 [callDelay]，第一次也等；呼叫前檢查上限，
///   計數在發出前加一，失敗的也算。
/// - 列表：過去整月 0 列當失敗（2021-01～2026-08 每月每市場至少 5 列，
///   0 列只會是回應異常）；有列的日期不在該月也當失敗（可能是別段期間的
///   資料）。
/// - 上市「權」「權息」列逐筆查明細、核對參考價（[ExRightResult.matchesReference]），
///   查到就寫；DB 已有的列不重查（[DividendBackfillScope.recheck] 例外）。
///   核對不符時連同 DB 裡同一鍵的舊列一起刪掉（recheck 才會有舊列）。
/// - 完成：[AppDatabase.completeDividendMonth] 在同一個 transaction 內核對預期
///   的列都在庫才寫完成紀錄。
/// - 失敗：一般失敗記進失敗紀錄（退避用）；網路錯誤只停該市場本輪、不記失敗；
///   限流整輪停止（摘要帶 [DividendBackfillSummary.rateLimitError]、不往外拋）；
///   同一市場連續 [ApiConfig.dividendBackfillMaxConsecutiveFailures] 次一般失敗
///   就停掉該市場（斷路器）。DB 錯誤往外拋：那是系統性問題，繼續只會白打 API。
class DividendBackfiller {
  DividendBackfiller({
    required AppDatabase database,
    TwseClient? twseClient,
    TpexClient? tpexClient,
    this.callDelay = const Duration(
      milliseconds: ApiConfig.dividendCallDelayMs,
    ),
    this.minActiveStocksPerMarket =
        ApiConfig.dividendBackfillMinActiveStocksPerMarket,
  }) : _db = database,
       _twse = twseClient,
       _tpex = tpexClient;

  final AppDatabase _db;
  final TwseClient? _twse;
  final TpexClient? _tpex;

  /// 每次呼叫前的等待
  final Duration callDelay;

  /// 某市場在市主檔少於此檔數時不回補該市場
  final int minActiveStocksPerMarket;

  /// [breaker] 省略時每次呼叫各自從零計數（每輪更新）；修復工具逐月呼叫時
  /// 傳同一個，連續失敗才會跨月累積——一個月只打一次列表，各自計數永遠到不
  /// 了上限，端點改版時會把整個範圍白打一遍。
  Future<DividendBackfillSummary> backfill({
    required DateTime now,
    required int maxCalls,
    DividendBackfillScope scope = const DividendBackfillScope(),
    DividendBackfillBreaker? breaker,
  }) async {
    final currentMonth = CalendarMonth.of(now);
    final to = scope.to;
    if (to != null && !to.isBefore(currentMonth)) {
      throw ArgumentError.value(to, 'scope.to', '必須早於本月 $currentMonth');
    }

    final stocks = await _db.getAllActiveStocks();
    final knownSymbols = {for (final s in stocks) s.symbol};
    final coverage = await loadDividendCoverage(_db, now: now);
    final run = _Run(
      now: now,
      maxCalls: maxCalls,
      knownSymbols: knownSymbols,
      breaker: breaker ?? DividendBackfillBreaker(),
    );

    for (final market in dividendMarkets) {
      if (scope.markets != null && !scope.markets!.contains(market)) continue;
      if ((market == MarketCode.twse ? _twse : _tpex) == null) {
        run.marketStops[market] = '$market 沒有 client';
        continue;
      }
      final count = stocks.where((s) => s.market == market).length;
      final reason = dividendMarketSkipReason(
        market,
        count,
        minStocks: minActiveStocksPerMarket,
      );
      if (reason != null) run.marketStops[market] = reason;
    }

    final plan = coverage.plan(
      from: scope.from,
      to: scope.to,
      markets: scope.markets,
      recheck: scope.recheck,
      ignoreBackoff: scope.ignoreBackoff,
    );
    for (final unit in plan) {
      if (unit.action != DividendUnitAction.process) continue;
      final key = unit.key;
      if (run.marketStops.containsKey(key.market)) continue;
      // 上限只在 _call 檢查：用完時拋 _BudgetExhausted，停在這個單位
      try {
        if (key.market == MarketCode.tpex) {
          await _processTpex(run, key);
        } else {
          await _processTwse(run, key, recheck: scope.recheck);
        }
      } on RateLimitException catch (e) {
        run.rateLimitError = e;
        break;
      } on _BudgetExhausted {
        run.stoppedAt = key;
        break;
      }
    }

    return DividendBackfillSummary(
      calls: run.calls,
      maxCalls: maxCalls,
      completed: run.completed,
      failures: run.failures,
      marketStops: run.marketStops,
      rateLimitError: run.rateLimitError,
      stoppedAt: run.stoppedAt,
      coverage: await loadDividendCoverage(_db, now: now),
    );
  }

  Future<void> _processTpex(_Run run, DividendMonthKey key) async {
    final month = key.month;
    final rows = await _list(run, key, () {
      return _tpex!.getExRightResults(
        startDate: month.firstDay,
        endDate: month.lastDay,
      );
    });
    if (rows == null) return;
    final known = [
      for (final r in rows)
        if (run.knownSymbols.contains(r.symbol)) r,
    ];
    await _complete(
      run,
      key,
      rows: [for (final r in known) dividendDistributionCompanion(r)],
      listed: rows,
      known: known,
    );
  }

  Future<void> _processTwse(
    _Run run,
    DividendMonthKey key, {
    required bool recheck,
  }) async {
    final month = key.month;
    final rows = await _list(run, key, () {
      return _twse!.getExRightResults(
        startDate: month.firstDay,
        endDate: month.lastDay,
      );
    });
    if (rows == null) return;
    final known = [
      for (final r in rows)
        if (run.knownSymbols.contains(r.symbol)) r,
    ];
    await _db.upsertDividendDistributions([
      for (final r in known)
        if (!r.needsDetail) dividendDistributionCompanion(r),
    ]);

    final processed = recheck
        ? const <(String, DateTime)>{}
        : await _db.getDividendDistributionKeys(
            from: month.firstDay,
            to: month.lastDay,
          );
    final failedSymbols = <String>{};
    String? firstError;
    try {
      for (final row in known) {
        if (!row.needsDetail || processed.contains((row.symbol, row.exDate))) {
          continue;
        }
        final ExRightDetail detail;
        try {
          detail = await _call(
            run,
            key.market,
            () => _twse!.getExRightDetail(row.symbol, row.exDate),
          );
        } on _GeneralFailure catch (e) {
          failedSymbols.add(row.symbol);
          firstError ??= '明細 ${row.symbol}: ${e.cause}';
          if (run.marketStops.containsKey(key.market)) break;
          continue;
        }
        if (!row.matchesReference(detail)) {
          // recheck 時 DB 可能有舊列（例如核對上線前寫入的）：刪掉，否則
          // 下一輪把它當成已處理、不查明細就記完成
          await _db.deleteDividendDistribution(row.symbol, row.exDate);
          failedSymbols.add(row.symbol);
          firstError ??= '明細 ${row.symbol}: 推算的參考價與列表不符';
          _countFailure(run, key.market);
          if (run.marketStops.containsKey(key.market)) break;
          continue;
        }
        await _db.upsertDividendDistributions([
          dividendDistributionCompanion(row.withDetail(detail)),
        ]);
        _countSuccess(run, key.market);
      }
    } on _NetworkStop {
      await _recordDetailFailures(run, key, failedSymbols, firstError);
      return;
    } on RateLimitException {
      await _recordDetailFailures(run, key, failedSymbols, firstError);
      rethrow;
    } on _BudgetExhausted {
      await _recordDetailFailures(run, key, failedSymbols, firstError);
      rethrow;
    }
    if (failedSymbols.isNotEmpty) {
      await _recordDetailFailures(run, key, failedSymbols, firstError);
      return;
    }
    await _complete(run, key, rows: const [], listed: rows, known: known);
  }

  Future<void> _recordDetailFailures(
    _Run run,
    DividendMonthKey key,
    Set<String> failedSymbols,
    String? firstError,
  ) async {
    if (failedSymbols.isEmpty) return;
    // 每筆明細失敗已在查的當下計入斷路器
    await _fail(
      run,
      key,
      '${failedSymbols.length} 筆明細失敗，$firstError',
      failedSymbols: failedSymbols,
      listOk: true,
      countsForBreaker: false,
    );
  }

  /// 打列表並檢查。回 null＝已記失敗或該市場已停。
  Future<List<ExRightResult>?> _list(
    _Run run,
    DividendMonthKey key,
    Future<List<ExRightResult>> Function() fetch,
  ) async {
    final List<ExRightResult> rows;
    try {
      rows = await _call(run, key.market, fetch);
    } on _GeneralFailure catch (e) {
      // 呼叫失敗已在 _call 計入斷路器
      await _fail(
        run,
        key,
        '列表: ${e.cause}',
        listOk: false,
        countsForBreaker: false,
      );
      return null;
    } on _NetworkStop {
      return null;
    }
    if (rows.isEmpty) {
      await _fail(run, key, '列表 0 列（過去整月不會沒有除權息）', listOk: false);
      return null;
    }
    final month = key.month;
    final outside = rows.where((r) => CalendarMonth.of(r.exDate) != month);
    if (outside.isNotEmpty) {
      await _fail(
        run,
        key,
        '列表有 ${outside.length} 列不在 $month（例如 ${outside.first.symbol} '
        '${outside.first.exDate}）',
        listOk: false,
      );
      return null;
    }
    _countSuccess(run, key.market);
    return rows;
  }

  Future<void> _complete(
    _Run run,
    DividendMonthKey key, {
    required List<DividendDistributionCompanion> rows,
    required List<ExRightResult> listed,
    required List<ExRightResult> known,
  }) async {
    final missing = await _db.completeDividendMonth(
      market: key.market,
      month: key.month,
      rows: rows,
      expectedKeys: {for (final r in known) (r.symbol, r.exDate)},
      listedRows: listed.length,
      skippedSymbols: {
        for (final r in listed)
          if (!run.knownSymbols.contains(r.symbol)) r.symbol,
      },
      completedAt: run.now,
    );
    if (missing.isEmpty) {
      run.completed.add(key);
      return;
    }
    final sample = missing.take(3).map((k) => '${k.$1} ${k.$2}').join('、');
    await _fail(
      run,
      key,
      '核對失敗：${missing.length} 列不在庫（$sample）',
      listOk: true,
      countsForBreaker: false,
    );
  }

  Future<void> _fail(
    _Run run,
    DividendMonthKey key,
    String error, {
    Set<String> failedSymbols = const {},
    required bool listOk,
    bool countsForBreaker = true,
  }) async {
    run.failures.add((key: key, error: error));
    AppLogger.warning(
      'DividendBackfiller',
      '${key.market} ${key.month} 回補失敗: $error',
    );
    await _db.recordDividendMonthFailure(
      market: key.market,
      month: key.month,
      failedAt: run.now,
      error: error,
      failedSymbols: failedSymbols,
      listOk: listOk,
    );
    // 列表內容失敗（0 列、範圍不符）也算一般失敗：端點改成回空或回錯區間
    // 時，斷路器同樣要擋住每月白打
    if (countsForBreaker) _countFailure(run, key.market);
  }

  /// 斷路器歸零：列表通過空月與範圍檢查、或明細通過參考價核對才算成功——
  /// 只看 HTTP 成功的話，「回應正常但內容壞掉」永遠累積不到上限
  void _countSuccess(_Run run, String market) =>
      run.breaker._consecutiveFailures[market] = 0;

  /// 斷路器計數：同一市場連續達上限就停掉該市場本輪
  void _countFailure(_Run run, String market) {
    final failures = run.breaker._consecutiveFailures;
    final count = (failures[market] ?? 0) + 1;
    failures[market] = count;
    if (count >= ApiConfig.dividendBackfillMaxConsecutiveFailures) {
      run.marketStops[market] = '$market 連續 $count 次失敗，本輪停止';
    }
  }

  /// 等待 → 檢查上限 → 計數 → 呼叫，並分類例外（斷路器在內容也通過檢查後
  /// 才歸零，見 [_countSuccess]）：
  /// - [RateLimitException] 原樣往外拋（整輪停止）
  /// - [NetworkException] 停掉該市場本輪，拋 [_NetworkStop]
  /// - 其他：斷路器計數，拋 [_GeneralFailure]；達上限時停掉該市場
  Future<T> _call<T>(
    _Run run,
    String market,
    Future<T> Function() fetch,
  ) async {
    if (run.calls >= run.maxCalls) throw const _BudgetExhausted();
    await Future<void>.delayed(callDelay);
    run.calls++;
    try {
      return await fetch();
    } on RateLimitException {
      rethrow;
    } on NetworkException catch (e) {
      run.marketStops[market] = '$market 網路錯誤，本輪停止: $e';
      throw const _NetworkStop();
    } catch (e) {
      _countFailure(run, market);
      throw _GeneralFailure(e);
    }
  }
}

/// 回補一輪的結果
class DividendBackfillSummary {
  const DividendBackfillSummary({
    required this.calls,
    required this.maxCalls,
    required this.completed,
    required this.failures,
    required this.marketStops,
    required this.rateLimitError,
    required this.stoppedAt,
    required this.coverage,
  });

  final int calls;
  final int maxCalls;

  /// 本輪完成的單位
  final List<DividendMonthKey> completed;

  /// 本輪失敗的單位與第一個錯誤
  final List<({DividendMonthKey key, String error})> failures;

  /// 本輪停掉的市場與原因
  final Map<String, String> marketStops;

  final RateLimitException? rateLimitError;

  /// 呼叫上限用完時，下一個要處理的單位
  final DividendMonthKey? stoppedAt;

  /// 結束時重讀的完整度
  final DividendCoverage coverage;

  bool get rateLimited => rateLimitError != null;

  /// 每輪一行的進度（launchd 日誌 grep「除權除息回補」即可追收斂）
  String toLogLine() {
    final target = dividendBackfillTarget(coverage.now);
    int done([Set<String>? markets]) => coverage.completedCount(
      from: target.from,
      to: target.to,
      markets: markets,
    );
    int total([Set<String>? markets]) =>
        coverage.unitCount(from: target.from, to: target.to, markets: markets);
    final next = coverage.missing(from: target.from, to: target.to);
    final stop = rateLimited
        ? '限流'
        : stoppedAt != null
        ? '預算'
        : marketStops.isNotEmpty
        ? marketStops.values.join('；')
        : null;
    return '除權除息回補 本輪完成 ${completed.length}、失敗 ${failures.length}，'
        '呼叫 $calls/$maxCalls；累計 ${done()}/${total()}'
        '（TWSE ${done({MarketCode.twse})}/${total({MarketCode.twse})}、'
        'TPEx ${done({MarketCode.tpex})}/${total({MarketCode.tpex})}）'
        '${next.isEmpty ? '，已補齊' : '，剩 ${next.length} 單位，下一個 ${_label(next.first)}'}'
        '${stop == null ? '' : '；停止：$stop'}';
  }

  /// 回補範圍內有待重試的失敗或本輪停掉的市場時的警示；沒有異常回 null
  String? warningLine() {
    final target = dividendBackfillTarget(coverage.now);
    final pending = [
      for (final key in coverage.units(from: target.from, to: target.to))
        if (coverage.failureOf(key) case final f?) (key: key, failure: f),
    ];
    if (pending.isEmpty && marketStops.isEmpty) return null;
    final listed = pending
        .take(10)
        .map(
          (p) =>
              '${_label(p.key)}（第 ${p.failure.failCount} 次，'
              '${p.failure.lastError}）',
        )
        .join('；');
    final more = pending.length > 10 ? '；…' : '';
    return [
      if (pending.isNotEmpty) '除權除息回補 ${pending.length} 個單位待重試：$listed$more',
      if (marketStops.isNotEmpty) '停掉的市場：${marketStops.values.join('；')}',
      '可用 dart run tool/backfill_dividend_distributions.dart 手動處理',
    ].join('。');
  }

  static String _label(DividendMonthKey key) => '${key.market} ${key.month}';
}

class _Run {
  _Run({
    required this.now,
    required this.maxCalls,
    required this.knownSymbols,
    required this.breaker,
  });

  final DateTime now;
  final int maxCalls;
  final Set<String> knownSymbols;
  int calls = 0;
  final completed = <DividendMonthKey>[];
  final failures = <({DividendMonthKey key, String error})>[];
  final marketStops = <String, String>{};
  final DividendBackfillBreaker breaker;
  RateLimitException? rateLimitError;
  DividendMonthKey? stoppedAt;
}

/// 回補斷路器的連續失敗計數（逐市場）。見 [DividendBackfiller.backfill] 的
/// `breaker`。
class DividendBackfillBreaker {
  final _consecutiveFailures = <String, int>{};
}

class _BudgetExhausted implements Exception {
  const _BudgetExhausted();
}

class _NetworkStop implements Exception {
  const _NetworkStop();
}

class _GeneralFailure implements Exception {
  const _GeneralFailure(this.cause);

  final Object cause;

  @override
  String toString() => '$cause';
}
