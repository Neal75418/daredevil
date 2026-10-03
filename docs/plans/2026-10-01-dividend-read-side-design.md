# 股利資料第 3 段：讀取端改用除權除息配發表 — 設計

> **狀態（2026-10-03）**：設計定案（已經對抗式審查修訂），待拆實作計畫。

## 背景

股利資料專案分三段。前兩段已完成：

- **第 1 段**：新表 `dividend_distribution`（一次除權息一列，PK `(symbol, ex_date)`，存每股現金股利與每千股無償配股），
  解析 TWSE TWT49U／TWT49UDetail 與 TPEx exDailyQ。
- **第 2 段**：每輪更新步驟 6.6 同步本月，並以剩餘呼叫份額由新到舊回補過去 5 個完整年度；
  修復工具 `tool/backfill_dividend_distributions.dart` 可一次補完。上市權／權息列逐筆以列表的
  「減除股利參考價」核對明細（明細配股只顯示到小數 1 位，以 ±0.1 股推區間）。
  逐月完成紀錄 `dividend_month_ledger`、失敗紀錄 `dividend_month_failure`。

macOS DB（2026-10-03）：兩市場各 69 個月（2021-01～2026-09）全部完成、失敗紀錄 0 筆；配發表 10,515 列
（有配股 940 列、只有現金增資的 0/0 列 505 列）。

讀取端仍在讀舊表 `dividend_history`，它不可信（2026-10-03 macOS DB）：

- PK `(symbol, year)`：一年多次配息只留一期
- 3,557 列中 3,543 列沒有除息日；2021–2024 年合計只有 30 列
- `year` 語意混用（宣告年度與發放年度）
- 配股與官方不符：2025-06～09 上市有配股的列中，26 筆兩表不一致；以官方「減除股利參考價」
  仲裁，新表 26/26 吻合、舊表 0/26

## 目標與成功標準

- 讀股利的地方全部改用 `dividend_distribution`，移除 `dividend_history` 與 FinMind 股利路徑
- 資料不完整時（手機回補期間、同步失敗、卡住的列、缺價格欄位）一律顯示「建置中」或不觸發，**不顯示錯的數字**
- 52 週新高／新低依交易所的除權息參考價還原（含現金股利、配股、現金增資），第一次真正生效
- 提交 52 週規則改動前，在 DB 副本量測新舊差異並經同意

## 非目標

| 項目 | 理由 |
|:--|:--|
| 均線、RSI 等其他指標改用還原價 | 牽動所有規則與評分門檻，另案；本段只提供共用還原函式 |
| 大盤「52 週新高／新低家數」（`market_overview_dao`）改用還原價 | 全市場逐檔還原放在 SQL 成本高，另案；除息旺季會高估新低家數 |
| 價格提醒的 52 週類型（`AlertEvaluationService`） | 目前沒有使用中的 52 週提醒（2026-10-03：只有高於 6 筆、低於 40 筆）；需要時重用還原函式 |
| WEEK_52 分數重新校準 | 現有分數在舊語意下校準，校準資料庫沒有股利資料；3-2 之後另案 |
| `rateLimitedAbort` 改為分 vendor | FinMind 限流會連帶跳過步驟 6.6；2026-08-08 以後未再發生，另案 |
| 上櫃估值改為全市場寫入 | 唯一用途是投資組合（0 筆持倉）；全市場寫入有外鍵整批失敗風險，且會改變上櫃候選股估值的新鮮度、翻轉門檻附近的規則 |
| 取得上市（櫃）日期、面額 | 年度平均的起算規則不需要上市日期；面額以名稱是否帶 `*` 判斷 |
| 高殖利率規則套用到 ETF | 門檻依一般股票訂定 |
| 手機專屬的回補加速 | 目前只用桌機；手機只要求不顯示錯的數字 |

## 讀取端現況（2026-10-03 盤點）

