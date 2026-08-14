import 'package:drift/drift.dart';

import 'package:daredevil/data/database/app_database.drift.dart';
import 'package:daredevil/data/database/tables/daily_institutional.drift.dart';

/// 法人買賣超排行(單一機構視角的一列)
class InstitutionalRankingRow {
  const InstitutionalRankingRow({
    required this.symbol,
    required this.name,
    required this.market,
    required this.netShares,
    required this.netAmount,
    required this.streakDays,
    required this.isDualSide,
  });

  final String symbol;
  final String name;
  final String market;

  /// 該機構淨買賣超(股;賣超為負)
  final double netShares;

  /// 淨買賣超金額(元;netShares × 當日收盤,賣超為負)
  final double netAmount;

  /// 連買/連賣天數(以資料存在的交易日連續同號計,含最新日)
  final int streakDays;

  /// 外資與投信同日同向(買榜=雙買、賣榜=雙賣)——最強共識訊號
  final bool isDualSide;
}

/// 法人買賣超排行(最新資料日的四視角)
class InstitutionalRanking {
  const InstitutionalRanking({
    required this.date,
    required this.foreignBuy,
    required this.foreignSell,
    required this.trustBuy,
    required this.trustSell,
  });

  final DateTime date;
  final List<InstitutionalRankingRow> foreignBuy;
  final List<InstitutionalRankingRow> foreignSell;
  final List<InstitutionalRankingRow> trustBuy;
  final List<InstitutionalRankingRow> trustSell;
}

