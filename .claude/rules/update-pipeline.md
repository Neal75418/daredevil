---
paths:
  - "lib/domain/services/update/**"
  - "lib/data/remote/**"
  - "**/syncer*"
  - "**/Syncer*"
  - "**/BatchData*"
  - "**/rule_accuracy*"
---

# Update Pipeline

```mermaid
flowchart LR
    US(["UpdateService<br/><b>Coordinator</b>"])

    subgraph Sync["🔄 11 Syncer / Updater"]
        direction TB
        S1["StockList"] ~~~ S2["HistoricalPrice"] ~~~ S3["Institutional"] ~~~ S4["MarketData"]
        S5["Fundamental"] ~~~ S6["QuarterlyReport"] ~~~ S7["Dividend"] ~~~ S8["MarketIndex"]
        S9["News"] ~~~ S10["TdccHolding"] ~~~ S11["InsiderTransfer"]
    end

    subgraph Help["🧰 3 Helpers"]
        direction TB
        H1["BatchDataBuilder"] ~~~ H2["BatchDataLoader"] ~~~ H3["CandidateSelector"]
    end

    subgraph Post["🩺 Post-Update — fail-safe"]
        direction TB
        R1["RuleAccuracyService"] ~~~ R2["ThesisMonitorService"] ~~~ R3["TrailingMaAlertService"]
        R4["NewsMentionSnapshot"] ~~~ R5["ZeroingImpactReporter"]
    end

    US ==> Sync ==> Help
    US -.->|錯誤不中斷更新| Post

    classDef coord fill:#4F46E5,stroke:#3730A3,stroke-width:2px,color:#FFFFFF
    classDef sync fill:#F59E0B,stroke:#78350F,stroke-width:2px,color:#FFFFFF
    classDef help fill:#10B981,stroke:#065F46,stroke-width:2px,color:#FFFFFF
    classDef post fill:#8B5CF6,stroke:#4C1D95,stroke-width:2px,color:#FFFFFF

    class US coord
    class S1,S2,S3,S4,S5,S6,S7,S8,S9,S10,S11 sync
    class H1,H2,H3 help
    class R1,R2,R3,R4,R5 post
```

## Update 元件

