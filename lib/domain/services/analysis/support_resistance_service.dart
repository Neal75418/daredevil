import 'package:daredevil/core/constants/rule_params.dart';
import 'package:daredevil/core/utils/list_helper.dart';
import 'package:daredevil/data/database/app_database.dart';

/// 支撐壓力檢測服務
///
/// 負責計算股票的支撐位、壓力位以及價格區間
/// 使用波段高低點聚類演算法識別關鍵價位
class SupportResistanceService {
  /// 找出支撐與壓力位
  ///
  /// 使用波段點聚類演算法，結合觸及次數、時近性、距離衰減三因子綜合評分
  (double?, double?) findSupportResistance(List<DailyPriceEntry> prices) {
    if (prices.length < RuleParams.swingWindow * 2) {
      return (null, null);
    }

    // 找出所有波段高點與低點
    final (:highs, :lows) = _detectSwingPoints(prices);

    // 取得當前價格作為參考。
    //
    // **末根停牌時退回最後一個有效收盤**（2026-08-29 稽核 M10）：舊碼在
    // `prices.last.close == null` 時直接回最後一個 swing 高/低點，那條路徑
    // 既沒有距離上界、也沒有檢查方向，於是會回報「高於現價的支撐」
    // （實測 fixture：最後有效收盤 80.0、回報支撐 94.05）。
    //
    // 觸發前提確實存在：上游 `classifyCandidate` 只保證**完整歷史**的末根
    // 有收盤，而 `analysis_coordinator_service` 傳進來的是 priorHistory
    // ——末根是倒數第二根，不受那道保證涵蓋（2026-08-28 實測 20 檔倒數第二
    // 根停牌）。⚠️ 那 20 檔當天都沒真的走到這裡（末根量 0–23,065 股，全被
    // `LiquidityChecker` 擋在 `analyzeStock` 之外）；可達性來自自選股的
    // `exemptFromLiquidity` 豁免——被豁免的正是這種低量標的。
    final currentClose = _lastValidClose(prices);
    if (currentClose == null) return (null, null);

    // 聚類波段點並找出最顯著的關卡
    final resistanceZones = _clusterSwingPoints(highs, prices.length);
    final supportZones = _clusterSwingPoints(lows, prices.length);

    // ATR-based 動態距離：高波動股用更寬的搜尋半徑
    final atrDistance = _calculateATRDistance(prices, currentClose);
    final maxDistance = atrDistance ?? TrendParams.maxSupportResistanceDistance;

    final maxResistance = currentClose * (1 + maxDistance);
    final minSupport = currentClose * (1 - maxDistance);

    // 找出最佳壓力與支撐
    var resistance = _scoreBestZone(
      resistanceZones,
      currentClose,
      above: true,
      boundPrice: maxResistance,
    );
    var support = _scoreBestZone(
      supportZones,
      currentClose,
      above: false,
      boundPrice: minSupport,
    );

    // 僅在最大距離內才回退至最近的波段點
    if (resistance == null && highs.isNotEmpty) {
      final lastHigh = highs.last.price;
      if (lastHigh > currentClose && lastHigh <= maxResistance) {
        resistance = lastHigh;
      }
    }
    if (support == null && lows.isNotEmpty) {
      final lastLow = lows.last.price;
      if (lastLow < currentClose && lastLow >= minSupport) {
        support = lastLow;
      }
    }

    return (support, resistance);
  }

  /// 找出 60 日價格區間
  ///
  /// 回傳 (區間底部, 區間頂部) 元組
  (double?, double?) findRange(List<DailyPriceEntry> prices) {
    final rangePrices = lastN(prices, RuleParams.rangeLookback);

    if (rangePrices.isEmpty) return (null, null);

    double? rangeHigh;
    double? rangeLow;

    for (final price in rangePrices) {
      final high = price.high;
      final low = price.low;

      if (high != null && (rangeHigh == null || high > rangeHigh)) {
        rangeHigh = high;
      }
      if (low != null && (rangeLow == null || low < rangeLow)) {
        rangeLow = low;
      }
    }

    return (rangeLow, rangeHigh);
  }

