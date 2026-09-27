// tool/refetch_market_days.dart
//
// CLI tool — print 為預期輸出，關閉 avoid_print lint。
// ignore_for_file: avoid_print
//
// 盤後資料一次性修復：指定範圍內的交易日不論狀態一律以官方歷史端點重抓，
// 並記錄抓取狀態（設計見 docs/plans/2026-09-26-market-data-finality-design.md §5）。
// 重抓邏輯與每日更新的「未定案重抓」共用 MarketDayRefetcher，不另寫一套。
//
// ⚠️ 對實際 DB 執行前，先用 --db 對副本彩排並比對官方資料，經同意才跑實際 DB；
// 避開 15:30／21:30 的 launchd 排程時段。
//
// 使用方式：
//   dart run tool/refetch_market_days.dart --dataset prices --market TPEx \
//     --from 2025-06-10 --to 2026-09-24 [--db <path>] [--dry-run]
//   dart run tool/refetch_market_days.dart --dataset valuation \
//     --from 2026-07-15 --to 2026-09-24
//
// --dataset  prices | institutional | dayTrading | margin | foreignShareholding | valuation
// --market   TWSE | TPEx（institutional、valuation 不需要——多帶會被拒絕；
//            foreignShareholding 只能 TWSE）
//
// 退出碼：0 成功／1 有失敗日或未預期例外／2 參數錯誤或 DB 不可用／4 限流中止

import 'dart:io';

import 'package:sqlite3/sqlite3.dart' show SqliteException;

import 'package:daredevil/core/constants/api_config.dart';
import 'package:daredevil/core/constants/market_codes.dart';
import 'package:daredevil/core/constants/market_dataset.dart';
import 'package:daredevil/core/utils/date_context.dart';
import 'package:daredevil/core/utils/taiwan_calendar.dart';
import 'package:daredevil/core/utils/taiwan_time.dart';
import 'package:daredevil/core/exceptions/app_exception.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/data/remote/finmind_client.dart';
import 'package:daredevil/data/remote/mops_client.dart';
import 'package:daredevil/data/remote/tpex_client.dart';
import 'package:daredevil/data/remote/twse_client.dart';
import 'package:daredevil/data/repositories/fundamental_repository.dart';
import 'package:daredevil/data/repositories/institutional_repository.dart';
import 'package:daredevil/data/repositories/market_day_fetch_ledger.dart';
import 'package:daredevil/data/repositories/price_repository.dart';
import 'package:daredevil/data/repositories/shareholding_repository.dart';
import 'package:daredevil/data/repositories/trading_repository.dart';
import 'package:daredevil/domain/services/update/market_day_refetcher.dart';

import 'tool_db.dart';

class RefetchArgs {
  const RefetchArgs({
    required this.dataset,
    required this.market,
    required this.from,
    required this.to,
    required this.dbPath,
    required this.dryRun,
  });

  /// null＝valuation（估值不在定案追蹤範圍，走獨立分支）
  final MarketDataset? dataset;
  final String market;
  final DateTime from;
  final DateTime to;
  final String dbPath;
  final bool dryRun;

  bool get valuation => dataset == null;
}

/// 逐一消化 CLI token 後的結果：[unknown]／[dangling]／[duplicate] 皆非空時
/// 代表解析失敗（見 [_scanArgs] 文件）。
typedef _ArgScan = ({
  Map<String, String> values,
  bool dryRun,
  List<String> unknown,
  List<String> dangling,
  List<String> duplicate,
});

const _knownFlags = {
  '--dataset',
  '--market',
  '--from',
  '--to',
  '--db',
  '--dry-run',
};

