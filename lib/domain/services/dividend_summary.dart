import 'package:daredevil/core/constants/analysis_params.dart';
import 'package:daredevil/core/constants/api_config.dart';
import 'package:daredevil/core/utils/date_context.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/domain/services/dividend_completeness.dart';

/// 除息年度在股利表上的狀態
enum DividendYearStatus {
  /// 完整且有除權息：顯示金額
  paid,

  /// 完整、沒有除權息，且在第一次除權息之後：計入平均為 0
  none,

  /// 完整、沒有除權息，且不在第一次除權息之後（可能尚未上市）：不計入平均
  noRecord,

  /// 今年：至顯示終點完整，還沒有除權息
  notYet,

  /// 不完整：不顯示金額
  building,
}

/// 股利表的一列：一個除息年度（依除權息日的年份，不是股利所屬年度）
class DividendYearRow {
  const DividendYearRow({
    required this.year,
    required this.status,
    this.cash = 0,
    this.stockShares = 0,
    this.cashCount = 0,
  });

  final int year;
  final DividendYearStatus status;

  /// 每股現金股利合計（元）；只有 [DividendYearStatus.paid] 有值
  final double cash;

  /// 每千股無償配股合計（股）；同上
  final double stockShares;

  /// 有現金的除權息次數：同一年息、權分兩天除只算一次
  final int cashCount;
}

/// 股利表的平均列
sealed class DividendAverage {
  const DividendAverage();
}

/// 前幾個完整年度中有建置中的年度：無法判定第一次除權息在哪一年，也無法
/// 排除建置中的年度其實是 0
final class DividendAverageBuilding extends DividendAverage {
  const DividendAverageBuilding();
}

/// 從第一次有除權息的完整年度 [fromYear] 到去年、共 [years] 年的平均；
/// 其間無除權息的年度計為 0
final class DividendAverageValue extends DividendAverage {
  const DividendAverageValue({
    required this.fromYear,
    required this.years,
    required this.cash,
    required this.stockShares,
  });

  final int fromYear;
  final int years;

  /// 每股現金股利（元）
  final double cash;

  /// 每千股無償配股（股）
  final double stockShares;
}

/// 近一年殖利率
sealed class TrailingYield {
  const TrailingYield();
}

/// 完整度不足
final class TrailingYieldBuilding extends TrailingYield {
  const TrailingYieldBuilding();
}

/// 近一年無配息：最近一次除息早於顯示終點
/// [AnalysisParams.trailingYieldStaleDays] 天以上，或沒有除息紀錄
final class TrailingYieldNone extends TrailingYield {
  const TrailingYieldNone();
}

/// Σ(現金股利 ÷ 除息前收盤)，事件取最近一次除息日往前
/// [AnalysisParams.trailingYieldWindowDays] 天內（含）者。逐次以當時的前收盤
/// 正規化，不受分割影響
final class TrailingYieldValue extends TrailingYield {
  const TrailingYieldValue(this.ratio);

  /// 比例（0.02＝2%）
  final double ratio;
}

/// 個股股利摘要：個股頁股利表、ETF 殖利率卡、投資組合預估共用
class DividendSummary {
  const DividendSummary({
    required this.displayEnd,
    required this.parValueTen,
    required this.current,
    required this.pastYears,
    required this.average,
    required this.trailingYield,
  });

  /// 依 [symbol] 的配發列與完整度彙總；今年＝[DividendCompleteness.now] 的
  /// 年份。
  ///
  /// [rows]：該檔的配發列，順序不拘；只有現金增資的 0/0 列不算配發，略過。
  /// [name]：股票名稱，帶 `*` 表示面額不是 10 元；null（主檔查不到）時不假設
  /// 面額
  factory DividendSummary.compute({
    required String symbol,
    required String? name,
    required Iterable<DividendDistributionEntry> rows,
    required DividendCompleteness completeness,
  }) {
    final thisYear = completeness.now.year;
    final end = completeness.displayEnd;
    final byYear = <int, List<DividendDistributionEntry>>{};
    for (final row in rows) {
      if (row.cashDividend <= 0 && row.stockSharesPerThousand <= 0) continue;
      byYear.putIfAbsent(row.exDate.year, () => []).add(row);
    }
    final firstYear = thisYear - ApiConfig.dividendBackfillYears;
    // 第一次除權息：表上各年（含建置中的年度）在庫的配發列都算，那些是真的
    // 除權息。較早的年度建置中又沒有在庫列時，真正的第一次可能更早：第一筆
    // 在庫事件之前、完整無事件的年度標「無除權息紀錄」（也可能其實是「無
    // 除權息」，兩種都屬實；平均此時是建置中）
    int? firstEventYear;
    for (var year = firstYear; year <= thisYear; year++) {
      if (byYear.containsKey(year)) {
        firstEventYear = year;
        break;
      }
    }

    // 顯示終點還在去年（1 月初、當年第一輪更新前）時，今年沒有可判斷的範圍
    final DividendYearRow current;
    if (end == null ||
        end.year < thisYear ||
        !completeness.isComplete(
          symbol,
          DateTime(thisYear),
          end,
          requirePrices: false,
        )) {
      current = DividendYearRow(
        year: thisYear,
        status: DividendYearStatus.building,
      );
    } else {
      final events = [
        for (final row
            in byYear[thisYear] ?? const <DividendDistributionEntry>[])
          if (!DateContext.normalize(row.exDate).isAfter(end)) row,
      ];
      current = events.isEmpty
          ? DividendYearRow(year: thisYear, status: DividendYearStatus.notYet)
          : _paid(thisYear, events);
    }

    final pastYears = [
      for (var year = thisYear - 1; year >= firstYear; year--)
        if (!completeness.isComplete(
          symbol,
          DateTime(year),
          DateTime(year, 12, 31),
          requirePrices: false,
        ))
          DividendYearRow(year: year, status: DividendYearStatus.building)
        else if (byYear[year] case final events?)
          _paid(year, events)
        else
          DividendYearRow(
            year: year,
            status: firstEventYear != null && year > firstEventYear
                ? DividendYearStatus.none
                : DividendYearStatus.noRecord,
          ),
    ];

    return DividendSummary(
      displayEnd: end,
      parValueTen: name != null && !name.contains('*'),
      current: current,
      pastYears: pastYears,
      average: _average(pastYears),
      trailingYield: _trailingYield(
        symbol,
        byYear.values.expand((e) => e),
        completeness,
      ),
    );
  }

