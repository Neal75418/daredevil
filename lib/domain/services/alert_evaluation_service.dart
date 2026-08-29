import 'package:daredevil/core/constants/rule_params.dart';
import 'package:daredevil/core/utils/logger.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/domain/services/analysis/support_resistance_service.dart';
import 'package:daredevil/domain/services/ohlcv_data.dart';
import 'package:daredevil/domain/services/technical_indicator_service.dart';

/// 警示評估所需的上下文資料
class AlertEvaluationContext {
  const AlertEvaluationContext({
    required this.currentPrices,
    required this.priceChanges,
    required this.volumeDataMap,
    required this.priceHistoryMap,
    required this.indicatorDataMap,
    required this.warningSymbols,
    required this.disposalSymbols,
    this.revenueYoyMap = const {},
    this.dividendYieldMap = const {},
    this.peRatioMap = const {},
    this.insiderChangeMap = const {},
    this.pledgeRatioMap = const {},
  });

  final Map<String, double> currentPrices;
  final Map<String, double> priceChanges;
  final Map<String, List<DailyPriceEntry>> volumeDataMap;
  final Map<String, List<DailyPriceEntry>> priceHistoryMap;
  final Map<String, List<DailyPriceEntry>> indicatorDataMap;
  final Set<String> warningSymbols;
  final Set<String> disposalSymbols;

  /// 營收年增率（%）
  final Map<String, double> revenueYoyMap;

  /// 現金殖利率（%）
  final Map<String, double> dividendYieldMap;

  /// 本益比
  final Map<String, double> peRatioMap;

  /// 董監持股變動（正=增持，負=減持）
  final Map<String, double> insiderChangeMap;

  /// 質押比例（%）
  final Map<String, double> pledgeRatioMap;
}

/// 評估價格警示條件的 Domain 服務
///
/// 從 UserDaoMixin 中抽取，修正分層違規 — 技術指標計算
/// 應屬於 Domain 層，而非 Data Access 層。
class AlertEvaluationService {
  AlertEvaluationService({
    TechnicalIndicatorService? indicatorService,
    SupportResistanceService? srService,
  }) : _indicatorService = indicatorService ?? TechnicalIndicatorService(),
       _srService = srService ?? SupportResistanceService();

  final TechnicalIndicatorService _indicatorService;
  final SupportResistanceService _srService;

  /// evaluator switch 中有實作的警示類型字串
  ///
  /// 使用 [AlertParams] 常數，與 presentation 層 AlertType.value 保持同步
  static const _implementedTypes = {
    AlertParams.typeAbove,
    AlertParams.typeBelow,
    AlertParams.typeChangePct,
    AlertParams.typeVolumeSpike,
    AlertParams.typeVolumeAbove,
    AlertParams.typeWeek52High,
    AlertParams.typeWeek52Low,
    AlertParams.typeRsiOverbought,
    AlertParams.typeRsiOversold,
    AlertParams.typeKdGoldenCross,
    AlertParams.typeKdDeathCross,
    AlertParams.typeCrossAboveMa,
    AlertParams.typeCrossBelowMa,
    AlertParams.typeTradingWarning,
    AlertParams.typeTradingDisposal,
    // Phase 3: 進階警示類型
    AlertParams.typeBreakResistance,
    AlertParams.typeBreakSupport,
    AlertParams.typeRevenueYoySurge,
    AlertParams.typeHighDividendYield,
    AlertParams.typePeUndervalued,
    AlertParams.typeInsiderSelling,
    AlertParams.typeInsiderBuying,
    AlertParams.typeHighPledgeRatio,
  };

