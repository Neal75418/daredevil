# 資料保留期 — 設計

> **狀態（2026-09-26）：暫緩實作。** 必要性是從 Mac 資料推估的（手機每年約增加 970 MB），
> 要先量測手機上 App 實際佔用空間與成長速度再決定；計畫已可直接執行，屆時先重新核對文中的程式碼位置與行號。

## 背景

App DB（macOS）666 MB。空間集中在三張表，且索引與資料各佔一半左右（2026-09-26 以 `dbstat` 量測）：

| 表 | 資料 | 索引 | 合計 | 資料期間 | 每年成長（估） |
|:--|--:|--:|--:|:--|--:|
| financial_data | 114.5 MB | 195.5 MB | 310 MB | 2024-09 ~ 2026-06（8 季、155 種項目） | ~155 MB |
| daily_price | 54.2 MB | 64.6 MB | 119 MB | 2025-06-10 ~ 2026-09-24 | ~90 MB |
| holding_distribution | 29.1 MB | 44.4 MB | 73.5 MB | 12 週 | ~320 MB |

問題是成長速度而非現況：照現行方式，手機 DB 每年增加約 970 MB（全部表合計；上表三張約 565 MB，其餘為訊號、法人、融資、當沖、估值、外資持股等）。而多數資料沒有讀者：
financial_data 107 萬列中只有約 8.6% 屬於有人讀的項目；holding_distribution 的讀者只看最新一週。

每張表的讀者與回看範圍已逐一盤點（見「附錄：讀者盤點」）。

## 目標與成功標準

- 手機 DB 穩定在約 390 MB（依實測換算，見「預估效果」），不再隨時間無上限成長
- 任何規則、畫面、補抓機制、釘選論點都不因清理而失去它需要的歷史（每張表的保留期 ≥ 盤點出的最長回看＋餘裕）
- macOS 保留完整歷史（回測、校準、回補工具只在 Mac 執行；holding_distribution 官方不給歷史、上櫃當沖是花 API 額度回補的，刪了就拿不回來）
- 每張 DB 表都有明確宣告的保留規則，新增表格若沒宣告，測試失敗

## 非目標

- 不改任何讀者的回看範圍
- 不處理新聞「重大訊息」的保留矛盾（註解寫永久累積、實際 30 天被 `cleanupOldNews` 清掉）——另案
- 不做雲端備份或匯出
- 不盤點冗餘索引（索引約佔一半空間）——另案

## 保留模式

| 模式 | 預設平台 | 原則 |
|:--|:--|:--|
| 研究模式 | macOS | 時間序列全部保留；只清「任何平台都用不到」的資料（`trading_warning` 已失效舊列、`update_run` 舊紀錄） |
| 精簡模式 | iOS、Android | 只留功能需要的資料 |

模式是注入的參數（`RetentionMode`），不是清理邏輯內部讀平台：

- 平台判斷只存在一個函式 `RetentionMode.forCurrentPlatform()`（`Platform.isMacOS` → 研究，其餘 → 精簡），只在組裝點呼叫：`UpdateServiceFactory.build`、`providers.dart` 建 repository 處、`tool/backfill.dart`
- 所有接收模式的建構子參數都是**必填、無預設值**：預設值若是 `forCurrentPlatform()`，測試在本機 Mac 與 CI ubuntu 會跑出不同結果
- 清理與過濾本身只看傳入的模式，兩種模式在任何機器上都能測
- 預載快照由 Mac 以精簡模式產生，也靠這個注入點
- 不提供使用者設定

## 各表保留規則

