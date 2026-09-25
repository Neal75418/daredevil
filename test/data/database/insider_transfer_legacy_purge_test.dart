// 舊解析規則寫入的「兩種方式擠在同一格」列（2026-09-26 前）股數不可信：
// 3189／3532 兩個數字被接成一個（80000008000000）、2442 以空格相隔解析失敗
// 存成 0。官方只給當日快照、這些舊申報不會再被重抓覆寫，個股詳情的內部人
// 分頁又不限日期——不清就永遠顯示錯的股數。新規則寫入的同類列（以總股數
// 為準）是對的，不能一起刪：以修正生效日切開。
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/data/database/app_database.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.upsertStocks([
      StockMasterCompanion.insert(symbol: '3189', name: '景碩', market: 'TWSE'),
      StockMasterCompanion.insert(symbol: '2442', name: '新美齊', market: 'TWSE'),
      StockMasterCompanion.insert(symbol: '2892', name: '第一金', market: 'TWSE'),
    ]);
  });
  tearDown(() async => db.close());

  final cutoff = DateTime(2026, 9, 26);

  InsiderTransferCompanion row(
    String symbol,
    DateTime date,
    String method,
    int shares,
  ) => InsiderTransferCompanion.insert(
    symbol: symbol,
    reportDate: date,
    identity: '大股東本人',
    name: '某某',
    transferMethod: method,
    transferShares: shares,
    currentHolding: 67037104,
  );

  Future<List<String>> remaining() async =>
      (await db
              .customSelect(
                'SELECT symbol, transfer_method FROM insider_transfer '
                'ORDER BY symbol, report_date',
              )
              .get())
          .map(
            (r) =>
                '${r.read<String>('symbol')}|${r.read<String>('transfer_method')}',
          )
          .toList();

  test('刪除修正前的多方式列；保留單一方式列與修正後的多方式列', () async {
    await db.insertInsiderTransfers([
      // 舊規則的受害者：數字被接起來
      row(
        '3189',
        DateTime(2026, 8, 28),
        '一般交易(每日得轉讓股數限制)鉅額逐筆交易',
        80000008000000,
      ),
      // 舊規則的受害者：空格相隔解析失敗成 0
      row('2442', DateTime(2026, 8, 18), '一般交易(每日得轉讓股數限制) 盤後定價交易', 0),
      // 單一方式：舊規則讀得對
      row('2892', DateTime(2026, 9, 25), '一般交易(每日得轉讓股數限制)', 259000),
      // 修正生效後寫入的多方式列：新規則以總股數為準，是對的
      row('3189', cutoff, '一般交易(每日得轉讓股數限制)鉅額逐筆交易', 16000000),
    ]);

    final deleted = await db.deleteLegacyMultiMethodInsiderTransfers(
      before: cutoff,
    );

    expect(deleted, 2);
    expect(await remaining(), [
      '2892|一般交易(每日得轉讓股數限制)',
      '3189|一般交易(每日得轉讓股數限制)鉅額逐筆交易',
    ]);
  });

  test('重複執行不再刪任何列（每次同步都跑、冪等）', () async {
    await db.insertInsiderTransfers([
      row(
        '3189',
        DateTime(2026, 8, 28),
        '一般交易(每日得轉讓股數限制)鉅額逐筆交易',
        80000008000000,
      ),
    ]);
    await db.deleteLegacyMultiMethodInsiderTransfers(before: cutoff);
    expect(await db.deleteLegacyMultiMethodInsiderTransfers(before: cutoff), 0);
  });
}