  /// 根據當前市場資料評估所有啟用中的警示
  ///
  /// 回傳已觸發的警示，以及應自動停用的未實作警示類型 ID
  /// （舊版 DB 資料）。
  ({
    List<PriceAlertEntry> triggered,
    List<int> unimplementedIds,
    List<String> skippedNoPrice,
  })
  evaluateAlerts(
    List<PriceAlertEntry> activeAlerts,
    AlertEvaluationContext context,
  ) {
    final triggered = <PriceAlertEntry>[];
    final unimplementedIds = <int>[];
    final skippedNoPrice = <String>[];

    for (final alert in activeAlerts) {
      // 未實作的警示類型不依賴 price data，直接收集並跳過
      if (!_implementedTypes.contains(alert.alertType)) {
        AppLogger.warning(
          'AlertEvaluationService',
          '未實作的警示類型: ${alert.alertType} (symbol=${alert.symbol})，將自動停用',
        );
        unimplementedIds.add(alert.id);
        continue;
      }

      final currentPrice = context.currentPrices[alert.symbol];
      if (currentPrice == null) {
        // 靜默稽核 #10:部分同步/停牌讓當日價格缺席時,連 KD/量能這類
        // 不必然依賴現價的警示也一併跳過——計數上報,「沒響」與「沒被
        // 評估」不得不可分
        skippedNoPrice.add(alert.symbol);
        continue;
      }

      final priceChange = context.priceChanges[alert.symbol];
      bool shouldTrigger = false;

      switch (alert.alertType) {
        case AlertParams.typeAbove:
          shouldTrigger = currentPrice >= alert.targetValue;
        case AlertParams.typeBelow:
          shouldTrigger = currentPrice <= alert.targetValue;
        case AlertParams.typeChangePct:
          if (priceChange != null) {
            shouldTrigger = priceChange.abs() >= alert.targetValue;
          }
        case AlertParams.typeVolumeSpike:
          final volumeData = context.volumeDataMap[alert.symbol];
          if (volumeData != null && volumeData.isNotEmpty) {
            shouldTrigger = _checkVolumeSpike(
              volumeData,
              currentPrice,
              priceChange,
            );
          }
        case AlertParams.typeVolumeAbove:
          final volumeData = context.volumeDataMap[alert.symbol];
          if (volumeData != null && volumeData.isNotEmpty) {
            shouldTrigger = _checkVolumeAbove(
              volumeData.last,
              alert.targetValue,
            );
          }
        case AlertParams.typeWeek52High:
          final priceHistory = context.priceHistoryMap[alert.symbol];
          if (priceHistory != null && priceHistory.isNotEmpty) {
            shouldTrigger = _checkWeek52High(priceHistory, currentPrice);
          }
        case AlertParams.typeWeek52Low:
          final priceHistory = context.priceHistoryMap[alert.symbol];
          if (priceHistory != null && priceHistory.isNotEmpty) {
            shouldTrigger = _checkWeek52Low(priceHistory, currentPrice);
          }
        case AlertParams.typeRsiOverbought:
          final indicatorData = context.indicatorDataMap[alert.symbol];
          if (indicatorData != null && indicatorData.isNotEmpty) {
            shouldTrigger = _checkRsiOverbought(
              indicatorData,
              alert.targetValue,
            );
          }
        case AlertParams.typeRsiOversold:
          final indicatorData = context.indicatorDataMap[alert.symbol];
          if (indicatorData != null && indicatorData.isNotEmpty) {
            shouldTrigger = _checkRsiOversold(indicatorData, alert.targetValue);
          }
        case AlertParams.typeKdGoldenCross:
          final indicatorData = context.indicatorDataMap[alert.symbol];
          if (indicatorData != null && indicatorData.isNotEmpty) {
            shouldTrigger = _checkKdGoldenCross(indicatorData);
          }
        case AlertParams.typeKdDeathCross:
          final indicatorData = context.indicatorDataMap[alert.symbol];
          if (indicatorData != null && indicatorData.isNotEmpty) {
            shouldTrigger = _checkKdDeathCross(indicatorData);
          }
        case AlertParams.typeCrossAboveMa:
          final indicatorData = context.indicatorDataMap[alert.symbol];
          if (indicatorData != null && indicatorData.isNotEmpty) {
            shouldTrigger = _checkCrossAboveMa(
              indicatorData,
              alert.targetValue.toInt(),
            );
          }
        case AlertParams.typeCrossBelowMa:
          final indicatorData = context.indicatorDataMap[alert.symbol];
          if (indicatorData != null && indicatorData.isNotEmpty) {
            shouldTrigger = _checkCrossBelowMa(
              indicatorData,
              alert.targetValue.toInt(),
            );
          }
        case AlertParams.typeTradingWarning:
          shouldTrigger = context.warningSymbols.contains(alert.symbol);
        case AlertParams.typeTradingDisposal:
          shouldTrigger = context.disposalSymbols.contains(alert.symbol);

        // Phase 3: 進階警示類型
        case AlertParams.typeBreakResistance:
          final priceHistory = context.priceHistoryMap[alert.symbol];
          if (priceHistory != null &&
              priceHistory.length >= RuleParams.swingWindow * 2) {
            final (_, resistance) = _srService.findSupportResistance(
              priceHistory,
            );
            if (resistance != null) {
              shouldTrigger = currentPrice > resistance;
            }
          }
        case AlertParams.typeBreakSupport:
          final priceHistory = context.priceHistoryMap[alert.symbol];
          if (priceHistory != null &&
              priceHistory.length >= RuleParams.swingWindow * 2) {
            final (support, _) = _srService.findSupportResistance(priceHistory);
            if (support != null) {
              shouldTrigger = currentPrice < support;
            }
          }
        case AlertParams.typeRevenueYoySurge:
          final yoy = context.revenueYoyMap[alert.symbol];
          if (yoy != null) {
            // targetValue 為門檻百分比（預設 30%）
            shouldTrigger = yoy >= alert.targetValue;
          }
        case AlertParams.typeHighDividendYield:
          final yield_ = context.dividendYieldMap[alert.symbol];
          if (yield_ != null) {
            shouldTrigger = yield_ >= alert.targetValue;
          }
        case AlertParams.typePeUndervalued:
          final pe = context.peRatioMap[alert.symbol];
          if (pe != null && pe > 0) {
            shouldTrigger = pe <= alert.targetValue;
          }
        case AlertParams.typeInsiderSelling:
          final change = context.insiderChangeMap[alert.symbol];
          if (change != null) {
            shouldTrigger = change < 0;
          }
        case AlertParams.typeInsiderBuying:
          final change = context.insiderChangeMap[alert.symbol];
          if (change != null) {
            shouldTrigger = change > 0;
          }
        case AlertParams.typeHighPledgeRatio:
          final ratio = context.pledgeRatioMap[alert.symbol];
          if (ratio != null) {
            shouldTrigger =
                ratio >= (alert.targetValue > 0 ? alert.targetValue : 30);
          }

        default:
          // 防禦：_implementedTypes 與 switch 不同步時的安全網
          // 既然 switch 沒有處理邏輯，應視為未實作並自動停用
          AppLogger.warning(
            'AlertEvaluationService',
            'switch 未處理的警示類型: ${alert.alertType} (symbol=${alert.symbol})，將自動停用',
          );
          unimplementedIds.add(alert.id);
      }

      if (shouldTrigger) {
        triggered.add(alert);
      }
    }

    return (
      triggered: triggered,
      unimplementedIds: unimplementedIds,
      skippedNoPrice: skippedNoPrice,
    );
  }

