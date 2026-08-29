import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';

import 'package:daredevil/core/constants/market_codes.dart';
import 'package:daredevil/core/constants/market_index_names.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/data/remote/twse_client.dart';
import 'package:daredevil/data/remote/tpex_client.dart';
import 'package:daredevil/presentation/providers/market_overview_provider.dart';
import 'package:daredevil/presentation/providers/providers.dart';

// ==========================================
// Mocks
// ==========================================

class MockAppDatabase extends Mock implements AppDatabase {}

class MockTwseClient extends Mock implements TwseClient {}

class MockTpexClient extends Mock implements TpexClient {}

// ==========================================
// Tests
// ==========================================

void main() {
  late MockAppDatabase mockDb;
  late MockTwseClient mockTwse;
  late MockTpexClient mockTpex;
  late ProviderContainer container;

  final testDate = DateTime.utc(2026, 2, 13);

  setUp(() {
    mockDb = MockAppDatabase();
    mockTwse = MockTwseClient();
    mockTpex = MockTpexClient();

    container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(mockDb),
        twseClientProvider.overrideWithValue(mockTwse),
        tpexClientProvider.overrideWithValue(mockTpex),
      ],
    );
  });

  tearDown(() {
    container.dispose();
  });

  /// 設定所有 mock 回傳空/預設值
  void setupEmptyDefaults() {
    when(() => mockDb.getLatestDataDate()).thenAnswer((_) async => testDate);
    when(() => mockTwse.getMarketIndices()).thenAnswer((_) async => []);
    when(
      () => mockTwse.getInstitutionalAmounts(date: any(named: 'date')),
    ).thenAnswer((_) async => null);
    when(
      () => mockTpex.getInstitutionalAmounts(date: any(named: 'date')),
    ).thenAnswer((_) async => null);
    when(() => mockDb.getLatestMarginTradingTotalsByMarket()).thenAnswer(
      (_) async =>
          <
            String,
            ({
              double marginBalance,
              double marginChange,
              double shortBalance,
              double shortChange,
              DateTime? dataDate,
            })
          >{},
    );
    when(
      () => mockDb.getIndexHistoryBatch(any(), days: any(named: 'days')),
    ).thenAnswer((_) async => {});
    when(
      () => mockDb.getAdvanceDeclineCountsByMarket(any()),
    ).thenAnswer((_) async => {});
    // 2026-08-29 靜默稽核 #7 的副產品:此 stub 原本缺席,既有測試一直讓
    // marginHistory 在 MissingStub 下靜默失敗——正是那條 catch→空的形狀,
    // 新的 failedSections 斷言把它照了出來
    when(
      () => mockDb.getRecentMarginTradingByMarket(
        any(),
        days: any(named: 'days'),
      ),
    ).thenAnswer((_) async => {});
    when(
      () => mockDb.getTurnoverSummaryByMarket(any()),
    ).thenAnswer((_) async => {});
    when(
      () => mockTpex.getTpexIndex(),
    ).thenAnswer((_) async => <TwseMarketIndex>[]);
    when(
      () => mockDb.getLimitUpDownCountsByMarket(any()),
    ).thenAnswer((_) async => <String, ({int limitUp, int limitDown})>{});
    when(
      () => mockDb.getRecentTurnoverByMarket(any(), days: any(named: 'days')),
    ).thenAnswer(
      (_) async => <String, List<({DateTime date, double turnover})>>{},
    );
    when(
      () => mockDb.getActiveWarningCountsByMarket(),
    ).thenAnswer((_) async => <String, Map<String, int>>{});
    when(
      () => mockDb.getRecentInstitutionalDailyByMarket(
        any(),
        days: any(named: 'days'),
      ),
    ).thenAnswer(
      (_) async =>
          <
            String,
            List<
              ({
                DateTime date,
                double foreignNet,
                double trustNet,
                double dealerNet,
                double? dealerSelfNet,
              })
            >
          >{},
    );
    when(() => mockDb.getIndustrySummaryByMarket(any(), any())).thenAnswer(
      (_) async =>
          <
            ({
              String industry,
              int stockCount,
              double avgChangePct,
              int advance,
              int decline,
            })
          >[],
    );
    when(
      () => mockDb.getNewHighLowCountsByMarket(
        any(),
        lookbackDays: any(named: 'lookbackDays'),
      ),
    ).thenAnswer((_) async => <String, ({int newHighs, int newLows})>{});
    when(
      () => mockDb.getRecentAdvanceDeclineByMarket(
        any(),
        days: any(named: 'days'),
        minCoverage: any(named: 'minCoverage'),
      ),
    ).thenAnswer(
      (_) async =>
          <
            String,
            List<({DateTime date, int advance, int decline, int unchanged})>
          >{},
    );
  }

  group('MarketOverviewState', () {
    test('has correct default values', () {
      const state = MarketOverviewState();

      expect(state.indices, isEmpty);
      expect(state.indexHistory, isEmpty);
      expect(state.isLoading, isFalse);
      expect(state.error, isNull);
      expect(state.dataDate, isNull);
      expect(state.hasData, isFalse);
    });

    test('hasData returns true when indices present', () {
      final state = MarketOverviewState(
        indices: [
          TwseMarketIndex(
            date: testDate,
            name: '加權指數',
            close: 20000,
            change: 100,
            changePercent: 0.5,
          ),
        ],
      );

      expect(state.hasData, isTrue);
    });

    test('hasData returns true when advanceDeclineByMarket has data', () {
      const state = MarketOverviewState(
        advanceDeclineByMarket: {
          'TWSE': AdvanceDecline(advance: 500, decline: 300),
        },
      );

      expect(state.hasData, isTrue);
    });

    test('copyWith creates new instance preserving unset values', () {
      const original = MarketOverviewState(isLoading: true);

      final updated = original.copyWith(isLoading: false, error: 'test');

      expect(updated.isLoading, isFalse);
      expect(updated.error, 'test');
      expect(updated.indices, isEmpty);
    });
  });

  group('AdvanceDecline', () {
    test('total is sum of all components', () {
      const ad = AdvanceDecline(advance: 500, decline: 300, unchanged: 200);

      expect(ad.total, 1000);
    });
  });

  group('MarketOverviewNotifier', () {
    test('initial state has default values', () {
      setupEmptyDefaults();

      final state = container.read(marketOverviewProvider);

      expect(state.isLoading, isFalse);
      expect(state.error, isNull);
      expect(state.indices, isEmpty);
    });

    test('🚨 區塊查詢失敗 → failedSections 列名(靜默稽核 #7)', () async {
      // 最尖銳的例子:注意/處置家數查詢失敗與「今天零警示」原本同樣渲染
      // 成安靜市場——現在 state 帶著失敗名單,儀表板標題掛註記
      setupEmptyDefaults();
      when(
        () => mockDb.getActiveWarningCountsByMarket(),
      ).thenThrow(Exception('boom'));

      final notifier = container.read(marketOverviewProvider.notifier);
      await notifier.loadData();

      final state = container.read(marketOverviewProvider);
      expect(state.failedSections, contains('warningCounts'));
      expect(state.error, isNull, reason: '主流程仍成功——這正是它原本隱形的原因');
    });

    test('全部正常 → failedSections 為空(不誤報)', () async {
      setupEmptyDefaults();
      // 健康日必須有指數:`setupEmptyDefaults` 的空指數會讓畫面根本沒有
      // Hero 卡,那不是「正常」——它現在(正確地)被列進 failedSections
      when(() => mockTwse.getMarketIndices()).thenAnswer(
        (_) async => [
          TwseMarketIndex(
            date: testDate,
            name: MarketIndexNames.taiex,
            close: 20000,
            change: 150,
            changePercent: 0.75,
          ),
        ],
      );
      final notifier = container.read(marketOverviewProvider.notifier);
      await notifier.loadData();
      expect(container.read(marketOverviewProvider).failedSections, isEmpty);
    });

    test('🚨 API 成功但無可用指數(名稱漂移/TPEx 空)→ 同樣列名', () async {
      // 與「API 全掛」不同路徑:TWSE 有回應但名稱全不在 dashboardIndices
      // (端點改名),TPEx 空、DB 也空 → filtered 收尾仍為空。使用者看到的
      // 同樣是沒有 Hero 卡,揭露不能只綁「API 拋例外」
      setupEmptyDefaults();
      when(() => mockTwse.getMarketIndices()).thenAnswer(
        (_) async => [
          TwseMarketIndex(
            date: testDate,
            name: '某個沒人認得的指數',
            close: 100,
            change: 1,
            changePercent: 1,
          ),
        ],
      );
      when(() => mockTpex.getTpexIndex()).thenAnswer((_) async => []);

      final notifier = container.read(marketOverviewProvider.notifier);
      await notifier.loadData();

      final state = container.read(marketOverviewProvider);
      expect(state.indices, isEmpty);
      expect(state.failedSections, contains('indices'));
    });

    test('🚨 指數 API 全掛且 DB 也空 → failedSections 說出來(review 補洞)', () async {
      // staleNames 只在 DB 拿得到資料時才有內容:兩者皆空時三條揭露管道
      // (indices/staleNames/error)同時靜默,而 mobile TWSE 分支連兜底
      // 文案都沒有——2026-08-29 review 實測的形狀
      setupEmptyDefaults();
      when(() => mockTwse.getMarketIndices()).thenThrow(Exception('down'));
      when(() => mockTpex.getTpexIndex()).thenThrow(Exception('down'));

      final notifier = container.read(marketOverviewProvider.notifier);
      await notifier.loadData();

      final state = container.read(marketOverviewProvider);
      expect(state.indices, isEmpty, reason: '前提:連 DB 備援都沒資料');
      expect(state.indexStaleNames, isEmpty, reason: '前提:staleNames 此時幫不上忙');
      expect(state.error, isNull, reason: '前提:主流程仍成功——原本因此全靜默');
      expect(state.failedSections, contains('indices'));
    });

    test('🚨 指數 API 全掛 → DB 備援全部列入 indexStaleNames(靜默稽核 #3)', () async {
      // 盤中 API 掛掉時 Hero 卡原本把昨收當即時值——回退必須留下標記,
      // 與同 provider 的 advanceDeclineStaleDates 防護對稱
      setupEmptyDefaults();
      when(() => mockTwse.getMarketIndices()).thenThrow(Exception('down'));
      when(() => mockTpex.getTpexIndex()).thenThrow(Exception('down'));
      when(
        () => mockDb.getIndexHistoryBatch(any(), days: any(named: 'days')),
      ).thenAnswer(
        (_) async => {
          '發行量加權股價指數': [
            MarketIndexEntry(
              id: 1,
              name: '發行量加權股價指數',
              date: testDate.subtract(const Duration(days: 1)),
              close: 21000,
              change: -100,
              changePercent: -0.5,
              createdAt: testDate,
            ),
          ],
        },
      );

      final notifier = container.read(marketOverviewProvider.notifier);
      await notifier.loadData();

      final state = container.read(marketOverviewProvider);
      expect(state.indices.map((i) => i.name), contains('發行量加權股價指數'));
      expect(
        state.indexStaleNames,
        contains('發行量加權股價指數'),
        reason: 'DB 補的昨收必須標 stale,不得與即時值同貌',
      );
    });

    test('指數 API 正常 → indexStaleNames 為空(不誤標)', () async {
      setupEmptyDefaults();
      when(() => mockTwse.getMarketIndices()).thenAnswer(
        (_) async => [
          TwseMarketIndex(
            date: testDate,
            name: '發行量加權股價指數',
            close: 20000,
            change: 150,
            changePercent: 0.75,
          ),
        ],
      );

      final notifier = container.read(marketOverviewProvider.notifier);
      await notifier.loadData();

      expect(container.read(marketOverviewProvider).indexStaleNames, isEmpty);
    });

    test('loadData sets loading and loads all data in parallel', () async {
      setupEmptyDefaults();

      // Override with actual data
      when(() => mockTwse.getMarketIndices()).thenAnswer(
        (_) async => [
          TwseMarketIndex(
            date: testDate,
            name: '發行量加權股價指數',
            close: 20000,
            change: 150,
            changePercent: 0.75,
          ),
          TwseMarketIndex(
            date: testDate,
            name: '未上榜指數',
            close: 100,
            change: 1,
            changePercent: 0.01,
          ),
        ],
      );

      when(() => mockDb.getAdvanceDeclineCountsByMarket(any())).thenAnswer(
        (_) async => {'TWSE': (advance: 500, decline: 300, unchanged: 200)},
      );

      final notifier = container.read(marketOverviewProvider.notifier);
      final loadFuture = notifier.loadData();

      // isLoading should be true immediately
      expect(container.read(marketOverviewProvider).isLoading, isTrue);

      await loadFuture;

      final state = container.read(marketOverviewProvider);
      expect(state.isLoading, isFalse);
      expect(state.error, isNull);
      expect(state.dataDate, testDate);
      expect(state.advanceDeclineByMarket['TWSE']!.advance, 500);
      expect(state.advanceDeclineByMarket['TWSE']!.decline, 300);
      expect(state.advanceDeclineByMarket['TWSE']!.unchanged, 200);

      // Verify indices are filtered to dashboardIndices only
      expect(state.indices.length, 1);
      expect(state.indices[0].name, '發行量加權股價指數');
    });

    test('loadData populates institutional totals by market', () async {
      setupEmptyDefaults();

      when(
        () => mockTwse.getInstitutionalAmounts(date: any(named: 'date')),
      ).thenAnswer(
        (_) async => TwseInstitutionalAmounts(
          date: testDate,
          foreignNet: 1000000,
          trustNet: 500000,
          dealerNet: -200000,
        ),
      );

      when(
        () => mockTpex.getInstitutionalAmounts(date: any(named: 'date')),
      ).thenAnswer(
        (_) async => TpexInstitutionalAmounts(
          date: testDate,
          foreignNet: 300000,
          trustNet: 100000,
          dealerNet: -50000,
        ),
      );

      final notifier = container.read(marketOverviewProvider.notifier);
      await notifier.loadData();

      final state = container.read(marketOverviewProvider);
      final twse = state.institutionalByMarket['TWSE']!;
      expect(twse.foreignNet, 1000000);
      expect(twse.trustNet, 500000);
      expect(twse.dealerNet, -200000);
      final tpex = state.institutionalByMarket['TPEx']!;
      expect(tpex.foreignNet, 300000);
    });

    test('loadData populates margin trading totals from DB', () async {
      setupEmptyDefaults();

      when(() => mockDb.getLatestMarginTradingTotalsByMarket()).thenAnswer(
        (_) async => {
          'TWSE': (
            marginBalance: 30000.0,
            marginChange: 700.0,
            shortBalance: 2000.0,
            shortChange: -100.0,
            dataDate: DateTime(2024, 3, 26),
          ),
          'TPEx': (
            marginBalance: 20000.0,
            marginChange: 300.0,
            shortBalance: 1000.0,
            shortChange: -100.0,
            dataDate: DateTime(2024, 3, 25),
          ),
        },
      );

      final notifier = container.read(marketOverviewProvider.notifier);
      await notifier.loadData();

      final state = container.read(marketOverviewProvider);
      final twseMargin = state.marginByMarket['TWSE']!;
      expect(twseMargin.marginBalance, 30000.0);
      expect(twseMargin.marginChange, 700.0);
      final tpexMargin = state.marginByMarket['TPEx']!;
      expect(tpexMargin.shortBalance, 1000.0);
      expect(tpexMargin.shortChange, -100.0);
    });

    test('loadData populates by-market breakdowns', () async {
      setupEmptyDefaults();

      when(() => mockDb.getAdvanceDeclineCountsByMarket(any())).thenAnswer(
        (_) async => {
          'TWSE': (advance: 400, decline: 200, unchanged: 100),
          'TPEx': (advance: 100, decline: 100, unchanged: 100),
        },
      );

      when(() => mockDb.getTurnoverSummaryByMarket(any())).thenAnswer(
        (_) async => {
          'TWSE': (totalTurnover: 200000000000.0),
          'TPEx': (totalTurnover: 50000000000.0),
        },
      );

      final notifier = container.read(marketOverviewProvider.notifier);
      await notifier.loadData();

      final state = container.read(marketOverviewProvider);
      expect(state.advanceDeclineByMarket['TWSE']?.advance, 400);
      expect(state.advanceDeclineByMarket['TPEx']?.decline, 100);
      expect(state.turnoverByMarket['TWSE']?.totalTurnover, 200000000000.0);
      expect(
        state.advanceDeclineStaleDates,
        isEmpty,
        reason: '兩市場當日皆有資料 → 無回退、staleDates 應為空',
      );
    });

    test('某市場當日缺資料 → 回退前一交易日並記錄 advanceDeclineStaleDates', () async {
      setupEmptyDefaults();

      // any() = 回退日（含兩市場）；testDate = 當日只有上櫃（上市個股未釋出）。
      // mocktail 後註冊的 stub 優先，故 testDate 呼叫回 TPEx-only、回退日呼叫回兩者。
      when(() => mockDb.getAdvanceDeclineCountsByMarket(any())).thenAnswer(
        (_) async => {
          'TWSE': (advance: 250, decline: 800, unchanged: 70),
          'TPEx': (advance: 400, decline: 350, unchanged: 60),
        },
      );
      when(() => mockDb.getAdvanceDeclineCountsByMarket(testDate)).thenAnswer(
        (_) async => {'TPEx': (advance: 400, decline: 350, unchanged: 60)},
      );

      final notifier = container.read(marketOverviewProvider.notifier);
      await notifier.loadData();

      final state = container.read(marketOverviewProvider);
      // 上市當日缺資料 → 標記為回退（stale），且資料採回退日
      expect(
        state.advanceDeclineStaleDates.containsKey('TWSE'),
        isTrue,
        reason: '上市當日缺資料 → 應記錄 advanceDeclineStaleDates',
      );
      expect(
        state.advanceDeclineByMarket['TWSE']?.advance,
        250,
        reason: '上市漲跌家數採用回退日資料',
      );
      // 上櫃當日有資料 → 不算 stale
      expect(
        state.advanceDeclineStaleDates.containsKey('TPEx'),
        isFalse,
        reason: '上櫃當日有資料 → 不應標記 stale',
      );
    });

    test('loadData handles error gracefully', () async {
      when(
        () => mockDb.getLatestDataDate(),
      ).thenThrow(Exception('DB connection failed'));

      final notifier = container.read(marketOverviewProvider.notifier);
      await notifier.loadData();

      final state = container.read(marketOverviewProvider);
      expect(state.isLoading, isFalse);
      expect(state.error, isNotNull);
      expect(state.error, isNotEmpty);
    });

    test('individual load failures do not affect other sections', () async {
      setupEmptyDefaults();

      // API indices fails, but DB queries succeed
      when(
        () => mockTwse.getMarketIndices(),
      ).thenThrow(Exception('Network error'));

      when(() => mockDb.getAdvanceDeclineCountsByMarket(any())).thenAnswer(
        (_) async => {'TWSE': (advance: 100, decline: 50, unchanged: 20)},
      );

      final notifier = container.read(marketOverviewProvider.notifier);
      await notifier.loadData();

      final state = container.read(marketOverviewProvider);
      expect(state.error, isNull); // no top-level error
      expect(state.indices, isEmpty); // indices failed gracefully
      expect(
        state.advanceDeclineByMarket['TWSE']!.advance,
        100,
      ); // DB data loaded
    });

    test('loadData uses DateTime.now() when no data date in DB', () async {
      setupEmptyDefaults();
      when(() => mockDb.getLatestDataDate()).thenAnswer((_) async => null);

      final notifier = container.read(marketOverviewProvider.notifier);
      await notifier.loadData();

      final state = container.read(marketOverviewProvider);
      expect(state.dataDate, isNotNull);
    });

    test('loadData populates breadth trend (new high/low + AD line)', () async {
      setupEmptyDefaults();

      when(
        () => mockDb.getNewHighLowCountsByMarket(
          any(),
          lookbackDays: any(named: 'lookbackDays'),
        ),
      ).thenAnswer(
        (_) async => {
          'TWSE': (newHighs: 156, newLows: 29),
          'TPEx': (newHighs: 82, newLows: 55),
        },
      );

      // 日期降序（最新在前）：每日 adv-dec = +50, +30, -20
      // 反轉 oldest→newest 後累積 = [-20, 10, 60]
      when(
        () => mockDb.getRecentAdvanceDeclineByMarket(
          any(),
          days: any(named: 'days'),
          minCoverage: any(named: 'minCoverage'),
        ),
      ).thenAnswer(
        (_) async => {
          'TWSE': [
            (date: testDate, advance: 80, decline: 30, unchanged: 0), // +50
            (
              date: testDate.subtract(const Duration(days: 1)),
              advance: 60,
              decline: 30,
              unchanged: 0,
            ), // +30
            (
              date: testDate.subtract(const Duration(days: 2)),
              advance: 40,
              decline: 60,
              unchanged: 0,
            ), // -20
          ],
        },
      );

      final notifier = container.read(marketOverviewProvider.notifier);
      await notifier.loadData();

      final state = container.read(marketOverviewProvider);
      expect(state.newHighLowByMarket['TWSE']?.newHighs, 156);
      expect(state.newHighLowByMarket['TWSE']?.newLows, 29);
      expect(state.newHighLowByMarket['TPEx']?.newHighs, 82);
      expect(state.newHighLowByMarket['TPEx']?.newLows, 55);

      // 累積 AD 線 oldest→newest：[-20, -20+30=10, 10+50=60]
      expect(state.adLineByMarket['TWSE'], [-20.0, 10.0, 60.0]);
    });

    // ── 自營 streak 改用 dealerSelfNet（null-safe）─────────────
    //
    // setupEmptyDefaults 讓 getInstitutionalAmounts 回 null → instByMarket 空，
    // _validateStreakConsistency 對 streak 直接 pass-through（不做方向對齊），
    // 故可純粹驗 dealerSelfNet 的 streak 計算。
    group('dealer streak uses dealerSelfNet (null-safe)', () {
      DateTime d(int back) => testDate.subtract(Duration(days: back));

      /// 設定法人每日聚合（日期降序，最新在前）。
      /// [dealerSelf] 與 daily 等長，逐日對應 dealer_self_net（可含 null）。
      void stubInstDaily(List<double?> dealerSelf) {
        when(
          () => mockDb.getRecentInstitutionalDailyByMarket(
            any(),
            days: any(named: 'days'),
          ),
        ).thenAnswer(
          (_) async => {
            'TWSE': [
              for (var i = 0; i < dealerSelf.length; i++)
                (
                  date: d(i),
                  foreignNet: 0.0,
                  trustNet: 0.0,
                  // 含避險合計刻意恆正（重現 bug 前提：合計 streak 失真），
                  // 但 streak 應改採 dealerSelfNet，不受此影響。
                  dealerNet: 100.0,
                  dealerSelfNet: dealerSelf[i],
                ),
            ],
          },
        );
      }

      test('populated dealerSelfNet → correct buy streak', () async {
        setupEmptyDefaults();
        // 最新 3 日皆買超（>0），第 4 日翻空 → streak = +3
        stubInstDaily([5.0, 4.0, 3.0, -2.0, -1.0]);

        final notifier = container.read(marketOverviewProvider.notifier);
        await notifier.loadData();

        final state = container.read(marketOverviewProvider);
        expect(
          state.institutionalStreakByMarket['TWSE']?.dealerStreak,
          3,
          reason: '自營 streak 應為 +3（自行買賣，非含避險合計）',
        );
      });

      test('populated dealerSelfNet → correct sell streak', () async {
        setupEmptyDefaults();
        stubInstDaily([-5.0, -4.0, 2.0]);

        final notifier = container.read(marketOverviewProvider.notifier);
        await notifier.loadData();

        final state = container.read(marketOverviewProvider);
        expect(
          state.institutionalStreakByMarket['TWSE']?.dealerStreak,
          -2,
          reason: '連 2 日賣超 → -2',
        );
      });

      test('latest day null dealerSelfNet → streak 0 (badge hidden)', () async {
        setupEmptyDefaults();
        // 全為歷史 NULL（重新同步前的舊資料）
        stubInstDaily([null, null, null]);

        final notifier = container.read(marketOverviewProvider.notifier);
        await notifier.loadData();

        final state = container.read(marketOverviewProvider);
        expect(
          state.institutionalStreakByMarket['TWSE']?.dealerStreak,
          0,
          reason: '最新日 dealerSelfNet 為 null → streak 0，badge 隱藏',
        );
      });

      test('mid-series null breaks the run (not counted)', () async {
        setupEmptyDefaults();
        // 最新 2 日買超，第 3 日 null → streak 停在 2（null 中斷，不誤計）
        stubInstDaily([5.0, 4.0, null, 3.0, 2.0]);

        final notifier = container.read(marketOverviewProvider.notifier);
        await notifier.loadData();

        final state = container.read(marketOverviewProvider);
        expect(
          state.institutionalStreakByMarket['TWSE']?.dealerStreak,
          2,
          reason: '中段 null 中斷 streak，不把 null 後的同向日納入',
        );
      });

      test('含避險合計反號 → 對齊重置自行買賣 streak（隱藏矛盾 badge）', () async {
        setupEmptyDefaults();
        // 自行買賣連 3 日買超 → self streak +3
        stubInstDaily([5.0, 4.0, 3.0, -2.0]);
        // 但今日「含避險合計」為負（避險反向）：與 self streak 方向矛盾。
        // 與外資/投信一致對齊 → 重置 -1（|−1|<2 → badge 隱藏），避免「連3日買超」
        // 配負值顯示金額的散戶誤讀。
        when(
          () => mockTwse.getInstitutionalAmounts(date: any(named: 'date')),
        ).thenAnswer(
          (_) async => TwseInstitutionalAmounts(
            date: testDate,
            foreignNet: 0,
            trustNet: 0,
            dealerNet: -9999,
          ),
        );

        final notifier = container.read(marketOverviewProvider.notifier);
        await notifier.loadData();

        final state = container.read(marketOverviewProvider);
        expect(
          state.institutionalStreakByMarket['TWSE']?.dealerStreak,
          -1,
          reason: '自營 streak 與含避險合計反號 → 對齊重置 -1，badge 隱藏',
        );
      });

      test('含避險合計同號 → 保留自行買賣 streak（一致則照常顯示）', () async {
        setupEmptyDefaults();
        // 自行買賣連 3 日買超 → self streak +3
        stubInstDaily([5.0, 4.0, 3.0, -2.0]);
        // 今日「含避險合計」同為正：方向一致 → 保留 +3，badge 照常顯示。
        when(
          () => mockTwse.getInstitutionalAmounts(date: any(named: 'date')),
        ).thenAnswer(
          (_) async => TwseInstitutionalAmounts(
            date: testDate,
            foreignNet: 0,
            trustNet: 0,
            dealerNet: 9999,
          ),
        );

        final notifier = container.read(marketOverviewProvider.notifier);
        await notifier.loadData();

        final state = container.read(marketOverviewProvider);
        expect(
          state.institutionalStreakByMarket['TWSE']?.dealerStreak,
          3,
          reason: '自營 streak 與含避險合計同號 → 保留 +3，badge 照常顯示',
        );
      });

      test(
        'foreign/trust streaks unaffected by dealerSelfNet switch',
        () async {
          setupEmptyDefaults();
          when(
            () => mockDb.getRecentInstitutionalDailyByMarket(
              any(),
              days: any(named: 'days'),
            ),
          ).thenAnswer(
            (_) async => {
              'TWSE': [
                for (var i = 0; i < 3; i++)
                  (
                    date: d(i),
                    foreignNet: 10.0, // 連 3 日買超
                    trustNet: -5.0, // 連 3 日賣超
                    dealerNet: 100.0,
                    dealerSelfNet: null, // 自營隱藏，不影響外資/投信
                  ),
              ],
            },
          );

          final notifier = container.read(marketOverviewProvider.notifier);
          await notifier.loadData();

          final streak = container
              .read(marketOverviewProvider)
              .institutionalStreakByMarket['TWSE']!;
          expect(streak.foreignStreak, 3, reason: '外資 streak 仍用 foreignNet');
          expect(streak.trustStreak, -3, reason: '投信 streak 仍用 trustNet');
          expect(streak.dealerStreak, 0, reason: '自營 dealerSelfNet 全 null → 0');
        },
      );
    });

    test('history sparklines 保留各自完整序列（不被情緒對齊的日期交集縮短）', () async {
      setupEmptyDefaults();

      // 兩組來源日期集刻意不同（重現 bug 前提）：
      // - turnover / advanceRatio：coverage-filter 過，僅 8 個完整日。
      // - institutional / margin：未 filter，12 個每日（含 turnover/AD 缺的 4 個舊日）。
      // 全部 DAO 回傳日期降序（最新在前）。
      DateTime d(int back) => testDate.subtract(Duration(days: back));

      // 8 個完整日（back 0..7）
      when(
        () => mockDb.getRecentTurnoverByMarket(any(), days: any(named: 'days')),
      ).thenAnswer(
        (_) async => {
          'TWSE': [
            for (var back = 0; back < 8; back++)
              (date: d(back), turnover: 1000.0 + back),
          ],
        },
      );
      when(
        () => mockDb.getRecentAdvanceDeclineByMarket(
          any(),
          days: any(named: 'days'),
          minCoverage: any(named: 'minCoverage'),
        ),
      ).thenAnswer(
        (_) async => {
          'TWSE': [
            for (var back = 0; back < 8; back++)
              (date: d(back), advance: 60, decline: 40, unchanged: 0),
          ],
        },
      );

      // 12 個每日（back 0..11）— 比上面多出 back 8..11 共 4 個舊日
      when(
        () => mockDb.getRecentInstitutionalDailyByMarket(
          any(),
          days: any(named: 'days'),
        ),
      ).thenAnswer(
        (_) async => {
          'TWSE': [
            for (var back = 0; back < 12; back++)
              (
                date: d(back),
                foreignNet: 100.0 + back,
                trustNet: 0.0,
                dealerNet: 0.0,
                dealerSelfNet: 0.0,
              ),
          ],
        },
      );
      when(
        () => mockDb.getRecentMarginTradingByMarket(
          any(),
          days: any(named: 'days'),
        ),
      ).thenAnswer(
        (_) async => {
          'TWSE': [
            for (var back = 0; back < 12; back++)
              (
                date: d(back),
                marginBalance: 10000.0 + back,
                shortBalance: 500.0 + back,
              ),
          ],
        },
      );

      final notifier = container.read(marketOverviewProvider.notifier);
      await notifier.loadData();

      final state = container.read(marketOverviewProvider);
      final trends = state.historyTrends;

      // 個別 sparkline 必須維持各自完整長度，不被 4-way 日期交集（8）縮短。
      expect(
        trends.turnover['TWSE'],
        hasLength(8),
        reason: 'turnover sparkline 應為完整 8 日',
      );
      expect(
        trends.advanceRatio['TWSE'],
        hasLength(8),
        reason: 'advanceRatio sparkline 應為完整 8 日',
      );
      expect(
        trends.institutionalTotalNet['TWSE'],
        hasLength(12),
        reason: 'institutional sparkline 應為完整 12 日（未被縮到交集 8）',
      );
      expect(
        trends.marginBalance['TWSE'],
        hasLength(12),
        reason: 'margin sparkline 應為完整 12 日（未被縮到交集 8）',
      );
      expect(
        trends.shortBalance['TWSE'],
        hasLength(12),
        reason: 'short sparkline 應為完整 12 日',
      );

      // 帶日期序列為 oldest→newest（最舊在前）。
      final turnover = trends.turnover['TWSE']!;
      expect(turnover.first.date.isBefore(turnover.last.date), isTrue);
    });

    // ── 產業 5 日動能：fail-soft 契約 + 正規化撞名加權合併 ─────────
    //
    // momentum5d 管線已於 2026-08-13 移除(唯一 UI 讀者「產業表現」區塊
    // 併入族群排行,情緒綜合只讀 avgChangePct)。原 fail-soft 測試隨管線
    // 刪除;撞名正規化「合併」本身仍是活邏輯,保留改寫如下。
    group('產業名稱正規化合併', () {
      test('兩個原始產業名稱撞同一 canonical → 合併為一筆,stockCount 加權', () async {
        setupEmptyDefaults();

        // 真實撞名對:IndustryNames._normalizationMap 中「觀光事業」與
        // 「觀光餐旅」皆正規化為「觀光餐旅類」。
        when(() => mockDb.getIndustrySummaryByMarket(any(), 'TWSE')).thenAnswer(
          (_) async => [
            (
              industry: '觀光事業',
              stockCount: 10,
              avgChangePct: 3.0,
              advance: 6,
              decline: 4,
            ),
            (
              industry: '觀光餐旅',
              stockCount: 30,
              avgChangePct: 1.0,
              advance: 15,
              decline: 15,
            ),
          ],
        );

        final notifier = container.read(marketOverviewProvider.notifier);
        await notifier.loadData();

        final state = container.read(marketOverviewProvider);
        final twseIndustries = state.industrySummaryByMarket['TWSE']!;

        expect(
          twseIndustries,
          hasLength(1),
          reason: '兩筆原始名稱皆正規化為「觀光餐旅類」→ 應合併為一筆',
        );

        final merged = twseIndustries.single;
        expect(merged.industry, '觀光餐旅類');
        expect(merged.stockCount, 40, reason: '10 + 30');
        // stockCount 加權:(3.0*10 + 1.0*30) / 40 = 1.5(算術平均會是 2.0)
        expect(merged.avgChangePct, closeTo(1.5, 1e-9));
        expect(merged.advance, 21);
        expect(merged.decline, 19);
      });
    });
  });

  group('cumulativeAdLine', () {
    test('running sum oldest→newest on known series', () {
      expect(cumulativeAdLine([5, 3, -2, 4]), [5.0, 8.0, 6.0, 10.0]);
    });

    test('all-positive series strictly increases', () {
      expect(cumulativeAdLine([1, 1, 1]), [1.0, 2.0, 3.0]);
    });

    test('all-negative series strictly decreases', () {
      expect(cumulativeAdLine([-1, -2, -3]), [-1.0, -3.0, -6.0]);
    });

    test('single element returns itself', () {
      expect(cumulativeAdLine([7]), [7.0]);
    });

    test('empty input returns empty list', () {
      expect(cumulativeAdLine([]), isEmpty);
    });
  });

  // 籌碼槓桿判讀拿「最新指數」配「較舊的融資資料」，結論可能整個反過來
  //
  // market_dashboard.dart 的 `_indexChangePercent` 掃 `state.indices` 取
  // **最新**漲跌幅，但融資融券區塊自帶較舊的 sectionDate（TWSE 約 21:00 才
  // 發布，傍晚更新時常落後 1~3 天，畫面也確實標著該日期）。兩者被組成一句
  // 因果陳述送進 `MarketReadingService.interpretMarginLeverage`。
  //
  // 2026-07-27 20:39 實機（融資資料日 07-24）：
  //   櫃買指數 07-24 = **-3.69%**（融資那天，大跌）
  //   櫃買指數 07-27 = +0.12%（畫面取的）
  //   → 顯示「指數漲、融資減：籌碼洗清，相對健康」（positive）
  //   → 正確應為「指數跌、融資減：去槓桿中」（neutral）
  // **結論相反且更樂觀**：使用者會以為籌碼在轉好，實際上那天櫃買跌 3.69%，
  // 是恐慌性去槓桿。上市側 07-24 與 07-27 同為下跌，故結論碰巧一致、看不出來。
  //
  // 與本日修掉的「近期法人動向其實是單日」「營收年增取到兩年前那月」同型：
  // **用不同時間基準的兩個事實組成一句因果陳述**。
  group('融資判讀必須用融資資料當天的指數', () {
    test('🚨 融資日與最新日不同時，state 要帶出融資日的指數漲跌幅', () async {
      setupEmptyDefaults();
      final marginDay = DateTime(2026, 7, 24);
      final latestDay = DateTime(2026, 7, 27);

      when(() => mockDb.getLatestMarginTradingTotalsByMarket()).thenAnswer(
        (_) async => {
          MarketCode.tpex: (
            marginBalance: 2220000.0,
            marginChange: -12000.0,
            shortBalance: 36000.0,
            shortChange: 6915.0,
            dataDate: marginDay,
          ),
        },
      );
      when(
        () => mockDb.getIndexHistoryBatch(any(), days: any(named: 'days')),
      ).thenAnswer(
        (_) async => {
          MarketIndexNames.tpexIndex: [
            MarketIndexEntry(
              id: 1,
              date: marginDay,
              name: MarketIndexNames.tpexIndex,
              close: 377.63,
              change: -14.48,
              changePercent: -3.69,
              createdAt: marginDay,
            ),
            MarketIndexEntry(
              id: 2,
              date: latestDay,
              name: MarketIndexNames.tpexIndex,
              close: 378.09,
              change: 0.46,
              changePercent: 0.12,
              createdAt: latestDay,
            ),
          ],
        },
      );

      await container.read(marketOverviewProvider.notifier).loadData();
      final state = container.read(marketOverviewProvider);

      expect(
        state.marginIndexChangePercent[MarketCode.tpex],
        -3.69,
        reason:
            '判讀句要用融資那天的指數。取最新的 +0.12% 會把「去槓桿中」講成'
            '「籌碼洗清，相對健康」——方向相反且更樂觀',
      );
    });

    test('🚨 雙市場融資日不同:各市場用**自己的**融資日配指數(2026-08-01 複審)', () async {
      // 初版修法把兩市場融資日壓成單一 earliest scalar——TPEx(較舊)配對
      // 正確,但 TWSE 被迫用 TPEx 的舊日期配自己較新的融資值,要修的
      // 日期錯配換個市場重現。融資 T+1 差異是常態不是例外。
      setupEmptyDefaults();
      final twseDay = DateTime(2026, 7, 28); // TWSE 融資較新
      final tpexDay = DateTime(2026, 7, 27); // TPEx T+1 落後

      when(() => mockDb.getLatestMarginTradingTotalsByMarket()).thenAnswer(
        (_) async => {
          MarketCode.twse: (
            marginBalance: 3000000.0,
            marginChange: 5000.0,
            shortBalance: 40000.0,
            shortChange: -100.0,
            dataDate: twseDay,
          ),
          MarketCode.tpex: (
            marginBalance: 2220000.0,
            marginChange: -12000.0,
            shortBalance: 36000.0,
            shortChange: 6915.0,
            dataDate: tpexDay,
          ),
        },
      );
      when(
        () => mockDb.getIndexHistoryBatch(any(), days: any(named: 'days')),
      ).thenAnswer(
        (_) async => {
          MarketIndexNames.taiex: [
            MarketIndexEntry(
              id: 1,
              date: tpexDay,
              name: MarketIndexNames.taiex,
              close: 41000,
              change: -900,
              changePercent: -2.15, // 舊日——TWSE 不得用這天
              createdAt: tpexDay,
            ),
            MarketIndexEntry(
              id: 2,
              date: twseDay,
              name: MarketIndexNames.taiex,
              close: 41500,
              change: 500,
              changePercent: 1.22, // TWSE 融資日的正確配對
              createdAt: twseDay,
            ),
          ],
          MarketIndexNames.tpexIndex: [
            MarketIndexEntry(
              id: 3,
              date: tpexDay,
              name: MarketIndexNames.tpexIndex,
              close: 377.63,
              change: -14.48,
              changePercent: -3.69, // TPEx 融資日的正確配對
              createdAt: tpexDay,
            ),
          ],
        },
      );

      await container.read(marketOverviewProvider.notifier).loadData();
      final state = container.read(marketOverviewProvider);

      expect(
        state.marginIndexChangePercent[MarketCode.twse],
        1.22,
        reason: 'TWSE 要用自己的融資日(7/28)指數,不得用 TPEx 的舊日(7/27)',
      );
      expect(
        state.marginIndexChangePercent[MarketCode.tpex],
        -3.69,
        reason: 'TPEx 用自己的融資日(7/27)',
      );
    });

    test('對照組：查不到融資日的指數時回 null，寧可不顯示也不要用錯的', () async {
      setupEmptyDefaults();
      when(() => mockDb.getLatestMarginTradingTotalsByMarket()).thenAnswer(
        (_) async => {
          MarketCode.tpex: (
            marginBalance: 2220000.0,
            marginChange: -12000.0,
            shortBalance: 36000.0,
            shortChange: 6915.0,
            dataDate: DateTime(2026, 7, 24),
          ),
        },
      );
      // 指數歷史沒有 07-24 那天
      when(
        () => mockDb.getIndexHistoryBatch(any(), days: any(named: 'days')),
      ).thenAnswer(
        (_) async => {
          MarketIndexNames.tpexIndex: [
            MarketIndexEntry(
              id: 1,
              date: DateTime(2026, 7, 27),
              name: MarketIndexNames.tpexIndex,
              close: 378.09,
              change: 0.46,
              changePercent: 0.12,
              createdAt: DateTime(2026, 7, 27),
            ),
          ],
        },
      );

      await container.read(marketOverviewProvider.notifier).loadData();
      final state = container.read(marketOverviewProvider);

      expect(
        state.marginIndexChangePercent[MarketCode.tpex],
        isNull,
        reason: '缺對應日資料時不得回退到最新值——那正是這個 bug 本身',
      );
    });
  });
}
