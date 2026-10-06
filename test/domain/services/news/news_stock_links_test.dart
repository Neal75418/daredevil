import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/domain/services/news/news_stock_links.dart';
import 'package:daredevil/domain/services/news/stock_name_matcher.dart';

NewsItemEntry news(String id, String title) => NewsItemEntry(
  id: id,
  source: '鉅亨網',
  title: title,
  url: 'https://example.com/$id',
  category: 'OTHER',
  publishedAt: DateTime(2026, 10, 6, 9),
  fetchedAt: DateTime(2026, 10, 6, 9),
);

StockMasterEntry stock(String symbol, String name) => StockMasterEntry(
  symbol: symbol,
  name: name,
  market: 'TWSE',
  isActive: true,
  updatedAt: DateTime(2026, 10, 6),
);

void main() {
  final matcher = StockNameMatcher.forNewsLinks(
    [stock('9901', '甲乙'), stock('9907', '測試電子')],
    excludedNames: const {},
    nonCompanyPhrases: const {},
    extraAliases: const {},
  );

  Map<String, List<String>> merge(
    List<NewsItemEntry> items, [
    Map<String, List<String>> codeMap = const {},
  ]) => NewsStockLinks.merge(news: items, codeMap: codeMap, matcher: matcher);

  test('代號在前（依代號排序）、簡稱在後（依標題位置）', () {
    // 甲乙出現在前、但掃描順序是測試電子（較長）先
    final r = merge(
      [news('n1', '甲乙與測試電子齊漲')],
      {
        'n1': ['9920', '9910'],
      },
    );
    expect(r['n1'], ['9910', '9920', '9901', '9907']);
  });

  test('代號與名稱都命中同一檔只列一次', () {
    final r = merge(
      [news('n1', '甲乙(9901)營收')],
      {
        'n1': ['9901'],
      },
    );
    expect(r['n1'], ['9901']);
  });

  test('代號對應重複只列一次', () {
    final r = merge(
      [news('n1', '公告')],
      {
        'n1': ['9930', '9930'],
      },
    );
    expect(r['n1'], ['9930']);
  });

  test('只有代號對應（標題沒有名稱）照收', () {
    final r = merge(
      [news('n1', '公告一則')],
      {
        'n1': ['9930'],
      },
    );
    expect(r['n1'], ['9930']);
  });

  test('沒有任何相關股票的新聞不在結果裡', () {
    expect(merge([news('n1', '大盤收高')]).containsKey('n1'), isFalse);
  });

  test('mergeInBackground 在真的背景 isolate 算出與 merge 相同的結果', () async {
    final items = [news('n1', '甲乙與測試電子齊漲'), news('n2', '大盤收高')];
    final codeMap = {
      'n1': ['9910'],
    };
    expect(
      await NewsStockLinks.mergeInBackground(
        news: items,
        codeMap: codeMap,
        matcher: matcher,
      ),
      NewsStockLinks.merge(news: items, codeMap: codeMap, matcher: matcher),
    );
  });
}
