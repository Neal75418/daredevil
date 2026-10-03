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

/// 股利配發 Table：一次除權息一列
///
/// 來源為 TWSE 除權除息計算結果表（TWT49U／TWT49UDetail）與 TPEx
/// exDailyQ，皆可回溯歷史、附除權息交易日。季配、半年配、月配各期分列
/// （[DividendHistory] 以 (symbol, year) 為 PK，同年多次配息會互相覆蓋）。
///
/// 只有現金增資的除權不是股利，但也寫入（金額皆 0）：有這列＝這次除權息
/// 已處理過，同步才不會對它重查 TWT49UDetail。讀取端查詢（DAO 的
/// `getDividendDistributions*`）只回有配發的列。
@DataClassName('DividendDistributionEntry')
class DividendDistribution extends Table {
  /// 股票代碼
  TextColumn get symbol =>
      text().references(StockMaster, #symbol, onDelete: KeyAction.cascade)();

  /// 除權息交易日（當地午夜，與 daily_price.date 同樣正規化）
  DateTimeColumn get exDate => dateTime()();

  /// 每股現金股利（元）。必填、無預設值：來源拆不出的金額不得以 0 寫入。
  RealColumn get cashDividend => real()();

  /// 每千股無償配股（股）。存股數而非面額元：面額不一定是 10 元，
  /// 股數才是股東實際配到的量。必填、無預設值（同上）。
  RealColumn get stockSharesPerThousand => real()();

  /// 除權息前收盤價（列表）。還原因子的分母。null＝列表缺值，或 2026-10
  /// 以前寫入、尚未由回補補價的列
  RealColumn get closeBefore => real().nullable()();

  /// 除權息參考價（列表）：交易所訂的除權息後參考價，含現金增資的影響。
  /// 還原因子＝[referencePrice] ÷ [closeBefore]
  RealColumn get referencePrice => real().nullable()();

  @override
  Set<Column> get primaryKey => {symbol, exDate};
}

/// 除權除息逐月完成紀錄：一列＝一個事實
///
/// 一列代表：該市場該月的除權除息列表中，代號屬於當時在市股票主檔
/// （`getAllActiveStocks`，與每輪本月同步同一定義）的每一列都已寫入
/// [DividendDistribution]，「權」「權息」列都已查過 TWT49UDetail。當時略過
/// 的代號記在 [skippedSymbols]；其中任一個之後變成在市，這個事實就不再
/// 涵蓋現況，該月視為未完成、重新回補。
///
/// - 沒有列＝未知，不等於那個月沒配息。本月與未來月份永遠沒有列。
/// - 只能經 DAO 的 `completeDividendMonth` 寫入（同一個 transaction 內核對
///   預期的列都在庫）。
/// - 與 [DividendDistribution] 同生共死：不可加進 schema fingerprint 的
///   保留白名單。資料被清掉而完成紀錄還在，會把缺資料讀成沒配息。
/// - 月份鍵用 year＋month 兩個 INT：DateTimeColumn 在 text 模式下會帶
///   時區 offset，PK 比的是原始字串、比較卻走 julianday，兩者不一致。
@DataClassName('DividendMonthLedgerEntry')
class DividendMonthLedger extends Table {
  /// `MarketCode.twse`／`MarketCode.tpex`
  TextColumn get market => text()();

  /// 西元年
  IntColumn get year => integer()();

  /// 1–12
  // Drift 文件的欄位 CHECK 寫法，產生碼處理自我引用，不會遞迴
  // ignore: recursive_getters
  IntColumn get month => integer().check(month.isBetweenValues(1, 12))();

  /// 完成時間（台北牆鐘，診斷用）
  DateTimeColumn get completedAt => dateTime()();

  /// 列表原始列數（含不在主檔的代號）
  IntColumn get listedRows => integer()();

  /// 已知代號的列數；完成時這些列全在 [DividendDistribution]（含金額皆 0
  /// 的已處理列）
  IntColumn get knownRows => integer()();

  /// 當時不在主檔而略過的代號：排序、去重、逗號分隔；沒有則為空字串
  TextColumn get skippedSymbols => text()();

  /// 完成時是否已以列表記錄該月各列的前收盤與除權息參考價。2026-10 以前
  /// 寫下的紀錄為 false，回補重開這些月份一次（只打列表）補價
  BoolColumn get pricesRecorded =>
      boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {market, year, month};
}

/// 除權除息逐月回補的失敗紀錄（營運狀態，不是事實）
///
/// 給回補排程退避與 warning 用；判斷資料是否完整只看
/// [DividendMonthLedger]。該單位完成時整列刪除。與 [DividendMonthLedger]
/// 同生共死，不可加進保留白名單。
@DataClassName('DividendMonthFailureEntry')
class DividendMonthFailure extends Table {
  /// `MarketCode.twse`／`MarketCode.tpex`
  TextColumn get market => text()();

  /// 西元年
  IntColumn get year => integer()();

  /// 1–12
  // Drift 文件的欄位 CHECK 寫法，產生碼處理自我引用，不會遞迴
  // ignore: recursive_getters
  IntColumn get month => integer().check(month.isBetweenValues(1, 12))();

