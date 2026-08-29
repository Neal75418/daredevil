import 'dart:convert';
import 'package:daredevil/core/utils/number_formatter.dart';

import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

import 'package:daredevil/core/constants/analysis_params.dart';
import 'package:daredevil/core/constants/calibrated_scores/horizon.dart';
import 'package:daredevil/core/constants/rule_enums.dart';
import 'package:daredevil/core/utils/logger.dart';
import 'package:daredevil/core/utils/price_limit.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/data/remote/finmind_client.dart';
import 'package:daredevil/domain/models/stock_summary.dart';
import 'package:daredevil/domain/services/signal_confluence.dart';
import 'package:daredevil/domain/services/technical_indicator_service.dart';
import 'package:daredevil/domain/models/signal_names.dart';

/// 個股 AI 智慧分析摘要生成服務
///
/// 以模板式 NLG 將規則引擎結果轉化為結構化摘要資料，
/// 具備訊號匯流偵測、衝突偵測、加權情緒判斷與信心度評估。
///
/// 回傳 [SummaryData]（純結構化資料，不含翻譯），
/// 由 presentation 層的 [SummaryLocalizer] 負責翻譯為 [StockSummary]。
class AnalysisSummaryService {
  const AnalysisSummaryService();

  static const _confluenceDetector = SignalConfluenceDetector();

  /// 從個股分析資料生成 [SummaryData]
  ///
  /// Stage 5c dual-horizon: [horizon] 決定 service 讀取 `scoreShort` /
  /// `scoreLong` 及 `ruleScoreShort` / `ruleScoreLong`。Placeholder JSON
  /// 為空時兩個 horizon 產生相同結果（invariant：pre-calibration 期間切換
  /// 不會產生 user-visible 變化）。
  SummaryData generate({
    required DailyAnalysisEntry? analysis,
    required List<DailyReasonEntry> reasons,
    required DailyPriceEntry? latestPrice,
    required double? priceChange,
    required List<DailyInstitutionalEntry> institutionalHistory,
    required List<FinMindRevenue> revenueHistory,
    required FinMindPER? latestPER,
    required Horizon horizon,
    MarketStage? marketStage,
  }) {
    if (analysis == null && reasons.isEmpty) {
      // confidence 必須明寫：省略會吃到建構子預設的 medium，讓一檔連一條訊號
      // 都沒有的股票在畫面上標「佐證中等」。零訊號 = 佐證有限，也與
      // _calculateConfidence 在 points = 0 時的結果一致。
      return const SummaryData(
        overallParts: [LocalizableString('summary.noSignals')],
        sentiment: SummarySentiment.neutral,
        confidence: AnalysisConfidence.low,
      );
    }

    // 訊號匯流偵測
    //
    // **空方先跑**（2026-08-29 稽核 M9）：多空兩組模式共用
    // `{PE_UNDERVALUED, PBR_UNDERVALUED}` 這個 signalGroup，兩次獨立偵測會
    // 讓同一檔股票同時被判「價值投資」與「價值陷阱」。兩者同時成立時空方
    // 資訊嚴格較多（「便宜」兩邊都知道，陷阱那條額外說便宜不夠），所以由
    // 空方先消耗，多方拿不到就不合成。
    final bearishConfluence = _confluenceDetector.detect(
      reasons,
      bullish: false,
    );
    final bullishConfluence = _confluenceDetector.detect(
      reasons,
      bullish: true,
      alreadyConsumed: bearishConfluence.consumedTypes,
    );

    // 衝突偵測
    final hasConflict = _hasSignificantConflict(reasons);

    // 綜合評估（接收匯流結果）
    final overallParts = _buildOverallAssessment(
      analysis,
      latestPrice,
      priceChange,
      bullishConfluence: bullishConfluence,
      bearishConfluence: bearishConfluence,
      hasConflict: hasConflict,
      horizon: horizon,
      marketStage: marketStage,
    );

    // 匯流整合的關鍵訊號 & 風險因子
    final keySignals = _buildKeySignals(
      reasons,
      bullishConfluence,
      priceChange: priceChange,
      horizon: horizon,
    );
    final riskFactors = _buildRiskFactors(
      reasons,
      bearishConfluence,
      priceChange: priceChange,
      horizon: horizon,
    );

    // 連買/連賣天數若已由規則陳述（關鍵訊號 / 風險提示），輔助數據不得
    // 再自行從顯示窗數一次 —— 兩者窗口不同會在同一張卡上自相矛盾。
    final streakStatedByRule = reasons.any(
      (r) =>
          r.reasonType == SignalName.institutionalBuyStreak ||
          r.reasonType == SignalName.institutionalSellStreak,
    );

    final supporting = _buildSupportingData(
      institutionalHistory,
      revenueHistory,
      latestPER,
      streakStatedByRule: streakStatedByRule,
    );

    // 加權情緒（含基本面修正）
    final sentiment = _determineSentiment(
      analysis,
      reasons,
      hasConflict: hasConflict,
      revenueHistory: revenueHistory,
      latestPER: latestPER,
      horizon: horizon,
    );

    // 信心度
    final confidence = _calculateConfidence(
      reasons: reasons,
      institutionalHistory: institutionalHistory,
      revenueHistory: revenueHistory,
      latestPER: latestPER,
      hasConflict: hasConflict,
      confluenceCount:
          bullishConfluence.matchedCount + bearishConfluence.matchedCount,
      horizon: horizon,
    );

    // 輔助數據去重：同一句已在關鍵訊號／風險提示出現過就不再重複
    // （2026-07-26 實機發現，1810 和成）。
    //
    // 「本益比僅 7.6 倍，估值偏低。」在關鍵訊號與輔助數據各出現一次，
    // 一字不差——同一個 i18n key 被 `_buildSupportingData` 與規則映射
    // 各用一次。若兩處引數不一致（來源不同：規則 evidence vs latestPER），
    // 重複顯示會從冗餘升級為矛盾。一律保留關鍵訊號那份（已排序、已計分）。
    //
    // 與 streakStatedByRule 互補而非重疊：那個處理的是**不同 key 講同一
    // 件事**（institutionalBuyStreakDays vs institutionalBuyTrend），
    // key 比對抓不到；此處處理的是同一個 key 出現兩次。
    final statedKeys = {
      for (final k in keySignals) k.key,
      for (final r in riskFactors) r.key,
    };
    final dedupedSupporting = [
      for (final d in supporting)
        if (!statedKeys.contains(d.key)) d,
    ];

    return SummaryData(
      overallParts: overallParts,
      keySignals: keySignals,
      riskFactors: riskFactors,
      supportingData: dedupedSupporting,
      sentiment: sentiment,
      confidence: confidence,
      hasConflict: hasConflict,
      confluenceCount:
          bullishConfluence.matchedCount + bearishConfluence.matchedCount,
    );
  }

