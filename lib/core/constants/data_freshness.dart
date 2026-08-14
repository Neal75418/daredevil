/// 資料新鮮度判斷參數
///
/// 集中管理 Repository 層使用的批次資料快取門檻、
/// 時效性判斷天數和回溯緩衝天數。
abstract final class DataFreshness {
  /// 歷史回補退避:app_settings key,值為 JSON {symbol: 'yyyy-MM-dd'}
  /// (最後一次「成功抓取但覆蓋無成長」的日期)。
  ///
  /// 動機(2026-08-14,8291 尚茂實錄):窗內交易密度天生低於
  /// minAcceptableDataRatio 的股票,FinMind 已無更多資料仍每天被重打
  /// (2026-07-27 起每天白燒 1 個配額)。「count 比對」式標記會被滑動
  /// 窗的 ±1 抖動打穿,故用時間退避:期內跳過、期滿重試一次(新上市
  /// 補檔或除牌復牌時自癒),浪費有上界=1 次/退避期。
  static const String historicalBackfillBackoffKey =
      'historical_backfill_backoff_v1';

  /// 退避天數:30 天重試一次的浪費(1 次呼叫)可忽略,而真有新資料時
  /// 最多晚 30 天補上——歷史資料的時效壓力本來就低。
  static const int historicalBackfillBackoffDays = 30;

  // ==================================================
  // 批次資料快取門檻
  // ==================================================

  /// 上市（TWSE）批次資料新鮮度門檻
  ///
  /// 若該日期已有超過此數量的資料，則跳過 API 呼叫。
  static const int twseBatchThreshold = 100;

  /// 全市場批次資料新鮮度門檻
  ///
  /// 上市 + 上櫃約 1800+ 家，用 1500 作為快取判斷門檻。
  static const int fullMarketThreshold = 1500;

  /// 營收資料快取門檻
  ///
  /// 全市場通常有 ~1800+ 檔股票，超過此數量視為該月已有資料。
  static const int revenueRecordThreshold = 1000;

  // ==================================================
  // 時效性判斷
  // ==================================================

  // 財報新鮮度不用「距今 N 天」常數——財報日期是季度截止日，天數啟發式
  // 在每季發布後僅 ~2-6 週有效，其餘時間每輪重抓。統一走
  // TaiwanCalendar.expectedLatestReportQuarter（發布行事曆感知）。

  /// 上櫃估值資料新鮮天數
  ///
  /// 3 天內視為新鮮，不需重複同步。
  static const int otcValuationFreshDays = 3;

  /// 每月最少交易日數
  ///
  /// 少於此數量表示該月資料不完整，需要重新同步。
  static const int minTradingDaysPerMonth = 10;

  // ==================================================
  // 回溯緩衝天數
  // ==================================================

  /// 當沖資料回溯緩衝天數
  static const int dayTradingBufferDays = 10;

  /// 融資融券資料回溯緩衝天數
  static const int marginTradingBufferDays = 10;

  /// 董監持股預設回溯月數
  static const int insiderDefaultMonths = 12;

  /// 董監持股近期查詢月數
  static const int insiderRecentMonths = 6;

  // ==================================================
  // 當沖比例顯示門檻
  // ==================================================

  /// 高當沖比例「診斷日誌」門檻（%）——僅供 extended_market_rules 的
  /// debug log 閘門用；真正的規則判定門檻是
  /// `InstitutionalParams.dayTradingHighThreshold`（50），別混用。
  static const double dayTradingHighRatio = 30.0;

  /// 高當沖比例顯示門檻（%）— 用於日誌統計
  static const double dayTradingHighDisplayRatio = 60.0;

  /// 極高當沖比例顯示門檻（%）— 用於日誌統計
  static const double dayTradingExtremeDisplayRatio = 70.0;

  /// 當沖比例驗證上限（%）
  static const double dayTradingMaxValidRatio = 100.0;

  // ==================================================
  // App Lifecycle
  // ==================================================

  /// App 回到前景後，超過此時間（分鐘）視為資料過期，自動重新載入
  static const int appStaleThresholdMinutes = 30;

