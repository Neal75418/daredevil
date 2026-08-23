// tool/backfill_tpex_day_trading.dart
//
// CLI tool — print 為預期輸出，關閉 avoid_print lint。
// ignore_for_file: avoid_print
//
// 上櫃當沖歷史回補（一次性）
//
// ## 為什麼需要這支
//
// 上櫃官方端點 `/www/zh-tw/intraday/stat` **無視 date 參數、只給最新交易日**
// （2026-08-23 實測六個日期回同一份資料、md5 相同），所以每日同步補得到今天、
// 補不到過去。上市那邊沒這問題——TWTB4U 吃日期，`backfill.dart --only-day-trading`
// 逐日回補即可，且走 TWSE 不吃 FinMind 額度。
//
// 歷史只能走 FinMind `TaiwanStockDayTrading`（實測回到 2020-03，欄位與兩市場
// 官方逐位元相符）。免付費層不支援不帶 data_id 的全市場查詢，只能逐檔——
// 但單檔一次呼叫可拉整段區間，所以成本是「檔數」而非「檔數 × 天數」。
//
// ## 使用方式
//
//   # 先看要打幾次、不動任何東西
//   dart run tool/backfill_tpex_day_trading.dart --dry-run
//
//   # 實跑（預設只補流動性夠的股票；--all 補全部上櫃股）
//   dart run tool/backfill_tpex_day_trading.dart --years 2
//
//   --db <path>     預設 app DB；calibration 用 tool/calibration.db
//   --years N       回補年數，預設 2
//   --limit N       最多處理幾檔（分批跑用）
//   --all           不套流動性門檻
//   --dry-run       只印計畫，不打 API 不寫 DB
//
// ## 額度
//
// FinMind free tier 600 次/小時。每檔 1 次呼叫。預設範圍（流動性達標的上櫃股）
// 實測約 248 檔 ≈ 25 分鐘。**它會排擠當天的財報同步**（那也吃 FinMind），
// 所以刻意做成獨立手動 CLI，不塞進每日更新。
//
// ## Resume
//
// 每檔跑完即寫入。中斷後重跑會跳過「該檔已有足量歷史」的股票，不重打 API。
import 'dart:io';

import 'package:daredevil/core/constants/api_config.dart';
import 'package:daredevil/core/constants/data_freshness.dart';
import 'package:daredevil/core/constants/market_codes.dart';
import 'package:daredevil/core/utils/date_context.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/data/remote/finmind_client.dart';
import 'package:drift/drift.dart' show Value;

/// 單檔視為「已回補」的最少列數比例（相對於預期交易日數）
const _resumeCoverageRatio = 0.8;

/// 每檔之間的間隔——600/hr = 每 6 秒 1 次，取 6.2 秒留餘裕
const _callInterval = Duration(milliseconds: 6200);