  // ==================================================
  // 綜合評估（含匯流敘述升級）
  // ==================================================

  List<LocalizableString> _buildOverallAssessment(
    DailyAnalysisEntry? analysis,
    DailyPriceEntry? latestPrice,
    double? priceChange, {
    required ConfluenceResult bullishConfluence,
    required ConfluenceResult bearishConfluence,
    required bool hasConflict,
    required Horizon horizon,
    MarketStage? marketStage,
  }) {
    final parts = <LocalizableString>[];

    // 大盤位階 context：讓個股多空 read 有 regime 脈絡（順勢 vs 逆勢）。
    // insufficient / null（大盤資料未載入）時不顯示，graceful degrade。
    final marketKey = switch (marketStage) {
      MarketStage.bullish => 'summary.marketBullish',
      MarketStage.bearish => 'summary.marketBearish',
      MarketStage.neutral => 'summary.marketNeutral',
      _ => null,
    };
    if (marketKey != null) {
      parts.add(LocalizableString(marketKey));
    }

    final close = latestPrice?.close?.toStringAsFixed(1) ?? '-';
    // **帶正負號**（2026-07-26 修）：曾用 `.abs()` 剝掉符號，再由句子的
    // 「漲幅／跌幅」用詞表達方向——但那個用詞取自 `analysis.trendState`
    // （趨勢），不是當日漲跌的方向。兩者本來就可能不一致：處於上升趨勢的
    // 股票今天當然可以大跌。
    //
    // 實機（1810 和成，2026-07-24）：頁首 ↓ −2.15（−6.99%），摘要卻寫
    // 「上升趨勢…漲幅 7.0%」——同一天一個說跌、一個說漲。
    //
    // 現在句子只陳述趨勢，當日漲跌一律帶號、用詞中性（見 summary.overall*
    // 的 i18n）。
    final change = priceChange == null
        ? '0.0'
        : AppNumberFormat.signedFixed(priceChange, decimals: 1);

    // 有匯流時用合成敘述開頭
    final hasConfluence =
        bullishConfluence.matchedCount > 0 ||
        bearishConfluence.matchedCount > 0;

    if (hasConfluence) {
      final primaryConfluence = bullishConfluence.matchedCount > 0
          ? bullishConfluence
          : bearishConfluence;
      parts.add(
        LocalizableString(
          'summary.confluenceOverall',
          {'close': close, 'change': change},
          {
            'confluence': LocalizableString(
              primaryConfluence.summaryKeys.first,
            ),
          },
        ),
      );
    } else {
      final trendKey = switch (analysis?.trendState) {
        TrendState.upCode => 'summary.overallUp',
        TrendState.downCode => 'summary.overallDown',
        _ => 'summary.overallRange',
      };
      parts.add(
        LocalizableString(trendKey, {'close': close, 'change': change}),
      );
    }

    // 反轉訊號（匯流未涵蓋時才顯示）
    final confluenceConsumed = {
      ...bullishConfluence.consumedTypes,
      ...bearishConfluence.consumedTypes,
    };
    if (analysis?.reversalState == ReversalState.w2sCode &&
        !confluenceConsumed.contains(SignalName.reversalW2S)) {
      parts.add(const LocalizableString('summary.reversalW2S'));
    } else if (analysis?.reversalState == ReversalState.s2wCode &&
        !confluenceConsumed.contains(SignalName.reversalS2W)) {
      parts.add(const LocalizableString('summary.reversalS2W'));
    }

    // 支撐/壓力（含距離百分比 + 風險報酬比）
    final support = analysis?.supportLevel;
    final resistance = analysis?.resistanceLevel;
    if (support != null && resistance != null) {
      final closeVal = latestPrice?.close;
      if (closeVal != null && closeVal > 0) {
        // **帶號**：負值代表關卡已被跨越。曾用 `.abs()` 剝掉方向，於是
        // 「已跌破的支撐」被講成「離支撐還有 X% 緩衝」——方向相反，且偏向
        // 誘導續抱。這與 :196 那條（priceChange 被 .abs() 吃掉方向）是同一個
        // bug class，2026-07-26 只修了那一處、沒掃到這裡。
        //
        // 關卡被跨越不是資料髒，是設計中的一級狀態：analysis_coordinator_service
        // 刻意把當日排除在支撐壓力計算之外（否則今日永遠無法突破，因為今日
        // 會成為新的高點）。實測 754 列中 133 列壓力已突破、43 列支撐已跌破。
        final supportDist = (closeVal - support) / closeVal * 100;
        final resistanceDist = (resistance - closeVal) / closeVal * 100;

        // 恰好等於關卡（dist == 0）不算跨越，維持正常文案顯示「距 0.0%」。
        // 兩者同時被跨越需 support > close > resistance（支撐高於壓力），
        // 實測 0 筆，故不另設文案；真發生時落在支撐已跌破那支。
        final levelKey = supportDist < 0
            ? 'summary.supportResistanceBelowSupport'
            : resistanceDist < 0
            ? 'summary.supportResistanceAboveResistance'
            : 'summary.supportResistanceWithDist';

        parts.add(
          LocalizableString(levelKey, {
            'support': support.toStringAsFixed(1),
            'resistance': resistance.toStringAsFixed(1),
            // 方向由文案用詞承載，此處一律給幅度
            'supportDist': supportDist.abs().toStringAsFixed(1),
            'resistanceDist': resistanceDist.abs().toStringAsFixed(1),
          }),
        );

        // 風險報酬比（upside / downside）
        final downside = closeVal - support;
        final upside = resistance - closeVal;
        if (downside > 0 && upside > 0) {
          final rr = upside / downside;
          // 顯示用**無條件捨去**而非四捨五入。捨去後恆 <= 原值，於是
          //   原值 >= 2.0 → 顯示值仍 >= 2.0（不會漏掉「有利」）
          //   原值 <  1.0 → 顯示值仍 <  1.0（不會漏掉「不利」）
          //   中間段也留在中間段
          // 三個條件封閉 → 畫面數字與下方判讀在數學上不可能互相矛盾。
          //
          // 四捨五入會製造：光寶科 2301 rr=1.9630 顯示「1:2.0」卻不給
          // 「賠率相對有利」；rr=0.96 顯示「1:1.0」（上下檔相當）卻寫
          // 「下檔風險已大於上檔空間」。實測 578 列中 12 列（2.1%）中招。
          //
          // 不採「判定改用四捨五入後的值」——那會讓顯示精度決定分析判斷。
          // 捨去對報酬取保守估計，也是風險評估該有的方向；文案本就寫
          // 「估算…約」。誤差上限 0.099。
          // 先四捨五入到小數第 6 位消除浮點噪音，再用整數除法取十分位。
          // 直接 `(rr * 10).floor()` 會被 FP 誤差咬：真值恰好 0.6 時
          // upside/downside 可能算出 0.5999999999999999 → 砍成 0.5，
          // 整整掉一格（實測 79,200 組構造值中 2,419 組中招，比它要修的
          // 12/578 還多）。1e-6 遠大於雙精度在此量級的誤差、又遠小於
          // 十分位，故兩側都安全。
          final tenths = (rr * 1e6).round() ~/ 100000;
          final ratioText = (tenths / 10).toStringAsFixed(1);
          parts.add(
            LocalizableString('summary.riskReward', {'ratio': ratioText}),
          );
          // RR 判讀：上檔空間 vs 下檔風險（賠率高/低提示）
          if (rr >= AnalysisParams.riskRewardFavorableThreshold) {
            parts.add(const LocalizableString('summary.riskRewardFavorable'));
          } else if (rr < 1) {
            parts.add(const LocalizableString('summary.riskRewardPoor'));
          }
        }
      } else {
        parts.add(
          LocalizableString('summary.supportResistance', {
            'support': support.toStringAsFixed(1),
            'resistance': resistance.toStringAsFixed(1),
          }),
        );
      }
    }

    // 分數評語（Stage 5c: 依 horizon 讀對應欄位）
    final score = _analysisScoreFor(analysis, horizon).toInt();
    final scoreKey = switch (score) {
      >= AnalysisParams.scoreExceptionalThreshold => 'summary.scoreExceptional',
      >= AnalysisParams.scoreStrongThreshold => 'summary.scoreStrong',
      >= AnalysisParams.scoreWorthwatchingThreshold =>
        'summary.scoreWorthwatching',
      >= AnalysisParams.scoreWatchThreshold => 'summary.scoreWatch',
      >= AnalysisParams.scoreNeutralThreshold => 'summary.scoreNeutral',
      _ => 'summary.scoreCaution',
    };
    parts.add(LocalizableString(scoreKey, {'score': score.toString()}));

    // 衝突提示
    if (hasConflict) {
      parts.add(const LocalizableString('summary.mixedSignals'));
    }

    return parts;
  }