| 表 | 精簡模式 | 研究模式 | 依據（讀者盤點） |
|:--|:--|:--|:--|
| financial_data | 見「財報」 | 全部 | ROE 8 個點剛好用滿 12 季；少於 5 季觸發重抓 |
| holding_distribution | 每檔各自最新 2 期 | 全部 | 讀者只看最新一期（個股用該檔自己的最新期）；官方不給歷史 |
| daily_price | 460 天，另見「例外」 | 全部 | 規則與 Phase 0 補抓下限 400 天＋60 天餘裕 |
| daily_reason | 365 天 | 全部 | 命中率讀全部；見「規則命中率」 |
| daily_analysis | 365 天 | 全部 | 同上 |
| market_index | 400 天 | 全部 | syncer 要求最舊一筆早於 now−370，否則回補 |
| insider_holding | 430 天 | 全部 | 個股詳情「12 個月」從起始月 1 日算，最長約 396 天 |
| daily_institutional | 200 天 | 全部 | 最長 180 天（大盤連買賣） |
| shareholding | 120 天 | 全部 | 最長 90 天（個股籌碼） |
| margin_trading | 90 天 | 全部 | 最長 65 天（大盤融資） |
| day_trading | 60 天 | 全部 | 少於 40 天會被缺漏偵測判為缺漏而重抓 |
| stock_valuation | 60 天 | 全部 | 最長 30 天 |
| trading_warning | 刪 `is_active = 0` 且超過 30 天 | 同左 | 籌碼異動查 30 天內的處置股（不看 is_active） |
| update_run | 最近 200 筆 | 同左 | 畫面只顯示 30 筆 |
| news_item | 外部管理 | 外部管理 | 既有 `cleanupOldNews`（30 天、欄位為 `published_at`），本案不動、通用清理不碰 |
| 其餘表 | 不清 | 不清 | 讀全部歷史（monthly_revenue 歷史最高營收、portfolio_transaction、stock_event、pinned_thesis）、無讀者但刻意保留（news_mention_daily）、非時間序列或很小 |

### 日期與邊界

- 期限以「日曆天、相對於執行當下」計算；邊界當天保留（刪 `日期 < 今天 − N 天`）
- 比較一律用台北日曆日：欄位取 `date(欄位, '+8 hours')`、門檻為台北時區的 `YYYY-MM-DD`。
  SQLite 先依字尾轉成 UTC 再加 8 小時，`' +08:00'`、`+08:00`、`Z` 三種寫法都得到正確的台北日；`substr(欄位, 1, 10)` 對 `Z` 字尾會差一天，不採用

### 例外：不因期限刪除的列

1. **每檔的最新一筆**：以 symbol 為單位的天數型表（daily_price、stock_valuation、day_trading、margin_trading、shareholding、daily_institutional、insider_holding），每檔最新一筆一律保留。
   「取最新一筆」的讀者（`getLatestPricesBatch`、`valuation_dao.dart:36`、個股頁 `getRecentPrices`）不限日期，長期停牌股的最後資料不能因期限消失。
   holding_distribution 以「每檔各自最新 2 期」達到同樣效果。
   daily_reason／daily_analysis 不在此列：`pinned_thesis_provider.dart:93` 取該檔最新一筆分析，超過 365 天沒被分析的股票無法釘選論點。這是刻意的：沒有近一年分析就沒有可釘選的依據
2. **ACTIVE 釘選論點**：daily_price 對有 ACTIVE 論點的股票，保留從最早 pinnedDate 起的價格。
   `ThesisMonitorService` 讀 pinnedDate 起的全部價格判斷「曾站上參考價」；論點一旦站上就永不觸發 timeStop、可無限期 ACTIVE。
   刪掉早期價格會把它重新判成未站上 → 誤判失效，而且失效不可逆。INVALIDATED 論點與 UI 只讀最新價，不需保護
3. **事件當天價格**：daily_price 中與 stock_event 同一檔、同一台北日的列保留（目前 1,778 筆事件）。
   事件詳情以 `getPriceOnDate` 精確比對事件日（`event_detail_sheet.dart:58`、`price_dao.dart:72`），stock_event 全保留，價格被清就會靜默隱藏價格區塊

長期停牌股保留最新一筆後，個股頁的漲跌（需要 2 筆）會顯示不出來；影響可忽略，不另外處理。

### 財報（精簡模式）

允許項目：`EPS`、`IncomeAfterTaxes`、`Revenue`、`GrossProfit`、`OperatingIncome`（INCOME）、`Equity`、`TotalAssets`（BALANCE）。
前 6 種有讀者；`TotalAssets` 目前 `lib/` 無讀者，但解析器註解列為使用中，保守保留。

規則以「一檔、一種報表、一季」為一組，寫入過濾與事後清理用**同一條規則**（寫入端是 Dart 函數、事後清理是 SQL——手機上無法把整張表讀進 Dart 判斷；兩者由等價測試綁住：「精簡模式從頭寫入」必須等於「全寫後跑事後清理」）：

