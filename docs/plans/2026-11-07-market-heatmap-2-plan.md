# 大盤熱力圖第 2 段：盤中即時與收盤後滾動登記 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 熱力圖在盤中（9:00–13:30）讓市值前 69 檔每 15 秒以即時報價上色，收盤後到盤後資料寫入前以滾動登記逐批取得收盤報價；頁首、產業與合併塊的漲跌、提示都標出即時狀態。

**Architecture:**
- **domain（純 Dart）**：`heatmap_live.dart` 決定即時模式、要登記哪些股票，並把報價套到第 1 段算好的正式資料上（面積不變，只換顏色、顯示價格、產業與合併塊的漲跌）。加權改由格子自帶的平盤市值計算，分組、合併塊、即時三處共用一個函式。
- **報價中心**：只多公開唯讀的 `LiveQuoteState.fetchedAt`（每檔最近一次成功取得今天報價的時刻），行為不變。
- **presentation**：市場與放大的產業從畫面的區域狀態搬到 `heatmapSelectionProvider`；`heatmapLiveProvider`（Notifier）逐檔記「這頁開始登記它的時刻」，組出畫面要的 `HeatmapLiveView`；熱力圖頁用它登記、上色、顯示一行即時狀態。畫面文字集中在新的 `heatmap_text.dart`，painter 仍只經 `HeatmapPaintLabels` 拿字串。

**Tech Stack:** Flutter／Dart 3.10、flutter_riverpod 3、easy_localization、fake_async、mocktail、flutter_test

**Spec:** `docs/plans/2026-10-07-market-heatmap-design.md`（第 3 節「盤中即時」、第 2 節空心格子與提示、第 4 節即時列、「驗證」1 的即時項目、2、3 的提示、5、6、7）。第 1 段計畫：`docs/plans/2026-11-04-market-heatmap-1-plan.md`（介面、Global Constraints、「實作後的修正」的小格子合併與「對第 2 段的影響」）。

## Global Constraints

沿用第 1 段計畫的 Global Constraints（只讀資料庫、tool 鏈純 Dart、常數集中、漲跌不退回前一筆收盤、納入範圍、文案進翻譯檔、測試用虛構代號、painter 的字串經 `HeatmapPaintLabels` 傳入、提交規則），另加：

- **報價中心只加唯讀資料**：`LiveQuoteState.fetchedAt` 以外不改 `LiveQuoteCenter`、`LiveQuoteBook`、`LiveQuoteSchedule` 的行為；既有測試全部不改仍要綠。
- **盤中面積不變**：盤中與收盤後滾動期間，格子面積、排序、產業排序、合併都用正式資料（前一交易日收盤市值），只換顏色、顯示價格與漲跌。
- **漲跌公式**：即時與收盤報價的漲跌幅＝`(價格 − y) * 100 / y`（`y`＝MIS 昨收）；`y` ≤ 0 或不是有限數畫空心，不退回資料庫收盤。
- **69 檔＝兩批扣掉一個指數**：`HeatmapParams.liveTileLimit = ApiEndpoints.misBatchSize * 2 - 1`，不寫死 69。
- **提交**：同第 1 段——implementer 不 commit；每個 Task 完成後送 `pr-review-toolkit:code-reviewer`（opus），Critical／Important 修完才進下一個 Task；整段在 Task 7 經使用者說「提交」後一次提交，直接在 main。

## Review Focus

spec 沒寫、但最可能讓使用者撞到的情況，各在負責的 Task 補了測試：

1. **盤中開著頁面跨過 13:30**：換成收盤後滾動，盤中最後一筆（不是收盤報價）不得當收盤上色。→ Task 2、Task 4。
2. **盤後資料在頁面開著時寫入**：重讀後該市場正式資料是今天，回到「不需要即時」，只登記指數。→ Task 2、Task 4。
3. **切換市場、放大、取消放大**：這頁登記某檔之前別的畫面抓到的報價不能上色；一直有登記的大格子不因放大或取消放大而變空心；離開熱力圖再回來時最多一輪維持離開前的顏色（差異 9）。→ Task 4（`_since`）、Task 5（推頁再返回）。
4. **除權息日盤中**：`y` 是參考價；漲跌以 `y` 為基準，加權的平盤市值＝股數 × `y`，面積仍是前一日市值。→ Task 1。
5. **報價暫停或限流**：格子維持最後一次拿到的顏色，狀態行顯示暫停。→ Task 1、Task 4。
6. **日曆漏標的停市日（颱風）**：證交所整天只回前一天的報價。不能整天全空心、頁首不能寫「今日收盤 0／M 檔」：退回正式資料的顏色，狀態行顯示「證交所今天尚無報價」。→ Task 4（退回規則）、Task 5（狀態行與指數列）。
7. **滑鼠停在格子上或長按時每 15 秒換一份資料**：提示不能消失，數字換成新的。→ Task 5。
8. **窄螢幕**：狀態行最長的句子（收盤後進度＋限流）在 360 寬中英文都不溢位。→ Task 5。

## 與 spec 的差異（核可計畫時一併確認）

