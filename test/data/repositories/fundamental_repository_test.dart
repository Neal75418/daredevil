import 'package:daredevil/core/exceptions/app_exception.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/data/remote/finmind_client.dart';
import 'package:daredevil/data/remote/mops_client.dart';
import 'package:daredevil/data/remote/tpex_client.dart';
import 'package:daredevil/data/remote/twse_client.dart';
import 'package:daredevil/data/repositories/fundamental_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockAppDatabase extends Mock implements AppDatabase {}

class MockFinMindClient extends Mock implements FinMindClient {}

class MockTwseClient extends Mock implements TwseClient {}

class MockTpexClient extends Mock implements TpexClient {}

class MockMopsClient extends Mock implements MopsClient {}

void main() {
  late MockAppDatabase mockDb;
  late MockFinMindClient mockFinMind;
  late MockTwseClient mockTwse;
  late MockTpexClient mockTpex;
  late FundamentalRepository repo;

  setUpAll(() {
    registerFallbackValue(<StockValuationCompanion>[]);
  });

  setUp(() {
    mockDb = MockAppDatabase();
    mockFinMind = MockFinMindClient();
    mockTwse = MockTwseClient();
    mockTpex = MockTpexClient();
    repo = FundamentalRepository(
      mops: MockMopsClient(),
      db: mockDb,
      finMind: mockFinMind,
      twse: mockTwse,
      tpex: mockTpex,
    );
  });

  // ==========================================
  // syncMonthlyRevenue
  // ==========================================
  group('syncMonthlyRevenue', () {
    test('returns 0 when API returns empty data', () async {
      when(
        () => mockFinMind.getMonthlyRevenue(
          stockId: any(named: 'stockId'),
          startDate: any(named: 'startDate'),
          endDate: any(named: 'endDate'),
        ),
      ).thenAnswer((_) async => []);

      final result = await repo.syncMonthlyRevenue(
        symbol: '2330',
        startDate: DateTime(2025, 1, 1),
        endDate: DateTime(2025, 1, 31),
      );

      expect(result, equals(0));
    });

    test('rethrows RateLimitException', () async {
      when(
        () => mockFinMind.getMonthlyRevenue(
          stockId: any(named: 'stockId'),
          startDate: any(named: 'startDate'),
          endDate: any(named: 'endDate'),
        ),
      ).thenThrow(const RateLimitException('Rate limited'));

      await expectLater(
        () => repo.syncMonthlyRevenue(
          symbol: '2330',
          startDate: DateTime(2025, 1, 1),
          endDate: DateTime(2025, 1, 31),
        ),
        throwsA(isA<RateLimitException>()),
      );
    });

    test('wraps other exceptions as DatabaseException', () async {
      // 之前 return 0 屬於 silent failure（caller 看不出來是 0 筆還是壞了）。
      // 修為包成 DatabaseException 讓 upstream catch (e) 仍可降級但保留 cause。
      when(
        () => mockFinMind.getMonthlyRevenue(
          stockId: any(named: 'stockId'),
          startDate: any(named: 'startDate'),
          endDate: any(named: 'endDate'),
        ),
      ).thenThrow(Exception('unknown'));

      await expectLater(
        repo.syncMonthlyRevenue(
          symbol: '2330',
          startDate: DateTime(2025, 1, 1),
          endDate: DateTime(2025, 1, 31),
        ),
        throwsA(isA<DatabaseException>()),
      );
      verify(
        () => mockFinMind.getMonthlyRevenue(
          stockId: any(named: 'stockId'),
          startDate: any(named: 'startDate'),
          endDate: any(named: 'endDate'),
        ),
      ).called(1);
    });
  });

  // ==========================================
  // syncValuationData
  // ==========================================
  group('syncValuationData', () {
    test('returns 0 when API returns empty data', () async {
      when(
        () => mockFinMind.getPERData(
          stockId: any(named: 'stockId'),
          startDate: any(named: 'startDate'),
          endDate: any(named: 'endDate'),
        ),
      ).thenAnswer((_) async => []);

      final result = await repo.syncValuationData(
        symbol: '2330',
        startDate: DateTime(2025, 1, 1),
        endDate: DateTime(2025, 1, 31),
      );

      expect(result, equals(0));
    });

    test('rethrows RateLimitException', () async {
      when(
        () => mockFinMind.getPERData(
          stockId: any(named: 'stockId'),
          startDate: any(named: 'startDate'),
          endDate: any(named: 'endDate'),
        ),
      ).thenThrow(const RateLimitException('Rate limited'));

      await expectLater(
        () => repo.syncValuationData(
          symbol: '2330',
          startDate: DateTime(2025, 1, 1),
          endDate: DateTime(2025, 1, 31),
        ),
        throwsA(isA<RateLimitException>()),
      );
    });

    test('估值日期正規化：含時間的 date → 持久化時去除時間（防 PK 重複膨脹）', () async {
      final captured = <List<StockValuationCompanion>>[];
      when(
        () => mockFinMind.getPERData(
          stockId: any(named: 'stockId'),
          startDate: any(named: 'startDate'),
          endDate: any(named: 'endDate'),
        ),
      ).thenAnswer(
        (_) async => const [
          FinMindPER(
            stockId: '2330',
            date: '2026-06-23T14:30:00', // 含時間戳
            per: 30,
            pbr: 5,
            dividendYield: 2,
          ),
        ],
      );
      when(() => mockDb.insertValuationData(any())).thenAnswer((
        invocation,
      ) async {
        captured.add(
          invocation.positionalArguments.first as List<StockValuationCompanion>,
        );
      });

      await repo.syncValuationData(
        symbol: '2330',
        startDate: DateTime(2026, 6, 1),
        endDate: DateTime(2026, 6, 30),
      );

      expect(captured, hasLength(1));
      expect(
        captured.first.single.date.value,
        DateTime(2026, 6, 23),
        reason: 'date 須正規化到 00:00、不含時間，否則同日多次同步會產生不同 PK',
      );
    });
  });

  // ==========================================
  // syncAllMarketValuation
  // ==========================================
  group('syncAllMarketValuation', () {
    test('returns 0 when TWSE returns empty data', () async {
      when(() => mockTwse.getAllStockValuation()).thenAnswer((_) async => []);

      final result = await repo.syncAllMarketValuation(DateTime(2025, 1, 15));

      expect(result, equals(0));
    });

    test('rethrows NetworkException', () async {
      when(
        () => mockTwse.getAllStockValuation(),
      ).thenThrow(const NetworkException('Timeout'));

      await expectLater(
        () => repo.syncAllMarketValuation(DateTime(2025, 1, 15)),
        throwsA(isA<NetworkException>()),
      );
    });

    test('wraps other exceptions as DatabaseException', () async {
      // 之前 return 0 屬 silent failure（caller 看不出來是真 0 還是壞了）。
      when(
        () => mockTwse.getAllStockValuation(),
      ).thenThrow(Exception('unknown'));

      await expectLater(
        repo.syncAllMarketValuation(DateTime(2025, 1, 15)),
        throwsA(isA<DatabaseException>()),
      );
    });
  });

  // ==========================================
  // syncTwseValuationForDate
  // ==========================================
  group('syncTwseValuationForDate', () {
    test('BWIBBU_d 回一筆 → 寫入 insertValuationData，日期取自資料本身', () async {
      final captured = <List<StockValuationCompanion>>[];
      when(() => mockTwse.getStockValuationForDate(any())).thenAnswer(
        (_) async => [
          TwseValuation(
            date: DateTime(2026, 9, 24),
            code: '1101',
            per: 10.5,
            pbr: 0.82,
            dividendYield: 3.17,
          ),
        ],
      );
      when(() => mockDb.insertValuationData(any())).thenAnswer((
        invocation,
      ) async {
        captured.add(
          invocation.positionalArguments.first as List<StockValuationCompanion>,
        );
      });

      final result = await repo.syncTwseValuationForDate(DateTime(2026, 9, 24));

      expect(result, 1);
      expect(captured, hasLength(1));
      final companion = captured.single.single;
      expect(companion.symbol.value, '1101');
      expect(companion.date.value, DateTime(2026, 9, 24));
      expect(companion.per.value, 10.5);
    });
  });

  // ==========================================
  // syncOtcValuation
  // ==========================================
  group('syncOtcValuation', () {
    test('returns 0 for empty symbols', () async {
      final result = await repo.syncOtcValuation([]);

      expect(result, equals(0));
    });

    test('rethrows NetworkException', () async {
      // Skip freshness check by using force
      when(
        () => mockTpex.getAllValuation(date: any(named: 'date')),
      ).thenThrow(const NetworkException('Timeout'));

      await expectLater(
        () => repo.syncOtcValuation(['6547'], force: true),
        throwsA(isA<NetworkException>()),
      );
    });
  });

  // ==========================================
  // syncAllMarketRevenue
  // ==========================================
  group('syncAllMarketRevenue', () {
    test('returns 0 when API returns empty data', () async {
      when(() => mockTwse.getAllMonthlyRevenue()).thenAnswer((_) async => []);

      final result = await repo.syncAllMarketRevenue(DateTime(2025, 1, 15));

      expect(result, equals(0));
    });

    test('rethrows NetworkException', () async {
      when(
        () => mockTwse.getAllMonthlyRevenue(),
      ).thenThrow(const NetworkException('Timeout'));

      await expectLater(
        () => repo.syncAllMarketRevenue(DateTime(2025, 1, 15)),
        throwsA(isA<NetworkException>()),
      );
    });
  });
}
