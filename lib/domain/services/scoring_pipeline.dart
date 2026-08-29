// 單檔評分 pipeline 的共用核心。
//
// `scoring_service.scoreStocks`（主執行緒 fallback）與
// `scoring_isolate._evaluateStocksIsolated`（isolate）過去各自複製這段
// 邏輯、靠註解「與另一路徑對齊」人肉同步——歷史上已 drift 過（M8/H-1）。
// 兩條路徑改為共用此檔的純函式：改評分邏輯只改一處。
//
// 本檔對 Flutter SDK 零依賴、無狀態，isolate 可直接使用。

import 'package:daredevil/core/constants/calibrated_scores/calibrated_score_context.dart';
import 'package:daredevil/core/constants/calibrated_scores/horizon.dart';
import 'package:daredevil/core/constants/rule_params.dart';
import 'package:daredevil/domain/services/liquidity_checker.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/domain/models/models.dart';
import 'package:daredevil/domain/services/rule_engine.dart';

/// 豁免落庫門檻的 MA 階段穿越訊號。
///
/// 這四條是 Today 頁警示 banner／自選 tag 的**唯一**資料來源(讀
/// `daily_reason`),被淨額抵銷吞掉等於工具在事件當天失明。豁免只放行
/// 「落庫」,不改分數——落庫值仍 floor 到 0,排序與 mode routing 不受影響。
const _maStageExemptTypes = {
  ReasonType.breakMa20,
  ReasonType.breakMa60,
  ReasonType.reclaimMa20,
  ReasonType.reclaimMa60,
};

/// 候選股被略過的原因分類（統計計數用）
enum CandidateSkipReason { noData, insufficientData, lowLiquidity, staleBar }

/// 資格檢查：價格資料存在、歷史長度足夠、當日 bar 新鮮、流動性合格。
///
/// 回傳 null 表示通過；通過時保證 `prices.last` 的 close/volume 非 null
/// （由 [LiquidityChecker] 的 MISSING_DATA 檢查擔保）。
///
/// [asOf] 為評分日。給定時會要求 `prices.last` 就是該日的 bar，否則回
/// [CandidateSkipReason.staleBar]。
///
/// 為什麼需要這道檢查：`batch_data_loader` 的價格窗以 `endDate = 評分日`
/// 收斂，所以 DB 缺當日 bar 時 `prices.last` 會**自動退化成前一交易日**，
/// 而本函式原本只驗 null/長度/流動性 —— 於是「昨日 K 棒算出的訊號掛上
/// 今日日期寫進 daily_analysis」可以無聲通過。這條路徑不只在 API 限流時
/// 出現：`price_repository.dart` 的「兩市場皆空」是正常回傳（不拋例外）、
/// NetworkException 也不會翻起 `rateLimitedAbort`，所以上游任何以旗標為
/// 基礎的閘門都擋不住，必須在此處以資料本身為準。
///
/// 實測：2026-07-15~07-24 共 8 個交易日、1,568 列 daily_analysis，「當日
/// 無有效價格 bar」的有 0 列 —— 健康日此檢查是 no-op，只在故障路徑生效。
///
/// [asOf] 省略時不做此檢查（向後相容；isolate 輸入的 date 可為 null）。
/// [exemptFromLiquidity] 自選股專用：跳過**量能**門檻，但 `MISSING_DATA` 仍
/// 擋（下游 `prices.last.close!` / `volume!` 依賴那道保證，放行會 null 崩潰）。
///
/// 為什麼需要：`CandidateSelector` 步驟 1 已寫明「自選清單優先（豁免流動性
/// 過濾 — 使用者主動追蹤）」，但那個豁免只作用在中位數成交額那道；本函式的
/// 單日檢查原本沒對齊，於是上游給的豁免被下游吃掉（2026-08-16 實機：2059
/// 川湖連續四天空白卡）。
///
/// 📌 當時的病灶是**股數**門檻（100 萬股）——高價股天天成交數十億卻過不了，
/// 修法侷限在自選股豁免。該門檻已於 2026-08-29 整條移除（見
/// `LiquidityChecker`），全市場都不再被它擋。本豁免仍有意義：它現在跳過的是
/// **成交額**門檻，讓使用者主動追蹤的冷門股即使日成交不足 3,000 萬也留下分析列。
CandidateSkipReason? classifyCandidate(
  List<DailyPriceEntry>? prices, {
  DateTime? asOf,
  bool exemptFromLiquidity = false,
}) {
  if (prices == null || prices.isEmpty) return CandidateSkipReason.noData;
  if (prices.length < RuleParams.swingWindow) {
    return CandidateSkipReason.insufficientData;
  }
  if (asOf != null) {
    // 逐欄比 y/m/d：DateTime 的 == 連時分秒與 isUtc 一起比，
    // 評分日帶了時間就會把整批股票誤殺。與 update_service 既有回滾
    // 比較法同源。
    final last = prices.last.date;
    if (last.year != asOf.year ||
        last.month != asOf.month ||
        last.day != asOf.day) {
      return CandidateSkipReason.staleBar;
    }
  }
  final liquidity = LiquidityChecker.checkCandidateLiquidity(prices.last);
  if (liquidity != null) {
    // MISSING_DATA 永遠不豁免——它保證的是 close/volume 非 null，不是量能
    if (liquidity == 'MISSING_DATA') return CandidateSkipReason.noData;
    if (exemptFromLiquidity) return null;
    return CandidateSkipReason.lowLiquidity;
  }
  return null;
}

