// 文件裡的規則數必須與程式碼一致(2026-08-22)
//
// **為什麼需要**:規則數同時出現在 README.md、CLAUDE.md、docs/RULE_ENGINE.md、
// .claude/rules/architecture.md **四份文件**。2026-08-22 盤點時四份一起寫著
// 「64 條」,而 `RuleRegistry.defaultRules` 實際已是 70 條——沒有任何機制會在
// 新增規則時提醒更新文件,於是四份同步錯了六條。
//
// 跨文件的重複事實是 silent drift 的溫床:改 code 的人不會想到要改四個 .md。
// 本測試把「文件數字 = 程式碼數字」變成 CI 會擋下的不變量。
//
// **只守這一個數字**:規則數是專案核心賣點、跨四份文件、且查證成本是一行
// `.length`。其餘裝飾性計數(screens 數、client 數)已在同一次盤點中從文件
// 移除——與其守一個沒意義的數字,不如讓它不存在。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/domain/services/rule_registry.dart';

void main() {
  final actual = RuleRegistry.defaultRules.length;

  /// 文件 → 該檔中所有「N 條規則 / N rules」樣式的數字
  final docs = {
    'README.md': RegExp(r'(\d+)\s*條(?:異常偵測)?規則'),
    'CLAUDE.md': RegExp(r'(\d+)\s*條規則'),
    'docs/RULE_ENGINE.md': RegExp(r'(\d+)\s*條異常偵測規則'),
    '.claude/rules/architecture.md': RegExp(r'(\d+)\s*rules'),
  };

  group('文件宣稱的規則數 == RuleRegistry.defaultRules', () {
    for (final entry in docs.entries) {
      test('🚨 ${entry.key}', () {
        final file = File(entry.key);
        expect(file.existsSync(), isTrue, reason: '${entry.key} 不存在');
        final content = file.readAsStringSync();
        final hits = entry.value
            .allMatches(content)
            .map((m) => int.parse(m.group(1)!))
            .toSet();

        expect(
          hits,
          isNotEmpty,
          reason:
              '${entry.key} 找不到規則數的敘述。若是刻意移除該數字，'
              '請一併從本測試的 docs map 移除該檔——否則這條會變成永遠紅的雜訊。',
        );
        expect(
          hits,
          {actual},
          reason:
              '${entry.key} 寫的規則數與程式碼不符。'
              'RuleRegistry.defaultRules 實際 $actual 條，文件寫 $hits。'
              '新增/移除規則時四份文件要一起更新。',
        );
      });
    }
  });
}
