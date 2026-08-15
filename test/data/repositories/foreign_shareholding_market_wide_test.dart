// 全市場外資持股同步(2026-08-16)
//
// 補的缺口:上市外資持股原本只靠 FinMind 逐檔,而 update_service 只同步
// 「自選 + 熱門」約 48 檔。2026-08-14 實測上市候選 344 檔僅 82 檔有資料
// (24%),上櫃因有輪替機制是 116/116(100%)——結果上櫃股拿到外資加分
// 的機會是上市股的 4 倍,那是資料缺口不是市場事實。
//
// MI_QFIIS 一次回全市場 1,359 筆、免費、支援歷史日期,與當沖/融資融券
// 同屬「免費批次 API」那一層。
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

  final date = DateTime.utc(2026, 8, 14);

  TwseForeignShareholding row(String symbol, double ratio) =>
      TwseForeignShareholding(
        symbol: symbol,
        date: date,
        sharesIssued: 1000000,
        foreignRemainingShares: 500000,
        foreignSharesRatio: ratio,
        foreignUpperLimitRatio: 100,
      );

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
      StockMasterCompanion.insert(symbol: '2317', name: '鴻海', market: 'TWSE'),
    ]);
  });
  tearDown(() async => db.close());

  test('全市場寫入,回傳筆數', () async {
    when(
      () => twse.getAllForeignShareholding(date: any(named: 'date')),
    ).thenAnswer((_) async => [row('2330', 69.17), row('2317', 40.69)]);

    expect(await repo.syncAllMarketShareholding(date: date), 2);

    final rows = await db
        .customSelect('SELECT symbol, foreign_shares_ratio r FROM shareholding')
        .get();
    expect(rows, hasLength(2));
    expect(
      rows
          .firstWhere((e) => e.read<String>('symbol') == '2330')
          .read<double>('r'),
      69.17,
    );
  });

  test('🚨 stock_master 沒有的代號要濾掉(FK constraint)', () async {
    // MI_QFIIS 含 ETF 與剛上市未進 master 的標的,直接寫會炸 FK
    when(
      () => twse.getAllForeignShareholding(date: any(named: 'date')),
    ).thenAnswer(
      (_) async => [row('2330', 69.17), row('00400A', 5.13), row('9999', 1.0)],
    );

    expect(await repo.syncAllMarketShareholding(date: date), 1);
    final rows = await db.customSelect('SELECT * FROM shareholding').get();
    expect(rows, hasLength(1));
  });

  test('API 回空清單不寫入也不拋例外', () async {
    when(
      () => twse.getAllForeignShareholding(date: any(named: 'date')),
    ).thenAnswer((_) async => []);
    expect(await repo.syncAllMarketShareholding(date: date), 0);
  });

  test('🚨 已有當日資料時預設跳過,force 則覆蓋', () async {
    when(
      () => twse.getAllForeignShareholding(date: any(named: 'date')),
    ).thenAnswer((_) async => [row('2330', 69.17)]);
    await repo.syncAllMarketShareholding(date: date);

    // 第二次:資料已存在
    when(
      () => twse.getAllForeignShareholding(date: any(named: 'date')),
    ).thenAnswer((_) async => [row('2330', 88.88)]);

    expect(
      await repo.syncAllMarketShareholding(date: date),
      0,
      reason: '新鮮度檢查',
    );
    var r = await db
        .customSelect(
          "SELECT foreign_shares_ratio r FROM shareholding WHERE symbol='2330'",
        )
        .getSingle();
    expect(r.read<double>('r'), 69.17, reason: '沒 force 不該被覆蓋');

    expect(await repo.syncAllMarketShareholding(date: date, force: true), 1);
    r = await db
        .customSelect(
          "SELECT foreign_shares_ratio r FROM shareholding WHERE symbol='2330'",
        )
        .getSingle();
    expect(r.read<double>('r'), 88.88, reason: 'force 必須真的重抓並覆蓋');
  });
}
