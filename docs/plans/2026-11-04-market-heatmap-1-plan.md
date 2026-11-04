# 大盤熱力圖第 1 段：收盤後熱力圖 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 從大盤總覽頁進入的獨立頁，以資料庫的最新正式資料畫上市、上櫃各一張熱力圖（依產業分區、面積＝市值、顏色＝當日漲跌），可放大產業、點格子進個股頁、滑鼠／長按看提示；launchd 在背景寫入時一分鐘內自動重讀。

**Architecture:**
- **core**：`HeatmapParams`（排除產業、股數門檻、色階分界、版面尺寸、輪詢間隔）與 `HeatmapColors`（兩種主題的 6＋6 階、平盤、空心、自選框，值已在本計畫算好）。
- **domain（純 Dart）**：`heatmap.dart` 型別；`heatmap_grouping.dart` 股數規則、漲跌幅公式、分組與產業市值加權；`heatmap_layout.dart` 兩層 squarified 佈局與點擊查找。盤中（第 2 段）只換 `TileChange` 的來源，這兩個函式不變。
- **data**：`HeatmapDaoMixin` 讀正式資料日、內容指紋、某市場某日的價格列；`HeatmapRepository` 組出 `HeatmapMarketInput`（價格＋兩個股數來源＋自選∪持股）。
- **presentation**：`MarketHeatmapNotifier`（開頁讀取、通知與邊界重讀、可見期間每分鐘比對指紋、重讀合併）；`HeatmapView`（一個 `CustomPainter` 畫全部格子，提示另一層，無障礙分層）；`MarketHeatmapScreen`（市場切換、產業選單、頁首、圖例、頁尾）；大盤總覽頁標題列入口。

**Tech Stack:** Flutter／Dart 3.10、flutter_riverpod 3、go_router 17.1.0、drift 2.32、easy_localization、fake_async、mocktail、flutter_test

**Spec:** `docs/plans/2026-10-07-market-heatmap-design.md`（已提交 `c4263411`；前置項除權息漲跌修正已在 `fa42d01c` 完成）。

本計畫實作 spec 的：
- 第 1 節「資料與計算」全部。
- 第 2 節「畫面與互動」全部。
- 第 3 節只做「該市場指數一律登記」（與大盤總覽頁同一套 `marketIndexRegistrations`），以及表中「開盤前、休市日」與「該市場有今天正式資料後」兩列的行為；本段在所有時段都顯示最新正式資料。
- 第 4 節中與即時無關的各列。
- 「驗證」1（登記清單、上色來源、盤中產業漲跌、收盤後頁首彙總除外）、3、4、5、6（同樣除外），以及 7 的「讀取＋計算時間」與「盤後資料寫入後一分鐘內切回」。

整個功能分兩段：
1. 收盤後熱力圖（本計畫）。
2. 盤中即時與收盤後滾動登記：spec 第 3 節其餘部分、第 4 節的即時列、驗證 2 與驗證 1／6／7 的即時項目。第 1 段完成後依實際介面再寫計畫。

## Global Constraints

- **只讀資料庫**：
  - 不新增資料表或欄位，不新增資料來源，不寫任何表。
  - 不碰 `market_day_fetch` 的寫入（`fetched_at` 是定案判斷依據）。
- **不改報價中心**：本段只用既有 `LiveQuoteScope`＋`marketIndexRegistrations` 登記兩個指數，與 `MarketOverviewScreen` 相同。
- **tool 鏈純 Dart**：`HeatmapDaoMixin` 加進 `AppDatabase`，等於進了 `tool/daily_update.dart` 的 import 閉包。
  - `heatmap_dao.dart` 只能 import drift、`core/` 的純 Dart 檔、`app_database.drift.dart`。
  - 回傳型別定義在 DAO 檔內，不 import `domain/`。
  - 守門：`test/tool/tool_chain_pure_dart_test.dart`。
- **常數集中**：
  - 門檻、尺寸、間隔只寫在 `HeatmapParams`。
  - 顏色只寫在 `HeatmapColors`。
- **漲跌不退回前一筆收盤**：
  - 熱力圖任何路徑都不得呼叫 `PriceCalculator.calculatePriceChange`。
  - 漲跌幅只用 `priceChange / (close − priceChange) × 100`。
- **納入範圍**：
  - 排除產業別含 `ETF` 的列（`ETF`、`上櫃ETF`，與 `isEtfIndustry` 同判準）與產業別等於 `存託憑證` 的列（2026-11-04 `stock_master` 實測值）。
  - 只取 `is_active = 1` 的股票。
- **文案**：
  - 畫面上的固定文字、提示、無障礙描述一律放 `assets/translations/zh-TW.json`、`en.json` 的 `marketHeatmap` 區塊。
  - 產業名稱不翻譯，顯示資料庫原值；只有「未分類」走翻譯檔。
- **公開 repo**：
  - 測試資料一律用 99xx 虛構代號、虛構名稱（如「測試甲」）。
  - 需要真實情境時照真實數值、改代號。
  - 不放使用者的自選或持股。
- **提交**：
  - implementer 不 commit，改動留在工作樹。
  - 每個 Task 完成後送 `pr-review-toolkit:code-reviewer`（opus）審查，Critical／Important 修完才進下一個 Task。審查包＝工作樹對該 Task BASE 的差異加新檔全文；同一段內後面 Task 的審查包會含前面 Task，審查提示寫明本 Task 範圍。
  - 整段在 Task 8 經使用者說「提交」後一次提交（daredevil 依段提交的前例），直接在 main。
  - 格式：Conventional Commits，描述用繁體中文，內文寫改了什麼、為什麼，不加署名行。push 由使用者做。
- **指令**：`flutter test <path>`、`flutter analyze`（info 也擋）；golden 只在本機跑（`@Tags(['golden'])`）。

## Review Focus

spec 沒寫、但最可能讓使用者撞到的五種情況。每條都在負責的 Task 補了測試：

1. **兩個市場的正式資料日不同**：
   - 會發生的路徑有兩條：
     - 上櫃回空清單，走 `emptyMarkets`，上櫃不寫入。
     - 某市場寫入的列數未達覆蓋門檻，沒有 `market_day_fetch` 紀錄。
   - 上櫃行情斷線（`NetworkException`）不屬於這種：那時兩個市場都不寫，都停在前一天（見末尾「順帶發現」）。
   - 頁首日期要跟著切換的市場變。
   - 只有一個市場有資料時，另一個市場顯示空狀態，不能整頁錯誤。
   - → Task 7。
2. **放大中的產業在重讀後消失或換市場**：例如轉市場後該產業只剩 0 檔，或切到另一個市場時同名產業不存在。要回到全市場，不能畫空白或拋錯。→ Task 7。
3. **圖區極小或為 0**：視窗縮到很小、或鍵盤／分割畫面把高度壓到 0。
   - 佈局回空清單、不拋錯。
   - 小格照畫但不回應點擊。
   - → Task 3、Task 6。
4. **極端漲跌**：
   - 上櫃新股首日 +123.93%、分母 ≤ 0 → 前者第 6 階、後者空心。
   - 浮點邊界：收盤 6.57、漲 0.57（平盤 6.00）算出 `9.499999999999998`，必須落在 ≥ 9.5 的第 6 階，不能掉到第 5 階。
     - 在平盤 1～1,200 元、漲跌剛好等於分界的條件下，這是用台股跳動單位掃出來唯一會掉階的例子。
     - 0.15／10 在浮點下剛好是 1.5，測不到這個問題。
   - → Task 1、Task 2。
5. **頁面開著時切換深淺主題**：同一份資料要用新色階重畫（`shouldRepaint` 看 brightness），提示與圖例同步。→ Task 6、Task 7。

## 與 spec 的差異（核可計畫時一併確認）

1. **色階數值由本計畫定案**：spec 只給條件，本計畫算出實際色值（見 Task 1 色表）。各色由 `PriceColors` 的漲跌色以 alpha 0.40／0.54／0.66／0.78／0.89／1.0 疊在頁面底色上產生。
2. **spec 的「黑白字都到不了 4.5 的亮度帶（0.16～0.22）」不存在**：
   - 純黑、純白取對比較高者時，最差發生在相對亮度約 0.179，對比仍有 4.58。
   - 所以文字 ≥ 4.5 對任何填色都成立。測試照樣逐階驗。
3. **「平盤灰、第 1 階、空心分得開」的門檻由本計畫訂**：
   - 平盤、第 1 階對頁面底色都 ≥ 1.25。
   - 平盤對兩個方向的第 1 階都 ≥ 1.15。
   - 空心邊框對頁面底色 ≥ 3.0。
   - 平盤是灰階、第 1 階落在股價色相區。
   - 淺色主題的平盤因此取 `#E4E4E4`：原本想用的 `#D9D9D9` 對跌第 1 階只有 1.14（對漲第 1 階 1.18），跌方向只能靠色相分辨。
4. **分階前先四捨五入到小數 2 位，所有漲跌幅也一律顯示 2 位**（格子、產業標題、選單、提示）。
   - 這樣看到的數字與顏色永遠同一階。
   - 浮點例子見 Review Focus 第 4 條。
5. **「頁面可見」＝`TickerMode` 開著且 App 在前景**：
   - App 前景與否目前只有報價中心知道。本計畫新增 `appVisibilityProvider`，由 `main.dart` 同一個生命週期回呼設定。
6. **測試位置**：
   - spec 把內容指紋的測試列在 Widget 測試。本計畫改成兩處：指紋四個成分在 DAO 層用真的 in-memory DB 測；重讀觸發、合併、輪詢在 provider 層用假 repository＋`fakeAsync` 測。
   - 頁面測試只驗接線。
7. **「未分類」**：產業別為空時 `HeatmapIndustry.name` 為 null，畫面顯示翻譯檔的「未分類」。
8. **數字格式**：
   - 漲跌幅一律小數 2 位（`+1.83%`），理由見第 4 點。
   - 市值在提示中：中文以「億」為單位、小數 1 位、千分位；英文以十億（B）為單位。
