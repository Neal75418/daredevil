// dividend_distribution：一次除權息一列（PK = symbol + 除息日）
//
// 舊表 dividend_history 以 (symbol, year) 為 PK、insertOrReplace 寫入，
// 季配股同一年的多次配息互相覆蓋，只留最後一期。
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/data/database/app_database.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.upsertStocks([
      StockMasterCompanion.insert(symbol: '2330', name: '台積電', market: 'TWSE'),
      StockMasterCompanion.insert(
        symbol: '0056',
        name: '元大高股息',
        market: 'TWSE',
      ),
    ]);
  });

  tearDown(() => db.close());

  DividendDistributionCompanion row(
    String symbol,
    DateTime exDate, {
    double cash = 0,
    double stockPerThousand = 0,
  }) => DividendDistributionCompanion.insert(
    symbol: symbol,
    exDate: exDate,
    cashDividend: cash,
    stockSharesPerThousand: stockPerThousand,
  );

  test('同一年多次配息各自保留（季配不互相覆蓋）', () async {
    await db.upsertDividendDistributions([
      row('2330', DateTime(2025, 3, 18), cash: 4.5),
      row('2330', DateTime(2025, 6, 12), cash: 4.5),
      row('2330', DateTime(2025, 9, 16), cash: 5.0),
      row('2330', DateTime(2025, 12, 11), cash: 5.0),
    ]);

    final rows = await db.getDividendDistributions('2330');
    expect(rows.map((r) => r.cashDividend), [5.0, 5.0, 4.5, 4.5]);
  });

  test('同一除息日重抓：覆蓋為新值，不重複', () async {
    await db.upsertDividendDistributions([
      row('2330', DateTime(2025, 3, 18), cash: 4.5),
    ]);
    await db.upsertDividendDistributions([
      row('2330', DateTime(2025, 3, 18), cash: 4.50002),
    ]);

    final rows = await db.getDividendDistributions('2330');
    expect(rows, hasLength(1));
    expect(rows.single.cashDividend, 4.50002);
  });

  test('單檔查詢依除息日由新到舊，只含該檔', () async {
    await db.upsertDividendDistributions([
      row('2330', DateTime(2024, 6, 13), cash: 3.5),
      row('0056', DateTime(2025, 1, 17), cash: 1.07),
      row('2330', DateTime(2025, 3, 18), cash: 4.5),
    ]);

    final rows = await db.getDividendDistributions('2330');
    expect(rows.map((r) => r.exDate), [
      DateTime(2025, 3, 18),
      DateTime(2024, 6, 13),
    ]);
  });

  test('批次查詢依股票分組、各組由新到舊；空清單回空 map', () async {
    await db.upsertDividendDistributions([
      row('2330', DateTime(2024, 6, 13), cash: 3.5),
      row('0056', DateTime(2025, 1, 17), cash: 1.07),
      row('2330', DateTime(2025, 3, 18), cash: 4.5, stockPerThousand: 0),
      row('0056', DateTime(2024, 10, 16), cash: 1.0),
    ]);

    final map = await db.getDividendDistributionsBatch(['2330', '0056']);
    expect(map.keys.toSet(), {'2330', '0056'});
    expect(map['2330']!.map((r) => r.exDate), [
      DateTime(2025, 3, 18),
      DateTime(2024, 6, 13),
    ]);
    expect(map['0056']!.map((r) => r.exDate), [
      DateTime(2025, 1, 17),
      DateTime(2024, 10, 16),
    ]);
    expect(await db.getDividendDistributionsBatch(const []), isEmpty);
  });
}