| 讀者 | 讀什麼 | 問題 |
|:--|:--|:--|
| 52 週新高／新低規則（`indicator_rules.dart` 的 `_sumDividendsInPeriod`） | 窗內現金股利總額，從極值扣掉 | 除息日幾乎全空，扣除額實際為 0（近 90 天 1,323 筆 evidence 中只有 1 筆非 0）；不分極值在除息前或後都扣；不處理配股與現金增資 |
| 個股頁股利表（`StockFundamentalsLoader._loadDividendHistory` → `DividendTable`） | 依 `year` 取 5 列 | DB 沒資料時打 FinMind 並背景寫回舊表；股利清單為空時頁首顯示「部分基本面資料暫無法取得（股利）」 |
| 投資組合（`DividendIntelligenceService`） | 預估年股利、近兩年趨勢 | 依舊表 `year`；目前 0 筆持倉 |
| 個股頁殖利率卡、高殖利率規則 | 官方估值 `stock_valuation.dividend_yield` | 不需改；ETF 沒有官方估值 |

寫入端：`DividendSyncer.sync()` 以 TWSE `getDeclaredDividends()`（t187ap45_L）與 TPEx t187ap39_O 寫舊表；
**同一個 TWSE 回應也是上市股東會日期的唯一來源**（2026-10-03：上市 525 筆、上櫃 943 筆 SHAREHOLDER_MEETING）。
個股頁 FinMind 回退也寫舊表。行事曆的除權息事件來自 TWT48U 預告（`stock_event`），與舊表無關。

評分建構 `StockData` 有兩條路徑：評分 isolate（`scoring_isolate.dart`）與 isolate 失敗時的主執行緒回退
（`ScoringService`）。

## 設計

### 1. 配發表補存前收盤價與除權息參考價

- `dividend_distribution` 新增兩欄（nullable）：`close_before`（除權息前收盤價）、`reference_price`
  （除權息參考價：交易所訂的除權息後參考價，含現金增資的影響）。以 `beforeOpen` 的 `_ensure*Column`
  （`ALTER TABLE ADD COLUMN`）補上，不 bump schema fingerprint
- 兩市場的列表都有這兩欄（TWSE TWT49U、TPEx exDailyQ）；所有列（息、權、權息、只有現金增資）都存，缺值存 null；
  0 或負值也存 null（還原因子是兩者相除，0 會讓因子變成 0 或無限大）。例外是要查明細的上市權／權息列（尚未在庫，
  或修復工具 `--recheck`）：前收盤 ≤ 0 時明細核對推不出正的參考價，列表的減除股利參考價大於 0.01 就判為不符，
  整列不寫入（`--recheck` 時連舊列一起刪）、記為 `REFERENCE_MISMATCH`，讀取端不論要不要價格都判為不完整
- 本月同步與回補寫入時一併存；上市已查過明細的列（DB 已有）也以列表的值更新這兩欄（不重查明細、不動金額）
- **補齊既有資料**：完成紀錄新增 `prices_recorded`（既有紀錄補進來為 false），回補的完成判定要求它為 true。
  舊紀錄的月份因此重開一次，重做只需 1 次列表呼叫（明細已在庫、不重查）；完成時寫 true，之後不再重開——
  即使列表本身缺值（那些列的兩欄仍為 null，由讀取端的完整度條件 4 處理），也不會每輪重開白打 API。
  macOS 全部 138 個單位約 138 次呼叫，可由修復工具一次補完（約 7 分鐘，副本彩排、備份、經同意後執行）；
  手機由每輪回補自動補齊
- 2026-10-03 以兩市場 2021–2026 全部列表實測：13,393 列兩欄皆無缺值；596 列「除權息參考價」低於「減除股利參考價」
  （現金增資的影響）；5 列參考價高於前收盤（認購價高於市價），因子可大於 1

### 2. 完整度事實

讀取端判斷「某檔在某段期間的除權除息資料是否完整」，需要兩個事實，**所有月份（含本月）統一記錄**：

- **列表已同步到哪一天**：新表 `dividend_listing`，PK `(market, year, month)`，欄位 `listed_through`（日期）
- **未解決的列**：新表 `dividend_unresolved`，PK `(market, symbol, ex_date)`，欄位 `reason`、`recorded_at`（這次判定的時間；
  交易第一句必須是寫入，整批取代時無法先讀出舊列保留首次出現時間，故只記一個）。
  列表上有、但不在 `dividend_distribution` 的列。`reason`：`pendingDetail`（尚未查明細，例如預算用完）、
  `detailFailed`、`referenceMismatch`、`notInMaster`（列表當時不在股票主檔）。`symbol` 不加外鍵

