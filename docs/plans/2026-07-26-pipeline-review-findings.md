# 更新流程稽核 — 原始 Finding 全集（2026-07-26）

本檔為 13-agent 稽核 workflow 的**原始輸出存檔**，共 46 項（已去重；
多個 agent 對同一問題的重複回報保留為獨立條目，因其證據角度不同）。

存在的理由：稽核結果原本只活在對話與 workflow 暫存裡，一經 context 壓縮就
無法獨立追蹤「哪些做了、哪些沒做」。本檔把 `title` / `evidence` /
`analystImpact` / `recommendation` / `effort` **逐字保留**，並標註處理狀態。

> ⚠️ **標為「未查證」者，連是不是真問題都尚未確認。** 本輪實測顯示稽核
> finding 誤報率不低——曾多次推翻 finding 的關鍵前提（例：某提案宣稱的門檻
> 會放行半市場、「PARTIAL 是常態」與實測 54:2 相反）。任何一項在動手前都
> 必須先以 grep / DB 查詢親自查證。

## 狀態圖例

| 標記 | 意義 |
|:---|:---|
| ✅ 已修 | 本輪修復，經 mutation 驗證；實作已 grep 確認存在於程式碼 |
| ⚠️ 曾修後撤回 | 修法本身有問題已回退，理由見該項目自身的說明 |
| 📋 已記錄未修 | 查證為真但受資料源／配額／時間限制，非改 code 可解 |
| ❓ 未查證 | 尚未確認真偽 |

## 分布

- 嚴重度：high 16 / medium 23 / low 7
- 處理狀態（2026-07-27 收盤重新計數）：❓ 14 / ✅ 19 / 📋 11 / ⚠️ 2

## 值得優先查證的未查證項

以下幾項若為真，嚴重度應高於原始標記，建議優先：

- **生產評分路徑的基本面批次查詢沒有 as-of 上界**（標記 low）——若為真是
  look-ahead，重跑歷史日會把未來資料寫進 `daily_reason`
- **前景與背景更新沒有跨 isolate 互斥**（medium）
- **下市／長停股整檔剔除＝用訊號當下不可知的未來資訊做樣本選擇**（medium）
- **三個步驟 10+ 跑在 `_finishUpdate` 之後，失敗仍顯示「更新完成」**（medium）

---

## severity: high

### 1. InstitutionalSyncResult.errors 被 coordinator 丟棄——同款 pattern 在 Fundamental/Dividend 有明文警告，法人這條漏掉

**狀態**：✅ 已修 — 同批錯誤轉發修復

**證據**：lib/domain/services/update_service.dart:516-527 只讀 instResult.estimatedCount，從未讀 instResult.errors；lib/domain/services/update/institutional_syncer.dart:60 與 98 把當日/回補失敗塞進 errors 並回傳；對照 lib/domain/services/update/fundamental_syncer.dart:499-502 的註解「caller 必須讀取並轉發到 UpdateResult，否則對使用者靜默（與 DividendSyncResult.errors 同 pattern）」——股利（update_service.dart:408）與基本面（625,637,779）都有轉發，只有法人漏了

**對分析判斷的影響**：當日法人抓取失敗時 syncedDays 停在 0，log 印出「法人資料同步完成: 0 天」——與今天日誌裡「9 天已完整跳過（不睡不打）→ 0 天」的健康狀態逐字相同，肉眼無法分辨；UpdateResult.errors 為空 → 綠燈「更新完成」。法人買賣超是 INSTITUTIONAL_BUY 系列規則的唯一輸入，當日缺就代表外資/投信連買、買超爆量等訊號整批不觸發。使用者的解讀會是「今天沒有法人在買」，實際是「法人資料沒抓到」——這兩者的交易含意完全相反。

**建議**：在 update_service.dart:527 後加 `for (final e in instResult.errors) ctx.result.errors.add('法人: $e');`；同時把 InstitutionalSyncer 的收尾 log 拆成 syncedDays=0(全跳過) 與 syncedDays=0(全失敗) 兩種訊息，讓日誌本身可診斷。

**工作量**：small

### 2. WarningRepository 完全不吃校正後日期，非交易日回補時整段跳過上市注意/處置股 API

**狀態**：❓ 未查證

**證據**：lib/data/repositories/warning_repository.dart:60-63 `syncAllMarketWarnings({bool force})` 是全 pipeline 唯一連 date 參數都沒有的同步入口，內部一律用 `_clock.now()`；:87 `final isTradingDay = TaiwanCalendar.isTradingDay(today)`；:98-124 只有 isTradingDay 為真才呼叫 TWSE `getTradingWarnings` / `getDisposalInfo`，否則走 :123 的 debug log。呼叫端 lib/domain/services/update/market_data_updater.dart:513 `_warningRepo.syncAllMarketWarnings(force: force)` 也沒有把 UpdateService 已經校正好的 `ctx.normalizedDate`（update_service.dart:205-212）傳進去。2026-07-25 日誌實證：`[WarningRepo] 非交易日，跳過 TWSE 注意/處置股票 API` 且 `警示同步: 34 筆 (上市注意 0, 上市處置 0, 上櫃注意 22, 上櫃處置 31)`，同一輪 `ModeRecommendations ... droppedDisposal=0`。

**對分析判斷的影響**：整條 pipeline 都已經校正到 7/24 在跑 7/24 的資料，只有警示這一段還活在 7/25，結果是：非交易日跑更新時，上市（TWSE）的注意/處置名單完全不會刷新，只剩上櫃資料是新的。處置股是 v3 法則裡直接踢出可交易宇宙的硬條件（-50 分、mode 推薦 droppedDisposal），而我最需要這份名單的時機恰好就是週末/連假在排下週交易計畫的時候。具體踩雷情境：某上市股週四盤後被公告處置，我週四沒開 App，週日開 App 跑更新 → 上市處置名單停留在週三的狀態 → 這檔股票沒被 droppedDisposal 排除，照常出現在起漲/強勢榜 → 我週一掛單買進，才發現它是分盤撮合（每 5 或 20 分鐘一次）加全額交割，當沖不能做、停損也砍不掉。上櫃股不會有這個問題、上市股會，這種市場別不對稱的失效最難靠肉眼發現。

**建議**：(1) `syncAllMarketWarnings` 增加 `required DateTime date` 參數，由 MarketDataUpdater 從 UpdateService 的 `ctx.normalizedDate` 一路傳下來，`isTradingDay` 與寫入的 `normalizedDate` 都改用它——校正後日期本來就保證是交易日，非交易日分支自然不再誤觸；(2) 若 TWSE 公告端點確實只吃「當日」而無法帶歷史日期（:85-87 註解的說法），那就不能靜默跳過：非交易日路徑至少要把「上市警示為 N 天前的舊資料」寫進 `UpdateResult.errors`，讓摘要顯示警告，而不是回傳一個看起來成功的 34 筆；(3) 順手把 syncKillerFeaturesData 的結果納入 ctx.result.errors——目前 update_service.dart:748-750 明寫「不加入 errors」，等於這類缺漏對使用者永遠靜默。

**工作量**：medium

### 3. _syncKillerFeatures 明文「不加入 errors」：警示同步整段失敗完全無聲，新公告的處置股會照樣進三模式榜

**狀態**：✅ 已修 — `killerResult.warningError` / `insiderError` 已轉發至 `result.errors`

**證據**：lib/domain/services/update_service.dart:747-750（generic catch 註解「不加入 errors，因為這是額外功能，不影響主流程」，只 AppLogger.warning）；lib/domain/services/update/market_data_updater.dart:503-543 回傳的 warningError / insiderError（宣告於 585-604）全 repo 無任何消費點；syncKillerFeaturesData 把 NetworkException rethrow（515-518），rethrow 後正好落進 update_service.dart:748 的裸 catch；lib/data/repositories/warning_repository.dart:95-146 的 failCount 部分失敗也只 log 不回傳

**對分析判斷的影響**：處置股是三模式榜的硬性宇宙排除（lib/presentation/providers/mode_recommendation_provider.dart:429 `activeWarnings[symbol]?.warningType == 'DISPOSAL'`）。今天新公告的處置股若 TWSE/TPEx 警示端點掛了就不會寫進 trading_warning，getActiveWarningsMapBatch 查不到 → droppedDisposal=0，該股正常出現在「起漲/強勢/回檔」榜單，同時 DisposalWarningRule / AttentionWarningRule（rules/warning_rules.dart:24,55）也不觸發，卡片連風險徽章都不會亮。使用者對一檔分盤交易＋預收款券、根本無法照常進出的股票下單，而整場更新是綠燈。

**建議**：把 killerResult.warningError / insiderError 轉發進 ctx.result.errors（該欄位當初就是為此設計的，卻沒有 caller）；warning_repository.syncAllMarketWarnings 回傳 per-source 失敗數而非只在全滅時拋 NetworkException，讓「今天真的沒有新警示」與「抓不到」可區分。

**工作量**：small

### 4. rateLimitedAbort 只擋同步不擋評分：限流截斷的更新照樣完成評分並寫入 daily_analysis/daily_reason，與完整日在 DB 中無法區分

**狀態**：✅ 已修 `c359d07` — 判準刻意**不用**該旗標：「兩市場皆空」是正常回傳不拋例外、NetworkException 同樣不翻旗，故改以資料本身（最後一根 bar 是否為評分日）為準

**證據**：lib/domain/services/update_service.dart:366/380/394/421/479/511/542/548/550/552/758 都有 `if (ctx.rateLimitedAbort) return;`，但步驟 6 篩選（265）、步驟 7-8 `_analyzeStocks`（274、812-832）完全沒有這個檢查。`_finishUpdate`（834-855）只把 partial 狀態寫進 update_run，daily_analysis / daily_reason 沒有任何降級標記。RateLimitException 來源真實存在：lib/data/remote/api_budget_tracker.dart:86-101 在 FinMind 600/hr 用完時就會拋。UI 的限流對話框只掛在手動下拉路徑 lib/presentation/screens/today/today_screen.dart:815-825；背景路徑 lib/app/headless_update_runner.dart:104 與 lib/app/background_update_service.dart:80-94（每日 15:00 WorkManager）完全沒有 UI。

**對分析判斷的影響**：假設 FinMind 在法人同步階段撞限流：ctx.rateLimitedAbort 翻起，基本面/上櫃補資料/6.5 全部跳過，但評分照跑——法人買超、基本面類規則因為缺資料而不觸發。隔天早上我開 app 看到的起漲/強勢/回檔三個 tab，長得跟正常日一模一樣，實際上是「半盲」算出來的：該進的沒進榜（漏訊號），該被扣分的沒被扣。更糟的是這批降級 reason 會被步驟 10+ 的 RuleAccuracyService 當成正常樣本永久計入（rule_accuracy_service.dart:127-148 無日期/品質過濾），污染我用來判斷規則可信度的命中率，而且不會隨下次更新自動修復。

**建議**：在步驟 6 之前加 `if (ctx.rateLimitedAbort)` 分支，二選一：(a) 直接跳過 scoring、保留前一日分析，並在 update_run message 標明「資料不完整，未產生當日評分」；(b) 照樣評分但在 daily_analysis 加 `degraded` 欄位，讓 RuleAccuracyService 排除該日、UI 在三模式頁掛角標。無論哪一種，背景/CLI 路徑都要有可查證的落地紀錄，不能只靠前景 snackbar。

**工作量**：medium

### 5. 上櫃（TPEx）資料覆蓋系統性缺口：估值/PBR/當沖對上櫃全盲，掃描榜單結構性偏向上市股

**狀態**：📋 已記錄未修 — 實測估值/月營收上櫃涵蓋 249/904 vs 上市 1,080/1,225；受 FinMind 配額綁定

**證據**：實測 DB：daily_reason 全期 `PBR_UNDERVALUED` TWSE 150 筆 / TPEx **0** 筆；`DAY_TRADING_HIGH|EXTREME` TWSE 102 筆 / TPEx **0** 筆；day_trading 表逐日皆只有 TWSE ~1129 筆、TPEx 0（lib/data/remote/tpex_client.dart 無任何當沖端點）。估值覆蓋：TPEx 226/1311 檔（17%）vs TWSE 1081/1379（78%）；2026/6 月營收：TPEx 294 vs TWSE 1203。結果 7/24 daily_analysis 只有 27 檔 TPEx vs 115 檔 TWSE，但當日有價格的是 TPEx 904 / TWSE 1225（TPEx 佔 42% 宇宙、只佔 19% 榜位）。配額限制見 lib/domain/services/update/market_data_updater.dart:373-383（maxSyncCount=20）與日誌「上櫃候選 269 檔超過配額限制，僅同步前 20 檔」。

**對分析判斷的影響**：兩個具體傷害：(1) 一檔上櫃股跟一檔上市股基本面完全相同，上櫃那檔因為沒有估值/營收資料，少拿 PBR_UNDERVALUED(12)+PE_UNDERVALUED(15)+REVENUE 系列的分數，永遠排在上市股後面——我以為榜單是「全市場最強的」，實際是「上市股最強的」。台股中小型飆股大量在上櫃，這等於系統性錯過我最想抓的那一段。(2) 我是當沖交易者，卻在任何上櫃股上都看不到「高當沖比」警示——不是「這檔當沖比低」，是「根本沒資料」。我會把「沒警示」讀成「籌碼乾淨」，然後在一檔 75% 當沖比的上櫃股上接刀。

**建議**：(a) 短期：在 UI 上把「資料不可得」與「未觸發」分開——上櫃股的當沖/估值欄位顯示「無資料」而非留白，風險徽章區加一行「本檔缺當沖資料」。(b) 中期：TPEx 有免費 OpenAPI 的當沖統計與本益比/股價淨值比日報（與 TWSE 同性質的整批端點），改走整批而非 FinMind 逐檔，就能同時解掉 20 檔配額天花板。(c) 在有整批來源之前，評分層應對缺資料的市場做分數正規化（例如按「可得資料項數」歸一），避免覆蓋率直接轉成排名優勢。

**工作量**：large

### 6. 價格走快取路徑時，候選排序從「波動度降冪」退化成「股票代號升冪」，於是當天所有 take(N) 配額都優先發給 ETF

**狀態**：⚠️ 部分已修（2026-07-27）

**ETF 佔位那半已修**：`3faea63`（籌碼異動）、`22bdfd0`（財報配額）、`1de3234`
（上櫃財報回填）三處都改成「過濾早於取前 N」。

**排序退化本身仍在，刻意未修。** 2026-07-27 實測量化：上市有財報者依代號分段
1xxx 63% / 2xxx 37% / 3xxx 48% / 5xxx 23% / 9xxx **7%**——確有偏斜。

但同日的對抗式驗證指出一個削弱因素：**每個新交易日 `existingCount=0` 必走 API
路徑**（`price_repository.dart` 的 `fullMarketThreshold`=1500），而 API 路徑本來
就依波動度降冪排序。快取路徑只在「同日重跑」時生效。故影響面小於原始描述，
但「同日重跑時名額固定給同一批」仍為真。未修。