9. **入口與「← 全市場」的位置**：
   - 入口按鈕放在大盤總覽頁 AppBar 的 actions（spec 只寫「標題列加一個按鈕」）。
   - 放大時，「← 全市場」取代 AppBar 的標題文字。這樣仍在標題列，也不取代系統返回鍵，窄螢幕不會多占寬度。

## 檔案結構

| 檔案 | 動作 | 職責 |
|:--|:--|:--|
| `lib/core/constants/heatmap_params.dart` | 新增 | 排除產業判斷、股數門檻、色階分界與 `stepOf`、版面尺寸、輪詢間隔 |
| `lib/core/theme/heatmap_colors.dart` | 新增 | 兩種主題的頁面底色、6＋6 階、平盤、空心邊框與文字、自選框、文字黑白 |
| `lib/domain/models/heatmap.dart` | 新增 | 輸入、股數判定、格子漲跌、產業、市場資料型別 |
| `lib/domain/services/heatmap/heatmap_grouping.dart` | 新增 | `resolveHeatmapShares`、`heatmapChangePercent`、`buildHeatmapMarket` |
| `lib/domain/services/heatmap/heatmap_layout.dart` | 新增 | `squarify`、`layoutHeatmap`、`tileAt`、`industryHeaderAt` |
| `lib/data/database/dao/heatmap_dao.dart` | 新增 | 正式資料日、內容指紋、價格列 |
| `lib/data/database/app_database.dart` | 修改 | `with` 清單加 `HeatmapDaoMixin` |
| `lib/data/repositories/heatmap_repository.dart` | 新增 | 組 `HeatmapMarketInput` |
| `lib/presentation/providers/app_visibility_provider.dart` | 新增 | App 前景／背景 |
| `lib/main.dart` | 修改 | 生命週期回呼同時設定 `appVisibilityProvider` |
| `lib/presentation/providers/market_heatmap_provider.dart` | 新增 | 狀態、讀取、重讀合併、指紋輪詢、可見性 |
| `lib/presentation/widgets/heatmap/heatmap_painter.dart` | 新增 | 畫格子、產業標題、自選框、空心；無障礙節點 |
| `lib/presentation/widgets/heatmap/heatmap_view.dart` | 新增 | 佈局快取、點擊、滑鼠、長按、提示層 |
| `lib/presentation/widgets/heatmap/heatmap_tooltip.dart` | 新增 | 提示內容 |
| `lib/presentation/widgets/heatmap/heatmap_legend.dart` | 新增 | 色階、自選框、空心、市值加權說明 |
| `lib/presentation/screens/market/market_heatmap_screen.dart` | 新增 | 頁面組裝、市場切換、產業選單、頁首、頁尾、空與錯誤狀態 |
| `lib/core/constants/app_routes.dart`、`lib/app/router.dart` | 修改 | `/market-heatmap` |
| `lib/presentation/screens/market/market_overview_screen.dart` | 修改 | AppBar 入口 |
| `assets/translations/zh-TW.json`、`en.json` | 修改 | `marketHeatmap` 區塊 |
| `CHANGELOG.md` | 修改 | Added |

---

### Task 1: 參數與色階

**Files:**
- Create: `lib/core/constants/heatmap_params.dart`、`lib/core/theme/heatmap_colors.dart`
- Modify: `test/core/theme/semantic_colors_test.dart`（第一層色相禁區守門加一條）
- Test: `test/core/constants/heatmap_params_test.dart`、`test/core/theme/heatmap_colors_test.dart`

**Interfaces:**
- Produces:
  - `abstract final class HeatmapParams`（純 Dart，不 import Flutter）：
    - `static bool isExcludedIndustry(String? industry)`：`industry` 含 `ETF` 或等於 `存託憑證`。
    - `static const double shareMismatchRatio = 0.10`。
    - `static const List<double> stepBounds = [0.5, 1.5, 3.0, 5.0, 9.5]`。
    - `static int stepOf(double percent)`：先四捨五入到小數 2 位再取絕對值；0 → 0；其餘回 1..6。
    - `static const Duration fingerprintPollInterval = Duration(minutes: 1)`。
    - 版面：`industryGap = 2.0`、`tileGap = 1.0`、`industryHeaderHeight = 16.0`、`industryHeaderMinWidth = 60.0`、`industryHeaderMinHeight = 40.0`、`labelFontSize = 11.0`、`tileNameMinWidth = 48.0`、`tileNameMinHeight = 30.0`、`tilePercentMinWidth = 40.0`（11px 字下 `+1.83%` 約 37px；這只是預篩，實際仍以量出來的文字寬度為準）、`tilePercentMinHeight = 14.0`、`minInteractiveSide = 4.0`。
  - `abstract final class HeatmapColors`：
    - `static Color pageBackground(Brightness b)`
    - `static Color fill({required int step, required bool up, required Brightness brightness})`（step 1..6）
    - `static Color flat(Brightness b)`
    - `static Color textOn(Color fill)`（`fill.computeLuminance() > 0.179` 用黑，否則白）
    - `static Color hollowBorder(Brightness b)`、`static Color hollowText(Brightness b)`
    - `static Color headerText(Brightness b)`：產業標題列（底色＝頁面底色）的文字色。
    - `static const Color mineOuter`、`static const Color mineInner`
    - `static List<Color> allFills(Brightness b)`：12 階加平盤，供守門測試。

色表（`Color(0xFF……)`）：

| | 深色主題 | 淺色主題 |
|:--|:--|:--|
| 頁面底色 | `18181B`（`SemanticColors.darkBackground`） | `FFFFFF` |
| 漲 1–6 | `742B33` `95313B` `B03743` `CC3D4A` `E64250` `FF4757` | `FFB5BC` `FF9CA4` `FF8690` `FF6F7C` `FF5B69` `FF4757` |
| 跌 1–6 | `21643E` `247E4B` `279555` `29AB60` `2CC069` `2ED573` | `A4D8B9` `84CBA0` `69BF8B` `4DB376` `34A963` `1B9E50` |
| 平盤 | `303030` | `E4E4E4` |
| 空心邊框 | `6B6B6B` | `8C8C8C` |
| 空心文字 | `A1A1A1` | `717171` |
| 產業標題文字 | `F4F4F5`（`SemanticColors.darkTextPrimary`） | `18181B` |
| 自選框外／內 | `000000`／`FFFFFF` | 同左 |

- [ ] **Step 1: 寫失敗的測試**

`heatmap_params_test.dart`：
- `stepOf 依 spec 分界`：`stepOf(0) == 0`；`stepOf(0.49) == 1`；`stepOf(0.5) == 2`；`stepOf(1.5) == 3`；`stepOf(3) == 4`；`stepOf(5) == 5`；`stepOf(9.5) == 6`；`stepOf(123.93) == 6`；負值對稱（`stepOf(-0.5) == 2`、`stepOf(-9.5) == 6`）。
- `stepOf 先四捨五入到 2 位`：`stepOf(0.57 / (6.57 - 0.57) * 100) == 6`（未四捨五入是 9.499999999999998）；`stepOf(1.13 / (23.73 - 1.13) * 100) == 5`（4.999999999999999）；`stepOf(0.004) == 0`（顯示為 0.00% 的值畫平盤）。
- `isExcludedIndustry`：`ETF`、`上櫃ETF`、`存託憑證` 為 true；`半導體業`、`null` 為 false。

`heatmap_colors_test.dart`（兩種主題各跑一次，用 `ColorContrast`）：
- `每一階文字（純黑或純白）對比 ≥ 4.5`：對 `allFills` 每個色，`ColorContrast.ratio(textOn(c), c) >= 4.5`。
- `每一階對頁面底色的對比不低於前一階`：漲、跌各 1..6 非遞減。
- `平盤、第 1 階對頁面底色 ≥ 1.25；平盤對兩方向第 1 階 ≥ 1.15`。
- `空心邊框對頁面底色 ≥ 3.0；空心文字、產業標題文字對頁面底色 ≥ 4.5`。
- `自選框：對每一階填色、平盤、頁面底色，外框或內框至少一條 ≥ 3.0`。
- `漲各階色相在紅區、跌各階在綠區；平盤、空心、自選框為灰階`（色相用 `ColorContrast.hue`，灰階回負值）。
- `色值與計畫色表一致`：逐階比對上表 hex，防止日後改色漏跑上面的條件。

`semantic_colors_test.dart` 第一層加 `熱力圖的平盤、空心邊框、空心文字、自選框不得落在股價色相區（兩主題）`。

- [ ] **Step 2: 跑測試確認失敗**

Run: `flutter test test/core/constants/heatmap_params_test.dart test/core/theme/heatmap_colors_test.dart test/core/theme/semantic_colors_test.dart`
Expected: FAIL（`HeatmapParams`／`HeatmapColors` 未定義）

- [ ] **Step 3: 實作兩個檔案**（值照上表與 Interfaces）

- [ ] **Step 4: 跑測試確認通過**（同 Step 2 指令，Expected: PASS）

- [ ] **Step 5: 記錄進度、送審**

---

### Task 2: 型別、股數規則、分組計算

**Files:**
- Create: `lib/domain/models/heatmap.dart`、`lib/domain/services/heatmap/heatmap_grouping.dart`
- Test: `test/domain/services/heatmap/heatmap_grouping_test.dart`