  // ==================================================
  // 警示檢查輔助方法 - 成交量警示
  // ==================================================

  /// 計算平均成交量（排除最新一天，計算前 20 個交易日）
  double? _calculateAverageVolume(List<DailyPriceEntry> prices) {
    if (prices.length < 2) return null; // 至少需要 2 筆資料（1 筆歷史 + 1 筆最新）

    // 排除最新一天，只計算歷史資料
    final historicalPrices = prices.sublist(0, prices.length - 1);

    final volumes = historicalPrices
        .map((p) => p.volume)
        .where((v) => v != null && v > 0)
        .map((v) => v!)
        .toList();

    if (volumes.isEmpty) return null;

    // 取最近 20 個交易日（排除今天後的）
    final recent = volumes.length > AlertParams.volumeSmaWindow
        ? volumes.sublist(volumes.length - AlertParams.volumeSmaWindow)
        : volumes;
    return recent.reduce((a, b) => a + b) / recent.length;
  }

  /// 檢查成交量爆量（成交量 >= 4x 均量 且價格變動 >= 1.5%）
  bool _checkVolumeSpike(
    List<DailyPriceEntry> prices,
    double currentPrice,
    double? priceChange,
  ) {
    if (prices.isEmpty) return false;

    final avgVolume = _calculateAverageVolume(prices);
    if (avgVolume == null) return false;

    final latestVolume = prices.last.volume;
    if (latestVolume == null || latestVolume <= 0) return false;

    // 條件 1: 成交量 >= 4x 均量
    final volumeSpike = latestVolume >= avgVolume * 4;

    // 條件 2: 價格變動 >= 1.5%
    final significantPriceChange =
        priceChange != null && priceChange.abs() >= 1.5;

    return volumeSpike && significantPriceChange;
  }