**證據**：API 路徑 lib/data/repositories/price_candidate_filter.dart:47 `candidates.sort((a,b)=>b.score.compareTo(a.score))`（依 |漲跌幅| 排序）；快取路徑同檔 :56-75 `quickFilterCandidatesFromDb` 完全沒有排序，且 lib/data/database/dao/price_dao.dart:92-94 的查詢無 ORDER BY。實測該查詢 `EXPLAIN QUERY PLAN` 走 idx_daily_price_date，前 25 筆為 0050,0051,0052,0053,0055,0056,0057,0061,006203…00668（全是 ETF）。日誌對照：「價格同步: 2129 筆 (2026-07-24, 快取)」→「[FundamentalSyncer] 財報同步: 跳過 111 檔 ETF，實際同步 39 檔」（update_service.dart:692-701 的 150 個財報名額有 111 個給了 ETF 後被丟棄）；DB 實測 7/24 有外資持股的 20 檔上櫃股中 6 檔是 ETF（00877/00887/00888/00928/00955/009815）。

**對分析判斷的影響**：非交易日回補與同日第二次更新（冷啟動 6 小時 gate 會觸發）走的都是快取路徑。那些 run 裡，財報名額 74%、上櫃外資持股名額 30% 花在 ETF 上，而 ETF 在 ModeRecommendations 又被 droppedEtf 丟掉（日誌 droppedEtf=7）。結果是當天真正在動的股票拿不到 EPS/ROE/外資資料，EPS_*、ROE_*、FOREIGN_* 規則對它們永遠沉默——我在榜單上看到的「基本面好」的股票，其實只是「有被查財報」的那 39 檔自選+熱門股。

**建議**：(1) `quickFilterCandidatesFromDb` 補上與 API 路徑相同的波動度排序（daily_price 已有 price_change 欄位可直接算）；(2) 在所有 per-symbol 配額切片前先用 `StockPatterns.isEtfCode` 過濾，與 syncFinancialStatements/syncBalanceSheets 的既有做法一致（目前 syncOtcCandidatesFundamentals / syncOtcCandidatesMarketData 都沒過濾）。

**工作量**：small

### 7. 全市場價格抓取失敗被 safeAwait 吞成空陣列，評分照跑並把昨天的 K 棒寫成今天的分析

**狀態**：✅ 已修 `c359d07` / `b2275af` — 資格檢查加入當日 bar 判斷（`staleBar`）；另修 regime 橫斷面污染與今日頁日期錨。`MarketSyncResult.emptyMarkets` 提供 per-market 可見度

**證據**：lib/data/repositories/price_repository.dart:338-357（safeAwait 把例外轉空陣列；兩邊皆空只 AppLogger.warning 後回傳 MarketSyncResult(count:0)，不拋例外）→ lib/domain/services/update_service.dart:465（pricesUpdated=0，不記 error）→ lib/domain/services/update/candidate_selector.dart:37-41（候選來自 getSymbolsWithSufficientData 歷史窗，不要求當日有價）→ lib/domain/services/scoring_pipeline.dart:25-37（classifyCandidate 只檢查筆數與流動性，完全沒有 prices.last.date == date 的檢查）→ 規則層一律拿 data.prices.last 當「今天」（lib/domain/services/rules/pullback_rules.dart:58,121,242,345、candlestick_rules.dart:66,128,170）

**對分析判斷的影響**：TWSE 端點掛掉或回 HTML 錯誤頁（safeAwait 吃掉例外）時，上市 2,000+ 檔今日 K 棒完全沒進 DB，但這些股票仍被選為候選、規則拿「昨天收盤」當「今天收盤」算漲跌幅、量比、突破、回檔位置，結果寫進 daily_analysis(date=今天)。UI 顯示綠色「更新完成，分析 142 檔」、零警告。更陰險的是若只有 TWSE 掛、TPEx 成功，今日頁的資料日期取 MAX(daily_price.date)（today_provider.dart:125 → getLatestDataDate）會顯示今天，連日期這個最後防線都失效。使用者隔天早上照著實際是前一天的訊號在開盤下單。

**建議**：三層都要補：(1) MarketSyncResult 增加 per-market 成功旗標，syncAllPricesForDate 在任一市場空/失敗時把訊息塞進錯誤清單（不要只 log）；(2) UpdateService 收到「當日價格覆蓋率低於門檻」時把它當 fatal，不進入 _analyzeStocks，而不是照跑後宣告成功；(3) classifyCandidate 新增 CandidateSkipReason.staleData（prices.last.date != date），讓陳舊資料進入既有的評分帳目計數而不是靜默通過。

**工作量**：medium

### 8. 外資持股「latest」查詢無日期下限，輪替過的上櫃股用最舊 9 天前的持股算「近 60 日增持」並照樣觸發 +18

**狀態**：✅ 已修 — `buildShareholdingMap` 導入雙 cutoff：delta 用 `foreignShareholdingMaxStaleTradingDays`（緊）、level 用 `foreignShareholdingLevelMaxStaleTradingDays`（鬆），並記錄 level vs delta 的腐壞速度不同

**證據**：lib/data/database/dao/shareholding_dao.dart:39-53 `getLatestShareholdingsBatch` 只有 `MAX(date)`、無 startDate 下界；78-99 `getShareholdingsBeforeDateBatch` 同樣無下界。lib/domain/services/update/batch_data_builder.dart:20-37 直接把 latest 與 prev 相減成 `foreignSharesRatioChange`，全程沒有新鮮度 gate。明確對照組：估值有 gate——lib/domain/services/rules/fundamental_scan_rules.dart:14-16 `_isValuationStale` + lib/core/constants/rule_params_fundamental.dart:55 `valuationMaxStaleDays = 7`，同一個團隊在估值上做了防護、在持股上沒做。DB 實證：147 檔的 latest 日期分佈為 7/23:55、7/22:28、7/21:14、7/20:18、7/19:8、7/16:6、7/15:13、7/14:5——只有 55 檔是最新日，92 檔（63%）是舊資料，最舊已 9 天。

**對分析判斷的影響**：上櫃候選每天只輪到前 20 檔（market_data_updater.dart:374-376），輪過一次之後就停在那天。實際情境：一檔上櫃股 7/15 進過 top-20 抓了資料、之後再沒輪到，今天評分時仍拿 7/15 的持股比 5/16 的持股算「外資近 60 日持續增持」→ 觸發 +18 進推薦榜。我看到「外資持續加碼」的證據 chip 而買進，但那是兩個多月前結束的行為，外資可能早已在最近三週賣光。這比完全沒資料更危險——沒資料至少規則會安靜跳過，陳舊資料會主動製造一個看起來有憑有據的假訊號。

**建議**：比照 valuation 的做法，在 ShareholdingData 建構或規則入口加 `shareholdingMaxStaleDays` gate（建議 ≤3 個交易日，因為這是日頻資料，比估值更該嚴），超期回 null 讓 ForeignShareholdingIncreasing/Decreasing/Exodus 全部跳過。同時 `getShareholdingsBeforeDateBatch` 應加下界（例如 beforeDate - 30 天），避免 prev 拿到半年前的列讓 change 變成長期漂移量而非 60 日變化。

**工作量**：small

### 9. 外資持股只覆蓋 147/2690 檔（自選+15 檔硬編碼權值股+輪替 20 檔上櫃），+18 分規則結構性只有特權池拿得到

**狀態**：📋 已記錄未修 — 實測全市場僅 147 檔有資料；`maxSyncCount = 20` 的配額取捨

**證據**：lib/domain/services/update_service.dart:578-586 只對 `watchlistSymbols ∪ _popularStocks` 呼叫 syncSymbolsMarketData；popularStocks 是 lib/core/constants/default_stocks.dart:9-25 的 15 檔硬編碼權值股。上櫃額外走 lib/domain/services/update/market_data_updater.dart:345-383，`otcCandidates.take(maxSyncCount)`（預設 20）。DB 實證：`SELECT COUNT(DISTINCT symbol) FROM shareholding` = 147（stock_master 共 2690 檔，TWSE 1379 / TPEx 1311）。分數：lib/core/constants/rule_scores.dart:166 foreignShareholdingIncreasing=+18、169 decreasing=-12、295 foreignExodus=-20；規則在 lib/domain/services/rules/extended_market_rules.dart:14-70 與 insider_rules.dart:127,165。今日 daily_reason 實測：FOREIGN_SHAREHOLDING_INCREASING 命中 16 檔（TWSE 8 / TPEx 8），佔 142 檔評分結果的 11%，但有資格觸發的候選不到 897 檔的 6%。

**對分析判斷的影響**：排行榜把「有外資持股資料」與「沒有」的股票放在同一把尺上比分數。我的自選股與那 15 檔權值股天生比別人多 18 分的上限，我會誤以為「我追蹤的股票品質就是比較好」，實際上那是資料覆蓋造成的分數通膨。反向更致命：一檔外資近兩個月狂買的非自選中小型股，因為 shareholding 表裡根本沒有它，永遠拿不到這 +18，也永遠不會因為外資撤退拿到 -20 → 掃描結果對「外資動向」這個維度在 94% 的市場上是全盲的，但 UI 呈現的卻是一份統一的排名。

**建議**：短期：在推薦卡片/詳情頁對沒有外資持股資料的股票明確標示「此項未評估」，並在 ranking 說明揭露覆蓋率，避免跨股比較被誤讀。中期：外資持股不必逐檔打 FinMind——TWSE 有全市場外資及陸資持股比率日報（MI_QFIIS）、TPEx 有對應 OpenAPI，改成批次抓取即可把覆蓋率從 147 拉到全市場，跟法人/融資/TDCC 同一個模式。

**工作量**：large

### 10. 外資持股只覆蓋 55/897 檔候選股，且覆蓋名單是「自選∪熱門 + 上櫃前 20」的固定集合——+18 分變成「有沒有付錢查它」的函數，跨股票分數不可比

**狀態**：📋 已記錄未修 — 同上

**證據**：update_service.dart:578-586 只把 watchlist ∪ popularStocks 送進 syncSymbolsMarketData；lib/domain/services/update/market_data_updater.dart:345-349 `int maxSyncCount = 20` 是寫死在方法簽章的魔術數字（未進 ApiConfig，違反 CLAUDE.md「配置集中」）；TWSE 市場候選股完全沒有任何 shareholding 同步路徑（全 repo 只有 market_data_updater.dart:315 與 :433 兩個呼叫點）。DB 實證：7/24 有持股資料者共 55 檔＝35 檔 TWSE（恰為 watchlist∪popular 的 TWSE 成員）＋20 檔 TPEx；當日被評分的 142 檔中只有 20 檔有 7/24 持股，而 FOREIGN_SHAREHOLDING_INCREASING 觸發了 16 檔（有資料者的 80%）。

**對分析判斷的影響**：這條規則在「有資料」的股票上觸發率高達 80%、每次 +18 分（short max 僅 80 分，佔 22%）。等於自選股與熱門股在排名上有結構性加分，而日誌中「分數不足 320 檔」被砍掉的股票裡，有一部分只是從來沒被查過外資持股。我用這張榜單做相對強弱比較時，比的是「資料完整度」而不是「籌碼強度」。

**建議**：優先查證 TWSE OpenAPI 的全市場外資及陸資持股統計端點（MI_QFIIS 系列，免費、單次取全市場），若可用即取代逐檔 FinMind，覆蓋率問題直接消失；在那之前，把 FOREIGN_* 規則降級為 explanatory-only（顯示但不計分），或只在「資料齊備子集」內做相對排名。maxSyncCount=20 至少要移進 ApiConfig 並附上決策依據。

**工作量**：medium

### 11. 外資持股是唯一稀缺配額（FinMind）的最大 per-symbol 消費者，但評分端對它沒有新鮮度界限——資料停在 3 天前的股票照樣拿 +18 分

**狀態**：✅ 已修 — 同上雙 cutoff 閘門，設在 builder 一處攔截全部消費端

**證據**：lib/domain/services/update/batch_data_loader.dart:108-110 `getLatestShareholdingsBatch(candidates)` 不帶日期上界；lib/domain/services/update/batch_data_builder.dart:22-33 直接以「最新一列」當 current；lib/domain/services/rules/extended_market_rules.dart:29-36 觸發 +18（lib/core/constants/rule_scores.dart:166）。實證（app DB `~/Library/Containers/com.neo.afterclose/.../afterclose.sqlite`）：3479 的 shareholding 最後一列是 2026-07-21（ratio 7.63，共 7 列），但 daily_reason 在 2026-07-24 仍記錄 3479 的 FOREIGN_SHAREHOLDING_INCREASING；同批 16 檔中 3479(7/21)、3693(7/22)、6259(7/22)、1326/2337/3163(7/23) 六檔的持股資料都不是 7/24。

**對分析判斷的影響**：7/24 的榜單上，我看到「3479 外資持股比例增加」並把它當成當日籌碼轉強的理由進場，實際那是 7/17→7/21 的變化，7/22-7/24 三天外資做了什麼完全沒有資料。因為 lookback 只有 5 天（rule_params_institutional.dart:110），一檔掉出配額覆蓋的股票會連續數日重複放送同一筆過期訊號，直到 prev 追上 current 才自動消失——這是「訊號看起來每天都在」但其實已經死掉的最壞情況。

**建議**：在 BatchDataLoader 對 shareholding 加日期上界與最大陳舊天數（例如 current 必須 ≥ date-2），超出即視為無資料（回 null），讓規則不觸發而不是用舊值觸發；同時在個股詳情顯示該欄位的資料日期。

**工作量**：small

### 12. 步驟 4.7 的 150 檔財報預算在 ETF 過濾之前就切完，marketCandidates 分到的 111 個名額 100% 被 ETF 吃光 → 897 檔候選中只有 39 檔有 EPS/ROE

**狀態**：✅ 已修（2026-07-27 `22bdfd0`）— **但原始說法有一半是錯的**

機制成立：ETF 過濾晚於 take，111 個名額被 ETF 吃光且不遞補。已把過濾提到
`UpdateService.selectFinancialSyncTargets` 內（取前 N 之前），並抽成
`@visibleForTesting` 純函數加守門測試。

**「897 檔候選中只有 39 檔有 EPS/ROE」不成立**：DB 實查有 EPS 的是 **386 檔**
（TWSE 372 / TPEx 14），故 severity 由 high 降為 medium。真正的結構性缺口是
上櫃恆為 0 名額，見 #5 與 `afterclose_otc_financial_backfill`（另案已修）。

**證據**：lib/domain/services/update_service.dart:692-701（prioritySymbols = watchlist∪popular；remainingSlots = ApiConfig.financialSyncMaxCandidates(150) − prioritySymbols.length；再從 ctx.marketCandidates.take(remainingSlots)）→ ETF 過濾卻在下游 lib/domain/services/update/fundamental_syncer.dart:305-315 與 407-418。候選來源順序無 ORDER BY：lib/data/repositories/price_candidate_filter.dart:60 呼叫 lib/data/database/dao/price_dao.dart:92-94 `(select(dailyPrice)..where(date))`，回傳順序未定義（實務上為 symbol 索引序，'00xxx' ETF 排最前）。日誌算術可證：`[UpdateService] 步驟 4.7: 損益=0, 資負=已快取 (150 檔)` + `[FundamentalSyncer] 財報同步: 跳過 111 檔 ETF，實際同步 39 檔`，150−111=39，恰等於 `[UpdateService] 步驟 4.5: ... 持股=39`（watchlist∪popular 的規模）→ marketCandidates 貢獻的 111 個名額沒有一檔是可查財報的個股。

