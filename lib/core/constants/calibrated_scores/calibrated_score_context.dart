import 'package:meta/meta.dart';

import 'package:daredevil/core/constants/calibrated_scores/horizon.dart';

/// Scoring isolate 使用的 calibrated scores 查詢 context
///
/// 封裝兩個 horizon 的 `rule_id → calibrated score` 查找表，
/// 由主 isolate 從 [CalibratedScoresRegistry.snapshotForIsolate] 抽取後
/// 隨 [ScoringIsolateInput] 以 typed 物件直接傳入 scoring isolate。
///
/// ## 為什麼需要此 DTO
///
/// [CalibratedScoresRegistry] 是主 isolate 的 singleton，無法被
/// `Isolate.run()` spawn 的新 isolate 存取（isolate 間記憶體隔離）。
/// 在 isolate 邊界引入此 typed DTO，讓 scoring isolate 內的
/// `calculateScore` 能同步查詢兩個 horizon 的 calibrated 分數。
///
/// 設計對齊 [`CLAUDE.md`] 的 Isolate 通訊規則：
/// > 使用 typed DTO (ShareholdingData, WarningDataContext,
/// > InsiderDataContext)，避免 `Map<String, dynamic>`
///
/// ## 查詢語意
///
/// - [lookup] 回傳 `int?`：存在即為 calibrated value
/// - 查無（rule 未 calibrated 或 map 為空）回傳 null
/// - 呼叫端應 fallback 到 `TriggeredReason.score`（hardcoded embedded）
///
/// ## 空 context
///
/// 使用 [CalibratedScoreContext.empty] 產生空 context，所有查詢都會回 null，
/// 等效於「全部走 hardcoded fallback」——僅剩 registry 未載入或測試情境
/// （production JSON 自 2026-07-13 起已有校準值）。
@immutable
class CalibratedScoreContext {
  const CalibratedScoreContext({
    required this.shortScores,
    required this.longScores,
    this.zeroedShortRules = const {},
  });

  /// 短線 horizon 的 rule_id → calibrated score 查找表
  final Map<String, int> shortScores;

  /// 長線 horizon 的 rule_id → calibrated score 查找表
  final Map<String, int> longScores;

  /// 負證據歸零集(僅 short;2026-07-29 三態 lookup)。
  /// 在集內的規則 [lookup] short 回 0——歸零生效、不 fallback。
  /// 長線不套用:其校準仍是舊 absolute+pooled 產物,待重校準。
  final Set<String> zeroedShortRules;

  /// 空 context — 用於 registry 未載入、placeholder 為空、測試或 default param。
  ///
  /// 所有 [lookup] 查詢都會回 null，呼叫端自然走 fallback 路徑。
  /// 是 const 實例，可在 `const` 建構式或 default param 中直接使用。
  static const CalibratedScoreContext empty = CalibratedScoreContext(
    shortScores: <String, int>{},
    longScores: <String, int>{},
  );

  /// Horizon-aware 查詢單一規則的 calibrated score
  ///
  /// 若 [ruleId] 不在對應 horizon 的查找表中**或被 calibrated 砍到 0**，
  /// 回傳 null。呼叫端應 fallback 到 `TriggeredReason.score`（hardcoded
  /// embedded 值）。
  ///
  /// **2026-06-19**：跟 [CalibratedScoresTable.lookup] 對齊 — 0 視為 null
  /// fallback。原本 `Map<String, int>` 直接查 → score=0 回 0、把 caller 的
  /// `lookup() ?? hardcoded` fallback 永遠不會觸發；38 條被 calibrated 砍到
  /// 0 的 rule 在 scoring isolate 寫進 daily_reason 時拿 0 而非 hardcoded
  /// 正分，整個 Mode aggregator 失去 ranking 訊號。
  ///
  /// 這個 context 跟 [CalibratedScoresTable] 是兩個獨立 class（前者是 isolate
  /// DTO、後者是主 isolate 的 lookup table），fallback 邏輯必須兩邊同時修。
  int? lookup(Horizon horizon, String ruleId) {
    if (horizon == Horizon.short && zeroedShortRules.contains(ruleId)) {
      return 0; // 三態第二態:負證據歸零(caller 的 ?? hardcoded 不觸發)
    }
    final v = switch (horizon) {
      Horizon.short => shortScores[ruleId],
      Horizon.long => longScores[ruleId],
    };
    return (v == null || v == 0) ? null : v;
  }

  /// 該規則是否「經校準背書」——任一 horizon 有非零 calibrated 分數
  /// （即 [lookup] 回非 null）。用於 UI 區分「回測驗證過 edge 的訊號」
  /// vs「fallback 到 hardcoded 的啟發式訊號」。
  ///
  /// 目前僅 WEEK_52_HIGH（short）與 EPS_CONSECUTIVE_GROWTH（short+long）
  /// 為 true；其餘 ~40 條被校準砍到 0、走 hardcoded fallback → false。
  /// 2026-07-29:歸零規則 lookup 回 0(非 null),但「歸零」是校準判死、
  /// 不是背書——判斷改為「任一 horizon 有**非零**校準分」。
  bool isCalibrationBacked(String ruleId) =>
      (lookup(Horizon.short, ruleId) ?? 0) != 0 ||
      (lookup(Horizon.long, ruleId) ?? 0) != 0;

  /// 序列化為 `Map<String, dynamic>`
  ///
  /// 內部是 `Map<String, int>` 與 `Set<String>`，序列化只需把 Set 轉成 List。
  Map<String, dynamic> toMap() => {
    'shortScores': shortScores,
    'longScores': longScores,
    'zeroedShortRules': zeroedShortRules.toList(),
  };

  /// 從 [toMap] 的輸出還原
  ///
  /// 容錯處理：null 或缺失欄位會 fall back 到空 map，呼叫端的查詢
  /// 會回 null 進而 fallback 到 hardcoded。不會 throw。
  factory CalibratedScoreContext.fromMap(Map<String, dynamic> map) =>
      CalibratedScoreContext(
        shortScores: Map<String, int>.from(
          (map['shortScores'] ?? <String, int>{}) as Map,
        ),
        longScores: Map<String, int>.from(
          (map['longScores'] ?? <String, int>{}) as Map,
        ),
        zeroedShortRules: Set<String>.from(
          (map['zeroedShortRules'] ?? const <String>[]) as List,
        ),
      );
}
