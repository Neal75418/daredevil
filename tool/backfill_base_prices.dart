// 既有資料的平盤價修復：把 daily_price 的 base_price 與 price_change 補成
// 「收盤 − 交易所當天的平盤價」（除權息漲跌修正 spec 第 4 節）。
//
//   dart run tool/backfill_base_prices.dart [--db <path>] [--market TWSE|TPEx|both]
//       [--from yyyy-MM-dd] [--to yyyy-MM-dd] [--dry-run]
//
// - 上市：挑「價格表裡有上市列、但有平盤價的列不到
//   ApiConfig.basePriceBackfillDoneRatio」的日子，逐日抓證交所股價升降幅度
//   （TWT84U），套用到該日已存在的上市列，並把收盤空值的列漲跌改成空值。這個
//   條件同時是「做過沒」的判斷，中斷了重跑就接續（不用「有任何一列」：上櫃那一輪
//   會把平盤價寫進主檔已轉上市的轉市場列，一列就讓那天被當成做過）。
// - --dry-run 仍會開 DB（beforeOpen 會補 base_price 欄），只是不打網路。
// - 上櫃：價格表有上櫃列的每個月抓一次除權除息結果（exDailyQ），套用到
//   (代號, 除權息日) 已存在的列，**不依目前主檔的市場過濾**（轉上市股票轉
//   市場前的列靠這裡修）。上櫃分不出做過沒，每次全部跑（17 個月）。
// - 只改兩欄、不重抓整天、不動 market_day_fetch 與其他欄；每天／每月一個
//   transaction。請求間隔 ApiConfig.repairToolCallDelayMs（3 秒）。
// - 使用前先照 spec 第 4 節的部署順序（CLI 與 GUI 都換新）；先在副本跑、比對
//   後再對 live DB 跑（spec 驗證第 9、10 點）。
//
// 退出碼：0 全部完成；1 有失敗的天／月；2 參數或 DB 問題；4 限流中止。
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

import 'package:daredevil/core/constants/api_config.dart';
import 'package:daredevil/core/constants/market_codes.dart';
import 'package:daredevil/core/exceptions/app_exception.dart';
import 'package:daredevil/core/utils/date_context.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/data/remote/tpex_client.dart';
import 'package:daredevil/data/remote/twse_client.dart';

import 'tool_db.dart';

class BasePriceBackfillArgs {
  const BasePriceBackfillArgs({
    required this.dbPath,
    required this.market,
    required this.dryRun,
    this.from,
    this.to,
  });

  final String dbPath;

  /// `MarketCode.twse`、`MarketCode.tpex` 或 `'both'`
  final String market;
  final DateTime? from;
  final DateTime? to;
  final bool dryRun;

  bool get doTwse => market != MarketCode.tpex;
  bool get doTpex => market != MarketCode.twse;
}

final _ymd = RegExp(r'^\d{4}-\d{2}-\d{2}$');

DateTime? _parseYmd(String? s) {
  if (s == null || !_ymd.hasMatch(s)) return null;
  final d = DateTime.tryParse(s);
  return d == null ? null : DateContext.normalize(d);
}

/// 解析參數；錯誤經 [err] 回報並回 null。
BasePriceBackfillArgs? parseBasePriceArgs(
  List<String> args,
  void Function(String) err,
) {
  String? dbPath;
  var market = 'both';
  DateTime? from;
  DateTime? to;
  var dryRun = false;
  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    String? next() => i + 1 < args.length ? args[++i] : null;
    switch (a) {
      case '--db':
        dbPath = next();
        if (dbPath == null) {
          err('--db 需要路徑');
          return null;
        }
      case '--market':
        final m = next();
        if (m != MarketCode.twse && m != MarketCode.tpex && m != 'both') {
          err('--market 必須是 ${MarketCode.twse}、${MarketCode.tpex} 或 both');
          return null;
        }
        market = m!;
      case '--from':
        from = _parseYmd(next());
        if (from == null) {
          err('--from 格式 yyyy-MM-dd');
          return null;
        }
      case '--to':
        to = _parseYmd(next());
        if (to == null) {
          err('--to 格式 yyyy-MM-dd');
          return null;
        }
      case '--dry-run':
        dryRun = true;
      default:
        err('不認得的參數: $a');
        return null;
    }
  }
  if (from != null && to != null && from.isAfter(to)) {
    err('--from 不可晚於 --to');
    return null;
  }
  return BasePriceBackfillArgs(
    dbPath:
        dbPath ??
        '${Platform.environment['HOME']}/Library/Containers/'
            'com.neo.afterclose/Data/Documents/afterclose.sqlite',
    market: market,
    from: from,
    to: to,
    dryRun: dryRun,
  );
}

Future<void> main(List<String> args) async {
  exit(await runBasePriceBackfill(args));
}

