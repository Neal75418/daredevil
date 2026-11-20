# 大盤熱力圖精簡（市值前 30 檔）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 大盤熱力圖改成每個市場一張不分產業的圖，只畫市值前 30 檔，每格寫股名、價格、漲跌幅。

**Architecture:** 資料層在排除規則之後取市值前 N 檔並算出覆蓋率，`HeatmapMarketData` 從「產業 → 格子」兩層改成一層 `tiles`。版面改單層 squarify；即時套色、登記清單、收盤進度都直接走 `tiles`。產業區塊、放大、產業選單、合併塊與它們的清單面板連同測試一起刪除。

**Tech Stack:** Flutter／Dart 3、Riverpod 3（`pubspec.lock` 鎖定的版本）、`CustomPainter`、easy_localization、flutter_test（含 golden）。

**Spec:** `docs/plans/2026-11-19-market-heatmap-top30-design.md`

## Global Constraints

- 圖上的檔數：`HeatmapParams.topTileCount = 30`；可畫的不足 30 檔時全部畫。
- 「最多 30 檔」只由 `buildHeatmapMarket` 保證。它之後的每一層（即時套色、登記清單、收盤進度、版面、繪製）都照 `HeatmapMarketData.tiles` 給的全部處理，不自己再取前 30；直接建 `HeatmapMarketData` 的測試給幾檔就是幾檔。唯一的例外是登記清單另以 `liveTileLimit` 為保險上限（Task 2 Step 3）。
- `topTileCount ≤ HeatmapParams.liveTileLimit`（69），以測試釘住。「一輪一個請求」是 30 檔時的結果，不是要求，不釘。
- 排除規則、漲跌算法、色階、空心原因、內容指紋輪詢、報價中心、`LiveQuoteScope.listen` 的行為都不改。
- 覆蓋率的百分比用既有的 `heatmapCoveragePercent`。
- 畫面上的字一律走翻譯檔（`heatmap_no_hardcoded_cjk_test` 會擋）；中、英兩份都要改。
- 讀「現在」用 `DeviceTime.now()` 或注入的 `AppClock`；測試慣例照 `test/CLAUDE.md`。
- 註解只寫現在式的「做什麼／為什麼」，不寫日期、審查編號、改動歷史。
- `flutter analyze` 全專案無訊息（info 也擋）。
- 流程：實作者不 commit；每個 Task 做完送 `pr-review-toolkit:code-reviewer`（opus）審查，Critical／Important 修完才進下一個 Task；使用者說「提交」才提交。直接在 `main` 上做，不開分支、不建 worktree。
- 每條新測試先看到紅再實作；突變還原用寫回原內容並逐位元組比對，不用 `git checkout`。

## Review Focus

1. 可畫的股票不足 30 檔 → 全部畫，圖例的檔數寫實際數，覆蓋率寫 100%。（Task 1 Step 1 第 3 條、Task 2 Step 11）
2. 前 30 檔裡有空心格（盤中暫停交易、收盤沒撮合）→ 只寫股名、不寫價格；收盤後頁首的檔數對得上。（Task 1 Step 1 第 9 條、Task 2 Step 6 與 Step 13）
3. 圖區極小或極扁（視窗縮到很小）→ 不丟例外，寫不下字的格子不寫。（Task 1 Step 1 第 6 條、Task 2 Step 9）
4. 正式資料重讀後前 30 名換人，而滑鼠正停在某一格 → 提示照新版面在同一個位置重查，不指著已經不在那裡的股票。（Task 2 Step 9）
5. 上市、上櫃來回切換 → 登記清單立刻換成另一個市場的檔與指數，前一個市場的不殘留。（Task 2 Step 5）

---

### Task 1: 新的純函式與參數（先加，不接線）

做完後 App 行為不變，全套測試照綠。

**Files:**
- Modify: `lib/core/constants/heatmap_params.dart`
- Modify: `lib/domain/services/heatmap/heatmap_grouping.dart`
- Modify: `lib/domain/services/heatmap/heatmap_layout.dart`
- Modify: `lib/presentation/widgets/heatmap/heatmap_painter.dart`（`heatmapTileLines`）
- Test: `test/core/constants/heatmap_params_test.dart`、`test/domain/services/heatmap/heatmap_grouping_test.dart`、`test/domain/services/heatmap/heatmap_layout_test.dart`、`test/presentation/widgets/heatmap/heatmap_painter_test.dart`

**Interfaces:**
- Produces:
  - `HeatmapParams.topTileCount`（`static const int`，值 30）
  - `({List<HeatmapTile> tiles, double coverage}) heatmapTopTiles(Iterable<HeatmapTile> all, {required int count})`
  - `List<HeatmapTileLayout> layoutHeatmapTiles(List<HeatmapTile> tiles, {required double width, required double height})`
  - `HeatmapTileLayout? heatmapTileAt(List<HeatmapTileLayout> layout, double x, double y)`
  - `({bool name, bool price, bool percent}) heatmapTileLines({required bool nameFits, double? priceWidth, required double? percentWidth, required double lineHeight, required double width, required double height})`