  /// 冷啟動自動更新門檻：距上次**成功** update_run 超過此時間（小時）才會
  /// 在 `TodayNotifier.loadData()` 觸發背景 `runUpdate`
  ///
  /// 「成功」二字曾只寫在此處而未落實 —— `getLatestUpdateRun()` 不過濾
  /// status，一次 PARTIAL / FAILED 會冒充「剛更新過」把重試擋滿 6 小時。
  /// 現以 `getLatestSuccessfulUpdateRun()` 為基準，狂打 API 的疑慮另由
  /// [coldStartRetryThrottleMinutes] 承接（見該常數註解）。
  ///
  /// **設計動機（2026-06-18 B-lite）**：macOS 沒有 workmanager 背景任務，
  /// CLI 走 launchd 又卡 Flutter binding（dart:ui 缺）。妥協做法：使用者
  /// 開 app 時自動跑 update。`6` 小時對齊「**一個交易日只跑 1 次就夠**」：
  /// - 同日多次開 app 不重複跑（symbol-level freshness check 也會擋）
  /// - 隔天首次開 app（≥12h）一定觸發
  /// - 出國 / 長假後回來，app 一開馬上有最新資料
  ///
  /// 非交易日（週末 / 國定假日）即使 stale 也不觸發 — 由 caller 額外用
  /// `TaiwanCalendar.isTradingDay()` 過濾。
  static const int coldStartAutoUpdateGateHours = 6;

  /// 冷啟動自動更新的**重試節流**（分鐘）：距上次「嘗試」（不分成功與否）
  /// 未滿此時間就不再觸發
  ///
  /// 與 [coldStartAutoUpdateGateHours] 是兩個不同問題，必須分開判斷：
  /// - `coldStartAutoUpdateGateHours` 問「資料夠不夠新」→ 看上次**成功**
  /// - 本常數問「是不是在狂打 API」→ 看上次**嘗試**
  ///
  /// 混成一個判斷（用 `getLatestUpdateRun` 不分 status）會讓一次失敗的更新
  /// 把重試擋滿 6 小時 —— 更新失敗反而更不會重試，方向是反的。
  /// 反過來只看成功、不節流，則會在資料久未成功時每開一次 app 就打一次 API。
  static const int coldStartRetryThrottleMinutes = 60;

  /// 孤兒 RUNNING run 的收斂門檻:`started_at` 超過此時長的 RUNNING 才視為
  /// 孤兒(app 被殺/崩潰遺留),由 DB beforeOpen 收斂成 FAILED。單輪更新
  /// 正常 2-5 分鐘、極端回補 <30 分鐘,2 小時保守涵蓋。**必須有 age
  /// cutoff**:macOS CLI(tool/daily_update.dart,launchd 排程)與 GUI 共用
  /// 同一份 DB 各開獨立連線,CLI 的 beforeOpen 無條件清 RUNNING 會誤殺
  /// GUI 正在進行的 run;真孤兒通常隔數小時至數天才被下次開啟收斂,
  /// 門檻不影響收斂效果。
  static const orphanRunningCutoff = Duration(hours: 2);

  /// 提醒認領的租約時效(2026-08-08 五次審查 I-1)。
  ///
  /// 認領(寫 `triggeredAt`)之後、消費或釋放之前 process 若被殺/斷電,
  /// 該筆會卡在 `(isActive=true, triggeredAt≠null)`:盤中路徑因
  /// `triggeredAt != null` 跳過、收盤路徑再認領也拿不到,**兩條都撿不
  /// 到**,而 UI 的開關還顯示 ON(看起來仍在盯盤)。與 update_run 的
  /// 孤兒 RUNNING 是同一個形狀,解法照抄:超過時效就回收成待監控。
  ///
  /// 15 分鐘:盤中輪詢是 5 分鐘一輪,留三輪餘裕;**必須有 cutoff**,
  /// 否則會誤殺另一個 process 正在處理中的認領。
  static const alertClaimLease = Duration(minutes: 15);

  /// 股票清單初始化最低股票數
  ///
  /// 低於此數量表示股票清單尚未完整初始化，需要從 TWSE/TPEx 同步。
  static const int minInitialStockCount = 500;

  // ==================================================
  // 歷史價格資料估算
  // ==================================================

  /// 交易日佔日曆天的比例（台股約 71%）
  ///
  /// 用於由上市天數估算預期應有的交易日筆數。
  static const double tradingDayRatio = 0.71;

  /// 歷史資料可接受比例
  ///
  /// 實際資料達預期交易日的 50% 即視為足夠，不需重複同步。
  static const double minAcceptableDataRatio = 0.5;

  // `historicalPartialSyncMonths`（早期固定 4）已於 2026-06 移除：partial 場景
  // 的 API 呼叫數實際取決於 cached 資料的月份分佈，由 estimator 動態計算，
  // 而非靠單一常數估算。詳見 `HistoricalPriceSyncer._estimateAvgMonthsNeeded`。

  // ==================================================
  // 法人資料估算
  // ==================================================

  /// 每個交易日的法人資料估計筆數（上市 + 上櫃約 1000 檔）
  ///
  /// 用於由同步天數估算已處理的資料量。
  static const int estimatedDailyInstitutionalRecords = 1000;

