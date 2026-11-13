# 即時報價的資料時間與收盤後背景收集 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 證交所回舊快照時價格不倒退、快照停住過久才提示「報價延遲」（A）；收盤後 App 看不見（macOS）也把收盤報價收完，熱力圖整張圖在背景一路換到底（B）。

**Architecture:** 快照時刻從 MIS 回應解析進每一檔 `IntradayQuote`；`LiveQuoteBook.apply` 依快照時刻與每列 `t` 決定換或擋，並記每檔「最近一次收到」；頁首規則用它算延遲。報價中心的計時器在 macOS 看不見時不停，「這一拍能不能抓」在 `_step` 判斷；熱力圖的登記清單改由 provider 經 `LiveQuoteScope.listen` 交給報價中心，不靠畫面重畫。

**Tech Stack:** Flutter／Dart 3、Riverpod 3（flutter_riverpod 3.3.1，`pubspec.lock` 鎖定的版本）、fakeAsync、mocktail。

**Spec:** `docs/plans/2026-11-09-mis-quote-freshness-design.md`（以下稱 spec；A1～A5、B1～B3 指 spec 的小節）。

## Global Constraints

- 請求規則不改：每分鐘最多 8 個、相鄰至少 2 秒、避開 CLI（每 5 分鐘整點後 10 秒內不送）、批次 35 檔、收盤後每檔滿 1 分鐘才重抓、有回應而不是收盤報價試滿 10 次放棄。
- 常數放 `LiveQuoteParams`：`snapshotFutureTolerance = Duration(seconds: 60)`、`delayActiveWindow = Duration(minutes: 2)`、`delayThreshold = Duration(minutes: 3)`。
- 頁首文案：zh-TW「報價延遲（證交所資料停在 {time}）」、en "Quotes delayed (exchange data as of {time})"，key `liveQuote.delayed`。
- 不繞過證交所快取；`_` 參數保留。盤中提醒（CLI 與 App 內）不改。
- 背景收集只在 macOS：預設 `defaultTargetPlatform == TargetPlatform.macOS`，只經 `LiveQuoteCenter` 的建構參數注入；測試不改全域目標平台（`flutter test` 底下 `defaultTargetPlatform` 是 android，既有測試預設走非 macOS）。
- 測試的「現在」與快照時刻一律用注入的時鐘組（`test/CLAUDE.md`「時間」），改到的測試檔撥 +90 天要綠。
- 註解只寫現在式的「做什麼／為什麼」，不寫日期、審查編號、改動歷史、計畫段落。說明會因本計畫變不準的既有註解一併改（各 Task 的 Files 列出）。
- 提交：implementer 不 commit。每個 Task 的審查（`pr-review-toolkit:code-reviewer`，opus）Critical／Important 修完才進下一個 Task。**Task 4 審查過後停下，使用者說「提交」才提交 A**（`feat:`，含 spec 與本計畫）；B 從 Task 5 開始，Task 7 後同樣等「提交」。A、B 共用 `live_quote_provider.dart` 等檔，事後拆不乾淨，所以中途提交。工作樹裡 `docs/plans/2026-11-07-market-heatmap-2-plan.md` 的 11/9 收盤後紀錄與本計畫無關，不帶進 A、B（另以 `docs:` 提交，由使用者決定時機）。

## Review Focus

1. **時刻偏前或格式怪的快照**：一份 `sysTime` 比本機晚幾分鐘的回應不能讓那一檔停住；預期當成 null、照常換上（Task 2「偏前快照當 null、之後正常快照照常換上」）。
2. **剛閃過色的股票收到較舊快照**：`withoutFlash()` 漏帶新欄位時保護悄悄失效；預期不換、不閃（Task 2「閃色後的下一輪收到較舊快照」）。
3. **重新進入畫面、App 從背景回來、盤中途暫停交易、批次失敗**：手上的報價是自己沒抓或證交所沒給，不能說成「證交所資料停在」；在規則層級四者都是「最近一次收到在窗口外」（Task 3 暫停交易、批次失敗不寫「最近一次收到」兩條；Task 4「重新進入」一條）。
4. **看不見時斷線或被限流**：沒人看得到，不能重試到午夜；預期停到重新可見（Task 5 斷線、限流、可見時限流隨即看不見三條）。
5. **看不見跨過午夜**：前一天傍晚看過、之後一直被蓋住，隔天 13:30 要照樣替固定清單頁收（Task 5 登記日測試）。熱力圖跨午夜靠 `liveQuoteBoundaryProvider` 觸發重算，不另寫測試。

---

## A：資料時間（Task 1～4，完成後提交 A）

### Task 1: 解析快照時刻

**Files:**
- Modify: `lib/data/models/twse/intraday_quote.dart`（`IntradayQuote`、`parseResponse`）
- Modify: `lib/data/remote/intraday_quote_client.dart`（`_requestBatch` 的 `_` 參數說明）
- Test: `test/data/remote/intraday_quote_parsing_test.dart`；`test/data/remote/intraday_quote_client_test.dart`（只改說明文字）

**Interfaces:**
- Produces: `IntradayQuote.snapshotAt`（`DateTime?`，建構參數 `this.snapshotAt` 選填）；`static DateTime? IntradayQuote.parseSnapshotTime(Object? sysDate, Object? sysTime)`（公開純函式）。

- [ ] **Step 1: 寫會紅的測試**（`group('快照時刻')`）
  - 8/8 fixture（`test/fixtures/twse_mis_intraday.json`）：每一檔 `snapshotAt == DateTime(2026, 8, 8, 0, 54, 14)`，`date` 是 8/7。
  - 10/5 fixture（`twse_mis_intraday_limit_locked_20261005.json`，`queryTime` 只有 `sysDate`）：每一檔 `snapshotAt` 為 null。
  - `parseSnapshotTime`：`('20261109','13:30:05')` → `DateTime(2026,11,9,13,30,5)`；`(null,'13:30:05')`、`('20261109',null)`、`('2026119','13:30:05')`、`('20261330','13:30:05')`、`('20260230','13:30:05')`、`('20261109','24:00:00')`、`('20261109','13:60:00')`、`('20261109','13:30')` → null。
