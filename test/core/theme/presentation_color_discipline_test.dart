// presentation 層禁用裸 Colors.green / Colors.red(2026-08-15 審計疫苗)
//
// 紅漲綠跌是本 app 鐵律:綠=下跌。settings 曾把「同步成功」硬編碼
// Colors.green,與全 app「綠=跌」語意相撞(成功語意應走品牌藍
// DesignTokens.successColor)。semantic_colors_test 只掃常數宣告值,
// 抓不到 widget 硬編碼——本測試補上這條防線。
//
// 允許清單:僅收「已文件化的刻意例外」,新增前先讀該檔的設計註解。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 已文件化例外:
/// - event_calendar_provider:EventType 色組有 semantic_colors_test 色相
///   掃描守門+逐色對比實測註解,紅綠在此是除權息/股東會的事件語意
const _allowlist = {'lib/presentation/providers/event_calendar_provider.dart'};

void main() {
  test('presentation 不得裸用 Colors.green/Colors.red(語意走 tokens)', () {
    final violations = <String>[];
    final files = Directory('lib/presentation')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));

    final pattern = RegExp(r'Colors\.(green|red)(Accent)?\b');
    for (final f in files) {
      final rel = f.path.replaceAll(r'\', '/');
      if (_allowlist.contains(rel)) continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (line.trimLeft().startsWith('//')) continue;
        if (pattern.hasMatch(line)) {
          violations.add('$rel:${i + 1}: ${line.trim()}');
        }
      }
    }

    expect(
      violations,
      isEmpty,
      reason:
          '裸 Colors.green/red 撞紅漲綠跌語意。成功→DesignTokens.successColor(theme)、'
          '錯誤/危險→AppTheme.errorColor、警告→DesignTokens.warningColor(theme)。'
          '刻意例外需在檔內文件化並加入本測試允許清單。\n違規:\n${violations.join('\n')}',
    );
  });
}
