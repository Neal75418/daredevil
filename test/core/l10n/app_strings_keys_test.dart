import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 結構守門(2026-08-01 全專案 smell 掃描):S(app_strings)註冊的每個
/// i18n key 必須存在於 zh-TW 與 en 兩個語系檔。
///
/// 動機:'watchlist.removeFailed' 曾被兩個畫面引用卻從未加進任何語系檔
/// ——easy_localization 的 fallback 是把 key 原字串畫在畫面上,兩個語系
/// 的用戶都看到 "watchlist.removeFailed" 字面。copy 層守門讓這類洞在
/// 測試就炸,不用等實機。
void main() {
  Map<String, dynamic> loadLocale(String name) =>
      json.decode(File('assets/translations/$name.json').readAsStringSync())
          as Map<String, dynamic>;

  bool hasKey(Map<String, dynamic> root, String dotted) {
    dynamic node = root;
    for (final part in dotted.split('.')) {
      if (node is! Map<String, dynamic> || !node.containsKey(part)) {
        return false;
      }
      node = node[part];
    }
    return true;
  }

  final literalKey = RegExp(
    r"'([a-z][a-zA-Z0-9]*(?:\.[a-zA-Z0-9]+)+)'\s*\.tr\(",
  );

  void expectAllKeysExist(Set<String> keys) {
    for (final locale in ['zh-TW', 'en']) {
      final root = loadLocale(locale);
      final missing = keys.where((k) => !hasKey(root, k)).toList()..sort();
      expect(
        missing,
        isEmpty,
        reason: '$locale.json 缺 key(畫面會直接顯示 key 原字串): $missing',
      );
    }
  }

  test('S 註冊的每個 key 都存在於 zh-TW 與 en', () {
    final source = File('lib/core/l10n/app_strings.dart').readAsStringSync();
    final keys = literalKey.allMatches(source).map((m) => m.group(1)!).toSet();
    expect(keys, isNotEmpty, reason: '抽取失敗=regex 壞了,不是真的沒 key');
    expectAllKeysExist(keys);
  });

  // 只掃 S 不夠:lib/ 裡另有近千處直接 'key'.tr()。行事曆刪除後的
  // 「復原」按鈕引用不存在的 'common.undo',兩個語系都顯示 key 字面。
  test('lib/ 裡每個字面 key 的 .tr() 都存在於 zh-TW 與 en', () {
    final keys = <String>{};
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      keys.addAll(
        literalKey.allMatches(f.readAsStringSync()).map((m) => m.group(1)!),
      );
    }
    expect(keys.length, greaterThan(500), reason: '抽取量過少=regex 或路徑壞了');
    expectAllKeysExist(keys);
  });
}