- [ ] **Step 2: 跑，確認紅**：`flutter test test/data/remote/intraday_quote_parsing_test.dart`。
- [ ] **Step 3: 實作**：`parseResponse` 讀 `json['queryTime']`（`Map` 才讀），算一次 `parseSnapshotTime(...)`，帶進每一檔。驗證：`sysDate` 8 位數字、`sysTime` 符合 `HH:mm:ss`；月 1–12、日以 `DateTime(y,m,d)` 組回後年月日相同、時 0–23、分秒 0–59。
- [ ] **Step 4: 改 `_` 參數說明**（client 與其測試）：快取以 `ex_ch` 字串為鍵，`_` 不同照樣回快取；參數保留（不確定它對中間層快取有沒有作用）。
- [ ] **Step 5: 跑**：`flutter test test/data/remote/ test/tool/tool_chain_pure_dart_test.dart` 綠（`intraday_quote.dart` 在盤中提醒 CLI 的 import 範圍內）；`flutter analyze` 沒有問題。

---

### Task 2: 記帳本：價格不倒退、最近一次收到、報價時間不往回

**Files:**
- Modify: `lib/domain/models/live_quote.dart`（`LiveQuoteEntry`）
- Modify: `lib/domain/services/live_quote/live_quote_book.dart`（含 `latestQuoteTime` 說明改成「今天換上去的各筆 `t` 的最大值，不往回」）
- Modify: `lib/core/constants/live_quote_params.dart`（Global Constraints 的三個常數）
- Test: `test/domain/services/live_quote/live_quote_book_test.dart`

**Interfaces:**
- Consumes: `IntradayQuote.snapshotAt`、`IntradayQuote.time`（Task 1）。
- Produces:
  - `LiveQuoteEntry.snapshotAt`（`DateTime?`）、`LiveQuoteEntry.rowTime`（`String?`，MIS 列的 `t`）；兩者選填建構參數，`withoutFlash()` 帶上。
  - `RoundOutcome apply(QuoteBatchReport report, {required Iterable<String> requested, required DateTime now, required bool afterClose, Map<String, DateTime> receivedAt = const {}})`
  - `Map<String, DateTime> get lastReceivedAt`（換日清空）
  - `({int applied, int rejected, int futureSnapshots, int missingSnapshots, DateTime? oldestSnapshot})? get lastApplyStats`：最近一次 `apply` 中，列日期是今天、要套用的那幾檔：總數（換上＋擋下）、擋下幾檔、快照時刻晚於「現在＋60 秒」而當成 null 的幾檔、快照時刻為 null（含當成 null 的）的幾檔、換上去的最舊快照時刻。

- [ ] **Step 1: 寫會紅的測試**（`group('快照時刻：不倒退')`；沿用檔內 `at()`／`row()`／`parseResponse` 的寫法，helper 加 `queryTime`（`sysDate`／`sysTime`）參數，日期用 `at()` 的那一天；每輪傳不同的 `now`，例如 10:00:05、10:00:20、10:00:35，`receivedAt` 用該輪 `now` 前幾秒）
  - 第 1 輪快照 10:00:00、價 100；第 2 輪快照 09:59:30、價 99、`t` 不比較新 → `entries` 價仍 100、`flash` null、`fetchedAt` 等於第 2 輪的 `now`（與第 1 輪不同）、`status` ok、`lastReceivedAt` 等於第 2 輪的 `receivedAt`、`lastApplyStats.rejected == 1`、回傳 `RoundOutcome.success`、`latestResponseHadToday` true。
  - 同上但第 2 輪那一列 `t` 嚴格晚於第 1 輪 → 換上 99。
  - 畫面那筆 `t` 是 `'9:9'`（無法解析）、新的快照較舊 → 擋下。
  - 快照時刻相等 → 換上。任一邊 null → 換上；換上 null 後 `entries[s].snapshotAt` 為 null。
  - 第 1 輪快照 10:01:30、`now` 10:00:20（晚於現在＋60 秒）→ 當 null：換上、`snapshotAt` 為 null、`futureSnapshots == 1`；第 2 輪快照 10:00:30 正常 → 換上。
  - 快照日期不是今天（前一天 13:30）→ 當 null（不計入 `futureSnapshots`）。
  - 閃色後的下一輪：第 1 輪快照 S1 價 100；第 2 輪 S2>S1、價 101（有 flash）；第 3 輪 S1 與 S2 之間、價 100.5 → 不換、`flash` null。另確認 `withoutFlash()` 保留 `snapshotAt`、`rowTime`。
  - 被擋下時不更新今天記到的成交價：第 1 輪快照 S2 有成交 101；第 2 輪快照 S1<S2 有成交 99（被擋）；第 3 輪快照 S3 只有五檔、無 `trade` → 顯示價走記憶，為 101。
  - 報價時間不往回：第 1 輪換上 `t`=10:00:05；第 2 輪被擋的那檔 `t`=09:59:40 → `latestQuoteTime` 仍 `10:00:05`。
  - 收盤後被擋下仍計一次嘗試：`now` 與快照都在 13:31～13:45（`afterClose: true`、畫面那筆不是收盤報價）→ 試滿 10 次後 `pendingAfterClose` 不含它。
  - `lastReceivedAt` 只記今天的報價：`receivedAt` 帶了某檔、但那檔列被丟掉（`quotes` 沒有）或日期不是今天 → 不記。
  - `rollDay` 之後 `lastReceivedAt` 為空、`latestQuoteTime` 為 null。
