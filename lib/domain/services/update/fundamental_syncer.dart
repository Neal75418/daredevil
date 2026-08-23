import 'package:meta/meta.dart' show visibleForTesting;

import 'package:daredevil/core/constants/api_config.dart';
import 'package:daredevil/core/constants/market_codes.dart';
import 'package:daredevil/core/constants/stock_patterns.dart';
import 'package:daredevil/core/exceptions/app_exception.dart';
import 'package:daredevil/core/utils/clock.dart';
import 'package:daredevil/core/utils/logger.dart';
import 'package:daredevil/core/utils/safe_execution.dart';
import 'package:daredevil/core/utils/taiwan_calendar.dart';
import 'package:daredevil/data/models/finmind/revenue.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/data/repositories/fundamental_repository.dart';
import 'package:daredevil/data/repositories/market_data_repository.dart';

/// 選出本輪要同步財報的上櫃候選 —— **最舊優先**。
///
/// 兩個規則：
/// 1. ETF（代碼 00 開頭）在取前 N 之**前**排除
/// 2. 其餘依最新財報日由舊到新排序，**無資料者視為最舊**；同日期以代號排序
///    保證決定性
///
/// ## 為什麼不能沿用 take(N)
///
/// 上市那條路徑（[UpdateService.selectFinancialSyncTargets]）依候選順序取前 N，
/// 搬到上櫃會立刻復發兩個已修過的同型病：
///
/// - **ETF 佔位**：上櫃今日有價格的 904 檔中 15 檔是 ETF 且全部 0 筆財報
///   （2026-07-27 正式 DB 實查）。ETF 永遠不會變新鮮，排序鍵恆為「最舊」，
///   不先排除就是每輪固定霸佔 15 個名額、且永遠排在最前面。
/// - **前綴永不輪替**：價格走快取路徑時候選順序退化為代號升冪，take 前 N
///   每天都是同一批；補完後他們變新鮮、同步 0 筆，後面的 790 檔永遠輪不到。
///
/// 最舊優先讓補完者自然沉到隊尾，890 檔待回填約 10 個交易日收斂。
///
/// 已知殘留：FinMind 對少數股票恆回 0 筆（2026-07-27 實測上市 33 檔中 7835、
/// 9136 兩檔如此），這類永遠停在「無資料」→ 永久排在隊首佔名額。實測比例約
/// 6%，回填完成後預估固定佔用 ~50 個名額。因無「已嘗試」時戳可依據，此處
/// 不另處理，改由同步日誌印出「目標 N 檔／實際寫入 M 檔」讓停滯可被觀察。
@visibleForTesting
List<String> selectOtcFinancialTargets({
  required List<String> candidates,
  required Map<String, DateTime?> latestDates,
  required int limit,
}) {
  // 無資料者用 epoch 當排序鍵 → 自然排在最前
  final epoch = DateTime.fromMillisecondsSinceEpoch(0);
  final ordered = candidates.where((s) => !StockPatterns.isEtfCode(s)).toList()
    ..sort((a, b) {
      final cmp = (latestDates[a] ?? epoch).compareTo(latestDates[b] ?? epoch);
      return cmp != 0 ? cmp : a.compareTo(b);
    });
  return ordered.length > limit ? ordered.sublist(0, limit) : ordered;
}

/// 基本面資料同步器
///
/// 負責同步營收、PE、PBR、殖利率等基本面資料
class FundamentalSyncer {
  const FundamentalSyncer({
    required AppDatabase database,
    required FundamentalRepository fundamentalRepository,
    MarketDataRepository? marketDataRepository,
    AppClock clock = const SystemClock(),
  }) : _db = database,
       _fundamentalRepo = fundamentalRepository,
       _marketDataRepo = marketDataRepository,
       _clock = clock;

  final AppDatabase _db;
  final FundamentalRepository _fundamentalRepo;
  final MarketDataRepository? _marketDataRepo;
  final AppClock _clock;

