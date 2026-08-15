import 'package:drift/drift.dart';

import 'package:daredevil/data/database/tables/stock_master.dart';

/// 每日分析結果 Table（每日資料不可變）
///
/// Dual-horizon: `score` 欄位拆分為 `scoreShort` + `scoreLong`，
/// 技術分析欄位（trendState / reversalState / support / resistance）
/// 是 horizon-agnostic 仍維持單欄位。
@DataClassName('DailyAnalysisEntry')
@TableIndex(name: 'idx_daily_analysis_date', columns: {#date})
@TableIndex(name: 'idx_daily_analysis_score_short', columns: {#scoreShort})
@TableIndex(name: 'idx_daily_analysis_score_long', columns: {#scoreLong})
@TableIndex(
  name: 'idx_daily_analysis_date_score_short',
  columns: {#date, #scoreShort},
)
@TableIndex(
  name: 'idx_daily_analysis_date_score_long',
  columns: {#date, #scoreLong},
)
class DailyAnalysis extends Table {
  /// 股票代碼
  TextColumn get symbol =>
      text().references(StockMaster, #symbol, onDelete: KeyAction.cascade)();

  /// 分析日期
  DateTimeColumn get date => dateTime()();

  /// 趨勢狀態：UP（上漲）、DOWN（下跌）、RANGE（盤整）
  TextColumn get trendState => text()();

  /// 反轉狀態：NONE（無）、W2S（弱轉強）、S2W（強轉弱）
  TextColumn get reversalState => text().withDefault(const Constant('NONE'))();

  /// 支撐價位
  RealColumn get supportLevel => real().nullable()();

  /// 壓力價位
  RealColumn get resistanceLevel => real().nullable()();

  /// 短線（5 日）所有觸發規則的總分數
  RealColumn get scoreShort => real().withDefault(const Constant(0))();

  /// 長線（60 日）所有觸發規則的總分數
  RealColumn get scoreLong => real().withDefault(const Constant(0))();

  /// 分析運算時間
  DateTimeColumn get computedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {symbol, date};
}

/// 每日分析觸發原因 Table
///
/// Dual-horizon: `ruleScore` 欄位拆分為 `ruleScoreShort` +
/// `ruleScoreLong`，同一條 rule 在兩個 horizon 下的分數貢獻可能不同
/// （calibrated JSON 為空時兩者相等，走 hardcoded fallback）。
@DataClassName('DailyReasonEntry')
@TableIndex(name: 'idx_daily_reason_date', columns: {#date})
class DailyReason extends Table {
  /// 股票代碼
  TextColumn get symbol =>
      text().references(StockMaster, #symbol, onDelete: KeyAction.cascade)();

  /// 分析日期
  DateTimeColumn get date => dateTime()();

  /// 原因排序（1 = 主要、2 = 次要）
  IntColumn get rank => integer()();

  /// 原因類型代碼
  TextColumn get reasonType => text()();

  /// 證據資料（JSON 格式）
  TextColumn get evidenceJson => text()();

  /// 此規則在短線 horizon 的分數貢獻
  RealColumn get ruleScoreShort => real().withDefault(const Constant(0))();

  /// 此規則在長線 horizon 的分數貢獻
  RealColumn get ruleScoreLong => real().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {symbol, date, rank};
}

/// 規則準確度追蹤表
///
/// 記錄每條規則的歷史表現，用於計算命中率和平均報酬率。
@DataClassName('RuleAccuracyEntry')
class RuleAccuracy extends Table {
  /// 規則 ID（如 reversal_w2s）
  TextColumn get ruleId => text()();

  /// 統計週期：「N 天 + D」持有天數字串（如 5D、20D、60D）
  TextColumn get period => text()();

  /// 觸發次數
  IntColumn get triggerCount => integer().withDefault(const Constant(0))();

  /// 成功次數（N 日後上漲）
  IntColumn get successCount => integer().withDefault(const Constant(0))();

  /// 平均報酬率（%）
  RealColumn get avgReturn => real().withDefault(const Constant(0))();

  /// 觸發「日」數（distinct 觸發日期）
  ///
  /// 有效樣本量級是這個值，不是 [triggerCount]。同一天觸發的數十檔股票
  /// 幾乎共用同一個市場因子（實測 2026-07-17 全市場單日 −3.95%），
  /// 加上持有窗重疊，pooled 筆數是偽重複。
  /// 判準與 calibration 決策層的 [CalibrationThresholds.minDistinctDates]
  /// 同源 —— 該處註解早已寫明此事，只是未擴散到 app 內的顯示層。
  IntColumn get distinctDates => integer().withDefault(const Constant(0))();

  /// 最後更新時間
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {ruleId, period};
}
