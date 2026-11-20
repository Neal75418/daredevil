# 收盤摘要 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 新增「收盤摘要」頁與今日頁入口卡：持股與自選股每檔一列，照 v3 標出狀態與事件，最上面一行大盤油門。

**Architecture:** 計算全部是 domain 層的純函式（個股價格條件、籌碼章、油門、持股、組裝），輸入是已讀好的資料列，輸出是 `CloseSummary`。一支 loader 從資料庫讀出輸入（可指定資料日，供量測用），provider 接 loader 與組裝。畫面只顯示 `CloseSummary`，不再計算。

**Tech Stack:** Flutter／Dart 3、Riverpod 3、Drift、easy_localization、go_router、flutter_test。

**Spec:** `docs/plans/2026-11-20-close-summary-design.md`

## Global Constraints

- 門檻全部放 `CloseSummaryParams`（Task 1）；已有的沿用：強者榜月漲 `SectorParams.rotationStrongListRet20Pct`（15.0）、20 日均量 `SectorParams.rotationStrongListDailyVolumeShares`（3,000,000 股）、守門價 `AlertParams.stopGateAtrMultiple`（2.0）與 `AlertParams.stopGateAtrPeriod`（20）。
- 價格用資料庫原始價；組裝前每檔先 `contiguousSuffix()`，再去掉收盤為 null 的列。回看天數不夠的條件是「資料不足」，一律當未通過。
- 漲跌幅一律 `PriceCalculator.calculatePriceChange(bars, bars.last)`；漲跌停一律 `PriceLimit.statusOf(changePercent: …)`（`.isUp`／`.isDown`）。
- ATR 的 K 線一律經 `AlertTargetCalculator.ohlcFrom`（Task 2 從 `AlertQuickSet.toOhlc` 搬來），與個股頁同一口徑。交易類型用 `TransactionTypes` 常數、市場代碼用 `MarketCode`。
- 張數＝股數 ÷ 1,000，只在畫面換算；domain 層一律用股。
- 只用正式盤後資料，不讀即時報價。
- 畫面字一律走 `assets/translations/zh-TW.json` 與 `en.json`，並且要過 `test/core/l10n/no_investment_advice_copy_test.dart`（禁「推薦」「進場」「停損」「停利」「機會」「值得」等；英文照該檔的 regex 全部避開，包括 entry、stop loss、picks——「強者榜」不可譯成 strong picks）；不為 `closeSummary.` 開放行清單。所以畫面用語是：持股的停損價叫「成本守門價」（與個股頁「最新收盤 − 2×ATR」的守門價不同值，名稱要分開），時間停損寫「8 日未達 +1R」，進場前提寫「前提條件」，結構 C 寫「突破當天」。
- 事件 chip 不用紅綠（紅綠只給股價漲跌，見 `semantic_colors.dart`）。
- 讀「現在」用注入的 `AppClock`（`appClockProvider`）；測試照 `test/CLAUDE.md`（撥時間、`DeviceTime`）。
- 註解只寫現在式的「做什麼／為什麼」，不寫日期、審查編號、改動歷史。
- `flutter analyze` 全專案無訊息（info 也擋）。
- 流程：實作者不 commit；每個 Task 做完送 `pr-review-toolkit:code-reviewer`（opus）審查，Critical／Important 修完才進下一個 Task（審查不設輪數上限，第 3 輪還有 Critical／Important 先停下報告）。整份計畫一次提交：Task 1～5 審完不停下等提交，Task 6 Step 7 使用者說「提交」才提交。直接在 `main` 上做，不開分支、不建 worktree。
- 每條新測試先看到紅再實作；突變還原用寫回原內容並逐位元組比對，不用 `git checkout`。

## 計畫審查後定案的事（設計文件已同步）

- 資料日 D＝`daily_price` 的最新日期（`getLatestDataDate()`，兩個市場合計），不是「TWSE 的最新交易日」；某個市場 D 還沒有資料時，那個市場的股票寫「行情未到」（Task 3、Task 4）。
- 「法人已到」改成分市場判斷；頁首寫哪個市場未到。
- 加權指數最後一筆不是 D 時，油門寫「加權指數未到」，不拿前一天的狀態頂替。
- 強者榜條件「可展開看」改成直接列出未通過的條件名稱，不做展開互動。
- 畫面用語照 Global Constraints 改（設計文件的「停損價」「時間停損到期」「突破日不進場」是概念名稱）。

## 順帶發現（範圍外，只記錄）

- 連買天數的算法與法人排行頁不同：資料庫不存三方都是 0 的法人列，讀取端把「沒有列」當 0（`institutional_dao.dart` 的 `deleteInstitutionalRows` 說明），本計畫照此把缺的那天當 0、連買中斷；法人排行的 `streak` 只走有資料的列、缺的那天跳過，連買不中斷。同一檔在兩頁可能顯示不同的連買天數。本計畫維持現在的算法，法人排行要不要改另案。

## Review Focus

1. 某檔在資料日沒有成交（停牌、處置）vs. 它所屬市場的資料還沒寫入（上櫃行情常被切斷）→ 前者寫「資料日沒有成交」，後者寫「行情未到」；兩者都不標待處理事件、不算進入口卡。（Task 3 Step 1 第 6 條）
2. 價格到了、某個市場的法人還沒到 → 頁首寫哪個市場未到，那些股票的籌碼章與雙章齊不判，不拿前一日頂替。（Task 2 Step 1 第 5 條、Task 3 Step 1 第 8 條、Task 4 Step 1 第 2 條）
3. 持股賣光後又買回、或進場已經好幾個月 → 進場日取最後一次歸零後第一筆買進；進場很久以前也照樣算得出成本守門價。（Task 2 Step 5 第 3 條、Task 4 Step 1 第 3 條）
4. 沒有自選也沒有持股、或資料庫沒有任何價格 → 頁面與入口卡顯示空狀態或不顯示，不丟例外。（Task 4 Step 1 第 4 條、Task 5 Step 1 第 6 條、Task 6 Step 1 第 3 條）
5. 使用者把「強者榜」分組改名 → 頁首寫明找不到，強者榜相關事件（含「符合強者榜入選條件」）都不標，其他事件照常。（Task 3 Step 1 第 4 條、Task 5 Step 1 第 4 條）

