import 'package:drift/drift.dart';

import 'package:daredevil/core/constants/calibrated_scores/horizon.dart';
import 'package:daredevil/core/constants/rule_params.dart';
import 'package:daredevil/core/utils/clock.dart';
import 'package:daredevil/core/utils/date_context.dart';
import 'package:daredevil/core/utils/request_deduplicator.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/data/database/dao/analysis_dao.dart';
import 'package:daredevil/domain/repositories/analysis_repository.dart';
import 'package:daredevil/domain/models/market_regime.dart';

import 'package:daredevil/core/utils/taiwan_calendar.dart';

/// 分析結果與推薦股 Repository 實作
class AnalysisRepository implements IAnalysisRepository {
  AnalysisRepository({
    required AppDatabase database,
    AppClock clock = const SystemClock(),
  }) : _db = database,
       _clock = clock;

  final AppDatabase _db;
  final AppClock _clock;

  /// Request deduplicators
  final _analysisDedup = RequestDeduplicator<DailyAnalysisEntry?>();
  final _reasonsDedup = RequestDeduplicator<List<DailyReasonEntry>>();

  // ==================================================
  // 每日分析
  // ==================================================

  /// 取得特定股票和日期的分析結果
  ///
  /// 使用 Request Deduplication 防止同時多次查詢相同股票
  @override
  Future<DailyAnalysisEntry?> getAnalysis(String symbol, DateTime date) {
    final normalizedDate = DateContext.normalize(date);
    final cacheKey = 'analysis_${symbol}_${normalizedDate.toIso8601String()}';

    return _analysisDedup.call(
      cacheKey,
      () => _db.getAnalysis(symbol, normalizedDate),
    );
  }

  /// 取得某日期的所有分析結果（內部使用）。
  ///
  /// Dual-horizon: 排序依據由 [horizon] 決定（short → scoreShort，
  /// long → scoreLong）。
  Future<List<DailyAnalysisEntry>> getAnalysesForDate(
    DateTime date, {
    required Horizon horizon,
  }) {
    return _db.getAnalysisForDate(
      DateContext.normalize(date),
      horizon: horizon,
    );
  }

  /// 儲存分析結果
  ///
  /// Dual-horizon: 接受 [scoreShort] 跟 [scoreLong] 兩個獨立分數（各 horizon
  /// 由 scoring pipeline 分別計算，可不同）。
  @override
  Future<void> saveAnalysis({
    required String symbol,
    required DateTime date,
    required String trendState,
    required String reversalState,
    double? supportLevel,
    double? resistanceLevel,
    required double scoreShort,
    required double scoreLong,
  }) {
    return _db.insertAnalysis(
      DailyAnalysisCompanion.insert(
        symbol: symbol,
        date: DateContext.normalize(date),
        trendState: trendState,
        reversalState: Value(reversalState),
        supportLevel: Value(supportLevel),
        resistanceLevel: Value(resistanceLevel),
        scoreShort: Value(scoreShort),
        scoreLong: Value(scoreLong),
      ),
    );
  }

  // ==================================================
  // 每日原因
  // ==================================================

  /// 取得股票在某日期的觸發原因
  ///
  /// 使用 Request Deduplication 防止同時多次查詢相同股票
  @override
  Future<List<DailyReasonEntry>> getReasons(String symbol, DateTime date) {
    final normalizedDate = DateContext.normalize(date);
    final cacheKey = 'reasons_${symbol}_${normalizedDate.toIso8601String()}';

    return _reasonsDedup.call(
      cacheKey,
      () => _db.getReasons(symbol, normalizedDate),
    );
  }

  /// 儲存股票的觸發原因（原子性取代既有原因）
  @override
  Future<void> saveReasons(
    String symbol,
    DateTime date,
    List<ReasonData> reasons,
  ) async {
    // 限制最大原因數
    final limitedReasons = reasons.take(RuleParams.maxReasonsPerStock).toList();
    final normalizedDate = DateContext.normalize(date);

    final entries = <DailyReasonCompanion>[];
    for (var i = 0; i < limitedReasons.length; i++) {
      final reason = limitedReasons[i];
      entries.add(
        DailyReasonCompanion.insert(
          symbol: symbol,
          date: normalizedDate,
          rank: i + 1,
          reasonType: reason.type,
          evidenceJson: reason.evidenceJson,
          // Dual-horizon：ReasonData 攜帶兩個 horizon 的分數，
          // 直接寫入各自欄位。Stage 5a placeholder JSON 為空時兩值
          // 相等（都走 fallback），calibration 上線後會分化。
          ruleScoreShort: Value(reason.scoreShort.toDouble()),
          ruleScoreLong: Value(reason.scoreLong.toDouble()),
        ),
      );
    }

    // 使用原子性取代確保一致性
    await _db.replaceReasons(symbol, normalizedDate, entries);
  }