/// 逐一消化 [args] 裡的 token：值旗標（`--dataset`／`--market`／`--from`／
/// `--to`／`--db`）吃掉下一個 token 當值，`--dry-run` 是布林旗標，不吃值。
///
/// 任何沒被消化的 token 一律進 [_ArgScan.unknown]——包含單橫線（`-db`）、
/// em dash（`—db`）、忘了寫旗標名的裸值、打錯字的長旗標。這樣才不會出現
/// 「打錯字被默默忽略、`--db` 的值沒生效、`-dry-run` 沒被當成
/// `--dry-run`」這類看起來像成功、實際上落回實際 app DB 或真的執行的情況。
/// 同一個值旗標重複出現（例如 `--db a --db b`）也視為錯誤，避免使用者
/// 誤以為後面那個才生效。
_ArgScan _scanArgs(List<String> args) {
  const valueFlags = {'--dataset', '--market', '--from', '--to', '--db'};
  final values = <String, String>{};
  var dryRun = false;
  final unknown = <String>[];
  final dangling = <String>[];
  final duplicate = <String>[];
  var i = 0;
  while (i < args.length) {
    final token = args[i];
    if (valueFlags.contains(token)) {
      final hasValue = i + 1 < args.length && !args[i + 1].startsWith('-');
      if (values.containsKey(token)) {
        duplicate.add(token);
      } else if (!hasValue) {
        dangling.add(token);
      } else {
        values[token] = args[i + 1];
      }
      i += hasValue ? 2 : 1;
      continue;
    }
    if (token == '--dry-run') {
      if (dryRun) duplicate.add(token);
      dryRun = true;
      i++;
      continue;
    }
    unknown.add(token);
    i++;
  }
  return (
    values: values,
    dryRun: dryRun,
    unknown: unknown,
    dangling: dangling,
    duplicate: duplicate,
  );
}

RefetchArgs? parseRefetchArgs(
  List<String> args,
  void Function(String) err, {
  DateTime? today,
}) {
  final scan = _scanArgs(args);
  final errors = <String>[
    if (scan.unknown.isNotEmpty)
      '無法識別的參數: ${scan.unknown.join(', ')}（已知旗標: ${_knownFlags.join(', ')}）',
    if (scan.dangling.isNotEmpty) '旗標缺值: ${scan.dangling.join(', ')}',
    if (scan.duplicate.isNotEmpty) '旗標重複: ${scan.duplicate.join(', ')}',
  ];
  if (errors.isNotEmpty) {
    for (final e in errors) {
      err(e);
    }
    return null;
  }

  final values = scan.values;
  final ds = values['--dataset'];
  final isValuation = ds == 'valuation';
  final dataset = isValuation
      ? null
      : MarketDataset.values.where((d) => d.code == ds).firstOrNull;
  if (!isValuation && dataset == null) {
    err(
      '--dataset 必須是 ${MarketDataset.values.map((d) => d.code).join(' | ')} | valuation',
    );
    return null;
  }
  final from = DateTime.tryParse(values['--from'] ?? '');
  final to = DateTime.tryParse(values['--to'] ?? '');
  if (from == null || to == null || from.isAfter(to)) {
    err('--from／--to 必須是 YYYY-MM-DD，且 from ≤ to');
    return null;
  }
  // 當天的資料尚未定案（收盤後續補、除權息調整都可能改動），--to 一旦落在
  // 台北今天或更晚，修復摘要統計出來的「成功/失敗」筆數就沒有意義——一律
  // 拒絕，而不是默默跑出一份會誤導使用者的報告。
  final effectiveToday = DateContext.normalize(today ?? TaiwanTime.today());
  if (!DateContext.normalize(to).isBefore(effectiveToday)) {
    err('--to 必須早於台北今天（當天的資料不會定案）');
    return null;
  }
  // institutional 一次涵蓋兩市場、valuation 只修上市，兩者都不吃 --market——
  // 多帶了直接拒絕，而不是默默忽略（忽略會讓使用者誤以為 --market TPEx
  // 對 valuation 有作用）。
  final needsMarket = !isValuation && dataset != MarketDataset.institutional;
  final market = values['--market'];
  if (!needsMarket && market != null) {
    err(
      '--dataset ${isValuation ? 'valuation' : dataset!.code} 不需要 --market'
      '（valuation 僅修上市；institutional 自動涵蓋兩市場），請移除',
    );
    return null;
  }
  if (needsMarket && market != MarketCode.twse && market != MarketCode.tpex) {
    err('--market 必須是 ${MarketCode.twse} 或 ${MarketCode.tpex}');
    return null;
  }
  if (dataset == MarketDataset.foreignShareholding &&
      market != MarketCode.twse) {
    err('foreignShareholding 只有上市（上櫃走 FinMind，不在修復範圍）');
    return null;
  }
  return RefetchArgs(
    dataset: dataset,
    market: market ?? MarketCode.twse,
    from: DateContext.normalize(from),
    to: DateContext.normalize(to),
    dbPath:
        values['--db'] ??
        '${Platform.environment['HOME']}/Library/Containers/'
            'com.neo.afterclose/Data/Documents/afterclose.sqlite',
    dryRun: scan.dryRun,
  );
}