**對分析判斷的影響**：lib/domain/services/rules/fundamental_scan_rules.dart:374/440/504/559（epsHistory）與 630/666/726（roeHistory）共 7 條規則，對 897 檔候選中的 858 檔永遠拿不到資料、恆不觸發。後果是「長線分數」被系統性低估在自選清單以外的所有股票上：一檔基本面真的轉強的非自選股，永遠只能靠技術/籌碼規則得分，不可能在強勢/長線榜上贏過我已經在看的 39 檔。等於這個榜單在結構上只會把我已知的標的還給我，喪失掃描的意義；而我看到的低分會被誤讀為「這檔基本面不行」，實際上是「這檔根本沒被查過」。

**建議**：把 ETF 過濾提到 `_syncBalanceSheetAndEps` 組 targetSymbols 之前（`ctx.marketCandidates.where((s) => !StockPatterns.isEtfCode(s)).take(remainingSlots)`），並讓 `quickFilterCandidatesFromDb` 依成交值排序輸出（目前依賴未定義的 DB row order 選誰有財報，本身就不該接受）。若要更根本，把 4.7 移到步驟 6 之後、直接用 CandidateSelector 已排序的 candidates。

**工作量**：small

### 13. 注意股（ATTENTION）警示永不失效：140 檔被標記，實際名單只有 19 檔——121 檔背著幽靈 -15 分與假風險徽章

**狀態**：✅ 已修 — `updateExpiredWarnings` 補上 DISPOSAL 且 endDate 為 NULL 的過期路徑（`nullEndDateCutoff`），並新增 `deactivateStaleAttentionWarnings` 做 per-market 全量刷新。實證：140 檔標記 vs 當日實際 19 檔

**證據**：lib/data/database/dao/trading_warning_dao.dart:91-97 `updateExpiredWarnings` 只用 `disposal_end_date < now` 判定失效；lib/data/repositories/warning_repository.dart:259-273 `_createWarningEntry` 只在 `warningType == 'DISPOSAL'` 時算 isActive，ATTENTION 一律 isActive=true。實測 DB（~/Library/Containers/com.neo.afterclose/.../afterclose.sqlite）：`select count(*) from trading_warning where warning_type='ATTENTION' and is_active=1 and disposal_end_date is null` = 437 筆（NULL 使 `<` 判定恆為 NULL，永遠不會被 update 到）；distinct symbol = 140，但 2026-07-25 當日名單只有 19 檔。對照 DISPOSAL：163 筆 active 全部仍在處置期內（機制正常）。7/24 的 daily_reason 中 TRADING_WARNING_ATTENTION 觸發 9 筆，其中 6669 最後一次真正列注意是 7/17、3685 是 7/18（已過 6-7 天）。

**對分析判斷的影響**：注意股是「當日」監管旗標，隔天就可能解除。現在只要被列過一次就永久扣 -15 分並掛橘色風險徽章（RiskWarnings.moderate）。兩個實際後果：(1) 一檔剛好在 12 分邊緣的起漲訊號被 -15 打到門檻以下 → 直接從三個 mode tab 消失，我永遠看不到它；(2) 我點進個股看到「被列入注意股票」徽章，會誤以為現在還有監管盯著而放棄進場，實際上該旗標一週前就解除了。DB 只累積 11 天就已經有 121 檔假旗標，跑三個月後幾乎每檔活躍股都會中獎，風險徽章徹底失去鑑別力。

**建議**：ATTENTION 需要自己的失效規則（TWSE/TPEx 注意股是逐日名單，非期間制）：每次同步成功後，把「本次名單以外、warningType='ATTENTION' 且 date < 本次同步日」的列一律 isActive=false（等同 full-refresh 語意）。同時修 `updateExpiredWarnings` 的 NULL 盲點（`disposal_end_date IS NULL AND warning_type='ATTENTION'` 也要納入條件），並把它移出 `entries.isNotEmpty` 分支——目前 0 筆同步時連 DISPOSAL 過期都不會被清。另建議在 warningMap 裡帶上 flag 日期，讓規則能顯示「7/17 列入注意」而非無時間資訊的斷言。

**工作量**：small

### 14. 注意股（ATTENTION）警示永不失效：一旦上過名單就永久背 -15 分

**狀態**：✅ 已修 — `updateExpiredWarnings` 補上 DISPOSAL 且 endDate 為 NULL 的過期路徑（`nullEndDateCutoff`），並新增 `deactivateStaleAttentionWarnings` 做 per-market 全量刷新。實證：140 檔標記 vs 當日實際 19 檔

**證據**：lib/data/database/dao/trading_warning_dao.dart:91-97 `updateExpiredWarnings` 的 where 條件是 `t.disposalEndDate.isSmallerThanValue(now)`；lib/data/repositories/warning_repository.dart:272-280 `_createWarningEntry` 只在 `warningType == 'DISPOSAL'` 時才算 isActive，ATTENTION 一律 isActive=true 且 disposalEndDate=null → SQL 中 `disposal_end_date < ?` 對 NULL 恆為 NULL、永遠不會被 update 到。lib/data/database/dao/trading_warning_dao.dart:44-67 `getActiveWarningsMapBatch` 只過濾 `isActive=true`，完全沒有日期條件。表 PK 為 {symbol, date, warningType}（lib/data/database/tables/market_data_tables.dart:298），每日同步寫新列，舊列永久留存。全 repo grep 不到任何 trading_warning 的 delete / retention 清理。消費端：lib/domain/services/rules/warning_rules.dart:24 → RuleScores.tradingWarningAttention = -15（lib/core/constants/rule_scores.dart:277）；lib/presentation/providers/mode_recommendation_provider.dart:386-391 的註解明寫「只需信任 isActive=true 即代表目前仍生效」——這個假設對 ATTENTION 不成立。日誌佐證：本次寫入 22 筆上櫃注意，每天都是新的一批。

**對分析判斷的影響**：注意股在台股是逐日名單（多半掛 1~3 天就下架）。目前設計下，任何股票只要在 App 使用期間曾被列過一次注意，之後每天評分都被扣 15 分，永遠不會恢復。實際後果：(a) 一檔在 5 月因短期波動上過注意、6 月起跌回整理、7 月剛起漲的股票，評分被壓低 15 分，很可能卡在「分數不足 320」那一群裡不出現在起漲榜——我看不到它，而且完全沒有任何提示告訴我它是被一條三個月前的過期監管旗標擋掉的；(b) 個股詳情與自選頁會一直掛「被列入注意股票」的風險標記，讓我對一檔實際上早已正常的股票持續低配部位；(c) 大盤總覽的「生效注意股家數」(market_overview_dao.dart:349-357) 會單調累積，市場實際通常 <50 檔，跑幾個月後會膨脹到數百檔，等於這個市場情緒指標整個失真。可自我驗證：打開大盤總覽看注意股家數，若遠大於當日 TWSE/TPEx 公告家數即已中獎。

**建議**：ATTENTION 的「目前生效」必須以日期界定而非 isActive 旗標。最小修法：(1) `getActiveWarningsMapBatch` / `getAllActiveWarnings` / `getActiveWarningsByType` / `getDisposalStocksBatch` 全部加上 `date >= ?` 參數（門檻建議取最近一個交易日，或 ATTENTION 用 N 個交易日窗），寫法可直接抄 chip_anomaly_service.dart:333-336 已經在用的 `WHERE warning_type='DISPOSAL' AND date >= ?`——同一個表兩種讀法、防護不對稱正是這個 bug 的溫床；(2) `updateExpiredWarnings` 補一條 ATTENTION 分支：本輪同步日不在名單中的 ATTENTION 列一律 isActive=false（或改成同步時先把當日以前的 ATTENTION 全部 deactivate 再寫入）；(3) 加一次性 migration 把既有的舊 ATTENTION 列 isActive 清掉，否則修了讀取端仍要等自然衰減；(4) 補守門測試：寫入 D-30 的 ATTENTION 後，D 日 `getActiveWarningsMapBatch` 必須回空。

**工作量**：medium

### 15. 注意股（ATTENTION）警示永遠不會失效，-15 分永久黏在股票上——實測 140 檔背著警示，但當日實際只有 19 檔

**狀態**：✅ 已修 — 同上（三個 agent 對同一問題的重複回報）

**證據**：lib/data/database/dao/trading_warning_dao.dart:91-97 `updateExpiredWarnings` 的 WHERE 只有 `isActive=true AND disposal_end_date < now`；ATTENTION 列的 disposal_end_date 恆為 NULL（lib/data/repositories/warning_repository.dart:165-175 建 TWSE 注意股、196-207 建 TPEx 注意股時皆未傳 disposalEndDate），SQL 中 `NULL < x` 求值為 NULL → 該列永遠不被更新。讀取端 trading_warning_dao.dart:44-67 `getActiveWarningsMapBatch` 只信 `is_active=1`、無任何日期下限，直接餵給 lib/domain/services/update/batch_data_loader.dart:123-126 與 202-214。扣分值 lib/core/constants/rule_scores.dart:277 `tradingWarningAttention = -15`。DB 實證：`SELECT warning_type,is_active,COUNT(*) FROM trading_warning GROUP BY 1,2` → ATTENTION/1/437 列、140 檔 distinct；但 `SELECT DATE(date),COUNT(DISTINCT symbol) ... WHERE warning_type='ATTENTION'` 顯示最新交易日只有 19 檔（7/14~7/24 每日 19~71 檔）。對照 DISPOSAL 有 92 列已正確 is_active=0，證明失效機制只對處置股生效。

**對分析判斷的影響**：140 檔中有 121 檔（86%）帶著早已出關的注意股標記，被扣 -15 分並在卡片掛風險徽章。今天有 320 檔因「分數不足」被跳過，-15 足以把成立訊號壓到 minScoreThreshold 以下。實際情境：一檔股票 7/14 因單日振幅被列注意（隔天即出關），7/24 出現法人連買 + 突破訊號，但因為那條 10 天前的注意記錄仍 active，分數被扣掉 15 分而掉出推薦榜；或它有進榜，我在卡片上看到「注意股」風險徽章而不敢買。更糟的是這個池子只會單調成長——DB 只累積 10 天就已 7 倍膨脹，跑三個月後幾乎全市場都會被標成注意股，這個風險訊號會完全失去鑑別力。

**建議**：注意股是「逐日公告」而非「期間性」，不該用 disposal_end_date 判存續。兩種修法擇一：(a) `updateExpiredWarnings` 補一條 `OR (warning_type='ATTENTION' AND date < <本次同步日>)`；(b) `getActiveWarningsMapBatch` 加 `date >= (SELECT MAX(date) FROM trading_warning WHERE warning_type=t.warning_type)`，只認最新一期名單。同時補一個守門測試：連續寫入兩天的 ATTENTION 後，第一天那批必須 is_active=0。

**工作量**：small

### 16. 當沖／融資同步失敗在 MarketDataUpdater 內被吞掉，「當沖=0」與「API 掛了」無法分辨，投機股的 -5 風險扣分靜默消失

**狀態**：❓ 未查證

**證據**：lib/domain/services/update/market_data_updater.dart:55-66 與 68-77（兩個 generic catch 只 AppLogger.warning，count 留 0）；MarketDataSyncResult（546-564）根本沒有 error 欄位可回傳；lib/domain/services/update_service.dart:594-598 只把 0 印進 log；扣分定義見 lib/core/constants/rule_scores.dart:203 `dayTradingExtreme = -5`，規則在 lib/domain/services/rules/extended_market_rules.dart:135-136（ratio == null 直接 return null）

**對分析判斷的影響**：當沖資料缺席時 dayTradingMap 沒有該股，DayTradingExtremeRule 直接 return null，-5 的投機過熱扣分憑空消失。一檔當沖比例爆表的股票因此多 5 分，足以從 8-11 分的「觀察區」跨過 12 分的成立訊號門檻（scoring_pipeline.dart:92-94 + mode_recommendation_provider.dart:441 isSignalTier），被路由進三模式 tab。使用者看到的是「訊號成立」，而不是「這檔今天是當沖客的提款機」——正好是最容易套在高點的那類股票。

**建議**：MarketDataSyncResult 增加 dayTradingError / marginError 並由 coordinator 轉發；另加一條合理性檢查：該日已有全市場價格但當沖筆數為 0 時直接記一條警告（今天的健康值是 1129 筆，0 筆必然是異常而非「今天沒人當沖」）。

**工作量**：small

## severity: medium

### 17. release build 完全沒有日誌，且所有靜默降級只留 breadcrumb 不產生 Sentry 事件

**狀態**：❓ 未查證

**證據**：lib/core/utils/logger.dart:116-122（assert 判斷 debug，release 直接 return，連 print 都不執行）；logger.dart:74-88 warning 只呼叫 _sentryBreadcrumb，只有 error 才 _sentryCapture（93-104）。整條 update pipeline 的降級路徑清一色用 warning：price_repository.dart:355、market_data_updater.dart:65,76,520,533、warning_repository.dart:110,120,135,145、institutional_syncer.dart:61,99、market_index_syncer.dart:112,135,159、update_service.dart:749

**對分析判斷的影響**：上述第 1、2、3、4、8 項的所有降級，在正式版 App 裡既沒有 log 可事後追、也不會產生任何 Sentry 事件（breadcrumb 只有在同一 session 稍後另有一個 captureException 時才會被一併上傳，而這些路徑正好都不 capture）。當真的發生「拿昨天資料下單」時，事後完全沒有可回溯的證據能證明是哪一天、哪個來源掛的，只能靠重現。

**建議**：為「整市場來源 0 筆 / 全數 parse 失敗 / killer features 失敗 / 當日價格缺市場」這幾類 invariant 破壞開一條 AppLogger.degradation 通道，固定送 Sentry message（不需 exception），與一般 warning 分流；至少讓這幾類升為 AppLogger.error。

**工作量**：small

### 18. rule_accuracy 的樣本是逐日重複觸發的序列相關樣本（pseudo-replication），n 被灌水 2-4 倍，而 n≥30 正是 calibration 的砍規則門檻

**狀態**：✅ 已修 `f8de299` — 新增 `distinctDates`，信心度判準改看觸發日數

**證據**：lib/domain/services/rule_accuracy_service.dart:283-339 逐筆 reason 累加，每個 (symbol, date, rule) 都算一筆獨立樣本；holdingPeriods 含 5D（:50），相鄰兩日的同股同規則樣本共享 4/5 的 forward window。實測 DB（daily_reason 僅 7/14~7/23 共 8 個交易日）每規則的「筆數/相異股票數」重複倍率：HIGH_DIVIDEND_YIELD 200/45 = **4.44**、PBR_UNDERVALUED 150/35 = **4.29**、CONCENTRATION_HIGH 761/226 = 3.37、INSTITUTIONAL_BUY_STREAK 286/108 = 2.65。rule_accuracy 表 5D 期別因此出現 CONCENTRATION_HIGH n=276、REVENUE_YOY_SURGE n=107 這種數字，但背後只有 226 / 137 檔股票、8 天。class docstring（:26-32）只承認跨規則的 co-occurrence inflation，完全沒提跨日的序列相關。cut 門檻見 lib/core/constants/calibration_thresholds.dart:113（sampleSizeCutThreshold=30）與 :109（tStatCutThreshold=1.5）。

