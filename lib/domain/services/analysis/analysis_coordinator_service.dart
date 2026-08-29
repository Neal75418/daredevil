import 'package:daredevil/core/constants/rule_params.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/domain/models/models.dart';
import 'package:daredevil/domain/services/ohlcv_data.dart';
import 'package:daredevil/domain/services/technical_indicator_service.dart';
import 'package:daredevil/domain/services/analysis/trend_detection_service.dart';
import 'package:daredevil/domain/services/analysis/reversal_detection_service.dart';
import 'package:daredevil/domain/services/analysis/support_resistance_service.dart';

/// 分析協調服務
///
/// 整合所有分析服務，提供統一的股票分析入口
/// 協調趨勢檢測、反轉檢測、支撐壓力計算、價量分析等功能
class AnalysisCoordinatorService {
  AnalysisCoordinatorService({
    TrendDetectionService? trendService,
    ReversalDetectionService? reversalService,
    SupportResistanceService? srService,
    TechnicalIndicatorService? indicatorService,
  }) : trendService = trendService ?? TrendDetectionService(),
       reversalService = reversalService ?? ReversalDetectionService(),
       srService = srService ?? SupportResistanceService(),
       indicatorService = indicatorService ?? TechnicalIndicatorService();

  /// 趨勢檢測服務
  final TrendDetectionService trendService;

  /// 反轉檢測服務
  final ReversalDetectionService reversalService;

  /// 支撐壓力檢測服務
  final SupportResistanceService srService;

  /// 技術指標服務
  final TechnicalIndicatorService indicatorService;

  /// 分析單一股票並回傳分析結果
  ///
  /// 需至少 [RuleParams.swingWindow] + 1 天的價格歷史。
  ///
  /// **為什麼是 +1**：下方為避開前視偏差會截掉最後一根才餵給
  /// [TrendDetectionService.detectTrendState]，而後者自己也要求
  /// `>= swingWindow`。若這裡只擋 `< swingWindow`，恰好 20 根的股票會
  /// 通過每一道閘門、拿到一個**未經計算**的 `TrendState.range` ——那個值
  /// 會落庫成 `daily_analysis.trend_state` 並被渲染成「盤整」，把「資料
  /// 不足」講成一個趨勢主張。回 null 則由呼叫端的 `skippedNoAnalysis`
  /// 計數，不會無聲消失。
  ///
  /// 為了避免前視偏差，支撐/壓力/區間使用「過去」價格計算，
  /// 反轉狀態則使用完整價格（包含今日）與過去關卡做比較
  AnalysisResult? analyzeStock(List<DailyPriceEntry> priceHistory) {
    if (priceHistory.length < RuleParams.swingWindow + 1) {
      return null; // 資料不足
    }

    // 將歷史資料分為「過去」（上下文）和「當前」（行動）
    // 以避免前視偏差（當前價格影響支撐/壓力位計算）
    // 若計算區間/壓力時包含「今日」，則「今日」永遠無法突破
    // 因為「今日」會成為新的高點
    final priorHistory = priceHistory.length > 1
        ? priceHistory.sublist(0, priceHistory.length - 1)
        : priceHistory;

    // 使用「過去」歷史計算支撐與壓力
    final (support, resistance) = srService.findSupportResistance(priorHistory);

    // 使用「過去」歷史計算 60 日區間
    final (rangeBottom, rangeTop) = srService.findRange(priorHistory);

    // 使用「過去」歷史判斷趨勢狀態
    final trendState = trendService.detectTrendState(priorHistory);

    // 判斷反轉狀態
    // 注意：這裡傳入完整的 priceHistory，因為需要看到「今日」價格
    // 才能與剛計算出的「過去」關卡做比較
    final reversalState = reversalService.detectReversalState(
      priceHistory,
      trendState: trendState,
      rangeTop: rangeTop,
      rangeBottom: rangeBottom,
      support: support,
    );

    return AnalysisResult(
      trendState: trendState,
      reversalState: reversalState,
      supportLevel: support,
      resistanceLevel: resistance,
      rangeTop: rangeTop,
      rangeBottom: rangeBottom,
    );
  }

