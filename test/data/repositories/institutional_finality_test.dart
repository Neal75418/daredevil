import 'package:drift/drift.dart' show Value, Variable;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:daredevil/core/constants/market_codes.dart';
import 'package:daredevil/core/constants/market_dataset.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/data/remote/finmind_client.dart';
import 'package:daredevil/data/remote/tpex_client.dart';
import 'package:daredevil/data/remote/twse_client.dart';
import 'package:daredevil/data/repositories/institutional_repository.dart';
import 'package:daredevil/data/repositories/market_day_fetch_ledger.dart';

class MockTwseClient extends Mock implements TwseClient {}

class MockTpexClient extends Mock implements TpexClient {}

class MockFinMindClient extends Mock implements FinMindClient {}

void main() {
  late AppDatabase db;
  late MockTwseClient twse;
  late MockTpexClient tpex;
  late InstitutionalRepository repo;
  final day = DateTime(2026, 7, 17);

  TwseInstitutional twseRow(String code, double foreign) => TwseInstitutional(
    date: day,
    code: code,
    name: code,
    foreignBuy: 0,
    foreignSell: 0,
    foreignNet: foreign,
    investmentTrustBuy: 0,
    investmentTrustSell: 0,
    investmentTrustNet: 0,
    dealerBuy: 0,
    dealerSell: 0,
    dealerNet: 0,
    totalNet: foreign,
  );
  TpexInstitutional tpexRow(String code, double foreign) => TpexInstitutional(
    date: day,
    code: code,
    name: code,
    foreignBuy: 0,
    foreignSell: 0,
    foreignNet: foreign,
    investmentTrustBuy: 0,
    investmentTrustSell: 0,
    investmentTrustNet: 0,
    dealerBuy: 0,
    dealerSell: 0,
    dealerNet: 0,
    totalNet: foreign,
  );

  setUpAll(() => registerFallbackValue(DateTime(2026)));

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.upsertStocks([
      for (final s in ['1101', '1102'])
        StockMasterCompanion.insert(
          symbol: s,
          name: s,
          market: MarketCode.twse,
        ),
      for (final s in ['3624', '6488'])
        StockMasterCompanion.insert(
          symbol: s,
          name: s,
          market: MarketCode.tpex,
        ),
      // 已下市（is_active=false）
      StockMasterCompanion.insert(
        symbol: '9999',
        name: '下市股',
        market: MarketCode.twse,
        isActive: const Value(false),
      ),
    ]);
    twse = MockTwseClient();
    tpex = MockTpexClient();
    repo = InstitutionalRepository(
      database: db,
      finMindClient: MockFinMindClient(),
      twseClient: twse,
      tpexClient: tpex,
    );
  });

  tearDown(() => db.close());

  Future<void> seedPrelim(String symbol, double foreign) =>
      db.insertInstitutionalData([
        DailyInstitutionalCompanion.insert(
          symbol: symbol,
          date: day,
          foreignNet: Value(foreign),
          investmentTrustNet: const Value(0),
          dealerNet: const Value(0),
        ),
      ]);

  Future<List<String>> symbolsOnDay() async => [
    for (final r
        in await db
            .customSelect(
              'SELECT symbol FROM daily_institutional WHERE date >= ? AND date < ?',
              variables: [
                Variable.withDateTime(day),
                Variable.withDateTime(
                  DateTime(day.year, day.month, day.day + 1),
                ),
              ],
            )
            .get())
      r.read<String>('symbol'),
  ];

  void stubBoth(List<TwseInstitutional> t, List<TpexInstitutional> p) {
    when(
      () => twse.getAllInstitutionalData(date: any(named: 'date')),
    ).thenAnswer((_) async => t);
    when(
      () => tpex.getAllInstitutionalData(date: any(named: 'date')),
    ).thenAnswer((_) async => p);
  }

  /// 補滿回應列數：全 0 比例要低於安全閥（10%）才會刪。填充代號不在
  /// stock_master，寫入時被濾掉，不影響其他斷言
  List<TwseInstitutional> padTwse(List<TwseInstitutional> rows) => [
    ...rows,
    for (var i = 0; i < 20; i++) twseRow('P$i', 100),
  ];

  test('定案回應明確列出且全 0 → 刪除該股的初值列', () async {
    await seedPrelim('1101', 3000000);
    stubBoth(padTwse([twseRow('1101', 0), twseRow('1102', 500)]), [
      tpexRow('3624', 100),
      tpexRow('6488', 200),
    ]);
    await repo.syncAllMarketInstitutional(day, force: true);
    expect(await symbolsOnDay(), isNot(contains('1101')));
    expect(await symbolsOnDay(), containsAll(['1102', '3624', '6488']));
  });

  test('回應裡沒有的代號（含下市股）舊列不動', () async {
    await seedPrelim('9999', 100);
    await seedPrelim('1101', 100);
    stubBoth(
      [twseRow('1102', 500)],
      [tpexRow('3624', 100), tpexRow('6488', 200)],
    );
    await repo.syncAllMarketInstitutional(day, force: true);
    expect(await symbolsOnDay(), containsAll(['9999', '1101']));
  });

  test('🚨 安全閥：全 0 比例異常（整個市場都是 0）→ 不刪舊列', () async {
    await seedPrelim('1101', 100);
    await seedPrelim('1102', 100);
    stubBoth([twseRow('1101', 0), twseRow('1102', 0)], []);
    await repo.syncAllMarketInstitutional(day, force: true);
    expect(
      await symbolsOnDay(),
      containsAll(['1101', '1102']),
      reason: '欄位改版讓 parser 全部退成 0 時，不可整批刪掉',
    );
  });

  test('DB 不寫入全 0 列', () async {
    stubBoth(padTwse([twseRow('1101', 0), twseRow('1102', 500)]), []);
    await repo.syncAllMarketInstitutional(day, force: true);
    expect(await symbolsOnDay(), isNot(contains('1101')));
  });

  test('單邊失敗（回空）：另一市場照常寫入與記錄，失敗那邊不記錄、也不刪列', () async {
    await seedPrelim('3624', 100);
    stubBoth([twseRow('1101', 100), twseRow('1102', 500)], []);
    final ledger = MarketDayFetchLedger(
      database: db,
      fetchedAt: DateTime(2026, 7, 18),
    );
    await repo.syncAllMarketInstitutional(day, force: true, ledger: ledger);
    expect(ledger.recorded.map((r) => r.market), [MarketCode.twse]);
    expect(await symbolsOnDay(), contains('3624'));
  });

  test('isDayFinal：兩市場都定案才 true', () async {
    Future<void> mark(String m) => db.upsertMarketDayFetch(
      dataset: MarketDataset.institutional.code,
      market: m,
      date: day,
      fetchedAt: DateTime(2026, 7, 18),
      rowCount: 2,
    );
    await mark(MarketCode.tpex);
    expect(await repo.isDayFinal(day), isFalse, reason: '只有上櫃定案');
    await db.customStatement('DELETE FROM market_day_fetch');
    await mark(MarketCode.twse);
    expect(await repo.isDayFinal(day), isFalse, reason: '只有上市定案');
    await mark(MarketCode.tpex);
    expect(await repo.isDayFinal(day), isTrue);
  });
}
