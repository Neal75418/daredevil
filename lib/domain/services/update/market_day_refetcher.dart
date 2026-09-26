import 'package:daredevil/core/constants/api_config.dart';
import 'package:daredevil/core/constants/market_codes.dart';
import 'package:daredevil/core/constants/market_dataset.dart';
import 'package:daredevil/core/exceptions/app_exception.dart';
import 'package:daredevil/core/utils/date_context.dart';
import 'package:daredevil/core/utils/logger.dart';
import 'package:daredevil/core/utils/market_day_finality.dart';
import 'package:daredevil/core/utils/taiwan_calendar.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/data/repositories/market_day_fetch_ledger.dart';
import 'package:daredevil/data/repositories/shareholding_repository.dart';
import 'package:daredevil/domain/repositories/institutional_repository.dart';
import 'package:daredevil/domain/repositories/price_repository.dart';
import 'package:daredevil/domain/repositories/trading_repository.dart';

/// 回補窗起點：[today] 往回 [ApiConfig.tradingBackfillLookbackDays] 個日曆天
/// （不含時分秒；[today] 不必先正規化）。
DateTime refetchWindowStart(DateTime today) {
  final todayDay = DateTime(today.year, today.month, today.day);
  return DateTime(
    todayDay.year,
    todayDay.month,
    todayDay.day - ApiConfig.tradingBackfillLookbackDays,
  );
}

/// 重抓候選日：早於台北今天、不早於追蹤起始日、在回補窗（日曆天）內的
/// 交易日，新→舊。當天的資料交給每日路徑，避免同一輪用歷史端點再抓一次。
List<DateTime> refetchCandidateDays({
  required DateTime today,
  required DateTime trackingSince,
}) {
  final todayDay = DateTime(today.year, today.month, today.day);
  final windowStart = refetchWindowStart(todayDay);
  final since = DateTime(
    trackingSince.year,
    trackingSince.month,
    trackingSince.day,
  );
  final from = since.isAfter(windowStart) ? since : windowStart;
  return [
    for (
      var d = DateTime(todayDay.year, todayDay.month, todayDay.day - 1);
      !d.isBefore(from);
      d = DateTime(d.year, d.month, d.day - 1)
    )
      if (TaiwanCalendar.isTradingDay(d)) d,
  ];
}

String _key(String dataset, String market, DateTime day) =>
    '$dataset|$market|${DateContext.formatYmd(day)}';

/// 每組（資料集, 市場）要重抓的日子：候選日中沒有定案狀態列者（含完全
/// 沒有狀態列），每組最多 [maxPerGroup] 天，取最新的。
Map<FinalityGroup, List<DateTime>> selectRefetchDays({
  required List<DateTime> candidateDays,
  required List<MarketDayFetchEntry> fetches,
  required int maxPerGroup,
}) {
  final fetchedAt = {
    for (final f in fetches) _key(f.dataset, f.market, f.date): f.fetchedAt,
  };
  return {
    for (final g in finalityGroups)
      g: [
        for (final day in candidateDays)
          if (!_isFinal(fetchedAt[_key(g.dataset.code, g.market, day)], day))
            day,
      ].take(maxPerGroup).toList(),
  };
}

bool _isFinal(DateTime? fetchedAt, DateTime day) =>
    fetchedAt != null &&
    isFetchFinal(dataDate: day, fetchedAtTaipei: fetchedAt);

/// 一次重抓的結果（進更新日誌與 UpdateResult）
class RefetchSummary {
  final Map<FinalityGroup, int> attempted = {};
  final Map<FinalityGroup, int> finalized = {};

  /// 超過每輪上限、留給下一輪的天數
  final Map<FinalityGroup, int> deferred = {};
  final List<String> errors = [];

  /// 追蹤起始日以後、已超出回補窗仍未定案的（資料集/市場 日期）
  final List<String> staleOutOfWindow = [];
  Object? rateLimitError;

  bool get rateLimited => rateLimitError != null;

