import 'package:daredevil/core/constants/market_codes.dart';
import 'package:daredevil/core/constants/api_config.dart';
import 'package:daredevil/core/constants/data_freshness.dart';
import 'package:daredevil/core/exceptions/app_exception.dart';
import 'package:daredevil/core/utils/date_context.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/data/repositories/price_repository.dart';
import 'package:daredevil/domain/services/update/historical_price_syncer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockAppDatabase extends Mock implements AppDatabase {}

class MockPriceRepository extends Mock implements PriceRepository {}

void main() {
  late MockAppDatabase mockDb;
  late MockPriceRepository mockPriceRepo;
  late HistoricalPriceSyncer syncer;

  final testDate = DateTime(2025, 1, 15);

  /// 建立 N 天的價格資料
  List<DailyPriceEntry> createPrices(
    String symbol,
    int days, {
    DateTime? firstDate,
  }) {
    final start = firstDate ?? testDate.subtract(Duration(days: days));
    return List.generate(
      days,
      (i) => DailyPriceEntry(
        symbol: symbol,
        date: start.add(Duration(days: i)),
        close: 100.0,
      ),
    );
  }

  /// 設定 DB 的 getSymbolsWithSufficientData 回傳值
  void setupSufficientDataSymbols(List<String> symbols) {
    when(
      () => mockDb.getSymbolsWithSufficientData(
        minDays: any(named: 'minDays'),
        startDate: any(named: 'startDate'),
        endDate: any(named: 'endDate'),
      ),
    ).thenAnswer((_) async => symbols);
  }

  /// 設定 DB 的價格覆蓋回傳值（fixtures 仍以 entry list 描述，
  /// 於此導出 PriceCoverage——與 DAO aggregate 同語意，讓既有測試
  /// 全數成為 aggregate 重構的等價證明）
  void setupPriceHistoryBatch(Map<String, List<DailyPriceEntry>> batch) {
    final coverage = <String, PriceCoverage>{};
    for (final entry in batch.entries) {
      final prices = entry.value;
      if (prices.isEmpty) continue;
      var first = prices.first.date;
      var last = prices.first.date;
      final months = <(int, int), int>{};
      for (final p in prices) {
        if (p.date.isBefore(first)) first = p.date;
        if (p.date.isAfter(last)) last = p.date;
        final key = (p.date.year, p.date.month);
        months[key] = (months[key] ?? 0) + 1;
      }
      coverage[entry.key] = PriceCoverage(
        count: prices.length,
        firstDate: first,
        lastDate: last,
        daysByMonth: months,
      );
    }
    when(
      () => mockDb.getPriceCoverageBatch(
        any(),
        startDate: any(named: 'startDate'),
        endDate: any(named: 'endDate'),
      ),
    ).thenAnswer((_) async => coverage);
  }

  /// 設定 PriceRepo 的 syncStockPrices 成功回傳
  void setupSyncSuccess(String symbol, {int count = 10}) {
    when(
      () => mockPriceRepo.syncStockPrices(
        symbol,
        startDate: any(named: 'startDate'),
        endDate: any(named: 'endDate'),
      ),
    ).thenAnswer((_) async => count);
  }

  /// 設定 PriceRepo 的 syncStockPrices 拋出錯誤
  void setupSyncFailure(String symbol) {
    when(
      () => mockPriceRepo.syncStockPrices(
        symbol,
        startDate: any(named: 'startDate'),
        endDate: any(named: 'endDate'),
      ),
    ).thenThrow(Exception('API Error'));
  }

  setUpAll(() {
    registerFallbackValue(DateTime(2020));
    registerFallbackValue(<String>{});
  });

  setUp(() {
    mockDb = MockAppDatabase();
    mockPriceRepo = MockPriceRepository();
    syncer = HistoricalPriceSyncer(
      database: mockDb,
      priceRepository: mockPriceRepo,
    );
    // 市場日快照回補（phase 0）的良性預設：股票主檔為空 → phase 0
    // 直接跳過（fresh DB 防護），既有 per-symbol 測試行為不變。
    when(() => mockDb.getStocksByMarket(any())).thenAnswer((_) async => []);
    // 預算估算的市場查詢預設回空：**全部視為市場未知 → 按上市（逐月）計價**，
    // 與加入分市場計價之前的行為逐字相同，既有測試的期望值因此不變。
    when(
      () => mockDb.getMarketsForSymbolsBatch(any()),
    ).thenAnswer((_) async => <String, String>{});
    // 回補退避的良性預設:無標記、寫入不做事
    when(() => mockDb.getSetting(any())).thenAnswer((_) async => null);
    when(() => mockDb.setSetting(any(), any())).thenAnswer((_) async {});
  });

  group('HistoricalPriceSyncer', () {
    group('syncHistoricalPrices', () {
      test('returns zero when all symbols have sufficient data', () async {
        setupSufficientDataSymbols([]);
        setupPriceHistoryBatch({
          '2330': createPrices('2330', 260),
          '2317': createPrices('2317', 260),
        });

        final result = await syncer.syncHistoricalPrices(
          date: testDate,
          watchlistSymbols: ['2330', '2317'],
          popularStocks: [],
          marketCandidates: [],
        );

        expect(result.syncedCount, 0);
        expect(result.symbolsProcessed, 0);
        verifyNever(
          () => mockPriceRepo.syncStockPrices(
            any(),
            startDate: any(named: 'startDate'),
            endDate: any(named: 'endDate'),
          ),
        );
      });

      test('syncs symbols with zero price data', () async {
        setupSufficientDataSymbols([]);
        setupPriceHistoryBatch({'2330': []});
        setupSyncSuccess('2330', count: 250);

        final result = await syncer.syncHistoricalPrices(
          date: testDate,
          watchlistSymbols: ['2330'],
          popularStocks: [],
          marketCandidates: [],
        );

        expect(result.syncedCount, 250);
        expect(result.symbolsProcessed, 1);
        expect(result.hasErrors, isFalse);
      });

      test(
        'skips non-priority symbols with near-complete data (>= 180 days)',
        () async {
          // firstDate > 365 days ago ensures _hasEnoughDataForAge won't skip
          final oldFirstDate = testDate.subtract(const Duration(days: 400));

          setupSufficientDataSymbols([]);
          setupPriceHistoryBatch({
            'A330': createPrices('A330', 200), // >= 180, should skip
            'A317': createPrices(
              'A317',
              50,
              firstDate: oldFirstDate,
            ), // < 180, needs sync
          });
          setupSyncSuccess('A317', count: 200);

          // 注意：兩檔都 NOT in watchlist/popular → 走 lenient 路徑
          final result = await syncer.syncHistoricalPrices(
            date: testDate,
            watchlistSymbols: [],
            popularStocks: [],
            marketCandidates: ['A330', 'A317'],
          );

          expect(result.syncedCount, 200);
          expect(result.symbolsProcessed, 1);

          // A330 should not be synced (non-priority, >= 180 → lenient skip)
          verifyNever(
            () => mockPriceRepo.syncStockPrices(
              'A330',
              startDate: any(named: 'startDate'),
              endDate: any(named: 'endDate'),
            ),
          );
        },
      );

      // 2026-06 production regression：watchlist/popular 股卡在 200-240 天
      // 區間時，被 nearThreshold (180) 與 _hasEnoughDataForAge 兩個 lenient
      // 早退濾掉，永遠補不到 250 → 52w high/low rule 永久無法觸發。
      // 修正後 priority 股只認嚴格 250 天門檻，會持續 top-up 到 250。
      test(
        'priority stock (watchlist) with 221/250 days is NOT skipped — keeps topping up to 250',
        () async {
          // 模擬 production：2330 在 watchlist，cache 有 221 天，
          // firstDate 約 250 天前（成熟股，age ratio check 會說「夠了」）。
          final oldFirstDate = testDate.subtract(const Duration(days: 250));

          setupSufficientDataSymbols([]);
          setupPriceHistoryBatch({
            '2330': createPrices('2330', 221, firstDate: oldFirstDate),
          });
          setupSyncSuccess('2330', count: 30);

          final result = await syncer.syncHistoricalPrices(
            date: testDate,
            watchlistSymbols: ['2330'],
            popularStocks: [],
            marketCandidates: [],
          );

          // priority 股應該被同步（追到 250）
          expect(result.symbolsProcessed, 1);
          verify(
            () => mockPriceRepo.syncStockPrices(
              '2330',
              startDate: any(named: 'startDate'),
              endDate: any(named: 'endDate'),
            ),
          ).called(1);
        },
      );

      test(
        'priority stock (popular) overrides _hasEnoughDataForAge ratio skip',
        () async {
          // 2454 in popular，cache 200/250 days，age ratio check 認為夠
          // (200/250 ≈ 80% > 50% threshold)。修正前會被 ratio 跳過。
          final oldFirstDate = testDate.subtract(const Duration(days: 250));

          setupSufficientDataSymbols([]);
          setupPriceHistoryBatch({
            '2454': createPrices('2454', 200, firstDate: oldFirstDate),
          });
          setupSyncSuccess('2454', count: 50);

          final result = await syncer.syncHistoricalPrices(
            date: testDate,
            watchlistSymbols: [],
            popularStocks: ['2454'],
            marketCandidates: [],
          );

          expect(result.symbolsProcessed, 1);
          verify(
            () => mockPriceRepo.syncStockPrices(
              '2454',
              startDate: any(named: 'startDate'),
              endDate: any(named: 'endDate'),
            ),
          ).called(1);
        },
      );

      test(
        'priority stock with >= 250 days IS skipped (truly complete)',
        () async {
          // sanity：priority 股若已達 250 仍應跳過，不應無限制呼叫 API
          setupSufficientDataSymbols([]);
          setupPriceHistoryBatch({'2330': createPrices('2330', 260)});

          final result = await syncer.syncHistoricalPrices(
            date: testDate,
            watchlistSymbols: ['2330'],
            popularStocks: [],
            marketCandidates: [],
          );

          expect(result.symbolsProcessed, 0);
          verifyNever(
            () => mockPriceRepo.syncStockPrices(
              '2330',
              startDate: any(named: 'startDate'),
              endDate: any(named: 'endDate'),
            ),
          );
        },
      );

      test('handles partial failures gracefully', () async {
        setupSufficientDataSymbols([]);
        setupPriceHistoryBatch({'2330': [], '2317': []});
        setupSyncSuccess('2330', count: 250);
        setupSyncFailure('2317');

        final result = await syncer.syncHistoricalPrices(
          date: testDate,
          watchlistSymbols: ['2330', '2317'],
          popularStocks: [],
          marketCandidates: [],
        );

        expect(result.syncedCount, 250);
        expect(result.symbolsProcessed, 1);
        expect(result.hasErrors, isTrue);
        expect(result.failedSymbols, contains('2317'));
      });

      test('deduplicates symbols from multiple sources', () async {
        final oldFirstDate = testDate.subtract(const Duration(days: 400));

        setupSufficientDataSymbols(['2330']);
        setupPriceHistoryBatch({
          '2330': createPrices(
            '2330',
            50,
            firstDate: oldFirstDate,
          ), // needs sync
          '2317': createPrices('2317', 260), // sufficient
        });
        setupSyncSuccess('2330', count: 200);

        final result = await syncer.syncHistoricalPrices(
          date: testDate,
          watchlistSymbols: ['2330'],
          popularStocks: ['2330', '2317'],
          marketCandidates: ['2330'],
        );

        // 2330 should only be synced once
        expect(result.symbolsProcessed, 1);
        verify(
          () => mockPriceRepo.syncStockPrices(
            '2330',
            startDate: any(named: 'startDate'),
            endDate: any(named: 'endDate'),
          ),
        ).called(1);
      });

      test('calls onProgress callback', () async {
        setupSufficientDataSymbols([]);
        setupPriceHistoryBatch({'2330': []});
        setupSyncSuccess('2330', count: 10);

        final progressMessages = <String>[];

        await syncer.syncHistoricalPrices(
          date: testDate,
          watchlistSymbols: ['2330'],
          popularStocks: [],
          marketCandidates: [],
          onProgress: progressMessages.add,
        );

        expect(progressMessages, isNotEmpty);
        expect(progressMessages.any((m) => m.contains('歷史資料')), isTrue);
      });
    });

    group('fresh database scenario', () {
      test('syncs popular stocks with only 1 day of data (fresh DB)', () async {
        // Fresh DB: 每檔股票只有今天 1 天資料
        // _hasEnoughDataForAge 會誤判為「剛上市」，但新增的 swingWindow guard 應觸發同步
        setupSufficientDataSymbols([]);
        setupPriceHistoryBatch({
          '2330': createPrices('2330', 1, firstDate: testDate),
          '2317': createPrices('2317', 1, firstDate: testDate),
        });
        setupSyncSuccess('2330', count: 250);
        setupSyncSuccess('2317', count: 250);

        final result = await syncer.syncHistoricalPrices(
          date: testDate,
          watchlistSymbols: [],
          popularStocks: ['2330', '2317'],
          marketCandidates: [],
        );

        expect(result.syncedCount, 500);
        expect(result.symbolsProcessed, 2);
        verify(
          () => mockPriceRepo.syncStockPrices(
            '2330',
            startDate: any(named: 'startDate'),
            endDate: any(named: 'endDate'),
          ),
        ).called(1);
        verify(
          () => mockPriceRepo.syncStockPrices(
            '2317',
            startDate: any(named: 'startDate'),
            endDate: any(named: 'endDate'),
          ),
        ).called(1);
      });
    });

    group('_hasEnoughDataForAge', () {
      test('skips new stock with proportional data', () async {
        // Stock listed 100 days ago with 50 days of data
        // Expected: ~71 trading days, threshold: ~35 days
        // 50 >= 35, should skip
        final firstDate = testDate.subtract(const Duration(days: 100));

        setupSufficientDataSymbols([]);
        setupPriceHistoryBatch({
          '6547': createPrices('6547', 50, firstDate: firstDate),
        });

        final result = await syncer.syncHistoricalPrices(
          date: testDate,
          watchlistSymbols: ['6547'],
          popularStocks: [],
          marketCandidates: [],
        );

        expect(result.syncedCount, 0);
        expect(result.symbolsProcessed, 0);
      });

      test('syncs new stock with insufficient proportional data', () async {
        // Stock listed 100 days ago with only 10 days of data
        // Expected: ~71 trading days, threshold: ~35 days
        // 10 < 35, should sync
        final firstDate = testDate.subtract(const Duration(days: 100));

        setupSufficientDataSymbols([]);
        setupPriceHistoryBatch({
          '6547': createPrices('6547', 10, firstDate: firstDate),
        });
        setupSyncSuccess('6547', count: 60);

        final result = await syncer.syncHistoricalPrices(
          date: testDate,
          watchlistSymbols: ['6547'],
          popularStocks: [],
          marketCandidates: [],
        );

        expect(result.syncedCount, 60);
        expect(result.symbolsProcessed, 1);
      });
    });

    group('_prioritizeSymbols', () {
      test('prioritizes watchlist over popular over others', () async {
        // Create 205 symbols that all need data
        // All have 0 data → avgMonthsPerSymbol ≈ 14
        // Dynamic maxSyncCount = ceil(300/14) = 22
        final allSymbols = List.generate(
          205,
          (i) => 'S${i.toString().padLeft(3, '0')}',
        );
        final watchlistSymbols = [
          'S200',
          'S201',
          'S202',
        ]; // last 3 are watchlist
        final popularSymbols = ['S203', 'S204']; // and 2 popular

        setupSufficientDataSymbols([]);
        setupPriceHistoryBatch(
          Map.fromEntries(
            allSymbols.map((s) => MapEntry(s, <DailyPriceEntry>[])),
          ),
        );

        // Mock getStocksBatch for market-aware prioritization
        when(() => mockDb.getStocksBatch(any())).thenAnswer(
          (_) async => {
            for (final s in allSymbols)
              s: StockMasterEntry(
                symbol: s,
                name: s,
                market: 'TWSE',
                isActive: true,
                updatedAt: testDate,
              ),
          },
        );

        // Setup sync for all
        for (final symbol in allSymbols) {
          setupSyncSuccess(symbol, count: 1);
        }

        final result = await syncer.syncHistoricalPrices(
          date: testDate,
          watchlistSymbols: watchlistSymbols,
          popularStocks: popularSymbols,
          marketCandidates: allSymbols,
        );

        // 0-data symbols: dynamic maxSyncCount = ceil(300/14) = 22
        // 5 priority (3 watchlist + 2 popular) + 17 others = 22
        expect(result.symbolsProcessed, 22);
        expect(result.totalSymbolsNeeded, 205);

        // Watchlist symbols should always be synced
        for (final symbol in watchlistSymbols) {
          verify(
            () => mockPriceRepo.syncStockPrices(
              symbol,
              startDate: any(named: 'startDate'),
              endDate: any(named: 'endDate'),
            ),
          ).called(1);
        }

        // Popular symbols should also be synced
        for (final symbol in popularSymbols) {
          verify(
            () => mockPriceRepo.syncStockPrices(
              symbol,
              startDate: any(named: 'startDate'),
              endDate: any(named: 'endDate'),
            ),
          ).called(1);
        }
      });
    });

    // 2026-06 production regression：早期 _estimateAvgMonthsNeeded 對所有
    // 非零 symbol 一律假設 4 月，但 PriceRepository 實際走整個視窗的月份
    // 迴圈，partial-data symbol 若資料分佈零散會打很多 API。低估 budget
    // 讓 maxSyncCount 估高，跑到一半被 TWSE 限流（300 預算實打 1125 次）。
    //
    // 修正後 estimator 鏡像 price_repository 的「< minTradingDaysPerMonth
    // 月份算缺」邏輯，每 symbol 真實計算缺月。
    group('_estimateAvgMonthsNeeded fragmentation regression', () {
      test(
        'fragmented partial data caps syncCount to match real API budget',
        () async {
          // 200 檔每檔在 3 個非連續月各放 3 天 = 9 天總量 + 9 個月缺資料。
          //
          // 視窗 = testDate - historyRequiredDays = 約 250 天 (~12 個月)。
          // 9 天遠 < nearThreshold(180) → _findSymbolsNeedingData 不會早退。
          // firstTradeDate 在約 12 個月前 → _hasEnoughDataForAge 期望 ~85 天
          // (300×0.71×0.5)，9 天遠不足 → 進佇列。
          //
          // OLD estimator: 200 檔 × 4 月 = 800 → maxSyncCount = ceil(300/4) = 75
          //   會嘗試同步 75 檔，但真實 calls = 75 × 9 月 ≈ 675 → 超 budget 2.25 倍
          // NEW estimator: 200 檔 × 9 月 = 1800 → maxSyncCount = ceil(300/9) = 34
          //   只同步 ~34 檔，真實 calls ≈ 306 ≈ budget，不超

          final allSymbols = List.generate(
            200,
            (i) => 'F${i.toString().padLeft(3, '0')}',
          );

          // 每 symbol 在 3 個非連續月各放 3 天，oldest-first 排序（DAO 行為）
          List<DailyPriceEntry> fragmentedPrices(String symbol) {
            final out = <DailyPriceEntry>[];
            // 反向：先放最早 → 最新（符合 DAO `OrderingTerm.asc(date)`）
            for (final monthOffset in [10, 6, 2]) {
              // testDate.month - 10 = -9 → Dart 自動 normalize 到前一年
              final monthStart = DateTime(
                testDate.year,
                testDate.month - monthOffset,
                5,
              );
              for (var i = 0; i < 3; i++) {
                out.add(
                  DailyPriceEntry(
                    symbol: symbol,
                    date: monthStart.add(Duration(days: i)),
                    close: 100.0,
                  ),
                );
              }
            }
            return out;
          }

          setupSufficientDataSymbols([]);
          setupPriceHistoryBatch({
            for (final s in allSymbols) s: fragmentedPrices(s),
          });
          when(() => mockDb.getStocksBatch(any())).thenAnswer(
            (_) async => {
              for (final s in allSymbols)
                s: StockMasterEntry(
                  symbol: s,
                  name: s,
                  market: 'TWSE',
                  isActive: true,
                  updatedAt: testDate,
                ),
            },
          );
          for (final s in allSymbols) {
            setupSyncSuccess(s, count: 1);
          }

          final result = await syncer.syncHistoricalPrices(
            date: testDate,
            watchlistSymbols: [],
            popularStocks: [],
            marketCandidates: allSymbols,
          );

          expect(result.totalSymbolsNeeded, 200);

          // 核心斷言：修正後 maxSyncCount 應反映真實 API 成本（~9 月/檔）
          // 預期 symbolsProcessed ~34（300/9 budget），絕不應 ≥ 75（OLD bug 值）。
          // 用寬容區間避免月份邊界數字計算與測試環境差異產生 noise。
          expect(
            result.symbolsProcessed,
            lessThanOrEqualTo(45),
            reason:
                'maxSyncCount should cap to real API budget (~34), '
                'NOT old over-optimistic 75 from constant-4 partialMonths',
          );
          expect(
            result.symbolsProcessed,
            greaterThanOrEqualTo(20),
            reason:
                'cap should not be absurdly low — '
                'budget 300 / max(15) ≥ 20',
          );
        },
      );

      test(
        'zero-data symbol estimates full window (≈14 months) — not constant fallback',
        () async {
          // Fresh DB 場景對照組：完全沒資料的 symbol 應該估算成整個視窗
          // (~14 個月)，而不是被誤判成「partial」(舊 constant 4)。
          // 這個 case 在修法前後行為應一致，作為 sanity check。
          final allSymbols = List.generate(
            100,
            (i) => 'Z${i.toString().padLeft(3, '0')}',
          );
          setupSufficientDataSymbols([]);
          setupPriceHistoryBatch({for (final s in allSymbols) s: []});
          when(() => mockDb.getStocksBatch(any())).thenAnswer(
            (_) async => {
              for (final s in allSymbols)
                s: StockMasterEntry(
                  symbol: s,
                  name: s,
                  market: 'TWSE',
                  isActive: true,
                  updatedAt: testDate,
                ),
            },
          );
          for (final s in allSymbols) {
            setupSyncSuccess(s, count: 1);
          }

          final result = await syncer.syncHistoricalPrices(
            date: testDate,
            watchlistSymbols: [],
            popularStocks: [],
            marketCandidates: allSymbols,
          );

          // 100 檔 × ~14 月 → maxSyncCount = ceil(300/14) = 22。
          // 寬容區間：22 ± 2 涵蓋 9 / 10 月視窗的邊界。
          expect(result.totalSymbolsNeeded, 100);
          expect(
            result.symbolsProcessed,
            inInclusiveRange(18, 28),
            reason:
                'fresh DB: 100 stocks × ~14 months = ~1400 calls, '
                'budget 300 → maxSyncCount around 21-22',
          );
        },
      );
    });

    group('市場日快照回補（phase 0）', () {
      // testDate = 2025-01-15（週三）。窗內鄰近交易日：
      // 1/14（二）、1/13（一）、1/10（五）；1/11-12 為週末。
      final tue = DateTime(2025, 1, 14);
      final mon = DateTime(2025, 1, 13);

      StockMasterEntry stockEntry(String symbol, String market) =>
          StockMasterEntry(
            symbol: symbol,
            name: symbol,
            market: market,
            isActive: true,
            updatedAt: testDate,
          );

      List<StockMasterEntry> twseStocks(int n) =>
          List.generate(n, (i) => stockEntry('11$i', 'TWSE'));
      List<StockMasterEntry> tpexStocks(int n) =>
          List.generate(n, (i) => stockEntry('33$i', 'TPEx'));

      /// 測試用 syncer：市場日回補呼叫間不延遲（避免測試等待真實時間）
      late HistoricalPriceSyncer fastSyncer;

      /// phase 1（per-symbol）快速通過：無任何需求
      void setupEmptyPerSymbolPhase() {
        setupSufficientDataSymbols([]);
        setupPriceHistoryBatch({});
      }

      /// count 回應器：預設每日皆完整，[missingTwseDays] 內的日子缺漏
      ///
      /// 以 grouped 語意 stub（market → ymd → count）：缺漏日**不出現**在
      /// Map 中（真實 GROUP BY 只會產生 COUNT>=1 的組），scanner 以 ?? 0
      /// 處理缺鍵。
      void setupDayCounts({
        Set<DateTime> missingTwseDays = const {},
        int twseComplete = 10,
        int tpexComplete = 8,
      }) {
        when(
          () => mockDb.getPriceCountsByDayAndMarket(
            startDate: any(named: 'startDate'),
            endDate: any(named: 'endDate'),
          ),
        ).thenAnswer((inv) async {
          final start = inv.namedArguments[#startDate] as DateTime;
          final end = inv.namedArguments[#endDate] as DateTime;
          final twse = <String, int>{};
          final tpex = <String, int>{};
          for (
            var d = DateTime(start.year, start.month, start.day);
            !d.isAfter(end);
            d = d.add(const Duration(days: 1))
          ) {
            final key = DateContext.formatYmd(d);
            if (!missingTwseDays.contains(d)) twse[key] = twseComplete;
            tpex[key] = tpexComplete;
          }
          return {'TWSE': twse, 'TPEx': tpex};
        });
      }

      void setupTwseBackfill(int rowsPerDay) {
        when(
          () => mockPriceRepo.backfillTwsePricesByDate(
            date: any(named: 'date'),
            targetSymbols: any(named: 'targetSymbols'),
          ),
        ).thenAnswer((_) async => rowsPerDay);
      }

      setUp(() {
        fastSyncer = HistoricalPriceSyncer(
          database: mockDb,
          priceRepository: mockPriceRepo,
          marketDayCallDelay: Duration.zero,
        );
        when(
          () => mockDb.getStocksByMarket('TWSE'),
        ).thenAnswer((_) async => twseStocks(10));
        when(
          () => mockDb.getStocksByMarket('TPEx'),
        ).thenAnswer((_) async => tpexStocks(8));
        setupEmptyPerSymbolPhase();
      });

      test('缺漏市場日觸發整市場回補（新→舊、只補缺的市場）', () async {
        setupDayCounts(missingTwseDays: {tue, mon});
        setupTwseBackfill(800);

        final result = await fastSyncer.syncHistoricalPrices(
          date: testDate,
          watchlistSymbols: [],
          popularStocks: [],
          marketCandidates: [],
        );

        final captured = verify(
          () => mockPriceRepo.backfillTwsePricesByDate(
            date: captureAny(named: 'date'),
            targetSymbols: captureAny(named: 'targetSymbols'),
          ),
        ).captured;
        // 兩次呼叫、新→舊
        expect(captured[0], tue);
        expect(captured[2], mon);
        // targetSymbols = 該市場全部股票
        expect(captured[1], twseStocks(10).map((s) => s.symbol).toSet());
        // TPEx 每日完整 → 不呼叫
        verifyNever(
          () => mockPriceRepo.backfillTpexPricesByDate(
            date: any(named: 'date'),
            targetSymbols: any(named: 'targetSymbols'),
          ),
        );
        // 週末不列入缺漏檢查——上方 captured 斷言已證明只回補 tue/mon
        // （grouped 掃描下不再有 per-day 查詢可供 verifyNever）
        // 回補列數進 result（含 phase 1 early-return 路徑）
        expect(result.marketDayRows, 1600);
      });

      test('單次更新的回補呼叫數受上限保護、且由最近日開始', () async {
        setupDayCounts(
          missingTwseDays: {
            // 窗內全部日子都缺（用寬鬆 750 天涵蓋整個 lookback 窗）
            for (var i = 1; i <= 750; i++) testDate.subtract(Duration(days: i)),
          },
        );
        setupTwseBackfill(5);

        await fastSyncer.syncHistoricalPrices(
          date: testDate,
          watchlistSymbols: [],
          popularStocks: [],
          marketCandidates: [],
        );

        final captured = verify(
          () => mockPriceRepo.backfillTwsePricesByDate(
            date: captureAny(named: 'date'),
            targetSymbols: any(named: 'targetSymbols'),
          ),
        ).captured;
        expect(
          captured.length,
          ApiConfig.historicalMarketDayMaxCallsPerRun,
          reason: '上限保護：單次更新最多補 N 個市場日',
        );
        expect(captured.first, tue, reason: '最近的缺漏交易日優先');
      });

      test('連續零筆中止（端點失效防護），且 phase 1 照常執行', () async {
        setupDayCounts(
          missingTwseDays: {
            for (var i = 1; i <= 750; i++) testDate.subtract(Duration(days: i)),
          },
        );
        setupTwseBackfill(0);

        final result = await fastSyncer.syncHistoricalPrices(
          date: testDate,
          watchlistSymbols: [],
          popularStocks: [],
          marketCandidates: [],
        );

        verify(
          () => mockPriceRepo.backfillTwsePricesByDate(
            date: any(named: 'date'),
            targetSymbols: any(named: 'targetSymbols'),
          ),
        ).called(ApiConfig.historicalMarketDayMaxConsecutiveZeroDays);
        expect(result.marketDayRows, 0);
        // phase 1 未被 phase 0 中止
        verify(
          () => mockDb.getSymbolsWithSufficientData(
            minDays: any(named: 'minDays'),
            startDate: any(named: 'startDate'),
            endDate: any(named: 'endDate'),
          ),
        ).called(1);
      });

      test('RateLimit 中止 phase 0、不外拋、phase 1 照常執行', () async {
        setupDayCounts(missingTwseDays: {tue, mon});
        when(
          () => mockPriceRepo.backfillTwsePricesByDate(
            date: any(named: 'date'),
            targetSymbols: any(named: 'targetSymbols'),
          ),
        ).thenThrow(const RateLimitException());

        final result = await fastSyncer.syncHistoricalPrices(
          date: testDate,
          watchlistSymbols: [],
          popularStocks: [],
          marketCandidates: [],
        );

        verify(
          () => mockPriceRepo.backfillTwsePricesByDate(
            date: any(named: 'date'),
            targetSymbols: any(named: 'targetSymbols'),
          ),
        ).called(1);
        expect(result.marketDayRows, 0);
        verify(
          () => mockDb.getSymbolsWithSufficientData(
            minDays: any(named: 'minDays'),
            startDate: any(named: 'startDate'),
            endDate: any(named: 'endDate'),
          ),
        ).called(1);
      });

      test('股票主檔為空（fresh DB）→ phase 0 全跳過', () async {
        when(() => mockDb.getStocksByMarket(any())).thenAnswer((_) async => []);

        final result = await fastSyncer.syncHistoricalPrices(
          date: testDate,
          watchlistSymbols: [],
          popularStocks: [],
          marketCandidates: [],
        );

        verifyNever(
          () => mockDb.getPriceCountsByDayAndMarket(
            startDate: any(named: 'startDate'),
            endDate: any(named: 'endDate'),
          ),
        );
        verifyNever(
          () => mockPriceRepo.backfillTwsePricesByDate(
            date: any(named: 'date'),
            targetSymbols: any(named: 'targetSymbols'),
          ),
        );
        expect(result.marketDayRows, 0);
      });

      test('單日失敗（DatabaseException）不中斷後續日子', () async {
        setupDayCounts(missingTwseDays: {tue, mon});
        var call = 0;
        when(
          () => mockPriceRepo.backfillTwsePricesByDate(
            date: any(named: 'date'),
            targetSymbols: any(named: 'targetSymbols'),
          ),
        ).thenAnswer((_) async {
          call++;
          if (call == 1) throw const DatabaseException('單日失敗');
          return 700;
        });

        final result = await fastSyncer.syncHistoricalPrices(
          date: testDate,
          watchlistSymbols: [],
          popularStocks: [],
          marketCandidates: [],
        );

        verify(
          () => mockPriceRepo.backfillTwsePricesByDate(
            date: any(named: 'date'),
            targetSymbols: any(named: 'targetSymbols'),
          ),
        ).called(2);
        expect(result.marketDayRows, 700);
      });
    });
  });

  // 上櫃股被當成上市股計價，動態上限被高估壓低
  //
  // `PriceRepository.syncStockPrices`（price_repository.dart:172-183）依市場
  // 分流：
  //   上櫃 → `_tpexSource.fetchSingleStockPrices(startDate, endDate)` 整段 **1 次**
  //   上市 → `_twseSource.fetchMonthlyPrices(months: monthsToFetch)` **逐月**
  // 但 `_estimateAvgMonthsNeeded` 完全不分市場，一律以「需要幾個月＝幾次呼叫」
  // 計價，再用 `maxSyncCount = historicalPriceMaxMonthlyApiCalls / avgMonths`
  // 壓低每輪可同步檔數。
  //
  // 2026-07-27 正式日誌實證：
  //   [HistoricalPriceSyncer] 需要歷史資料: 8291(138 天,起:6/23)
  //   [HistoricalPriceSyncer] 每檔平均需 8.0 個月 API 呼叫，動態限制為 38 檔
  //   [FinMind] TaiwanStockPrice(8291): 138 筆      ← **只有這一行 = 1 次呼叫**
  // 8291 尚茂為 TPEx（DB 實查）→ 估 8 次、實際 1 次，高估 8 倍。
  // Fresh DB（avgMonths≈14）時高估可達 14 倍。
  //
  // 影響面校正：穩態下節流綁不住（當日只有 1 檔需要、上限 38），只有冷啟動
  // 或長期未開才會綁。DB 現況 TPEx 57 檔 / TWSE 62 檔不足 250 日。
  // 故這是**回補速度**問題，不影響正確性。
  //
  // **估錯方向不對稱**：高估只是慢，低估會讓上限放大到打爆 FinMind 配額。
  // 因此市場未知時一律按上市（逐月）計價。
  group('歷史價格預算：上櫃整段 1 次呼叫，不得按月計價', () {
    test('🚨 上櫃股每檔只算 1 次呼叫（實測 8291 估 8 次、實際 1 次）', () async {
      final symbols = [for (var i = 0; i < 60; i++) '5${400 + i}'];
      setupSufficientDataSymbols([]);
      setupPriceHistoryBatch({});
      when(
        () => mockDb.getMarketsForSymbolsBatch(any()),
      ).thenAnswer((_) async => {for (final s in symbols) s: MarketCode.tpex});
      for (final sym in symbols) {
        setupSyncSuccess(sym);
      }

      await syncer.syncHistoricalPrices(
        date: testDate,
        watchlistSymbols: symbols,
        popularStocks: [],
        marketCandidates: [],
      );

      // 全上櫃 → avgMonths 應為 1 → maxSyncCount = 300 → 10 檔全部同步
      for (final sym in symbols) {
        verify(
          () => mockPriceRepo.syncStockPrices(
            sym,
            startDate: any(named: 'startDate'),
            endDate: any(named: 'endDate'),
          ),
        ).called(1);
      }
    });

    test('🚨 市場未知時必須按上市（逐月）計價——低估會打爆配額', () async {
      final symbols = [for (var i = 0; i < 60; i++) '9${100 + i}'];
      setupSufficientDataSymbols([]);
      setupPriceHistoryBatch({});
      // DAO 查不到這些 symbol（主檔尚未同步 / 已下市）
      when(
        () => mockDb.getMarketsForSymbolsBatch(any()),
      ).thenAnswer((_) async => <String, String>{});
      for (final sym in symbols) {
        setupSyncSuccess(sym);
      }

      await syncer.syncHistoricalPrices(
        date: testDate,
        watchlistSymbols: symbols,
        popularStocks: [],
        marketCandidates: [],
      );

      final synced = verify(
        () => mockPriceRepo.syncStockPrices(
          captureAny(),
          startDate: any(named: 'startDate'),
          endDate: any(named: 'endDate'),
        ),
      ).captured.length;

      expect(
        synced,
        lessThan(symbols.length),
        reason:
            '整個視窗（historyRequiredDays）跨約 9 個月，未知市場按逐月計價 → '
            'maxSyncCount ≈ 300/9 ≈ 33 < 60。若把未知當成上櫃（1 次），'
            '上限會放大到 300，冷啟動時足以打爆 FinMind 的 600/hr',
      );
    });

    test('對照組：上市股維持逐月計價，行為不變', () async {
      final symbols = [for (var i = 0; i < 60; i++) '2${400 + i}'];
      setupSufficientDataSymbols([]);
      setupPriceHistoryBatch({});
      when(
        () => mockDb.getMarketsForSymbolsBatch(any()),
      ).thenAnswer((_) async => {for (final s in symbols) s: MarketCode.twse});
      for (final sym in symbols) {
        setupSyncSuccess(sym);
      }

      await syncer.syncHistoricalPrices(
        date: testDate,
        watchlistSymbols: symbols,
        popularStocks: [],
        marketCandidates: [],
      );

      final synced = verify(
        () => mockPriceRepo.syncStockPrices(
          captureAny(),
          startDate: any(named: 'startDate'),
          endDate: any(named: 'endDate'),
        ),
      ).captured.length;

      expect(
        synced,
        lessThan(symbols.length),
        reason: '上市維持逐月計價，60 檔應被節流；不得因本次修法變寬鬆',
      );
    });
  });

  // 撞 FinMind 限流時，coordinator 無從得知 —— 止血旗標翻不起來
  //
  // phase 1 的 per-symbol 迴圈在 historical_price_syncer.dart:636-643 捕捉
  // RateLimitException，設**區域變數** `rateLimited`（:602）中止迴圈，
  // 但既不 rethrow、也不放進 [HistoricalPriceSyncResult]。
  //
  // 於是 update_service.dart 的 `_syncHistoricalData`：
  //   - :549 的 `on RateLimitException` 永遠不觸發 → ctx.rateLimitedAbort 恆 false
  //   - 失敗只走 `ctx.result.errors.add(...)`（**不是 recordError**）
  //     → UpdateResult.hasRateLimitError 也恆 false
  // 兩者都是「限流被降級成一般失敗」，與 1bf5040 修掉的 ParallelWaitError
  // 是同一個 bug class 的另一處。
  //
  // **不 rethrow 是對的**：整段歷史回補不該因為配額用完就算全失敗，
  // 已抓到的資料要保留。缺的是把「為什麼中止」帶出去。
  //
  // 影響面校正（2026-07-27 一併查證，故非 high）：
  //   配額用完後 finmind_client 的 checkBudget 會在發網路請求前擋下，
  //   下游步驟不會真的送出請求、也不會多燒配額；且自 1bf5040 起步驟 4.7
  //   會自己設起旗標。真正的損害是**歷史價格這一段的失敗被誤分類**，
  //   日誌只寫「歷史資料同步失敗 (N 檔)」，事後追查配額問題時語意消失。
  group('限流中止必須讓 caller 分辨得出來', () {
    test('🚨 撞限流時 result 要帶出原始例外，不能只當成「N 檔失敗」', () async {
      setupSufficientDataSymbols([]);
      setupPriceHistoryBatch({'2330': createPrices('2330', 5)});
      when(
        () => mockDb.getStocksBatch(any()),
      ).thenAnswer((_) async => <String, StockMasterEntry>{});
      when(
        () => mockPriceRepo.syncStockPrices(
          any(),
          startDate: any(named: 'startDate'),
          endDate: any(named: 'endDate'),
        ),
      ).thenThrow(const RateLimitException());

      final result = await syncer.syncHistoricalPrices(
        date: testDate,
        watchlistSymbols: ['2330'],
        popularStocks: [],
        marketCandidates: [],
      );

      expect(
        result.rateLimitError,
        isA<RateLimitException>(),
        reason:
            'coordinator 要靠這個設 rateLimitedAbort 並走 recordError；'
            '只有 failedSymbols 的話「限流」與「個股資料異常」無法分辨',
      );
      expect(result.rateLimited, isTrue);
      expect(result.failedSymbols, isNotEmpty, reason: '既有語意不變：限流中止的檔仍算失敗');
    });

    test('對照組：一般失敗不得被誤標成限流', () async {
      setupSufficientDataSymbols([]);
      setupPriceHistoryBatch({'2330': createPrices('2330', 5)});
      when(
        () => mockDb.getStocksBatch(any()),
      ).thenAnswer((_) async => <String, StockMasterEntry>{});
      setupSyncFailure('2330');

      final result = await syncer.syncHistoricalPrices(
        date: testDate,
        watchlistSymbols: ['2330'],
        popularStocks: [],
        marketCandidates: [],
      );

      expect(result.failedSymbols, isNotEmpty);
      expect(
        result.rateLimited,
        isFalse,
        reason: 'DatabaseException / 格式錯誤不該讓整條更新進入止血模式',
      );
      expect(result.rateLimitError, isNull);
    });

    test('對照組：全部成功時不得誤報限流', () async {
      setupSufficientDataSymbols([]);
      setupPriceHistoryBatch({'2330': createPrices('2330', 5)});
      when(
        () => mockDb.getStocksBatch(any()),
      ).thenAnswer((_) async => <String, StockMasterEntry>{});
      setupSyncSuccess('2330');

      final result = await syncer.syncHistoricalPrices(
        date: testDate,
        watchlistSymbols: ['2330'],
        popularStocks: [],
        marketCandidates: [],
      );

      expect(result.rateLimited, isFalse);
      expect(result.rateLimitError, isNull);
    });
  });

  group('回補退避(2026-08-14 假進度收斂:8291 連日重打實錄)', () {
    // 8291 尚茂:窗內密度 48.6% 永遠低於 50% 門檻,FinMind 已無更多資料,
    // 每天白燒 1 個配額(2026-07-27 起)。設計=時間退避:成功抓取但覆蓋
    // 無成長 → 記日期,退避期內跳過,期滿重試(自癒,浪費有上界)。
    List<DailyPriceEntry> thinStock() => createPrices(
      '8291',
      139,
      firstDate: testDate.subtract(const Duration(days: 400)),
    );

    test('🚨 成功抓取但覆蓋無成長 → 寫入退避標記', () async {
      setupSufficientDataSymbols([]);
      setupPriceHistoryBatch({'8291': thinStock()});
      setupSyncSuccess('8291', count: 124); // 假進度:有寫入但全是重寫既有列

      await syncer.syncHistoricalPrices(
        date: testDate,
        watchlistSymbols: [],
        popularStocks: [],
        marketCandidates: ['8291'],
      );

      final captured = verify(
        () => mockDb.setSetting(
          DataFreshness.historicalBackfillBackoffKey,
          captureAny(),
        ),
      ).captured;
      expect(captured, isNotEmpty, reason: '無成長必須留下退避標記');
      expect(captured.last as String, contains('8291'));
    });

    test('🚨 退避期內 → 跳過不打 API', () async {
      when(
        () => mockDb.getSetting(DataFreshness.historicalBackfillBackoffKey),
      ).thenAnswer((_) async => '{"8291":"2025-01-10"}'); // 5 天前,期內
      setupSufficientDataSymbols([]);
      setupPriceHistoryBatch({'8291': thinStock()});

      await syncer.syncHistoricalPrices(
        date: testDate,
        watchlistSymbols: [],
        popularStocks: [],
        marketCandidates: ['8291'],
      );

      verifyNever(
        () => mockPriceRepo.syncStockPrices(
          '8291',
          startDate: any(named: 'startDate'),
          endDate: any(named: 'endDate'),
        ),
      );
    });

    test('🚨 標記日在未來(時鐘回撥)→ 視同無標記重試,不得永久封鎖', () async {
      // date.difference(未來標記) 為負 → 永遠 < 30 → 若不防護該股被鎖到未來
      when(
        () => mockDb.getSetting(DataFreshness.historicalBackfillBackoffKey),
      ).thenAnswer((_) async => '{"8291":"2025-06-01"}'); // testDate 之後
      setupSufficientDataSymbols([]);
      setupPriceHistoryBatch({'8291': thinStock()});
      setupSyncSuccess('8291', count: 124);

      await syncer.syncHistoricalPrices(
        date: testDate,
        watchlistSymbols: [],
        popularStocks: [],
        marketCandidates: ['8291'],
      );

      verify(
        () => mockPriceRepo.syncStockPrices(
          '8291',
          startDate: any(named: 'startDate'),
          endDate: any(named: 'endDate'),
        ),
      ).called(1);
    });

    test('寫回時 prune 已過期標記(下市股不會在表裡永久殘留)', () async {
      // 9999 的標記早已期滿且本輪不在候選內(如已下市)——過期標記與
      // 不存在行為等價,寫回時順手清掉,表大小以「近 30 天內停滯股」為界
      when(
        () => mockDb.getSetting(DataFreshness.historicalBackfillBackoffKey),
      ).thenAnswer((_) async => '{"9999":"2024-01-01"}');
      setupSufficientDataSymbols([]);
      setupPriceHistoryBatch({'8291': thinStock()});
      setupSyncSuccess('8291', count: 124);

      await syncer.syncHistoricalPrices(
        date: testDate,
        watchlistSymbols: [],
        popularStocks: [],
        marketCandidates: ['8291'],
      );

      final captured = verify(
        () => mockDb.setSetting(
          DataFreshness.historicalBackfillBackoffKey,
          captureAny(),
        ),
      ).captured;
      expect(captured.last as String, contains('8291'));
      expect(
        captured.last as String,
        isNot(contains('9999')),
        reason: '過期標記必須被 prune,否則表只增不減',
      );
    });

    test('🚨 退避表讀取失敗 → 本輪不寫回(不得把整表洗成空)', () async {
      // fail-open 回空表只該影響「跳過」判斷;若接著整表覆寫,一次讀取
      // 故障就會抹掉全部既有標記,配額洩漏全面回歸
      when(
        () => mockDb.getSetting(DataFreshness.historicalBackfillBackoffKey),
      ).thenThrow(Exception('模擬 settings 讀取故障'));
      setupSufficientDataSymbols([]);
      setupPriceHistoryBatch({'8291': thinStock()});
      setupSyncSuccess('8291', count: 124);

      final result = await syncer.syncHistoricalPrices(
        date: testDate,
        watchlistSymbols: [],
        popularStocks: [],
        marketCandidates: ['8291'],
      );

      expect(result.succeededSymbols, ['8291'], reason: '同步本體不得受退避故障影響');
      verifyNever(
        () => mockDb.setSetting(
          DataFreshness.historicalBackfillBackoffKey,
          any(),
        ),
      );
    });

    test('退避期滿 → 重試一次(FinMind 可能有新資料)', () async {
      when(
        () => mockDb.getSetting(DataFreshness.historicalBackfillBackoffKey),
      ).thenAnswer((_) async => '{"8291":"2024-11-01"}'); // 75 天前,期滿
      setupSufficientDataSymbols([]);
      setupPriceHistoryBatch({'8291': thinStock()});
      setupSyncSuccess('8291', count: 124);

      await syncer.syncHistoricalPrices(
        date: testDate,
        watchlistSymbols: [],
        popularStocks: [],
        marketCandidates: ['8291'],
      );

      verify(
        () => mockPriceRepo.syncStockPrices(
          '8291',
          startDate: any(named: 'startDate'),
          endDate: any(named: 'endDate'),
        ),
      ).called(1);
    });

    test('🚨 覆蓋有成長 → 清除既有標記(自癒,不會永久封鎖)', () async {
      when(
        () => mockDb.getSetting(DataFreshness.historicalBackfillBackoffKey),
      ).thenAnswer((_) async => '{"8291":"2024-11-01"}'); // 期滿重試
      setupSufficientDataSymbols([]);
      // 兩段式覆蓋:需求掃描時 139,同步後重查 150(有成長)
      var calls = 0;
      final pre = {'8291': thinStock()};
      final post = {
        '8291': createPrices(
          '8291',
          150,
          firstDate: testDate.subtract(const Duration(days: 400)),
        ),
      };
      when(
        () => mockDb.getPriceCoverageBatch(
          any(),
          startDate: any(named: 'startDate'),
          endDate: any(named: 'endDate'),
        ),
      ).thenAnswer((_) async {
        calls++;
        final src = calls == 1 ? pre : post;
        final out = <String, PriceCoverage>{};
        for (final e in src.entries) {
          final months = <(int, int), int>{};
          for (final p in e.value) {
            final k = (p.date.year, p.date.month);
            months[k] = (months[k] ?? 0) + 1;
          }
          out[e.key] = PriceCoverage(
            count: e.value.length,
            firstDate: e.value.first.date,
            lastDate: e.value.last.date,
            daysByMonth: months,
          );
        }
        return out;
      });
      setupSyncSuccess('8291', count: 150);

      await syncer.syncHistoricalPrices(
        date: testDate,
        watchlistSymbols: [],
        popularStocks: [],
        marketCandidates: ['8291'],
      );

      final captured = verify(
        () => mockDb.setSetting(
          DataFreshness.historicalBackfillBackoffKey,
          captureAny(),
        ),
      ).captured;
      expect(captured, isNotEmpty);
      expect(
        captured.last as String,
        isNot(contains('8291')),
        reason: '成長後標記必須清除——退避不可變成永久封鎖',
      );
    });
  });
}