  // ==================================================
  // 關鍵訊號（含匯流整合）
  // ==================================================

  List<LocalizableString> _buildKeySignals(
    List<DailyReasonEntry> reasons,
    ConfluenceResult confluence, {
    double? priceChange,
    required Horizon horizon,
  }) {
    // mergeSort 保證 stable — 同分時保留輸入順序（= [reasons] 註冊順序），
    // 避免不同 build 摘要顯示的 chip 順序漂移。
    final positive = reasons
        .where((r) => _ruleScoreFor(r, horizon) > 0)
        .toList();
    mergeSort<DailyReasonEntry>(
      positive,
      compare: (a, b) =>
          _ruleScoreFor(b, horizon).compareTo(_ruleScoreFor(a, horizon)),
    );

    const maxItems = AnalysisParams.summaryMaxItems;
    final signals = <LocalizableString>[];

    // 漲停板置頂顯示
    if (PriceLimit.isLimitUp(priceChange)) {
      signals.add(const LocalizableString('summary.limitUp'));
    }

    signals.addAll(
      confluence.summaryKeys
          .take(maxItems - signals.length)
          .map((key) => LocalizableString(key)),
    );

    final remainingSlots = maxItems - signals.length;
    if (remainingSlots > 0) {
      final remaining = positive
          .where((r) => !confluence.consumedTypes.contains(r.reasonType))
          .take(remainingSlots)
          .map((r) => _reasonToLocalizable(r.reasonType, r.evidenceJson))
          .whereType<LocalizableString>();
      signals.addAll(remaining);
    }
    return signals;
  }

  // ==================================================
  // 風險因子（含匯流整合）
  // ==================================================

  List<LocalizableString> _buildRiskFactors(
    List<DailyReasonEntry> reasons,
    ConfluenceResult confluence, {
    double? priceChange,
    required Horizon horizon,
  }) {
    final negative = reasons
        .where((r) => _ruleScoreFor(r, horizon) < 0)
        .toList();
    mergeSort<DailyReasonEntry>(
      negative,
      compare: (a, b) =>
          _ruleScoreFor(a, horizon).compareTo(_ruleScoreFor(b, horizon)),
    );

    const maxItems = AnalysisParams.summaryMaxItems;
    final risks = <LocalizableString>[];

    // 跌停板置頂顯示
    if (PriceLimit.isLimitDown(priceChange)) {
      risks.add(const LocalizableString('summary.limitDown'));
    }

    risks.addAll(
      confluence.summaryKeys
          .take(maxItems - risks.length)
          .map((key) => LocalizableString(key)),
    );

    final remainingSlots = maxItems - risks.length;
    if (remainingSlots > 0) {
      final remaining = negative
          .where((r) => !confluence.consumedTypes.contains(r.reasonType))
          .take(remainingSlots)
          .map((r) => _reasonToLocalizable(r.reasonType, r.evidenceJson))
          .whereType<LocalizableString>();
      risks.addAll(remaining);
    }
    return risks;
  }

