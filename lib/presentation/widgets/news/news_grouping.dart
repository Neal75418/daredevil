import 'package:daredevil/core/l10n/app_strings.dart';
import 'package:daredevil/core/utils/date_context.dart';
import 'package:daredevil/data/database/app_database.dart';

/// 一個帶標題的新聞段落
typedef NewsSection = ({String title, List<NewsItemEntry> items});

/// 新聞頁的三段分組：今天／昨天／更早（本地日期）；空的段落不出現
List<NewsSection> groupNewsTodayYesterdayEarlier(
  List<NewsItemEntry> news,
  DateTime now,
) {
  final today = DateContext.normalize(now);
  final yesterday = today.subtract(const Duration(days: 1));
  final todayNews = <NewsItemEntry>[];
  final yesterdayNews = <NewsItemEntry>[];
  final earlierNews = <NewsItemEntry>[];
  for (final item in news) {
    final day = _localDay(item.publishedAt);
    if (day == today) {
      todayNews.add(item);
    } else if (day == yesterday) {
      yesterdayNews.add(item);
    } else {
      earlierNews.add(item);
    }
  }
  return [
    if (todayNews.isNotEmpty) (title: S.newsToday, items: todayNews),
    if (yesterdayNews.isNotEmpty)
      (title: S.newsYesterday, items: yesterdayNews),
    if (earlierNews.isNotEmpty) (title: S.newsEarlier, items: earlierNews),
  ];
}

/// 個股新聞的逐日分組（本地日期）：今天、昨天標字加日期，其他日期 M/d。
/// [news] 須已依時間新到舊排序
List<NewsSection> groupNewsByDay(List<NewsItemEntry> news, DateTime now) {
  final today = DateContext.normalize(now);
  final yesterday = today.subtract(const Duration(days: 1));
  final sections = <NewsSection>[];
  DateTime? currentDay;
  for (final item in news) {
    final day = _localDay(item.publishedAt);
    if (day != currentDay) {
      currentDay = day;
      final md = '${day.month}/${day.day}';
      final title = day == today
          ? '${S.newsToday} $md'
          : day == yesterday
          ? '${S.newsYesterday} $md'
          : md;
      sections.add((title: title, items: <NewsItemEntry>[]));
    }
    sections.last.items.add(item);
  }
  return sections;
}

/// 預覽的完整時間（本地時間）
String formatNewsFullTime(DateTime publishedAt) {
  final dt = publishedAt.toLocal();
  return '${dt.year}/${dt.month}/${dt.day} '
      '${dt.hour.toString().padLeft(2, '0')}:'
      '${dt.minute.toString().padLeft(2, '0')}';
}

DateTime _localDay(DateTime at) {
  final local = at.toLocal();
  return DateTime(local.year, local.month, local.day);
}
