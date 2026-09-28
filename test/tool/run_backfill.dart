// Stage 3 operational runner — wraps tool/backfill.dart main logic in a
// flutter_test `test()` block. Originally required because logger and
// drift_flutter pulled dart:ui into the import closure, so
// `dart run tool/backfill.dart` failed to compile. Both were decoupled on
// 2026-06-19 and `dart run` works now; the wrapper is kept as-is.
//
// This is NOT a unit test. It's a CLI invocation wrapper intended to be run
// by `scripts/calibrate.sh`. The `test()` block is purely a vehicle for the
// flutter test runner to load the Flutter Dart runtime.
//
// ## How it gets its arguments
//
// Arguments come from environment variables set by `scripts/calibrate.sh`:
//
//   FINMIND_TOKEN    required — FinMind API token
//   BACKFILL_YEARS   optional — default 2
//   CALIBRATION_DB   optional — default tool/calibration.db
//   BACKFILL_SYMBOLS optional — CSV whitelist, e.g. "2330,2317"
//   BACKFILL_DRY_RUN optional — set to "1" to enable dry run

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/backfill.dart' as backfill;

void main() {
  test('Stage 3: historical backfill', () async {
    final args = <String>[];

    final years = Platform.environment['BACKFILL_YEARS'];
    if (years != null && years.isNotEmpty) {
      args.addAll(['--years', years]);
    }

    // 精準區間覆寫（例：只補 2021-2023，不重抓既有 2024-2026）
    final startDate = Platform.environment['BACKFILL_START_DATE'];
    if (startDate != null && startDate.isNotEmpty) {
      args.addAll(['--start-date', startDate]);
    }
    final endDate = Platform.environment['BACKFILL_END_DATE'];
    if (endDate != null && endDate.isNotEmpty) {
      args.addAll(['--end-date', endDate]);
    }

    final db = Platform.environment['CALIBRATION_DB'];
    if (db != null && db.isNotEmpty) {
      args.addAll(['--db', db]);
    }

    final symbols = Platform.environment['BACKFILL_SYMBOLS'];
    if (symbols != null && symbols.isNotEmpty) {
      args.addAll(['--symbols', symbols]);
    }

    if (Platform.environment['BACKFILL_DRY_RUN'] == '1') {
      args.add('--dry-run');
    }

    // TWSE 不可用時的備援：改走 FinMind per-symbol（batch 路徑已支援歷史日期）
    if (Platform.environment['BACKFILL_PRICES_VIA_FINMIND'] == '1') {
      args.add('--prices-via-finmind');
    }

    // 跳過基本面 3 phase（省 FinMind quota；第一階段只驗價格類規則）
    if (Platform.environment['BACKFILL_SKIP_FUNDAMENTALS'] == '1') {
      args.add('--skip-fundamentals');
    }

    // 當沖 phase 開關（見 backfill.dart 的 day_trading phase doc）
    if (Platform.environment['BACKFILL_SKIP_DAY_TRADING'] == '1') {
      args.add('--skip-day-trading');
    }
    // 只補當沖：既有 DB 已有價格、多輪累積當沖歷史時用
    if (Platform.environment['BACKFILL_ONLY_DAY_TRADING'] == '1') {
      args.add('--only-day-trading');
    }
    final dayTradingMaxDays =
        Platform.environment['BACKFILL_DAY_TRADING_MAX_DAYS'];
    if (dayTradingMaxDays != null && dayTradingMaxDays.isNotEmpty) {
      args.addAll(['--day-trading-max-days', dayTradingMaxDays]);
    }

    // Token is read from FINMIND_TOKEN env var inside backfill.dart's
    // _parseArgs — no need to pass explicitly here.
    final code = await backfill.runBackfillCli(args);
    expect(
      code,
      0,
      reason:
          'backfill should exit 0; got $code. Exit codes: '
          '1=invalid args, 3=partial failure, 4=rate limit, 5=network',
    );
  }, timeout: Timeout.none);
}