- [ ] **Step 1: 寫會紅的測試**（測試資料照各測試檔既有的建法）

  `heatmap_params_test.dart`
  1. 「圖上的檔數不超過一輪能登記的檔數」：`expect(HeatmapParams.topTileCount, lessThanOrEqualTo(HeatmapParams.liveTileLimit))`，並 `greaterThan(0)`。

  `heatmap_grouping_test.dart`，group「heatmapTopTiles」
  2. 「市值由大到小取前 count 檔；同值依代號由小到大」：依 `A=50, D=30, B=30, C=20` 的順序傳入（D 在 B 前面：32 筆以內 Dart 用穩定的插入排序，照代號順序傳入的話不比代號也會綠），`count: 3` → 代號依序 `['A', 'B', 'D']`。
  3. 「不足 count 檔時全部回傳，覆蓋率恰為 1.0」：市值 `0.1, 0.2, 0.3` 由小到大傳入（整數市值加總順序不影響結果，釘不住）、`count: 30` → 3 檔，`expect(coverage, 1.0)`（不是 `closeTo`；差一個位元會被 `heatmapCoveragePercent` 寫成 99%）。
  4. 「覆蓋率＝取到的市值 ÷ 全部市值」：市值 `60, 30, 10`，`count: 2` → `closeTo(0.9, 1e-12)`。
  5. 「沒有任何一檔，或全部市值不是有限正數」→ `tiles` 為空、`coverage == 0`。

  `heatmap_layout_test.dart`，group「layoutHeatmapTiles」
  6. 「圖區沒有面積、不是有限數、或沒有格子 → 空清單」：`width: 0`、`height: double.infinity`、空清單三種各一個 `expect(..., isEmpty)`；另加 `width: 3, height: 2` 放 30 檔不丟例外、回 30 筆。
  7. 「面積與市值成比例、鋪滿圖區、互不重疊」：市值 `6, 3, 1`、`width: 100, height: 50` → 各格 `bounds` 面積 `closeTo(3000／1500／500, 1e-6)`，三格面積合計 `closeTo(5000, 1e-6)`，任兩格 `bounds` 的交集面積為 0。
  8. 「實際畫的矩形四邊各內縮半個格子間隔；短邊小於 `minInteractiveSide` 的不互動」；以及 `heatmapTileAt`：點在某格 `paint` 內回那一格，點在格子間隔上回 null，點在不互動的格子上回 null。

  `heatmap_painter_test.dart`，group「heatmapTileLines」（既有的幾條斷言補上 `price: false`）
  9. 新增四條，`lineHeight: 10, width: 100`：
     - `height: 30, priceWidth: 40, percentWidth: 50` → `(name: true, price: true, percent: true)`
     - `height: 29`，其餘同上 → `(name: true, price: false, percent: true)`（放不下三行先省價格）
     - `height: 30, priceWidth: 120, percentWidth: 50` → `(name: true, price: false, percent: true)`（價格太寬）
     - `height: 30, priceWidth: 40, percentWidth: null` → `(name: true, price: false, percent: false)`（空心格不寫價格）

- [ ] **Step 2: 跑測試確認是紅的**

  Run: `flutter test test/core/constants/heatmap_params_test.dart test/domain/services/heatmap/heatmap_grouping_test.dart test/domain/services/heatmap/heatmap_layout_test.dart test/presentation/widgets/heatmap/heatmap_painter_test.dart`
  Expected: 編譯失敗（`topTileCount`、`heatmapTopTiles`、`layoutHeatmapTiles`、`heatmapTileAt` 未定義；`heatmapTileLines` 沒有 `priceWidth` 參數）。

- [ ] **Step 3: 實作**
  - `HeatmapParams.topTileCount`。
  - `heatmapTopTiles`：排序用同檔既有的 `_byCapThen`；取到的市值與全部市值在同一個迴圈、同樣順序累加，全部都取時比例才會恰為 1.0（與 `heatmapValueCoverage` 同一個手法）。
  - `layoutHeatmapTiles`：`squarify` 切整個圖區、每格用既有的 `_layoutTile`；輸入檢查照 `layoutHeatmap` 的條件。
  - `heatmapTileAt`：只回 `interactive` 的格子，命中判斷用既有的 `_contains` 對 `paint`。
  - `heatmapTileLines`：`price` 只在 `percent` 為 true、`priceWidth` 不是 null 且 `≤ width`、`3 × lineHeight ≤ height` 時為 true；`name`、`percent` 的規則不變。既有呼叫端不傳 `priceWidth`，行為不變。

- [ ] **Step 4: 跑測試確認轉綠**

  Run: Step 2 的指令，再跑 `flutter analyze`、`flutter test`
  Expected: 全部通過；`flutter analyze` 顯示 `No issues found!`。

- [ ] **Step 5: 突變（各拔一次，看到對應的測試轉紅後還原）**
  - `heatmapTopTiles` 同值時不比代號；覆蓋率的分母改成只算取到的；全部市值改成照傳入的順序另外加一次（與取到的不同順序）；
  - `layoutHeatmapTiles` 不內縮；`heatmapTileAt` 也回不互動的格子；
  - `heatmapTileLines` 的 `3 × lineHeight` 改成 `2 ×`；拿掉「`percent` 為 true」這個條件。

- [ ] **Step 6: 送審**（實作者不 commit）

---

### Task 2: 換成單層圖

