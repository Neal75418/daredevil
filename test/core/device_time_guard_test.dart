import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// lib、tool、bin 讀「現在」只能走 `DeviceTime.now()`。
///
/// 測試以 `scripts/test_time_shift.sh N` 把時間往後撥，找出「過了某天才會紅」
/// 的測試；直接讀 `DateTime.now()`（含 `TZDateTime.now`、`DateTime.timestamp`）
/// 的程式不會跟著撥，撥了也看不出問題。tool 也要掃：`test/tool/` 跑的是
/// tool 的程式。
///
/// 只略過整行註解；字串、行尾註解裡出現也算——寧可誤報（看得到），不要漏抓。
void main() {
  test('lib／tool／bin 不得直接讀 DateTime.now()，一律走 DeviceTime.now()', () {
    final nowRe = RegExp(r'DateTime\s*\.\s*(now|timestamp)\b');
    final violations = <String>[];
    final scanned = <String, int>{};
    for (final root in const ['lib', 'tool', 'bin']) {
      for (final entity in Directory(root).listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        scanned.update(root, (n) => n + 1, ifAbsent: () => 1);
        if (entity.path == 'lib/core/utils/device_time.dart') continue;
        final source = _blankLineComments(entity.readAsStringSync());
        for (final m in nowRe.allMatches(source)) {
          final line = '\n'.allMatches(source.substring(0, m.start)).length + 1;
          violations.add('${entity.path}:$line');
        }
      }
    }
    expect(
      violations,
      isEmpty,
      reason:
          '改用 DeviceTime.now()（能注入時鐘的地方優先用 AppClock）：\n'
          '${violations.join('\n')}',
    );
    // sanity：確實掃到了檔案（防路徑錯誤假綠）
    expect(scanned['lib'], greaterThan(400));
    expect(scanned['tool'], greaterThan(10));
    expect(scanned['bin'], greaterThan(0));
  });
}

/// 整行註解換成空行（行號不變）
String _blankLineComments(String source) => source
    .split('\n')
    .map((l) => l.trimLeft().startsWith('//') ? '' : l)
    .join('\n');
