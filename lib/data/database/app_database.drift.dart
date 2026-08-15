// dart format width=80
// ignore_for_file: type=lint
import 'package:drift/drift.dart' as i0;
import 'package:daredevil/data/database/tables/stock_master.drift.dart' as i1;
import 'package:daredevil/data/database/tables/daily_price.drift.dart' as i2;
import 'package:daredevil/data/database/tables/daily_institutional.drift.dart'
    as i3;
import 'package:daredevil/data/database/tables/news_tables.drift.dart' as i4;
import 'package:daredevil/data/database/tables/analysis_tables.drift.dart'
    as i5;
import 'package:daredevil/data/database/tables/user_tables.drift.dart' as i6;
import 'package:daredevil/data/database/tables/market_data_tables.drift.dart'
    as i7;
import 'package:daredevil/data/database/tables/portfolio_tables.drift.dart'
    as i8;
import 'package:daredevil/data/database/tables/event_tables.drift.dart' as i9;
import 'package:daredevil/data/database/tables/market_index_tables.drift.dart'
    as i10;

abstract class $AppDatabase extends i0.GeneratedDatabase {
  $AppDatabase(i0.QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final i1.$StockMasterTable stockMaster = i1.$StockMasterTable(this);
  late final i2.$DailyPriceTable dailyPrice = i2.$DailyPriceTable(this);
  late final i3.$DailyInstitutionalTable dailyInstitutional = i3
      .$DailyInstitutionalTable(this);
  late final i4.$NewsItemTable newsItem = i4.$NewsItemTable(this);
  late final i4.$NewsStockMapTable newsStockMap = i4.$NewsStockMapTable(this);
  late final i4.$NewsMentionDailyTable newsMentionDaily = i4
      .$NewsMentionDailyTable(this);
  late final i5.$DailyAnalysisTable dailyAnalysis = i5.$DailyAnalysisTable(
    this,
  );
  late final i5.$DailyReasonTable dailyReason = i5.$DailyReasonTable(this);
  late final i5.$RuleAccuracyTable ruleAccuracy = i5.$RuleAccuracyTable(this);
  late final i6.$WatchlistGroupsTable watchlistGroups = i6
      .$WatchlistGroupsTable(this);
  late final i6.$WatchlistTable watchlist = i6.$WatchlistTable(this);
  late final i6.$UpdateRunTable updateRun = i6.$UpdateRunTable(this);
  late final i6.$AppSettingsTable appSettings = i6.$AppSettingsTable(this);
  late final i6.$PriceAlertTable priceAlert = i6.$PriceAlertTable(this);
  late final i6.$PinnedThesisTable pinnedThesis = i6.$PinnedThesisTable(this);
  late final i7.$ShareholdingTable shareholding = i7.$ShareholdingTable(this);
  late final i7.$DayTradingTable dayTrading = i7.$DayTradingTable(this);
  late final i7.$FinancialDataTable financialData = i7.$FinancialDataTable(
    this,
  );
  late final i7.$HoldingDistributionTable holdingDistribution = i7
      .$HoldingDistributionTable(this);
  late final i7.$MonthlyRevenueTable monthlyRevenue = i7.$MonthlyRevenueTable(
    this,
  );
  late final i7.$StockValuationTable stockValuation = i7.$StockValuationTable(
    this,
  );
  late final i7.$DividendHistoryTable dividendHistory = i7
      .$DividendHistoryTable(this);
  late final i7.$MarginTradingTable marginTrading = i7.$MarginTradingTable(
    this,
  );
  late final i7.$TradingWarningTable tradingWarning = i7.$TradingWarningTable(
    this,
  );
  late final i7.$InsiderHoldingTable insiderHolding = i7.$InsiderHoldingTable(
    this,
  );
  late final i7.$InsiderTransferTable insiderTransfer = i7
      .$InsiderTransferTable(this);
  late final i8.$PortfolioPositionTable portfolioPosition = i8
      .$PortfolioPositionTable(this);
  late final i8.$PortfolioTransactionTable portfolioTransaction = i8
      .$PortfolioTransactionTable(this);
  late final i9.$StockEventTable stockEvent = i9.$StockEventTable(this);
  late final i10.$MarketIndexTable marketIndex = i10.$MarketIndexTable(this);
  late final i7.$QuarterlyReportTable quarterlyReport = i7
      .$QuarterlyReportTable(this);
  @override
  Iterable<i0.TableInfo<i0.Table, Object?>> get allTables =>
      allSchemaEntities.whereType<i0.TableInfo<i0.Table, Object?>>();
  @override
  List<i0.DatabaseSchemaEntity> get allSchemaEntities => [
    stockMaster,
    dailyPrice,
    dailyInstitutional,
    newsItem,
    newsStockMap,
    newsMentionDaily,
    dailyAnalysis,
    dailyReason,
    ruleAccuracy,
    watchlistGroups,
    watchlist,
    updateRun,
    appSettings,
    priceAlert,
    pinnedThesis,
    shareholding,
    dayTrading,
    financialData,
    holdingDistribution,
    monthlyRevenue,
    stockValuation,
    dividendHistory,
    marginTrading,
    tradingWarning,
    insiderHolding,
    insiderTransfer,
    portfolioPosition,
    portfolioTransaction,
    stockEvent,
    marketIndex,
    quarterlyReport,
    i1.idxStockMasterIndustry,
    i2.idxDailyPriceDate,
    i3.idxDailyInstitutionalDate,
    i4.idxNewsItemPublishedAt,
    i4.idxNewsItemSource,
    i4.idxNewsStockMapSymbol,
    i5.idxDailyAnalysisDate,
    i5.idxDailyAnalysisScoreShort,
    i5.idxDailyAnalysisScoreLong,
    i5.idxDailyAnalysisDateScoreShort,
    i5.idxDailyAnalysisDateScoreLong,
    i5.idxDailyReasonDate,
    i7.idxShareholdingDate,
    i7.idxDayTradingDate,
    i7.idxFinancialDataDate,
    i7.idxFinancialDataType,
    i7.idxHoldingDistDate,
    i7.idxMonthlyRevenueDate,
    i7.idxStockValuationDate,
    i7.idxMarginTradingDate,
    i7.idxTradingWarningDate,
    i7.idxTradingWarningType,
    i7.idxInsiderHoldingDate,
    i7.idxInsiderTransferDate,
    i8.idxPortfolioPositionSymbol,
    i8.idxPortfolioTxSymbol,
    i8.idxPortfolioTxDate,
    i9.idxStockEventDate,
    i9.idxStockEventSymbol,
    i10.idxMarketIndexDate,
    i10.idxMarketIndexName,
  ];
  @override
  i0.StreamQueryUpdateRules
  get streamUpdateRules => const i0.StreamQueryUpdateRules([
    i0.WritePropagation(
      on: i0.TableUpdateQuery.onTableName(
        'stock_master',
        limitUpdateKind: i0.UpdateKind.delete,
      ),
      result: [i0.TableUpdate('daily_price', kind: i0.UpdateKind.delete)],
    ),
    i0.WritePropagation(
      on: i0.TableUpdateQuery.onTableName(
        'stock_master',
        limitUpdateKind: i0.UpdateKind.delete,
      ),
      result: [
        i0.TableUpdate('daily_institutional', kind: i0.UpdateKind.delete),
      ],
    ),
    i0.WritePropagation(
      on: i0.TableUpdateQuery.onTableName(
        'news_item',
        limitUpdateKind: i0.UpdateKind.delete,
      ),
      result: [i0.TableUpdate('news_stock_map', kind: i0.UpdateKind.delete)],
    ),
    i0.WritePropagation(
      on: i0.TableUpdateQuery.onTableName(
        'stock_master',
        limitUpdateKind: i0.UpdateKind.delete,
      ),
      result: [i0.TableUpdate('news_stock_map', kind: i0.UpdateKind.delete)],
    ),
    i0.WritePropagation(
      on: i0.TableUpdateQuery.onTableName(
        'stock_master',
        limitUpdateKind: i0.UpdateKind.delete,
      ),
      result: [i0.TableUpdate('daily_analysis', kind: i0.UpdateKind.delete)],
    ),
    i0.WritePropagation(
      on: i0.TableUpdateQuery.onTableName(
        'stock_master',
        limitUpdateKind: i0.UpdateKind.delete,
      ),
      result: [i0.TableUpdate('daily_reason', kind: i0.UpdateKind.delete)],
    ),
    i0.WritePropagation(
      on: i0.TableUpdateQuery.onTableName(
        'stock_master',
        limitUpdateKind: i0.UpdateKind.delete,
      ),
      result: [i0.TableUpdate('watchlist', kind: i0.UpdateKind.delete)],
    ),
    i0.WritePropagation(
      on: i0.TableUpdateQuery.onTableName(
        'watchlist_groups',
        limitUpdateKind: i0.UpdateKind.delete,
      ),
      result: [i0.TableUpdate('watchlist', kind: i0.UpdateKind.update)],
    ),
    i0.WritePropagation(
      on: i0.TableUpdateQuery.onTableName(
        'stock_master',
        limitUpdateKind: i0.UpdateKind.delete,
      ),
      result: [i0.TableUpdate('price_alert', kind: i0.UpdateKind.delete)],
    ),
    i0.WritePropagation(
      on: i0.TableUpdateQuery.onTableName(
        'stock_master',
        limitUpdateKind: i0.UpdateKind.delete,
      ),
      result: [i0.TableUpdate('shareholding', kind: i0.UpdateKind.delete)],
    ),
    i0.WritePropagation(
      on: i0.TableUpdateQuery.onTableName(
        'stock_master',
        limitUpdateKind: i0.UpdateKind.delete,
      ),
      result: [i0.TableUpdate('day_trading', kind: i0.UpdateKind.delete)],
    ),
    i0.WritePropagation(
      on: i0.TableUpdateQuery.onTableName(
        'stock_master',
        limitUpdateKind: i0.UpdateKind.delete,
      ),
      result: [i0.TableUpdate('financial_data', kind: i0.UpdateKind.delete)],
    ),
    i0.WritePropagation(
      on: i0.TableUpdateQuery.onTableName(
        'stock_master',
        limitUpdateKind: i0.UpdateKind.delete,
      ),
      result: [
        i0.TableUpdate('holding_distribution', kind: i0.UpdateKind.delete),
      ],
    ),
    i0.WritePropagation(
      on: i0.TableUpdateQuery.onTableName(
        'stock_master',
        limitUpdateKind: i0.UpdateKind.delete,
      ),
      result: [i0.TableUpdate('monthly_revenue', kind: i0.UpdateKind.delete)],
    ),
    i0.WritePropagation(
      on: i0.TableUpdateQuery.onTableName(
        'stock_master',
        limitUpdateKind: i0.UpdateKind.delete,
      ),
      result: [i0.TableUpdate('stock_valuation', kind: i0.UpdateKind.delete)],
    ),
    i0.WritePropagation(
      on: i0.TableUpdateQuery.onTableName(
        'stock_master',
        limitUpdateKind: i0.UpdateKind.delete,
      ),
      result: [i0.TableUpdate('dividend_history', kind: i0.UpdateKind.delete)],
    ),
    i0.WritePropagation(
      on: i0.TableUpdateQuery.onTableName(
        'stock_master',
        limitUpdateKind: i0.UpdateKind.delete,
      ),
      result: [i0.TableUpdate('margin_trading', kind: i0.UpdateKind.delete)],
    ),
    i0.WritePropagation(
      on: i0.TableUpdateQuery.onTableName(
        'stock_master',
        limitUpdateKind: i0.UpdateKind.delete,
      ),
      result: [i0.TableUpdate('trading_warning', kind: i0.UpdateKind.delete)],
    ),
    i0.WritePropagation(
      on: i0.TableUpdateQuery.onTableName(
        'stock_master',
        limitUpdateKind: i0.UpdateKind.delete,
      ),
      result: [i0.TableUpdate('insider_holding', kind: i0.UpdateKind.delete)],
    ),
    i0.WritePropagation(
      on: i0.TableUpdateQuery.onTableName(
        'stock_master',
        limitUpdateKind: i0.UpdateKind.delete,
      ),
      result: [i0.TableUpdate('insider_transfer', kind: i0.UpdateKind.delete)],
    ),
    i0.WritePropagation(
      on: i0.TableUpdateQuery.onTableName(
        'stock_master',
        limitUpdateKind: i0.UpdateKind.delete,
      ),
      result: [
        i0.TableUpdate('portfolio_position', kind: i0.UpdateKind.delete),
      ],
    ),
    i0.WritePropagation(
      on: i0.TableUpdateQuery.onTableName(
        'stock_master',
        limitUpdateKind: i0.UpdateKind.delete,
      ),
      result: [
        i0.TableUpdate('portfolio_transaction', kind: i0.UpdateKind.delete),
      ],
    ),
    i0.WritePropagation(
      on: i0.TableUpdateQuery.onTableName(
        'stock_master',
        limitUpdateKind: i0.UpdateKind.delete,
      ),
      result: [i0.TableUpdate('quarterly_report', kind: i0.UpdateKind.delete)],
    ),
  ]);
  @override
  i0.DriftDatabaseOptions get options =>
      const i0.DriftDatabaseOptions(storeDateTimeAsText: true);
}

class $AppDatabaseManager {
  final $AppDatabase _db;
  $AppDatabaseManager(this._db);
  i1.$$StockMasterTableTableManager get stockMaster =>
      i1.$$StockMasterTableTableManager(_db, _db.stockMaster);
  i2.$$DailyPriceTableTableManager get dailyPrice =>
      i2.$$DailyPriceTableTableManager(_db, _db.dailyPrice);
  i3.$$DailyInstitutionalTableTableManager get dailyInstitutional =>
      i3.$$DailyInstitutionalTableTableManager(_db, _db.dailyInstitutional);
  i4.$$NewsItemTableTableManager get newsItem =>
      i4.$$NewsItemTableTableManager(_db, _db.newsItem);
  i4.$$NewsStockMapTableTableManager get newsStockMap =>
      i4.$$NewsStockMapTableTableManager(_db, _db.newsStockMap);
  i4.$$NewsMentionDailyTableTableManager get newsMentionDaily =>
      i4.$$NewsMentionDailyTableTableManager(_db, _db.newsMentionDaily);
  i5.$$DailyAnalysisTableTableManager get dailyAnalysis =>
      i5.$$DailyAnalysisTableTableManager(_db, _db.dailyAnalysis);
  i5.$$DailyReasonTableTableManager get dailyReason =>
      i5.$$DailyReasonTableTableManager(_db, _db.dailyReason);
  i5.$$RuleAccuracyTableTableManager get ruleAccuracy =>
      i5.$$RuleAccuracyTableTableManager(_db, _db.ruleAccuracy);
  i6.$$WatchlistGroupsTableTableManager get watchlistGroups =>
      i6.$$WatchlistGroupsTableTableManager(_db, _db.watchlistGroups);
  i6.$$WatchlistTableTableManager get watchlist =>
      i6.$$WatchlistTableTableManager(_db, _db.watchlist);
  i6.$$UpdateRunTableTableManager get updateRun =>
      i6.$$UpdateRunTableTableManager(_db, _db.updateRun);
  i6.$$AppSettingsTableTableManager get appSettings =>
      i6.$$AppSettingsTableTableManager(_db, _db.appSettings);
  i6.$$PriceAlertTableTableManager get priceAlert =>
      i6.$$PriceAlertTableTableManager(_db, _db.priceAlert);
  i6.$$PinnedThesisTableTableManager get pinnedThesis =>
      i6.$$PinnedThesisTableTableManager(_db, _db.pinnedThesis);
  i7.$$ShareholdingTableTableManager get shareholding =>
      i7.$$ShareholdingTableTableManager(_db, _db.shareholding);
  i7.$$DayTradingTableTableManager get dayTrading =>
      i7.$$DayTradingTableTableManager(_db, _db.dayTrading);
  i7.$$FinancialDataTableTableManager get financialData =>
      i7.$$FinancialDataTableTableManager(_db, _db.financialData);
  i7.$$HoldingDistributionTableTableManager get holdingDistribution =>
      i7.$$HoldingDistributionTableTableManager(_db, _db.holdingDistribution);
  i7.$$MonthlyRevenueTableTableManager get monthlyRevenue =>
      i7.$$MonthlyRevenueTableTableManager(_db, _db.monthlyRevenue);
  i7.$$StockValuationTableTableManager get stockValuation =>
      i7.$$StockValuationTableTableManager(_db, _db.stockValuation);
  i7.$$DividendHistoryTableTableManager get dividendHistory =>
      i7.$$DividendHistoryTableTableManager(_db, _db.dividendHistory);
  i7.$$MarginTradingTableTableManager get marginTrading =>
      i7.$$MarginTradingTableTableManager(_db, _db.marginTrading);
  i7.$$TradingWarningTableTableManager get tradingWarning =>
      i7.$$TradingWarningTableTableManager(_db, _db.tradingWarning);
  i7.$$InsiderHoldingTableTableManager get insiderHolding =>
      i7.$$InsiderHoldingTableTableManager(_db, _db.insiderHolding);
  i7.$$InsiderTransferTableTableManager get insiderTransfer =>
      i7.$$InsiderTransferTableTableManager(_db, _db.insiderTransfer);
  i8.$$PortfolioPositionTableTableManager get portfolioPosition =>
      i8.$$PortfolioPositionTableTableManager(_db, _db.portfolioPosition);
  i8.$$PortfolioTransactionTableTableManager get portfolioTransaction =>
      i8.$$PortfolioTransactionTableTableManager(_db, _db.portfolioTransaction);
  i9.$$StockEventTableTableManager get stockEvent =>
      i9.$$StockEventTableTableManager(_db, _db.stockEvent);
  i10.$$MarketIndexTableTableManager get marketIndex =>
      i10.$$MarketIndexTableTableManager(_db, _db.marketIndex);
  i7.$$QuarterlyReportTableTableManager get quarterlyReport =>
      i7.$$QuarterlyReportTableTableManager(_db, _db.quarterlyReport);
}
