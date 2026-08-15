// AppLogger 在 CLI 的可見性(2026-08-15 稽核)
//
// 實測:`dart run tool/xxx.dart`(launchd 兩支 CLI 的執行方式)下
// assert 未啟用 → 原本包在 assert 內的輸出全數 no-op,608 個呼叫點
// 輸出零位元組。本專案有「自動更新靜默斷 13 天」的前科。
//
// 修法:加顯式 forceOutput 開關供 CLI 啟用;app release 行為不變
// (預設 false,仍由 assert gate 決定)。
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:daredevil/core/utils/logger.dart';

List<String> captureLogs(void Function() body) {
  final out = <String>[];
  runZoned(
    body,
    zoneSpecification: ZoneSpecification(
      print: (_, __, ___, line) => out.add(line),
    ),
  );
  return out;
}

void main() {
  tearDown(() => AppLogger.forceOutput = false);

  test('🚨 forceOutput=true 時 warning/error 必須輸出(CLI 可見性)', () {
    AppLogger.forceOutput = true;
    final logs = captureLogs(() {
      AppLogger.warning('T', '警告內容');
      AppLogger.error('T', '錯誤內容');
    });
    expect(logs.join('\n'), contains('警告內容'));
    expect(logs.join('\n'), contains('錯誤內容'));
  });

  test('forceOutput=false 維持原行為(不改變 app release 靜默)', () {
    AppLogger.forceOutput = false;
    var isDebug = false;
    assert(() {
      isDebug = true;
      return true;
    }());
    final logs = captureLogs(() => AppLogger.warning('T', '這行'));
    if (isDebug) {
      expect(logs.join('\n'), contains('這行'), reason: 'debug 下照舊輸出');
    } else {
      expect(logs, isEmpty, reason: 'assert 未啟用且未強制 → 維持靜默');
    }
  });
}