1. **只登記正在看的市場的指數**：符合 spec「該市場指數一律登記」；第 1 段沿用大盤總覽的兩個指數，盤中加 69 檔會變成 71 檔＝3 批、一輪 22.5 秒，所以改回 spec 的寫法。
2. **報價中心公開 `fetchedAt`**：spec 要「只用熱力圖自己登記的股票上色」。中心的報價只在抓到時換新，看不出是不是登記之後抓的；加唯讀欄位，熱力圖只用「這頁開始登記該檔之後」抓到的。spec 的非目標「不改報價中心」指行為與分層登記，本段不改行為。
3. **加權改用格子自帶的平盤市值**：第 1 段合併塊從「市值 ÷ (1 + 漲跌幅)」反推，盤中面積與漲跌基準不同時不成立（第 1 段程式註解已寫要改）。正式資料的結果不變（合併塊只差浮點最後一位）。
4. **合併塊與小產業群組也標即時比例**：spec 只對產業訂「・即時 N%」。手機上前 69 檔有很多被合進「其他 N 檔」或「其他 N 個產業」，只靠少數即時成員就整塊上色會誤導，所以同樣標比例：圖上的合併塊標籤（放不下時與產業標題同樣先捨比例）、提示、清單、無障礙描述都標。被合併的成員照樣算在 69 檔名額裡（spec 的定義是市值前 69，與螢幕大小無關）。
5. **提示與無障礙描述的空心計數**：畫面上寫「空心 N」（原本「無漲跌資料 N」，盤中多半是未即時，會說錯；與圖例「空心＝沒有今日漲跌」一致），無障礙描述寫「沒有今日漲跌 N」（報讀軟體使用者看不到空心）。
6. **即時比例的文字**：盤中「・即時 N%」，收盤後滾動「・收盤 N%」；一檔都沒有時盤中「未即時」、收盤後「未收盤」；比例夾在 1%～99%（只要有一檔、或還差一檔，就不寫成 0% 或 100%）。
7. **即時狀態獨立成一行**：指數列下方一行，最多兩行、超過以省略號結束；暫停、限流等狀態放在句首（截斷時先捨後面的進度）。即時時段（含停市退回）這一行取代第 1 段指數列的報價狀態（同一件事不寫兩次）；圖用即時上色時也取代右側「M/D 收盤」，停市日退回正式資料時保留「M/D 收盤」（唯一看得出顏色是哪天的線索）。盤中中心還沒有任何狀態時這一行不顯示。
8. **停市日退回正式資料**：中心回報「證交所今天尚無報價」、而且**整個市場（不論放大）**沒有任何一檔有今天的報價時，圖用正式資料上色、狀態行顯示中心的狀態（暫停、限流優先，否則「證交所今天尚無報價」）。spec「失敗時」要求頁首顯示，但沒寫格子怎麼辦。開盤頭幾秒同樣會退回、拿到第一筆今天的報價就離開，與開盤前的顯示一致。
9. **離開熱力圖再回來，格子先維持離開前的顏色**：頁面被蓋住或 App 到背景時不清掉「開始登記的時刻」，回來後最多一輪（約 15 秒）顯示離開前自己抓到的顏色，下一輪換新——與 spec「格子維持最後一次拿到的顏色」、自選卡片一致。不認的只有「這頁登記該檔之前」別的畫面抓到的報價。
10. **已打開的底部清單（其他 N 檔、其他 N 個產業）是打開當下的快照**，不跟著即時更新；關掉再打開才是新的。
11. **實機驗證在下一個交易日**：本計畫寫於週六（11/7），spec「驗證」7 的即時項目排在 11/9（一）。

## 檔案結構

| 檔案 | 動作 | 職責 |
|:--|:--|:--|
| `lib/domain/models/heatmap.dart` | 修改 | `HeatmapTile.baseCap`、`HollowReason` 新值、`TileChangeHollow.previous`、`HeatmapIndustry.liveCoverage`、`HeatmapMarketData.liveMode`、`HeatmapLiveMode` |
| `lib/domain/services/heatmap/heatmap_grouping.dart` | 修改 | 格子帶 `baseCap`；公開 `heatmapWeightedChange`、`heatmapValueCoverage` |
| `lib/domain/services/heatmap/heatmap_layout.dart` | 修改 | 合併塊與群組改用共用加權；新增 `coverage` 欄位 |
| `lib/domain/services/heatmap/heatmap_live.dart` | 新增 | `heatmapLiveModeAt`、`heatmapLiveSymbols`、`overlayHeatmapLive` |
| `lib/core/constants/heatmap_params.dart` | 修改 | `liveTileLimit` |
| `lib/domain/services/live_quote/live_quote_book.dart`、`lib/presentation/providers/live_quote_provider.dart` | 修改 | `fetchedAt` |
| `lib/presentation/providers/heatmap_live_provider.dart` | 新增 | `heatmapSelectionProvider`、`HeatmapLiveView`、`heatmapLiveProvider` |
| `lib/presentation/widgets/heatmap/heatmap_text.dart` | 新增 | 空心原因、漲跌與即時比例、空心計數的文字 |
| `lib/presentation/widgets/heatmap/heatmap_painter.dart`、`heatmap_view.dart`、`heatmap_tooltip.dart`、`heatmap_other_sheet.dart`、`heatmap_industry_group_sheet.dart` | 修改 | 文字改用 `heatmap_text.dart`／`HeatmapPaintLabels`；提示跟著新資料 |
| `lib/presentation/screens/market/market_heatmap_screen.dart` | 修改 | 用 `heatmapSelectionProvider`、登記、即時狀態行、產業選單 |
| `assets/translations/zh-TW.json`、`en.json`、`CHANGELOG.md` | 修改 | 字串、Added |

---

### Task 1: 平盤市值、空心原因、即時套色

**Files:**
- Modify: `lib/domain/models/heatmap.dart`、`lib/domain/services/heatmap/heatmap_grouping.dart`、`lib/domain/services/heatmap/heatmap_layout.dart`
- Create: `lib/domain/services/heatmap/heatmap_live.dart`、`lib/presentation/widgets/heatmap/heatmap_text.dart`
- Modify（讓新的列舉值編譯得過、文字集中）：`market_heatmap_screen.dart`（第 484–486 行的 switch）、`heatmap_tooltip.dart`、`heatmap_other_sheet.dart`（成員列的空心字）、`assets/translations/*.json`
- Test: `test/domain/services/heatmap/heatmap_grouping_test.dart`、`heatmap_layout_test.dart`、新增 `heatmap_live_test.dart`、新增 `test/presentation/widgets/heatmap/heatmap_text_test.dart`；其餘直接建 `HeatmapTile` 的測試補 `baseCap`

