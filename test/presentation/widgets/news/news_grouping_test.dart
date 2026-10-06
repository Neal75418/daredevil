import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/presentation/widgets/news/news_grouping.dart';

import '../../../helpers/time_zone_helpers.dart';
import '../../../helpers/widget_test_helpers.dart';

NewsItemEntry item(String id, DateTime at) => NewsItemEntry(
  id: id,
  source: '鉅亨網',
  title: id,
  url: 'https://example.com/$id',
  category: 'OTHER',
  publishedAt: at,
  fetchedAt: at,
);

void main() {
  setUpAll(() async => setupTestLocalization());

  final now = DateTime(2026, 10, 6, 15);

  test('三段分組：今天／昨天／更早（空的段落不出現）', () {
    final r = groupNewsTodayYesterdayEarlier([
      item('t', DateTime(2026, 10, 6, 9)),
      item('e', DateTime(2026, 10, 1, 9)),
    ], now);
    expect(r.map((s) => s.items.single.id), ['t', 'e']);
    expect(r.first.title, 'news.today');
    expect(r.last.title, 'news.earlier');
  });

  test('逐日分組：今天、昨天標字，其他日期 M/d', () {
    final r = groupNewsByDay([
      item('a', DateTime(2026, 10, 6, 9)),
      item('b', DateTime(2026, 10, 5, 9)),
      item('c', DateTime(2026, 10, 3, 9)),
      item('d', DateTime(2026, 10, 3, 8)),
    ], now);
    expect(r.map((s) => s.title), [
      'news.today 10/6',
      'news.yesterday 10/5',
      '10/3',
    ]);
    expect(r.last.items.map((n) => n.id), ['c', 'd']);
  });

  final cross = crossDayLocal(2026, 10, 6); // 本地 10/6、UTC 不同日的時刻

  test('分組用本地日期（UTC 時間先轉本地）', () {
    final r = groupNewsByDay([item('x', cross!.toUtc())], now);
    expect(r.single.title, 'news.today 10/6');
    final r3 = groupNewsTodayYesterdayEarlier([item('x', cross.toUtc())], now);
    expect(r3.single.title, 'news.today');
  }, skip: cross == null ? 'UTC 時區驗不到跨日' : false);

  test('預覽完整時間用本地時間', () {
    String two(int v) => v.toString().padLeft(2, '0');
    expect(
      formatNewsFullTime(cross!.toUtc()),
      '2026/10/6 ${two(cross.hour)}:${two(cross.minute)}',
    );
  }, skip: cross == null ? 'UTC 時區驗不到時差' : false);
}
