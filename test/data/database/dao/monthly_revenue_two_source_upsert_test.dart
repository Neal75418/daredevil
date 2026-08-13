// 雙來源 upsert 的 ytd 保全(2026-08-13 審查 Critical 1 的回歸測試)
//
// FinMind 歷史路徑不帶 ytd、openapi/MOPS 帶——同一 (symbol, date) 兩種
// 順序都不得讓 ytd 遺失:
// - FinMind 先、MOPS 後:upsert 的 SET 清單漏列時,MOPS 值被靜默丟棄
//   (審查以真 DB 實測抓到——4,025 綠也沒接到這條線)
// - MOPS 先、FinMind 後:直接覆蓋(非 coalesce)會用 NULL 洗掉好值
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/data/database/app_database.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.upsertStocks([
      StockMasterCompanion.insert(symbol: '2330', name: '台積電', market: 'TWSE'),
    ]);
  });

  tearDown(() => db.close());

  MonthlyRevenueCompanion finmindShape() => MonthlyRevenueCompanion.insert(
    symbol: '2330',
    date: DateTime(2026, 7),
    revenueYear: 2026,
    revenueMonth: 7,
    revenue: 250000000,
    momGrowth: const Value(4.17),
    yoyGrowth: const Value(25.0),
    // FinMind 無累計資料——companion 刻意不帶本欄
  );

  MonthlyRevenueCompanion mopsShape() => MonthlyRevenueCompanion.insert(
    symbol: '2330',
    date: DateTime(2026, 7),
    revenueYear: 2026,
    revenueMonth: 7,
    revenue: 250000000,
    momGrowth: const Value(4.17),
    yoyGrowth: const Value(25.0),
    ytdYoyGrowth: const Value(41.87),
  );

  Future<double?> readYtd() async =>
      (await db
              .customSelect(
                "SELECT ytd_yoy_growth FROM monthly_revenue WHERE symbol='2330'",
              )
              .getSingle())
          .readNullable<double>('ytd_yoy_growth');

  test('🚨 FinMind 先、MOPS 後 → ytd 必須寫入', () async {
    await db.insertMonthlyRevenue([finmindShape()]);
    await db.insertMonthlyRevenue([mopsShape()]);
    expect(await readYtd(), closeTo(41.87, 0.001));
  });

  test('🚨 MOPS 先、FinMind 後 → ytd 不得被 NULL 洗掉', () async {
    await db.insertMonthlyRevenue([mopsShape()]);
    await db.insertMonthlyRevenue([finmindShape()]);
    expect(await readYtd(), closeTo(41.87, 0.001));
  });
}