這個 Task 會讓上層暫時編譯不過，所以由下往上一層一層做：每一層先改該層的測試、看到紅、再改程式，跑該層的測試檔。全套測試與 `flutter analyze` 在 Step 16 才要求全綠。

**Files:**
- Modify: `lib/domain/models/heatmap.dart`、`lib/domain/services/heatmap/heatmap_grouping.dart`、`lib/domain/services/heatmap/heatmap_layout.dart`、`lib/domain/services/heatmap/heatmap_live.dart`
- Modify: `lib/presentation/providers/heatmap_live_provider.dart`
- Modify: `lib/presentation/widgets/heatmap/heatmap_painter.dart`、`heatmap_text.dart`、`heatmap_tooltip.dart`、`heatmap_legend.dart`、`heatmap_view.dart`
- Modify: `lib/presentation/screens/market/market_heatmap_screen.dart`
- Modify: `assets/translations/zh-TW.json`、`assets/translations/en.json`
- Delete: `lib/presentation/widgets/heatmap/heatmap_other_sheet.dart`、`lib/presentation/widgets/heatmap/heatmap_industry_group_sheet.dart`
- Delete: `test/presentation/widgets/heatmap/heatmap_other_sheet_test.dart`、`test/presentation/widgets/heatmap/heatmap_industry_group_sheet_test.dart`
- Test（改寫）: `test/domain/models/heatmap_test.dart`、`test/domain/services/heatmap/heatmap_grouping_test.dart`、`heatmap_layout_test.dart`、`heatmap_live_test.dart`、`test/presentation/providers/market_heatmap_provider_test.dart`、`heatmap_live_provider_test.dart`、`heatmap_live_integration_test.dart`、`test/presentation/widgets/heatmap/heatmap_painter_test.dart`、`heatmap_text_test.dart`、`heatmap_view_test.dart`、`test/presentation/screens/market/market_heatmap_screen_test.dart`、`market_heatmap_background_test.dart`、`test/presentation/screens/golden/market_heatmap_screen_golden_test.dart`、`test/helpers/heatmap_live_fixtures.dart`

**Interfaces:**
- Consumes: Task 1 的 `topTileCount`、`heatmapTopTiles`、`layoutHeatmapTiles`、`heatmapTileAt`、`heatmapTileLines`。
- Produces（之後各 Step 與 Task 3 都用這些名字）:
  - `HeatmapTile({symbol, name, industry, close, marketCap, change, isMine})`：新增 `final String? industry`（null 是未分類）；`baseCap` 拿掉。
  - `HeatmapMarketData({market, dataDate, tiles, capCoverage, excludedForShares, liveMode})`：`final List<HeatmapTile> tiles`（市值由大到小）、`final double capCoverage`（0～1）；`industries` 與 `HeatmapIndustry` 拿掉。
  - `List<String> heatmapLiveSymbols(HeatmapMarketData official, {required HeatmapLiveMode mode, required Map<String, LiveQuoteEntry> entries, required Set<String> closingGivenUp, required DateTime today})`：沒有 `zoomIndustryKey`；結果照 `official.tiles` 的順序，仍以 `HeatmapParams.liveTileLimit` 為上限。
  - `overlayHeatmapLive(...)`：參數不變，回傳的 `tiles` 與輸入同順序，`capCoverage` 照抄。
  - `heatmapSelectionProvider`：`NotifierProvider.autoDispose<HeatmapSelectionNotifier, String>`（維持 autoDispose：離開頁面後重新進來回到上市），狀態是市場代碼，方法只剩 `selectMarket(String market)`；`HeatmapSelection` typedef 拿掉。
  - `String formatHeatmapPrice(double price)`：放在 `heatmap_painter.dart`、`formatHeatmapPercent` 旁邊（`heatmap_text.dart` 已經 import painter，反過來放會成環）；小數 2 位，格子與提示共用。
  - `HeatmapPaintLabels({required Locale locale, required String Function(HeatmapTileLayout tile) tileSemantics})`：`locale` 進 `==`，換語系時語意才重建。
  - `HeatmapPainter({required List<HeatmapTileLayout> layout, required Brightness brightness, required HeatmapPaintLabels labels, required ValueChanged<String> onTileTap, String? fontFamily, List<String>? fontFamilyFallback})`。
  - `HeatmapView({required HeatmapMarketData data, required ValueChanged<String> onTileTap, required HeatmapPaintLabels labels, required String uncategorizedLabel})`。
  - `HeatmapTooltip({required HeatmapTile tile, required String industryName, required DateTime dataDate, required HeatmapLiveMode? liveMode})`：參數不變。
  - `HeatmapLegend({required int tileCount, required String marketLabel, required double coverage})`。
  - 翻譯鍵 `marketHeatmap.legendCoverage`：中文 `市值前 {count} 檔・占{market}市值 {pct}%`；英文 `Top {count} by market cap · {pct}% of {market} market cap`。

**資料層**

