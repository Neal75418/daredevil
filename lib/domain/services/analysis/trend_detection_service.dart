import 'package:daredevil/core/constants/rule_params.dart';
import 'package:daredevil/core/utils/list_helper.dart';
import 'package:daredevil/core/utils/logger.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/domain/services/technical_indicator_service.dart';

/// 趨勢檢測服務
///
/// 負責判斷股票的趨勢狀態（上升、下降、盤整）
/// 以及檢測弱轉強、強轉弱等反轉條件
class TrendDetectionService {
  /// 偵測趨勢狀態
  ///
  /// 使用線性迴歸計算最近 [RuleParams.swingWindow] 天的價格斜率
  /// 根據斜率判斷為上升趨勢、下降趨勢或盤整
  TrendState detectTrendState(List<DailyPriceEntry> prices) {
    if (prices.length < RuleParams.swingWindow) {
      return TrendState.range;
    }

    // 取得近期價格進行趨勢分析
    final recentPrices = lastN(prices, RuleParams.swingWindow);

    // 使用收盤價計算簡易趨勢。
    //
    // **保留原始位置當 x**(2026-08-15 數值稽核):舊實作先
    // `whereType<double>()` 剔除停牌日再用陣列位置當 x,於是剩下的點被
    // 當成連續交易日——20 天窗口有 12 天停牌時,8 個點涵蓋 20 天的漲幅,
    // 斜率被放大約 2.7 倍(實測臨界:同樣 +1.0% 的漲幅,無停牌判 range、
    // 12 天停牌判 up)。而門檻是每交易日 0.08%,放大後輕易穿越 →
    // TrendState 誤判 → 連鎖影響所有讀 trendState 的規則與轉折判定。
    final points = <({double x, double y})>[];
    for (var i = 0; i < recentPrices.length; i++) {
      final close = recentPrices[i].close;
      if (close != null) points.add((x: i.toDouble(), y: close));
    }

    if (points.length < TrendParams.minTrendDataPoints) return TrendState.range;

    // 注意：recentPrices 由 lastN() 得來，順序為新到舊（newest-first），
    // 因此需取負值才是時間正向的斜率
    final slope = -_calculateSlope(points);
    final closes = [for (final p in points) p.y];

    // 依平均價格標準化斜率（防止除以零）
    final avgPrice = closes.reduce((a, b) => a + b) / closes.length;
    if (avgPrice <= 0) return TrendState.range;

    final normalizedSlope = (slope / avgPrice) * 100;

    // 趨勢偵測閾值
    if (normalizedSlope > TrendParams.trendUpThreshold) {
      return TrendState.up;
    } else if (normalizedSlope < TrendParams.trendDownThreshold) {
      return TrendState.down;
    } else {
      return TrendState.range;
    }
  }

  /// 檢查弱轉強條件（W2S）
  ///
  /// 僅在原本弱勢（下跌或盤整趨勢）時檢查；滿足以下任一條件即為弱轉強：
  /// - 突破區間頂部（需量能確認）
  /// - 形成更高的低點且站上 MA20
  bool checkWeakToStrong(
    List<DailyPriceEntry> prices,
    double todayClose, {
    required TrendState trendState,
    double? rangeTop,
    double? ma20,
  }) {
    if (trendState != TrendState.down && trendState != TrendState.range) {
      return false;
    }

    // 突破區間頂部（需量能確認——與本檔 _hasHigherLow 的量能確認一致；
    // 共用 BreakoutRule 的 1.5x 常數 reversalVolumeConfirm，但語意不同：
    // 此處比「近 20 日均量 vs 前 20 日均量」、資料不足擋下，BreakoutRule
    // 比「今日量 vs 20 日均量」、資料不足放行；audit signal #4）
    if (rangeTop != null) {
      final breakoutLevel = rangeTop * (1 + TrendParams.breakoutBuffer);
      if (todayClose > breakoutLevel &&
          _hasLevelBreachVolumeConfirmation(prices)) {
        return true;
      }
    }

    // 形成更高的低點
    return _hasHigherLow(prices, ma20: ma20);
  }

