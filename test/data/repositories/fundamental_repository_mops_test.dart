import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:daredevil/core/constants/market_codes.dart';
import 'package:daredevil/core/exceptions/app_exception.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/data/remote/finmind_client.dart';
import 'package:daredevil/data/remote/mops_client.dart';
import 'package:daredevil/data/remote/tpex_client.dart';
import 'package:daredevil/data/remote/twse_client.dart';
import 'package:daredevil/core/utils/clock.dart';
import 'package:daredevil/data/repositories/fundamental_repository.dart';

class MockAppDatabase extends Mock implements AppDatabase {}

class MockFinMindClient extends Mock implements FinMindClient {}

class MockTwseClient extends Mock implements TwseClient {}

class MockTpexClient extends Mock implements TpexClient {}

class MockMopsClient extends Mock implements MopsClient {}

class FakeMonthlyRevenueCompanion extends Fake
    implements MonthlyRevenueCompanion {}

class _FixedClock implements AppClock {
  const _FixedClock(this._now);
  final DateTime _now;
  @override
  DateTime now() => _now;
}

StockMasterEntry _stock(String symbol, String market) => StockMasterEntry(
  symbol: symbol,
  name: '測試$symbol',
  market: market,
  industry: '測試',
  isActive: true,
  updatedAt: DateTime(2026, 8, 1),
);