  /// 同步全市場基本面資料（TWSE 批次 API）
  ///
  /// 包含估值（PE、PBR、殖利率）和營收資料
  Future<FundamentalSyncResult> syncMarketWideFundamentals({
    required DateTime date,
    bool force = false,
  }) async {
    var valuationCount = 0;
    int? revenueCount = 0;
    final errors = <String>[];

    valuationCount = await guardSync(
      tag: 'FundamentalSyncer',
      label: '估值資料同步',
      fallback: valuationCount,
      errors: errors,
      errorLabel: '全市場估值',
      action: () => _fundamentalRepo.syncAllMarketValuation(date, force: force),
    );

    // force 需轉給營收：否則強制同步時營收會因 skip-if-cached 而不重抓。
    // （guardSync<int?>：null 是合法回傳、代表營收已快取跳過同步）
    revenueCount = await guardSync<int?>(
      tag: 'FundamentalSyncer',
      label: '營收資料同步',
      fallback: revenueCount,
      errors: errors,
      errorLabel: '全市場營收',
      action: () => _fundamentalRepo.syncAllMarketRevenue(date, force: force),
    );

    // 公布期漸進營收(MOPS,每月 1~14 日):openapi 月批切換前逐日吃
    // 已申報公司,營收訊號公布當晚即觸發。窗口外/來源掛掉回 null,
    // fail-soft 不中斷管線。
    final mopsCount = await guardSync<int?>(
      tag: 'FundamentalSyncer',
      label: 'MOPS 公布期營收同步',
      fallback: null,
      errors: errors,
      errorLabel: 'MOPS 公布期營收',
      action: () => _fundamentalRepo.syncInProgressRevenue(date),
    );

    final revenueLabel = revenueCount == null ? '已快取' : '$revenueCount';
    final mopsLabel = mopsCount == null ? '—' : '+$mopsCount(公布期)';
    AppLogger.info(
      'FundamentalSyncer',
      '全市場基本面: 估值=$valuationCount, 營收=$revenueLabel, MOPS=$mopsLabel',
    );

    return FundamentalSyncResult(
      valuationCount: valuationCount,
      revenueCount: revenueCount,
      errors: errors,
    );
  }

  /// 補充上櫃自選股的基本面資料
  ///
  /// TWSE 批次 API 僅涵蓋上市股票，上櫃自選股需逐檔補充
  Future<FundamentalSyncResult> syncOtcWatchlistFundamentals({
    required DateTime date,
    bool force = false,
  }) async {
    final watchlist = await _db.getWatchlist();
    final otcStocks = await _db.getStocksByMarket(MarketCode.tpex);
    final otcSymbolSet = otcStocks.map((s) => s.symbol).toSet();

    final otcWatchlistSymbols = watchlist
        .map((w) => w.symbol)
        .where((symbol) => otcSymbolSet.contains(symbol))
        .toList();

    if (otcWatchlistSymbols.isEmpty) {
      return const FundamentalSyncResult(valuationCount: 0, revenueCount: 0);
    }

    var valuationCount = 0;
    var revenueCount = 0;
    final errors = <String>[];

    valuationCount = await guardSync(
      tag: 'FundamentalSyncer',
      label: '上櫃自選估值同步',
      fallback: valuationCount,
      errors: errors,
      errorLabel: '上櫃自選估值',
      action: () => _fundamentalRepo.syncOtcValuation(
        otcWatchlistSymbols,
        date: date,
        force: force,
      ),
    );

    revenueCount = await guardSync(
      tag: 'FundamentalSyncer',
      label: '上櫃自選營收同步',
      fallback: revenueCount,
      errors: errors,
      errorLabel: '上櫃自選營收',
      action: () =>
          _fundamentalRepo.syncOtcRevenue(otcWatchlistSymbols, force: force),
    );

    AppLogger.info(
      'FundamentalSyncer',
      '上櫃自選 ${otcWatchlistSymbols.length} 檔: 估值=$valuationCount, 營收=$revenueCount',
    );

    return FundamentalSyncResult(
      valuationCount: valuationCount,
      revenueCount: revenueCount,
      errors: errors,
    );
  }