**對分析判斷的影響**：這決定了哪些規則會被 calibration 判為 active、進而決定我看到的分數怎麼加總。慢變數規則（高股息、PBR 低估、籌碼集中——它們的觸發條件好幾週都不會變）每天重複計一次，n 輕鬆衝過 30、t-stat 被 √n 放大，於是一條沒有真實 edge 的規則被留下來並持續加分；反之快變數規則（形態、突破，重複倍率只有 1.08-1.16）樣本天生少、被砍掉。最後的評分系統會系統性偏向「靜態屬性」而非「時機訊號」，而我買的是時機。

**建議**：聚合時以「事件」為單位而非「(symbol,date) 列」：同一 (symbol, rule) 在 holding period 內的連續觸發只計第一筆（entry-based de-dup），或改算 cluster-robust standard error（同 symbol 的樣本視為一個 cluster）——tool/ 下已有 clustered t-stat 的相關工作（calibration_thresholds.dart 的「超額模式（clustered 決策層）」段落），把同一套 clustering 套進 runtime 的 rule_accuracy 即可。至少要把「相異 (symbol, cluster) 數」一併寫進 rule_accuracy 表與 bias_telemetry，讓 n 的真假可被看見。

**工作量**：medium

### 19. trading_warning「每日一列」的儲存模型與「取一列代表當前狀態」的讀取方式不匹配，處置延長時會顯示錯誤出關日並產生重複行事曆事件

**狀態**：❓ 未查證

**證據**：lib/data/database/dao/trading_warning_dao.dart:49-66 `getActiveWarningsMapBatch` 只用 `OrderingTerm.desc(t.warningType)` 排序（讓 DISPOSAL 勝過 ATTENTION），同一 symbol 有多筆 active DISPOSAL 時沒有任何日期排序，靠 `if (!map.containsKey(...))` 保留第一筆——實際取到哪一筆由 SQLite 掃描順序決定（通常是較舊的列）。因為 PK 含 date（market_data_tables.dart:298），一檔處置 10 天的股票會累積 10 筆 active 列。lib/data/repositories/event_repository.dart:198-212 `syncDisposalEndEvents` 對每一筆 active DISPOSAL 都 insert 一個 DISPOSAL_END 事件，且 stock_event 的 PK 是 autoincrement id（event_tables.drift.dart:466）、`insertStockEvent`（event_dao.dart:41-43）是純 insert 無去重。消費端 lib/domain/services/rules/warning_rules.dart:60-64 直接把 `disposalEndDate` 印進描述文字。

**對分析判斷的影響**：台股處置常見「二次處置／延長處置」——原本 7/31 出關，7/25 又公告延長到 8/12。此時 DB 同時有 end=7/31（舊列）與 end=8/12（新列）兩筆 active，而 getActiveWarningsMapBatch 很可能回舊的那筆：個股頁與規則描述會寫「處置期限至 7/31」，事件行事曆同時出現 7/31 和 8/12 兩個「處置結束」。我照 7/31 這個日期規劃 8/1 進場，結果那天股票還在分盤撮合，掛出去的單成交價和我預期差一大截。另外處置期間每多跑一天更新，行事曆就多一筆重複的「處置結束」事件（同一天 N 筆），把真正該注意的事件淹掉——這正是我用行事曆的目的相反。

**建議**：(1) `getActiveWarningsMapBatch` 的 orderBy 補上 `OrderingTerm.desc(t.date)` 作次要鍵，確保取到最新公告的那一筆（同時解掉 warningType 排序依賴字串字典序這個隱性假設）；(2) `syncDisposalEndEvents` 先依 symbol 收斂成「最新 date 的那筆」再產事件，或在插入前對 (symbol, eventType, eventDate) 去重；(3) 更根本的做法是替 trading_warning 加上「當前狀態」視圖語意——每次同步後把該 symbol 早於本輪同步日的同型別列 isActive 設為 false，讓 active 集合恆等於最近一次公告的快照，這樣同時把上面注意股永不失效那條一併治掉。

**工作量**：medium

### 20. 「API 回傳空資料」與「schema 變更導致全數 parse 失敗」在日誌上完全相同，內部人轉讓與 TDCC 皆然

**狀態**：❓ 未查證

**證據**：lib/data/remote/tpex_client.dart:1053-1057（data is! List → warning + return []）與 1059-1064（tryFromJson 回 null 的項目靜默 continue，沒有 parsed/total 對帳）；lib/domain/services/update/insider_transfer_syncer.dart:32-35（空即 return 0、只記 debug）；lib/domain/services/update_service.dart:424-426（transferCount == 0 時連 info log 都不印）；同 pattern 見 lib/domain/services/update/tdcc_holding_syncer.dart:47

**對分析判斷的影響**：今天日誌的「TPEX 內部人轉讓: 0 筆 → API 回傳空資料」在 TPEx 改一個欄位名之後會輸出一字不差的同一行。內部人轉讓是「大股東準備出貨」的先行訊號，一旦因欄位改名長期歸零，沒有任何機制會發現——這類訊號本來就常常是 0 筆，「一直 0」不會引起懷疑，可能靜默失效好幾個月。

**建議**：client 層在「HTTP 200 但 parsed=0 而 raw list 非空」時升為 error 級並帶上 parsed/total；syncer 層對全市場端點加「連續 K 個交易日回 0 筆」的偵測，命中就記一條 error 進 UpdateResult，讓合法的零與失效的零分家。

**工作量**：medium

### 21. 「連續 3 個月無資料＝上市前」的啟發式一旦誤判，會被 firstKnownDate 固化成永久截斷，且下游只會靜默不觸發、不會提示

**狀態**：❓ 未查證

**證據**：lib/data/repositories/twse_price_source.dart:19,48-56（連續 3 個空月即 break，跳過更早月份）；price_repository.dart:121-125 `firstKnownDate = existingHistory.length >= 60 ? existingHistory.first.date : null`，:142-152 之後永久跳過早於它的月份；historical_price_syncer.dart:347,360-378 `_hasEnoughDataForAge` 又用同一個 firstDate 當上市日推算「應有交易日數」→ 判定資料已足、不再補。break 的判定只看「API 回空」，沒有跟 TaiwanCalendar 對照該月是否確實有交易日。

**對分析判斷的影響**：長期停牌後復牌、或 TWSE STOCK_DAY 對轉板／創新板個股缺月的股票，會被永久釘在 250 根以下。52 週高低與年線類規則對它不是給錯訊號，而是**永遠不觸發**——我在掃描結果裡看不到它創新高，會以為它沒創新高，實際是資料被截斷了，而 UI 沒有任何「歷史不足」標記。

**建議**：break 前先用 TaiwanCalendar 確認該月確有交易日（有交易日卻回空＝可疑，應重試而非判定上市前）；firstKnownDate 改以 stock_master 的實際上市日為準，或在資料筆數明顯低於上市天數時不信任它；至少對 <250 根的股票在個股頁標記「歷史不足，52 週規則未評估」。

**工作量**：medium

### 22. 「部分更新成功」只活在一次性 snackbar：update_run.status=partial 有寫入但 UI 從不讀取，errors 明細完全不持久化

**狀態**：✅ 已修（2026-08-23 查證，非本輪修復）

**查證結果**：本條寫下後已被實作補齊，兩個缺口都補了。
- 明細持久化：`UpdateService._partialRunMessage` 把失敗步驟連同例外訊息組成
  `message`（截斷 500 字）寫入 `update_run`；DB 實測 PARTIAL 列的 message 形如
  「部分更新成功(3 項失敗): 籌碼資料更新失敗: AppException: TWSE receive timeout…」。
- UI 出口：`today_screen.dart` 讀最新一列的 `status`，PARTIAL 顯示
  `Icons.error_outline` + warning 色徽章（SUCCESS 刻意不顯示以減 noise），
  徽章可點開 `UpdateHistorySheet`，逐列顯示 status icon 與完整 message
  （長訊息走 ExpansionTile 展開）。

**原始記錄（保留以備回溯）**：

**證據**：lib/domain/services/update_service.dart:841-848 寫入 partial/success 與 message，errors 內容未持久化；lib/data/database/dao/user_dao.dart:196 getLatestUpdateRun；lib/presentation/providers/today_provider.dart:117-136 只取 finishedAt/startedAt，status 與 message 完全沒被讀；背景路徑 lib/app/headless_update_runner.dart:104 拿到 UpdateResult 直接回傳，errors 沒有任何出口

**對分析判斷的影響**：snackbar 關掉之後，一次「5 項資料缺漏的 partial 更新」與一次完美更新在 App 裡長得一模一樣。背景路徑（WorkManager / launchd CLI）更徹底——那條路上根本沒有 snackbar，警告從產生到消失都沒被任何人看過。使用者盤前打開 App 看今日榜單時，無從得知這批分數是在法人缺席、警示缺席、當沖缺席的情況下算出來的，只能假設一切正常。

**建議**：update_run 增一個 errorsJson 欄位持久化 result.errors；今日頁在最近一次 run 為 partial 時常駐一條可點開的「本次更新有 N 項資料缺漏」橫幅，直到下一次乾淨的更新才消失——把警告從「一次性事件」改成「狀態」。

**工作量**：medium

### 23. 三個步驟 10+ 跑在 _finishUpdate 之後，失敗無法反映到 update_run 狀態或 result.errors——出場層（釘選論點失效檢查）整個沒跑也顯示「更新完成」

**狀態**：✅ 已修 — 查證屬實。`_finishUpdate` 依 `result.errors` 決定
`update_run` 狀態並設 `result.success = true`，而三個 fail-safe 跑在它之後
且只 `AppLogger`，故失敗永遠反映不到狀態上。

修法：三個 fail-safe 移到 `_finishUpdate` **之前**，並在 catch 內
`recordError`（仍不 rethrow，維持「不中斷流程」語意）。既有測試釘住的
`result.success == true` 契約不變，只是 `update_run` 會正確標為 PARTIAL。

此修法安全的前提是同批已修的冷啟動 gate（`ccc630d`）：在那之前 PARTIAL
會把自動更新擋滿 6 小時，讓 PARTIAL 更準確反而有害。

測試 +2，順序與記錄兩個面向各經 mutation 驗證。

**證據**：lib/domain/services/update_service.dart:287 先 `await _finishUpdate(ctx, result)`，該方法內 844-848 已寫 `finishUpdateRun(success)` 並在 850-851 設 `result.success = true; result.message = '更新完成'`；之後 295-297 才跑三個 FailSafe。`_checkPinnedThesesFailSafe`（892-902）catch 所有例外後只 `AppLogger.error`，不碰 result.errors、不改 update_run。`_updateRuleAccuracyStatsFailSafe`（862-872）、`_snapshotNewsMentionsFailSafe`（876-888）同型。

**對分析判斷的影響**：ThesisMonitorService 是出場層（timeStop 檢查釘選論點是否失效）。它整個 throw 掉時，我在 app 上看到的是「更新完成、0 項警告」，釘選部位沒有任何失效提示——而我會把「沒提示」讀成「論點還成立」繼續抱著。這正好是出場決策最貴的誤讀方向：漏一次出場訊號的成本遠大於漏一次進場訊號。同理 rule_accuracy 更新失敗時，個股詳情的命中率會是上一輪的舊值，但沒有任何地方標示它 stale。

**建議**：把三個 post-step 的失敗寫回 `ctx.result.errors`（至少 thesis monitor 必須），並把 `finishUpdateRun` 移到三個 post-step 之後；或保留現在的 early-finish 但在 post-step 失敗時補一次 `finishUpdateRun(partial, message)`。UI 端「釘選論點檢查未執行」需要與「論點仍成立」明確區分。

**工作量**：small

### 24. 上櫃 1311 檔完全沒有當沖資料（不是今天沒抓到，是沒有資料源），程式碼內兩處註解自相矛盾、日誌與 UI 都看不出差別

**狀態**：✅ 已修（2026-08-23）

**修復**：接上兩條路徑——每日走櫃買 `/www/zh-tw/intraday/stat`（免費、842 檔、
1 次呼叫），歷史走 FinMind `TaiwanStockDayTrading`（一次性 CLI
`tool/backfill_tpex_day_trading.dart`）。app DB 已回補 2025-06-10 起 59,098 列
／295 個交易日／748 檔，抽驗與官方逐位元相符。

本條建議的「TPEx 有上櫃股票個股當日沖銷交易統計日報（非被 Cloudflare 擋的那個
端點）」是對的——舊站路徑已 302，新站 `/www/zh-tw/intraday/stat` 以 app 實際
User-Agent 測試回 200。

⚠️ 尚未做：`tool/calibration.db` 未回補上櫃當沖（僅 9,714 列，來自上櫃轉上市
個股），故校準結果目前仍以上市樣本為主。

**原始記錄（保留以備回溯）**：

**證據**：lib/domain/services/update/market_data_updater.dart:54 註解「無 TPEX 對等：上櫃端點被 Cloudflare 擋」，但同檔 483-485 回傳處註解寫「當沖資料已由批次 TPEX API 同步，此處回傳 0」——兩處對同一事實的描述相反，日誌只會印「步驟 6.5: 上櫃 (20/269 檔): ... 當沖=0」，讀起來像「今天上櫃沒有高當沖股」而不是「這個資料源不存在」。DB 實證：`SELECT m.market,COUNT(*) FROM day_trading d JOIN stock_master m ... WHERE d.date=MAX(date)` → TWSE 1129 列、TPEx 0 列。今日 daily_reason：DAY_TRADING_HIGH 命中 TWSE 11 檔、TPEx 0 檔。UI 端 lib/presentation/screens/stock_detail/widgets/day_trading_section.dart:23-34 在 history 為空時顯示通用的 'chip.noData'。另外 trading_repository.dart:131-140：上市股若當天沒有價格列，分母為 0 時 ratio 直接寫 0（非 NULL）——DB 實測最新日有 33 列 ratio=0，另有 96 檔 TWSE 有價格但完全沒有當沖列。

**對分析判斷的影響**：我是當沖交易者，當沖比例是我最核心的籌碼指標之一。上櫃股（佔宇宙 49%）在個股頁永遠顯示「無資料」，也永遠拿不到 dayTradingExtreme(-5) 與風險徽章。實際情境：一檔上櫃投機股當沖率 80%、隔日沖籌碼把價格拱上去，在我的掃描結果裡它看起來乾乾淨淨、沒有任何投機警示，我照著「回檔進場」訊號買進，隔天被隔日沖倒貨吃掉。而同樣情況的上市股會被標紅。「無資料」文案讓我把它讀成「當沖不高」，這是最糟的一種缺失——沉默且會被誤讀為好消息。

