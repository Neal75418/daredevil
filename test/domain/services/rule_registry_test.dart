import 'dart:io';

import 'package:daredevil/domain/services/rule_registry.dart';
import 'package:flutter_test/flutter_test.dart';

/// 從 source 行掃出「可實例化且應註冊」的 Rule 類名。
///
/// 抓:column 0 的 class 宣告,可帶 base/final/interface/mixin 修飾詞,
/// 直接 `extends StockRule`(含換行 extends)或名稱以 Rule 結尾。
/// 跳過:abstract 與 sealed(隱含 abstract)——不可實例化,無從註冊。
Set<String> scanRuleDeclarations(Iterable<String> lines) {
  final head = RegExp(
    r'^(?:(?:base|final|interface|mixin)\s+)?class\s+(\w+)(?:$|[\s<{])',
  );
  final result = <String>{};
  String? pendingName; // 換行 extends:上一行是 class 頭、等下一行判定
  for (final line in lines) {
    if (pendingName != null) {
      if (line.trimLeft().startsWith('extends StockRule')) {
        result.add(pendingName);
      }
      pendingName = null;
    }
    // abstract/sealed(隱含 abstract)由 head regex 排除:修飾詞白名單
    // 只列可實例化的四種——不另設 startsWith 跳過(那會是 regex 已拒絕
    // 之後的死碼,mutation 驗證時等價存活)
    final m = head.firstMatch(line);
    if (m == null) continue;
    final name = m.group(1)!;
    if (RegExp(r'\bextends\s+StockRule\b').hasMatch(line) ||
        name.endsWith('Rule')) {
      result.add(name);
    } else if (!line.contains('extends') && !line.contains('{')) {
      pendingName = name; // 宣告頭在行尾斷開,extends 可能在下一行
    }
  }
  return result;
}

void main() {
  group('RuleRegistry', () {
    test('🚨 完整性:rules/ 內每個具體 Rule 類都必須註冊進 defaultRules', () {
      // 沒有這條守門,新增第 71 條規則忘了掛進 defaultRules 會全綠——
      // 規則類寫了、測試也綠、但引擎永遠不執行它(2026-08-29 稽核)。
      // 宣告來源=掃 source(runtime 無反射可枚舉子類)。
      final declared = <String>{};
      for (final f in Directory(
        'lib/domain/services/rules',
      ).listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('.dart')) continue;
        declared.addAll(scanRuleDeclarations(f.readAsLinesSync()));
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

    group('掃描器本身的樣式覆蓋(2026-08-29 review:漏抓處恰與守門對象重合)', () {
      // 守門的雙向檢查只救得了「註冊了但掃不到」那半;「新類既掃不到又
      // 沒註冊」兩個差集都空、照樣全綠——所以掃描樣式必須自己有測試。
      test('抓得到:修飾詞、換行 extends、泛型', () {
        expect(
          scanRuleDeclarations([
            'class PlainRule extends StockRule {',
            'final class FinalRule extends StockRule {',
            'base class BaseModRule extends StockRule {',
            'interface class IfaceRule extends StockRule {',
            'mixin class MixinRule extends StockRule {',
            'class WrappedRule',
            '    extends StockRule {',
            'class GenericRule<T> extends StockRule {',
          ]),
          {
            'PlainRule',
            'FinalRule',
            'BaseModRule',
            'IfaceRule',
            'MixinRule',
            'WrappedRule',
            'GenericRule',
          },
        );
      });

      test('不誤抓:abstract/sealed(不可實例化)、Base 後綴、註解、縮排', () {
        expect(
          scanRuleDeclarations([
            'abstract class StockRule {',
            'abstract class TemplateRule extends StockRule {',
            // sealed 隱含 abstract——不可實例化,不得要求註冊
            'sealed class SealedRule extends StockRule {',
            'class _Week52RuleBase extends StockRule {', // Rule 後還有字
            '// class CommentedRule extends StockRule {',
            '  class IndentedRule extends StockRule {', // 巢狀/字串內
          ]),
          {'_Week52RuleBase'}, // 直接 extends StockRule 且可實例化——要抓
        );
      });
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