---

### Task 1: 參數、個股價格條件、油門（純函式，不接線）

**Files:**
- Create: `lib/core/constants/close_summary_params.dart`
- Create: `lib/domain/services/close_summary/price_checks.dart`
- Create: `lib/domain/services/close_summary/throttle.dart`
- Test: `test/domain/services/close_summary/price_checks_test.dart`、`test/domain/services/close_summary/throttle_test.dart`

**Interfaces:**
- Produces:

```dart
abstract final class CloseSummaryParams {
  static const int maPeriod = 20;
  static const int throttleThresholdDays = 4;      // 5 日門檻＝前 4 日收盤平均
  static const int demotionBelowMaDays = 2;
  static const int sectorCoolingMinStocks = 2;
  static const int structureCLookbackDays = 20;
  static const List<int> structureBSupportPeriods = [5, 10, 20];
  static const int structureBTrendMaPeriod = 10;
  static const double structureBTouchRatio = 1.015;
  static const double structureBHoldRatio = 0.995;
  static const double triggerDayDowngradePct = -5.0;
  static const double maxBiasPct = 15.0;
  static const double minRevenueYoy3mPct = 30.0;
  static const double minDayVolumeShares = 3000000;
  static const int chipStreakDays = 3;
  static const double chipMinVolumeShare = 0.01;
  static const int timeStopTradingDays = 8;
  static const int priceLookbackCalendarDays = 130; // 夠 61 根（60 日漲幅）＋長假
  static const int holdingAtrLeadCalendarDays = 45; // 進場日之前要多讀的天數（ATR(20) 需 21 根）
  static const String strongListGroupName = '強者榜';
  static const String delistReviewGroupName = '除名重審';
  static const String thermometerGroupName = '大盤溫度計';
}

enum CheckOutcome { pass, fail, insufficient }

class StrongListCheck {            // 四條件各自的結果
  final CheckOutcome ret20, limitUpIn20, avgVolume20, aboveMa20;
  int get passed;                  // pass 的條數
  bool get allPassed;
}
StrongListCheck checkStrongList(List<DailyPriceEntry> bars);
/// >0：連續收在當日 20MA 之上（含等於）的天數；<0：連續收在之下的天數；資料不足回 0。
int maSideStreak(List<DailyPriceEntry> bars);
bool crossedBelowMa(List<DailyPriceEntry> bars); // D 收在 20MA 下、前一日在 20MA 上（含等於）
int? structureBSupport(List<DailyPriceEntry> bars); // 成立時回支撐均線週期（5／10／20，取最短的）；不成立或資料不足回 null
bool structureC(List<DailyPriceEntry> bars);
class EntryPrerequisites {
  final CheckOutcome moving, bias, revenue, dayVolume;
  final double? biasPct;
  bool get allPassed;
}
EntryPrerequisites checkEntryPrerequisites(List<DailyPriceEntry> bars, {required double? revenueYoy3m});

enum ThrottleState { full, reduced, flat }
class ThrottleReading {
  final ThrottleState state;
  final double close, ma20, threshold;
  final DateTime? lastBreakDate;   // 讀到的歷史裡最近一次收破 5 日門檻的日子（含 D）
  final int? tradingDaysSinceBreak;
  final int lookbackTradingDays;   // 查過收破與否的交易日數＝筆數 − 4（前 4 筆沒有門檻可比）；lastBreakDate 為 null 時畫面寫「近 N 個交易日內沒有」
}
ThrottleReading? readThrottle(List<MarketIndexEntry> taiex); // 升冪；少於 21 筆回 null；不檢查日期（由 Task 3 判斷）
```

所有 `bars` 都是升冪、最後一根是資料日 D、已處理過斷點與 null 收盤（Global Constraints）。

- [ ] **Step 1: 寫會紅的測試**（`price_checks_test.dart`；用小工具函式依收盤序列造 `DailyPriceEntry`）
  1. 強者榜四條件各自邊界：20 日漲幅恰好 15.0% → `ret20` fail、15.01% → pass；近 20 根有一根漲幅 ≥ 9.85% → `limitUpIn20` pass，那根在第 21 根 → fail；20 日均量恰好 3,000,000 → fail；D 收盤等於 20MA → `aboveMa20` fail。
  2. 少於 21 根 → 四條件都是 `insufficient`，`passed` 不計入、`allPassed` false。
  3. `maSideStreak`：最後 3 根收在各自當日 20MA 下 → −3；最後一根剛站上 → 1；最後一根恰好等於 20MA、前兩根在下 → 1；不足 20 根 → 0。
  4. `crossedBelowMa`：前一日等於 20MA、D 在下 → true；兩日都在下 → false。
  5. `structureC`：D 收盤大於前 20 根（不含 D）的最高價 → true；只大於前 20 根最高收盤、不大於最高價 → false。
  6. `structureBSupport`：20 日漲幅 > 0、收在 10MA 上、D 最低 ≤ 5MA × 1.015 且收盤 ≥ 5MA × 0.995 → 5；同時也碰到 10MA 時仍回 5；收盤在 5MA × 0.994 但碰到 10MA → 10；碰到 5MA 支撐但收盤 ≤ 10MA → null；20 日漲幅 ≤ 0 → null。
  7. `checkEntryPrerequisites`：60 日漲幅 0 → `moving` fail；乖離 15.0% → `bias` fail、14.99% → pass，`biasPct` 照算；`revenueYoy3m` null → `revenue` insufficient、30.0 → fail；D 成交 3,000,000 股 → `dayVolume` fail；少於 61 根 → `moving` insufficient。
- [ ] **Step 2: 寫會紅的測試**（`throttle_test.dart`）
  1. D 收盤 < 前 4 日平均 → `flat`；≥ 門檻但 < 含 D 的 20 日平均 → `reduced`；兩者都在上 → `full`。
  2. `lastBreakDate`：第 −10 根與第 −3 根各收破一次 → 第 −3 根那天、`tradingDaysSinceBreak` 3；D 當天收破 → D、0；整段都沒收破 → null，`lookbackTradingDays` 等於筆數 − 4。
  3. 少於 21 筆 → null。