- 組內有任何允許項目 → 只留允許項目
- 組內沒有任何允許項目 → 整組保留。
  金融股（2801、2812、2820、2834、2836、2838、2845、2849、2897、5876）的損益表用 `IncomeAfterTax`（單數）等不同名稱，2026Q1、Q2 沒有任何允許項目（實測 20 組）。
  INCOME 的新鮮度檢查（`fundamental_syncer.dart:484-503`、`fundamental_repository.dart:586-591`）只看「該季有沒有任一列」，整組濾光會讓它每輪都重抓 FinMind。整組保留每季每檔約 11 列，量可忽略。
  BALANCE 目前沒有空組（每組都有 Equity），規則照樣適用；其新鮮度檢查是「季數 ≥ 5」（`market_data_repository.dart:171-190`），14 季滿足
- 每檔、每種報表保留自己最新的 14 季（以該檔自己的季別排序，不是全市場同一個截止日）：ROE 8 個點需 12 季，加 2 季緩衝

## 規則命中率

`rule_accuracy_service` 讀全部 `daily_reason`／`daily_analysis`，並從訊號日往後讀 `daily_price` 算報酬。

- 精簡模式下訊號歷史保留 365 天，命中率變成近一年的樣本。訊號是手機每日評分自行產生的（不從外部抓），手機本來就只有安裝後的歷史；限期只是讓第二年起不再無上限成長
- 價格保留期 460 天 ≥ 訊號 365 天，訊號日起的價格都在；460 天的實際下限來自規則與補抓的 400 天
- 命中率說明顯示實際樣本（既有 `rule_accuracy.distinct_dates`＝觸發日數），兩種模式都依實際資料，不寫死「近一年」
- `rule_accuracy_service.dart:461` 的註解「distinct_dates 會隨天數單調成長」在精簡模式下不再成立，一併更正

## 元件

### 1. `DataRetentionPolicy`（`lib/core/constants/`）

每張 DB 表一筆宣告：`keepAll`、`days(n)`、`latestPeriodsPerSymbol(n)`、`custom`（financial_data、trading_warning、update_run）、`external`（news_item，由既有清理管理、通用清理不碰），分精簡、研究兩欄。
財報允許項目清單、季數、每批筆數與時間預算也放這裡。每筆宣告旁註明依據（file:line）。

### 2. 財報寫入過濾（精簡模式）

`financial_data` 寫入前套用「財報」的判斷函數：沒人讀的項目不寫入。研究模式照舊全寫。

過濾放在三條寫入路徑共同經過的 `insertFinancialData`（模式由呼叫端傳入），不是只加在其中一條：

- `fundamental_repository.dart:622`（FinMind INCOME）
- `market_data_repository.dart:210`（FinMind BALANCE）
- `market_data_repository.dart:110`（官方全市場 BALANCE）

BALANCE 佔 financial_data 的 80%，只過濾 INCOME 等於大宗照寫、再靠事後清理刪。

### 3. `DataRetentionService`（`lib/domain/services/`）

- 建構時注入 `RetentionMode`
- 依政策逐表刪除過期資料（含財報事後清理，既有 DB 的非允許項目由此清掉），回傳各表刪除筆數與「是否做完」
- **分批＋時間預算**：每批以 rowid 為界刪固定筆數、各自一個交易；每批前檢查已用時間，超過預算就停，下一輪從剩下的繼續（清理是冪等的）。
  手機第一次清理是大量刪除，背景任務時間很短，不能一次做完
- 掛在 `UpdateService` 步驟 10+ fail-safe 後處理的最後一步、`_finishUpdate` 之前（失敗才反映在 update_run 狀態）；捕捉例外後 `recordError`，不 rethrow
- CLI、App、背景更新都走 `UpdateService`，一併涵蓋。非交易日 `UpdateService` 提早結束（`update_service.dart:288-297`），清理也不跑；資料只在交易日成長，不影響穩態，未做完的部分下個交易日接續
- 刪除筆數寫入日誌；有刪除或未做完時附在更新摘要

### 4. 磁碟空間回收

SQLite 刪除資料不會縮小檔案；空頁會被後續寫入重用。