**建議**：最低成本先治誤讀：UI 與日誌把「此市場無資料源」和「今日無資料」用不同文案（例如上櫃股顯示「上櫃市場未提供當沖統計」），並把 market_data_updater.dart:483-485 那條矛盾註解改正。治本：TPEx 有「上櫃股票個股當日沖銷交易統計」日報（非被 Cloudflare 擋的那個端點），可比照 TWSE 走批次；若確認取不到，就把 dayTradingRatio 的缺失明確標成 market-level 已知盲區寫進 docs/RULE_ENGINE.md。另外 trading_repository.dart:139 的 `ratio = 0` fallback 應改寫 NULL——0 是「當沖佔比為零」的真值，不該拿來表示「算不出來」。

**工作量**：medium

### 25. 上櫃估值/營收只覆蓋 249 檔且無一筆是最新日期，價值面規則實質是上市專屬；take(N) 取候選前綴且從不輪替，尾端上櫃股是「永遠輪不到」而非「今天沒輪到」

**狀態**：📋 已記錄未修 — FinMind 配額綁定（`maxSyncCount = 20`）

**證據**：lib/domain/services/update/fundamental_syncer.dart:164-167 `otcCandidates.take(maxSyncCount)`（ApiConfig.otcFundamentalsSyncMaxCount=100）、lib/domain/services/update/market_data_updater.dart:374-376 同款 `take(20)`，兩處都是取排序後的固定前綴，沒有任何「上次同步時間最舊者優先」的輪替機制。候選順序來自 lib/domain/services/update/candidate_selector.dart:59-88，每日近乎穩定 → 同一批上櫃股每天被選中，尾端那批永遠不被選中。DB 實證：stock_valuation 中 TWSE 有 1080 檔且 latest 全部落在最新日；TPEx 只有 249 檔有任何資料，且 latest 日期散佈 7/14~7/22、沒有任何一檔是最新日（最舊 9 天）。monthly_revenue 同樣是 TWSE 1067 檔 vs TPEx 249 檔（皆 2026/06）。搭配 rule_params_fundamental.dart:55 的 7 天 stale gate，那 249 檔裡還有一部分連規則都進不去。今日 reason 分佈：PE_UNDERVALUED TWSE 8/TPEx 0、PBR_UNDERVALUED 15/0、EPS_CONSECUTIVE_GROWTH 8/0、HIGH_DIVIDEND_YIELD 20/2；最終 daily_analysis 142 檔為 TWSE 115 / TPEx 27（81:19），而宇宙比例是 51:49。

**對分析判斷的影響**：這正是「以為看到全市場最佳機會、其實是資料最完整那群的最佳機會」的實例。我打開掃描結果看到的是一份混合排名，但上櫃股在價值面（本益比、股價淨值比、殖利率、EPS 連續成長）上結構性拿不到分，只能靠純技術面訊號擠進榜。結果是：上櫃的低估值 / 高殖利率標的對我是完全隱形的，而我不會知道——因為畫面上沒有任何「這 1062 檔沒有基本面資料」的提示。已知事項 #2 說優先序設計本身合理，我同意；但這裡的問題不是誰先誰後，而是沒有輪替導致覆蓋是永久性分層，跑一年也不會收斂。

**建議**：把 `take(N)` 改成「N = 前 N−k 檔照現有優先序 + k 檔依 last_synced_at 最舊者優先」的混合配額（例如上櫃基本面 100 = 80 優先 + 20 輪替、外資持股 20 = 15 + 5）。以 269 檔上櫃候選計算，k=20 時約 14 個交易日即可讓全部至少更新過一輪，API 預算不變。另外在掃描頁對「基本面資料不可得」的股票加一個小標記，讓跨市場比較的失真是可見的。

**工作量**：medium

### 26. 下市/長停股整檔剔除 = 用訊號當下不可知的未來資訊做樣本選擇，把最壞的尾部（下市 -100%）從統計中系統性抹掉

**狀態**：📋 已記錄未修 — 偏誤屬實，但**建議的修法不可行**，且現況影響為零。

- 「用最後有效收盤價當出場價」不可行：下市前多為連續跌停無量，該價格不是
  可成交價
- 「固定懲罰 -60%」是憑空數字——用假數字取代有偏誤的統計並不更誠實
- 現況 `daily_reason` 僅 8 天，而下市需數月，實際排除量為零

正確方向是**揭露而非修正**：把 `skippedStaleSymbol` 佔比呈現到規則命中率
UI（目前只寫 AppLogger）。待 `daily_reason` 累積至有意義深度後再做。
已把此限制與判定理由寫進 `rule_accuracy_service` 的 survivorship 註解。

**證據**：lib/domain/services/rule_accuracy_service.dart:208-227：用 `getLatestPricesBatch`（全域最新價，非 as-of 訊號日）與 `getLatestDataDate()` 判定 staleSymbols，:283-287 整檔 symbol 的所有 reason 全數 skip（計入 `skippedStaleSymbol`）。判定依據 CalibrationThresholds.stalePriceThresholdDays。docstring :256-264 明確說明這是為了避免「winner 全留、崩盤前夕靜默消失」——但整檔排除的實際效果是連崩盤/下市這個事件本身也一併排除。

**對分析判斷的影響**：訊號發生當下我不可能知道這檔三個月後會下市。統計把這些標的整批拿掉之後，我看到的「命中率 33%、平均報酬 +1.25%」是在一個「事後確認活到今天」的宇宙裡算出來的。對專打弱勢股的規則（WEEK_52_LOW、RSI_EXTREME_OVERSOLD、PBR_UNDERVALUED 這種價值陷阱高發區）傷害最大——它們真正的風險就是尾部歸零，而那正好是被剔掉的部分。我照著「平均報酬只有 -0.4%，看起來還好」去接一檔破底股，實際分布的左尾被裁掉了。

**建議**：改成保留下市/長停股，但用「最後一個有效收盤價」當終端出場價（下市即實現該筆報酬），而非整檔丟棄；真的無法定價（如全額交割後歸零）就以固定懲罰值（例如 -60%）入帳並在 telemetry 分開計數。同時把 `skippedStaleSymbol` 佔比顯示到規則命中率 UI 上（現在只寫 AppLogger），讓「這條規則有 X% 樣本因下市被排除」對使用者可見。

**工作量**：medium

### 27. 並行分支同時打同一台 TPEX 伺服器，抵銷 WarningRepository 內部刻意的序列化防護

**狀態**：❓ 未查證

**證據**：lib/domain/services/update_service.dart:256-261 把 4 組 syncer 用 `.wait` 並行。分支 A（_syncAuxiliaryData）內含 MarketIndexSyncer 的 TPEx 指數、DividendSyncer 的 TPEX 股利/股東會、InsiderTransferSyncer 的 TPEX 內部人轉讓；分支 C（_syncMarketAndFundamentalData）內含 FundamentalSyncer 的 TPEX 估值/營收、TradingRepository 的 TPEX 融資、WarningRepository 的 TPEX 注意/處置。lib/data/repositories/warning_repository.dart:89-90 自己寫著「TPEX 伺服器對併行請求敏感，序列化避免 Connection reset」並在 127-146 逐一 await——但這個序列化只在單一 repo 內生效。lib/data/remote/tpex_client.dart 全檔沒有任何 mutex/queue/Completer 序列化原語（grep 零命中）。

**對分析判斷的影響**：TPEX connection reset 會被 warning_repository.dart:137-146 的 per-source catch 吃成一行 warning，回傳空清單而不是拋錯（只有 4 個來源全掛才 throw，見 149-152）。結果是 warningMap 裡少掉上櫃處置股。處置股是人工撮合（每 5-20 分鐘一次）、且多半不能當沖——一檔上櫃處置股因此沒被標記、照樣出現在起漲榜，我照榜單掛單進場後才發現價格根本沒有連續成交，滑價與無法出場的風險全部落在我身上。本次日誌（TPEX 注意 22 / 處置 31）雖然沒中招，但這是機率性的，且失敗時的訊號是「靜默 0 筆」。

**建議**：在 TpexClient 內加 process 級序列化佇列（所有 request 串成一條 chain），或把所有 TPEX 呼叫收攏到同一個並行分支內序列執行。同時把 warning_repository 的 per-source 失敗轉發到 ctx.result.errors（目前只有 log），讓「上櫃處置抓不到」不再是靜默事件。

**工作量**：medium

### 28. 前景與背景更新沒有跨 isolate 互斥：_activeUpdate 是 instance 欄位，背景 isolate 另建一整套服務圖與獨立的 API 預算追蹤器

**狀態**：📋 已記錄未修 — 機制查證屬實，但**在主要使用平台不可達**。

- 背景 WorkManager 只在 Android / iOS 註冊
  （`background_update_service.dart` 的 `Platform.isAndroid || Platform.isIOS`），
  **macOS 不存在此路徑**
- iOS 上要碰撞需背景任務（15:00）與前景冷啟動同時發生，且冷啟動 gate 的
  兩個條件（距上次成功 ≥6h、距上次嘗試 ≥60min，見 `ccc630d`）皆通過
- 跨 isolate 互斥需引入檔案鎖或 DB lock 表，兩者都帶新的失效模式
  （isolate 被 OS 殺掉後鎖殘留），代價與風險不成比例

已把 `_activeUpdate` 的 docstring 由「防止並發更新」改為事實陳述（instance
級、跨 isolate 無效、平台限定），並註明重新評估的觸發條件。

**證據**：lib/domain/services/update_service.dart:161-194 的 `_activeUpdate` Completer 是 instance 欄位（docstring 178 行宣稱「防止並發更新」）。lib/app/headless_update_runner.dart:95-104 在 WorkManager isolate 內用 UpdateServiceFactory 另建一個 UpdateService，並注入自己的 AppDatabase（48、116 行 db.close()）與自己的 ApiBudgetTracker（77）；lib/data/remote/api_budget_tracker.dart:10、22-24 明文寫著 tracker 是 process-local、「背景跑 WorkManager 觸發新 isolate 也是新 tracker，等於 reset」。lib/app/background_update_service.dart:65-84 把背景任務排在每天 15:00（ApiConfig.marketCloseHour）——正是使用者盤後打開 app、觸發 cold-start auto-update（today_provider.dart:149-155 的 B-lite 開關）的時間窗。

**對分析判斷的影響**：兩個 run 各以為自己有 600 次 FinMind 額度、合計打 1200 次向真實的 600/hr 上限 → 429 → markRateLimited → 兩邊同時 rateLimitedAbort。搭配上面第 2 項（限流不擋評分），結果是兩個都寫出降級評分，後完成的覆蓋前一個。另外 ScoringService 的 clear-then-write transaction（scoring_service.dart:350-377）在兩個 run 之間交錯時，A 的 BatchDataLoader 可能正好讀到 B 尚未寫完的 6.5 上櫃資料，讓部分上櫃股以「缺基本面」的狀態被評分。整體症狀是：盤後開 app 的那天，榜單品質莫名比其他天差，而且無從診斷。

**建議**：改用 DB 層 advisory lock：開始更新前檢查 update_run 是否有 N 分鐘內仍 running 的列，有就 skip 並回傳 skipped 結果（update_run 已有 startedAt/status 可直接利用，成本很低）。背景任務尤其該讓路給前景。

**工作量**：medium

### 29. 外資持股變化的比較區間隨同步節奏在 0~7 天之間浮動，同一門檻套在不同長度的窗上——排名反映同步運氣而非外資動向

**狀態**：❓ 未查證

**證據**：lib/domain/services/update/batch_data_loader.dart:113-121 prev 端用 `getShareholdingsBeforeDateBatch(beforeDate: date - foreignShareholdingLookbackDays)`（=5 天，rule_params_institutional.dart:110），current 端用 lib/data/database/dao/shareholding_dao.dart:39-53 `getLatestShareholdingsBatch`（全域 MAX(date)，無上下界）。lib/domain/services/update/batch_data_builder.dart:26-29 直接相減得 ratioChange，規則（extended_market_rules.dart:25-36）只比門檻、不看區間長度。實測 DB：以 7/24 為基準算每檔的 (latest − prev) 實際間隔，分布為 0 天 24 檔、3 天 8 檔、4 天 18 檔、5 天 14 檔、6 天 28 檔、7 天 55 檔。另 shareholding 表全庫只有 147 檔有資料（7/24 當天僅 55 檔），意即 FOREIGN_* 系列規則實質只覆蓋自選+熱門股。

**對分析判斷的影響**：同一份「外資持股比例增加 0.8%」的訊號，在 A 股是 7 天累積、在 B 股是 3 天累積——7 天窗的股票跨過門檻的機率大約是 3 天窗的兩倍多，純粹因為它的同步排程比較舊。我拿這個榜單挑「外資最積極加碼」的標的時，實際上是在挑「上次同步隔比較久」的標的。更隱蔽的是那 24 檔間隔 0 天的（latest 就是 prev），ratioChange 恆為 0，它們永遠不可能觸發外資加碼或 FOREIGN_EXODUS(-20 severe)——我以為有在監控，其實那幾檔完全沒有被評估。

**建議**：(a) `getLatestShareholdingsBatch` 加 `asOf` 上界參數（與 price/institutional 一致）；(b) prev 端改成「取 latest 之前第 N 個實際資料點」而非「日期早於 T-5 的最新一點」，並把實際間隔天數寫進 evidence 與 description（「外資持股比例 5 日增加 0.8%」）；(c) 間隔為 0 或超過某上限（例如 15 天）時 return null 並計入 skip 帳目，別靜默算成「無變化」。

**工作量**：medium

### 30. 指數深度回補（單輪 60 次連續 MI_INDEX）與當日高價值 TWSE 批次抓取並行執行，而 TWSE 是 per-IP redirect-loop 限流

**狀態**：❓ 未查證

**證據**：update_service.dart:256-261 四路 `.wait` 並行（_syncAuxiliaryData 含指數回補 vs _syncMarketAndFundamentalData 含估值/營收/當沖/融資/警示）；api_config.dart:186 `indexBackfillMaxDaysPerRun = 60`；market_index_syncer.dart:409-412 自承「2026-07-16 活體驗證：60 天排隊、50 次呼叫後撞限流中止」；market_client_mixin.dart:93-102 redirect loop → RateLimitException；update_service.dart:599-606 籌碼路徑收到 RateLimitException 即設 `ctx.rateLimitedAbort = true`，:548-553 讓後續基本面/財報/Killer Features 全數跳過。另 historical_price_syncer.dart 的 Phase 0（api_config.dart:109，30 次 MI_INDEX）在同一輪稍早也打同一支端點。

**對分析判斷的影響**：fresh DB 或指數深度不足的前 4-5 輪更新，當日的當沖比例／融資變化／估值／注意處置股可能被「52 週大盤位階」這種背景補歷史的動作擠掉。回檔模式與當沖門檻判斷直接吃這些欄位，我會在「部分更新成功」的提示下用到前一天的籌碼數字做今天的決策。指數深度回補本身失敗是 fail-soft（market_index_syncer.dart:455-460 只 break），代價卻由高價值資料承擔。