- [ ] **Step 3: 跑兩個測試檔，確認是紅的**（找不到符號）
- [ ] **Step 4: 實作**：均線用 `TechnicalIndicatorService().calculateSMA`；20 日漲幅用 `PriceCalculator.ret20d`、60 日用 `ret60d`；漲停用 `PriceLimit.statusOf(changePercent: PriceCalculator.calculatePriceChange(…)).isUp`。
- [ ] **Step 5: 跑兩個測試檔，確認轉綠**
- [ ] **Step 6: 突變（各拔一次，看到對應測試轉紅後還原）**：四條件的 `>` 改 `>=`（各一次）；`maSideStreak` 等於時算在下方；`structureC` 改比最高收盤；`structureBSupport` 拿掉「收在 10MA 上」；油門判斷順序對調（先看月線）；`lastBreakDate` 改成找最舊的一次。
- [ ] **Step 7: 送審**（實作者不 commit）

---

### Task 2: 籌碼章與對做、持股成本守門價與時間（純函式，不接線）

**Files:**
- Create: `lib/domain/services/close_summary/chip_checks.dart`
- Create: `lib/domain/services/close_summary/holding_checks.dart`
- Modify: `lib/domain/services/alert/alert_target_calculator.dart`（`_atr` 改成公開的 `simpleAtr`；`AlertQuickSet.toOhlc` 的本體搬來成為 `ohlcFrom`）
- Modify: `lib/presentation/screens/stock_detail/widgets/alert_quick_set.dart`（`toOhlc` 留著，改成一行轉呼叫 `AlertTargetCalculator.ohlcFrom`；`alerts_tab.dart` 不用動）
- Test: `test/domain/services/close_summary/chip_checks_test.dart`、`test/domain/services/close_summary/holding_checks_test.dart`、`test/domain/services/alert/alert_target_calculator_test.dart`、`test/presentation/screens/stock_detail/widgets/alert_quick_set_test.dart`（既有的 `toOhlc` 測試經轉呼叫測到 `ohlcFrom`，不另寫重複的）

**Interfaces:**
- Consumes: Task 1 的 `CloseSummaryParams`。
- Produces:

```dart
// alert_target_calculator.dart
static double? simpleAtr(List<Ohlc> bars, int period);          // 原 _atr，行為不變
static List<Ohlc> ohlcFrom(List<DailyPriceEntry> history);      // 原 AlertQuickSet.toOhlc，行為不變

enum ChipParty { foreign, trust }
class ChipCheck {
  final double foreignNetShares, trustNetShares;   // D 當日；D 沒有該股的法人列時為 0
  final int foreignStreak, trustStreak;            // 連買為正、連賣為負，含 D，不設下限
  final ChipParty? sealedBy;                       // 籌碼章成立的一方；兩方都成立取外資
  final bool opposed;                              // 對做
  bool get sealed;
}
/// [institutionalReady] 為 false（該股所屬市場 D 的法人還沒寫入）時回 null。
/// 市場已到但某天沒有該股的法人列＝那天兩方都是 0。
ChipCheck? checkChip({required List<DailyInstitutionalEntry> institutional, required List<DailyPriceEntry> bars, required bool institutionalReady});

/// 目前這段持有（最後一次 BUY／SELL 累計數量歸零之後）第一筆買進的日期；沒有買進回 null。
DateTime? holdingEntryDate(List<PortfolioTransactionEntry> transactions);

enum TimeStopState { running, lifted, expired }
class HoldingCheck {
  final DateTime entryDate;
  final double quantity, avgCost;
  final double? stopPrice, oneR;        // 成本守門價與 1R；進場日之前（含）不足 21 根 → null
  final int tradingDaysHeld;            // 進場日之後到 D 的交易日數（不含進場日；進場當天為 0）
  final TimeStopState? timeStop;        // stopPrice 為 null 時 null
  final double unrealizedPnl, unrealizedPct;
  bool get stopBroken;                  // D 收盤 < stopPrice
}
HoldingCheck? checkHolding({required PortfolioPositionEntry position, required List<PortfolioTransactionEntry> transactions, required List<DailyPriceEntry> bars});
```

- [ ] **Step 1: 寫會紅的測試**（`chip_checks_test.dart`）
  1. 外資最近 3 根價格日每天買超都 ≥ 當天成交量 1%（其中一天恰好 1.00%）→ `sealedBy` foreign；其中一天 0.99% → 不成立。
  2. 3 個價格日裡有一天沒有該股的法人列 → 那天算 0，不成立。
  3. 外資成立，投信在這 3 天某一天賣超 = 外資 3 天買超合計 → `opposed` true；少 1 股 → false；外資自己某天賣超不算對做。
  4. `foreignStreak`／`trustStreak`：連買 4 天 → 4；D 賣超、前 2 天也賣 → −3；不受 1% 下限影響。
  5. `institutionalReady` false → null；true 但 D 沒有該股的列 → `foreignNetShares` 0、不成立。
- [ ] **Step 2: 跑 `chip_checks_test.dart`，確認紅；實作；確認綠**
- [ ] **Step 3: 搬移與改名**：`_atr` → 公開 `simpleAtr`；`AlertQuickSet.toOhlc` 的本體搬到 `AlertTargetCalculator.ohlcFrom`，原方法改成一行轉呼叫（只搬與改名，行為不變）。在 `alert_target_calculator_test.dart` 加一條：`simpleAtr` 固定 21 根、期望值手算到小數第 4 位。
- [ ] **Step 4: 跑 `alert_target_calculator_test.dart` 與 `alert_quick_set_test.dart`，確認綠**
- [ ] **Step 5: 寫會紅的測試**（`holding_checks_test.dart`）
  1. 成本 100、進場日（含）往回 20 根的 TR 平均為 4 → `stopPrice` 92、`oneR` 8；進場後 D 的 ATR 變大，`stopPrice` 不變。
  2. 進場後第 5 個交易日收盤 108（= 成本 + 1R）→ `lifted`；8 天內有一天最高價 109、但收盤最高 107.99，第 8 天 → `expired`；第 7 天 → `running`、`tradingDaysHeld` 7。
  3. 交易：3/1 買、3/5 全賣、3/10 買、3/12 加碼 → `holdingEntryDate` 3/10；`checkHolding` 的 `entryDate` 也是 3/10。
  4. 進場日之前（含）不足 21 根 → `stopPrice`、`oneR`、`timeStop` 為 null，`tradingDaysHeld`、損益照算。
  5. D 收盤 91.99 → `stopBroken` true；92 → false。
  6. 損益：數量 120、成本 525、D 收盤 530 → `unrealizedPnl` 600、`unrealizedPct` ≈ 0.952。
  7. 交易裡只有股利（沒有買進）→ `holdingEntryDate` null、`checkHolding` null。
