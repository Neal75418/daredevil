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

  // SQLite 端的「現在」（欄位預設值、SQL 的 now）不經 DeviceTime、撥不到。
  // 資料表定義的 withDefault 是既有的例外（見 DeviceTime 說明）；查詢條件裡
  // 拿它跟 DeviceTime 比，撥時間時就會像 UpdateRun.startedAt 那樣必然不一致
  test('資料表定義以外不得讀 SQLite 端的「現在」', () {
    final sqlNowRes = [
      // Drift 的 currentDateAndTime；SQL 的 CURRENT_TIMESTAMP 等
      RegExp(
        r'\bcurrentDateAndTime\b|\bcurrent_(timestamp|date|time)\b',
        caseSensitive: false,
      ),
      // SQL 日期函式帶 'now'（含跳脫引號、strftime 的格式參數）
      RegExp(
        r'''\b(date|datetime|julianday|strftime|unixepoch|time)\s*\(\s*(\\?['"][^'"]*\\?['"]\s*,\s*)?\\?['"]now\\?['"]''',
        caseSensitive: false,
      ),
      // SQL 日期函式省略時間參數＝'now'（只認全小寫或全大寫，避開 Dart 的
      // DateTime(…) 等建構子）
      RegExp(
        r'''\b(date|datetime|julianday|unixepoch|time|DATE|DATETIME|JULIANDAY|UNIXEPOCH|TIME)\s*\(\s*\)|\b(strftime|STRFTIME)\s*\(\s*\\?['"][^'"]*\\?['"]\s*\)''',
      ),
    ];
    // Drift 的 currentDate 常數。只掃 lib：tool 把 currentDate 當一般參數名
    // （replay_calibrator）；具名參數 `currentDate:`（showDatePicker）不算
    final driftCurrentDateRe = RegExp(r'\bcurrentDate\b(?!\s*:)');
    final violations = <String>[];
    var scanned = 0;
    for (final root in const ['lib', 'tool', 'bin']) {
      for (final entity in Directory(root).listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        scanned++;
        if (entity.path.startsWith('lib/data/database/tables/')) continue;
        final source = _blankLineComments(entity.readAsStringSync());
        final res = [...sqlNowRes, if (root == 'lib') driftCurrentDateRe];
        for (final re in res) {
          for (final m in re.allMatches(source)) {
            final line =
                '\n'.allMatches(source.substring(0, m.start)).length + 1;
            violations.add('${entity.path}:$line: ${m[0]}');
          }
        }
      }
    }
    expect(
      violations,
      isEmpty,
      reason:
          '改從 Dart 端帶 DeviceTime.now() 當參數：\n'
          '${violations.join('\n')}',
    );
    expect(scanned, greaterThan(400));
  });
}

/// 整行註解換成空行（行號不變）
String _blankLineComments(String source) => source
    .split('\n')
    .map((l) => l.trimLeft().startsWith('//') ? '' : l)
    .join('\n');
