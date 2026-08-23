/// API 端點常數
///
/// 集中管理所有外部 API URL，便於維護與修改。
abstract final class ApiEndpoints {
  // ==================================================
  // TWSE (台灣證券交易所)
  // ==================================================

  /// TWSE 官方網站基礎 URL
  static const String twseBaseUrl = 'https://www.twse.com.tw';

  /// TWSE Open Data API 基礎 URL
  static const String twseOpenDataBaseUrl = 'https://openapi.twse.com.tw';

  /// 每日全市場股價
  static const String twseDailyPricesAll = '/rwd/zh/afterTrading/STOCK_DAY_ALL';

  /// 個股歷史價格
  static const String twseStockDay = '/exchangeReport/STOCK_DAY';

  /// 三大法人買賣超（個股）
  static const String twseInstitutional = '/rwd/zh/fund/T86';

  /// 三大法人買賣金額統計表（市場總計，單位：元）
  static const String twseInstitutionalAmounts = '/rwd/zh/fund/BFI82U';

  /// 融資融券餘額
  static const String twseMarginTrading = '/rwd/zh/marginTrading/MI_MARGN';

  /// 外資及陸資投資持股統計(全市場,免費,支援歷史日期)
  ///
  /// 2026-08-16 接入:補上市股外資持股的覆蓋缺口——原本只靠 FinMind
  /// 逐檔且只同步自選+熱門約 48 檔,實測上市候選僅 24% 有資料,造成
  /// 上櫃股拿到外資訊號的機會是上市股的 4 倍。
  static const String twseForeignShareholding = '/rwd/zh/fund/MI_QFIIS';

  /// 當沖交易標的
  static const String twseDayTrading = '/exchangeReport/TWTB4U';

  /// 估值資料（本益比、殖利率、股價淨值比）- Open Data
  /// TWSE 上市公司每日重大訊息（openapi t187ap04_L）
  static const String twseMaterialInfo =
      'https://openapi.twse.com.tw/v1/opendata/t187ap04_L';

  /// TWSE 上市除權除息預告表（openapi TWT48U_ALL）——帶確定除權息交易日
  static const String twseExRightPreannouncement =
      'https://openapi.twse.com.tw/v1/exchangeReport/TWT48U_ALL';

  /// TWSE 停資停券預告表（openapi BFI84U）
  static const String twseShortSuspension =
      'https://openapi.twse.com.tw/v1/exchangeReport/BFI84U';

  static const String twseValuation =
      '$twseOpenDataBaseUrl/v1/exchangeReport/BWIBBU_ALL';

  /// 月營收資料 - Open Data
  static const String twseMonthlyRevenue =
      '$twseOpenDataBaseUrl/v1/opendata/t187ap05_L';

  /// 上市內部人持股轉讓事前申報(每日,2026-08-05 補接上市源)
  static const String twseInsiderTransfer =
      '$twseOpenDataBaseUrl/v1/opendata/t187ap12_L';

  /// 綜合損益表六業別後綴(ci=一般業、basi=金融保險、bd=證券期貨、
  /// fh=金控、ins=保險、mim=異業;兩市場共用同一組,2026-08-06 季報總覽)
  static const List<String> quarterlyReportIndustrySuffixes = [
    'ci',
    'basi',
    'bd',
    'fh',
    'ins',
    'mim',
  ];

  /// 上市綜合損益表(季報,t187ap06_L_業別;公布期逐日填充)
  static String twseQuarterlyReport(String suffix) =>
      '$twseOpenDataBaseUrl/v1/opendata/t187ap06_L_$suffix';

  /// 盤中即時報價(MIS,2026-08-08)。ex_ch 以 `tse_2330.tw|otc_6538.tw`
  /// 形式串接,前綴依 stock_master.market 決定(**別手猜市場別**)。
  /// 單次請求上限約 35 檔,超過要分批。
  static const String twseMisIntraday =
      'https://mis.twse.com.tw/stock/api/getStockInfo.jsp';

  /// 單次 MIS 請求的最大檔數
  static const int misBatchSize = 35;

  /// 大盤各類指數（每日收盤後更新）
  static const String twseMarketIndex = '/rwd/zh/afterTrading/MI_INDEX';

  /// 上市注意股票
  /// 回傳交易量異常、價格異常波動的股票清單
  /// 2025 年後端點變更：TWTAVU → notice
  static const String twseTradingWarning = '/rwd/zh/announcement/notice';

