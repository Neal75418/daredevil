/// API 設定常數
///
/// 集中管理所有 API 相關的超時、延遲、重試等參數。
abstract final class ApiConfig {
  // ==================================================
  // HTTP 超時設定
  // ==================================================

  /// RSS 解析器連線超時（秒）
  static const int rssConnectTimeoutSec = 15;

  /// RSS 解析器接收超時（秒）
  static const int rssReceiveTimeoutSec = 15;

  /// TWSE 連線超時（秒）
  static const int twseConnectTimeoutSec = 30;

  /// TWSE 接收超時（秒）
  static const int twseReceiveTimeoutSec = 60;

  /// FinMind 連線超時（秒）
  static const int finmindConnectTimeoutSec = 30;

  /// FinMind 接收超時（秒）
  static const int finmindReceiveTimeoutSec = 30;

  /// TDCC 快取 TTL（分鐘）— 週資料，60 分鐘已足夠
  static const int tdccCacheTtlMin = 60;

  // ==================================================
  // 請求延遲設定（避免過度請求）
  // ==================================================

  /// FinMind 批次請求基礎延遲（毫秒）
  static const int finmindBaseDelayMs = 500;

  /// 價格資料批次查詢延遲（毫秒）
  static const int priceBatchQueryDelayMs = 250;

  /// 價格資料請求間延遲（毫秒）
  static const int priceRequestDelayMs = 200;

  /// Syncer 批次操作間延遲（毫秒），避免觸發 API rate limit
  static const int syncerBatchDelayMs = 500;

  /// TWSE 歷史資料逐月請求間延遲（毫秒）
  static const int twseHistoryRequestDelayMs = 300;

  /// t187ap03_L 官方名單的完整性下限（實際 ~1093 家）。低於此值視為
  /// 部分回應——殭屍清理（官方名單缺席→標下市）當輪跳過，避免 API
  /// 截斷造成大規模誤殺；per-symbol 的產業別覆蓋不受此限（部分名單
  /// 內的資料仍是對的）。
  /// 2026-08-05 複審調升 800→1000:實際名冊 ~1,093 家,800 留下 293 檔
  /// 的部分回應盲區(floor 過了但名單仍缺漏 → 缺席者被誤判下市)。1000
  /// 縮盲區至 ~93 檔;誤殺者若有成交,同輪價格步(STOCK_DAY_ALL feed 的
  /// isActive=true)分鐘級救回——此救援依賴為顯式設計,見
  /// stock_repository 的三態註解。若未來上市家數縮水逼近 floor,
  /// syncStockList 會記警報(見該處),屆時再行下調。
  /// 外資持股「當日資料算完整」的覆蓋率門檻(相對於上市股數)
  ///
  /// 2026-08-16 實機:正式 DB 的 8/13 只有 213 筆——FinMind 逐檔留下的
  /// 零星結果,而 MI_QFIIS 全市場是 1,200+ 筆。新鮮度檢查若用「有沒有列」,
  /// 這種半殘的日子會被永遠跳過、再也不會被重抓。0.5 遠高於零星資料的
  /// 規模、遠低於全市場快照,兩者之間有數量級的差距,不需要精細校準。
  static const double foreignShareholdingMinCoverageRatio = 0.5;

  static const int twseOfficialListSanityFloor = 1000;

  /// 名冊縮水警報門檻:本輪家數低於「DB 既有存活家數 × 此比例」即警告
  ///
  /// 2026-08-15 改用相對比較,取代原本的 `floor × 1.1`。原因:floor 是**災難
  /// 下限**不是正常值,拿它當參考點有兩個後果——(1) floor 調升到貼近實際
  /// 家數後(1000 vs ~1,095),警告從那天起必然響,噪音化等同沒有警告;
  /// (2) 真正該抓的是上面註解自承的「floor 過了但名單仍缺漏」盲區(~93 檔),
  /// 而那種情況家數遠高於 floor,絕對門檻完全看不見。
  ///
  /// 0.98 ≈ 22 家:遠高於上市家數的週級自然波動(個位數),遠低於盲區上限。
  /// 相對比較也讓「上市家數漂移就要重新校準 floor」這件人工待辦永遠不必發生。
  static const double twseOfficialRosterShrinkWarnRatio = 0.98;

