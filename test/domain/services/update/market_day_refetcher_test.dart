import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:daredevil/core/constants/api_config.dart';
import 'package:daredevil/core/constants/market_codes.dart';
import 'package:daredevil/core/constants/market_dataset.dart';
import 'package:daredevil/core/exceptions/app_exception.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/data/repositories/market_day_fetch_ledger.dart';
import 'package:daredevil/data/repositories/shareholding_repository.dart';
import 'package:daredevil/domain/repositories/institutional_repository.dart';
import 'package:daredevil/domain/repositories/price_repository.dart';
import 'package:daredevil/domain/repositories/trading_repository.dart';
import 'package:daredevil/domain/services/update/market_day_refetcher.dart';

class MockPriceRepository extends Mock implements IPriceRepository {}

class MockInstitutionalRepository extends Mock
    implements IInstitutionalRepository {}

class MockTradingRepository extends Mock implements ITradingRepository {}

class MockShareholdingRepository extends Mock
    implements ShareholdingRepository {}

void main() {
  group('refetchCandidateDays', () {
    test('早於今天、不早於追蹤起始日、只含交易日，新→舊', () {
      final days = refetchCandidateDays(
        today: DateTime(2026, 9, 29, 15, 30),
        trackingSince: DateTime(2026, 9, 23),
      );
      // 9/25 中秋、9/26–27 週末、9/28 教師節
      expect(days, [DateTime(2026, 9, 24), DateTime(2026, 9, 23)]);
    });

    test('追蹤起始日早於 40 日曆天窗時以窗口為界', () {
      final days = refetchCandidateDays(
        today: DateTime(2026, 9, 29),
        trackingSince: DateTime(2026, 1, 1),
      );
      expect(days.last.isBefore(DateTime(2026, 8, 20)), isFalse);
      // 窗口起點＝9/29 往回 40 日曆天＝8/20（交易日，精確落在邊界上）
      expect(days.last, DateTime(2026, 8, 20));
    });

    test('第一次執行（起始日＝今天）沒有候選日', () {
      expect(
        refetchCandidateDays(
          today: DateTime(2026, 9, 29),
          trackingSince: DateTime(2026, 9, 29),
        ),
        isEmpty,
      );
    });
  });

  group('selectRefetchDays', () {
    MarketDayFetchEntry fetch(
      MarketDataset ds,
      String m,
      DateTime d,
      DateTime at,
    ) => MarketDayFetchEntry(
      dataset: ds.code,
      market: m,
      date: d,
      fetchedAt: at,
      rowCount: 1,
    );

    final d1 = DateTime(2026, 9, 24);
    final d2 = DateTime(2026, 9, 23);

    test('沒有狀態列或未定案的日子入選；已定案的不入選', () {
      final plan = selectRefetchDays(
        candidateDays: [d1, d2],
        fetches: [
          fetch(
            MarketDataset.prices,
            MarketCode.twse,
            d1,
            DateTime(2026, 9, 24, 21, 30),
          ),
          fetch(
            MarketDataset.prices,
            MarketCode.twse,
            d2,
            DateTime(2026, 9, 24, 15, 30),
          ),
        ],
        maxPerGroup: 10,
      );
      expect(plan[(dataset: MarketDataset.prices, market: MarketCode.twse)], [
        d1,
      ]);
      expect(plan[(dataset: MarketDataset.prices, market: MarketCode.tpex)], [
        d1,
        d2,
      ]);
    });

    test('每組最多 maxPerGroup 天（取最新的）', () {
      final plan = selectRefetchDays(
        candidateDays: [d1, d2],
        fetches: const [],
        maxPerGroup: 1,
      );
      expect(plan[(dataset: MarketDataset.margin, market: MarketCode.tpex)], [
        d1,
      ]);
    });

    test('9 組都有計畫（外資持股只有上市）', () {
      final plan = selectRefetchDays(
        candidateDays: [d1],
        fetches: const [],
        maxPerGroup: 10,
      );
      expect(plan.keys, hasLength(9));
      expect(
        plan.containsKey((
          dataset: MarketDataset.foreignShareholding,
          market: MarketCode.tpex,
        )),
        isFalse,
      );
    });
  });

  group('MarketDayRefetcher', () {
    late AppDatabase db;
    late MockPriceRepository price;
    late MockInstitutionalRepository inst;
    late MockTradingRepository trading;
    late MockShareholdingRepository sh;
    late MarketDayRefetcher refetcher;
    late MarketDayFetchLedger ledger;
    final today = DateTime(2026, 9, 29, 15, 30);
    final d = DateTime(2026, 9, 24);
    final calls = <String>[];

    setUpAll(() {
      registerFallbackValue(DateTime(2026));
      registerFallbackValue(<String>{});
    });

    setUp(() async {
      db = AppDatabase.forTesting();
      await db.upsertStocks([
        StockMasterCompanion.insert(
          symbol: '1101',
          name: 'a',
          market: MarketCode.twse,
        ),
        StockMasterCompanion.insert(
          symbol: '3624',
          name: 'b',
          market: MarketCode.tpex,
        ),
      ]);
      await db.setSetting(MarketDayRefetcher.trackingSinceKey, '2026-09-24');
      price = MockPriceRepository();
      inst = MockInstitutionalRepository();
      trading = MockTradingRepository();
      sh = MockShareholdingRepository();
      calls.clear();
      when(
        () => price.backfillTwsePricesByDate(
          date: any(named: 'date'),
          targetSymbols: any(named: 'targetSymbols'),
          ledger: any(named: 'ledger'),
        ),
      ).thenAnswer((_) async {
        calls.add('prices/TWSE');
        return 1;
      });
      when(
        () => price.backfillTpexPricesByDate(
          date: any(named: 'date'),
          targetSymbols: any(named: 'targetSymbols'),
          ledger: any(named: 'ledger'),
        ),
      ).thenAnswer((_) async {
        calls.add('prices/TPEx');
        return 1;
      });
      when(
        () => inst.syncAllMarketInstitutional(
          any(),
          force: any(named: 'force'),
          ledger: any(named: 'ledger'),
        ),
      ).thenAnswer((_) async {
        calls.add('institutional');
        return 1;
      });
      when(
        () => trading.syncAllDayTradingFromTwse(
          date: any(named: 'date'),
          force: any(named: 'force'),
          ledger: any(named: 'ledger'),
        ),
      ).thenAnswer((_) async {
        calls.add('dayTrading/TWSE');
        return 1;
      });
      when(
        () => trading.syncAllDayTradingFromTpex(
          date: any(named: 'date'),
          force: any(named: 'force'),
          ledger: any(named: 'ledger'),
        ),
      ).thenAnswer((_) async {
        calls.add('dayTrading/TPEx');
        return 1;
      });
      when(
        () => trading.backfillMarginTradingByDate(
          date: any(named: 'date'),
          markets: any(named: 'markets'),
          ledger: any(named: 'ledger'),
        ),
      ).thenAnswer((_) async {
        calls.add('margin');
        return (twseRows: 1, tpexRows: 1);
      });
      when(
        () => sh.syncAllMarketShareholding(
          date: any(named: 'date'),
          force: any(named: 'force'),
          ledger: any(named: 'ledger'),
        ),
      ).thenAnswer((_) async {
        calls.add('foreignShareholding');
        return 1;
      });
      refetcher = MarketDayRefetcher(
        database: db,
        priceRepository: price,
        institutionalRepository: inst,
        tradingRepository: trading,
        shareholdingRepository: sh,
        callDelay: Duration.zero,
      );
      ledger = MarketDayFetchLedger(database: db, fetchedAt: today);
    });

    tearDown(() => db.close());

    test('順序：價格 → 法人 → 當沖 → 融資券 → 外資持股（完整序列）', () async {
      await refetcher.refetchPending(today: today, ledger: ledger);
      // 候選日只有 9/24 一天，故每組恰一次呼叫：完整序列可以逐項比對
      expect(calls, [
        'prices/TWSE',
        'prices/TPEx',
        'institutional',
        'dayTrading/TWSE',
        'dayTrading/TPEx',
        'margin',
        'margin',
        'foreignShareholding',
      ]);

      // 🚨 I1a：只比對呼叫序列會漏掉「傳錯 ledger」「force 沒開」「日期錯位」
      // 這類參數層級的錯誤，逐一釘住每個 repository 呼叫的實際參數。
      // backfillTwse/TpexPricesByDate 介面本身沒有 force 參數（回補語意本就
      // 隱含強制），故這兩個呼叫只釘 date/targetSymbols/ledger。
      verify(
        () => price.backfillTwsePricesByDate(
          date: d,
          targetSymbols: any(named: 'targetSymbols', that: isNotEmpty),
          ledger: any(named: 'ledger', that: same(ledger)),
        ),
      ).called(1);
      verify(
        () => price.backfillTpexPricesByDate(
          date: d,
          targetSymbols: any(named: 'targetSymbols', that: isNotEmpty),
          ledger: any(named: 'ledger', that: same(ledger)),
        ),
      ).called(1);
      verify(
        () => inst.syncAllMarketInstitutional(
          d,
          force: true,
          ledger: any(named: 'ledger', that: same(ledger)),
        ),
      ).called(1);
      verify(
        () => trading.syncAllDayTradingFromTwse(
          date: d,
          force: true,
          ledger: any(named: 'ledger', that: same(ledger)),
        ),
      ).called(1);
      verify(
        () => trading.syncAllDayTradingFromTpex(
          date: d,
          force: true,
          ledger: any(named: 'ledger', that: same(ledger)),
        ),
      ).called(1);
      verify(
        () => trading.backfillMarginTradingByDate(
          date: d,
          markets: any(named: 'markets', that: equals({MarketCode.twse})),
          ledger: any(named: 'ledger', that: same(ledger)),
        ),
      ).called(1);
      verify(
        () => trading.backfillMarginTradingByDate(
          date: d,
          markets: any(named: 'markets', that: equals({MarketCode.tpex})),
          ledger: any(named: 'ledger', that: same(ledger)),
        ),
      ).called(1);
      verify(
        () => sh.syncAllMarketShareholding(
          date: d,
          force: true,
          ledger: any(named: 'ledger', that: same(ledger)),
        ),
      ).called(1);
    });

    test('法人兩市場同一天只打一次', () async {
      await refetcher.refetchPending(today: today, ledger: ledger);
      expect(calls.where((c) => c == 'institutional'), hasLength(1));
    });

    test('已定案的組不重抓', () async {
      await db.upsertMarketDayFetch(
        dataset: MarketDataset.prices.code,
        market: MarketCode.twse,
        date: d,
        fetchedAt: DateTime(2026, 9, 25),
        rowCount: 1,
      );
      await refetcher.refetchPending(today: today, ledger: ledger);
      expect(calls, isNot(contains('prices/TWSE')));
      expect(calls, contains('prices/TPEx'));
    });

    test('追蹤起始日不存在時寫入今天，且不回頭抓舊日子', () async {
      await db.deleteSetting(MarketDayRefetcher.trackingSinceKey);
      await refetcher.refetchPending(today: today, ledger: ledger);
      expect(calls, isEmpty);
      expect(
        await db.getSetting(MarketDayRefetcher.trackingSinceKey),
        '2026-09-29',
      );
    });

    test('追蹤起始日設定值損壞時，不拋例外、重設為今天、本輪無候選日', () async {
      await db.setSetting(MarketDayRefetcher.trackingSinceKey, 'garbage');
      await refetcher.refetchPending(today: today, ledger: ledger);
      expect(calls, isEmpty);
      expect(
        await db.getSetting(MarketDayRefetcher.trackingSinceKey),
        '2026-09-29',
      );
    });

    test('限流：中止其餘重抓並回報', () async {
      when(
        () => price.backfillTwsePricesByDate(
          date: any(named: 'date'),
          targetSymbols: any(named: 'targetSymbols'),
          ledger: any(named: 'ledger'),
        ),
      ).thenThrow(const RateLimitException('429'));
      final s = await refetcher.refetchPending(today: today, ledger: ledger);
      expect(s.rateLimited, isTrue);
      expect(calls, isEmpty);
    });

    test('🚨 限流中止時 stoppedAt 記下出事的那一天（不是用次數回推）', () async {
      when(
        () => price.backfillTwsePricesByDate(
          date: any(named: 'date'),
          targetSymbols: any(named: 'targetSymbols'),
          ledger: any(named: 'ledger'),
        ),
      ).thenThrow(const RateLimitException('429'));
      // 候選日只有 9/24 一天（見「順序」測試的註解），限流就發生在這天上
      final s = await refetcher.refetchPending(today: today, ledger: ledger);
      expect(s.stoppedAt, d);
    });

    test('正常跑完（沒有中止）時 stoppedAt 為 null', () async {
      final s = await refetcher.refetchPending(today: today, ledger: ledger);
      expect(s.stoppedAt, isNull);
    });

    test('網路異常：只中止該組其餘天數，其他組照常執行', () async {
      when(
        () => price.backfillTwsePricesByDate(
          date: any(named: 'date'),
          targetSymbols: any(named: 'targetSymbols'),
          ledger: any(named: 'ledger'),
        ),
      ).thenThrow(const NetworkException('x'));
      final s = await refetcher.refetchPending(today: today, ledger: ledger);
      expect(calls, contains('prices/TPEx'));
      expect(calls, contains('foreignShareholding'));
      expect(s.errors, isNotEmpty);
      expect(s.errors.single, contains('prices/TWSE'));
      expect(s.rateLimited, isFalse);
      // 🚨 網路錯誤那條 stoppedAt 寫入路徑：候選日只有 9/24 一天，出事就
      // 在這天
      expect(s.stoppedAt, d);
    });

    test('網路異常：同一組後續天數會被跳過（其他組不受影響）', () async {
      // 拉早追蹤起始日到 9/23，讓上市價格這組有兩個候選日（9/24、9/23）
      await db.setSetting(MarketDayRefetcher.trackingSinceKey, '2026-09-23');
      when(
        () => price.backfillTwsePricesByDate(
          date: any(named: 'date'),
          targetSymbols: any(named: 'targetSymbols'),
          ledger: any(named: 'ledger'),
        ),
      ).thenThrow(const NetworkException('x'));
      await refetcher.refetchPending(today: today, ledger: ledger);
      // thenThrow 的 stub 不會跑進 calls（那是 thenAnswer 的副作用），改用
      // verify 計數呼叫次數
      verify(
        () => price.backfillTwsePricesByDate(
          date: any(named: 'date'),
          targetSymbols: any(named: 'targetSymbols'),
          ledger: any(named: 'ledger'),
        ),
      ).called(1);
      expect(
        calls.where((c) => c == 'prices/TPEx'),
        hasLength(2),
        reason: '上櫃價格這組不受上市失敗影響，兩天都照跑',
      );
    });

    test('一般錯誤：記錄並繼續下一組', () async {
      when(
        () => price.backfillTwsePricesByDate(
          date: any(named: 'date'),
          targetSymbols: any(named: 'targetSymbols'),
          ledger: any(named: 'ledger'),
        ),
      ).thenThrow(const DatabaseException('x'));
      final s = await refetcher.refetchPending(today: today, ledger: ledger);
      expect(s.errors, isNotEmpty);
      expect(calls, contains('prices/TPEx'));
    });

    test('沒有記錄到狀態的日子（例如颱風停市回 0 列），下輪仍是候選', () async {
      // 「回 0 列不寫狀態」由 ledger 的門檻負責（另有專門測試涵蓋）；這裡釘的是
      // refetcher 這一側：沒狀態的日子不會因為「這輪抓過」就被跳過
      await refetcher.refetchPending(today: today, ledger: ledger);
      calls.clear();
      await refetcher.refetchPending(today: today, ledger: ledger);
      expect(calls, contains('prices/TWSE'));
    });

    test('法人：上市已定案、上櫃未定案 → 仍打一次（取聯集，不是交集）', () async {
      await db.upsertMarketDayFetch(
        dataset: MarketDataset.institutional.code,
        market: MarketCode.twse,
        date: d,
        fetchedAt: DateTime(2026, 9, 25),
        rowCount: 1,
      );
      await refetcher.refetchPending(today: today, ledger: ledger);
      expect(calls.where((c) => c == 'institutional'), hasLength(1));
    });

    test('finalized 計數：只有實際回報定案的組才計入，未回報的組維持 0', () async {
      when(
        () => price.backfillTwsePricesByDate(
          date: any(named: 'date'),
          targetSymbols: any(named: 'targetSymbols'),
          ledger: any(named: 'ledger'),
        ),
      ).thenAnswer((inv) async {
        calls.add('prices/TWSE');
        final l = inv.namedArguments[#ledger] as MarketDayFetchLedger?;
        await l?.report(
          dataset: MarketDataset.prices,
          market: MarketCode.twse,
          date: inv.namedArguments[#date] as DateTime,
          rows: 1,
        );
        return 1;
      });
      final s = await refetcher.refetchPending(today: today, ledger: ledger);
      const twse = (dataset: MarketDataset.prices, market: MarketCode.twse);
      const tpex = (dataset: MarketDataset.prices, market: MarketCode.tpex);
      // 次日以後抓取（today = 9/29、資料日 9/24）：算定案
      expect(s.finalized[twse], 1);
      expect(s.finalized[tpex] ?? 0, 0);
      expect(s.toLogLine(), contains('prices/TWSE 1/1'));

      // 🚨 M1：同日抓取（fetchedAt 與資料日同一天）不算定案，即使 ledger 有回報
      // 這筆——finalized 計數必須額外過 isFetchFinal，不能只看「有沒有回報」
      final sameDayLedger = MarketDayFetchLedger(database: db, fetchedAt: d);
      final sameDaySummary = await refetcher.refetchRange(
        dataset: MarketDataset.prices,
        market: MarketCode.twse,
        from: d,
        to: d,
        ledger: sameDayLedger,
      );
      expect(sameDaySummary.finalized[twse] ?? 0, 0);
    });

    test('滑出回補窗仍未定案（含完全沒有狀態列）→ 只列入 staleOutOfWindow，不進 errors', () async {
      // 起始日 8/03：9/29 的 40 日曆天窗從 8/20 起，8/03–8/19 已滑出窗外
      await db.setSetting(MarketDayRefetcher.trackingSinceKey, '2026-08-03');
      final s = await refetcher.refetchPending(today: today, ledger: ledger);
      expect(s.staleOutOfWindow, isNotEmpty);
      expect(s.staleOutOfWindow.any((e) => e.contains('2026-08-19')), isTrue);
      // 8/20 是窗口起點本身、仍在窗內，不應算進滑出窗外
      expect(s.staleOutOfWindow.any((e) => e.contains('2026-08-20')), isFalse);
      expect(s.errors, isEmpty);
    });

    test('每組每輪最多 finalityRefetchMaxDaysPerRun 天，其餘記入 deferred', () async {
      // 追蹤起始日拉到 8/24：9/29 往回 40 日曆天內的交易日遠多於 10 天
      await db.setSetting(MarketDayRefetcher.trackingSinceKey, '2026-08-24');
      final s = await refetcher.refetchPending(today: today, ledger: ledger);
      expect(
        calls.where((c) => c == 'prices/TWSE'),
        hasLength(ApiConfig.finalityRefetchMaxDaysPerRun),
      );
      const g = (dataset: MarketDataset.prices, market: MarketCode.twse);
      final candidates = refetchCandidateDays(
        today: today,
        trackingSince: DateTime(2026, 8, 24),
      ).length;
      expect(
        s.deferred[g],
        candidates - ApiConfig.finalityRefetchMaxDaysPerRun,
      );
      expect(s.toLogLine(), contains('剩 ${s.deferred[g]} 天'));
    });

    test('🚨 M6：tradingRepository 未注入時跳過當沖/融資券，但不拋例外、價格照常執行', () async {
      final r = MarketDayRefetcher(
        database: db,
        priceRepository: price,
        institutionalRepository: inst,
        shareholdingRepository: sh,
        callDelay: Duration.zero,
      );
      final s = await r.refetchPending(today: today, ledger: ledger);
      expect(calls, contains('prices/TWSE'));
      expect(calls, contains('prices/TPEx'));
      expect(calls, contains('institutional'));
      expect(calls, contains('foreignShareholding'));
      expect(calls, isNot(contains('dayTrading/TWSE')));
      expect(calls, isNot(contains('margin')));
      expect(s.errors, isEmpty);
    });

    test('refetchRange：範圍內交易日不論狀態一律重抓', () async {
      await db.upsertMarketDayFetch(
        dataset: MarketDataset.prices.code,
        market: MarketCode.twse,
        date: d,
        fetchedAt: DateTime(2026, 9, 25),
        rowCount: 1,
      );
      await refetcher.refetchRange(
        dataset: MarketDataset.prices,
        market: MarketCode.twse,
        from: DateTime(2026, 9, 23),
        to: d,
        ledger: ledger,
      );
      expect(calls.where((c) => c == 'prices/TWSE'), hasLength(2));
    });
  });
}