  /// 上市處置股票
  /// 回傳交易受限制的股票清單
  /// 2025 年後端點變更：TWTAUU → punish
  static const String twseDisposal = '/rwd/zh/announcement/punish';

  /// 上市董監持股 - Open Data（免費、無限制）
  /// 回傳董監事持股餘額資料，格式與 TPEX 相同（個別董監記錄）
  static const String twseInsiderHolding =
      '$twseOpenDataBaseUrl/v1/opendata/t187ap11_L';

  /// 上市股票基本資料 - Open Data（免費、無限制）
  /// 回傳上市公司基本資料，包含已發行股數
  static const String twseStockInfo =
      '$twseOpenDataBaseUrl/v1/opendata/t187ap03_L';

  /// 上市已宣告股利 - Open Data（免費、無限制）
  /// 回傳已宣告的除權息資料，含除息交易日、現金/股票股利、股東會日期
  static const String twseDeclaredDividend =
      '$twseOpenDataBaseUrl/v1/opendata/t187ap45_L';

  // ==================================================
  // TPEX (台灣櫃檯買賣中心)
  // ==================================================

  /// TPEX 官方網站基礎 URL
  static const String tpexBaseUrl = 'https://www.tpex.org.tw';

  /// 每日全市場上櫃股價（回傳 tables[0].data）
  static const String tpexDailyPricesAll =
      '/web/stock/aftertrading/daily_close_quotes/stk_quote_result.php';

  /// 三大法人上櫃買賣超（回傳 tables[0].data）
  static const String tpexInstitutional =
      '/web/stock/3insti/daily_trade/3itrade_hedge_result.php';

  /// 三大法人買賣金額彙總表（市場總計，單位：元）
  static const String tpexInstitutionalAmounts =
      '/web/stock/3insti/3insti_summary/3itrdsum_result.php';

  /// 上櫃融資融券餘額（回傳 tables[0].data，單位：張）
  ///
  /// 注意：`margin_balance` 才是正確的融資融券端點（20 欄，單位：張）。
  /// `margin_sbl` 是融券+借券端點，不包含融資資料。
  static const String tpexMarginTrading =
      '/web/stock/margin_trading/margin_balance/margin_bal_result.php';

  /// TPEX OpenAPI 基礎 URL（免費、無限制）
  /// 上櫃現股當沖交易統計（逐檔）
  ///
  /// 新站路徑（舊的 `/web/stock/.../intraday_trading_list.php` 已 302）。
  /// **無視 `date` 參數，永遠回最新交易日**——寫入日期必須取回應的 `date`。
  /// 回應含兩張表：第一張是全市場彙總，**逐檔資料在第二張**。
  static const String tpexDayTrading = '/www/zh-tw/intraday/stat';

  static const String tpexOpenApiBaseUrl = 'https://www.tpex.org.tw/openapi';

  /// 櫃買指數歷史（OHLC + Change）- OpenAPI（免費、無限制）
  /// 回傳近月每日指數資料，日期格式 YYYYMMDD
  static const String tpexIndex = '$tpexOpenApiBaseUrl/v1/tpex_index';

  /// TPEx 上櫃除權除息預告表——帶確定除權息交易日
  static const String tpexExRightPreannouncement =
      '$tpexOpenApiBaseUrl/v1/tpex_exright_prepost';

  /// 上櫃估值資料（本益比、股價淨值比、殖利率）- OpenAPI
  /// 回傳 JSON 陣列，每筆含 SecuritiesCompanyCode, PriceEarningRatio, PriceBookRatio, YieldRatio
  static const String tpexValuation =
      '$tpexOpenApiBaseUrl/v1/tpex_mainboard_peratio_analysis';

  /// 上櫃注意股票 - OpenAPI（免費、無限制）
  /// 回傳交易量異常、價格異常波動的股票清單
  static const String tpexTradingWarning =
      '$tpexOpenApiBaseUrl/v1/tpex_trading_warning_information';

  /// 上櫃處置股票 - OpenAPI（免費、無限制）
  /// 回傳交易受限制的股票清單
  static const String tpexDisposal =
      '$tpexOpenApiBaseUrl/v1/tpex_disposal_information';

  /// 上櫃董監持股 - OpenAPI（免費、無限制）
  /// 回傳董監事持股餘額資料
  static const String tpexInsiderHolding =
      '$tpexOpenApiBaseUrl/v1/mopsfin_t187ap11_O';

  /// 上櫃公司每月營業收入彙總表 - OpenAPI（免費、無限制）
  /// 回傳所有上櫃公司的月營收資料，包含月增率和年增率
  static const String tpexMonthlyRevenue =
      '$tpexOpenApiBaseUrl/v1/mopsfin_t187ap05_O';

