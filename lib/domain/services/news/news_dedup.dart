import 'package:daredevil/data/database/app_database.dart';

/// 新聞顯示去重（新聞頁與個股新聞分頁共用）
///
/// 規則：**正規化標題 + 發布日（本地時間）** 分組，保留組內最早發布的那筆
/// （原始媒體優先於聚合轉載）。「同日」約束必要——語料驗證顯示跨天的同標題
/// （如每日期貨行情欄目）是不同新聞，不可合併。僅影響顯示層，DB 與個股
/// 關聯評分不受影響。
abstract final class NewsDedup {
  /// 去重後依發布時間新到舊排序
  static List<NewsItemEntry> sameDayTitle(List<NewsItemEntry> items) {
    final best = <String, NewsItemEntry>{};
    for (final n in items) {
      final day = n.publishedAt.toLocal();
      final key =
          '${day.year}-${day.month}-${day.day}|${_normalizeTitle(n.title)}';
      final current = best[key];
      if (current == null || n.publishedAt.isBefore(current.publishedAt)) {
        best[key] = n;
      }
    }
    return best.values.toList()
      ..sort((a, b) => b.publishedAt.compareTo(a.publishedAt));
  }

  /// 全形/半形空白（`\s` 不保證涵蓋 U+3000，故顯式列入）
  static final RegExp _whitespace = RegExp(r'[\s　]+');

  /// 聚合器品牌化前綴（如 Yahoo 轉載通訊社稿加掛的「【台股盤中】」
  /// 「【盤前焦點】」）——剝除後才能與原始稿合併去重。上限 12 字防
  /// 誤剝正文（語料實測前綴均 ≤ 6 字）。
  static final RegExp _brandPrefix = RegExp(r'^【[^】]{1,12}】');

  /// 標題正規化（僅用於去重 key，顯示仍用原標題）：
  /// 剝【…】前綴 → 全形/半形空白折疊為單一空格
  static String _normalizeTitle(String title) {
    return title
        .replaceFirst(_brandPrefix, '')
        .replaceAll(_whitespace, ' ')
        .trim();
  }
}