  String toLogLine() {
    final parts = [
      for (final g in finalityGroups)
        if ((attempted[g] ?? 0) > 0 || (deferred[g] ?? 0) > 0)
          '${g.dataset.code}/${g.market} ${finalized[g] ?? 0}/${attempted[g] ?? 0}${(deferred[g] ?? 0) > 0 ? '（剩 ${deferred[g]} 天）' : ''}',
    ];
    return '未定案重抓: ${parts.isEmpty ? '無' : parts.join(', ')}'
        '${errors.isEmpty ? '' : '；失敗 ${errors.length}'}'
        '${rateLimited ? '；限流中止' : ''}';
  }
}

/// 重抓未定案的日子（spec §4.5(b)）
///
/// 每輪更新在當日路徑與既有回補之後執行；修復工具以 [refetchRange] 重用
/// 同一套抓取邏輯。每個抓取都傳 [MarketDayFetchLedger]，由 repository 在
/// 寫入時回報，這裡只負責挑日子與依序呼叫。
class MarketDayRefetcher {
  MarketDayRefetcher({
    required AppDatabase database,
    required IPriceRepository priceRepository,
    IInstitutionalRepository? institutionalRepository,
    ITradingRepository? tradingRepository,
    ShareholdingRepository? shareholdingRepository,
    this.callDelay = const Duration(
      milliseconds: ApiConfig.finalityRefetchCallDelayMs,
    ),
  }) : _db = database,
       _priceRepo = priceRepository,
       _institutionalRepo = institutionalRepository,
       _tradingRepo = tradingRepository,
       _shareholdingRepo = shareholdingRepository;

  /// app_settings key：第一次執行更新的台北日期，之後不再變動
  static const String trackingSinceKey = 'finality_tracking_since';

  final AppDatabase _db;
  final IPriceRepository _priceRepo;
  final IInstitutionalRepository? _institutionalRepo;
  final ITradingRepository? _tradingRepo;
  final ShareholdingRepository? _shareholdingRepo;
  final Duration callDelay;

  Future<RefetchSummary> refetchPending({
    required DateTime today,
    required MarketDayFetchLedger ledger,
  }) async {
    final todayDay = DateContext.normalize(today);
    final sinceRaw = await _db.getOrInitSetting(
      trackingSinceKey,
      DateContext.formatYmd(todayDay),
    );
    var since = DateTime.tryParse(sinceRaw);
    if (since == null) {
      // 設定值損壞（非預期手動編輯／舊版格式）：解析失敗不能讓每一輪都
      // 拋例外失敗，修復成今天（原值已不可用，不算違反「已存在不覆寫」）、
      // 本輪視為沒有候選日，下一輪起照常追蹤。
      AppLogger.warning(
        'MarketDayRefetcher',
        'finality_tracking_since 格式錯誤（$sinceRaw），重設為今天',
      );
      since = todayDay;
      await _db.setSetting(trackingSinceKey, DateContext.formatYmd(todayDay));
    }
    final candidates = refetchCandidateDays(
      today: todayDay,
      trackingSince: since,
    );
    final summary = RefetchSummary();
    final fetches = await _db.getMarketDayFetchesSince(since);

    // 追蹤起始日以後、已滑出回補窗仍未定案（含完全沒有狀態列）的日子：
    // 這些資料會一直停在初值，必須看得見。只記 warning、不進 errors——
    // 它們不會自己消失，進 errors 會讓之後每一輪 launchd 都 exit 1。
    final windowStart = refetchWindowStart(todayDay);
    final outOfWindow = <DateTime>[
      for (
        var d = DateTime(
          windowStart.year,
          windowStart.month,
          windowStart.day - 1,
        );
        !d.isBefore(since);
        d = DateTime(d.year, d.month, d.day - 1)
      )
        if (TaiwanCalendar.isTradingDay(d)) d,
    ];
    const noCap = 1 << 30;
    for (final e in selectRefetchDays(
      candidateDays: outOfWindow,
      fetches: fetches,
      maxPerGroup: noCap,
    ).entries) {
      for (final d in e.value) {
        summary.staleOutOfWindow.add(
          '${e.key.dataset.code}/${e.key.market} ${DateContext.formatYmd(d)}',
        );
      }
    }
    if (summary.staleOutOfWindow.isNotEmpty) {
      // 這些日子會一直留著，只印筆數與前 10 筆，避免日誌行無限變長
      final list = summary.staleOutOfWindow;
      AppLogger.warning(
        'MarketDayRefetcher',
        '超出回補窗仍未定案 ${list.length} 筆（會停在初值，需用 '
            'tool/refetch_market_days.dart 修）: ${list.take(10).join(', ')}'
            '${list.length > 10 ? ' …' : ''}',
      );
    }

    final plan = selectRefetchDays(
      candidateDays: candidates,
      fetches: fetches,
      maxPerGroup: ApiConfig.finalityRefetchMaxDaysPerRun,
    );
    // 超過每輪上限、留給下一輪的天數（進摘要）
    final all = selectRefetchDays(
      candidateDays: candidates,
      fetches: fetches,
      maxPerGroup: noCap,
    );
    for (final g in finalityGroups) {
      summary.deferred[g] = (all[g]?.length ?? 0) - (plan[g]?.length ?? 0);
    }
    await _execute(plan, ledger, summary);
    return summary;
  }

