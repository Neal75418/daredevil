import 'dart:async';
import 'package:daredevil/core/constants/api_config.dart';
import 'package:daredevil/core/constants/rule_enums.dart';
import 'package:daredevil/core/exceptions/app_exception.dart';
import 'package:daredevil/core/constants/market_codes.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/data/remote/tdcc_client.dart';
import 'package:daredevil/data/remote/api_budget_tracker.dart';
import 'package:daredevil/data/remote/finmind_client.dart';
import 'package:daredevil/data/remote/tpex_client.dart';
import 'package:daredevil/data/repositories/analysis_repository.dart';
import 'package:daredevil/data/repositories/fundamental_repository.dart';
import 'package:daredevil/data/repositories/insider_repository.dart';
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
import 'package:daredevil/domain/services/update/news_mention_snapshot_service.dart';
import 'package:daredevil/domain/services/thesis/thesis_monitor_service.dart';
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

  setUpAll(() {
    registerFallbackValue(DateTime(2026, 7, 6));
    registerFallbackValue(
      ScoringBatchData(pricesMap: const {}, newsMap: const {}),
    );
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
    when(() => mockPriceRepo.syncAllPricesForDate(any())).thenAnswer(
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
    // TDCC 新鮮度檢查：無本週資料
    when(
      () => mockDb.getLatestHoldingDistributionDate(any()),
    ).thenAnswer((_) async => null);
  });

  /// 建立最小依賴的 UpdateService：
  /// 預設只提供 tdcc client（twse/tpex/finMind 為 null → 對應 syncer 不建立），
  /// 只提供 required repositories（institutional 等為 null → 對應 syncer 不建立）。
  /// 各測試可額外注入 tpex / fundamental 以啟用對應 syncer。
  UpdateService buildService({
    TpexClient? tpex,
    FinMindClient? finMind,
    FundamentalRepository? fundamental,
    NewsMentionSnapshotService? newsMentionSnapshot,
    TradingRepository? trading,
    ShareholdingRepository? shareholding,
    WarningRepository? warning,
    InsiderRepository? insider,
    ThesisMonitorService? thesisMonitor,
  }) {
    return UpdateService(
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
      clients: UpdateClients(tdcc: mockTdcc, tpex: tpex, finMind: finMind),
      services: UpdateServices(
        scoring: mockScoring,
        newsMentionSnapshot: newsMentionSnapshot,
        thesisMonitor: thesisMonitor,
      ),
    );
  }

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

    test('半個市場價格取得失敗必須可見（TWSE 空、TPEx 有資料）', () async {
      // safeAwait 把來源失敗吞成空陣列：只有 TWSE 掛掉時 tpexPrices 非空、
      // 不進「兩者皆空」分支 → 用半個市場的資料照常評分且無人知曉。
      when(() => mockPriceRepo.syncAllPricesForDate(any())).thenAnswer(
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
      when(() => mockPriceRepo.syncAllPricesForDate(any())).thenAnswer(
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

      final service = buildService(tpex: mockTpex);
      final result = await service.runDailyUpdate(forDate: tradingDay);

      expect(result.success, isTrue);
      // DividendSyncResult.errors 必須被 caller 讀取並轉發，否則靜默
      expect(result.errors, anyElement(contains('股利')));
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
        () => mockFundamental.syncOtcRevenue(
          any(),
          date: any(named: 'date'),
          force: any(named: 'force'),
        ),
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
  // syncer 內部捕捉 RateLimitException 後只設區域旗標中止迴圈、不 rethrow
  // （這是對的——已抓到的歷史資料要保留），但沒把「為什麼中止」帶出去：
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
      when(() => mockPriceRepo.syncAllPricesForDate(any())).thenAnswer(
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
      when(() => mockPriceRepo.syncAllPricesForDate(any())).thenAnswer(
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
  // update_service.dart:756-759 用 Dart record 的 `.wait` 平行跑損益表與資產
  // 負債表。record `.wait` 在任一支失敗時拋的是 **ParallelWaitError**，不是
  // 底層例外，於是 :767 的 `on RateLimitException` 永遠不會觸發。
  //
  // 2026-07-27 實跑驗證（非推理）：
  //   A record.wait  → 落 generic，型別 ParallelWaitError<(int?, int?), ...>
  //   B Future.wait  → 分型 catch 命中
  //   C 兩者皆錯     → Future.wait 拋清單中第一個
  //   D             → Future.wait 仍等所有 future 結束，不留 unhandled error
  //
  // 影響：`UpdateResult.recordError` 的 `if (exception is RateLimitException)`
  // （update_service.dart:1140）判不到 → `hasRateLimitError` 恆為 false →
  // today_screen.dart:820 的限流專屬提示永遠不亮，使用者只看到一般警告數。
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
  // 掃過全部 16 處 record `.wait`：只有 update_service.dart:759 落在有
  // `on RateLimitException` 的 try 裡。:287 那處包的四個 helper 各自有內部
  // try/catch 並自行設 rateLimitedAbort，例外不會逸出——**不是同型，別順手改**。
  // 2026-08-01 實機(run #123 force):額度 600/600 時 getStockList 拋
  // RateLimitException,syncer 按慣例 rethrow,但 _syncStockList 是唯一
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
      when(() => mockPriceRepo.syncAllPricesForDate(any())).thenAnswer(
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

  // 步驟 4.7 的目標清單由兩條佇列組成：上市走
  // `selectFinancialSyncTargets`（取 `[...twse, ...tpex]` 的前 150 名），
  // 上櫃走 `FundamentalSyncer.selectOtcFinancialBacklog`（獨立配額、最舊優先）。
  //
  // 這組測試守的是**接線**：backlog 算出來卻沒接進同步呼叫會是靜默 no-op，
  // 日誌照印、測試照綠，而上櫃覆蓋率原地不動——正是本輪要修的病本身。
  group('financialQuotaForBudget(2026-08-05 季報季額度爆量修復)', () {
    // 背景:上市佇列原無額度守衛(假設「重跑 needy 為空」),Q2 季報季
    // 全市場同時變 needy → 每輪 150+100 檔 ×2=488 次呼叫,單輪吃掉
    // 82% 小時額度,連點更新即 402、其他 FinMind 步驟全滅。
    test('🚨 整點滿額度:上市滿額、上櫃吃剩餘,總支出必留 reserve', () {
      final q = UpdateService.financialQuotaForBudget(
        usage: (used: 0, budget: 600),
      );
      expect(q.twse, ApiConfig.financialSyncMaxCandidates);
      expect(q.otc, lessThan(ApiConfig.otcFinancialSyncMaxCount));
      final spend = (q.twse + q.otc) * 2;
      expect(
        600 - spend,
        greaterThanOrEqualTo(ApiConfig.financialBackfillReserve),
        reason: '財報支出後必須留 reserve 給本輪其餘步驟+下一次手動更新',
      );
    });

    test('🚨 同小時第二輪:額度耗到 reserve 內 → 兩市場皆 0(快速通過)', () {
      final q = UpdateService.financialQuotaForBudget(
        usage: (used: 450, budget: 600),
      );
      expect(q.twse, 0);
      expect(q.otc, 0);
    });

    test('部分額度:上市先拿、上櫃吃剩', () {
      // affordable = (600-300-200)/2 = 50 → twse 50、otc 0
      final q = UpdateService.financialQuotaForBudget(
        usage: (used: 300, budget: 600),
      );
      expect(q.twse, 50);
      expect(q.otc, 0);
    });

    test('usage null(未掛 tracker)→ 回上限(量不到≠沒額度)', () {
      final q = UpdateService.financialQuotaForBudget(usage: null);
      expect(q.twse, ApiConfig.financialSyncMaxCandidates);
      expect(q.otc, ApiConfig.otcFinancialSyncMaxCount);
    });
  });

  group('步驟 4.7：上櫃財報回填佇列', () {
    /// 上市候選遠多於 `financialSyncMaxCandidates`，模擬正式環境
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
        () => mock.syncOtcRevenue(
          any(),
          date: any(named: 'date'),
          force: any(named: 'force'),
        ),
      ).thenAnswer((_) async => 0);
      return mock;
    }

    void stubCandidates(List<String> candidates) {
      when(() => mockPriceRepo.syncAllPricesForDate(any())).thenAnswer(
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

    test('🚨 上櫃候選排在上市之後，仍須拿到財報同步（現行串接下永遠是 0）', () async {
      stubCandidates([...twseCandidates, otcSymbol]);
      when(() => mockDb.getStocksByMarket(any())).thenAnswer(
        (_) async => [
          StockMasterEntry(
            symbol: otcSymbol,
            name: '松翰',
            market: MarketCode.tpex,
            industry: '半導體',
            isActive: true,
            updatedAt: tradingDay,
          ),
        ],
      );
      when(
        () => mockDb.getLatestFinancialDataDatesBatch(any(), any()),
      ).thenAnswer((_) async => const {});

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

    test('🚨 額度吃緊時上櫃回填必須縮量（守接線：算出的上限要真的傳下去）', () async {
      stubCandidates([
        ...twseCandidates,
        for (var i = 0; i < 60; i++) '${5400 + i}',
      ]);
      when(() => mockDb.getStocksByMarket(any())).thenAnswer(
        (_) async => [
          for (var i = 0; i < 60; i++)
            StockMasterEntry(
              symbol: '${5400 + i}',
              name: 'OTC$i',
              market: MarketCode.tpex,
              industry: '半導體',
              isActive: true,
              updatedAt: tradingDay,
            ),
        ],
      );
      when(
        () => mockDb.getLatestFinancialDataDatesBatch(any(), any()),
      ).thenAnswer((_) async => const {});

      // 2026-08-05 季報季修復後語意更新:配額統一為 financialQuotaForBudget
      // (reserve 200、上市先拿)。used=60 → affordable=(600-60-200)/2=170
      // → 上市拿滿 150、上櫃吃剩 20——沿用「算出的上限要真的傳下去」的
      // 接線守護(若接線漏掉仍傳固定 100,這裡會是 60=候選全數)。
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
      final otcSynced = synced.where((s) => s.startsWith('54')).length;

      expect(
        otcSynced,
        20,
        reason:
            '上市先拿 150 後上櫃只剩 20((600-60-200)/2-150)。若接線漏掉、'
            '仍傳固定 100,這裡會是 60(候選全數)——撞爆 600 的路徑',
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

    test('對照組：上市配額不得被上櫃佇列排擠', () async {
      stubCandidates([...twseCandidates, otcSymbol]);
      when(() => mockDb.getStocksByMarket(any())).thenAnswer(
        (_) async => [
          StockMasterEntry(
            symbol: otcSymbol,
            name: '松翰',
            market: MarketCode.tpex,
            industry: '半導體',
            isActive: true,
            updatedAt: tradingDay,
          ),
        ],
      );
      when(
        () => mockDb.getLatestFinancialDataDatesBatch(any(), any()),
      ).thenAnswer((_) async => const {});

      final mockFundamental = buildFundamentalMock();
      final service = buildService(fundamental: mockFundamental);
      await service.runDailyUpdate(forDate: tradingDay);

      final synced = verify(
        () => mockFundamental.syncFinancialStatements(
          symbol: captureAny(named: 'symbol'),
          startDate: any(named: 'startDate'),
          endDate: any(named: 'endDate'),
        ),
      ).captured.cast<String>();

      expect(
        synced.where((s) => s != otcSymbol).length,
        ApiConfig.financialSyncMaxCandidates,
        reason: '上櫃走獨立配額，上市那 150 個名額必須原封不動',
      );
    });
  });
}