- [ ] **Step 2: 跑，確認紅**：`flutter test test/domain/services/live_quote/live_quote_book_test.dart`。
- [ ] **Step 3: 實作**：擋下條件照 spec A2 兩條。第 2 條另寫 `static bool _strictlyLater(String? a, String? b)`（兩邊都解析得出、`a > b` 才 true），**不動 `_later`**（`maxTime` 從 null 開始，靠 `_later` 在 `b` 為 null 時回 true）。換上時 `_display` 帶可信的 `snapshotAt`（或 null）與 `rowTime: q.time`。`_latestQuoteTime` 只取換上的檔、取 max。`lastApplyStats` 每次 `apply` 覆寫。
- [ ] **Step 4: 跑**：同上綠；既有 book 測試不改仍綠。
- [ ] **Step 5: 突變**（各一次要紅；用寫回原內容還原，不用 git checkout，`cmp` 確認）：拿掉第 2 條（`t` 較新）；`_strictlyLater` 換成 `_later`；拿掉「晚於現在＋60 秒」；拿掉「日期不是今天」；`withoutFlash` 漏帶 `snapshotAt`；擋下的那檔不寫 `_fetchedAt`；擋下的那檔不寫 `lastReceivedAt`；`latestQuoteTime` 改回本輪最大值。

---

### Task 3: 報價中心：每批收到時刻、公開最近一次收到、觀測

**Files:**
- Modify: `lib/presentation/providers/live_quote_provider.dart`（`LiveQuoteState`（含 `latestQuoteTime` 說明同 Task 2）、`_Round`、`_step`、`_finishRound`、`_publish`）
- Test: `test/presentation/providers/live_quote_provider_test.dart`（`_mis(rows, {DateTime? at})`：`at` 不為 null 時帶 `queryTime`（由 `at` 組 `sysDate`／`sysTime`），為 null 時不帶，供「快照時刻缺失」那條用；`_tradeEach` 傳它的 `now` 帶 `queryTime`；不從 `DeviceTime`／`DateTime.now()` 取）

**Interfaces:**
- Consumes: Task 2 的 `apply(... receivedAt:)`、`lastReceivedAt`、`lastApplyStats`。
- Produces: `LiveQuoteState.lastReceivedAt`（`Map<String, DateTime>`，預設空；說明：各檔最近一次拿到今天報價的那一批收到的時刻，取自報價中心的時鐘，換日清空）。

- [ ] **Step 1: 寫會紅的測試**（`_Harness`＋`_MisAdapter`／`_ScriptedClient`，比照檔內既有寫法）
  - 兩批的一輪：第 1 批在 T1 回來、第 2 批在 T2 回來 → 發布後 `lastReceivedAt[第1批的代號] == T1`、`[第2批] == T2`。
  - 不寫入的情況：App 停拍作廢的一輪（`_stopTicker` 設 `discarded`）與限流丟掉的一輪，已回來的批次都不寫；登記變更而截斷的一輪照既有規則套用已回來的批次，那些照寫。
  - 盤中途暫停交易：某檔前幾輪有報價，之後每輪列被丟掉 → `lastReceivedAt[那檔]` 停在最後有報價的那一批。
  - 批次失敗：某批網路錯誤 → 那批的代號 `lastReceivedAt` 不變。
  - 快照時刻缺失的 warning（以檔內 `crumbs` breadcrumb 擷取驗）：有回應的一輪，換上的檔快照時刻全為 null，連續三輪只記一次；中間一輪有快照時刻後再缺，再記一次。
  - 偏前快照的 warning：連續三輪 `futureSnapshots > 0` 只記一次。
  - 有回應但沒有今天報價的一輪（`applied == 0`）不記「快照時刻缺失」的 warning。
  - 既有「一段失敗只記兩筆」（`crumbs` `hasLength(2)`）照綠（helper 已帶 `queryTime`）。
- [ ] **Step 2: 跑，確認紅**。
- [ ] **Step 3: 實作**：`_Round.add(QuoteBatchReport r, DateTime at)` 對 `r.quotes` 的每一檔記 `at`；`_step` 傳 `after`；`_finishRound` 把 `round.receivedAt` 交給 `apply`。`_publish` 帶 `lastReceivedAt`。`_finishRound` 依 `lastApplyStats` 以 debug 記一行「擋下 N 檔、最舊快照 HH:MM:SS、可見／看不見」；`applied > 0 && missingSnapshots == applied`（全為 null）時、`futureSnapshots > 0` 時，各自一段連續期間只記一次 warning（比照 `_noteFailure`／`_noteRecovery` 的去重）。按輪判斷：批次結果在 `_Round` 裡合併，`apply` 才知道哪些是今天的報價。
- [ ] **Step 4: 跑**：`flutter test test/presentation/providers/live_quote_provider_test.dart` 綠。
- [ ] **Step 5: 突變**（各一次要紅）：拿掉 `applied > 0`；warning 不去重；`_Round.add` 不記收到時刻；作廢的一輪照寫 `lastReceivedAt`。

---

### Task 4: 頁首「報價延遲」，與 A 的整合測試

**Files:**
- Modify: `lib/presentation/widgets/live_quote_status.dart`（`LiveHeaderKind.delayed`、`LiveHeaderStatus.text`、`LiveQuoteStatusRule.header`）
- Modify: `assets/translations/zh-TW.json`、`assets/translations/en.json`（`liveQuote.delayed`）
- Modify: 呼叫點：`lib/presentation/providers/live_price_provider.dart`、`heatmap_live_provider.dart`（`_header` 已有 `now`）、`portfolio_live_provider.dart`（已有 `now`）、`alert_live_provider.dart`、`lib/presentation/screens/portfolio/position_detail_screen.dart`（有 `ref`，讀 `appClockProvider`）；`lib/presentation/providers/market_index_live_provider.dart`（`MarketIndexLive.of` 與 `marketLiveIndicesProvider`）、`lib/presentation/screens/stock_detail/widgets/stock_detail_header.dart`（`StockHeaderLive.from`）、`lib/presentation/screens/stock_detail/stock_detail_screen.dart`（呼叫 `StockHeaderLive.from` 的 Consumer）
- Modify: `CHANGELOG.md`（A 那一句）
- Test: `test/presentation/widgets/live_quote_status_test.dart`；`test/presentation/screens/today/widgets/market_summary_strip_test.dart`（寬 320、英文真實翻譯不溢位）；`test/presentation/screens/stock_detail/widgets/stock_detail_header_test.dart`（英文真實翻譯不溢位）；`test/presentation/providers/heatmap_live_integration_test.dart`（A 的整合測試）