- [ ] **Step 1: 改寫 `heatmap_test.dart` 與 `heatmap_grouping_test.dart`**
  - 模型的相等性：`industry`、`capCoverage`、`tiles` 任一不同就不相等。
  - `buildHeatmapMarket`：
    - 「先排除再取前 30」：35 檔可畫的普通股，另加市值比它們都大的 ETF、存託憑證各 1 檔，與 1 檔缺股數的 → `tiles` 是普通股市值前 30，`excludedForShares == 1`。
    - 「每格帶產業別；空字串與 null 都是 null」。
    - 「覆蓋率＝前 30 檔市值 ÷ 全部可畫股票市值」：35 檔市值都相同 → `closeTo(30 / 35, 1e-12)`。
    - 既有的排除、漲跌幅、股數規則的斷言保留，改成從 `data.tiles` 找那一檔。
  - 產業分組、產業加權漲跌的測試刪除。

- [ ] **Step 2: 跑 `flutter test test/domain/models/heatmap_test.dart test/domain/services/heatmap/heatmap_grouping_test.dart`，確認編譯失敗；改 `heatmap.dart` 與 `heatmap_grouping.dart`**，再跑到綠。
  `buildHeatmapMarket` 照舊逐檔過濾，全部可畫的格子交給 `heatmapTopTiles(all, count: HeatmapParams.topTileCount)`。`heatmapWeightedChange`、`heatmapValueCoverage`、`heatmapAllNoClosingMatch`、`_industry` 在這一步刪除。

- [ ] **Step 3: 改寫 `heatmap_live_test.dart`，再改 `heatmap_live.dart`**
  - `heatmapLiveSymbols`：盤中回 `official.tiles` 的代號（照原順序）；收盤後只回還沒有今日收盤報價、也不在 `closingGivenUp` 的；給 80 檔時只回前 `liveTileLimit` 檔。放大產業的測試刪除。
  - `overlayHeatmapLive`：逐格判定的既有斷言保留（盤中與收盤後的每一種結果）；新增「`tiles` 的順序、`capCoverage`、`marketCap` 與輸入相同」。
  - 保留一條：即時價或昨收算出的平盤市值不是有限正數 → 空心 `noChangeData`（`baseCap` 欄位拿掉後，這個判斷改用區域變數，不能跟著消失）。
  - 產業加權、即時占比的測試刪除。

  Run: `flutter test test/domain/services/heatmap/heatmap_live_test.dart` → 綠。

- [ ] **Step 4: `heatmap_layout.dart` 刪到只剩單層**：留 `HeatmapBox`、`HeatmapTileLayout`、`layoutHeatmapTiles`、`heatmapTileAt`、`squarify` 與它們用到的私有函式；其餘（產業、合併塊、小產業合併、`HeatmapBreadth`、`tileAt`、`otherAt`、`smallIndustriesAt`、`industryHeaderAt`）連同 `heatmap_layout_test.dart` 裡對應的測試刪除。`squarify` 的測試保留。`HeatmapTileLayout.bounds` 的說明還在講產業與標題列，改成單層的說法。

  Run: `flutter test test/domain/services/heatmap/` → 綠。

**Provider**

- [ ] **Step 5: 改寫 `heatmap_live_provider_test.dart` 與 `market_heatmap_provider_test.dart`，再改 `heatmap_live_provider.dart`**（測試直接建 `HeatmapMarketData` 時就給 30 檔；「35 檔取前 30」只在 Step 1 測）
  - 「盤中登記的是圖上全部的檔」：30 檔的市場 → `stockRegistrations` 是這 30 檔、順序相同，全部 `hasOfficialToday == false`。
  - 「切到另一個市場，登記清單立刻換成那個市場的檔與指數」：上市 → 上櫃後，`heatmapRegistrationsProvider` 的值不含任何上市代號與加權指數。
  - 「沒有人聽之後重新讀，選擇回到上市」（釘住 autoDispose）。
  - 「收盤後的進度以圖上的檔數為分母」：30 檔中 25 檔有今日收盤報價、2 檔今天被放棄 → `closing == (done: 25, unmatched: 2, total: 30)`。
  - 既有的頁首狀態、停市日退回、30 秒放寬、跨日清空的測試保留，資料改成單層。放大相關的測試刪除。
  - `market_heatmap_provider_test.dart` 只改斷言讀資料的方式（`industries` → `tiles`）；`market_heatmap_provider.dart` 本身不用改。

  Run: `flutter test test/presentation/providers/heatmap_live_provider_test.dart test/presentation/providers/market_heatmap_provider_test.dart` → 綠。

**繪製與元件**

- [ ] **Step 6: 改寫 `heatmap_painter_test.dart`，再改 `heatmap_painter.dart`**
  - 「`formatHeatmapPrice(3955)` 是 `'3955.00'`、`formatHeatmapPrice(53.4)` 是 `'53.40'`」。
  - 「有漲跌值、夠大的格子畫三行：股名、價格、漲跌幅」；「高度只夠兩行時畫股名與漲跌幅，不是股名與價格」；「空心格子只畫股名」。價格用 3955（`3955.00`，7 個字）、漲跌幅用 `+1.00%`（6 個字）：測試字型下每個字一樣寬，字數相同就分不出第二行畫的是哪一段。沿用這個檔記錄繪製呼叫的做法，逐行比對寬度與置中位置。
  - 「每一個可互動的格子一個語意節點，標籤是 `labels.tileSemantics`，點了呼叫 `onTileTap`」；不互動的格子沒有節點。
  - 自選雙線框、色階、空心框的既有測試保留。產業標題、合併塊、`zoomed` 分層的測試刪除。
  - `HeatmapPainter` 只畫 `layout` 裡的格子；價格那一行是 `formatHeatmapPrice(tile.tile.close)`（即時套色後 `close` 已是即時價），只在有漲跌值的格子量、畫；`shouldRepaint`／`shouldRebuildSemantics` 比對剩下的欄位。

  Run: `flutter test test/presentation/widgets/heatmap/heatmap_painter_test.dart` → 綠。