  /// MOPS(公開資訊觀測站,舊版)base URL——月營收公布期漸進 CSV 來源。
  /// 新版 MOPS 已下架靜態頁,只有舊版過渡站有;關站風險由呼叫端 fail-soft
  /// 承接(退回等 openapi 月批,零下行)。
  static const String mopsBaseUrl = 'https://mopsov.twse.com.tw';

  /// MOPS WAF 會擋非瀏覽器 UA(回安全頁),需帶一般瀏覽器 UA(2026-08-03 實測)
  static const String mopsUserAgent =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
      'AppleWebKit/537.36 (KHTML, like Gecko) Safari/537.36';

  /// 月營收公布期窗口:每月 1~此日內,每日更新掃 MOPS 漸進 CSV。
  /// 法定申報截止 10 日,+4 天緩衝(補申報/更正)。
  static const int mopsRevenueWindowLastDay = 14;

  /// TWSE/TPEX 市場 API 最大重試次數
  static const int marketClientMaxRetries = 2;

  /// 重試延遲（毫秒）
  static const int retryDelayMs = 1000;

  /// 財報同步最大市場候選數（避免 FinMind 免費額度耗盡）
  static const int financialSyncMaxCandidates = 150;

  // 上櫃候選估值／營收「不設」候選上限（2026-07-29 移除 otcFundamentalsSyncMaxCount）：
  // 兩者走 TPEx OpenAPI 全市場端點、各 1 次呼叫與檔數無關,cap 省不到配額,
  // 只會讓 repo 僅 persist 前綴候選、餓死其餘覆蓋。財報是逐檔打 FinMind、
  // 成本差兩個數量級,才需要 [otcFinancialSyncMaxCount] 專屬配額。

  /// 上櫃財報（損益表＋資產負債表）每輪回填上限
  ///
  /// [financialSyncMaxCandidates] 那條路徑吃的是 `[...twse, ...tpex]` 串接後
  /// 的前 150 名，而上市候選恆為 500~800 檔以上（2026-07-27 日誌：候選 1372），
  /// **上櫃永遠是餘數而餘數是 0** —— 實測財報覆蓋率上市 32.9%、上櫃 1.5%。
  /// 故另給上櫃一條專屬配額，上市那條完全不動。
  ///
  /// 定為 100 的依據（2026-07-27 實測，非估算）：上線首輪整輪 FinMind 用量
  /// 384/600（3 + 外資持股 39 + 169 檔 × 2 + 4），其中回填佔 200。
  /// 待回填 890 檔，最舊優先下約 10 個交易日收斂，之後穩態趨近 0。
  ///
  /// 這是**上限**，實際每輪由 [UpdateService.otcFinancialLimitForBudget]
  /// 依剩餘額度下修——見 [otcFinancialBackfillReserve]。
  static const int otcFinancialSyncMaxCount = 100;

  /// 財報回填(上市+上櫃合併)的小時額度保留量(2026-08-05 季報季修復)。
  ///
  /// 上市佇列原無額度守衛——「重跑 needy 為空」的假設在**季報季**破產:
  /// Q2 一開始全市場同時變 needy,每輪 150+100 檔 ×2=488 次呼叫,單輪
  /// 吃掉 82% 小時額度(2026-08-05 實測 494/600),連點更新即 402、其他
  /// FinMind 步驟(持股/營收歷史/月營收)全滅。
  ///
  /// 200 的量法:單輪非財報 FinMind 用量 ~50(自選持股+營收歷史+OTC
  /// 配額步)×2 輪+緩衝——保證同一小時內「一輪重回填+一輪快速手動」
  /// 都不會撞 402。
  static const int financialBackfillReserve = 200;