**Interfaces:**
- Consumes: `LiveQuoteEntry.snapshotAt`（經 `MergedPrice.live`，`live.symbol` 對 `state.lastReceivedAt`）、`LiveQuoteState.lastReceivedAt`、三個常數。
- Produces:
  - `static LiveHeaderStatus? header({required LiveQuoteState state, required Iterable<MergedPrice> merged, required String? intradayTime, required DateTime now})`；`LiveHeaderKind.delayed`（`time` 為 HH:MM:SS）。
  - `MarketIndexLive.of({..., required DateTime now})`、`StockHeaderLive.from({..., required DateTime now})`；`marketLiveIndicesProvider` 與 `stock_detail_screen.dart` 的 Consumer 以 `ref.read(appClockProvider).now()` 傳入。

- [ ] **Step 1: 寫會紅的測試**（`group('報價延遲')`，`now` 盤中 10:30:00；這個檔沒載翻譯，斷言 `kind` 與 `time`）
  - 一張即時卡片：快照 10:26:00、最近一次收到 10:29:00（延遲恰好 3 分）→ `quoteTime`；快照 10:25:59、收到 10:29:00 → `LiveHeaderStatus(LiveHeaderKind.delayed, '10:25:59')`。
  - 兩張卡片取延遲最大的那張的快照時刻。
  - 最近一次收到 10:28:00（恰好 2 分鐘前）仍算；10:27:59 不算 → `quoteTime`（重新進入的情況）。
  - 快照為 null 的卡片略過；全部略過 → `quoteTime`。
  - 優先順序：同時限流 → `pausedRateLimit`；同時 `stalled` → `pausedNetwork`。（「證交所今天尚無報價」要求沒有即時卡片，「報價延遲」要求有，兩者互斥；延遲排在它之後只是照 spec 的順序，不另寫測試。）
  - 收盤後：`now` 14:00:00、收到 13:59:30、快照 13:55:00（在窗口內、延遲 4 分 30 秒）→ 不是 `delayed`（照既有收盤後規則）。
  - 中文全文：在 widget 測試（`buildProviderTestApp(zhTranslations: true)`）裡顯示「報價延遲（證交所資料停在 10:25:59）」。
- [ ] **Step 2: 跑，確認紅**。
- [ ] **Step 3: 實作** spec A4 的規則：只看 `MergedPriceKind.live` 的卡片、`LiveQuoteSchedule.phaseAt(now) == MarketPhase.open`，放在 `noQuotesToday` 之後、`quoteTime` 之前。8 個呼叫點照 Interfaces 傳 `now`。
- [ ] **Step 4: A 的整合測試**（`heatmap_live_integration_test.dart`，真的報價中心＋假 client；兩條都 `_Session(async, start: DateTime(2026,11,9,10,0))`；`_Session` 的 `_view` 改成可關掉再重訂，供「重新進入」用）
  - 假 client 對同一批交替回新、舊快照（舊的快照時刻較早、`t` 不較新）20 輪 → 每檔顯示價序列只往前（等於「至今最新快照」的價）、沒有反向閃色、`latestQuoteTime` 單調、`stalled` 始終 false。
  - 重新進入：連續 3 輪舊快照（距上一次換上超過 30 秒，約 45 秒）之後，關掉 `_view`、`async.elapse(Duration.zero)` 讓 autoDispose 執行，再重訂 → 那幾檔照樣上色（靠擋下時仍記 `fetchedAt`）。
  - 假 client 從 10:00 起一直回快照 09:56:00 的同一份 → 第一次發布（約 10:00:13，10:00:00～09 是 CLI 讓開窗口）起頁首為 `delayed`、時刻 09:56:00。
- [ ] **Step 5: CHANGELOG** 補一句：「證交所回較舊的資料時價格不倒退；資料停住超過 3 分鐘時頁首寫報價延遲」。
- [ ] **Step 6: 跑全套**：`flutter test`（全套，含 `test/core`、`test/tool` 的守門）綠；英文不溢位兩條綠；改到的測試檔撥 +90 天綠；`flutter analyze` 沒有問題。
- [ ] **Step 7: 突變**（各一次要紅）：拿掉窗口條件、門檻改 `>=`、拿掉 `phase == open`、`delayed` 排到暫停前面；擋下的那檔不寫 `_fetchedAt`（「重新進入」那條要紅）。
- [ ] **Step 8: 停下，等使用者說「提交」後提交 A**（`feat:`，含 spec 與本計畫；不含 heatmap-2 計畫的修改）。

---

## B：收盤後背景收集（Task 5～7，完成後提交 B）

### Task 5: 收盤後 App 看不見也收完（報價中心）

**Files:**
- Modify: `lib/presentation/providers/live_quote_provider.dart`（建構參數、`_registrations` 存登記日、`_union`、`_syncTicker`、`_step`、`_finishRound`；類別說明的「App 可見」、`setAppVisible`、`_syncTicker` 的說明一併改）
- Test: `test/presentation/providers/live_quote_provider_test.dart`（`_Harness` 加建構參數，放 `liveQuoteCenterProvider` 的 override）；`test/presentation/providers/heatmap_live_integration_test.dart`（`_Session` 加同樣的參數；「一輪送到一半 App 不可見一輪 → 只損失那一輪」那條改為明確注入 `collectAfterCloseWhenHidden: false`，另寫 macOS 版）

**Interfaces:**
- Produces: `LiveQuoteCenter({bool? collectAfterCloseWhenHidden})`（null 時 `defaultTargetPlatform == TargetPlatform.macOS`；`liveQuoteCenterProvider` 仍用 `LiveQuoteCenter.new`）。