**Interfaces:**
- Consumes: `HeatmapParams.isExcludedIndustry`、`HeatmapParams.shareMismatchRatio`、`MarketCode.twse`／`MarketCode.tpex`。
- Produces（全部 `@immutable`、純 Dart）：
  - `typedef HeatmapShares = ({double shares, DateTime date});`
  - `sealed class SharesResolution`，子類別有三個：`SharesOk(double shares)`、`SharesMissing()`、`SharesInconsistent()`。
  - `enum HollowReason { noChangeData }`：第 2 段會加 `notLive`、`noTrade`、`noQuote`、`awaitingClose`。
  - `sealed class TileChange`，子類別有兩個：`TileChangeValue(double percent)`、`TileChangeHollow(HollowReason reason)`。
  - `class HeatmapStockInput`：`{String symbol, String name, String? industry, double close, double? priceChange, HeatmapShares? foreign, HeatmapShares? insider}`。
  - `class HeatmapMarketInput`：`{String market, DateTime dataDate, List<HeatmapStockInput> stocks, Set<String> mine}`。
  - `class HeatmapTile`：`{String symbol, String name, double close, double marketCap, TileChange change, bool isMine}`。
  - `class HeatmapIndustry`：
    - 欄位：`{String? name, double marketCap, double? weightedChangePercent, List<HeatmapTile> tiles}`。
    - `String get key => name ?? ''`。
  - `class HeatmapMarketData`：`{String market, DateTime dataDate, List<HeatmapIndustry> industries, int excludedForShares}`。
  - `SharesResolution resolveHeatmapShares({required String market, HeatmapShares? foreign, HeatmapShares? insider})`
  - `double? heatmapChangePercent({required double close, required double? priceChange})`
  - `HeatmapMarketData buildHeatmapMarket(HeatmapMarketInput input)`：頂層函式。排在頂層是為了計算超過 100ms 時能直接丟進 `Isolate.run`。

規則：
- 股數 ≤ 0 視同沒有。
- **上市**只看 `foreign`。
- **上櫃**：
  - 兩邊都有、`|a − b| / max(a, b) > 0.10` → `SharesInconsistent`。
  - 否則取日期較新的；同日取 `foreign`。
- `close <= 0` 的列直接略過，不計頁尾。
- 產業排序：市值降冪、同值依 `key` 升冪。
- 格子排序：市值降冪、同值依代號升冪。
- 產業別為 null 或空字串時 `name` 為 null。

- [ ] **Step 1: 寫失敗的測試**（代號 99xx、名稱「測試甲／乙…」）

股數規則：
- `上市只用外資持股`：外資 null、董監有值 → `SharesMissing`。
- `上櫃取較新的一筆`：外資 10/1 1000、董監 10/15 1050 → `SharesOk(1050)`。
- `上櫃同日用外資持股`：同日 1000 與 1050 → `SharesOk(1000)`。
- `上櫃相差恰 10% 仍可用、超過才不畫`：900 對 1000 → `SharesOk`；1000 對 1120 → `SharesInconsistent`。
- `上櫃只有一個來源就用它`：只有董監 → `SharesOk`。
- `股數 ≤ 0 視同沒有`：外資 0、董監 null → `SharesMissing`。
- `公司行動空窗照用董監股數`（照 5904 數值、代號 9904）：上櫃、外資 null、董監 1,064,438,260（7/15）、收盤 720 → 市值 `720 * 1064438260`。這是已知限制，測試釘住目前行為。

漲跌幅：
- `漲跌幅＝漲跌／(收盤−漲跌)`：`heatmapChangePercent(close: 105, priceChange: 5) == 5.0`。
- `漲跌空值與分母 ≤ 0 回 null`：`(close: 5, priceChange: null)`、`(5, 5)`、`(5, 6)` 皆 null。

分組：
- `排除 ETF、上櫃ETF、存託憑證，且不計入頁尾`：`excludedForShares == 0`、產業清單沒有它們。
- `缺股數與股數不一致計入頁尾、不畫`：一檔 missing、一檔 inconsistent → `excludedForShares == 2`、格子不含它們。
- `漲跌空值畫空心`：`change` 是 `TileChangeHollow(HollowReason.noChangeData)`。
- `產業漲跌為市值加權、空心成員不計`：
  - 成員市值 300（+2%）、100（−2%）、600（空心）→ `weightedChangePercent == 1.0`。
  - 全部空心的產業為 null。
- `新股首日大漲照常上色`：`close: 22.393, priceChange: 12.393` → `TileChangeValue`，percent ≈ 123.93。
- `grouping 不先四捨五入`：`close: 3.07, priceChange: 0.07` 的 percent `closeTo(2.3333, 1e-4)`（不是 2.33）。浮點邊界本身由 Task 1 的 `stepOf` 測試負責，這裡不測，以免綁住算式順序。
- `收盤 ≤ 0 略過且不計頁尾`：close 0 的一檔不在格子裡、`excludedForShares` 不增加。
- `上櫃股數 ≤ 0 的股票計入頁尾`：外資 0、董監 null → `excludedForShares` 加 1。
- `自選或持股標記`：`mine` 含 9901 → 該格 `isMine`。
- `排序穩定`：兩個同市值產業依名稱、同市值格子依代號；同樣輸入呼叫兩次結果相等。
- `產業別空白歸未分類`：industry `''` 與 null 都在 `name == null` 的同一組。
- `0 檔`：空清單 → `industries` 空、`excludedForShares == 0`。

- [ ] **Step 2: 跑測試確認失敗**

Run: `flutter test test/domain/services/heatmap/heatmap_grouping_test.dart`
Expected: FAIL（型別與函式未定義）

- [ ] **Step 3: 實作 `heatmap.dart` 與 `heatmap_grouping.dart`**

輸入不含前一筆收盤，結構上就不可能退回前收盤。

- [ ] **Step 4: 跑測試確認通過**

- [ ] **Step 5: 記錄進度、送審**

---

### Task 3: 佈局與點擊查找

**Files:**
- Create: `lib/domain/services/heatmap/heatmap_layout.dart`
- Test: `test/domain/services/heatmap/heatmap_layout_test.dart`

**Interfaces:**
- Consumes: `HeatmapIndustry`、`HeatmapTile`（Task 2）；`HeatmapParams` 版面常數（Task 1）。
- Produces（純 Dart，不用 `dart:ui`）：
  - `typedef HeatmapBox = ({double left, double top, double width, double height});`
  - `class HeatmapTileLayout`：`{HeatmapTile tile, HeatmapBox bounds, HeatmapBox paint, bool interactive}`。
    - `bounds` 是切間隔前的矩形（面積與市值成比例）。
    - `paint` 是內縮 `tileGap / 2` 後的矩形。
    - `interactive` ＝ `paint` 的短邊 ≥ `minInteractiveSide`。
  - `class HeatmapIndustryLayout`：`{HeatmapIndustry industry, HeatmapBox bounds, HeatmapBox? header, List<HeatmapTileLayout> tiles}`。
  - `List<HeatmapBox> squarify(List<double> values, HeatmapBox area)`：
    - `values` 已降冪，回傳順序相同。
    - 演算法：Bruls、Huizing、van Wijk 的 squarified——沿短邊排列，加入下一個值會讓該列最差長寬比變大時就換列。
  - `List<HeatmapIndustryLayout> layoutHeatmap(List<HeatmapIndustry> industries, {required double width, required double height})`：
    - 第一層依產業市值切；產業矩形內縮 `industryGap / 2`。
    - 內縮後寬 ≥ `industryHeaderMinWidth` 且高 ≥ `industryHeaderMinHeight` 才在頂端切出 `industryHeaderHeight` 的標題列；格子鋪滿剩下的區域。
    - `width` 或 `height` ≤ 0、或沒有產業時回 `[]`。
  - `HeatmapTileLayout? tileAt(List<HeatmapIndustryLayout> layout, double x, double y)`：只回 `interactive` 的格子。
  - `HeatmapIndustryLayout? industryHeaderAt(List<HeatmapIndustryLayout> layout, double x, double y)`

- [ ] **Step 1: 寫失敗的測試**（容差 1e-6）
- `面積與市值成比例`：每格 `bounds` 面積 ÷ 圖區面積 ＝ 該格市值 ÷ 總市值。
  - 要分兩層驗：產業層對總市值；格子層對產業內容區（扣掉標題列）。
- `矩形不重疊`：任兩格 `bounds` 交集面積 < 1e-6。
- `鋪滿圖區`：產業 `bounds` 面積和 ＝ 寬 × 高；各產業格子 `bounds` 面積和 ＝ 產業內縮後扣標題列的面積。
- `squarify 長寬比`：10 個等值在正方形中，最差長寬比 ≤ 3。用來抓「退化成 slice-and-dice」的突變。
- `0 檔與 1 檔`：空清單回 `[]`；單產業單格時格子 `bounds` ＝ 產業內容區。
- `極端比例`：一檔占 41%、其餘 200 檔均分，仍滿足比例、不重疊、鋪滿。
- `同樣輸入同樣輸出`：兩次呼叫逐格相等。
- `圖區為 0 或極小`：`width: 0` 回 `[]`；`10×10` 放 40 檔等值（單一產業）不拋錯，且所有格子 `interactive == false`（只有一格時內縮後仍有 7×7，是可點的，資料要夠多）。
- `小產業不畫標題列`：內縮後寬 59 的產業 `header == null`，格子從頂端開始。
- `tileAt 只回可互動的格子`：點在大格中心回該格；點在非互動小格回 null；點在間隔回 null。
- `industryHeaderAt`：點在標題列回該產業；點在格子區回 null。

- [ ] **Step 2: 跑測試確認失敗**

Run: `flutter test test/domain/services/heatmap/heatmap_layout_test.dart`
Expected: FAIL

- [ ] **Step 3: 實作 `heatmap_layout.dart`**

- [ ] **Step 4: 跑測試確認通過**

- [ ] **Step 5: 記錄進度、送審**

---

### Task 4: 資料讀取（DAO＋repository）

**Files:**
- Create: `lib/data/database/dao/heatmap_dao.dart`、`lib/data/repositories/heatmap_repository.dart`
- Modify: `lib/data/database/app_database.dart`（`with` 清單加 `HeatmapDaoMixin`，放在 `MarketDayFetchDaoMixin` 後）
- Test: `test/data/database/dao/heatmap_dao_test.dart`、`test/data/repositories/heatmap_repository_test.dart`

**Interfaces:**
- Consumes：
  - `MarketDataset.prices.code`、`MarketCode`。
  - 既有 `getLatestShareholdingsBatch`、`getLatestInsiderHoldingsBatch`、`getWatchlistAndHoldingSymbols`。
  - Task 2 的 `HeatmapMarketInput`／`HeatmapStockInput`／`HeatmapShares`（只有 repository 用，DAO 不用）。