**Interfaces:**
- model：
  - `HeatmapTile` 新增 `required double baseCap`（平盤市值；沒有漲跌值時 0），納入 `==`／`hashCode`；`close` 說明改為「顯示的價格：正式資料是收盤，即時是即時價」。
  - `enum HollowReason { noChangeData, notLive, noTrade, noQuote, noClosingQuote }`
  - `TileChangeHollow(this.reason, {this.previous})`，`final ({double percent, DateTime date})? previous`（只有 `notLive` 帶：正式資料那天的漲跌幅與日期），納入 `==`／`hashCode`。
  - `enum HeatmapLiveMode { intraday, afterClose }`
  - `HeatmapIndustry.liveCoverage`（`double?`，預設 null）、`HeatmapMarketData.liveMode`（`HeatmapLiveMode?`，預設 null），都納入 `==`／`hashCode`。
- grouping：
  - `double? heatmapWeightedChange(Iterable<HeatmapTile> tiles)`：只算 `TileChangeValue` 且 `baseCap > 0` 的格子，Σ(baseCap × 漲跌幅) ÷ Σ baseCap；分母 ≤ 0 或結果不是有限數回 null。
  - `double heatmapValueCoverage(Iterable<HeatmapTile> tiles)`：有漲跌值的格子市值合計 ÷ 全部市值合計；全部市值 ≤ 0 回 0。兩個合計在同一個迴圈、同樣順序累加（全部有值時兩者逐位相同，比例恰為 1.0，文字的「夾 1～99」才判得出來）。
- layout：`HeatmapOtherLayout`、`HeatmapIndustryGroupLayout` 新增 `final double coverage`（`heatmapValueCoverage(成員)`；群組是群組內全部格子），納入 `==`／`hashCode`。
- live：
  ```dart
  HeatmapMarketData overlayHeatmapLive(
    HeatmapMarketData official, {
    required HeatmapLiveMode mode,
    required Map<String, LiveQuoteEntry> entries,
    required Map<String, LiveSymbolStatus> symbolStatus,
    required Set<String> registered,
    required Set<String> fresh,
    required DateTime today,
  })
  ```
- text（`heatmap_text.dart`，presentation，可呼叫 `.tr()`）：`String heatmapHollowReasonText(HollowReason reason)`；本 Task 先把既有三處（畫面 switch、提示、其他 N 檔清單的成員列）改用它，`noChangeData` 的文字不變。新增翻譯鍵：`hollowNotLive`「盤中未即時」、`hollowNoTrade`「尚無成交」、`hollowNoQuote`「無報價」、`hollowNoClosingQuote`「尚未取得收盤報價」（en 同步）。

- [ ] **Step 1: 寫失敗的測試**

grouping：`baseCap＝股數 × (收盤 − 漲跌)`（9901 收盤 110、漲 10、股數 1,000 → 100,000）；漲跌空值 → 0。`heatmapWeightedChange`：同 baseCap 各 ±10% → 0；只有空心 → null；baseCap 0 的有值格子不參與。`heatmapValueCoverage`：市值 300 與 100、只有前者有值 → 0.75。既有產業加權測試期望值不變。

layout：兩檔市值 1,000、`baseCap` 1,000、各 +5%／−5% 合進同一塊 → 合併塊 `weightedChangePercent == 0`（舊的反推算法得 −0.25%）；`coverage` 依成員有無值計算。

live（`today = DateTime(2026, 11, 9)`、正式資料日 11/6、9901 收盤 100、市值 100,000、正式漲跌 −0.8%；漲跌幅用 `closeTo(x, 1e-9)`）：
- 盤中、在 `fresh`、成交價 103、`y` 100 → 漲跌 3、`close == 103`、`marketCap == 100000`、`baseCap == 100000`。
- 盤中、`y` 是參考價 95、成交價 99.75 → 漲跌 5、`baseCap == 95000`。
- 盤中、在 `registered` 不在 `fresh`：狀態 `noQuote` → `noQuote`；其他（沒有狀態、`batchFailed`、`ok`）→ `notLive`。
- 盤中、不在 `registered`（中心有今天報價也一樣）→ `notLive`、`previous == (percent: -0.8, date: DateTime(2026, 11, 6))`；正式資料是空心時 `previous == null`。
- 盤中、`fresh` 但 `displaySource == trialOrBook` → `noTrade`；`locked` 照常上色；報價日期是前一天 → `notLive`；`y` ≤ 0 → `noChangeData`。
- 收盤後：今天的收盤報價不論在不在 `registered`／`fresh` 都上色；不是收盤報價 → `noClosingQuote`。
- 產業：兩檔市值各 100、一檔即時 +2%、一檔未即時 → `weightedChangePercent` 2、`liveCoverage` 0.5；全部未即時 → null、0。
- `liveMode == mode`；產業與格子順序、`marketCap`、`excludedForShares`、`dataDate` 與正式資料相同。

text：五種原因各自的文字（en、zh 用 key 字串比對即可）。

- [ ] **Step 2**：`flutter test test/domain/services/heatmap/ test/presentation/widgets/heatmap/heatmap_text_test.dart` → 編譯失敗。
- [ ] **Step 3: 實作**：分組把既有的平盤市值寫進格子、`_industry` 改用 `heatmapWeightedChange`；layout 刪 `_weightedChange`、改用共用函式（整個產業都合併時仍直接用產業的值）並填 `coverage`；`overlayHeatmapLive` 依上面規則逐格換 `change`、`close`、`baseCap`（即時 `baseCap = tile.marketCap / tile.close * y`），產業用 `heatmapWeightedChange`、`heatmapValueCoverage` 重算；`grep -rn 'HeatmapTile(' lib test` 全部補 `baseCap`（照該處的市值與漲跌換算，既有期望值不變）。
- [ ] **Step 4**：`flutter test test/domain/ test/presentation/widgets/heatmap/ test/presentation/screens/market/`、`flutter analyze` → PASS。