**建議**：把指數深度回補序列化到 TWSE 批次抓取之後（移出並行 block，或在 _syncAuxiliaryData 內延後到 _syncMarketAndFundamentalData 完成），或把單輪上限從 60 降到 10-15 讓它跨多輪收斂——它本來就是「錦上添花」的背景步驟。

**工作量**：small

### 31. 月營收快取門檻跨市場混算，可能在上市公司公布完成前就閂死該月同步；且營收規則對資料月份零時效檢查

**狀態**：✅ 已修 `19122f4` — `getRevenueCountForYearMonth` 加 market 參數

**證據**：lib/data/repositories/fundamental_repository.dart:312-326：`getRevenueCountForYearMonth(dataYear, dataMonth) > DataFreshness.revenueRecordThreshold(=1000)` 即 return null 跳過整批寫入。lib/data/database/dao/revenue_dao.dart:202-210 該 count 不分市場、對 monthly_revenue 全表計數，而上櫃營收（fundamental_repository.dart:417-448 `syncOtcRevenue`）寫進的是同一張表。日誌實證交叉汙染：`[TWSE] 月營收: 1082 筆` 但 `[FundamentalRepo] 2026/6 營收資料已快取 (1316 筆)` — 多出的 234 筆即非 TWSE 來源，代表計數器確實混市場，而上市單一市場滿覆蓋約 1,050~1,082 筆、只比門檻 1000 高一點點。消費端無任何時效防護：lib/domain/services/rules/fundamental_scan_rules.dart:30-34 `RevenueYoYSurgeRule` 直接取 `data.latestRevenue`（來自 batch_data_loader.dart:89-92 `getLatestMonthlyRevenuesBatch`，SQL 為 MAX(date)、無下限），只看 yoyGrowth 不看 revenueYear/revenueMonth；對照 :13-17 估值有 `_isValuationStale`（valuationMaxStaleDays=7）、財報有 `TaiwanCalendar.expectedLatestReportQuarter`——只有營收沒有對應把關，而 `TaiwanCalendar.expectedLatestRevenueMonth`（taiwan_calendar.dart:261-264）其實已經存在，只被 fundamental_syncer.dart:279 的自選回補用到。

**對分析判斷的影響**：台股月營收絕大多數公司壓在 10 日截止當天才公布。若在 8/9 那輪 count 已經被（上市部分覆蓋 + 累積的上櫃列）推過 1000，8/10 這批最關鍵的資料就會被判定「已快取」而永久不抓，而且下一個月才有機會自然修復。對交易的影響是雙重的：第一，7 月營收缺的那些公司，`latestRevenue` 會退回 6 月的數字；第二，因為規則完全不檢查資料月份，`RevenueYoYSurgeRule` 會照樣觸發並在畫面上寫「營收年增 45% (站上季線且長紅)」——描述字串裡沒有月份（fundamental_scan_rules.dart:43），我根本看不出這是兩個月前、市場早就消化完的數字。我會把它當成剛出爐的營收利多去追價，追的卻是已經反應過的行情；反過來 `RevenueYoYDeclineRule` 也會用舊數字持續扣分，讓一檔營收剛轉正的股票遲遲不進榜。

**建議**：(1) `getRevenueCountForYearMonth` 加 market 參數（JOIN stock_master 過濾 TWSE），讓上市的快取判斷只數上市列；(2) 門檻改成相對量（例如「該月列數 ≥ 當前 API 回傳筆數的 98%」或直接比對 `getAllActiveStocks` 中該市場家數），別用寫死的 1000 對上 1,082 這種只差 8% 的邊際；更穩的做法是把 API 回傳的 code 集合與 DB 該月已有的 symbol 集合做差集，有差集就寫（insertMonthlyRevenue 已是 upsert + coalesce，重寫成本極低）；(3) 營收規則加時效閘門：用既有的 `TaiwanCalendar.expectedLatestRevenueMonth(evaluationTime)`，`latestRevenue` 不是最近 1~2 個應公布月就不觸發（比照 `_isValuationStale` 的寫法）；至少也要把 `revenueYear/revenueMonth` 寫進 description，讓「營收年增 45%」變成「6 月營收年增 45%」。

**工作量**：medium

### 32. 歷史價格的 RateLimitException 不 rethrow、記錄時用 errors.add 而非 recordError，導致既不設 rateLimitedAbort 也不彈限流對話框，下游 FinMind 步驟繼續空打

**狀態**：✅ 已修（2026-07-27 `b225da4`）

查證為真且完整：phase 1 的 per-symbol 迴圈捕捉 RateLimitException 後只設
**區域變數** `rateLimited` 中止迴圈，既不 rethrow、也不放進
`HistoricalPriceSyncResult`，故 coordinator 的 `on RateLimitException`
接不到、失敗只走 `errors.add` 而非 `recordError`。

修法：result 保留原始例外，coordinator 據此設 `rateLimitedAbort` 並走
`recordError`。**不 rethrow 是對的**（已抓到的歷史資料要保留），缺的只是
把「為什麼中止」帶出去。只在收到確證的 RateLimitException 時填入——
NetworkException 與防禦性 circuit breaker 是推測不是確證。

**嚴重度校正**：配額用完後 `checkBudget` 會在發網路請求前擋下，下游不會
多燒配額；真正的損害是錯誤分類與 UI 限流提示，非資料缺口。屬 medium。

**證據**：lib/domain/services/update/historical_price_syncer.dart:636-642（RateLimitException 只轉成 failedSymbols + rateLimited=true，函式不 rethrow）；lib/domain/services/update_service.dart:495-499 用 ctx.result.errors.add(...) 而非 recordError(...) → UpdateResult.hasRateLimitError 保持 false（定義見 update_service.dart:1000-1003）→ lib/presentation/screens/today/today_screen.dart:820 的 showApiRateLimitDialog 不會觸發；ctx.rateLimitedAbort（update_service.dart:968-972 的設計意圖）也沒被翻起

**對分析判斷的影響**：FinMind 配額在步驟 4 打爆之後，步驟 4.6/4.7/6.5 的上櫃估值、上櫃營收、財報、外資持股全部繼續打同一個被限流的 API、各自回 0 筆並各自靜默降級——這正是 rateLimitedAbort 當初要防的情境，卻在最會撞限流的那一步失效。使用者只看到一條「歷史資料同步失敗 (N 檔)」的橘色警告，不會意識到「今天所有 FinMind 來源的資料都是舊的」。今天日誌的「上櫃 (20/269 檔) 營收=94」在限流時會變成 0/269，外觀上跟配額用盡的正常截斷無法區分。

**建議**：HistoricalPriceSyncResult 增加 rateLimited 旗標；_syncHistoricalData 讀到該旗標時改用 ctx.result.recordError(...) 並設 ctx.rateLimitedAbort = true，與其他 syncer 的契約對齊。

**工作量**：small

### 33. 歷史價格預算把上櫃股（1 次 FinMind 呼叫/檔）當成上市股（1 次/月）計價，估算灌水最多 14 倍，把每輪可同步檔數壓到 15-28 檔

**狀態**：✅ 已修（2026-07-27 `b225da4`）

查證為真，證據在 `price_repository.dart` 的市場分流：上櫃走
`_tpexSource.fetchSingleStockPrices(startDate, endDate)` **整段 1 次**，
上市才是 `_twseSource.fetchMonthlyPrices(months: ...)` 逐月；而
`_estimateAvgMonthsNeeded` 完全不分市場。

正式日誌實證：8291 尚茂（TPEx）估「8.0 個月」，實際
`TaiwanStockPrice(8291): 138 筆` **只有 1 次呼叫**。

修法：估算改為分市場計價，**查不到市場者一律按上市（逐月）保守計價**——
估錯方向不對稱，高估只是回補變慢，低估會讓 maxSyncCount 放大到打爆
FinMind 的 600/hr，有專門的守門測試釘住這個方向。

**影響面校正**：穩態下節流綁不住（當日只有 1 檔需要、上限 38），只有冷啟動
或長期未開才會綁。屬回補速度問題，不影響正確性。

**證據**：lib/domain/services/update/historical_price_syncer.dart:417-472 `_estimateAvgMonthsNeeded` 對每檔一律用「視窗內缺口月數」計價，全程沒有查 market；但 lib/data/repositories/price_repository.dart:170-184 顯示上櫃走 `_tpexSource.fetchSingleStockPrices`（tpex_price_source.dart:25-35，FinMind 單次 range 查詢＝1 呼叫），只有上市走 `fetchMonthlyPrices`（twse_price_source.dart:40-81，逐月）。日誌「每檔平均需 11.0 個月 API 呼叫，動態限制為 28 檔（API 預算 300）」；DB 實證 8291 market=TPEx、145 筆，真實成本 1 次呼叫卻被估成 ~8 個月。在市股票 TPEx 1311 / TWSE 1379，上櫃佔 49%。

**對分析判斷的影響**：fresh DB 或長假回來時，待補歷史清單約一半是上櫃股，估算把預算灌水近一個數量級 → 每輪只補 15-28 檔而非實際負擔得起的上百檔。上櫃股要多花數週才湊滿 250 根 K（indicator_rules.dart:82 對 52 週高低是硬性 250 根門檻），這段期間起漲/強勢模式對上櫃股系統性漏訊號，我會誤以為「這波是上市股在漲」。

**建議**：估算與扣帳按市場分開：TPEx 記 1 次、TWSE 記缺口月數；並把兩個 vendor 的預算分別結算（FinMind 走已存在的 ApiBudgetTracker 600/hr，TWSE 走 scraping-politeness 預算）。

**工作量**：medium

### 34. 法人連續買賣天數被 10 日載入窗右設限，「連續 9 日」實為「≥9 日」——同一 codebase 已為市場總覽徽章解過這個 bug，個股規則沒跟上

**狀態**：✅ 已修 `c5b6e7e` — 取數窗改用 `institutionalStreakLookbackDays`，並以 `streakTruncated` 揭露觸頂

**證據**：lib/core/constants/rule_params_institutional.dart:10 `institutionalLookbackDays = 10`（日曆天）；lib/domain/services/update/batch_data_loader.dart:53-56 用它當 instStartDate，所以規則拿到的 history 最多 7-9 個交易日。lib/domain/services/rules/institutional_rules.dart:32 註解寫「掃描整個歷史以取得完整連續天數」、:40-59 從 history 末端往回數但視窗本身已被截斷；description（:104）直接輸出「連續買超 $streakDays 日」。實測 DB：INSTITUTIONAL_BUY_STREAK 全期 streakDays 分布 4:82, 5:58, 6:49, 7:41, 8:39, **9:17，10 以上 0 筆**——分布在視窗邊界硬切。對照組：同檔 rule_params_institutional.dart:15-20 的 `kStreakLookbackDays = 90` docstring 已明確記載「預設 30 會把真實連續天數截斷在 30（DB 內 dealer 曾連 47 日淨買、卻顯示「連30日」）」，並在徽章顯示「90+」。

**對分析判斷的影響**：「外資投信連續買超 9 日」跟「連續 25 日買超」是完全不同等級的籌碼訊號——後者是主力鎖碼、我會加大部位並拉長持有；前者可能只是一波短打。現在兩者在畫面上長得一模一樣，我沒有任何辦法分辨，等於失去部位大小與持有期的決策依據。此外 totalNet / dailyAvg / significantDays 三道過濾也都只算被截斷的 9 天，長期溫吞吸貨（每日剛好卡在門檻附近但持續兩個月）會被算成「總量不足」而整條訊號消失。

**建議**：把個股 streak 規則的取數窗與徽章對齊（獨立常數，例如 `institutionalStreakLookbackDays = 90`，只給 streak 規則用、不動其他規則的 10 日窗，避免拖慢 batch load）。streak 觸頂時 description 改輸出「連續買超 9 日以上」並在 evidence 加 `truncated: true`，讓 rule_accuracy 與 UI 都能分辨。

**工作量**：small

### 35. 法人連買/連賣 streak 用陣列索引判「連續」而非日曆日，缺漏日把「中斷」靜默變成「連續」——實測 15% 的股票在 10 日窗內有缺日

**狀態**：✅ 已修 `94b7977` — 以價格列為 ground truth 補零值列，三種缺列語意分開處理

**證據**：lib/domain/services/rules/institutional_rules.dart:40-58 從 history 末端往前掃、不合格就 `break; // 連續中斷 - 必須是真正連續`，但整段完全沒有比對相鄰兩列的日期是否為連續交易日；資料來源 lib/data/database/dao/institutional_dao.dart:50-80 只是照 date ASC 排序後分組，缺的日子就是陣列裡不存在。寫入端 lib/data/repositories/institutional_repository.dart:148-167 明確過濾掉「totalNet、foreignNet、investmentTrustNet 皆為 0」的列（backfill 路徑 245-265 同邏輯）→ 法人零進出的日子在表裡根本沒有列。完整性檢查 institutional_repository.dart:320-323 `isDayComplete` 只看單日全市場筆數 > DataFreshness.fullMarketThreshold(1500)，是 market-level 門檻、不是 per-symbol，所以個股層級的缺漏永遠偵測不到、也永遠不會被回補（回答日誌那句「9 天已完整跳過」的疑問：它保證的是「那天全市場有 1500 筆以上」，不保證「你關注的那檔有」）。DB 實證：最近 10 個交易日，2091 檔有法人資料的股票中 311 檔（15%）列數不足 10（例：00851 缺 5 天、1108 與 1233 各缺 1 天）。門檻 lib/core/constants/rule_params_institutional.dart:13 streakDays=4、25 minDailyNetShares=50000。

**對分析判斷的影響**：法人淨額為 0 的一天（combinedNet=0，本來一定會 break streak）因為表裡沒有那一列而被直接跳過，等於把「買 2 天、空 1 天、再買 2 天」讀成「連續 4 日買超」。INSTITUTIONAL_BUY_STREAK 是今日命中數最高的籌碼訊號之一（39 次，TWSE 37/TPEx 2）。我依「外資+投信連 4 買」判定法人正在建倉、認為籌碼在持續流入而進場並抱單，實際上流入是斷續的、動能比帳面弱，這會直接影響我的持有天數與停損容忍度。缺漏又集中在成交清淡的中小型股（零進出日多），所以偏誤方向是「越冷門的股票 streak 越容易被灌水」。

**建議**：streak 迴圈改成同時比對日期：往前一筆時用 `TaiwanCalendar` 取前一個交易日，若 `history[i-1].date` 不等於該日即視同該日淨額為 0 → break。這是純規則層改動、不需要改同步或補資料，也不會增加 API 呼叫。順帶把 InstitutionalSellStreak（同檔案下方）一起改，屬同一 bug class。

**工作量**：medium

### 36. 董監持股只有單一月份快照且無回補，INSIDER_SELLING_STREAK（-25，severe 風險徽章）結構性永遠不會觸發

**狀態**：📋 已記錄未修 — 每月申報的 cold-start，約需累積至 2026-09-15；`b538c41` 另修掉 buyingChange 單位混用（百分點 vs 股）的未爆彈

