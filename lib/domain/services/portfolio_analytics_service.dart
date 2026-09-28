import 'dart:math' as math;

import 'package:daredevil/core/constants/transaction_types.dart';
import 'package:daredevil/core/utils/clock.dart';
import 'package:daredevil/data/database/app_database.dart';

/// 投資組合績效分析服務
///
/// 提供各種績效指標計算：
/// - Total Return（總報酬率）
/// - Period Return（期間報酬）
/// - Max Drawdown（最大回撤）
/// - Industry Allocation（產業配置）
class PortfolioAnalyticsService {
  const PortfolioAnalyticsService({AppClock clock = const SystemClock()})
    : _clock = clock;

  final AppClock _clock;

  /// 計算投資組合績效
  ///
  /// [transactions] 所有交易紀錄（按日期升序排列）
  /// [positions] 目前持倉
  /// [currentPrices] symbol -> 目前價格
  /// [stocksMap] symbol -> 股票資訊
  PortfolioPerformance calculatePerformance({
    required List<PortfolioTransactionEntry> transactions,
    required List<PortfolioPositionEntry> positions,
    required Map<String, double> currentPrices,
    required Map<String, StockMasterEntry> stocksMap,
  }) {
    if (transactions.isEmpty && positions.isEmpty) {
      return PortfolioPerformance.empty;
    }

    // 計算持倉成本和市值
    double totalCostBasis = 0;
    double totalMarketValue = 0;
    double totalDividends = 0;
    double totalRealizedPnl = 0;

    for (final pos in positions) {
      totalCostBasis += pos.avgCost * pos.quantity;
      final price = currentPrices[pos.symbol] ?? pos.avgCost;
      totalMarketValue += price * pos.quantity;
      totalDividends += pos.totalDividendReceived;
      totalRealizedPnl += pos.realizedPnl;
    }

    // 計算歷史總買入成本（含已平倉），作為 totalReturn 的正確分母
    // 避免僅用持倉成本（totalCostBasis）導致已實現損益膨脹回報率
    double totalHistoricalBuyCost = 0;
    double totalSellProceeds = 0;
    for (final tx in transactions) {
      if (tx.txType == TransactionTypes.buy) {
        totalHistoricalBuyCost += tx.quantity * tx.price + tx.fee;
      } else if (tx.txType == TransactionTypes.sell) {
        totalSellProceeds += tx.quantity * tx.price - tx.fee - tx.tax;
      }
    }

    // 總報酬 = (當前市值 + 已收股利 + 已賣出收入 - 歷史總買入成本) / 歷史總買入成本
    final totalReturn = totalHistoricalBuyCost > 0
        ? ((totalMarketValue +
                      totalDividends +
                      totalSellProceeds -
                      totalHistoricalBuyCost) /
                  totalHistoricalBuyCost) *
              100
        : 0.0;

    // 期間報酬
    final periodReturns = _calculatePeriodReturns(
      transactions: transactions,
      positions: positions,
      currentPrices: currentPrices,
    );

    // 當前回撤（從成本基準計算，非歷史最大回撤）
    final maxDrawdown = _calculateCurrentDrawdown(
      transactions: transactions,
      positions: positions,
      currentPrices: currentPrices,
    );

    // 產業配置
    final industryAllocation = _calculateIndustryAllocation(
      positions: positions,
      currentPrices: currentPrices,
      stocksMap: stocksMap,
    );

    return PortfolioPerformance(
      totalReturn: totalReturn,
      totalMarketValue: totalMarketValue,
      totalCostBasis: totalCostBasis,
      totalDividends: totalDividends,
      totalRealizedPnl: totalRealizedPnl,
      periodReturns: periodReturns,
      maxDrawdown: maxDrawdown,
      industryAllocation: industryAllocation,
    );
  }

