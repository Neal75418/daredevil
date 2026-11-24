import 'dart:collection';
import 'dart:math' as math;

import 'package:daredevil/core/constants/portfolio_params.dart';
import 'package:daredevil/core/constants/rule_params.dart';
import 'package:daredevil/core/constants/transaction_types.dart';
import 'package:daredevil/core/utils/date_context.dart';
import 'package:daredevil/core/utils/taiwan_calendar.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/domain/models/dividend_context.dart';

/// 投資組合績效分析服務
///
/// 提供各種績效指標計算：
/// - Total Return（總報酬率）
/// - Period Return（期間報酬）
/// - Max Drawdown（最大回撤）
/// - Industry Allocation（產業配置）
class PortfolioAnalyticsService {
  const PortfolioAnalyticsService();

  /// 計算投資組合績效
  ///
  /// [transactions] 所有交易紀錄（含已平倉的股票）
  /// [positions] 目前持倉
  /// [currentPrices] symbol -> 目前價格
  /// [stocksMap] symbol -> 股票資訊
  /// [periodInputs] 期間報酬用的資料日、日線與除權息；null（沒有任何收盤）
  /// 時期間報酬全部為 null
  PortfolioPerformance calculatePerformance({
    required List<PortfolioTransactionEntry> transactions,
    required List<PortfolioPositionEntry> positions,
    required Map<String, double> currentPrices,
    required Map<String, StockMasterEntry> stocksMap,
    required PeriodReturnInputs? periodInputs,
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
    final periodReturns = periodInputs == null
        ? PeriodReturns.empty
        : _PeriodReturnCalculator(
            transactions: transactions,
            inputs: periodInputs,
            fallbackPrices: {
              for (final pos in positions)
                pos.symbol: currentPrices[pos.symbol] ?? pos.avgCost,
            },
          ).calculate(
            totalReturn: totalReturn,
            hasBuyCost: totalHistoricalBuyCost > 0,
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

/// 期間報酬：日／週／月是近 1／5／20 個交易日的實際報酬，年化只在持有滿一年
/// 後換算。
///
/// 交易日取日線裡所有收盤列的日期（依日期去重，同一天可能有不同時區寫法的
/// 多筆列）。一個窗口是「期初那天收盤」到「資料日收盤」：
/// - 期初持股以期初當天或之前最近的收盤計值；期間內的買進成本、賣出收入是
///   現金流，期間內才買進的部位以買進成本當起點
/// - 除權息日以參考價入帳：除息前一天收盤的持股 × (除息前收盤 − 參考價) 算
///   流入（與今日損益以參考價當昨收同一個口徑），現金股利的入帳紀錄因此不再算
/// - 期初有持股、但收盤列從期初之後才開始的股票（掛牌前就記了買進），期初
///   以前的交易改當期間內的現金流；那些交易早於讀到的日線時（長期停牌後
///   恢復）算不出來
/// - 日線裡沒有任何收盤列的在倉持股（很久沒有行情）以最新收盤（沒有就用
///   均價）計值，與總報酬同一套
///
/// 算不出來（回 null）：期初市值加買進成本不為正；期初持有、又沒有任何價格
/// 可用；有持股的股票除權息資料不完整、窗口內有股票股利入帳、或持有期間的
/// 收盤序列有水位斷點（停牌後恢復，且跳動超過門檻：分割、減資）
class _PeriodReturnCalculator {
  _PeriodReturnCalculator({
    required this.transactions,
    required PeriodReturnInputs inputs,
    required this.fallbackPrices,
  }) : _end = DateContext.normalize(inputs.asOf),
       _dividendContext = inputs.dividendContext {
    for (final MapEntry(key: symbol, value: rows)
        in inputs.closeHistory.entries) {
      for (final row in rows) {
        final close = row.close;
        final day = DateContext.normalize(row.date);
        if (close == null || day.isAfter(_end)) continue;
        (_closes[symbol] ??= SplayTreeMap())[day] = close;
        _tradingDays.add(day);
      }
    }
  }

  /// 持股數小於等於這個值當成沒有持股（買賣股數加總留下的浮點殘量）
  static const _quantityEpsilon = 1e-9;

  final List<PortfolioTransactionEntry> transactions;

  /// 沒有任何收盤列的股票用來計值的價格
  final Map<String, double> fallbackPrices;

  final DateTime _end;
  final DividendContextLookup _dividendContext;
  final _closes = <String, SplayTreeMap<DateTime, double>>{};
  final _tradingDays = SplayTreeSet<DateTime>();

  PeriodReturns calculate({
    required double totalReturn,
    required bool hasBuyCost,
  }) {
    final descending = _tradingDays.toList().reversed.toList();
    double? window(int tradingDaysBack) => descending.length > tradingDaysBack
        ? _windowReturn(descending[tradingDaysBack])
        : null;
    return PeriodReturns(
      daily: window(PortfolioParams.dailyWindowTradingDays),
      weekly: window(PortfolioParams.weeklyWindowTradingDays),
      monthly: window(PortfolioParams.monthlyWindowTradingDays),
      yearly: hasBuyCost ? _annualized(totalReturn) : null,
    );
  }

  /// [start] 收盤到資料日收盤的報酬（%）
  double? _windowReturn(DateTime start) {
    final heldAtStart = {
      for (final MapEntry(key: symbol, value: quantity) in _holdings(
        start,
      ).entries)
        if (quantity > _quantityEpsilon) symbol,
    };
    final shifted = {
      for (final symbol in heldAtStart)
        if (_closes[symbol] case final series?
            when _closeOnOrBefore(series, start) == null)
          symbol,
    };

    // 收盤列從期初之後才開始、但交易早於讀到的日線：之前可能有行情只是沒讀到
    // （長期停牌後恢復），期初價值未知
    final firstDay = _tradingDays.first;
    if (transactions.any(
      (tx) =>
          shifted.contains(tx.symbol) &&
          DateContext.normalize(tx.date).isBefore(firstDay),
    )) {
      return null;
    }

    final startValue = _valueAt(start, exclude: shifted);
    final endValue = _valueAt(_end);
    if (startValue == null || endValue == null) return null;

    double buys = 0;
    double inflows = 0;
    final active = {...heldAtStart};
    for (final tx in transactions) {
      final day = DateContext.normalize(tx.date);
      if (day.isAfter(_end)) continue;
      if (!day.isAfter(start) && !shifted.contains(tx.symbol)) continue;
      switch (tx.txType) {
        case TransactionTypes.buy:
          buys += tx.quantity * tx.price + tx.fee;
          active.add(tx.symbol);
        case TransactionTypes.sell:
          inflows += tx.quantity * tx.price - tx.fee - tx.tax;
        case TransactionTypes.dividendStock:
          // 入帳那天股數跳一截，價格沒有對應的調整（除權在更早之前）
          return null;
      }
    }

    for (final symbol in active) {
      final context = _dividendContext(symbol, start, _end);
      if (context is! DividendComplete) return null;
      for (final event in context.events) {
        final heldBefore = _holdings(event.exDate, inclusive: false)[symbol];
        inflows +=
            (heldBefore ?? 0) * (event.closeBefore - event.referencePrice);
      }
      if (_hasPriceBreak(symbol, start, context.events)) return null;
    }

    final base = startValue + buys;
    if (base <= 0) return null;
    return (endValue + inflows - buys - startValue) / base * 100;
  }

  /// [day] 收盤時（[inclusive] 為 false 時是 [day] 之前）各股的持股數
  Map<String, double> _holdings(DateTime day, {bool inclusive = true}) {
    final held = <String, double>{};
    for (final tx in transactions) {
      final txDay = DateContext.normalize(tx.date);
      if (inclusive ? txDay.isAfter(day) : !txDay.isBefore(day)) continue;
      final delta = switch (tx.txType) {
        TransactionTypes.buy || TransactionTypes.dividendStock => tx.quantity,
        TransactionTypes.sell => -tx.quantity,
        _ => 0.0,
      };
      held[tx.symbol] = (held[tx.symbol] ?? 0) + delta;
    }
    return held;
  }

  /// [day] 收盤時的持股市值（略過 [exclude]）；有持股卻沒有價格可用時回 null
  double? _valueAt(DateTime day, {Set<String> exclude = const {}}) {
    double value = 0;
    for (final MapEntry(key: symbol, value: quantity) in _holdings(
      day,
    ).entries) {
      if (quantity <= _quantityEpsilon || exclude.contains(symbol)) continue;
      final series = _closes[symbol];
      final price = series == null
          ? fallbackPrices[symbol]
          : _closeOnOrBefore(series, day);
      if (price == null) return null;
      value += quantity * price;
    }
    return value;
  }

  static double? _closeOnOrBefore(
    SplayTreeMap<DateTime, double> series,
    DateTime day,
  ) {
    final key = series.containsKey(day) ? day : series.lastKeyBefore(day);
    return key == null ? null : series[key];
  }

  /// [symbol] 從期初（當天或之前最近的收盤，沒有就從第一筆）到資料日的收盤
  /// 序列，在持有期間有沒有水位斷點（分割、減資）：相鄰兩個收盤之間有這檔
  /// 沒有收盤的交易日（停止買賣），且跳動超過
  /// `RuleParams.priceDiscontinuityRatio`。沒有停牌的大漲跌（新股掛牌頭幾天、
  /// 無漲跌幅限制的 ETF）不算；中間有除權息日時，前收盤先乘上還原因子再比
  bool _hasPriceBreak(
    String symbol,
    DateTime start,
    List<DividendPriceEvent> events,
  ) {
    final series = _closes[symbol];
    if (series == null) return false;
    final from = series.containsKey(start)
        ? start
        : (series.lastKeyBefore(start) ?? series.firstKey()!);
    DateTime? previousDay;
    double? previousClose;
    for (final MapEntry(key: day, value: close) in series.entries) {
      if (day.isBefore(from)) continue;
      // 先看停牌：多數相鄰收盤是連續交易日，一判就排除，不必每對都重算持股
      if (previousDay != null &&
          previousClose != null &&
          _suspendedBetween(previousDay, day) &&
          (_holdings(previousDay)[symbol] ?? 0) > _quantityEpsilon) {
        var expected = previousClose;
        for (final event in events) {
          if (event.exDate.isAfter(previousDay) && !event.exDate.isAfter(day)) {
            expected *= event.factor;
          }
        }
        if ((close / expected - 1).abs() > RuleParams.priceDiscontinuityRatio) {
          return true;
        }
      }
      previousDay = day;
      previousClose = close;
    }
    return false;
  }

  /// [after] 與 [before] 之間（不含頭尾）有沒有交易日：兩個相鄰收盤之間有
  /// 交易日，表示這檔那幾天沒有收盤（停止買賣）
  static bool _suspendedBetween(DateTime after, DateTime before) {
    for (
      var day = DateTime(after.year, after.month, after.day + 1);
      day.isBefore(before);
      day = DateTime(day.year, day.month, day.day + 1)
    ) {
      if (TaiwanCalendar.isTradingDay(day)) return true;
    }
    return false;
  }

  /// 年化報酬（%）：首筆交易到資料日未滿 `PortfolioParams.minAnnualizeDays`
  /// 天回 null；滿了用複利換算。總報酬低於 -100% 時年化為 -100%
  double? _annualized(double totalReturn) {
    final first = transactions
        .map((tx) => DateContext.normalize(tx.date))
        .reduce((a, b) => a.isBefore(b) ? a : b);
    final days = _end.difference(first).inDays;
    if (days < PortfolioParams.minAnnualizeDays) return null;
    final growth = math.max(1 + totalReturn / 100, 0.0);
    return (math.pow(growth, PortfolioParams.daysPerYear / days) - 1) * 100;
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

/// [symbol] 在 (from, to] 之間的除權息事件；資料不完整時回
/// [DividendContext.incomplete]
typedef DividendContextLookup =
    DividendContext Function(String symbol, DateTime from, DateTime to);

/// 期間報酬的輸入
class PeriodReturnInputs {
  const PeriodReturnInputs({
    required this.asOf,
    required this.closeHistory,
    required this.dividendContext,
  });

  /// 資料日（在倉持股最新收盤的日期）
  final DateTime asOf;

  /// 交易過的每一檔在 [asOf] 之前一段期間的日線（任意順序；[asOf] 之後的列不算）
  final Map<String, List<DailyPriceEntry>> closeHistory;

  final DividendContextLookup dividendContext;
}

/// 期間報酬；算不出來的欄位為 null（畫面顯示「—」）
class PeriodReturns {
  const PeriodReturns({this.daily, this.weekly, this.monthly, this.yearly});

  /// 近 1 個交易日的報酬（%）；算不出來為 null
  final double? daily;

  /// 近 5 個交易日的報酬（%）；算不出來為 null
  final double? weekly;

  /// 近 20 個交易日的報酬（%）；算不出來為 null
  final double? monthly;

  /// 年化報酬（%）；持有未滿一年為 null
  final double? yearly;

  static const empty = PeriodReturns();
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
