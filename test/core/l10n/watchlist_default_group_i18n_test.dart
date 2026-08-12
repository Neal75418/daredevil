// 預設分組三個 i18n key 的守門(2026-08-12)
//
// `app_strings_keys_test` 只掃 `S` class 註冊的 key;這三個是
// `watchlist_group_sheets.dart` 的 inline `.tr()`,typo 不會被抓——
// 會直接把原始 key 字串渲染到畫面上。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const keys = ['setDefaultGroup', 'unsetDefaultGroup', 'defaultGroupHint'];

  for (final locale in ['zh-TW', 'en']) {
    test('$locale 有預設分組三鍵', () {
      final map =
          jsonDecode(
                File('assets/translations/$locale.json').readAsStringSync(),
              )
              as Map<String, dynamic>;
      final watchlist = map['watchlist'] as Map<String, dynamic>;
      for (final k in keys) {
        expect(
          watchlist[k],
          isA<String>().having((s) => s.isNotEmpty, 'non-empty', true),
          reason: 'watchlist.$k 缺失或為空($locale)',
        );
      }
    });
  }
}
