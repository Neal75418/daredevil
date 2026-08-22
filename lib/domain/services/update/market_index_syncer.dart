import 'package:drift/drift.dart';

import 'package:daredevil/core/constants/api_config.dart';
import 'package:daredevil/core/constants/market_index_names.dart';
import 'package:daredevil/core/exceptions/app_exception.dart';
import 'package:daredevil/core/utils/clock.dart';
import 'package:daredevil/core/utils/date_context.dart';
import 'package:daredevil/core/utils/logger.dart';
import 'package:daredevil/core/utils/taiwan_calendar.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/data/models/extensions/dto_extensions.dart';
import 'package:daredevil/data/remote/finmind_client.dart';
import 'package:daredevil/data/remote/tpex_client.dart';
import 'package:daredevil/data/remote/twse_client.dart';

/// 大盤指數歷史同步器
///
/// 從 TWSE MI_INDEX API 取得指數資料，篩選 Dashboard 重點指數後寫入 MarketIndex 表。
/// 供大盤總覽走勢圖與大盤位階（MA20/MA60 乖離）使用。
///
/// - [sync] 同步當日資料，資料不足時自動觸發 [backfill]；同步後一律嘗試
///   [backfillDeepHistory]（fail-safe，見其 doc）。
/// - [backfill] 回補近 45 天歷史，確保走勢圖至少有 ~20 個交易日的資料點。
/// - [backfillDeepHistory] 分批回補至 ~370 天（~250 交易日）深度，解鎖
///   大盤位階所需的 MA60（60 交易日）長窗——DB 清空後只剩近期 API 回應窗
///   （~42 天），不足 MA60，且僅靠每日累積需近一年才能自然補齊。
/// - [backfillTpexIndexHistory] 櫃買指數同深度回補（FinMind 單次呼叫，
///   官方 TPEx 端點無歷史查詢能力）。
///
/// ## 已知邊界：深度回補內部缺口不重訪（設計接受，非缺陷）
///
/// [backfillDeepHistory] 由新至舊單向走訪，單日遇空回應或例外時僅跳過該日、
/// 不中斷整體回補（見 [_fetchAndUpsertDates] 的「其餘例外」分支）。下次執行
/// 時的起點是 DB 現有最舊 [MarketIndexNames.taiex] 列（「最早錨點」），只會
/// 繼續往比錨點更舊的方向走——錨點以內（比錨點新）曾被跳過的日期不會被
/// 重新嘗試，除非 DB 整表清空重建（如 schema fingerprint 不符觸發的全清；
/// `market_index` 不在 `AppDatabase._userInputTableNames` whitelist 內）。
///
/// 對真正休市日（本就無資料可補）此行為正確；但對開發中一次性 API 失敗
/// （單次逾時、偶發 5xx 等），會在指數歷史留下永久小洞。此為可接受的邊界：
/// MA20/MA60 乖離計算基於 DB 現有列本身，並非強制要求連續交易日窗，少數
/// 缺口不影響代表性。
class MarketIndexSyncer {
  const MarketIndexSyncer({
    required AppDatabase database,
    required TwseClient twseClient,
    TpexClient? tpexClient,
    FinMindClient? finMindClient,
    AppClock clock = const SystemClock(),
    Duration requestDelay = const Duration(
      milliseconds: ApiConfig.syncerBatchDelayMs,
    ),
  }) : _db = database,
       _twse = twseClient,
       _tpex = tpexClient,
       _finMind = finMindClient,
       _clock = clock,
       _requestDelay = requestDelay;

  final AppDatabase _db;
  final TwseClient _twse;
  final TpexClient? _tpex;
  final FinMindClient? _finMind;
  final AppClock _clock;

  /// DB 中指數筆數低於此值時，自動觸發回補
  ///
  /// 只需 ~20 個交易日供 Dashboard 走勢圖。曾為「相對強度 RS」拉到 200（~1 年深度），
  /// 但 RS 已驗證無 edge 取消，且 200 會在 force re-sync 觸發 365 天逐日 TWSE 回補
  /// burst → 撞 TWSE 反爬限流（redirect loop）→ 中止同步。已回退。
  static const _backfillThreshold = 20;

