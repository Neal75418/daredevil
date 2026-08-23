// tool/backfill.dart
//
// CLI tool — print 為預期輸出，關閉 avoid_print lint。
// ignore_for_file: avoid_print
//
// Stage 3: Historical data backfill CLI for calibration purposes.
//
// 把 2 年（可自訂）的台股歷史資料從 TWSE + FinMind 抓下來寫進獨立的
// calibration DB，供 Stage 4 `tool/replay_calibrator.dart` 消費產出
// `rule_accuracy` 表，再由 `tool/recalibrate.dart` 生成 calibrated
// rule scores JSON。詳細設計、資料源清單與實測耗時見 docs/CALIBRATION.md。
//
// ## 使用方式
//
//   # 預設：2 年、tool/calibration.db、FINMIND_TOKEN env var
//   dart run tool/backfill.dart
//
//   # 自訂
//   dart run tool/backfill.dart \
//     --db tool/calibration.db \
//     --years 2 \
//     --finmind-token eyJ... \
//     --symbols 2330,2317,2454 \
//     --dry-run
//
//   # 只補當沖歷史（既有 DB 已有價格時；不需 FinMind token）
//   dart run tool/backfill.dart --only-day-trading --years 9
//
// ## Backfill 資料源（6 個，per-day batch 架構）
//
//   1. daily_price           via backfillTwsePricesByDate / backfillTpexPricesByDate
//                            （MI_INDEX / afterTrading 歷史端點，逐交易日整市場）
//   2. daily_institutional   via backfillInstitutionalByDate（T86/TPEx 批次）
//   3. day_trading           via TradingRepository.syncAllDayTradingFromTwse
//   4. monthly_revenue       via FundamentalRepository.syncMonthlyRevenue
//   5. financial_data (EPS)  via FundamentalRepository.syncFinancialStatements
//   6. stock_valuation (PER) via FundamentalRepository.syncValuationData
//
// `dividend_history` 暫不 backfill — 它只用於 52 週新高/新低的股息
// 調整，非 calibration 的必要輸入。
//
// ## Rate limit
//
// 價格/法人走 per-day batch（每市場每日 1 call），批間有
// interDayDelayMs（預設 5000ms）顯式 delay。FinMind 600/hr (with token)
// 只剩營收/財報/估值 phase 會碰到。
//
// ## Resumability
//
// 所有 phase 都 idempotent — 價格/法人走 per-day「已達目標列數即跳過」
// 檢查（resume guard），營收/財報走 existing-data 檢查。script 中途被
// kill 可以直接重跑續傳。
//
// ## 錯誤處理
//
// - 單 symbol 失敗：log + continue，記錄到 failed symbols list
// - `RateLimitException`：立即 abort（超過 API 額度）
// - `NetworkException`：立即 abort（網路斷線）
// - 其他：log + continue

import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:sqlite3/sqlite3.dart';

import 'package:daredevil/core/utils/date_context.dart';
import 'package:daredevil/core/constants/data_freshness.dart';
import 'package:daredevil/core/constants/market_codes.dart';
import 'package:daredevil/core/exceptions/app_exception.dart';
import 'package:daredevil/core/utils/clock.dart';
import 'package:daredevil/core/utils/taiwan_calendar.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/data/remote/finmind_client.dart';
import 'package:daredevil/data/remote/mops_client.dart';
import 'package:daredevil/data/remote/tpex_client.dart';
import 'package:daredevil/data/remote/twse_client.dart';
import 'package:daredevil/data/repositories/fundamental_repository.dart';
import 'package:daredevil/data/repositories/institutional_repository.dart';
import 'package:daredevil/data/repositories/price_repository.dart';
import 'package:daredevil/data/repositories/stock_repository.dart';
import 'package:daredevil/data/repositories/trading_repository.dart';
import 'package:daredevil/domain/repositories/fundamental_repository.dart';
import 'package:daredevil/domain/repositories/institutional_repository.dart';
import 'package:daredevil/domain/repositories/price_repository.dart';
import 'package:daredevil/domain/repositories/stock_repository.dart';
import 'package:daredevil/domain/repositories/trading_repository.dart';

// ============================================================================
// Public data models (importable by tests)
// ============================================================================

/// Backfill 執行配置
class BackfillConfig {
  const BackfillConfig({
    required this.dbPath,
    required this.years,
    required this.finMindToken,
    this.symbolsWhitelist,
    this.dryRun = false,
    this.skipStockListSync = false,
    this.interDayDelayMs = 5000,
    this.startDateOverride,
    this.endDateOverride,
    this.pricesViaFinMind = false,
    this.skipFundamentals = false,
    this.skipDayTrading = false,
    this.onlyDayTrading = false,
    this.dayTradingMaxDaysPerRun = defaultDayTradingMaxDaysPerRun,
  });

  /// 當沖 phase 單輪回補上限（交易日數）。0 = 不設限，跑完整個日期區間。
  ///
  /// 250 ≈ 一年交易日。取這個值的理由是實測而非湊整：TWSE per-day 端點在
  /// 5s 節流下，前次 operational run 的 institutional phase 跑到第 128 天
  /// 才吃到「API 回傳 HTML 而非 JSON，疑似限流」；MarketIndexSyncer 的深度
  /// 回補則在 50 次呼叫後撞限流中止。單輪壓在 ~250 天讓多數 run 能自然跑完
  /// 而不是中途 abort，靠 resume guard 多輪收斂到 9 年（~9 輪），
  /// 比一次排 2,230 天然後在中段被砍掉更可預測。
  static const int defaultDayTradingMaxDaysPerRun = 250;

  /// SQLite 檔案路徑
  final String dbPath;

  /// 回溯年數
  final int years;

  /// FinMind API token（env var 或 CLI flag）
  final String finMindToken;

  /// 限定 backfill 的 symbol list（null = 全市場）
  final List<String>? symbolsWhitelist;

  /// Dry-run 模式：印出計畫但不實際抓取
  final bool dryRun;

  /// 跳過 stock list 同步（測試用）
  final bool skipStockListSync;

  /// 每天 batch call 之間的延遲毫秒數
  ///
  /// 預設 5000ms（≈ 0.2 req/sec）避開 TWSE IP-based rate limit。
  /// 歷史經驗（已 stale）：500ms 在 70 calls 內被 ban、1500ms 給「充足
  /// 喘息」。但 2026-06 實測 1500ms 在 IP 已被部分標記時 6-22 calls 就被
  /// 擋，TWSE 之後可能收緊限額。5000ms 是經驗保守值，trade off ~3x
  /// wall-clock 換 retry-loop 失敗率近零。500 trading days × 5s ≈
  /// 42 分鐘 per market；如果仍被擋可進一步調到 8000-10000ms。
  ///
  /// 單元測試傳 0 跳過 delay。可用 env var `BACKFILL_INTER_DAY_DELAY_MS`
  /// 覆寫不必改 code。
  final int interDayDelayMs;

  /// 明確指定 backfill 起始日（覆寫 years-based 計算）。
  ///
  /// null = 用 `endDate - years*365`。用於精準回補特定區間（例如只補
  /// 2021-2023 而不重抓已存在的 2024-2026）。
  final DateTime? startDateOverride;

  /// 明確指定 backfill 結束日（覆寫 `DateTime.now()`）。null = now。
  final DateTime? endDateOverride;

  /// 價格回補改走 FinMind per-symbol（而非 TWSE STOCK_DAY_ALL batch）。
  ///
  /// 2026-06 起 TWSE STOCK_DAY_ALL 已不支援歷史 date 參數（一律回最新日），
  /// 故歷史回補（2021-2023 等）必須走 FinMind。預設 false 維持原 batch 行為。
  final bool pricesViaFinMind;

  /// 跳過 3 個基本面 phase（revenue / financial / valuation）。
  ///
  /// 基本面是 FinMind quota 最大宗（~3× 價格用量）。第一階段 walk-forward
  /// 只驗證價格類規則時可跳過，省下大量配額；基本面留作選配第二階段。
  final bool skipFundamentals;

  /// 跳過當沖 phase。
  final bool skipDayTrading;

  /// 只跑當沖 phase（跳過價格／法人／基本面）。
  ///
  /// 針對「calibration.db 已有 9 年價格、只缺當沖」的既有 DB：多輪累積當沖
  /// 歷史時不需要也不該重跑其他 phase。
  final bool onlyDayTrading;

