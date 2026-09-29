import 'dart:async';
import 'package:daredevil/core/constants/api_config.dart';
import 'package:daredevil/core/constants/default_stocks.dart';
import 'package:daredevil/core/utils/logger.dart';
import 'package:daredevil/core/constants/rule_enums.dart';
import 'package:daredevil/core/exceptions/app_exception.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/data/remote/tdcc_client.dart';
import 'package:daredevil/data/remote/api_budget_tracker.dart';
import 'package:daredevil/data/remote/finmind_client.dart';
import 'package:daredevil/data/remote/tpex_client.dart';
import 'package:daredevil/data/remote/twse_client.dart';
import 'package:daredevil/data/repositories/analysis_repository.dart';
import 'package:daredevil/data/repositories/fundamental_repository.dart';
import 'package:daredevil/data/repositories/insider_repository.dart';
import 'package:daredevil/data/repositories/market_day_fetch_ledger.dart';
import 'package:daredevil/data/repositories/shareholding_repository.dart';
import 'package:daredevil/data/repositories/trading_repository.dart';
import 'package:daredevil/data/repositories/warning_repository.dart';
import 'package:daredevil/data/repositories/news_repository.dart';
import 'package:daredevil/data/repositories/price_repository.dart';
import 'package:daredevil/data/repositories/stock_repository.dart';
import 'package:daredevil/domain/models/scoring_batch_data.dart';
import 'package:daredevil/domain/repositories/news_repository.dart'
    show NewsSyncResult;
import 'package:daredevil/domain/repositories/price_repository.dart'
    show MarketSyncResult;
import 'package:daredevil/domain/services/scoring_service.dart';
import 'package:daredevil/domain/services/update/market_day_refetcher.dart';
import 'package:daredevil/domain/services/update/dividend_backfiller.dart';
import 'package:daredevil/domain/services/update/dividend_coverage.dart';
import 'package:daredevil/domain/services/update/news_mention_snapshot_service.dart';
import 'package:daredevil/domain/services/thesis/thesis_monitor_service.dart';
import 'package:daredevil/core/utils/clock.dart';
import 'package:daredevil/core/utils/taiwan_calendar.dart';
import 'package:daredevil/domain/services/update_service.dart';
import 'package:daredevil/domain/services/update_service_deps.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockAppDatabase extends Mock implements AppDatabase {}

class MockStockRepository extends Mock implements StockRepository {}

class MockPriceRepository extends Mock implements PriceRepository {}

class MockNewsRepository extends Mock implements NewsRepository {}

class MockAnalysisRepository extends Mock implements AnalysisRepository {}

class MockTdccClient extends Mock implements TdccClient {}

class MockTwseClient extends Mock implements TwseClient {}

class MockTpexClient extends Mock implements TpexClient {}

class MockFundamentalRepository extends Mock implements FundamentalRepository {}

class MockScoringService extends Mock implements ScoringService {}

class MockNewsMentionSnapshotService extends Mock
    implements NewsMentionSnapshotService {}

class MockThesisMonitorService extends Mock implements ThesisMonitorService {}

class MockTradingRepository extends Mock implements TradingRepository {}

class MockShareholdingRepository extends Mock
    implements ShareholdingRepository {}

class MockWarningRepository extends Mock implements WarningRepository {}

class MockInsiderRepository extends Mock implements InsiderRepository {}

class MockMarketDayRefetcher extends Mock implements MarketDayRefetcher {}

class MockDividendBackfiller extends Mock implements DividendBackfiller {}

DividendBackfillSummary _backfillSummary(
  DateTime now, {
  RateLimitException? rateLimitError,
  Map<String, String> marketStops = const {},
}) => DividendBackfillSummary(
  calls: 0,
  maxCalls: 0,
  completed: const [],
  failures: const [],
  marketStops: marketStops,
  rateLimitError: rateLimitError,
  stoppedAt: null,
  coverage: DividendCoverage.compute(
    now: now,
    ledger: const [],
    failures: const [],
    knownSymbols: const {},
  ),
);

class _FakeLedger extends Fake implements MarketDayFetchLedger {}

