import 'dart:async';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/data/remote/tpex_client.dart';
import 'package:daredevil/data/remote/twse_client.dart';
import 'package:daredevil/core/constants/market_codes.dart';
import 'package:daredevil/core/exceptions/app_exception.dart';
import 'package:daredevil/core/utils/clock.dart';
import 'package:daredevil/data/repositories/warning_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockAppDatabase extends Mock implements AppDatabase {}

class MockTpexClient extends Mock implements TpexClient {}

class MockTwseClient extends Mock implements TwseClient {}

class _FixedClock implements AppClock {
  const _FixedClock(this._now);
  final DateTime _now;
  @override
  DateTime now() => _now;
}

void main() {
  late MockAppDatabase mockDb;
  late MockTpexClient mockTpexClient;
  late MockTwseClient mockTwseClient;
  late WarningRepository repository;

  setUp(() {
    mockDb = MockAppDatabase();
    mockTpexClient = MockTpexClient();
    mockTwseClient = MockTwseClient();
    repository = WarningRepository(
      database: mockDb,
      tpexClient: mockTpexClient,
      twseClient: mockTwseClient,
    );
  });

  group('WarningRepository', () {
    group('getWatchlistWarnings', () {
      test('returns only warnings for symbols in watchlist', () async {
        // 全市場有多筆警示，但只有部分在自選股中
        final allWarnings = [
          _createWarning(symbol: 'AAA', warningType: 'ATTENTION'),
          _createWarning(symbol: 'BBB', warningType: 'DISPOSAL'),
          _createWarning(symbol: 'CCC', warningType: 'ATTENTION'),
          _createWarning(symbol: 'DDD', warningType: 'ATTENTION'),
        ];

        when(
          () => mockDb.getAllActiveWarnings(),
        ).thenAnswer((_) async => allWarnings);

        final result = await repository.getWatchlistWarnings(['AAA', 'CCC']);

        expect(result.length, equals(2));
        expect(result.keys, containsAll(['AAA', 'CCC']));
        expect(result.keys, isNot(contains('BBB')));
        expect(result.keys, isNot(contains('DDD')));
      });

      test('DISPOSAL takes priority over ATTENTION for same symbol', () async {
        // 同一股票同時有注意和處置警示，處置優先
        final allWarnings = [
          _createWarning(symbol: 'TEST', warningType: 'ATTENTION'),
          _createWarning(symbol: 'TEST', warningType: 'DISPOSAL'),
        ];

        when(
          () => mockDb.getAllActiveWarnings(),
        ).thenAnswer((_) async => allWarnings);

        final result = await repository.getWatchlistWarnings(['TEST']);

        expect(result.length, equals(1));
        expect(result['TEST']!.warningType, equals('DISPOSAL'));
      });

      test('returns empty map when watchlist is empty', () async {
        final result = await repository.getWatchlistWarnings([]);

        expect(result, isEmpty);
        verifyNever(() => mockDb.getAllActiveWarnings());
      });

      test('returns empty map when no warnings match watchlist', () async {
        final allWarnings = [
          _createWarning(symbol: 'AAA', warningType: 'ATTENTION'),
          _createWarning(symbol: 'BBB', warningType: 'DISPOSAL'),
        ];

        when(
          () => mockDb.getAllActiveWarnings(),
        ).thenAnswer((_) async => allWarnings);

        final result = await repository.getWatchlistWarnings([
          'XXX',
          'YYY',
          'ZZZ',
        ]);

        expect(result, isEmpty);
      });
    });

    group('getDisposalStocksBatch', () {
      test('returns set of disposal symbols', () async {
        final disposalSet = {'AAA', 'CCC'};

        when(
          () => mockDb.getDisposalStocksBatch(['AAA', 'BBB', 'CCC']),
        ).thenAnswer((_) async => disposalSet);

        final result = await repository.getDisposalStocksBatch([
          'AAA',
          'BBB',
          'CCC',
        ]);

        expect(result, equals(disposalSet));
        expect(result.contains('AAA'), isTrue);
        expect(result.contains('BBB'), isFalse);
        expect(result.contains('CCC'), isTrue);
      });
    });
  });

  group('syncAllMarketWarnings 接線層（HIGH bug 的實際住所）', () {
    final tradingDay = DateTime(2026, 7, 24, 18); // 週五交易日

    late WarningRepository repo;

    void stubDbAndDisposals() {
      when(
        () => mockDb.getLatestWarningSyncTime(),
      ).thenAnswer((_) async => null);
      when(
        () => mockDb.getWarningCountForDate(any()),
      ).thenAnswer((_) async => 0);
      when(() => mockDb.getAllActiveStocks()).thenAnswer((_) async => []);
      when(() => mockDb.insertWarningData(any())).thenAnswer((_) async {});
      when(
        () => mockDb.updateExpiredWarnings(now: any(named: 'now')),
      ).thenAnswer((_) async => 0);
      when(
        () => mockDb.deactivateStaleAttentionWarnings(
          currentSymbols: any(named: 'currentSymbols'),
          syncedMarkets: any(named: 'syncedMarkets'),
          syncDate: any(named: 'syncDate'),
        ),
      ).thenAnswer((_) async => 0);
      when(
        () => mockTwseClient.getDisposalInfo(date: any(named: 'date')),
      ).thenAnswer((_) async => []);
      when(() => mockTpexClient.getDisposalInfo()).thenAnswer((_) async => []);
      when(() => mockDb.transaction<int>(any())).thenAnswer(
        (inv) => (inv.positionalArguments[0] as Future<int> Function())(),
      );
    }

    setUp(() {
      repo = WarningRepository(
        database: mockDb,
        tpexClient: mockTpexClient,
        twseClient: mockTwseClient,
        clock: _FixedClock(tradingDay),
      );
      stubDbAndDisposals();
    });

    Set<String> capturedSyncedMarkets() {
      final captured = verify(
        () => mockDb.deactivateStaleAttentionWarnings(
          currentSymbols: any(named: 'currentSymbols'),
          syncedMarkets: captureAny(named: 'syncedMarkets'),
          syncDate: any(named: 'syncDate'),
        ),
      ).captured;
      return captured.single as Set<String>;
    }

    test('🚨 來源回空清單的市場不得進 syncedMarkets（否則整市場被清空）', () async {
      // client 在 decodeResponseData 回 null 或 stat != 'OK' 時是 return []
      // 而非拋例外 → 呼叫端收不到例外、會誤判為同步成功。
      when(
        () => mockTwseClient.getTradingWarnings(date: any(named: 'date')),
      ).thenAnswer((_) async => []);
      when(() => mockTpexClient.getTradingWarnings()).thenAnswer(
        (_) async => [
          TpexTradingWarning(
            date: tradingDay,
            code: '3088',
            warningType: 'ATTENTION',
          ),
        ],
      );

      await repo.syncAllMarketWarnings();

      expect(capturedSyncedMarkets(), {
        MarketCode.tpex,
      }, reason: 'TWSE 回空清單無法與「今日真的沒有」區分，不得當權威名單');
    });

    test('非交易日不得把 TWSE 當已同步', () async {
      final holidayRepo = WarningRepository(
        database: mockDb,
        tpexClient: mockTpexClient,
        twseClient: mockTwseClient,
        clock: _FixedClock(DateTime(2026, 7, 25, 18)), // 週六
      );
      when(() => mockTpexClient.getTradingWarnings()).thenAnswer(
        (_) async => [
          TpexTradingWarning(
            date: DateTime(2026, 7, 25),
            code: '3088',
            warningType: 'ATTENTION',
          ),
        ],
      );

      await holidayRepo.syncAllMarketWarnings();

      expect(capturedSyncedMarkets(), {
        MarketCode.tpex,
      }, reason: 'TWSE 端點在非交易日被跳過，不該被當成取得了權威名單');
    });

    test('兩市場都取得非空名單時，兩者都進 syncedMarkets', () async {
      when(
        () => mockTwseClient.getTradingWarnings(date: any(named: 'date')),
      ).thenAnswer(
        (_) async => [
          TwseTradingWarning(
            date: tradingDay,
            code: '2330',
            warningType: 'ATTENTION',
          ),
        ],
      );
      when(() => mockTpexClient.getTradingWarnings()).thenAnswer(
        (_) async => [
          TpexTradingWarning(
            date: tradingDay,
            code: '3088',
            warningType: 'ATTENTION',
          ),
        ],
      );

      await repo.syncAllMarketWarnings();

      expect(capturedSyncedMarkets(), {MarketCode.twse, MarketCode.tpex});
    });
  });

  group('syncAllMarketWarnings 雙來源同時斷網(2026-07-30 async 衛生)', () {
    setUpAll(() => registerFallbackValue(DateTime(2026)));

    test('TWSE 注意+處置同時 NetworkException:rethrow 且零 unhandled error', () async {
      // 固定交易日,確保 TWSE 平行分支被執行
      final repo = WarningRepository(
        database: mockDb,
        tpexClient: mockTpexClient,
        twseClient: mockTwseClient,
        clock: _FixedClock(DateTime(2026, 7, 29, 18)),
      );
      when(
        () => mockDb.getLatestWarningSyncTime(),
      ).thenAnswer((_) async => null); // 無同步紀錄 → 走完整同步路徑
      when(
        () => mockTwseClient.getTradingWarnings(date: any(named: 'date')),
      ).thenAnswer((_) async => throw const NetworkException('斷網', null));
      when(
        () => mockTwseClient.getDisposalInfo(date: any(named: 'date')),
      ).thenAnswer((_) async => throw const NetworkException('斷網', null));

      final unhandled = <Object>[];
      Object? thrown;
      // 注意:不可在 runZonedGuarded 內用 expectLater——assertion 失敗的
      // TestFailure 會被 zone handler 攔走,外層 await 永遠不完成(卡 30s
      // timeout)。錯誤不能跨 zone 邊界,zone 內用 try/catch 手動捕捉。
      await runZonedGuarded(() async {
        try {
          await repo.syncAllMarketWarnings();
        } catch (e) {
          thrown = e;
        }
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);
      }, (e, st) => unhandled.add(e));
      expect(thrown, isA<NetworkException>());

      expect(
        unhandled,
        isEmpty,
        reason:
            '第一個 await rethrow 後,第二個 future 的 rejection 不得'
            '成為 zone 層 unhandled async error(舊「先啟動再逐一 await」的病)',
      );
    });
  });
}

/// 建立測試用 TradingWarningEntry
TradingWarningEntry _createWarning({
  required String symbol,
  required String warningType,
  String? reasonCode,
  String? reasonDescription,
  String? disposalMeasures,
  DateTime? disposalStartDate,
  DateTime? disposalEndDate,
  bool isActive = true,
}) {
  return TradingWarningEntry(
    symbol: symbol,
    date: DateTime.now(),
    warningType: warningType,
    reasonCode: reasonCode,
    reasonDescription: reasonDescription,
    disposalMeasures: disposalMeasures,
    disposalStartDate: disposalStartDate,
    disposalEndDate: disposalEndDate,
    isActive: isActive,
  );
}
