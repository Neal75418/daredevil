import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/constants/data_freshness.dart';
import 'package:mocktail/mocktail.dart';

import 'package:daredevil/core/exceptions/app_exception.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/data/remote/tpex_client.dart';
import 'package:daredevil/data/remote/twse_client.dart';
import 'package:daredevil/domain/services/update/insider_transfer_syncer.dart';

class MockAppDatabase extends Mock implements AppDatabase {}

class MockTwseClient extends Mock implements TwseClient {}

class MockTpexClient extends Mock implements TpexClient {}

class FakeCompanion extends Fake implements InsiderTransferCompanion {}

TpexInsiderTransfer _transfer(String symbol) => TpexInsiderTransfer(
  symbol: symbol,
  companyName: '測試$symbol',
  reportDate: DateTime(2026, 8, 4),
  identity: '董事',
  name: '某人',
  transferMethod: '一般交易',
  transferShares: 1000,
  currentHolding: 5000,
);

StockMasterEntry _stock(String symbol, String market) => StockMasterEntry(
  symbol: symbol,
  name: '測試$symbol',
  market: market,
  industry: '測試',
  isActive: true,
  updatedAt: DateTime(2026, 8, 1),
);

/// 內部人轉讓雙源同步(2026-08-05 補接上市源)。
///
/// 契約:
/// - 上市(t187ap12_L)+上櫃(ap12_O)合併寫入——原本只有上櫃,面板
///   左欄永遠空白,空白被誤讀成「今天沒異動」
/// - **per-source 隔離**:單側連線故障記 warning、另一側照常(同日
///   TPEx 大檔曾三連斷線的實例);兩側都掛才往上拋
/// - RateLimitException 一律直接 rethrow(全域狀態)
void main() {
  setUpAll(() {
    registerFallbackValue(FakeCompanion());
    registerFallbackValue(<InsiderTransferCompanion>[]);
  });

  late MockAppDatabase db;
  late MockTwseClient twse;
  late MockTpexClient tpex;
  late InsiderTransferSyncer syncer;

  setUp(() {
    db = MockAppDatabase();
    twse = MockTwseClient();
    tpex = MockTpexClient();
    syncer = InsiderTransferSyncer(
      database: db,
      twseClient: twse,
      tpexClient: tpex,
    );
    when(
      () => db.getAllActiveStocks(),
    ).thenAnswer((_) async => [_stock('2330', 'TWSE'), _stock('6538', 'TPEx')]);
    when(() => db.insertInsiderTransfers(any())).thenAnswer((_) async {});
    when(
      () => db.deleteLegacyMultiMethodInsiderTransfers(
        before: any(named: 'before'),
      ),
    ).thenAnswer((_) async => 0);
  });

  // 舊解析規則寫入的多方式列股數錯誤、官方不會重給：每次同步先清（冪等）。
  // 休市日 API 回空也要清——清理不依賴當日有沒有新資料
  test('每次同步先清舊規則寫入的多方式列（API 回空也清）', () async {
    when(() => twse.getInsiderTransfers()).thenAnswer((_) async => []);
    when(() => tpex.getInsiderTransfers()).thenAnswer((_) async => []);

    await syncer.sync();

    verify(
      () => db.deleteLegacyMultiMethodInsiderTransfers(
        before: DataFreshness.insiderMultiMethodLegacyCutoff,
      ),
    ).called(1);
  });

  test('🚨 雙源合併寫入(上市+上櫃)', () async {
    when(
      () => twse.getInsiderTransfers(),
    ).thenAnswer((_) async => [_transfer('2330')]);
    when(
      () => tpex.getInsiderTransfers(),
    ).thenAnswer((_) async => [_transfer('6538')]);

    final count = await syncer.sync();

    expect(count, 2);
    final captured =
        verify(() => db.insertInsiderTransfers(captureAny())).captured.single
            as List<InsiderTransferCompanion>;
    expect(captured.map((c) => c.symbol.value).toSet(), {'2330', '6538'});
  });

  test('🚨 單側故障不砍另一側(per-source 隔離)', () async {
    when(
      () => twse.getInsiderTransfers(),
    ).thenThrow(const ApiException('twse down', 500));
    when(
      () => tpex.getInsiderTransfers(),
    ).thenAnswer((_) async => [_transfer('6538')]);

    final count = await syncer.sync();

    expect(count, 1, reason: '上市掛掉,上櫃照常寫入');
  });

  test('兩側都掛 → 拋出(讓 UpdateService 記 errors)', () async {
    when(
      () => twse.getInsiderTransfers(),
    ).thenThrow(const ApiException('twse down', 500));
    when(() => tpex.getInsiderTransfers()).thenThrow(Exception('tpex down'));

    await expectLater(syncer.sync(), throwsA(anything));
    verifyNever(() => db.insertInsiderTransfers(any()));
  });

  test('RateLimitException 直接 rethrow,不進單側容錯', () async {
    when(
      () => twse.getInsiderTransfers(),
    ).thenThrow(const RateLimitException('429'));

    await expectLater(syncer.sync(), throwsA(isA<RateLimitException>()));
    verifyNever(() => tpex.getInsiderTransfers());
  });

  test('單源 harness(僅上櫃)向後相容', () async {
    final soloSyncer = InsiderTransferSyncer(database: db, tpexClient: tpex);
    when(
      () => tpex.getInsiderTransfers(),
    ).thenAnswer((_) async => [_transfer('6538')]);

    expect(await soloSyncer.sync(), 1);
  });
}