兩張表以 `beforeOpen` 的 `Migrator.createTable` 補建，不 bump schema fingerprint、不加進 `_userInputTableNames`
（fingerprint reset 時與 `dividend_distribution` 一起清空）。

**有效列表日**＝`max(dividend_listing.listed_through, 該月有完成紀錄時的月底)`。完成紀錄本身就代表「整月列過且
已知列全部在庫」，所以不需要初始化種資料；只寫完成紀錄的舊版程式（例如 3-1 之前的 CLI）寫下的完成也算數，
兩者不會分歧。

**寫入規則**（本月同步 `DividendSyncer.syncDistributions` 與歷史回補 `DividendBackfiller` 共用）：

- 某市場某範圍的**列表成功後**，無論後續明細是否中斷（預算用完、網路、限流），都寫入事實：
  更新範圍內各月的 `listed_through`，並以該範圍的現況**整批取代**未解決的列
- **`listed_through` 的值**：回補為該月月底；本月同步為該輪更新的資料日（不是牆鐘的今天——凌晨補跑時
  資料日是前一個交易日，不可多宣稱一天）
- **`listed_through` 只能連續前進**：某月的列表範圍起點若晚於「現有有效列表日的隔天」（且不是該月 1 日），
  代表中間有一段沒列過，不前進。例：10/1 本月同步的範圍是 9/24～10/1，9 月只有在有效列表日 ≥ 9/23 時才前進；
  本月同步的範圍必定從本月 1 日開始，所以這條只作用在上個月的尾巴
- **未解決的列在交易內由 DB 現況推導**：列表上的列 − 範圍內已存在 `dividend_distribution` 的 key，
  再依記憶體中的已知原因標 `reason`（未知者為 `pendingDetail`）。「不在未解決清單＝資料在庫」是交易當下
  查核的事實，不由呼叫端回推
- 事實的寫入自成一個交易；失敗時保留舊值（保守方向：讀取端視為未列過）。本月同步照現行記進 errors、不往外拋；
  回補照現行往外拋
- 列表本身失敗：不動事實
- `dividend_coverage.dart` 給第 3 段的註解中「失敗紀錄的 failedSymbols 可據此判斷其餘都在庫」不成立
  （回補因預算用完中斷時，未查的列不在 failedSymbols），改以事實表為準並改正註解

### 3. 完整度讀取模型 `DividendCompleteness`（`lib/domain/services/dividend_completeness.dart`）

`isComplete(symbol, from, to, requirePrices:)`——**不帶市場參數，兩個市場都查**（配發表沒有市場欄；上櫃轉上市的代號在期間內
會出現在兩個市場的列表；`stock_master` 的市場在轉板當天可能還沒更新）。為真的條件：

1. 與 `[from, to]` 重疊的每個月，**兩個市場**的有效列表日都 `≥ min(to, 該月月底)`
2. `dividend_unresolved` 沒有該 `symbol`、`ex_date ∈ [from, to]` 的列（任一市場）
3. 與 `[from, to]` 重疊、有完成紀錄的月份，`symbol` 不在任一市場的 `skipped_symbols`
   （當時不在主檔、之後才進主檔的代號；回補會依現行規則重開該月並取代事實）
4. `requirePrices` 時，該 `symbol` 在 `[from, to]` 內的配發列都有 `close_before` 與 `reference_price`。
   用到價格的讀取端（第 4 節還原、第 6 節 ETF 殖利率）傳 true；只看金額的（股利表的年度狀態、投資組合趨勢）傳
   false——缺價格不影響金額，不該讓它顯示建置中。參數必填，避免還原漏傳

否則為「建置中」。回補範圍（今年往前 5 年的 1 月）以前的期間一律為「建置中」。

