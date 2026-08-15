import 'package:collection/collection.dart';
import 'package:daredevil/core/constants/fundamental_decay_groups.dart';

import 'package:daredevil/core/constants/calibrated_scores/calibrated_score_context.dart';
import 'package:daredevil/core/constants/calibrated_scores/horizon.dart';
import 'package:daredevil/core/constants/rule_params.dart';
import 'package:daredevil/core/utils/logger.dart';
import 'package:daredevil/domain/models/models.dart';
import 'package:daredevil/domain/services/rule_registry.dart';
import 'package:daredevil/domain/services/rules/stock_rules.dart';

/// 股票分析規則引擎
///
/// 使用策略模式（Strategy Pattern）對股票資料套用一系列 [StockRule] 規則
class RuleEngine {
  /// 建立規則引擎，可選擇傳入自訂規則
  ///
  /// 若提供 [customRules]，則僅使用該規則集；否則載入預設規則集
  RuleEngine({List<StockRule>? customRules}) {
    _rules.addAll(customRules ?? RuleRegistry.defaultRules);
  }

  final List<StockRule> _rules = [];

  /// Mutex groups — 同 group 內的規則視為「同一個面向的訊號」，只保留分數最高的一條
  ///
  /// 動機：部分規則定義上彼此重疊（例如放量突破會同時觸發 VOLUME_SPIKE、PRICE_SPIKE、
  /// TECH_BREAKOUT、HIGH_VOLUME_BREAKOUT），若全部累加會 double-count 導致分數膨脹塞
  /// 爆 cap，使 Top 20 失去區分度。用 mutex group 語義讓「同一個訊號」只計一次。
  ///
  /// 贏家決定規則：依 [TriggeredReason.score] 由高至低，group 內第一個遇到的即是贏家。
  /// 分數相同時，依 [_rules] 註冊順序（[applyMutexGroups] 用 `package:collection`
  /// 的 [mergeSort] 確保穩定排序）決定贏家 — 此行為 deterministic，由
  /// [RuleRegistry.defaultRules] 順序隱含定義。
  ///
  /// **INVARIANT**：每個 [ReasonType] 最多只能出現在**一個** group 中。違反時
  /// [_reasonToGroup] 會靜默採用「最後寫入者勝出」，新增 group 時要特別注意。
  ///
  /// ## 既有 group 規格
  ///
  /// - **momentum_breakout**：放量突破家族，同根 K 棒會同時觸發 4 條規則
  /// - **bullish_reversal_candle**：底部反轉 K 線族群（Hammer / BullishEngulfing /
  ///   MorningStar / ThreeWhiteSoldiers），都在描述「最近一根 / 三根 K 棒呈現
  ///   多方反轉」這個同一現象，加總會 over-weight，3 條同時觸發可堆到 +60
  ///   直接撞 maxScore=80
  /// - **bearish_reversal_candle**：頂部反轉 K 線族群（對稱版本），避免空方
  ///   訊號集中扣分讓篩選失準
  ///
  /// ## 刻意排除（不進 mutex）
  ///
  /// - **patternDoji / patternDojiBearish**：indecision 形態，與「明確反轉」
  ///   語意不同，可與反轉 K 線正當共存（出現後 1-2 日才常見反轉）
  /// - **patternGapUp / patternGapDown**：跳空缺口主要傳達「open vs prev close」
  ///   的隔日斷層資訊，與單日 K 棒形狀（Hammer / Engulfing）描述的是不同
  ///   訊號層，可共存
  /// - **techBreakout / techBreakdown**：突破/跌破支撐壓力，與 K 線形狀獨立
  /// - **kdGoldenCross / maAlignmentBullish 等指標訊號**：不同訊號家族（oscillator
  ///   / 趨勢），與 K 線無語意重疊
  static const Map<String, Set<ReasonType>> _mutexGroups = {
    'momentum_breakout': {
      ReasonType.techBreakout,
      ReasonType.volumeSpike,
      ReasonType.priceSpike,
      ReasonType.highVolumeBreakout,
    },
    'bullish_reversal_candle': {
      ReasonType.patternHammer,
      ReasonType.patternBullishEngulfing,
      ReasonType.patternMorningStar,
      ReasonType.patternThreeWhiteSoldiers,
    },
    'bearish_reversal_candle': {
      ReasonType.patternHangingMan,
      ReasonType.patternBearishEngulfing,
      ReasonType.patternEveningStar,
      ReasonType.patternThreeBlackCrows,
    },
    // 2026-08-15 數值稽核新增(DB 實證共現率 100% / 23%):
    // - oversold_indecision:DojiRule 的多方分支本身要求 rsi ≤ 30
    //   (rsiExtremeOversold 的觸發條件),兩者是子集關係、必然同時觸發。
    //   兩條 short 分數皆 +10 → 「RSI≤30 加一根小實體 K」這**一個**條件
    //   曾貢獻 Mode A +20 分,超過 12 分的成立門檻、直接佔用 Top-30 席位。
    // - pullback_at_support:HammerAtSupport 的位置上界(close ≤ ma20×1.06)
    //   完全包含 PullbackToMa20 的回檔帶([ma20×0.985, ma20×1.03]),
    //   是 2026-07-18 修 MA10×MA20 時沒 sweep 到的 sibling。
    'oversold_indecision': {
      ReasonType.patternDoji,
      ReasonType.rsiExtremeOversold,
    },
    'pullback_at_support': {
      ReasonType.hammerAtSupport,
      ReasonType.pullbackToMa20,
    },
  };