- **新建 DB**：`auto_vacuum` 必須在第一張表建立前、切 WAL 前設定才生效。放 `onCreate` 會因 setup 已先切 WAL 而靜默變成 0。
  - App 與 CLI 的連線 setup 抽成**一個共用的頂層函式**，順序統一為 `busy_timeout` → `auto_vacuum` → `journal_mode = WAL`。目前兩邊順序不同：App 的 `busy_timeout` 在 WAL 之後（`app_database_flutter.dart:40-41`），CLI 在之前（`app_database.dart:187-188`）
  - **只在全新空檔（`PRAGMA page_count` 為 0）才設定 `auto_vacuum`**，不是每次開啟都設。
    DB 已是 INCREMENTAL 時，設定這個 pragma 會開寫入交易；另一個程序（launchd CLI 盤中每 5 分鐘寫入）正持有寫鎖時，會回 `database is locked`，App 開不了 DB（實測重現）
- **清理後**：`PRAGMA incremental_vacuum(N)` 分批釋放空頁、受同一個時間預算管制，再 `PRAGMA wal_checkpoint(TRUNCATE)`，否則 WAL 模式下檔案不會變小。checkpoint 遇 BUSY 視為下輪再做，不算失敗
- **既有 Mac DB**（目前 `auto_vacuum = 0`）：`tool/vacuum_db.dart` 切換為 INCREMENTAL 並完整 VACUUM。
  - 執行前必須停掉 launchd 兩支 CLI 並關閉 App
  - 工具先以 `lsof` 檢查 DB 檔（含 `-wal`、`-shm`）是否被其他程序開著，有就中止並列出程序，不硬做（工具只在 Mac 執行）。
    WAL 模式下，閒置連線不持有鎖：`BEGIN EXCLUSIVE` 與 `locking_mode = EXCLUSIVE` 加寫入都照樣成功（實測），不能用鎖判斷
- **既有手機 DB**：不自動完整 VACUUM（需約兩倍暫存空間、耗時、可能被系統中止）。
  清理後檔案停在歷史最高水位但不再成長；要縮檔只能刪除 App 資料重新同步

### 5. 守門測試

從 `AppDatabase.allTables` 列舉所有表，斷言每張表在 `DataRetentionPolicy` 都有宣告（含 `keepAll`）。新增表格若忘了決定保留期，測試失敗；清單由 DB 推導，不需人工維護。

## 與預載快照的關係

預載快照由 Mac 以注入的精簡模式清理後產生，手機拿到的資料與它日後自行清理後的樣子一致。
`VACUUM INTO` 產出的 `auto_vacuum` 取決於產生快照那條連線上的設定值，不是來源檔（實測：來源為 0、連線先設 INCREMENTAL，產出為 INCREMENTAL）。快照工具必須明確設定並驗證產出為 INCREMENTAL。快照本身另案設計。

## 預估效果

精簡模式穩態約 390 MB。以 2026-09-26 各表實測大小（含索引）÷ 實際交易日數，換算成保留期內的交易日數（日曆天 × 250/365）：

| 表 | 精簡模式 |
|:--|--:|
| daily_price（460 天） | ~117 MB |
| daily_reason＋daily_analysis（365 天） | ~109 MB |
| financial_data（14 季） | ~47 MB |
| daily_institutional（200 天） | ~39 MB |
| margin_trading（90 天） | ~18 MB |
| shareholding（120 天） | ~13 MB |
| holding_distribution（2 期） | ~12 MB |
| day_trading（60 天） | ~11 MB |
| stock_valuation（60 天） | ~8 MB |
| 其餘（insider_holding、news_item、market_index 等） | ~16 MB |
| **合計** | **~390 MB** |

- 訊號歷史目前只累積 51 個交易日（22 MB），365 天的數字是依每日成長換算的穩態
- 當沖列數在 2026-06 起暴增（每月約 3 萬列），以近 60 天實際列數計算
- 財報目前只有 8 季（實保留 9.2 萬列、約 27 MB），14 季為換算後的穩態
- 現況每年約增加 970 MB；精簡模式下總量不再隨時間成長
- 研究模式：時間序列持續累積（刻意保留）

## 測試

所有清理測試用注入的模式跑兩組，不依賴執行測試的機器。