- Produces：
  - `heatmap_dao.dart` 的型別：
    - `typedef HeatmapFingerprint = ({DateTime date, int rows, int changeRows, double? changeSum, double? closeSum});`
    - `typedef HeatmapPriceRow = ({String symbol, String name, String? industry, double close, double? priceChange});`
  - `mixin HeatmapDaoMixin on $AppDatabase`：
    - `Future<DateTime?> getLatestFormalPriceDate(String market)`：`market_day_fetch` 中 `dataset = prices`、該市場的最大 `date`。
      - 照 `PriceDaoMixin.getLatestDataDate` 用 `customSelect('SELECT MAX(date) AS max_date …')` 加 `read<DateTime?>`。
      - 不要用 drift 的 `.max()`：文字日期模式下 aggregate 回 UTC（見 `financial_data_dao.dart:71` 的註解），再 normalize 會在 +08:00 的機器上差一天，CI（+00:00）測不到。
    - `Future<HeatmapFingerprint?> getHeatmapFingerprint(String market)`：
      - 沒有正式資料日時回 null。
      - 否則對該日、該市場（join `stock_master` 依 `market` 過濾）的 `daily_price` 取 `COUNT(*)`、`COUNT(price_change)`、`SUM(price_change)`、`SUM(close)`。
      - 日期條件照 `MarketOverviewDaoMixin` 用 `dp.date >= ? AND dp.date < ?`，走 `idx_daily_price_date_symbol`。
    - `Future<List<HeatmapPriceRow>> getHeatmapPriceRows(String market, DateTime date)`：`is_active = 1`、該市場、該日、`close IS NOT NULL`；`price_change` 原值照回。
  - `class HeatmapRepository`（建構子 `HeatmapRepository(AppDatabase db)`）：
    - `Future<HeatmapFingerprint?> fingerprint(String market)`
    - `Future<HeatmapMarketInput> loadInput(String market, DateTime date)`：價格列＋兩個股數來源最新一筆（`sharesIssued` 非 null 才帶）＋自選∪持股。

- [ ] **Step 1: 寫失敗的測試**（`AppDatabase.forTesting()`；先寫 `stock_master` 再寫 `daily_price`，外鍵；日期一律 `DateContext.normalize`）

`heatmap_dao_test.dart`：
- `正式資料日兩個市場各自判斷`：上市有 10/7、上櫃只有 10/6 → 各回 10/7、10/6。
- `只寫入一部分股票的日子不算正式資料`：`daily_price` 有上櫃 10/7 兩檔、`market_day_fetch` 沒有 10/7 上櫃 → 上櫃回 10/6。
- `其他資料集的紀錄不算`：`market_day_fetch` 有 `institutional` 10/8 → 價格正式資料日不變。
- `沒有任何紀錄回 null`：正式資料日與指紋都是 null。
- `價格列排除下市、他市場、收盤空值`：三種各一列，都不在結果。
- `漲跌空值照回、不退回前一筆收盤`：前一日有收盤 100、當日收盤 105、`price_change` null → 回 `priceChange == null`。
- 指紋各成分（同一市場同一天另有至少一列非空漲跌、非空收盤，避免合計從 0 變空值）：
  - `只改內容不改日期時指紋改變`。
  - `新增一列收盤與漲跌都空的：只有 rows 變`。
  - `0 改成空值：只有 changeRows 變`。
  - `非空漲跌改成另一個非空值：只有 changeSum 變`。
  - `收盤由空值變有值：只有 closeSum 變`。
  - `沒有改動時指紋相等`。
- `兩個市場分開`：改上櫃的一列，上市指紋不變。

`heatmap_repository_test.dart`：
- `loadInput 帶入兩個股數來源最新一筆與日期`：外資兩天取較新、董監一筆。
- `股數欄位為 null 的來源不帶`。
- `自選與持股都算 mine`：持股數量 0 的不算。

- [ ] **Step 2: 跑測試確認失敗**

Run: `flutter test test/data/database/dao/heatmap_dao_test.dart test/data/repositories/heatmap_repository_test.dart`
Expected: FAIL

- [ ] **Step 3: 實作 DAO、加進 `AppDatabase`、實作 repository**

DAO mixin 不需要 build_runner。

- [ ] **Step 4: 跑測試確認通過，並守 tool 鏈**

Run: `flutter test test/data/database/dao/heatmap_dao_test.dart test/data/repositories/heatmap_repository_test.dart test/tool/tool_chain_pure_dart_test.dart && dart compile kernel tool/daily_update.dart -o build/daily_update.dill`
Expected: PASS；kernel 編譯成功

- [ ] **Step 5: 記錄進度、送審**

---

### Task 5: 頁面狀態與重讀

**Files:**
- Create: `lib/presentation/providers/app_visibility_provider.dart`、`lib/presentation/providers/market_heatmap_provider.dart`
- Modify: `lib/main.dart:255-257`（`onAppVisibilityChanged` 回呼裡同時 `ref.read(appVisibilityProvider.notifier).set(visible)`；`initState` 不動）
- Test: `test/presentation/providers/market_heatmap_provider_test.dart`、`test/presentation/providers/app_visibility_provider_test.dart`

**Interfaces:**
- Consumes：
  - Task 2 的 `buildHeatmapMarket`；Task 4 的 `HeatmapRepository`、`HeatmapFingerprint`。
  - 既有 `databaseProvider`、`dataUpdateEpochProvider`、`liveQuoteBoundaryProvider`。
- Produces：
  - `final appVisibilityProvider = NotifierProvider<AppVisibility, bool>(AppVisibility.new);`
    - `build()` 讀 `WidgetsBinding.instance.lifecycleState`：null 回 true，否則回 `AppLifecycleCoordinator.isVisible(state)`。
    - `void set(bool visible)`：同值直接 return。
    - 啟動時不得在 `_DaredevilAppState.initState` 寫它：Riverpod 在 widget 樹建構期間寫 provider state 會拋 `Tried to modify a provider while the widget tree was building`，同值也拋（審查者在 scratch 專案以 flutter_riverpod 3.3.1 重現）。
    - 既有的 `LiveQuoteCenter.setAppVisible` 也是因此只改欄位，見 `live_quote_provider.dart:110` 的註解。
    - 生命週期回呼不在 build 期間，可以寫。
  - `final heatmapRepositoryProvider = Provider<HeatmapRepository>(...)`
  - `class MarketHeatmapState`：
    - 欄位：`{bool isLoading = true, Object? error, Map<String, HeatmapMarketData> markets = const {}, Set<String> failedMarkets = const {}}`。
    - 沒有正式資料的市場不在 `markets` 裡。
    - `failedMarkets`：上一次讀取失敗的市場。下一次成功讀到該市場（含讀到「沒有正式資料」）時移除。
    - `error` 只在第一次讀取整個失敗、畫面沒資料時有值；之後任何一次讀取成功就清掉。
  - `final marketHeatmapProvider = NotifierProvider.autoDispose<MarketHeatmapNotifier, MarketHeatmapState>(...)`
  - `MarketHeatmapNotifier`：
    - `Future<void> reload()`
    - `Future<void> checkFingerprint()`
    - `void setVisible(bool visible)`

行為：
- **觸發來源**：
  - `build()`：`ref.listen` 兩個 provider（epoch 變動、boundary 換值）都呼叫 `reload()`；`Future.microtask(reload)` 做第一次讀取；`ref.onDispose` 取消計時器、設 `_active = false`。
- **`reload()`**：
  - 進行中再被呼叫只設 `_pending = true`。
  - 否則迴圈「清 `_pending`、讀兩個市場」直到 `_pending` 為 false。
  - 每個市場的讀法：先 `fingerprint`；null 則移除該市場並記基準 null；否則 `loadInput(market, fp.date)`，再 `buildHeatmapMarket`，記基準＝這次的 `fp`。
  - 讀取與計算各用 `Stopwatch` 計時，`AppLogger.debug('MarketHeatmap', ...)` 印毫秒（Task 8 量測用）。
  - 失敗時：
    - 沒有資料就設 `error`；已有資料則保留畫面、記 warning。
    - 單一市場讀取失敗時，該市場加進 `failedMarkets`，畫面資料保留、基準不動。
    - warning 只在該市場加進 `failedMarkets` 那次記（含從沒成功過的第一次失敗），持續失敗不重複記。
- **`checkFingerprint()` 觸發重讀的條件**：任一市場指紋與基準不同，**或** `failedMarkets` 不是空的。
  - 不能只靠比對基準：若這次重讀是 epoch 觸發、指紋其實沒變，下一分鐘比對相等，失敗的讀取永遠不會重試。
  - 也不能把基準設成 null 代替：null 同時表示「沒有正式資料」，兩種意思會混在一起。
- **`checkFingerprint()`**：
  - reload 進行中（`_inFlight`）只設 `_pending = true`。
  - 否則讀兩個市場的指紋，依上面的條件決定要不要 `reload()`。
  - 讀指紋本身失敗：保留畫面，下一分鐘再試；warning 只在由成功轉失敗那次記，資料庫持續壞掉時不每分鐘一筆。
- **`setVisible(v)`**：
  - `_visible` 初值為 false：畫面第一次 `setVisible(true)` 才啟動計時器。不要照 `LiveQuoteCenter._appVisible` 的初值 true，否則第一次呼叫會被當成同值而不啟動。
  - 值沒變不動作。
  - 變可見：啟動 `Timer.periodic(HeatmapParams.fingerprintPollInterval, (_) => checkFingerprint())`；已讀過一次的話立即 `checkFingerprint()`。
  - 變不可見：取消計時器。
  - 這個方法會在 `didChangeDependencies` 被呼叫，只能動欄位與計時器，不能同步寫 `state`；`checkFingerprint` 第一個動作必須是 await。