  // ==================================================
  // 輔助數據
  // ==================================================

  List<LocalizableString> _buildSupportingData(
    List<DailyInstitutionalEntry> institutionalHistory,
    List<FinMindRevenue> revenueHistory,
    FinMindPER? latestPER, {
    bool streakStatedByRule = false,
  }) {
    final data = <LocalizableString>[];

    if (institutionalHistory.isNotEmpty) {
      // DAO 回傳 ascending order，.last 才是最新一天
      final latest = institutionalHistory.last;
      final foreign = _formatNetLocalizable(latest.foreignNet);
      final trust = _formatNetLocalizable(latest.investmentTrustNet);
      data.add(
        LocalizableString('summary.institutionalFlow', const {}, {
          'foreign': foreign,
          'trust': trust,
        }),
      );

      // 多日趨勢：從最新往回算連買/連賣天數。
      //
      // **規則已陳述時跳過**（2026-07-26 實機發現）：關鍵訊號的天數取自規則
      // evidence（評分路徑，institutionalStreakLookbackDays=90），此處卻是從
      // 個股詳情的顯示窗（institutionalLookbackDays=10）自行數的。實測同一張
      // 卡並列「連續買超 17 天以上」與「連續 7 天買超」。
      //
      // 不把顯示窗一起放寬：institutionalHistory 也餵籌碼頁的法人表，
      // 9 列變 60 幾列非所欲。規則在 ≥4 日觸發、此處在 ≥3 日顯示，跳過後
      // 恰好由此處覆蓋「剛好 3 日、規則還沒觸發」那一格。
      if (!streakStatedByRule && institutionalHistory.length >= 3) {
        final consecutiveBuyDays = _countConsecutiveDays(
          institutionalHistory.reversed,
          (e) => (e.foreignNet ?? 0) + (e.investmentTrustNet ?? 0) > 0,
        );
        if (consecutiveBuyDays >= 3) {
          data.add(
            LocalizableString('summary.institutionalBuyTrend', {
              'days': consecutiveBuyDays.toString(),
            }),
          );
        } else {
          final consecutiveSellDays = _countConsecutiveDays(
            institutionalHistory.reversed,
            (e) => (e.foreignNet ?? 0) + (e.investmentTrustNet ?? 0) < 0,
          );
          if (consecutiveSellDays >= 3) {
            data.add(
              LocalizableString('summary.institutionalSellTrend', {
                'days': consecutiveSellDays.toString(),
              }),
            );
          }
        }
      }
    }

    // 這是**純門檻標籤，不含成長性調整**：`pe > peSummaryLowLabelThreshold`
    // 一律標「估值偏高」。實例（2026-07-24）——同樣 PE 約 17 拿到同一句：
    //   3231 緯創  PE 17.9，但 EPS 年增 65.4%、營收年增 53.8%（PEG < 0.3）
    //   3673 TPK-KY PE 17.2，PBR 0.63、空頭排列，是價值陷阱側
    // 兩者的投資含意完全相反，標籤卻相同。
    //
    // **這是已知取捨，不是待修的 bug**：門檻在 AnalysisParams 的 docstring
    // 明載為 label-only、不影響評分，且與規則側門檻刻意分離（見 5eb1d29）。
    // 要加成長調整（PEG 之類）等於引入新的評價方法論，須先過回測驗證，
    // 不能因為「看起來怪」就改。
    //
    // 寫在這裡是因為緯創那張卡已被誤判提報過：關鍵訊號滿是高成長、輔助
    // 數據卻說估值偏高，形狀很像本檔其他真缺陷（同卡兩個相反說法），
    // 但那些是同一指標互相矛盾，此處是單一指標的機械標籤。
    final pe = latestPER?.per;
    if (pe != null && pe > 0) {
      final key = pe <= AnalysisParams.peSummaryLowLabelThreshold
          ? 'summary.peUndervalued'
          : 'summary.peOvervalued';
      data.add(LocalizableString(key, {'pe': pe.toStringAsFixed(1)}));
    }

    final yield_ = latestPER?.dividendYield;
    if (yield_ != null &&
        yield_ >= AnalysisParams.dividendYieldSummaryLabelThreshold) {
      data.add(
        LocalizableString('summary.highDividendYield', {
          'yield': yield_.toStringAsFixed(1),
        }),
      );
    }

    if (revenueHistory.isNotEmpty) {
      // **`.last` 才是最新月**：revenue_dao.dart:22 是
      // `OrderingTerm.asc(t.date)`（升冪），而取數窗是兩年
      // （data/loaders/stock_fundamentals_loader.dart:45），所以 `.first` 取到的是**兩年前**。
      // 實機 2425 承啟：同卡並列「營收年增率達 375.6%」（規則 evidence，
      // 2026/6）與「營收年增率為 -40.1%」（此處誤取 2024/7）。
      // 同檔 :444 的法人那段早有註解點出這個升冪陷阱，此處漏了。
      final latest = revenueHistory.last;
      final yoy = latest.yoyGrowth;
      if (yoy != null &&
          yoy.abs() >= AnalysisParams.revenueYoySignificantThreshold) {
        final key = yoy > 0
            ? 'summary.revenueYoySurge'
            : 'summary.revenueYoyDecline';
        data.add(LocalizableString(key, {'growth': yoy.toStringAsFixed(1)}));
      }
    }

    return data;
  }

  // ==================================================
  // 加權 Sentiment（含衝突偵測 + 基本面修正）
  // ==================================================

