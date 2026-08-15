// 外資持股歷史回補(2026-08-16)
//
// 接上 MI_QFIIS 全市場同步之後,新覆蓋的 262 檔上市股只有「當日」一筆。
// 但 FOREIGN_SHAREHOLDING_INCREASING / DECREASING 讀的是**變化量**
// (`foreignShareholdingLookbackDays = 5` 個交易日前的水位差),所以在
// 累積滿 5 個交易日之前,那些股票的變化量規則仍然不會觸發——覆蓋補上了、
// 訊號還是沒有,只是換個原因沉默。
//
// MI_QFIIS 支援歷史日期(2026-08-16 實測 7/15 回 1,351 筆),所以回補幾次
// 呼叫就能讓規則立刻全面生效,不必等一週。
//
// **設計**:只補「缺的交易日」,已有資料的日子跳過——回補要能重跑、
// 不能每次都把整個窗口重打一遍(那是本專案回補迴圈收斂設計的第一條)。
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/data/models/twse/models.dart';
import 'package:daredevil/data/remote/finmind_client.dart';
import 'package:daredevil/data/remote/twse_client.dart';
import 'package:daredevil/data/repositories/shareholding_repository.dart';

class MockTwseClient extends Mock implements TwseClient {}

class MockFinMindClient extends Mock implements FinMindClient {}

void main() {
  late AppDatabase db;
  late MockTwseClient twse;
  late ShareholdingRepository repo;

  // 2026-08-14 為週五;往前的交易日:8/13、8/12、8/11、8/08、8/07
  final asOf = DateTime.utc(2026, 8, 14);

  setUp(() async {
    db = AppDatabase.forTesting();
    twse = MockTwseClient();
    repo = ShareholdingRepository(
      database: db,
      finMindClient: MockFinMindClient(),
      twseClient: twse,
    );
    await db.upsertStocks([
      StockMasterCompanion.insert(symbol: '2330', name: '台積電', market: 'TWSE'),
    ]);
    // 任何日期都回一筆,日期由參數決定(模擬 API 的實際行為)
    when(
      () => twse.getAllForeignShareholding(date: any(named: 'date')),
    ).thenAnswer((inv) async {
      final d = inv.namedArguments[#date] as DateTime;
      return [
        TwseForeignShareholding(
          symbol: '2330',
          date: d,
          foreignSharesRatio: 69.0,
          sharesIssued: 1000,
          foreignRemainingShares: 500,
          foreignUpperLimitRatio: 100,
        ),
      ];
    });
  });
  tearDown(() async => db.close());

  Future<int> storedDays() async {
    final r = await db
        .customSelect('SELECT COUNT(DISTINCT date) c FROM shareholding')
        .getSingle();
    return r.read<int>('c');
  }

  test('🚨 回補讓變化量規則不必等一週才生效', () async {
    final filled = await repo.backfillForeignShareholding(asOf: asOf, days: 5);

    expect(filled, greaterThanOrEqualTo(5), reason: '5 個交易日都要補到');
    expect(await storedDays(), greaterThanOrEqualTo(5));
  });

  test('🚨 已有資料的日子不重打(回補要能重跑)', () async {
    await repo.backfillForeignShareholding(asOf: asOf, days: 5);
    final callsAfterFirst = verify(
      () => twse.getAllForeignShareholding(date: any(named: 'date')),
    ).callCount;

    final second = await repo.backfillForeignShareholding(asOf: asOf, days: 5);
    expect(second, 0, reason: '第二次應該全部跳過');
    verifyNever(() => twse.getAllForeignShareholding(date: any(named: 'date')));
    expect(callsAfterFirst, greaterThan(0));
  });

  test('只補交易日,不打週末', () async {
    await repo.backfillForeignShareholding(asOf: asOf, days: 5);
    final rows = await db
        .customSelect('SELECT DISTINCT date FROM shareholding')
        .get();
    for (final r in rows) {
      final d = DateTime.parse(r.read<String>('date').substring(0, 10));
      expect(
        d.weekday,
        lessThanOrEqualTo(DateTime.friday),
        reason: '$d 是週末,不該有資料',
      );
    }
  });

  test('單日失敗不中斷其餘日子', () async {
    var calls = 0;
    when(
      () => twse.getAllForeignShareholding(date: any(named: 'date')),
    ).thenAnswer((inv) async {
      calls++;
      if (calls == 2) throw Exception('模擬單日失敗');
      final d = inv.namedArguments[#date] as DateTime;
      return [
        TwseForeignShareholding(
          symbol: '2330',
          date: d,
          foreignSharesRatio: 69.0,
        ),
      ];
    });

    final filled = await repo.backfillForeignShareholding(asOf: asOf, days: 5);
    expect(filled, greaterThanOrEqualTo(4), reason: '只有一天該失敗');
  });

  test('🚨 當日已有「零星資料」仍要補齊全市場(實機才暴露的坑)', () async {
    // 正式 DB 實測:8/13 只有 213 筆(FinMind 逐檔的零星結果),而全市場
    // 應有 1,200+ 筆。若新鮮度檢查只看「有沒有列」,這種半殘的日子會被
    // 永遠跳過 —— 覆蓋看起來補了,實際上那天還是缺一千多檔。
    await db.upsertStocks([
      for (var i = 0; i < 40; i++)
        StockMasterCompanion.insert(
          symbol: '${2000 + i}',
          name: 'T$i',
          market: 'TWSE',
        ),
    ]);
    // 先塞一筆 8/14 的零星資料
    await db.insertShareholdingData([
      ShareholdingCompanion.insert(
        symbol: '2330',
        date: asOf,
        foreignSharesRatio: const Value(1.0),
      ),
    ]);

    when(
      () => twse.getAllForeignShareholding(date: any(named: 'date')),
    ).thenAnswer((inv) async {
      final d = inv.namedArguments[#date] as DateTime;
      return [
        for (var i = 0; i < 40; i++)
          TwseForeignShareholding(
            symbol: '${2000 + i}',
            date: d,
            foreignSharesRatio: 50.0,
          ),
      ];
    });

    final filled = await repo.backfillForeignShareholding(asOf: asOf, days: 1);
    expect(filled, 1, reason: '零星資料不算完整,該日必須重抓');
    final c = await db
        .customSelect('SELECT COUNT(*) c FROM shareholding')
        .getSingle();
    expect(c.read<int>('c'), greaterThan(1), reason: '全市場都要寫進去');
  });
}