  /// 檢查成交量高於目標值
  bool _checkVolumeAbove(DailyPriceEntry price, double targetVolume) {
    final volume = price.volume;
    if (volume == null || volume <= 0) return false;
    return volume >= targetVolume;
  }

  // ==================================================
  // 警示檢查輔助方法 - 52 週警示
  // ==================================================

  /// 檢查是否創 52 週新高
  bool _checkWeek52High(List<DailyPriceEntry> prices, double currentPrice) {
    if (prices.isEmpty) return false;

    // 找出過去 52 週的最高價
    double? maxHigh;
    for (final price in prices) {
      if (price.high != null) {
        if (maxHigh == null || price.high! > maxHigh) {
          maxHigh = price.high;
        }
      }
    }

    if (maxHigh == null) return false;

    // 當前價格 >= 52 週最高價
    return currentPrice >= maxHigh;
  }

  /// 檢查是否創 52 週新低
  bool _checkWeek52Low(List<DailyPriceEntry> prices, double currentPrice) {
    if (prices.isEmpty) return false;

    // 找出過去 52 週的最低價
    double? minLow;
    for (final price in prices) {
      if (price.low != null) {
        if (minLow == null || price.low! < minLow) {
          minLow = price.low;
        }
      }
    }

    if (minLow == null) return false;

    // 當前價格 <= 52 週最低價
    return currentPrice <= minLow;
  }

  // ==================================================
  // 警示檢查輔助方法 - RSI/KD 指標警示
  // ==================================================

  /// 檢查 RSI 超買（RSI >= 目標值，如 70）
  bool _checkRsiOverbought(List<DailyPriceEntry> prices, double targetRsi) {
    if (prices.length < AlertParams.rsiMinDataPoints) return false;

    final ohlcv = prices.extractOhlcv();
    if (ohlcv.closes.length < AlertParams.rsiMinDataPoints) return false;

    // 使用 TechnicalIndicatorService 計算 RSI（gapBefore 避免跨停牌缺口的
    // 價差被誤採計為單一交易日變動，產生虛假極端 RSI 觸發警示）
    final rsiValues = _indicatorService.calculateRSI(
      ohlcv.closes,
      period: 14,
      gapBefore: ohlcv.gapBefore,
    );

    final latestRsi = rsiValues.last;
    if (latestRsi == null) return false;

    return latestRsi >= targetRsi;
  }

  /// 檢查 RSI 超賣（RSI <= 目標值，如 30）
  bool _checkRsiOversold(List<DailyPriceEntry> prices, double targetRsi) {
    if (prices.length < AlertParams.rsiMinDataPoints) return false;

    final ohlcv = prices.extractOhlcv();
    if (ohlcv.closes.length < AlertParams.rsiMinDataPoints) return false;

    final rsiValues = _indicatorService.calculateRSI(
      ohlcv.closes,
      period: 14,
      gapBefore: ohlcv.gapBefore,
    );

    final latestRsi = rsiValues.last;
    if (latestRsi == null) return false;

    return latestRsi <= targetRsi;
  }

  /// 檢查 KD 黃金交叉（K 上穿 D）
  ///
  /// 檢查最近 2 天內是否發生過黃金交叉。
  /// 簡化版本：只檢查交叉本身，不要求在低檔區。
  bool _checkKdGoldenCross(List<DailyPriceEntry> prices) {
    if (prices.length < AlertParams.kdMinDataPoints) return false;

    final ohlcv = prices.extractOhlcv();
    final highs = ohlcv.highs;
    final lows = ohlcv.lows;
    final closes = ohlcv.closes;
    final gapBefore = ohlcv.gapBefore;

    if (highs.length < 11) return false;

    final kd = _indicatorService.calculateKD(
      highs,
      lows,
      closes,
      kPeriod: 9,
      dPeriod: 3,
    );

    if (kd.k.length < 2 || kd.d.length < 2) return false;

    // 檢查最近 2 天內是否發生過黃金交叉
    final startIndex = kd.k.length >= 3 ? kd.k.length - 3 : 0;
    for (int i = startIndex; i < kd.k.length - 1; i++) {
      // i 與 i+1 之間若跨停牌缺口，i 並非真正的「前一交易日」，略過避免
      // 把跨數日的漂移誤判為交叉
      if (gapBefore[i + 1]) continue;

      final prevK = kd.k[i];
      final prevD = kd.d[i];
      final nextK = kd.k[i + 1];
      final nextD = kd.d[i + 1];

      if (prevK != null && prevD != null && nextK != null && nextD != null) {
        // K 上穿 D（前一天 K < D，今天 K >= D）
        if (prevK < prevD && nextK >= nextD) {
          return true;
        }
      }
    }

    return false;
  }