- [ ] **Step 1: 寫失敗的測試**（mocktail `MockHeatmapRepository`＋`ProviderContainer`＋`fakeAsync`；`liveQuoteBoundaryProvider` 以可手動換值的假 notifier override）
- `開頁讀取兩個市場；沒有正式資料的市場不在 markets`。
- `epoch 變動重讀`：bump 後 `loadInput` 多叫一次。
- `boundary 換值重讀`。
- `可見時每分鐘比對指紋：不變不重讀`：經過 3 分鐘，`fingerprint` 叫 3 輪、`loadInput` 沒增加。
- `同一日期只改內容也重讀`：第 2 輪指紋只有 `closeSum` 不同 → 重讀。
- `最新資料日改變時重讀、並換成新日期的資料`：`loadInput` 收到新日期。
- `兩個市場分開偵測`：只有上櫃指紋變也會重讀，重讀後兩邊基準都更新。
- `不可見時不輪詢、回到可見立即比對`：不可見 5 分鐘 `fingerprint` 0 次；`setVisible(true)` 後當下 1 次。
- `重讀中又觸發兩次，結束後恰好再讀一次`：`loadInput` 以 Completer 卡住，期間 epoch bump 加一次 `checkFingerprint` → 總共 2 輪讀取。
- `寫入夾在讀指紋與讀資料之間，下一次比對會再重讀`：
  - 第一次讀取時指紋回 fp1、資料已是新的。
  - 下一分鐘指紋回 fp2 → 重讀。
  - 基準必須是 fp1，不是讀資料後的值。
- `指紋查詢失敗保留畫面`：拋錯後 `state.markets` 不變、`error` 仍 null；下一分鐘照常比對。
- `第一次讀取失敗顯示錯誤；有資料後的失敗保留畫面`。
- `dispose 後計時器停止`。

`app_visibility_provider_test.dart`（用 `testWidgets`：普通 `test` 設的 hidden 會留到下一條測試，`testWidgets` 結束時會重設；或在 `addTearDown` 設回 resumed）：
- `初值跟著 WidgetsBinding 的生命週期`：
  - 沒有生命週期狀態時 → true。
  - `handleAppLifecycleStateChanged(AppLifecycleState.hidden)` 後新建 container → false。
  - resumed → true。
- `set 後改變並通知；同值不通知`。

`market_heatmap_provider_test.dart` 另加：
- `單一市場讀取失敗後下一分鐘重試`：已載入完成後 epoch bump，這次上櫃 `loadInput` 拋錯一次（指紋全程不變）。
  - 畫面保留舊資料、`failedMarkets` 含上櫃。
  - 下一分鐘仍會重讀；成功後 `failedMarkets` 清空。
- `持續失敗只記一次 warning`：上櫃連續 3 分鐘失敗，warning 1 次。warning 用 `AppLogger.setSentryDelegates(breadcrumb:)` 收集（前例 `test/presentation/providers/live_quote_provider_test.dart:31`）。
- `沒有正式資料的市場不會每分鐘重讀`：上櫃指紋恆為 null，3 分鐘內 `loadInput` 沒有增加。
- `失敗後讀到沒有正式資料就不再重讀`：上櫃先失敗一次，下一次重讀時指紋為 null → `failedMarkets` 清空，之後 3 分鐘 `loadInput` 沒有增加。
- `第一次讀取整個失敗後，下一次成功清掉 error`。

- [ ] **Step 2: 跑測試確認失敗**

Run: `flutter test test/presentation/providers/market_heatmap_provider_test.dart test/presentation/providers/app_visibility_provider_test.dart`
Expected: FAIL

- [ ] **Step 3: 實作兩個 provider，接上 `main.dart`**

- [ ] **Step 4: 跑測試確認通過**

- [ ] **Step 5: 記錄進度、送審**

---

### Task 6: 繪製與互動（HeatmapView）

**Files:**
- Create: `lib/presentation/widgets/heatmap/heatmap_painter.dart`、`heatmap_view.dart`、`heatmap_tooltip.dart`
- Test: `test/presentation/widgets/heatmap/heatmap_painter_test.dart`、`heatmap_view_test.dart`

**Interfaces:**
- Consumes: Task 1 色表與 `stepOf`；Task 2 型別；Task 3 `layoutHeatmap`、`tileAt`、`industryHeaderAt`。
- Produces：
  - `class HeatmapPaintLabels`：
    - 欄位：`{String uncategorized, String Function(HeatmapIndustryLayout) industrySemantics, String Function(HeatmapTileLayout) tileSemantics}`。
    - 由頁面以翻譯檔組好傳入。
    - 以 `uncategorized` 與兩個函式的 identity 判斷相等。
  - `class HeatmapPainter extends CustomPainter`：
    - 建構子：`HeatmapPainter({required List<HeatmapIndustryLayout> layout, required Brightness brightness, required bool zoomed, required HeatmapPaintLabels labels})`。
    - `shouldRepaint`：`layout` 不是同一個物件，或 `brightness`／`zoomed`／`labels` 改變。
    - `semanticsBuilder`：
      - 未放大時每個產業一個節點（`industrySemantics`）。
      - 放大時每個可互動格子一個節點（`tileSemantics`）。
  - `class HeatmapView extends StatefulWidget`：
    - 建構子：`HeatmapView({required HeatmapMarketData data, required String? zoomIndustryKey, required ValueChanged<String> onIndustryTap, required ValueChanged<String> onTileTap, required HeatmapPaintLabels labels})`。
    - `zoomIndustryKey` 為 null 時畫全市場，否則只把那個產業傳給 `layoutHeatmap`。
  - `class HeatmapTooltip extends StatelessWidget`：建構子 `HeatmapTooltip({required HeatmapTile tile})`。
  - `HeatmapTileStyle heatmapTileStyle(TileChange change, Brightness brightness)`：放在 `heatmap_painter.dart`。
    - `HeatmapTileStyle` 是 `({Color? fill, Color? border, Color text})`；空心時 `fill` 為 null。
    - painter 一律經過它取色。
  - `String formatHeatmapPercent(double percent)`、`String formatHeatmapCap(double marketCap, Locale locale)`：同檔，見下方「漲跌格式」「市值格式」。

繪製規則：
- **填色**：`TileChangeValue` 用 `HeatmapColors.fill(step: stepOf(p), up: p > 0, ...)`，step 0 用 `flat`。
- **空心**：只畫 `hollowBorder` 1px、不填色，文字用 `hollowText`。
- **產業標題列**：
  - 填 `pageBackground`、文字用 `HeatmapColors.headerText`，內容如「半導體業 +1.83%」。
  - 沒有漲跌時只寫名稱；寬度不夠時用省略號。
- **格子文字**：純黑白 `textOn(fill)`，字級 `labelFontSize`。
  - `paint` 寬高 ≥ `tileName*` 時寫名稱＋漲跌幅（各一行）。
  - ≥ `tilePercent*` 時只寫漲跌幅。
  - 文字量出來比格子寬就不寫那一行。
- **自選框**：`isMine` 時在 `paint` 外緣畫 `mineOuter` 1px、內一圈 `mineInner` 1px。
- **漲跌格式**：`+1.83%`／`-0.40%`／`0.00%`，小數 2 位、正值加 `+`。
  - 用一個 `String formatHeatmapPercent(double percent)`（放在 `heatmap_painter.dart`），格子、標題、選單、提示都經過它。
  - 正負號由四捨五入到 2 位後的值決定（與 `stepOf` 同一個值）：0 < |p| < 0.005 一律輸出 `0.00%`，與平盤色一致。
- **市值格式**：`String formatHeatmapCap(double marketCap, Locale locale)`（同檔）。
  - `zh` 開頭的語系：÷ 1e8、小數 1 位、千分位（`1,234.5`）。
  - 其他語系：÷ 1e9、小數 1 位、千分位。
  - 呼叫端用 `Localizations.localeOf(context)` 取語系。不要用 easy_localization 的 `context.locale`：預設的 `buildProviderTestApp` 沒包 EasyLocalization，會拋錯。

`HeatmapView` 的結構：
- `LayoutBuilder` 依（data、zoomIndustryKey、尺寸）快取佈局，三者不變就用同一個 list，`shouldRepaint` 因此回 false。
- `Stack`：
  - `RepaintBoundary(CustomPaint)`。
  - `MouseRegion`（hover → `tileAt` → `ValueNotifier<HeatmapTileLayout?>`；exit 清空）。
  - `GestureDetector`：
    - `onTapUp`：先查 `industryHeaderAt` 再查 `tileAt`。
    - `onLongPressStart`：顯示提示，手機用。
  - `ValueListenableBuilder` 畫 `Positioned` 的 `HeatmapTooltip`，靠在指標旁，超出圖區時翻到另一側。
- 提示內容：
  - 名稱、代號、價格、漲跌幅（`formatHeatmapPercent`）、市值。
  - 市值：`tooltipCap`，`{value}` 用 `formatHeatmapCap`。
  - 空心格子寫原因（`marketHeatmap.hollowNoChange`）。
- `layoutHeatmap` 在 `LayoutBuilder` 內執行時用 `Stopwatch` 計時，`AppLogger.debug('MarketHeatmap', …)` 印毫秒（Task 8 量測用）。

- [ ] **Step 1: 寫失敗的測試**

`heatmap_painter_test.dart`：
- `同樣佈局與主題不要求重畫`。
- `主題改變要重畫`。
- `放大狀態改變要重畫`。
- `未放大時無障礙節點＝產業數；放大時＝可互動格子數`：呼叫 `semanticsBuilder` 數節點、比對 label。
- `格子樣式`（測純函式 `heatmapTileStyle`，不驗畫布）：
  - 空心 → `fill == null`、邊框 `hollowBorder`、文字 `hollowText`。
  - 0% → `flat`；+2% → 漲第 3 階；−9.5% → 跌第 6 階。
  - 兩種主題各一次。