  /// 檢查強轉弱條件（S2W）
  ///
  /// 僅在原本強勢（上升或盤整趨勢）時檢查——已在下跌趨勢代表本就弱勢，跌破
  /// 支撐是「延續」而非「反轉」（延續由 BreakdownRule 承接），與 [checkWeakToStrong]
  /// 對 trendState 的門檻對稱（audit signal #4）。滿足以下任一即為強轉弱：
  /// - 跌破支撐位（需量能確認）
  /// - 跌破區間底部（需量能確認）
  /// - 形成更低的高點
  bool checkStrongToWeak(
    List<DailyPriceEntry> prices,
    double todayClose, {
    required TrendState trendState,
    double? support,
    double? rangeBottom,
  }) {
    if (trendState != TrendState.up && trendState != TrendState.range) {
      return false;
    }

    // 跌破支撐（需量能確認——恐慌性跌破通常伴隨放量，與 BreakdownRule 對相同
    // 價位跌破共用 BreakoutRule 的 1.5x 常數，語意見上方 checkWeakToStrong 註解）
    if (support != null) {
      final breakdownLevel = support * (1 - TrendParams.breakdownBuffer);
      if (todayClose < breakdownLevel &&
          _hasLevelBreachVolumeConfirmation(prices)) {
        AppLogger.debug(
          'TrendDetectionService',
          '跌破支撐(量能確認): close=$todayClose < support=$support * 0.97 = $breakdownLevel',
        );
        return true;
      }
    }

    // 跌破區間底部（需量能確認）
    if (rangeBottom != null) {
      final breakdownLevel = rangeBottom * (1 - TrendParams.breakdownBuffer);
      if (todayClose < breakdownLevel &&
          _hasLevelBreachVolumeConfirmation(prices)) {
        AppLogger.debug(
          'TrendDetectionService',
          '跌破區間底部(量能確認): close=$todayClose < rangeBottom=$rangeBottom * 0.97 = $breakdownLevel',
        );
        return true;
      }
    }

    // 形成更低的高點（trendState 已保證為 up/range）
    return _hasLowerHigh(prices);
  }

  // ==================================================
  // 私有輔助方法
  // ==================================================

  /// 檢查是否形成更高的低點（反轉訊號）
  ///
  /// 條件：
  /// 1. 近期低點高於前期低點 7%（higherLowBuffer=1.07，2026 收緊）
  /// 2. 收盤站上 MA20
  /// 3. 近期成交量高於前期平均（量能確認）
  bool _hasHigherLow(List<DailyPriceEntry> prices, {double? ma20}) {
    if (prices.length < TrendParams.reversalMinDataPoints) return false;

    // 分為近期 (0-19) 與前期 (20-39)
    final recentPrices = prices
        .skip(prices.length - TrendParams.reversalHalfWindow)
        .toList();
    final priorPrices = prices
        .skip(prices.length - TrendParams.reversalMinDataPoints)
        .take(TrendParams.reversalHalfWindow)
        .toList();

    final recentLow = recentPrices
        .map((p) => p.low ?? double.infinity)
        .reduce((a, b) => a < b ? a : b);

    final priorLow = priorPrices
        .map((p) => p.low ?? double.infinity)
        .reduce((a, b) => a < b ? a : b);

    if (!recentLow.isFinite || !priorLow.isFinite || priorLow == 0) {
      return false;
    }

    // 條件 1：近期低點高於前期低點（使用 higherLowBuffer）
    if (recentLow <= priorLow * TrendParams.higherLowBuffer) {
      return false;
    }

    // 條件 2：收盤站上 MA20
    final todayClose = prices.last.close;
    if (todayClose == null) return false;

    final ma = ma20 ?? TechnicalIndicatorService.latestSMA(prices, 20);
    if (ma == null || todayClose < ma) {
      return false;
    }

    // 條件 3：量能確認
    return _hasVolumeConfirmation(recentPrices, priorPrices);
  }

