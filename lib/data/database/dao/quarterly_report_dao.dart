import 'package:drift/drift.dart';

import 'package:daredevil/data/database/app_database.drift.dart';
import 'package:daredevil/data/database/tables/market_data_tables.drift.dart';

/// 季報總覽清單(最新一季全部已申報公司,2026-08-06)
class QuarterlyReportOverview {
  const QuarterlyReportOverview({
    required this.year,
    required this.quarter,
    required this.rows,
    required this.filedByMarket,
  });

  /// 西元年度
  final int year;

  /// 季別 1~4
  final int quarter;
  final List<QuarterlyReportOverviewRow> rows;

  /// 各市場已申報家數(刻意不提供分母,理由同 RevenueOverview:
  /// 可得的分母混入興櫃/ETF,任何進度分數都是假的)。
  final Map<String, int> filedByMarket;
}

/// 季報總覽單列
class QuarterlyReportOverviewRow {
  const QuarterlyReportOverviewRow({
    required this.symbol,
    required this.name,
    required this.market,
    required this.eps,
    required this.netIncome,
    required this.revenue,
    required this.priorEps,
  });

  final String symbol;
  final String name;
  final String market;

  /// 基本每股盈餘(元,累計)
  final double? eps;

  /// 本期淨利(千元,累計)
  final double? netIncome;

  /// 營業收入(千元,累計;金融業別無此欄)
  final double? revenue;

  /// 去年同期 EPS(元,累計基期=去年 1..Q 季的 FinMind **單季** EPS
  /// 加總;任一季缺漏即 null,不硬算低估的假基期)
  final double? priorEps;

  /// EPS 年增差值(元)——「EPS 年增」排序鍵與總覽頁年增欄的**單一
  /// 事實來源**(2026-08-06:排序鍵原本只算不顯示,使用者看不出榜單
  /// 依據;顯示與排序共用此 getter 保證永遠一致)。刻意用差值不用
  /// 比率:低基期(創見 1.85→46.63 = +2,420%)會把比率炸成噪音。
  double? get epsYoyDelta =>
      (eps != null && priorEps != null) ? eps! - priorEps! : null;

  /// 淨利率 %(淨利/營收,同為千元單位消掉;2026-08-13)。
  ///
  /// 給 EPS 榜一個品質維度:同樣的 EPS 年增,44% 淨利率(宜鼎)與
  /// 12% 淨利率的含金量不同。缺任一值或營收 ≤0 為 null——不除零、
  /// 不用假 0 冒充「零利潤」。
  double? get netMarginPct =>
      (netIncome != null && revenue != null && revenue! > 0)
      ? netIncome! / revenue! * 100
      : null;

  /// 轉虧為盈(去年同期 EPS ≤ 0、本期 > 0;兩值皆須存在)
  bool get isTurnaround =>
      eps != null && priorEps != null && priorEps! <= 0 && eps! > 0;
}

/// 季報操作
mixin QuarterlyReportDaoMixin on $AppDatabase {
  /// 批次寫入季報(insertOrReplace:官方全列快照,重抓即修正)
  Future<void> insertQuarterlyReports(
    List<QuarterlyReportCompanion> entries,
  ) async {
    await batch((b) {
      b.insertAll(quarterlyReport, entries, mode: InsertMode.insertOrReplace);
    });
  }

  /// 季報總覽:資料中最新一季的完整清單。
  ///
  /// 設計沿 [getRevenueOverviewForLatestMonth](2026-08-05 月營收總覽):
  /// - 「最新一季」= quarterly_report 實際存在的最大 (year, quarter)——
  ///   零日曆邏輯:公布期自然指向進行中的季,平時指向最後完整季
  /// - 只列 active 股票(殭屍下市股 join 排除)
  /// - 去年同期 EPS:官方 t187ap06 是**累計制**(Q2=上半年),FinMind 的
  ///   financial_data EPS 是**單季**值(2026-08-06 生產資料實測:2454 的
  ///   2025 四季序列 18.43→17.5→15.84→14.4 遞減,累計制不可能遞減)——
  ///   基期必須**加總去年 1..Q 季**的單季值,且 Q 季齊全才成立;缺季
  ///   寧可 null(UI 顯「—」)也不硬算:拿單季冒充累計基期會把年增
  ///   方向整個弄反(2454 實例:錯法 +12.94、正解 −5.49)
  Future<QuarterlyReportOverview?> getQuarterlyReportOverview() async {
    final latest = await customSelect(
      'SELECT year AS y, quarter AS q FROM quarterly_report '
      'ORDER BY year DESC, quarter DESC LIMIT 1',
      readsFrom: {quarterlyReport},
    ).getSingleOrNull();
    if (latest == null) return null;
    final year = latest.read<int>('y');
    final quarter = latest.read<int>('q');

    // 去年 1..Q 季的季末日(FinMind EPS 列的主鍵日,已對 live DB 驗證
    // 恰為 3/31、6/30、9/30、12/31)
    final priorQuarterEnds = [
      for (var q = 1; q <= quarter; q++)
        switch (q) {
          1 => DateTime(year - 1, 3, 31),
          2 => DateTime(year - 1, 6, 30),
          3 => DateTime(year - 1, 9, 30),
          _ => DateTime(year - 1, 12, 31),
        },
    ];
    final datePlaceholders = List.filled(
      priorQuarterEnds.length,
      '?',
    ).join(', ');

    final rows = await customSelect(
      '''
      SELECT qr.symbol, sm.name, sm.market,
             qr.eps, qr.net_income, qr.revenue,
             fd.prior_eps
      FROM quarterly_report qr
      JOIN stock_master sm ON sm.symbol = qr.symbol AND sm.is_active = 1
      LEFT JOIN (
        SELECT symbol, SUM(value) AS prior_eps, COUNT(*) AS quarter_count
        FROM financial_data
        WHERE data_type = 'EPS'
          AND value IS NOT NULL
          AND date IN ($datePlaceholders)
        GROUP BY symbol
      ) fd ON fd.symbol = qr.symbol AND fd.quarter_count = ?
      WHERE qr.year = ? AND qr.quarter = ?
      ''',
      variables: [
        ...priorQuarterEnds.map(Variable.withDateTime),
        Variable.withInt(quarter),
        Variable.withInt(year),
        Variable.withInt(quarter),
      ],
      readsFrom: {quarterlyReport, stockMaster, financialData},
    ).get();

    final entries = rows
        .map(
          (r) => QuarterlyReportOverviewRow(
            symbol: r.read<String>('symbol'),
            name: r.read<String>('name'),
            market: r.read<String>('market'),
            eps: r.readNullable<double>('eps'),
            netIncome: r.readNullable<double>('net_income'),
            revenue: r.readNullable<double>('revenue'),
            priorEps: r.readNullable<double>('prior_eps'),
          ),
        )
        .toList();

    final filedByMarket = <String, int>{};
    for (final e in entries) {
      filedByMarket.update(e.market, (v) => v + 1, ifAbsent: () => 1);
    }

    return QuarterlyReportOverview(
      year: year,
      quarter: quarter,
      rows: entries,
      filedByMarket: filedByMarket,
    );
  }
}