- 每張天數型表：邊界當天保留、前一天刪除；日期字串為 `' +08:00'`、`Z` 字尾時都以台北日曆日判斷（`Z` 字尾的 16:00 屬於台北隔天）
- 每檔最新一筆：超過期限的唯一一筆不被刪
- holding_distribution：最新期早於全市場最新期的股票，仍保留它自己的最新 2 期
- ACTIVE 論點：pinnedDate 早於 460 天時，該檔 pinnedDate 起的價格保留、pinnedDate 前的照刪；INVALIDATED 論點不受保護
- 事件當天價格：超過 460 天的事件日價格保留，同檔前後日照刪
- 財報：允許項目過濾、整組無允許項目時整組保留（金融股樣本）、每檔各自 14 季（不同檔最新季別不同）；寫入過濾與事後清理結果一致
- 財報寫入過濾：三條寫入路徑（FinMind INCOME、FinMind BALANCE、官方 BALANCE）在精簡模式下都只寫允許項目
- news_item：通用清理不下任何 SQL
- 財報新鮮度：金融股在精簡模式寫入後，下一輪不再重抓
- `trading_warning`：只刪「已失效且超過 30 天」；仍生效的舊列保留
- `update_run`：保留最近 200 筆
- 分批與時間預算：預算用完即停並回報「未做完」，下一輪接著刪完
- `DataRetentionService` 失敗不中斷更新，且記入 `recordError`
- 守門：每張表都有政策宣告（附下限，避免列舉失敗時空轉通過）
- `auto_vacuum`：以**檔案 DB 呼叫共用的 setup 函式**建立，斷言為 INCREMENTAL（記憶體 DB 或跳過 setup 的測試會假綠）；清理後檔案實際變小
- setup 對既有 DB 不寫入：對已是 INCREMENTAL、且另一連線持有寫鎖的檔案 DB 執行 setup，不拋 `database is locked`
- 每個新增條件做 mutation 驗收

## 風險

- **保留期估算錯誤會靜默縮小資料**：每個期限都依盤點出的讀者回看再加餘裕，並在政策宣告旁註明依據（file:line）；日後讀者延長回看時，需同步更新政策——在守門測試旁寫明
- **補抓迴圈**：保留期短於補抓下限會造成「清掉 → 隔天重抓」的迴圈。日價 460 > 400、當沖 60 > 40、大盤指數 400 > 370、法人 200 > 90、融資 90 > 40、財報 14 季 > 5 季，皆高於下限；財報整組濾光的情況由「整組保留」處理
- **新的「讀全部歷史」讀者**：像論點監控這種從某日讀到今天的讀者，新增時若沒同步加例外會靜默出錯。政策檔頭列出現有例外與理由
- **既有 DB 不會變小**：Mac 要 user 執行 `tool/vacuum_db.dart`；手機只能重裝

## 附錄：讀者盤點（摘要）

| 表 | 最長回看 | 來源 |
|:--|:--|:--|
| daily_price | 400 天（規則、Phase 0 補抓）；52 週高低日曆窗 504 天、但只需 200 筆（460 天約 315 個交易日）；ACTIVE 論點從 pinnedDate 起；事件日精確比對；各處取最新一筆 | `rule_params.dart:49`、`historical_price_syncer.dart:220`、`market_overview_dao.dart:636`、`thesis_monitor_service.dart:27`、`price_dao.dart:72` |
| daily_institutional | 180 天 | `market_overview_dao.dart:401` |
| daily_analysis／daily_reason | 全部（命中率） | `rule_accuracy_service.dart:132/146` |
| shareholding | 90 天 | `data_freshness.dart:197` |
| day_trading | 補抓下限 40 天 | `api_config.dart:223` |
| financial_data | 12 季（ROE 8 點）；重抓下限 5 季 | `financial_data_dao.dart:164-263`、`api_config.dart:72` |
| holding_distribution | 最新一期（個股：該檔自己的最新期；批次：全市場最新期） | `holding_distribution_dao.dart:9-26`、`:48` |
| stock_valuation | 30 天；取最新一筆 | `data_freshness.dart:204`、`valuation_dao.dart:36` |
| margin_trading | 65 天 | `market_overview_dao.dart:478` |
| trading_warning | 30 天（處置股，不看 is_active） | `chip_scoring_params.dart:266` |
| insider_holding | 12 個月，從起始月 1 日算（約 396 天） | `insider_repository.dart:41`、`stock_chip_loader.dart:45` |
| market_index | 390 天（下限 370） | `market_index_syncer.dart:206-219` |
| monthly_revenue | 全部（歷史最高營收） | `revenue_dao.dart:322-337` |
| update_run | 最近 30 筆 | `update_history_provider.dart:19` |
