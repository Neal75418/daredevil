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

  test('🚨 前提：CLI 確實有讀環境變數（否則本測試是空的）', () {
    expect(envVarsRead('test/tool/run_backfill.dart'), isNotEmpty);
    expect(envVarsRead('test/tool/run_replay.dart'), isNotEmpty);
    expect(envVarsDocumented(), isNotEmpty);
  });

  test('🚨 calibrate.sh 說明未漏列任何 CLI 實際讀取的環境變數', () {
    final read = {
      ...envVarsRead('test/tool/run_backfill.dart'),
      ...envVarsRead('test/tool/run_replay.dart'),
    };
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
      ...envVarsRead('test/tool/run_backfill.dart'),
      ...envVarsRead('test/tool/run_replay.dart'),
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