  /// 挑出本輪要回填財報的上櫃候選（最舊優先、已排除 ETF）
  ///
  /// 上市那條路徑（[UpdateService.selectFinancialSyncTargets]）取
  /// `[...twse, ...tpex]` 的前 [ApiConfig.financialSyncMaxCandidates] 名，
  /// 上市候選恆遠超過上限 → 上櫃永遠分不到名額。本方法給上櫃一條獨立佇列，
  /// 上市那條不受影響。挑選規則見 [selectOtcFinancialTargets]。
  ///
  /// 失敗時 **fail-closed 回空清單**：拿不到最新財報日就無從排序，若退回
  /// 全清單會讓整包上櫃候選逐檔打 FinMind。這條路徑的價值是慢速回填，
  /// 少跑一輪無害，配額爆掉才會傷到當日主要資料。
  Future<List<String>> selectOtcFinancialBacklog({
    required List<String> candidates,
    int limit = ApiConfig.otcFinancialSyncMaxCount,
  }) async {
    if (candidates.isEmpty || limit <= 0) return const [];
    try {
      final otcStocks = await _db.getStocksByMarket(MarketCode.tpex);
      final otcSymbols = otcStocks.map((s) => s.symbol).toSet();
      final otcCandidates = candidates.where(otcSymbols.contains).toList();
      if (otcCandidates.isEmpty) return const [];

      final latestDates = await _db.getLatestFinancialDataDatesBatch(
        otcCandidates,
        'INCOME',
      );
      return selectOtcFinancialTargets(
        candidates: otcCandidates,
        latestDates: latestDates,
        limit: limit,
      );
    } catch (e) {
      AppLogger.warning('FundamentalSyncer', '上櫃財報候選挑選失敗，本輪略過回填', e);
      return const [];
    }
  }

  /// 補充上櫃候選股票的基本面資料
  ///
  /// 用於分析前補充候選清單中上櫃股票的基本面。
  ///
  /// **不設候選上限**(2026-07-29):估值/營收各走 TPEx OpenAPI 全市場
  /// 批次端點(1 次呼叫,與檔數無關),舊 take(100) cap 省不到配額,
  /// 卻讓 repo 只 persist 前綴 100 檔(fetch 889 筆→寫 56 檔的生產實測),
  /// cap 外候選的價值面規則永遠 fire 不了。新鮮度過濾由 repo 內部負責。
  Future<FundamentalSyncResult> syncOtcCandidatesFundamentals({
    required List<String> candidates,
    required DateTime date,
  }) async {
    if (candidates.isEmpty) {
      return const FundamentalSyncResult(valuationCount: 0, revenueCount: 0);
    }

    // 取得上櫃股票清單
    final otcStocks = await _db.getStocksByMarket(MarketCode.tpex);
    final otcSymbols = otcStocks.map((s) => s.symbol).toSet();

    // 篩選出候選清單中的上櫃股票
    final otcCandidates = candidates
        .where((symbol) => otcSymbols.contains(symbol))
        .toList();

    if (otcCandidates.isEmpty) {
      return const FundamentalSyncResult(valuationCount: 0, revenueCount: 0);
    }

    var valuationCount = 0;
    var revenueCount = 0;
    final errors = <String>[];

    valuationCount = await guardSync(
      tag: 'FundamentalSyncer',
      label: '上櫃候選估值同步',
      fallback: valuationCount,
      errors: errors,
      errorLabel: '上櫃候選估值',
      action: () =>
          _fundamentalRepo.syncOtcValuation(otcCandidates, date: date),
    );

    revenueCount = await guardSync(
      tag: 'FundamentalSyncer',
      label: '上櫃候選營收同步',
      fallback: revenueCount,
      errors: errors,
      errorLabel: '上櫃候選營收',
      action: () => _fundamentalRepo.syncOtcRevenue(otcCandidates),
    );

    return FundamentalSyncResult(
      valuationCount: valuationCount,
      revenueCount: revenueCount,
      errors: errors,
    );
  }