  /// 建立規則引擎所需的分析上下文
  ///
  /// 整合分析結果和技術指標，供規則引擎使用
  AnalysisContext buildContext(
    AnalysisResult result, {
    required DateTime evaluationTime,
    List<DailyPriceEntry>? priceHistory,
    MarketDataContext? marketData,
    bool? isMarketUptrend,
  }) {
    TechnicalIndicators? indicators;

    // 若有提供價格歷史則計算技術指標
    if (priceHistory != null &&
        priceHistory.length >= _minIndicatorDataPoints) {
      indicators = calculateTechnicalIndicators(priceHistory);
    }

    return AnalysisContext(
      trendState: result.trendState,
      reversalState: result.reversalState,
      supportLevel: result.supportLevel,
      resistanceLevel: result.resistanceLevel,
      rangeTop: result.rangeTop,
      rangeBottom: result.rangeBottom,
      indicators: indicators,
      marketData: marketData,
      evaluationTime: evaluationTime,
      isMarketUptrend: isMarketUptrend,
    );
  }

  /// 從價格歷史計算技術指標
  ///
  /// 回傳最近一日的 RSI、KD、MA 值，
  /// 以及前一日的 KD 用於交叉偵測。
  /// MA 值預先計算一次，供所有規則共用。
  TechnicalIndicators? calculateTechnicalIndicators(
    List<DailyPriceEntry> prices,
  ) {
    if (prices.length < _minIndicatorDataPoints) {
      return null;
    }

    // 擷取 OHLC 資料（含 gapBefore：哪些有效交易日前跨了停牌缺口）
    final (:closes, :highs, :lows, :gapBefore, volumes: _) = prices
        .extractOhlcv();

    if (closes.length < IndicatorParams.rsiPeriod + 2) {
      return null;
    }

    // 計算 RSI — 傳入 gapBefore 讓跨缺口的價差不被當成單一交易日變動
    // （見 latestRSI 的缺口處理語意；root cause: 停牌列被 extractOhlcv 丟棄後，
    // 若不帶缺口資訊，相鄰陣列元素可能實際橫跨多個交易日）
    final rsiValues = indicatorService.calculateRSI(
      closes,
      period: IndicatorParams.rsiPeriod,
      gapBefore: gapBefore,
    );
    final currentRsi = rsiValues.isNotEmpty ? rsiValues.last : null;

    // 計算 KD
    final kd = indicatorService.calculateKD(
      highs,
      lows,
      closes,
      kPeriod: IndicatorParams.kdPeriodK,
      dPeriod: IndicatorParams.kdPeriodD,
    );

    // 取得當日與前一日的 KD 值
    double? currentK, currentD, prevK, prevD;

    if (kd.k.length >= 2 && kd.d.length >= 2) {
      currentK = kd.k.last;
      currentD = kd.d.last;
      // prevK/prevD 僅在「今日」與其前一個有效交易日之間沒有停牌缺口時，
      // 才真正代表「前一交易日」——否則 kd.k[len-2] 可能是好幾個交易日前的
      // 舊值，KD 交叉規則、KdHighLevelPullbackRule 的 prevKdK-kdK 單日跌幅
      // 都會誤判，寧可回傳 null 讓規則自然略過（rules 已對 null 做防禦）
      if (!gapBefore.last) {
        prevK = kd.k[kd.k.length - 2];
        prevD = kd.d[kd.d.length - 2];
      }
    } else if (kd.k.isNotEmpty && kd.d.isNotEmpty) {
      currentK = kd.k.last;
      currentD = kd.d.last;
    }

    // 預先計算所有 MA（供規則共用，避免重複計算）
    final ma5 = TechnicalIndicatorService.latestSMA(prices, 5);
    final ma10 = TechnicalIndicatorService.latestSMA(prices, 10);
    final ma20 = TechnicalIndicatorService.latestSMA(prices, 20);
    final ma60 = TechnicalIndicatorService.latestSMA(prices, 60);
    final volResult = TechnicalIndicatorService.latestVolumeMA(prices, 20);

    return TechnicalIndicators(
      rsi: currentRsi,
      kdK: currentK,
      kdD: currentD,
      prevKdK: prevK,
      prevKdD: prevD,
      ma5: ma5,
      ma10: ma10,
      ma20: ma20,
      ma60: ma60,
      volumeMA20: volResult.volumeMA,
    );
  }

  /// 技術指標所需的最少資料點數
  /// RSI 需要：rsiPeriod + 1 (14 + 1 = 15)
  /// KD 需要：kdPeriodK + kdPeriodD - 1 + 1 (9 + 3 - 1 + 1 = 12)
  /// MA60 需要：60
  /// 取最大值以確保皆可計算
  static final _minIndicatorDataPoints = [
    IndicatorParams.rsiPeriod + 1,
    IndicatorParams.kdPeriodK + IndicatorParams.kdPeriodD,
    60,
  ].reduce((a, b) => a > b ? a : b);
}