  /// Reverse lookup — `ReasonType → group name`，由 [_mutexGroups] 展開建構。
  ///
  /// 建構時 assert disjointness：若某 [ReasonType] 出現在 >1 group 中，會
  /// 在首次存取此 static field 時直接拋 [StateError]，防止 silent
  /// last-writer-wins。對應 docstring INVARIANT 條款。
  static final Map<ReasonType, String> _reasonToGroup = _buildReasonToGroup();

  static Map<ReasonType, String> _buildReasonToGroup() {
    final result = <ReasonType, String>{};
    for (final entry in _mutexGroups.entries) {
      for (final type in entry.value) {
        final existing = result[type];
        if (existing != null && existing != entry.key) {
          throw StateError(
            'Mutex group invariant violated: ReasonType.${type.name} '
            'appears in both "$existing" and "${entry.key}". '
            'Each ReasonType may belong to at most one mutex group.',
          );
        }
        result[type] = entry.key;
      }
    }
    return result;
  }

  /// 對股票執行所有規則並回傳**所有**觸發的原因（**未經 mutex 過濾**）
  ///
  /// Mutex 過濾改成由消費端在進入 [calculateScore] / [getTopReasons] 前
  /// **顯式**呼叫 [applyMutexGroups]，並自行決定要用哪個 `scoreOf`：
  /// - scoring 路徑（scoring_isolate / scoring_service）：每個 horizon 各
  ///   呼一次 applyMutexGroups，`scoreOf` 是 horizon-aware calibrated lookup
  ///   （設計：scoring 是 calibration 的 source of truth）
  /// - UI 路徑（getTopReasons）：呼叫端傳 `(r) => r.score`（hardcoded，
  ///   對應 design intent — UI 顯示「最強訊號」與舊行為一致）
  ///
  /// 過去 evaluateStock 直接套 hardcoded mutex，會把 calibration 永遠鎖在
  /// hardcoded 排序上 — 即使 calibration 認為 volumeSpike 在某 horizon
  /// 比 techBreakout 強，也無法贏 mutex。同時 mutex loser 規則永遠拿不到
  /// calibration sample，因為 replay_calibrator 也吃這份過濾結果。
  /// 把 mutex 延後到 score-aware 階段同時解這兩個問題。
  List<TriggeredReason> evaluateStock(AnalysisContext context, StockData data) {
    if (data.prices.isEmpty) return [];

    final triggered = <TriggeredReason>[];

    for (final rule in _rules) {
      try {
        final reason = rule.evaluate(context, data);
        if (reason != null) {
          triggered.add(reason);
        }
      } catch (e, stackTrace) {
        // 記錄規則執行失敗，但不中斷程式
        AppLogger.warning('RuleEngine', '規則 ${rule.id} 評估失敗', e, stackTrace);
      }
    }

    // 依 hardcoded 分數排序（穩定輸出順序，供下游可預期 iteration）
    //
    // `dart:core` 的 `List.sort` 為 dual-pivot Quicksort，**官方文件明文不保證
    // stable**（即同分時 tie-break 順序不固定）。`package:collection` 的
    // `mergeSort` 是 stable，分數打平時保留輸入順序 = [_rules] 註冊順序，
    // 與 [_mutexGroups] 「分數相同依註冊順序」的契約對齊。
    mergeSort<TriggeredReason>(
      triggered,
      compare: (a, b) => b.score.compareTo(a.score),
    );
    return triggered;
  }