**顯示用的終點**＝`min(今天, 兩個市場最新的連續有效列表日)`，畫面標「截至 M/D」。不用「今天」為終點：每天凌晨到
第一輪更新之間、沒跑更新的週末假日，不應讓所有股票都變成「建置中」。

### 4. 共用還原函式 `DividendAdjuster`

純函式：輸入升冪價格序列（`List<DailyPriceEntry>`）與該檔事件（含只有現金增資的 0/0 列），輸出同型別的還原後序列。

- 每個事件的還原因子＝`reference_price ÷ close_before`（交易所自己的除權息調整比例，涵蓋現金股利、配股、現金增資）
- 日期 `d` 的 OHLC 乘上所有 `d < ex_date ≤ 評分日` 事件的因子（除息當天的價格已是除息後，不調整；評分日之後的事件
  不得套用，避免換日回退時的前視）
- 呼叫端只在 `requirePrices: true` 的完整度為真時呼叫（條件 4 保證每個事件都有兩欄）
- DAO 新增讀取「含 0/0 列、含兩欄」的事件查詢；既有給畫面的查詢仍濾掉 0/0 列

對純現金股利與配股，因子與第 2 段核對用的公式在除權息前收盤處一致；差別在於它也涵蓋現金增資
（2025-08-29 以來 105 次只有現金增資的除權中，除權當天跌幅大於 3% 的有 34 次、大於 12% 的有 2 次：3149、4130）。

本段只有 52 週規則使用；放在 `domain/services/`，供日後其他指標採用。

### 5. 52 週新高／新低規則

- 窗內價格先經 `DividendAdjuster` 還原，再取極值（排除今日，與現行相同）
- 以下情況**不觸發**：
  - `DividendCompleteness.isComplete(symbol, 窗口首日, 評分日, requirePrices: true)` 為假
  - 還原後序列仍有水位斷點：`contiguousSuffix()` 回傳的長度短於整段（門檻 `RuleParams.priceDiscontinuityRatio`）。
    剩下的是減資、分割、面額變更等不在 TWT49U 的事件（2025-08-29 以來非除權息日的 >12% 跳動 111 筆、71 檔，
    例 5904 面額變更、2321、6949）
- **新低的空頭過濾**（`close < MA20 < MA60`）改用同一條還原後收盤計算 MA20／MA60，不再用未還原的 `context.indicators`
- evidence 保留既有欄位：`week52High`／`week52Low` 為原始極值、`adjustedHigh`／`adjustedLow` 為還原後極值、
  `dividendAdjustment` 為兩者差
- **資料傳遞**：`StockData` 新增**必填**的 `DividendContext`（`incomplete` 或 `complete(events)`，不以 null 表示），
  事件與完整度放進 `ScoringBatchData`，由 `BatchDataLoader` 在主 isolate 讀好；isolate 與主執行緒回退
  **兩條建構路徑都改**，取代 `dividendHistoryMap`
- **觀測**：每輪記一行「52 週：完整度不足 N 檔、斷點 M 檔」，停發不會靜默
- `price_continuity.dart` 與 `analysis_coordinator_service.dart` 中「52 週規則本來就正確處理除息」的註解改正

### 6. 股利摘要 `DividendSummary`

依除息日年份彙總（欄名「除息年度」，與「股利所屬年度」區分）：

- **金額**：現金加總；配股——名稱不帶 `*` 的股票以「元」顯示（每千股配股 ÷ 100），合計＝現金＋股票（台股慣例，
  面額 10 元）；名稱帶 `*`（面額非 10 元，2026-10-03 在市 46 檔、其中 9 檔有配股）顯示「每千股 X 股」、合計顯示「—」
- **次數**：只數有現金的除權息（同一年息與權分兩天除，不算兩次）

每個年度的狀態：

| 狀態 | 條件 | 顯示 |
|:--|:--|:--|
| 有配發 | 完整且有事件 | 金額；多次配息時標次數 |
| 無除權息 | 完整、沒有事件，且在第一次除權息之後 | 「無除權息」，計入平均為 0 |
| 無除權息紀錄 | 完整、沒有事件，且在第一次除權息之前（可能尚未上市） | 「無除權息紀錄」，不計入平均 |
| 建置中 | 不完整 | 「建置中」 |
| 今年 | 本年度至顯示終點 | 標「截至 M/D」；尚無事件顯示「尚未除息」；不完整顯示「建置中」 |

