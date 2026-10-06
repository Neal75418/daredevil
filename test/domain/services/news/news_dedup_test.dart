import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/domain/services/news/news_dedup.dart';

import '../../../helpers/time_zone_helpers.dart';

NewsItemEntry item(String id, String title, DateTime publishedAt) =>
    NewsItemEntry(
      id: id,
      source: '鉅亨網',
      title: title,
      url: 'https://example.com/$id',
      category: 'OTHER',
      publishedAt: publishedAt,
      fetchedAt: publishedAt,
    );

void main() {
  test('同日同標題保留最早一筆、結果新到舊', () {
    final r = NewsDedup.sameDayTitle([
      item('late', '同一標題', DateTime(2026, 10, 6, 12)),
      item('early', '同一標題', DateTime(2026, 10, 6, 9)),
      item('other', '另一則', DateTime(2026, 10, 6, 10)),
    ]);
    expect(r.map((n) => n.id), ['other', 'early']);
  });

  test('不同天的同標題都保留', () {
    final r = NewsDedup.sameDayTitle([
      item('d1', '期貨行情', DateTime(2026, 10, 5, 9)),
      item('d2', '期貨行情', DateTime(2026, 10, 6, 9)),
    ]);
    expect(r, hasLength(2));
  });

  test('剝【…】前綴與全形空白後視為同一則', () {
    final r = NewsDedup.sameDayTitle([
      item('a', '【台股盤中】 加權指數　上漲', DateTime(2026, 10, 6, 10)),
      item('b', '加權指數 上漲', DateTime(2026, 10, 6, 9)),
    ]);
    expect(r.map((n) => n.id), ['b']);
  });

  final cross = crossDayLocal(2026, 10, 6);
  test('以本地日期判斷同日（UTC 時間先轉本地）', () {
    // cross 與本地 12:00 同在本地 10/6，但 UTC 日期不同
    final a = item('a', '同一標題', cross!.toUtc());
    final b = item('b', '同一標題', DateTime(2026, 10, 6, 12).toUtc());
    expect(NewsDedup.sameDayTitle([a, b]), hasLength(1));
  }, skip: cross == null ? 'UTC 時區驗不到跨日' : false);
}