  SummarySentiment _determineSentiment(
    DailyAnalysisEntry? analysis,
    List<DailyReasonEntry> reasons, {
    required bool hasConflict,
    required List<FinMindRevenue> revenueHistory,
    required FinMindPER? latestPER,
    required Horizon horizon,
  }) {
    // Stage 5c: 依 horizon 讀對應的 score + ruleScore
    final score = _analysisScoreFor(analysis, horizon).toInt();

    // 加權計算（依 horizon 讀 per-rule 分數）
    final positiveWeight = reasons
        .where((r) => _ruleScoreFor(r, horizon) > 0)
        .fold<double>(0, (sum, r) => sum + _ruleScoreFor(r, horizon));
    final negativeWeight = reasons
        .where((r) => _ruleScoreFor(r, horizon) < 0)
        .fold<double>(0, (sum, r) => sum + _ruleScoreFor(r, horizon).abs());

    // 基本面修正
    var fundamentalBias = 0.0;
    final pe = latestPER?.per;
    if (pe != null && pe > 0 && pe <= AnalysisParams.peDeepValueThreshold) {
      fundamentalBias += AnalysisParams.fundamentalBiasPoints;
    }
    final yield_ = latestPER?.dividendYield;
    if (yield_ != null && yield_ >= AnalysisParams.highYieldBiasThreshold) {
      fundamentalBias += AnalysisParams.fundamentalBiasPoints;
    }
    if (revenueHistory.isNotEmpty) {
      // 同上：升冪清單取 `.last`。此處影響的不只顯示——它進 fundamentalBias，
      // 直接左右情緒標籤（偏多／中性／偏空），取錯等於用兩年前的營收
      // 決定今天的多空傾向。
      final yoy = revenueHistory.last.yoyGrowth;
      if (yoy != null && yoy > AnalysisParams.revenueStrongGrowthThreshold) {
        fundamentalBias += AnalysisParams.fundamentalBiasPoints;
      }
      if (yoy != null &&
          yoy < AnalysisParams.revenueSignificantDeclineThreshold) {
        fundamentalBias -= AnalysisParams.fundamentalBiasPoints;
      }
    }

    final adjustedPositive =
        positiveWeight + (fundamentalBias > 0 ? fundamentalBias : 0);
    final adjustedNegative =
        negativeWeight + (fundamentalBias < 0 ? fundamentalBias.abs() : 0);
    final totalWeight = adjustedPositive + adjustedNegative;

    if (totalWeight == 0) return SummarySentiment.neutral;

    final bullRatio = adjustedPositive / totalWeight;

    // 衝突時提高判斷門檻（不產生 strong 級別）
    if (hasConflict) {
      if (bullRatio > AnalysisParams.conflictBullRatioThreshold &&
          score >= AnalysisParams.conflictBullScoreThreshold) {
        return SummarySentiment.bullish;
      }
      if (bullRatio < AnalysisParams.conflictBearRatioThreshold &&
          score < AnalysisParams.conflictBearScoreThreshold) {
        return SummarySentiment.bearish;
      }
      return SummarySentiment.neutral;
    }

    // 5 級情緒梯度：先檢查 strong 門檻
    if (bullRatio >= AnalysisParams.strongBullRatioThreshold &&
        score >= AnalysisParams.strongBullScoreThreshold) {
      return SummarySentiment.strongBullish;
    }
    if (bullRatio >= AnalysisParams.bullRatioThreshold &&
        score >= AnalysisParams.bullScoreThreshold) {
      return SummarySentiment.bullish;
    }
    if (bullRatio <= AnalysisParams.strongBearRatioThreshold &&
        score < AnalysisParams.strongBearScoreThreshold) {
      return SummarySentiment.strongBearish;
    }
    if (bullRatio <= AnalysisParams.bearRatioThreshold &&
        score < AnalysisParams.bearScoreThreshold) {
      return SummarySentiment.bearish;
    }
    return SummarySentiment.neutral;
  }

  // ==================================================
  // 衝突偵測
  // ==================================================

  /// 偵測特定矛盾訊號對
  static bool _hasSignificantConflict(List<DailyReasonEntry> reasons) {
    final types = reasons.map((r) => r.reasonType).toSet();

    for (final pair in _conflictPairs) {
      final hasA = pair.$1.any(types.contains);
      final hasB = pair.$2.any(types.contains);
      if (hasA && hasB) return true;
    }
    return false;
  }

  static const _conflictPairs = [
    ({SignalName.reversalW2S}, {SignalName.kdDeathCross}),
    ({SignalName.techBreakout}, {SignalName.maAlignmentBearish}),
    ({SignalName.institutionalBuyStreak}, {SignalName.foreignExodus}),
    (
      {SignalName.peUndervalued, SignalName.pbrUndervalued},
      {SignalName.epsDeclineWarning},
    ),
    ({SignalName.maAlignmentBullish}, {SignalName.techBreakdown}),
  ];

  // ==================================================
  // 信心度計算
  // ==================================================

  AnalysisConfidence _calculateConfidence({
    required List<DailyReasonEntry> reasons,
    required List<DailyInstitutionalEntry> institutionalHistory,
    required List<FinMindRevenue> revenueHistory,
    required FinMindPER? latestPER,
    required bool hasConflict,
    required int confluenceCount,
    required Horizon horizon,
  }) {
    var points = 0;

    final totalSignals = reasons.length;
    if (totalSignals >= AnalysisParams.manySignalsThreshold) {
      points += 2;
    } else if (totalSignals >= AnalysisParams.someSignalsThreshold) {
      points += 1;
    }

    // 高分訊號品質加權：有 2+ 個 |ruleScore| ≥ 15 的訊號（依當前 horizon）
    final highScoreSignals = reasons
        .where(
          (r) =>
              _ruleScoreFor(r, horizon).abs() >=
              AnalysisParams.highQualitySignalThreshold,
        )
        .length;
    if (highScoreSignals >= 2) points += 1;

    points += confluenceCount;

    if (!hasConflict) points += 1;

    if (institutionalHistory.isNotEmpty) points += 1;
    if (revenueHistory.isNotEmpty) points += 1;
    if (latestPER != null) points += 1;

    if (points >= AnalysisParams.confidenceHighThreshold) {
      return AnalysisConfidence.high;
    }
    if (points >= AnalysisParams.confidenceMediumThreshold) {
      return AnalysisConfidence.medium;
    }
    return AnalysisConfidence.low;
  }

