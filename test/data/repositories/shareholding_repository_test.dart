import 'package:daredevil/core/exceptions/app_exception.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/data/remote/finmind_client.dart';
import 'package:daredevil/data/remote/twse_client.dart';
import 'package:daredevil/data/repositories/shareholding_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockAppDatabase extends Mock implements AppDatabase {}

class MockFinMindClient extends Mock implements FinMindClient {}

class MockTwseClient extends Mock implements TwseClient {}

void main() {
  late MockAppDatabase mockDb;
  late MockFinMindClient mockClient;
  late ShareholdingRepository repo;

  setUp(() {
    mockDb = MockAppDatabase();
    mockClient = MockFinMindClient();
    repo = ShareholdingRepository(
      database: mockDb,
      finMindClient: mockClient,
      twseClient: MockTwseClient(),
    );
  });

  // ==========================================
  // syncShareholding
  // ==========================================
  group('syncShareholding', () {
    test('skips when latest data is same day as target', () async {
      final targetDate = DateTime(2025, 1, 15);
      when(() => mockDb.getLatestShareholding(any())).thenAnswer(
        (_) async => ShareholdingEntry(symbol: '2330', date: targetDate),
      );

      final result = await repo.syncShareholding(
        '2330',
        startDate: DateTime(2025, 1, 1),
        endDate: targetDate,
      );

      expect(result, equals(0));
      verifyNever(
        () => mockClient.getShareholding(
          stockId: any(named: 'stockId'),
          startDate: any(named: 'startDate'),
          endDate: any(named: 'endDate'),
        ),
      );
    });

    test('fetches and inserts data when not fresh', () async {
      when(
        () => mockDb.getLatestShareholding(any()),
      ).thenAnswer((_) async => null);
      when(
        () => mockClient.getShareholding(
          stockId: any(named: 'stockId'),
          startDate: any(named: 'startDate'),
          endDate: any(named: 'endDate'),
        ),
      ).thenAnswer(
        (_) async => [
          const FinMindShareholding(
            stockId: '2330',
            date: '2025-01-15',
            foreignInvestmentRemainingShares: 5000000,
            foreignInvestmentSharesRatio: 75.5,
            foreignInvestmentUpperLimitRatio: 100.0,
            numberOfSharesIssued: 25930381,
          ),
        ],
      );
      when(() => mockDb.insertShareholdingData(any())).thenAnswer((_) async {});

      final result = await repo.syncShareholding(
        '2330',
        startDate: DateTime(2025, 1, 1),
      );

      expect(result, equals(1));
      verify(() => mockDb.insertShareholdingData(any())).called(1);
    });

    test('rethrows RateLimitException', () async {
      when(
        () => mockDb.getLatestShareholding(any()),
      ).thenAnswer((_) async => null);
      when(
        () => mockClient.getShareholding(
          stockId: any(named: 'stockId'),
          startDate: any(named: 'startDate'),
          endDate: any(named: 'endDate'),
        ),
      ).thenThrow(const RateLimitException('Rate limited'));

      await expectLater(
        () => repo.syncShareholding('2330', startDate: DateTime(2025, 1, 1)),
        throwsA(isA<RateLimitException>()),
      );
    });
  });

  // ==========================================
  // Delegation
  // ==========================================
  group('delegation', () {
    test('getLatestShareholding delegates to db and returns result', () async {
      when(
        () => mockDb.getLatestShareholding(any()),
      ).thenAnswer((_) async => null);

      final result = await repo.getLatestShareholding('2330');

      expect(result, isNull);
      verify(() => mockDb.getLatestShareholding('2330')).called(1);
    });

    test(
      'getLatestHoldingDistribution delegates to db and returns result',
      () async {
        when(
          () => mockDb.getLatestHoldingDistribution(any()),
        ).thenAnswer((_) async => []);

        final result = await repo.getLatestHoldingDistribution('2330');

        expect(result, isEmpty);
        verify(() => mockDb.getLatestHoldingDistribution('2330')).called(1);
      },
    );
  });
}
