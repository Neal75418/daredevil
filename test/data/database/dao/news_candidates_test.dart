import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/data/database/app_database.dart';

void main() {
  late AppDatabase db;
  final since = DateTime.utc(2026, 9, 6, 13);

  NewsItemCompanion row(String id, String title, DateTime at) =>
      NewsItemCompanion.insert(
        id: id,
        source: '鉅亨網',
        title: title,
        url: 'https://example.com/$id',
        category: 'OTHER',
        publishedAt: at,
      );

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.upsertStocks([
      StockMasterCompanion.insert(symbol: '9901', name: '甲乙', market: 'TWSE'),
      StockMasterCompanion.insert(symbol: '9909', name: 'ABC', market: 'TWSE'),
    ]);
    await db.insertNewsWithMappings(
      [
        row('in-name', '甲乙營收創新高', since.add(const Duration(hours: 1))),
        row('in-code', '某公司(9901)公告', since.add(const Duration(hours: 2))),
        row('edge', '甲乙剛好在界線', since),
        row('old', '甲乙舊聞', since.subtract(const Duration(minutes: 1))),
        row('other', '丙丁營收', since.add(const Duration(hours: 3))),
        row('lower', 'abc 新產品', since.add(const Duration(hours: 4))),
      ],
      [NewsStockMapCompanion.insert(newsId: 'in-code', symbol: '9901')],
    );
  });

  tearDown(() => db.close());

  Future<List<String>> ids(
    String symbol,
    List<String> names,
    DateTime s,
  ) async => [
    for (final n in await db.getNewsCandidatesForStock(
      symbol: symbol,
      names: names,
      since: s,
    ))
      n.id,
  ];

  test('代號對應或標題含名稱、截止點含當下、新到舊', () async {
    expect(await ids('9901', ['甲乙'], since), ['in-code', 'in-name', 'edge']);
  });

  test('截止點傳本地或 UTC 時間結果相同（drift 以 julianday 比較）', () async {
    expect(await ids('9901', ['甲乙'], since.toLocal()), [
      'in-code',
      'in-name',
      'edge',
    ]);
  });

  test('沒有名稱時只回代號對應', () async {
    expect(await ids('9901', const [], since), ['in-code']);
  });

  test('標題比對分大小寫、不吃萬用字元（instr，不是 LIKE）', () async {
    expect(await ids('9909', ['ABC'], since), isEmpty);
    expect(await ids('9909', ['%'], since), isEmpty);
  });
}
