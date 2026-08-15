import 'package:drift/drift.dart';

import 'package:daredevil/data/database/app_database.drift.dart';
import 'package:daredevil/data/database/tables/market_data_tables.drift.dart';

/// 財務報表操作
mixin FinancialDataDaoMixin on $AppDatabase {
  /// 批次新增財務資料
  /// 某檔在指定財報類型下已有幾個「季別」(distinct date)
  ///
  /// 給 `_syncFinancialStatement` 的新鮮度檢查用。**只看最新一季會漏掉歷史**:
  /// 2026-08-16 接入免費資產負債表後,官方端點把當季寫進全市場,若檢查只問
  /// 「最新一季有沒有」就對每一檔成立,FinMind 的 per-symbol 路徑——歷史
  /// Equity 的唯一來源——永遠不再執行(實測 529 檔缺 Q1,ROE 因此算不出來)。
  Future<int> countFinancialDataQuarters(
    String symbol,
    String statementType,
  ) async {
    final expr = financialData.date.count(distinct: true);
    final query = selectOnly(financialData)
      ..addColumns([expr])
      ..where(
        financialData.symbol.equals(symbol) &
            financialData.statementType.equals(statementType),
      );
    return (await query.getSingle()).read(expr) ?? 0;
  }

  Future<void> insertFinancialData(List<FinancialDataCompanion> entries) async {
    await batch((b) {
      for (final entry in entries) {
        b.insert(financialData, entry, mode: InsertMode.insertOrReplace);
      }
    });
  }

  /// 取得股票與報表類型的最新財務資料日期（新鮮度檢查用）
  Future<DateTime?> getLatestFinancialDataDate(
    String symbol,
    String statementType,
  ) async {
    final result =
        await (select(financialData)
              ..where((t) => t.symbol.equals(symbol))
              ..where((t) => t.statementType.equals(statementType))
              ..orderBy([(t) => OrderingTerm.desc(t.date)])
              ..limit(1))
            .getSingleOrNull();
    return result?.date;
  }

  /// 批次取得多檔股票的最新財務資料日期（新鮮度**預篩**用）
  ///
  /// 一次 GROUP BY 取代逐檔 [getLatestFinancialDataDate]——54 檔 × 2 表
  /// 逐檔查在 app 的 isolate 連線上累積數秒。無資料的 symbol 不在回傳
  /// Map 中（caller 以 null 視為需同步）。
  Future<Map<String, DateTime>> getLatestFinancialDataDatesBatch(
    List<String> symbols,
    String statementType,
  ) async {
    if (symbols.isEmpty) return {};

    final maxDate = financialData.date.max();
    final query = selectOnly(financialData)
      ..addColumns([financialData.symbol, maxDate])
      ..where(financialData.statementType.equals(statementType))
      ..where(financialData.symbol.isIn(symbols))
      ..groupBy([financialData.symbol]);

    final rows = await query.get();
    // read() 對 aggregate 運算式回 UTC 表示，與逐檔版（table 映射、local）
    // 是同一時刻的不同表示——isBefore 比較不受影響，但為了與
    // [getLatestFinancialDataDate] 完全等價（含 == 語意），統一轉 local。
    return {
      for (final row in rows)
        if (row.read(maxDate) != null)
          row.read(financialData.symbol)!: row.read(maxDate)!.toLocal(),
    };
  }

  /// 取得單檔股票的 EPS 歷史（最近 8 季，降序）
  Future<List<FinancialDataEntry>> getEPSHistory(String symbol) {
    return (select(financialData)
          ..where((t) => t.symbol.equals(symbol))
          ..where((t) => t.statementType.equals('INCOME'))
          ..where((t) => t.dataType.equals('EPS'))
          ..orderBy([(t) => OrderingTerm.desc(t.date)])
          ..limit(8))
        .get();
  }

  /// 批次取得多檔股票的 EPS 歷史（評分管線用）
  Future<Map<String, List<FinancialDataEntry>>> getEPSHistoryBatch(
    List<String> symbols,
  ) async {
    if (symbols.isEmpty) return {};

    final entries =
        await (select(financialData)
              ..where((t) => t.symbol.isIn(symbols))
              ..where((t) => t.statementType.equals('INCOME'))
              ..where((t) => t.dataType.equals('EPS'))
              ..orderBy([(t) => OrderingTerm.desc(t.date)]))
            .get();

    final result = <String, List<FinancialDataEntry>>{};
    for (final e in entries) {
      result.putIfAbsent(e.symbol, () => []).add(e);
    }
    // 每檔只保留最近 8 季
    for (final key in result.keys) {
      if (result[key]!.length > 8) {
        result[key] = result[key]!.sublist(0, 8);
      }
    }
    return result;
  }

  /// 取得最新一季的完整財務指標（UI 用）
  Future<Map<String, double>> getLatestQuarterMetrics(String symbol) async {
    final latest =
        await (select(financialData)
              ..where((t) => t.symbol.equals(symbol))
              ..where((t) => t.statementType.equals('INCOME'))
              ..orderBy([(t) => OrderingTerm.desc(t.date)])
              ..limit(1))
            .getSingleOrNull();

    if (latest == null) return {};

    final entries =
        await (select(financialData)
              ..where((t) => t.symbol.equals(symbol))
              ..where((t) => t.date.equals(latest.date)))
            .get();

    return {
      for (final e in entries)
        if (e.value != null) e.dataType: e.value!,
    };
  }

  /// 取得單檔股票的 Equity 歷史（最近 8 季，降序）
  Future<List<FinancialDataEntry>> getEquityHistory(String symbol) {
    return (select(financialData)
          ..where((t) => t.symbol.equals(symbol))
          ..where((t) => t.statementType.equals('BALANCE'))
          ..where((t) => t.dataType.equals('Equity'))
          ..orderBy([(t) => OrderingTerm.desc(t.date)])
          ..limit(8))
        .get();
  }

  /// 批次計算 ROE 歷史（評分管線用）
  ///
  /// 從 INCOME.IncomeAfterTaxes + BALANCE.Equity 按 symbol+date join 計算
  /// ROE = IncomeAfterTaxes × 4 / Equity × 100（年化）
  /// 回傳虛擬 FinancialDataEntry (dataType='ROE')
  ///
  /// **2026-06-20 修正**：原查 `'NetIncome'` 但 DB financial_data 0 筆 'NetIncome'
  /// （幻影字串）→ roeHistory 永遠空 → ROE_EXCELLENT / ROE_IMPROVING / ROE_DECLINING
  /// 三條 rule 全史 0 fire（死碼）。正確欄位 'IncomeAfterTaxes'（稅後淨利、單季、
  /// 4585 筆）。已驗 IncomeAfterTaxes 是單季非累計 → ×4 年化正確。
  Future<Map<String, List<FinancialDataEntry>>> getROEHistoryBatch(
    List<String> symbols,
  ) async {
    if (symbols.isEmpty) return {};

    // 1. 批次查稅後淨利
    final netIncomeEntries =
        await (select(financialData)
              ..where((t) => t.symbol.isIn(symbols))
              ..where((t) => t.statementType.equals('INCOME'))
              ..where((t) => t.dataType.equals('IncomeAfterTaxes'))
              ..orderBy([(t) => OrderingTerm.desc(t.date)]))
            .get();

    // 2. 批次查 Equity
    final equityEntries =
        await (select(financialData)
              ..where((t) => t.symbol.isIn(symbols))
              ..where((t) => t.statementType.equals('BALANCE'))
              ..where((t) => t.dataType.equals('Equity'))
              ..orderBy([(t) => OrderingTerm.desc(t.date)]))
            .get();

    // 3. 建立 Equity 快速查詢 map: (symbol, date) -> value
    final equityMap = <(String, DateTime), double>{};
    for (final e in equityEntries) {
      if (e.value != null && e.value! > 0) {
        equityMap[(e.symbol, e.date)] = e.value!;
      }
    }

    // 4. 計算 ROE = **近四季淨利合計 ÷ 平均權益**（2026-08-15 數值稽核修正）
    //
    // 舊口徑是「單季淨利 × 4 ÷ 期末權益」，拿去比 15% 這個**年度**門檻。
    // 全市場實測：舊法通過 405 檔、標準法 339 檔，其中 114 檔只有舊法會過
    // （占實際觸發量 28%）、48 檔被漏掉；偏差方向隨季節走——Q4 旺季股必過、
    // Q1 淡季股必漏，量到的是台股獲利季節性而不是股東權益報酬率。
    //
    // 資料不齊（缺季、季度不連續）時**不產生該季 ROE**，不用可得資料湊
    // ×4 頂替——那正是舊口徑的錯誤本身。
    final bySymbol = <String, List<FinancialDataEntry>>{};
    for (final ni in netIncomeEntries) {
      bySymbol.putIfAbsent(ni.symbol, () => []).add(ni);
    }

    final result = <String, List<FinancialDataEntry>>{};
    for (final entry in bySymbol.entries) {
      final list = entry.value; // 已由查詢按 date DESC 排序
      for (var i = 0; i + 3 < list.length; i++) {
        final window = list.sublist(i, i + 4);
        if (window.any((e) => e.value == null)) continue;
        if (!_isConsecutiveQuarters(window)) continue;

        final ttmNet = window.fold<double>(0, (sum, e) => sum + e.value!);
        final asOf = window.first.date;
        final equityNow = equityMap[(entry.key, asOf)];
        if (equityNow == null || equityNow <= 0) continue;

        // 平均權益需要去年同季期末；查無時退回期末權益（分子仍是四季合計，
        // 不會退化成舊口徑）。日期用容差比對——實際落庫日有 ±1 天漂移。
        final equityYearAgo = _findEquityAboutOneYearBefore(
          equityEntries,
          entry.key,
          asOf,
        );
        final avgEquity = equityYearAgo == null
            ? equityNow
            : (equityNow + equityYearAgo) / 2;
        if (avgEquity <= 0) continue;

        result
            .putIfAbsent(entry.key, () => [])
            .add(
              FinancialDataEntry(
                symbol: entry.key,
                date: asOf,
                statementType: 'ROE',
                dataType: 'ROE',
                value: ttmNet / avgEquity * 100,
                originName: null,
              ),
            );
      }
    }

    // 5. 每檔只保留最近 8 季
    for (final key in result.keys) {
      if (result[key]!.length > 8) {
        result[key] = result[key]!.sublist(0, 8);
      }
    }
    return result;
  }

  /// 四筆財報日是否為連續四季（相鄰間隔約一季）。
  ///
  /// 用日數容差而非季號運算：實際落庫日有 ±1 天漂移（2026-06-29 vs 06-30），
  /// 精確比對會把正常資料判成跳季。
  static bool _isConsecutiveQuarters(List<FinancialDataEntry> descByDate) {
    for (var i = 0; i < descByDate.length - 1; i++) {
      final gap = descByDate[i].date.difference(descByDate[i + 1].date).inDays;
      if (gap < 80 || gap > 100) return false;
    }
    return true;
  }

  /// 找 [symbol] 在 [asOf] 約一年前的權益（350~380 天容差，取最接近者）。
  static double? _findEquityAboutOneYearBefore(
    List<FinancialDataEntry> equityEntries,
    String symbol,
    DateTime asOf,
  ) {
    double? best;
    int? bestDelta;
    for (final e in equityEntries) {
      if (e.symbol != symbol || e.value == null || e.value! <= 0) continue;
      final days = asOf.difference(e.date).inDays;
      if (days < 350 || days > 380) continue;
      final delta = (days - 365).abs();
      if (bestDelta == null || delta < bestDelta) {
        bestDelta = delta;
        best = e.value;
      }
    }
    return best;
  }
}
