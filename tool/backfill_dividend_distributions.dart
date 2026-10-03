// tool/backfill_dividend_distributions.dart
//
// CLI tool — print 為預期輸出，關閉 avoid_print lint。
// ignore_for_file: avoid_print
//
// 除權除息歷史回補：指定範圍的（市場, 月）以 TWSE TWT49U／TWT49UDetail 與
// TPEx exDailyQ 寫進股利配發表並記完成紀錄。邏輯與每輪更新的步驟 6.6 共用
// DividendBackfiller，不另寫一套；這裡不設每輪呼叫上限、不理會退避，每次
// 呼叫間隔 ApiConfig.repairToolCallDelayMs。
// 2026-10 以前完成的月份沒有記錄前收盤與除權息參考價，第一次執行會把它們
// 重開一次（每個單位只打 1 次列表、不重查明細）。
//
// ⚠️ 對實際 DB 執行前，先用 --db 對副本彩排，經同意並備份後才跑實際 DB；
// 先關 App，避開 15:30／21:30 的 launchd 排程。每處理一個月前會檢查是否有
// 更新正在跑，有就停下（退出碼 2）。整個回補範圍約 850 次呼叫 × 3 秒 ≈ 43
// 分鐘再加網路時間，可用 --from／--to 分段；中斷後重跑同一條指令即可接續
// （--recheck 例外：已完成的月份也重做，重跑會從頭來）。斷路器計數跨月
// 累計；某市場被斷路器或網路錯誤停掉後，之後的月份不再處理該市場。
//
// 使用方式：
//   dart run tool/backfill_dividend_distributions.dart \
//     [--from 2025-06] [--to 2025-09] [--market TWSE|TPEx] [--recheck] \
//     [--db <path>] [--dry-run]
//
// --from／--to  YYYY-MM；預設為整個回補範圍（今年往前 5 年的 1 月～上個月）
// --market      只補一個市場（預設兩個）
// --recheck     已完成的月份也重做：重新列表、權／權息列一律重查明細
// --dry-run     只驗參數、印出計畫，不開 DB、不打 API
//
// 退出碼：0 範圍內全部完成／1 仍有未完成（失敗、網路停止、斷路）或未預期
// 例外／2 參數錯誤、DB 不可用、有更新正在跑、在市主檔不足／4 限流中止
// （已寫入的保留，重跑同一條指令接續）
//
// 唯讀查完成紀錄：
//   sqlite3 "file:<db>?mode=ro" "SELECT market, year, month, known_rows,
//     skipped_symbols FROM dividend_month_ledger ORDER BY year, month"

import 'dart:io';

import 'package:meta/meta.dart';
import 'package:sqlite3/sqlite3.dart' show SqliteException;

import 'package:daredevil/core/constants/api_config.dart';
import 'package:daredevil/core/constants/data_freshness.dart';
import 'package:daredevil/core/constants/market_codes.dart';
import 'package:daredevil/core/constants/rule_enums.dart';
import 'package:daredevil/core/utils/calendar_month.dart';
import 'package:daredevil/core/utils/logger.dart';
import 'package:daredevil/core/utils/taiwan_time.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/data/remote/tpex_client.dart';
import 'package:daredevil/data/remote/twse_client.dart';
import 'package:daredevil/domain/services/update/dividend_backfiller.dart';
import 'package:daredevil/domain/services/update/dividend_coverage.dart';

import 'tool_db.dart';

class BackfillDividendArgs {
  const BackfillDividendArgs({
    required this.markets,
    required this.from,
    required this.to,
    required this.recheck,
    required this.dbPath,
    required this.dryRun,
  });

  /// null＝兩個市場
  final Set<String>? markets;
  final CalendarMonth from;
  final CalendarMonth to;
  final bool recheck;
  final String dbPath;
  final bool dryRun;
}

const _valueFlags = {'--from', '--to', '--market', '--db'};
const _boolFlags = {'--recheck', '--dry-run'};