**證據**：實測 DB：`insider_holding` 全表只有 **一個日期 2026-07-15**（1965 筆）；daily_reason 全期的 INSIDER_* 只有 HIGH_PLEDGE_RATIO 6 筆，INSIDER_SELLING_STREAK 0 筆。lib/data/repositories/insider_repository.dart:265 `if (sortedAsc.length < requiredMonths) return (false, 0);`（requiredMonths 預設 3，:214）→ 單筆快照必定回 false。同檔 :78-85 的同步只抓「當月」且 existingCount > 1500 就整段跳過（日誌「董監持股資料已是最新 (1965 筆)」），沒有任何歷史月份回補路徑。該規則有註冊（lib/domain/services/rule_registry.dart:90）且列在 RiskWarnings.severe（lib/core/constants/risk_warnings.dart:41）。

**對分析判斷的影響**：「內部人連續減持」是我判斷經營層信心的第一手訊號，而且是 app 標為 severe（紅底徽章）的七條之一。現在它是一條死規則：任何一檔內部人連三個月倒貨的股票，在掃描結果與個股頁上都會顯示「無重大風險」。這是最危險的一種錯誤——不是給錯訊號，是在該示警的時候完全沉默，而 UI 的乾淨畫面讓我以為系統檢查過了。全新安裝的裝置要連續使用 3-4 個月才可能首次觸發。

**建議**：(a) 加一次性歷史回補：TWSE/TPEx 的董監持股月報有歷史查詢參數，開機時回補 `DataFreshness.insiderDefaultMonths`(12) 個月，之後每月增量即可；(b) 在回補完成前，讓規則回傳一個明確的「資料不足」狀態而非 false，UI 顯示「內部人資料累積中（1/3 月）」——寧可顯示不知道，也不能顯示無風險；(c) 把同樣的檢查套到 :83 的新鮮度短路上：目前只看筆數不看月份數，永遠不會發現只有一個月。

**工作量**：medium

### 37. 規則命中率 UI 只給裸命中率、不給 baseline，34.6% 的隨機基準被當成 50% 讀——n=22 的 59% 會被誤讀為高勝率

**狀態**：⚠️ 曾修 `c0c43a2`、後於 `ca18a90` 移除 — 靜態基準（另一 dev DB 的 34.61%）與量測窗（實測 19.04%）來自不同市場環境，14 條有樣本的規則中 10 條正負號翻轉。顯示方向相反的比較比不顯示更糟

**證據**：lib/domain/services/rule_accuracy_service.dart:439-458 `getRuleSummaryText`：`triggerCount < 5` 才回 null，之後直接輸出「命中率 X%，平均 N 日報酬 Y」；只有 `triggerCount < sampleSizeCutThreshold`(30) 時附「信心度較低」。lib/core/constants/calibration_thresholds.dart:76-86 早已實測出 per-period 的隨機 baseline：5D≥1.5% 的 baseline 是 **0.3461**、60D≥8% 是 0.3965，且 docstring 直指「用 0.5 當 baseline 會系統性低估 rule 的 alpha」。但這份 baseline 只用在 calibration 的 t-stat，完全沒進 UI。實測 rule_accuracy 5D：PE_UNDERVALUED hit 59.1% (n=22)、VOLUME_SPIKE 47.1% (n=17)、INSTITUTIONAL_BUY_STREAK 33.3% (n=111)。

**對分析判斷的影響**：我在個股詳情頁看到「法人連買：命中率 33%」會直覺判定這條規則很爛而忽略它——但 5D 的隨機基準就是 34.6%，33% 只是持平、不是災難。反過來看到「PE 低估：命中率 59%」會覺得抓到寶而重壓——實際上 n=22 低於 calibration 自己的 30 筆顯著性下限，且那 22 筆還是上面提到的序列重複樣本。兩個方向的誤讀都會直接改變我的部位配置。

**建議**：`getRuleSummaryText` 改成輸出相對 baseline 的 lift：「命中率 59%（隨機基準 35%，+24pp）」，baseline 直接讀 `CalibrationThresholds.successProbabilityBaselines[holdingDays]`。並把顯示門檻從 `triggerCount >= 5` 提高到與 calibration 一致的 30（低於 30 顯示「樣本不足，暫不評價」而非給一個會被信的數字）。

**工作量**：small

### 38. 規則層沒有跨頻率資料的「新鮮度閘門」：法人(日)/TDCC(週)/董監(月)/財報(季) 被當成同一天的事實使用，只有估值有 age gate

**狀態**：❓ 未查證

**證據**：全 lib/domain/services/rules/ 目錄下只有 fundamental_scan_rules.dart:15 與 :215 用到 `context.evaluationTime.difference(...)` 做時效判斷（估值 `_isValuationStale`）。法人：lib/domain/services/rules/fundamental_rules.dart:33-35 `InstitutionalShiftRule` 取 `history.last` 當「今日」，:66-76 同時取 `data.prices.last` 當「今日價格」，兩者無日期比對；institutional_rules.dart:40 的 streak 迴圈也是純 list 相鄰、非日曆相鄰。實測 DB：2026-07-24 有價格但無當日法人資料的股票 **168 檔**（7/23 為 166 檔）；另有 28 檔在 7/21、7/23 有法人資料但 7/22 缺（`intersect ... not in` 查詢），這些中間缺漏會被 streak 迴圈直接跨過、當成連續。董監持股 InsiderDataContext、TDCC concentration（holding_distribution 最新 7/17，落後 7 天）同樣無 age 欄位。

**對分析判斷的影響**：一旦某天 TWSE 法人檔延遲發布或 syncer 失敗（這在盤後 21:00 前跑更新時是常態），規則會把 T-1 的法人淨額配上 T 的價格與量能算 ratio，產出「法人由賣轉買（佈局）」這種明確的進場訊號——而那個買超其實發生在前一天、價格早就反應過了。我照著這個訊號隔天開盤追進，等於追一個已經走完的 event。中間缺漏日更糟：一檔實際是「買、無、買、買」的股票會被報成「連續 3 日買超」，缺的那天可能根本沒有法人進場。這類錯誤沒有任何日誌或 UI 提示，我無從察覺。

**建議**：在 AnalysisContext 或 MarketDataContext 加上各資料源的 `asOfDate`，並在規則進入判斷前做兩件事：(1) 對日頻資料（法人、當沖）要求 `asOf == evaluationTime`，不符就 return null 或在 description 標註「（法人資料為 M/D）」；(2) streak 類規則改用日曆相鄰驗證（用 TaiwanCalendar 逐一檢查前一個交易日是否存在），缺漏日視為 streak 中斷而非跳過。同時在 UpdateService 完成日誌加一行「法人資料覆蓋率 1961/2129」，讓覆蓋率退化可被看見。

**工作量**：medium

### 39. 釘選論點檢查先蓋「已檢查」章再逐筆評估，中途失敗會讓從未評估的論點顯示「最後檢查：今天」

**狀態**：❓ 未查證

**證據**：lib/domain/services/thesis/thesis_monitor_service.dart:25 `await _db.touchLastChecked(asOf)` 位於 for 迴圈之前；lib/data/database/dao/thesis_dao.dart:105-109 一次 update 全部 ACTIVE；迴圈內 getPriceHistory / invalidateThesis 任一拋例外即整段中止並被 lib/domain/services/update_service.dart:899-901 的 fail-safe 吞成一條 AppLogger.error；UI 直接顯示該欄位 lib/presentation/widgets/pinned_thesis_section.dart:310-313

**對分析判斷的影響**：這是出場層。假設使用者釘了 5 個論點，第 2 筆的價格查詢炸掉 → 第 3-5 筆從未被 timeStop 規則評估，但卡片上仍寫「最後檢查 今天」。使用者看到這行字的意思是「系統今天確認過它還成立」，於是續抱一個其實已經觸發時間停損的部位。整場更新照樣是綠燈「更新完成」，UpdateResult 一個字都沒提。

**建議**：把 touchLastChecked 改成逐筆評估成功後才蓋章（或迴圈內 per-thesis try/catch，失敗者不蓋章並累計失敗數回傳給 coordinator 記入 errors）。fail-safe 的正確語意是「不中斷更新」，不是「假裝檢查過」。

**工作量**：small

## severity: low

### 40. force 契約在融資融券這一段斷掉：協調層註解宣稱三類籌碼都強制重抓，實作只把 force 傳給當沖

**狀態**：❓ 未查證

**證據**：lib/domain/services/update_service.dart:567-575 的註解明寫「硬寫 force: true 是刻意：當沖/融資/融券 batch API 每次都重抓全市場…新鮮度檢查反而浪費一次 DB count query」，並以 `force: true` 呼叫 `syncMarketWideData`。但 lib/domain/services/update/market_data_updater.dart:56-59 只把 force 傳給 `syncAllDayTradingFromTwse`，:70 的 `_tradingRepo.syncAllMarginTradingFromTwse(date: date)` 沒有帶 force，因此 trading_repository.dart:247-255 的 `existingCount > DataFreshness.fullMarketThreshold(=1500)` 快取閘門照常生效。2026-07-25 日誌可見結果：`[TradingRepo] 融資融券資料已快取 (1993 筆)，跳過同步`，與同一輪當沖確實重抓 1219 筆形成對比。另 fundamental_repository.dart:159-192 `syncAllMarketValuation` 宣告了 `bool force` 參數但函式體內從未引用（dead parameter）。

**對分析判斷的影響**：日常路徑上這不會給我錯資料——快取判準是綁在目標日期上的，資料真的補齊了才會跳過，且缺漏日另有回補迴圈守住。真正的風險是「我以為 force 有效」：當我懷疑某天的融資餘額寫壞（例如撞到部分寫入或市場別缺一邊）而按下強制更新時，融資融券那段其實根本沒有重抓，我會誤判成「重抓過了、資料就是長這樣」，接著拿錯誤的融資餘額變化去讀籌碼（chip_analysis_service.dart:142-173 的 marginBalance 判斷）。同一份 codebase 裡 FundamentalSyncer 對營收特地補過同型的洞（fundamental_syncer.dart:53-55 的註解「force 需轉給營收：否則強制同步時營收會因 skip-if-cached 而不重抓」），這裡是同一個 bug class 沒掃乾淨。

**建議**：market_data_updater.dart:70 補上 `force: force`，讓 force 語意在整條鏈上一致；順手刪掉 `syncAllMarketValuation` 那個未使用的 force 參數（或真的接上），避免下次有人以為它有效。並補一條測試：以 force=true 呼叫 syncMarketWideData 時，verify 融資融券的 repo 方法收到 force=true。既然這是 bug class，建議一併 grep 所有 `force` 參數在 syncer→repo 之間的傳遞，確認沒有第三處遺漏。

**工作量**：small

### 41. rule_accuracy 每次全表 delete+rebuild，樣本深度完全綁 daily_reason 的現有跨度——本次僅約 8 個交易日，20D/60D 命中率結構上為零樣本

**狀態**：📋 已記錄未修 — `daily_reason` 僅 8 天（2026-07-15 fingerprint wipe 所致，且無回補路徑）

**證據**：lib/domain/services/rule_accuracy_service.dart:366-367 每次 `delete(_db.ruleAccuracy).go()` 後從當前 daily_reason 全量重建，統計不是累積的。日誌 `price window: 2026/7/14~2026/10/22` 反推：queryLowerBound = minEntry − 1 天 buffer（193 行）⇒ 最早 reason = 2026/7/15；queryUpperBound = addTradingDays(maxEntry, 60) + 1 天（194-196）⇒ maxEntry = 7/24。即 daily_reason 只涵蓋 7/15~7/24。holdingPeriods = [1,3,5,10,20,60]（50 行），4076 reasons × 6 = 24,456 個 (reason×period)，`skipped_no_exit_price=14489` = 59% 尚未到期。addTradingDays(7/24, 20) ≈ 8/21、(7/24, 60) ≈ 10/22 全在未來 ⇒ 20D/60D 累加器一筆都寫不進去，`getRuleStats(ruleId, '60D')`（404-423）必回 null。

**對分析判斷的影響**：個股詳情的「規則命中率」實際上只由最早那 2-3 天的訊號撐起來，且只有 1D/3D/5D 有數字；60D horizon 直接空白。我若拿頁面上的 5D 命中率去推斷一條規則適不適合波段/長線持有，等於用 3 天的樣本外推 3 個月，方向性錯誤的機率很高。（緩解：getRuleSummaryText 在 n<30 時會附「信心度較低」註記，見 439-458；但 60D 是「完全沒有」而非「樣本少」，UI 顯示為空白時我無法分辨是「沒統計到」還是「這條規則長線沒用」。）另註：本次 log 的 `price window` 語意本身正確，它是 SQL 查詢邊界（含最長 holding 的出場日），不是宣稱資料已存在——這點沒有問題。

**建議**：至少在 UI 區分「樣本不足以計算」與「無資料」；並考慮讓 rule_accuracy 保留 period 維度的樣本涵蓋率（例如記錄該 period 的 matured/total 比例）供顯示層判斷。長期則需要讓 daily_reason 有明確的保留策略與最小累積深度目標，否則任何一次 DB 重建都會把命中率統計歸零。

**工作量**：medium

### 42. 上櫃營收新鮮度檢查拿日曆月比對營收月，命中率恆為 0%，等同無效閘門且讓 API 成本帳目失真

**狀態**：📋 已記錄未修（2026-07-27 查證為真，但無害）

機制成立：新鮮度拿 `targetDate` 的日曆月（如 2026-07）比對營收月，而 7 月營收
8 月才公布 → 判定恆為 stale。實測日誌每輪都是「100 檔中 100 檔需同步」。

**但成本是 0**：`syncOtcRevenue` 走 TPEx OpenAPI **全市場單次端點**
（`fundamental_repository.dart` 的「免費無限制」註解），100 檔與 1 檔都是 1 次
呼叫。閘門失效不會多燒配額，只是日誌數字沒有資訊量。

不修的理由：修它需要引入「營收發布行事曆」語意（財報那條有
`TaiwanCalendar.expectedLatestReportQuarter`，營收沒有對應物），成本高於收益。
與 #43 為同一件事。

**證據**：lib/data/repositories/fundamental_repository.dart:384-401：`isCurrentMonth = latest.revenueYear == targetDate.year && latest.revenueMonth == targetDate.month`。但 revenueMonth 是「營收所屬月」（N 月營收於 N+1 月 10 日前公布），targetDate 是交易日，兩者結構上永遠差 1~2 個月，條件恆為 false。日誌實證兩處都是 100% miss：`上櫃營收新鮮度檢查: 4 檔中 4 檔需同步`、`上櫃營收新鮮度檢查: 100 檔中 100 檔需同步 → 同步完成: 94/100 檔`。正確的判準 `TaiwanCalendar.expectedLatestRevenueMonth`（taiwan_calendar.dart:261-264，含 `now.day > 10 ? 1 : 2` 的公布日邏輯）已存在於同一份 codebase，只被 fundamental_syncer.dart:279 用到。連帶效果：`syncOtcRevenue` 回傳 successCount=94，被 update_service.dart:792-799 加總成 `(API ~94 calls)`，但實際 fundamental_repository.dart:418 只打了 1 次 `_tpex.getAllMonthlyRevenue()` 批次。

