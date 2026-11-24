import 'package:drift/drift.dart';

import 'package:daredevil/core/constants/calibrated_scores/horizon.dart';
import 'package:daredevil/data/database/app_database.drift.dart';
import 'package:daredevil/data/database/tables/analysis_tables.drift.dart';

/// Mode-aggregated stock score (per [ScoringMode], summed across mode rules)
class ModeStockScore {
  const ModeStockScore({
    required this.symbol,
    required this.modeScoreShort,
    required this.modeScoreLong,
  });

  final String symbol;
  final double modeScoreShort;
  final double modeScoreLong;
}

/// 每日分析、原因、推薦操作
mixin AnalysisDaoMixin on $AppDatabase {
  /// 取得指定日期的分析結果。
  ///
  /// Dual-horizon: 排序依據由 [horizon] 決定：
  /// - [Horizon.short] → `scoreShort` DESC
  /// - [Horizon.long]  → `scoreLong` DESC
  ///
  /// 之前硬寫 scoreShort 是 Stage 5b 過渡狀態；改 required 讓所有 caller
  /// 顯式選擇。
  Future<List<DailyAnalysisEntry>> getAnalysisForDate(
    DateTime date, {
    required Horizon horizon,
  }) {
    return (select(dailyAnalysis)
          ..where((t) => t.date.equals(date))
          ..orderBy([
            (t) => OrderingTerm.desc(
              horizon == Horizon.short ? t.scoreShort : t.scoreLong,
            ),
          ]))
        .get();
  }

  /// 取得股票的分析結果
  Future<DailyAnalysisEntry?> getAnalysis(String symbol, DateTime date) {
    return (select(dailyAnalysis)
          ..where((t) => t.symbol.equals(symbol))
          ..where((t) => t.date.equals(date)))
        .getSingleOrNull();
  }

  /// 新增分析結果
  Future<void> insertAnalysis(DailyAnalysisCompanion entry) {
    return into(dailyAnalysis).insertOnConflictUpdate(entry);
  }

  /// 批次取得多檔股票在指定日期的分析結果（批次查詢）
  ///
  /// 回傳 symbol -> 分析結果 的 Map
  Future<Map<String, DailyAnalysisEntry>> getAnalysesBatch(
    List<String> symbols,
    DateTime date,
  ) async {
    if (symbols.isEmpty) return {};

    final results =
        await (select(dailyAnalysis)
              ..where((t) => t.symbol.isIn(symbols))
              ..where((t) => t.date.equals(date)))
            .get();

    return {for (final analysis in results) analysis.symbol: analysis};
  }

  /// 清除指定日期的所有分析記錄
  ///
  /// 在每日更新前呼叫，確保不會有舊的分析記錄殘留
  Future<int> clearAnalysisForDate(DateTime date) {
    return (delete(dailyAnalysis)..where((t) => t.date.equals(date))).go();
  }

  // ==================================================
  // 每日原因操作
  // ==================================================

  /// 取得指定日期的全部推薦理由(不分股票)——負證據歸零觀測統計用。
  /// 吃 idx_daily_reason_date(2026-07-29 新增)。
  Future<List<DailyReasonEntry>> getAllReasonsForDate(DateTime date) {
    return (select(dailyReason)..where((t) => t.date.equals(date))).get();
  }

  /// 取得股票在指定日期的觸發原因
  Future<List<DailyReasonEntry>> getReasons(String symbol, DateTime date) {
    return (select(dailyReason)
          ..where((t) => t.symbol.equals(symbol))
          ..where((t) => t.date.equals(date))
          ..orderBy([(t) => OrderingTerm.asc(t.rank)]))
        .get();
  }

  /// Mode-based 股票分數加總（每檔股票該 mode 內所有 rule 的 score 加總）
  ///
  /// 用於 Today screen 的 3-tab Mode UI — 起漲 / 強勢 / 回檔 各自獨立排序。
  ///
  /// [reasonTypeCodes] 該 mode 內 ReasonType code 列表（UPPER_SNAKE_CASE）
  /// [date] 查詢日期
  ///
  /// 回傳每檔股票的 short / long score 加總（filter 在 mode 內的 rule）。
  /// caller 自己決定排序（現行：A/C 按 score DESC、B 按 60D 報酬 DESC，
  /// tiebreak symbol ASC——Mode C v2 起為正分機會 tab）。
  Future<List<ModeStockScore>> getModeStockScores(
    DateTime date,
    List<String> reasonTypeCodes,
  ) async {
    if (reasonTypeCodes.isEmpty) return [];

    // Drift 不直接支援 SELECT symbol, SUM, SUM, COUNT GROUP BY 的型別
    // 安全 mapping，用 selectOnly + addColumns。
    final symbolCol = dailyReason.symbol;
    final shortSum = dailyReason.ruleScoreShort.sum();
    final longSum = dailyReason.ruleScoreLong.sum();

    final query = selectOnly(dailyReason)
      ..addColumns([symbolCol, shortSum, longSum])
      ..where(dailyReason.date.equals(date))
      ..where(dailyReason.reasonType.isIn(reasonTypeCodes))
      ..groupBy([symbolCol]);

    final rows = await query.get();
    return rows
        .map(
          (row) => ModeStockScore(
            symbol: row.read(symbolCol)!,
            modeScoreShort: row.read(shortSum) ?? 0,
            modeScoreLong: row.read(longSum) ?? 0,
          ),
        )
        .toList();
  }

  /// 批次取得多檔股票在指定日期的觸發原因（批次查詢）
  ///
  /// 回傳 symbol -> 原因列表 的 Map，依 rank 排序
  Future<Map<String, List<DailyReasonEntry>>> getReasonsBatch(
    List<String> symbols,
    DateTime date,
  ) async {
    if (symbols.isEmpty) return {};

    final results =
        await (select(dailyReason)
              ..where((t) => t.symbol.isIn(symbols))
              ..where((t) => t.date.equals(date))
              ..orderBy([
                (t) => OrderingTerm.asc(t.symbol),
                (t) => OrderingTerm.asc(t.rank),
              ]))
            .get();

    // 依 symbol 分組
    final grouped = <String, List<DailyReasonEntry>>{};
    for (final entry in results) {
      grouped.putIfAbsent(entry.symbol, () => []).add(entry);
    }

    return grouped;
  }

  /// 新增原因（⚠️ production 寫入一律走 replaceReasons；本方法僅測試
  /// seeding 使用，2026-07-23 稽核確認 lib 零呼叫）
  Future<void> insertReasons(List<DailyReasonCompanion> entries) async {
    await batch((b) {
      for (final entry in entries) {
        b.insert(dailyReason, entry, mode: InsertMode.insertOrReplace);
      }
    });
  }

  /// 取代股票在指定日期的原因（原子性操作）
  Future<void> replaceReasons(
    String symbol,
    DateTime date,
    List<DailyReasonCompanion> entries,
  ) {
    return transaction(() async {
      // 刪除此 symbol/date 的既有原因
      await (delete(dailyReason)
            ..where((t) => t.symbol.equals(symbol))
            ..where((t) => t.date.equals(date)))
          .go();

      // 新增新的原因
      if (entries.isNotEmpty) {
        await batch((b) {
          for (final entry in entries) {
            b.insert(dailyReason, entry);
          }
        });
      }
    });
  }

  /// 清除指定日期的所有原因記錄
  ///
  /// 在每日更新前呼叫，確保不會有舊的原因記錄殘留
  Future<int> clearReasonsForDate(DateTime date) {
    return (delete(dailyReason)..where((t) => t.date.equals(date))).go();
  }

  // ==================================================
  // 大盤判定
  // ==================================================

  /// 評分日的大盤判定讀數；沒有存為 null
  Future<MarketRegimeEntry?> getMarketRegimeForDate(DateTime date) {
    return (select(
      marketRegime,
    )..where((t) => t.date.equals(date))).getSingleOrNull();
  }

  /// 刪掉評分日的大盤判定讀數
  Future<int> clearMarketRegimeForDate(DateTime date) {
    return (delete(marketRegime)..where((t) => t.date.equals(date))).go();
  }

  /// 寫入一筆大盤判定讀數（同一天已有的要先 [clearMarketRegimeForDate]）
  Future<void> insertMarketRegime(MarketRegimeCompanion row) {
    return into(marketRegime).insert(row);
  }
}