  // ==================================================
  // 私有輔助方法
  // ==================================================

  /// 將波段點聚類為價格區域
  ///
  /// 將差距在 [_clusterThreshold]（2%）以內的點分為一組
  List<_PriceZone> _clusterSwingPoints(
    List<_SwingPoint> points,
    int totalDataPoints,
  ) {
    if (points.isEmpty) return [];

    // 依價格排序
    final sorted = List<_SwingPoint>.from(points)
      ..sort((a, b) => a.price.compareTo(b.price));

    final zones = <_PriceZone>[];
    var currentZonePoints = <_SwingPoint>[sorted.first];

    for (var i = 1; i < sorted.length; i++) {
      final point = sorted[i];
      // 與 zone 的**錨點(第一個點,已排序故為最低價)**比較,不是跑動平均
      // (2026-08-15 數值稽核):用平均當基準會鏈式漂移——每收一個點平均
      // 就往上移,下一個點又以新平均為基準,一個 zone 實際可跨到約
      // 2×threshold(3.9%)。而回報值是 zone 的平均價,跨 3.9% 的 zone
      // 其平均離兩端最遠成員 1.9%,可能是**沒有任何波段點碰過的價位**。
      //
      // 改用固定錨點後上界回到 threshold(2%)。實測影響很小:真實資料
      // 119 檔中回報值偏離最近真實高/低點 >0.5% 的僅 1 檔、最遠 0.67%
      // ——理論缺陷成立,但等距密集的波段點在真實市場罕見。
      final anchor = currentZonePoints.first.price;

      // 防止除以零（雖然價格不應為 0）
      final isWithinThreshold = anchor > 0
          ? (point.price - anchor).abs() / anchor <= _clusterThreshold
          : true; // 若錨點為 0，將所有零價格點歸為一組
      if (isWithinThreshold) {
        currentZonePoints.add(point);
      } else {
        // 儲存當前區域並開始新區域
        zones.add(_createZone(currentZonePoints, totalDataPoints));
        currentZonePoints = [point];
      }
    }

    // 別忘了最後一個區域
    if (currentZonePoints.isNotEmpty) {
      zones.add(_createZone(currentZonePoints, totalDataPoints));
    }

    return zones;
  }

  /// 從波段點列表建立價格區域
  ///
  /// 前置條件：[points] 不可為空
  _PriceZone _createZone(List<_SwingPoint> points, int totalDataPoints) {
    assert(points.isNotEmpty, '_createZone called with empty points list');

    final prices = points.map((p) => p.price);
    final avgPrice = prices.reduce((a, b) => a + b) / points.length;
    final maxIndex = points.map((p) => p.index).reduce((a, b) => a > b ? a : b);
    // 時近性權重：越近期 = 權重越高（0.0 到 1.0）
    final recencyWeight = totalDataPoints > 0
        ? maxIndex / totalDataPoints
        : 0.5;

    return _PriceZone(
      avgPrice: avgPrice,
      touches: points.length,
      recencyWeight: recencyWeight,
    );
  }

  /// 偵測價格序列中的波段高低點
  ({List<_SwingPoint> highs, List<_SwingPoint> lows}) _detectSwingPoints(
    List<DailyPriceEntry> prices,
  ) {
    final swingHighs = <_SwingPoint>[];
    final swingLows = <_SwingPoint>[];

    const halfWindow = RuleParams.swingWindow ~/ 2;

    for (var i = halfWindow; i < prices.length - halfWindow; i++) {
      final current = prices[i];
      final high = current.high;
      final low = current.low;

      if (high == null || low == null) continue;

      var isSwingHigh = true;
      var isSwingLow = true;

      for (var j = i - halfWindow; j <= i + halfWindow; j++) {
        if (j == i) continue;
        final other = prices[j];

        if (isSwingHigh && other.high != null && other.high! > high) {
          isSwingHigh = false;
        }
        if (isSwingLow && other.low != null && other.low! < low) {
          isSwingLow = false;
        }

        if (!isSwingHigh && !isSwingLow) break;
      }

      if (isSwingHigh) swingHighs.add(_SwingPoint(price: high, index: i));
      if (isSwingLow) swingLows.add(_SwingPoint(price: low, index: i));
    }

    return (highs: swingHighs, lows: swingLows);
  }

