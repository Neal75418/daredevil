# 出場層：釘選論點失效追蹤 — Design Spec

> ⚠️ **§2 的三個失效條件只有 timeStop 上線。**
> hardStop（-8%）與 trendBreak（跌破 MA60）經 replay gate 81,989 樣本驗證
> **全年全 mode 為負，不上線**（結果見 `2026-07-12-exit-gate-report.md`）。
> 本文以下仍以三條件描述設計，讀時請自行扣除那兩條——`ThesisInvalidationRules`
> 與 `PinnedThesis.invalidationReason` 的實際值域只有 timeStop。

> 評分改進 #3（八項中最後一項）。App 只有進場推薦、沒有出場紀律——
> 損益大半由出場決定。本設計把「推薦」升級為可追蹤的「論點」：
> 釘選 → 每日檢查失效條件 → 失效進警示頁。
>
> **狀態**：Design 定案（2026-07-11，三輪問答收斂 + 自審 6 項 +
> 對抗性審查 16 項全數摺入）。
> 實作順序：**先 replay gate 驗證出場條件有 edge，才寫 app 端**。

---

## 1. 需求收斂（使用者決策紀錄）

| 決策點 | 定案 | 理由 |
|---|---|---|
| 偵測對象 | **釘選推薦**（pinned thesis） | Neal 不在 app 記持倉；自選股缺進場論點快照，失效無從定義。釘選 = 論點快照 + 紙上驗證跟單紀律 |
| 失效條件 | **通用三條起步** | 可回測、可解釋；per-mode 客製留 v2 |
| 提醒方式 | **接警示頁** | 盤後節奏 = 更新後看一輪，不需推播 |

## 2. 失效條件（先過 gate 才上線）

以「參考價」= 釘選資料日收盤（**僅供顯示與條件基準**，不代表可成交價）：

1. **hardStop** — 收盤 < 參考價 × (1 − `ExitParams.hardStopPct` 8%)
2. **trendBreak** — 收盤 < MA60（regime 證據最強的趨勢線）
3. **timeStop** — 釘選後滿 `ExitParams.timeStopTradingDays` 40 個**交易日**
   （以該股價格列數計，非日曆差），且**從未**收高於參考價
   （語意 = 論點從未實現；rolling「連續 N 日未創 peak」版留 v2 由 gate 評估）

**邊界規則（2026-07-11 對抗性審查補完）**：
- **同日 tie-break**：多條件同日為真時優先序 HARD_STOP > TREND_BREAK >
  TIME_STOP（`ExitParams` 常數，單元測試覆蓋同日 tie case）。
- **MA60 資料不足**（釘選日前不足 60 根，新上市）：trendBreak **不判定**
  （視為未觸發），只跑 hardStop/timeStop——比照 `MarketStage.insufficient`
  語意。
- **停牌不計入 timeStop**（刻意決策）：以價格列數計數，停牌期間倒數凍結。
  已知限制：長停股會滯留 ACTIVE，v1 以「已下市/停牌 UI 提示」補償（§6）。
- **基準分離**：觸發判斷永遠用 referencePrice（T0 收盤）；gate 的報酬計算
  永遠用模擬進場價（T+1 收盤）——兩者不可互換。

先觸發者（跨日）定 `invalidatedReason`；參數起始值由 replay gate 結果最終定案。

**紀律語意（寫死）**：
- 一旦 INVALIDATED **不自動復活**——價格回升不翻回 ACTIVE。重新看多請
  重新釘選（新記錄、新參考價）。
- 同一 symbol 同時只允許一筆 ACTIVE。

## 3. Replay gate（tool/exit_validate.dart，實作前置）

- **樣本**：既有 replay 基礎設施的 mode 主訊號 firing 日。
- **進場模擬**：**訊號日次一交易日收盤**（盤後 app 買不到訊號日收盤——
  與 calibration look-ahead 修正同一原則）。
- **對照**：「條件出場（出場後 0 報酬）」vs「持有滿 60 交易日」同窗總報酬。
- **指標**：平均超額報酬差、勝率、最大回檔、平均持有天數。
- **報告切面**：**按 mode 分組**（Mode A 剛突破離 MA60 近，trendBreak 可能
  過敏，不可一刀切）+ **逐年拆**（穩定性，防全期挑參數過擬合——tilt 教訓）。
- **統計嚴謹度**：每個 (mode × 年) cell 樣本 < 30 者標灰不計入結論
  （沿用 calibration `sampleSizeCutThreshold` 慣例）；上線需**逐年方向
  一致**（多數年份同向），不接受單年暴衝拉平均——tilt 過擬合教訓。
- **Survivorship 揭露**：60 日窗內無 exit price（下市/長停）的樣本比照
  `RuleAccuracyService._BiasCounters` 模式計數並印進報告，不靜默跳過。
- **漲跌停 flag**：釘選日或觸發日為漲/跌停的樣本在報告中標記
  （用既有 `price_limit.dart` 判斷），v1 只觀察不特殊處理。
- **方法論限制（報告必附）**：出場後以 0% 報酬計＝不含資金再部署效益，
  gate 系統性低估出場紀律的實務價值——「沒 edge」應解讀為「單筆訊號品質
  無差異」，不等於「紀律沒用」。