Future<int> main(List<String> args) async {
  final dryRun = args.contains('--dry-run');
  final all = args.contains('--all');
  final years = _intArg(args, '--years') ?? 2;
  final limit = _intArg(args, '--limit');
  final dbPath =
      _strArg(args, '--db') ??
      '${Platform.environment['HOME']}/Library/Containers/'
          'com.neo.afterclose/Data/Documents/afterclose.sqlite';

  final token = Platform.environment['FINMIND_TOKEN'];
  if (token == null || token.isEmpty) {
    stderr.writeln('❌ FINMIND_TOKEN 未設');
    return 2;
  }
  if (!File(dbPath).existsSync()) {
    stderr.writeln('❌ DB 不存在: $dbPath');
    return 2;
  }

  final end = DateContext.normalize(DateTime.now());
  final start = DateTime(end.year - years, end.month, end.day);
  print('📦 DB: $dbPath');
  print('📅 區間: ${_ymd(start)} → ${_ymd(end)}（$years 年）');

  final db = AppDatabase.forToolFile(dbPath);
  try {
    final stocks = await db.getStocksByMarket(MarketCode.tpex);
    final active = stocks.where((s) => s.isActive).toList();
    print('📊 上櫃股: ${active.length} 檔（active）');

    // 流動性篩選：只補會進評分候選的股票。三年前熱、現在冷的會被漏掉，
    // 但當沖過熱本來就集中在活躍股，而且額度是實打實的成本。
    var targets = active.map((s) => s.symbol).toList();
    if (!all) {
      final liquid = <String>[];
      for (final s in targets) {
        final rows = await db.getPriceHistory(
          s,
          startDate: end.subtract(const Duration(days: 30)),
        );
        if (rows.length < 15) continue;
        final turnovers =
            rows
                .where((r) => r.volume != null)
                .map((r) => (r.close ?? 0) * r.volume!)
                .toList()
              ..sort();
        if (turnovers.isEmpty) continue;
        final median = turnovers[turnovers.length ~/ 2];
        if (median >= ApiConfig.dayTradingBackfillMinMedianTurnover) {
          liquid.add(s);
        }
      }
      print(
        '💧 流動性達標: ${liquid.length} 檔'
        '（20 日中位成交值 ≥ ${ApiConfig.dayTradingBackfillMinMedianTurnover ~/ 10000} 萬）',
      );
      targets = liquid;
    }

    // Resume：已有足量歷史的跳過
    final expectedRows = (years * 250 * _resumeCoverageRatio).round();
    final todo = <String>[];
    for (final s in targets) {
      final have = await db.getDayTradingHistory(s, startDate: start);
      if (have.length < expectedRows) todo.add(s);
    }
    final skipped = targets.length - todo.length;
    print('⏭  已有足量歷史、跳過: $skipped 檔');

    final work = limit == null ? todo : todo.take(limit).toList();
    final mins = (work.length * _callInterval.inMilliseconds / 60000).ceil();
    print('🎯 要打 API: ${work.length} 檔 ≈ $mins 分鐘');

    if (dryRun) {
      print('🧪 --dry-run：不打 API、不寫 DB');
      if (work.isNotEmpty) {
        print('   前 5 檔: ${work.take(5).join(", ")}');
      }
      return 0;
    }
    if (work.isEmpty) {
      print('✅ 無事可做');
      return 0;
    }

    final finMind = FinMindClient()..token = token;
    var done = 0;
    var rowsWritten = 0;
    var failed = 0;
    var skippedNoPrice = 0;

    for (final symbol in work) {
      try {
        final data = await finMind.getDayTrading(
          stockId: symbol,
          startDate: _ymd(start),
          endDate: _ymd(end),
        );
        if (data.isNotEmpty) {
          // **必須算出比例才寫**。校準 replay 只吃 dayTradingRatio，
          // ratio 為 null 的列直接略過（replay_calibrator.dart 的
          // 「不補 0」設計——補了會讓「沒資料」與「當沖 0%」變同一件事）。
          // 只寫原始量值等於回補了幾萬列卻一列都用不到。
          //
          // 分母＝價格表同日總量。上櫃價格歷史從 2025-06 才有，更早的日子
          // 算不出比例——那些列**不寫**，寧可沒資料也不要寫入校準看不見的列。
          final prices = await db.getPriceHistory(
            symbol,
            startDate: start,
            endDate: end,
          );
          final volByDay = <String, double>{
            for (final p in prices)
              if (p.volume != null && p.volume! > 0)
                _ymd(p.date): p.volume!.toDouble(),
          };

          final entries = <DayTradingCompanion>[];
          for (final d in data) {
            final total = volByDay[d.date];
            if (total == null) {
              skippedNoPrice++;
              continue;
            }
            var ratio = (d.volume / total) * 100;
            if (ratio > DataFreshness.dayTradingMaxValidRatio) {
              ratio = DataFreshness.dayTradingMaxValidRatio;
            }
            if (ratio < 0) ratio = 0;
            entries.add(
              DayTradingCompanion.insert(
                symbol: d.stockId,
                date: DateTime.parse(d.date),
                buyVolume: Value(d.buyAmount),
                sellVolume: Value(d.sellAmount),
                dayTradingRatio: Value(ratio),
                tradeVolume: Value(d.volume),
              ),
            );
          }
          if (entries.isNotEmpty) {
            await db.upsertDayTradingPreservingRatio(entries);
            rowsWritten += entries.length;
          }
        }
        done++;
        if (done % 10 == 0 || done == work.length) {
          print(
            '   $done/${work.length} 檔，累計 $rowsWritten 列'
            '${failed > 0 ? "，失敗 $failed" : ""}',
          );
        }
      } catch (e) {
        failed++;
        stderr.writeln('   ⚠️ $symbol 失敗: $e');
      }
      if (done + failed < work.length) await Future.delayed(_callInterval);
    }

    print(
      '✅ 完成: $done 檔成功、$failed 檔失敗，寫入 $rowsWritten 列'
      '${skippedNoPrice > 0 ? "，跳過 $skippedNoPrice 列（該日無價格、算不出比例）" : ""}',
    );
    return failed > 0 && done == 0 ? 1 : 0;
  } finally {
    await db.close();
  }
}

int? _intArg(List<String> args, String name) {
  final i = args.indexOf(name);
  if (i < 0 || i + 1 >= args.length) return null;
  return int.tryParse(args[i + 1]);
}

String? _strArg(List<String> args, String name) {
  final i = args.indexOf(name);
  if (i < 0 || i + 1 >= args.length) return null;
  return args[i + 1];
}

String _ymd(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';