/// 主流程。測試注入 [twse]／[tpex]／[db]（注入的不由本函式關閉）與
/// [callDelay]；[log] 預設 print。回傳退出碼。
Future<int> runBasePriceBackfill(
  List<String> args, {
  TwseClient? twse,
  TpexClient? tpex,
  AppDatabase? db,
  Duration callDelay = const Duration(
    milliseconds: ApiConfig.repairToolCallDelayMs,
  ),
  void Function(String)? log,
  DateTime? today,
}) async {
  final out = log ?? print;
  // 上櫃當月的迄日夾到今天：迄日在未來的 exDailyQ 請求形狀沒驗過，
  // DividendSyncer 的迄日一律是今天
  final todayDay = DateContext.normalize(today ?? DateTime.now());
  final a = parseBasePriceArgs(args, stderr.writeln);
  if (a == null) return 2;

  final ownsDb = db == null;
  final AppDatabase database;
  if (db != null) {
    database = db;
  } else {
    if (!File(a.dbPath).existsSync()) {
      stderr.writeln('[base] DB 不存在: ${a.dbPath}（修復工具不建立新 DB）');
      return 2;
    }
    // 一律經 openToolDatabase（tool_db_guard_test 把關）：fingerprint 不符時
    // 在開 DB 前中止，不觸發行情表 DROP。
    try {
      database = openToolDatabase(a.dbPath);
    } on SchemaFingerprintMismatch catch (e) {
      stderr.writeln('[base] $e');
      return 2;
    } on SqliteException catch (e) {
      stderr.writeln('[base] DB 檔案無效（非 SQLite 或已損毀）: $e');
      return 2;
    }
  }
  final ownsClients = twse == null && tpex == null;
  final twseClient = twse ?? TwseClient();
  final tpexClient = tpex ?? TpexClient();

  try {
    final days = a.doTwse
        ? await database.getTwseDaysWithoutBasePrice(from: a.from, to: a.to)
        : const <DateTime>[];
    final months = a.doTpex
        ? await database.getTpexMonthsWithPrices(from: a.from, to: a.to)
        : const <({int year, int month})>[];
    out(
      '[base] 上市 ${days.length} 天、上櫃 ${months.length} 個月'
      '（約 ${days.length + months.length} 次呼叫，間隔 '
      '${callDelay.inMilliseconds} ms）；DB=${a.dbPath}',
    );
    if (a.dryRun) return 0;

    var calls = 0;
    var rateLimited = false;
    var twseUpdated = 0;
    final twseFailed = <String>[];
    for (final day in days) {
      if (calls > 0) await Future<void>.delayed(callDelay);
      calls++;
      final ymd = DateContext.formatYmd(day);
      try {
        final bases = await twseClient.getOpeningBasePrices(day);
        var updated = 0;
        var nulled = 0;
        await database.transaction<void>(() async {
          updated = await database.applyBasePrices([
            for (final e in bases.entries)
              (symbol: e.key, date: day, basePrice: e.value),
          ]);
          nulled = await database.nullifyPriceChangeWithoutClose(
            date: day,
            market: MarketCode.twse,
          );
        });
        twseUpdated += updated;
        out('[base] TWSE $ymd: 更新 $updated 列（沒成交改空值 $nulled 列）');
      } on RateLimitException catch (e) {
        out('[base] TWSE $ymd 限流，中止（已做的天保留；重跑會接續）: $e');
        rateLimited = true;
        break;
      } catch (e) {
        twseFailed.add(ymd);
        out('[base] TWSE $ymd 失敗（下一天繼續）: $e');
      }
    }

    var tpexUpdated = 0;
    final tpexFailed = <String>[];
    if (!rateLimited) {
      for (final m in months) {
        if (calls > 0) await Future<void>.delayed(callDelay);
        calls++;
        final label = '${m.year}-${m.month.toString().padLeft(2, '0')}';
        try {
          final monthEnd = DateTime(m.year, m.month + 1, 0);
          final rows = await tpexClient.getExRightResults(
            startDate: DateTime(m.year, m.month, 1),
            endDate: monthEnd.isAfter(todayDay) ? todayDay : monthEnd,
          );
          var updated = 0;
          await database.transaction<void>(() async {
            updated = await database.applyBasePrices([
              for (final r in rows)
                if (r.tradingBasePrice != null)
                  (
                    symbol: r.symbol,
                    date: DateContext.normalize(r.exDate),
                    basePrice: r.tradingBasePrice!,
                  ),
            ]);
          });
          tpexUpdated += updated;
          out('[base] TPEx $label: ${rows.length} 列除權息，更新 $updated 列');
        } on RateLimitException catch (e) {
          out('[base] TPEx $label 限流，中止: $e');
          rateLimited = true;
          break;
        } catch (e) {
          tpexFailed.add(label);
          out('[base] TPEx $label 失敗（下一個月繼續）: $e');
        }
      }
    }

    out(
      '[base] 摘要：上市 ${days.length} 天（更新 $twseUpdated 列、失敗 '
      '${twseFailed.length} 天${twseFailed.isEmpty ? '' : ': ${twseFailed.join(', ')}'}）；'
      '上櫃 ${months.length} 個月（更新 $tpexUpdated 列、失敗 '
      '${tpexFailed.length} 個月${tpexFailed.isEmpty ? '' : ': ${tpexFailed.join(', ')}'}）'
      '${rateLimited ? '；限流中止' : ''}',
    );
    final gap = await database.getBasePriceGap();
    out('[base] 缺平盤價（每輪摘要同一個計數）：上市 ${gap.twseRows} 列、上櫃 ${gap.tpexRows} 列');
    if (rateLimited) return 4;
    return twseFailed.isEmpty && tpexFailed.isEmpty ? 0 : 1;
  } catch (e, st) {
    stderr.writeln('[base] 未預期錯誤: $e');
    stderr.writeln(st.toString());
    return 1;
  } finally {
    if (ownsClients) {
      twseClient.close();
      tpexClient.close();
    }
    if (ownsDb) await database.close();
  }
}
