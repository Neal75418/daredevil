import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/presentation/providers/news_provider.dart';
import 'package:daredevil/presentation/providers/providers.dart';
import 'package:daredevil/presentation/providers/stock_news_provider.dart';

/// 簡稱比對的結果只在記憶體：fixture 含「名稱比得到、代號比不到」的標題，
/// 載入後 news_stock_map 的完整集合必須與載入前相同。
void main() {
  test('載入新聞頁與個股新聞不寫入 news_stock_map', () async {
    final db = AppDatabase.forTesting();
    addTearDown(db.close);
    await db.upsertStocks([
      StockMasterCompanion.insert(symbol: '9901', name: '甲乙', market: 'TWSE'),
      StockMasterCompanion.insert(symbol: '9902', name: '丙丁', market: 'TWSE'),
    ]);
    final at = DateTime.now().toUtc().subtract(const Duration(hours: 1));
    await db.insertNewsWithMappings(
      [
        NewsItemCompanion.insert(
          id: 'name-only',
          source: '鉅亨網',
          title: '甲乙營收創新高',
          url: 'https://example.com/1',
          category: 'OTHER',
          publishedAt: at,
        ),
        NewsItemCompanion.insert(
          id: 'code',
          source: '鉅亨網',
          title: '某公司(9902)公告',
          url: 'https://example.com/2',
          category: 'OTHER',
          publishedAt: at,
        ),
      ],
      [NewsStockMapCompanion.insert(newsId: 'code', symbol: '9902')],
    );
    Future<Set<(String, String)>> snapshot() async => {
      for (final r in await db.select(db.newsStockMap).get())
        (r.newsId, r.symbol),
    };
    final before = await snapshot();

    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);
    await container.read(newsProvider.notifier).loadData();
    final s = container.read(newsProvider);
    expect(s.relatedStocksByNewsId['name-only'], ['9901']); // 確實比對到了
    final sub = container.listen(stockNewsProvider('9901'), (_, _) {});
    addTearDown(sub.close);
    final stockNews = await container.read(stockNewsProvider('9901').future);
    expect(stockNews.items.map((n) => n.id), ['name-only']);

    expect(await snapshot(), before);
  });
}
