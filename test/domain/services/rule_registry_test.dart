import 'dart:io';

import 'package:daredevil/domain/services/rule_registry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RuleRegistry', () {
    test('🚨 完整性:rules/ 內每個具體 Rule 類都必須註冊進 defaultRules', () {
      // 沒有這條守門,新增第 71 條規則忘了掛進 defaultRules 會全綠——
      // 規則類寫了、測試也綠、但引擎永遠不執行它(2026-08-29 稽核)。
      // 宣告來源=掃 source(runtime 無反射可枚舉子類);兩個 pattern:
      // 直接繼承 StockRule,或(防未來出現中繼基底類)名稱以 Rule 結尾
      // 的非 abstract 類。
      final declared = <String>{};
      final direct = RegExp(
        r'^(?:final\s+)?class\s+(\w+)\s+extends\s+StockRule',
      );
      final byName = RegExp(r'^(?:final\s+)?class\s+(\w+Rule)[\s<{]');
      for (final f in Directory(
        'lib/domain/services/rules',
      ).listSync().whereType<File>()) {
        if (!f.path.endsWith('.dart')) continue;
        for (final line in f.readAsLinesSync()) {
          if (line.trimLeft().startsWith('abstract')) continue;
          final m = direct.firstMatch(line) ?? byName.firstMatch(line);
          if (m != null) declared.add(m.group(1)!);
        }
      }
      final registered = RuleRegistry.defaultRules
          .map((r) => r.runtimeType.toString())
          .toSet();

      expect(declared, isNotEmpty, reason: 'source 掃描本身失效(路徑/樣式)');
      // sanity floor:掃描器退化成只抓到少數類時要炸,不得假綠
      expect(declared.length, greaterThanOrEqualTo(60));
      expect(
        declared.difference(registered),
        isEmpty,
        reason: '宣告了但沒註冊——引擎永遠不會執行這些規則',
      );
      expect(
        registered.difference(declared),
        isEmpty,
        reason: '註冊了但 rules/ 找不到宣告——掃描樣式漂移,守門正在假綠',
      );
    });

    test('defaultRules is not empty', () {
      expect(RuleRegistry.defaultRules, isNotEmpty);
    });

    test('all rule IDs are unique', () {
      final ids = RuleRegistry.defaultRules.map((r) => r.id).toSet();
      expect(ids.length, RuleRegistry.defaultRules.length);
    });

    test('all rules have non-empty id', () {
      for (final rule in RuleRegistry.defaultRules) {
        expect(rule.id, isNotEmpty, reason: '${rule.runtimeType} has empty id');
      }
    });
  });
}