  /// 當沖 phase 單輪最多回補幾個交易日（0 = 不設限）。
  final int dayTradingMaxDaysPerRun;
}

/// 單一 phase 的執行結果
class PhaseResult {
  const PhaseResult({
    required this.phase,
    required this.symbolsProcessed,
    required this.symbolsSucceeded,
    required this.rowsInserted,
    required this.failedSymbols,
    required this.duration,
  });

  final String phase;
  final int symbolsProcessed;
  final int symbolsSucceeded;
  final int rowsInserted;
  final List<String> failedSymbols;
  final Duration duration;

  @override
  String toString() {
    final failRate = symbolsProcessed == 0
        ? 0
        : ((symbolsProcessed - symbolsSucceeded) / symbolsProcessed * 100)
              .toStringAsFixed(1);
    return '[$phase] $symbolsSucceeded/$symbolsProcessed succeeded '
        '($failRate% failed), $rowsInserted rows, '
        '${_formatDuration(duration)}';
  }
}

/// 整體 backfill 結果
class BackfillResult {
  const BackfillResult({required this.phases, required this.totalDuration});

  final List<PhaseResult> phases;
  final Duration totalDuration;

  int get totalRows => phases.fold(0, (sum, p) => sum + p.rowsInserted);

  bool get hasFailures => phases.any((p) => p.failedSymbols.isNotEmpty);
}

/// 依賴注入容器 — 便於測試 mock
class BackfillDeps {
  const BackfillDeps({
    required this.db,
    required this.stockRepo,
    required this.priceRepo,
    required this.institutionalRepo,
    required this.fundamentalRepo,
    this.finMind,
    this.tradingRepo,
  });

  final AppDatabase db;
  final IStockRepository stockRepo;
  final IPriceRepository priceRepo;
  final IInstitutionalRepository institutionalRepo;
  final IFundamentalRepository fundamentalRepo;

  /// 當沖 repository — 僅 day_trading phase 需要。
  ///
  /// 可選（同 [finMind] 慣例）：未注入時 day_trading phase 整段略過並留 log，
  /// 不讓既有 caller 因為新增 phase 而爆掉。
  final ITradingRepository? tradingRepo;

  /// FinMind client — 僅 `pricesViaFinMind` 模式需要（歷史價格 per-symbol 回補）。
  final FinMindClient? finMind;
}

// ============================================================================
// Core backfill logic (testable via dep injection)
// ============================================================================

/// Backfill 主體邏輯，可透過 [BackfillDeps] 注入 mock 進行測試
class Backfiller {
  Backfiller({
    required this.config,
    required this.deps,
    void Function(String)? logger,
  }) : _log = logger ?? print;

  final BackfillConfig config;
  final BackfillDeps deps;
  final void Function(String) _log;

  /// 執行完整的 backfill pipeline
  ///
  /// 各 phase 順序執行（prices/institutional/day_trading/revenue/financial/valuation）。遇到 rate limit / network exception 時立即
  /// 向上拋出 — 呼叫端負責決定要 retry 或 abort。
  Future<BackfillResult> run() async {
    final overallStart = DateTime.now();
    final phases = <PhaseResult>[];

    // Phase 0: 確保 stock_master 表有內容
    //
    // onlyDayTrading 不需要：TWTB4U 一次回全市場、TradingRepository 也不吃
    // targetSymbols，跑 stock list sync 只會平白消耗 FinMind 配額。
    if (!config.skipStockListSync && !config.onlyDayTrading) {
      await _syncStockList();
    }

    // 決定 symbol 範圍
    final symbols = config.onlyDayTrading
        ? const <String>[]
        : await _resolveSymbols();
    if (!config.onlyDayTrading) {
      _log('📋 Target symbols: ${symbols.length}');
    }

    if (config.dryRun) {
      _log('🔍 Dry run — 不實際執行 backfill');
      _logDryRunPlan(symbols);
      return BackfillResult(
        phases: const [],
        totalDuration: DateTime.now().difference(overallStart),
      );
    }

    // 日期範圍 — 優先用明確的 start/end override，否則回退 years-based
    // 正規化到午夜：DateTime.now() 的時間分量若洩漏進 day-loop，
    // countPricesByDateAndMarket 的 TEXT 等值比對永遠 miss → skip-guard 全滅、
    // 每輪 retry 從頭重抓（2026-07-10 燒掉 26 輪的教訓之一）。
    final endDate = DateContext.normalize(
      config.endDateOverride ?? DateTime.now(),
    );
    final startDate = DateContext.normalize(
      config.startDateOverride ??
          endDate.subtract(Duration(days: config.years * 365)),
    );
    _log('📅 Date range: ${_formatDate(startDate)} → ${_formatDate(endDate)}');

    // onlyDayTrading：既有 calibration.db 已有 9 年價格、只缺當沖時，
    // 多輪累積走這條路徑，不重跑任何其他 phase。
    if (config.onlyDayTrading) {
      final dayTrading = await _backfillDayTradingBatch(
        startDate: startDate,
        endDate: endDate,
      );
      if (dayTrading != null) phases.add(dayTrading);
      final totalDuration = DateTime.now().difference(overallStart);
      final result = BackfillResult(
        phases: phases,
        totalDuration: totalDuration,
      );
      _logSummary(result);
      return result;
    }

    // Phase 1: prices — TWSE 上市 / TPEx 上櫃皆走 per-day batch
    //
    // TWSE 上市股票走 STOCK_DAY_ALL?date=...（一次回該日全部上市股票）。
    // TPEx 上櫃股票走 TPEx OpenAPI（一次回該日全部上櫃股票）。
    // 避開的問題：
    //   - 舊 TWSE 月度 per-symbol path 撐 5 分鐘就觸發 TWSE IP-based
    //     rate limit "Redirect loop detected"（1400 symbols × 24 months
    //     ≈ 33,000 calls 太集中）
    //   - 舊 FinMind per-symbol path 吃 600/day 免費額度
    // batch path 後兩個市場各約 500 calls / 2 年，永久脫離兩種 rate limit。
    if (config.pricesViaFinMind) {
      // 歷史回補：STOCK_DAY_ALL batch 已不支援歷史日期 → 走 FinMind per-symbol
      phases.add(
        await _backfillPricesViaFinMind(
          symbols: symbols,
          startDate: startDate,
          endDate: endDate,
        ),
      );
    } else {
      final partitioned = await _partitionSymbolsByMarket(symbols);
      if (partitioned.twse.isNotEmpty) {
        phases.add(
          await _backfillTwsePricesBatch(
            twseSymbols: partitioned.twse,
            startDate: startDate,
            endDate: endDate,
          ),
        );
      }
      if (partitioned.tpex.isNotEmpty) {
        phases.add(
          await _backfillTpexPricesBatch(
            tpexSymbols: partitioned.tpex,
            startDate: startDate,
            endDate: endDate,
          ),
        );
      }
    }
    // Phase 2: institutional — 改走 TWSE T86 + TPEx daily batch
    //
    // 與 prices:tpex 同 pattern：per-day 一次拿全市場兩個 source（TWSE
    // /rwd/zh/fund/T86 + TPEx OpenAPI），按 targetSymbols 過濾後寫入。
    // 取代舊的 per-symbol FinMind 路徑（吃 600/day 免費額度）。
    phases.add(
      await _backfillInstitutionalBatch(
        targetSymbols: symbols,
        startDate: startDate,
        endDate: endDate,
      ),
    );
    // Phase 2.5: day_trading — TWSE TWTB4U per-day batch
    //
    // 必須排在價格 phase 之後：當沖比例 = 當沖成交股數 ÷ 同日
    // daily_price.volume，分母沒落地就只能寫 0（TWTB4U 本身不提供比例）。
    if (!config.skipDayTrading) {
      final dayTrading = await _backfillDayTradingBatch(
        startDate: startDate,
        endDate: endDate,
      );
      if (dayTrading != null) phases.add(dayTrading);
    }

    // 基本面 3 phase 是 FinMind quota 最大宗 — skipFundamentals 時跳過，
    // 只跑價格 + 法人（第一階段 walk-forward 只驗價格類規則）。
    if (!config.skipFundamentals) {
      phases.add(
        await _runPhase(
          name: 'revenue',
          symbols: symbols,
          syncOne: (symbol) => deps.fundamentalRepo.syncMonthlyRevenue(
            symbol: symbol,
            startDate: startDate,
            endDate: endDate,
          ),
        ),
      );
      phases.add(
        await _runPhase(
          name: 'financial',
          symbols: symbols,
          syncOne: (symbol) => deps.fundamentalRepo.syncFinancialStatements(
            symbol: symbol,
            startDate: startDate,
            endDate: endDate,
          ),
        ),
      );
      phases.add(
        await _runPhase(
          name: 'valuation',
          symbols: symbols,
          syncOne: (symbol) => deps.fundamentalRepo.syncValuationData(
            symbol: symbol,
            startDate: startDate,
            endDate: endDate,
          ),
        ),
      );
    } else {
      _log('⏭️  skipFundamentals — 跳過 revenue/financial/valuation phase');
    }

    final totalDuration = DateTime.now().difference(overallStart);
    final result = BackfillResult(phases: phases, totalDuration: totalDuration);
    _logSummary(result);
    return result;
  }

