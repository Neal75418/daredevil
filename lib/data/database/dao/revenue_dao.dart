import 'package:daredevil/core/constants/revenue_overview_params.dart';
import 'package:drift/drift.dart';

import 'package:daredevil/data/database/app_database.drift.dart';
import 'package:daredevil/data/database/tables/market_data_tables.drift.dart';

/// 營收總覽清單(最新月全部已申報公司)
class RevenueOverview {
  const RevenueOverview({
    required this.year,
    required this.month,
    required this.rows,
    required this.filedByMarket,
  });

  final int year;
  final int month;
  final List<RevenueOverviewRow> rows;

  /// 各市場已申報家數。
  ///
  /// **刻意不提供分母**(2026-08-05):stock_master 無主板/興櫃欄位——
  /// FinMind 把興櫃股也標成 TPEx(實測 4 碼非 ETF 上櫃 1,305 檔 vs
  /// 主板實際 ~800),而 ETF 不申報月營收。任何可得的分母都會把進度
  /// 變成到不了的假分數;只顯示真實可知的「已公布家數」。
  final Map<String, int> filedByMarket;
}

/// 營收總覽單列
class RevenueOverviewRow {
  const RevenueOverviewRow({
    required this.symbol,
    required this.name,
    required this.market,
    required this.revenue,
    required this.momGrowth,
    required this.yoyGrowth,
    this.ytdYoyGrowth,
    required this.isNewHigh,
  });

  final String symbol;
  final String name;
  final String market;

  /// 千元
  final double revenue;
  final double? momGrowth;
  final double? yoyGrowth;

  /// 累計年增率 %(年初至當月 vs 去年同期;缺值/自洽失配為 null)
  final double? ytdYoyGrowth;

  /// 當月營收 > 歷史最高(純資料口徑,不含技術過濾)
  final bool isNewHigh;

  /// 低基期識別(2026-08-13):單月年增極端而累計年增平庸=基期效應/
  /// 一次性認列(聯上 2026-07 單月 +1,096,390% 實例)。用兩個資料點的
  /// **關係**判定,參數見 [RevenueOverviewParams]。累計缺值不標——
  /// 資料缺不是證據。
  bool get isLowBase {
    final yoy = yoyGrowth;
    final ytd = ytdYoyGrowth;
    if (yoy == null || ytd == null) return false;
    if (yoy < RevenueOverviewParams.lowBaseMinYoyPct) return false;
    return ytd < yoy / RevenueOverviewParams.lowBaseDivergenceRatio;
  }
}