  /// 計算期間報酬
  PeriodReturns _calculatePeriodReturns({
    required List<PortfolioTransactionEntry> transactions,
    required List<PortfolioPositionEntry> positions,
    required Map<String, double> currentPrices,
  }) {
    if (transactions.isEmpty) {
      return PeriodReturns.empty;
    }

    // 找出最早和最近的交易
    final sortedTx = List.of(transactions)
      ..sort((a, b) => a.date.compareTo(b.date));
    final firstTxDate = sortedTx.first.date;

    // 計算目前總市值與已收股利
    double currentValue = 0;
    double totalDividends = 0;
    for (final pos in positions) {
      final price = currentPrices[pos.symbol] ?? pos.avgCost;
      currentValue += price * pos.quantity;
      totalDividends += pos.totalDividendReceived;
    }

    // 計算總買入成本（所有 BUY 的現金流出）作為報酬率分母
    // 不扣除 SELL proceeds，避免獲利 portfolio 分母變 ≤ 0
    double totalBuyCost = 0;
    double totalSellProceeds = 0;
    for (final tx in sortedTx) {
      if (tx.txType == TransactionTypes.buy) {
        totalBuyCost += tx.quantity * tx.price + tx.fee;
      } else if (tx.txType == TransactionTypes.sell) {
        totalSellProceeds += tx.quantity * tx.price - tx.fee - tx.tax;
      }
    }

    if (totalBuyCost <= 0) {
      return PeriodReturns.empty;
    }

    // 計算持有天數
    final daysSinceStart = _clock.now().difference(firstTxDate).inDays;
    if (daysSinceStart == 0) {
      return PeriodReturns.empty;
    }

    // 總報酬率 = (當前市值 + 已收股利 + 已賣出收入 - 總買入成本) / 總買入成本
    final totalReturn =
        ((currentValue + totalDividends + totalSellProceeds - totalBuyCost) /
            totalBuyCost) *
        100;

    // 日報酬（簡化計算）
    final dailyReturn = totalReturn / daysSinceStart;

    // 週報酬
    final weekReturn = daysSinceStart >= 7 ? dailyReturn * 7 : totalReturn;

    // 月報酬
    final monthReturn = daysSinceStart >= 30 ? dailyReturn * 30 : totalReturn;

    // 年報酬（年化）
    // < 30 天：用線性外推（日報酬 × 365），避免短期複利公式產生極端數字
    final double yearReturn;
    if (daysSinceStart < 30) {
      yearReturn = dailyReturn * 365;
    } else {
      yearReturn =
          (math.pow(1 + totalReturn / 100, 365 / daysSinceStart) - 1)
              .toDouble() *
          100;
    }

    // NaN/Infinity 防護（totalReturn < -100% 時 math.pow 可能產生 NaN）
    final safeYearReturn = yearReturn.isNaN || yearReturn.isInfinite
        ? totalReturn.clamp(-100.0, 1000.0)
        : yearReturn;

    return PeriodReturns(
      daily: dailyReturn,
      weekly: weekReturn,
      monthly: monthReturn,
      yearly: safeYearReturn.clamp(-100.0, 1000.0), // 限制極端值
    );
  }

  /// 計算當前回撤（從成本基準 vs 當前市值）
  ///
  /// 注意：此方法計算的是「當前回撤」而非真正的「最大歷史回撤」。
  /// 峰值取 max(成本, 市值)，不追蹤歷史淨值曲線。
  /// 欄位名稱保留 maxDrawdown 以維持 API 相容性。
  double _calculateCurrentDrawdown({
    required List<PortfolioTransactionEntry> transactions,
    required List<PortfolioPositionEntry> positions,
    required Map<String, double> currentPrices,
  }) {
    if (transactions.isEmpty) return 0;

    // 簡化計算：基於持倉的成本與市值差距
    double peak = 0;
    double maxDrawdown = 0;

    // 計算當前總市值
    double currentValue = 0;
    double totalCost = 0;

    for (final pos in positions) {
      final price = currentPrices[pos.symbol] ?? pos.avgCost;
      currentValue += price * pos.quantity;
      totalCost += pos.avgCost * pos.quantity;
    }

    // 簡化：以 max(成本, 市值) 當峰值，等於未實現虧損佔成本的比例
    peak = math.max(totalCost, currentValue);

    if (peak > 0 && currentValue < peak) {
      maxDrawdown = ((peak - currentValue) / peak) * 100;
    }

    return maxDrawdown;
  }