- [ ] **Step 6: 跑 `holding_checks_test.dart`，確認紅；實作（ATR 用 `AlertTargetCalculator.simpleAtr(ohlcFrom(進場日以前的 bars), AlertParams.stopGateAtrPeriod)`、倍數用 `AlertParams.stopGateAtrMultiple`；交易類型用 `TransactionTypes`）；確認綠**
- [ ] **Step 7: 突變**：1% 下限改 `>`；對做改成看同一方；對做的 `>=` 改 `>`；成本守門價改用 D 的 ATR；+1R 判斷改用最高價；時間天數 8 改 7；進場日改成第一筆買進。
- [ ] **Step 8: 送審**（實作者不 commit）

---

### Task 3: 組裝成摘要（純函式，不接線）

**Files:**
- Create: `lib/domain/models/close_summary.dart`
- Create: `lib/domain/services/close_summary/close_summary_builder.dart`
- Test: `test/domain/services/close_summary/close_summary_builder_test.dart`

**Interfaces:**
- Consumes: Task 1、Task 2 的全部。
- Produces:

```dart
enum SummaryEventKind {
  // 待處理
  stopBroken, timeStopExpired, belowMaStreak, strongListQualified, dualSeal,
  structureB, structureC, triggerDowngrade, sectorCooling,
  // 資訊
  limitUp, limitDown, limitUpForeignSelling;
  bool get isActionable;
}
class SummaryEvent { final SummaryEventKind kind; final int? days; final int? supportPeriod; final String? industry; }
enum GroupRole { strongList, delistReview, thermometer, other }
enum RowDataStatus { ok, marketPending, noTrade } // 市場 D 未寫入／同市場有資料但這檔 D 沒有成交
class CloseSummaryRow {
  final String symbol, name, market;
  final int? groupId;
  final String? groupName;
  final GroupRole role;
  final RowDataStatus status;          // 非 ok 時以下數值全為 null、events 空
  final double? close, changePct, volumeShares, biasPct;
  final StrongListCheck? strongList;
  final EntryPrerequisites? prerequisites;
  final ChipCheck? chip;               // null：該市場法人未到
  final HoldingCheck? holding;
  final int? thermometerStreak;        // 只有溫度計列有（maSideStreak）
  final List<SummaryEvent> events;     // 待處理在前
  bool get hasActionable;
}
class CloseSummarySection { final bool isHoldings; final int? groupId; final String? groupName; final List<CloseSummaryRow> rows; } // groupId null＋!isHoldings＝未分組
class CloseSummary {
  final DateTime dataDate;
  final Set<String> pricePendingMarkets, institutionalPendingMarkets; // MarketCode
  final bool indexReady;               // 加權指數最後一筆是 D
  final ThrottleReading? throttle;     // indexReady 為 false 時 null
  // expected＝TaiwanCalendar.expectedLatestTradingDataDate(now)；兩者互斥
  final bool awaitingToday;            // 今天是交易日、now.hour < DataFreshness.dailyDataReadyHour、D 與 expected 同一天
  final bool dataBehind;               // D 早於 expected
  final bool strongListGroupMissing;
  final List<CloseSummarySection> sections;
  int get holdingCount;
  int get actionableStockCount;        // 有待處理事件的不重複檔數
}
class CloseSummaryInput {
  final DateTime dataDate, now;        // now：台灣時間（AppClock 的 SystemClock 回傳 TaiwanTime.now()）
  final Map<String, bool> priceReadyByMarket, institutionalReadyByMarket; // MarketCode → D 是否有列
  final List<MarketIndexEntry> taiex;
  final List<WatchlistWithGroup> watchlist;
  final List<WatchlistGroupEntry> groups;
  final List<PortfolioPositionEntry> positions;
  final Map<String, List<PortfolioTransactionEntry>> transactions;
  final Map<String, StockMasterEntry> stocks;
  final Map<String, List<DailyPriceEntry>> prices;          // 原始，未處理斷點
  final Map<String, List<DailyInstitutionalEntry>> institutional;
  final Map<String, List<MonthlyRevenueEntry>> revenues;
}
CloseSummary buildCloseSummary(CloseSummaryInput input);
```

規則（設計文件「分組在 v3 裡的意義」「事件分兩類」「v3 條件的計算」的落地）：
- 角色：分組名稱等於 `CloseSummaryParams` 的三個名稱之一就是該角色，其餘（含未分組、不在自選的持股）是 `other`。`strongListGroupMissing`＝分組表裡沒有名稱為「強者榜」的分組；此時所有列都不標「符合強者榜入選條件」。
- 列的資料狀態：該股市場（`stock_master.market`）的 `priceReadyByMarket` 為 false → `marketPending`；市場已到但這檔最後一根不是 D → `noTrade`。
- 哪些事件適用：`strongList`→連 N 日收破月線（`maSideStreak ≤ −2`，N＝其絕對值）、結構 B／C、觸發日降級、雙章齊、族群退燒；`delistReview`→符合強者榜入選條件、族群退燒；`other`→符合強者榜入選條件、結構 B／C、觸發日降級、雙章齊、族群退燒；`thermometer`→不標價格與籌碼事件，只填 `thermometerStreak`。持股不論角色另加成本守門價（`stopBroken`）與時間到期（`timeStop == expired`）。資訊事件除了溫度計都標。
- 觸發日降級：結構 B 或 C 成立且 D 漲跌幅 ≤ −5% → 標降級、不標該結構，也不算價格章。雙章齊＝價格章＋`chip.sealed`＋`!chip.opposed`＋前提條件全過。
- 族群退燒：只看在自選裡、非溫度計、`status == ok` 的列；`industry` 為 null 的略過；`IndustryNames.normalize(industry)` 相同且 `crossedBelowMa` 為 true 的有 ≥ 2 檔 → 這幾檔都標，`industry` 填正規化後的名稱。
- 漲停但外資賣超：漲停且 `chip.foreignNetShares < 0`。
- 年增 3 月均：`yoy3mAvg`（`revenue_stats.dart`）。
- 區段：持股（`positions` 數量 > 0）在最前；其餘照 `groups` 的順序以 `groupId` 分段，未分組最後；空區段不出現；持股列不在分組區段重複，但角色仍照它的分組。段內：`hasActionable` 在前，再依 `changePct` 由高到低（null 最後），再依代號。

