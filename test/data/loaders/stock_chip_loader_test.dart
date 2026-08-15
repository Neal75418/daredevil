import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:daredevil/core/utils/clock.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/data/remote/finmind_client.dart';
import 'package:daredevil/data/repositories/insider_repository.dart';
import 'package:daredevil/core/constants/data_freshness.dart';
import 'package:daredevil/data/loaders/stock_chip_loader.dart';

// ==========================================
// Mocks
// ==========================================

class MockAppDatabase extends Mock implements AppDatabase {}

class MockFinMindClient extends Mock implements FinMindClient {}

class MockInsiderRepository extends Mock implements InsiderRepository {}

class _FakeClock implements AppClock {
  @override
  DateTime now() => DateTime(2026, 2, 15, 14, 0);
}

// ==========================================
// Tests
// ==========================================

void main() {
  late MockAppDatabase mockDb;
  late MockFinMindClient mockFinMind;
  late MockInsiderRepository mockInsiderRepo;
  late StockChipLoader loader;

  setUp(() {
    mockDb = MockAppDatabase();
    mockFinMind = MockFinMindClient();
    mockInsiderRepo = MockInsiderRepository();
    loader = StockChipLoader(
      db: mockDb,
      finMind: mockFinMind,
      insiderRepo: mockInsiderRepo,
      clock: _FakeClock(),
    );
  });

  // ==========================================
  // ==========================================
  // loadInsiderFromDb
  // ==========================================

  group('loadInsiderFromDb', () {
    test('returns sorted data (newest first)', () async {
      final entries = [
        InsiderHoldingEntry(
          symbol: '2330',
          date: DateTime(2026, 1, 1),
          pledgeRatio: 0.0,
        ),
        InsiderHoldingEntry(
          symbol: '2330',
          date: DateTime(2026, 2, 1),
          pledgeRatio: 0.0,
        ),
      ];

      when(
        () => mockInsiderRepo.getInsiderHoldingHistory(
          any(),
          months: any(named: 'months'),
        ),
      ).thenAnswer((_) async => entries);

      final result = await loader.loadInsiderFromDb('2330');

      expect(result, hasLength(2));
      // Should be sorted descending (newest first)
      expect(result.first.date.isAfter(result.last.date), isTrue);
    });

    test('returns empty list on error', () async {
      when(
        () => mockInsiderRepo.getInsiderHoldingHistory(
          any(),
          months: any(named: 'months'),
        ),
      ).thenThrow(Exception('DB error'));

      final result = await loader.loadInsiderFromDb('2330');

      expect(result, isEmpty);
    });
  });

  // ==========================================
  // fetchInstitutionalFromApi
  // ==========================================

  group('fetchInstitutionalFromApi', () {
    test('returns data with hasError=false on success', () async {
      final apiData = [
        const FinMindInstitutional(
          stockId: '2330',
          date: '2026-02-14',
          foreignBuy: 5000,
          foreignSell: 3000,
          investmentTrustBuy: 1000,
          investmentTrustSell: 500,
          dealerBuy: 200,
          dealerSell: 100,
        ),
      ];

      when(
        () => mockFinMind.getInstitutionalData(
          stockId: any(named: 'stockId'),
          startDate: any(named: 'startDate'),
          endDate: any(named: 'endDate'),
        ),
      ).thenAnswer((_) async => apiData);

      final result = await loader.fetchInstitutionalFromApi('2330');

      expect(result.hasError, isFalse);
      expect(result.data, hasLength(1));
      expect(result.data.first.symbol, '2330');
    });

    test('returns empty data with hasError=true on failure', () async {
      when(
        () => mockFinMind.getInstitutionalData(
          stockId: any(named: 'stockId'),
          startDate: any(named: 'startDate'),
          endDate: any(named: 'endDate'),
        ),
      ).thenThrow(Exception('API error'));

      final result = await loader.fetchInstitutionalFromApi('2330');

      expect(result.hasError, isTrue);
      expect(result.data, isEmpty);
    });
  });

  // ==========================================
  // loadAllChipData
  // ==========================================

  group('loadAllChipData', () {
    test('uses existingInsider when provided', () async {
      final existingInsider = [
        InsiderHoldingEntry(
          symbol: '2330',
          date: DateTime(2026, 2, 1),
          pledgeRatio: 0.0,
        ),
      ];

      when(
        () => mockDb.getDayTradingHistory(
          any(),
          startDate: any(named: 'startDate'),
        ),
      ).thenAnswer((_) async => <DayTradingEntry>[]);
      when(
        () => mockDb.getShareholdingHistory(
          any(),
          startDate: any(named: 'startDate'),
        ),
      ).thenAnswer((_) async => <ShareholdingEntry>[]);
      when(
        () => mockDb.getMarginTradingHistory(
          any(),
          startDate: any(named: 'startDate'),
        ),
      ).thenAnswer((_) async => <MarginTradingEntry>[]);
      when(
        () => mockDb.getLatestHoldingDistribution(any()),
      ).thenAnswer((_) async => <HoldingDistributionEntry>[]);

      final result = await loader.loadAllChipData(
        '2330',
        existingInstitutional: [],
        existingInsider: existingInsider,
      );

      expect(result.insider, hasLength(1));
      // Should NOT call getRecentInsiderHoldings since existingInsider was provided
      verifyNever(
        () => mockDb.getRecentInsiderHoldings(
          any(),
          months: any(named: 'months'),
        ),
      );
    });

    test('fetches insider from DB when existingInsider is empty', () async {
      when(
        () => mockDb.getDayTradingHistory(
          any(),
          startDate: any(named: 'startDate'),
        ),
      ).thenAnswer((_) async => <DayTradingEntry>[]);
      when(
        () => mockDb.getShareholdingHistory(
          any(),
          startDate: any(named: 'startDate'),
        ),
      ).thenAnswer((_) async => <ShareholdingEntry>[]);
      when(
        () => mockDb.getMarginTradingHistory(
          any(),
          startDate: any(named: 'startDate'),
        ),
      ).thenAnswer((_) async => <MarginTradingEntry>[]);
      when(
        () => mockDb.getLatestHoldingDistribution(any()),
      ).thenAnswer((_) async => <HoldingDistributionEntry>[]);
      when(
        () => mockDb.getRecentInsiderHoldings(
          any(),
          months: any(named: 'months'),
        ),
      ).thenAnswer((_) async => <InsiderHoldingEntry>[]);

      final result = await loader.loadAllChipData(
        '2330',
        existingInstitutional: [],
      );

      verify(
        () => mockDb.getRecentInsiderHoldings(
          '2330',
          months: DataFreshness.insiderRecentMonths,
        ),
      ).called(1);
      expect(result.dayTrading, isEmpty);
      expect(result.shareholding, isEmpty);
      expect(result.marginTrading, isEmpty);
      expect(result.holdingDist, isEmpty);
      expect(result.insider, isEmpty);
    });
  });
}