  /// 畫面「截至 M/D」；null＝連回補起點的月份都沒列過（全部建置中）
  final DateTime? displayEnd;

  /// 面額 10 元（名稱不帶 `*`）：配股可換算成元，合計＝現金＋股票
  final bool parValueTen;

  /// 今年（至 [displayEnd]）
  final DividendYearRow current;

  /// 去年起往前 [ApiConfig.dividendBackfillYears] 個完整年度，新到舊。更早的
  /// 年度不在回補範圍內，列出也只會是建置中
  final List<DividendYearRow> pastYears;

  /// null＝前幾個完整年度都沒有除權息，沒有可平均的年度
  final DividendAverage? average;

  final TrailingYield trailingYield;

  /// 今年與前幾年全部建置中：整區改顯示「股利資料建置中」
  bool get allBuilding =>
      current.status == DividendYearStatus.building &&
      pastYears.every((r) => r.status == DividendYearStatus.building);

  /// 配股換算成每股元（面額 10 元：每千股 X 股＝X ÷ 100 元）；面額不是 10 元
  /// 時 null
  double? stockYuan(double stockShares) =>
      parValueTen ? stockShares / 100 : null;

  /// 合計（元）＝現金＋配股換算的元；面額不是 10 元時 null（畫面顯示「—」）
  double? totalYuan(double cash, double stockShares) =>
      parValueTen ? cash + stockShares / 100 : null;

  static DividendYearRow _paid(
    int year,
    Iterable<DividendDistributionEntry> events,
  ) {
    var cash = 0.0;
    var stockShares = 0.0;
    var cashCount = 0;
    for (final e in events) {
      cash += e.cashDividend;
      stockShares += e.stockSharesPerThousand;
      if (e.cashDividend > 0) cashCount++;
    }
    return DividendYearRow(
      year: year,
      status: DividendYearStatus.paid,
      cash: cash,
      stockShares: stockShares,
      cashCount: cashCount,
    );
  }

  static DividendAverage? _average(List<DividendYearRow> pastYears) {
    if (pastYears.any((r) => r.status == DividendYearStatus.building)) {
      return const DividendAverageBuilding();
    }
    // pastYears 新到舊：最後一個有配發的就是第一次除權息的年度
    int? fromYear;
    for (final row in pastYears) {
      if (row.status == DividendYearStatus.paid) fromYear = row.year;
    }
    if (fromYear == null) return null;
    final counted = [
      for (final row in pastYears)
        if (row.year >= fromYear) row,
    ];
    var cash = 0.0;
    var stockShares = 0.0;
    for (final row in counted) {
      cash += row.cash;
      stockShares += row.stockShares;
    }
    return DividendAverageValue(
      fromYear: fromYear,
      years: counted.length,
      cash: cash / counted.length,
      stockShares: stockShares / counted.length,
    );
  }

  /// 有事件時完整度窗口＝[最近除息日 − 350 天, 顯示終點]；沒有（或最近一次
  /// 早於顯示終點 400 天以上）時＝[顯示終點 − 400 天, 顯示終點]；兩者都要求
  /// 價格
  static TrailingYield _trailingYield(
    String symbol,
    Iterable<DividendDistributionEntry> rows,
    DividendCompleteness completeness,
  ) {
    final end = completeness.displayEnd;
    if (end == null) return const TrailingYieldBuilding();
    final events = [
      for (final row in rows)
        if (row.cashDividend > 0 &&
            !DateContext.normalize(row.exDate).isAfter(end))
          row,
    ];
    DateTime? latest;
    for (final e in events) {
      final exDate = DateContext.normalize(e.exDate);
      if (latest == null || exDate.isAfter(latest)) latest = exDate;
    }
    final staleCutoff = DateTime(
      end.year,
      end.month,
      end.day - AnalysisParams.trailingYieldStaleDays,
    );
    if (latest == null || !latest.isAfter(staleCutoff)) {
      return completeness.isComplete(
            symbol,
            staleCutoff,
            end,
            requirePrices: true,
          )
          ? const TrailingYieldNone()
          : const TrailingYieldBuilding();
    }
    final from = DateTime(
      latest.year,
      latest.month,
      latest.day - AnalysisParams.trailingYieldWindowDays,
    );
    if (!completeness.isComplete(symbol, from, end, requirePrices: true)) {
      return const TrailingYieldBuilding();
    }
    var ratio = 0.0;
    for (final e in events) {
      if (DateContext.normalize(e.exDate).isBefore(from)) continue;
      // 配發列與完整度是兩次查詢，中間可能被改寫：缺價時視為建置中
      final close = e.closeBefore;
      if (close == null || close <= 0) return const TrailingYieldBuilding();
      ratio += e.cashDividend / close;
    }
    return TrailingYieldValue(ratio);
  }
}