  /// 自上次完成以來失敗的輪數
  IntColumn get failCount => integer()();

  /// 最後一次失敗的時間（台北牆鐘）
  DateTimeColumn get lastFailedAt => dateTime()();

  /// 最後一次失敗的第一個錯誤（截斷至 300 字）
  TextColumn get lastError => text()();

  /// 最後一次失敗時明細查不到或核對不符的代號：排序、去重、逗號分隔。
  /// 診斷用，程式不讀（退避看 failCount／lastFailedAt，warning 看
  /// failCount／lastError）；預算用完而中斷時未查的列也不在這裡，哪些列
  /// 不在庫要看 `dividend_unresolved`。
  TextColumn get failedSymbols => text()();

  /// 最後一次失敗時列表本身是否成功（列表失敗時整月的列都不可信）
  BoolColumn get listOk => boolean()();

  @override
  Set<Column> get primaryKey => {market, year, month};
}

/// 除權除息列表已同步到哪一天：一列＝某市場某月的列表已涵蓋到
/// [listedThrough]（含）
///
/// 本月同步與歷史回補在列表成功後寫入（DAO `recordDividendListing`），只能
/// 連續前進。讀取端的「有效列表日」另把完成紀錄算進去（完成＝列到月底），
/// 只寫完成紀錄的舊版程式寫下的完成也算數。與 [DividendDistribution] 同生
/// 共死，不可加進保留白名單。
@DataClassName('DividendListingEntry')
class DividendListing extends Table {
  /// `MarketCode.twse`／`MarketCode.tpex`
  TextColumn get market => text()();

  /// 西元年
  IntColumn get year => integer()();

  /// 1–12
  // Drift 文件的欄位 CHECK 寫法，產生碼處理自我引用，不會遞迴
  // ignore: recursive_getters
  IntColumn get month => integer().check(month.isBetweenValues(1, 12))();

  /// 列表已涵蓋到的日期（含），當地午夜
  DateTimeColumn get listedThrough => dateTime()();

  @override
  Set<Column> get primaryKey => {market, year, month};
}

/// 列表上有、但不在 [DividendDistribution] 的除權除息列
///
/// 列表成功後以範圍內的現況整批取代（DAO `recordDividendListing`）。讀取端
/// 據此逐檔判斷完整度：清單上的代號在那段期間不完整。與
/// [DividendDistribution] 同生共死，不可加進保留白名單。
@DataClassName('DividendUnresolvedEntry')
class DividendUnresolved extends Table {
  /// `MarketCode.twse`／`MarketCode.tpex`
  TextColumn get market => text()();

  /// 不加外鍵：可能是不在股票主檔的代號
  TextColumn get symbol => text()();

  /// 除權息交易日（當地午夜）
  DateTimeColumn get exDate => dateTime()();

  /// `DividendUnresolvedReason.code`
  TextColumn get reason => text()();

  /// 這次判定的時間（台北牆鐘，診斷用）
  DateTimeColumn get recordedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {market, symbol, exDate};
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

  // ── 當日流量欄 ────────────────────────────────────────────────────
  // 下列四欄(marginBuy/marginSell/shortBuy/shortSell)與餘額欄同在一列 API
  // 回應內(兩市場的融資券列解析),解析不需額外請求。
  // 消費端:大盤總覽融資／融券列的當日增減顯示,以及籌碼槓桿判讀
  // (`MarketReadingService.interpretMarginLeverage`)。市場情緒分數的融資
  // 子項用的是餘額歷史,不讀這四欄。

  /// 融資買進（張）
  RealColumn get marginBuy => real().nullable()();

  /// 融資賣出（張）
  RealColumn get marginSell => real().nullable()();

  /// 融資餘額（張）
  RealColumn get marginBalance => real().nullable()();

  /// 融券買進/回補（張）
  RealColumn get shortBuy => real().nullable()();

  /// 融券賣出（張）
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
/// 資料來源：上市 TWSE t187ap12_L、上櫃 TPEx mopsfin_t187ap12_O。
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

/// 盤後資料的抓取狀態（2026-09-26）
///
/// 每組（資料集, 市場, 資料日）記最後一次**全市場**抓取成功寫入的時間。
/// 「是否定案」由 `fetched_at` 與資料日算出（見 `isFetchFinal`），刻意不存
/// 旗標，避免旗標與事實不同步。只有全市場抓取會寫入；逐檔、部分股票的
/// 抓取不代表那天整個市場已抓過。
@DataClassName('MarketDayFetchEntry')
class MarketDayFetch extends Table {
  /// `MarketDataset.code`
  TextColumn get dataset => text()();

  /// `MarketCode.twse`／`MarketCode.tpex`
  TextColumn get market => text()();

  /// 資料日（與 daily_price.date 同樣正規化為當地午夜）
  DateTimeColumn get date => dateTime()();

  /// 抓取時間：台北牆鐘（`AppClock.now()`），取本輪更新開始的時刻。
  /// 比實際發出請求早，只會讓判定偏向「未定案」。
  DateTimeColumn get fetchedAt => dateTime()();

  /// 該次寫入的列數（診斷用）
  IntColumn get rowCount => integer()();

  @override
  Set<Column> get primaryKey => {dataset, market, date};
}