- **平均**：從第一次有除權息的完整年度起算到去年；不足 5 年標示「YYYY 起 N 年平均」。**前 5 個完整年度中任一年
  建置中，平均顯示「建置中」**（此時無法判定第一次除權息在哪一年，也無法排除建置中的年度其實是 0）
- **ETF 近一年殖利率**（`StockPatterns.isEtfCode`）＝`Σ(現金ᵢ ÷ close_beforeᵢ)`，事件取以最近一次除息日為終點、
  其前 350 天內（含）者。逐次以當時的前收盤正規化，不受分割影響（0050 於 2025-06-18 分割：2025-07～2026-01 若以
  總額 ÷ 現價計算約 6%，實際約 2%）
  - 最近一次除息早於顯示終點 400 天以上：「近一年無配息」
  - 完整度窗口：有事件時 `[最近除息日 − 350 天, 顯示終點]`；沒有事件時 `[顯示終點 − 400 天, 顯示終點]`；
    `requirePrices: true`，不完整為「建置中」
  - 窗口依據（2026-10-01 macOS DB，54 檔 2024–2025 固定頻率 ETF，2025-01～2026-09 逐日回測配息次數）：
    350 天誤差 0.05%（1 檔年配 ETF 15 天）；355 天 0.98%、365 天 28%；以今天為終點最好也有 1.74%。
    固定年配相鄰間隔 352–377 天；在市 ETF 最近除息超過 400 天者 3 檔（0054、00742、00920），均已停止配息

### 7. 讀取端

- **個股頁股利表**：今年＋前 5 個完整年度共 6 列與平均列，依第 6 節顯示；資料只讀 DB，不再打 FinMind。
  新增「股利資料建置中」狀態與文案；`missingParts` 不再因股利清單為空而加入「股利」（`hasSomeData` 一併調整），
  避免頁首紅字錯誤與無效的重試
- **個股頁殖利率卡**：一般股票照舊（官方）；ETF 顯示「近一年殖利率」
- **投資組合**：預估年股利——有官方估值者＝官方殖利率 × 同一天收盤價；其餘（ETF、無估值）＝近一年殖利率 × 最新收盤價。
  趨勢——最近兩個完整年度的**現金**合計比較（不受面額影響），任一年建置中則不顯示趨勢

### 8. 移除

讀取端全部改完後才移除：

- **`dividend_history` 表**：加入 `_ensureRetiredSchemaDropped`（`DROP TABLE IF EXISTS`），不 bump fingerprint。
  **前提：GUI 已重編到 3-3 以後的版本**——舊版 GUI 仍讀寫舊表（DROP 後會拋 `no such table`；2026-10-03 使用中的
  GUI 是 2026-09-27 的 Debug build，早於所有股利 commit）
- 索引：`legacyRedundantIndexes` 與 `index_hygiene_test.dart` 的 `legacyDdl` 一併移除 `idx_dividend_history_symbol`
  （兩者由不變量測試要求相等）
- DAO：`getDividendHistory`、`getDividendHistoryBatch`、`insertDividendData`
- `DividendSyncer.sync()`：移除股利寫入與上櫃 t187ap39_O 呼叫；**保留** TWSE `getDeclaredDividends()`，只取上市股東會日期；
  調整 `DividendSyncResult` 與 `UpdateService` 的日誌
- 個股頁 FinMind 股利回退；`FinMindClient.getDividends` 與 `FinMindDividend`（若已無其他使用者）
- `AnalysisParams.dividendLookbackYears`、`StockData.dividendHistory` 與評分 DTO 的舊欄位
- `test/tools/scoring_snapshot.dart`（不在全套測試內）改讀新事件
- 過時的註解與文件：`price_continuity.dart`、`analysis_coordinator_service.dart`、`event_tables.dart`、`market_data_tables.dart`、
  `event_repository.dart`、`exright_preannouncement.dart`、`dividend_coverage.dart`、`tool/check_db_range.dart`、
  `tool/backfill.dart`、`tool/replay_calibrator.dart`、`docs/RULE_ENGINE.md`
