// 當沖比例計算的行為釘樁（characterization test，真 in-memory DB）
//
// `dayTradingRatio` = 當沖成交股數 ÷ 價格表當日總成交量 × 100，是當沖規則
// （DAY_TRADING_HIGH / DAY_TRADING_EXTREME）唯一的輸入。此前全庫沒有任何測試
// 斷言這個值算得對不對——既有測試都是「塞一個 ratio 進去」測下游，`>100` 的
// 鉗制（`DataFreshness.dayTradingMaxValidRatio`）更是零覆蓋。
//
// 本檔在把計算抽成上市／上櫃共用之前先釘住現行行為，讓重構從「希望沒改壞」
// 變成「證明沒改壞」。
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:daredevil/core/constants/data_freshness.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/data/remote/tpex_client.dart';
import 'package:daredevil/data/remote/twse_client.dart';
import 'package:daredevil/data/repositories/trading_repository.dart';

class MockTwseClient extends Mock implements TwseClient {}

class MockTpexClient extends Mock implements TpexClient {}

void main() {
  late AppDatabase db;
  late MockTwseClient mockTwse;
  late TradingRepository repo;

  final day = DateTime(2026, 7, 7);

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.upsertStocks([
      StockMasterCompanion.insert(symbol: '2330', name: '台積電', market: 'TWSE'),
    ]);
    mockTwse = MockTwseClient();
    repo = TradingRepository(
      database: db,
      twseClient: mockTwse,
      tpexClient: MockTpexClient(),
    );
  });

  tearDown(() async => db.close());

  /// 價格表塞入當日總成交量
  Future<void> seedPriceVolume(double volume) => db.insertPrices([
    DailyPriceCompanion.insert(
      symbol: '2330',
      date: day,
      close: const Value(100),
      volume: Value(volume),
    ),
  ]);

  /// 讓 client 回傳指定的當沖成交股數
  void stubDayTrading(double tradeVolume) {
    when(
      () => mockTwse.getAllDayTradingData(date: any(named: 'date')),
    ).thenAnswer(
      (_) async => [
        TwseDayTrading(
          date: day,
          code: '2330',
          name: '台積電',
          buyVolume: 100000,
          sellVolume: 90000,
          totalVolume: tradeVolume,
        ),
      ],
    );
  }

  Future<double?> syncAndReadRatio() async {
    await repo.syncAllDayTradingFromTwse(date: day, force: true);
    final rows = await db.getDayTradingHistory(
      '2330',
      startDate: day,
      endDate: day,
    );
    return rows.isEmpty ? null : rows.single.dayTradingRatio;
  }

  test('比例 = 當沖量 ÷ 總量 × 100', () async {
    await seedPriceVolume(4000);
    stubDayTrading(1000); // 1000 / 4000 = 25%

    expect(await syncAndReadRatio(), closeTo(25.0, 1e-9));
  });

  test('🚨 超過 100% 必須鉗制（此前零測試覆蓋）', () async {
    await seedPriceVolume(1000);
    stubDayTrading(3500); // 350% —— 資料異常

    expect(
      await syncAndReadRatio(),
      DataFreshness.dayTradingMaxValidRatio,
      reason: '不鉗制會讓 DAY_TRADING_EXTREME 對髒資料狂噴訊號',
    );
  });

  test('🚨 價格表無該日資料 → 比例為 0，不得瞎猜', () async {
    // 刻意不 seed 價格
    stubDayTrading(1000);

    expect(await syncAndReadRatio(), 0.0, reason: '分母未知時給 0；給任何非零值都是編造');
  });

  test('總成交量為 0 → 比例為 0，不得除以零', () async {
    await seedPriceVolume(0);
    stubDayTrading(1000);

    expect(await syncAndReadRatio(), 0.0);
  });

  test('當沖量為 0 → 比例為 0', () async {
    await seedPriceVolume(4000);
    stubDayTrading(0);

    expect(await syncAndReadRatio(), 0.0);
  });
}
