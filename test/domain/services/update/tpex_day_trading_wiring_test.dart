// 上櫃當沖接進 syncMarketWideData（2026-08-23）
//
// 三件必須成立的事：
//   1. 真的有被呼叫，且 force 有傳（融資融券曾因漏傳 force 而強制更新無感，
//      見 margin_force_propagation_test）
//   2. 它失敗**不得**中止整段——這是三個來源裡最不關鍵的一個，讓它 rethrow
//      會連帶犧牲融資融券與外資持股
//   3. 筆數與上市分開記，否則一邊整批掛掉會被另一邊的數字蓋過去
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:daredevil/core/exceptions/app_exception.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/data/repositories/insider_repository.dart';
import 'package:daredevil/data/repositories/shareholding_repository.dart';
import 'package:daredevil/data/repositories/trading_repository.dart';
import 'package:daredevil/data/repositories/warning_repository.dart';
import 'package:daredevil/domain/services/update/market_data_updater.dart';

class MockAppDatabase extends Mock implements AppDatabase {}

class MockTradingRepository extends Mock implements TradingRepository {}

class MockShareholdingRepository extends Mock
    implements ShareholdingRepository {}

class MockWarningRepository extends Mock implements WarningRepository {}

class MockInsiderRepository extends Mock implements InsiderRepository {}

void main() {
  late MockTradingRepository trading;
  late MockAppDatabase db;
  late MarketDataUpdater updater;

  final date = DateTime(2026, 8, 21);

  setUp(() {
    trading = MockTradingRepository();
    db = MockAppDatabase();
    updater = MarketDataUpdater(
      database: db,
      tradingRepository: trading,
      shareholdingRepository: MockShareholdingRepository(),
      warningRepository: MockWarningRepository(),
      insiderRepository: MockInsiderRepository(),
      backfillCallDelay: Duration.zero,
    );
    when(
      () => trading.syncAllDayTradingFromTwse(
        date: any(named: 'date'),
        force: any(named: 'force'),
      ),
    ).thenAnswer((_) async => 11);
    when(
      () => trading.syncAllDayTradingFromTpex(force: any(named: 'force')),
    ).thenAnswer((_) async => 22);
    when(
      () => trading.syncAllMarginTrading(
        date: any(named: 'date'),
        force: any(named: 'force'),
      ),
    ).thenAnswer((_) async => 33);
    when(() => db.countStocksByMarket(any())).thenAnswer((_) async => 0);
  });

  test('🚨 上櫃當沖有被呼叫，且 force 有傳', () async {
    await updater.syncMarketWideData(date: date, force: true);

    verify(() => trading.syncAllDayTradingFromTpex(force: true)).called(1);
  });

  test('force=false 照常傳 false', () async {
    await updater.syncMarketWideData(date: date);

    verify(() => trading.syncAllDayTradingFromTpex(force: false)).called(1);
  });

  test('🚨 兩市場筆數分開記，不得相加後失去辨識度', () async {
    final r = await updater.syncMarketWideData(date: date);

    expect(r.dayTradingCount, 11, reason: '上市');
    expect(r.tpexDayTradingCount, 22, reason: '上櫃');
    expect(r.total, 11 + 22 + 33);
  });

  test('🚨 上櫃當沖失敗不得中止整段（融資融券仍須執行）', () async {
    when(
      () => trading.syncAllDayTradingFromTpex(force: any(named: 'force')),
    ).thenThrow(const NetworkException('TPEx 掛了'));

    final r = await updater.syncMarketWideData(date: date);

    verify(
      () => trading.syncAllMarginTrading(
        date: any(named: 'date'),
        force: any(named: 'force'),
      ),
    ).called(1);
    expect(r.tpexDayTradingCount, 0);
    expect(r.dayTradingCount, 11, reason: '上市不受牽連');
  });

  test('🚨 上櫃限流必須往上拋（與 pipeline 既有契約一致）', () async {
    when(
      () => trading.syncAllDayTradingFromTpex(force: any(named: 'force')),
    ).thenThrow(const RateLimitException());

    await expectLater(
      updater.syncMarketWideData(date: date),
      throwsA(isA<RateLimitException>()),
      reason:
          'pipeline 靠 RateLimitException 設 rateLimitedAbort 並中止後續；'
          '吞掉只是讓中止晚幾行發生卻少一個來源的線索。而且限流時四行後的'
          '融資融券同樣打 TPEx、照樣會死——「吞掉才能保住融資」的理由對限流'
          '不成立，只對網路錯誤成立',
    );
  });
}