  /// 回補自選股的月營收歷史（「近 3 月均年增」所需）
  ///
  /// 全市場批次同步只涵蓋最新一個月，歷史月份僅在使用者開過詳情頁的股票
  /// 才有——多數自選股算不出「近 3 月均年增」。本方法對缺近 3 個應公布月
  /// 完整 YoY 的自選股，走 FinMind 逐檔回補 ~16 個月（涵蓋近 3 月的前一年
  /// 同月，讓 [FinMindRevenue.calculateGrowthRates] 算得出 YoY）。
  ///
  /// 冪等：近 3 個應公布月（[TaiwanCalendar.expectedLatestRevenueMonth]）
  /// 皆有非空 YoY 即跳過。ETF 無營收，過濾。單檔 generic 失敗記 warning
  /// 續跑；RateLimitException rethrow 交由 coordinator 中止。
  Future<int> syncWatchlistRevenueHistory() async {
    final watchlist = await _db.getWatchlist();
    final symbols = watchlist
        .map((w) => w.symbol)
        .where((s) => !StockPatterns.isEtfCode(s))
        .toList();
    if (symbols.isEmpty) return 0;

    final needySymbols = await _filterNeedingRevenueHistory(symbols);
    if (needySymbols.isEmpty) {
      AppLogger.debug(
        'FundamentalSyncer',
        '營收歷史: ${symbols.length} 檔近3月皆完整，無需回補',
      );
      return 0;
    }

    final now = _clock.now();
    // 近 3 月最舊為 expected-2；其前一年同月再留 1 個月緩衝 → 回推 16 個月
    final start = DateTime(now.year, now.month - 16, 1);
    var count = 0;

    const chunkSize = ApiConfig.syncerBatchSize;
    for (var i = 0; i < needySymbols.length; i += chunkSize) {
      final chunk = needySymbols.skip(i).take(chunkSize).toList();
      final results = await Future.wait(
        chunk.map((s) async {
          try {
            return await _fundamentalRepo.syncMonthlyRevenue(
              symbol: s,
              startDate: start,
              endDate: now,
            );
          } on RateLimitException {
            rethrow;
          } on NetworkException {
            rethrow;
          } catch (e) {
            AppLogger.warning('FundamentalSyncer', '$s: 營收歷史回補失敗', e);
            return 0;
          }
        }),
      );
      count += results.fold(0, (sum, n) => sum + n);

      if (i + chunkSize < needySymbols.length) {
        await Future.delayed(
          const Duration(milliseconds: ApiConfig.syncerBatchDelayMs),
        );
      }
    }

    if (count > 0) {
      AppLogger.info(
        'FundamentalSyncer',
        '營收歷史回補: $count 筆 (${needySymbols.length} 檔)',
      );
    }
    return count;
  }

  /// 冪等預篩：回傳「近 3 個應公布月」缺月或缺 YoY 的 symbols
  ///
  /// 一次批次查詢（與財報預篩同款設計）。查詢失敗 fail-open 回全清單。
  Future<List<String>> _filterNeedingRevenueHistory(
    List<String> symbols,
  ) async {
    try {
      final recent = await _db.getRecentMonthlyRevenueBatch(symbols, months: 3);
      final latest = TaiwanCalendar.expectedLatestRevenueMonth(_clock.now());
      // DateTime 建構子會自動正規化跨年（month 0 → 前一年 12 月）
      final expectedKeys = <int>{};
      for (var back = 0; back < 3; back++) {
        final m = DateTime(latest.year, latest.month - back, 1);
        expectedKeys.add(m.year * 100 + m.month);
      }
      return symbols.where((s) {
        final rows = recent[s] ?? const [];
        final completeKeys = {
          for (final r in rows)
            if (r.yoyGrowth != null) r.revenueYear * 100 + r.revenueMonth,
        };
        return !completeKeys.containsAll(expectedKeys);
      }).toList();
    } catch (e) {
      AppLogger.warning('FundamentalSyncer', '營收歷史預篩失敗，退回全清單', e);
      return symbols;
    }
  }