  /// 上櫃財報回填時保留給後續步驟的 FinMind 額度
  ///
  /// 回填佇列是最舊優先，設計上保證每輪都選得出 100 檔全新的 stale 股，
  /// 所以**重跑不會變便宜**（與上市那條 needy 為空的性質相反）。
  /// 2026-07-27 實測同一 sliding 1hr 窗內兩輪合計 497/600，第三輪會破表。
  ///
  /// 40 = 步驟 6.5 上櫃外資持股配額 20（market_data_updater.dart 的
  /// `maxSyncCount` 預設值）+ 20 緩衝。
  static const int otcFinancialBackfillReserve = 40;

  /// Syncer 批次大小（每批並行處理的股票數）
  static const int syncerBatchSize = 10;

  /// 市場籌碼資料更新器批次大小（每批並行處理的股票數）
  static const int marketDataBatchSize = 5;

  /// 市場籌碼資料更新器最大總錯誤次數（斷路器閾值）
  static const int marketDataMaxTotalErrors = 5;

  /// 額度耗盡提前終止最低錯誤次數
  static const int marketDataQuotaExhaustMinErrors = 2;

  /// 外資持股查詢額外緩衝天數（確保不遺漏邊界資料）
  static const int foreignShareholdingBufferDays = 5;

  /// 歷史價格同步連續失敗批次上限（斷路器閾值）
  ///
  /// 連續失敗達此值時中止同步，避免在網路或 API 異常時持續耗費配額。
  static const int historicalPriceMaxConsecutiveFailedBatches = 2;

  /// 歷史價格同步月度 API 呼叫預算
  ///
  /// 用於動態計算單次同步最多可處理的股票數量。
  static const int historicalPriceMaxMonthlyApiCalls = 300;

  /// 歷史價格同步每批並行處理的股票數
  static const int historicalPriceBatchSize = 5;

  /// 歷史價格同步動態上限最大值
  ///
  /// 正常日（每檔平均 1 個月）約同步 200 檔。
  static const int historicalPriceMaxSyncCount = 200;

  /// 歷史價格同步動態上限最小值
  ///
  /// Fresh DB 場景（每檔平均 14 個月）仍至少同步 15 檔。
  static const int historicalPriceMinSyncCount = 15;

  /// 市場日快照回補：單次更新最多補幾個（日, 市場）
  ///
  /// 一個缺漏市場日 = 1 次 TWSE MI_INDEX 或 TPEx afterTrading 呼叫，
  /// 即可補齊該市場**全部**股票當日價格。30 × 每日更新 → 380 天窗
  /// 全缺（fresh DB）約 17 個更新日收斂。
  static const int historicalMarketDayMaxCallsPerRun = 30;

  /// 市場日快照回補：單日覆蓋率低於此比例（相對股票主檔市場股數）
  /// 視為缺漏日
  ///
  /// 用 50% 而非高門檻：歷史日的市場規模較今日小（下市股），過高會
  /// 把「已完整的舊日子」誤判為缺漏而反覆重抓（同 tool/backfill 教訓）。
  ///
  /// ⚠️ 隱性耦合：此值必須 > 候選層 per-symbol 同步所能覆蓋的市場比例
  /// （目前 CandidateSelector 流動性下限後約 43% 市場），否則「只有
  /// 候選股有資料的半市場日」會被誤判為完整、永不回補。若候選層
  /// 放寬到過半市場，需同步調高此值。
  static const double historicalMarketDayMinCoverageRatio = 0.5;

  /// 市場日快照回補：連續零筆中止閾值（端點失效防護）
  ///
  /// 交易日回 0 筆代表端點回應日期 ≠ 請求日期（repository 過濾後全數
  /// 丟棄）或日曆未知的臨時休市。連續達此值即中止本次回補，
  /// 避免燒光單次上限。
  static const int historicalMarketDayMaxConsecutiveZeroDays = 3;

