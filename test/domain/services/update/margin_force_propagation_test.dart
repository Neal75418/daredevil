// force 未傳遞到融資融券(2026-08-16)
//
// **實機發現**:2026-08-15 23:01 與 2026-08-16 00:40 兩次**強制更新**的
// 日誌都印出 `融資融券資料已快取 (2003 筆)，跳過同步`。而 trading_repository
// 的新鮮度檢查包在 `if (!force)` 裡——force=true 時根本不該走到那行。
//
// 根因:`syncMarketWideData` 有 force 參數,緊鄰的當沖呼叫傳了、融資融券
// 那行漏傳,於是永遠吃預設值 false。兩行相隔四行,肉眼掃過去像是一致的。
//
// **影響**:強制更新無法重抓融資融券。日常更新不受影響(當日尚無資料時
// existingCount 低於門檻,照樣抓),但「資料有誤想重抓」這條路是斷的——
// 而那正是強制更新存在的理由。
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

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

  final date = DateTime(2026, 8, 14);

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
      () => trading.syncAllDayTradingFromTpex(force: any(named: 'force')),
    ).thenAnswer((_) async => 0);
    when(
      () => trading.syncAllDayTradingFromTwse(
        date: any(named: 'date'),
        force: any(named: 'force'),
      ),
    ).thenAnswer((_) async => 0);
    when(
      () => trading.syncAllMarginTrading(
        date: any(named: 'date'),
        force: any(named: 'force'),
      ),
    ).thenAnswer((_) async => 0);
    // 回補路徑先算市場規模,回 0 讓它直接收斂、不進逐日回補
    when(() => db.countStocksByMarket(any())).thenAnswer((_) async => 0);
  });

  test('🚨 force=true 必須傳到融資融券(當沖有傳、它漏了)', () async {
    await updater.syncMarketWideData(date: date, force: true);

    verify(
      () => trading.syncAllMarginTrading(date: date, force: true),
    ).called(1);
  });

  test('force=false 照常傳 false', () async {
    await updater.syncMarketWideData(date: date);

    verify(
      () => trading.syncAllMarginTrading(date: date, force: false),
    ).called(1);
  });

  test('當沖的傳遞不得被改壞(對照組)', () async {
    await updater.syncMarketWideData(date: date, force: true);

    verify(
      () => trading.syncAllDayTradingFromTwse(date: date, force: true),
    ).called(1);
  });
}