### Task 2: 即時模式與登記清單

**Files:** Modify `lib/domain/services/heatmap/heatmap_live.dart`、`lib/core/constants/heatmap_params.dart`；Test `test/domain/services/heatmap/heatmap_live_test.dart`

**Interfaces:**
- `HeatmapParams.liveTileLimit`（`ApiEndpoints.misBatchSize * 2 - 1`）
- `HeatmapLiveMode? heatmapLiveModeAt({required MarketPhase phase, required DateTime dataDate, required DateTime now})`：`open` → `intraday`、`afterClose` → `afterClose`，資料日與 `now` 同一天時都回 null；`preOpen`、`closed` → null。
- `List<String> heatmapLiveSymbols(HeatmapMarketData official, {required HeatmapLiveMode mode, required String? zoomIndustryKey, required Map<String, LiveQuoteEntry> entries, required DateTime today})`

- [ ] **Step 1: 寫失敗的測試**
  - 模式：上面五種組合；開著頁面跨 9:00（`preOpen` → `open`）由 null 變 `intraday`；收盤後跨午夜到下一個交易日 `preOpen` → null。
  - `1 + HeatmapParams.liveTileLimit == 2 * ApiEndpoints.misBatchSize`。
  - 盤中全市場：三個產業共 100 檔 → 全市場市值前 69，市值降冪、同值代號升冪。
  - 盤中放大：80 檔的產業 → 前 69；10 檔的產業 → 10 檔；放大的產業不存在（重讀後消失）→ 視同全市場。
  - 收盤後：前 69 大裡 5 檔已有今天收盤報價 → 由第 70～74 名補上；前一天的收盤報價、不是收盤報價的都不算已取得；放大與否結果相同；整個市場不到 69 檔 → 全部。
- [ ] **Step 2**：`flutter test test/domain/services/heatmap/heatmap_live_test.dart` → 失敗。
- [ ] **Step 3: 實作**（全市場清單攤平各產業後重排；「今天的收盤報價」＝`entry.date` 與 `today` 同一天且 `isClosingQuote`）。
- [ ] **Step 4**：同 Step 2 → PASS。

### Task 3: 報價中心公開 `fetchedAt`

**Files:** Modify `lib/domain/services/live_quote/live_quote_book.dart`、`lib/presentation/providers/live_quote_provider.dart`；Test 兩者現有的測試檔

**Interfaces:** `LiveQuoteBook.fetchedAt`（`Map<String, DateTime>`，唯讀）：`apply` 中拿到今天報價的代號記 `now`，換日清空報價時一起清空。`LiveQuoteState.fetchedAt`（預設 `const {}`），`_publish` 帶出。

- [ ] **Step 1: 寫失敗的測試**：一輪請求 9901（今天報價）、9902（無報價）、9903（批次失敗）→ `{'9901': now}`；下一輪只有 9902 拿到 → 9901 保留舊時刻；換日後清空；provider 一輪結束後 `state.fetchedAt` 同上。
- [ ] **Step 2**：`flutter test test/domain/services/live_quote/ test/presentation/providers/live_quote_provider_test.dart` → 編譯失敗。
- [ ] **Step 3: 實作**（只加欄位與賦值）。
- [ ] **Step 4**：同 Step 2，另跑 `flutter test test/presentation/`（既有報價中心相關測試不改仍綠）→ PASS。

### Task 4: 選取狀態與熱力圖即時檢視

**Files:** Create `lib/presentation/providers/heatmap_live_provider.dart`；Test 新增 `test/presentation/providers/heatmap_live_provider_test.dart`

**Interfaces:**
```dart
typedef HeatmapSelection = ({String market, String? zoom});
final heatmapSelectionProvider =
    NotifierProvider.autoDispose<HeatmapSelectionNotifier, HeatmapSelection>(...);
// selectMarket(String)：換市場並清掉放大；zoomTo(String key)；clearZoom()

@immutable
class HeatmapLiveView {           // 定義 == 與 hashCode（資料、模式、登記〔listEquals〕、狀態、進度）
  final HeatmapMarketData? data;  // 套上即時後；不需要即時或停市退回時是正式資料；沒有正式資料為 null
  final HeatmapLiveMode? mode;
  final List<LiveQuoteRegistration> stockRegistrations; // 不含指數；hasOfficialToday 一律 false
  final LiveHeaderStatus? quoteStatus;
  final ({int done, int total})? closing;
}

final heatmapLiveProvider =
    NotifierProvider.autoDispose<HeatmapLiveNotifier, HeatmapLiveView>(...);
```
規則：
- `build` watch `heatmapSelectionProvider`、`marketHeatmapProvider.select((s) => s.markets[market])`、`liveQuoteCenterProvider`、`liveQuoteBoundaryProvider`；`now` 用 `appClockProvider`。
- `mode = heatmapLiveModeAt(...)`；null → `data` 原樣、其餘空或 null。
- `registered = heatmapLiveSymbols(...)`。欄位 `_since: Map<String, DateTime>`（Notifier 實例跨 build 保留）逐檔記「該檔進入 `registered`」的時刻：新進清單的記 `now`、離開清單的移除；另記 `_sinceDay`（記錄所屬的日期），`now` 換日時整個清空（頁面被蓋住過夜時 provider 暫停、沒有重算，回來時第一次 build 才換日）；頁面可見性不影響（差異 9）。`fresh` ＝ `registered` 中 `fetchedAt[s]` 不早於 `_since[s]` 的代號。
- **停市日退回**：`center.latestResponseHadToday == false` 且**整個市場圖上所有代號**（不論放大）都沒有今天的報價（`entries[s]?.date` 不是今天）→ `data` 用正式資料（`data.liveMode == null`）、`closing` null、`stockRegistrations` 照常（要靠它們拿到今天的報價才離開退回）、`quoteStatus` ＝`header` 的結果若是 `pausedRateLimit`／`pausedNetwork` 就用它，否則 `LiveHeaderStatus(LiveHeaderKind.noQuotesToday)`。
- 盤中（沒有退回）`quoteStatus = LiveQuoteStatusRule.header(state: center, merged: [registered 各檔 LiveQuoteMerge.merge(official: OfficialPrice(date: data.dataDate, close: tile.close), live: fresh ? entries[s] : null, now: now)], intradayTime: center.latestQuoteTime)`。
- 收盤後（沒有退回）`quoteStatus` 只保留 `header` 的 `pausedRateLimit`、`pausedNetwork`（`noQuotesToday` 只由上面的退回規則產生：收盤後 `registered` 只剩還沒拿到收盤報價的，用它判斷會誤報）；`closing.total` ＝整個市場圖上的檔數（不論放大、合併），`done` ＝其中今天有收盤報價的檔數。
- 新舊 `data` 相等時沿用舊的物件（`HeatmapView` 以 identity 快取佈局，避免每次 publish 都重排）。

