// 月營收總覽新增 key 的守門(2026-08-13,同 watchlist_default_group 模式:
// inline .tr() 不在 S-class 掃描範圍,typo 會直接渲染原始 key)
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final locale in ['zh-TW', 'en']) {
    test('$locale 有累計年增三鍵', () {
      final map =
          jsonDecode(
                File('assets/translations/$locale.json').readAsStringSync(),
              )
              as Map<String, dynamic>;
      final ro = map['revenueOverview'] as Map<String, dynamic>;
      expect(ro['ytdShort'], isA<String>());
      expect(ro['lowBase'], isA<String>());
      expect(ro['histogramCaption'], isA<String>());
      expect((ro['sort'] as Map<String, dynamic>)['ytdYoy'], isA<String>());
      // 季報同輪新增的 key 一起守(screen 測試比對原始 key,JSON 缺失照樣綠)
      final qo = map['quarterlyOverview'] as Map<String, dynamic>;
      expect(qo['marginCol'], isA<String>());
      expect(ro['entryUnfiled'], isA<String>());
      expect(qo['entryUnfiled'], isA<String>());
    });
  }
}
