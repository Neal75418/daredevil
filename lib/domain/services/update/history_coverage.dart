import 'package:daredevil/core/constants/api_config.dart';
import 'package:daredevil/core/constants/market_codes.dart';
import 'package:daredevil/core/constants/rule_params.dart';
import 'package:daredevil/core/utils/date_context.dart';
import 'package:daredevil/core/utils/taiwan_calendar.dart';
import 'package:daredevil/data/database/app_database.dart';

/// 某市場某日「已補齊」所需的最低筆數（市場股數 × 覆蓋比例，無條件進位）
int coverageThreshold(int marketStockCount) =>
    (marketStockCount * ApiConfig.historicalMarketDayMinCoverageRatio).ceil();

/// 回補窗內缺漏的（日, 市場），由新到舊。
///
/// 「歷史資料補齊」的**唯一定義**：窗 `[endDay - historyRequiredDays,
/// endDay - 1]` 內每個交易日、每個有門檻的市場，該日筆數達
/// [thresholds]（市場股數 × [ApiConfig.historicalMarketDayMinCoverageRatio]）
/// 才算補齊。市場日回補（決定要補哪些）與今日頁的建置進度共用這一份，
/// 兩邊才不會一個說補齊了、另一個還在補。
///
/// [dayCounts]：市場 → `yyyy-MM-dd` → 筆數。[limit] 為回補單次上限。
List<(DateTime, String)> findMissingMarketDays({
  required DateTime endDay,
  required Map<String, int> thresholds,
  required Map<String, Map<String, int>> dayCounts,
  int? limit,
}) {
  final end = DateTime(endDay.year, endDay.month, endDay.day);
  final windowStart = end.subtract(
    const Duration(days: RuleParams.historyRequiredDays),
  );
  final missing = <(DateTime, String)>[];
  for (
    var day = end.subtract(const Duration(days: 1));
    !day.isBefore(windowStart);
    day = day.subtract(const Duration(days: 1))
  ) {
    if (!TaiwanCalendar.isTradingDay(day)) continue;
    final dayKey = DateContext.formatYmd(day);
    for (final MapEntry(key: market, value: threshold) in thresholds.entries) {
      if (limit != null && missing.length >= limit) return missing;
      final count = dayCounts[market]?[dayKey] ?? 0;
      if (count < threshold) missing.add((day, market));
    }
  }
  return missing;
}

/// 歷史資料建置進度（已補齊的（日, 市場）數 / 回補窗內總數）
class HistoryCoverage {
  const HistoryCoverage({required this.covered, required this.total});

  factory HistoryCoverage.from({
    required DateTime endDay,
    required Map<String, int> thresholds,
    required Map<String, Map<String, int>> dayCounts,
  }) {
    final total = findMissingMarketDays(
      endDay: endDay,
      thresholds: thresholds,
      dayCounts: const {},
    ).length;
    final missing = findMissingMarketDays(
      endDay: endDay,
      thresholds: thresholds,
      dayCounts: dayCounts,
    ).length;
    return HistoryCoverage(covered: total - missing, total: total);
  }

  final int covered;
  final int total;

  int get missing => total - covered;

  /// 股票主檔都還沒有（total 為 0）不算補齊
  bool get isComplete => total > 0 && missing == 0;

  /// 今日頁「建置中」提示的判準：缺漏超過一輪回補上限才算。
  ///
  /// 容忍是為了日曆漏標的休市日（颱風停市、新增國定假日、預估錯的農曆
  /// 假日；2026-07-13 就一次補進 4 天）：官方端點回 0 筆，那個（日, 市場）永遠補不齊，嚴格用 [isComplete]
  /// 會讓已補齊的使用者常駐看到「99%（約再 1 次更新）」直到滑出回補窗
  /// （約 13 個月）。新安裝缺上百個照樣顯示；代價是最後一輪前提示先消失。
  bool get isBuilding => missing > ApiConfig.historicalMarketDayMaxCallsPerRun;

  /// 無條件捨去：差一點補齊時不會顯示成 100%
  int get percent => total == 0 ? 0 : covered * 100 ~/ total;

  /// 依回補單次上限估算還要幾次更新
  int get remainingRuns =>
      (missing / ApiConfig.historicalMarketDayMaxCallsPerRun).ceil();
}

/// 從 DB 計算目前的歷史資料建置進度（今日頁顯示用）。
///
/// 窗口右端取 `min(今天, dataDate 隔天)`：資料只是落後幾天時，最近幾天的
/// 0 筆是落後提示的事、不是「歷史沒補齊」，算進來會讓兩條提示同時出現。
///
/// 一次 GROUP BY 查詢（實測 660 MB DB 熱快取約 0.4 秒，在 drift 背景
/// isolate），呼叫端只在 DB 有變時重算。
Future<HistoryCoverage> loadHistoryCoverage(
  AppDatabase db,
  DateTime now, {
  required DateTime dataDate,
}) async {
  final today = DateTime(now.year, now.month, now.day);
  final afterData = DateTime(dataDate.year, dataDate.month, dataDate.day + 1);
  final endDay = afterData.isBefore(today) ? afterData : today;
  final thresholds = <String, int>{};
  for (final market in [MarketCode.twse, MarketCode.tpex]) {
    final stocks = await db.getStocksByMarket(market);
    if (stocks.isEmpty) continue;
    thresholds[market] = coverageThreshold(stocks.length);
  }
  if (thresholds.isEmpty) return const HistoryCoverage(covered: 0, total: 0);
  final dayCounts = await db.getPriceCountsByDayAndMarket(
    startDate: endDay.subtract(
      const Duration(days: RuleParams.historyRequiredDays),
    ),
    endDate: endDay,
  );
  return HistoryCoverage.from(
    endDay: endDay,
    thresholds: thresholds,
    dayCounts: dayCounts,
  );
}
