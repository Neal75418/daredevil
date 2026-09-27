# CLAUDE.md

本檔案為 Claude Code 提供專案開發指引。專題知識按需載入自 `.claude/rules/`（只在碰到對應路徑時載入，細節放那裡，這裡只留每次都用得到的）。

---

## 專案概述

**Daredevil** — 本地優先盤後台股掃描 App（Flutter / Dart 3）。所有運算在裝置端完成，無雲端依賴。

> **命名邊界（2026-08-07 由 AfterClose 更名）**：對外名稱、repo、Dart package 皆為 `daredevil`；
> 但 **bundle ID 仍是 `com.neo.afterclose`、DB 檔名仍是 `afterclose.sqlite`**——它們決定 macOS 容器路徑（`~/Library/Containers/com.neo.afterclose/Data/Documents/`），改動等同 App 換家、既有資料庫（數十萬列價格）會看似清空。
> **除非做容器遷移，否則不要動這兩個字串**；文件裡出現它們是實體事實，不是漏改。打包／通知相關陷阱見 `.claude/rules/macos-packaging.md`。

---

## 常用指令

| 動作                                                   | 指令                                                                                                            |
|:-------------------------------------------------------|:----------------------------------------------------------------------------------------------------------------|
| 測試／靜態檢查                                         | `flutter test`；`flutter analyze`（全專案、info 也擋；CI 與 pre-commit 同）                                     |
| Drift 改表（`tables/` 或 `@DriftDatabase` 清單）後重產 | `dart run build_runner build --delete-conflicting-outputs`（DAO mixin 不需要；`*.drift.dart` 有版控，一起提交） |
| 安裝 git hooks                                         | `./scripts/install-hooks.sh`                                                                                    |
| launchd CLI 重編                                       | `ops/launchd/install.sh --cli-only`（只換 binary）；不帶參數則含 plist 安裝                                     |
| update 鏈純 Dart 終驗                                  | `dart compile kernel tool/daily_update.dart -o build/daily_update.dill`（預設輸出落在 `tool/`、未被 gitignore） |
| 年度休市日核對                                         | `dart run tool/check_twse_holidays.dart <西元年>`                                                               |

---

## 關鍵路徑

| 路徑                                             | 說明                                                                                                                                                             |
|:-------------------------------------------------|:-----------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `lib/core/constants/rule_params.dart`            | 規則參數 barrel（8 domain param 檔 + enums + scores）                                                                                                            |
| `lib/core/constants/analysis_params.dart`        | 分析摘要 + 交易成本參數                                                                                                                                          |
| `lib/core/exceptions/app_exception.dart`         | 例外階層 (sealed class)                                                                                                                                          |
| `lib/core/utils/request_deduplicator.dart`       | Request Deduplication 機制                                                                                                                                       |
| `lib/domain/services/rules/`                     | 規則（15 檔；權威數量與清單見 `RuleRegistry.defaultRules`）                                                                                                      |
| `lib/domain/services/scoring_isolate.dart`       | Isolate 評分（typed DTO 跨界；設計取捨與 sendability 說明見檔內註解）                                                                                            |
| `lib/domain/services/update/`                    | 更新元件（syncer／updater／helpers／定案重抓；清單與行為見 `.claude/rules/update-pipeline.md`）；**coordinator `UpdateService` 在上一層 `lib/domain/services/`** |
| `lib/data/database/tables/`                      | Drift 資料表定義                                                                                                                                                 |
| `lib/data/database/dao/batch_query_mixin.dart`   | 批次查詢共享工具 (groupBySymbol)                                                                                                                                 |
| `lib/domain/services/rule_accuracy_service.dart` | 推薦績效回測引擎 (多週期驗證)                                                                                                                                    |
| `lib/domain/services/thesis/`                    | 釘選論點失效（timeStop；hardStop/trendBreak 被 gate 砍）                                                                                                         |
| `lib/core/theme/semantic_colors.dart`            | 色彩語意分類（紅綠專屬股價，見守門測試）                                                                                                                         |
| `lib/core/theme/color_contrast.dart`             | WCAG 對比度／色相／疊色計算——**色彩守門測試專用公式庫**（執行期生產碼不 import；留在 lib/ 是為與色彩宣告同住、供未來生產消費者直接取用）                         |
| `lib/domain/services/price_continuity.dart`      | 價格水位斷點偵測（除權息／減資／分割）——套在 `calculateTechnicalIndicators` 內，**刻意不放價格入口**（那會踩到 52 週等下游長度閘，取捨見檔頭）                   |

---

## 開發工作流程

### Git Hooks

**版控在 `scripts/`，用 `./scripts/install-hooks.sh` 安裝**（只放 `.git/hooks/` 就是未版控、換機消失——本專案已為此吃過兩次虧）。

`pre-commit`：
1. **補做 CLI 重編** — 若上次 post-commit 留下 `.git/cli-rebuild-pending` 就同步補上（失敗則擋下 commit）
2. **Auto-format** — 格式化 staged `.dart` 檔案並重新 stage
3. **Analyze** — `flutter analyze`（全專案、info 也擋；CI 同）

`post-commit`：動到 `lib/`、`bin/`、`tool/`、`ops/launchd/`、`pubspec` 時**背景重編 launchd 的 CLI 產物**（`install.sh --cli-only`，約 9s）。