- [ ] **Step 1: 寫會紅的測試**（fakeAsync；`liveQuoteCenterProvider.overrideWith(() => LiveQuoteCenter(collectAfterCloseWhenHidden: true))`；收盤後第一個請求在 13:30:10）
  - 看不見、盤中 10:00 有登記 → 10 分鐘內請求數 0。
  - 看不見、13:25 有登記（60 檔）→ 13:30:10 起開始送；全部拿到收盤報價後撥到 14:30 請求數不變。
  - 前一天收完並停、一直看不見，撥到隔天 13:31 → 有請求。
  - 只登記自選、看不見時收完，撥到隔天 09:01 → 10 分鐘內請求數 0。
  - 看不見、收盤後一直斷線（13:30:00 起、門檻 120 秒，13:32:01 判為暫停）→ 13:32:10 起不再送；13:40:20 重新可見 → 下一拍照常送。
  - 看不見時 13:30:10 被限流 → 撥到 13:40:20 請求數不增加；重新可見 → 下一拍送出試探。可見時 13:30:10 被限流、隨即看不見 → 撥到 13:40:20，看不見之後送出的請求數為 0（總數維持 1）。
  - 看不見時套用的輪次沒有閃色：只登記 1 檔，13:30:10 回 13:29:50 的成交 100（不是收盤報價）、13:31:10 回 13:30:00 的成交 101（收盤報價）→ `entries` 的 `flash` 為 null（同樣資料在可見時會閃，作對照）。
  - 登記日：D 日以 `hasOfficialToday: true` 登記、看不見跨到 D+1，13:31 有請求（先在「沒有記登記日」的版本上看到紅）。
  - `collectAfterCloseWhenHidden: false`：看不見時計時器停（收盤後請求數 0），既有行為不變。
  - macOS 版的「一輪送到一半 App 不可見一輪」：`collectAfterCloseWhenHidden: true`，收盤後第 5 輪第 1 批回來後 `setAppVisible(false)`，第 2 批照常送出、那一輪照常套用，6 分鐘內收齊。
- [ ] **Step 2: 跑，確認紅**。
- [ ] **Step 3: 實作** spec B1：`_syncTicker` 條件「有登記，而且（可見，或 `_collectWhenHidden`）」；`_step` 在 `_rollDay` 之後，看不見時先看「收盤後、`plan.pending > 0`、`_rateLimitedUntil == null`」，不成立就做 `_stopTicker` 除了取消計時器以外的收尾（`_round` 作廢、`_lastCountedTick = null`）並 return；成立則 `_countStall` 後若 `_stalled` 同樣收尾 return；看不見且放行時 debug 記「與上一拍的間隔、`_unresponsive`、這一拍的暫停門檻」。`register` 記 `_now()` 的日期，與清單存在同一個 map（`unregister` 一起移除）；`_union` 在合併前逐個 owner 把登記日不是今天的 `hasOfficialToday` 當 false。`_finishRound` 在看不見時先 `_book.forgetLastRound()` 再 `apply`。
- [ ] **Step 4: 跑**：`flutter test test/presentation/providers/` 綠（含既有整合測試）。
- [ ] **Step 5: 突變**（各一次要紅）：拿掉 `_rateLimitedUntil` 條件；拿掉暫停後再判斷；拿掉登記日規則；拿掉看不見時 `forgetLastRound`；`_syncTicker` 拿掉 `_collectWhenHidden`。（「拿掉 `pending > 0`」不影響請求數——收盤後 due 一定在 pending 裡——只多出看不見時的 debug 行，不列入。）

---

### Task 6: 熱力圖登記清單不靠畫面重畫

**Files:**
- Modify: `lib/presentation/widgets/live_quote_scope.dart`（新增 `LiveQuoteScope.listen`）
- Modify: `lib/presentation/providers/heatmap_live_provider.dart`（新增 `heatmapRegistrationsProvider`）
- Modify: `lib/presentation/screens/market/market_heatmap_screen.dart`（改用 `LiveQuoteScope.listen`）
- Test: `test/presentation/widgets/live_quote_scope_test.dart`、`test/presentation/screens/market/market_heatmap_screen_test.dart`；新檔 `test/presentation/screens/market/market_heatmap_background_test.dart`（背景收集的 widget 整合測試，內容見 Task 7 Step 1）；共用資料（`_byCap`、`_twse()`、收盤沒撮合的設定）搬到 `test/helpers/heatmap_live_fixtures.dart`，`heatmap_live_integration_test.dart` 改用它

**Interfaces:**
- Consumes: `heatmapLiveProvider`（`stockRegistrations`）、`marketIndexRegistrations(MarketOverviewState, DateTime)`、`heatmapSelectionProvider`、`marketOverviewProvider`、`liveQuoteBoundaryProvider`、`appClockProvider`。
- Produces:
  - `const LiveQuoteScope.listen({Key? key, required ProviderListenable<List<LiveQuoteRegistration>> source, required Widget child})`
  - `final heatmapRegistrationsProvider = Provider.autoDispose<List<LiveQuoteRegistration>>(...)`：目前市場的指數＋`stockRegistrations`（順序同現在畫面的寫法）。