  /// 計算產業配置
  Map<String, IndustryAllocation> _calculateIndustryAllocation({
    required List<PortfolioPositionEntry> positions,
    required Map<String, double> currentPrices,
    required Map<String, StockMasterEntry> stocksMap,
  }) {
    if (positions.isEmpty) return {};

    // 計算總市值
    double totalValue = 0;
    final industryValues = <String, double>{};
    final industrySymbols = <String, List<String>>{};

    for (final pos in positions) {
      if (pos.quantity <= 0) continue;

      final price = currentPrices[pos.symbol] ?? pos.avgCost;
      final value = price * pos.quantity;
      totalValue += value;

      final stock = stocksMap[pos.symbol];
      final industry = stock?.industry ?? '其他';

      industryValues[industry] = (industryValues[industry] ?? 0) + value;
      industrySymbols.putIfAbsent(industry, () => []).add(pos.symbol);
    }

    if (totalValue <= 0) return {};

    return {
      for (final entry in industryValues.entries)
        entry.key: IndustryAllocation(
          industry: entry.key,
          value: entry.value,
          percentage: (entry.value / totalValue) * 100,
          symbols: industrySymbols[entry.key] ?? [],
        ),
    };
  }
}

/// 投資組合績效資料
class PortfolioPerformance {
  const PortfolioPerformance({
    required this.totalReturn,
    required this.totalMarketValue,
    required this.totalCostBasis,
    required this.totalDividends,
    required this.totalRealizedPnl,
    required this.periodReturns,
    required this.maxDrawdown,
    required this.industryAllocation,
  });

  /// 總報酬率（%）
  final double totalReturn;

  /// 目前總市值
  final double totalMarketValue;

  /// 總成本
  final double totalCostBasis;

  /// 總股利收入
  final double totalDividends;

  /// 已實現損益
  final double totalRealizedPnl;

  /// 期間報酬
  final PeriodReturns periodReturns;

  /// 回撤（%）
  ///
  /// 注意：實際計算為「當前回撤」（成本 vs 市值），並非追蹤歷史淨值曲線的最大回撤。
  /// 欄位名稱保留 maxDrawdown 以維持序列化與 UI 相容性。
  final double maxDrawdown;

  /// 產業配置
  final Map<String, IndustryAllocation> industryAllocation;

  /// 總損益
  double get totalPnl =>
      totalMarketValue - totalCostBasis + totalDividends + totalRealizedPnl;

  static const empty = PortfolioPerformance(
    totalReturn: 0,
    totalMarketValue: 0,
    totalCostBasis: 0,
    totalDividends: 0,
    totalRealizedPnl: 0,
    periodReturns: PeriodReturns.empty,
    maxDrawdown: 0,
    industryAllocation: {},
  );
}

/// 期間報酬
class PeriodReturns {
  const PeriodReturns({
    required this.daily,
    required this.weekly,
    required this.monthly,
    required this.yearly,
  });

  /// 日報酬（%）
  final double daily;

  /// 週報酬（%）
  final double weekly;

  /// 月報酬（%）
  final double monthly;

  /// 年報酬 / 年化報酬（%）
  final double yearly;

  static const empty = PeriodReturns(
    daily: 0,
    weekly: 0,
    monthly: 0,
    yearly: 0,
  );
}

/// 產業配置
class IndustryAllocation {
  const IndustryAllocation({
    required this.industry,
    required this.value,
    required this.percentage,
    required this.symbols,
  });

  /// 產業名稱
  final String industry;

  /// 市值
  final double value;

  /// 佔比（%）
  final double percentage;

  /// 包含的股票代碼
  final List<String> symbols;
}