/// 雙 horizon 評分核心：
///
/// 1. mutex 過濾——short / long 各自用 horizon-aware calibrated lookup
///    （H-1 fix：calculateScore 是 pure arithmetic contract、不做 mutex，
///    caller 顯式控制；calibration 因此能在不同 horizon 翻轉 mutex 贏家，
///    fallback 到 hardcoded 維持 calibration 未載入時的等效行為）
/// 2. 兩 horizon 各自 calculateScore
/// 3. 持久化門檻 = observationScoreThreshold（8）：任一 horizon ≥ 8 即保留，
///    掃描頁再分層（≥12 成立訊號 / 8–11 觀察區）。門檻兩 horizon 共用、
///    不做 per-horizon 拆分（設計 §9，YAGNI）
/// 4. UI 顯示用 hardcoded 分數另做一次 mutex（保持「design intent 強度」
///    可讀性）再取 topReasons——與 scoring 路徑的 mutex 互不影響
///
/// 回傳 null 表示兩 horizon 都低於觀察門檻、應過濾。
({
  int scoreShort,
  int scoreLong,
  List<TriggeredReason> topReasons,
  Map<String, double> decayMultipliers,
})?
scoreReasonsDualHorizon({
  required RuleEngine ruleEngine,
  required List<TriggeredReason> reasons,
  required CalibratedScoreContext calibratedScores,
}) {
  // 基本面同組遞減（對原始 reasons 算一次、兩 horizon 與持久化共用；
  // 排序用 hardcoded 設計分數、horizon 無關）
  final decayMultipliers = ruleEngine.computeFundamentalDecayMultipliers(
    reasons,
  );

  final mutedShort = ruleEngine.applyMutexGroups(
    reasons,
    (r) => calibratedScores.lookup(Horizon.short, r.type.code) ?? r.score,
  );
  final mutedLong = ruleEngine.applyMutexGroups(
    reasons,
    (r) => calibratedScores.lookup(Horizon.long, r.type.code) ?? r.score,
  );

  // floorAtZero: false —— 門檻要看「帶正負號的 raw 總分」:引擎的下限
  // clamp 會把純空方股(如只觸發跌破季線 -8)變 0 而被剪掉,掃描與風控
  // 就看不見它們。落庫值另行 floor 回 0,維持下游「分數非負」契約。
  final rawShort = ruleEngine.calculateScore(
    mutedShort,
    horizon: Horizon.short,
    calibratedScores: calibratedScores,
    decayMultipliers: decayMultipliers,
    floorAtZero: false,
  );
  final rawLong = ruleEngine.calculateScore(
    mutedLong,
    horizon: Horizon.long,
    calibratedScores: calibratedScores,
    decayMultipliers: decayMultipliers,
    floorAtZero: false,
  );

  // 門檻取絕對值(2026-07-31):純空方觸發(負總分)的股票也要落庫,
  // 否則「只跌破季線」的弱勢股在掃描器上隱形——空方風控正好在最需要
  // 它的股票上失明,rule_accuracy 觀察區也帶倖存者偏差。
  //
  // MA 階段穿越豁免(2026-08-03):上面那次修補只處理了「純空方」那一半,
  // 「正負抵銷歸零」是同一個洞的另一半——breakMa20(-8) 與
  // coilingBelowMa20(+8) 分數對稱、不在任何 mutex group,而觸發條件天生
  // 重疊(「強勢股小幅跌破月線」必然同時命中),MA 家族自己就淨額歸零。
  //
  // 落庫門檻是**掃描頁的雜訊過濾器**,不是風控訊號閘門。站回/跌破是
  // Today 頁警示 banner 與自選 tag 的唯一資料來源,不得被抵銷吞掉。
  // 實機(2026-08-03 自選 24 檔):真實 5 次穿越只報 3 次——6538 跌破月線
  // (raw=7)、8039 漲停站回月線,兩檔整檔未落庫,40% 漏報。
  final hasStageSignal = reasons.any(
    (r) => _maStageExemptTypes.contains(r.type),
  );
  if (!hasStageSignal &&
      rawShort.abs() < RuleParams.observationScoreThreshold &&
      rawLong.abs() < RuleParams.observationScoreThreshold) {
    return null;
  }
  final scoreShort = rawShort < 0 ? 0 : rawShort;
  final scoreLong = rawLong < 0 ? 0 : rawLong;

  // 落庫用 **short 的 mutex 結果**,與 [scoreShort] 同一份(2026-08-15
  // 數值稽核第 01 條)。
  //
  // 舊行為另外用 hardcoded 分數再跑一次 mutex(mutedForUi)當落庫來源,
  // 於是 calibration 把某條規則歸零時兩邊選出**不同贏家**——落庫的那份
  // 不是實際貢獻分數的那份。而 `analysis_dao.getModeStockScores` 是對
  // daily_reason 做 `SUM(rule_score_short)`,所以三個 mode tab 的分數、
  // 排名、`modeCMinScore` / `minRoutedAbsScore` 門檻**全都建在錯的那份上**。
  // 真實資料實測(2026-08-14,455 檔):69 檔落庫加總 ≠ 總分,最大差 30 分。
  //
  // 選 short 而非 long:mode tab 只消費 short(getModeStockScores)。
  // long 的加總仍可能不等於 scoreLong——long horizon 幾乎未校準
  // (JSON 40 條僅 1 條非零),兩者實務上選出同一批贏家,故不另外落庫。
  final topReasons = ruleEngine.getTopReasons(mutedShort);

  return (
    scoreShort: scoreShort,
    scoreLong: scoreLong,
    topReasons: topReasons,
    decayMultipliers: decayMultipliers,
  );
}