- [ ] **Step 1: 寫會紅的測試**
  - scope（真的 go_router＋真的報價中心，比照檔內）：`listen` 模式下 source（一個測試用 `NotifierProvider`）變動 → 不 pump 也登記新清單（`registeredMarkets`）。
  - scope：`tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden)` 後，source 是衍生 provider（記 build 次數）時，`tester.pump(const Duration(milliseconds: 1))` 讓 `Timer(Duration.zero)` 跑（不帶 duration 的 `pump()` 不前進時間）→ 照樣登記；scope 子樹的 build 次數在切 hidden 那一幀之後不增加。
  - scope：被不透明頁面蓋住 → 取消登記；route builder 讀 `Theme.of(context)`、非 const 建 `LiveQuoteScope.listen`；蓋住期間 source 依賴的 `NotifierProvider` 變兩次、切兩次深色模式（計數確認 scope 的 `didUpdateWidget` 被呼叫兩次）→ 仍未登記、衍生的 source 沒有重算（build 次數不變）；回來 → 以現值重新登記，之後 source 變動照樣跟著換。（Riverpod 恢復訂閱時會補送暫停期間漏掉的事件，斷言以「回來後的清單等於現值」為準。）
  - scope：蓋住期間 source 沒變，回來後照樣重新登記（這條才殺得死「恢復時不重新登記」的突變）。
  - 熱力圖頁（`_LiveCenter` 覆寫了 `register`，用 `_LiveCenter.symbols` 驗）：登記清單等於 `heatmapRegistrationsProvider` 的值；切 hidden、畫面停排後，`heatmapLiveProvider` 換下一批 → `_LiveCenter.symbols` 跟著換（先在現在的程式上看到紅：停在切 hidden 時的清單）。
  - 背景收集的 widget 整合測試（見 Task 7 Step 1 的內容）在這個 Task 先寫好、先看到紅：Task 5 已能在背景收集，紅的原因只剩登記清單沒換——收盤進度停在 62 檔（前 69 檔裡有 7 檔收盤沒撮合），不是 69。
- [ ] **Step 2: 跑，確認紅**。
- [ ] **Step 3: 實作** spec B2：同一個 State、同一個 owner；`listenManual` 的訂閱以欄位記住是否暫停，只在 `TickerMode` 的值改變時 `pause()`／`resume()`；恢復時用 `subscription.read()`。
- [ ] **Step 4: 跑**：`flutter test test/presentation/` 綠。
- [ ] **Step 5: 突變**：`TickerMode` 關閉時不 pause、每次 `_sync` 都 pause（重複計次）、恢復時不重新登記，各一次要紅。

---

### Task 7: B 的整合測試、全套驗證、文件、實機

**Files:**
- Test: `test/presentation/screens/market/market_heatmap_background_test.dart`（Task 6 建立）
- Modify: `CHANGELOG.md`（B 那一句）、本計畫末尾「實作後的修正」

- [ ] **Step 1: B 的整合測試**（Task 6 Step 1 已寫好並看到紅，這裡確認轉綠；`testWidgets`；pump `MarketHeatmapScreen`（停在上市，沿用 `_twse()` 的 1,078 檔）＋真的報價中心（`collectAfterCloseWhenHidden: true`）＋假 adapter；時鐘用累加 `tester.pump(Duration)` 經過時間的 `AppClock` 替身）
  - 13:25 切 hidden（`handleAppLifecycleStateChanged(AppLifecycleState.hidden)`、`setAppVisible(false)`、`appVisibilityProvider` 設為 false），之後以 `tester.pump(const Duration(seconds: 1))` 逐秒前進（不畫幀、會跑 Timer）→ 沿用既有「100 檔收盤沒撮合」的資料，全部收完的時刻 ≤ `DateTime(2026,11,9,13,31) + 25 分鐘`（與既有測試同一個絕對上限），熱力圖登記清單在背景一路換下去。
- [ ] **Step 2: 全套**：`flutter analyze`；`flutter test`；改到的測試檔 `scripts/test_time_shift.sh 90`（用 xargs 傳檔名）；`flutter test --tags golden test/presentation/screens/golden/market_heatmap_screen_golden_test.dart` 圖不變。
- [ ] **Step 3: CHANGELOG** 補一句：「收盤後 App 在 Mac 上被蓋住也繼續收收盤價，熱力圖切回來時已經是齊的」。
- [ ] **Step 4: 實機**（下一個交易日，debug 版 `flutter run -d macos 2>&1 | tee` 日誌）：照 spec「驗證／實機」逐項；結果寫進本計畫末。
- [ ] **Step 5: 使用者說「提交」後提交 B**（`feat:`）。

---

## 實作後的修正（A：Task 1～4，2026-11-13）

### 與計畫或 spec 寫法不同的地方

- Task 1：沒有另寫「月 1–12」的判斷。年月日組回 `DateTime` 後相同已涵蓋（13 月會進位到隔年）。
- Task 2：快照時刻「偏前」跟**那一批收到的時刻**比（`receivedAt[symbol] ?? now`），不是跟整輪套用的時刻比（spec A2 與本計畫寫「現在＋60 秒」）。多批的一輪從第 1 批回來到套用可差約 80 秒，跟套用時刻比會採信比收到時刻晚約 140 秒的快照。沒給收到時刻時與計畫相同。
- Task 2：統計的型別取名 `LiveApplyStats`；`lastApplyStats` 換日時設回 null。
- Task 3：兩個快照時刻的 warning 改成**每天各記一次、換日重置**（spec A1 與本計畫寫「一段連續期間只記一次」「恢復後再缺再記」）。本機時鐘慢 X 秒時，偏前的條件等於「快取年齡 < X−60 秒」；X 在 60 秒到「60 秒＋快取存活期」之間時每個快取週期翻一次，逐段記會一直重記、擠掉 Sentry 的其他 breadcrumb。每輪的 debug 行另寫「沒有可信快照時刻 M 檔(其中偏前 F 檔)」。代價：同一天內恢復後再出現的異常，release 版只留當天第一筆。
- Task 3：「整輪都沒有可信的快照時刻」不含整輪都偏前的那一輪（偏前另記），否則偏前那一輪會用掉缺失當天的那一次。
- Task 3：判斷粒度是整輪，不是 spec A1 寫的批次（理由見 Task 3 Step 3）。多批的頁面只有一部分批次缺 `queryTime` 時不記 warning，只在 debug 行看得到檔數。
- Task 4：個股頁價格下方的狀態行限寬為整列的 60%、放不下就換行。價格欄在 Row 裡寬度不受限，英文「報價延遲」在測試字型下把股名欄擠到溢位 175px。大盤摘要條不用改（狀態在 `Wrap` 裡，320 寬時自己換行）。
- Task 4：中文全文的測試另開 `test/presentation/widgets/live_quote_status_zh_test.dart`（真實翻譯寫入全域，要獨立一檔）。
- Task 4：CHANGELOG 既有「盤中即時報價實際約 45 秒才更新一次」那一條寫的「每輪都拿到新報價」與 11/9 的量測不符，而且還沒發布：整條拿掉，由新的一條寫明「同一組股票約 1～2 分鐘才換一份新資料」。
- Task 4：整合測試另加「平常的快取落後 20 分鐘，頁首從不寫報價延遲」（反目標第一條的守門）。