  /// 回補天數（日曆天，包含非交易日）。45 ≈ ~20 個交易日，足夠走勢圖。
  /// 逐日查 TWSE MI_INDEX（免費、含加權與各產業類指數），不耗 FinMind 配額。
  static const _backfillCalendarDays = 45;

  /// 查詢 DB 時額外加入的緩衝天數，確保不遺漏邊界資料
  static const _queryBufferDays = 10;

  /// 觸發回補判斷時查詢的歷史天數
  static const _historyCheckDays = 30;

  /// API 請求間隔，避免 TWSE rate limit（可由建構子覆寫，測試用 [Duration.zero]）
  final Duration _requestDelay;

  /// 同步當日大盤指數至 DB
  ///
  /// 僅同步 Dashboard 需要的重點指數（MarketIndexNames.dashboardIndices，
  /// 現為 8 個），回傳寫入筆數。
  /// 同步後若 DB 資料不足 [_backfillThreshold] 筆，自動觸發歷史回補。
  Future<int> sync() async {
    var synced = 0;

    try {
      final indices = await _twse.getMarketIndices();

      if (indices.isNotEmpty) {
        final companions = _filterAndConvert(indices, _clock.now());
        if (companions.isNotEmpty) {
          await _db.upsertMarketIndices(companions);
          synced = companions.length;
          AppLogger.info('MarketIndexSyncer', 'TWSE 指數同步完成: $synced 筆');
        }
      } else {
        AppLogger.debug('MarketIndexSyncer', '無 TWSE 指數資料可同步（非交易日或盤中）');
      }
    } on RateLimitException {
      rethrow;
    } on NetworkException {
      rethrow;
    } catch (e) {
      AppLogger.warning('MarketIndexSyncer', 'TWSE 指數同步失敗', e);
    }

    // 同步 TPEx 櫃買指數（OpenAPI 回傳近月歷史，一次寫入）
    if (_tpex != null) {
      try {
        final tpexIndices = await _tpex.getTpexIndex();
        if (tpexIndices.isNotEmpty) {
          final companions = tpexIndices
              .map((idx) => idx.toDatabaseCompanion())
              .toList();
          await _db.upsertMarketIndices(companions);
          synced += companions.length;
          AppLogger.info(
            'MarketIndexSyncer',
            'TPEx 指數同步完成: ${companions.length} 筆',
          );
        }
      } on RateLimitException {
        rethrow;
      } on NetworkException {
        rethrow;
      } catch (e) {
        AppLogger.warning('MarketIndexSyncer', 'TPEx 指數同步失敗', e);
      }
    }

    // 同步 FinMind 含息報酬指數
    if (_finMind != null) {
      try {
        final triData = await _finMind.getTotalReturnIndex();
        if (triData.length >= 2) {
          final companions = _convertTotalReturnIndex(triData);
          if (companions.isNotEmpty) {
            await _db.upsertMarketIndices(companions);
            synced += companions.length;
            AppLogger.info(
              'MarketIndexSyncer',
              '含息報酬指數同步完成: ${companions.length} 筆',
            );
          }
        }
      } on RateLimitException {
        rethrow;
      } on NetworkException {
        rethrow;
      } catch (e) {
        AppLogger.warning('MarketIndexSyncer', '含息報酬指數同步失敗', e);
      }
    }

    // 無論今日同步是否成功，都檢查是否需要歷史回補
    await _backfillIfNeeded();

    // 深度回補（解鎖大盤位階 MA60 長窗深度）：完全 fail-safe，任何例外
    // （含 RateLimitException / NetworkException）皆不影響當日同步結果，
    // 也不設 ctx.rateLimitedAbort（見 backfillDeepHistory doc）。
    try {
      await backfillDeepHistory();
    } catch (e) {
      AppLogger.warning('MarketIndexSyncer', '指數深度回補失敗，不影響當日同步', e);
    }

    // 櫃買指數歷史一次性回補（同上 fail-safe 慣例）
    try {
      await backfillTpexIndexHistory();
    } catch (e) {
      AppLogger.warning('MarketIndexSyncer', '櫃買指數歷史回補失敗，不影響當日同步', e);
    }

    return synced;
  }