  /// 執行單一 phase — 對所有 symbol 呼叫 [syncOne]
  ///
  /// 錯誤處理政策：
  /// - [RateLimitException] / [NetworkException]：rethrow（立即 abort）
  /// - 其他 exception：log + 記入 failedSymbols，繼續下個 symbol
  Future<PhaseResult> _runPhase({
    required String name,
    required List<String> symbols,
    required Future<int> Function(String symbol) syncOne,
  }) async {
    _log('');
    _log('▶️  Phase [$name] — ${symbols.length} symbols');
    final start = DateTime.now();
    final failedSymbols = <String>[];
    var succeeded = 0;
    var rowsInserted = 0;
    var lastLogAt = DateTime.now();

    for (var i = 0; i < symbols.length; i++) {
      final symbol = symbols[i];
      try {
        final rows = await syncOne(symbol);
        rowsInserted += rows;
        succeeded++;
      } on RateLimitException catch (e) {
        _log('⛔ Phase [$name] 觸發 API rate limit — 中止 backfill: $e');
        rethrow;
      } on NetworkException catch (e) {
        _log('⛔ Phase [$name] 網路錯誤 — 中止 backfill: $e');
        rethrow;
      } catch (e) {
        failedSymbols.add(symbol);
        _log('  ⚠️  $symbol failed: $e');
      }

      // 每 10 秒印一次進度
      final now = DateTime.now();
      if (now.difference(lastLogAt).inSeconds >= 10 ||
          i == symbols.length - 1) {
        final pct = ((i + 1) / symbols.length * 100).toStringAsFixed(1);
        final elapsed = now.difference(start);
        _log(
          '  📊 [$name] ${i + 1}/${symbols.length} ($pct%), '
          'elapsed ${_formatDuration(elapsed)}, '
          'rows=$rowsInserted, failed=${failedSymbols.length}',
        );
        lastLogAt = now;
      }
    }

    final duration = DateTime.now().difference(start);
    return PhaseResult(
      phase: name,
      symbolsProcessed: symbols.length,
      symbolsSucceeded: succeeded,
      rowsInserted: rowsInserted,
      failedSymbols: failedSymbols,
      duration: duration,
    );
  }

  /// 同步 stock list 至 stock_master
  Future<void> _syncStockList() async {
    _log('▶️  Phase [stock_list] — 從 FinMind 同步股票清單');
    final start = DateTime.now();
    try {
      final count = await deps.stockRepo.syncStockList();
      final duration = DateTime.now().difference(start);
      _log(
        '✅ [stock_list] synced $count stocks in ${_formatDuration(duration)}',
      );
    } on RateLimitException {
      rethrow;
    } on NetworkException {
      rethrow;
    } catch (e) {
      _log('⚠️  [stock_list] 同步失敗，嘗試使用既有資料: $e');
    }
  }

  /// 決定要 backfill 的 symbol 列表
  ///
  /// 優先順序：CLI whitelist > stock_master 中所有 active stocks
  Future<List<String>> _resolveSymbols() async {
    if (config.symbolsWhitelist != null &&
        config.symbolsWhitelist!.isNotEmpty) {
      return config.symbolsWhitelist!;
    }
    final stocks = await deps.stockRepo.getAllStocks();
    return stocks.map((s) => s.symbol).toList();
  }

  /// 依市場別把 symbol 拆成 TWSE 上市 / TPEx 上櫃兩組
  ///
  /// stock_master 內找不到的 symbol 預設視為 TWSE（與 `PriceRepository.
  /// syncStockPrices` 內 `isOtc = stock?.market == MarketCode.tpex` 的
  /// 行為一致）。
  Future<_MarketPartition> _partitionSymbolsByMarket(
    List<String> symbols,
  ) async {
    final stockMap = await deps.db.getStocksBatch(symbols);
    final twse = <String>[];
    final tpex = <String>[];
    for (final symbol in symbols) {
      final market = stockMap[symbol]?.market;
      if (market == MarketCode.tpex) {
        tpex.add(symbol);
      } else {
        twse.add(symbol);
      }
    }
    return _MarketPartition(twse: twse, tpex: tpex);
  }