### 「報價時間」改成只看這一頁的卡片（改了 spec A3）

- 原本照 spec A3 做成「報價中心全 App 共用、整天不往回」的 `latestQuoteTime`。審查指出換頁後頁首的時間可能不在這一頁任何一張卡片上；照 11/9 量到的快取行為（每一組查詢各一份、各自落後）模擬「自選 → 熱力圖 30 秒 → 回自選」，回來後 120 秒裡有 64 秒頁首比這一頁每一張卡片都新。
- 改法：自選與熱力圖頁首取這一頁用即時報價的卡片裡最新的那一列時間（`LiveQuoteStatusRule.latestRowTime`，讀 `LiveQuoteEntry.rowTime`）；`LiveQuoteBook.latestQuoteTime`、`LiveQuoteState.latestQuoteTime` 拿掉。spec A3 已改寫。
- 本計畫 Task 2、3 裡關於 `latestQuoteTime` 的步驟與測試（「報價時間不往回」兩條、`rollDay` 後為 null、說明文字）因此不適用；記帳本既有的「`latestQuoteTime` 取本輪各筆 `t` 的最大值、格式不符的不算」一條也拿掉，由 `latestRowTime`「無法解析的不算」接手。「不往回」改由「擋下時畫面那筆的 `rowTime` 不變」與整合測試「頁首的報價時間不往回」守。
- 測試：規則 2 條、自選頁首 1 條、熱力圖頁首取列時間與「別的畫面抓到比較新的報價」整合測試各 1 條（後者先在舊做法上紅：頁首寫別頁的 10:00:39，應為自己格子的 09:59:30）。

### 延後的 Minor（審查提出、未修）

- spec A4 說「英文字串比現有的長很多」不準：代入時間後英文最長的是限流那句（54 字），「報價延遲」45 字。兩條英文不溢位的測試改成把每一句報價狀態都量一遍。
- 未驗證的前提：證交所若把過期的快取先回出去，離開超過 3 分鐘再回來的第一輪會閃一次「報價延遲」（下一輪恢復）。11/7 週末量到過第 1 次回應是 2 小時 34 分前的快照，盤中沒量過。實機驗收加一項「離開 5 分鐘以上再回來」（已加進 spec「驗證／實機」），真的出現再處理。
- `queryTime.sysDate` 是上萬層巢狀陣列時 `toString()` 會 StackOverflow。既有的 `row['n']?.toString()` 也一樣；證交所不會回這種內容。
- `docs/plans/2026-10-05-intraday-live-quotes-design.md` 仍寫「請求改帶每次不同的 `_` 參數」（舊設計文件，不改）。

### 突變（各 Task 各拔一次）

Task 1：10 個全紅（3 個差一的邊界突變起初存活，補上界測試後轉紅）。Task 2：25 個全紅（審查指出的 4 個起初存活，補測試後轉紅；原有 2 個關於 `latestQuoteTime` 的隨欄位拿掉）。Task 3：19 個全紅（2 個起初存活：收到時刻記成送出的時刻、debug 行兩個檔數對調）。Task 4：16 個全紅（1 個起初存活：大盤摘要條的狀態不換行）。「報價時間」改看這一頁：6 個全紅。全部改完後各清單重跑一次，結果相同。

### 驗證

`flutter test` 全套 6877 條通過（另 3 條略過）、`flutter analyze` 沒有問題；A 改到的 13 個測試檔撥 +90 天 411 條通過。實機（spec「驗證／實機」）排在下一個交易日，結果補在本節。

## 實作後的修正（B：Task 5～7，2026-11-13）

### 與計畫或 spec 寫法不同的地方