  // ==================================================
  // 當沖 / 融資融券缺漏日回補
  //
  // 這兩類資料台交所約 21:00 後才發布，使用者在那之前更新就抓不到；
  // 原本 syncer 只抓「更新當下那一天」，錯過即永久缺漏
  // （2026-07-14 實測：近 30 交易日當沖缺 12 天、融資缺 10 天）。
  // ==================================================

  /// 缺漏日掃描窗（日曆天；內部以 TaiwanCalendar 過濾出交易日）
  static const int tradingBackfillLookbackDays = 40;

  /// 籌碼回補：單日、單市場的覆蓋率門檻（相對該市場在市股票數）
  ///
  /// 低於此比例視為缺漏；回補後跨過此比例才算「有進度」（否則某來源持續回
  /// 「非零但不足額」會無限重試）。**逐市場**判斷——合併門檻
  /// （`DataFreshness.fullMarketThreshold`）是以上市+上櫃合計校準的，
  /// 上市單邊約 1,280 筆低於它，上櫃失效時該日會被永遠判為缺漏。
  ///
  /// ⚠️ 隱含假設：**各市場的融資融券覆蓋率維持在該市場在市股票數的 50% 以上**
  /// （2026-07-14 實測 上市 ~99%、上櫃 ~97%，headroom 約 2×）。分母含 ETF/ETN
  /// （`StockPatterns.isValidCode` 收 00xxx），若日後大量上市**不可融資**的標的，
  /// headroom 會被無聲侵蝕——屆時需調降此值。刻意與價格用的
  /// [historicalMarketDayMinCoverageRatio] 分開（那個綁的是候選層覆蓋率）。
  static const double tradingBackfillMinCoverageRatio = 0.5;

  /// 單次更新最多回補幾個缺漏日
  ///
  /// 每天最多 3 次呼叫（當沖 1 TWSE + 融資 1 TWSE + 1 TPEx），皆為免費
  /// 公開端點、不吃 FinMind 配額。5 天 → ≤15 次呼叫，約 3 次更新即可
  /// 補完目前的積欠，之後穩態每次僅 0-1 天。
  static const int tradingBackfillMaxDaysPerRun = 5;

  /// 連續零筆中止閾值（端點失效防護，同市場日快照回補）
  static const int tradingBackfillMaxConsecutiveZeroDays = 3;

  /// 財報同步回溯天數（約 2 年）
  static const int financialSyncLookbackDays = 730;

  // ==================================================
  // 指數深度回補（解鎖大盤位階 MA60 長窗深度）
  //
  // MarketIndexSyncer 每日主同步只寫入當日資料；DB 清空後僅剩近期 API
  // 回應窗（實測 ~42 天），不足大盤位階 MA60 所需的 60 個交易日，更遠低於
  // 「52 週」深度目標（~250 交易日）。深度回補從既有最早一筆資料往回走，
  // 逐日呼叫 TWSE MI_INDEX（含 date 參數，2026-07-12 活體驗證支援歷史
  // 日期）分批補齊。僅 TWSE：TPEx 櫃買指數 OpenAPI 不支援 date 參數、
  // 無法逐日回補歷史（見 MarketIndexSyncer class doc）。
  // ==================================================

  /// 指數深度回補：單次更新最多回補幾個交易日
  ///
  /// 曾一次回補 200 天觸發 TWSE 反爬限流（redirect loop）中止同步、已回退
  /// （見 [MarketIndexSyncer] class doc）。分批 60 天/次，多輪逐步收斂：
  /// 由 fresh DB 的 ~42 天回補到 [indexBackfillTargetCalendarDays]
  /// （~250 交易日）約需 4-5 次每日同步；越過 MA60 所需的 60 個交易日
  /// 則僅需 1 次即可解鎖大盤位階。
  static const int indexBackfillMaxDaysPerRun = 60;