  /// 上櫃股票基本資料 - OpenAPI（免費、無限制）
  /// 回傳上櫃公司基本資料，包含已發行股數 (IssueShares)
  static const String tpexStockInfo =
      '$tpexOpenApiBaseUrl/v1/mopsfin_t187ap03_O';

  /// 上櫃已宣告股利 - OpenAPI（免費、無限制）
  /// 回傳已宣告的除權息資料，含除息交易日、現金/股票股利
  static const String tpexDeclaredDividend =
      '$tpexOpenApiBaseUrl/v1/mopsfin_t187ap39_O';

  /// 上櫃股東會日程 - OpenAPI（免費、無限制）
  /// 回傳股東會開會日期、地點、是否改選董監、電子投票
  static const String tpexShareholderMeeting =
      '$tpexOpenApiBaseUrl/v1/t187ap41_O';

  /// 上櫃內部人股權轉讓 - OpenAPI（免費、無限制）
  /// 回傳董監事/經理人/大股東股權轉讓申報資料
  static const String tpexInsiderTransfer =
      '$tpexOpenApiBaseUrl/v1/mopsfin_t187ap12_O';

  /// 上市資產負債表(t187ap07_L_業別;後綴同季報)
  ///
  /// 2026-08-16 接入:取代 FinMind 逐檔的 BalanceSheet——那是額度的唯一
  /// 瓶頸(129 檔 × 2 = 258 次/輪)。⚠️ 金額單位是**千元**,FinMind 是元。
  static String twseBalanceSheet(String suffix) =>
      '$twseOpenDataBaseUrl/v1/opendata/t187ap07_L_$suffix';

  /// 上櫃資產負債表(mopsfin_t187ap07_O_業別)
  static String tpexBalanceSheet(String suffix) =>
      '$tpexOpenApiBaseUrl/v1/mopsfin_t187ap07_O_$suffix';

  /// 上櫃綜合損益表(季報,mopsfin_t187ap06_O_業別;後綴同上市)
  static String tpexQuarterlyReport(String suffix) =>
      '$tpexOpenApiBaseUrl/v1/mopsfin_t187ap06_O_$suffix';

  /// 上櫃融券賣出排行 - OpenAPI（免費、無限制）
  /// 回傳融券賣出排名 Top 20
  static const String tpexShortSellRanking =
      '$tpexOpenApiBaseUrl/v1/tpex_margin_trading_short_sell';

  /// 上櫃產業別 EPS - OpenAPI（免費、無限制）
  /// 回傳各產業公司的基本每股盈餘、營收、營業利益、稅後淨利
  static const String tpexIndustryEps =
      '$tpexOpenApiBaseUrl/v1/mopsfin_t187ap14_O';

  // ==================================================
  // TDCC (台灣集中保管結算所)
  // ==================================================

  /// TDCC 股權分散表 - Open Data（免費、無需認證、每週更新）
  /// 一次回傳全市場所有股票的持股級距分布
  static const String tdccHoldingDistribution =
      'https://openapi.tdcc.com.tw/v1/opendata/1-5';

  // ==================================================
  // FinMind
  // ==================================================

  /// FinMind API 基礎 URL
  static const String finmindBaseUrl =
      'https://api.finmindtrade.com/api/v4/data';

  /// FinMind 網站（供使用者註冊 Token）
  static const String finmindWebsite = 'https://finmindtrade.com/';

  // ==================================================
  // RSS 新聞來源
  // ==================================================

  // MoneyDJ 已於 2026-07-15 移除：其 RSS 退化到單次僅回 1 筆、
  // 內容以美股/國際為主（502 筆僅 4 筆能關聯個股），且掃遍分類代碼
  // （MB010000-MB070000）無台股分類可用。

  /// Yahoo 財經
  static const String rssYahooFinance =
      'https://tw.stock.yahoo.com/rss?category=tw-market';

  /// 鉅亨網
  static const String rssCnyes =
      'https://news.cnyes.com/rss/v1/news/category/tw_stock';

  /// 中央社
  static const String rssCna = 'https://feeds.feedburner.com/rsscna/finance';

  /// 經濟日報（證券版）
  static const String rssUdnMoney =
      'https://money.udn.com/rssfeed/news/1001/5590/5607?ch=money_rss';

  /// 自由財經
  static const String rssLtnBusiness =
      'https://news.ltn.com.tw/rss/business.xml';
}