- Task 5：看不見時的閘門多一個條件「還沒判為暫停」（spec B1 與本計畫只寫收盤後、還有要收的、不在限流）。審查發現：盤中可見時判為暫停（門檻 60 秒）、隨即看不見，13:30 一到門檻變成 120 秒，照原寫法每一拍重算會把暫停解除、看不見時照樣送請求，違反目標「看不見之前或之後開始的暫停都不收」。先以測試重現（看不見之後多送 1 個請求）再修；spec B1 已補上這個條件與原因。
- Task 5：`unregister` 不讀時鐘。`_changeRegistrations` 比的是登記時的原樣（不看登記日），只有每一拍的計畫才套「登記日不是今天的『已有今天正式資料』不算數」。`unregister` 在畫面 dispose 時呼叫，那時不能碰 `ref`。代價：登記日造成的差別不會截斷進行中的一輪，至多把那一輪送完。
- Task 5：預設平台另寫一條測試，用 `debugDefaultTargetPlatformOverride`（Global Constraints 寫「測試不改全域目標平台」，理由是整棵 widget 樹會照 macOS 版面渲染；這條在 provider 層、沒有 widget 樹，用完還原）。預設值是正式程式唯一的接線，不釘住的話「預設寫錯平台」沒有測試會紅。
- Task 5：看不見時的每拍 debug 行，判為暫停之後不再記（判定的那一拍記一行並註明）。照「看不見且放行時記」的字面，暫停後每秒一行會記到午夜，與 spec A5「避免整夜每秒一行」相抵。
- Task 5：既有 5 條「盤中 App 看不見」的測試改成兩種平台都跑（不在背景收集的停計時器、在背景收集的每一拍自己判斷，對外行為相同）。
- Task 6：`LiveQuoteScope.listen` 在 `TickerMode` 關閉時**關掉**訂閱、打開時重新訂閱，不用 spec B2 與本計畫 Step 3 寫的 `pause()`／`resume()`。照原寫法實作後，既有測試「離開熱力圖再回來」炸在 riverpod 3.2.1 內部的暫停計數檢查（原因與最小重現見 spec B2，已改寫）。Step 5 的三個突變（關閉時不 pause、每次都 pause、恢復時不重新登記）改成對應的三個：關閉時不關訂閱、重複訂閱、恢復時不重新登記。
- Task 6：listen 模式只有來源物件換了才重新訂閱；同一個來源、頁面重建時不重新訂閱，只以現值再登記一次（每次重建都同步，見下面「固定清單每次重建都重新登記」那一條）。「同一個可見性下再同步一次不能重複訂閱、被蓋住時不能誤登記」除了計畫寫的切深色模式，另用 GlobalKey 把 State 搬到樹上別處來製造（關閉時仍不登記、打開時不重複訂閱各一條）。
- Task 6：Step 1 第 2 點要求的「scope 子樹的 build 次數在切 hidden 那一幀之後不增加」是空過的斷言（同一個 widget 實例重畫時不重建，看得見時畫了幀也數不到），改成斷言前提 `tester.binding.framesEnabled` 為 false；背景收集的 widget 整合測試另以 `addPersistentFrameCallback` 記幀數（並確認看得見時有在數）。spec「驗證」的範例同此改寫。
- Task 6（最後審查提出）：固定清單的 `LiveQuoteScope` 改成**每次重建都重新登記**，清單內容沒變也一樣。Task 5 的登記日規則只在 `register` 時更新登記日，而原本清單內容相同就不重新登記：前一天以「已有今天正式資料」登記、看不見跨過午夜、隔天第一次重建時已有當天的正式資料（內容與前一天那份相同），登記日就停在前一天，收盤後多抓（以真的報價中心重現：重建之後仍每分鐘重抓）。七個固定清單的頁面都在 build 裡用當下的時鐘算清單，重建時給的一定是當下的；內容相同的重新登記不換版本、不影響進行中的一輪。
- Task 6：熱力圖頁的 build 不再 watch `liveQuoteBoundaryProvider`（原本只為了重算登記清單），改由 `heatmapRegistrationsProvider` 自己 watch；provider 層另寫「跨過午夜而熱力圖的檢視沒變，指數的『已有今天正式資料』照樣重算」。
- Task 6：`heatmap_live_integration_test.dart` 的替身原本自己抄一份清單公式、清單變了才登記，改成聽 `heatmapRegistrationsProvider`、每次通知就登記（與 `LiveQuoteScope.listen` 相同），請求序列的斷言全部照綠。共用資料只搬資料與假回應，mock 類別照 `test/CLAUDE.md` 留在各測試檔。

### 已知的差別與限制（不修）

- macOS 上 App 剛看不見、下一拍之前回來的那一個請求照常套用（不閃色）：盤中是幾秒內的新資料；收盤後若它有回應，先前的暫停或限流因此解除、看不見時接著收。macOS 以外的平台是看不見的當下就作廢。
- 看不見收集途中電腦睡眠超過暫停門檻（收盤後一輪 8 批以內是 120 秒）：醒來即判為暫停，等切回 App 才接著收（已寫進 spec「已知限制」與實機清單）。
- `LiveQuoteScope.listen` 的來源要用 autoDispose；不是的話，頁面被蓋住期間上游變過、回來時會踩到同一個 Riverpod 檢查（只有 debug 有這個 assert）。
- macOS 版的報價中心整合測試（`heatmap_live_integration_test.dart`）不經畫面，只證明報價中心這一層；「真的熱力圖頁在看不見時收得完」由 `market_heatmap_background_test.dart` 證明。

### 順帶發現（範圍外）

- riverpod 3.2.1（`pubspec.lock` 鎖定的版本）：被畫面 watch 的衍生 provider，只要還有「掛著但不活躍」的下游 provider（非 autoDispose、曾被讀過、現在沒人聽，或 listener 被暫停），畫面被蓋住期間上游變過、回來時 debug 就會炸 `pausedActiveSubscriptionCount` 的 assertion。與本功能無關的地方也可能踩到。riverpod 3.3.2 的 CHANGELOG 寫「Fixes assertion error when providers are unpaused」（沒有實測）；升級是依賴變更，另案處理。
- spec 與本計畫原本寫 flutter_riverpod 3.3.2，`pubspec.lock` 鎖的是 3.3.1；引用的行號已照 3.3.1 改正。
- `live_quote_scope.dart` 與其測試檔頭的說明帶日期（既有的，不是這次加的）。

### 突變（各 Task 各拔一次）

Task 5：第 1 輪 22 個全紅；審查的 Important 修完後清單改成 23 個重跑全紅（原本「已暫停的拍子照樣每秒記一行」隨 `wasStalled` 拿掉，換成「看不見的閘門拿掉已暫停」；另加「登記日改在合併之後、依勝出那一筆套用」）。修完自查時發現「判為暫停的那一拍收尾並 return」原有測試殺不死，補「判為暫停的那一拍剛好輪到重抓」後轉紅。Task 6：13 個全紅；最後審查改了「固定清單每次重建都重新登記」之後清單對應調整、重跑 13 個全紅（其中「還原成內容相同就不重新登記」只有新補的那條測試會紅）。

### 驗證

`flutter test` 全套 6907 條通過（另 3 條略過）、`flutter analyze` 沒有問題；熱力圖的 golden（`flutter test --tags golden test/presentation/screens/golden/market_heatmap_screen_golden_test.dart`）圖不變；B 改到的 6 個測試檔撥 +90 天 206 條通過。實機（spec「驗證／實機」）排在下一個交易日，結果補在本節。