  /// 法人資料口徑版本（來源 + 欄位語意）
  ///
  /// 與 app_settings 的 `institutional_data_version` 比對，不符即一次性
  /// 清空重建（[InstitutionalRepository.ensureDataVersion]）。日後若更換
  /// 資料來源或欄位口徑（如 dealer_self_net 計算方式），bump 此值即可
  /// 觸發遷移——這取代了原本 force 同步每次 clearAllData 的破壞式全清
  /// （中斷會留下殘缺深度，且日常 15 天回補補不回 62 天）。
  static const String institutionalDataVersion = 'twse-batch-1';

  // ==================================================
  // 篩選器查詢回溯天數
  // ==================================================

  // ==================================================
  // 籌碼資料載入回溯天數
  // ==================================================

  /// 籌碼 API 查詢回溯天數（融資融券、法人）
  static const int chipDataLookbackDays = 20;

  /// 籌碼短期資料回溯天數（當沖、融資融券 DB 查詢）
  static const int chipTradingLookbackDays = 15;

  /// 籌碼持股比例回溯天數（外資持股 DB 查詢）
  static const int chipShareholdingLookbackDays = 90;

  // ==================================================
  // 估值資料查詢回溯天數（詳細頁面）
  // ==================================================

  /// 個股詳細頁估值 DB 查詢回溯天數
  static const int valuationDbLookbackDays = 30;

  /// 個股詳細頁估值 API fallback 查詢回溯天數
  static const int valuationApiLookbackDays = 5;

  // ==================================================
  // 新聞資料保留天數
  // ==================================================

  /// 舊新聞清理保留天數
  static const int newsRetentionDays = 30;

  // ==================================================
  // 當沖資料查詢回溯天數
  // ==================================================

  /// 當沖資料回溯查詢天數（無目標日期資料時的 fallback 窗口）
  static const int dayTradingFallbackDays = 5;

  // ==================================================
  // 月營收顯示月數
  // ==================================================

  /// 比較頁面與批次載入的月營收顯示月數
  static const int revenueDisplayMonths = 6;

  // ==================================================
  // 總報酬指數查詢回溯天數
  // ==================================================

  /// FinMind 總報酬指數預設查詢回溯天數
  static const int totalReturnIndexLookbackDays = 60;

  // ==================================================
  // 大盤位階歷史查詢回溯天數
  // ==================================================

  /// 大盤位階（均線乖離）歷史查詢回溯天數（日曆天）
  ///
  /// MA60 至少需 60 個交易日；台股交易日約佔日曆天 71%，120 日曆天約
  /// 涵蓋 85 個交易日，足以計算 MA60 並留有緩衝。與走勢圖的 30 點窗口
  /// 分離載入，避免拉長 sparkline。
  static const int marketStageHistoryLookbackDays = 120;

  // ==================================================
  // 當沖資料刪除視窗（UTC 偏移補償）
  //
  // 寫入日 X 前先刪 [X−before, X+after]（含端點），清理歷史上 UTC/本地
  // 時間不一致造成的同日變體時間戳。
  //
  // ⚠️ 不變式：before 與 after 都必須 < 24——資料列存於本地午夜，窗一旦
  // 碰到 X±1 的午夜就會把**鄰日整天刪光**。每日路徑只寫「今天」（隔天必
  // 為空）故無症狀；缺漏日回補寫歷史日時，鄰日通常有完整資料，after=36
  // 曾使回補每補一天就毀掉後一天，缺漏沿日曆往前遷移、永不收斂
  // （2026-07-14 實戰事故）。
  // ==================================================

  /// 當沖資料刪除視窗前緣（小時）— 涵蓋 UTC 偏移
  static const int dayTradingDeleteWindowBeforeHours = 12;

  /// 當沖資料刪除視窗後緣（小時）— 涵蓋 UTC 偏移
  static const int dayTradingDeleteWindowAfterHours = 12;

  // ==================================================
  // 日曆事件預覽
  // ==================================================

  /// 日曆頁面「近期事件」預覽天數
  static const int upcomingEventsDays = 14;

  // ==================================================
  // 警示資料新鮮度
  // ==================================================

  /// 警示資料同步新鮮度門檻（小時）
  ///
  /// 最近一次同步距今不超過此時間，則跳過重新同步。
  static const int warningSyncFreshnessHours = 6;

  // ==================================================
  // 警示價格歷史
  // ==================================================

  /// 價格警示觸發判定的歷史價格回溯天數
  static const int alertPriceHistoryDays = 2;
}
