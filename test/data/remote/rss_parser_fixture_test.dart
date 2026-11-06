import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:daredevil/data/remote/rss_parser.dart';
import 'package:daredevil/core/utils/device_time.dart';

/// RssParser 對真實 feed 形狀的解析測試(2026-07-30 審查)。
///
/// 之前 RssParser 的 RFC 822/時區/Atom fallback 分支只有 client_close
/// 冒煙測試,格式回歸(媒體改版、CDATA/HTML 包裝、爛日期)無守門。
/// Fixture 仿台灣財經媒體常見形狀:CDATA + HTML 內文、+0800/GMT/EST
/// 時區、兩位數年份、content:encoded 優先序、Atom published→updated
/// fallback、缺 pubDate 的 DeviceTime.now() fallback。
class _MockDio extends Mock implements Dio {}

String _fixture(String name) =>
    File('test/fixtures/remote/$name').readAsStringSync();

void main() {
  const source = NewsFeedSource(
    name: '測試來源',
    url: 'https://news.example.tw/rss',
    category: 'market',
  );

  late _MockDio dio;
  late RssParser parser;

  setUp(() {
    dio = _MockDio();
    parser = RssParser(dio: dio);
  });

  void stubFeed(String fixtureName) {
    when(() => dio.get<dynamic>(any())).thenAnswer(
      (_) async => Response<dynamic>(
        requestOptions: RequestOptions(path: source.url),
        statusCode: 200,
        data: _fixture(fixtureName),
      ),
    );
  }

  group('RSS 2.0 fixture', () {
    test('解析出全部有效項目;缺 link 的跳過', () async {
      stubFeed('rss_20_feed.xml');
      final items = await parser.parseFeed(source);
      // 5 個 item,1 個缺 link → 4 個
      expect(items, hasLength(4));
      expect(items.map((i) => i.title), isNot(contains('缺連結的項目應被跳過')));
    });

    test('+0800 時區換算成 UTC;CDATA/HTML/entities 全剝除', () async {
      stubFeed('rss_20_feed.xml');
      final items = await parser.parseFeed(source);
      final tsmc = items.firstWhere((i) => i.title.contains('2330'));
      // 18:30 +0800 = 10:30 UTC
      expect(tsmc.publishedAt, DateTime.utc(2026, 7, 29, 10, 30));
      expect(tsmc.content, '台積電今日舉行法說會 & 釋出樂觀展望。');
      expect(tsmc.extractStockCodes(), ['2330']);
    });

    test('GMT 時區與 content:encoded 優先序', () async {
      stubFeed('rss_20_feed.xml');
      final items = await parser.parseFeed(source);
      final evergreen = items.firstWhere((i) => i.title.contains('2603'));
      expect(evergreen.publishedAt, DateTime.utc(2026, 7, 29, 6, 0));
      expect(evergreen.content, '貨櫃三雄放量,長榮亮燈漲停。');
    });

    test('兩位數年份 + 具名時區 EST(-5):26→2026、08:15 EST=13:15 UTC', () async {
      stubFeed('rss_20_feed.xml');
      final items = await parser.parseFeed(source);
      final est = items.firstWhere((i) => i.title.contains('EST'));
      expect(est.publishedAt, DateTime.utc(2026, 7, 29, 13, 15, 30));
    });

    test('爛 pubDate:fallback 到 DeviceTime.now()(不丟棄新聞)', () async {
      stubFeed('rss_20_feed.xml');
      final before = DeviceTime.now();
      final items = await parser.parseFeed(source);
      final after = DeviceTime.now();
      final bad = items.firstWhere((i) => i.title.contains('爛日期'));
      // 行為鎖定:解析失敗以「現在」當發布時間。代價是這類新聞會被排序
      // 頂到最前——改行為(如丟棄或 epoch)前先改這條測試。
      expect(bad.publishedAt.isBefore(before), isFalse);
      expect(bad.publishedAt.isAfter(after), isFalse);
    });

    test('id 穩定:同 guid 同 source 產生相同 id', () async {
      stubFeed('rss_20_feed.xml');
      final a = await parser.parseFeed(source);
      final b = await parser.parseFeed(source);
      expect(
        a.firstWhere((i) => i.title.contains('2330')).id,
        b.firstWhere((i) => i.title.contains('2330')).id,
      );
    });
  });

  group('Atom fixture', () {
    test('entry 解析:link href、published 時區、HTML content 剝除', () async {
      stubFeed('atom_feed.xml');
      final items = await parser.parseFeed(source);
      expect(items, hasLength(2));
      final mtk = items.firstWhere((i) => i.title.contains('2454'));
      expect(mtk.url, 'https://atom.example.tw/e/2001');
      // 15:45 +08:00 = 07:45 UTC
      expect(mtk.publishedAt.toUtc(), DateTime.utc(2026, 7, 29, 7, 45));
      expect(mtk.content, '聯發科發表新一代旗艦晶片。');
    });

    test('缺 published 時 fallback 用 updated', () async {
      stubFeed('atom_feed.xml');
      final items = await parser.parseFeed(source);
      final fallback = items.firstWhere((i) => i.title.contains('updated'));
      expect(fallback.publishedAt.toUtc(), DateTime.utc(2026, 7, 28, 9, 30));
    });
  });
}