/// 月營收操作
mixin RevenueDaoMixin on $AppDatabase {
  /// 取得股票的月營收歷史
  Future<List<MonthlyRevenueEntry>> getMonthlyRevenueHistory(
    String symbol, {
    required DateTime startDate,
    DateTime? endDate,
  }) {
    final query = select(monthlyRevenue)
      ..where((t) => t.symbol.equals(symbol))
      ..where((t) => t.date.isBiggerOrEqualValue(startDate));

    if (endDate != null) {
      query.where((t) => t.date.isSmallerOrEqualValue(endDate));
    }

    query.orderBy([(t) => OrderingTerm.asc(t.date)]);
    return query.get();
  }

  /// 批次取得多檔股票的最新月營收（批次查詢）
  /// [asOf] 給定時只取該日（含）以前的資料
  ///
  /// 無上界的全域 `MAX(date)` 在對歷史日重跑時會把**未來**的基本面寫進當日
  /// 訊號（`daily_reason` → `rule_accuracy` 的輸入）。`tool/replay_calibrator`
  /// 早已做 point-in-time 過濾，此處補上同一口徑，讓 runtime 與 calibrator
  /// 結構上一致，也讓「把歷史重放進 daily_reason」成為安全的操作。
  ///
  /// 省略時維持原本的全域最新語意（正式路徑的評分日恆為今日，實測四張
  /// 基本面表無任何超前列，故行為不變）。
  Future<Map<String, MonthlyRevenueEntry>> getLatestMonthlyRevenuesBatch(
    List<String> symbols, {
    DateTime? asOf,
  }) async {
    if (symbols.isEmpty) return {};

    // 建立 SQL IN 子句的佔位符
    final placeholders = List.filled(symbols.length, '?').join(', ');

    final query =
        '''
    SELECT mr.*
    FROM monthly_revenue mr
    INNER JOIN (
      SELECT symbol, MAX(date) as max_date
      FROM monthly_revenue
      WHERE symbol IN ($placeholders)
      ${asOf == null ? '' : 'AND date <= ?'}
      GROUP BY symbol
    ) latest ON mr.symbol = latest.symbol AND mr.date = latest.max_date
  ''';

    final results = await customSelect(
      query,
      variables: [
        ...symbols.map((s) => Variable.withString(s)),
        if (asOf != null) Variable.withDateTime(asOf),
      ],
      readsFrom: {monthlyRevenue},
    ).get();

    final result = <String, MonthlyRevenueEntry>{};
    for (final row in results) {
      final entry = MonthlyRevenueEntry(
        symbol: row.read<String>('symbol'),
        date: row.read<DateTime>('date'),
        revenueYear: row.read<int>('revenue_year'),
        revenueMonth: row.read<int>('revenue_month'),
        revenue: row.read<double>('revenue'),
        momGrowth: row.readNullable<double>('mom_growth'),
        yoyGrowth: row.readNullable<double>('yoy_growth'),
        ytdYoyGrowth: row.readNullable<double>('ytd_yoy_growth'),
      );
      result[entry.symbol] = entry;
    }

    return result;
  }

  /// 取得股票近 N 個月的營收資料
  Future<List<MonthlyRevenueEntry>> getRecentMonthlyRevenue(
    String symbol, {
    int months = 13, // 13 個月以計算 12 個月的年增率
  }) {
    return (select(monthlyRevenue)
          ..where((t) => t.symbol.equals(symbol))
          ..orderBy([(t) => OrderingTerm.desc(t.date)])
          ..limit(months))
        .get();
  }

  /// 批次取得多檔股票近 N 個月的營收資料（批次查詢）
  ///
  /// 回傳 symbol -> 營收資料列表 的 Map（依日期降冪排序）
  Future<Map<String, List<MonthlyRevenueEntry>>> getRecentMonthlyRevenueBatch(
    List<String> symbols, {
    int months = 6, // 6 個月用於追蹤月增率
  }) async {
    if (symbols.isEmpty) return {};

    // 建立 SQL IN 子句的佔位符
    final placeholders = List.filled(symbols.length, '?').join(', ');

    // 使用 ROW_NUMBER 取得每檔股票的前 N 個月
    // 比執行 N 次個別查詢更有效率
    final query =
        '''
    SELECT * FROM (
      SELECT mr.*,
             ROW_NUMBER() OVER (PARTITION BY symbol ORDER BY date DESC) as rn
      FROM monthly_revenue mr
      WHERE symbol IN ($placeholders)
    ) ranked
    WHERE rn <= ?
    ORDER BY symbol, date DESC
  ''';

    final results = await customSelect(
      query,
      variables: [
        ...symbols.map((s) => Variable.withString(s)),
        Variable.withInt(months),
      ],
      readsFrom: {monthlyRevenue},
    ).get();

    // 依 symbol 分組
    final result = <String, List<MonthlyRevenueEntry>>{};
    for (final row in results) {
      final symbol = row.read<String>('symbol');
      final entry = MonthlyRevenueEntry(
        symbol: symbol,
        date: row.read<DateTime>('date'),
        revenueYear: row.read<int>('revenue_year'),
        revenueMonth: row.read<int>('revenue_month'),
        revenue: row.read<double>('revenue'),
        momGrowth: row.readNullable<double>('mom_growth'),
        yoyGrowth: row.readNullable<double>('yoy_growth'),
        ytdYoyGrowth: row.readNullable<double>('ytd_yoy_growth'),
      );
      result.putIfAbsent(symbol, () => []).add(entry);
    }

    return result;
  }

  /// 批次新增月營收資料
  /// growth 欄位 coalesce(新值, 舊值)：per-symbol 回補抓固定窗口時，窗口
  /// 舊端月份在批次內沒有前一年基期 → 成長率算出 null；整列 REPLACE 會把
  /// 先前寬窗口算好的非空 YoY/MoM 靜默降級成 null（表格已顯示的年增率變
  /// 回「-」）。營收本身一律取新值（官方數字，重抓即修正）。
  Future<void> insertMonthlyRevenue(
    List<MonthlyRevenueCompanion> entries,
  ) async {
    await batch((b) {
      for (final entry in entries) {
        b.insert(
          monthlyRevenue,
          entry,
          onConflict:
              DoUpdate<$MonthlyRevenueTable, MonthlyRevenueEntry>.withExcluded(
                (old, excluded) => MonthlyRevenueCompanion.custom(
                  revenue: excluded.revenue,
                  momGrowth: coalesce([excluded.momGrowth, old.momGrowth]),
                  yoyGrowth: coalesce([excluded.yoyGrowth, old.yoyGrowth]),
                  // coalesce 而非直接覆蓋(2026-08-13 審查 Critical 1):
                  // FinMind 歷史路徑的 companion 不帶本欄,excluded 為 NULL
                  // ——直接覆蓋會把 openapi/MOPS 已寫入的好值洗掉;漏列則
                  // FinMind 先到的列**永遠 NULL**(實測:自選股最容易先被
                  // FinMind 觸到,正是使用者最在乎的列)
                  ytdYoyGrowth: coalesce([
                    excluded.ytdYoyGrowth,
                    old.ytdYoyGrowth,
                  ]),
                ),
              ),
        );
      }
    });
  }

  /// 營收總覽:資料中最新月份的完整清單(2026-08-05,營收總覽頁)。
  ///
  /// - 「最新月份」= monthly_revenue 實際存在的最大 (year, month)——
  ///   零日曆邏輯:公布期自然指向進行中的月,平時指向最後完整月
  /// - 「創高」= 純資料口徑(當月 > 歷史最高,排除當月自身),與
  ///   [getMaxRevenueBatch] 同一把尺;**刻意不含** REVENUE_NEW_HIGH 規則
  ///   的「站上 MA20」過濾——清單是資料事實視角,技術面安靜的創高股
  ///   正是訊號層看不見、清單要保住的族群
  /// - 只列 active 股票(殭屍下市股 join 排除)
  Future<RevenueOverview?> getRevenueOverviewForLatestMonth() async {
    final latest = await customSelect(
      'SELECT revenue_year AS y, revenue_month AS m FROM monthly_revenue '
      'ORDER BY revenue_year DESC, revenue_month DESC LIMIT 1',
      readsFrom: {monthlyRevenue},
    ).getSingleOrNull();
    if (latest == null) return null;
    final year = latest.read<int>('y');
    final month = latest.read<int>('m');

    // 當月清單(join 主檔取名稱/市場、排除非 active)+ 歷史最高
    // (排除當月自身)一次算完
    final rows = await customSelect(
      '''
      SELECT mr.symbol, sm.name, sm.market,
             mr.revenue, mr.mom_growth, mr.yoy_growth, mr.ytd_yoy_growth,
             (SELECT MAX(h.revenue) FROM monthly_revenue h
               WHERE h.symbol = mr.symbol
                 AND NOT (h.revenue_year = mr.revenue_year
                          AND h.revenue_month = mr.revenue_month)
             ) AS max_prior
      FROM monthly_revenue mr
      JOIN stock_master sm ON sm.symbol = mr.symbol AND sm.is_active = 1
      WHERE mr.revenue_year = ? AND mr.revenue_month = ?
      ''',
      variables: [Variable.withInt(year), Variable.withInt(month)],
      readsFrom: {monthlyRevenue, stockMaster},
    ).get();

    final entries = rows.map((r) {
      final maxPrior = r.readNullable<double>('max_prior');
      final revenue = r.read<double>('revenue');
      return RevenueOverviewRow(
        symbol: r.read<String>('symbol'),
        name: r.read<String>('name'),
        market: r.read<String>('market'),
        revenue: revenue,
        momGrowth: r.readNullable<double>('mom_growth'),
        yoyGrowth: r.readNullable<double>('yoy_growth'),
        ytdYoyGrowth: r.readNullable<double>('ytd_yoy_growth'),
        // 無歷史基準(首月資料)不算創高——「創高」必須有可比對象
        isNewHigh: maxPrior != null && maxPrior > 0 && revenue > maxPrior,
      );
    }).toList();

    final filedByMarket = <String, int>{};
    for (final e in entries) {
      filedByMarket.update(e.market, (v) => v + 1, ifAbsent: () => 1);
    }

    return RevenueOverview(
      year: year,
      month: month,
      rows: entries,
      filedByMarket: filedByMarket,
    );
  }

  /// 批次取得多檔股票的歷史最高月營收（排除最新月份）
  ///
  /// 排除每檔股票最新一筆紀錄，僅比較歷史資料。
  /// 用於「營收創歷史新高」規則，避免當月營收與自身比較。
  Future<Map<String, double>> getMaxRevenueBatch(List<String> symbols) async {
    if (symbols.isEmpty) return {};

    final placeholders = List.filled(symbols.length, '?').join(', ');
    final query =
        '''
    SELECT symbol, MAX(revenue) as max_revenue
    FROM (
      SELECT symbol, revenue,
             ROW_NUMBER() OVER (PARTITION BY symbol ORDER BY date DESC) as rn
      FROM monthly_revenue
      WHERE symbol IN ($placeholders)
    ) history
    WHERE rn > 1
    GROUP BY symbol
  ''';

    final results = await customSelect(
      query,
      variables: symbols.map((s) => Variable.withString(s)).toList(),
      readsFrom: {monthlyRevenue},
    ).get();

    final map = <String, double>{};
    for (final row in results) {
      final maxRevenue = row.readNullable<double>('max_revenue');
      if (maxRevenue != null) {
        map[row.read<String>('symbol')] = maxRevenue;
      }
    }
    return map;
  }

  /// 取得指定年/月的月營收資料筆數
  ///
  /// 用於檢查是否已有該月的全市場營收資料，以避免重複的 API 呼叫。
  /// [market] 給定時只數該市場的筆數
  ///
  /// 「該月抓齊了沒」的判斷必須與**實際抓取的範圍**同市場。全市場營收
  /// 同步只抓上市（`getAllMonthlyRevenue`），上櫃由另一條流程寫入；用
  /// 不分市場的總數判斷，等於讓上櫃的筆數替上市背書。
  ///
  /// 實測 2026/06：全市場 1,316 = 上市 1,067 + 上櫃 249，門檻 1,000。
  /// 四分之一的判斷依據不是它要判斷的市場，而上市自身只有 6.7% 餘裕。
  Future<int> getRevenueCountForYearMonth(
    int year,
    int month, {
    String? market,
  }) async {
    final countExpr = monthlyRevenue.symbol.count();
    final query = selectOnly(monthlyRevenue)
      ..addColumns([countExpr])
      ..where(monthlyRevenue.revenueYear.equals(year))
      ..where(monthlyRevenue.revenueMonth.equals(month));
    if (market != null) {
      query.join([
        innerJoin(
          stockMaster,
          stockMaster.symbol.equalsExp(monthlyRevenue.symbol),
        ),
      ]);
      query.where(stockMaster.market.equals(market));
    }
    final result = await query.getSingle();
    return result.read(countExpr) ?? 0;
  }
}