- `formatHeatmapPercent`：`1.834 → '+1.83%'`、`-0.4 → '-0.40%'`、`0 → '0.00%'`、`9.499999999999998 → '+9.50%'`、`0.004 → '0.00%'`、`-0.004 → '0.00%'`。
- `formatHeatmapCap`：`Locale('zh', 'TW')` 下 `123450000000 → '1,234.5'`；`Locale('en')` 下 `123440000000 → '123.4'`、`1234500000000 → '1,234.5'`。測試值都避開四捨五入的中點（例如 123.45），以免綁住格式化實作的進位方式。

`heatmap_view_test.dart`：
- 一律用 `buildProviderTestApp(..., zhTranslations: true)`（`test/helpers/provider_test_helpers.dart`）：`buildTestApp` 沒包 EasyLocalization，`.tr()` 回 key、不代入參數，驗不到提示裡的數字。`setUpAll` 照 `test/CLAUDE.md` 呼叫 `setupTestLocalization()`。
- 找 painter 用 `find.byWidgetPredicate((w) => w is CustomPaint && w.painter is HeatmapPainter)`：`MaterialApp` 的 debug banner 也是 `CustomPaint`。
- 測試清單：
  - `點格子回呼代號`。
  - `點非互動小格沒有回呼`。
  - `點產業標題回呼產業 key`。
  - `滑鼠移上去顯示提示：名稱、代號、價格、漲跌幅、市值`：斷言實際字串，例如 `+1.83%`、`市值 1,234.5 億`。移出後提示消失。
  - `空心格子的提示寫原因`。
  - `長按顯示提示`。
  - `滑鼠移動不重建 CustomPaint`：hover 前後取到的 painter 是同一個物件。
  - `主題切換後提示仍在、painter 改用深色`：同一份資料從淺色切到深色，`pumpAndSettle` 後再斷言（`AnimatedTheme` 過半才換 brightness）。
- `極小圖區不拋錯`：包在 `SizedBox(width: 10, height: 10)`。
- `放大後只畫該產業`：`zoomIndustryKey` 設定後無障礙節點變成該產業的格子。

- [ ] **Step 2: 跑測試確認失敗**

Run: `flutter test test/presentation/widgets/heatmap/`
Expected: FAIL

- [ ] **Step 3: 實作三個檔案**

- [ ] **Step 4: 跑測試確認通過**

- [ ] **Step 5: 記錄進度、送審**

---

### Task 7: 熱力圖頁、入口、文案、golden

**Files:**
- Create: `lib/presentation/screens/market/market_heatmap_screen.dart`、`lib/presentation/widgets/heatmap/heatmap_legend.dart`
- Modify: `lib/core/constants/app_routes.dart`（`static const marketHeatmap = '/market-heatmap';`）、`lib/app/router.dart`（大盤總覽之後加全螢幕 `GoRoute`，name `marketHeatmap`）、`lib/presentation/screens/market/market_overview_screen.dart`（AppBar `actions` 加 `IconButton(Icons.grid_view)`，tooltip 用 `marketHeatmap.title`，`context.push(AppRoutes.marketHeatmap)`）、`assets/translations/zh-TW.json`、`assets/translations/en.json`、`CHANGELOG.md`
- Test: `test/presentation/screens/market/market_heatmap_screen_test.dart`、`test/presentation/screens/golden/market_heatmap_screen_golden_test.dart`、`test/presentation/heatmap_no_hardcoded_cjk_test.dart`、`test/presentation/screens/market/market_overview_screen_test.dart`（既有檔，加一條入口測試）、`test/app/router_market_heatmap_route_test.dart`

**Interfaces:**
- Consumes：
  - Task 5 `marketHeatmapProvider`、`appVisibilityProvider`；Task 6 `HeatmapView`、`HeatmapPaintLabels`。
  - 既有 `marketOverviewProvider`、`marketLiveIndicesProvider`、`marketIndexRegistrations`、`appClockProvider`、`AppRoutes.stockDetail`。
- Produces：`class MarketHeatmapScreen extends ConsumerStatefulWidget`（route builder 使用）。

頁面組成（由上而下）：
1. **AppBar**：
   - 標題 `marketHeatmap.title`；放大時標題換成 `TextButton`（`marketHeatmap.backToWhole`「← 全市場」），點了回全市場。系統返回鍵維持在 leading。
   - `actions`：上市／上櫃 `SegmentedButton`（樣式同 `MarketDashboard._buildMarketSelector`），以及產業選單 `PopupMenuButton`。
   - 產業選單第一項「全市場」，其餘依市值排序，每項後面帶市值加權漲跌（`formatHeatmapPercent`；沒有時 `—`）。
2. **頁首**：
   - 指數照大盤總覽頁 `market_dashboard.dart:366-375`／`406-415` 同一套：
     - `shown = marketLiveIndicesProvider.byMarket[market]`；官方值取 `marketOverviewProvider` 的 `indices` 中 `heroIndexName(market)` 那一筆。
     - 顯示 `shown?.index ?? 官方值`。
     - 非即時標示：`isStale = !(shown?.isLive ?? false) && state.indexStaleNames.contains(name)`。
     - 另外帶 `flash`、`flashEnabled`、`statusText`。
     - 漲跌幅用 `indexChangePercentText`（`market_overview_selectors.dart:27`）。
     - 兩者都沒有時顯示 `marketOverview.noData`。
   - 指數名稱沿用 `marketOverview.summary.taiex`／`marketOverview.summary.tpex`（加權／櫃買），不另開 key。
   - 右側寫熱力圖資料時間 `marketHeatmap.closeOf`（`M/d`，取該市場 `dataDate`）。
3. **圖例**（`HeatmapLegend`）：
   - 色階 13 格，兩端寫 `marketHeatmap.legendMax`，`{value}` 取 `HeatmapParams.stepBounds.last`。
   - 另外三項：自選雙線框、空心格子、「產業漲跌為市值加權」。
4. **`Expanded(HeatmapView)`**。
5. **頁尾**：`excludedForShares > 0` 才顯示 `marketHeatmap.footerExcluded`。

可見性元件 `_HeatmapVisibility`（`ConsumerStatefulWidget`）包住**整個 Scaffold body**：
- 載入中、錯誤卡片、空狀態、熱力圖四種狀態都在它裡面。
  - 只包 `HeatmapView` 的話，沒資料的畫面不會輪詢：剛安裝的空狀態等不到 launchd 第一次寫入，切到沒資料的市場時還會把輪詢整個停掉。
- `initState` 先取 `ref.read(marketHeatmapProvider.notifier)` 存起來：Riverpod 3 在 dispose 時 `ref.read` 會拋 `StateError`（`main.dart:277` 的註解；`LiveQuoteScope` 同做法）。
- 在 `didChangeDependencies` 與 `ref.listenManual(appVisibilityProvider)` 時，以 `TickerMode.of(context) && appVisible` 呼叫 `setVisible`。
- dispose 時用存起來的 notifier 呼叫 `setVisible(false)`。

其他規則：
- 整頁包 `LiveQuoteScope(registrations: marketIndexRegistrations(overviewState, now))`，並 `ref.watch(liveQuoteBoundaryProvider)` 讓登記跨邊界重算，與 `MarketOverviewScreen` 相同。
- 狀態（依序判斷，針對目前選的市場）：
  - `isLoading` 且沒有任何資料：載入中。
  - 有 `error`，或目前市場在 `failedMarkets` 且不在 `markets`：錯誤卡片＋重試（樣式同 `MarketOverviewScreen._content`），重試呼叫 `reload()`。
  - 目前市場不在 `markets`：空狀態 `marketHeatmap.empty`。
- `HeatmapPaintLabels` 在 State 的 `didChangeDependencies` 依目前 locale 建一次並保存。不要在 `build` 內每次新建：closure 每次都是新物件，`shouldRepaint` 會一直回 true。
- 切換市場清掉放大。
- `zoomIndustryKey` 不在目前市場的產業裡（重讀後消失）時視同全市場。
- 點格子 `context.push(AppRoutes.stockDetail(symbol))`。

翻譯（`marketHeatmap` 區塊，zh-TW／en）：

| key | zh-TW | en |
|:--|:--|:--|
| `title` | 大盤熱力圖 | Market Heatmap |
| `wholeMarket` | 全市場 | All industries |
| `backToWhole` | ← 全市場 | ← All industries |
| `industryMenu` | 產業 | Industry |
| `closeOf` | `{date} 收盤` | `Close {date}` |
| `legendMax` | `≥ {value}%` | `≥ {value}%` |
| `legendMine` | 雙線框＝自選或持股 | Double border = watchlist or holding |
| `legendHollow` | 空心＝沒有今日漲跌 | Hollow = no change today |
| `legendWeighted` | 產業漲跌為市值加權 | Industry change is market-cap weighted |
| `footerExcluded` | `{count} 檔缺股數或股數不一致，未列入` | `{count} stocks not shown: share count missing or inconsistent` |
| `empty` | 完成第一次資料更新後就會顯示 | Shown after the first data update |
| `loadError` | 熱力圖資料讀取失敗 | Failed to load heatmap data |
| `uncategorized` | 未分類 | Uncategorized |
| `hollowNoChange` | 無漲跌資料 | No change data |
| `tooltipPrice` | 價格 | Price |
| `tooltipChange` | 漲跌幅 | Change |
| `tooltipCap` | `市值 {value} 億` | `Market cap NT${value}B` |
| `dirUp`／`dirDown`／`dirFlat` | 上漲／下跌／平盤 | up／down／flat |
| `semIndustry` | `{name}，市值加權{dir} {pct}，共 {count} 檔` | `{name}, cap-weighted {dir} {pct}, {count} stocks` |
| `semIndustryNoChange` | `{name}，無漲跌資料，共 {count} 檔` | `{name}, no change data, {count} stocks` |
| `semTile` | `{name}，{dir} {pct}` | `{name}, {dir} {pct}` |
| `semTileHollow` | `{name}，{reason}` | `{name}, {reason}` |