- [ ] **Step 7: `heatmap_text.dart` 與翻譯**：加 `marketHeatmap.legendCoverage`（中、英）；`heatmapTooltipPriceText` 改用 `formatHeatmapPrice`。產業標題用的 `heatmapCoverageSuffix`、`heatmapCoverageSemantics`、`heatmapNoChangeText`、`heatmapWeightedText` 連同 `heatmap_text_test.dart` 裡的測試刪除；`heatmapCoveragePercent` 留著（圖例要用），說明改成現在的用途。

  Run: `flutter test test/presentation/widgets/heatmap/heatmap_text_test.dart` → 綠。

- [ ] **Step 8: `heatmap_legend.dart`**：最後一項換成 `marketHeatmap.legendCoverage`，`pct` 用 `heatmapCoveragePercent(coverage)`。測試放在 `market_heatmap_screen_test.dart`（Step 11）。

- [ ] **Step 9: 改寫 `heatmap_view_test.dart`，再改 `heatmap_view.dart` 與 `heatmap_tooltip.dart`**
  - 「點格子呼叫 `onTileTap`；點格子間隔沒有反應」。
  - 「滑鼠提示第二行是『代號 · 產業』；產業別是 null 時寫 `uncategorizedLabel`」。
  - 「資料換了（前 30 名換人）而滑鼠沒動：提示改指新版面同一個位置的那一格；那個位置沒有格子就收掉」。
  - 「圖區 3×2 時不丟例外」。
  - 版面快取：同一份 `data`（identity）與同樣大小不重排，沿用既有的測試手法。
  - 放大、產業標題、合併塊的測試刪除。

**頁面**

- [ ] **Step 10: 刪兩個清單面板與它們的測試**（Files 的 Delete 清單）。

- [ ] **Step 11: 改寫 `market_heatmap_screen_test.dart`，再改 `market_heatmap_screen.dart`**
  - 「圖例寫『市值前 30 檔・占上市市值 74%』；切到上櫃後寫『占上櫃市值 52%』」（載入真實中文翻譯；兩個市場的 `capCoverage` 給 0.74 與 0.52，值不同才驗得到有跟著換）。
  - 「可畫的只有 3 檔時圖例寫 3 檔、100%」。
  - 「標題列只有上市／上櫃切換，沒有產業選單」；「點格子進個股頁」。
  - 「App 看不見、畫面停止排程後，登記跟著 `heatmapRegistrationsProvider` 換」這一條保留，資料改成單層（收盤後抓到一檔、清單少一檔）。
  - 頁尾「N 檔缺股數或股數不一致，未列入」、讀取失敗、空狀態、頁首指數與即時狀態行的既有測試保留。
  - 放大、「← 全市場」、產業選單、兩個清單面板的測試刪除。
  - 頁面：拿掉 `_zoomTo`、`_clearZoom`、`_showOther`、`_showSmallIndustries`、`_dropMissingZoom`、`_industryMenu` 與產業／合併塊的語意文字；市場名稱沿用切換鈕的 `marketOverview.twse`／`marketOverview.tpex`。

**整合測試**

- [ ] **Step 12: `test/helpers/heatmap_live_fixtures.dart`**：`heatmapFixtureTwse()` 改成把 1,078 檔組成 `HeatmapMarketInput`、經 `buildHeatmapMarket` 產生（圖上因此只有市值前 30 檔，與正式程式同一條路）；補一個回傳「市值前 30 檔代號」的函式給斷言用；沒撮合的名單改成落在前 30 檔裡的 3 檔。

- [ ] **Step 13: 改寫 `heatmap_live_integration_test.dart`**
  - 刪除只有一輪多批才成立的三條：「一輪送到一半被限流」「不在背景收集的平台：一輪送到一半 App 不可見」「在背景收集的平台：一輪送到一半 App 看不見」。
  - 「前提：虛構代號各不相同；市值前 69 與代號排序的前 69 不同」改成前 30 的前提。
  - 「每檔都回收盤報價」改成：第一輪結束時圖上 30 檔全部是今日收盤，之後不再送請求；被請求的只有市值前 30 檔與指數。
  - 「20 檔整天沒成交」改成前 30 檔裡 2 檔整天沒成交 → 各被請求恰好 10 次後不再請求。
  - 「100 檔收盤那一盤沒撮合（多於登記上限 69）」改成前 30 檔裡 3 檔收盤沒撮合 → 每分鐘重試一次、各被請求恰好 `LiveQuoteParams.afterCloseMaxAttempts`（10）次後放棄；最後頁首是「今日收盤 27／30 檔・3 檔收盤沒撮合・待盤後更新」。
  - 新增「盤中每一輪的請求數是 ⌈(圖上檔數 ＋ 1) ÷ `ApiEndpoints.misBatchSize`⌉」。
  - 其餘（CLI 避讓、回應慢、逾時重抓、較舊快照的五條）保留，數字改成 30 檔的前提。