  /// 指數深度回補目標深度（日曆天）
  ///
  /// ~370 日曆天涵蓋約 250 個交易日（52 週），與 `AlertParams.week52LookbackDays`
  /// 的日曆/交易日換算慣例一致。
  static const int indexBackfillTargetCalendarDays = 370;

  // ==================================================
  // 排程設定
  // ==================================================

  /// 台股收盤時間（時）
  static const int marketCloseHour = 15;

  /// 台股收盤時間（分）
  static const int marketCloseMinute = 0;

  /// 背景更新重試延遲（分鐘）
  static const int backoffDelayMinutes = 15;

  // ==================================================
  // 資料處理設定
  // ==================================================

  /// 民國年轉換偏移量（民國元年 = 西元 1912 年，偏移量 = 1911）
  static const int rocYearOffset = 1911;

  /// 合理西元年下限（日期解析防護）
  ///
  /// 台股集中市場 1962 年開業，2000 為保守下限。早於此年的日期視為解析錯誤
  /// （曾出現 `0000-12-18` 等髒資料），由 [TwParseUtils.parseAdDate] 與
  /// [MarketIndexSyncer] 的寫入防護拒絕。
  static const int minSaneAdYear = 2000;

  /// 寫入日期與請求日期容許的最大偏移天數（指數同步防護）
  ///
  /// TWSE API 偶爾回傳與請求日期無關的髒日期（例如固定 `12-18`）。同步當日
  /// 資料時，若解析出的日期與請求日期相差超過此天數即視為異常並跳過。
  static const int marketIndexDateDriftToleranceDays = 7;

  /// 法人資料「日常更新」的回補天數（涵蓋分析所需的 ~10 天回溯）
  static const int institutionalDailyBackfillDays = 15;

  /// 法人資料「強制同步」的回補天數（calendar，~62 個交易日）
  ///
  /// 強制同步把回補窗拉深以補足下游信號所需的歷史深度：institutionalSurge
  /// baseline（60 日）、自營/外資 streak 深度、情緒法人 Z-score 視窗
  /// （10 日）。已完整的天由 per-day 檢查跳過（非破壞式、中斷可續傳）；
  /// 全缺時以 1 秒/交易日節流，~62 個交易日約 2-3 分鐘。
  static const int institutionalForceBackfillDays = 90;

  /// 新聞內容最大長度（超過截斷以節省儲存空間）
  static const int newsContentMaxLength = 500;

  // ==================================================
  // UI 訊息顯示時間
  // ==================================================

  /// 長訊息顯示時間（秒）- 用於成功訊息
  static const int longMessageDurationSec = 3;

  /// 短訊息顯示時間（秒）- 用於狀態更新
  static const int shortMessageDurationSec = 2;

  /// 提醒對話框顯示時間（秒）
  static const int alertDialogDurationSec = 4;

  // ==================================================
  // 重新整理設定
  // ==================================================

  /// 下拉重新整理超時（秒）
  static const int refreshTimeoutSec = 30;

  /// 大盤總覽載入超時（秒）
  ///
  /// 超過此時間後先顯示 DB 快取資料，API 回應後再更新。
  static const int marketOverviewLoadTimeoutSec = 20;

  /// 更新操作超時（分鐘）
  static const int updateTimeoutMin = 60;

  /// Provider keepAlive 持續時間（分鐘）
  static const int keepAliveMin = 3;
}

/// 快取設定常數
abstract final class CacheConfig {
  /// 批次查詢快取最大容量
  static const int batchQueryMaxSize = 50;

  /// 批次查詢快取 TTL（秒）
  static const int batchQueryTtlSec = 30;

  /// FinMind API response 快取最大容量
  static const int finmindResponseCacheMaxSize = 200;

  /// TWSE/TPEX market client response 快取最大容量
  static const int marketClientCacheMaxSize = 20;

  /// TWSE/TPEX market client 快取 TTL（分鐘）
  static const int marketClientCacheTtlMin = 30;
}