CHANGELOG `### Added` 加一條：
- 大盤熱力圖：從大盤總覽頁標題列進入，上市、上櫃各一張。
- 依產業分區、面積是市值、顏色是當日漲跌。
- 可從產業選單或點產業標題放大；點格子進個股頁；滑鼠移上去或長按看價格、漲跌幅與市值。
- 自選或持股加雙線框，沒有漲跌資料的畫成空心。
- 盤後資料在背景寫入後一分鐘內自動更新。
- 盤中即時顏色會在後續版本加入。

- [ ] **Step 1: 寫失敗的測試**

`market_heatmap_screen_test.dart`：
- override `marketHeatmapProvider`、`marketOverviewProvider`、`marketLiveIndicesProvider`。
- 斷言文字的測試用 `buildProviderTestApp(..., zhTranslations: true)`，原因同 Task 6。
- 測試清單：
  - `兩個市場日期不同時頁首跟著切換`：上市 10/7、上櫃 10/6，切到上櫃顯示「10/6 收盤」。
  - `只有一個市場有資料，另一個顯示空狀態`。
  - `第一次讀取失敗顯示錯誤卡片、重試呼叫 reload`。
  - `沒有任何資料顯示空狀態文案`。
  - `頁尾只在有缺股數時顯示`：excluded 3 → 「3 檔缺股數或股數不一致，未列入」、0 → 無。
  - `圖例`：13 格色塊、「≥ 9.5%」、自選、空心、市值加權四項文字都在；切換深淺主題、`pumpAndSettle` 後，色塊換成該主題色表。
  - `指數非即時時標示，與大盤總覽一致`：`isLive` false 且名稱在 `indexStaleNames` → 出現非即時標示。
  - `產業選單依市值排序並帶漲跌；選了就放大、標題換成「← 全市場」`。
  - `窄螢幕放大狀態點得到「← 全市場」`：
    - 寬 360，用 go_router 從另一頁 push 進來（才會有返回鍵）。
    - 放大到名稱最長的產業後，「← 全市場」按鈕寬度 ≥ 48（最小點擊區），點了回全市場。
    - AppBar 擠不下時標題只會被壓扁、不拋 overflow，所以不能用「沒有 overflow 例外」當斷言。
  - `切換市場清掉放大`。
  - `放大中的產業在重讀後消失時回到全市場`。
  - `點格子進個股頁`：用 go_router 測試 app 驗 location 為 `/stock/9901`。
  - `被不透明頁蓋住時 setVisible(false)、返回後 true`：用假 notifier 記錄呼叫。
  - `空狀態、錯誤卡片、載入中也會 setVisible(true)`：三種狀態各一次。
  - `切到沒資料的市場不會 setVisible(false)`。
  - `單一市場第一次讀取失敗時顯示錯誤卡片，不是空狀態`：上櫃在 `failedMarkets`、不在 `markets`。
  - `離開頁面時 setVisible(false) 不拋錯`：pop 後沒有 `StateError`。

`market_overview_screen_test.dart`：`標題列有熱力圖入口，點了進 /market-heatmap`。

`test/app/router_market_heatmap_route_test.dart`：照 `router_market_route_test.dart`，用真正的 `router.dart` 驗 `/market-heatmap` 建出 `MarketHeatmapScreen`。總覽頁的入口測試用的是自建 router，抓不到真 router 漏接。

`heatmap_no_hardcoded_cjk_test.dart`：
- 掃 `market_heatmap_screen.dart` 與 `lib/presentation/widgets/heatmap/*.dart`。
  - 不掃 provider：它只有 `AppLogger` 的中文 log，不是使用者看得到的字。
- 去掉 `//` 註解後，不得含 CJK 統一表意文字（U+4E00–U+9FFF）。
- 另加檔案數下限 ≥ 5，路徑寫錯時才不會無聲通過。

golden（`@Tags(['golden'])`，虛構資料：3 個產業、約 20 檔，含空心、平盤、自選框、各階）：
- `熱力圖頁（淺色）`、`熱力圖頁（深色）`。
- 寬度照 `market_overview_screen_golden_test.dart` 的設定。

- [ ] **Step 2: 跑測試確認失敗**

Run: `flutter test test/presentation/screens/market/ test/presentation/heatmap_no_hardcoded_cjk_test.dart test/app/router_market_heatmap_route_test.dart`
Expected: FAIL

- [ ] **Step 3: 實作頁面、圖例、路由、入口、翻譯、CHANGELOG**

- [ ] **Step 4: 跑測試確認通過；產生 golden 並目視檢查**

Run: `flutter test test/presentation/screens/market/ test/presentation/heatmap_no_hardcoded_cjk_test.dart test/app/router_market_heatmap_route_test.dart test/core/l10n/ test/golden_tag_guard_test.dart && flutter test --update-goldens test/presentation/screens/golden/market_heatmap_screen_golden_test.dart`
Expected: PASS；Read 兩張 png 目視確認色階、空心、自選框、標題列、頁尾

- [ ] **Step 5: 記錄進度、送審**

---

### Task 8: 全套驗證、量測、mutation、審查、經同意提交

**Files:** 依結果修改；`docs/plans/2026-11-04-market-heatmap-1-plan.md` 末尾補「實作後的修正」。

- [ ] **Step 1: 全套與靜態檢查**

Run: `flutter analyze && flutter test`
Expected: analyze 0 issue；全套綠。記下通過數，與開工前基準比對（基準在 Task 1 開始前先跑一次記進帳本）。

- [ ] **Step 2: 量測讀取＋計算時間**（spec 驗證 7）
- 對真實資料庫開 GUI debug（`flutter run -d macos`），開熱力圖頁、切市場、等一分鐘輪詢。
- 從 log 讀 `MarketHeatmap` 的毫秒數：provider 的讀取、計算，以及 view 的佈局。
- 照 spec：任一市場「資料讀取＋計算」超過 100ms 時，把 `buildHeatmapMarket` 改成 `Isolate.run` 執行。
  - 若改了，寫一條測試：同一份輸入在 isolate 與主 isolate 結果相等。100ms 是這次量測的判準，執行期沒有消費者，不加常數。
  - 佈局時間另外記錄；超過一幀（約 16ms）時寫進計畫末尾，交給審查判斷要不要處理。
  - 結果記進計畫末尾。
- 滑鼠在圖上快速移動時，用 DevTools 效能面板確認沒有整張重畫（只有提示層 rebuild）。

- [ ] **Step 3: 盤後寫入後自動切回**（spec 驗證 7）
- App 開在熱力圖頁、保持前景，等下一次 launchd 寫入（15:30 或 21:30）。
- 確認一分鐘內頁首日期換成當天，log 有指紋變化觸發的重讀。
- 同時記錄當輪 update_run 狀態：若遇到上櫃全市場行情斷線（`價格資料更新失敗 … TPEX request failed`），**兩個市場**都停在前一天是預期行為（`safeAwaitPair` 對 `NetworkException` 往上拋，上市也不寫），換一輪再驗。

- [ ] **Step 4: mutation**（照 spec 驗證 6 的第 1 段項目，每個突變手動改、跑對應測試、確認變紅、還原；還原用備份檔，不用 `git checkout`）

| 目標 | 突變 | 應該變紅的測試 |
|:--|:--|:--|
| `isExcludedIndustry` | 拿掉 `存託憑證`；ETF 的「包含」改成「等於」（`上櫃ETF` 漏掉） | grouping「排除 ETF…」、params `isExcludedIndustry` |
| `resolveHeatmapShares` | `>` 改 `>=`；同日改取董監；上市也看董監；拿掉「≤ 0 視同沒有」 | 股數規則各條 |
| `heatmapChangePercent` | 分母 `<= 0` 改 `< 0`；改用 `close` 當分母 | 漲跌幅兩條 |
| grouping 的 `close <= 0` 略過 | 拿掉 | 「收盤 ≤ 0 略過且不計頁尾」 |
| 產業加權 | 空心成員以 0 計入；改成簡單平均 | 「產業漲跌為市值加權」 |
| `stepOf` | 拿掉四捨五入；任一分界 `>=` 改 `>` | params 兩條 |
| `squarify` | 改成固定沿寬邊切 | 長寬比 |
| `layoutHeatmap` | 標題列寬、高門檻各拔一次；`interactive` 恆 true | 小產業標題列、極小圖區 |
| `tileAt` | 不檢查 `interactive` | 「tileAt 只回可互動的格子」 |
| `getLatestFormalPriceDate` | 拿掉 `dataset = prices` 條件 | 「其他資料集的紀錄不算」 |
| `getHeatmapPriceRows` | `is_active`、市場、`close IS NOT NULL` 三個條件各拔一次 | 「價格列排除下市、他市場、收盤空值」 |
| 指紋四成分 | 各拔一個 | 四條「只有它變」 |
| `reload` 合併 | 進行中觸發直接丟棄；改成每次觸發各讀一次 | 「恰好再讀一次」 |
| 基準 | 讀資料後重讀指紋當基準 | 「寫入夾在中間」 |
| `failedMarkets` | `checkFingerprint` 不看它；拿掉 warning 去重；讀到沒有正式資料時不移除 | 「單一市場讀取失敗後下一分鐘重試」、「持續失敗只記一次 warning」、「失敗後讀到沒有正式資料就不再重讀」 |
| `setVisible` | 回到可見不立即比對；`_visible` 初值改 true | 「回到可見立即比對」、「可見時每分鐘比對」 |
| `shouldRepaint` | 不比 brightness | painter「主題改變要重畫」 |

存活的突變補測試，記進計畫末尾。

- [ ] **Step 5: 文件同步**
- 確認 `CHANGELOG.md` 已寫。
- 檢查 `README.md` 功能清單、`CLAUDE.md`／`.claude/rules/architecture.md`（三條讀取路徑：熱力圖走 ① Provider，不新增路徑）要不要補，有就補。

- [ ] **Step 6: 整段審查**
- 送 `pr-review-toolkit:code-reviewer`（opus）。
- 範圍：本段 BASE（帳本記錄的 Task 1 開工時 HEAD）到工作樹，含新檔全文。
- Critical／Important 修完再審；第 3 輪還有就停下報告。
- 最後一輪通過後沒再改動，那次就算提交前檢查。

