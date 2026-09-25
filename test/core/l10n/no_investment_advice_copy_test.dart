import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 文案守門：App 只呈現「發生了什麼」，不給操作指示。
///
/// 投信投顧法第 4 條：對個股提供分析意見或推介建議並取得報酬即屬投顧
/// 業務；主管機關問答集舉「買賣價位、支撐壓力、停損停利」為軟體可能涉及
/// 的例子。免費時風險低，但任何收費或廣告都會讓這些字眼變成法律風險。
/// 2026-09 已把「今日推薦／強烈推薦／可考慮分批進場／停利至壓力、停損至
/// 支撐／建議觀望」改為中性描述；這裡防止寫回來。「AI」同理：摘要是規則
/// 模板，不是模型產生的，標 AI 會抬高使用者對可信度的預期。
void main() {
  const forbidden = [
    '推薦',
    '進場',
    '買點',
    '停利',
    '停損',
    '分批',
    '建議觀望',
    '建議等待',
    '建議留意',
    '機會',
    '有利',
    '值得',
    '追高',
    '接刀',
    'AI',
  ];

  /// 英文同一類措辭（不分大小寫、字邊界）。刻意不禁 "buy"／"sell"：
  /// 交易紀錄的「買進／賣出」與法人「買賣超」是正當描述。
  final forbiddenEn = RegExp(
    r'\brecommend|\bpicks?\b|\bentry\b|buy[- ]the[- ]dip|dip[- ]buying|'
    r'scal(e|ing) in|stop[- ]?loss|take[- ]profit|\bAI\b|opportunit|'
    r'favorable|worth (watching|prioritizing)|\bchas(e[sd]?|ing)\b',
    caseSensitive: false,
  );

  /// 放行清單：key 前綴 → 理由。新增前先想清楚是不是描述而非指示。
  const allowed = {'disclaimer.': '免責聲明本身要寫「不構成投資建議／not recommendations」'};
  bool isAllowed(String key) => allowed.keys.any(key.startsWith);

  Iterable<MapEntry<String, String>> flatten(
    Object? node, [
    String path = '',
  ]) sync* {
    if (node is Map<String, dynamic>) {
      for (final e in node.entries) {
        yield* flatten(e.value, path.isEmpty ? e.key : '$path.${e.key}');
      }
    } else if (node is String) {
      yield MapEntry(path, node);
    }
  }

  test('zh-TW 文案不含操作建議字眼', () {
    final zh = json.decode(
      File('assets/translations/zh-TW.json').readAsStringSync(),
    );
    final entries = flatten(zh).toList();
    expect(entries.length, greaterThan(1000), reason: '抽取失敗=路徑或結構壞了');

    final hits = [
      for (final e in entries)
        if (!isAllowed(e.key))
          for (final word in forbidden)
            if (e.value.contains(word)) '${e.key}: 「$word」 in ${e.value}',
    ];
    expect(hits, isEmpty);
  });

  // 英文曾漏改：模式標籤 "Entry"（中文「起漲候選」）、"worth prioritizing"
  test('en 文案不含操作建議字眼', () {
    final en = json.decode(
      File('assets/translations/en.json').readAsStringSync(),
    );
    final entries = flatten(en).toList();
    expect(entries.length, greaterThan(1000), reason: '抽取失敗=路徑或結構壞了');

    final hits = [
      for (final e in entries)
        if (!isAllowed(e.key) && forbiddenEn.hasMatch(e.value))
          '${e.key}: ${e.value}',
    ];
    expect(hits, isEmpty);
  });
}