  /// 檢查 KD 死亡交叉（K 下穿 D）
  ///
  /// 檢查最近 2 天內是否發生過死亡交叉。
  /// 簡化版本：只檢查交叉本身，不要求在高檔區。
  bool _checkKdDeathCross(List<DailyPriceEntry> prices) {
    if (prices.length < AlertParams.kdMinDataPoints) return false;

    final ohlcv = prices.extractOhlcv();
    final highs = ohlcv.highs;
    final lows = ohlcv.lows;
    final closes = ohlcv.closes;
    final gapBefore = ohlcv.gapBefore;

    if (highs.length < 11) return false;

    final kd = _indicatorService.calculateKD(
      highs,
      lows,
      closes,
      kPeriod: 9,
      dPeriod: 3,
    );

    if (kd.k.length < 2 || kd.d.length < 2) return false;

    // 檢查最近 2 天內是否發生過死亡交叉
    final startIndex = kd.k.length >= 3 ? kd.k.length - 3 : 0;
    for (int i = startIndex; i < kd.k.length - 1; i++) {
      if (gapBefore[i + 1]) continue;

      final prevK = kd.k[i];
      final prevD = kd.d[i];
      final nextK = kd.k[i + 1];
      final nextD = kd.d[i + 1];

      if (prevK != null && prevD != null && nextK != null && nextD != null) {
        // K 下穿 D（前一天 K > D，今天 K <= D）
        if (prevK > prevD && nextK <= nextD) {
          return true;
        }
      }
    }

    return false;
  }

  // ==================================================
  // 警示檢查輔助方法 - 均線交叉警示
  // ==================================================

  /// 檢查股價突破均線（價格由下往上穿越均線）
  ///
  /// 檢查最近 2 天內是否發生過突破。
  bool _checkCrossAboveMa(List<DailyPriceEntry> prices, int maDays) {
    if (prices.length < maDays + 2) return false;

    final closes = prices.map((p) => p.close).whereType<double>().toList();
    if (closes.length < maDays + 2) return false;

    final maValues = _indicatorService.calculateSMA(closes, maDays);

    if (maValues.length < 2) return false;

    // 檢查最近 2 天內是否發生過突破
    final startIndex = maValues.length >= 3 ? maValues.length - 3 : 0;
    for (int i = startIndex; i < maValues.length - 1; i++) {
      final prevClose = closes[i];
      final prevMa = maValues[i];
      final nextClose = closes[i + 1];
      final nextMa = maValues[i + 1];

      if (prevMa != null && nextMa != null) {
        // 價格由下往上穿越均線（前一天 close < MA，今天 close >= MA）
        if (prevClose < prevMa && nextClose >= nextMa) {
          return true;
        }
      }
    }

    return false;
  }

  /// 檢查股價跌破均線（價格由上往下穿越均線）
  ///
  /// 檢查最近 2 天內是否發生過跌破。
  bool _checkCrossBelowMa(List<DailyPriceEntry> prices, int maDays) {
    if (prices.length < maDays + 2) return false;

    final closes = prices.map((p) => p.close).whereType<double>().toList();
    if (closes.length < maDays + 2) return false;

    final maValues = _indicatorService.calculateSMA(closes, maDays);

    if (maValues.length < 2) return false;

    // 檢查最近 2 天內是否發生過跌破
    final startIndex = maValues.length >= 3 ? maValues.length - 3 : 0;
    for (int i = startIndex; i < maValues.length - 1; i++) {
      final prevClose = closes[i];
      final prevMa = maValues[i];
      final nextClose = closes[i + 1];
      final nextMa = maValues[i + 1];

      if (prevMa != null && nextMa != null) {
        // 價格由上往下穿越均線（前一天 close > MA，今天 close <= MA）
        if (prevClose > prevMa && nextClose <= nextMa) {
          return true;
        }
      }
    }

    return false;
  }
}