  /// 檢查是否形成更低的高點（反轉訊號）
  ///
  /// 條件：
  /// 1. 近期高點低於前期高點 5%
  /// 2. 近期成交量高於前期平均（量能確認）
  bool _hasLowerHigh(List<DailyPriceEntry> prices) {
    if (prices.length < TrendParams.reversalMinDataPoints) return false;

    // 分為近期 (0-19) 與前期 (20-39)
    final recentPrices = prices
        .skip(prices.length - TrendParams.reversalHalfWindow)
        .toList();
    final priorPrices = prices
        .skip(prices.length - TrendParams.reversalMinDataPoints)
        .take(TrendParams.reversalHalfWindow)
        .toList();

    final recentHigh = recentPrices
        .map((p) => p.high ?? double.negativeInfinity)
        .reduce((a, b) => a > b ? a : b);

    final priorHigh = priorPrices
        .map((p) => p.high ?? double.negativeInfinity)
        .reduce((a, b) => a > b ? a : b);

    if (!recentHigh.isFinite || !priorHigh.isFinite || priorHigh == 0) {
      return false;
    }

    // 條件 1：近期高點低於前期高點（使用 lowerHighBuffer）
    if (recentHigh >= priorHigh * TrendParams.lowerHighBuffer) {
      return false;
    }

    // 條件 2：量能確認
    return _hasVolumeConfirmation(recentPrices, priorPrices);
  }

  /// 價位突破/跌破的量能確認
  ///
  /// 與 [_hasHigherLow]/[_hasLowerHigh] 一致，以近期 vs 前期 20 日窗口比較量能，
  /// 要求近期均量達前期的 [TrendParams.reversalVolumeConfirm] 倍。資料不足
  /// （< [TrendParams.reversalMinDataPoints]）時回 false（與兩個手足子檢查的
  /// 最低資料要求一致），避免無量假突破/假跌破觸發反轉訊號。
  bool _hasLevelBreachVolumeConfirmation(List<DailyPriceEntry> prices) {
    if (prices.length < TrendParams.reversalMinDataPoints) return false;

    final recentPrices = prices
        .skip(prices.length - TrendParams.reversalHalfWindow)
        .toList();
    final priorPrices = prices
        .skip(prices.length - TrendParams.reversalMinDataPoints)
        .take(TrendParams.reversalHalfWindow)
        .toList();

    return _hasVolumeConfirmation(recentPrices, priorPrices);
  }

  /// 檢查量能確認
  ///
  /// 近期平均成交量需高於前期平均成交量的 [TrendParams.reversalVolumeConfirm] 倍
  bool _hasVolumeConfirmation(
    List<DailyPriceEntry> recentPrices,
    List<DailyPriceEntry> priorPrices,
  ) {
    final recentVol =
        recentPrices.map((p) => p.volume ?? 0).reduce((a, b) => a + b) /
        recentPrices.length;

    final priorVol =
        priorPrices.map((p) => p.volume ?? 0).reduce((a, b) => a + b) /
        priorPrices.length;

    if (priorVol <= 0) return false;

    return recentVol >= priorVol * TrendParams.reversalVolumeConfirm;
  }

  /// 計算線性迴歸斜率
  /// 最小平方法斜率。[points] 的 x 是**在原始窗口中的位置**,不是
  /// 陣列索引——停牌日被剔除後仍要保留時間間隔(見 detectTrendState)。
  double _calculateSlope(List<({double x, double y})> points) {
    final n = points.length;
    if (n < 2) return 0;

    double sumX = 0;
    double sumY = 0;
    double sumXY = 0;
    double sumX2 = 0;

    for (final p in points) {
      sumX += p.x;
      sumY += p.y;
      sumXY += p.x * p.y;
      sumX2 += p.x * p.x;
    }

    final denominator = n * sumX2 - sumX * sumX;
    // 使用 epsilon 比較以確保浮點數安全
    const epsilon = 1e-10;
    if (denominator.abs() < epsilon) return 0;

    return (n * sumXY - sumX * sumY) / denominator;
  }
}
