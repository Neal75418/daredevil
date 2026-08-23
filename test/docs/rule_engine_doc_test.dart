// docs/RULE_ENGINE.md 的規則表必須與程式一致（2026-08-23）
//
// **為什麼需要**：既有的 `doc_rule_count_consistency_test.dart` 只用一條窄
// regex 抓各文件標題那一處總數。它在 `64 Rules` 與「66 reason / 64 規則」
// 就躺在 RULE_ENGINE.md 裡的情況下**全綠**，也沒發現六條 MA 階梯規則從沒被
// 收錄、`DAY_TRADING_HIGH` 的分數寫 +12 而程式是 0。
//
// 這裡守兩件**數字化、抓得住**的事：
//   1. 文件收錄的規則集合 == `ReasonType` 全集（漏收或幻影都會紅）
//   2. 每一列印的設計基準分 == `ReasonType.score`
//
// 觸發條件那一欄是散文，守不住——靠 post-commit 提醒與人工 review。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/constants/reason_type.dart';

void main() {
  const docPath = 'docs/RULE_ENGINE.md';

  /// 解析 `| RULE_CODE | +12 | 條件… |` 形式的列。
  ///
  /// 分數允許 `+12` / `-8` / `±8`（雙向規則，比對絕對值）/ `0`。
  Map<String, ({int score, bool bidirectional})> parseDocRules() {
    final result = <String, ({int score, bool bidirectional})>{};
    final row = RegExp(r'^\|\s*([A-Z][A-Z0-9_]+)\s*\|\s*([+±-]?\d+)\s*\|');
    for (final line in File(docPath).readAsLinesSync()) {
      final m = row.firstMatch(line);
      if (m == null) continue;
      final raw = m.group(2)!;
      final bidi = raw.startsWith('±');
      result[m.group(1)!] = (
        score: int.parse(raw.replaceAll('±', '').replaceAll('+', '')),
        bidirectional: bidi,
      );
    }
    return result;
  }

  test('🚨 前提：文件解析得出規則列（解析壞掉會讓整組測試變空）', () {
    final parsed = parseDocRules();
    expect(
      parsed.length,
      greaterThan(50),
      reason: '只解析到 ${parsed.length} 列——表格格式可能變了，parser 需同步',
    );
  });

  test('🚨 文件收錄的規則集合 == ReasonType 全集', () {
    final doc = parseDocRules().keys.toSet();
    final codes = ReasonType.values.map((r) => r.code.toUpperCase()).toSet();

    final missing = codes.difference(doc).toList()..sort();
    final phantom = doc.difference(codes).toList()..sort();

    expect(
      missing,
      isEmpty,
      reason:
          '這些規則存在於程式但文件沒收錄，讀者查不到它們代表什麼：$missing\n'
          '請補進 docs/RULE_ENGINE.md 對應的分類表。',
    );
    expect(phantom, isEmpty, reason: '文件寫了不存在的規則（多半是改名後沒同步）：$phantom');
  });

  test('🚨 每列印的設計基準分 == ReasonType.score', () {
    final doc = parseDocRules();
    final byCode = {
      for (final r in ReasonType.values) r.code.toUpperCase(): r.score,
    };

    final wrong = <String>[];
    for (final e in doc.entries) {
      final actual = byCode[e.key];
      if (actual == null) continue; // 幻影由上一條測試負責
      final expected = e.value.bidirectional ? actual.abs() : actual;
      final printed = e.value.score;
      if (printed != expected) {
        wrong.add('${e.key}: 文件 $printed / 程式 $actual');
      }
    }
    expect(
      wrong,
      isEmpty,
      reason:
          '設計基準分與程式不符：$wrong\n'
          '注意這一欄是 hardcoded fallback，不是實際生效分數'
          '（實際值由 calibration 決定，見 docs/CALIBRATION.md）。',
    );
  });
}