- **Coordinator**: `UpdateService` — 協調所有 syncer 執行順序 + 錯誤處理。注意它住在 `lib/domain/services/`，**不在 `update/` 底下**（`update/update.dart` 只是 barrel export）
- **11 Syncers**: 各自從 External API 拉取特定類別資料（stock list、price、institutional、market data、fundamental、news、market index、TDCC holding、dividend、insider transfer、quarterly report）
  - `HistoricalPriceSyncer` 兩段式：**Phase 0 市場日快照回補**（lookback 窗內整市場缺漏的交易日，1 次呼叫補該市場全部股票一天——TWSE MI_INDEX / TPEx afterTrading 歷史端點；單次上限與連續零筆斷路器見 `ApiConfig.historicalMarketDay*`）→ **Phase 1 per-symbol**（補個股殘缺；priority＝自選+熱門追 250 天、非 priority 180 天早退）。**Phase 1 還有第三道閘**：覆蓋天數沒長的標的會被凍結 `DataFreshness.historicalBackfillBackoffDays = 30` 天並跳過——「是 needy」不等於「這輪會被同步」。**成本分市場**：**上櫃燒 FinMind**（`TpexPriceSource.fetchSingleStockPrices` 內部呼叫 `_finMind.getDailyPrices`，整段區間 **1 次**）；**上市燒 TWSE**（`TwsePriceSource.fetchMonthlyPrices` **逐月**，該檔完全沒有 FinMind）。⚠️ **類別名會騙人**——`TpexPriceSource` 的單檔歷史走的是 FinMind，真正吃 600/hr 額度的是上櫃這條，不是上市；預算估算（`_estimateAvgMonthsNeeded`）據此分流，**查不到市場者一律按上市保守計價**——高估只是回補變慢，低估會放大 `maxSyncCount` 打爆額度。限流中止會把原始例外放進 `HistoricalPriceSyncResult.rateLimitError`（**不 rethrow**，已抓到的資料要保留），caller 據此設 `rateLimitedAbort`
  - `QuarterlyReportSyncer`（2026-08-06）：TWSE/TPEx t187ap06 六業別 × 兩市場共 12 個免額度 openapi 端點,抓「最新一季綜合損益表」官方申報快照寫入 `quarterly_report`。每次更新都跑:公布期端點逐日填充、平時回最後完整季。雙源 per-source 隔離 + 業別 per-variant 隔離;金融業別未申報時回單一全 null 佔位列,model 的 null-aware 解析自然拒收
  - `FundamentalSyncer` 跑財報佇列**之前**先跑 `syncMarketWideBalanceSheets`（2026-08-16）：六業別 × 兩市場共 12 個**免額度** t187ap07 端點，一次補齊全市場資產負債表，讓後面兩條 FinMind 佇列的單位成本**砍半**。⚠️ 因此「財報是額度唯一瓶頸」的舊成本模型已不準
  - `FundamentalSyncer` 財報有**兩條獨立佇列**：上市走 `UpdateService.selectFinancialSyncTargets`
    （取 `[...twse, ...tpex]` 前 `financialSyncMaxCandidates`）；上櫃另走
    `selectOtcFinancialBacklog`（**最舊優先 + ETF 在取前 N 之前排除**），因為串接下上市候選恆
    遠超上限、上櫃永遠是餘數而餘數是 0。**兩市場都受額度節流**：
    `UpdateService.financialQuotaForBudget` 回傳 `({int twse, int otc})`，
    額度＝`(budget − used − financialBackfillReserve) ÷ 2`，上市先拿、上櫃吃剩；
    `quota.twse == 0` 時上市直接短路成空清單。
    （2026-08-05 季報季修復：原本只擋上櫃，因為假設「上市 needy 為空所以不是壓力來源」——
    季報季全市場同時變 needy，單輪 488 次呼叫吃掉 82% 小時額度，該假設破產。
    `ApiConfig.financialBackfillReserve = 200` 就是為此存在。）
    ⚠️ `otcFinancialLimitForBudget` 仍留在 `update_service.dart:1025`，但
    **已無 production 呼叫者**，只剩測試與一則過期註解引用——別照它推論行為。
    回填佇列設計上每輪都選得出全新的 stale 股，**重跑不會變便宜**
  - `MarketDataUpdater` 除當日籌碼外含**當沖/融資缺漏日回補**（TWSE ~21:00 才發布，早更新錯過的日子掃 40 天窗補回），以及**全市場外資持股**（2026-08-16，`syncAllMarketShareholding` / `backfillForeignShareholding`，走 MI_QFIIS——同樣是免費、全市場的那一類，加它是為了修 FOREIGN_* 規則在 TWSE/TPEx 之間 4 倍的觸發不對稱）。（**per-source 斷路器 + 逐市場門檻 + 價格表當停市 ground truth**，設計取捨見 `ApiConfig.tradingBackfill*` 註解）
  - `InstitutionalSyncer` **非破壞式** force：force 只對當日繞快取，歷史回補日走 per-day 完整性檢查（已完整跳過、中斷可續傳）；全清僅由**口徑版本檢核**（`ensureDataVersion`，bump `DataFreshness.institutionalDataVersion` 觸發一次性遷移）承接，且遷移由 **pending marker** 驅動（`isDeepBackfillPending` / `markDeepBackfillComplete`）——被限流打斷的那輪下次會**接續**，不會靜默退回 15 天淺窗；回補逐日 `onProgress` 回報