- [ ] **Step 1: 寫失敗的測試**（`ProviderContainer`；`marketHeatmapProvider`、`liveQuoteCenterProvider` 用固定狀態的假 notifier，可換狀態；`appClockProvider` 固定時刻可改）
  - 週一 10:30、資料日上週五 → `intraday`、69 檔登記、`hasOfficialToday` 全 false、市場別正確。
  - 開頁 10:00，`fetchedAt` 10:05 的格子上色、09:40 的 `notLive`。
  - 全市場 → 放大半導體業 → 取消放大：一直在清單裡的 9901（`fetchedAt` 10:05、放大前已登記）全程上色；放大時才進清單的 9950（`fetchedAt` 09:40）`notLive`。
  - 離開清單後移除：9960 在全市場清單、不在放大的產業裡；10:10 放大，10:12 它被別的畫面抓到（`fetchedAt` 10:12），10:15 取消放大 → 9960 是 `notLive`（`_since` 是 10:15），直到 `fetchedAt` 不早於 10:15。
  - 13:35 → `afterClose`；前 69 大裡 3 檔已有收盤報價 → 登記其餘的前 69、`closing == (done: 3, total: 圖上檔數)`；放大後 `closing.total` 不變。
  - 13:35、`rateLimitedUntil` 有值 → `pausedRateLimit`；中心沒有暫停 → `quoteStatus == null`。
  - 盤後資料寫入（假 notifier 換成資料日今天）→ `mode == null`、登記空、`data` 是原資料。
  - 盤中 `stalled` → `pausedNetwork`，已上色的格子不變。
  - 盤中跨 13:30（改時刻後 `invalidate(liveQuoteBoundaryProvider)`）→ 盤中最後一筆的格子變 `noClosingQuote`。
  - 換日：10:05 抓到 9901（`_since` 10:00）；改成隔天 09:10、9901 的 `fetchedAt` 是隔天 09:05（別的畫面抓的）→ 9901 是 `notLive`（`_since` 在換日時清空、重記為 09:10）。
  - 停市日：`latestResponseHadToday == false`、整個市場都沒有今天報價 → `data` 等於正式資料、`data.liveMode == null`、`quoteStatus.kind == noQuotesToday`；盤中與收盤後都一樣；同時限流時 `quoteStatus.kind == pausedRateLimit`；退回期間 `stockRegistrations` 不是空的、`closing == null`。
  - 不誤退回：收盤後 `latestResponseHadToday == false`（最近一輪只問了拿不到報價的股票），但圖上已有今天的收盤報價 → 不退回、`closing.done > 0`、`quoteStatus` 不是 `noQuotesToday`；放大到一個沒有任何收盤報價的產業時同樣不退回（範圍是整個市場）。
  - 開盤頭幾秒退回後，第一筆今天的報價一到就離開退回。
  - 中心狀態換新但內容相同時 `HeatmapLiveView` 相等（`==`），而且 `data` 是同一個物件（`identical`）。
- [ ] **Step 2**：`flutter test test/presentation/providers/heatmap_live_provider_test.dart` → 編譯失敗。
- [ ] **Step 3: 實作**。
- [ ] **Step 4**：同 Step 2 → PASS。

### Task 5: 熱力圖頁接上即時

**Files:** Modify `market_heatmap_screen.dart`、`heatmap_text.dart`、`heatmap_painter.dart`、`heatmap_view.dart`、`heatmap_tooltip.dart`、`heatmap_other_sheet.dart`、`heatmap_industry_group_sheet.dart`、翻譯檔、`CHANGELOG.md`；Test `market_heatmap_screen_test.dart`、`heatmap_painter_test.dart`、`heatmap_view_test.dart`、兩個 sheet 的測試、`heatmap_text_test.dart`