- [ ] **Step 1: 寫會紅的測試**
  1. 區段順序：持股、強者榜、備取觀察、未分組；同時是持股與強者榜的股票只在持股段，但角色仍是 `strongList`（會標連 N 日收破月線）；兩個同名分組各自成段。
  2. 段內排序：有待處理的在前；同為無事件時漲幅高的在前；漲幅 null 在最後。
  3. 角色與事件：除名重審的股票結構 C 成立 → 不標；4/4 → 標符合強者榜入選條件；強者榜的股票 4/4 → 不標入選條件；溫度計 → 沒有價格與籌碼事件、`thermometerStreak` 有值；溫度計同時是持股且收破成本守門價 → 只有 `stopBroken`。
  4. 分組表沒有「強者榜」（原本那組改名）→ `strongListGroupMissing` true；改名那組裡 4/4 的股票不標符合強者榜入選條件；其他事件（結構、雙章齊）照常。
  5. 族群退燒：同產業 2 檔自選同日跌破月線 → 兩檔都標；只有 1 檔 → 不標；其中一檔是溫度計、或只是持股不在自選、或 `noTrade` → 不計入；`industry` null → 略過不丟例外。
  6. 上櫃 `priceReadyByMarket` false → 上櫃股票 `marketPending`；上市有資料、某檔最後一根是 D−1 → `noTrade`；兩者 `events` 空、不計入 `actionableStockCount`。
  7. 某檔只有 15 根 → 強者榜四條件 `insufficient`、不標入選條件與結構。
  8. 上櫃 `institutionalReadyByMarket` false → `institutionalPendingMarkets` 含上櫃、上櫃股票 `chip` null、雙章齊不標，其餘事件照標；上市股票照常判。
  9. 觸發日降級（用結構 B）：碰 5MA 支撐、漲跌 −5.0% → 只有降級；−4.99% → 結構 B（5 日線）。
  10. `actionableStockCount` 只算待處理，漲停（資訊）不算；`holdingCount` 等於持股數。
  11. 加權最後一筆是 D−1 → `indexReady` false、`throttle` null。
  12. `awaitingToday`／`dataBehind`：週三 14:00、D 是週二 → `awaitingToday` true、`dataBehind` false；週三 17:00、D 是週二 → `dataBehind` true；週三 14:00、D 是週一 → `dataBehind` true、`awaitingToday` false；週六、D 是週五 → 兩者 false。
- [ ] **Step 2: 跑測試檔，確認紅**
- [ ] **Step 3: 實作**（斷點與 null 收盤照 Global Constraints 先處理）
- [ ] **Step 4: 跑測試檔，確認綠**
- [ ] **Step 5: 突變**：持股列也放進分組段；排序拿掉 `hasActionable`；除名重審也標結構；`strongListGroupMissing` 時仍標入選條件；族群退燒門檻 2 改 1；降級後仍標結構；`actionableStockCount` 算進資訊事件；`marketPending` 改判成 `noTrade`。
- [ ] **Step 6: 送審**（實作者不 commit）

---

### Task 4: 從資料庫讀輸入、provider

**Files:**
- Create: `lib/domain/services/close_summary/close_summary_loader.dart`
- Create: `lib/presentation/providers/close_summary_provider.dart`
- Modify: `lib/data/database/dao/institutional_dao.dart`（加一個依市場計數的查詢；價格沿用既有的 `countPricesByDateAndMarket`）
- Test: `test/domain/services/close_summary/close_summary_loader_test.dart`、`test/presentation/providers/close_summary_provider_test.dart`、法人 DAO 的測試檔

**Interfaces:**
- Consumes: Task 2 的 `holdingEntryDate`、Task 3 的 `CloseSummaryInput`、`buildCloseSummary`。
- Produces:

```dart
// institutional_dao.dart：D 當天該市場（join stock_master.market）的法人列數，寫法對照 price_dao 的 countPricesByDateAndMarket
Future<int> countInstitutionalByDateAndMarket(DateTime date, String market);

/// [asOf] 給定時以它為資料日（量測用）；否則用 getLatestDataDate()。資料庫沒有任何價格回 null。
Future<CloseSummaryInput?> loadCloseSummaryInput(AppDatabase db, {required DateTime now, DateTime? asOf});
final closeSummaryProvider = FutureProvider.autoDispose<CloseSummary?>(...);
```

- 讀法：自選 `getWatchlistWithGroups`、分組 `getWatchlistGroups`、持股 `getPortfolioPositions`、各持股 `getTransactionsForSymbol`、主檔 `getStocksBatch`、法人 `getInstitutionalHistoryBatch`、營收 `getRecentMonthlyRevenueBatch(months: 6)`、加權 `getIndexHistoryBatch([MarketIndexNames.taiex], days: priceLookbackCalendarDays, now: D)`。
- 價格 `getPriceHistoryBatch`：`endDate`＝D；`startDate`＝D − `priceLookbackCalendarDays` 天與（最早的持股進場日 − `holdingAtrLeadCalendarDays` 天）取較早者。法人同一區間。
- `priceReadyByMarket`／`institutionalReadyByMarket`：對 `MarketCode.twse`、`MarketCode.tpex` 各看 D 當天的計數 > 0（`countPricesByDateAndMarket`、`countInstitutionalByDateAndMarket`；與 `asOf` 同一天，不用全表最新日）。上市法人約 16:00 才發布，15:30 那輪之後常只有上櫃法人，所以要分市場。
- 營收不依 D 過濾：`monthly_revenue.date` 是營收月份、不是公布日，資料庫裡的列在讀取當下都已公布。指定 `asOf` 量過去的日子時會用到之後才公布的營收，只影響量測，記在 loader 的說明。
- provider：
  - `ref.watch(dataUpdateEpochProvider)`（專案「資料已寫入新一輪」的慣例）與 `ref.watch(todayProvider.select((s) => (s.dataDate, s.lastUpdate)))`（法人晚到時 `dataDate` 會變）。
  - 對 `watchlist`、`watchlistGroups`、`portfolioPosition` 三張表的 `db.tableUpdates(...)` 訂閱，有寫入就 `ref.invalidateSelf()`，`ref.onDispose` 取消訂閱：入口卡所在的今日頁一直掛著，移組、記交易後要立刻反映。價格與法人表不訂閱（更新途中逐批寫入會一直重算）。這個取捨寫在 provider 的註解。
  - 讀 `databaseProvider`、`appClockProvider`。