  // ==================================================
  // 智慧日期回退
  // ==================================================

  /// 尋找最近有分析資料的日期和結果
  ///
  /// 統一的 3 天窗口 + 交易日回退邏輯，所有日期已正規化。
  @override
  Future<({DateTime targetDate, List<DailyAnalysisEntry> analyses})>
  findLatestAnalyses({required Horizon horizon}) async {
    final now = _clock.now();

    // 依序嘗試今天、昨天、前天的資料
    for (var daysAgo = 0; daysAgo <= 2; daysAgo++) {
      final date = DateContext.normalize(now.subtract(Duration(days: daysAgo)));
      final analyses = await getAnalysesForDate(date, horizon: horizon);
      if (analyses.isNotEmpty) {
        return (targetDate: date, analyses: analyses);
      }
    }

    // 若最近 3 天都無資料，嘗試前一交易日（處理連續假期）
    final prevTradingDay = TaiwanCalendar.getPreviousTradingDay(
      DateContext.normalize(now.subtract(const Duration(days: 3))),
    );
    final normalizedDate = DateContext.normalize(prevTradingDay);
    final analyses = await getAnalysesForDate(normalizedDate, horizon: horizon);
    return (targetDate: normalizedDate, analyses: analyses);
  }

  /// 尋找最近有分析資料的日期。
  /// 日期判斷與 horizon 無關（兩個 horizon 同日寫入），但 underlying
  /// `getAnalysesForDate` 仍需指定排序欄位；用 short 是 implementation
  /// detail，不影響 return 值。
  @override
  Future<DateTime?> findLatestAnalysisDate() async {
    final result = await findLatestAnalyses(horizon: Horizon.short);
    return result.analyses.isNotEmpty ? result.targetDate : null;
  }

  // ==================================================
  // 資料清理
  // ==================================================

  /// 清除指定日期的所有原因記錄
  @override
  Future<int> clearReasonsForDate(DateTime date) {
    return _db.clearReasonsForDate(DateContext.normalize(date));
  }

  /// 清除指定日期的所有分析記錄
  @override
  Future<int> clearAnalysisForDate(DateTime date) {
    return _db.clearAnalysisForDate(DateContext.normalize(date));
  }

  @override
  Future<void> replaceMarketRegimeForDate(
    DateTime date,
    MarketRegimeReading? reading,
  ) async {
    final day = DateContext.normalize(date);
    await _db.clearMarketRegimeForDate(day);
    if (reading == null) return;
    await _db.insertMarketRegime(
      MarketRegimeCompanion.insert(
        date: day,
        eligibleCount: reading.eligibleCount,
        upCount: reading.upCount,
        medianReturn: reading.medianReturn,
        isUptrend: reading.isUptrend,
        lookbackDays: reading.lookbackDays,
      ),
    );
  }

  @override
  Future<MarketRegimeReading?> getMarketRegime(DateTime date) async {
    final row = await _db.getMarketRegimeForDate(DateContext.normalize(date));
    if (row == null) return null;
    return MarketRegimeReading(
      eligibleCount: row.eligibleCount,
      upCount: row.upCount,
      medianReturn: row.medianReturn,
      isUptrend: row.isUptrend,
      lookbackDays: row.lookbackDays,
    );
  }

  @override
  Future<List<ModeStockScore>> getModeStockScores(
    DateTime date,
    List<String> reasonTypeCodes,
  ) {
    return _db.getModeStockScores(DateContext.normalize(date), reasonTypeCodes);
  }

  @override
  Future<T> runInTransaction<T>(Future<T> Function() action) {
    return _db.transaction(() => action());
  }
}
