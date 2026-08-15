// 官方權威範圍的存活檔數(2026-08-15)
//
// 用途:`syncStockList` 判斷「這次抓到的官方名冊是否相對於既有規模異常
// 縮水」。sanity floor 是絕對下限,擋的是災難性的部分回應;但 floor 通過
// 之後仍可能缺漏(api_config 註解自承「1000 縮盲區至 ~93 檔」),那段盲區
// 目前只靠價格步被動救回。要偵測它就得跟**上一輪的既有規模**比,而 DB
// 本身就是上一輪的結果——不必另外存 state。
//
// 範圍必須與 stock_repository 的 `inOfficialUniverse` 完全一致:
// TWSE + 4 碼 + 非 00 開頭(ETF/上櫃不在官方公司名單範圍內)。
// 兩邊算的若不是同一個母體,比例比較就沒有意義。
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/data/database/app_database.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting());
  tearDown(() async => db.close());

  test('只算 TWSE 四碼非 ETF 的存活股', () async {
    await db.upsertStocks([
      StockMasterCompanion.insert(symbol: '2330', name: '台積電', market: 'TWSE'),
      StockMasterCompanion.insert(symbol: '2317', name: '鴻海', market: 'TWSE'),
      // 以下都不該計入
      StockMasterCompanion.insert(
        symbol: '0050',
        name: '元大台灣50',
        market: 'TWSE',
      ),
      StockMasterCompanion.insert(
        symbol: '00878',
        name: '國泰永續',
        market: 'TWSE',
      ),
      StockMasterCompanion.insert(symbol: '6423', name: '億而得', market: 'TPEx'),
      StockMasterCompanion.insert(symbol: '91021', name: 'DR股', market: 'TWSE'),
    ]);
    expect(await db.countActiveOfficialUniverse(), 2);
  });

  test('🚨 已下市的不計入——否則基準永遠不會縮,相對比較就失效', () async {
    await db.upsertStocks([
      StockMasterCompanion.insert(symbol: '2330', name: '台積電', market: 'TWSE'),
      StockMasterCompanion.insert(symbol: '1606', name: '歌林', market: 'TWSE'),
    ]);
    await db.deactivateStocksNotIn({'2330'});
    expect(await db.countActiveOfficialUniverse(), 1);
  });

  test('空資料庫回 0(首次啟動時沒有基準可比)', () async {
    expect(await db.countActiveOfficialUniverse(), 0);
  });
}