  /// 同步指定股票清單的損益表資料（含 EPS）
  ///
  /// 每批 10 檔並行，批間延遲 500ms 避免超過 FinMind 配額。
  /// 每檔股票內部有發布行事曆感知的新鮮度檢查（已有應發布的最新一季即跳過）。
  /// ETF（代碼以 00 開頭）無財報資料，自動過濾以避免無效 API 呼叫。
  Future<int> syncFinancialStatements({required List<String> symbols}) async {
    // 過濾 ETF：00 開頭的代碼（0050、00636、006205 等）沒有財報資料
    final stockSymbols = symbols
        .where((s) => !StockPatterns.isEtfCode(s))
        .toList();
    if (stockSymbols.isEmpty) return 0;

    if (stockSymbols.length < symbols.length) {
      AppLogger.debug(
        'FundamentalSyncer',
        '財報同步: 跳過 ${symbols.length - stockSymbols.length} 檔 ETF，'
            '實際同步 ${stockSymbols.length} 檔',
      );
    }

    final needySymbols = await _filterNeedingStatementSync(
      stockSymbols,
      'INCOME',
    );
    if (needySymbols.isEmpty) {
      AppLogger.debug(
        'FundamentalSyncer',
        '財報: ${stockSymbols.length} 檔皆已快取，無需同步',
      );
      return 0;
    }

    final now = _clock.now();
    final start = now.subtract(
      const Duration(days: ApiConfig.financialSyncLookbackDays),
    );
    final end = now;
    var count = 0;

    const chunkSize = ApiConfig.syncerBatchSize;
    for (var i = 0; i < needySymbols.length; i += chunkSize) {
      final chunk = needySymbols.skip(i).take(chunkSize).toList();
      final results = await Future.wait(
        chunk.map(
          (s) => _fundamentalRepo.syncFinancialStatements(
            symbol: s,
            startDate: start,
            endDate: end,
          ),
        ),
      );
      count += results.fold(0, (sum, n) => sum + n);

      if (i + chunkSize < needySymbols.length) {
        await Future.delayed(
          const Duration(milliseconds: ApiConfig.syncerBatchDelayMs),
        );
      }
    }

    if (count > 0) {
      AppLogger.info(
        'FundamentalSyncer',
        '財報同步: $count 筆 (${needySymbols.length} 檔)',
      );
    }
    return count;
  }

  /// 批次 freshness 預篩：回傳缺「應發布的最新一季」的 symbols
  ///
  /// 一次 GROUP BY 查詢取代 chunk 內逐檔 MAX(date)（2026-07-15 儀表實測
  /// 財報段 7.1s 全是逐檔查詢 + chunk 間睡眠，實際 0 筆要抓——與法人
  /// 節流同款病）。穩態 needy 為空 → 零逐檔查詢、零睡眠。repo 內逐檔
  /// 檢查保留作雙重保險。查詢失敗 fail-open 回全清單（退回舊行為，
  /// 寧多查不漏抓）。
  Future<List<String>> _filterNeedingStatementSync(
    List<String> symbols,
    String statementType,
  ) async {
    try {
      final latestDates = await _db.getLatestFinancialDataDatesBatch(
        symbols,
        statementType,
      );
      final expectedQuarter = TaiwanCalendar.expectedLatestReportQuarter(
        _clock.now(),
      );
      return symbols.where((s) {
        final latest = latestDates[s];
        return latest == null || latest.isBefore(expectedQuarter);
      }).toList();
    } catch (e) {
      AppLogger.warning(
        'FundamentalSyncer',
        '財報 freshness 預篩失敗，退回逐檔檢查 ($statementType)',
        e,
      );
      return symbols;
    }
  }