- [ ] **Step 1: 寫會紅的測試**（`AppDatabase.forTesting()` 寫入資料再讀）
  1. 指定 `asOf` 為 D−1：價格、法人、指數都不含 D 的列，`dataDate` 是 D−1。
  2. 法人有 D−1 與 D、`asOf` = D−1 → 上市 `institutionalReadyByMarket` true；上櫃價格有 D、法人只有 D−1（不指定 asOf）→ 上櫃 false、上市 true。
  3. 持股進場在 D−200 天 → 讀到的價格涵蓋進場日之前 21 根，`buildCloseSummary` 的該列 `holding.stopPrice` 不是 null。
  4. 資料庫沒有任何價格 → null；有價格但沒有自選與持股 → 有輸入、清單都空。
  5. `countInstitutionalByDateAndMarket`：上市 2 檔、上櫃 1 檔有 D 的法人列 → TWSE 2、TPEx 1；D−1 的列不算；某市場沒有 → 0。
  6. provider：`dataUpdateEpochProvider` bump 後重算；改某檔的分組（寫 `watchlist`）後重算（讀到第二份結果）。
- [ ] **Step 2: 跑測試檔，確認紅；實作；確認綠**
- [ ] **Step 3: 突變**：`endDate` 拿掉；市場是否就緒改成「全表有任何列」；價格起點不看持股進場日；provider 不訂閱 `watchlist` 的寫入。
- [ ] **Step 4: 送審**（實作者不 commit）

---

### Task 5: 摘要頁、路由、翻譯

**Files:**
- Create: `lib/presentation/screens/close_summary/close_summary_screen.dart`
- Create: `lib/presentation/screens/close_summary/close_summary_row_tile.dart`
- Modify: `lib/core/constants/app_routes.dart`（`static const closeSummary = '/close-summary';`）、`lib/app/router.dart`（Shell 外的全螢幕路由，`name: 'closeSummary'`）
- Modify: `assets/translations/zh-TW.json`、`assets/translations/en.json`（`closeSummary.*`）
- Test: `test/presentation/screens/close_summary/close_summary_screen_test.dart`

**Interfaces:**
- Consumes: Task 4 的 `closeSummaryProvider`、Task 3 的模型。
- Produces: `CloseSummaryScreen`（`const`）、`AppRoutes.closeSummary`。

畫面（照設計「頁面」一節的草圖，用語照 Global Constraints）：
- 頁首：「{日期}（{星期}）收盤」；法人：已到／{市場}未到；價格有市場未到時一行「{市場}行情未到」；`awaitingToday` 一行「今天的資料 15:30 更新後才有」；`dataBehind` 一行「資料落後：最新是 {日期}」；油門一行（全開／小量／空手＋加權收盤、月線、5 日門檻與上下），`indexReady` false 時寫「加權指數未到」；最近一次收破 5 日門檻「{日期}（{n} 個交易日前）」，沒有時「近 {N} 個交易日內沒有」；`strongListGroupMissing` 一行「找不到『強者榜』分組，強者榜相關事件不標」；「大盤總覽 →」連到 `AppRoutes.market`。
- 每一列：名稱、代號、收盤、漲跌幅（紅綠照 `PriceColors`）、成交量（張）；外資與投信當日張數與連買／連賣天數（`chip` null 時寫「法人未到」）；「強者榜條件 n/4」後面直接列未通過的條件名稱，`insufficient` 的寫「資料不足」；乖離；籌碼章 ✓（外資／投信連 N）與「對做 → 暫緩」；未過的前提條件；事件以 chip 列出，待處理與資訊用不同樣式（都不用紅綠）。持股另一行：成本、股數、損益（元、%）、成本守門價與距離（null 時「資料不足」）、「持有第 n 天／共 8 天」（0 天寫「今天建立」）或「已達 +1R」。溫度計列：「月線之上第 n 天」／「月線之下第 n 天」。`marketPending` 只寫「行情未到」、`noTrade` 只寫「資料日沒有成交」。點列 `context.push(AppRoutes.stockDetail(symbol))`。
- 下拉重新整理：`ref.invalidate(closeSummaryProvider)`。provider 回 null：空狀態「還沒有價格資料」；沒有任何列：空狀態「還沒有自選或持股」。
- 事件文字（zh-TW 照寫）：收破成本守門價、8 日未達 +1R、連 {n} 日收破月線、符合強者榜入選條件、雙章齊（次日條件另看）、結構 B 回測 {n} 日線、結構 C 突破（突破當天）、觸發日收跌逾 5%，降級、族群退燒：{industry}、漲停、跌停、漲停但外資賣超。en 版由實作者照意思寫，照 Global Constraints 的 regex 全部避開。

- [ ] **Step 1: 寫會紅的 widget 測試**（`buildProviderTestApp(..., zhTranslations: true)`，override `closeSummaryProvider` 給固定的 `CloseSummary`）
  1. 頁首：油門「小量」、最近一次收破門檻的日期與交易日數；上櫃法人未到時看到「上櫃未到」；`indexReady` false 時看到「加權指數未到」、沒有油門狀態字。
  2. 區段標題依序出現：持股、強者榜、未分組。
  3. 事件文字照上面的 zh-TW；`belowMaStreak` days 3 → 「連 3 日收破月線」；`insufficient` 的條件顯示「資料不足」。
  4. `strongListGroupMissing` → 頁首那一行出現。
  5. 點某列 → 路由到該股詳情（`router.state.matchedLocation`）。
  6. provider 回 null 與沒有列 → 各自的空狀態文字；不丟例外。
  7. 英文翻譯載入（`enTranslations: true`）時同一份資料 390 寬不溢位。
