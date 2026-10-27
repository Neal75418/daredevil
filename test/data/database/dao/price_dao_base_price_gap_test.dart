// 每輪摘要計數：「漲跌因為缺平盤價而是空值」的列（除權息漲跌修正 spec 第 3 節）
//
// 上市：收盤非空、漲跌空值（本設計之後上市只有缺平盤價才會這樣）。
// 上櫃：配發表有這檔這天、收盤非空、漲跌空值（只有 FinMind 價格的股票本來
// 就沒有漲跌，所以只數除權息列）。市場依目前的主檔判斷。
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/utils/date_context.dart';
import 'package:daredevil/data/database/app_database.dart';

void main() {
  late AppDatabase db;
  final d1 = DateContext.normalize(DateTime(2025, 9, 9));
  final d2 = DateContext.normalize(DateTime(2026, 9, 16));
  final d3 = DateContext.normalize(DateTime(2026, 10, 22));

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.upsertStocks([
      for (final s in ['9901', '9902', '9903', '9904'])
        StockMasterCompanion.insert(symbol: s, name: s, market: 'TWSE'),
      for (final s in ['9911', '9912'])
        StockMasterCompanion.insert(symbol: s, name: s, market: 'TPEx'),
    ]);
  });

  tearDown(() => db.close());

  DailyPriceCompanion row(
    String symbol,
    DateTime date, {
    double? close,
    double? change,
  }) => DailyPriceCompanion.insert(
    symbol: symbol,
    date: date,
    close: Value(close),
    priceChange: Value(change),
  );

  Future<void> dividend(String symbol, DateTime exDate) =>
      db.upsertDividendDistributions([
        DividendDistributionCompanion.insert(
          symbol: symbol,
          exDate: exDate,
          cashDividend: 1,
          stockSharesPerThousand: 0,
        ),
      ]);

  test('上市：收盤非空、漲跌空值才數；收盤空不數；漲跌 0 不數', () async {
    await db.insertPrices([
      row('9901', d2, close: 10, change: null),
      row('9902', d2, close: null, change: null),
      row('9903', d2, close: 10, change: 0),
    ]);
    final gap = await db.getBasePriceGap();
    expect(gap.twseRows, 1);
    expect(gap.tpexRows, 0);
  });

  test('上櫃：只數配發表有這檔這天的列；只有 FinMind 價格（無配發列）的不數', () async {
    await db.insertPrices([
      row('9911', d2, close: 10, change: null),
      row('9912', d2, close: 10, change: null),
      row('9911', d3, close: 10, change: null),
    ]);
    await dividend('9911', d2);
    final gap = await db.getBasePriceGap();
    expect(gap.tpexRows, 1);
    expect(gap.twseRows, 0);
  });

  test('轉市場（主檔上市、資料是上櫃的文字標記列）算在上市', () async {
    await db.insertPrices([row('9904', d1, close: 41.45, change: null)]);
    await dividend('9904', d1);
    final gap = await db.getBasePriceGap();
    expect((gap.twseRows, gap.tpexRows), (1, 0));
  });

  test('earliest／latest 跨兩市場；全 0 時都 null', () async {
    expect(await db.getBasePriceGap(), (
      twseRows: 0,
      tpexRows: 0,
      earliest: null,
      latest: null,
    ));
    // 兩個極值分屬兩個市場（上市最早、上櫃最近），先到先贏／只取單一市場的
    // 寫法都會紅；GROUP BY 的輸出順序是 TPEx 先、TWSE 後
    await db.insertPrices([
      row('9901', d1, close: 10, change: null),
      row('9911', d2, close: 10, change: null),
      row('9911', d3, close: 10, change: null),
      row('9912', d3, close: 10, change: null), // 無配發列，不數也不影響日期
    ]);
    await dividend('9911', d2);
    await dividend('9911', d3);
    final gap = await db.getBasePriceGap();
    expect((gap.twseRows, gap.tpexRows), (1, 2));
    expect(gap.earliest, d1);
    expect(gap.latest, d3);
  });

  test(
    'earliest／latest 鏡像：上櫃最早、上市最近（釘住 latest 的先到先贏與 earliest 的後到覆蓋）',
    () async {
      await db.insertPrices([
        row('9901', d3, close: 10, change: null),
        row('9911', d1, close: 10, change: null),
        row('9911', d2, close: 10, change: null),
      ]);
      await dividend('9911', d1);
      await dividend('9911', d2);
      final gap = await db.getBasePriceGap();
      expect((gap.twseRows, gap.tpexRows), (1, 2));
      expect(gap.earliest, d1);
      expect(gap.latest, d3);
    },
  );
}