/// 修復工具逐日呼叫間隔——valuation 分支（手動迴圈）與
/// [MarketDayRefetcher] 的 `callDelay` 共用同一個值，見 [ApiConfig]。
const _callDelay = Duration(milliseconds: ApiConfig.repairToolCallDelayMs);

/// 部分失敗（網路錯誤停掉該組剩餘天數，或被限流中止）時，組出「總交易日
/// 數、已嘗試幾日、未嘗試幾日，以及下次該用哪個 `--to` 續跑」的訊息。
///
/// [notAttempted] 是 [days]（`--to`→`--from`，新→舊排序）裡尚未嘗試的尾段；
/// 其中最新的一天（[notAttempted] 的第一筆）就是下次重跑該傳給 `--to`
/// 的日期——使用者從那天往回跑即可銜接上這次未完成的部分。
String describeRemainingDays({
  required int totalDays,
  required int attemptedDays,
  required List<DateTime> notAttempted,
}) {
  if (notAttempted.isEmpty) {
    return '共 $totalDays 個交易日，已全部嘗試（$attemptedDays 日）。';
  }
  final resumeTo = DateContext.formatYmd(notAttempted.first);
  return '共 $totalDays 個交易日，已嘗試 $attemptedDays 日，'
      '尚有 ${notAttempted.length} 日未嘗試；下次可用 --to $resumeTo 續跑。';
}

/// 由 [days]（`--to`→`--from`，新→舊排序）與 `RefetchSummary.stoppedAt`
/// 算出「尚未嘗試」的日子。
///
/// 優先使用 [stoppedAt]（`MarketDayRefetcher` 直接回報「中止在哪一天」）：
/// 未嘗試日＝[days] 裡等於 [stoppedAt] 的那天，以及所有更舊的日子（即
/// `days.sublist(idx)`，[days] 是新→舊排列，`idx` 那天以後全部還沒抓完）。
/// [stoppedAt] 為 null（沒有中止、正常跑完）時，未嘗試日為空清單。
///
/// [attempted] 只在 [stoppedAt] 缺席時當**後備**：呼叫端忘記接
/// `stoppedAt`、或未來新增的呼叫路徑沒有把它傳進來時，仍有一個答案可用，
/// 不必因為缺一個欄位就崩潰或回傳明顯錯誤的型別。
///
/// ⚠️ **這個後備並不可靠**：它用 `attempted < days.length` 猜測
/// 「是否中止」，而中止若剛好發生在候選範圍內**最舊那一天**，出事那天已
/// 被 `attempt()` 算進 attempted（見下段），使 `attempted` 精確等於
/// `days.length`——與「沒有中止、跑滿全部候選日」的訊號完全相同，後備會
/// 把它誤判成「已全部嘗試」而漏掉那一天。[stoppedAt] 有值時不會有這個
/// 問題，因為它不靠比較兩個數字推算，而是由 `MarketDayRefetcher` 直接
/// 講出「就是這一天」。換句話說，後備只是「有勝於無」，不是「一樣正確
/// 的另一條路」。
///
/// 後備算法：`attempted < days.length` 代表提早中止，未嘗試日子從
/// `attempted - 1`（`MarketDayRefetcher._execute` 的 `attempt()` 在呼叫
/// fetch **之前**就先把 attempted 加 1，出事那天已經被算進去）算起；
/// 沒有中止、跑滿全部候選日時 `attempted == days.length`，回傳空清單
/// ——但如前述，這道判準無法區分這兩種情況。
///
/// 僅對「單一 dataset/market 的 [MarketDayRefetcher.refetchRange] 呼叫」
/// 成立：這種呼叫下同一組（dataset, market）只會被自己的 day-loop 處理，
/// 中止不會被其他組打斷（見 `_execute` 對價格／當沖／融資券的逐市場迴圈）；
/// `stoppedAt` 若真的被其他組先設過，也不會影響這裡的判讀。institutional
/// 一次涵蓋兩市場，兩組同步處理同一份天數，中止時兩組的 attempted 恆相等，
/// `stoppedAt` 對兩組都代表同一天，一樣成立。
List<DateTime> computeNotAttempted({
  required List<DateTime> days,
  required int attempted,
  DateTime? stoppedAt,
}) {
  if (stoppedAt != null) {
    final idx = days.indexWhere((d) => DateContext.isSameDay(d, stoppedAt));
    if (idx >= 0) return days.sublist(idx);
  }
  final aborted = attempted < days.length;
  var startIndex = aborted ? attempted - 1 : attempted;
  if (startIndex < 0) startIndex = 0;
  if (startIndex > days.length) startIndex = days.length;
  return days.sublist(startIndex);
}