  // ==================================================
  // ReasonType → LocalizableString
  // ==================================================

  LocalizableString? _reasonToLocalizable(
    String reasonType,
    String evidenceJson,
  ) {
    final evidence = _parseEvidence(evidenceJson);
    return _signalBuilders[reasonType]?.call(evidence);
  }

  Map<String, dynamic> _parseEvidence(String json) {
    try {
      final decoded = jsonDecode(json);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (e) {
      AppLogger.debug(
        'AnalysisSummaryService',
        'Evidence JSON parse failed: $json ($e)',
      );
    }
    return const {};
  }

  LocalizableString _formatNetLocalizable(double? net) {
    if (net == null) return const LocalizableString('summary.netDash');
    final lots = (net / 1000).round();
    if (lots == 0) return const LocalizableString('summary.netNeutral');
    if (lots > 0) {
      return LocalizableString('summary.netBuy', {'lots': lots.toString()});
    }
    return LocalizableString('summary.netSell', {
      'lots': lots.abs().toString(),
    });
  }

  /// 從最新往回數，符合條件的連續天數
  int _countConsecutiveDays(
    Iterable<DailyInstitutionalEntry> entries,
    bool Function(DailyInstitutionalEntry) predicate,
  ) {
    var count = 0;
    for (final e in entries) {
      if (predicate(e)) {
        count++;
      } else {
        break;
      }
    }
    return count;
  }

  // ==================================================
  // 映射表：ReasonType 代碼 → LocalizableString 建構
  // ==================================================

  // ==================================================
  // 核心訊號
  // ==================================================
  static final _coreSignals =
      <String, LocalizableString Function(Map<String, dynamic>)>{
        SignalName.reversalW2S: (_) =>
            const LocalizableString('summary.reversalW2S'),
        SignalName.reversalS2W: (_) =>
            const LocalizableString('summary.reversalS2W'),
        SignalName.techBreakout: (_) =>
            const LocalizableString('summary.breakout'),
        SignalName.techBreakdown: (_) =>
            const LocalizableString('summary.breakdown'),
        SignalName.volumeSpike: (e) =>
            LocalizableString('summary.volumeSpike', {
              'multiple': _numStr(
                e['multiple'] ?? e['volumeMultiple'],
                fractionDigits: 1,
              ),
            }),
        // 量能宣稱帶窗+實際倍數(2026-08-01):priceSpike 量的是 20 日均、
        // weakRally 量的是 5 日均,兩者同日觸發是合法狀態(連環爆量墊高
        // 短均)——無窗文案會在同卡寫出「量增顯著」+「量縮」的直接對立。
        SignalName.priceSpike: (e) => LocalizableString('summary.priceSpike', {
          'pctChange': _numStr(e['pctChange'] ?? e['changePct']),
          'volMult': _numStr(e['volumeMultiple']),
        }),
        SignalName.institutionalBuy: (_) =>
            const LocalizableString('summary.institutionalBuy'),
        SignalName.institutionalSell: (_) =>
            const LocalizableString('summary.institutionalSell'),
        SignalName.newsRelated: (_) =>
            const LocalizableString('summary.newsRelated'),
      };

  // ==================================================
  // KD 訊號
  // ==================================================
  static final _kdSignals =
      <String, LocalizableString Function(Map<String, dynamic>)>{
        SignalName.kdGoldenCross: (_) =>
            const LocalizableString('summary.kdGoldenCross'),
        SignalName.kdDeathCross: (_) =>
            const LocalizableString('summary.kdDeathCross'),
      };

  // ==================================================
  // 法人連續買賣
  // ==================================================
  static final _institutionalStreakSignals =
      <String, LocalizableString Function(Map<String, dynamic>)>{
        // streakTruncated：取數窗被吃滿，真實天數可能更長 → 用「N 天以上」，
        // 與規則 description 保持一致，避免同一訊號兩處說法矛盾。
        SignalName.institutionalBuyStreak: (e) {
          final days = e['streakDays'];
          if (days != null) {
            final key = e['streakTruncated'] == true
                ? 'summary.institutionalBuyStreakDaysTruncated'
                : 'summary.institutionalBuyStreakDays';
            return LocalizableString(key, {
              'days': _numStr(days, fractionDigits: 0),
            });
          }
          return const LocalizableString('summary.institutionalBuyStreak');
        },
        SignalName.institutionalSellStreak: (e) {
          final days = e['streakDays'];
          if (days != null) {
            final key = e['streakTruncated'] == true
                ? 'summary.institutionalSellStreakDaysTruncated'
                : 'summary.institutionalSellStreakDays';
            return LocalizableString(key, {
              'days': _numStr(days, fractionDigits: 0),
            });
          }
          return const LocalizableString('summary.institutionalSellStreak');
        },
      };

  // ==================================================
  // K 線型態
  // ==================================================
  static final _candlestickPatterns =
      <String, LocalizableString Function(Map<String, dynamic>)>{
        SignalName.patternDoji: (_) =>
            const LocalizableString('summary.patternDoji'),
        SignalName.patternDojiBearish: (_) =>
            const LocalizableString('summary.patternDojiBearish'),
        SignalName.patternBullishEngulfing: (_) =>
            const LocalizableString('summary.patternBullishEngulfing'),
        SignalName.patternBearishEngulfing: (_) =>
            const LocalizableString('summary.patternBearishEngulfing'),
        SignalName.patternHammer: (_) =>
            const LocalizableString('summary.patternHammer'),
        SignalName.patternHangingMan: (_) =>
            const LocalizableString('summary.patternHangingMan'),
        SignalName.patternGapUp: (_) =>
            const LocalizableString('summary.patternGapUp'),
        SignalName.patternGapDown: (_) =>
            const LocalizableString('summary.patternGapDown'),
        SignalName.patternMorningStar: (_) =>
            const LocalizableString('summary.patternMorningStar'),
        SignalName.patternEveningStar: (_) =>
            const LocalizableString('summary.patternEveningStar'),
        SignalName.patternThreeWhiteSoldiers: (_) =>
            const LocalizableString('summary.patternThreeWhiteSoldiers'),
        SignalName.patternThreeBlackCrows: (_) =>
            const LocalizableString('summary.patternThreeBlackCrows'),
      };

  // ==================================================
  // 技術指標訊號
  // ==================================================
  static final _technicalIndicators =
      <String, LocalizableString Function(Map<String, dynamic>)>{
        SignalName.week52High: (_) =>
            const LocalizableString('summary.week52High'),
        SignalName.week52Low: (_) =>
            const LocalizableString('summary.week52Low'),
        SignalName.maAlignmentBullish: (_) =>
            const LocalizableString('summary.maAlignmentBullish'),
        SignalName.maAlignmentBearish: (_) =>
            const LocalizableString('summary.maAlignmentBearish'),
        SignalName.rsiExtremeOverbought: (e) => LocalizableString(
          'summary.rsiOverbought',
          {'rsi': _numStr(e['rsi'], fractionDigits: 0)},
        ),
        SignalName.rsiExtremeOversold: (e) => LocalizableString(
          'summary.rsiOversold',
          {'rsi': _numStr(e['rsi'], fractionDigits: 0)},
        ),
      };

  // ==================================================
  // 延伸市場資料
  // ==================================================
  static final _extendedMarketData =
      <String, LocalizableString Function(Map<String, dynamic>)>{
        // 帶出實際百分點：規則判的是兩點淨變化過門檻（0.5pp），不是單調
        // 遞增。原文案寫「持續增加／減少」，而實測 2026-07-24 觸發的 33 檔
        // 有 11 檔（33%）最新一天其實在反向——3006 晶豪科最後兩天連跌，
        // 同卡的輔助數據還寫著「外資 賣超 1259 張」。
        // 規則自己的 description 本來就只說「增加/減少 X%」，不含連續性宣稱。
        // 方向由用詞承載，代入值取絕對值；小數位與規則 description 一致。
        SignalName.foreignShareholdingIncreasing: (e) => LocalizableString(
          'summary.foreignIncreasing',
          {'change': _absNumStr(e['change'], fractionDigits: 2)},
        ),
        SignalName.foreignShareholdingDecreasing: (e) => LocalizableString(
          'summary.foreignDecreasing',
          {'change': _absNumStr(e['change'], fractionDigits: 2)},
        ),
        SignalName.dayTradingHigh: (e) => LocalizableString(
          'summary.dayTradingHigh',
          {'ratio': _numStr(e['dayTradingRatio'] ?? e['ratio'])},
        ),
        SignalName.dayTradingExtreme: (e) => LocalizableString(
          'summary.dayTradingExtreme',
          {'ratio': _numStr(e['dayTradingRatio'] ?? e['ratio'])},
        ),
        SignalName.concentrationHigh: (_) =>
            const LocalizableString('summary.concentrationHigh'),
      };

  // ==================================================
  // 價量背離
  // ==================================================
  static final _priceVolumeDivergence =
      <String, LocalizableString Function(Map<String, dynamic>)>{
        SignalName.priceVolumeWeakRally: (e) => LocalizableString(
          'summary.priceVolumeWeakRally',
          {'volShrink': _absNumStr(e['volumeChange'], fractionDigits: 0)},
        ),
        SignalName.priceVolumeBearishDivergence: (_) =>
            const LocalizableString('summary.bearishDivergence'),
        SignalName.highVolumeBreakout: (_) =>
            const LocalizableString('summary.highVolumeBreakout'),
        SignalName.lowVolumeAccumulation: (_) =>
            const LocalizableString('summary.lowVolumeAccumulation'),
      };

  // ==================================================
  // 基本面
  // ==================================================
  static final _fundamentalSignals =
      <String, LocalizableString Function(Map<String, dynamic>)>{
        SignalName.revenueYoySurge: (e) => LocalizableString(
          'summary.revenueYoySurge',
          {'growth': _numStr(e['yoyGrowth'])},
        ),
        SignalName.revenueYoyDecline: (e) => LocalizableString(
          'summary.revenueYoyDecline',
          {'growth': _numStr(e['yoyGrowth'])},
        ),
        // 單月不說「連續」——與 fundamental_scan_rules 的 description 同一判斷。
        // revenueMomConsecutiveMonths 目前為 1，故正式環境恆走單月分支。
        SignalName.revenueMomGrowth: (e) => e['consecutiveMonths'] == 1
            ? LocalizableString('summary.revenueMomGrowthSingle', {
                'growth': _numStr(e['avgMomGrowth']),
              })
            : LocalizableString('summary.revenueMomGrowth', {
                'months': _numStr(e['consecutiveMonths'], fractionDigits: 0),
              }),
        SignalName.revenueNewHigh: (e) => LocalizableString(
          'summary.revenueNewHigh',
          {'surpassPct': _numStr(e['surpassPct'])},
        ),
        SignalName.highDividendYield: (e) => LocalizableString(
          'summary.highDividendYield',
          {'yield': _numStr(e['dividendYield'])},
        ),
        SignalName.peUndervalued: (e) => LocalizableString(
          'summary.peUndervalued',
          {'pe': _numStr(e['pe'])},
        ),
        SignalName.peOvervalued: (e) =>
            LocalizableString('summary.peOvervalued', {'pe': _numStr(e['pe'])}),
        SignalName.pbrUndervalued: (e) => LocalizableString(
          'summary.pbrUndervalued',
          {'pbr': _numStr(e['pbr'])},
        ),
      };

  // ==================================================
  // Killer Features
  // ==================================================
  static final _killerFeatures =
      <String, LocalizableString Function(Map<String, dynamic>)>{
        SignalName.tradingWarningAttention: (_) =>
            const LocalizableString('summary.warningAttention'),
        SignalName.tradingWarningDisposal: (_) =>
            const LocalizableString('summary.warningDisposal'),
        SignalName.insiderSellingStreak: (e) => LocalizableString(
          'summary.insiderSelling',
          {'months': _numStr(e['sellingStreakMonths'], fractionDigits: 0)},
        ),
        SignalName.insiderSignificantBuying: (_) =>
            const LocalizableString('summary.insiderBuying'),
        SignalName.highPledgeRatio: (_) =>
            const LocalizableString('summary.highPledge'),
        SignalName.foreignConcentrationWarning: (_) =>
            const LocalizableString('summary.foreignConcentration'),
        SignalName.foreignExodus: (_) =>
            const LocalizableString('summary.foreignExodus'),
      };

  // ==================================================
  // EPS 訊號
  // ==================================================
  static final _epsSignals =
      <String, LocalizableString Function(Map<String, dynamic>)>{
        SignalName.epsYoySurge: (e) => LocalizableString(
          'summary.epsYoYSurge',
          {'growth': _numStr(e['yoyGrowth'])},
        ),
        SignalName.epsConsecutiveGrowth: (e) => LocalizableString(
          'summary.epsConsecutiveGrowth',
          {'quarters': _numStr(e['consecutiveQuarters'], fractionDigits: 0)},
        ),
        SignalName.epsTurnaround: (_) =>
            const LocalizableString('summary.epsTurnaround'),
        SignalName.epsDeclineWarning: (_) =>
            const LocalizableString('summary.epsDecline'),
      };

  // ==================================================
  // ROE 訊號
  // ==================================================
  static final _roeSignals =
      <String, LocalizableString Function(Map<String, dynamic>)>{
        SignalName.roeExcellent: (e) => LocalizableString(
          'summary.roeExcellent',
          {'roe': _numStr(e['roe'])},
        ),
        SignalName.roeImproving: (_) =>
            const LocalizableString('summary.roeImproving'),
        SignalName.roeDeclining: (_) =>
            const LocalizableString('summary.roeDeclining'),
      };

  /// 回檔模式 v2 主訊號（2026-07-23 稽核修復：v2 上線時漏接摘要層，
  /// 只靠回檔訊號上榜的股票摘要會不提核心訊號）
  static final _pullbackSignals =
      <String, LocalizableString Function(Map<String, dynamic>)>{
        SignalName.pullbackToMa20: (e) => LocalizableString(
          'summary.pullbackToMa20',
          {'distance': _numStr(e['distanceToMa20Pct'])},
        ),
        SignalName.pullbackToMa10: (_) =>
            const LocalizableString('summary.pullbackToMa10'),
        SignalName.hammerAtSupport: (_) =>
            const LocalizableString('summary.hammerAtSupport'),
        SignalName.kdHighPullback: (_) =>
            const LocalizableString('summary.kdHighPullback'),
      };

  // ==================================================
  // MA 生命週期(2026-07-31 新增,複審補接摘要層)
  // ==================================================
  static final _maStageSignals =
      <String, LocalizableString Function(Map<String, dynamic>)>{
        SignalName.reclaimMa20: (_) =>
            const LocalizableString('summary.reclaimMa20'),
        SignalName.reclaimMa60: (_) =>
            const LocalizableString('summary.reclaimMa60'),
        SignalName.breakMa20: (_) =>
            const LocalizableString('summary.breakMa20'),
        SignalName.breakMa60: (_) =>
            const LocalizableString('summary.breakMa60'),
        SignalName.coilingBelowMa20: (_) =>
            const LocalizableString('summary.coilingBelowMa20'),
        SignalName.coilingBelowMa60: (_) =>
            const LocalizableString('summary.coilingBelowMa60'),
      };

  /// 守門測試用:能被翻成摘要文案的訊號代碼全集。缺席的 ReasonType 會被
  /// `.whereType<LocalizableString>()` 靜默濾掉——回檔 v2(2026-07-23)與
  /// MA 穿越(2026-07-31)兩批新規則都漏接過,靠結構測試擋第三次。
  @visibleForTesting
  static Set<String> get summarySignalCodes => _signalBuilders.keys.toSet();

  /// 合併所有分類的 signal builders
  static final Map<String, LocalizableString Function(Map<String, dynamic>)>
  _signalBuilders = {
    ..._coreSignals,
    ..._kdSignals,
    ..._institutionalStreakSignals,
    ..._candlestickPatterns,
    ..._pullbackSignals,
    ..._maStageSignals,
    ..._technicalIndicators,
    ..._extendedMarketData,
    ..._priceVolumeDivergence,
    ..._fundamentalSignals,
    ..._killerFeatures,
    ..._epsSignals,
    ..._roeSignals,
  };

  /// 取絕對值後格式化——方向由文案用詞承載，避免出現「減少 -1.89」。
  static String _absNumStr(dynamic value, {int fractionDigits = 1}) {
    if (value is num) return value.abs().toStringAsFixed(fractionDigits);
    return _numStr(value, fractionDigits: fractionDigits);
  }

  static String _numStr(dynamic value, {int fractionDigits = 1}) {
    if (value == null) return '-';
    if (value is num) return value.toStringAsFixed(fractionDigits);
    return value.toString();
  }

  // ==================================================
  // Horizon resolvers (Stage 5c)
  // ==================================================

  /// 依 [horizon] 讀取 [DailyAnalysisEntry] 對應欄位的 score
  ///
  /// 空 analysis → 0，與既有的 `analysis?.scoreShort ?? 0` 行為一致。
  static double _analysisScoreFor(
    DailyAnalysisEntry? analysis,
    Horizon horizon,
  ) {
    if (analysis == null) return 0;
    return switch (horizon) {
      Horizon.short => analysis.scoreShort,
      Horizon.long => analysis.scoreLong,
    };
  }

  /// 依 [horizon] 讀取 [DailyReasonEntry] 對應欄位的 per-rule score
  static double _ruleScoreFor(DailyReasonEntry reason, Horizon horizon) {
    return switch (horizon) {
      Horizon.short => reason.ruleScoreShort,
      Horizon.long => reason.ruleScoreLong,
    };
  }
}