- [ ] **Step 2: 跑測試檔，確認紅；實作；確認綠**
- [ ] **Step 3: 跑 `test/core/l10n/no_investment_advice_copy_test.dart`，確認綠**（新加的翻譯沒有禁用字）
- [ ] **Step 4: 突變**：區段不照順序；事件 chip 不分待處理／資訊樣式（用測試能分辨的 key）；點列不導頁；在 `closeSummary.` 某個值裡寫回「停損」（第 3 步的守門要紅）。
- [ ] **Step 5: 送審**（實作者不 commit）

---

### Task 6: 今日頁入口卡、量測、文件、收尾

**Files:**
- Create: `lib/presentation/screens/today/widgets/close_summary_entry_card.dart`
- Modify: `lib/presentation/screens/today/today_screen.dart`（大盤摘要條那個 `SliverToBoxAdapter` 之後加一個）
- Modify: 兩份翻譯檔、`CHANGELOG.md`、本計畫（檔尾「實作後的修正」）
- Test: `test/presentation/screens/today/widgets/close_summary_entry_card_test.dart`、`test/presentation/screens/today/today_screen_test.dart`、`test/presentation/screens/golden/today_screen_golden_test.dart`

**Interfaces:**
- Consumes: `closeSummaryProvider`、`AppRoutes.closeSummary`。
- Produces: `CloseSummaryEntryCard`。

- [ ] **Step 1: 寫會紅的測試**
  1. 有資料：「收盤摘要・{日期}・持股 {h} 檔・事件 {n} 檔 →」，`n`＝`actionableStockCount`；點卡 → `AppRoutes.closeSummary`。
  2. 第一次載入中與錯誤時整張不顯示（與族群排名同一做法，不擋今日頁主線）；已有資料、依賴改變重算時沿用上一次的內容，不閃（`AsyncValue.when` 要設 `skipLoadingOnReload: true`：`dataUpdateEpochProvider`／`todayProvider` 引起的重算屬於 reload，預設會顯示 loading）。
  3. provider 回 null 或沒有任何列 → 卡片不顯示。
  4. `today_screen_test`：入口卡在大盤摘要條之後、釘選論點之前。既有的 `today_screen_test.dart` 與 `today_screen_golden_test.dart` 預設 override `closeSummaryProvider` 回 null，不讓既有測試去讀共用的 in-memory DB；golden 圖不變。
- [ ] **Step 2: 跑測試，確認紅；實作；確認綠**
- [ ] **Step 3: 量測每天的待處理檔數（設計要求，上線前）**
  - 先複製一份資料庫，不直接開正式檔（`AppDatabase` 開檔時 `beforeOpen` 會寫入，schema 不符時還會重建表）：`sqlite3 "file:$HOME/Library/Containers/com.neo.afterclose/Data/Documents/afterclose.sqlite?mode=ro" "VACUUM INTO '<scratchpad>/close_summary_measure.sqlite'"`。
  - 在 scratchpad 寫一支不提交的測試，用 `AppDatabase.forToolFile` 開副本，對 2026-11-10 起每個交易日呼叫 `loadCloseSummaryInput(db, now: D 的 17:00, asOf: D)` 與 `buildCloseSummary`，印出每天的列數、`actionableStockCount`、各事件種類的檔數。
  - 任一天待處理檔數超過列數的三分之一 → 停下，把數字交給使用者決定是否調整分類，不往下做。結果寫進本計畫檔尾。用完刪掉副本。
- [ ] **Step 4: 文件**：`CHANGELOG.md` 的 Unreleased › Added 加一條（收盤摘要：持股與自選股照交易決策表的條件標出狀態與事件，今日頁有入口；用語避開禁用字）；本計畫檔尾加「實作後的修正」（與計畫或設計不同的地方、延後的小問題、突變結果、Step 3 的量測）；實作中再有與設計不同的地方，設計文件同步改。
- [ ] **Step 5: 驗證**

  Run: `flutter analyze` → `No issues found!`

  Run: `flutter test` → `All tests passed!`

  Run: `scripts/test_time_shift.sh 90 <Task 1～6 新增與改到的測試檔>` → 全部通過

  Run: `flutter test --tags golden test/presentation/screens/golden/today_screen_golden_test.dart` → 通過

  Run: `dart compile kernel tool/daily_update.dart -o build/daily_update.dill` → 編譯成功（改到 `lib/domain`、`alert_target_calculator.dart` 與 DAO，確認 update 鏈仍是純 Dart）

- [ ] **Step 6: 送審**（整個變更的最後審查；實作者不 commit）
- [ ] **Step 7: 使用者說「提交」後提交**（`feat:`；設計文件與本計畫一併提交）
- [ ] **Step 8: 實機**（下一個交易日 15:30 更新之後，debug 版）：今日頁入口卡的數字與摘要頁一致；油門、持股（使用者已記的那筆）、強者榜各段與手動核對一兩檔；15:30 之前打開時頁首有「今天的資料 15:30 更新後才有」；移一檔到別的分組後入口卡數字立刻變。結果寫進本計畫檔尾。

## 實作後的修正（2026-11-20）

### 與計畫或設計寫法不同的地方