- [ ] **Step 14: 改寫 `market_heatmap_background_test.dart`**：13:25 起 App 看不見、熱力圖頁開著 → 13:31 前 27 檔收到今日收盤；3 檔收盤沒撮合的每分鐘重試一次，約 13:40 試滿 10 次放棄。測試跑到 13:45，斷言最後是「27／30・3 檔收盤沒撮合」、之後不再送請求、看不見期間 0 幀。名稱與說明不再寫「登記清單一路換下去」。

- [ ] **Step 15: 改寫 golden 測試的資料**（`market_heatmap_screen_golden_test.dart`）：單層 30 檔，含漲、跌、平盤各階與 1 檔空心、1 檔自選。

**收尾**

- [ ] **Step 16: 全部跑一次**

  Run: `flutter analyze`
  Expected: `No issues found!`

  Run: `flutter test`
  Expected: `All tests passed!`

  Run: `flutter test --update-goldens --tags golden test/presentation/screens/golden/market_heatmap_screen_golden_test.dart`，再不帶 `--update-goldens` 跑一次
  Expected: 通過；打開兩張圖確認是單層、三行字、沒有產業標題。

- [ ] **Step 17: 突變（各拔一次）**
  - `buildHeatmapMarket` 先取前 30 再排除；
  - `overlayHeatmapLive` 拿掉「平盤市值是有限正數」的判斷；
  - `heatmapLiveSymbols` 收盤後不排除已放棄的；
  - `heatmapSelectionProvider` 拿掉 autoDispose；
  - painter 兩行時改畫股名與價格；讓空心格子也寫價格；語意節點不看 `interactive`；
  - 圖例的檔數寫死 `topTileCount` 而不是實際檔數；
  - 提示的產業別一律寫未分類。

- [ ] **Step 18: 送審**（實作者不 commit）

---

### Task 3: 清掉殘留、文件、驗證

**Files:**
- Modify: `lib/core/constants/heatmap_params.dart`、`lib/core/theme/heatmap_colors.dart`、`lib/presentation/widgets/heatmap/heatmap_mine_mark.dart`、`assets/translations/zh-TW.json`、`assets/translations/en.json`、其餘由 Step 1 的搜尋結果決定
- Test: `test/core/constants/heatmap_params_test.dart`、`test/core/theme/heatmap_colors_test.dart`、`test/core/theme/semantic_colors_test.dart`
- Modify: `CHANGELOG.md`、`docs/plans/2026-10-07-market-heatmap-design.md`、`docs/plans/2026-11-09-mis-quote-freshness-design.md`、本計畫（檔尾「實作後的修正」）

**Interfaces:**
- Consumes: Task 2 的全部。
- Produces: 無新介面。

- [ ] **Step 1: 找出沒有人用的東西並刪除**
  - 對 `HeatmapParams` 的每個常數、`marketHeatmap.*` 的每個翻譯鍵、`lib/**/heatmap*` 裡每個公開的函式、類別與建構參數，各搜一次 `lib/` 的引用；只剩定義與測試在用的就刪（連同測試）。以搜尋結果為準，不照下面的清單盲刪。
  - 預期會刪的常數：`industryGap`、`industryHeaderHeight`、`industryHeaderMinWidth`、`industryHeaderMinHeight`、`foldMinSide`、`foldAspectAllowance`、`industryFoldMinSide`。
  - 預期會刪的翻譯鍵：`otherShort`、`otherLabel`、`semOther*`、`tooltipStocks`、`tooltipBreadth*`、`tooltipWeighted`、`wholeMarket`、`backToWhole`、`industryMenu`、`legendWeighted`、`semIndustry*`、`groupLabel`、`groupShort`、`semGroupLabel`、`liveCoverage`、`closingCoverage`、`semLiveCoverage`、`semClosingCoverage`、`semAppend`、`notLive`、`notClosed`、`tooltipMine`、`semWithMine`、`mineMark`。
  - 預期會刪的其他成員：`HeatmapColors.headerText`（連同 `heatmap_colors_test.dart`、`semantic_colors_test.dart` 裡對它的斷言）、`HeatmapMineMark.semanticLabel`。
  - 要保留的：`HeatmapColors.pageBackground` 與 `HeatmapColors.allFills`。拿掉產業標題列之後 `lib/` 裡沒有人引用它們，但它們是 `heatmap_colors_test.dart` 對比守門的基準（格子間隔露出的頁面底色、全部的填色），刪了守門測試也跟著沒了；`pageBackground` 的說明改成現在的用途。
  - 搜引用找不到、要直接改的說明文字：`HeatmapParams.liveTileLimit`、`HeatmapParams.liveRegistrationGrace`（不再有放大、一輪兩批的敘述）、`HeatmapParams.labelFontSize` 與 `HeatmapParams.textPadding`（還在講標題列）、`heatmapCoveragePercent`（現在給圖例的覆蓋率用）、`HeatmapLegend` 與 `heatmapRegistrationsProvider` 的類別說明、`live_quote_scope.dart` 類別說明裡「熱力圖收盤後抓到一批換下一批」那一句。