- `.claude/rules/update-pipeline.md` 與資料保留期計畫：「三張表同生共死／保留規則一致」改為**五張**
  （distribution、ledger、failure、listing、unresolved），保留期政策表移除 `dividend_history`
- CHANGELOG：各段的變更，並更正既有條目中「52 週規則已處理除息」的宣稱

## 已知限制

- **分割、面額變更**不在 TWT49U：個股頁各年金額照當時每股金額，跨分割的年度平均會混用股數（例 0050）；
  ETF 殖利率以逐次比例計算不受影響；52 週由價格歷史內的斷點偵測擋下
- 其他指標（均線、RSI 等）與 52 週新低以外的規則仍用未還原價格（非目標）
- 有效列表日以「當輪資料日」記錄；若交易所某日的列表晚於當日更新才公布當日事件，該日的事件會在下一輪的 7 天重疊
  範圍內補進，期間依第 2 節規則以未解決或缺列呈現

## 分段與順序

| 段 | 內容 | 使用者可見變化 |
|:--|:--|:--|
| 3-1 | 配發表補兩欄（兩市場寫入、缺欄月份重開補價）＋兩張事實表與寫入＋`DividendCompleteness` | 無。提交後 macOS 以修復工具補價（約 7 分鐘，彩排、備份、同意後執行） |
| 3-2 | `DividendAdjuster`＋52 週規則改寫（含新低過濾的均線、兩條評分路徑、觀測日誌） | 52 週訊號改變；**量測後經同意才提交** |
| 3-3 | `DividendSummary`＋個股頁股利表、ETF 殖利率卡、投資組合 | 個股頁（**GUI 需重編才看得到**） |
| 3-4 | 第 8 節的移除 | 無；**前提：GUI 已重編到 3-3 以後** |

每段可獨立運作：讀取端換完才移除舊表。CLI 由 post-commit hook 自動重編；GUI 需手動重編。

## 驗證

每段：先寫失敗測試、`dart format`、`flutter analyze`、全套 `flutter test`、update 鏈純 Dart 編譯
（`dart compile kernel`）、mutation（每個新增條件逐一拔掉，跑所有消費者測試）、程式審查與複審。

- **3-1**：兩欄補建、reset 時五張表一起清空；兩市場 parser 存兩欄（含息列、0/0 列、缺值）；缺欄月份被重開且只打列表；
  事實寫入的交易一致性、列表成功後明細中斷仍寫、連續性規則、資料日而非牆鐘、有效列表日由完成紀錄推導（模擬只寫
  完成紀錄的舊版）；完整度四條件各自的正反例與跨市場反例（轉板代號）
- **3-2**：還原因子對照交易所實例（純現金、配股 6669、現金增資 3149）；斷點與不完整時不觸發；評分日之後的事件不套用；
  isolate 與回退兩條路徑結果一致（補一筆「還原後才觸發」的資料）；sendability 測試放 `DividendContext` 真實例。
  **量測**：擴充 `test/tools/scoring_snapshot.dart`（已對齊 production 的價格窗），在 DB 副本逐日回放最近約 62 個交易日，
  母體＝通過候選分類的全部股票（不只 `daily_analysis` 內者），只跑新舊兩版 52 週規則、事件只取 `ex_date ≤ 當日`，
  舊版與 `daily_reason` 對帳，列出消失與新增的訊號並各舉實例；註明完整度用的是現況。經同意才提交
  （2026-10-03 粗估：近 55 個交易日落庫的新低 461 筆中約 227 筆會消失、新高約新增 213 筆）
- **3-3**：年度狀態表各情況、平均建置中、`*` 股票的顯示、次數只數現金、ETF 350／400 天邊界與分割（0050）案例、
  「建置中」不出現頁首紅字錯誤
- **3-4**：移除後全專案無殘留引用（含 `test/tools/`、`tool/`、`docs/`、`.claude/`）；索引清單與測試同步；
  既有 DB 開啟後舊表被移除、其他資料不變；上市股東會事件數不減