  /// 從區域列表中找出最佳評分的關卡價位
  ///
  /// [above] 為 true 時搜尋壓力（現價上方），false 時搜尋支撐（現價下方）。
  /// 使用觸及次數、時近性、距離衰減三因子綜合評分。
  double? _scoreBestZone(
    List<_PriceZone> zones,
    double currentClose, {
    required bool above,
    required double boundPrice,
  }) {
    double? bestPrice;
    var bestScore = 0.0;

    for (final zone in zones) {
      final inRange = above
          ? (zone.avgPrice > currentClose && zone.avgPrice <= boundPrice)
          : (zone.avgPrice < currentClose && zone.avgPrice >= boundPrice);

      if (inRange) {
        final distance = (zone.avgPrice - currentClose).abs();
        final distanceFactor =
            1.0 /
            (1.0 + (distance / currentClose) * TrendParams.distanceDecayFactor);
        final score = zone.touches * (1 + zone.recencyWeight) * distanceFactor;
        if (score > bestScore) {
          bestScore = score;
          bestPrice = zone.avgPrice;
        }
      }
    }

    return bestPrice;
  }

  /// 由新到舊找出第一個可用的收盤價（跳過停牌根）
  ///
  /// 全部停牌／無有效收盤時回 null——此時沒有任何可參照的價位，
  /// 關卡只能是 null，不能拿波段點硬湊。
  double? _lastValidClose(List<DailyPriceEntry> prices) {
    for (var i = prices.length - 1; i >= 0; i--) {
      final close = prices[i].close;
      if (close != null && close > 0) return close;
    }
    return null;
  }

  /// 計算 ATR-based 動態距離
  ///
  /// 回傳值是相對價格的比例（如 0.1 表示 10%）
  double? _calculateATRDistance(
    List<DailyPriceEntry> prices,
    double currentClose,
  ) {
    if (prices.length < 20 || currentClose <= 0) return null;

    final recentPrices = prices.length > 20
        ? prices.sublist(prices.length - 20)
        : prices;

    double sumTR = 0;
    var count = 0;

    for (var i = 1; i < recentPrices.length; i++) {
      final current = recentPrices[i];
      final prev = recentPrices[i - 1];

      final high = current.high;
      final low = current.low;
      final prevClose = prev.close;

      if (high != null && low != null && prevClose != null) {
        final tr1 = high - low;
        final tr2 = (high - prevClose).abs();
        final tr3 = (low - prevClose).abs();
        sumTR += [tr1, tr2, tr3].reduce((a, b) => a > b ? a : b);
        count++;
      }
    }

    if (count == 0) return null;

    final atr = sumTR / count;
    return (atr / currentClose) * TrendParams.atrDistanceMultiplier;
  }

  /// 波段點聚類閾值
  static const _clusterThreshold = TrendParams.clusterThreshold;
}

// ==================================================
// 私有輔助類別（僅在此服務內部使用）
// ==================================================

/// 帶有價格與位置索引的波段點
class _SwingPoint {
  const _SwingPoint({required this.price, required this.index});

  final double price;
  final int index;
}

/// 代表聚類波段點的價格區域
class _PriceZone {
  const _PriceZone({
    required this.avgPrice,
    required this.touches,
    required this.recencyWeight,
  });

  /// 此區域所有點的平均價格
  final double avgPrice;

  /// 觸及此區域的波段點數量
  final int touches;

  /// 依觸及時間的時近性權重（0.0 到 1.0）
  final double recencyWeight;
}