  /// 同一 mutex group 內只保留 [scoreOf] 回傳值最高的 reason。
  ///
  /// 由呼叫端在進 [calculateScore] / [getTopReasons] 之前**顯式**呼叫；
  /// 這兩個 method 本身都不再做 mutex（pure 算術 / pure dedup）。
  /// [scoreOf] 由呼叫端提供：
  /// - scoring 路徑：horizon-aware calibrated lookup（每 horizon 各呼一次）
  /// - UI 顯示路徑：通常傳 `(r) => r.score`（hardcoded，對應 design
  ///   intent — UI 顯示「最強訊號」的可讀性比 calibration 結果更重要）
  ///
  /// 內部會 stable-sort 輸入再過濾 — 呼叫端不需先排序。
  /// 不屬於任何 group 的 reason 原樣保留。
  List<TriggeredReason> applyMutexGroups(
    List<TriggeredReason> reasons,
    int Function(TriggeredReason) scoreOf,
  ) {
    if (reasons.isEmpty) return reasons;

    // 使用 mergeSort 保證 stable：[scoreOf] 結果相同時保留輸入順序
    // (= [_rules] 註冊順序)。`dart:core` 的 `List.sort` 不保證穩定 —
    // calibrated 分數打平時 mutex 贏家可能隨 VM 飄移。
    final sorted = [...reasons];
    mergeSort<TriggeredReason>(
      sorted,
      compare: (a, b) => scoreOf(b).compareTo(scoreOf(a)),
    );

    final seenGroups = <String>{};
    final result = <TriggeredReason>[];
    for (final reason in sorted) {
      final group = _reasonToGroup[reason.type];
      if (group == null) {
        result.add(reason); // 不屬於任何 group
      } else if (seenGroups.add(group)) {
        result.add(reason); // group 內第一次遇到（scoreOf 最高），勝出
      }
      // 其他：已有該 group 贏家，跳過
    }
    return result;
  }

  /// 計算最終分數，含冷卻懲罰與上限
  ///
  /// ## Dual-horizon
  ///
  /// 此 method 必須指定 [horizon]。每個 reason 會先嘗試在
  /// [calibratedScores] 對應 horizon 的查找表中查 calibrated 值，
  /// 查無則 fallback 到 `TriggeredReason.score`（hardcoded embedded）。
  /// 呼叫端需為每支股票分別呼叫 `Horizon.short` 與 `Horizon.long` 以得到
  /// 雙 horizon 分數。
  ///
  /// [calibratedScores] 預設為 [CalibratedScoreContext.empty]，代表
  /// 「所有規則都走 fallback」— 等效 Stage 5a 行為，單元測試可省略此參數。
  ///
  /// ## 組合加成已移除
  ///
  /// 組合加成（breakout+volume、reversal+volume、institutional+combo）已於
  /// 2026-04 移除：個別規則本身已要求量能配合，再加 bonus 是 double-count，
  /// 且會讓多訊號股票全部黏在 maxScore 80 失去區分度。
  int calculateScore(
    List<TriggeredReason> reasons, {
    required Horizon horizon,
    CalibratedScoreContext calibratedScores = CalibratedScoreContext.empty,
    Map<String, double>? decayMultipliers,
    bool floorAtZero = true,
  }) {
    if (reasons.isEmpty) return 0;

    double score = 0.0;

    // 1. 累計各規則的分數 — 優先用 calibrated 值，查無則 fallback 到
    //    hardcoded `reason.score`。多空訊號透過正負分數自然抵消。
    //    [decayMultipliers]（基本面同組遞減，見
    //    [computeFundamentalDecayMultipliers]）由呼叫端顯式傳入。
    //
    // 注意：本 method 是純算術契約（sum + clamp），不做 mutex
    // 過濾。Mutex 過濾應由呼叫端（scoring_isolate / scoring_service）
    // 用 horizon-aware scoreOf 呼叫 [applyMutexGroups] 後再傳進來 —
    // 這樣 calibration 才能影響哪條 rule 贏 mutex group。
    for (final reason in reasons) {
      final code = reason.type.code;
      final calibrated = calibratedScores.lookup(horizon, code);
      final multiplier = decayMultipliers?[code] ?? 1.0;
      score += (calibrated ?? reason.score) * multiplier;
    }

    // 2. 分數範圍限制（下限 0：僅推薦做多；上限 maxScore 避免多訊號膨脹）。
    //    [floorAtZero]=false 供 scoring_pipeline 的落庫門檻取得帶正負號的
    //    raw 總分——下限 clamp 會把純空方股變 0、被門檻剪掉,掃描/風控就
    //    看不見它們(2026-07-31 審查 CRITICAL:abs 門檻曾因此淪為 no-op)。
    if (floorAtZero && score < 0) score = 0;
    if (score > RuleScores.maxScore) score = RuleScores.maxScore.toDouble();

    return score.round();
  }