/// MOPS 公布期漸進營收同步(2026-08-03)。
///
/// 行為契約:
/// - 窗口與目標月以 **clock 真實今天** 判定(2026-08-05 複審修正:
///   原用傳入的校正交易日,月初逢週末/元旦時校正日=上月末 → day>14
///   → 公布首日整段跳過);每月 1~14 日內每次更新都掃,15 日後靜默跳過
/// - 窗口內一律抓(無覆蓋門檻跳過——上櫃壓線申報者的完整性優先)
/// - MOPS 掛掉(舊版隨時可能關站)→ fail-soft,不得中斷更新管線
/// - 目標月 = 上個月(1 月時 = 去年 12 月)
void main() {
  late MockAppDatabase db;
  late MockMopsClient mops;
  late FundamentalRepository repo;

  FundamentalRepository buildRepo(DateTime now) => FundamentalRepository(
    db: db,
    finMind: MockFinMindClient(),
    twse: MockTwseClient(),
    tpex: MockTpexClient(),
    mops: mops,
    clock: _FixedClock(now),
  );

  setUpAll(() {
    registerFallbackValue(FakeMonthlyRevenueCompanion());
    registerFallbackValue(<MonthlyRevenueCompanion>[]);
    registerFallbackValue(MopsMarket.sii);
  });

  MopsMonthlyRevenue row(String code, {double revenue = 1000}) =>
      MopsMonthlyRevenue(
        code: code,
        year: 2026,
        month: 7,
        revenue: revenue,
        momGrowth: 5.0,
        yoyGrowth: 10.0,
      );

  setUp(() {
    db = MockAppDatabase();
    mops = MockMopsClient();
    // 預設時鐘固定在公布窗口內(2026-08-15 踩到:未注入 clock 吃真實
    // 日期,每月 15 日起窗口關閉,三個依賴預設 repo 的測試半個月紅、
    // 「MOPS 掛掉」則因窗外早退而綠得毫無意義)。需要窗外行為的測試
    // 自行 buildRepo 覆寫。
    repo = buildRepo(DateTime(2026, 8, 4));
    when(
      () => db.getAllActiveStocks(),
    ).thenAnswer((_) async => [_stock('2408', 'TWSE'), _stock('6538', 'TPEx')]);
    when(
      () => db.getRevenueCountForYearMonth(
        any(),
        any(),
        market: any(named: 'market'),
      ),
    ).thenAnswer((_) async => 0);
    when(() => db.insertMonthlyRevenue(any())).thenAnswer((_) async {});
  });

  test('🚨 公布期內(8/4):兩市場都掃,寫入 2026/7', () async {
    when(
      () => mops.getInProgressRevenue(
        year: any(named: 'year'),
        month: any(named: 'month'),
        market: MopsMarket.sii,
      ),
    ).thenAnswer((_) async => [row('2408')]);
    when(
      () => mops.getInProgressRevenue(
        year: any(named: 'year'),
        month: any(named: 'month'),
        market: MopsMarket.otc,
      ),
    ).thenAnswer((_) async => [row('6538')]);

    repo = buildRepo(DateTime(2026, 8, 4));
    final count = await repo.syncInProgressRevenue(DateTime(2026, 8, 4));

    expect(count, 2);
    final captured = verify(
      () => db.insertMonthlyRevenue(captureAny()),
    ).captured;
    final all = captured
        .expand((c) => c as List<MonthlyRevenueCompanion>)
        .toList();
    expect(all, hasLength(2));
    expect(all.every((c) => c.revenueYear.value == 2026), isTrue);
    expect(all.every((c) => c.revenueMonth.value == 7), isTrue);
  });

  test('🚨 15 日後:靜默跳過,client 不被呼叫', () async {
    repo = buildRepo(DateTime(2026, 8, 15));
    final count = await repo.syncInProgressRevenue(DateTime(2026, 8, 15));

    expect(count, isNull);
    verifyNever(
      () => mops.getInProgressRevenue(
        year: any(named: 'year'),
        month: any(named: 'month'),
        market: any(named: 'market'),
      ),
    );
  });

  // 2026-08-05 行為變更(原「覆蓋達門檻→跳過」測試翻轉):上櫃沒有月批
  // 全量源接手(openapi 只涵蓋上市),以覆蓋數提前跳過會讓 8/10 壓線申報
  // 的上櫃公司永遠缺漏——省一次免費請求換清單不完整,不划算。窗口內
  // 一律抓;upsert 冪等、兩源逐位元一致,重複寫零風險。
  test('🚨 覆蓋已滿仍照抓(保上櫃壓線交卷完整性,不做門檻跳過)', () async {
    when(
      () => mops.getInProgressRevenue(
        year: any(named: 'year'),
        month: any(named: 'month'),
        market: MopsMarket.sii,
      ),
    ).thenAnswer((_) async => [row('2408')]);
    when(
      () => mops.getInProgressRevenue(
        year: any(named: 'year'),
        month: any(named: 'month'),
        market: MopsMarket.otc,
      ),
    ).thenAnswer((_) async => [row('6538')]);

    final count = await repo.syncInProgressRevenue(DateTime(2026, 8, 10));

    expect(count, 2, reason: '兩市場都抓,與 DB 既有覆蓋數無關');
    verify(
      () => mops.getInProgressRevenue(
        year: any(named: 'year'),
        month: any(named: 'month'),
        market: MopsMarket.sii,
      ),
    ).called(1);
    verifyNever(
      () => db.getRevenueCountForYearMonth(
        any(),
        any(),
        market: any(named: 'market'),
      ),
    );
  });

  test('🚨 MOPS 掛掉 → fail-soft 不拋(舊站關站不得中斷管線)', () async {
    when(
      () => mops.getInProgressRevenue(
        year: any(named: 'year'),
        month: any(named: 'month'),
        market: any(named: 'market'),
      ),
    ).thenThrow(const ApiException('mopsov down', 404));

    final count = await repo.syncInProgressRevenue(DateTime(2026, 8, 4));

    expect(count, isNull);
    verifyNever(() => db.insertMonthlyRevenue(any()));
  });

  test('不在 stock_master 的代號被過濾(FK 防炸)', () async {
    when(
      () => mops.getInProgressRevenue(
        year: any(named: 'year'),
        month: any(named: 'month'),
        market: MopsMarket.sii,
      ),
    ).thenAnswer((_) async => [row('2408'), row('9999')]);
    when(
      () => mops.getInProgressRevenue(
        year: any(named: 'year'),
        month: any(named: 'month'),
        market: MopsMarket.otc,
      ),
    ).thenAnswer((_) async => const []);

    final count = await repo.syncInProgressRevenue(DateTime(2026, 8, 4));

    expect(count, 1);
  });

  test('🚨 月初逢週末:校正日=上月末仍要跑(窗口用真今天,複審 Low #5)', () async {
    repo = buildRepo(DateTime(2026, 8, 1)); // 週六,真今天 8/1
    when(
      () => mops.getInProgressRevenue(
        year: any(named: 'year'),
        month: any(named: 'month'),
        market: any(named: 'market'),
      ),
    ).thenAnswer((_) async => const []);

    // 傳入的是校正後交易日 7/31(day=31)——不得因此跳過
    await repo.syncInProgressRevenue(DateTime(2026, 7, 31));

    verify(
      () => mops.getInProgressRevenue(
        year: 2026,
        month: 7,
        market: MopsMarket.sii,
      ),
    ).called(1);
  });

  test('1 月的目標月 = 去年 12 月', () async {
    when(
      () => mops.getInProgressRevenue(
        year: any(named: 'year'),
        month: any(named: 'month'),
        market: any(named: 'market'),
      ),
    ).thenAnswer((_) async => const []);

    repo = buildRepo(DateTime(2027, 1, 5));
    await repo.syncInProgressRevenue(DateTime(2027, 1, 5));

    verify(
      () => mops.getInProgressRevenue(
        year: 2026,
        month: 12,
        market: MopsMarket.sii,
      ),
    ).called(1);
  });
}