/// 每日三大法人進出資料操作
mixin InstitutionalDaoMixin on $AppDatabase {
  /// 取得股票的法人資料歷史
  Future<List<DailyInstitutionalEntry>> getInstitutionalHistory(
    String symbol, {
    required DateTime startDate,
    DateTime? endDate,
  }) {
    final query = select(dailyInstitutional)
      ..where((t) => t.symbol.equals(symbol))
      ..where((t) => t.date.isBiggerOrEqualValue(startDate));

    if (endDate != null) {
      query.where((t) => t.date.isSmallerOrEqualValue(endDate));
    }

    query.orderBy([(t) => OrderingTerm.asc(t.date)]);

    return query.get();
  }

  /// 批次新增法人資料
  Future<void> insertInstitutionalData(
    List<DailyInstitutionalCompanion> entries,
  ) async {
    await batch((b) {
      for (final entry in entries) {
        b.insert(dailyInstitutional, entry, mode: InsertMode.insertOrReplace);
      }
    });
  }

  /// 批次取得多檔股票的法人資料（批次查詢）
  ///
  /// 回傳 symbol -> 法人資料列表 的 Map，依日期升冪排序
  Future<Map<String, List<DailyInstitutionalEntry>>>
  getInstitutionalHistoryBatch(
    List<String> symbols, {
    required DateTime startDate,
    DateTime? endDate,
  }) async {
    if (symbols.isEmpty) return {};

    final query = select(dailyInstitutional)
      ..where((t) => t.symbol.isIn(symbols))
      ..where((t) => t.date.isBiggerOrEqualValue(startDate));

    if (endDate != null) {
      query.where((t) => t.date.isSmallerOrEqualValue(endDate));
    }

    query.orderBy([
      (t) => OrderingTerm.asc(t.symbol),
      (t) => OrderingTerm.asc(t.date),
    ]);

    final results = await query.get();

    // 依 symbol 分組
    final grouped = <String, List<DailyInstitutionalEntry>>{};
    for (final entry in results) {
      grouped.putIfAbsent(entry.symbol, () => []).add(entry);
    }

    return grouped;
  }

  /// 全市場法人資料範圍查詢（無 symbol 過濾），依 symbol 分組
  ///
  /// 族群排行需要全市場（~2,500 檔）近幾個交易日的法人淨買賣。
  /// [getInstitutionalHistoryBatch] 走 `symbol IN (...)`，SQLite 變數上限
  /// 撐不住全市場清單 → 提供無過濾版本（與 PriceDao.getAllPricesInRange
  /// 同款設計）。
  Future<Map<String, List<DailyInstitutionalEntry>>>
  getAllInstitutionalInRange({
    required DateTime startDate,
    DateTime? endDate,
  }) async {
    final query = select(dailyInstitutional)
      ..where((t) => t.date.isBiggerOrEqualValue(startDate));

    if (endDate != null) {
      query.where((t) => t.date.isSmallerOrEqualValue(endDate));
    }

    query.orderBy([
      (t) => OrderingTerm.asc(t.symbol),
      (t) => OrderingTerm.asc(t.date),
    ]);

    final results = await query.get();

    final grouped = <String, List<DailyInstitutionalEntry>>{};
    for (final entry in results) {
      grouped.putIfAbsent(entry.symbol, () => []).add(entry);
    }
    return grouped;
  }

  /// 取得指定日期的法人資料筆數
  Future<int> getInstitutionalCountForDate(DateTime date) async {
    final countExpr = dailyInstitutional.symbol.count();
    final query = selectOnly(dailyInstitutional)
      ..addColumns([countExpr])
      ..where(dailyInstitutional.date.equals(date));
    final result = await query.getSingle();
    return result.read(countExpr) ?? 0;
  }

  /// 清除所有法人資料
  ///
  /// 用於修正單位錯誤後重新同步資料
  Future<int> clearAllInstitutionalData() async {
    return await (delete(dailyInstitutional)).go();
  }

  /// 計算某交易日已寫入的法人資料筆數（backfill per-day resume 判斷用，
  /// 與 [PriceDaoMixin.countPricesByDateAndMarket] 同模式；法人 phase
  /// 兩市場一起跑，故不分市場、比對全市場總數）。
  Future<int> countInstitutionalByDate(DateTime date) async {
    final result = await customSelect(
      'SELECT COUNT(*) AS cnt FROM daily_institutional WHERE date = ?',
      variables: [Variable.withDateTime(date)],
    ).getSingle();
    return result.read<int>('cnt');
  }

  /// 法人買賣超排行(2026-08-05,盤後籌碼排行頁)。
  ///
  /// 口徑:
  /// - 排序鍵=金額(淨股數 × 當日收盤)——跨價位可比;張數並列供顯示
  /// - 連買天數:資料存在的交易日連續同號,含最新日(90 日回看窗)
  /// - 雙買/雙賣:外資與投信同日同向
  /// - 自營刻意不做(避險盤污染+持續性差,2026-08-05 設計定稿)
  /// - 只列 active 股票;無當日收盤價者無法計金額,不進榜
  Future<InstitutionalRanking?> getInstitutionalRanking({
    int limit = 50,
  }) async {
    // 基準日=「上市資料已到」的最新日,不是裸 MAX(date):TPEx 法人
    // ~15:00 先發布、TWSE ~16:00 後——15:30 輪之後、21:30 輪之前的
    // 時段裸 MAX 會指向只有上櫃的半套日,外資榜整排只剩上櫃股。
    // 上市較晚發布,它到了=兩市場都齊(2026-08-05 實測過渡態後修正)。
    final latest = await customSelect(
      'SELECT MAX(di.date) AS d FROM daily_institutional di '
      'JOIN stock_master sm ON sm.symbol = di.symbol '
      "WHERE sm.market = 'TWSE'",
      readsFrom: {dailyInstitutional, stockMaster},
    ).getSingleOrNull();
    final latestStr = latest?.readNullable<String>('d');
    if (latestStr == null) return null;

    final rows = await customSelect(
      'SELECT di.symbol, sm.name, sm.market, '
      '       di.foreign_net, di.investment_trust_net, dp.close '
      'FROM daily_institutional di '
      'JOIN stock_master sm ON sm.symbol = di.symbol AND sm.is_active = 1 '
      'JOIN daily_price dp ON dp.symbol = di.symbol AND dp.date = di.date '
      // ETF(00 開頭)不進榜:法人對 ETF 的買賣是申購/造市的機制性
      // 行為(投信買 0050 常為自家申購),非選股觀點;與掃描器排除
      // ETF 的口徑一致(2026-08-05 實機複查:0050/0056/00947 曾入榜)
      'WHERE di.date = ? AND dp.close IS NOT NULL '
      "AND di.symbol NOT LIKE '00%'",
      variables: [Variable.withString(latestStr)],
      readsFrom: {dailyInstitutional, stockMaster, dailyPrice},
    ).get();
    if (rows.isEmpty) return null;

    final parsed = rows
        .map(
          (r) => (
            symbol: r.read<String>('symbol'),
            name: r.read<String>('name'),
            market: r.read<String>('market'),
            foreignNet: r.readNullable<double>('foreign_net'),
            trustNet: r.readNullable<double>('investment_trust_net'),
            close: r.read<double>('close'),
          ),
        )
        .toList();

    // 四視角各自取 top,先選出需要算連買天數的 symbol 聯集
    List<T> topBy<T>(
      List<T> list,
      double Function(T) key, {
      required bool descending,
    }) {
      final sorted = List.of(list)
        ..sort(
          (a, b) =>
              descending ? key(b).compareTo(key(a)) : key(a).compareTo(key(b)),
        );
      return sorted.take(limit).toList();
    }

    final fBuy = topBy(
      parsed.where((r) => (r.foreignNet ?? 0) > 0).toList(),
      (r) => r.foreignNet! * r.close,
      descending: true,
    );
    final fSell = topBy(
      parsed.where((r) => (r.foreignNet ?? 0) < 0).toList(),
      (r) => r.foreignNet! * r.close,
      descending: false,
    );
    final tBuy = topBy(
      parsed.where((r) => (r.trustNet ?? 0) > 0).toList(),
      (r) => r.trustNet! * r.close,
      descending: true,
    );
    final tSell = topBy(
      parsed.where((r) => (r.trustNet ?? 0) < 0).toList(),
      (r) => r.trustNet! * r.close,
      descending: false,
    );

    // 連買天數:只為榜上 symbol 算(60 日回看;ISO 字串前 10 碼比較,
    // 避開儲存格式的時區後綴差異)
    final symbols = <String>{
      for (final r in [...fBuy, ...fSell, ...tBuy, ...tSell]) r.symbol,
    };
    final latestDay = DateTime.parse(latestStr.substring(0, 10));
    final cutoff = latestDay
        .subtract(const Duration(days: 90))
        .toIso8601String()
        .substring(0, 10);
    // 上界鎖基準日(2026-08-05 複審 High #4):TPEx 法人比 TWSE 早發布,
    // 過渡態(15:30~21:30)DB 已有比基準日更新的上櫃列;無上界時 DESC
    // 首列是那筆,streak 與榜單的量口徑錯開一天(live 實測 8 檔錯 5 檔)。
    final histRows = symbols.isEmpty
        ? const <QueryRow>[]
        : await customSelect(
            'SELECT symbol, date, foreign_net, investment_trust_net '
            'FROM daily_institutional '
            "WHERE symbol IN (${List.filled(symbols.length, '?').join(', ')}) "
            "AND date >= '$cutoff' AND date <= ? "
            'ORDER BY symbol, date DESC',
            variables: [
              for (final sym in symbols) Variable.withString(sym),
              Variable.withString(latestStr),
            ],
            readsFrom: {dailyInstitutional},
          ).get();

    final histBySymbol = <String, List<({double? f, double? t})>>{};
    for (final r in histRows) {
      histBySymbol.putIfAbsent(r.read<String>('symbol'), () => []).add((
        f: r.readNullable<double>('foreign_net'),
        t: r.readNullable<double>('investment_trust_net'),
      ));
    }

    int streak(String symbol, {required bool foreign, required bool buy}) {
      var count = 0;
      for (final day in histBySymbol[symbol] ?? const []) {
        final net = foreign ? day.f : day.t;
        final match = net != null && (buy ? net > 0 : net < 0);
        if (!match) break;
        count++;
      }
      return count;
    }

    InstitutionalRankingRow toRow(
      ({
        double? foreignNet,
        String market,
        String name,
        String symbol,
        double? trustNet,
        double close,
      })
      r, {
      required bool foreign,
      required bool buy,
    }) {
      final net = foreign ? r.foreignNet! : r.trustNet!;
      final other = foreign ? r.trustNet : r.foreignNet;
      return InstitutionalRankingRow(
        symbol: r.symbol,
        name: r.name,
        market: r.market,
        netShares: net,
        netAmount: net * r.close,
        streakDays: streak(r.symbol, foreign: foreign, buy: buy),
        isDualSide: other != null && (buy ? other > 0 : other < 0),
      );
    }

    return InstitutionalRanking(
      date: latestDay,
      foreignBuy: [for (final r in fBuy) toRow(r, foreign: true, buy: true)],
      foreignSell: [for (final r in fSell) toRow(r, foreign: true, buy: false)],
      trustBuy: [for (final r in tBuy) toRow(r, foreign: false, buy: true)],
      trustSell: [for (final r in tSell) toRow(r, foreign: false, buy: false)],
    );
  }
}