> **🚨 為什麼需要它**：launchd 跑的是 **AOT 編譯產物**，不是 source。產物落後時**三個訊號全部正常**（exit code 0、`update_run` 記 SUCCESS、日誌無異常），2026-08-15 實測落後 3 天才靠檔案時間戳撞見。編譯閉包涵蓋整個 `lib/`，**任何規則／評分／syncer 改動都算**，別靠人工判斷「算不算重大」。
> 佐證：兩支 CLI 每次執行印 `[build=<sha> compiled=<time>]`（`lib/core/utils/build_stamp.dart` 讀 bundle 根的 `BUILD_INFO`，由 `install.sh` 寫入、dirty 會標記）。hook 只在本機正常 commit 路徑有效；rebase／cherry-pick／換機時，**日誌那行 SHA 是唯一能事後驗證的證據**。

### 測試

覆蓋率目標 Domain／Data 85%、Presentation 70%（Codecov 回報，未強制）。測試慣例見 `test/CLAUDE.md`。

---

## 編碼標準

### 速查

| 原則                      | 規範                                                      |
|:--------------------------|:----------------------------------------------------------|
| **Request Deduplication** | Repository 層使用 `RequestDeduplicator` 避免重複 API 呼叫 |
| **狀態管理**              | `AsyncNotifier` / `StateNotifier`，避免 `StateProvider`   |
| **Rule Engine**           | 純函數：輸入 `AnalysisContext` → 輸出 `TriggeredReason`   |
| **配置集中**              | 所有閾值放 `lib/core/constants/`，禁止魔術數字            |
| **路由**                  | 使用 `AppRoutes` 常數，禁止硬編碼路由字串                 |
| **OHLCV 提取**            | 使用 `prices.extractOhlcv()` extension，避免重複迴圈      |
| **Dart 3**                | Records, Pattern Matching, Sealed Classes                 |

### Repository Pattern

Data 層提供實作；`domain/repositories/` 介面**只保留有真消費者的**（lib 內以介面型別使用，或供 `tool/backfill` 測試注入）——新增介面前先確認有第二個實作或注入需求，單實作勿加儀式介面。

### 錯誤處理

`RateLimitException` / `NetworkException` 必須 rethrow，其餘包裝為 `DatabaseException`。
例外：`UpdateService`（頂層 orchestrator）改以 `rateLimitedAbort` 旗標 + `recordError` 終止流程，不再往上拋

### Isolate 通訊

使用 typed DTO（`ShareholdingData`、`WarningDataContext`、`InsiderDataContext`），避免 `Map<String, dynamic>`；input 欄位不得混入 closure／ReceivePort 等不可傳型別。
**可跨界性由真 spawn 的 sendability 測試把關**（`scoring_watchlist_zero_reason_test`，各元素型別須放真實例——sendability 走 runtime 物件圖，空集合驗不到）。static 是 per-isolate 的：主 isolate 設的 `AppLogger.forceOutput` 不會帶進 worker，曾讓 AOT CLI 中規則／評分的 warning／error 全部靜默；要跨 isolate 生效的 static 設定須在 `Isolate.run` closure 內重設（見 `scoring_isolate.dart` 的 `evaluateStocksInIsolate` 註解）。

### 🚨 launchd 排程

兩支 CLI 的 plist **版控在 `ops/launchd/`**，安裝／更新一律跑 `ops/launchd/install.sh`（會把樣板路徑換成本機實際值再 bootstrap）。
**不要只改 `~/Library/LaunchAgents/` 的副本**——那是本機產物，repo 搬家或換機就靜默失效（本專案有過自動更新靜默斷 13 天的前科）。
日誌輪替**由 CLI 自己做**（`LogRotation`，1 MB 就地截斷）——刻意不用 newsyslog，那要在 `/etc` 放未版控、換機消失的設定檔。

### 🚨 tool 鏈純 Dart

`tool/daily_update.dart`、`tool/intraday_alert_check.dart`（launchd 執行的是 `bin/` 同名 wrapper 編出的 AOT 產物，實作留在 `tool/`）的 import 閉包**不得**含 flutter／easy_localization／flutter plugins（shared_preferences 等）——混入即編譯失敗且**靜默斷自動更新**（2026-07 斷 13 天才發現）。
守門：`test/tool/tool_chain_pure_dart_test.dart`；改動 update 鏈後跑 `dart compile kernel tool/daily_update.dart -o build/daily_update.dill` 終驗。
`@visibleForTesting` 用 `package:meta`，i18n 格式化用 presentation 專用 `LocalizedNumberFormat`。
`dart run tool/...` 每次都會跑 build hook（需網路，曾卡 lock 20 分鐘以上）；手動跑工具前先確認沒有其他 `dart run`／`flutter test`／`flutter run` 行程。

---

## 按需載入的規則（`.claude/rules/`）

| 規則檔               | 內容                                                             | 載入條件（`paths:` frontmatter）                                                                                        |
|----------------------|------------------------------------------------------------------|-------------------------------------------------------------------------------------------------------------------------|
| `architecture.md`    | **實際** import 方向（非理想分層）、三條讀取路徑                 | `lib/core/**`、`lib/data/**`、`lib/domain/**`、`lib/presentation/**`、`lib/app/**`、`lib/main.dart`                     |
| `update-pipeline.md` | Update Pipeline Mermaid 圖、syncers + helpers 詳解               | `lib/domain/services/update/**`、`lib/data/remote/**`、`**/syncer*`、`**/Syncer*`、`**/BatchData*`、`**/rule_accuracy*` |
| `macos-packaging.md` | 舊 bundle 同 ID 陷阱與清法、通知授權測試方式、CLI 重編免 bootout | `macos/**`、`build/**`、`ops/launchd/**`、`notification_service.dart`、`notification_provider.dart`                     |