- **3 Helpers**: `BatchDataBuilder`（建構外資/董監等評分資料 Map，含衍生欄位）、`BatchDataLoader`（從 DB 平行載入評分批次資料 → `ScoringBatchData`）、`CandidateSelector`（選出評分候選；流動性下限＝20 日中位成交值 ≥ 3,000 萬 NTD，**套用於市場候選／熱門股／其餘可分析股票三者**，僅自選股豁免）
- **跨 syncer 配額**：`ApiBudgetTracker`（per-vendor、sliding 1hr；FinMind free tier
  600/hr 是唯一實際 bottleneck）。狀態經 `ApiBudgetStore` 持久化，**兩條路徑用不同實作**：
  Flutter 走 `SharedPrefsApiBudgetStore`，**launchd CLI 走 `FileApiBudgetStore`**（純 Dart 檔案）——
  因為 shared_preferences 是 flutter plugin，import 進去會把 `dart:ui` 拉進 tool 的純 Dart 鏈。
  **跨 app 重啟延續**——純記憶體時重啟即歸零，但 FinMind 伺服器端的額度不會忘記
  （2026-07-27 實測：重啟後本地計數 42/600、伺服器直接回 402）。
  **`restore()` 必須被 await，不可 fire-and-forget**：建構與 `checkBudget` 都是同步的，
  讓載入與呼叫賽跑會讓早期呼叫看到空狀態。掛在 `main.dart` 與 headless runner 起始；
  回傳 `(restoredCalls, cooldownVendors)` 供記錄，沒有這個回報就無法從日誌驗證它生效。
  **收尾 `flush()` 同樣必要**：自動存檔每 10 次呼叫才觸發一次，run 結束不 flush 會丟掉尾端
  ≤9 次記帳。**遺失方向是放寬不是保守**——少記 → 下輪超發 → 402，正是持久化要防的那件事。
  儲存失敗一律 fail-open 回「無歷史」
- **Post-Update**: `RuleAccuracyService` 在更新後 fail-safe 聚合 per-rule 命中率統計（caller 仍 await，但錯誤不會中斷更新；從 `daily_reason` 聚合寫 `rule_accuracy`，供個股詳情規則表現顯示。**不是 unbiased 統計**——lookahead / survivorship / zero-price 已修，但 **co-occurrence inflation 仍未修**，且樣本被限縮在**訊號層**——`_computeUnbiasedRuleStats` 明確再篩一次 `scoreShort ≥ minScoreThreshold` 或 `scoreLong ≥ minScoreThreshold`（**12**），把觀察區 8–11 排除掉。（`daily_reason` 的落庫門檻確實是 `observationScoreThreshold` = 8，但那是持久化下限，**不是取樣邊界**。）所以它量到的是「已上榜股票上的規則表現」。逐項揭露見 `rule_accuracy_service.dart` class doc）；`ThesisMonitorService` 同模式檢查釘選論點失效（timeStop 單條件，全量重算冪等）；`TrailingMaAlertService` 同模式重算均線階梯提醒（每檔自選股恰好一筆，依現價落在 5／20／60MA 的哪一階決定提醒方向與價位，**只讀寫 `managed_by = TRAILING_MA` 的列**，使用者手動設的提醒一列不動）。**刻意不做成可選注入**——其餘 fail-safe service 為 null 時整段靜默跳過，而本專案有「自動更新靜默斷 13 天」的前科
- **另兩個 post-update 觀測元件**（圖上有、先前文字漏列）：`NewsMentionSnapshotService`
  每次回補最近 N 個本地日的提及數快照——**窗內全量覆寫**（先刪 `[from, to]` 再寫重算
  結果）而非 upsert，**唯一例外是新聞來源整段為空時 early return 且不碰 DB**——空陣列視為讀取失敗的保守訊號，否則一次抓取失敗就會清空整個窗；`ZeroingImpactReporter` 每日輸出負證據歸零的三個數，讓「歸零有沒有
  生效、量級多大」每天可從 log 驗證（2026-07-29 三態 lookup 的配套觀測）
