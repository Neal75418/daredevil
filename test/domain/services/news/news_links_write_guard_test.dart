import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 簡稱比對只供顯示，不得寫入 news_stock_map（評分的輸入）。任何 import
/// 比對器、合併函式或其 provider 的 lib 檔案，都不得出現寫入 news_stock_map
/// 的 API。
void main() {
  test('使用簡稱比對的 lib 檔案不寫 news_stock_map', () {
    const importMarkers = [
      'news/stock_name_matcher.dart',
      'news/news_stock_links.dart',
      'providers/news_link_provider.dart',
    ];
    // 使用比對器的檔案沒有理由碰 news_stock_map：連 drift 的 table 識別字
    // （managers／raw 寫入都會用到）一起擋
    const forbidden = [
      'NewsStockMapCompanion',
      'insertNewsWithMappings',
      'newsStockMap',
    ];

    final users = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      if (f.path.endsWith('.drift.dart')) continue;
      final src = f.readAsStringSync();
      if (!importMarkers.any(src.contains)) continue;
      users.add(f.path);
      for (final word in forbidden) {
        expect(src.contains(word), isFalse, reason: '${f.path} 出現 $word');
      }
    }
    // sanity floor：至少要掃到熱度、快照、新聞頁、個股新聞等使用者，否則是假綠
    expect(users.length, greaterThanOrEqualTo(5), reason: users.join('\n'));
  });
}