- **上線標準**：某條件出場版平均超額 ≥ 持有版，或最大回檔顯著改善且報酬
  不明顯犧牲。沒 edge 的條件不進 app；參數被打臉就修或砍。跑一次認帳。

## 4. 資料模型

新表 `pinned_thesis`（Drift）：

| 欄位 | 型別 | 說明 |
|---|---|---|
| id | int PK | autoIncrement |
| symbol | text FK stock_master | |
| pinnedDate | datetime | **快照資料日**（dataDate，非點擊時刻） |
| referencePrice | real | 釘選資料日收盤 |
| mode | text | 釘選當下路由 mode（momentum/strength/pullback） |
| triggeredRules | text JSON | 當日觸發規則碼快照 |
| scoreShort / scoreLong | real | 分數快照 |
| status | text | ACTIVE / INVALIDATED / ARCHIVED |
| invalidatedDate | datetime? | |
| invalidatedReason | text? | HARD_STOP / TREND_BREAK / TIME_STOP |
| lastCheckedDate | datetime? | monitor 每次跑必更新（staleness 顯示用） |
| createdAt / updatedAt | datetime | updatedAt **僅於 status 實際變更時**更新 |

**不存 peak/增量狀態**：monitor 每次跑對每筆 ACTIVE 從 pinnedDate
**全量重算**三條件（釘選數 × ≤250 收盤，量極小）——冪等，App 跳幾天
不更新也不會錯。

**INVALIDATED 凍結**：monitor 只掃 `status = ACTIVE`——已失效者被排除於
重算之外，`invalidatedDate/reason` 一經寫入即凍結（回填修史也不會動它），
「不復活」由此在程式層面獲得保障。

**一 symbol 一 ACTIVE**：app/service 層 enforcement（insert 前查
`status = ACTIVE` 是否已存在），不做 partial unique index（單使用者
單寫入路徑，SQLite 層約束過度工程）；此檢查需測試覆蓋。

## 5. 偵測服務（方案 A：更新管線整合）

- `ThesisInvalidationRules`（純函數）：輸入 (thesis, **含釘選日前 ≥60 根**
  的收盤序列)——trendBreak 對每個評估日需要該日往前 60 根算 MA60；
  逐日檢查、首個觸發日即失效日 → `InvalidationResult?`（reason + 觸發日）。
- `ThesisMonitorService`：每日更新完成後 fail-safe 執行（與
  `RuleAccuracyService` post-update 同模式；錯誤不中斷更新流程）。
  逐筆 ACTIVE 檢查 → 失效者更新 status/invalidatedDate/reason。
- 常數集中 `lib/core/constants/exit_params.dart`（`ExitParams`）。

被否決的替代方案：Provider 端即時計算（無歷史、警示頁無從顯示）、
併入 scoring isolate（使用者資料不進批次評分、耦合過重）。

## 6. UI

- **釘選入口**：今日頁推薦卡片 + 個股詳情 header 的 📌 按鈕
  （已有 ACTIVE 釘選 → 顯示已釘選狀態，不可重複）。
- **釘選追蹤區**：今日頁下方新 section——卡片顯示釘選日、參考價 vs
  現價、狀態徽章（ACTIVE 綠 / INVALIDATED 紅 + reason）。
- **警示頁**：新「論點失效」section，讀 `status = INVALIDATED` 的釘選
  （不動 PriceAlert 表——那是使用者自訂價格提醒，語意不同）。
- **封存**：失效卡片一鍵 ARCHIVED（保留紀錄、離開警示頁）。
- **取消釘選**：ACTIVE 卡片提供次要操作「取消」＝物理刪除（誤觸/改變
  心意情境，不需審計軌跡；與失效紀律流程分離——「INVALIDATED 不復活」
  不等於「ACTIVE 不能反悔」）。
- **現價來源**：`daily_price` 該股最新 close（明定，不走 daily_analysis）。
- **Staleness / 下市提示**：卡片顯示「最後檢查 {lastCheckedDate}」；
  `stock_master.isActive = false`（下市/長停）的 ACTIVE 釘選顯示
  「已下市，價格未更新」警示——現價凍結在最後一筆，不得誤讀為健康追蹤。
- **triggeredRules 快照 v1 不顯示**：保留給後續「當初為什麼釘選」回溯
  功能（v1.5+），非漏刻。

## 7. 測試

全程 TDD：失效規則純函數單元測試（三條件邊界 + 交易日計數）、
ThesisMonitorService in-memory DB 測試（冪等、fail-safe、不復活）、
UI widget 測試（釘選鈕狀態、追蹤卡、警示 section）、exit_validate
比照 tool 測試慣例（synthetic 序列驗證出場模擬數學）。

## 8. 實作順序

1. `tool/exit_validate.dart` + gate 報告 → **Neal 核可條件與參數**
2. 表 + migration + `ExitParams`（gate 定案值）
3. `ThesisInvalidationRules` + `ThesisMonitorService`
4. UI（釘選鈕 → 追蹤區 → 警示 section）
5. 文件同步（CLAUDE.md 關鍵路徑 / update-pipeline.md）

## 9. 風險

- Gate 可能判「全部條件都沒 edge」——有效結論：只上「狀態追蹤不出訊號」
  的釘選功能（保留快照與紙上驗證價值），出場條件不上。
- Mode A 樣本若 trendBreak 過敏，per-mode 門檻提前到 v1.5 而非 v2。