/// 逐一消化 token：值旗標吃下一個 token；沒被消化的一律當未知（單橫線、
/// em dash、裸值、打錯字），缺值與重複也拒絕——免得打錯字默默落回實際
/// app DB 或真的執行。規則同 `tool/refetch_market_days.dart`。
BackfillDividendArgs? parseBackfillDividendArgs(
  List<String> args,
  void Function(String) err, {
  DateTime? now,
}) {
  final values = <String, String>{};
  final flags = <String>{};
  final unknown = <String>[];
  final dangling = <String>[];
  final duplicate = <String>[];
  var i = 0;
  while (i < args.length) {
    final token = args[i];
    if (_valueFlags.contains(token)) {
      final hasValue = i + 1 < args.length && !args[i + 1].startsWith('-');
      if (values.containsKey(token)) {
        duplicate.add(token);
      } else if (!hasValue) {
        dangling.add(token);
      } else {
        values[token] = args[i + 1];
      }
      i += hasValue ? 2 : 1;
    } else if (_boolFlags.contains(token)) {
      if (!flags.add(token)) duplicate.add(token);
      i++;
    } else {
      unknown.add(token);
      i++;
    }
  }
  final knownFlags = [..._valueFlags, ..._boolFlags].join(', ');
  final errors = [
    if (unknown.isNotEmpty) '無法識別的參數: ${unknown.join(', ')}（已知旗標: $knownFlags）',
    if (dangling.isNotEmpty) '旗標缺值: ${dangling.join(', ')}',
    if (duplicate.isNotEmpty) '旗標重複: ${duplicate.join(', ')}',
  ];
  if (errors.isNotEmpty) {
    errors.forEach(err);
    return null;
  }

  final target = dividendBackfillTarget(now ?? TaiwanTime.now());
  CalendarMonth? month(String flag, CalendarMonth fallback) {
    final raw = values[flag];
    if (raw == null) return fallback;
    final parsed = CalendarMonth.tryParse(raw);
    if (parsed == null) err('$flag 必須是 YYYY-MM（例如 2025-06）：$raw');
    return parsed;
  }

  final from = month('--from', target.from);
  final to = month('--to', target.to);
  if (from == null || to == null) return null;
  if (from.isAfter(to)) {
    err('--from 不可晚於 --to');
    return null;
  }
  if (to.isAfter(target.to)) {
    err('--to 必須早於本月（本月由每輪更新的本月同步處理）：最晚 ${target.to}');
    return null;
  }
  if (from.isBefore(target.from)) {
    err('--from 不可早於回補範圍起點 ${target.from}');
    return null;
  }
  final market = values['--market'];
  if (market != null &&
      market != MarketCode.twse &&
      market != MarketCode.tpex) {
    err('--market 必須是 ${MarketCode.twse} 或 ${MarketCode.tpex}');
    return null;
  }
  return BackfillDividendArgs(
    markets: market == null ? null : {market},
    from: from,
    to: to,
    recheck: flags.contains('--recheck'),
    dbPath:
        values['--db'] ??
        '${Platform.environment['HOME']}/Library/Containers/'
            'com.neo.afterclose/Data/Documents/afterclose.sqlite',
    dryRun: flags.contains('--dry-run'),
  );
}

/// 限流優先於未完成：已寫入的保留，重跑同一條指令即可接續
int backfillDividendExitCode({
  required bool rateLimited,
  required int missing,
}) {
  if (rateLimited) return 4;
  return missing == 0 ? 0 : 1;
}

Future<void> main(List<String> args) async {
  AppLogger.forceOutput = true; // CLI：繞過 assert gate，逐月進度才看得到
  exit(await runBackfillDividendCli(args));
}