- [ ] **Step 2: 文件**
  - `CHANGELOG.md`：Unreleased › Added 裡「大盤熱力圖」與「大盤熱力圖盤中即時」兩條還沒發布，直接改寫成現在的樣子（市值前 30 檔、不分產業、每格股名／價格／漲跌幅、圖例寫覆蓋率；盤中圖上每一檔即時、收盤後一輪內換成今日收盤），不另加一條與它們矛盾的 Changed。Unreleased › Changed 裡「收盤後 App 在 Mac 上被蓋住也繼續收收盤價」那一條，熱力圖的部分改成「圖上的 30 檔一輪就收完」。
  - `2026-10-07-market-heatmap-design.md` 開頭加一行指到 `2026-11-19-market-heatmap-top30-design.md`。
  - `2026-11-09-mis-quote-freshness-design.md` 寫「熱力圖整張圖一路換到底」的地方加註圖上只剩 30 檔。
  - 本計畫檔尾加「實作後的修正」：與計畫或設計不同的地方、延後的小問題、突變結果。

- [ ] **Step 3: 驗證**

  Run: `flutter analyze` → `No issues found!`

  Run: `flutter test` → `All tests passed!`

  Run: `scripts/test_time_shift.sh 90 <Task 1～3 改到的測試檔>` → 全部通過

  Run: `flutter test --tags golden test/presentation/screens/golden/market_heatmap_screen_golden_test.dart` → 通過

  Run: `dart compile kernel tool/daily_update.dart -o build/daily_update.dill` → 編譯成功（改到 `lib/domain`，確認 update 鏈仍是純 Dart）

- [ ] **Step 4: 送審**（整個變更的最後審查；實作者不 commit）

- [ ] **Step 5: 使用者說「提交」後提交**（`feat:`；設計文件與本計畫一併提交）

- [ ] **Step 6: 實機**（下一個交易日，debug 版）：盤中圖上每一檔都即時、沒有空心的「未即時」格；收盤後一輪內全部換成今日收盤；視窗 1740×1410 與手機直向各看一次，確認不雜、小格子的字不擠。結果寫進本計畫檔尾。

## 實作後的修正（2026-11-19）

### 與計畫或設計寫法不同的地方

- Task 1：`heatmapTopTiles` 在全部市值不是有限正數時回空清單與 0（圖是空的）。`buildHeatmapMarket` 已先排除單檔市值不是有限數的股票，要每檔都有限、合計超過 double 上限才會走到，正常資料沒有劇本走到。
- Task 2：`HeatmapTile.industry` 做成必填的具名參數，每個建構點都要明寫，`buildHeatmapMarket` 漏帶會編譯失敗。
- Task 2：`HeatmapPaintLabels` 比 Interfaces 原本寫的多一個 `locale`，並放進 `==`。描述函式 `_tileSemantics` 是頂層函式，每次取到的是同一個物件；labels 不帶語系的話，同一頁換語系後 painter 不會重建無障礙描述。Interfaces 已改。
- Task 2：`heatmap_live_test.dart` 的「市值相同：跨產業依代號升冪」「市值相同的格子跨過上限」刪除。排序改由 `heatmapTopTiles` 負責（Task 1 已測），`heatmapLiveSymbols` 只照 `tiles` 的順序；另補一條代號順序與市值順序不同的資料。
- Task 2：整合測試「別的畫面抓到比較新的報價」原本靠「別頁那一檔在另一批」成立，現在圖上的檔加指數同一批，改成同一份回應裡逐列給時間（`_Session.snapshot` 加 `rowAt`）。測的東西不變：頁首只看自己格子裡最新的那一列。
- Task 2：Step 6 先改了 painter 才重寫測試（舊測試檔本來就編譯不過）。新測試能不能分辨對錯，改由 Step 17 的突變補驗。
- Task 2：測試不釘「一輪一個請求」（Global Constraints）。整合測試的請求數由 `topTileCount` 與 `misBatchSize` 算出一輪幾個請求，再依此分輪斷言；相鄰兩輪的間隔跟 `LiveQuoteParams.pollInterval` 比，不跟 `LiveQuoteSchedule.pollInterval(…)` 比，後者是被測的函式本身，拿它算期望值時「每輪間隔縮短」的突變會存活。把一批暫時改成 20 檔（一輪變兩個請求）時，熱力圖的 provider、整合、頁面、背景收集測試全部通過。
- Task 2：頁面測試原本直接建 120 檔的資料（測超過登記上限與三位數的進度），改成 30 檔。正式程式圖上最多 30 檔，超過登記上限只在 `heatmapLiveSymbols` 的單元測試裡測。
- Task 2：同一頁換語系的測試需要兩種語系都能切換，`buildProviderTestApp` 加 `switchableTranslations`（從 zh_TW 開始，測試裡呼叫 `setLocale`）。只載一種翻譯與不載翻譯的兩條路徑行為不變。
- Task 3：圖例「雙線框＝含自選或持股」改成「雙線框＝自選或持股」（英文同改）。「含」是合併塊還在時的用字，現在每格就是一檔。
- Task 3：`HeatmapMineMark` 拿掉 `semanticLabel`、改用 `ExcludeSemantics`。現在只剩圖例用它，旁邊有說明文字；行為與原本不給 `semanticLabel` 時相同。`fill` 改成必填（沒有人傳 null）。
- Task 3：`heatmapTileLines` 的 `priceWidth` 改成必填（`required double?`）。選填時新的呼叫端忘了傳，價格會默默不寫。
- Task 3：README 的功能表把「產業分區」改成「市值前 30 檔」（設計與計畫都漏列了它）。
- Task 3：刪除的東西照 `lib/` 的搜尋結果：7 個常數、27 個翻譯鍵（Step 1 預期 28 個，其中 `legendWeighted` 已在 Task 2 換成 `legendCoverage`）、`HeatmapColors.headerText`（連同兩個色彩測試裡的斷言）、`HeatmapMineMark.semanticLabel`。`HeatmapColors.pageBackground`、`allFills` 保留，說明改成現在的用途。`HeatmapTileLayout.bounds` 在 `lib/` 裡也沒有讀取者，同樣保留：實際畫的 `paint` 四邊各內縮半個間隔、面積不跟市值成比例，「面積與市值成比例」只能用 `bounds` 驗。模型與資料來源說明裡的「分組計算」改寫成 `buildHeatmapMarket`。