  /// 法人資料 batch backfill（TWSE T86 + TPEx OpenAPI 一起）
  ///
  /// 對日期範圍內每個交易日呼叫
  /// [IInstitutionalRepository.backfillInstitutionalByDate]，每天 1 次
  /// 兩個 source 並行拿全市場資料，過濾後寫入 DB。
  ///
  /// 跟 [_runPhase] 同樣的 rate limit / network exception abort 政策；
  /// 其他例外記入 `failedSymbols`（以日期字串標記）繼續。
  Future<PhaseResult> _backfillInstitutionalBatch({
    required List<String> targetSymbols,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    _log('');
    _log(
      '▶️  Phase [institutional] — ${targetSymbols.length} symbols × per-day '
      'TWSE+TPEx batch',
    );
    final phaseStart = DateTime.now();
    final targetSet = targetSymbols.toSet();
    final failedDays = <String>[];
    var rowsInserted = 0;
    var daysProcessed = 0;
    var daysSucceeded = 0;
    var lastLogAt = DateTime.now();

    final totalCalendarDays = endDate.difference(startDate).inDays;

    var current = startDate;
    while (!current.isAfter(endDate)) {
      if (!TaiwanCalendar.isTradingDay(current)) {
        current = current.add(const Duration(days: 1));
        continue;
      }

      final dayStr = _formatDate(current);

      // Resume：該日已有足量法人 rows（≥50% target，同 price phase 門檻
      // 語意）→ 跳過。法人 phase 無此 guard 時，每輪 retry 要重抓 ~2 小時
      // 才能走到後面的 FinMind phase（2026-07-13 rate-limit 輪迴實測）。
      final existingInst = await deps.db.countInstitutionalByDate(current);
      if (existingInst >= targetSet.length * 0.5) {
        daysSucceeded++;
        daysProcessed++;
        current = current.add(const Duration(days: 1));
        continue;
      }

      try {
        final count = await deps.institutionalRepo.backfillInstitutionalByDate(
          date: current,
          targetSymbols: targetSet,
        );
        rowsInserted += count;
        daysSucceeded++;
      } on RateLimitException catch (e) {
        _log('⛔ Phase [institutional] $dayStr 觸發 API rate limit — abort: $e');
        rethrow;
      } on NetworkException catch (e) {
        _log('⛔ Phase [institutional] $dayStr 網路錯誤 — abort: $e');
        rethrow;
      } catch (e) {
        failedDays.add(dayStr);
        _log('  ⚠️  $dayStr failed: $e');
      }
      daysProcessed++;

      final now = DateTime.now();
      if (now.difference(lastLogAt).inSeconds >= 10 ||
          current.isAtSameMomentAs(endDate)) {
        final daysCovered = current.difference(startDate).inDays;
        final pct = totalCalendarDays == 0
            ? '0.0'
            : (daysCovered / totalCalendarDays * 100).toStringAsFixed(1);
        final elapsed = now.difference(phaseStart);
        _log(
          '  📊 [institutional] $daysProcessed trading days '
          '(through $dayStr, $pct% of calendar), '
          'elapsed ${_formatDuration(elapsed)}, '
          'rows=$rowsInserted, failed=${failedDays.length}',
        );
        lastLogAt = now;
      }

      // 避開 TWSE IP-based rate limit（同樣端點上次跑 2.5 req/sec 就被 ban）
      if (config.interDayDelayMs > 0) {
        await Future.delayed(Duration(milliseconds: config.interDayDelayMs));
      }
      current = current.add(const Duration(days: 1));
    }

    final duration = DateTime.now().difference(phaseStart);
    return PhaseResult(
      phase: 'institutional',
      // Per-day 模式：用 daysProcessed 填 symbolsProcessed（同
      // _backfillTpexPricesBatch 慣例）
      symbolsProcessed: daysProcessed,
      symbolsSucceeded: daysSucceeded,
      rowsInserted: rowsInserted,
      // failedSymbols 此處為失敗的日期字串
      failedSymbols: failedDays,
      duration: duration,
    );
  }

  /// 當沖歷史 batch backfill（TWSE TWTB4U per-day）
  ///
  /// 為什麼需要這個 phase：`calibration.db` 有 310 萬筆價格／9 年歷史，但
  /// `day_trading` 是 **0 列** —— 當沖資料從未進過 calibration pipeline，
  /// 而 app 端 `ApiConfig.tradingBackfillLookbackDays = 40` 只維護滾動 40 天
  /// 窗。2026-07-18 的當沖門檻研究因此只拿得到 29 個交易日、20D 只剩 9 個
  /// 重疊窗，無法對任何門檻下結論。
  ///
  /// 端點可行性（2026-07-18 實測 8 個日期，含 2017-05-11 / 2018-04-17 /
  /// 2020-04-17 / 2023-04-17）：TWTB4U **仍支援歷史 date 參數**，回應
  /// `date` 欄位與請求一致、rows 901~1213，深度可回到 2017-05-11——正好
  /// 涵蓋 `calibration.db` 價格起點。這點與 STOCK_DAY_ALL 不同（後者
  /// 2026-06 起忽略 date、一律回最新日，見 [BackfillConfig.pricesViaFinMind]）。
  ///
  /// 設計對齊 [_backfillInstitutionalBatch]（per-day batch + resume guard +
  /// 限流 rethrow）與 `MarketIndexSyncer.backfillDeepHistory`（由新至舊、
  /// 單輪上限、多輪收斂）。
  ///
  /// 冪等性由兩層保證：
  /// 1. 本方法的 resume guard（該日已有 > [DataFreshness.twseBatchThreshold]
  ///    列即跳過，連 API 都不打）
  /// 2. `day_trading` 的 PK 為 (symbol, date) + `InsertMode.insertOrReplace`
  ///
  /// 回傳 null 表示 phase 未執行（未注入 [BackfillDeps.tradingRepo]）。
  Future<PhaseResult?> _backfillDayTradingBatch({
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final tradingRepo = deps.tradingRepo;
    if (tradingRepo == null) {
      _log('⏭️  未注入 tradingRepo — 跳過 day_trading phase');
      return null;
    }

    _log('');
    _log('▶️  Phase [day_trading] — per-day TWSE TWTB4U batch');
    final phaseStart = DateTime.now();
    final failedDays = <String>[];
    var rowsInserted = 0;
    var daysProcessed = 0;
    var daysSucceeded = 0;
    var apiCalls = 0;
    var consecutiveZeroDays = 0;
    var lastLogAt = DateTime.now();

    // 由新至舊走訪（同 MarketIndexSyncer.backfillDeepHistory）：限流中止時
    // 優先保住較近期的區段——研究通常從最近往回取窗，近期資料先到手比
    // 「2017 年補完但近三年還缺」有用得多。
    final maxDays = config.dayTradingMaxDaysPerRun;
    var current = endDate;
    while (!current.isBefore(startDate)) {
      if (maxDays > 0 && daysProcessed >= maxDays) {
        _log('  ⏸️  [day_trading] 已達單輪上限 $maxDays 個交易日 — 本輪結束，重跑可續補');
        break;
      }
      if (!TaiwanCalendar.isTradingDay(current)) {
        current = current.subtract(const Duration(days: 1));
        continue;
      }

      final dayStr = _formatDate(current);

      // Resume：該日已有足量當沖 rows → 跳過，連 API 都不打。門檻沿用
      // TradingRepository 自身的 freshness 門檻，避免兩層判斷不一致造成
      // 「這裡放行、repo 內部又跳過」的空轉。
      final existing = await deps.db.getDayTradingCountForDate(current);
      if (existing > DataFreshness.twseBatchThreshold) {
        daysSucceeded++;
        daysProcessed++;
        current = current.subtract(const Duration(days: 1));
        continue;
      }

      try {
        if (apiCalls > 0 && config.interDayDelayMs > 0) {
          await Future.delayed(Duration(milliseconds: config.interDayDelayMs));
        }
        final count = await tradingRepo.syncAllDayTradingFromTwse(
          date: current,
        );
        apiCalls++;
        rowsInserted += count;
        daysSucceeded++;

        if (count == 0) {
          consecutiveZeroDays++;
          if (consecutiveZeroDays >= _maxConsecutiveZeroDays) {
            _log(
              '⛔ Phase [day_trading] 連續 $_maxConsecutiveZeroDays 個交易日 0 筆 — '
              '疑似端點失效（TWTB4U 若開始忽略 date 參數，TwseClient 的日期'
              '守衛會整批丟棄）→ abort phase',
            );
            failedDays.add('$dayStr(連續零筆中止)');
            daysProcessed++;
            break;
          }
        } else {
          consecutiveZeroDays = 0;
        }
      } on RateLimitException catch (e) {
        _log('⛔ Phase [day_trading] $dayStr 觸發 API rate limit — abort: $e');
        rethrow;
      } on NetworkException catch (e) {
        _log('⛔ Phase [day_trading] $dayStr 網路錯誤 — abort: $e');
        rethrow;
      } catch (e) {
        failedDays.add(dayStr);
        _log('  ⚠️  $dayStr failed: $e');
      }
      daysProcessed++;

      final now = DateTime.now();
      if (now.difference(lastLogAt).inSeconds >= 10) {
        final elapsed = now.difference(phaseStart);
        _log(
          '  📊 [day_trading] $daysProcessed trading days '
          '(through $dayStr), elapsed ${_formatDuration(elapsed)}, '
          'rows=$rowsInserted, failed=${failedDays.length}',
        );
        lastLogAt = now;
      }

      current = current.subtract(const Duration(days: 1));
    }

    final duration = DateTime.now().difference(phaseStart);
    return PhaseResult(
      phase: 'day_trading',
      // Per-day 模式：用 daysProcessed 填 symbolsProcessed（同
      // _backfillInstitutionalBatch 慣例）
      symbolsProcessed: daysProcessed,
      symbolsSucceeded: daysSucceeded,
      rowsInserted: rowsInserted,
      // failedSymbols 此處為失敗的日期字串
      failedSymbols: failedDays,
      duration: duration,
    );
  }

  /// 連續 N 個「日曆判定為交易日」fetch 回 0 rows 即 abort 該 phase。
  ///
  /// 連續 0 的兩種可能：(a) 端點失效（TWSE 2026-06 起 STOCK_DAY_ALL
  /// 忽略 date 參數、repository 按請求日過濾後回 0）——fail-fast 的目標；
  /// (b) **TaiwanCalendar 不認識的舊年度假日群集**（實測 2021 春節
  /// 2/8–2/16 連續 7 個平日休市、被當交易日去抓、API 正確回無資料）。
  ///
  /// 閾值必須 > 台股最長休市群集（春節 ~8 個平日），取 10：假日群集
  /// 最多浪費 ~10 次 API 呼叫後自行恢復；端點真失效仍會在 ~1 分鐘內
  /// abort（vs 死迴圈燒 3 小時）。2026-07-12 曾因閾值 3 在 2021 春節
  /// 誤殺 TWSE phase。
  static const int _maxConsecutiveZeroDays = 10;

  /// TWSE 上市股票價格 batch backfill
  ///
  /// 對日期範圍內每個交易日呼叫 [IPriceRepository.backfillTwsePricesByDate]，
  /// 每天 1 次 TWSE STOCK_DAY_ALL?date=... 拿全市場上市股票價格，過濾後
  /// 寫入 DB。Pattern 與 [_backfillTpexPricesBatch] 對稱。
  Future<PhaseResult> _backfillTwsePricesBatch({
    required List<String> twseSymbols,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    _log('');
    _log(
      '▶️  Phase [prices:twse] — ${twseSymbols.length} symbols × per-day batch',
    );
    final phaseStart = DateTime.now();
    final targetSet = twseSymbols.toSet();
    final failedDays = <String>[];
    var rowsInserted = 0;
    var daysProcessed = 0;
    var daysSucceeded = 0;
    var consecutiveZeroDays = 0;
    var lastLogAt = DateTime.now();

    final totalCalendarDays = endDate.difference(startDate).inDays;

    var current = startDate;
    while (!current.isAfter(endDate)) {
      if (!TaiwanCalendar.isTradingDay(current)) {
        current = current.add(const Duration(days: 1));
        continue;
      }

      final dayStr = _formatDate(current);

      // Resume：該日該市場已有足量 rows（≥50% target）→ 跳過、不打 API。
      // TWSE 限流窗口有限（每輪 ~30-40 分鐘），沒有 per-day skip 的話
      // retry 每輪都從頭重抓同一段、永遠推不到 abort 點之後。
      // 門檻 50%（而非 >0）：仍遠高於 FinMind per-symbol phase 寫入的
      // 候選子集（~300 列），但涵蓋歷史年份的市場規模——2021 年 TWSE 僅
      // ~1,050 檔，用「今日股票數 × 80%」(1,101) 當分母會把已完整的舊
      // 日子全部誤判為缺、每輪重抓整段歷史（2026-07-13 實測 48 分鐘
      // 重抓 522 天的教訓）。
      final existing = await deps.db.countPricesByDateAndMarket(
        current,
        MarketCode.twse,
      );
      if (existing >= targetSet.length * 0.5) {
        daysSucceeded++;
        daysProcessed++;
        // skip = 該日已完整 → 歸零連零計數：假日群集（曆表不含的舊年度
        // 春節）之間被完整日隔開，不得跨年累積誤觸 abort（2026-07-13
        // 實測 2022+2023 春節零日跨過一年 skip 疊加到 10 的教訓）。
        consecutiveZeroDays = 0;
        current = current.add(const Duration(days: 1));
        continue;
      }

      try {
        final count = await deps.priceRepo.backfillTwsePricesByDate(
          date: current,
          targetSymbols: targetSet,
        );
        rowsInserted += count;
        daysSucceeded++;
        if (count == 0) {
          consecutiveZeroDays++;
          if (consecutiveZeroDays >= _maxConsecutiveZeroDays) {
            _log(
              '⛔ Phase [prices:twse] 連續 $_maxConsecutiveZeroDays 個交易日 0 rows'
              '（最後: $dayStr）— abort phase。疑似端點失效 / date 參數被忽略'
              '（TWSE 2026-06 起 STOCK_DAY_ALL 已知不支援歷史查詢）',
            );
            failedDays.add('$dayStr(consecutive-zero-abort)');
            break;
          }
        } else {
          consecutiveZeroDays = 0;
        }
      } on RateLimitException catch (e) {
        _log('⛔ Phase [prices:twse] $dayStr 觸發 API rate limit — abort: $e');
        rethrow;
      } on NetworkException catch (e) {
        _log('⛔ Phase [prices:twse] $dayStr 網路錯誤 — abort: $e');
        rethrow;
      } catch (e) {
        failedDays.add(dayStr);
        _log('  ⚠️  $dayStr failed: $e');
      }
      daysProcessed++;

      final now = DateTime.now();
      if (now.difference(lastLogAt).inSeconds >= 10 ||
          current.isAtSameMomentAs(endDate)) {
        final daysCovered = current.difference(startDate).inDays;
        final pct = totalCalendarDays == 0
            ? '0.0'
            : (daysCovered / totalCalendarDays * 100).toStringAsFixed(1);
        final elapsed = now.difference(phaseStart);
        _log(
          '  📊 [prices:twse] $daysProcessed trading days '
          '(through $dayStr, $pct% of calendar), '
          'elapsed ${_formatDuration(elapsed)}, '
          'rows=$rowsInserted, failed=${failedDays.length}',
        );
        lastLogAt = now;
      }

      // 避開 TWSE IP-based rate limit（同樣端點上次跑 2.5 req/sec 就被 ban）
      if (config.interDayDelayMs > 0) {
        await Future.delayed(Duration(milliseconds: config.interDayDelayMs));
      }
      current = current.add(const Duration(days: 1));
    }

    final duration = DateTime.now().difference(phaseStart);
    return PhaseResult(
      phase: 'prices:twse',
      // Per-day 模式：用 daysProcessed 填 symbolsProcessed
      symbolsProcessed: daysProcessed,
      symbolsSucceeded: daysSucceeded,
      rowsInserted: rowsInserted,
      // failedSymbols 此處為失敗的日期字串
      failedSymbols: failedDays,
      duration: duration,
    );
  }

  /// TPEx 上櫃股票價格 batch backfill
  ///
  /// 對日期範圍內每個交易日呼叫 [IPriceRepository.backfillTpexPricesByDate]，
  /// 每天 1 次 API call 拿全市場上櫃股票價格，過濾後寫入 DB。
  ///
  /// 跟 [_runPhase] 同樣的 rate limit / network exception abort 政策；
  /// 其他例外記入 `failedSymbols`（以日期字串標記）繼續。
  Future<PhaseResult> _backfillTpexPricesBatch({
    required List<String> tpexSymbols,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    _log('');
    _log(
      '▶️  Phase [prices:tpex] — ${tpexSymbols.length} symbols × per-day batch',
    );
    final phaseStart = DateTime.now();
    final targetSet = tpexSymbols.toSet();
    final failedDays = <String>[];
    var rowsInserted = 0;
    var daysProcessed = 0;
    var daysSucceeded = 0;
    var consecutiveZeroDays = 0;
    var lastLogAt = DateTime.now();

    final totalCalendarDays = endDate.difference(startDate).inDays;

    var current = startDate;
    while (!current.isAfter(endDate)) {
      if (!TaiwanCalendar.isTradingDay(current)) {
        current = current.add(const Duration(days: 1));
        continue;
      }

      final dayStr = _formatDate(current);

      // Resume：與 prices:twse 對稱的 per-day skip（見該處說明）
      final existing = await deps.db.countPricesByDateAndMarket(
        current,
        MarketCode.tpex,
      );
      if (existing >= targetSet.length * 0.5) {
        daysSucceeded++;
        daysProcessed++;
        // skip = 該日已完整 → 歸零連零計數：假日群集（曆表不含的舊年度
        // 春節）之間被完整日隔開，不得跨年累積誤觸 abort（2026-07-13
        // 實測 2022+2023 春節零日跨過一年 skip 疊加到 10 的教訓）。
        consecutiveZeroDays = 0;
        current = current.add(const Duration(days: 1));
        continue;
      }

      try {
        final count = await deps.priceRepo.backfillTpexPricesByDate(
          date: current,
          targetSymbols: targetSet,
        );
        rowsInserted += count;
        daysSucceeded++;
        if (count == 0) {
          consecutiveZeroDays++;
          if (consecutiveZeroDays >= _maxConsecutiveZeroDays) {
            _log(
              '⛔ Phase [prices:tpex] 連續 $_maxConsecutiveZeroDays 個交易日 0 rows'
              '（最後: $dayStr）— abort phase。疑似端點失效 / date 參數被忽略'
              '（TWSE 2026-06 起 STOCK_DAY_ALL 已知不支援歷史查詢）',
            );
            failedDays.add('$dayStr(consecutive-zero-abort)');
            break;
          }
        } else {
          consecutiveZeroDays = 0;
        }
      } on RateLimitException catch (e) {
        _log('⛔ Phase [prices:tpex] $dayStr 觸發 API rate limit — abort: $e');
        rethrow;
      } on NetworkException catch (e) {
        _log('⛔ Phase [prices:tpex] $dayStr 網路錯誤 — abort: $e');
        rethrow;
      } catch (e) {
        failedDays.add(dayStr);
        _log('  ⚠️  $dayStr failed: $e');
      }
      daysProcessed++;

      final now = DateTime.now();
      if (now.difference(lastLogAt).inSeconds >= 10 ||
          current.isAtSameMomentAs(endDate)) {
        final daysCovered = current.difference(startDate).inDays;
        final pct = totalCalendarDays == 0
            ? '0.0'
            : (daysCovered / totalCalendarDays * 100).toStringAsFixed(1);
        final elapsed = now.difference(phaseStart);
        _log(
          '  📊 [prices:tpex] $daysProcessed trading days '
          '(through $dayStr, $pct% of calendar), '
          'elapsed ${_formatDuration(elapsed)}, '
          'rows=$rowsInserted, failed=${failedDays.length}',
        );
        lastLogAt = now;
      }

      // 跟 prices:twse / institutional 對稱 — 避免任何 batch endpoint 觸發
      // IP-based rate limit。TPEx OpenAPI 較寬鬆但保持同步驟簡化推理。
      if (config.interDayDelayMs > 0) {
        await Future.delayed(Duration(milliseconds: config.interDayDelayMs));
      }
      current = current.add(const Duration(days: 1));
    }

    final duration = DateTime.now().difference(phaseStart);
    return PhaseResult(
      phase: 'prices:tpex',
      // 這個 phase 是 per-day 模式：用 daysProcessed 填 symbolsProcessed
      // 讓 toString() 的失敗率計算對應「失敗的天數 / 處理過的天數」。
      symbolsProcessed: daysProcessed,
      symbolsSucceeded: daysSucceeded,
      rowsInserted: rowsInserted,
      // failedSymbols 此處實為失敗的日期字串 — 讀 log 看上下文容易理解
      failedSymbols: failedDays,
      duration: duration,
    );
  }

  /// 用 FinMind TaiwanStockPrice 逐檔回補歷史價格（上市 + 上櫃皆可）。
  ///
  /// 動機：TWSE STOCK_DAY_ALL batch 端點 2026-06 起不再支援歷史 date 參數
  /// （一律回最新交易日），舊的 TWSE per-symbol 月度端點則 rate-limit 嚴重。
  /// FinMind getDailyPrices 一個 call 帶整段 date range、per-symbol，是歷史
  /// 回補唯一可行來源。
  ///
  /// rate limit / network 政策同 [_runPhase]：立即 abort；其他例外記 failed
  /// 後續行。每檔之間沿用 [BackfillConfig.interDayDelayMs] delay 控 FinMind
  /// 600/hr 額度。
  Future<PhaseResult> _backfillPricesViaFinMind({
    required List<String> symbols,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final finMind = deps.finMind;
    _log('');
    _log(
      '▶️  Phase [prices:finmind] — ${symbols.length} symbols × FinMind range',
    );
    final phaseStart = DateTime.now();
    if (finMind == null) {
      _log('⚠️  [prices:finmind] 無 FinMindClient 注入 — 跳過');
      return PhaseResult(
        phase: 'prices:finmind',
        symbolsProcessed: 0,
        symbolsSucceeded: 0,
        rowsInserted: 0,
        failedSymbols: const [],
        duration: DateTime.now().difference(phaseStart),
      );
    }

    final startStr = _formatDate(startDate);
    final endStr = _formatDate(endDate);

    // Resumability：跳過已補過該區間的 symbol（前次 run 完成的）。閾值 > 100
    // 列以排除既有稀疏樣本（原 calibration.db 每股僅數列），只認「完整回補過」。
    // ISO date 字串可直接字典序比較（DB 存 ISO text）。
    final endExclusive = _formatDate(endDate.add(const Duration(days: 1)));
    final doneRows = await deps.db
        .customSelect(
          'SELECT symbol FROM daily_price '
          "WHERE date >= '$startStr' AND date < '$endExclusive' "
          'GROUP BY symbol HAVING COUNT(*) > 100',
        )
        .get();
    final doneSymbols = doneRows.map((r) => r.read<String>('symbol')).toSet();
    if (doneSymbols.isNotEmpty) {
      _log('  ↪️  resumability: 跳過 ${doneSymbols.length} 個已完成 symbol');
    }

    final failed = <String>[];
    var succeeded = 0;
    var rowsInserted = 0;
    var skipped = 0;
    var lastLogAt = DateTime.now();

    for (var i = 0; i < symbols.length; i++) {
      final symbol = symbols[i];
      if (doneSymbols.contains(symbol)) {
        skipped++;
        succeeded++;
        continue;
      }
      try {
        final fps = await finMind.getDailyPrices(
          stockId: symbol,
          startDate: startStr,
          endDate: endStr,
        );
        final companions = <DailyPriceCompanion>[];
        for (final fp in fps) {
          final date = DateTime.tryParse(fp.date);
          if (date == null) continue;
          companions.add(
            DailyPriceCompanion.insert(
              symbol: symbol,
              date: date,
              open: Value(fp.open),
              high: Value(fp.high),
              low: Value(fp.low),
              close: Value(fp.close),
              volume: Value(fp.volume),
            ),
          );
        }
        if (companions.isNotEmpty) {
          await deps.db.insertPrices(companions);
          rowsInserted += companions.length;
        }
        succeeded++;
      } on RateLimitException catch (e) {
        _log('⛔ Phase [prices:finmind] $symbol 觸發 rate limit — abort: $e');
        rethrow;
      } on NetworkException catch (e) {
        _log('⛔ Phase [prices:finmind] $symbol 網路錯誤 — abort: $e');
        rethrow;
      } catch (e) {
        failed.add(symbol);
        _log('  ⚠️  $symbol failed: $e');
      }

      final now = DateTime.now();
      if (now.difference(lastLogAt).inSeconds >= 10 ||
          i == symbols.length - 1) {
        final pct = ((i + 1) / symbols.length * 100).toStringAsFixed(1);
        _log(
          '  📊 [prices:finmind] ${i + 1}/${symbols.length} ($pct%), '
          'rows=$rowsInserted, skipped=$skipped, failed=${failed.length}, '
          'elapsed ${_formatDuration(now.difference(phaseStart))}',
        );
        lastLogAt = now;
      }

      // FinMind 600/hr 額度 → 控速（與 batch 端點共用 delay 旋鈕）
      if (config.interDayDelayMs > 0) {
        await Future.delayed(Duration(milliseconds: config.interDayDelayMs));
      }
    }

    return PhaseResult(
      phase: 'prices:finmind',
      symbolsProcessed: symbols.length,
      symbolsSucceeded: succeeded,
      rowsInserted: rowsInserted,
      failedSymbols: failed,
      duration: DateTime.now().difference(phaseStart),
    );
  }

  void _logDryRunPlan(List<String> symbols) {
    _log('');
    _log('DRY RUN PLAN:');
    _log('  DB path: ${config.dbPath}');
    _log('  Years: ${config.years}');
    _log('  Symbols: ${symbols.length}');
    // 🚨 依 config 列出實際會跑的 phase(2026-08-22 修)。原本是寫死的字串,
    // 不管 skipFundamentals / skipDayTrading / onlyDayTrading 設什麼都印一樣
    // ——dry run 的意義就是預覽會發生什麼,印一份與實際不符的清單比不印更糟。
    final phases = <String>[
      if (config.onlyDayTrading) ...[
        'day_trading (only)',
      ] else ...[
        if (!config.skipStockListSync) 'stock_list',
        // 價格來源是二選一(見主流程的 if/else),不是兩者都跑
        if (config.pricesViaFinMind)
          'prices:finmind'
        else ...[
          'prices:twse',
          'prices:tpex (per-day batch)',
        ],
        'institutional (per-day batch)',
        if (!config.skipDayTrading) 'day_trading',
        if (!config.skipFundamentals) ...['revenue', 'financial', 'valuation'],
      ],
    ];
    _log('  Phases: ${phases.join(', ')}');
    // per-day batch 口徑（2026-07-23 稽核修復：原估算沿用已退役的
    // per-symbol 架構，會嚴重高估 quota/耗時）
    final tradingDays = (config.years * 250).round();
    // 🚨 這個區塊也要依 config(2026-08-23 補)。先前只把上面的 Phases 改成
    // config-aware,估算卻仍無條件印——開 pricesViaFinMind 時預覽說
    // 「FinMind ~0 次」,實際是每 symbol 一次(~2,400,約 4 小時),而那正是
    // 新的 SKIP_FUNDAMENTALS 預設要避免的失敗。
    _log('  Estimated API calls:');
    if (config.onlyDayTrading) {
      _log('    - DayTrading:    ~$tradingDays 交易日 × 1 市場（僅 TWSE TWTB4U）');
    } else {
      if (config.pricesViaFinMind) {
        _log(
          '    - Prices:        ${symbols.length} symbols '
          '(FinMind per-symbol range call)',
        );
      } else {
        _log(
          '    - Prices:        ~$tradingDays 交易日 × 2 市場 (per-day batch) '
          '= ~${tradingDays * 2}',
        );
      }
      _log('    - Institutional: ~$tradingDays 交易日 × 2 市場 (per-day batch)');
      if (!config.skipDayTrading) {
        _log('    - DayTrading:    ~$tradingDays 交易日 × 1 市場（僅 TWSE TWTB4U）');
      }
    }
    if (config.skipFundamentals) {
      _log(
        '    - Revenue/Financial/Valuation: 跳過'
        '（BACKFILL_SKIP_FUNDAMENTALS）',
      );
    } else {
      _log('    - Revenue:       ${symbols.length} (FinMind per-symbol)');
      _log('    - Financial:     ${symbols.length} (FinMind per-symbol)');
      _log('    - Valuation:     ${symbols.length} (FinMind per-symbol)');
    }
    // FinMind 用量 = 基本面三 phase + (價格走 FinMind 時的每 symbol 一次)
    final totalFinMind =
        (config.skipFundamentals ? 0 : symbols.length * 3) +
        (config.pricesViaFinMind && !config.onlyDayTrading
            ? symbols.length
            : 0);
    final eta = Duration(seconds: (totalFinMind * 3600 / 600).round());
    _log(
      '  FinMind calls total: ~$totalFinMind (~${_formatDuration(eta)} at '
      '600/hr limit)',
    );
  }

  void _logSummary(BackfillResult result) {
    _log('');
    _log('=' * 60);
    _log('✅ BACKFILL COMPLETE');
    _log('=' * 60);
    _log('Total duration: ${_formatDuration(result.totalDuration)}');
    _log('Total rows: ${result.totalRows}');
    _log('');
    _log('Per-phase:');
    for (final p in result.phases) {
      _log('  $p');
    }
    if (result.hasFailures) {
      _log('');
      _log('⚠️  Failed symbols per phase:');
      for (final p in result.phases) {
        if (p.failedSymbols.isNotEmpty) {
          _log(
            '  [${p.phase}]: ${p.failedSymbols.take(10).join(', ')}'
            '${p.failedSymbols.length > 10 ? " ..." : ""}',
          );
        }
      }
    }
  }
}

// ============================================================================
// CLI entry point
// ============================================================================

/// Dart CLI main — 只是 [runBackfillCli] 的 thin wrapper，負責把 int
/// exit code 送回 shell。
///
/// 可以透過兩種方式執行（C 方案 refactor 後 drift_flutter 已拆離，
/// 兩者皆可；2026-07-23 實測 `dart run` 正常編譯執行）：
/// - `dart run tool/backfill.dart ...`
/// - `flutter test test/tool/run_backfill.dart` — 見 scripts/calibrate.sh
Future<void> main(List<String> args) async {
  final code = await runBackfillCli(args);
  exit(code);
}

/// 不呼叫 [exit] 的 backfill 入口函式。供 test wrapper 使用。
///
/// 返回 exit code：
///   0 — 成功
///   1 — 無效 CLI 參數
///   3 — 完成但有 symbol 失敗（partial success）
///   4 — rate limit 觸發
///   5 — network error
///   6 — schema fingerprint 不符（未開 DB，避免歷史資料被 reset 清空）
Future<int> runBackfillCli(List<String> args) async {
  final config = _parseArgs(args);
  if (config == null) {
    _printUsage(stderr);
    return 1;
  }

  // 若 --years 過大提醒使用者
  if (config.years > 5) {
    stderr.writeln('⚠️  --years ${config.years} 很大，FinMind 可能回傳不完整歷史且耗時數天');
  }

  // 建立 DB（自動建立 schema via fingerprint 機制）
  final dbFile = File(config.dbPath);
  final isNewDb = !dbFile.existsSync();
  if (isNewDb) {
    print('📦 建立新的 calibration DB: ${config.dbPath}');
  } else {
    print('📦 開啟既有 calibration DB: ${config.dbPath}');
    // ⚠️ 開 DB 前必須先擋：AppDatabase 的 fingerprint reset 是不可逆的。
    final mismatch = _checkSchemaFingerprint(config.dbPath);
    if (mismatch != null) {
      stderr.writeln(mismatch);
      return 6;
    }
  }

  final db = AppDatabase.forToolFile(config.dbPath);

  try {
    // 初始化 clients
    final finMind = FinMindClient()..token = config.finMindToken;
    final twse = TwseClient();
    final tpex = TpexClient();
    const clock = SystemClock();

    // 初始化 repositories
    final stockRepo = StockRepository(
      database: db,
      finMindClient: finMind,
      twseClient: twse,
    );
    final priceRepo = PriceRepository(
      database: db,
      finMindClient: finMind,
      twseClient: twse,
      tpexClient: tpex,
      clock: clock,
    );
    final institutionalRepo = InstitutionalRepository(
      database: db,
      finMindClient: finMind,
      twseClient: twse,
      tpexClient: tpex,
      clock: clock,
    );
    final fundamentalRepo = FundamentalRepository(
      mops: MopsClient(),
      db: db,
      finMind: finMind,
      twse: twse,
      tpex: tpex,
      clock: clock,
    );

    final tradingRepo = TradingRepository(
      database: db,
      twseClient: twse,
      tpexClient: tpex,
      clock: clock,
    );

    final deps = BackfillDeps(
      db: db,
      stockRepo: stockRepo,
      priceRepo: priceRepo,
      institutionalRepo: institutionalRepo,
      fundamentalRepo: fundamentalRepo,
      finMind: finMind,
      tradingRepo: tradingRepo,
    );

    final backfiller = Backfiller(config: config, deps: deps);
    final result = await backfiller.run();

    if (result.hasFailures) {
      print('');
      print('⚠️  Backfill 完成但有 symbol 失敗，請檢查上方 log');
      return 3;
    }
    return 0;
  } on RateLimitException catch (e) {
    stderr.writeln('');
    stderr.writeln('❌ API rate limit exceeded: $e');
    stderr.writeln('💡 請等一段時間後再重跑 — resumability 會自動跳過已完成的部分');
    return 4;
  } on NetworkException catch (e) {
    stderr.writeln('');
    stderr.writeln('❌ Network error: $e');
    stderr.writeln('💡 檢查網路連線後重跑');
    return 5;
  } finally {
    await db.close();
  }
}

/// 開 DB 前比對 schema fingerprint，不一致就中止並回傳錯誤訊息（null = 安全）。
///
/// 為什麼需要這道關卡：[AppDatabase] 的 `_ensureSchemaFingerprint` 在
/// fingerprint 不符時，會把所有**非 user-input whitelist** 的 Drift 表
/// `DROP` 後重建。對 app 而言這是可接受的——那些都是 derived data，隔天
/// syncer 重抓即可。對 `tool/calibration.db` 卻是**九年歷史當場歸零**：
/// 310 萬筆價格 + 250 萬筆法人，重抓要數十小時而且 FinMind 免費配額根本
/// 不夠。
///
/// 2026-07-18 實測（在副本上）：`calibration.db` 存的 fingerprint 是
/// `stage5b-dual-horizon-2026-04-11`、code 已是
/// `stage5b-news-mention-daily-2026-07-15`，開一次 tool 之後
/// `daily_price` / `stock_master` / `daily_institutional` 全部變 0 列。
/// 檔案大小不變（freelist 未回收），**從外觀完全看不出資料已經沒了**。
///
/// 修法不是在這裡自動 reset，而是要人工確認 schema 差異後補齊 + 更新
/// fingerprint（見錯誤訊息內的指引）。自動化這件事等於把「無聲毀資料」
/// 從一種路徑換到另一種。
String? _checkSchemaFingerprint(String dbPath) {
  final db = sqlite3.open(dbPath, mode: OpenMode.readOnly);
  try {
    final hasTable = db.select(
      "SELECT name FROM sqlite_master WHERE type='table' "
      "AND name='_drift_schema_fingerprint'",
    );
    // 沒有 fingerprint 表 = 這個 DB 還沒被現行機制管理過，交給
    // AppDatabase 自己初始化（它會走 `stored == null` 的 else 分支、只寫入
    // 不 drop）。
    if (hasTable.isEmpty) return null;

    final rows = db.select(
      'SELECT value FROM _drift_schema_fingerprint WHERE id = 1',
    );
    if (rows.isEmpty) return null;

    final stored = rows.first['value'] as String?;
    if (stored == null || stored == appSchemaFingerprint) return null;

    return '''
❌ Schema fingerprint 不符 — 已中止，未開啟 DB。
   DB   : $dbPath
   stored  = $stored
   expected= $appSchemaFingerprint

   直接開啟會觸發 AppDatabase 的 schema reset：所有非 user-input 表
   （daily_price / stock_master / daily_institutional / day_trading ...）
   會被 DROP 重建，歷史資料全數消失且檔案大小不變、事後難以察覺。

💡 處理方式：
   1. 先備份：sqlite3 "file:$dbPath?mode=ro" "VACUUM INTO '<backup>.db'"
   2. 比對 schema 差異（對照一個用現行 code 新建的空 DB）：
      SELECT type,name,sql FROM sqlite_master WHERE name NOT LIKE 'sqlite_%';
   3. 差異若只是「新增表 / 新增索引」，手動補上該表與索引後執行：
      UPDATE _drift_schema_fingerprint SET value='$appSchemaFingerprint' WHERE id=1;
   4. 若有既存表的欄位變動，必須先 ALTER TABLE 對齊再更新 fingerprint。
''';
  } finally {
    db.close();
  }
}

// ============================================================================
// CLI arg parsing
// ============================================================================

BackfillConfig? _parseArgs(List<String> args) {
  String dbPath = 'tool/calibration.db';
  int years = 2;
  String? finMindToken;
  List<String>? symbolsWhitelist;
  var dryRun = false;
  DateTime? startDateOverride;
  DateTime? endDateOverride;
  var pricesViaFinMind = false;
  var skipFundamentals = false;
  var skipDayTrading = false;
  var onlyDayTrading = false;
  var dayTradingMaxDaysPerRun = BackfillConfig.defaultDayTradingMaxDaysPerRun;

  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    switch (arg) {
      case '--db':
        if (i + 1 >= args.length) return null;
        dbPath = args[++i];
      case '--skip-day-trading':
        skipDayTrading = true;
      case '--only-day-trading':
        onlyDayTrading = true;
      case '--day-trading-max-days':
        if (i + 1 >= args.length) return null;
        final parsed = int.tryParse(args[++i]);
        if (parsed == null || parsed < 0) {
          stderr.writeln('❌ Invalid --day-trading-max-days: must be >= 0');
          return null;
        }
        dayTradingMaxDaysPerRun = parsed;
      case '--prices-via-finmind':
        // 歷史回補必用：STOCK_DAY_ALL batch 已不支援歷史日期
        pricesViaFinMind = true;
      case '--skip-fundamentals':
        skipFundamentals = true;
      case '--years':
        if (i + 1 >= args.length) return null;
        final parsed = int.tryParse(args[++i]);
        if (parsed == null || parsed < 1) {
          stderr.writeln('❌ Invalid --years: must be positive integer');
          return null;
        }
        years = parsed;
      case '--start-date':
        if (i + 1 >= args.length) return null;
        startDateOverride = DateTime.tryParse(args[++i]);
        if (startDateOverride == null) {
          stderr.writeln('❌ Invalid --start-date: expected YYYY-MM-DD');
          return null;
        }
      case '--end-date':
        if (i + 1 >= args.length) return null;
        endDateOverride = DateTime.tryParse(args[++i]);
        if (endDateOverride == null) {
          stderr.writeln('❌ Invalid --end-date: expected YYYY-MM-DD');
          return null;
        }
      case '--finmind-token':
        if (i + 1 >= args.length) return null;
        finMindToken = args[++i];
      case '--symbols':
        if (i + 1 >= args.length) return null;
        symbolsWhitelist = args[++i]
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList();
        if (symbolsWhitelist.isEmpty) symbolsWhitelist = null;
      case '--dry-run':
        dryRun = true;
      case '--help' || '-h':
        return null;
      default:
        stderr.writeln('❌ Unknown arg: $arg');
        return null;
    }
  }

  if (onlyDayTrading && skipDayTrading) {
    stderr.writeln('❌ --only-day-trading 與 --skip-day-trading 互斥');
    return null;
  }

  // Token 優先順序：CLI flag > env var
  finMindToken ??= Platform.environment['FINMIND_TOKEN'];
  // --only-day-trading 全程只打 TWSE TWTB4U，不碰 FinMind → 不強制要 token。
  if ((finMindToken == null || finMindToken.isEmpty) && !onlyDayTrading) {
    stderr.writeln(
      '❌ FinMind token required. Use --finmind-token <token> or set '
      'FINMIND_TOKEN env var.',
    );
    return null;
  }
  finMindToken ??= '';

  // start/end override 健全性檢查
  if (startDateOverride != null &&
      endDateOverride != null &&
      !startDateOverride.isBefore(endDateOverride)) {
    stderr.writeln('❌ --start-date 必須早於 --end-date');
    return null;
  }

  // env var override 讓你在不改 code 下實驗 rate limit 容忍度
  final delayOverride = Platform.environment['BACKFILL_INTER_DAY_DELAY_MS'];
  final interDayDelayMs = delayOverride != null
      ? (int.tryParse(delayOverride) ?? 5000)
      : 5000;

  return BackfillConfig(
    dbPath: dbPath,
    years: years,
    finMindToken: finMindToken,
    symbolsWhitelist: symbolsWhitelist,
    dryRun: dryRun,
    interDayDelayMs: interDayDelayMs,
    startDateOverride: startDateOverride,
    endDateOverride: endDateOverride,
    pricesViaFinMind: pricesViaFinMind,
    skipFundamentals: skipFundamentals,
    skipDayTrading: skipDayTrading,
    onlyDayTrading: onlyDayTrading,
    dayTradingMaxDaysPerRun: dayTradingMaxDaysPerRun,
  );
}

void _printUsage(IOSink sink) {
  sink.writeln(
    'Usage: dart run tool/backfill.dart '
    '[--db <path>] [--years <N>] [--finmind-token <token>] '
    '[--symbols <csv>] [--dry-run] '
    '[--skip-day-trading | --only-day-trading] [--day-trading-max-days <N>]',
  );
  sink.writeln('');
  sink.writeln('Historical data backfill for Stage 4 calibration.');
  sink.writeln('');
  sink.writeln('Options:');
  sink.writeln(
    '  --db <path>           SQLite file path (default: tool/calibration.db)',
  );
  sink.writeln('  --years <N>           Lookback years (default: 2)');
  sink.writeln(
    '  --start-date <date>   Explicit start YYYY-MM-DD (overrides --years)',
  );
  sink.writeln(
    '  --end-date <date>     Explicit end YYYY-MM-DD (default: now)',
  );
  sink.writeln(
    '  --prices-via-finmind  Historical prices via FinMind per-symbol '
    '(required\n'
    '                        for history; STOCK_DAY_ALL batch no longer serves\n'
    '                        historical dates)',
  );
  sink.writeln(
    '  --finmind-token       FinMind API token (or set FINMIND_TOKEN env var)',
  );
  sink.writeln(
    '  --symbols <csv>       Whitelist symbols, e.g. "2330,2317,2454"',
  );
  sink.writeln(
    '  --skip-fundamentals   Skip revenue/financial/valuation phases',
  );
  sink.writeln('  --only-day-trading    Run only the day_trading phase');
  sink.writeln(
    '  --day-trading-max-days <N>  Cap day_trading backfill days per run '
    '(0 = no cap)',
  );
  sink.writeln('  --dry-run             Print plan without fetching');
  sink.writeln('  --help, -h            Show this help');
}

/// 依市場別分組的 symbol 子集
class _MarketPartition {
  const _MarketPartition({required this.twse, required this.tpex});
  final List<String> twse;
  final List<String> tpex;
}

// ============================================================================
// Formatting helpers
// ============================================================================

String _formatDate(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

String _formatDuration(Duration d) {
  if (d.inHours > 0) {
    return '${d.inHours}h${d.inMinutes.remainder(60)}m';
  } else if (d.inMinutes > 0) {
    return '${d.inMinutes}m${d.inSeconds.remainder(60)}s';
  } else {
    return '${d.inSeconds}s';
  }
}