  /// 櫃買指數歷史一次性回補（解鎖櫃買位階 MA60 所需深度）
  ///
  /// TPEx 官方 OpenAPI 不支援日期參數、只回傳近月資料（見
  /// [backfillDeepHistory] doc 的端點調查註記）——過去只能靠每日同步
  /// 自然累積（~2 個多月才夠 MA60）。FinMind `TaiwanStockPrice` 以
  /// `TPEx` 為 data_id 可**一次**拉整年日線，且數值與官方 TPEx OpenAPI
  /// 分毫不差（2026-07-22 實測 368.53/381.96 逐筆吻合）。
  ///
  /// 配額：整段回補＝**1 次** FinMind 呼叫；最早一筆達
  /// [ApiConfig.indexBackfillTargetCalendarDays] 深度後前置檢查短路 →
  /// 穩態零呼叫。漲跌／漲跌幅由相鄰收盤推算（FinMind 該資料集無
  /// spread 欄位可信賴），首筆無前日基期故略過。
  ///
  /// Idempotent：(date, name) UNIQUE upsert，與官方來源同日重複寫入
  /// 無害（數值一致）。例外一律往上拋，由 [sync] 的 fail-soft
  /// try/catch 吸收（與 [backfillDeepHistory] 同慣例）。
  Future<int> backfillTpexIndexHistory() async {
    final finMind = _finMind;
    if (finMind == null) return 0;
    final now = _clock.now();

    final existing = await _db.getIndexHistoryBatch(
      [MarketIndexNames.tpexIndex],
      days: ApiConfig.indexBackfillTargetCalendarDays + _queryBufferDays,
      now: now,
    );
    final rows = existing[MarketIndexNames.tpexIndex] ?? const [];
    final targetDay = DateContext.normalize(
      now.subtract(
        const Duration(days: ApiConfig.indexBackfillTargetCalendarDays),
      ),
    );
    if (rows.isNotEmpty &&
        !DateContext.normalize(rows.first.date).isAfter(targetDay)) {
      AppLogger.debug('MarketIndexSyncer', '櫃買指數歷史已達目標深度，略過');
      return 0;
    }

    final prices = await finMind.getDailyPrices(
      stockId: 'TPEx',
      startDate: DateContext.formatYmd(targetDay),
      endDate: DateContext.formatYmd(now),
    );
    final valid = prices.where((p) => p.close != null).toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    if (valid.length < 2) {
      AppLogger.warning(
        'MarketIndexSyncer',
        '櫃買指數歷史回補: FinMind 回應不足（${valid.length} 筆），略過',
      );
      return 0;
    }

    final companions = <MarketIndexCompanion>[];
    for (var i = 1; i < valid.length; i++) {
      final prevClose = valid[i - 1].close!;
      final cur = valid[i];
      if (prevClose == 0) continue;
      final change = cur.close! - prevClose;
      companions.add(
        MarketIndexCompanion.insert(
          date: DateTime.parse(cur.date),
          name: MarketIndexNames.tpexIndex,
          close: cur.close!,
          change: change,
          changePercent: change / prevClose * 100,
        ),
      );
    }
    await _db.upsertMarketIndices(companions);
    AppLogger.info(
      'MarketIndexSyncer',
      '櫃買指數歷史回補完成: ${companions.length} 筆（1 次 API 呼叫）',
    );
    return companions.length;
  }