void main() {
  late MockAppDatabase mockDb;
  late MockStockRepository mockStockRepo;
  late MockPriceRepository mockPriceRepo;
  late MockNewsRepository mockNewsRepo;
  late MockAnalysisRepository mockAnalysisRepo;
  late MockTdccClient mockTdcc;
  late MockScoringService mockScoring;

  // 2026-07-06 為週一交易日
  final tradingDay = DateTime(2026, 7, 6);

  late MockMarketDayRefetcher mockRefetcher;
  late MockDividendBackfiller mockBackfiller;

  setUpAll(() {
    registerFallbackValue(DateTime(2026, 7, 6));
    registerFallbackValue(
      ScoringBatchData(pricesMap: const {}, newsMap: const {}),
    );
    registerFallbackValue(_FakeLedger());
    registerFallbackValue(const DividendBackfillScope());
    registerFallbackValue(<DividendDistributionCompanion>[]);
  });

  setUp(() {
    mockDb = MockAppDatabase();
    mockStockRepo = MockStockRepository();
    mockPriceRepo = MockPriceRepository();
    mockNewsRepo = MockNewsRepository();
    mockAnalysisRepo = MockAnalysisRepository();
    mockTdcc = MockTdccClient();
    mockScoring = MockScoringService();

    // --- 主流程 happy-path stubs（candidates 為空，聚焦輔助資料步驟）---
    when(() => mockDb.createUpdateRun(any(), any())).thenAnswer((_) async => 1);
    when(
      () =>
          mockDb.finishUpdateRun(any(), any(), message: any(named: 'message')),
    ).thenAnswer((_) async {});
    // 股票清單：空 DB → needsInit → syncStockList
    when(() => mockStockRepo.getAllStocks()).thenAnswer((_) async => []);
    when(() => mockStockRepo.syncStockList()).thenAnswer((_) async => 1000);
    // 價格：dataDate 與目標日一致 → 不觸發日期校正
    when(
      () => mockPriceRepo.syncAllPricesForDate(
        any(),
        force: any(named: 'force'),
        ledger: any(named: 'ledger'),
      ),
    ).thenAnswer(
      (_) async => MarketSyncResult(
        count: 100,
        candidates: const [],
        dataDate: tradingDay,
      ),
    );
    // 歷史資料 / 候選篩選：無符合股票
    when(
      () => mockDb.getSymbolsWithSufficientData(
        minDays: any(named: 'minDays'),
        startDate: any(named: 'startDate'),
        endDate: any(named: 'endDate'),
      ),
    ).thenAnswer((_) async => []);
    // 流動性下限：無成交值資料 → 全部 permissive 放行
    when(
      () => mockDb.getMedianTurnoverBatch(
        endDate: any(named: 'endDate'),
        windowDays: any(named: 'windowDays'),
        minDataDays: any(named: 'minDataDays'),
      ),
    ).thenAnswer((_) async => {});
    when(() => mockDb.getStocksBatch(any())).thenAnswer((_) async => {});
    when(
      () => mockPriceRepo.syncStockPrices(
        any(),
        startDate: any(named: 'startDate'),
        endDate: any(named: 'endDate'),
      ),
    ).thenAnswer((_) async => 10);
    // 新聞
    when(
      () => mockNewsRepo.syncNews(sources: any(named: 'sources')),
    ).thenAnswer((_) async => const NewsSyncResult(itemsAdded: 0, errors: []));
    when(
      () => mockNewsRepo.cleanupOldNews(
        olderThanDays: any(named: 'olderThanDays'),
      ),
    ).thenAnswer((_) async => 0);
    // BatchDataLoader 的空批次查詢
    when(
      () => mockDb.getPriceHistoryBatch(
        any(),
        startDate: any(named: 'startDate'),
        endDate: any(named: 'endDate'),
      ),
    ).thenAnswer((_) async => {});
    when(
      () => mockNewsRepo.getNewsForStocksBatch(any(), days: any(named: 'days')),
    ).thenAnswer((_) async => {});
    when(
      () =>
          mockDb.getLatestMonthlyRevenuesBatch(any(), asOf: any(named: 'asOf')),
    ).thenAnswer((_) async => {});
    when(
      () => mockDb.getLatestValuationsBatch(any(), asOf: any(named: 'asOf')),
    ).thenAnswer((_) async => {});
    when(
      () => mockDb.getRecentMonthlyRevenueBatch(
        any(),
        months: any(named: 'months'),
      ),
    ).thenAnswer((_) async => {});
    when(
      () => mockDb.getDayTradingMapForDate(any()),
    ).thenAnswer((_) async => {});
    when(
      () => mockDb.getLatestShareholdingsBatch(any(), asOf: any(named: 'asOf')),
    ).thenAnswer((_) async => {});
    when(
      () => mockDb.getShareholdingsBeforeDateBatch(
        any(),
        beforeDate: any(named: 'beforeDate'),
      ),
    ).thenAnswer((_) async => {});
    when(
      () => mockDb.getActiveWarningsMapBatch(any()),
    ).thenAnswer((_) async => {});
    when(
      () => mockDb.getMarketsForSymbolsBatch(any()),
    ).thenAnswer((_) async => <String, String>{});
    when(
      () =>
          mockDb.getLatestInsiderHoldingsBatch(any(), asOf: any(named: 'asOf')),
    ).thenAnswer((_) async => {});
    when(() => mockDb.getEPSHistoryBatch(any())).thenAnswer((_) async => {});
    when(() => mockDb.getROEHistoryBatch(any())).thenAnswer((_) async => {});
    when(
      () => mockDb.getDividendHistoryBatch(any()),
    ).thenAnswer((_) async => {});
    when(() => mockDb.getMaxRevenueBatch(any())).thenAnswer((_) async => {});
    // 評分（空結果）；當日清除已移入 ScoringService 的寫入 transaction，
    // 此處 scoring 為 mock 故不需 stub clear
    when(
      () => mockScoring.scoreStocksInIsolate(
        candidates: any(named: 'candidates'),
        date: any(named: 'date'),
        batchData: any(named: 'batchData'),
        // 自選股零訊號仍落庫(2026-08-16)——漏了這個 matcher 會讓整個 stub
        // 不匹配、回傳 null,失敗訊息是無關的 'Null is not a subtype'
        watchlistSymbols: any(named: 'watchlistSymbols'),
      ),
    ).thenAnswer((_) async => []);
    // 完成階段：警示價格
    when(() => mockDb.getActiveAlerts()).thenAnswer((_) async => []);
    when(() => mockDb.getWatchlist()).thenAnswer((_) async => []);
    when(() => mockDb.getLatestPricesBatch(any())).thenAnswer((_) async => {});
    // TDCC 新鮮度檢查：DB 尚無資料 → 一律抓
    when(
      () => mockDb.getLatestHoldingDistributionDate(any()),
    ).thenAnswer((_) async => null);

    mockRefetcher = MockMarketDayRefetcher();
    when(
      () => mockRefetcher.refetchPending(
        today: any(named: 'today'),
        ledger: any(named: 'ledger'),
      ),
    ).thenAnswer((_) async => RefetchSummary());

    mockBackfiller = MockDividendBackfiller();
    when(
      () => mockBackfiller.backfill(
        now: any(named: 'now'),
        maxCalls: any(named: 'maxCalls'),
        scope: any(named: 'scope'),
      ),
    ).thenAnswer(
      (inv) async => _backfillSummary(inv.namedArguments[#now] as DateTime),
    );
  });

  /// 建立最小依賴的 UpdateService：
  /// 預設只提供 tdcc client（twse/tpex/finMind 為 null → 對應 syncer 不建立），
  /// 只提供 required repositories（institutional 等為 null → 對應 syncer 不建立）。
  /// 各測試可額外注入 tpex / fundamental 以啟用對應 syncer。
  UpdateService buildService({
    TwseClient? twse,
    TpexClient? tpex,
    FinMindClient? finMind,
    FundamentalRepository? fundamental,
    NewsMentionSnapshotService? newsMentionSnapshot,
    TradingRepository? trading,
    ShareholdingRepository? shareholding,
    WarningRepository? warning,
    InsiderRepository? insider,
    ThesisMonitorService? thesisMonitor,
    MarketDayRefetcher? refetcher,
    AppClock? clock,
    bool realDividendBackfiller = false,
  }) {
    return UpdateService(
      // 固定在非 12 月：預設用系統時鐘時，12 月起交易日曆提醒會附在
      // message 上，整份測試的結果隨執行日期改變
      clock: clock ?? _Clock(DateTime(2026, 7, 6, 15, 30)),
      database: mockDb,
      repositories: UpdateRepositories(
        stock: mockStockRepo,
        price: mockPriceRepo,
        news: mockNewsRepo,
        analysis: mockAnalysisRepo,
        fundamental: fundamental,
        trading: trading,
        shareholding: shareholding,
        warning: warning,
        insider: insider,
      ),
      clients: UpdateClients(
        tdcc: mockTdcc,
        twse: twse,
        tpex: tpex,
        finMind: finMind,
      ),
      services: UpdateServices(
        scoring: mockScoring,
        newsMentionSnapshot: newsMentionSnapshot,
        thesisMonitor: thesisMonitor,
        marketDayRefetcher: refetcher ?? mockRefetcher,
        dividendBackfiller: realDividendBackfiller ? null : mockBackfiller,
      ),
    );
  }

  // 日曆過期影響的是正在跑的更新，提醒放在每日更新的摘要（不改程式碼的
  // 期間 CI 不會跑）；不算失敗，否則 launchd 每天都回報失敗
  group('交易日曆到期提醒', () {
    test('12 月起下一年未經證交所確認：摘要附提醒、不算失敗', () async {
      final result = await buildService(
        clock: _Clock(DateTime(2026, 12, 2, 15, 30)),
      ).runDailyUpdate(forDate: tradingDay);

      expect(result.calendarNotice, contains('2027'));
      expect(result.summary, contains('交易日曆待更新'));
      expect(result.errors.where((e) => e.contains('交易日曆')), isEmpty);
      // App 內更新紀錄與 CLI 印的都是這份 message（狀態見 runOutcome 測試）
      expect(result.message, contains('交易日曆待更新'));
      final written =
          verify(
                () => mockDb.finishUpdateRun(
                  any(),
                  any(),
                  message: captureAny(named: 'message'),
                ),
              ).captured.single
              as String?;
      expect(written, contains('交易日曆待更新'));
    });

    test('有警告又需更新日曆：摘要兩者都呈現', () {
      final result = UpdateResult(date: tradingDay)
        ..success = true
        ..stocksAnalyzed = 3
        ..calendarNotice = '交易日曆 2027 年尚未依證交所公告更新';
      result.recordError('TDCC 失敗');
      expect(result.summary, '分析 3 檔（1 項警告）；交易日曆待更新');
    });

    // 狀態只看錯誤：日曆提醒不算失敗（否則 launchd 每天回報失敗）
    group('runOutcome', () {
      test('沒有錯誤、需更新日曆：狀態仍是成功，訊息附提醒', () {
        final o = UpdateService.runOutcome(const [], calendarStale: true);
        expect(o.status, UpdateStatus.success.code);
        expect(o.message, '更新完成；交易日曆待更新');
      });

      test('沒有錯誤、日曆正常：更新完成', () {
        final o = UpdateService.runOutcome(const [], calendarStale: false);
        expect(o.status, UpdateStatus.success.code);
        expect(o.message, '更新完成');
      });

      test('有錯誤：部分成功，提醒不影響狀態', () {
        for (final stale in [false, true]) {
          final o = UpdateService.runOutcome(const [
            'TDCC 失敗',
          ], calendarStale: stale);
          expect(o.status, UpdateStatus.partial.code, reason: '$stale');
        }
      });
    });

    test('日曆涵蓋且已確認：不提醒', () async {
      final result = await buildService(
        clock: _Clock(DateTime(2026, 10, 1, 15, 30)),
      ).runDailyUpdate(forDate: tradingDay);

      expect(result.calendarNotice, isNull);
      expect(result.summary, isNot(contains('交易日曆')));
    });
  });

  group('async 錯誤衛生(2026-07-30 審查)', () {
    test('run 起手狀態是 RUNNING(孤兒 sweep 才能區分中斷 vs 部分失敗)', () async {
      final service = buildService();
      await service.runDailyUpdate(forDate: DateTime(2026, 7, 28));
      verify(
        () => mockDb.createUpdateRun(any(), UpdateStatus.running.code),
      ).called(1);
    });

    test(
      'createUpdateRun 拋錯:rethrow 給 caller 且零 unhandled(孤兒 Completer)',
      () async {
        when(
          () => mockDb.createUpdateRun(any(), any()),
        ).thenAnswer((_) async => throw StateError('disk full'));

        final unhandled = <Object>[];
        Object? thrown;
        await runZonedGuarded(() async {
          try {
            await buildService().runDailyUpdate(forDate: tradingDay);
          } catch (e) {
            thrown = e;
          }
          await Future<void>.delayed(Duration.zero);
          await Future<void>.delayed(Duration.zero);
        }, (e, st) => unhandled.add(e));

        expect(thrown, isA<StateError>());
        expect(
          unhandled,
          isEmpty,
          reason:
              '無併發等待者時 completer.future 沒有 listener,completeError '
              '會讓同一錯誤再以 unhandled async error 打進 zone(需 .ignore())',
        );
      },
    );

    test('getWatchlist 拋錯:降級續跑,不得以 ParallelWaitError 收場', () async {
      when(
        () => mockDb.getWatchlist(),
      ).thenAnswer((_) async => throw StateError('db corrupt'));

      final result = await buildService().runDailyUpdate(forDate: tradingDay);

      // 步驟 4(record .wait 分支)的 getWatchlist 必須降級記錄而非裸拋;
      // 全域 stub 也會讓步驟 6(candidate_selector,順序路徑)拋錯終止 run,
      // 那是頂層 catch 的正常職責——重點是訊息必須可讀、不得是
      // ParallelWaitError 包裝(修復前步驟 4 會先以 ParallelWaitError 收場)
      expect(result.errors, anyElement(contains('自選清單讀取失敗')));
      expect(
        result.message ?? '',
        isNot(contains('ParallelWaitError')),
        reason: '裸拋穿進步驟 4 的 record .wait 會被包成不可讀的 ParallelWaitError',
      );
      expect(
        result.message ?? '',
        contains('db corrupt'),
        reason: '終止訊息應保留原始例外內容(可讀的故障現場)',
      );
    });
  });

  group('部分失敗的對外可見性(2026-08-15 稽核)', () {
    // 稽核發現:result.success 無條件為 true(它的語意是「主流程完成」,
    // 這點正確且被 TDCC 測試釘住),但 result.message 也無條件是「更新完成」
    // ——CLI 只印 message 與 exit code,於是 20 個 recordError 呼叫點的內容
    // 對維運完全不可見。專案有「自動更新靜默斷 13 天」的前科。
    test('🚨 有 errors 時 message 必須反映 partial,不得謊報「更新完成」', () async {
      when(
        () => mockTdcc.getAllHoldingDistribution(),
      ).thenThrow(Exception('unexpected payload'));

      final result = await buildService().runDailyUpdate(forDate: tradingDay);

      expect(result.errors, isNotEmpty, reason: '前提:確實有記錄到錯誤');
      expect(
        result.message ?? '',
        isNot('更新完成'),
        reason: '有失敗項卻說「更新完成」= 維運看不到問題',
      );
      expect(
        result.message ?? '',
        contains('TDCC'),
        reason: 'message 應帶出實際失敗內容供 CLI 直接輸出',
      );
    });

    test('🚨 hasErrors 提供 CLI 判斷 exit code 的依據', () async {
      when(
        () => mockTdcc.getAllHoldingDistribution(),
      ).thenThrow(Exception('unexpected payload'));

      final result = await buildService().runDailyUpdate(forDate: tradingDay);
      expect(result.hasErrors, isTrue);
      expect(result.success, isTrue, reason: '主流程仍完成——兩者語意不同');
    });

    test('全數成功時 message 維持「更新完成」、hasErrors 為 false', () async {
      final result = await buildService().runDailyUpdate(forDate: tradingDay);
      if (result.errors.isEmpty) {
        expect(result.message, '更新完成');
        expect(result.hasErrors, isFalse);
      }
    });
  });

  group('UpdateService 輔助資料同步失敗的可見性', () {
    test('TDCC generic 同步失敗應記錄到 result.errors（partial 警告可見）', () async {
      // TDCC client 拋出 generic exception（模擬 API 格式變更等非限流故障）
      when(
        () => mockTdcc.getAllHoldingDistribution(),
      ).thenThrow(Exception('unexpected payload'));

      final service = buildService();
      final result = await service.runDailyUpdate(forDate: tradingDay);

      // 主流程不受輔助資料失敗影響
      expect(result.success, isTrue);
      // 失敗必須可見：TDCC 失敗應進 errors 使 status 成為 partial
      expect(
        result.errors,
        anyElement(contains('TDCC')),
        reason: 'TDCC generic 失敗被靜默吞掉，使用者無從得知資料 stale',
      );
      expect(result.hasWarnings, isTrue);
    });

    test('🚨 PARTIAL run 的 message 必須含錯誤細節（事後可重建故障現場）', () async {
      // 2026-07-29 審查:PARTIAL 只寫死「部分更新成功」,update_run 表事後
      // 看不出哪一步敗——7/28「誤判更新掛死」事件的直接成因之一。
      when(
        () => mockTdcc.getAllHoldingDistribution(),
      ).thenThrow(Exception('unexpected payload'));

      final service = buildService();
      await service.runDailyUpdate(forDate: tradingDay);

      final captured =
          verify(
                () => mockDb.finishUpdateRun(
                  any(),
                  UpdateStatus.partial.code,
                  message: captureAny(named: 'message'),
                ),
              ).captured.single
              as String?;
      expect(
        captured,
        contains('TDCC'),
        reason: 'message 不含失敗步驟細節,故障現場無法從 update_run 重建',
      );
    });

    test('PARTIAL message 超長錯誤必須截斷至 500 字(含省略號)', () async {
      when(
        () => mockTdcc.getAllHoldingDistribution(),
      ).thenThrow(Exception('boom ${'x' * 700}'));

      final service = buildService();
      await service.runDailyUpdate(forDate: tradingDay);

      final captured =
          verify(
                () => mockDb.finishUpdateRun(
                  any(),
                  UpdateStatus.partial.code,
                  message: captureAny(named: 'message'),
                ),
              ).captured.single
              as String?;
      expect(captured, isNotNull);
      expect(
        captured!.length,
        lessThanOrEqualTo(500),
        reason: 'update_run.message 不設限會無界成長',
      );
      expect(captured, endsWith('…'));
      expect(captured, startsWith('部分更新成功'));
    });

    test('超長錯誤又需更新交易日曆：仍在 500 字內、提醒保留在結尾', () async {
      when(
        () => mockTdcc.getAllHoldingDistribution(),
      ).thenThrow(Exception('boom ${'x' * 700}'));

      await buildService(
        clock: _Clock(DateTime(2026, 12, 2, 15, 30)),
      ).runDailyUpdate(forDate: tradingDay);

      final captured =
          verify(
                () => mockDb.finishUpdateRun(
                  any(),
                  UpdateStatus.partial.code,
                  message: captureAny(named: 'message'),
                ),
              ).captured.single
              as String;
      expect(captured.length, lessThanOrEqualTo(500));
      expect(captured, contains('…'));
      expect(captured, endsWith('交易日曆待更新'));
    });

    test('半個市場價格取得失敗必須可見（TWSE 空、TPEx 有資料）', () async {
      // safeAwait 把來源失敗吞成空陣列：只有 TWSE 掛掉時 tpexPrices 非空、
      // 不進「兩者皆空」分支 → 用半個市場的資料照常評分且無人知曉。
      when(
        () => mockPriceRepo.syncAllPricesForDate(
          any(),
          force: any(named: 'force'),
          ledger: any(named: 'ledger'),
        ),
      ).thenAnswer(
        (_) async => MarketSyncResult(
          count: 900,
          candidates: const [],
          dataDate: tradingDay,
          emptyMarkets: const ['TWSE'],
        ),
      );

      final service = buildService();
      final result = await service.runDailyUpdate(forDate: tradingDay);

      expect(
        result.errors,
        anyElement(contains('TWSE')),
        reason: '缺半個市場卻回報成功，等於讓使用者用殘缺資料下單',
      );
      expect(result.hasWarnings, isTrue);
    });

    test('🚨 日期回滾時不得誤報缺市場（早盤假 partial）', () async {
      // 交易日盤前/盤中：TPEx 當日行情檔未發布 → 空；TWSE 端點自動回上一交易日
      // → dataDate 早於 targetDate、觸發回滾。此時「TPEx 今日零筆」是預期的，
      // 而回滾後那一天的資料 DB 早已完整，記 error 會讓每個交易日早盤都假 partial。
      final prevDay = tradingDay.subtract(const Duration(days: 1));
      when(
        () => mockPriceRepo.syncAllPricesForDate(
          any(),
          force: any(named: 'force'),
          ledger: any(named: 'ledger'),
        ),
      ).thenAnswer(
        (_) async => MarketSyncResult(
          count: 1200,
          candidates: const [],
          dataDate: prevDay,
          emptyMarkets: const ['TPEx'],
        ),
      );

      final service = buildService();
      final result = await service.runDailyUpdate(forDate: tradingDay);

      expect(
        result.errors.where((e) => e.contains('TPEx')),
        isEmpty,
        reason: '日期已回滾到有完整資料的那天，不該報缺市場',
      );
    });

    test('兩個市場都有資料時不得誤報錯誤', () async {
      final service = buildService();
      final result = await service.runDailyUpdate(forDate: tradingDay);

      expect(
        result.errors.where((e) => e.contains('價格')),
        isEmpty,
        reason: '正常路徑不得產生假警告',
      );
    });

    test('🚨 警示同步失敗必須轉發到 errors（處置股是硬排除、非額外功能）', () async {
      // KillerFeaturesSyncResult 的 warningError/insiderError 過去零消費點，
      // 且裸 catch 明寫「額外功能不影響主流程」。但處置股是三模式榜的硬性
      // 宇宙排除（-50 分 + droppedDisposal），缺名單是 fail-open：危險股照常
      // 上榜、風險徽章不亮，而使用者看到綠燈。
      final trading = MockTradingRepository();
      final shareholding = MockShareholdingRepository();
      final warningRepo = MockWarningRepository();
      final insider = MockInsiderRepository();

      // 步驟 4.5 籌碼鏈：讓它安靜通過
      when(
        () => trading.syncAllDayTradingFromTwse(date: any(named: 'date')),
      ).thenAnswer((_) async => 0);
      when(
        () => trading.syncAllMarginTrading(date: any(named: 'date')),
      ).thenAnswer((_) async => 0);
      when(
        () => shareholding.syncShareholding(
          any(),
          startDate: any(named: 'startDate'),
          endDate: any(named: 'endDate'),
        ),
      ).thenAnswer((_) async => 0);
      when(
        () => mockDb.getLatestDayTradingDate(),
      ).thenAnswer((_) async => null);
      when(
        () => mockDb.getDayTradingCountForDate(any()),
      ).thenAnswer((_) async => 1);
      when(
        () => mockDb.countStocksByMarket(any()),
      ).thenAnswer((_) async => 100);
      when(
        () => mockDb.countPricesByDateAndMarket(any(), any()),
      ).thenAnswer((_) async => 100);
      when(
        () => mockDb.countMarginTradingByDateAndMarket(any(), any()),
      ).thenAnswer((_) async => 100);
      when(() => mockDb.getStocksByMarket(any())).thenAnswer((_) async => []);

      // 步驟 4.8：警示同步失敗（generic，非 rate limit）
      when(
        () => warningRepo.syncAllMarketWarnings(force: any(named: 'force')),
      ).thenThrow(Exception('TWSE announcement 500'));
      when(
        () => insider.syncAllInsiderHoldings(force: any(named: 'force')),
      ).thenAnswer((_) async => 0);

      final service = buildService(
        trading: trading,
        shareholding: shareholding,
        warning: warningRepo,
        insider: insider,
      );
      final result = await service.runDailyUpdate(forDate: tradingDay);

      expect(
        result.errors,
        anyElement(contains('警示')),
        reason: '缺處置股名單會讓危險股照常上榜，必須進 errors 讓 run 降級',
      );
      // 不斷言 hasWarnings：它是 `errors.isNotEmpty && success`，而本測試的
      // 精簡 harness 未 stub 全部步驟、success 未必為 true。要釘的契約是
      // 「警示失敗有沒有進 errors」，那才是本次修復的內容。
    });

    test('內部人轉讓 generic 同步失敗應記錄到 result.errors', () async {
      final mockTpex = MockTpexClient();
      // TDCC 成功（回空資料 → 跳過寫入）
      when(
        () => mockTdcc.getAllHoldingDistribution(),
      ).thenAnswer((_) async => {});
      // 股利路徑成功（回空清單）
      when(() => mockDb.getAllActiveStocks()).thenAnswer((_) async => []);
      when(() => mockTpex.getDeclaredDividends()).thenAnswer((_) async => []);
      when(() => mockTpex.getShareholderMeetings()).thenAnswer((_) async => []);
      when(
        () => mockTpex.getExRightResults(
          startDate: any(named: 'startDate'),
          endDate: any(named: 'endDate'),
        ),
      ).thenAnswer((_) async => []);
      // 內部人轉讓：generic exception
      when(
        () => mockTpex.getInsiderTransfers(),
      ).thenThrow(Exception('schema changed'));

      final service = buildService(tpex: mockTpex);
      final result = await service.runDailyUpdate(forDate: tradingDay);

      expect(result.success, isTrue);
      expect(result.errors, anyElement(contains('內部人轉讓')));
    });

    test('股利 syncer 內部收集的錯誤應轉發到 result.errors', () async {
      final mockTpex = MockTpexClient();
      when(
        () => mockTdcc.getAllHoldingDistribution(),
      ).thenAnswer((_) async => {});
      when(() => mockDb.getAllActiveStocks()).thenAnswer((_) async => []);
      // 股利來源 generic 失敗 → DividendSyncer 收進自身 result.errors（不 throw）
      when(
        () => mockTpex.getDeclaredDividends(),
      ).thenThrow(Exception('payload broken'));
      when(() => mockTpex.getShareholderMeetings()).thenAnswer((_) async => []);
      when(() => mockTpex.getInsiderTransfers()).thenAnswer((_) async => []);
      when(
        () => mockTpex.getExRightResults(
          startDate: any(named: 'startDate'),
          endDate: any(named: 'endDate'),
        ),
      ).thenAnswer((_) async => []);

      final service = buildService(tpex: mockTpex);
      final result = await service.runDailyUpdate(forDate: tradingDay);

      expect(result.success, isTrue);
      // DividendSyncResult.errors 必須被 caller 讀取並轉發，否則靜默
      expect(result.errors, anyElement(contains('股利')));
    });

    test('除權除息同步內部收集的錯誤應轉發到 result.errors', () async {
      final mockTpex = MockTpexClient();
      when(
        () => mockTdcc.getAllHoldingDistribution(),
      ).thenAnswer((_) async => {});
      when(() => mockDb.getAllActiveStocks()).thenAnswer((_) async => []);
      when(() => mockTpex.getDeclaredDividends()).thenAnswer((_) async => []);
      when(() => mockTpex.getShareholderMeetings()).thenAnswer((_) async => []);
      when(() => mockTpex.getInsiderTransfers()).thenAnswer((_) async => []);
      // 除權除息來源 generic 失敗 → syncDistributions 收進自身 errors（不 throw）
      when(
        () => mockTpex.getExRightResults(
          startDate: any(named: 'startDate'),
          endDate: any(named: 'endDate'),
        ),
      ).thenThrow(Exception('exDailyQ payload broken'));

      final service = buildService(tpex: mockTpex);
      final result = await service.runDailyUpdate(forDate: tradingDay);

      expect(result.success, isTrue);
      expect(result.errors.where((e) => e.contains('除權除息')), hasLength(1));
      // 範圍取自 UpdateService 的時鐘（7/6）：7 天前 6/29 早於月初 7/1
      verify(
        () => mockTpex.getExRightResults(
          startDate: DateTime(2026, 6, 29),
          endDate: DateTime(2026, 7, 6),
        ),
      ).called(1);
    });

    test('除權除息拋網路錯誤：記錯誤、不標記限流，本輪照常完成', () async {
      final mockTpex = MockTpexClient();
      when(
        () => mockTdcc.getAllHoldingDistribution(),
      ).thenAnswer((_) async => {});
      when(() => mockDb.getAllActiveStocks()).thenAnswer((_) async => []);
      when(() => mockTpex.getDeclaredDividends()).thenAnswer((_) async => []);
      when(() => mockTpex.getShareholderMeetings()).thenAnswer((_) async => []);
      when(() => mockTpex.getInsiderTransfers()).thenAnswer((_) async => []);
      when(
        () => mockTpex.getExRightResults(
          startDate: any(named: 'startDate'),
          endDate: any(named: 'endDate'),
        ),
      ).thenThrow(const NetworkException('exDailyQ timeout'));

      final service = buildService(tpex: mockTpex);
      final result = await service.runDailyUpdate(forDate: tradingDay);

      expect(result.success, isTrue);
      expect(result.hasRateLimitError, isFalse);
      expect(result.errors, anyElement(contains('除權除息同步失敗')));
    });

    test('已宣告股利撞到限流：不再打除權除息', () async {
      final mockTpex = MockTpexClient();
      when(
        () => mockTdcc.getAllHoldingDistribution(),
      ).thenAnswer((_) async => {});
      when(() => mockDb.getAllActiveStocks()).thenAnswer((_) async => []);
      when(
        () => mockTpex.getDeclaredDividends(),
      ).thenThrow(const RateLimitException('redirect loop'));

      final service = buildService(tpex: mockTpex);
      await service.runDailyUpdate(forDate: tradingDay);

      verifyNever(
        () => mockTpex.getExRightResults(
          startDate: any(named: 'startDate'),
          endDate: any(named: 'endDate'),
        ),
      );
    });

    test('除權除息撞到限流：本輪標記限流', () async {
      final mockTpex = MockTpexClient();
      when(
        () => mockTdcc.getAllHoldingDistribution(),
      ).thenAnswer((_) async => {});
      when(() => mockDb.getAllActiveStocks()).thenAnswer((_) async => []);
      when(() => mockTpex.getDeclaredDividends()).thenAnswer((_) async => []);
      when(() => mockTpex.getShareholderMeetings()).thenAnswer((_) async => []);
      when(
        () => mockTpex.getExRightResults(
          startDate: any(named: 'startDate'),
          endDate: any(named: 'endDate'),
        ),
      ).thenThrow(const RateLimitException('redirect loop'));

      final service = buildService(tpex: mockTpex);
      final result = await service.runDailyUpdate(forDate: tradingDay);

      expect(result.hasRateLimitError, isTrue);
      expect(result.errors, anyElement(contains('除權除息同步中止')));
    });

    test('已宣告股利拋網路錯誤：除權除息仍照常同步（兩者分開 try）', () async {
      final mockTpex = MockTpexClient();
      when(
        () => mockTdcc.getAllHoldingDistribution(),
      ).thenAnswer((_) async => {});
      when(() => mockDb.getAllActiveStocks()).thenAnswer((_) async => []);
      // sync() 對 NetworkException rethrow → UpdateService 記錯誤後繼續
      when(
        () => mockTpex.getDeclaredDividends(),
      ).thenThrow(const NetworkException('t187ap45 timeout'));
      when(() => mockTpex.getInsiderTransfers()).thenAnswer((_) async => []);
      when(
        () => mockTpex.getExRightResults(
          startDate: any(named: 'startDate'),
          endDate: any(named: 'endDate'),
        ),
      ).thenAnswer((_) async => []);

      final service = buildService(tpex: mockTpex);
      final result = await service.runDailyUpdate(forDate: tradingDay);

      expect(result.errors, anyElement(contains('股利/股東會')));
      verify(
        () => mockTpex.getExRightResults(
          startDate: any(named: 'startDate'),
          endDate: any(named: 'endDate'),
        ),
      ).called(1);
    });

    test(
      '全市場估值 generic 失敗（FundamentalSyncer 內部收集）應轉發到 result.errors',
      () async {
        final mockFundamental = MockFundamentalRepository();
        when(
          () => mockTdcc.getAllHoldingDistribution(),
        ).thenAnswer((_) async => {});
        // 估值 generic 失敗；營收成功
        when(
          () => mockFundamental.syncAllMarketValuation(
            any(),
            force: any(named: 'force'),
          ),
        ).thenThrow(Exception('BWIBBU format changed'));
        when(
          () => mockFundamental.syncAllMarketRevenue(
            any(),
            force: any(named: 'force'),
          ),
        ).thenAnswer((_) async => 0);
        when(() => mockDb.getStocksByMarket(any())).thenAnswer((_) async => []);
        when(
          () => mockFundamental.syncFinancialStatements(
            symbol: any(named: 'symbol'),
            startDate: any(named: 'startDate'),
            endDate: any(named: 'endDate'),
          ),
        ).thenAnswer((_) async => 0);

        final service = buildService(fundamental: mockFundamental);
        final result = await service.runDailyUpdate(forDate: tradingDay);

        expect(result.success, isTrue);
        // FundamentalSyncer 內部 catch 收集的失敗必須被 caller 轉發，否則靜默
        expect(result.errors, anyElement(contains('估值')));
      },
    );

    test('上櫃自選估值 generic 失敗（syncOtcWatchlistFundamentals）應轉發', () async {
      final mockFundamental = MockFundamentalRepository();
      when(
        () => mockTdcc.getAllHoldingDistribution(),
      ).thenAnswer((_) async => {});
      when(
        () => mockFundamental.syncAllMarketValuation(
          any(),
          force: any(named: 'force'),
        ),
      ).thenAnswer((_) async => 0);
      when(
        () => mockFundamental.syncAllMarketRevenue(
          any(),
          force: any(named: 'force'),
        ),
      ).thenAnswer((_) async => 0);
      when(
        () => mockFundamental.syncFinancialStatements(
          symbol: any(named: 'symbol'),
          startDate: any(named: 'startDate'),
          endDate: any(named: 'endDate'),
        ),
      ).thenAnswer((_) async => 0);
      // watchlist 含一檔上櫃股 → 觸發 OTC watchlist 補充
      when(() => mockDb.getWatchlist()).thenAnswer(
        (_) async => [
          WatchlistEntry(symbol: '3567', createdAt: DateTime(2026, 1, 1)),
        ],
      );
      when(() => mockDb.getStocksByMarket(any())).thenAnswer(
        (_) async => [
          StockMasterEntry(
            symbol: '3567',
            name: '逸昌',
            market: 'TPEx',
            isActive: true,
            updatedAt: DateTime(2026, 7, 8),
          ),
        ],
      );
      // OTC 估值 generic 失敗（syncer 內部收集、不 throw）
      when(
        () => mockFundamental.syncOtcValuation(
          any(),
          date: any(named: 'date'),
          force: any(named: 'force'),
        ),
      ).thenThrow(Exception('OTC valuation broken'));
      when(
        () => mockFundamental.syncOtcRevenue(any(), force: any(named: 'force')),
      ).thenAnswer((_) async => 0);

      final service = buildService(fundamental: mockFundamental);
      final result = await service.runDailyUpdate(forDate: tradingDay);

      expect(result.success, isTrue);
      expect(result.errors, anyElement(contains('上櫃自選估值')));
    });

    test('財報 generic 同步失敗應記錄到 result.errors', () async {
      final mockFundamental = MockFundamentalRepository();
      when(
        () => mockTdcc.getAllHoldingDistribution(),
      ).thenAnswer((_) async => {});
      // 全市場基本面成功
      when(
        () => mockFundamental.syncAllMarketValuation(
          any(),
          force: any(named: 'force'),
        ),
      ).thenAnswer((_) async => 0);
      when(
        () => mockFundamental.syncAllMarketRevenue(
          any(),
          force: any(named: 'force'),
        ),
      ).thenAnswer((_) async => 0);
      // 上櫃自選：watchlist 空 → 早退（getWatchlist 已 stub 回空）
      when(() => mockDb.getStocksByMarket(any())).thenAnswer((_) async => []);
      // 財報：generic exception
      when(
        () => mockFundamental.syncFinancialStatements(
          symbol: any(named: 'symbol'),
          startDate: any(named: 'startDate'),
          endDate: any(named: 'endDate'),
        ),
      ).thenThrow(Exception('EPS format changed'));

      final service = buildService(fundamental: mockFundamental);
      final result = await service.runDailyUpdate(forDate: tradingDay);

      expect(result.success, isTrue);
      expect(result.errors, anyElement(contains('財報')));
    });
  });

  group('UpdateService 新聞提及快照 fail-safe', () {
    test('新聞提及快照拋例外時更新流程照常完成', () async {
      when(
        () => mockTdcc.getAllHoldingDistribution(),
      ).thenAnswer((_) async => {});

      final mockSnapshotService = MockNewsMentionSnapshotService();
      when(
        () => mockSnapshotService.snapshotRecentDays(),
      ).thenThrow(Exception('snapshot boom'));

      final service = buildService(newsMentionSnapshot: mockSnapshotService);
      final result = await service.runDailyUpdate(forDate: tradingDay);

      // 快照失敗不應中斷或拖垮整體更新結果（fail-safe：只 log，不 rethrow）
      expect(result.success, isTrue);
      verify(() => mockSnapshotService.snapshotRecentDays()).called(1);
    });

    // ====================================================================
    // 步驟 10+ 的失敗必須可見（finding #23）
    //
    // 三個 fail-safe（規則準確度統計、新聞提及快照、釘選論點失效檢查）原本
    // 跑在 `_finishUpdate` **之後**，且只 AppLogger、不碰 result.errors。
    // 而 `_finishUpdate` 依 result.errors 決定 update_run 狀態並設
    // `result.success = true` —— 於是這三步整個沒跑，畫面仍是乾淨的
    // 「更新完成」、update_run 仍是 SUCCESS。
    //
    // 影響最重的是釘選論點檢查：那是**出場層**。它靜默沒跑代表該失效的
    // 論點不會被標記，使用者會抱著一個已達出場條件的部位而毫不知情。
    // 新聞提及快照失敗則是永久損失——news_mention_daily 在 wipe 白名單內
    // 正因為「歷史不可重建」。
    //
    // fail-safe 的語意是「不中斷流程」，不是「不留下痕跡」。
    // ====================================================================

    test('🚨 快照失敗必須進 result.errors（fail-safe ≠ 無痕）', () async {
      when(
        () => mockTdcc.getAllHoldingDistribution(),
      ).thenAnswer((_) async => {});

      final mockSnapshotService = MockNewsMentionSnapshotService();
      when(
        () => mockSnapshotService.snapshotRecentDays(),
      ).thenThrow(Exception('snapshot boom'));

      final service = buildService(newsMentionSnapshot: mockSnapshotService);
      final result = await service.runDailyUpdate(forDate: tradingDay);

      expect(result.success, isTrue, reason: 'fail-safe 仍不得中斷流程');
      expect(
        result.errors,
        anyElement(contains('新聞提及快照')),
        reason: '失敗必須留下痕跡，否則使用者看到的是乾淨的「更新完成」',
      );
    });

    test('🚨 釘選論點檢查失敗必須進 result.errors（出場層靜默沒跑最危險）', () async {
      when(
        () => mockTdcc.getAllHoldingDistribution(),
      ).thenAnswer((_) async => {});

      final mockThesis = MockThesisMonitorService();
      when(
        () => mockThesis.checkActiveTheses(asOf: any(named: 'asOf')),
      ).thenThrow(Exception('thesis boom'));

      final service = buildService(thesisMonitor: mockThesis);
      final result = await service.runDailyUpdate(forDate: tradingDay);

      expect(result.success, isTrue);
      expect(result.errors, anyElement(contains('釘選論點')));
    });
  });

  // 步驟 3.5：歷史價格撞限流時，止血旗標與錯誤分類雙雙失效
  //
  // 修正前，syncer 內部捕捉 RateLimitException 後只設區域旗標中止迴圈、不
  // rethrow（這是對的——已抓到的歷史資料要保留），但沒把「為什麼中止」帶出去
  // （現已由 HistoricalPriceSyncResult.rateLimitError 帶出，詳見
  // historical_price_syncer_test 的「撞 FinMind 限流時，coordinator 無從得知」段落）：
  //   - update_service.dart 的 `on RateLimitException` 接不到 → rateLimitedAbort 恆 false
  //   - 失敗只走 `ctx.result.errors.add(...)`（不是 recordError）
  //     → UpdateResult.hasRateLimitError 恆 false
  //
  // 與 1bf5040 修掉的 ParallelWaitError 是同一個 bug class 的另一處：
  // **限流被降級成一般失敗**。
  group('步驟 3.5：歷史價格限流的分類', () {
    test('🚨 歷史價格撞限流時 hasRateLimitError 必須為 true', () async {
      when(
        () => mockTdcc.getAllHoldingDistribution(),
      ).thenAnswer((_) async => {});
      when(
        () => mockPriceRepo.syncAllPricesForDate(
          any(),
          force: any(named: 'force'),
          ledger: any(named: 'ledger'),
        ),
      ).thenAnswer(
        (_) async => MarketSyncResult(
          count: 3,
          candidates: const ['2330'],
          dataDate: tradingDay,
        ),
      );
      // 讓 2330 被判定為需要歷史資料，然後同步時撞限流
      when(
        () => mockDb.getSymbolsWithSufficientData(
          minDays: any(named: 'minDays'),
          startDate: any(named: 'startDate'),
          endDate: any(named: 'endDate'),
        ),
      ).thenAnswer((_) async => []);
      // phase 0（市場日快照回補）的 fresh-DB 防護：股票主檔空 → 直接跳過。
      // 不 stub 的話 phase 0 會先拋 TypeError，整個 _syncHistoricalData 走
      // generic catch，根本到不了要測的 phase 1。
      when(() => mockDb.getStocksByMarket(any())).thenAnswer((_) async => []);
      when(
        () => mockDb.getPriceCoverageBatch(
          any(),
          startDate: any(named: 'startDate'),
          endDate: any(named: 'endDate'),
        ),
      ).thenAnswer((_) async => const <String, PriceCoverage>{});
      when(
        () => mockPriceRepo.syncStockPrices(
          any(),
          startDate: any(named: 'startDate'),
          endDate: any(named: 'endDate'),
        ),
      ).thenThrow(const RateLimitException());

      final service = buildService();
      final result = await service.runDailyUpdate(forDate: tradingDay);

      expect(
        result.hasRateLimitError,
        isTrue,
        reason:
            'syncer 不 rethrow（正確），但 coordinator 必須從 result.rateLimited '
            '判讀出來，否則限流被記成一般失敗、UI 的限流提示永遠不亮',
      );
      expect(
        result.errors.any((e) => e.contains('rate limit')),
        isTrue,
        reason: '錯誤訊息要標明限流，否則事後追查配額問題時語意消失',
      );
    });

    test('對照組：一般失敗不得被誤標成限流', () async {
      when(
        () => mockTdcc.getAllHoldingDistribution(),
      ).thenAnswer((_) async => {});
      when(
        () => mockPriceRepo.syncAllPricesForDate(
          any(),
          force: any(named: 'force'),
          ledger: any(named: 'ledger'),
        ),
      ).thenAnswer(
        (_) async => MarketSyncResult(
          count: 3,
          candidates: const ['2330'],
          dataDate: tradingDay,
        ),
      );
      when(
        () => mockDb.getSymbolsWithSufficientData(
          minDays: any(named: 'minDays'),
          startDate: any(named: 'startDate'),
          endDate: any(named: 'endDate'),
        ),
      ).thenAnswer((_) async => []);
      // phase 0（市場日快照回補）的 fresh-DB 防護：股票主檔空 → 直接跳過。
      // 不 stub 的話 phase 0 會先拋 TypeError，整個 _syncHistoricalData 走
      // generic catch，根本到不了要測的 phase 1。
      when(() => mockDb.getStocksByMarket(any())).thenAnswer((_) async => []);
      when(
        () => mockDb.getPriceCoverageBatch(
          any(),
          startDate: any(named: 'startDate'),
          endDate: any(named: 'endDate'),
        ),
      ).thenAnswer((_) async => const <String, PriceCoverage>{});
      when(
        () => mockPriceRepo.syncStockPrices(
          any(),
          startDate: any(named: 'startDate'),
          endDate: any(named: 'endDate'),
        ),
      ).thenThrow(Exception('parser 掛了'));

      final service = buildService();
      final result = await service.runDailyUpdate(forDate: tradingDay);

      expect(result.hasRateLimitError, isFalse, reason: '個股資料異常不該讓整條更新進入止血模式');
    });
  });

  // 步驟 4.7 的 rate limit 止血旗標翻不起來 —— record `.wait` 包掉例外型別
  //
  // 修正前 update_service.dart 用 Dart record 的 `.wait` 平行跑損益表與資產
  // 負債表（現已改 `Future.wait<int?>`）。record `.wait` 在任一支失敗時拋的是
  // **ParallelWaitError**，不是底層例外，於是 `on RateLimitException` 永遠不會觸發。
  //
  // 2026-07-27 實跑驗證（非推理）：
  //   A record.wait  → 落 generic，型別 ParallelWaitError<(int?, int?), ...>
  //   B Future.wait  → 分型 catch 命中
  //   C 兩者皆錯     → Future.wait 拋清單中第一個
  //   D             → Future.wait 仍等所有 future 結束，不留 unhandled error
  //
  // 影響：`UpdateResult.recordError` 的 `if (exception is RateLimitException)`
  // 判不到 → `hasRateLimitError` 恆為 false → 今日頁的限流專屬提示永遠不亮，
  // 使用者只看到一般警告數。
  //
  // 步驟 4.7 是全流程 FinMind 用量最大的一步（2026-07-27 實測 338/384 = 88%），
  // 止血旗標偏偏死在這裡。
  //
  // **嚴重度校正**：一併查過的兩項後果不成立，故非 high——
  //   步驟 4.8 的 warning/insider repo 一行 FinMind 都沒有（只有 TWSE/TPEx，
  //   額度 10000），不存在「繼續打爆掉的 API」；且額度用完後
  //   finmind_client 的 checkBudget 在發網路請求前就擋下。
  //   真正的損害只有錯誤分類與 UI 提示。
  //
  // 當時掃過全部 16 處 record `.wait`：只有財報那處落在有 `on RateLimitException`
  // 的 try 裡。步驟 4 平行組那處包的四個 helper 各自有內部 try/catch 並自行設
  // rateLimitedAbort，例外不會逸出——**不是同型，別順手改**。
  // 2026-08-01 實機(run #123 force):額度 600/600 時 getStockList 拋
  // RateLimitException,syncer 按慣例 rethrow,但當時 _syncStockList 是唯一
  // **完全沒有** try/catch 的 pipeline 步驟——整輪「未捕捉例外」硬摔,
  // 而非優雅 rateLimitedAbort。週一首輪額度總是新鮮,此路徑潛伏至
  // force+額度耗盡的組合才引爆。
  group('步驟 2：股票清單限流分型', () {
    test('🚨 股票清單撞限流:不得未捕捉炸整輪,須標 hasRateLimitError', () async {
      when(
        () => mockStockRepo.syncStockList(),
      ).thenThrow(const RateLimitException('600/600'));

      final service = buildService();
      final result = await service.runDailyUpdate(forDate: tradingDay);

      expect(result.hasRateLimitError, isTrue);
      expect(
        result.errors.any((e) => e.contains('股票清單')),
        isTrue,
        reason: '限流要以 recordError 分型入帳,不是未捕捉炸掉',
      );
    });
  });

  group('步驟 4.7：rate limit 例外分型', () {
    test('🚨 財報同步撞限流時 hasRateLimitError 必須為 true', () async {
      when(
        () => mockTdcc.getAllHoldingDistribution(),
      ).thenAnswer((_) async => {});
      when(
        () => mockPriceRepo.syncAllPricesForDate(
          any(),
          force: any(named: 'force'),
          ledger: any(named: 'ledger'),
        ),
      ).thenAnswer(
        (_) async => MarketSyncResult(
          count: 3,
          candidates: const ['2330', '2317', '2454'],
          dataDate: tradingDay,
        ),
      );
      when(() => mockDb.getStocksByMarket(any())).thenAnswer((_) async => []);

      final mockFundamental = MockFundamentalRepository();
      when(
        () => mockFundamental.syncAllMarketValuation(
          any(),
          force: any(named: 'force'),
        ),
      ).thenAnswer((_) async => 0);
      when(
        () => mockFundamental.syncAllMarketRevenue(
          any(),
          force: any(named: 'force'),
        ),
      ).thenAnswer((_) async => 0);
      // 損益表那支撞限流；資產負債表正常 —— 正是 record `.wait` 會包掉的情境
      when(
        () => mockFundamental.syncFinancialStatements(
          symbol: any(named: 'symbol'),
          startDate: any(named: 'startDate'),
          endDate: any(named: 'endDate'),
        ),
      ).thenThrow(const RateLimitException());

      final service = buildService(fundamental: mockFundamental);
      final result = await service.runDailyUpdate(forDate: tradingDay);

      expect(
        result.hasRateLimitError,
        isTrue,
        reason:
            'record `.wait` 把 RateLimitException 包成 ParallelWaitError，'
            '`on RateLimitException` 接不到 → 旗標死在 FinMind 用量最大的那一步',
      );
      expect(
        result.errors.any((e) => e.contains('rate limit')),
        isTrue,
        reason: '錯誤訊息要保留 rate limit 分類，否則事後追查配額問題語意消失',
      );
    });
  });

  // 步驟 4.7 的目標清單來自單一「最舊優先」佇列（2026-09-05）：自選＋熱門優先，
  // 其餘全市場依 INCOME 最新日期由舊到新（`FundamentalSyncer.selectFinancialBacklog`）。
  //
  // 這組測試守的是**接線**：佇列算出來卻沒接進同步呼叫、或算出的額度沒真的傳
  // 下去，都是靜默 no-op——日誌照印、測試照綠，而覆蓋率原地不動。
  group('financialQuotaForBudget(額度感知,2026-09-05 收成單一數字)', () {
    // 背景:2026-08-05 季報季全市場同時變 needy → 單輪 488 次呼叫吃掉 82%
    // 小時額度,連點更新即 402。reserve 200 就是為此存在。
    test('🚨 整點滿額度:取滿上限,且總支出必留 reserve', () {
      final limit = UpdateService.financialQuotaForBudget(
        usage: (used: 0, budget: 600),
      );
      expect(limit, ApiConfig.financialSyncMaxCount);
      expect(
        600 - limit * 2,
        greaterThanOrEqualTo(ApiConfig.financialBackfillReserve),
        reason: '財報支出後必須留 reserve 給本輪其餘步驟+下一次手動更新',
      );
    });

    test('🚨 同小時第二輪:額度耗到 reserve 內 → 0(快速通過)', () {
      expect(
        UpdateService.financialQuotaForBudget(usage: (used: 450, budget: 600)),
        0,
      );
      expect(
        UpdateService.financialQuotaForBudget(usage: (used: 650, budget: 600)),
        0,
        reason: 'sliding 窗內可能已超額，相減會是負的，不得回負數',
      );
    });

    test('部分額度:(600-300-200)/2 = 50', () {
      expect(
        UpdateService.financialQuotaForBudget(usage: (used: 300, budget: 600)),
        50,
      );
    });

    test('usage null(未掛 tracker)→ 回上限(量不到≠沒額度)', () {
      expect(
        UpdateService.financialQuotaForBudget(usage: null),
        ApiConfig.financialSyncMaxCount,
      );
    });

    test('單調性：已用越多、可補越少，且永不超過上限', () {
      var prev = ApiConfig.financialSyncMaxCount + 1;
      for (var used = 0; used <= 700; used += 7) {
        final limit = UpdateService.financialQuotaForBudget(
          usage: (used: used, budget: 600),
        );
        expect(limit, inInclusiveRange(0, ApiConfig.financialSyncMaxCount));
        expect(limit, lessThanOrEqualTo(prev), reason: 'used=$used 時反而變多了');
        prev = limit;
      }
      expect(prev, 0, reason: '額度用滿後應收斂到 0');
    });
  });

  group('步驟 4.7：財報回填單一佇列', () {
    /// 上市候選遠多於 `financialSyncMaxCount`，模擬正式環境
    /// （2026-07-27 日誌：上市候選 1372 檔 vs 上限 150）
    final twseCandidates = [for (var i = 0; i < 400; i++) '${2000 + i}'];
    const otcSymbol = '5471'; // 松翰，上櫃、無財報

    MockFundamentalRepository buildFundamentalMock() {
      final mock = MockFundamentalRepository();
      when(
        () => mock.syncAllMarketValuation(any(), force: any(named: 'force')),
      ).thenAnswer((_) async => 0);
      when(
        () => mock.syncAllMarketRevenue(any(), force: any(named: 'force')),
      ).thenAnswer((_) async => 0);
      when(
        () => mock.syncFinancialStatements(
          symbol: any(named: 'symbol'),
          startDate: any(named: 'startDate'),
          endDate: any(named: 'endDate'),
        ),
      ).thenAnswer((_) async => 0);
      when(
        () => mock.syncOtcValuation(
          any(),
          date: any(named: 'date'),
          force: any(named: 'force'),
        ),
      ).thenAnswer((_) async => 0);
      when(
        () => mock.syncOtcRevenue(any(), force: any(named: 'force')),
      ).thenAnswer((_) async => 0);
      return mock;
    }

    void stubCandidates(List<String> candidates) {
      when(
        () => mockPriceRepo.syncAllPricesForDate(
          any(),
          force: any(named: 'force'),
          ledger: any(named: 'ledger'),
        ),
      ).thenAnswer(
        (_) async => MarketSyncResult(
          count: candidates.length,
          candidates: candidates,
          dataDate: tradingDay,
        ),
      );
      when(
        () => mockTdcc.getAllHoldingDistribution(),
      ).thenAnswer((_) async => {});
    }

    test('🚨 上櫃候選排在上市之後仍須拿到財報同步——不靠專屬名額，靠最舊優先', () async {
      // 上市候選全部已新鮮、上櫃那檔無資料：舊的「取候選前 150」會把名額全給上市
      // 再被下游新鮮度過濾清空；單一佇列下無資料者排隊首
      final fresh = TaiwanCalendar.expectedLatestReportQuarter(DateTime.now());
      stubCandidates([...twseCandidates, otcSymbol]);
      when(() => mockDb.getStocksByMarket(any())).thenAnswer((_) async => []);
      when(
        () => mockDb.getLatestFinancialDataDatesBatch(any(), any()),
      ).thenAnswer((_) async => {for (final s in twseCandidates) s: fresh});

      final mockFundamental = buildFundamentalMock();
      final service = buildService(fundamental: mockFundamental);
      await service.runDailyUpdate(forDate: tradingDay);

      verify(
        () => mockFundamental.syncFinancialStatements(
          symbol: otcSymbol,
          startDate: any(named: 'startDate'),
          endDate: any(named: 'endDate'),
        ),
      ).called(1);
    });

    test('🚨 額度吃緊時回填必須縮量（守接線：算出的上限要真的傳下去）', () async {
      stubCandidates([
        ...twseCandidates,
        for (var i = 0; i < 60; i++) '${5400 + i}',
      ]);
      when(() => mockDb.getStocksByMarket(any())).thenAnswer((_) async => []);
      when(
        () => mockDb.getLatestFinancialDataDatesBatch(any(), any()),
      ).thenAnswer((_) async => const {});

      // used=60 → affordable=(600-60-200)/2=170。若接線漏掉、仍傳上限 200，
      // 這裡會是 200；若退回舊的固定值也不會剛好 170。
      final tracker = ApiBudgetTracker();
      for (var i = 0; i < 60; i++) {
        tracker.recordCall(ApiVendor.finMind);
      }
      final finMind = FinMindClient(budgetTracker: tracker);
      addTearDown(finMind.close);

      final mockFundamental = buildFundamentalMock();
      final service = buildService(
        fundamental: mockFundamental,
        finMind: finMind,
      );
      await service.runDailyUpdate(forDate: tradingDay);

      final synced = verify(
        () => mockFundamental.syncFinancialStatements(
          symbol: captureAny(named: 'symbol'),
          startDate: any(named: 'startDate'),
          endDate: any(named: 'endDate'),
        ),
      ).captured.cast<String>();

      expect(
        synced.length,
        170,
        reason: '熱門 15 檔計入上限，其餘 155 個名額給最舊優先；總數必須等於算出的額度',
      );
      expect(
        synced,
        containsAll(DefaultStocks.popularStocks),
        reason:
            '熱門股不在候選池，只能經由 priority 進來；接線若把 priority 丟掉，'
            '名額會被候選補滿、總數仍是 170 而這裡轉紅',
      );
    });

    test('🚨 額度耗至 reserve 內:財報整段跳過(同小時第二輪不再 402)', () async {
      stubCandidates([...twseCandidates, otcSymbol]);
      when(() => mockDb.getStocksByMarket(any())).thenAnswer((_) async => []);
      when(
        () => mockDb.getLatestFinancialDataDatesBatch(any(), any()),
      ).thenAnswer((_) async => const {});

      final tracker = ApiBudgetTracker();
      for (var i = 0; i < 520; i++) {
        tracker.recordCall(ApiVendor.finMind);
      }
      final finMind = FinMindClient(budgetTracker: tracker);
      addTearDown(finMind.close);

      final mockFundamental = buildFundamentalMock();
      final service = buildService(
        fundamental: mockFundamental,
        finMind: finMind,
      );
      await service.runDailyUpdate(forDate: tradingDay);

      verifyNever(
        () => mockFundamental.syncFinancialStatements(
          symbol: any(named: 'symbol'),
          startDate: any(named: 'startDate'),
          endDate: any(named: 'endDate'),
        ),
      );
    });

    test('🚨 自選股必須經由 priority 進回填，且額度吃緊時先截熱門、不截自選', () async {
      // priority = {...watchlist, ...popular}：自選在前。used=380 → limit=10，
      // priority 有 1+15=16 檔 → 只同步前 10 檔。自選那檔不在候選池、也不是熱門，
      // 只有 priority 這條路能到它；若接線漏掉 watchlist、或 popular 排在前面，這裡轉紅
      const watched = '5471';
      when(() => mockDb.getWatchlist()).thenAnswer(
        (_) async => [WatchlistEntry(symbol: watched, createdAt: tradingDay)],
      );
      stubCandidates(twseCandidates);
      when(() => mockDb.getStocksByMarket(any())).thenAnswer((_) async => []);
      when(
        () => mockDb.getLatestFinancialDataDatesBatch(any(), any()),
      ).thenAnswer((_) async => const {});

      final tracker = ApiBudgetTracker();
      for (var i = 0; i < 380; i++) {
        tracker.recordCall(ApiVendor.finMind);
      }
      final finMind = FinMindClient(budgetTracker: tracker);
      addTearDown(finMind.close);

      final mockFundamental = buildFundamentalMock();
      final service = buildService(
        fundamental: mockFundamental,
        finMind: finMind,
      );
      await service.runDailyUpdate(forDate: tradingDay);

      final synced = verify(
        () => mockFundamental.syncFinancialStatements(
          symbol: captureAny(named: 'symbol'),
          startDate: any(named: 'startDate'),
          endDate: any(named: 'endDate'),
        ),
      ).captured.cast<String>();

      expect(synced.length, 10, reason: 'limit=(600-380-200)/2=10');
      expect(synced, contains(watched), reason: '自選股在 priority 最前，截斷截的是熱門股');
      expect(
        synced.where(DefaultStocks.popularStocks.contains).length,
        9,
        reason: '剩下 9 個名額給熱門股，回填一檔都沒有',
      );
    });

    test('🚨 低波動、無 INCOME 的上市股必須排在「已新鮮的候選」前面——名額不是給波動度的', () async {
      // 生產實況(2026-09-05 app DB):460 檔只有官方批次給的資產負債表、零 EPS,
      // 其中 18 檔當天有評分且全是上市大型低波動股(台灣大 3045、群光 2385…)。
      // live 路徑的候選依波動度降冪,上市名額窗取前 N → 這些股票永遠排不進去;
      // 本週五輪實測被回填的 102 檔裡 0 檔來自那 460 檔。
      const starved = '3045';
      final fresh = TaiwanCalendar.expectedLatestReportQuarter(DateTime.now());
      // 名額窗塞滿「已新鮮」的高波動候選,餓死的那檔排在最後
      final volatileFresh = [for (var i = 0; i < 400; i++) '${2000 + i}'];
      stubCandidates([...volatileFresh, starved]);
      when(() => mockDb.getStocksByMarket(any())).thenAnswer((_) async => []);
      when(
        () => mockDb.getLatestFinancialDataDatesBatch(any(), any()),
      ).thenAnswer((_) async => {for (final s in volatileFresh) s: fresh});

      final mockFundamental = buildFundamentalMock();
      final service = buildService(fundamental: mockFundamental);
      await service.runDailyUpdate(forDate: tradingDay);

      verify(
        () => mockFundamental.syncFinancialStatements(
          symbol: starved,
          startDate: any(named: 'startDate'),
          endDate: any(named: 'endDate'),
        ),
      ).called(1);
    });
  });

  // 步驟 6.6 的歷史回補：用本月同步剩下的份額、同一個 now；本月同步失敗時
  // 不回補；回補的失敗只記 log，不進 errors（收斂期每輪都會有，進 errors 會
  // 讓每一輪都 PARTIAL、launchd exit 1）
  group('步驟 6.6 歷史回補', () {
    MockTpexClient healthyTpex() {
      final tpex = MockTpexClient();
      when(
        () => mockTdcc.getAllHoldingDistribution(),
      ).thenAnswer((_) async => {});
      when(() => mockDb.getAllActiveStocks()).thenAnswer((_) async => []);
      when(
        () => mockDb.upsertDividendDistributions(any()),
      ).thenAnswer((_) async {});
      when(
        () => mockDb.getDividendDistributionKeys(
          from: any(named: 'from'),
          to: any(named: 'to'),
        ),
      ).thenAnswer((_) async => {});
      when(() => tpex.getDeclaredDividends()).thenAnswer((_) async => []);
      when(() => tpex.getShareholderMeetings()).thenAnswer((_) async => []);
      when(() => tpex.getInsiderTransfers()).thenAnswer((_) async => []);
      when(
        () => tpex.getExRightResults(
          startDate: any(named: 'startDate'),
          endDate: any(named: 'endDate'),
        ),
      ).thenAnswer((_) async => []);
      return tpex;
    }

    Future<List<dynamic>> capturedBackfill() async => verify(
      () => mockBackfiller.backfill(
        now: captureAny(named: 'now'),
        maxCalls: captureAny(named: 'maxCalls'),
        scope: any(named: 'scope'),
      ),
    ).captured;

    test('回補拿到本月同步剩下的份額（只有上櫃：30 − 1）', () async {
      await buildService(
        tpex: healthyTpex(),
      ).runDailyUpdate(forDate: tradingDay);

      final captured = await capturedBackfill();
      expect(captured[1], 29);
    });

    test('本月同步與回補用同一個 now（只取一次時鐘）', () async {
      final tpex = healthyTpex();
      await buildService(
        tpex: tpex,
        clock: _IncrementingClock(DateTime(2026, 7, 6, 15, 30)),
      ).runDailyUpdate(forDate: tradingDay);

      final now = (await capturedBackfill())[0] as DateTime;
      final syncEnd =
          verify(
                () => tpex.getExRightResults(
                  startDate: any(named: 'startDate'),
                  endDate: captureAny(named: 'endDate'),
                ),
              ).captured.single
              as DateTime;
      expect(syncEnd, DateTime(now.year, now.month, now.day));
      expect(now, isNot(DateTime(2026, 7, 6, 15, 30)), reason: '時鐘遞增有效');
    });

    for (final (name, error) in [
      ('限流', const RateLimitException('redirect loop') as Object),
      ('網路錯誤', const NetworkException('timeout')),
    ]) {
      test('本月同步$name：不回補', () async {
        final tpex = healthyTpex();
        when(
          () => tpex.getExRightResults(
            startDate: any(named: 'startDate'),
            endDate: any(named: 'endDate'),
          ),
        ).thenThrow(error);

        await buildService(tpex: tpex).runDailyUpdate(forDate: tradingDay);

        verifyNever(
          () => mockBackfiller.backfill(
            now: any(named: 'now'),
            maxCalls: any(named: 'maxCalls'),
            scope: any(named: 'scope'),
          ),
        );
      });
    }

    test('本月同步有 per-source 錯誤：回補照常，errors 只有那一條', () async {
      final tpex = healthyTpex();
      when(
        () => tpex.getExRightResults(
          startDate: any(named: 'startDate'),
          endDate: any(named: 'endDate'),
        ),
      ).thenThrow(Exception('exDailyQ payload broken'));

      final result = await buildService(
        tpex: tpex,
      ).runDailyUpdate(forDate: tradingDay);

      await capturedBackfill();
      expect(result.errors.where((e) => e.contains('除權除息')), hasLength(1));
    });

    test('回補整體拋錯：本輪仍成功、不進 errors、不標限流；記 error 送 Sentry', () async {
      final captured = <String>[];
      AppLogger.setSentryDelegates(
        capture: (error, _, tag, message) =>
            captured.add('$tag $message $error'),
      );
      addTearDown(AppLogger.setSentryDelegates);
      when(
        () => mockBackfiller.backfill(
          now: any(named: 'now'),
          maxCalls: any(named: 'maxCalls'),
          scope: any(named: 'scope'),
        ),
      ).thenThrow(Exception('disk I/O error'));

      final result = await buildService(
        tpex: healthyTpex(),
      ).runDailyUpdate(forDate: tradingDay);

      expect(result.success, isTrue);
      // mock 環境下其他步驟本來就有無關的 errors，只看回補相關的
      expect(
        result.errors.where((e) => e.contains('回補') || e.contains('disk I/O')),
        isEmpty,
      );
      expect(result.hasRateLimitError, isFalse);
      expect(captured.where((c) => c.contains('除權除息回補失敗（系統性）')), [
        contains('disk I/O error'),
      ]);
    });

    test('回補有市場被停掉：警示行記成 warning（Sentry breadcrumb）、不進 errors', () async {
      final warnings = <String>[];
      AppLogger.setSentryDelegates(
        breadcrumb: (message, _, level, _) {
          if (level == 'warning') warnings.add(message);
        },
      );
      addTearDown(AppLogger.setSentryDelegates);
      when(
        () => mockBackfiller.backfill(
          now: any(named: 'now'),
          maxCalls: any(named: 'maxCalls'),
          scope: any(named: 'scope'),
        ),
      ).thenAnswer(
        (inv) async => _backfillSummary(
          inv.namedArguments[#now] as DateTime,
          marketStops: {'TWSE': 'TWSE 網路錯誤，本輪停止'},
        ),
      );

      final result = await buildService(
        tpex: healthyTpex(),
      ).runDailyUpdate(forDate: tradingDay);

      expect(result.errors.where((e) => e.contains('除權除息')), isEmpty);
      expect(
        warnings.where((w) => w.contains('停掉的市場：TWSE 網路錯誤')),
        hasLength(1),
      );
    });

    // 中止旗標翻起來由 update_service_contract_guard_test 靜態守住：6.6 之後
    // 沒有步驟讀它，這裡從行為上觀察不到
    test('回補撞到限流：不進 errors、不標限流錯誤', () async {
      when(
        () => mockBackfiller.backfill(
          now: any(named: 'now'),
          maxCalls: any(named: 'maxCalls'),
          scope: any(named: 'scope'),
        ),
      ).thenAnswer(
        (inv) async => _backfillSummary(
          inv.namedArguments[#now] as DateTime,
          rateLimitError: const RateLimitException('redirect loop'),
        ),
      );

      final result = await buildService(
        tpex: healthyTpex(),
      ).runDailyUpdate(forDate: tradingDay);

      expect(result.errors.where((e) => e.contains('除權除息')), isEmpty);
      expect(result.hasRateLimitError, isFalse);
    });

    test('進度訊息：同步除權息資料', () async {
      final messages = <String>[];
      await buildService(tpex: healthyTpex()).runDailyUpdate(
        forDate: tradingDay,
        onProgress: (_, _, m) => messages.add(m),
      );

      expect(messages, contains('同步除權息資料'));
    });

    test('真實接線：回補由新到舊打到上個月的上櫃列表；限流不進 errors', () async {
      final tpex = healthyTpex();
      when(() => mockDb.getAllActiveStocks()).thenAnswer(
        (_) async => [
          for (var i = 0; i < 500; i++)
            StockMasterEntry(
              symbol: 'T$i',
              name: 'T$i',
              market: 'TPEx',
              isActive: true,
              updatedAt: DateTime(2026, 7, 1),
            ),
        ],
      );
      when(
        () => mockDb.getDividendMonthLedgerEntries(),
      ).thenAnswer((_) async => []);
      when(() => mockDb.getDividendMonthFailures()).thenAnswer((_) async => []);
      when(
        () => tpex.getExRightResults(
          startDate: DateTime(2026, 6, 1),
          endDate: DateTime(2026, 6, 30),
        ),
      ).thenThrow(const RateLimitException('redirect loop'));

      final result = await buildService(
        tpex: tpex,
        realDividendBackfiller: true,
      ).runDailyUpdate(forDate: tradingDay);

      verify(
        () => tpex.getExRightResults(
          startDate: DateTime(2026, 6, 1),
          endDate: DateTime(2026, 6, 30),
        ),
      ).called(1);
      expect(result.hasRateLimitError, isFalse);
      expect(result.errors.where((e) => e.contains('回補')), isEmpty);
    });
  });

  // 步驟 6.6 除權除息排在 5.5 未定案重抓與 6.5 上櫃候選補充之後、評分之前：
  // 前兩步抓的是本輪評分要用的資料，不能被除權除息的限流擋掉；5.5 撞到限流
  // 時 6.6 不再打 TWSE。
  group('步驟 6.6 的位置', () {
    void stubDividendDb() {
      when(
        () => mockDb.getDividendDistributionKeys(
          from: any(named: 'from'),
          to: any(named: 'to'),
        ),
      ).thenAnswer((_) async => {});
      when(
        () => mockDb.upsertDividendDistributions(any()),
      ).thenAnswer((_) async {});
    }

    // 對照組放一列要查明細的上市資料：每輪上限的接線要夠打兩個列表＋查明細
    // （這條會真的等一次 2 秒明細間隔，UpdateService 層無法注入）
    for (final refetchLimited in [false, true]) {
      test('5.5 ${refetchLimited ? '限流' : '正常'}：6.6 除權除息'
          '${refetchLimited ? '不執行' : '兩市場列表與明細都照常執行'}', () async {
        final summary = RefetchSummary();
        if (refetchLimited) {
          summary.rateLimitError = const RateLimitException('429');
        }
        when(
          () => mockRefetcher.refetchPending(
            today: any(named: 'today'),
            ledger: any(named: 'ledger'),
          ),
        ).thenAnswer((_) async => summary);
        // 少這行 syncer 會在打列表前拋錯，verifyNever 空轉成假綠
        when(() => mockDb.getAllActiveStocks()).thenAnswer(
          (_) async => [
            StockMasterEntry(
              symbol: '2836',
              name: '高雄銀',
              market: 'TWSE',
              isActive: true,
              updatedAt: DateTime(2026, 7, 1),
            ),
          ],
        );
        stubDividendDb();
        final twse = MockTwseClient();
        final tpex = MockTpexClient();
        when(
          () => twse.getExRightResults(
            startDate: any(named: 'startDate'),
            endDate: any(named: 'endDate'),
          ),
        ).thenAnswer(
          (_) async => [
            ExRightResult(
              symbol: '2836',
              exDate: DateTime(2026, 7, 3),
              cashDividend: null,
              stockSharesPerThousand: null,
            ),
          ],
        );
        when(() => twse.getExRightDetail('2836', any())).thenAnswer(
          (_) async => const ExRightDetail(
            symbol: '2836',
            cashDividend: 0.15,
            stockSharesPerThousand: 45,
          ),
        );
        when(
          () => tpex.getExRightResults(
            startDate: any(named: 'startDate'),
            endDate: any(named: 'endDate'),
          ),
        ).thenAnswer((_) async => []);

        await buildService(
          twse: twse,
          tpex: tpex,
        ).runDailyUpdate(forDate: tradingDay);

        for (final call in [
          () => twse.getExRightResults(
            startDate: any(named: 'startDate'),
            endDate: any(named: 'endDate'),
          ),
          () => tpex.getExRightResults(
            startDate: any(named: 'startDate'),
            endDate: any(named: 'endDate'),
          ),
          () => twse.getExRightDetail('2836', DateTime(2026, 7, 3)),
        ]) {
          if (refetchLimited) {
            verifyNever(call);
          } else {
            verify(call).called(1);
          }
        }
      });
    }

    for (final dividendLimited in [false, true]) {
      test('6.6 ${dividendLimited ? '限流' : '正常'}：6.5 上櫃候選補充照常執行', () async {
        final mockTpex = MockTpexClient();
        when(
          () => mockTdcc.getAllHoldingDistribution(),
        ).thenAnswer((_) async => {});
        when(() => mockDb.getAllActiveStocks()).thenAnswer((_) async => []);
        stubDividendDb();
        when(() => mockTpex.getDeclaredDividends()).thenAnswer((_) async => []);
        when(
          () => mockTpex.getShareholderMeetings(),
        ).thenAnswer((_) async => []);
        when(() => mockTpex.getInsiderTransfers()).thenAnswer((_) async => []);
        final exRight = when(
          () => mockTpex.getExRightResults(
            startDate: any(named: 'startDate'),
            endDate: any(named: 'endDate'),
          ),
        );
        if (dividendLimited) {
          exRight.thenThrow(const RateLimitException('redirect loop'));
        } else {
          exRight.thenAnswer((_) async => []);
        }
        // 讓候選非空，6.5 才會走到回報進度那一步
        when(
          () => mockDb.getSymbolsWithSufficientData(
            minDays: any(named: 'minDays'),
            startDate: any(named: 'startDate'),
            endDate: any(named: 'endDate'),
          ),
        ).thenAnswer((_) async => ['6488']);

        final messages = <String>[];
        final result = await buildService(tpex: mockTpex).runDailyUpdate(
          forDate: tradingDay,
          onProgress: (_, _, m) => messages.add(m),
        );

        expect(messages, contains('補充上櫃資料'));
        expect(result.hasRateLimitError, dividendLimited);
      });
    }
  });

  group('盤後資料定案接線（2026-09-26）', () {
    test('每輪開始清兩個 client 的快取', () async {
      final twse = MockTwseClient();
      final tpex = MockTpexClient();
      await buildService(
        twse: twse,
        tpex: tpex,
      ).runDailyUpdate(forDate: tradingDay);
      verify(() => twse.clearCache()).called(1);
      verify(() => tpex.clearCache()).called(1);
    });

    test('清快取發生在第一次抓取之前', () async {
      final twse = MockTwseClient();
      final tpex = MockTpexClient();
      await buildService(
        twse: twse,
        tpex: tpex,
      ).runDailyUpdate(forDate: tradingDay);
      verifyInOrder([
        () => twse.clearCache(),
        () => tpex.clearCache(),
        () => mockPriceRepo.syncAllPricesForDate(
          any(),
          force: any(named: 'force'),
          ledger: any(named: 'ledger'),
        ),
      ]);
    });

    test('價格同步收到 ledger，時間＝本輪開始的時鐘值（第一次 now() 呼叫，不是後面某次）', () async {
      // 🚨 M2：固定時鐘（_Clock）不管呼叫幾次都回同一個值，測不出「用的是
      // 不是第一次呼叫」。改用遞增時鐘，若實作在建立 ledger 之後又多呼叫一次
      // `_clock.now()` 才拿去用，這裡就會抓到（fetchedAt 會變成之後的值）。
      final clock = _IncrementingClock(DateTime(2026, 7, 6, 15, 30));
      await buildService(clock: clock).runDailyUpdate(forDate: tradingDay);

      final priceLedgerCaptured = verify(
        () => mockPriceRepo.syncAllPricesForDate(
          any(),
          force: any(named: 'force'),
          ledger: captureAny(named: 'ledger'),
        ),
      ).captured;
      final priceLedger = priceLedgerCaptured.single as MarketDayFetchLedger;
      expect(priceLedger.fetchedAt, clock.firstValue);

      // 同一個 ledger 實例貫穿全程：refetcher 收到的必須與價格同步收到的是
      // 同一個物件（不是另一個 fetchedAt 恰好相等的新實例）
      final refetcherLedgerCaptured = verify(
        () => mockRefetcher.refetchPending(
          today: any(named: 'today'),
          ledger: captureAny(named: 'ledger'),
        ),
      ).captured;
      final refetcherLedger =
          refetcherLedgerCaptured.single as MarketDayFetchLedger;
      expect(identical(refetcherLedger, priceLedger), isTrue);
    });

    test('重抓被呼叫；限流時結果帶限流錯誤', () async {
      final summary = RefetchSummary()
        ..rateLimitError = const RateLimitException('429');
      when(
        () => mockRefetcher.refetchPending(
          today: any(named: 'today'),
          ledger: any(named: 'ledger'),
        ),
      ).thenAnswer((_) async => summary);
      final result = await buildService().runDailyUpdate(forDate: tradingDay);
      verify(
        () => mockRefetcher.refetchPending(
          today: any(named: 'today'),
          ledger: any(named: 'ledger'),
        ),
      ).called(1);
      expect(result.hasRateLimitError, isTrue);
    });

    test('非交易日提早結束：不清快取、不重抓', () async {
      final twse = MockTwseClient();
      await buildService(twse: twse).runDailyUpdate(
        forDate: DateTime(2026, 7, 11), // 週六
      );
      verifyNever(() => twse.clearCache());
      verifyNever(
        () => mockRefetcher.refetchPending(
          today: any(named: 'today'),
          ledger: any(named: 'ledger'),
        ),
      );
    });
  });
}

class _Clock implements AppClock {
  const _Clock(this._now);
  final DateTime _now;

  @override
  DateTime now() => _now;
}

/// M2：每次呼叫回傳遞增的時間，讓「用第一次呼叫還是後面某次」可被測出來
/// （固定時鐘 [_Clock] 不管呼叫幾次都回同一個值，測不出這件事）。
class _IncrementingClock implements AppClock {
  _IncrementingClock(this.firstValue);

  final DateTime firstValue;
  int _calls = 0;

  @override
  DateTime now() {
    final value = firstValue.add(Duration(seconds: _calls));
    _calls++;
    return value;
  }
}
