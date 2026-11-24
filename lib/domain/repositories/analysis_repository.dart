import 'package:daredevil/core/constants/calibrated_scores/horizon.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/data/database/dao/analysis_dao.dart';
import 'package:daredevil/domain/models/market_regime.dart';

/// 分析結果與推薦的資料儲存庫介面
///
/// 支援測試時的 Mock 及不同實作（如本機資料庫、遠端 API、記憶體快取）
abstract class IAnalysisRepository {
  // ==================================================
  // 每日分析
  // ==================================================

  /// 取得特定股票在指定日期的分析結果
  Future<DailyAnalysisEntry?> getAnalysis(String symbol, DateTime date);

  /// 儲存分析結果
  ///
  /// Dual-horizon: [scoreShort] 與 [scoreLong] 取代舊的單一 `score`，由 scoring
  /// pipeline 各 horizon 分別計算（兩者可不同）。
  Future<void> saveAnalysis({
    required String symbol,
    required DateTime date,
    required String trendState,
    required String reversalState,
    double? supportLevel,
    double? resistanceLevel,
    required double scoreShort,
    required double scoreLong,
  });

  // ==================================================
  // 每日原因
  // ==================================================

  /// 取得特定股票在指定日期的推薦原因
  Future<List<DailyReasonEntry>> getReasons(String symbol, DateTime date);

  /// 儲存股票的推薦原因（原子性取代現有原因）
  Future<void> saveReasons(
    String symbol,
    DateTime date,
    List<ReasonData> reasons,
  );

  // ==================================================
  // 智慧日期回退
  // ==================================================

  /// 尋找最近有分析資料的日期和結果。
  ///
  /// 依序嘗試今天、昨天、前天，若 3 天都無資料則回退至前一交易日。
  /// 所有日期已正規化，安全用於資料庫查詢。
  ///
  /// Dual-horizon: [horizon] 決定 analyses 排序欄位（short → scoreShort，
  /// long → scoreLong）。
  Future<({DateTime targetDate, List<DailyAnalysisEntry> analyses})>
  findLatestAnalyses({required Horizon horizon});

  /// 尋找最近有分析資料的日期
  ///
  /// 若完全無資料則回傳 null。
  Future<DateTime?> findLatestAnalysisDate();

  // ==================================================
  // 資料清理
  // ==================================================

  /// 清除指定日期的所有原因記錄
  ///
  /// 在每日評分前呼叫，確保不會有舊的原因記錄殘留。
  /// 這解決了當股票不再觸發任何規則時，舊原因仍保留在資料庫的問題。
  Future<int> clearReasonsForDate(DateTime date);

  /// 清除指定日期的所有分析記錄
  ///
  /// 在每日評分前呼叫，確保不會有舊的分析記錄殘留。
  Future<int> clearAnalysisForDate(DateTime date);

  // ==================================================
  // 大盤判定
  // ==================================================

  /// 換掉 [date] 的大盤判定讀數：先刪，[reading] 不是 null 才寫入。評分在
  /// 寫入當天分析的同一個 transaction 裡呼叫
  Future<void> replaceMarketRegimeForDate(
    DateTime date,
    MarketRegimeReading? reading,
  );

  /// [date] 的大盤判定讀數；沒有存為 null
  Future<MarketRegimeReading?> getMarketRegime(DateTime date);

  // ==================================================
  // UI 用組合查詢
  // ==================================================

  /// Mode-based 股票分數加總
  ///
  /// 用於 Today screen 3-tab Mode UI。caller 傳入該 mode 內的所有 reason
  /// type code 列表（從 [ScoringMode] 分類取得），DAO 內 SQL aggregate
  /// 加總每檔股票的 mode-internal score。
  Future<List<ModeStockScore>> getModeStockScores(
    DateTime date,
    List<String> reasonTypeCodes,
  );

  // ==================================================
  // 交易控制
  // ==================================================

  /// 在單一資料庫 transaction 內執行回呼
  Future<T> runInTransaction<T>(Future<T> Function() action);
}

/// 儲存推薦原因的資料類別
///
/// Dual-horizon: [scoreShort] 與 [scoreLong] 分別代表此規則在
/// 短線 / 長線 horizon 下的 calibrated / fallback 分數。scoring pipeline
/// 在 isolate 內對每一條 reason 都會查兩個 horizon 的分數後一併放進此 DTO。
class ReasonData {
  const ReasonData({
    required this.type,
    required this.evidenceJson,
    required this.scoreShort,
    required this.scoreLong,
  });

  final String type;
  final String evidenceJson;
  final int scoreShort;
  final int scoreLong;
}