  /// 修復工具用：[from]～[to] 的交易日不論狀態一律重抓，不受每輪上限、
  /// 回補窗與追蹤起始日限制。法人一次請求涵蓋兩市場，[market] 被忽略。
  Future<RefetchSummary> refetchRange({
    required MarketDataset dataset,
    required String market,
    required DateTime from,
    required DateTime to,
    required MarketDayFetchLedger ledger,
  }) async {
    final days = <DateTime>[
      for (
        var d = DateContext.normalize(to);
        !d.isBefore(DateContext.normalize(from));
        d = DateTime(d.year, d.month, d.day - 1)
      )
        if (TaiwanCalendar.isTradingDay(d)) d,
    ];
    final plan = <FinalityGroup, List<DateTime>>{
      if (dataset == MarketDataset.institutional) ...{
        (dataset: dataset, market: MarketCode.twse): days,
        (dataset: dataset, market: MarketCode.tpex): days,
      } else
        (dataset: dataset, market: market): days,
    };
    final summary = RefetchSummary();
    await _execute(plan, ledger, summary);
    return summary;
  }

  Future<void> _execute(
    Map<FinalityGroup, List<DateTime>> plan,
    MarketDayFetchLedger ledger,
    RefetchSummary summary,
  ) async {
    var calls = 0;
    Future<_AttemptOutcome> attempt(
      List<FinalityGroup> groups,
      DateTime day,
      Future<void> Function() fetch,
    ) async {
      if (calls > 0) await Future<void>.delayed(callDelay);
      calls++;
      for (final g in groups) {
        summary.attempted[g] = (summary.attempted[g] ?? 0) + 1;
      }
      try {
        await fetch();
      } on RateLimitException catch (e) {
        summary.rateLimitError = e;
        return _AttemptOutcome.rateLimitAbort;
      } on NetworkException catch (e) {
        // 網路異常：單一（資料集, 市場, 日）失敗不代表整輪都會失敗（可能是
        // 該日 4xx／逾時，executeRequest 不會重試）。只停這個 attempt 涵蓋
        // 的組別（groups）之後的天數，其餘組別照常執行；下一輪自然再試
        // （spec §6）
        summary.errors.add(
          '${groups.map((g) => '${g.dataset.code}/${g.market}').join('+')} '
          '${DateContext.formatYmd(day)}: $e',
        );
        return _AttemptOutcome.networkStop;
      } on Exception catch (e) {
        summary.errors.add(
          '${groups.map((g) => '${g.dataset.code}/${g.market}').join('+')} '
          '${DateContext.formatYmd(day)}: $e',
        );
      }
      for (final g in groups) {
        final done = ledger.recorded.any(
          (r) =>
              r.dataset == g.dataset &&
              r.market == g.market &&
              DateContext.isSameDay(r.date, day),
        );
        if (done) summary.finalized[g] = (summary.finalized[g] ?? 0) + 1;
      }
      return _AttemptOutcome.ok;
    }

    List<DateTime> daysOf(MarketDataset ds, String market) =>
        plan[(dataset: ds, market: market)] ?? const [];

    // 1. 價格（當沖比例的分母，必須先於當沖）
    for (final market in [MarketCode.twse, MarketCode.tpex]) {
      final days = daysOf(MarketDataset.prices, market);
      if (days.isEmpty) continue;
      final symbols = {
        for (final s in await _db.getStocksByMarket(market)) s.symbol,
      };
      for (final day in days) {
        final outcome = await attempt(
          [(dataset: MarketDataset.prices, market: market)],
          day,
          () => market == MarketCode.twse
              ? _priceRepo.backfillTwsePricesByDate(
                  date: day,
                  targetSymbols: symbols,
                  ledger: ledger,
                )
              : _priceRepo.backfillTpexPricesByDate(
                  date: day,
                  targetSymbols: symbols,
                  ledger: ledger,
                ),
        );
        if (outcome == _AttemptOutcome.rateLimitAbort) return;
        if (outcome == _AttemptOutcome.networkStop) break;
      }
    }

    // 2. 法人：一次請求兩市場，任一市場未定案就一起抓
    final inst = _institutionalRepo;
    if (inst != null) {
      final twseDays = daysOf(MarketDataset.institutional, MarketCode.twse);
      final tpexDays = daysOf(MarketDataset.institutional, MarketCode.tpex);
      final union = {...twseDays, ...tpexDays}.toList()
        ..sort((a, b) => b.compareTo(a));
      for (final day in union) {
        final groups = [
          if (twseDays.contains(day))
            (dataset: MarketDataset.institutional, market: MarketCode.twse),
          if (tpexDays.contains(day))
            (dataset: MarketDataset.institutional, market: MarketCode.tpex),
        ];
        final outcome = await attempt(
          groups,
          day,
          () =>
              inst.syncAllMarketInstitutional(day, force: true, ledger: ledger),
        );
        if (outcome == _AttemptOutcome.rateLimitAbort) return;
        if (outcome == _AttemptOutcome.networkStop) break;
      }
    }

    // 3. 當沖、4. 融資券
    final trading = _tradingRepo;
    if (trading != null) {
      for (final market in [MarketCode.twse, MarketCode.tpex]) {
        for (final day in daysOf(MarketDataset.dayTrading, market)) {
          final outcome = await attempt(
            [(dataset: MarketDataset.dayTrading, market: market)],
            day,
            () => market == MarketCode.twse
                ? trading.syncAllDayTradingFromTwse(
                    date: day,
                    force: true,
                    ledger: ledger,
                  )
                : trading.syncAllDayTradingFromTpex(
                    date: day,
                    force: true,
                    ledger: ledger,
                  ),
          );
          if (outcome == _AttemptOutcome.rateLimitAbort) return;
          if (outcome == _AttemptOutcome.networkStop) break;
        }
      }
      for (final market in [MarketCode.twse, MarketCode.tpex]) {
        for (final day in daysOf(MarketDataset.margin, market)) {
          final outcome = await attempt(
            [(dataset: MarketDataset.margin, market: market)],
            day,
            () => trading.backfillMarginTradingByDate(
              date: day,
              markets: {market},
              ledger: ledger,
            ),
          );
          if (outcome == _AttemptOutcome.rateLimitAbort) return;
          if (outcome == _AttemptOutcome.networkStop) break;
        }
      }
    }

    // 5. 外資持股（僅上市）
    final sh = _shareholdingRepo;
    if (sh != null) {
      for (final day in daysOf(
        MarketDataset.foreignShareholding,
        MarketCode.twse,
      )) {
        final outcome = await attempt(
          [
            (
              dataset: MarketDataset.foreignShareholding,
              market: MarketCode.twse,
            ),
          ],
          day,
          () => sh.syncAllMarketShareholding(
            date: day,
            force: true,
            ledger: ledger,
          ),
        );
        if (outcome == _AttemptOutcome.rateLimitAbort) return;
        if (outcome == _AttemptOutcome.networkStop) break;
      }
    }
  }
}

/// [MarketDayRefetcher._execute] 內單次抓取的結果：`ok` 繼續下一天、
/// `networkStop` 只停該 attempt 涵蓋的組別（其他組別照常執行）、
/// `rateLimitAbort` 中止整輪剩餘重抓
enum _AttemptOutcome { ok, networkStop, rateLimitAbort }