  /// 回補近 [_backfillCalendarDays] 天的歷史指數資料
  ///
  /// 先查詢 DB 已有的日期以跳過重複呼叫，遇到 API 限流時提早中止。
  /// 回傳總寫入筆數。
  Future<int> backfill() async {
    final now = _clock.now();

    // 查詢 DB 已有的指數日期，避免重複呼叫 API
    final existingHistory = await _db.getIndexHistoryBatch(
      MarketIndexNames.dashboardIndices,
      days: _backfillCalendarDays + _queryBufferDays,
      now: now,
    );
    final existingDates = <String>{};
    for (final entries in existingHistory.values) {
      for (final entry in entries) {
        existingDates.add(
          '${entry.date.year}-${entry.date.month}-${entry.date.day}',
        );
      }
    }

    // 計算需要回補的交易日
    final datesToFetch = <DateTime>[];
    for (var i = 1; i <= _backfillCalendarDays; i++) {
      final date = now.subtract(Duration(days: i));
      if (!TaiwanCalendar.isTradingDay(date)) continue;
      final key = '${date.year}-${date.month}-${date.day}';
      if (existingDates.contains(key)) continue;
      datesToFetch.add(date);
    }

    if (datesToFetch.isEmpty) {
      AppLogger.info('MarketIndexSyncer', '歷史回補: DB 已有所有交易日資料，跳過');
      return 0;
    }

    AppLogger.info(
      'MarketIndexSyncer',
      '開始歷史回補: ${datesToFetch.length} 個交易日需補（已有 ${existingDates.length} 日）',
    );

    final (totalInserted, apiCalls) = await _fetchAndUpsertDates(
      datesToFetch,
      '回補',
    );

    AppLogger.info(
      'MarketIndexSyncer',
      '歷史回補完成: $totalInserted 筆 ($apiCalls 次 API 呼叫)',
    );
    return totalInserted;
  }

  /// 深度回補指數歷史，解鎖大盤位階（MA60）所需的長窗深度
  ///
  /// 從 DB 目前最早的 [MarketIndexNames.taiex] 資料往前一天開始往回走，
  /// 逐日呼叫 TWSE MI_INDEX（含 date 參數），跳過非交易日與已覆蓋日期，
  /// 直到達成 [ApiConfig.indexBackfillTargetCalendarDays] 目標深度或用完
  /// 本次上限 [ApiConfig.indexBackfillMaxDaysPerRun]。
  ///
  /// 所有 dashboardIndices 皆由同一次 TWSE 回應寫入，日期集合與加權指數
  /// 一致，故以它為代表判斷回補起點與既有覆蓋，無需逐指數查詢。
  ///
  /// **僅 TWSE**：TPEx 櫃買指數 OpenAPI（[TpexClient.getTpexIndex]）不支援
  /// date 參數、只回傳近月資料，無法逐日回補歷史（見 class doc）。櫃買指數
  /// 的歷史深度改由 [backfillTpexIndexHistory]（FinMind，單次呼叫）承接。
  ///
  /// Idempotent：與 [backfill] 共用 (date, name) UNIQUE upsert，重複執行
  /// 安全。呼叫端（[sync]）以 try/catch 完整包裹本方法，任何例外（含
  /// [RateLimitException] / [NetworkException]）皆 fail-soft、不影響當日
  /// 同步結果——這與 [backfill] 內部「NetworkException 仍 rethrow」的
  /// 既有慣例刻意不同：深度回補是「錦上添花」的背景步驟，其例外不應
  /// 讓 `_syncAuxiliaryData` 誤判為限流而連帶中止 TDCC/股利/內部人轉讓等
  /// 其餘同步器。
  ///
  /// 回傳本次寫入筆數。
  Future<int> backfillDeepHistory() async {
    final now = _clock.now();

    final existingHistory = await _db.getIndexHistoryBatch(
      [MarketIndexNames.taiex],
      days: ApiConfig.indexBackfillTargetCalendarDays + _queryBufferDays,
      now: now,
    );
    final existingRows = existingHistory[MarketIndexNames.taiex] ?? const [];

    if (existingRows.isEmpty) {
      AppLogger.debug('MarketIndexSyncer', '指數深度回補: 尚無既有資料，待每日同步或近期回補建立起點後再回補');
      return 0;
    }

    // getIndexHistoryBatch 已依日期升冪排序，first 即最早日期
    final earliestDay = DateContext.normalize(existingRows.first.date);
    final targetDay = DateContext.normalize(
      now.subtract(
        const Duration(days: ApiConfig.indexBackfillTargetCalendarDays),
      ),
    );

    if (!earliestDay.isAfter(targetDay)) {
      AppLogger.debug(
        'MarketIndexSyncer',
        '指數深度回補: 已達目標深度 '
            '(${ApiConfig.indexBackfillTargetCalendarDays} 天)，略過',
      );
      return 0;
    }

    final existingDates = <String>{
      for (final row in existingRows)
        '${row.date.year}-${row.date.month}-${row.date.day}',
    };

    // 從既有最早日期前一天開始往回走，跳過非交易日與已覆蓋日期（後者為
    // 防禦性檢查——正常情況下不會命中，因 earliestDay 本身即既有資料的
    // 最小值，但可防護未來若資料來源改變導致的不連續缺口）。
    // 上限 ApiConfig.indexBackfillMaxDaysPerRun 個交易日／次。
    final datesToFetch = <DateTime>[];
    var remainingTradingDays = 0;
    for (
      var day = earliestDay.subtract(const Duration(days: 1));
      !day.isBefore(targetDay);
      day = day.subtract(const Duration(days: 1))
    ) {
      if (!TaiwanCalendar.isTradingDay(day)) continue;
      final key = '${day.year}-${day.month}-${day.day}';
      if (existingDates.contains(key)) continue;

      if (datesToFetch.length < ApiConfig.indexBackfillMaxDaysPerRun) {
        datesToFetch.add(day);
      } else {
        remainingTradingDays++;
      }
    }

    if (datesToFetch.isEmpty) {
      AppLogger.debug('MarketIndexSyncer', '指數深度回補: 目標窗內已無缺漏交易日，略過');
      return 0;
    }

    final (inserted, apiCalls) = await _fetchAndUpsertDates(
      datesToFetch,
      '深度回補',
    );

    // apiCalls 可能因中途限流而少於 datesToFetch.length（見
    // _fetchAndUpsertDates 的 RateLimitException 處理）；未實際嘗試的
    // 排隊日期仍算「剩餘」，否則限流中止的那次會低估剩餘量、誤導下次
    // 進度預期（2026-07-16 活體驗證：60 天排隊、50 次呼叫後撞限流中止）。
    final notAttempted = datesToFetch.length - apiCalls;
    AppLogger.info(
      'MarketIndexSyncer',
      '指數回補 $apiCalls 天（剩餘 ~${remainingTradingDays + notAttempted}）',
    );

    return inserted;
  }