- [ ] **Step 7: 停下回報，等使用者說「提交」**
- 提交訊息示意：`feat: 大盤熱力圖（收盤後）`。
- 內文列出：頁面與入口、資料規則（股數、漲跌、納入範圍）、重讀機制、色階守門、量測結果。
- 提交後 post-commit 會重編 launchd CLI（`HeatmapDaoMixin` 在閉包內），確認 `~/.daredevil/cli/daily_update/BUILD_INFO` 換成新 SHA。

---

## 順帶發現（範圍外，記錄不修）

**上櫃斷線調查（2026-11-04）**：spec「順帶發現」第一項的追查結果，以及 Review Focus 第 1 條的背景。

**現象**：
- 7 月以來 update_run 訊息提到 TPEX 的 PARTIAL 有 23 列：
  - 全市場行情 `stk_quote_result.php` 斷線 9 次。
  - openapi `mopsfin_t187ap03_O`／`t187ap11_O`／`t187ap39_O` 斷線 8 次。
  - receive timeout 5 次。
  - 另 1 列（10/12 15:30 那輪，13 項失敗，FinMind 也逾時）是整體斷網，不算櫃買。
- 7 月的 PARTIAL 訊息沒有錯誤內容，所以先前記的「每月 7 月 0、8 月 4、9 月 6、10 月 11」不能當趨勢。
- 重試成功的輪次不會留下 PARTIAL。10/28～11/4 的 log 中，有抓上櫃全市場行情的 11 輪裡，第一次請求就被斷的有 4 輪，其中 1 輪三次全斷（10/30 21:30）。

**判斷**：
- 往櫃買的大回應會在傳輸途中被切斷。最可能在櫃買端（伺服器是 nginx，後端 Java），但也可能在往櫃買的網路路徑上：對照組走的是不同路由，也沒換別的網路驗。
  - app 端看到的是 `HttpException: Connection closed while receiving data`。
  - curl 看到的是 `Recv failure: Connection reset by peer`，HTTP 200、body 不完整。
- 斷線只出現在大回應：

  | 端點 | 大小 | update_run 斷線／逾時 |
  |:--|--:|:--|
  | `t187ap11_O` 董監持股 | 6.6 MB | 有 |
  | `t187ap39_O` 股利 | 5.1 MB | 有 |
  | `stk_quote_result.php` 全市場行情 | 2.0 MB（13,626 列，程式只留約 908 列） | 有 |
  | `t187ap03_O` 公司基本資料 | 1.1 MB | 有 |
  | 法人、融資券、本益比 | 108～157 KB | 0 次 |

  每個端點每輪都只打一次，曝險次數相同，但只有大回應會斷。
- 11/4 22:13～22:16（離峰）實測重現：

  | 對照組（同一條手機熱點路徑） | 大小 | 結果 |
  |:--|--:|:--|
  | 櫃買 `t187ap39_O` | 5.1 MB | 8 次有 6 次在 2～5 秒、收到 0.3～3.6 MB 時被 reset；成功的那次要 27.7 秒 |
  | Cloudflare | 5.1 MB | 4/4 成功（4～12.7 秒） |
  | 證交所 `t187ap03_L` | 1.3 MB | 4/4 成功 |

  本機這一段（熱點、Kaspersky 網路延伸〔已停用〕）因此排除，櫃買流量也沒有經過 VPN（走 en7、閘道 172.20.10.1）。這次實驗只做在 curl，沒有寫進 log 或 repo。
- 熱點頻寬本身只有約 0.4～1.2 MB/s，會拉長大回應的傳輸時間；這可能放大曝險，但換網路驗不了。
- 伺服器端縮不了回應：
  - 不支援壓縮（要 gzip 也回原文）。
  - 新舊兩個行情端點都沒有類別篩選（舊站 `se`、新站 `type` 參數都被忽略；官方行情頁表單只有日期）。
- 整點較慢、但不只整點才斷：
  - 排程 15:30／21:30 整點起跑時，全市場行情要 1.4～39 秒。
  - 21:58 兩個機房（台灣固網 210.63.162.130、新世紀資通 218.210.125.130）各 5 次全成功、約 1.5 秒。
  - 但上面 22:13 的離峰重現說明斷線不限整點。
- 已排除的候選：
  - 同輪並行：全市場行情是該輪第一個櫃買請求。
  - 殘留 keep-alive：每輪都是新程序。
  - 本機網路：見上面的對照組；排程那輪同一秒上市只花 0.4 秒。
- 連續失敗有時會聚集（10/30 21:30 三次全斷；11/4 22:15 連三次 reset），但排程那幾輪也有用現有 1～2 秒間隔就重試成功的（10/28、10/29、11/4 15:30）。現有資料分不出間隔長短與成功率的關係。

**影響**：
- `safeAwaitPair` 對 `NetworkException` 往上拋，上市已抓到的價格也不寫。
- 15:30 失敗：該輪評分用前一天的 K 棒。
- 21:30 失敗：價格停在 15:30 初值，等隔天步驟 5.5 定案重抓補回。

**建議修法**（技術上我建議先做 1，2、3 是待驗證的實驗；何時做由使用者排序）：
1. **`syncAllPricesForDate` 一邊成功時，另一邊的 `NetworkException` 不再往上拋**：
   - 另一市場照寫；失敗那個市場另外 `recordError`，附上原始例外，讓本輪 PARTIAL。
   - 不能直接沿用 `emptyMarkets` 的訊息：「當日價格為零筆」描述錯了。而且 `update_service.dart:811-818` 在 `dateRolledBack` 時不記錯，沿用那條路會把網路錯誤吞掉。
   - 兩邊都斷才往上拋（那才是真的斷網）。
   - 前例：上櫃當沖的每日路徑也只吞 `NetworkException`（`update-pipeline.md` 的 MarketDataUpdater 段）。
   - 要在 CLAUDE.md 錯誤處理段註明這個例外。
2. **大回應端點加長重試間隔或加次數**：目前沒有證據支持（見上一段），要先實驗再決定。
3. **launchd 排程避開整點**（例如 15:37／21:37）兩週，從 log 比較全市場行情耗時與第一次斷線率。
   - 只能改善「整點較慢」那部分；離峰也會斷，所以單靠它不夠。

## 計畫審查紀錄

- **2026-11-04 第 1 輪**（`pr-review-toolkit:code-reviewer`／opus）：1 Critical、7 Important、約 20 個 Minor。我逐條核對後全數納入：
  - **Critical**：`main.dart` 的 `initState` 寫 `appVisibilityProvider` 會在 debug 拋錯 → 改成 `build()` 讀生命週期、只在回呼裡 `set`。
  - **Important**：
    - dispose 時 `ref.read` 拋錯 → 改成 `initState` 先存 notifier。
    - 英文市值字串拼 `00` 算錯 → 改成以十億為單位另算。
    - 頁首指數漏了「非即時」標示 → 照大盤總覽的欄位列全。
    - 浮點測試例在 IEEE 下剛好等於 1.5，測不到問題 → 換成 6.57／0.57。
    - 「兩市場日期不同」的成因寫錯 → 改寫，並改正驗收預期。
    - 測試環境 `.tr()` 回 key → 斷言文字的測試改用真翻譯。
    - 修法 2 的佐證把下載耗時誤讀成重試間隔 → 撤回。
  - **Minor**：
    - DAO 讀 MAX 日期的 UTC 陷阱。
    - 可見性初值、單一市場失敗時的基準：改成設為 null，我自己核對時發現「保留舊基準」會讓失敗不重試。
    - 產業標題文字色進 `HeatmapColors`。
    - painter 的找法、10×10 測試資料、真 router 測試、圖例與主題切換測試。
    - 突變表補子條件。
    - 漲跌幅一律 2 位（與分階一致）。
    - 指數名稱沿用既有 key、`legendMax` 取參數。
    - isolate 門檻延到量測後、量測判準照 spec。
    - 「← 全市場」放標題、窄螢幕測試。
    - 斷線調查的次數與根因措辭。
- **2026-11-04 第 2 輪**（同一位審查者，只審第 1 輪的改動）：0 Critical、1 Important、9 Minor，全數納入：
  - **Important**：可見性元件只包 `HeatmapView`，空狀態、錯誤、載入中都不輪詢（剛安裝等不到第一次寫入、切到沒資料的市場會停掉輪詢）→ 改包整個 body，加兩條測試。
  - **Minor**：
    - 「失敗」與「沒有資料」共用 null → 改成 `failedMarkets`，讀取失敗的市場顯示錯誤卡片而不是空狀態，warning 不重複記，成功時清 `error`。
    - 極小值的正負號跟著四捨五入後的值。
    - 2 位小數後的文字門檻改 40。
    - 英文市值抽成 `formatHeatmapCap` 並測兩種語系。
    - 主題切換測試要 `pumpAndSettle`。
    - 窄螢幕測試經 router 進入、改斷言按鈕點得到。
    - 浮點測試不寫死精確值。
    - 生命週期測試用 `testWidgets` 避免狀態外漏。
    - 殘留措辭（isolate 門檻、「唯一」的範圍、10/12 那輪的時間、spec 附註的大小門檻）。
- **2026-11-04 第 3 輪**（同上，只審第 2 輪的改動）：0 Critical、0 Important，**可交付**。
  - 審查者逐一追過 `failedMarkets` 的各種情境（持續失敗、重讀中再失敗、讀到沒有正式資料、一好一壞、讀指紋失敗、第一次單邊或雙邊失敗），沒有迴圈也不會漏重試。
  - 6 個 Minor 我已直接改掉：
    - 突變表「基準」列換成三條 `failedMarkets` 突變。
    - 補「失敗後讀到沒有正式資料就不再重讀」測試。
    - warning 的記法與收集方式。
    - grouping 浮點測試改用 3.07／0.07。
    - 刪掉 Task 1 的 isolate 殘留句。
    - 窄螢幕斷言改成按鈕寬度 ≥ 48。
