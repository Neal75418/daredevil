import 'package:daredevil/core/constants/analysis_params.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/domain/services/dividend_summary.dart';

/// 官方估值的殖利率（%）與同一天的收盤價：殖利率 ÷ 100 × 收盤價＝交易所
/// 計算殖利率用的每股股利
typedef OfficialYield = ({double yieldPercent, double close});

/// 投資組合的股利分析
///
/// - 預估年股利（每股）：有官方估值者＝官方殖利率 × 同一天收盤價；其餘
///   （ETF、無估值）＝近一年殖利率 × 最新收盤價。無法預估（近一年殖利率建置
///   中，或沒有最新收盤）時為 null
/// - 趨勢：最近兩個完整年度的現金股利（不受面額影響）；任一年建置中為 null
class DividendIntelligenceService {
  const DividendIntelligenceService();

  /// [summaries]、[officialYields]、[currentPrices] 都以 symbol 為鍵；
  /// [officialYields] 只放可用的官方估值（近期、殖利率有值、估值日查得到收盤價）
  DividendAnalysis analyzeDividends({
    required List<PortfolioPositionEntry> positions,
    required Map<String, DividendSummary> summaries,
    required Map<String, OfficialYield> officialYields,
    required Map<String, double> currentPrices,
  }) {
    if (positions.isEmpty) return DividendAnalysis.empty;

    double? totalExpected = 0;
    double totalCostBasis = 0;
    double totalMarketValue = 0;
    final stockDividends = <StockDividendInfo>[];

    for (final pos in positions) {
      if (pos.quantity <= 0) continue;

      final latestClose = currentPrices[pos.symbol];
      final costBasis = pos.quantity * pos.avgCost;
      totalCostBasis += costBasis;
      totalMarketValue += pos.quantity * (latestClose ?? pos.avgCost);

      final summary = summaries[pos.symbol];
      final perShare = _estimatePerShare(
        officialYields[pos.symbol],
        summary,
        latestClose,
      );
      final expected = perShare == null ? null : perShare * pos.quantity;
      // 任一持股無法預估，合計就不可知：不加部分總和
      totalExpected = totalExpected == null || expected == null
          ? null
          : totalExpected + expected;

      stockDividends.add(
        StockDividendInfo(
          symbol: pos.symbol,
          estimatedDividendPerShare: perShare,
          expectedYearlyAmount: expected,
          personalYield: expected == null
              ? null
              : costBasis > 0
              ? expected / costBasis * 100
              : 0.0,
          trend: _trend(summary),
        ),
      );
    }

    stockDividends.sort(_byExpectedDesc);

    return DividendAnalysis(
      totalExpectedDividend: totalExpected,
      portfolioYieldOnCost: totalExpected == null
          ? null
          : totalCostBasis > 0
          ? totalExpected / totalCostBasis * 100
          : 0.0,
      portfolioYieldOnMarket: totalExpected == null
          ? null
          : totalMarketValue > 0
          ? totalExpected / totalMarketValue * 100
          : 0.0,
      stockDividends: stockDividends,
    );
  }

  double? _estimatePerShare(
    OfficialYield? official,
    DividendSummary? summary,
    double? latestClose,
  ) {
    if (official != null) return official.yieldPercent / 100 * official.close;
    return switch (summary?.trailingYield) {
      TrailingYieldValue(:final ratio) =>
        latestClose == null ? null : ratio * latestClose,
      TrailingYieldNone() => 0.0,
      TrailingYieldBuilding() || null => null,
    };
  }

  DividendTrend? _trend(DividendSummary? summary) {
    if (summary?.pastYears case [final recent, final previous, ...]) {
      if (recent.status == DividendYearStatus.building ||
          previous.status == DividendYearStatus.building) {
        return null;
      }
      if (previous.cash == 0) {
        return recent.cash > 0
            ? DividendTrend.increasing
            : DividendTrend.stable;
      }
      final changePercent = (recent.cash - previous.cash) / previous.cash * 100;
      if (changePercent > AnalysisParams.dividendTrendChangePercent) {
        return DividendTrend.increasing;
      }
      if (changePercent < -AnalysisParams.dividendTrendChangePercent) {
        return DividendTrend.decreasing;
      }
      return DividendTrend.stable;
    }
    return null;
  }

  /// 預期金額由大到小；無法預估（null）的排最後
  static int _byExpectedDesc(StockDividendInfo a, StockDividendInfo b) {
    final x = a.expectedYearlyAmount;
    final y = b.expectedYearlyAmount;
    if (x == null) return y == null ? 0 : 1;
    if (y == null) return -1;
    return y.compareTo(x);
  }
}

/// 股利分析結果
class DividendAnalysis {
  const DividendAnalysis({
    required this.totalExpectedDividend,
    required this.portfolioYieldOnCost,
    required this.portfolioYieldOnMarket,
    required this.stockDividends,
  });

  /// 預期年度股利總額；任一持股無法預估時為 null
  final double? totalExpectedDividend;

  /// 組合殖利率（以成本計算，%）；同上
  final double? portfolioYieldOnCost;

  /// 組合殖利率（以市價計算，%）；同上
  final double? portfolioYieldOnMarket;

  /// 各持股的股利資訊：預期金額由大到小，無法預估的排最後
  final List<StockDividendInfo> stockDividends;

  static const empty = DividendAnalysis(
    totalExpectedDividend: 0,
    portfolioYieldOnCost: 0,
    portfolioYieldOnMarket: 0,
    stockDividends: [],
  );
}

/// 單一持股的股利資訊
class StockDividendInfo {
  const StockDividendInfo({
    required this.symbol,
    required this.estimatedDividendPerShare,
    required this.expectedYearlyAmount,
    required this.personalYield,
    required this.trend,
  });

  final String symbol;

  /// 預估每股年股利（元）；無法預估時為 null
  final double? estimatedDividendPerShare;

  /// 預期年度股利金額；無法預估時為 null
  final double? expectedYearlyAmount;

  /// 個人殖利率（以成本計算，%）；無法預估時為 null
  final double? personalYield;

  /// 股利趨勢；最近兩個完整年度任一年建置中時為 null（不顯示）
  final DividendTrend? trend;
}

/// 股利趨勢
enum DividendTrend { increasing, stable, decreasing }