  /// 逐日回補共用執行邏輯：依序呼叫 TWSE 取得指定日期指數並 upsert，
  /// 呼叫間依 [_requestDelay] 節流。
  ///
  /// - [RateLimitException]：中止迴圈但不 rethrow（best-effort 提前結束，
  ///   見 [backfill] 內原有的不對稱設計說明）。
  /// - [NetworkException]：rethrow，交由呼叫端決定是否吸收（[backfill]
  ///   任其向上傳、[backfillDeepHistory] 由 [sync] 的 try/catch 吸收）。
  /// - 其餘例外：單日略過，不中斷整體回補。
  ///
  /// 回傳 (寫入筆數, 實際 API 呼叫數)。
  Future<(int inserted, int apiCalls)> _fetchAndUpsertDates(
    List<DateTime> dates,
    String logLabel,
  ) async {
    var totalInserted = 0;
    var apiCalls = 0;

    for (final date in dates) {
      try {
        if (apiCalls > 0) {
          await Future.delayed(_requestDelay);
        }

        final indices = await _twse.getMarketIndices(date: date);
        apiCalls++;

        if (indices.isEmpty) continue;

        final companions = _filterAndConvert(indices, date);
        if (companions.isEmpty) continue;

        await _db.upsertMarketIndices(companions);
        totalInserted += companions.length;
      } on RateLimitException {
        AppLogger.warning(
          'MarketIndexSyncer',
          '指數$logLabel API 限流，中止 (已完成 $apiCalls 次呼叫)',
        );
        break;
      } on NetworkException {
        rethrow;
      } catch (e) {
        // 單日失敗不中斷整個回補
        AppLogger.debug(
          'MarketIndexSyncer',
          '指數$logLabel ${DateContext.formatYmd(date)} 失敗: $e',
        );
      }
    }

    return (totalInserted, apiCalls);
  }

