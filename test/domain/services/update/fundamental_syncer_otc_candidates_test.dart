// FundamentalSyncer 上櫃候選段 — 批次端點不設候選上限
//
// 2026-07-29 多角色審查定案:syncOtcCandidatesFundamentals 的
// take(maxSyncCount) 是逐檔 API 時代的遺跡——estimation/營收實際走
// TPEx OpenAPI 全市場批次端點(各 1 次呼叫,與 symbol 數無關),
// cap 省不到任何配額,卻讓前綴以外的候選(實測 270 檔中的後 170 檔)
// 估值/營收永遠不落地:repo 端 fetch 全市場後只 persist 傳入清單
// (7/29 生產 log:fetch 889 筆 → 寫 56 檔),被 cap 排除的股票
// 價值面規則(PBR_UNDERVALUED 等)永遠 fire 不了。
//
// 修法:整串候選直接下傳,新鮮度過濾由 repo 內部負責(既有機制)。
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:daredevil/core/constants/market_codes.dart';
import 'package:daredevil/core/utils/clock.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/data/repositories/fundamental_repository.dart';
import 'package:daredevil/data/repositories/market_data_repository.dart';
import 'package:daredevil/domain/services/update/fundamental_syncer.dart';

class MockAppDatabase extends Mock implements AppDatabase {}

class MockFundamentalRepository extends Mock implements FundamentalRepository {}

class MockMarketDataRepository extends Mock implements MarketDataRepository {}

class _FixedClock implements AppClock {
  _FixedClock(this._now);
  final DateTime _now;

  @override
  DateTime now() => _now;
}

void main() {
  late MockAppDatabase mockDb;
  late MockFundamentalRepository mockFundRepo;
  late MockMarketDataRepository mockMarketRepo;
  late FundamentalSyncer syncer;

  final date = DateTime(2026, 7, 29);

  StockMasterEntry otcStock(String symbol) => StockMasterEntry(
    symbol: symbol,
    name: '測試$symbol',
    market: MarketCode.tpex,
    isActive: true,
    updatedAt: date,
  );

  setUp(() {
    mockDb = MockAppDatabase();
    mockFundRepo = MockFundamentalRepository();
    mockMarketRepo = MockMarketDataRepository();
    syncer = FundamentalSyncer(
      database: mockDb,
      fundamentalRepository: mockFundRepo,
      marketDataRepository: mockMarketRepo,
      clock: _FixedClock(date),
    );

    when(
      () => mockFundRepo.syncOtcValuation(any(), date: any(named: 'date')),
    ).thenAnswer((_) async => 0);
    when(() => mockFundRepo.syncOtcRevenue(any())).thenAnswer((_) async => 0);
  });

  group('syncOtcCandidatesFundamentals 批次端點候選傳遞', () {
    test('候選超過 100 檔時全數下傳,不得截斷(批次端點與檔數無關)', () async {
      // 270 檔上櫃候選 — 對齊 7/29 生產環境的實際規模
      final symbols = List.generate(270, (i) => (5000 + i).toString());
      when(
        () => mockDb.getStocksByMarket(MarketCode.tpex),
      ).thenAnswer((_) async => symbols.map(otcStock).toList());

      await syncer.syncOtcCandidatesFundamentals(
        candidates: symbols,
        date: date,
      );

      final captured =
          verify(
                () => mockFundRepo.syncOtcValuation(
                  captureAny(),
                  date: any(named: 'date'),
                ),
              ).captured.single
              as List<String>;
      expect(
        captured.length,
        270,
        reason: '估值走 TPEx 全市場批次端點(1 次呼叫),截斷候選只會餓死覆蓋、省不到配額',
      );

      final capturedRevenue =
          verify(
                () => mockFundRepo.syncOtcRevenue(captureAny()),
              ).captured.single
              as List<String>;
      expect(capturedRevenue.length, 270);
    });

    test('非上櫃候選仍被過濾,只下傳上櫃股', () async {
      when(
        () => mockDb.getStocksByMarket(MarketCode.tpex),
      ).thenAnswer((_) async => [otcStock('6226'), otcStock('3441')]);

      await syncer.syncOtcCandidatesFundamentals(
        candidates: ['2330', '6226', '3441', '2317'],
        date: date,
      );

      final captured =
          verify(
                () => mockFundRepo.syncOtcValuation(
                  captureAny(),
                  date: any(named: 'date'),
                ),
              ).captured.single
              as List<String>;
      expect(captured, ['6226', '3441']);
    });
  });
}
