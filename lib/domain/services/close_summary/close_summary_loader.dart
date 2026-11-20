/// 從資料庫讀出組裝收盤摘要需要的資料（[CloseSummaryInput]）。
library;

import 'package:daredevil/core/constants/close_summary_params.dart';
import 'package:daredevil/core/constants/market_codes.dart';
import 'package:daredevil/core/constants/market_index_names.dart';
import 'package:daredevil/core/utils/date_context.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/domain/models/close_summary.dart';
import 'package:daredevil/domain/services/close_summary/holding_checks.dart';

/// 以 `daily_price` 的最新日期為資料日；沒給 [asOf] 而資料庫沒有任何價格時
/// 回 null。[asOf] 給定時以它為資料日（量測過去的日子用）。[now] 為台灣時間。
///
/// 價格、法人讀到資料日為止，往回 `priceLookbackCalendarDays` 天。進場早於
/// 這個起點的持股，價格另外從其中最早一筆的進場日前
/// `holdingAtrLeadCalendarDays` 天讀起，成本守門價的 ATR 才算得出來（只拉長
/// 這些持股，不拉長全部自選）。
///
/// 只有價格、法人、指數依資料日截止。自選、分組、持股、交易、主檔都是讀取
/// 當下的狀態；營收也不依資料日過濾（`monthly_revenue.date` 是營收月份、不是
/// 公布日）。指定 [asOf] 量過去的日子時會混到之後的狀態，只影響量測。
Future<CloseSummaryInput?> loadCloseSummaryInput(
  AppDatabase db, {
  required DateTime now,
  DateTime? asOf,
}) async {
  final latest = asOf ?? await db.getLatestDataDate();
  if (latest == null) return null;
  final dataDate = DateContext.normalize(latest);

  final watchlist = await db.getWatchlistWithGroups();
  final groups = await db.getWatchlistGroups();
  final positions = await db.getPortfolioPositions();
  final transactions = {
    for (final p in positions)
      p.symbol: await db.getTransactionsForSymbol(p.symbol),
  };
  final symbols = {
    for (final w in watchlist) w.entry.symbol,
    for (final p in positions) p.symbol,
  }.toList();

  final startDate = dataDate.subtract(
    const Duration(days: CloseSummaryParams.priceLookbackCalendarDays),
  );
  // 進場較早的持股：只對它們另外往前讀價格
  DateTime? holdingStart;
  final longHoldings = <String>[];
  for (final MapEntry(key: symbol, value: txs) in transactions.entries) {
    final entry = holdingEntryDate(txs);
    if (entry == null) continue;
    final needed = entry.subtract(
      const Duration(days: CloseSummaryParams.holdingAtrLeadCalendarDays),
    );
    if (!needed.isBefore(startDate)) continue;
    longHoldings.add(symbol);
    if (holdingStart == null || needed.isBefore(holdingStart)) {
      holdingStart = needed;
    }
  }
  final prices = await db.getPriceHistoryBatch(
    symbols,
    startDate: startDate,
    endDate: dataDate,
  );
  if (holdingStart != null) {
    prices.addAll(
      await db.getPriceHistoryBatch(
        longHoldings,
        startDate: holdingStart,
        endDate: dataDate,
      ),
    );
  }

  final taiex = await db.getIndexHistoryBatch(
    [MarketIndexNames.taiex],
    days: CloseSummaryParams.priceLookbackCalendarDays,
    now: dataDate,
  );

  const markets = [MarketCode.twse, MarketCode.tpex];
  return CloseSummaryInput(
    dataDate: dataDate,
    now: now,
    priceReadyByMarket: {
      for (final m in markets)
        m: await db.countPricesInDayAndMarket(dataDate, m) > 0,
    },
    institutionalReadyByMarket: {
      for (final m in markets)
        m: await db.countInstitutionalInDayAndMarket(dataDate, m) > 0,
    },
    taiex: taiex[MarketIndexNames.taiex] ?? const [],
    watchlist: watchlist,
    groups: groups,
    positions: positions,
    transactions: transactions,
    stocks: await db.getStocksBatch(symbols),
    prices: prices,
    institutional: await db.getInstitutionalHistoryBatch(
      symbols,
      startDate: startDate,
      endDate: dataDate,
    ),
    revenues: await db.getRecentMonthlyRevenueBatch(
      symbols,
      months: CloseSummaryParams.revenueLookbackMonths,
    ),
  );
}