  /// 檢查 DB 資料是否不足，不足則觸發回補
  Future<void> _backfillIfNeeded() async {
    final history = await _db.getIndexHistoryBatch(
      MarketIndexNames.dashboardIndices,
      days: _historyCheckDays,
    );

    // 取任一指數的筆數作為判斷依據
    final sampleCount = history.values.isEmpty
        ? 0
        : history.values.first.length;

    if (sampleCount < _backfillThreshold) {
      AppLogger.info(
        'MarketIndexSyncer',
        '指數歷史不足 ($sampleCount < $_backfillThreshold)，開始回補',
      );
      await backfill();
    }
  }

  /// 將含息報酬指數轉換為 DB companion
  ///
  /// FinMind 只回傳 date + price，需自行計算 change/changePct（前後日比較）
  List<MarketIndexCompanion> _convertTotalReturnIndex(
    List<FinMindTotalReturnIndex> data,
  ) {
    // 按日期升序排列
    final sorted = [...data]..sort((a, b) => a.date.compareTo(b.date));
    final companions = <MarketIndexCompanion>[];

    for (var i = 0; i < sorted.length; i++) {
      final item = sorted[i];
      final prevPrice = i > 0 ? sorted[i - 1].price : item.price;
      final change = item.price - prevPrice;
      final changePct = prevPrice != 0 ? (change / prevPrice) * 100 : 0.0;

      companions.add(
        MarketIndexCompanion(
          date: Value(item.date),
          name: const Value(MarketIndexNames.totalReturnIndex),
          close: Value(item.price),
          change: Value(i > 0 ? change : 0),
          changePercent: Value(i > 0 ? changePct : 0),
        ),
      );
    }

    return companions;
  }

  /// 篩選 Dashboard 重點指數並轉換為 DB companion
  ///
  /// [expectedDate] 為本次請求對應的交易日，用於日期合理性防護：
  /// 解析出的日期若與 [expectedDate] 相差超過
  /// [ApiConfig.marketIndexDateDriftToleranceDays] 天，或年份早於
  /// [ApiConfig.minSaneAdYear] / 晚於明年，視為髒資料並跳過，避免再次寫入
  /// 像 `0000-12-18` / `2026-12-18` 這類污染走勢圖與均線的列。
  List<MarketIndexCompanion> _filterAndConvert(
    List<TwseMarketIndex> indices,
    DateTime expectedDate,
  ) {
    final targetNames = MarketIndexNames.dashboardIndices.toSet();
    final filtered = indices
        .where((idx) => targetNames.contains(idx.name))
        .where((idx) => _isPlausibleDate(idx.date, expectedDate))
        .toList();

    if (filtered.isEmpty) {
      AppLogger.debug('MarketIndexSyncer', '無匹配的重點指數');
      return [];
    }

    return filtered.map((idx) => idx.toDatabaseCompanion()).toList();
  }

  /// 寫入前日期合理性防護
  ///
  /// 拒絕年份越界（< [ApiConfig.minSaneAdYear] 或 > 明年）或與 [expectedDate]
  /// 偏移過大的日期，並記錄 warning。
  bool _isPlausibleDate(DateTime date, DateTime expectedDate) {
    final maxYear = _clock.now().year + 1;
    if (date.year < ApiConfig.minSaneAdYear || date.year > maxYear) {
      AppLogger.warning(
        'MarketIndexSyncer',
        '跳過年份越界的指數日期: ${DateContext.formatYmd(date)}'
            '（合理範圍 ${ApiConfig.minSaneAdYear}~$maxYear）',
      );
      return false;
    }

    final driftDays = date.difference(expectedDate).inDays.abs();
    if (driftDays > ApiConfig.marketIndexDateDriftToleranceDays) {
      AppLogger.warning(
        'MarketIndexSyncer',
        '跳過與請求日期偏移過大的指數日期: ${DateContext.formatYmd(date)}'
            '（請求 ${DateContext.formatYmd(expectedDate)}、偏移 $driftDays 天）',
      );
      return false;
    }

    return true;
  }
}
