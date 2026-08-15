import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:daredevil/core/constants/api_config.dart';
import 'package:daredevil/core/exceptions/app_exception.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/data/remote/finmind_client.dart';
import 'package:daredevil/data/remote/twse_client.dart';
import 'package:daredevil/data/repositories/stock_repository.dart';

class MockAppDatabase extends Mock implements AppDatabase {
  @override
  Future<T> transaction<T>(Future<T> Function() action, {bool? requireNew}) {
    return action();
  }
}

class MockFinMindClient extends Mock implements FinMindClient {}

class MockTwseClient extends Mock implements TwseClient {}

// Fake classes for registerFallbackValue
class FakeStockMasterCompanion extends Fake implements StockMasterCompanion {}

void main() {
  setUpAll(() {
    registerFallbackValue(FakeStockMasterCompanion());
    registerFallbackValue(<StockMasterCompanion>[]);
  });

  late MockAppDatabase mockDb;
  late MockFinMindClient mockClient;
  late MockTwseClient mockTwse;
  late StockRepository repository;

  setUp(() {
    mockDb = MockAppDatabase();
    mockClient = MockFinMindClient();
    mockTwse = MockTwseClient();
    // 預設空 map:legacy 測試維持 FinMind fallback 行為(floor 擋殭屍步)
    when(
      () => mockTwse.fetchIndustryCodes(),
    ).thenAnswer((_) async => <String, String>{});
    // 名冊縮水警報的基準(2026-08-15):0 = 無既有規模可比,不觸發警告。
    // 本檔測的是清理判定,警報行為由 stock_roster_shrink_warning_test 專測。
    when(() => mockDb.countActiveOfficialUniverse()).thenAnswer((_) async => 0);
    repository = StockRepository(
      database: mockDb,
      finMindClient: mockClient,
      twseClient: mockTwse,
    );
  });

  group('StockRepository', () {
    group('getAllStocks', () {
      test('returns all active stocks from database', () async {
        final stocks = [
          StockMasterEntry(
            symbol: '2330',
            name: '台積電',
            market: 'TWSE',
            industry: '半導體',
            isActive: true,
            updatedAt: DateTime(2024, 6, 15),
          ),
          StockMasterEntry(
            symbol: '2317',
            name: '鴻海',
            market: 'TWSE',
            industry: '電子',
            isActive: true,
            updatedAt: DateTime(2024, 6, 15),
          ),
        ];

        when(() => mockDb.getAllActiveStocks()).thenAnswer((_) async => stocks);

        final result = await repository.getAllStocks();

        expect(result, equals(stocks));
        expect(result.length, equals(2));
        verify(() => mockDb.getAllActiveStocks()).called(1);
      });

      test('returns empty list when no stocks', () async {
        when(() => mockDb.getAllActiveStocks()).thenAnswer((_) async => []);

        final result = await repository.getAllStocks();

        expect(result, isEmpty);
      });
    });

    group('getStock', () {
      test('returns stock for given symbol', () async {
        final stock = StockMasterEntry(
          symbol: '2330',
          name: '台積電',
          market: 'TWSE',
          industry: '半導體',
          isActive: true,
          updatedAt: DateTime(2024, 6, 15),
        );

        when(() => mockDb.getStock('2330')).thenAnswer((_) async => stock);

        final result = await repository.getStock('2330');

        expect(result, equals(stock));
        expect(result?.name, equals('台積電'));
      });

      test('returns null when stock not found', () async {
        when(() => mockDb.getStock('9999')).thenAnswer((_) async => null);

        final result = await repository.getStock('9999');

        expect(result, isNull);
      });
    });

    // ==================================================
    // TWSE 官方產業別覆蓋(2026-08-01 複審)
    //
    // FinMind TaiwanStockInfo 給上市電子股的分類多為泛用「電子工業」——
    // 實測 305 檔 active 塌陷同一桶(台積電/聯發科/大立光在內),上市
    // 「半導體業」卡只剩 29 檔且混著下市殭屍;產業排行整組失真。
    // 官方 t187ap03_L(免額度)才有細分碼:2330→24(半導體業)。
    // ==================================================
    group('TWSE 官方產業別覆蓋', () {
      late MockTwseClient mockTwse;

      setUp(() {
        mockTwse = MockTwseClient();
        repository = StockRepository(
          database: mockDb,
          finMindClient: mockClient,
          twseClient: mockTwse,
        );
        when(() => mockDb.upsertStocks(any())).thenAnswer((_) async {});
        when(
          () => mockDb.deactivateStocksNotIn(any()),
        ).thenAnswer((_) async => 0);
      });

      List<StockMasterCompanion> capturedEntries() =>
          verify(() => mockDb.upsertStocks(captureAny())).captured.single
              as List<StockMasterCompanion>;

      test('🚨 官方碼覆蓋 FinMind 泛用「電子工業」:2330→半導體業', () async {
        when(() => mockClient.getStockList()).thenAnswer(
          (_) async => const [
            FinMindStockInfo(
              stockId: '2330',
              stockName: '台積電',
              industryCategory: '電子工業',
              type: 'twse',
            ),
          ],
        );
        // 名單須 ≥ floor 才可信(三態語意);補足量假名單
        when(() => mockTwse.fetchIndustryCodes()).thenAnswer(
          (_) async => {
            for (
              var i = 1000;
              i < 1000 + ApiConfig.twseOfficialListSanityFloor + 100;
              i++
            )
              '$i': '20',
            '2330': '24',
          },
        );

        await repository.syncStockList();

        final entry = capturedEntries().single;
        expect(entry.industry.value, '半導體業');
        expect(entry.isActive.value, isTrue, reason: '官方在冊=存活(自癒)');
      });

      // 2026-08-05 複審調整:改用上櫃股承載——dedup 邏輯市場無關,而
      // 上市股在官方名單不可用時 industry 已改為不寫入,無從驗證 dedup。
      test('FinMind 同 symbol 重複列:細分優先,泛用列在後不得覆蓋', () async {
        when(() => mockClient.getStockList()).thenAnswer(
          (_) async => const [
            FinMindStockInfo(
              stockId: '3450',
              stockName: '聯鈞',
              industryCategory: '半導體業',
              type: 'tpex',
            ),
            FinMindStockInfo(
              stockId: '3450',
              stockName: '聯鈞',
              industryCategory: '電子工業',
              type: 'tpex',
            ),
          ],
        );
        when(
          () => mockTwse.fetchIndustryCodes(),
        ).thenAnswer((_) async => <String, String>{});

        final count = await repository.syncStockList();

        expect(count, 1, reason: '同 symbol 去重後只寫一筆');
        expect(capturedEntries().single.industry.value, '半導體業');
      });

      // 2026-08-05 複審修正:原斷言「沿用 FinMind 分類」實為**降級覆寫**
      // ——fail-soft 輪會把 1,087 檔上一輪已正確的官方分類整批洗成
      // FinMind taxonomy(生技 61→27、冒出官方不存在的「化學生技醫療」),
      // 產業卡組成週際翻覆。三態語意:官方權威範圍(上市 4 碼非 ETF)
      // 狀態未知時,industry 與 isActive 一律不寫入、保留 DB 現值。
      test('官方端點失敗 fail-soft:上市股 industry/isActive 皆不寫入(保留現值)', () async {
        when(() => mockClient.getStockList()).thenAnswer(
          (_) async => const [
            FinMindStockInfo(
              stockId: '2330',
              stockName: '台積電',
              industryCategory: '電子工業',
              type: 'twse',
            ),
          ],
        );
        when(
          () => mockTwse.fetchIndustryCodes(),
        ).thenThrow(const NetworkException('boom'));

        final count = await repository.syncStockList();

        expect(count, 1);
        final entry = capturedEntries().single;
        expect(entry.industry.present, isFalse, reason: '不得以 FinMind 降級覆寫官方分類');
        expect(entry.isActive.present, isFalse, reason: '不得復活已停用殭屍');
      });

      test('上櫃股不套上市官方碼(TPEx 分類本就細分正確)', () async {
        when(() => mockClient.getStockList()).thenAnswer(
          (_) async => const [
            FinMindStockInfo(
              stockId: '6488',
              stockName: '環球晶',
              industryCategory: '半導體業',
              type: 'tpex',
            ),
          ],
        );
        when(
          () => mockTwse.fetchIndustryCodes(),
        ).thenAnswer((_) async => {'6488': '26'});

        await repository.syncStockList();

        expect(capturedEntries().single.industry.value, '半導體業');
      });
    });

    // ==================================================
    // 官方名單殭屍清理(2026-08-01)
    //
    // FinMind 持續回傳已下市股(華亞科 2016 下市仍 type=twse),
    // deactivateStocksNotIn 永遠排除不到——實測 135 檔 active 殭屍,
    // 全部近月零價格資料(絕不誤殺交易中標的的實證)。官方 t187ap03_L
    // 名單缺席=下市。防護:sanity floor 擋部分回應、DR 自校準守衛
    // (官方名單當輪含 91xx 才對 DR 適用;實測名單涵蓋交易中 DR)。
    // ==================================================
    group('官方名單殭屍清理', () {
      late MockTwseClient mockTwse;

      /// 產生過 sanity floor 的官方名單(引用常數,floor 調整自動跟隨)
      Map<String, String> bigOfficial(Map<String, String> extra) => {
        for (var i = 0; i < ApiConfig.twseOfficialListSanityFloor + 100; i++)
          '${1000 + i}': '01',
        ...extra,
      };

      setUp(() {
        mockTwse = MockTwseClient();
        repository = StockRepository(
          database: mockDb,
          finMindClient: mockClient,
          twseClient: mockTwse,
        );
        when(() => mockDb.upsertStocks(any())).thenAnswer((_) async {});
        when(
          () => mockDb.deactivateStocksNotIn(any()),
        ).thenAnswer((_) async => 0);
      });

      List<StockMasterCompanion> capturedEntries() =>
          verify(() => mockDb.upsertStocks(captureAny())).captured.single
              as List<StockMasterCompanion>;

      const zombie = FinMindStockInfo(
        stockId: '3474',
        stockName: '華亞科',
        industryCategory: '半導體業',
        type: 'twse',
      );
      const alive = FinMindStockInfo(
        stockId: '2330',
        stockName: '台積電',
        industryCategory: '電子工業',
        type: 'twse',
      );

      test('🚨 官方名單缺席的上市 4 碼標 inactive;在冊者維持 active', () async {
        when(
          () => mockClient.getStockList(),
        ).thenAnswer((_) async => const [zombie, alive]);
        when(
          () => mockTwse.fetchIndustryCodes(),
        ).thenAnswer((_) async => bigOfficial({'2330': '24'}));

        await repository.syncStockList();

        final bySymbol = {for (final e in capturedEntries()) e.symbol.value: e};
        expect(bySymbol['3474']!.isActive.value, isFalse, reason: '下市殭屍');
        expect(bySymbol['2330']!.isActive.value, isTrue);
      });

      test('ETF(00 開頭)與上櫃股不受官方名單影響', () async {
        when(() => mockClient.getStockList()).thenAnswer(
          (_) async => const [
            FinMindStockInfo(
              stockId: '0050',
              stockName: '元大台灣50',
              industryCategory: 'ETF',
              type: 'twse',
            ),
            FinMindStockInfo(
              stockId: '5483',
              stockName: '中美晶',
              industryCategory: '半導體業',
              type: 'tpex',
            ),
          ],
        );
        when(
          () => mockTwse.fetchIndustryCodes(),
        ).thenAnswer((_) async => bigOfficial({}));

        await repository.syncStockList();

        for (final e in capturedEntries()) {
          expect(e.isActive.value, isTrue, reason: '${e.symbol.value} 不在清理範圍');
        }
      });

      test('DR 自校準守衛:官方名單含 91xx 時死 DR 清掉、不含時 DR 一律不動', () async {
        const deadDr = FinMindStockInfo(
          stockId: '9104',
          stockName: '萬宇科',
          industryCategory: '存託憑證',
          type: 'twse',
        );
        when(
          () => mockClient.getStockList(),
        ).thenAnswer((_) async => const [deadDr]);

        // 官方名單含交易中 DR(9103)→ 涵蓋 DR → 缺席的 9104 清掉
        when(
          () => mockTwse.fetchIndustryCodes(),
        ).thenAnswer((_) async => bigOfficial({'9103': '22'}));
        await repository.syncStockList();
        expect(capturedEntries().single.isActive.value, isFalse);

        // 官方名單無任何 91xx → DR 涵蓋性存疑 → 「不動」=不寫入
        // (2026-08-05 複審修正:原斷言 isTrue 把「守衛跳過=復活死股」
        // 鎖成規格——上一輪已停用的 9104 會被寫回 active。三態語意下
        // 未知一律 absent,保留 DB 現值)
        when(
          () => mockTwse.fetchIndustryCodes(),
        ).thenAnswer((_) async => bigOfficial({}));
        await repository.syncStockList();
        expect(
          capturedEntries().single.isActive.present,
          isFalse,
          reason: '守衛跳過時不得寫入 isActive,否則復活已停用殭屍',
        );
      });

      // 2026-08-05 複審修正:原斷言「industry 覆蓋照常」在三態語意下
      // 不再成立——floor 觸發代表整份名單不可信,industry 也一律不寫入
      // (上一輪的官方分類保留在 DB,不套用可疑的部分名單零損失)。
      test('官方名單過小(部分回應)→ 清理與 industry 皆不寫入(保留現值)', () async {
        when(
          () => mockClient.getStockList(),
        ).thenAnswer((_) async => const [zombie, alive]);
        when(
          () => mockTwse.fetchIndustryCodes(),
        ).thenAnswer((_) async => {'2330': '24'}); // 僅 1 家,遠低於 floor

        await repository.syncStockList();

        final bySymbol = {for (final e in capturedEntries()) e.symbol.value: e};
        expect(
          bySymbol['3474']!.isActive.present,
          isFalse,
          reason: '名單不完整時不得誤殺、也不得復活——一律不寫入',
        );
        expect(
          bySymbol['2330']!.industry.present,
          isFalse,
          reason: '可疑名單不得套用;上一輪官方分類保留於 DB',
        );
        expect(bySymbol['2330']!.isActive.present, isFalse);
      });
    });

    group('syncStockList', () {
      test('syncs valid 4-digit stock codes', () async {
        final stockInfos = [
          const FinMindStockInfo(
            stockId: '2330',
            stockName: '台積電',
            industryCategory: '半導體',
            type: 'twse',
          ),
          const FinMindStockInfo(
            stockId: '2317',
            stockName: '鴻海',
            industryCategory: '電子',
            type: 'twse',
          ),
        ];

        when(
          () => mockClient.getStockList(),
        ).thenAnswer((_) async => stockInfos);
        when(() => mockDb.upsertStocks(any())).thenAnswer((_) async {});
        when(
          () => mockDb.deactivateStocksNotIn(any()),
        ).thenAnswer((_) async => 0);

        final result = await repository.syncStockList();

        expect(result, equals(2));
        verify(() => mockDb.upsertStocks(any())).called(1);
      });

      test('syncs ETF codes starting with 00', () async {
        final stockInfos = [
          const FinMindStockInfo(
            stockId: '0050',
            stockName: '元大台灣50',
            industryCategory: 'ETF',
            type: 'twse',
          ),
          const FinMindStockInfo(
            stockId: '00878',
            stockName: '國泰永續高股息',
            industryCategory: 'ETF',
            type: 'twse',
          ),
        ];

        when(
          () => mockClient.getStockList(),
        ).thenAnswer((_) async => stockInfos);
        when(() => mockDb.upsertStocks(any())).thenAnswer((_) async {});
        when(
          () => mockDb.deactivateStocksNotIn(any()),
        ).thenAnswer((_) async => 0);

        final result = await repository.syncStockList();

        expect(result, equals(2));
      });

      test('filters out invalid stock codes (warrants, TDR)', () async {
        final stockInfos = [
          const FinMindStockInfo(
            stockId: '2330',
            stockName: '台積電',
            industryCategory: '半導體',
            type: 'twse',
          ),
          const FinMindStockInfo(
            stockId: '233001',
            stockName: '台積電權證',
            industryCategory: '權證',
            type: 'twse',
          ),
          const FinMindStockInfo(
            stockId: '9101',
            stockName: 'TDR',
            industryCategory: 'TDR',
            type: 'twse',
          ),
        ];

        when(
          () => mockClient.getStockList(),
        ).thenAnswer((_) async => stockInfos);
        when(() => mockDb.upsertStocks(any())).thenAnswer((_) async {});
        when(
          () => mockDb.deactivateStocksNotIn(any()),
        ).thenAnswer((_) async => 0);

        final result = await repository.syncStockList();

        // Only 2330 is valid (4 digits), 233001 is 6 digits (warrant), 9101 has 4 digits but counts
        expect(result, equals(2)); // 2330 and 9101 are 4 digits
      });

      test('deactivates stocks not in API response', () async {
        final stockInfos = [
          const FinMindStockInfo(
            stockId: '2330',
            stockName: '台積電',
            industryCategory: '半導體',
            type: 'twse',
          ),
        ];

        when(
          () => mockClient.getStockList(),
        ).thenAnswer((_) async => stockInfos);
        when(() => mockDb.upsertStocks(any())).thenAnswer((_) async {});
        when(
          () => mockDb.deactivateStocksNotIn(any()),
        ).thenAnswer((_) async => 3);

        await repository.syncStockList();

        final captured = verify(
          () => mockDb.deactivateStocksNotIn(captureAny()),
        ).captured;
        final activeSymbols = captured.first as Set<String>;
        expect(activeSymbols, equals({'2330'}));
      });

      test('rethrows RateLimitException', () async {
        when(
          () => mockClient.getStockList(),
        ).thenThrow(const RateLimitException());

        await expectLater(
          () => repository.syncStockList(),
          throwsA(isA<RateLimitException>()),
        );
      });

      test('wraps other exceptions in DatabaseException', () async {
        when(() => mockClient.getStockList()).thenThrow(Exception('API error'));

        await expectLater(
          () => repository.syncStockList(),
          throwsA(isA<DatabaseException>()),
        );
      });

      test('wraps database exceptions in DatabaseException', () async {
        final stockInfos = [
          const FinMindStockInfo(
            stockId: '2330',
            stockName: '台積電',
            industryCategory: '半導體',
            type: 'twse',
          ),
        ];

        when(
          () => mockClient.getStockList(),
        ).thenAnswer((_) async => stockInfos);
        when(() => mockDb.upsertStocks(any())).thenThrow(Exception('DB error'));
        when(
          () => mockDb.deactivateStocksNotIn(any()),
        ).thenAnswer((_) async => 0);

        await expectLater(
          () => repository.syncStockList(),
          throwsA(isA<DatabaseException>()),
        );
      });
    });

    group('searchStocks', () {
      test('searches stocks by query', () async {
        final stocks = [
          StockMasterEntry(
            symbol: '2330',
            name: '台積電',
            market: 'TWSE',
            industry: '半導體',
            isActive: true,
            updatedAt: DateTime(2024, 6, 15),
          ),
        ];

        when(() => mockDb.searchStocks('台積')).thenAnswer((_) async => stocks);

        final result = await repository.searchStocks('台積');

        expect(result, equals(stocks));
        expect(result.length, equals(1));
        verify(() => mockDb.searchStocks('台積')).called(1);
      });

      test('returns empty list when no matches', () async {
        when(() => mockDb.searchStocks('xyz')).thenAnswer((_) async => []);

        final result = await repository.searchStocks('xyz');

        expect(result, isEmpty);
      });

      test('searches by symbol', () async {
        final stocks = [
          StockMasterEntry(
            symbol: '2330',
            name: '台積電',
            market: 'TWSE',
            industry: '半導體',
            isActive: true,
            updatedAt: DateTime(2024, 6, 15),
          ),
        ];

        when(() => mockDb.searchStocks('2330')).thenAnswer((_) async => stocks);

        final result = await repository.searchStocks('2330');

        expect(result.length, equals(1));
        expect(result.first.symbol, equals('2330'));
      });
    });

    group('getStocksByMarket', () {
      test('returns stocks for TWSE market', () async {
        final stocks = [
          StockMasterEntry(
            symbol: '2330',
            name: '台積電',
            market: 'TWSE',
            industry: '半導體',
            isActive: true,
            updatedAt: DateTime(2024, 6, 15),
          ),
        ];

        when(
          () => mockDb.getStocksByMarket('TWSE'),
        ).thenAnswer((_) async => stocks);

        final result = await repository.getStocksByMarket('TWSE');

        expect(result, equals(stocks));
        verify(() => mockDb.getStocksByMarket('TWSE')).called(1);
      });

      test('returns stocks for TPEx market', () async {
        final stocks = [
          StockMasterEntry(
            symbol: '3008',
            name: '大立光',
            market: 'TPEx',
            industry: '光電',
            isActive: true,
            updatedAt: DateTime(2024, 6, 15),
          ),
        ];

        when(
          () => mockDb.getStocksByMarket('TPEx'),
        ).thenAnswer((_) async => stocks);

        final result = await repository.getStocksByMarket('TPEx');

        expect(result, equals(stocks));
        expect(result.first.market, equals('TPEx'));
      });

      test('returns empty list when no stocks in market', () async {
        when(
          () => mockDb.getStocksByMarket('UNKNOWN'),
        ).thenAnswer((_) async => []);

        final result = await repository.getStocksByMarket('UNKNOWN');

        expect(result, isEmpty);
      });
    });
  });

  group('Stock code validation pattern', () {
    // Test the regex pattern used in syncStockList
    final validStockPattern = RegExp(r'^(\d{4}|00\d{3,4})$');

    test('accepts 4-digit stock codes', () {
      expect(validStockPattern.hasMatch('2330'), isTrue);
      expect(validStockPattern.hasMatch('2317'), isTrue);
      expect(validStockPattern.hasMatch('0050'), isTrue);
      expect(validStockPattern.hasMatch('9999'), isTrue);
    });

    test('accepts 00xxx ETF codes', () {
      expect(validStockPattern.hasMatch('00878'), isTrue);
      expect(validStockPattern.hasMatch('00679'), isTrue);
      expect(validStockPattern.hasMatch('006208'), isTrue);
    });

    test('rejects 6-digit warrant codes', () {
      expect(validStockPattern.hasMatch('233001'), isFalse);
      expect(validStockPattern.hasMatch('231701'), isFalse);
    });

    test('rejects 3-digit codes', () {
      expect(validStockPattern.hasMatch('233'), isFalse);
      expect(validStockPattern.hasMatch('050'), isFalse);
    });

    test('rejects codes with letters', () {
      expect(validStockPattern.hasMatch('2330A'), isFalse);
      expect(validStockPattern.hasMatch('AAPL'), isFalse);
    });
  });
}
