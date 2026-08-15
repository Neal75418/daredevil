import 'package:daredevil/core/constants/analysis_params.dart';
import 'package:daredevil/core/utils/clock.dart';
import 'package:daredevil/data/database/app_database.dart';

/// 股利智慧分析服務
///
/// 提供股利相關的計算與預測：
/// - 持倉預期年度股利
/// - 個人殖利率（以成本計算）
/// - 股利趨勢分析
class DividendIntelligenceService {
  const DividendIntelligenceService({AppClock clock = const SystemClock()})
    : _clock = clock;

  final AppClock _clock;

  /// 計算持倉的股利預測資訊
  ///
  /// [positions] 持倉列表
  /// [dividendHistories] symbol -> 股利歷史
  /// [currentPrices] symbol -> 目前價格
  DividendAnalysis analyzeDividends({
    required List<PortfolioPositionEntry> positions,
    required Map<String, List<DividendHistoryEntry>> dividendHistories,
    required Map<String, double> currentPrices,
  }) {
    if (positions.isEmpty) return DividendAnalysis.empty;

    double totalExpectedDividend = 0;
    double totalCostBasis = 0;
    double totalMarketValue = 0;
    final stockDividends = <StockDividendInfo>[];

    for (final pos in positions) {
      if (pos.quantity <= 0) continue;

      final history = dividendHistories[pos.symbol] ?? [];
      final currentPrice = currentPrices[pos.symbol] ?? pos.avgCost;
      final costBasis = pos.quantity * pos.avgCost;
      final marketValue = pos.quantity * currentPrice;

      totalCostBasis += costBasis;
      totalMarketValue += marketValue;

      // 預估年度股利（使用最近一年或平均）
      final estimatedDividend = _estimateAnnualDividend(history);
      final expectedYearlyAmount = estimatedDividend * pos.quantity;
      totalExpectedDividend += expectedYearlyAmount;

      // 計算殖利率
      final personalYield = costBasis > 0
          ? (expectedYearlyAmount / costBasis) * 100
          : 0.0;
      // 股利趨勢
      final trend = _analyzeTrend(history);

      stockDividends.add(
        StockDividendInfo(
          symbol: pos.symbol,
          estimatedDividendPerShare: estimatedDividend,
          expectedYearlyAmount: expectedYearlyAmount,
          personalYield: personalYield,
          trend: trend,
        ),
      );
    }

    // 計算組合整體殖利率
    final portfolioYieldOnCost = totalCostBasis > 0
        ? (totalExpectedDividend / totalCostBasis) * 100
        : 0.0;
    final portfolioYieldOnMarket = totalMarketValue > 0
        ? (totalExpectedDividend / totalMarketValue) * 100
        : 0.0;

    // 按預期股利金額排序
    stockDividends.sort(
      (a, b) => b.expectedYearlyAmount.compareTo(a.expectedYearlyAmount),
    );

    return DividendAnalysis(
      totalExpectedDividend: totalExpectedDividend,
      portfolioYieldOnCost: portfolioYieldOnCost,
      portfolioYieldOnMarket: portfolioYieldOnMarket,
      stockDividends: stockDividends,
    );
  }

  /// 預估年度股利（每股）
  ///
  /// 策略：
  /// 1. 如果有當年度資料，使用當年度
  /// 2. 否則使用最近 3 年平均
  /// 3. 若資料不足，使用最近一年
  double _estimateAnnualDividend(List<DividendHistoryEntry> history) {
    if (history.isEmpty) return 0;

    final currentYear = _clock.now().year;

    // 只採計「最近 N 個**年度**」——不是 take(N) 取最近 N 筆
    // (2026-08-15 稽核:年度分布有 2021–2024 空洞,745 檔的歷史只有
    // 2018–2020,take(3) 會拿六到八年前的配息當最近三年)
    final windowStart = currentYear - AnalysisParams.dividendLookbackYears;
    final inWindow = history.where((h) => h.year >= windowStart);

    // **只算現金股利**:股票股利的單位是面額元(配 2 元 = 每股配 0.2 股),
    // 與現金不同幣值,相加沒有意義;而殖利率的標準定義本就是現金殖利率。
    final declaredThisYear = inWindow
        .where((h) => h.year == currentYear && h.cashDividend > 0)
        .toList();
    if (declaredThisYear.isNotEmpty) {
      return declaredThisYear.first.cashDividend;
    }

    // 當年度可能已建列但金額為 0(尚未宣告)——那是「還沒公布」不是
    // 「決定不配」,要退回窗口內平均而非回傳 0
    final valid = inWindow.where((h) => h.cashDividend > 0).toList();
    if (valid.isEmpty) return 0;

    final total = valid.fold<double>(0, (sum, h) => sum + h.cashDividend);
    return total / valid.length;
  }

  /// 分析股利趨勢
  ///
  /// [history] 必須為 year DESC 排序（最新年份在前），
  /// 由 dividend_dao 的 ORDER BY year DESC 保證。
  DividendTrend _analyzeTrend(List<DividendHistoryEntry> history) {
    if (history.length < 2) return DividendTrend.stable;

    // 防禦性排序：確保最新年份在前（正常路徑由 DAO 保證）
    if (history.first.year < history[1].year) {
      history = List.of(history)..sort((a, b) => b.year.compareTo(a.year));
    }

    // 比較最近兩年的股利變化
    final recent = history.first;
    final previous = history[1];

    final recentTotal = recent.cashDividend + recent.stockDividend;
    final previousTotal = previous.cashDividend + previous.stockDividend;

    if (previousTotal == 0) {
      return recentTotal > 0 ? DividendTrend.increasing : DividendTrend.stable;
    }

    final changePercent = ((recentTotal - previousTotal) / previousTotal) * 100;

    if (changePercent > 10) {
      return DividendTrend.increasing;
    } else if (changePercent < -10) {
      return DividendTrend.decreasing;
    } else {
      return DividendTrend.stable;
    }
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

  /// 預期年度股利總額
  final double totalExpectedDividend;

  /// 組合殖利率（以成本計算）
  final double portfolioYieldOnCost;

  /// 組合殖利率（以市價計算）
  final double portfolioYieldOnMarket;

  /// 各持股的股利資訊
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

  /// 預估每股股利
  final double estimatedDividendPerShare;

  /// 預期年度股利金額
  final double expectedYearlyAmount;

  /// 個人殖利率（以成本計算）
  final double personalYield;

  /// 股利趨勢
  final DividendTrend trend;
}

/// 股利趨勢
enum DividendTrend { increasing, stable, decreasing }