**對分析判斷的影響**：資料本身不會變舊（因為它每次都重抓），所以不會直接害我看錯數字，但有兩個間接代價：一是每輪多一次 getLatestMonthlyRevenuesBatch(100 檔) 的 DB 查詢加整批 upsert；二是更新摘要上「API ~94 calls」是假的（真值是 1），當我在判斷「今天是不是快撞 FinMind 配額、要不要手動限縮同步範圍」時，是拿一個高估近百倍的數字在做決策——而配額耗盡會直接讓自選股的外資持股、財報同步失敗。另外這條日誌永遠顯示 100/100 需同步，也讓我無法從日誌判斷上櫃營收到底有沒有真的更新到最新月。

**建議**：把 :393-396 的判斷改成 `final expected = TaiwanCalendar.expectedLatestRevenueMonth(targetDate); final isFresh = latest != null && !DateTime(latest.revenueYear, latest.revenueMonth).isBefore(expected);`，並補一個 unit test 固定住「7/24 時 6 月營收算新鮮、5 月算過期」。同時修 `FundamentalSyncResult.total` 的語意——它被當成 API call 數用（update_service.dart:792），但實際是資料列數；批次來源應回報固定成本 1，或乾脆把日誌字樣從「API ~N calls」改成「寫入 N 筆」。

**工作量**：small

### 43. 上櫃營收的新鮮度檢查用「當月」比對「營收月」，永遠不成立，等於沒有 gate

**狀態**：📋 已記錄未修 — 與 #42 為同一條，處置見 #42

**證據**：lib/data/repositories/fundamental_repository.dart:393-396 `latest.revenueYear == currentYear && latest.revenueMonth == currentMonth`；但 TPEX `資料年月` 是資料所屬月（tpex_client.dart:936-956 解析註解），營收次月 10 日才公布。DB 實證 monthly_revenue 最新為 2026/6（1316 筆），而 targetDate 是 2026/7 → 條件恆為 false。日誌「上櫃營收新鮮度檢查: 100 檔中 100 檔需同步」每輪皆然。專案內已有正確做法：fundamental_syncer.dart:279 用 `TaiwanCalendar.expectedLatestRevenueMonth`。

**對分析判斷的影響**：成本只有 1 次免費呼叫，但它讓「上櫃營收到底有沒有更新」在日誌上完全不可觀測——每輪都顯示 100/100 需同步，真的漏資料時也是同樣的訊息。同時 otcFundamentalsSyncMaxCount=100 這個配額參數形同失效，因為篩選永遠不會縮小清單。

**建議**：改用 `TaiwanCalendar.expectedLatestRevenueMonth(now)` 當比較基準（與財報的 expectedLatestReportQuarter 同款設計），讓穩態下真的跳過。

**工作量**：small

### 44. 內部人轉讓「API 回傳空資料」無法與「parser 全滅」區分——而這個 failure mode 在此專案已經發生過一次（有註解為證）

**狀態**：❓ 未查證

**證據**：lib/data/remote/tpex_client.dart:1059-1066：逐筆 `TpexInsiderTransfer.tryFromJson`，失敗只在 debug 層記一行（lib/data/models/tpex/tpex_insider_transfer.dart:76-86），聚合日誌印的是 `results.length`（解析成功數）而非 `data.length`（原始筆數），且沒有 skipped 計數器。對照組：lib/data/remote/tdcc_client.dart:79,86,96-100 就有 `skipped` 並印在日誌裡。下游 lib/domain/services/update/insider_transfer_syncer.dart:32-34 收到空 list 只印「API 回傳空資料」並回 0，不算錯誤。前科證據就寫在 tpex_insider_transfer.dart:35-37 的註解：「TPEx OpenAPI 的實際 key 帶群組前綴，舊版讀 '轉讓股數'/'目前持有股數' 等不存在的 key → 全部 fallback 成 0（已驗 17/17 筆皆 0 的 bug）」。UI 端 lib/presentation/screens/stock_detail/tabs/insider_tab.dart:121 用 `insiderTransfers.isNotEmpty` 決定是否渲染，資料為空時整個區段消失（不是顯示「無資料」）。

**對分析判斷的影響**：TPEx 只要再改一次欄位名，內部人轉讓就會靜默歸零數週，而日誌每天照樣印「API 回傳空資料」看起來一切正常。我在買進前習慣翻個股頁看有沒有董監申報轉讓，那個區段直接不見了，我會判定「沒有內部人在賣」而安心進場——但實際上這項檢查根本沒做。同一個 UI 行為也讓上市股（本來就只有 TPEx 來源、永遠是空的）和「今天真的沒申報」完全無法區分。

**建議**：client 日誌改印 `raw=N, parsed=M, skipped=N-M`；當 `raw > 0 && parsed == 0` 時升為 warning 並讓 syncer 視為同步失敗（走 recordError），而不是回 0 當成功。UI 對三種狀態用三種文案：「本市場無此資料源」／「近期無申報」／「資料同步失敗」。這一組修法同時適用於所有「逐筆 tryFromJson、聚合印 parsed 數」的 client（建議 grep `tryFromJson` 一次掃完同型別）。

**工作量**：small

### 45. 生產評分路徑的基本面批次查詢沒有 as-of 上界（全域 MAX(date)），與 replay_calibrator 的 point-in-time 口徑不一致，重跑歷史日會把未來資料寫進 daily_reason

**狀態**：✅ 已修 — 查證結論：**機制為真、觸發路徑不存在**（latent 而非 live），
但因其為「歷史重放進 daily_reason」的前置條件而修復。

查證細節：
- 機制屬實 — `getLatestValuationsBatch` / `getLatestMonthlyRevenuesBatch` /
  `getLatestShareholdingsBatch` 皆為全域 `MAX(date)` 無上界；同檔的 history
  變體本就支援 `endDate`，能力在只是沒接。
- **finding 描述的觸發路徑走不到** — 兩個 production 呼叫端
  （`today_provider` / `headless_update_runner`，CLI 亦走後者）都不帶
  `forDate`，`targetDate = forDate ?? _clock.now()`；只有測試傳歷史日。
- **另一條自行推導的路徑（日期回滾）也不成立** — 回滾發生於步驟 3，基本面
  同步在步驟 3.8-5 且吃回滾後的 `ctx.normalizedDate`，故基本面寫進回滾後
  那天、不會超前。
- **finding 的第二個宣稱不成立** — 「與 replay 口徑不同故不可互相驗證」：
  as-of = 今日時 point-in-time 等價於全域最新，正常每日路徑兩者一致。
- 修復為零行為變化：實測四張基本面表**無任何一列**日期超前最新價格日。

修法：三個 DAO 加 nullable `asOf`（`AND date <= ?`，`Variable.withDateTime`
沿用 day_trading_dao 慣例），由 `BatchDataLoader` 統一傳入評分日。省略時
維持原語意。測試 +5，DAO 語意與 loader 接線兩層各經 mutation 驗證。

**證據**：lib/domain/services/update/batch_data_loader.dart:71-140：只有 prices（:73）、institutional（:82-86）、dayTrading（:106）、prevShareholding（:114）帶日期；valuation（lib/data/database/dao/valuation_dao.dart:27-45 取全域 MAX(date)）、revenue（lib/data/database/dao/revenue_dao.dart:27-45 同）、shareholding（lib/data/database/dao/shareholding_dao.dart:39-53 同）、insider / eps / roe / dividend / maxRevenue 都不帶 `date`。對照組：tool/replay_calibrator.dart:610-625 明確做點時間過濾（`!revenueVisibleDate(e.date).isAfter(currentDate)`、:891-894 的營收 +1 月可見延遲），證明團隊知道正確做法、但只實作在 tool 端。觸發路徑：UpdateService.runDailyUpdate(forDate:) 與 force 重跑（update_service.dart:166-171、:244-246），ScoringService 對該日 clear-then-write 覆寫 daily_reason，而 RuleAccuracyService 直接讀全表 daily_reason（rule_accuracy_service.dart:142）。

**對分析判斷的影響**：日常「跑今天」不受影響（latest 就是今天），所以這不是每日的立即傷害。但只要我為了補資料對某個歷史日下 force 重跑，那天的 daily_reason 就會用「今天的」估值、營收、外資持股、EPS 重新產生訊號——例如 7/10 那天的分析會吃到 7/24 才公布的六月營收。這批被污染的列接著成為 rule_accuracy 的訓練樣本，讓命中率虛高，而我完全不會知道哪些日子被重寫過。也因為口徑與 replay_calibrator 不同，tool 算出來的 calibrated score 跟 runtime 產生的 daily_reason 不可互相驗證。

**建議**：給這批 DAO 加上 `asOf` 參數（`AND date <= ?`），由 BatchDataLoader 統一傳入 `ctx.normalizedDate`；營收沿用 replay_calibrator.dart:891 的 `revenueVisibleDate`（公布月 +1）作為可見日，把該函式從 tool 抽到 lib/core 共用，讓 runtime 與 calibrator 共一份口徑。若短期不想全改，至少在 `forDate != null || force` 時於 update_run.message 標記「歷史重跑」，讓 rule_accuracy 能排除這些列。

**工作量**：medium

### 46. 預算計量本身不可信：日誌把「寫入筆數」當成「API 呼叫數」報，而真正精確的 ApiBudgetTracker 數字從不印出

**狀態**：✅ 已修（第一步）— 查證屬實且比描述更嚴重。

`estimatedApiCalls = fundResult.total + marketResult.total`，而兩個 `total`
加的全是**寫入筆數**（`valuationCount + revenueCount`、
`dayTradingCount + shareholdingCount`），完全沒有 API 呼叫的成分。

2026-07-26 實測一次更新報「API ~94 calls」，真實 API 呼叫約 **2 次**
（上櫃估值與營收都走 TPEx OpenAPI 單次批次端點）——**高報 47 倍**。
高報方向特別有害：會讓人誤以為配額已緊而不敢調高 `maxSyncCount`，而
FinMind 配額正是上櫃涵蓋率上不去的瓶頸。

已把標籤改為「寫入 N 筆」並在註解記錄實測。`FundamentalRepository` 的
「API calls: 1」是正確的，未動。

**第二步待辦**：`ApiBudgetTracker`（per-vendor、sliding 1hr、只掛
FinMindClient）內部第 94 行算出的 `used` **沒有公開讀取點**，只在配額用完
時出現於例外訊息——等看到已來不及；且 tracker 未注入 `UpdateService`。
要印真值需動依賴注入鏈，且跨 isolate 各自一份 tracker 使數字只反映本次
process，故分開處理。

**證據**：update_service.dart:792-800 `estimatedApiCalls = fundResult.total + marketResult.total` → 日誌「步驟 6.5: …(API ~94 calls)」，但那 94 來自 syncOtcRevenue 的比對成功筆數，實際只有 1 次 TPEX 批次呼叫（fundamental_repository.dart:414-448 `_tpex.getAllMonthlyRevenue()` 一次抓全市場後本地過濾）。同理 market_data_updater.dart:312-332 的「持股=39」對 skip 與 sync 都 `return true`，看不出真實呼叫數。lib/data/remote/api_budget_tracker.dart:67 已有精確的 `callsInLastHourFor`，但全 repo 沒有任何地方把它印進更新日誌。

**對分析判斷的影響**：要調配額時，日誌會誤導我把免費的 TPEX 批次當成最大宗開銷（~94 calls），而真正稀缺的 FinMind 逐檔消耗（外資持股）被藏在「持股=39/0」裡看不見。實際估算下來每輪 FinMind 用量約 20-25 次，離 600/hr 的上限還有 96% 空間——也就是說目前所有把資料砍掉的上限（20、100、150、300）都不是被真實配額逼出來的。

**建議**：更新結束時輸出 ApiBudgetTracker 每個 vendor 的 used/budget；並把 TwseClient/TpexClient 也接上 tracker（TWSE 是唯一有實測限流證據的 vendor，卻是唯一沒被追蹤的）。停止用筆數冒充呼叫數。

**工作量**：small


### 47. 校準語料含 64% 生產永不評分的 stock-day（流動性宇宙分岔）

**狀態**：✅ 已決策執行（2026-08-29 使用者確認）——生產的流動性宇宙有
**兩道閘**（第一輪只補了一道，review 抓到）：

1. **候選層 20 日中位數閘**（`computeLiquidityEligibility`，point-in-time、
   窗界=全市場第 20 新交易日、permissive 語意鏡射 DAO）
2. **scoring 層單日閘**（`applySignalDayGate` 直接呼叫生產
   `LiquidityChecker.checkCandidateLiquidity`：股數 ≥ 100 萬、成交額
   ≥ 3,000 萬、缺值同樣 skip）——review 實測只套第一道時剩餘語料仍有
   28–39% 是生產當日 skip 的 stock-day，且系統性偏向高價薄量股

評估語料、universe 均值、baseline H0 套雙閘；**regime 只套中位數閘**
（生產先對候選批次全體算 regime、才逐股 classify）。兩道閘的「自選清單
豁免」皆刻意不模擬（lookahead + 使用者 overlay）。parity 由
`test/tool/replay_liquidity_gate_test.dart` 以生產 DAO/函式為 ground truth
釘住。**epoch 斷代**：gated 統計與歷次全語料結果不可比（exit_validate 的
81,989 樣本報告同屬舊 epoch）。

**證據**：生產只評分 CandidateSelector 產出（`candidate_selector.dart:48-58`，
20 日中位成交值 ≥ 3,000 萬，isolate 內二次把關 `scoring_isolate.dart:547-553`）；
replay 評 `stock_master` 全部（`test/tool/run_replay.dart` 預設無 whitelist）。
`tool/calibration.db` 近 20 個交易日：2,090 檔有 bar，1,347 檔（64%）過不了
流動性門檻。低流動股同樣餵進 regime universe。

**對分析判斷的影響**：calibrated scores 有約三分之二樣本來自生產永遠不會
評分的股票——比 2026-08-29 修掉的三處分岔（補零列／regime gate／法人窗）
加總都大。分數的統計性質（hit rate、t 值、cut 判定）被低流動股的行為拉動。

**為何不逕行修**：讓 replay 套同一道門檻是「校準語料定義」的變更——樣本大幅
縮小、所有規則統計重算、與歷次校準結果不可比。walk-forward 已用 top-400
流動樣本，方向一致但口徑不同。需要一次明確決策（含是否同步改 regime
universe），不適合夾帶在修 bug 的 commit 裡。

---

## 待遇到再決定的 UI 取捨

無正確性問題，建議實際遇到真實情境再定：

- 停牌股在自選頁的呈現
- 「連昨日也沒有」時今日頁的空狀態文案（現為「目前沒有符合條件的股票」，
  但事實可能是「沒算」）
- 背景路徑要不要為限流配長 backoff

## 方法論註記

- **量測本身也要反測**。得到「影響為 0」時，先確認不是機制沒生效造成的假零
  （例：補零實際改動 251 檔 `prevAvg`，證明機制有動、結果才可信）。
- **先查專案既有做法再設計**。本輪三次提案被既有實作取代（matched baseline
  → 超額模式已存在；自訂最小 universe → `kMinSymbolsForCompleteTradingDay`
  已存在；自訂日數門檻 → `minDistinctDates` 已存在）。註解與常數 docstring
  往往已寫著正解。
