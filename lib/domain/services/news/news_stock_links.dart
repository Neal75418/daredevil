import 'dart:isolate';

import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/domain/services/news/stock_name_matcher.dart';

/// 新聞的相關股票＝代號對應（news_stock_map）∪ 標題簡稱比對（顯示用）
///
/// 只供顯示：結果不得寫入 news_stock_map（評分的輸入）。
abstract final class NewsStockLinks {
  /// newsId → 相關股票代碼，不重複。順序：代號對應在前（依代號排序），
  /// 簡稱比對在後（依在標題出現的位置）。沒有任何相關股票的新聞不在 map 裡。
  static Map<String, List<String>> merge({
    required List<NewsItemEntry> news,
    required Map<String, List<String>> codeMap,
    required StockNameMatcher matcher,
  }) {
    final result = <String, List<String>>{};
    for (final n in news) {
      final codes = [...?codeMap[n.id]]..sort();
      final seen = <String>{};
      final symbols = [
        for (final s in codes)
          if (seen.add(s)) s,
        for (final s in matcher.matchInOrder(n.title))
          if (seen.add(s)) s,
      ];
      if (symbols.isNotEmpty) result[n.id] = symbols;
    }
    return result;
  }

  /// 同 [merge]，在背景 isolate 計算——新聞頁約 2,000 則時，測試模式量到
  /// 比對要 500 多毫秒，留在主 isolate 會卡畫面。
  ///
  /// 寫成非 async 的 static：送進 isolate 的 closure 只捕捉這三個參數（純資料）。
  static Future<Map<String, List<String>>> mergeInBackground({
    required List<NewsItemEntry> news,
    required Map<String, List<String>> codeMap,
    required StockNameMatcher matcher,
  }) =>
      Isolate.run(() => merge(news: news, codeMap: codeMap, matcher: matcher));
}
