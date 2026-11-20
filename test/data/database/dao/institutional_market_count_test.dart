import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/constants/market_codes.dart';
import 'package:daredevil/data/database/app_database.dart';

/// 依市場計數某日的法人列（收盤摘要判斷「哪個市場的法人到了沒」用）
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting());
  tearDown(() => db.close());

  final day = DateTime(2026, 11, 19);
  final prevDay = DateTime(2026, 11, 18);

  Future<void> seed() async {
    await db.upsertStocks([
      StockMasterCompanion.insert(symbol: '2330', name: '台積電', market: 'TWSE'),
      StockMasterCompanion.insert(symbol: '2317', name: '鴻海', market: 'TWSE'),
      StockMasterCompanion.insert(symbol: '6488', name: '環球晶', market: 'TPEx'),
      StockMasterCompanion.insert(symbol: '8299', name: '群聯', market: 'TPEx'),
    ]);
    await db.insertInstitutionalData([
      for (final s in ['2330', '2317', '6488'])
        DailyInstitutionalCompanion.insert(
          symbol: s,
          date: day,
          foreignNet: const Value(1),
        ),
      DailyInstitutionalCompanion.insert(
        symbol: '8299',
        date: prevDay,
        foreignNet: const Value(1),
      ),
    ]);
  }

  test('依 stock_master.market 分市場計數當天的列，前一天的不算', () async {
    await seed();
    expect(await db.countInstitutionalInDayAndMarket(day, MarketCode.twse), 2);
    expect(await db.countInstitutionalInDayAndMarket(day, MarketCode.tpex), 1);
    expect(
      await db.countInstitutionalInDayAndMarket(prevDay, MarketCode.twse),
      0,
    );
  });

  test('日期帶時間分量的列也算在當天', () async {
    await seed();
    await db.insertInstitutionalData([
      DailyInstitutionalCompanion.insert(
        symbol: '8299',
        date: day.add(const Duration(hours: 8)),
        foreignNet: const Value(1),
      ),
    ]);
    expect(await db.countInstitutionalInDayAndMarket(day, MarketCode.tpex), 2);
  });
}