| 地方 | 改成 | 理由 |
|:--|:--|:--|
| 油門的 `lookbackTradingDays` | 筆數 − 4 | 前 4 筆沒有 5 日門檻可比，「近 N 個交易日內沒有收破」的 N 要是真的查過的天數 |
| `HoldingCheck` | 多 `closePrice`；`tradingDaysHeld` 改 `int?` | 判斷收破要比資料日收盤；進場日早於讀到的第一根時數不出天數，寧可不寫 |
| 進場日晚於資料日 | 成本守門價、1R、時間為 null，天數 0 | 盤中記了買進、盤後資料還沒寫入時，不先用前一天的 ATR |
| 持股進場日 | 買進、賣出累計到 0 以下當 0 | 股票股利配來的股數可以一起賣掉，賣出可能超過買進合計 |
| 溫度計 | 多 `thermometerStreakAtLeast`，畫面寫「至少 N 天」 | 連續天數數到讀到的頭時，實際可能更多 |
| 組裝的日線前處理 | 先去掉資料日以後的日線，再切斷點 | 資料日之後的跳空不該切掉資料日以前的資料 |
| 市場就緒 | 價格與法人都用整日範圍計數（新增 `countInstitutionalInDayAndMarket`） | 防禦帶時間分量的日期；本機實測三張表 0 筆變體 |
| 讀取區間 | 只有進場早於 130 天回看起點的持股另外往前讀價格，法人一律 130 天 | 一筆舊持股原本會把全部自選一起拉長（審查實測 51 ms → 295 ms） |
| provider 的重算 | 拿掉 `todayProvider.select` 觸發 | App 內更新、逾時遲到回傳、回前景資料變了都會 bump 更新世代；多出來的只有 App 外更新跑到一半時讀到半套資料 |
| 頁首資料時間 | 抽成 `closeSummaryTimeFlags`，畫面每次 build 用當下時鐘重算 | 入口卡讓 provider 一直活著，摘要可能是早上算的；過了 16:00 沒更新時要改寫「資料落後」 |
| 頁首日期 | 只寫「11/19 收盤」，不寫星期 | App 其他畫面沒有星期格式，intl 星期名稱要另外初始化語系資料 |
| 溫度計列、除名重審列 | 溫度計不寫強者榜條件與前提條件；除名重審不寫前提條件 | 兩組都不看進場這一側 |
| 用語 | 「今天建立」改「建立當天」；不到半張的買賣超留一位小數；連 2 天以上才寫連買連賣；超過 8 天只寫「持有第 n 天」 | 隔天早上看時「今天」會錯；避免「±0 張」；與法人排行頁一致 |
| 計畫 Task 3 第 9 條 | 降級用碰 10 日線的結構 B 測 | 跌 5% 那天收盤很難守住 5 日線 |
| 漲跌停（Global Constraints 寫 `PriceLimit.statusOf(changePercent: …)`） | 以平盤價依升降單位算出漲跌停價再比對收盤（新增 `TwPriceTick`）；算不出平盤價或 ETF 時退回漲跌幅推算 | 最後審查實測：自選 59 檔 8/1 以後收在漲停價的 193 個日子，用 ±9.85% 推算漏掉 44 個（約 23%），40 個「檔 × 日」的強者榜條件因此少一條 |
| 進摘要頁 | 摘要已經算好時（入口卡讓它一直活著）進頁重算一次 | launchd 在 App 外寫入的每日更新不會通知 App，頁首會寫出錯的狀態 |
| `CloseSummary` | 拿掉 `awaitingToday`／`dataBehind`，頁首只用 `closeSummaryTimeFlags` | 畫面一律用當下時鐘重算，模型裡的值沒人讀，留著是兩個來源 |
| 找不到強者榜的提示 | 一個分組都沒有時不提示 | 從沒建過分組的人看了像錯誤 |

### 審查與突變

六段各送 opus 審查，每段修到沒有 Critical／Important 為止；整體最後審查 0 Critical／2 Important（漲跌停推算漏判、App 外更新後沿用舊結果）／6 Minor，都已修或寫進下方已知限制。突變共跑 136 個（不重複計算），第一輪存活的都補了測試後轉紅；唯一證實多餘的是摘要頁一度加上的 `AlwaysScrollableScrollPhysics`（主要捲動清單預設就能下拉，當時測試是拉的距離不夠），已拿掉。

### 上線前量測（Task 6 Step 3）

本機資料庫唯讀複製一份，對 11/10～11/20 每個交易日以資料日 17:00 計算（最後審查改用升降單位算漲跌停價後重量；待處理檔數不變，資訊類的漲跌停檔數變多）：

| 日 | 列數 | 待處理檔數 | 油門 | 備註 |
|:--|--:|--:|:--|:--|
| 11/10 | 59 | 8 | 小量 | |
| 11/11 | 59 | 9 | 小量 | |
| 11/12 | 59 | 9 | 小量 | |
| 11/13 | 59 | 9 | 小量 | |
| 11/16 | 59 | 9 | 空手 | 跌停 30 檔（資訊）、族群退燒 3 檔 |
| 11/17 | 59 | 7 | 空手 | |
| 11/18 | 59 | 5 | 空手 | |
| 11/19 | 59 | 4 | 空手 | |
| 11/20 | 59 | 4 | 空手 | 上市法人未到（16:00 才公布，15:30 那輪沒有） |

每天待處理 4～9 檔，遠低於列數的三分之一（約 20 檔），分類不用調整。強者榜 4 檔每天都標「連 N 日收破月線」：分組還是 7/29 的狀態，使用者移組前會一直標。第一次計算約 0.75 秒（冷啟動），之後約 45 毫秒。量測時還沒有持股紀錄，持股那一側要等實機。

### 延後的小問題

- 摘要頁一直開著時：跨過 16:00 不會自動重畫頁首；launchd 在 App 外寫入每日更新也不會反映。進頁時會重算，頁面開著期間要下拉。
- 買賣超不到 50 股時一位小數仍是 0，會寫成「0.0 張」（11/10 以後全市場 16,686 列裡外資 12 列、投信 1 列）。英文「1 lots」的單複數。
- 很長的股名會連代號一起被截掉（實際股名短）。
- `heat_analysis_tab.dart` 的下拉重新整理也沒有接住重讀失敗的例外（範圍外）。
- 分組以名稱完全比對：只有「強者榜」找不到時會在頁首提示；「除名重審」或「大盤溫度計」改名後，那些股票會變成一般角色，開始標結構與雙章齊、算進入口卡的數字。
- 正式環境的 Riverpod 會自動重試失敗的 provider（最多約 38 秒）：摘要讀取失敗時，錯誤頁要等重試用完才出現，這段時間沿用舊內容或顯示載入中。這是全 App 的既有行為。
- 某市場的全市場行情失敗、改逐檔補寫資料日的少數股票時，那個市場會被判成「已到」，其他股票寫「資料日沒有成交」而不是「行情未到」（沒有追到這條路徑會不會在資料日當天發生）。

