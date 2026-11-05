import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 熱力圖頁與元件畫出來的字都要走翻譯檔（文案守門測試只掃得到翻譯檔）。
/// 去掉 `//` 註解後不得含 CJK 統一表意文字。
void main() {
  test('熱力圖頁與元件沒有寫死的中文', () {
    final files = [
      File('lib/presentation/screens/market/market_heatmap_screen.dart'),
      ...Directory(
        'lib/presentation/widgets/heatmap',
      ).listSync().whereType<File>().where((f) => f.path.endsWith('.dart')),
    ];
    // 下限：路徑寫錯時會掃到 0 個、無聲通過
    expect(files.length, greaterThanOrEqualTo(5));

    final cjk = RegExp(r'[\u4E00-\u9FFF]');
    // 行首或空白後的 // 才是註解（字串裡的 https:// 不算）
    final comment = RegExp(r'(^|\s)//.*$');
    final offenders = <String>[];
    for (final f in files) {
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final code = lines[i].replaceFirst(comment, '');
        if (cjk.hasMatch(code)) offenders.add('${f.path}:${i + 1}');
      }
    }
    expect(offenders, isEmpty, reason: '寫死的中文：$offenders');
  });
}
