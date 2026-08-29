// tool/ 的 DB 開啟入口守門(2026-08-29 tool 稽核 Critical #2)
//
// AppDatabase 的 schema fingerprint 不符時會 DROP 所有非 user-input 表。
// 對 app DB 可接受(derived data,隔天重抓);對 `tool/calibration.db` 是
// **九年歷史當場歸零、檔案大小不變、從外觀看不出來**——2026-07-18 已經
// 真的燒過一次 1.2 GB。
//
// 守衛原本只寫在 backfill.dart 一支裡,而 9 支 tool 會開這個檔案;稽核
// 實測其餘 8 支全裸奔,且只要有人照 CLAUDE.md 的 DB 變更流程 bump 一次
// fingerprint 就會引爆。現在守衛住在 tool_db.dart 的單一入口,本測試
// 確保第 10 支工具繞不過去。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  /// 允許直接呼叫 AppDatabase.forToolFile 的檔案——只有共用入口本身。
  const allowed = {'tool_db.dart'};

  test('🚨 tool/ 只有 tool_db.dart 可以直接呼叫 AppDatabase.forToolFile', () {
    final offenders = <String>[];
    var scanned = 0;
    for (final f in Directory(
      'tool',
    ).listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      scanned++;
      final name = f.path.split('/').last;
      if (allowed.contains(name)) continue;
      for (final line in f.readAsLinesSync()) {
        // 跳過註解:多處 docstring 提到這個 API 是刻意的說明
        final t = line.trimLeft();
        if (t.startsWith('//') || t.startsWith('///') || t.startsWith('*')) {
          continue;
        }
        if (line.contains('AppDatabase.forToolFile(')) {
          offenders.add('$name: ${line.trim()}');
        }
      }
    }
    expect(scanned, greaterThanOrEqualTo(10), reason: '掃描本身失效(路徑/副檔名)');
    expect(
      offenders,
      isEmpty,
      reason:
          '請改用 tool_db.dart 的 openToolDatabase()——直接開會在 fingerprint '
          '不符時無聲 DROP 掉整個 calibration.db',
    );
  });

  test('🚨 只有 app DB 的兩支 CLI 可以 opt-in allowSchemaReset', () {
    // 校準鏈的 calibration.db 是唯一副本、重抓要數十小時且 FinMind 配額
    // 根本不夠——那裡 reset 不是「可接受的代價」,是資料毀損。
    const appDbClis = {'daily_update.dart', 'intraday_alert_check.dart'};
    final offenders = <String>[];
    for (final f in Directory(
      'tool',
    ).listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      final name = f.path.split('/').last;
      if (appDbClis.contains(name) || name == 'tool_db.dart') continue;
      if (f.readAsStringSync().contains('allowSchemaReset: true')) {
        offenders.add(name);
      }
    }
    expect(offenders, isEmpty);
  });
}
