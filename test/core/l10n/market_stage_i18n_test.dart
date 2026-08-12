// 均線位階子狀態四鍵的守門(2026-08-12)
//
// 這些是 hero_index_section 的 inline `.tr()`,不在 `S` class 守門範圍——
// typo 會把原始 key 渲染到大盤總覽的位階 chip 上。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const keys = [
    'neutralReclaim',
    'neutralBreakdown',
    'neutralAboveShort',
    'neutralBelowShort',
  ];

  test('🚨 widget switch 的字面量必須逐一存在於翻譯檔(typo 即紅)', () {
    // 真正的風險在 widget 的 switch 字串打錯——上面的固定清單守不到它。
    // 直接從 source 抽出 'neutralXxx' 字面量,逐一對兩個語系。
    final src = File(
      'lib/presentation/widgets/market_dashboard/hero_index_section.dart',
    ).readAsStringSync();
    final literals = RegExp(
      r"'(neutral\w+)'",
    ).allMatches(src).map((m) => m.group(1)!).toSet();
    expect(literals, isNotEmpty, reason: 'switch 被移除了?守門對象消失');
    for (final locale in ['zh-TW', 'en']) {
      final map =
          jsonDecode(
                File('assets/translations/$locale.json').readAsStringSync(),
              )
              as Map<String, dynamic>;
      final stage =
          (map['marketOverview'] as Map<String, dynamic>)['stage']
              as Map<String, dynamic>;
      for (final k in literals) {
        expect(stage[k], isA<String>(), reason: '$locale 缺 stage.$k');
      }
    }
  });

  for (final locale in ['zh-TW', 'en']) {
    test('$locale 有位階子狀態四鍵', () {
      final map =
          jsonDecode(
                File('assets/translations/$locale.json').readAsStringSync(),
              )
              as Map<String, dynamic>;
      final stage =
          (map['marketOverview'] as Map<String, dynamic>)['stage']
              as Map<String, dynamic>;
      for (final k in keys) {
        expect(
          stage[k],
          isA<String>().having((s) => s.isNotEmpty, 'non-empty', true),
          reason: 'marketOverview.stage.$k 缺失或為空($locale)',
        );
      }
    });
  }
}
