import 'package:drift/drift.dart';

import 'package:daredevil/data/database/tables/stock_master.dart';

/// 外資持股資料 Table
@DataClassName('ShareholdingEntry')
@TableIndex(name: 'idx_shareholding_date', columns: {#date})
class Shareholding extends Table {
  /// 股票代碼
  TextColumn get symbol =>
      text().references(StockMaster, #symbol, onDelete: KeyAction.cascade)();

  /// 交易日期
  DateTimeColumn get date => dateTime()();

  /// 外資持股餘額（股）
  RealColumn get foreignRemainingShares => real().nullable()();

  /// 外資持股比例（%）
  RealColumn get foreignSharesRatio => real().nullable()();

  /// 外資持股上限比例（%）
  RealColumn get foreignUpperLimitRatio => real().nullable()();

  /// 已發行股數
  RealColumn get sharesIssued => real().nullable()();

  @override
  Set<Column> get primaryKey => {symbol, date};
}

/// 當沖資料 Table
///
/// **資料來源說明：**
/// - TWSE TWTB4U（上市）：買賣欄位為金額（元）
/// - TPEx `/www/zh-tw/intraday/stat`（上櫃，2026-08-23 接上）：同一組欄位語意，
///   2026-08-21 兩市場各 6 檔 × 3 欄位與官方逐位元相符，故共用本表。
///   ⚠️ 兩市場同寫一天，故 delete window 與新鮮度檢查都必須分市場。
///
/// [dayTradingRatio] 為交易訊號使用的主要指標，
/// 由每日價量資料另行計算。
@DataClassName('DayTradingEntry')
@TableIndex(name: 'idx_day_trading_date', columns: {#date})
class DayTrading extends Table {
  /// 股票代碼
  TextColumn get symbol =>
      text().references(StockMaster, #symbol, onDelete: KeyAction.cascade)();

  /// 交易日期
  DateTimeColumn get date => dateTime()();

  /// 當沖買進金額（元，TWSE TWTB4U）
  RealColumn get buyVolume => real().nullable()();

  /// 當沖賣出金額（元，TWSE TWTB4U）
  RealColumn get sellVolume => real().nullable()();

  /// 當沖比例（%）
  ///
  /// 此為主要指標，由總成交量計算。
  RealColumn get dayTradingRatio => real().nullable()();

  /// 當沖成交股數
  RealColumn get tradeVolume => real().nullable()();

  @override
  Set<Column> get primaryKey => {symbol, date};
}

/// 季報快照(官方申報事實,2026-08-06)。
///
/// 來源:TWSE/TPEx openapi 綜合損益表(t187ap06 六業別 × 兩市場,公布期
/// 逐日填充)。與 [FinancialData](FinMind 回補)的差異:本表反映「誰已
/// 申報」的**官方事實**,不受自家回補佇列進度影響——季報總覽頁的清單
/// 完整性以此為基礎(沿月營收 MOPS 的同一設計原則)。
/// EPS/淨利為**累計制**(Q2=上半年);FinMind 的 financial_data EPS 是
/// **單季**值,口徑不同——YoY 基期須加總去年各季(見
/// QuarterlyReportDaoMixin)。
class QuarterlyReport extends Table {
  /// 股票代碼
  TextColumn get symbol =>
      text().references(StockMaster, #symbol, onDelete: KeyAction.cascade)();

  /// 西元年度
  IntColumn get year => integer()();

  /// 季別 1~4
  IntColumn get quarter => integer()();

  /// 基本每股盈餘(元,累計)
  RealColumn get eps => real().nullable()();

  /// 本期淨利(千元,累計)
  RealColumn get netIncome => real().nullable()();

  /// 營業收入(千元,累計;金融業別無此欄為 NULL)
  RealColumn get revenue => real().nullable()();

  @override
  Set<Column> get primaryKey => {symbol, year, quarter};
}

/// 財務報表資料 Table
///
/// 儲存損益表、資產負債表、現金流量表的 Key-Value 資料
@DataClassName('FinancialDataEntry')
@TableIndex(name: 'idx_financial_data_date', columns: {#date})
@TableIndex(name: 'idx_financial_data_type', columns: {#dataType})
class FinancialData extends Table {
  /// 股票代碼
  TextColumn get symbol =>
      text().references(StockMaster, #symbol, onDelete: KeyAction.cascade)();

  /// 報告日期（季度以日期格式儲存）
  DateTimeColumn get date => dateTime()();

  /// 報表類型：INCOME、BALANCE、CASHFLOW
  TextColumn get statementType => text()();

  /// 資料項目（如 Revenue、IncomeAfterTaxes、TotalAssets——⚠️ NetIncome 是 0 筆的幻影 key，見 financial_data_dao）
  TextColumn get dataType => text()();

  /// 數值（千元）
  RealColumn get value => real().nullable()();

  /// 原始中文名稱
  TextColumn get originName => text().nullable()();

  @override
  Set<Column> get primaryKey => {symbol, date, statementType, dataType};
}

/// 股權分散表 Table
///
/// 每個持股級距一筆資料（非正規化設計）
@DataClassName('HoldingDistributionEntry')
@TableIndex(name: 'idx_holding_dist_date', columns: {#date})
class HoldingDistribution extends Table {
  /// 股票代碼
  TextColumn get symbol =>
      text().references(StockMaster, #symbol, onDelete: KeyAction.cascade)();

  /// 報告日期
  DateTimeColumn get date => dateTime()();

  /// 持股級距（如 "1-999"、"1000-5000"）
  TextColumn get level => text()();

  /// 該級距股東人數——**已備料未消費**(2026-08-15 健檢)
  ///
  /// TDCC 每週寫入、目前僅 level/percent 有讀取端。刻意保留:與 percent
  /// 同在一列回應內(零額外請求),而「股東人數變化」是無法從現有欄位
  /// 推導的獨立訊號(人數減少=籌碼集中),停寫等於放棄未來的回溯基準。
  IntColumn get shareholders => integer().nullable()();

  /// 佔總股數比例（%）
  RealColumn get percent => real().nullable()();

  /// 持股數（股）——已備料未消費(同 [shareholders] 的保留理由)
  RealColumn get shares => real().nullable()();

  @override
  Set<Column> get primaryKey => {symbol, date, level};
}

/// 股利歷史 Table
///
/// 儲存歷年現金股利、股票股利、除權息日期
@DataClassName('DividendHistoryEntry')
class DividendHistory extends Table {
  /// 股票代碼
  TextColumn get symbol =>
      text().references(StockMaster, #symbol, onDelete: KeyAction.cascade)();

  /// 股利所屬年度
  IntColumn get year => integer()();

  /// 現金股利（元）
  RealColumn get cashDividend => real().withDefault(const Constant(0))();

  /// 股票股利（元）
  RealColumn get stockDividend => real().withDefault(const Constant(0))();

  /// 除息日（格式: yyyy-MM-dd）
  TextColumn get exDividendDate => text().nullable()();

  /// 除權日（格式: yyyy-MM-dd）
  TextColumn get exRightsDate => text().nullable()();

  @override
  Set<Column> get primaryKey => {symbol, year};
}

/// 月營收 Table
///
/// 用於基本面分析訊號
@DataClassName('MonthlyRevenueEntry')
@TableIndex(name: 'idx_monthly_revenue_date', columns: {#date})
class MonthlyRevenue extends Table {
  /// 股票代碼
  TextColumn get symbol =>
      text().references(StockMaster, #symbol, onDelete: KeyAction.cascade)();

  /// 報告日期（統一使用當月第一天）
  DateTimeColumn get date => dateTime()();

  /// 營收年度
  IntColumn get revenueYear => integer()();

  /// 營收月份
  IntColumn get revenueMonth => integer()();

  /// 月營收（千元）
  RealColumn get revenue => real()();

  /// 月增率（%）
  RealColumn get momGrowth => real().nullable()();

  /// 年增率（%）
  RealColumn get yoyGrowth => real().nullable()();

  /// 累計年增率 %(年初至當月 vs 去年同期;2026-08-13 加欄)。
  ///
  /// 來源與單月欄同一支 API(openapi/MOPS 皆自帶),FinMind 歷史回補
  /// 路徑無此資料留 null。既有 DB 由 `_ensureMonthlyRevenueYtdColumn`
  /// 補欄——本表不在 fingerprint 白名單,但 bump 指紋會 wipe 全部非
  /// 白名單表(含 58.7 萬列價格),走 ALTER 前例(dealer_self_net)。
  RealColumn get ytdYoyGrowth => real().nullable()();

  @override
  Set<Column> get primaryKey => {symbol, date};
}

/// 股票估值資料 Table（本益比、股價淨值比、殖利率）
///
/// 用於基本面分析訊號
@DataClassName('StockValuationEntry')
@TableIndex(name: 'idx_stock_valuation_date', columns: {#date})
class StockValuation extends Table {
  /// 股票代碼
  TextColumn get symbol =>
      text().references(StockMaster, #symbol, onDelete: KeyAction.cascade)();

  /// 交易日期
  DateTimeColumn get date => dateTime()();

  /// 本益比（PE ratio）
  RealColumn get per => real().nullable()();

  /// 股價淨值比（PB ratio）
  RealColumn get pbr => real().nullable()();

  /// 殖利率（%）
  RealColumn get dividendYield => real().nullable()();

  @override
  Set<Column> get primaryKey => {symbol, date};
}

/// 融資融券 Table
///
/// 用於籌碼分析訊號
@DataClassName('MarginTradingEntry')
@TableIndex(name: 'idx_margin_trading_date', columns: {#date})
class MarginTrading extends Table {
  /// 股票代碼
  TextColumn get symbol =>
      text().references(StockMaster, #symbol, onDelete: KeyAction.cascade)();

  /// 交易日期
  DateTimeColumn get date => dateTime()();

  // ── 已備料未消費(2026-08-15 健檢盤點)────────────────────────────
  // 下列四欄(marginBuy/marginSell/shortBuy/shortSell)每日全市場寫入但
  // 目前無讀取端——消費端只用 marginBalance/shortBalance 兩個「存量」。
  //
  // **刻意保留不停抓**:它們與餘額欄同在一列 API 回應內(twse_client
  // `row[2]`/`row[3]`、tpex_client 同),解析它們不需額外請求 → API 成本
  // 為零,只多約 21 MB/年儲存;而一旦停寫,未來要做「當日買賣超流量」
  // 分析時歷史補不回來(TWSE 明細不保證回溯)。備料成本 << 斷層代價。
  //
  // 要開消費請從這裡找:融資買賣超 = 散戶當日進出強度(餘額只看得到淨變化)。

  /// 融資買進（張）——已備料未消費
  RealColumn get marginBuy => real().nullable()();

  /// 融資賣出（張）——已備料未消費
  RealColumn get marginSell => real().nullable()();

  /// 融資餘額（張）
  RealColumn get marginBalance => real().nullable()();

  /// 融券買進/回補（張）——已備料未消費
  RealColumn get shortBuy => real().nullable()();

  /// 融券賣出（張）——已備料未消費
  RealColumn get shortSell => real().nullable()();

  /// 融券餘額（張）
  RealColumn get shortBalance => real().nullable()();

  @override
  Set<Column> get primaryKey => {symbol, date};
}

/// 注意股票/處置股票 Table
///
/// 用於風險控管：
/// - 注意股票 (ATTENTION): 交易量異常、價格異常波動
/// - 處置股票 (DISPOSAL): 嚴重異常，交易受限制
@DataClassName('TradingWarningEntry')
@TableIndex(name: 'idx_trading_warning_date', columns: {#date})
@TableIndex(name: 'idx_trading_warning_type', columns: {#warningType})
class TradingWarning extends Table {
  /// 股票代碼
  TextColumn get symbol =>
      text().references(StockMaster, #symbol, onDelete: KeyAction.cascade)();

  /// 公告日期
  DateTimeColumn get date => dateTime()();

  /// 警示類型：ATTENTION（注意）| DISPOSAL（處置）
  TextColumn get warningType => text()();

  /// 列入原因代碼
  TextColumn get reasonCode => text().nullable()();

  /// 原因說明
  TextColumn get reasonDescription => text().nullable()();

  /// 處置措施（僅處置股）
  TextColumn get disposalMeasures => text().nullable()();

  /// 處置起始日
  DateTimeColumn get disposalStartDate => dateTime().nullable()();

  /// 處置結束日
  DateTimeColumn get disposalEndDate => dateTime().nullable()();

  /// 是否目前生效
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  @override
  Set<Column> get primaryKey => {symbol, date, warningType};
}

/// 董監事持股餘額 Table
///
/// 用於內部人持股變化追蹤：
/// - 連續減持為強賣訊號
/// - 大量增持為買進訊號
/// - 高質押率為風險警示
@DataClassName('InsiderHoldingEntry')
@TableIndex(name: 'idx_insider_holding_date', columns: {#date})
class InsiderHolding extends Table {
  /// 股票代碼
  TextColumn get symbol =>
      text().references(StockMaster, #symbol, onDelete: KeyAction.cascade)();

  /// 報告日期（月報）
  DateTimeColumn get date => dateTime()();

  /// 董監持股比例（%）
  RealColumn get insiderRatio => real().nullable()();

  /// 質押比例（%）
  RealColumn get pledgeRatio => real().nullable()();

  /// 持股變動（股）- 與前期比較
  RealColumn get sharesChange => real().nullable()();

  /// 已發行股數
  RealColumn get sharesIssued => real().nullable()();

  @override
  Set<Column> get primaryKey => {symbol, date};
}

/// 內部人股權轉讓申報 Table
///
/// 儲存董監事、經理人、大股東的股權轉讓申報記錄。
/// 資料來源：TPEX ap12_O API。
@DataClassName('InsiderTransferEntry')
@TableIndex(name: 'idx_insider_transfer_date', columns: {#reportDate})
class InsiderTransfer extends Table {
  /// 股票代碼
  TextColumn get symbol =>
      text().references(StockMaster, #symbol, onDelete: KeyAction.cascade)();

  /// 申報日期
  DateTimeColumn get reportDate => dateTime()();

  /// 申請人身分（董事、經理人、大股東等）
  TextColumn get identity => text()();

  /// 姓名
  TextColumn get name => text()();

  /// 轉讓方式（一般交易、盤後定價等）
  TextColumn get transferMethod => text()();

  /// 轉讓股數
  IntColumn get transferShares => integer()();

  /// 目前持有股數
  IntColumn get currentHolding => integer()();

  /// 有效轉讓期間起始日
  DateTimeColumn get validPeriodStart => dateTime().nullable()();

  /// 有效轉讓期間結束日
  DateTimeColumn get validPeriodEnd => dateTime().nullable()();

  /// PK 含 [transferMethod](2026-08-16):同人同日以多種方式申報是實際
  /// 存在的形態(2026-08-14 實機 2442 一位經理人未成年子女三筆),PK 不含
  /// 轉讓方式時 `insertOrReplace` 會塌縮、轉讓總量低報。既有 DB 由
  /// `AppDatabase.ensureInsiderTransferPk()` 以 idempotent DDL 升級。
  @override
  Set<Column> get primaryKey => {
    symbol,
    reportDate,
    identity,
    name,
    transferMethod,
  };
}