**Interfaces（`heatmap_text.dart`）：**
- `int heatmapCoveragePercent(double coverage)`：四捨五入到整數後夾在 1～99（`coverage` 恰為 0 或 1 時不夾）；圖上與無障礙的比例都用它。
- `String heatmapCoverageSuffix(double coverage, HeatmapLiveMode mode)`：「・即時 {pct}%」／「・收盤 {pct}%」。
- `String heatmapNoChangeText(HeatmapLiveMode? mode)`：盤中「未即時」、收盤後「未收盤」、正式資料「無漲跌資料」。
- `String heatmapLiveStatusText(HeatmapLiveView view)`：有 `quoteStatus` 時它的文字放在最前面；收盤後（沒有退回）再以翻譯檔的分隔字接「今日收盤 {done}／{total} 檔・待盤後更新」；盤中與退回只有 `quoteStatus` 的文字；都沒有回空字串（不顯示）。
- 圖上文字、painter、產業選單、提示、兩個 sheet、無障礙描述的模式一律取 `data.liveMode`（停市退回時是 null，不是 `view.mode`）；唯一看 `view.mode` 的是指數列（見 Step 3）。`HeatmapPainter` 新增欄位 `liveMode`（`HeatmapLiveMode?`，納入 `shouldRepaint`）；`HeatmapPaintLabels` 新增 `coverageSuffix`（`String Function(double coverage, HeatmapLiveMode mode)`）與 `noChangeLabel`（`String Function(HeatmapLiveMode mode)`），painter 依自己的 `liveMode` 呼叫；`liveMode == null`（正式資料）時兩者都不呼叫，產業標題與合併塊標籤維持第 1 段（golden 不變）。`industrySemantics`、合併塊與群組的無障礙描述函式改收 `(layout, HeatmapLiveMode? mode)`；`HeatmapPaintLabels` 的 `==`／`hashCode` 納入新函式。畫面的 `_labels` 仍只依語系建一次。無障礙描述的即時比例子句用不帶「・」的鍵（`semLiveCoverage`「即時部分占 {pct}%」、`semClosingCoverage`「已收盤部分占 {pct}%」），報讀軟體才不會念出符號。
- 產業標題列與合併塊標籤在寬度不夠時**先捨掉即時比例**，再照第 1 段的規則捨掉漲跌幅。
- 翻譯鍵（zh／en 都加）：`liveCoverage`、`closingCoverage`、`semLiveCoverage`、`semClosingCoverage`、`notLive`、`notClosed`、`previousClose`「{date} 收盤 {pct}」、`closingProgress`、`statusJoin`「・」。修改既有鍵：`tooltipBreadthWithHollow` 改為「漲 {up}、跌 {down}、平 {flat}、空心 {hollow}」；`semOtherWithHollow` 的計數改為「沒有今日漲跌 {hollow}」；`semIndustryNoChange`、`semOtherNoChange` 裡寫死的「無漲跌資料」改成 `{status}` 參數（正式資料傳「無漲跌資料」、盤中「未即時」、收盤後「未收盤」）。

- [ ] **Step 1: 寫失敗的測試**
  - 登記（`market_heatmap_screen_test.dart`）：盤中 `LiveQuoteScope.registrations` ＝目前市場的指數 1 個＋`stockRegistrations`；切到上櫃後換成上櫃指數＋上櫃清單；不含另一個市場的指數。
  - 狀態行：盤中顯示 `quoteStatus` 文字、這時指數列不再顯示自己的報價狀態、右側不顯示「M/D 收盤」；收盤後指數已是今天、盤後資料還是前一天時，頁面不出現「指數為 M/D 收盤」；沒有狀態時不顯示這一行；收盤後「今日收盤 3／120 檔・待盤後更新」，限流時限流文字在前、進度在後；停市退回時（盤中 10:30 與收盤後 13:40 各一次）顯示「證交所今天尚無報價」、沒有「今日收盤 N／M 檔」、保留右側「M/D 收盤」——這時指數本身的報價狀態也是「證交所今天尚無報價」（測試讓指數真的帶這個狀態，不 override 掉），整頁這句 `findsOneWidget`；正式資料模式維持第 1 段（沒有這一行、有「M/D 收盤」）。
  - 離開再回來（差異 9）：照現有可見性那組測試的寫法用真的 go_router，盤中放大到某產業、9901 已上色 （9901 的 `fetchedAt` 早於推頁時刻）→ 推一個不透明頁面、期間報價中心照常發布、發布內容不含 9901 的新報價 → pop 回來：仍在放大、市場不變、9901 仍上色（顏色是離開前的）。「可見性改變就清掉 `_since`」的突變由這條轉紅。
  - 跨模式重畫：13:29 開頁（盤中、產業標題有「・即時」）→ 時刻改 13:31 並 `invalidate(liveQuoteBoundaryProvider)` → 標題改成「・收盤」、沒有值的產業寫「未收盤」（painter 的 `liveMode` 跟著換）。
  - 窄螢幕：狀態行 `maxLines: 2`＋省略號在結構上不會溢位；要防的是暫停、限流文字被截掉，由 `heatmapLiveStatusText` 的純函式測試釘住「暫停在前、進度在後」。不寫量真實字寬的測試（CI 在 Linux、沒有可載的系統字型）；360 寬的實際樣子在 Task 7 實機看。
  - 產業選單：盤中 +1.83%、即時 0.96 → 「+1.83%・即時 96%」；即時 0.004 → 「・即時 1%」；全部未即時 → 「未即時」；正式資料模式沒有值時維持第 1 段的「—」。
  - painter：盤中產業標題含「・即時」；窄到放不下時先捨掉即時比例、保留漲跌幅；同一份佈局、只換 `liveMode` 時 `shouldRepaint` 為 true（`liveMode` 進 `shouldRepaint` 的突變由這條釘住）。
  - 提示：`notLive` 帶 `previous` → 「盤中未即時」＋「11/6 收盤 -0.80%」（`formatHeatmapPercent` 的 ASCII 減號）；`previous == null` → 只有原因；其餘原因各自的文字；合併塊提示寫「空心 N」並帶即時比例；群組提示同。
  - 提示跟著新資料：滑鼠停在 9901 上、提示顯示 +3.00%，換一份即時資料（9901 變 +3.50%、面積不變）→ 同一次 pump 後提示仍在、顯示 +3.50%（不空白一幀）。既有測試「佈局換了時舊提示消失」（`heatmap_view_test.dart`）改寫成：同一座標查不到格子（例如放大後該處是別的產業標題或空白）才收起。
  - 合併塊標籤：盤中「其他 12 檔 +0.50%・即時 30%」；窄到放不下時先捨比例。
  - 無障礙：盤中產業描述含即時比例（不含「・」，比例 0.004 念「1%」）；未即時產業說「未即時」而不是「無漲跌資料」；合併塊描述寫「沒有今日漲跌 N」；盤中整塊空心的合併塊描述寫「未即時」。
  - 兩個 sheet：成員列空心時寫該格的原因（盤中「盤中未即時」），漲跌與比例經 `heatmap_text.dart`。
