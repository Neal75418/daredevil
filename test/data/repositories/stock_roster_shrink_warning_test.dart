// 名冊縮水警報的參考點(2026-08-15)
//
// **舊實作的問題**:警告條件是 `length < sanityFloor * 1.1`,而 floor 在
// 2026-08-05 從 800 調升到 1000(為了把「floor 過了但名單仍缺漏」的盲區
// 從 293 檔縮到 ~93 檔)。實際名冊 ~1,095 家 < 1,100,於是**從調升那天起
// 警告必然響**——一個永遠響的警告等於沒有警告,真正的異常會被埋掉。
//
// 更根本的是它的參考點錯了:floor 是「災難下限」,不是「正常值」。要偵測
// 的是「相對於既有規模的異常縮水」,而 DB 本身就記著上一輪的規模。
//
// 這兩個測試刻意選在**新舊邏輯結論相反**的點上,否則證明不了任何事:
//   案例 A:既有 1095、抓到 1080 → 舊響(<1100)、新不響(>1073)  = 消除噪音
//   案例 B:既有 1300、抓到 1150 → 舊不響(>1100)、新響(<1274)  = 補上漏報
// 案例 B 正是 floor 守不到的那段盲區:抓到的家數遠高於 floor,卻比上一輪
// 少了 150 家,那些缺席者會被判下市。
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/data/remote/finmind_client.dart';
import 'package:daredevil/data/remote/twse_client.dart';
import 'package:daredevil/data/repositories/stock_repository.dart';

class MockAppDatabase extends Mock implements AppDatabase {
  @override
  Future<T> transaction<T>(Future<T> Function() action, {bool? requireNew}) =>
      action();
}

class MockFinMindClient extends Mock implements FinMindClient {}

class MockTwseClient extends Mock implements TwseClient {}

class FakeStockMasterCompanion extends Fake implements StockMasterCompanion {}

void main() {
  setUpAll(() {
    registerFallbackValue(FakeStockMasterCompanion());
    registerFallbackValue(<StockMasterCompanion>[]);
  });

  late MockAppDatabase db;
  late MockFinMindClient finMind;
  late MockTwseClient twse;
  late StockRepository repo;

  setUp(() {
    db = MockAppDatabase();
    finMind = MockFinMindClient();
    twse = MockTwseClient();
    repo = StockRepository(
      database: db,
      finMindClient: finMind,
      twseClient: twse,
    );
    when(() => db.upsertStocks(any())).thenAnswer((_) async {});
    when(() => db.deactivateStocksNotIn(any())).thenAnswer((_) async => 0);
    when(() => finMind.getStockList()).thenAnswer(
      (_) async => const [
        FinMindStockInfo(
          stockId: '2330',
          stockName: '台積電',
          industryCategory: '半導體業',
          type: 'twse',
        ),
      ],
    );
  });

  /// 產生 [n] 筆四碼上市代號的官方名冊
  Map<String, String> roster(int n) => {
    for (var i = 0; i < n; i++) '${1000 + i}': '01',
  };

  /// 跑一次同步並收集所有 log 行(AppLogger 直接 print,沒有注入點)
  Future<List<String>> runAndCaptureLogs() async {
    final lines = <String>[];
    await runZoned(
      () => repo.syncStockList(),
      zoneSpecification: ZoneSpecification(
        print: (_, _, _, line) => lines.add(line),
      ),
    );
    return lines;
  }

  /// 名冊規模相關的警告(用固定詞彙錨定,避免抓到其他 [W])
  List<String> rosterWarnings(List<String> logs) =>
      logs.where((l) => l.contains('[W]') && l.contains('官方名冊')).toList();

  test('🚨 A. 既有 1095、抓到 1080 → 不得警告(正常波動不是異常)', () async {
    when(() => db.countActiveOfficialUniverse()).thenAnswer((_) async => 1095);
    when(() => twse.fetchIndustryCodes()).thenAnswer((_) async => roster(1080));

    final warnings = rosterWarnings(await runAndCaptureLogs());
    expect(
      warnings,
      isEmpty,
      reason:
          '1080/1095 = 98.6%,是正常波動。舊實作因 1080 < floor(1000)×1.1 '
          '而必然警告 —— 那是把災難下限當成正常值的參考點錯誤,結果是警告噪音化',
    );
  });

  test('🚨 B. 既有 1300、抓到 1150 → 必須警告(floor 守不到的盲區)', () async {
    when(() => db.countActiveOfficialUniverse()).thenAnswer((_) async => 1300);
    when(() => twse.fetchIndustryCodes()).thenAnswer((_) async => roster(1150));

    final warnings = rosterWarnings(await runAndCaptureLogs());
    expect(
      warnings,
      isNotEmpty,
      reason:
          '少了 150 家(11.5%),那些缺席者會被判下市。但 1150 遠高於 '
          'floor(1000),舊實作完全看不見 —— 這正是 api_config 註解自承的 '
          '「floor 過了但名單仍缺漏」盲區',
    );
  });

  test('首次啟動(DB 為空)不得警告——沒有基準可比', () async {
    when(() => db.countActiveOfficialUniverse()).thenAnswer((_) async => 0);
    when(() => twse.fetchIndustryCodes()).thenAnswer((_) async => roster(1050));

    expect(rosterWarnings(await runAndCaptureLogs()), isEmpty);
  });

  test('名冊變多不得警告(方向性)', () async {
    when(() => db.countActiveOfficialUniverse()).thenAnswer((_) async => 1095);
    when(() => twse.fetchIndustryCodes()).thenAnswer((_) async => roster(1200));

    expect(rosterWarnings(await runAndCaptureLogs()), isEmpty);
  });
}