/// 由 [days]、要重抓的 [dataset]／[market]，與整輪重抓結果 [summary]，算出
/// 續跑提示訊息（見 [describeRemainingDays]）；沒有失敗、也沒有被限流時
/// 回傳 null——這種情況沒什麼好提示的，呼叫端不需要印這行。
///
/// institutional 一次涵蓋兩市場，`summary.attempted`／`stoppedAt` 對兩組
/// 恆相等（見 [computeNotAttempted] 文件對「適用範圍」的說明），固定取
/// TWSE 那組即可代表整體進度。
String? resumeHint({
  required List<DateTime> days,
  required MarketDataset dataset,
  required String market,
  required RefetchSummary summary,
}) {
  if (!summary.rateLimited && summary.errors.isEmpty) return null;
  final group = dataset == MarketDataset.institutional
      ? (dataset: dataset, market: MarketCode.twse)
      : (dataset: dataset, market: market);
  final attempted = summary.attempted[group] ?? 0;
  final notAttempted = computeNotAttempted(
    days: days,
    attempted: attempted,
    stoppedAt: summary.stoppedAt,
  );
  // attemptedDays 由 days.length - notAttempted.length 反推，而不是直接
  // 沿用 summary.attempted：中止時出事那天已被 computeNotAttempted 算回
  // 未嘗試，這裡的「已嘗試」也要跟著扣掉，兩個數字加總才會等於總交易日
  // 數，訊息才不會自相矛盾。
  return describeRemainingDays(
    totalDays: days.length,
    attemptedDays: days.length - notAttempted.length,
    notAttempted: notAttempted,
  );
}

Future<void> main(List<String> args) async {
  exit(await runRefetchCli(args));
}