/// [backfillerFactory] 僅供測試注入；正式執行時建立 TWSE／TPEx client。
Future<int> runBackfillDividendCli(
  List<String> args, {
  DateTime? now,
  @visibleForTesting
  DividendBackfiller Function(AppDatabase db)? backfillerFactory,
}) async {
  final a = parseBackfillDividendArgs(args, stderr.writeln, now: now);
  if (a == null) return 2;

  final months = CalendarMonth.descending(from: a.from, to: a.to);
  final markets = a.markets ?? dividendMarkets.toSet();
  print(
    '[dividend-backfill] ${a.from}～${a.to}：${months.length} 個月 × '
    '${markets.length} 個市場，列表最多 ${months.length * markets.length} 次'
    '（明細次數要列表後才知道；已完成的月份要開 DB 才知道）；DB=${a.dbPath}',
  );
  if (a.dryRun) return 0;

  if (!File(a.dbPath).existsSync()) {
    stderr.writeln('[dividend-backfill] DB 不存在: ${a.dbPath}（不建立新 DB）');
    return 2;
  }
  final AppDatabase db;
  try {
    // 經 openToolDatabase：fingerprint 不符時在開 DB 前中止，不觸發 reset
    db = openToolDatabase(a.dbPath);
  } on SchemaFingerprintMismatch catch (e) {
    stderr.writeln('[dividend-backfill] $e');
    return 2;
  } on SqliteException catch (e) {
    stderr.writeln('[dividend-backfill] DB 檔案無效（非 SQLite 或已損毀）: $e');
    return 2;
  }

  TwseClient? twse;
  TpexClient? tpex;
  try {
    final stocks = await db.getAllActiveStocks();
    for (final market in markets) {
      final reason = dividendMarketSkipReason(
        market,
        stocks.where((s) => s.market == market).length,
      );
      if (reason != null) {
        stderr.writeln('[dividend-backfill] $reason（先跑一次更新補齊股票主檔）');
        return 2;
      }
    }

    final DividendBackfiller backfiller;
    if (backfillerFactory != null) {
      backfiller = backfillerFactory(db);
    } else {
      twse = TwseClient();
      tpex = TpexClient();
      backfiller = DividendBackfiller(
        database: db,
        twseClient: twse,
        tpexClient: tpex,
        callDelay: const Duration(
          milliseconds: ApiConfig.repairToolCallDelayMs,
        ),
      );
    }
    final clockNow = now ?? TaiwanTime.now();
    var rateLimited = false;
    // 逐月呼叫時斷路器計數與停掉的市場都要跨月延續，否則端點改版或斷線時
    // 每個月都白打一次、各記一次失敗
    final breaker = DividendBackfillBreaker();
    final active = {...markets};
    for (final m in months) {
      // 逐月處理，每月之前重查：工具要跑幾十分鐘，中途 launchd 或 App 可能
      // 開始更新，兩邊同時打 TWSE 更容易觸發限流
      final runningNow = await runningUpdateNotice(db);
      if (runningNow != null) {
        final done = m == months.first
            ? '尚未處理任何月份'
            : '已處理 ${m.addMonths(1)}～${months.first}';
        stderr.writeln('$runningNow；$done，之後重跑即可接續');
        return 2;
      }
      final summary = await backfiller.backfill(
        now: clockNow,
        maxCalls: 1 << 30,
        scope: DividendBackfillScope(
          markets: {...active},
          from: m,
          to: m,
          recheck: a.recheck,
          ignoreBackoff: true,
        ),
        breaker: breaker,
      );
      print('[dividend-backfill] $m ${summary.toLogLine()}');
      for (final f in summary.failures) {
        stderr.writeln(
          '[dividend-backfill] ${f.key.market} ${f.key.month} 失敗: ${f.error}',
        );
      }
      if (summary.rateLimited) {
        rateLimited = true;
        stderr.writeln(
          '[dividend-backfill] 限流中止於 $m: ${summary.rateLimitError}',
        );
        break;
      }
      for (final e in summary.marketStops.entries) {
        if (active.remove(e.key)) {
          stderr.writeln('[dividend-backfill] ${e.value}；之後的月份不再處理 ${e.key}');
        }
      }
      if (active.isEmpty) break;
    }

    final coverage = await loadDividendCoverage(db, now: clockNow);
    final missing = coverage.missing(from: a.from, to: a.to, markets: markets);
    print(
      '[dividend-backfill] 結果：${a.from}～${a.to} 共 '
      '${coverage.unitCount(from: a.from, to: a.to, markets: markets)} 個單位，'
      '未完成 ${missing.length}'
      '${missing.isEmpty ? '' : '（${missing.take(10).map((k) => '${k.market} ${k.month}').join('、')}${missing.length > 10 ? '…' : ''}）'}',
    );
    return backfillDividendExitCode(
      rateLimited: rateLimited,
      missing: missing.length,
    );
  } catch (e, st) {
    stderr.writeln('[dividend-backfill] 未預期錯誤: $e');
    stderr.writeln(st.toString());
    return 1;
  } finally {
    twse?.close();
    tpex?.close();
    await db.close();
  }
}

/// 最新一筆更新還在跑（RUNNING 且未超過孤兒門檻）時回傳說明，否則 null
Future<String?> runningUpdateNotice(AppDatabase db, {DateTime? clock}) async {
  final latest = await db.getLatestUpdateRun();
  if (latest == null || latest.status != UpdateStatus.running.code) return null;
  final age = (clock ?? DateTime.now()).difference(latest.startedAt);
  if (age > DataFreshness.orphanRunningCutoff) return null;
  return '[dividend-backfill] 有更新正在跑（${latest.startedAt} 開始）；等它結束'
      '再執行。App 被強制結束留下的 RUNNING 會在 '
      '${DataFreshness.orphanRunningCutoff.inHours} 小時後自動收斂';
}
