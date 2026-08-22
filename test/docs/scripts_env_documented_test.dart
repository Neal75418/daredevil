// calibrate.sh 的環境變數說明必須涵蓋 CLI 實際讀取的全部（2026-08-22）
//
// **為什麼**：`run_backfill.dart` 讀 11 個環境變數，`calibrate.sh` 的使用說明
// 只列了 5 個。沒列出的等同不存在——2026-08-22 因此沒發現
// `BACKFILL_SKIP_FUNDAMENTALS` 已經存在，繞了一大圈才在讀 source 時撞見，
// 期間白白撞了兩次 FinMind 限流、燒掉一小時額度。
//
// 這裡不驗說明寫得對不對（那要人看），只驗**沒有漏列**：漏列是靜默的，
// 寫錯至少還看得出來。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  /// CLI 從環境讀取的變數名
  Set<String> envVarsRead(String path) => RegExp(
    r"environment\['([A-Z_]+)'\]",
  ).allMatches(File(path).readAsStringSync()).map((m) => m.group(1)!).toSet();

  /// `calibrate.sh` 註解區塊裡 `export FOO=` 形式列出的變數名
  Set<String> envVarsDocumented() =>
      RegExp(r'^#\s+export\s+([A-Z_]+)=', multiLine: true)
          .allMatches(File('scripts/calibrate.sh').readAsStringSync())
          .map((m) => m.group(1)!)
          .toSet();

  /// 所有會被 `calibrate.sh` 的四個 stage 直接或間接讀到環境變數的檔。
  ///
  /// 🚨 2026-08-23 補上 `tool/` 三檔:先前只掃兩個 wrapper,但 Stage 1 的
  /// `BACKFILL_INTER_DAY_DELAY_MS` 與 Stage 4 的 `WF_FOLD_YEARS`／
  /// `WF_SAMPLE_SIZE` 是各 CLI 自己讀的,守門看不到——而 calibrate.sh 卻
  /// 宣稱「此處未列出的等同不存在(守門:scripts_env_documented_test)」。
  /// 那正是這支測試要防的那種「沒列出＝不存在」的靜默落差。
  const envSourceFiles = [
    'test/tool/run_backfill.dart',
    'test/tool/run_replay.dart',
    'tool/backfill.dart',
    'tool/replay_calibrator.dart',
    'tool/walkforward_validate.dart',
  ];

  test('🚨 前提：CLI 確實有讀環境變數（否則本測試是空的）', () {
    expect(envVarsRead('test/tool/run_backfill.dart'), isNotEmpty);
    expect(envVarsRead('test/tool/run_replay.dart'), isNotEmpty);
    expect(envVarsDocumented(), isNotEmpty);
  });

  test('🚨 calibrate.sh 說明未漏列任何 CLI 實際讀取的環境變數', () {
    final read = {for (final f in envSourceFiles) ...envVarsRead(f)};
    final documented = envVarsDocumented();
    final missing = read.difference(documented).toList()..sort();

    expect(
      missing,
      isEmpty,
      reason:
          '這些變數 CLI 讀得到但使用說明沒提，等同不存在：$missing\n'
          '請補進 scripts/calibrate.sh 開頭的「可選環境變數」區塊。',
    );
  });

  test('🚨 說明裡不得出現 CLI 根本不讀的變數（過時殘留）', () {
    final read = {
      for (final f in envSourceFiles) ...envVarsRead(f),
      // 由 shell 自己消費、不經 Dart CLI
      'FINMIND_TOKEN',
      'MAX_RETRIES',
      'SLEEP_BETWEEN_RETRIES',
      'CALIBRATE_LOG',
      'SKIP_WALKFORWARD',
    };
    final stale = envVarsDocumented().difference(read).toList()..sort();
    expect(stale, isEmpty, reason: '說明列了 CLI 不讀的變數：$stale');
  });
}