- [ ] **Step 2**：`flutter test test/presentation/screens/market/ test/presentation/widgets/heatmap/` → FAIL。
- [ ] **Step 3: 實作**
  - 畫面的 `_market`／`_zoom` 改讀寫 `heatmapSelectionProvider`。
  - `LiveQuoteScope.registrations` ＝ `marketIndexRegistrations(overview, now).where((r) => r.market == market)` ＋ `view.stockRegistrations`；圖、選單、頁尾用 `view.data`；`HeatmapView`／painter 傳 `view.data?.liveMode`。
  - 狀態行放在指數列下方（`maxLines: 2`、省略號）。`view.mode != null`（即時時段，含停市退回）時指數列下方整個狀態欄位都不顯示——包括報價狀態與「指數為 M/D 收盤」（`_IndexHeader` 的 `shown?.statusText ?? closeOf` 兩者都不給；收盤後 14:00 起總覽已有今天的指數，否則會冒出「指數為今天收盤」）；`data.liveMode != null`（圖用即時上色）時右側不顯示「M/D 收盤」，停市退回時保留。
  - `HeatmapView`：佈局換了而提示還開著時，在提示層的 builder 裡用新佈局對同一個座標同步查找（純計算）並畫出；幀結束後再把結果寫回 `_hover`（`addPostFrameCallback`，不在 build 期間改 notifier）；查不到才收起。
  - 產業選單、painter 標題、兩個 sheet、三種提示、無障礙描述的「漲跌＋即時比例／沒有值」全部經 `heatmap_text.dart` 或 `HeatmapPaintLabels`；`semIndustry` 保留「方向＋百分比」句型，另接即時比例子句。
  - CHANGELOG「Added」：熱力圖盤中即時、收盤後逐批取得收盤報價。
- [ ] **Step 4**：`flutter test test/presentation/ test/core/`（含 `no_investment_advice_copy_test` 與第 1 段的熱力圖寫死中文掃描）、`flutter analyze` → PASS。

### Task 6: 報價中心整合（spec「驗證」2）

**Files:** Test 新增 `test/presentation/providers/heatmap_live_integration_test.dart`

**Interfaces:** 真的 `LiveQuoteCenter`（覆寫 `liveQuoteClientProvider` 為假 client、`appClockProvider` 為隨 `fakeAsync` 前進的時鐘）＋Task 4 的 provider；以 `container.listen(heatmapLiveProvider, ...)` 在結果變動時呼叫 `center.register(owner, [目前市場指數, ...view.stockRegistrations])`，模擬 `LiveQuoteScope`。

- [ ] **Step 1: 寫測試**（上市規模 1,078 檔，虛構代號以英文字母開頭；13:31 開始）
  - 假 client 對每個請求回收盤報價 → 模擬時間 4 分 30 秒內 `closing.done == closing.total`；第一輪拿到的是市值前 69。
  - 其中 20 檔一律回無報價 → 這 20 檔被請求恰好 `LiveQuoteParams.afterCloseMaxAttempts` 次後不再出現在請求裡；其餘 1,058 檔在 6 分鐘內全部填滿；之後 `view.data.liveMode == afterClose`、`closing == (done: 1058, total: 1078)`、`quoteStatus` 不是 `noQuotesToday` 也不是 `pausedNetwork`（最近一輪只問這 20 檔時 `latestResponseHadToday` 是 false，不得誤退回）。
  - 跨過一次 CLI 避讓窗口、某一輪回應延遲 10 秒 → 全程沒有 `pausedNetwork`，6 分鐘內填滿。
  - 某一輪回限流 → `rateLimitedUntil` 過後繼續，`rateLimitedUntil` ＋ 5 分鐘內填滿；中間 App 不可見一輪 → 回到可見後繼續，6 分鐘內填滿。
- [ ] **Step 2**：`flutter test test/presentation/providers/heatmap_live_integration_test.dart` → PASS。本段沒有新的正式程式碼：失敗代表 Task 2／4 的清單或與報價中心的互動有問題，回頭修對應 Task 並補單元測試。

### Task 7: 全套驗證、mutation、實機、審查、經同意提交

