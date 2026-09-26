import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:daredevil/core/exceptions/app_exception.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/data/remote/tpex_client.dart';
import 'package:daredevil/data/remote/twse_client.dart';
import 'package:daredevil/domain/services/update/quarterly_report_syncer.dart';

class MockAppDatabase extends Mock implements AppDatabase {}

class MockTwseClient extends Mock implements TwseClient {}

class MockTpexClient extends Mock implements TpexClient {}

class FakeCompanion extends Fake implements QuarterlyReportCompanion {}

QuarterlyReportEntry _entry(String symbol, {double? eps = 4.71}) =>
    QuarterlyReportEntry(
      symbol: symbol,
      companyName: '測試$symbol',
      year: 2026,
      quarter: 2,
      eps: eps,
      netIncome: 790350,
      revenue: 11481997,
    );

StockMasterEntry _stock(String symbol, String market) => StockMasterEntry(
  symbol: symbol,
  name: '測試$symbol',
  market: market,
  industry: '測試',
  isActive: true,
  updatedAt: DateTime(2026, 8, 1),
);

/// 季報雙源同步(2026-08-06 最新一季財報總覽)。
///
/// 契約鏡射 InsiderTransferSyncer:
/// - 上市(t187ap06_L_*)+上櫃(ap06_O_*)合併寫入
/// - **per-source 隔離**:單側故障記 warning、另一側照常;兩側都掛才拋
/// - RateLimitException 一律直接 rethrow(全域狀態)
/// - 僅寫入 StockMaster 已知股票(FK constraint;興櫃/新掛牌落差丟棄)
void main() {
  setUpAll(() {
    registerFallbackValue(FakeCompanion());
    registerFallbackValue(<QuarterlyReportCompanion>[]);
  });

  late MockAppDatabase db;
  late MockTwseClient twse;
  late MockTpexClient tpex;
  late QuarterlyReportSyncer syncer;

  setUp(() {
    db = MockAppDatabase();
    twse = MockTwseClient();
    tpex = MockTpexClient();
    syncer = QuarterlyReportSyncer(
      database: db,
      twseClient: twse,
      tpexClient: tpex,
    );
    when(
      () => db.getAllActiveStocks(),
    ).thenAnswer((_) async => [_stock('1232', 'TWSE'), _stock('1570', 'TPEx')]);
    when(() => db.insertQuarterlyReports(any())).thenAnswer((_) async {});
  });

  test('🚨 雙源合併寫入(上市+上櫃),companion 欄位齊全', () async {
    when(
      () => twse.getQuarterlyReports(),
    ).thenAnswer((_) async => [_entry('1232')]);
    when(
      () => tpex.getQuarterlyReports(),
    ).thenAnswer((_) async => [_entry('1570', eps: 0.54)]);

    final count = await syncer.sync();

    expect(count, 2);
    final captured =
        verify(() => db.insertQuarterlyReports(captureAny())).captured.single
            as List<QuarterlyReportCompanion>;
    expect(captured.map((c) => c.symbol.value).toSet(), {'1232', '1570'});
    final c = captured.firstWhere((c) => c.symbol.value == '1232');
    expect(c.year.value, 2026);
    expect(c.quarter.value, 2);
    expect(c.eps.value, 4.71);
    expect(c.netIncome.value, 790350);
    expect(c.revenue.value, 11481997);
  });

  test('🚨 單側故障不砍另一側(per-source 隔離)', () async {
    when(
      () => twse.getQuarterlyReports(),
    ).thenThrow(const ApiException('twse down', 500));
    when(
      () => tpex.getQuarterlyReports(),
    ).thenAnswer((_) async => [_entry('1570')]);

    final count = await syncer.sync();

    expect(count, 1, reason: '上市掛掉,上櫃照常寫入');
  });

  test('兩側都掛 → 拋出(讓 UpdateService 記 errors)', () async {
    when(
      () => twse.getQuarterlyReports(),
    ).thenThrow(const ApiException('twse down', 500));
    when(() => tpex.getQuarterlyReports()).thenThrow(Exception('tpex down'));

    await expectLater(syncer.sync(), throwsA(anything));
    verifyNever(() => db.insertQuarterlyReports(any()));
  });

  test('RateLimitException 直接 rethrow,不進單側容錯', () async {
    when(
      () => twse.getQuarterlyReports(),
    ).thenThrow(const RateLimitException('429'));

    await expectLater(syncer.sync(), throwsA(isA<RateLimitException>()));
    verifyNever(() => tpex.getQuarterlyReports());
  });

  test('StockMaster 未知代號被 FK 過濾(不寫入)', () async {
    when(() => twse.getQuarterlyReports()).thenAnswer(
      (_) async => [_entry('1232'), _entry('7777')], // 7777 不在主檔
    );
    when(() => tpex.getQuarterlyReports()).thenAnswer((_) async => []);

    final count = await syncer.sync();

    expect(count, 1);
    final captured =
        verify(() => db.insertQuarterlyReports(captureAny())).captured.single
            as List<QuarterlyReportCompanion>;
    expect(captured.map((c) => c.symbol.value).toList(), ['1232']);
  });

  test('單源 harness(僅上櫃)向後相容', () async {
    final soloSyncer = QuarterlyReportSyncer(database: db, tpexClient: tpex);
    when(
      () => tpex.getQuarterlyReports(),
    ).thenAnswer((_) async => [_entry('1570')]);

    expect(await soloSyncer.sync(), 1);
  });
}