  /// 基本面同組遞減係數（2026-07-10 影響分析後採用）
  ///
  /// 線性加總隱含「訊號互相獨立」，但同族基本面訊號高度相關（例：
  /// ROE 優異與 ROE 改善是同一指標的兩個角度）——不處理會讓「基本面
  /// 好」一件事重複計分（實測訊號區 21% 的股票同組疊 ≥2 條）。
  ///
  /// 對 [FundamentalDecayGroups] 三組（價值/營收/獲利）內的**正分**
  /// 訊號，按設計分數 DESC 排名給遞減係數（1.0/0.5/0.25...）。
  /// 回傳 code → 係數 map（只含被遞減影響的組員；組外訊號不入 map、
  /// 呼叫端以 1.0 對待）。排序用 hardcoded 設計分數（horizon 無關——
  /// 「證據邊際價值遞減」的語意與 horizon 無關）。
  ///
  /// **已知縫隙(INVARIANT,2026-08-01 複審)**:排序不感知三態歸零
  /// (calibratedScores.zeroedShortRules)——被歸零的規則(貢獻恆 0)仍按
  /// hardcoded 分數佔用組內 100%/50% 檔位,可能把活著的規則擠到較差
  /// 檔位,違反「歸零=無效訊號理應讓位」語意。現況不觸發純屬巧合
  /// (revenue 組唯二排名候選 YOY_SURGE/MOM_GROWTH 目前同時被歸零,組內
  /// 無活成員可擠壓)。**下次校準重跑若讓其一翻活,必須回頭處理**:
  /// 結構修法=排序候選剔除歸零者,但 multiplier 為 short/long 共用
  /// (歸零僅 short),需先拆 horizon 雙份——耦合面不小,勿一行帶過。
  Map<String, double> computeFundamentalDecayMultipliers(
    List<TriggeredReason> reasons,
  ) {
    final result = <String, double>{};
    for (final group in FundamentalDecayGroups.all) {
      final members =
          reasons.where((r) => r.score > 0 && group.contains(r.type)).toList()
            ..sort((a, b) => b.score.compareTo(a.score));
      for (var i = 0; i < members.length; i++) {
        result[members[i].type.code] = FundamentalDecayGroups.factorForRank(i);
      }
    }
    return result;
  }

  /// 取得觸發原因（去重複）供資料庫儲存與篩選
  ///
  /// 依 description 去重複（每條規則產生唯一描述），保留所有不同規則的觸發結果。
  /// 例如同為 institutionalBuy 類型的「外資連續買超」和「法人由賣轉買」都會被保留。
  /// UI 層自行使用 .take(2) 或 .take(3) 控制顯示數量。
  List<TriggeredReason> getTopReasons(List<TriggeredReason> reasons) {
    if (reasons.isEmpty) return [];

    // 依 description 去重複，同一規則不會產生相同描述。
    // 注意：本 method 不做 mutex 過濾 — 呼叫端如果需要先過濾 mutex 應該
    // 顯式呼 [applyMutexGroups]。把職責分開讓單元測試各自獨立。
    final seenDescriptions = <String>{};
    final result = <TriggeredReason>[];

    for (final r in reasons) {
      if (seenDescriptions.add(r.description)) {
        result.add(r);
      }
    }

    return result;
  }
}