  /// 同步指定股票清單的資產負債表資料
  ///
  /// 每批 10 檔並行，批間延遲 500ms 避免超過 FinMind 配額。
  /// 需要 MarketDataRepository 才能使用。
  /// ETF（代碼以 00 開頭）無財報資料，自動過濾以避免無效 API 呼叫。
  /// 全市場資產負債表(免費官方端點,2026-08-16)
  ///
  /// **必須在 [syncBalanceSheets] 之前呼叫**:寫入最新一季之後,後者的
  /// per-statementType 新鮮度檢查會提早 return、不打 FinMind——財報是
  /// 額度的唯一瓶頸(129 檔 × 2 = 258 次/輪),這一步直接砍掉其中一半。
  Future<int> syncMarketWideBalanceSheets() async {
    final repo = _marketDataRepo;
    if (repo == null) return 0;
    return repo.syncMarketWideBalanceSheets();
  }

  Future<int?> syncBalanceSheets({required List<String> symbols}) async {
    final marketDataRepo = _marketDataRepo;
    // 過濾 ETF：00 開頭的代碼（0050、00636、006205 等）沒有資產負債表資料
    final stockSymbols = symbols
        .where((s) => !StockPatterns.isEtfCode(s))
        .toList();
    if (marketDataRepo == null || stockSymbols.isEmpty) return 0;

    if (stockSymbols.length < symbols.length) {
      AppLogger.debug(
        'FundamentalSyncer',
        '資產負債表同步: 跳過 ${symbols.length - stockSymbols.length} 檔 ETF，'
            '實際同步 ${stockSymbols.length} 檔',
      );
    }

    final needySymbols = await _filterNeedingStatementSync(
      stockSymbols,
      'BALANCE',
    );
    if (needySymbols.isEmpty) {
      AppLogger.debug(
        'FundamentalSyncer',
        '資產負債表: ${stockSymbols.length} 檔皆已快取，無需同步',
      );
      return null;
    }

    final now = _clock.now();
    final start = now.subtract(
      const Duration(days: ApiConfig.financialSyncLookbackDays),
    );
    final end = now;
    var count = 0;

    const chunkSize = ApiConfig.syncerBatchSize;
    for (var i = 0; i < needySymbols.length; i += chunkSize) {
      final chunk = needySymbols.skip(i).take(chunkSize).toList();
      final results = await Future.wait(
        chunk.map((s) async {
          try {
            return await marketDataRepo.syncBalanceSheet(
              s,
              startDate: start,
              endDate: end,
            );
          } on RateLimitException {
            rethrow;
          } catch (e) {
            AppLogger.warning('FundamentalSyncer', '$s: 資產負債表同步失敗', e);
            return 0;
          }
        }),
      );
      count += results.fold(0, (sum, n) => sum + n);

      if (i + chunkSize < needySymbols.length) {
        await Future.delayed(
          const Duration(milliseconds: ApiConfig.syncerBatchDelayMs),
        );
      }
    }

    if (count > 0) {
      AppLogger.info(
        'FundamentalSyncer',
        '資產負債表同步: $count 筆 (${needySymbols.length} 檔)',
      );
      return count;
    } else {
      AppLogger.debug(
        'FundamentalSyncer',
        '資產負債表: ${stockSymbols.length} 檔皆已快取，無需同步',
      );
      return null;
    }
  }
}

/// 基本面同步結果
class FundamentalSyncResult {
  const FundamentalSyncResult({
    required this.valuationCount,
    required this.revenueCount,
    this.errors = const [],
  });

  final int valuationCount;

  /// 營收同步筆數。null 表示已快取（跳過同步）。
  final int? revenueCount;

  /// 內部以 per-call catch 收集的 generic 失敗（不 throw）。
  /// caller 必須讀取並轉發到 UpdateResult，否則對使用者靜默
  /// （與 DividendSyncResult.errors 同 pattern）。
  final List<String> errors;

  bool get revenueCached => revenueCount == null;
  int get total => valuationCount + (revenueCount ?? 0);
}