### 突變

- Task 1：11 個全紅；審查修正後再 6 個，全紅。
- Task 2：24 個全紅（「覆蓋率 99.6% 寫 99%」起初存活，補測試後轉紅）。計畫 Step 17 的「空心格子也寫價格」在 painter 這一層等價（`heatmapTileLines` 沒有漲跌幅就不寫價格，Task 1 已驗），沒有列入。
- Task 2 審查修正後：14 個全紅。2 個起初存活：「每輪間隔縮成 5 秒」（期望值用被測的函式算）、頁面測試對「labels 的 `==` 不看語系」（補「換語系前後的 labels 不相等」）。
- Task 3：圖例用字改回「含自選或持股」，頁面的兩條圖例測試轉紅。其餘是刪除沒人用的東西，由 `flutter analyze` 與全套測試把關。

### 驗證

`flutter analyze` 沒有問題；`flutter test` 全套 6737 條通過（另 3 條略過）；改到的 16 個測試檔撥 +90 天 458 條通過；golden 通過；`dart compile kernel tool/daily_update.dart` 成功。

### 評估過改成 50 檔（同日，維持 30）

- 數字與決定見設計文件開頭的「同日評估」。
- 只把 `topTileCount` 改成 50 時，紅的只有分組測試裡寫死 30 的兩條（「先排除再取前 N 檔」「覆蓋率」）；其餘測試（含一輪變兩批的整合測試與背景收集）不用改就通過，與先前「一批改成 20 檔」的反向檢查一致。那兩條改成照常數寫，版面測試「圖區極小」也改成用 `topTileCount` 檔，維持 30 後留著。
- 圖上的檔加指數超過一批（`topTileCount` > `ApiEndpoints.misBatchSize` − 1）時，Task 2 刪掉的三條整合測試（一輪送到一半被限流；送到一半 App 看不見，兩種平台各一條）又會成立。改成 50 檔時曾照新檔數寫回並以突變驗過；維持 30 後一輪只有一批，沒有留下。日後再加檔數要一起加回，原本的寫法在 86ea61e0 的 `test/presentation/providers/heatmap_live_integration_test.dart`。

### 實機（2026-11-20）

盤中（debug 版，視窗 1740×1410）：
- 上市：11:56:42 進熱力圖，11:56:45 第一輪拿到 31 檔（30 檔加指數）今天的報價，30 格全部即時上色、沒有「盤中未即時」的空心格；之後每輪 31 檔、間隔約 14～15 秒。圖例寫「市值前 30 檔・占上市市值 74%」。
- 上櫃：11:57:10 切換，11:57:15 第一輪 31 檔，30 格全部上色；圖例「占上櫃市值 51%」。
- 縮小到 Mac 最小視窗 400×600：上櫃只有最小一格沒寫字；上市右下約 5 格沒寫字、幾格只寫股名（與設計開頭的量測一致）。自選或持股的雙線框兩個市場都有畫。

看到的問題與處理：
- 剛打開熱力圖或切換市場、第一輪報價回來之前，頁首沒有「報價時間」那一行；那一行出現時圖區變矮 16px，格子重排一次。改成即時時段（盤中、收盤後還沒有正式資料）狀態行還沒有內容時先佔一行，不在即時時段照舊不留空行；狀態行與佔位共用固定行高（系統字級不是 1 時，空行與有中文的行原本會差 1px）。
- 仍會跳一次、記下不處理的：頁面開著跨過 9:00（不在即時時段時不留空行，9:00 起才佔）；收盤後狀態行在一行與兩行之間切換（只在窄視窗或英文；要修得一律留兩行）；正式資料寫入後狀態行消失（同一刻資料也換掉）。

收盤後（上市；上櫃收盤後沒看）：
- 13:30:14 收盤後第一輪 31 檔；13:31:16 第二輪 27 檔，13:31:35 頁首「今日收盤 24／30 檔・待盤後更新」；還沒拿到收盤價的 6 檔照收盤後的每分鐘重試，13:32:17 第三輪補齊，之後不再抓。13:36 頁首「今日收盤 30／30 檔・待盤後更新」，30 格都是今日收盤。
- Step 6 原本預期「一輪內全部換成今日收盤」，實際是收盤後約兩分鐘、第三輪才齊。