Future<int> runRefetchCli(List<String> args) async {
  final a = parseRefetchArgs(args, stderr.writeln);
  if (a == null) return 2;

  final days = [
    for (
      var d = a.to;
      !d.isBefore(a.from);
      d = DateTime(d.year, d.month, d.day - 1)
    )
      if (TaiwanCalendar.isTradingDay(d)) d,
  ];
  final label = a.valuation ? 'valuation' : '${a.dataset!.code}/${a.market}';
  print(
    '[refetch] $label ${DateContext.formatYmd(a.from)}～${DateContext.formatYmd(a.to)}：'
    '${days.length} 個交易日（約 ${days.length} 次呼叫）；DB=${a.dbPath}',
  );
  if (a.dryRun) return 0;

  if (!File(a.dbPath).existsSync()) {
    stderr.writeln('[refetch] DB 不存在: ${a.dbPath}（修復工具不建立新 DB）');
    return 2;
  }

  // 一律經 openToolDatabase（tool_db_guard_test 把關）：fingerprint 不符時在
  // 開 DB 前中止。不開 allowSchemaReset——修復工具不得觸發行情表 DROP。
  //
  // 這個 try 只包住「開 DB＋fingerprint 檢查」這一段——SqliteException 在
  // 這裡代表「檔案根本不是 SQLite／已損毀」，比照參數/環境錯誤歸類為 2；
  // DB 開啟後、主邏輯執行中途才拋出的 SqliteException（例如檔案被鎖住）
  // 是執行期問題，不歸類成「DB 檔案無效」，交給下面主邏輯那層的兜底
  // （回 1），避免把兩種成因不同的錯誤混在一起回同一個退出碼。
  final AppDatabase db;
  try {
    db = openToolDatabase(a.dbPath);
  } on SchemaFingerprintMismatch catch (e) {
    stderr.writeln('[refetch] $e');
    return 2;
  } on SqliteException catch (e) {
    stderr.writeln('[refetch] DB 檔案無效（非 SQLite 或已損毀）: $e');
    return 2;
  }

  final twse = TwseClient();
  final tpex = TpexClient();
  final finMind = FinMindClient();
  try {
    if (a.valuation) {
      final fundamental = FundamentalRepository(
        mops: MopsClient(),
        db: db,
        finMind: finMind,
        twse: twse,
        tpex: tpex,
      );
      var succeeded = 0;
      var failed = 0;
      final zeroRowDates = <String>[];
      for (var i = 0; i < days.length; i++) {
        if (i > 0) await Future<void>.delayed(_callDelay);
        final day = days[i];
        try {
          final n = await fundamental.syncTwseValuationForDate(day);
          succeeded++;
          if (n == 0) zeroRowDates.add(DateContext.formatYmd(day));
          print('[refetch] valuation ${DateContext.formatYmd(day)}: $n 筆');
        } on RateLimitException catch (e) {
          final notAttempted = days.sublist(i);
          stderr.writeln('[refetch] 限流中止於 ${DateContext.formatYmd(day)}: $e');
          stderr.writeln(
            '[refetch] ${describeRemainingDays(totalDays: days.length, attemptedDays: i, notAttempted: notAttempted)}',
          );
          return 4;
        } catch (e) {
          failed++;
          stderr.writeln(
            '[refetch] valuation ${DateContext.formatYmd(day)} 失敗: $e',
          );
        }
      }
      print(
        '[refetch] valuation 摘要：共 ${days.length} 個交易日，成功 $succeeded、'
        '失敗 $failed、未嘗試 0'
        '${zeroRowDates.isEmpty ? '' : '；回 0 筆: ${zeroRowDates.join(', ')}'}',
      );
      return failed == 0 ? 0 : 1;
    }

    final refetcher = MarketDayRefetcher(
      database: db,
      priceRepository: PriceRepository(
        database: db,
        finMindClient: finMind,
        twseClient: twse,
        tpexClient: tpex,
      ),
      institutionalRepository: InstitutionalRepository(
        database: db,
        finMindClient: finMind,
        twseClient: twse,
        tpexClient: tpex,
      ),
      tradingRepository: TradingRepository(
        database: db,
        twseClient: twse,
        tpexClient: tpex,
      ),
      shareholdingRepository: ShareholdingRepository(
        database: db,
        finMindClient: finMind,
        twseClient: twse,
      ),
      callDelay: _callDelay,
    );
    final ledger = MarketDayFetchLedger(
      database: db,
      fetchedAt: TaiwanTime.now(),
    );
    final summary = await refetcher.refetchRange(
      dataset: a.dataset!,
      market: a.market,
      from: a.from,
      to: a.to,
      ledger: ledger,
    );
    print('[refetch] ${summary.toLogLine()}');
    for (final e in summary.errors) {
      stderr.writeln('[refetch] $e');
    }
    final hint = resumeHint(
      days: days,
      dataset: a.dataset!,
      market: a.market,
      summary: summary,
    );
    if (hint != null) {
      print('[refetch] $hint');
    }
    if (summary.rateLimited) return 4;
    return summary.errors.isEmpty ? 0 : 1;
  } catch (e, st) {
    stderr.writeln('[refetch] 未預期錯誤: $e');
    stderr.writeln(st.toString());
    return 1;
  } finally {
    twse.close();
    tpex.close();
    finMind.close();
    await db.close();
  }
}