- [ ] **Step 1**：`flutter test`、`flutter analyze`、`scripts/test_time_shift.sh 90 <本段改動的測試檔>` 全綠；`flutter test --tags golden` 本機跑（正式資料模式的熱力圖 golden 應不變，有差異先查原因）。
- [ ] **Step 2：mutation**（每項各拔一次，記錄哪條測試轉紅，寫進本計畫末「實作後的修正」）：`overlayHeatmapLive` 的 `fresh`、`registered`、`trialOrBook`、報價日期、`y ≤ 0`、收盤後 `isClosingQuote`、`baseCap` 改回反推、`coverage` 分母；`heatmapLiveModeAt` 各分支；`heatmapLiveSymbols` 的放大、收盤後排除、日期；`fetchedAt` 只記今天報價與換日清空；`_since` 的新進記時、離開移除、換日清空；指數列不顯示自己狀態的條件（`view.mode`）；停市日退回（含「整個市場、不論放大」的範圍）；退回期間照常登記個股；右側「M/D 收盤」的條件（`data.liveMode`，退回時保留）；收盤後只保留兩種暫停；painter 的 `liveMode` 進 `shouldRepaint`；新舊相等時沿用 `data` 物件；只登記目前市場的指數；比例夾 1～99；窄標題先捨即時比例；提示重新查找。
- [ ] **Step 3：實機**（11/9 週一，spec「驗證」7；另把視窗縮到 360 寬看狀態行，中英文各一次）：盤中前 69 檔每 15 秒變色、其餘空心；放大小產業後整個產業下一輪變色；開盤初期沒成交的格子空心；產業與合併塊的「・即時 N%」；滑鼠停在格子上提示不消失。13:30 之後狀態行「今日收盤 N／M 檔」約 4 分鐘接近填滿、大格子先；盤後寫入後一分鐘內回到「M/D 收盤」。除權息日（有的話）該檔盤中漲跌幅與盤後資料庫一致。結果寫進本計畫末。
- [ ] **Step 4：審查**：整段送 `pr-review-toolkit:code-reviewer`（opus），Critical／Important 修完；Minor 依風險當段修或記錄。
- [ ] **Step 5：使用者說「提交」後一次提交**（`feat: 熱力圖盤中即時與收盤後逐批取得收盤報價`，內文寫改了什麼、為什麼）。

## 順帶發現（範圍外，記錄不修）

- 交易日曆是寫死的表，颱風停市（例：2026-10-23）不在表上。熱力圖這邊由 Task 4 的「停市日退回」處理；歷史回補 Phase 0 每輪把這種日子當成缺漏的既有行為見 `.claude/rules/update-pipeline.md`「日曆漏標的休市日」，不在本段範圍。

## 計畫審查紀錄

- 2026-11-07 第一次審查（opus）：0 Critical、6 Important、多項 Minor，全部納入本版：提示每輪消失（Review Focus 7、Task 5）、停市日全空心（Review Focus 6、差異 8、Task 4）、合併塊只靠少數成員上色（差異 4、Task 1 的 `coverage`）、頁首溢位與重複（差異 7、Review Focus 8、Task 5）、開始即時的時刻改為逐檔（Task 4 的 `_since`）、新列舉值讓畫面的 switch 編譯不過與空心文字未集中（Task 1 的 `heatmap_text.dart`）；Minor：差異 1 措辭、選單沒有值維持「—」、無障礙不用「空心」、測試數值（−0.25%、ASCII 減號、`closeTo`）、比例夾 1～99、文字經 `HeatmapPaintLabels`、窄標題先捨比例、`closing.total` 定義、即時模式不再顯示「指數為 M/D 收盤」、跨 9:00 與午夜、底部清單是快照、Task 6 加時間上限與試滿後不再請求、`liveTileLimit` 改驗關係式、`hollowCount` 改為修改既有兩個鍵。
- 2026-11-07 第二次審查（opus）：0 Critical、3 Important、11 項 Minor，全部納入本版：頁面可見性改變不觸發重算、`_since` 時機不可預期 → 改為可見性不影響、離開回來最多一輪舊色（差異 9，拿掉 `setPageVisible`）；停市退回的判斷範圍收盤後會誤判 → 改看整張圖、補反向測試與 Task 6 斷言；依模式變化的文字被只依語系建一次的 `_labels` 鎖住 → painter 帶 `liveMode`、文字函式收模式、補跨 13:30 的畫面測試；Minor：提示同步重查不空白一幀、既有測試改寫、新舊相等沿用物件、合併塊圖上標比例、`semIndustryNoChange`／`semOtherNoChange` 改參數、狀態句暫停在前且量行數、`_since` 離開移除的測試、比例同迴圈累加、即時時隱藏右側日期而退回時保留、退回時的狀態優先序、開盤頭幾秒退回後離開的測試。
- 2026-11-07 第三次審查（opus）：第二次的 3 項 Important 確認解決；新增 1 Important、7 Minor，經使用者同意後納入本版：停市退回時指數列與狀態行重複「證交所今天尚無報價」→ 指數列不顯示自己狀態的條件改看 `view.mode`、測試讓指數真的帶該狀態並斷言只出現一次；Minor：差異 9 補推頁再返回的畫面測試、窄螢幕改用真字型量 `didExceedMaxLines`、`liveMode` 進 `shouldRepaint` 改由 painter 單元測試釘住、停市判斷寫明「整個市場（不論放大）」並補放大變體、退回期間照常登記個股、無障礙比例子句用不帶「・」的鍵、`_since` 換日清空（過夜回來不用別的畫面早上抓的價）、措辭與 `==`（`listEquals`、`HeatmapPaintLabels`）。
- 2026-11-07 第四次審查（opus，只看第三次的修正）：第三次的 Important 確認解決；新增 1 Important、8 Minor，經使用者同意後納入本版、不再開第五輪（實作時每個 Task 仍各自送審）：窄螢幕真字型測試在 CI（Linux）沒有字型可載 → 拿掉，改以結構（兩行＋省略號）與「暫停在前」的純函式測試保證，360 寬在 Task 7 實機看；Minor：Review Focus 3、6 補 Task 5、模式來源的「一律」限定範圍並註明指數列例外、即時時段指數列整個狀態欄位不顯示（含「指數為 M/D 收盤」）並補測試、停市範圍措辭統一、無障礙比例鍵入清單與共用 `heatmapCoveragePercent`、突變清單補右側日期條件與退回期間照常登記、差異 9 測試寫明前提、退回期間 `closing == null` 與盤中／收盤後各一次的畫面測試。
