# 盤中即時報價第 3 段：大盤與投資組合 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 今日頁大盤列與大盤總覽頁的加權、櫃買指數，以及投資組合（含持股詳情）的現價、市值、未實現損益、總計，在盤中顯示即時報價，並新增「今日損益（以昨收計）」。判讀文字、績效卡、配置圓餅、股利分析維持盤後並標資料日期。

**Architecture:**
- **指數**：`marketIndexLivePriceProvider(market)` 依合併規則算出要顯示的點數，`marketLiveIndicesProvider` 組成給畫面用的 `MarketLiveIndices`。
  - 大盤列（`MarketSummaryStrip`）與 Hero 卡（`HeroIndexSection`，經 `MarketDashboard`）只接收算好的值，不依賴 Riverpod。
  - 判讀文字照舊讀 `MarketOverviewState`（`_indexChangePercent` 不改），所以不會拿今天的漲跌配昨天的家數。
- **投資組合**：
  - 持股資料補回價格日期與交易所漲跌價差（目前在 provider 裡被丟掉）。
  - `portfolioLivePriceProvider(symbol)` 是每檔的合併結果。`portfolioLiveProvider` 用「現價換成合併後價格」的持股，走原本的 `PortfolioSummary` 算總計，並算出今日損益與頁首狀態。
  - `PortfolioState` 本身不變，績效、圓餅、股利照舊用盤後價格。
- **今日損益**：domain 純函式 `TodayPnlRule.compute`。
- **跟時間有關的判斷**：登記的「是否已有今天正式資料」與合併結果都 watch 第 2 段的 `liveQuoteBoundaryProvider`，跨過午夜、開盤、收盤時重算。

**Tech Stack:** Flutter／Dart 3.10、flutter_riverpod 3（riverpod 3.3.2）、go_router 17.1.0、easy_localization、mocktail、flutter_test

**Spec:** `docs/plans/2026-10-05-intraday-live-quotes-design.md`（75f215fb）。本計畫實作以下部分：
- §5 合併規則的指數與投資組合部分；
- §7 表格的「今日頁大盤列、大盤總覽頁的指數」「投資組合與持股詳情」兩列；
- 「今日損益（以昨收計）」；
- 「驗證」第 6 項中屬於大盤與投資組合的部分。

第 1 段 aeccdba4、第 2 段 e989da85 已提交。第 2 段計畫 `docs/plans/2026-10-06-intraday-live-quotes-2-plan.md` 末尾「實作後的修正」記錄了審查後的修正，本段沿用：
- 格狀卡片與換股以代號為 key，避免重播閃色；
- 「夠新」看畫面自己離開多久；
- 邊界 provider。

## Global Constraints

- **判讀文字一律用盤後的指數漲跌幅**（spec §7）。綜合判讀、成交量、廣度、籌碼槓桿的輸入不得混入即時指數；`heroIndexOf`、`_indexChangePercent`、`_marginIndexChangePercent` 不改。
- **上市情緒、漲跌家數維持前一交易日並標日期**。績效卡、配置圓餅、產業配置、股利分析維持盤後並標資料日期。
- **同一個數字只有一個來源**：
  - 大盤列與 Hero 卡讀同一個 `marketLiveIndicesProvider`；
  - 持股列、總覽、持股詳情讀同一個 `portfolioLivePriceProvider`。
- **只有現價閃色**（持股列、持股詳情的現價，Hero 卡的指數點數）。總計、損益不閃。
- **今日損益**：
  - 不把缺價的持股當 0，也不默默略過：顯示已計入的合計並標「N 檔無報價未計入」。
  - 收盤後有持股用的是非收盤報價時，標「含未收盤報價」。
  - 非交易日、盤前不顯示。
  - 用正式資料時，昨收＝收盤 − 交易所漲跌價差（除權息日即為參考價）；價差缺時退回前一交易日收盤。
- **掃描、今日訊號的 `StockCard` 不登記、不讀即時報價**。今日頁只登記兩個指數。
- **不寫資料庫、不動 live DB。**
- **色彩**：
  - 漲跌色只用 `PriceColors`／`AppTheme`（`presentation_color_discipline_test`）；
  - 閃色底色、灰字都要有對比度測試：兩種主題，用實際渲染的顏色與實際底色。
- **文案**：
  - 新字串 zh-TW、en 都要有（`app_strings_keys_test`）；
  - 不得出現 `no_investment_advice_copy_test` 的禁用詞；
  - 日期、數量用具名參數。
- **測試裡的報價中心**：`buildProviderTestApp` 預設是 `InertLiveQuoteCenter`；需要即時資料時傳 `liveQuoteCenter:`，時間 override `appClockProvider`。
- **golden**：本段不應改變任何 golden（惰性報價中心沒有即時資料時畫面不變）。任何 golden 有差異都是回歸：不重產，先查原因。CI 排除 golden tag，只在本機跑。
- **提交**：
  - commit／push 只在使用者說「提交」時做。直接在 main，Conventional Commits、中文、純文字、不加 Co-Authored-By。
  - 每個 task 結尾「記錄進度」，整段在 Task 9 一次提交。
  - 不在 09:00–13:30 提交。
- **測試行程**：跑 `flutter test` 前確認沒有其他 `dart run`／`flutter test`／`flutter run`。IDEA 的 analysis server 不算。
- **mutation**：
  - 在 scratchpad 的 repo 副本做，還原用備份檔、不用 git checkout。
  - 先確認副本基線全綠；先跑直接測試，存活者再跑全部消費者測試。
- **審查者**：不可 `dart run`、不可開背景任務、不可碰 scratchpad、不改檔。
- **heredoc**：插入程式碼的 Python／shell 腳本一律用加引號的 heredoc（`<<'PY'`）。不加引號時，反引號會被當成指令執行，靜默吃掉文字。

## Review Focus

1. **盤中指數大漲、但前一交易日漲跌家數偏空**。
   - 預期：Hero 卡與大盤列顯示今天的點數；綜合判讀、量價、廣度的句子與沒有即時時完全相同（用盤後漲跌幅），不出現「今天大漲配昨天家數」的因果顛倒。
   - 測試在 Task 3。
2. **投資組合有一檔暫停交易或一直沒報價**。
   - 預期：今日損益只計入有今天價格的持股，並標「1 檔無報價未計入」；總市值仍用該檔原本的資料，不當 0。
   - 測試在 Task 5、Task 6。
3. **除權息日、盤後資料寫入後**。
   - 預期：今日損益用「收盤 − 漲跌價差」當昨收，不憑空少掉股利。上櫃單檔走 FinMind 寫入、沒有價差時，用前一筆收盤。
   - 測試在 Task 4、Task 5。
4. **盤中打開投資組合**。
   - 預期：總覽的總市值、總損益用即時價；配置圓餅、績效卡、股利分析數字不變（盤後）並標資料日期。
   - 測試在 Task 7。
5. **指數用的是備援值（非即時）**。
   - 預期：備援值即使日期是今天，也不算正式資料。有即時就顯示即時、不掛「非即時」；沒有即時才維持「非即時(M/D)」。大盤列與 Hero 卡數字相同。
   - 測試在 Task 1、Task 2。

## 與 spec 的差異（核可計畫時一併確認）

1. **大盤列的指數不閃色，只有 Hero 卡的點數閃**。大盤列每組是一段 `Text.rich`，閃色元件包不進文字片段；硬拆會破壞「標籤不和數值拆行」的版面。
2. **大盤列的報價狀態接在指數那一行最後**（例：「報價時間 10:15:30」）。上市情緒、漲跌家數只在有指數用即時報價時標日期（例：「(10/2)」）；兩個指數都是正式資料時不標，維持現狀。
3. **Hero 卡各自顯示自己指數的報價狀態**（點數下方一行小字）。
4. **投資組合的盤後卡片標日期，用一行說明**：放在總覽卡下方，寫「績效、配置與股利以 10/2 收盤計」，不在四張卡各加一個標籤。
5. **投資組合的報價狀態放在「持倉」標題列**（同自選頁首的寫法），持股列只標例外（報價暫停、無報價、最後報價）。
6. **持股列的現價文字改用一般文字色**（原本是外框灰）。現價閃色時要疊在紅綠底上，灰字對比度可能不足 4.5。
7. **價差缺時的「前一交易日收盤」取資料庫裡該檔的前一筆**。中間缺資料時會比前一交易日更早，這是資料庫能給的最接近值。
8. **今日損益在收盤後一直顯示到午夜**。spec 只寫「非交易日或盤前不顯示」，收盤後顯示以收盤價算的今日損益。
9. **大盤總覽頁每一輪報價（約 15 秒）重建整個儀表板**。`MarketDashboard` 不依賴 Riverpod，要讓 Hero 卡單獨重建，得改它和既有測試的架構。15 秒一次的重建成本可接受，以後有效能問題再拆。

## 檔案結構

| 檔案 | 責任 | 動作 |
|:--|:--|:--|
| `lib/core/constants/live_quote_params.dart` | 參數 | `indexSymbolOf(market)` |
| `lib/presentation/providers/market_index_live_provider.dart` | 指數的合併結果、顯示用資料、登記清單 | 新增 |
| `lib/presentation/screens/today/widgets/market_summary_strip.dart`、`lib/presentation/screens/today/today_screen.dart` | 今日頁大盤列 | 即時點數、狀態、日期標示、登記 |
| `lib/presentation/widgets/market_dashboard/hero_index_section.dart`、`market_dashboard.dart`、`lib/presentation/screens/market/market_overview_screen.dart` | 大盤總覽頁 | Hero 即時、閃色、狀態、登記 |
| `lib/presentation/providers/portfolio_provider.dart` | 持股資料 | 價格日期、漲跌價差、`copyWithPrice`、`positionOf`、`priceDate` |
| `lib/domain/services/live_quote/today_pnl.dart` | 今日損益規則 | 新增 |
| `lib/presentation/providers/portfolio_live_provider.dart` | 持股的合併結果、即時總覽、登記清單 | 新增 |
| `lib/presentation/screens/portfolio/portfolio_tab.dart`、`widgets/position_card.dart`、`widgets/portfolio_summary_card.dart` | 投資組合頁 | 即時價、今日損益、狀態、日期說明、登記 |
| `lib/presentation/screens/portfolio/position_detail_screen.dart` | 持股詳情 | 即時價、狀態、登記 |
| `assets/translations/zh-TW.json`、`en.json`、`CHANGELOG.md` | 文案 | 新增 |

---

### Task 1: 指數的合併結果與顯示資料

**Files:**
- Modify: `lib/core/constants/live_quote_params.dart`
- Create: `lib/presentation/providers/market_index_live_provider.dart`
- Test: `test/presentation/providers/market_index_live_provider_test.dart`（新）

**Interfaces:**
- Consumes：
  - `LiveQuoteMerge`、`OfficialPrice`、`MergedPrice`、`MergedPriceKind`；
  - `liveQuoteCenterProvider`、`LiveQuoteState`、`LiveQuoteRegistration`；
  - `liveQuoteBoundaryProvider`、`appClockProvider`、`settingsProvider`（`priceFlash`）、`marketOverviewProvider`；
  - `heroIndexOf`、`heroIndexName`（`market_overview_selectors.dart`）、`LiveQuoteStatusRule`、`TwseMarketIndex`。
- Produces：
  - `static String LiveQuoteParams.indexSymbolOf(String market)`。
  - `class MarketIndexLive { TwseMarketIndex index; bool isLive; LiveQuoteFlash? flash; bool flashEnabled; String? statusText; static MarketIndexLive? of({required String market, required TwseMarketIndex? official, required MergedPrice merged, required LiveQuoteState center, required bool flashEnabled}) }`。
  - `class MarketLiveIndices { Map<String, MarketIndexLive> byMarket; String? statusText; bool get anyLive }`。
  - `final marketIndexLivePriceProvider = Provider.autoDispose.family<MergedPrice, String>`（key 為 `MarketCode.twse`／`MarketCode.tpex`）。
  - `final marketLiveIndicesProvider = Provider.autoDispose<MarketLiveIndices>`。
  - `List<LiveQuoteRegistration> marketIndexRegistrations(MarketOverviewState state, DateTime now)`。

- [ ] **Step 1: 寫失敗測試**

建立 `test/presentation/providers/market_index_live_provider_test.dart`：

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/constants/live_quote_params.dart';
import 'package:daredevil/core/constants/market_codes.dart';
import 'package:daredevil/core/utils/clock.dart';
import 'package:daredevil/data/models/twse/twse_market_index.dart';
import 'package:daredevil/domain/models/live_quote.dart';
import 'package:daredevil/presentation/providers/live_quote_provider.dart';
import 'package:daredevil/presentation/providers/market_index_live_provider.dart';
import 'package:daredevil/presentation/providers/market_overview_provider.dart';
import 'package:daredevil/presentation/providers/providers.dart';
import 'package:daredevil/presentation/providers/settings_provider.dart';

class _Clock implements AppClock {
  _Clock(this.value);
  final DateTime value;
  @override
  DateTime now() => value;
}

class _FakeSettings extends SettingsNotifier {
  _FakeSettings([this.initial = const SettingsState()]);
  final SettingsState initial;
  @override
  SettingsState build() => initial;
}

class _FixedMarket extends MarketOverviewNotifier {
  _FixedMarket(this.initial);
  final MarketOverviewState initial;
  @override
  MarketOverviewState build() => initial;
}

class _FixedCenter extends LiveQuoteCenter {
  _FixedCenter(this.initial);
  final LiveQuoteState initial;
  @override
  LiveQuoteState build() => initial;
}

/// 大盤指數的即時顯示(2026-10-06,spec §5、§7「今日頁大盤列、大盤總覽頁」)。
void main() {
  final morning = DateTime(2026, 10, 6, 10, 15);
  final yesterday = DateTime(2026, 10, 5);
  final today = DateTime(2026, 10, 6);

  TwseMarketIndex index(String name, DateTime date, {double close = 20000}) =>
      TwseMarketIndex(
        date: date,
        name: name,
        close: close,
        change: 100,
        changePercent: 0.5,
      );

  LiveQuoteEntry quote(String symbol, double price, {int? flashId}) =>
      LiveQuoteEntry(
        symbol: symbol,
        date: today,
        price: price,
        displaySource: LiveDisplaySource.trade,
        previousClose: 20000,
        quoteTime: '10:14:55',
        isClosingQuote: false,
        flash: flashId == null ? null : LiveQuoteFlash(id: flashId, up: true),
      );

  ProviderContainer container(
    MarketOverviewState market,
    LiveQuoteState live, {
    SettingsState settings = const SettingsState(),
  }) {
    final c = ProviderContainer(
      overrides: [
        appClockProvider.overrideWithValue(_Clock(morning)),
        marketOverviewProvider.overrideWith(() => _FixedMarket(market)),
        liveQuoteCenterProvider.overrideWith(() => _FixedCenter(live)),
        settingsProvider.overrideWith(() => _FakeSettings(settings)),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  test('indexSymbolOf:上市 t00、上櫃 o00', () {
    expect(LiveQuoteParams.indexSymbolOf(MarketCode.twse), 't00');
    expect(LiveQuoteParams.indexSymbolOf(MarketCode.tpex), 'o00');
  });

  test('🚨 盤後資料是昨天、有今天的即時 → 顯示即時點數,漲跌以 MIS 昨收算', () {
    final c = container(
      MarketOverviewState(
        indices: [index(MarketIndexNames.taiex, yesterday)],
      ),
      LiveQuoteState(entries: {'t00': quote('t00', 20200)}),
    );
    final shown = c.read(marketLiveIndicesProvider).byMarket[MarketCode.twse]!;
    expect(shown.isLive, isTrue);
    expect(shown.index.name, MarketIndexNames.taiex);
    expect(shown.index.close, 20200);
    expect(shown.index.change, closeTo(200, 1e-9));
    expect(shown.index.changePercent, closeTo(1.0, 1e-9));
    expect(shown.index.date, today);
    expect(shown.statusText, 'liveQuote.quoteTime');
  });

  test('盤後資料是今天 → 用盤後那一筆,不標狀態', () {
    final official = index(MarketIndexNames.taiex, today);
    final c = container(
      MarketOverviewState(indices: [official]),
      LiveQuoteState(entries: {'t00': quote('t00', 20200)}),
    );
    final indices = c.read(marketLiveIndicesProvider);
    final shown = indices.byMarket[MarketCode.twse]!;
    expect(shown.isLive, isFalse);
    expect(shown.index, same(official));
    expect(shown.statusText, isNull);
    expect(indices.anyLive, isFalse);
  });

  test('🚨 備援值(非即時)即使日期是今天也不算正式資料 → 有即時就用即時', () {
    final stale = index(MarketIndexNames.taiex, today);
    final c = container(
      MarketOverviewState(
        indices: [stale],
        indexStaleNames: {MarketIndexNames.taiex},
      ),
      LiveQuoteState(entries: {'t00': quote('t00', 20200)}),
    );
    expect(
      c.read(marketLiveIndicesProvider).byMarket[MarketCode.twse]!.isLive,
      isTrue,
    );
  });

  test('沒有盤後資料、有即時 → 名稱用預設的上櫃指數名稱', () {
    final c = container(
      const MarketOverviewState(),
      LiveQuoteState(entries: {'o00': quote('o00', 300)}),
    );
    final shown = c.read(marketLiveIndicesProvider).byMarket[MarketCode.tpex]!;
    expect(shown.index.name, MarketIndexNames.tpexIndex);
    expect(shown.isLive, isTrue);
  });

  test('沒有盤後也沒有即時 → 不顯示該指數', () {
    final c = container(const MarketOverviewState(), const LiveQuoteState());
    expect(c.read(marketLiveIndicesProvider).byMarket, isEmpty);
  });

  test('閃色事件帶到顯示資料;設定頁關閉價格閃色 → flashEnabled false', () {
    final c = container(
      MarketOverviewState(
        indices: [index(MarketIndexNames.taiex, yesterday)],
      ),
      LiveQuoteState(entries: {'t00': quote('t00', 20200, flashId: 7)}),
      settings: const SettingsState(priceFlash: false),
    );
    final shown = c.read(marketLiveIndicesProvider).byMarket[MarketCode.twse]!;
    expect(shown.flash!.id, 7);
    expect(shown.flashEnabled, isFalse);
  });

  test('🚨 登記兩個指數;「已有今天正式資料」只在日期是今天且不是備援值時成立', () {
    MarketOverviewState state(DateTime date, {bool stale = false}) =>
        MarketOverviewState(
          indices: [
            index(MarketIndexNames.taiex, date),
            index(MarketIndexNames.tpexIndex, date, close: 300),
          ],
          indexStaleNames: stale ? {MarketIndexNames.taiex} : const {},
        );

    expect(marketIndexRegistrations(state(today), morning), const [
      LiveQuoteRegistration(
        symbol: 't00',
        market: MarketCode.twse,
        hasOfficialToday: true,
      ),
      LiveQuoteRegistration(
        symbol: 'o00',
        market: MarketCode.tpex,
        hasOfficialToday: true,
      ),
    ]);
    expect(
      marketIndexRegistrations(state(today, stale: true), morning)
          .first
          .hasOfficialToday,
      isFalse,
    );
    expect(
      marketIndexRegistrations(state(yesterday), morning).first.hasOfficialToday,
      isFalse,
    );
    expect(
      marketIndexRegistrations(const MarketOverviewState(), morning)
          .map((r) => r.hasOfficialToday),
      [false, false],
    );
  });
}
```

（`MarketIndexNames` 由 `market_overview_provider.dart` 匯出。）

- [ ] **Step 2: 確認紅燈**

Run: `flutter test test/presentation/providers/market_index_live_provider_test.dart`
Expected: 編譯失敗（`market_index_live_provider.dart` 不存在、`indexSymbolOf` 未定義）

- [ ] **Step 3: 實作**

1. `lib/core/constants/live_quote_params.dart`：
   - 檔頭加 `import 'package:daredevil/core/constants/market_codes.dart';`（這個檔原本沒有 import；core 內互相 import，`core_layer_purity_test` 允許）。
   - 在 `tpexIndexSymbol` 之後加：

```dart

  /// 市場別 → 大盤指數的 MIS 代號(上市 t00、上櫃 o00)
  static String indexSymbolOf(String market) =>
      market == MarketCode.twse ? twseIndexSymbol : tpexIndexSymbol;
```

2. 建立 `lib/presentation/providers/market_index_live_provider.dart`：

```dart
import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:daredevil/core/constants/live_quote_params.dart';
import 'package:daredevil/core/constants/market_codes.dart';
import 'package:daredevil/core/utils/date_context.dart';
import 'package:daredevil/data/models/twse/twse_market_index.dart';
import 'package:daredevil/domain/models/live_quote.dart';
import 'package:daredevil/domain/services/live_quote/live_quote_merge.dart';
import 'package:daredevil/presentation/providers/live_price_provider.dart';
import 'package:daredevil/presentation/providers/live_quote_provider.dart';
import 'package:daredevil/presentation/providers/market_overview_provider.dart';
import 'package:daredevil/presentation/providers/providers.dart';
import 'package:daredevil/presentation/providers/settings_provider.dart';
import 'package:daredevil/presentation/widgets/live_quote_status.dart';
import 'package:daredevil/presentation/widgets/market_dashboard/market_overview_selectors.dart';

/// 大盤列、大盤總覽頁 Hero 卡要顯示的一個指數
@immutable
class MarketIndexLive {
  const MarketIndexLive({
    required this.index,
    required this.isLive,
    this.flash,
    this.flashEnabled = true,
    this.statusText,
  });

  /// 要顯示的指數:用即時報價時以即時點數與 MIS 昨收組成,否則是盤後那一筆
  final TwseMarketIndex index;

  /// 用即時報價(此時不掛「非即時」)
  final bool isLive;
  final LiveQuoteFlash? flash;

  /// 設定頁「價格閃色」
  final bool flashEnabled;

  /// 這個指數自己的報價狀態(已翻譯);用盤後正式資料時為 null
  final String? statusText;

  /// 依合併結果組出要顯示的指數;沒有盤後資料也沒有即時時回 null
  static MarketIndexLive? of({
    required String market,
    required TwseMarketIndex? official,
    required MergedPrice merged,
    required LiveQuoteState center,
    required bool flashEnabled,
  }) {
    final statusText = merged.kind == MergedPriceKind.official
        ? null
        : LiveQuoteStatusRule.header(
            state: center,
            merged: [merged],
            intradayTime: merged.quoteTime,
          )?.text();
    final live = merged.live;
    final price = merged.price;
    final previous = merged.previousClose;
    if (merged.kind == MergedPriceKind.live &&
        live != null &&
        price != null &&
        previous != null) {
      return MarketIndexLive(
        index: TwseMarketIndex(
          date: live.date,
          name: official?.name ?? heroIndexName(market),
          close: price,
          change: price - previous,
          changePercent: merged.changePercent ?? 0,
        ),
        isLive: true,
        flash: live.flash,
        flashEnabled: flashEnabled,
        statusText: statusText,
      );
    }
    if (official == null) return null;
    return MarketIndexLive(
      index: official,
      isLive: false,
      flashEnabled: flashEnabled,
      statusText: statusText,
    );
  }
}

/// 大盤列與 Hero 卡的兩個指數
@immutable
class MarketLiveIndices {
  const MarketLiveIndices({this.byMarket = const {}, this.statusText});

  /// 市場別(`MarketCode.twse`／`MarketCode.tpex`)→ 要顯示的指數
  final Map<String, MarketIndexLive> byMarket;

  /// 兩個指數合起來的報價狀態(大盤列用,已翻譯);都用正式資料時為 null
  final String? statusText;

  /// 有任一指數用即時報價(此時情緒、漲跌家數仍是盤後,要標日期)
  bool get anyLive => byMarket.values.any((i) => i.isLive);
}

/// 盤後的正式資料:該指數的日期;備援值(非即時)的日期傳 null,不算今天
OfficialPrice? _officialOf(MarketOverviewState s, String market) {
  final index = heroIndexOf(s, market);
  if (index == null) return null;
  return OfficialPrice(
    date: s.indexStaleNames.contains(index.name) ? null : index.date,
    close: index.close,
    priceChange: index.change,
  );
}

/// 大盤指數要顯示的點數(依合併規則;正式資料 = `MarketOverviewState` 的該
/// 指數,日期是今天且不是備援值)。判讀文字不走這裡(spec §7)
final marketIndexLivePriceProvider = Provider.autoDispose
    .family<MergedPrice, String>((ref, market) {
      ref.watch(liveQuoteBoundaryProvider);
      final official = ref.watch(
        marketOverviewProvider.select((s) => _officialOf(s, market)),
      );
      final live = ref.watch(
        liveQuoteCenterProvider.select(
          (s) => s.entries[LiveQuoteParams.indexSymbolOf(market)],
        ),
      );
      return LiveQuoteMerge.merge(
        official: official,
        live: live,
        now: ref.read(appClockProvider).now(),
      );
    });

/// 大盤列與 Hero 卡共用:兩個指數要顯示的值與狀態
final marketLiveIndicesProvider = Provider.autoDispose<MarketLiveIndices>((
  ref,
) {
  final center = ref.watch(liveQuoteCenterProvider);
  final flashEnabled = ref.watch(settingsProvider.select((s) => s.priceFlash));
  final byMarket = <String, MarketIndexLive>{};
  final merged = <MergedPrice>[];
  for (final market in const [MarketCode.twse, MarketCode.tpex]) {
    final m = ref.watch(marketIndexLivePriceProvider(market));
    merged.add(m);
    final item = MarketIndexLive.of(
      market: market,
      official: ref.watch(
        marketOverviewProvider.select((s) => heroIndexOf(s, market)),
      ),
      merged: m,
      center: center,
      flashEnabled: flashEnabled,
    );
    if (item != null) byMarket[market] = item;
  }
  final allOfficial = merged.every((m) => m.kind == MergedPriceKind.official);
  return MarketLiveIndices(
    byMarket: byMarket,
    statusText: allOfficial
        ? null
        : LiveQuoteStatusRule.header(
            state: center,
            merged: merged,
            intradayTime: null,
          )?.text(),
  );
});

/// 大盤列與大盤總覽頁登記的兩個指數;「已有今天正式資料」= 該指數日期是
/// 今天且不是備援值(收盤後據此決定要不要抓收盤報價)
List<LiveQuoteRegistration> marketIndexRegistrations(
  MarketOverviewState state,
  DateTime now,
) => [
  for (final market in const [MarketCode.twse, MarketCode.tpex])
    _indexRegistration(state, market, now),
];

LiveQuoteRegistration _indexRegistration(
  MarketOverviewState state,
  String market,
  DateTime now,
) {
  final date = _officialOf(state, market)?.date;
  return LiveQuoteRegistration(
    symbol: LiveQuoteParams.indexSymbolOf(market),
    market: market,
    hasOfficialToday: date != null && DateContext.isSameDay(date, now),
  );
}
```

- [ ] **Step 4: 確認通過**

Run: `flutter test test/presentation/providers/market_index_live_provider_test.dart`
Expected: 全部 PASS

Run: `flutter analyze`
Expected: `No issues found!`（`core_layer_purity_test` 也要過：`live_quote_params.dart` 只 import core）

- [ ] **Step 5: 記錄進度**（不 commit）

---

### Task 2: 今日頁大盤列

**Files:**
- Modify: `lib/presentation/screens/today/widgets/market_summary_strip.dart`
- Modify: `lib/presentation/screens/today/today_screen.dart`（大盤列那個 `Consumer`）
- Test: `test/presentation/screens/today/widgets/market_summary_strip_test.dart`、`test/presentation/screens/today/today_screen_test.dart`

**Interfaces:**
- Consumes：Task 1 的 `MarketLiveIndices`、`MarketIndexLive`、`marketLiveIndicesProvider`、`marketIndexRegistrations`；第 2 段的 `LiveQuoteScope`、`liveQuoteBoundaryProvider`。
- Produces：`MarketSummaryStrip({..., MarketLiveIndices? live})`。

- [ ] **Step 1: 寫失敗測試**

1. `test/presentation/screens/today/widgets/market_summary_strip_test.dart`：
   - import 加：

```dart
import 'package:daredevil/presentation/providers/market_index_live_provider.dart';
```

   - `pump` 加參數 `MarketLiveIndices? live`，`MarketSummaryStrip(` 加 `live: live,`。
   - 在 `main()` 最後加：

```dart
  group('盤中即時報價', () {
    final liveTwse = MarketLiveIndices(
      byMarket: {
        MarketCode.twse: MarketIndexLive(
          index: TwseMarketIndex(
            date: DateTime(2026, 9, 25),
            name: MarketIndexNames.taiex,
            close: 48524.6,
            change: 500,
            changePercent: 1.04,
          ),
          isLive: true,
        ),
      },
      statusText: '報價時間 10:15:30',
    );

    testWidgets('🚨 有即時指數 → 顯示即時點數與漲跌;沒即時的那個照舊', (tester) async {
      await pump(tester, _withData, live: liveTwse);
      expect(find.text('加權 48,524.60 +1.04%'), findsOneWidget);
      expect(find.text('櫃買 285.30 +0.10%'), findsOneWidget);
    });

    testWidgets('報價狀態接在指數那一行', (tester) async {
      await pump(tester, _withData, live: liveTwse);
      expect(find.text('報價時間 10:15:30'), findsOneWidget);
    });

    testWidgets('🚨 有指數用即時 → 情緒與漲跌家數標盤後資料的日期', (tester) async {
      final withDate = _withData.copyWith(dataDate: DateTime(2026, 9, 24));
      await pump(tester, withDate, live: liveTwse);
      expect(find.text('${sentimentGroup(withDate)} (9/24)'), findsOneWidget);
      expect(find.text('漲 408 跌 667 (9/24)'), findsOneWidget);
    });

    testWidgets('沒有指數用即時 → 不標日期(維持現狀)', (tester) async {
      final withDate = _withData.copyWith(dataDate: DateTime(2026, 9, 24));
      await pump(tester, withDate, live: const MarketLiveIndices());
      expect(find.text(sentimentGroup(withDate)), findsOneWidget);
      expect(find.text('漲 408 跌 667'), findsOneWidget);
    });

    testWidgets('🚨 備援值被即時取代 → 不掛「非即時」', (tester) async {
      final stale = MarketOverviewState(
        indices: _withData.indices,
        indexStaleNames: {MarketIndexNames.taiex},
        advanceDeclineByMarket: _withData.advanceDeclineByMarket,
      );
      await pump(tester, stale, live: liveTwse);
      expect(find.textContaining('非即時'), findsNothing);
    });
  });
```


2. `test/presentation/screens/today/today_screen_test.dart`：
   - import 加：

```dart
import 'package:daredevil/core/constants/market_codes.dart';
import 'package:daredevil/domain/models/live_quote.dart';
import 'package:daredevil/presentation/providers/live_quote_provider.dart';
```

（已有的不重複加。）

   - 在檔內最後一個類別之後加：

```dart

/// 記錄登記、不發請求的報價中心
class _LiveCenter extends LiveQuoteCenter {
  _LiveCenter(this.initial);
  final LiveQuoteState initial;
  final registered = <Object, List<LiveQuoteRegistration>>{};

  @override
  LiveQuoteState build() => initial;

  @override
  void register(Object owner, List<LiveQuoteRegistration> entries) =>
      registered[owner] = entries;

  @override
  void unregister(Object owner) => registered.remove(owner);

  @override
  void setAppVisible(bool visible) {}
}
```

   - `buildTestWidget` 參數在 `Widget Function(Widget screen)? wrap,` 之後加 `_LiveCenter? liveCenter,`；`router: router,` 之後加 `liveQuoteCenter: liveCenter == null ? null : () => liveCenter,`。
   - 在 `main()` 最後加：

```dart
  group('盤中即時報價(大盤列)', () {
    final market = MarketOverviewState(
      indices: [
        TwseMarketIndex(
          date: DateTime(2026, 10, 5),
          name: MarketIndexNames.taiex,
          close: 20000,
          change: 100,
          changePercent: 0.5,
        ),
      ],
      advanceDeclineByMarket: const {
        MarketCode.twse: AdvanceDecline(advance: 500, decline: 400, unchanged: 100),
      },
    );

    testWidgets('🚨 只登記兩個指數;訊號卡片不登記(維持盤後)', (tester) async {
      widenViewport(tester);
      final center = _LiveCenter(const LiveQuoteState());
      await tester.pumpWidget(
        buildTestWidget(
          marketState: market,
          liveCenter: center,
          modeRecommendations: (ref, mode) =>
              SynchronousFuture([rec('2330'), rec('2317')]),
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      final symbols = {
        for (final entries in center.registered.values)
          for (final r in entries) r.symbol,
      };
      expect(symbols, {'t00', 'o00'});
    });

    testWidgets('有即時指數 → 大盤列顯示即時點數', (tester) async {
      widenViewport(tester);
      final center = _LiveCenter(
        LiveQuoteState(
          entries: {
            't00': LiveQuoteEntry(
              symbol: 't00',
              date: DateTime(2026, 10, 6),
              price: 20200,
              displaySource: LiveDisplaySource.trade,
              previousClose: 20000,
              quoteTime: '10:14:55',
              isClosingQuote: false,
            ),
          },
        ),
      );
      await tester.pumpWidget(
        buildTestWidget(
          marketState: market,
          liveCenter: center,
          clock: _FixedClock(DateTime(2026, 10, 6, 10, 15)),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(find.textContaining('20,200.00'), findsOneWidget);
    });
  });
```

   - `_FixedClock(DateTime)` 是該檔既有的固定時鐘；`TwseMarketIndex` 已 import；`MarketIndexNames`、`AdvanceDecline` 由 `market_overview_provider.dart` 匯出；`rec(...)` 是該檔既有的輔助。

- [ ] **Step 2: 確認紅燈**

Run: `flutter test test/presentation/screens/today/widgets/market_summary_strip_test.dart test/presentation/screens/today/today_screen_test.dart`
Expected: 編譯失敗（`MarketSummaryStrip.live` 未定義、`buildProviderTestApp` 的 `liveQuoteCenter` 尚未在 today 測試傳入時無法登記）

- [ ] **Step 3: 實作**

1. `lib/presentation/screens/today/widgets/market_summary_strip.dart`：
   - import 加 `import 'package:daredevil/presentation/providers/market_index_live_provider.dart';`。
   - 建構子在 `required this.onRetry,` 之後加 `this.live,`。
   - 欄位加：

```dart

  /// 盤中即時報價(今日頁傳入);null = 盤後行為
  final MarketLiveIndices? live;
```

   - `build` 的兩個 `_indexGroup(` 呼叫，第三個參數由 `heroIndexOf(state, MarketCode.twse)`／`heroIndexOf(state, MarketCode.tpex)` 改為 `MarketCode.twse`／`MarketCode.tpex`。
   - 第一個 `Wrap` 的 `children` 在第二個 `_indexGroup(...)` 之後加：

```dart
                            if (live?.statusText case final status?)
                              Text(status, style: muted),
```

   - `build` 裡 `final separator = ...;` 之後加：

```dart
    // 指數用即時報價時,情緒與漲跌家數仍是盤後(前一交易日):標日期,
    // 避免看成今天的
    final postMarketDate = (live?.anyLive ?? false) ? state.dataDate : null;
```

   - 第二個 `Wrap` 的兩個呼叫改成：

```dart
                            _sentimentGroup(
                              muted: muted,
                              strong: strong,
                              dateLabel: postMarketDate,
                            ),
                            separator,
                            _breadthGroup(
                              context,
                              muted: muted,
                              strong: strong,
                              dateLabel: postMarketDate == null
                                  ? null
                                  : state.advanceDeclineStaleDates[MarketCode
                                            .twse] ??
                                        postMarketDate,
                            ),
```

   - `_indexGroup` 換成：

```dart
  /// 「加權 48,024.60 -0.28%」＋（備援值時）「非即時(9/24)」。有即時報價
  /// 時顯示即時點數,不掛「非即時」
  Widget _indexGroup(
    BuildContext context,
    String label,
    String market, {
    required TextStyle? muted,
    required TextStyle? strong,
    required Color warningColor,
  }) {
    final shown = live?.byMarket[market];
    final index = shown?.index ?? heroIndexOf(state, market);
    if (index == null) {
      return Text.rich(
        TextSpan(
          children: [
            TextSpan(text: '$label ', style: muted),
            TextSpan(text: _placeholder, style: strong),
          ],
        ),
      );
    }
    final isStale =
        !(shown?.isLive ?? false) && state.indexStaleNames.contains(index.name);
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: '$label ', style: muted),
          TextSpan(
            text: NumberFormat('#,##0.00').format(index.close),
            style: strong,
          ),
          const TextSpan(text: ' '),
          TextSpan(
            text: indexChangePercentText(index),
            style: strong?.copyWith(color: context.priceColor(index.change)),
          ),
          // 與大盤頁 hero 同一個警示色：備援值不得與即時值同貌
          if (isStale) ...[
            const TextSpan(text: ' '),
            TextSpan(
              text: 'marketOverview.indexStale'.tr(
                namedArgs: {'date': '${index.date.month}/${index.date.day}'},
              ),
              style: muted?.copyWith(color: warningColor),
            ),
          ],
        ],
      ),
    );
  }
```

   - `_sentimentGroup` 加參數 `DateTime? dateLabel`。在 `children` 最後加：

```dart
          if (dateLabel != null)
            TextSpan(
              text: ' (${dateLabel.month}/${dateLabel.day})',
              style: muted,
            ),
```

   - `_breadthGroup` 加參數 `DateTime? dateLabel`，同樣在 `children` 最後加上面那段。

2. `lib/presentation/screens/today/today_screen.dart`：
   - import 加：

```dart
import 'package:daredevil/presentation/providers/live_price_provider.dart';
import 'package:daredevil/presentation/providers/market_index_live_provider.dart';
import 'package:daredevil/presentation/widgets/live_quote_scope.dart';
```

   - 大盤摘要條那段 `SliverToBoxAdapter(child: Consumer(builder: (context, ref, _) => MarketSummaryStrip(...)))` 換成：

```dart
        SliverToBoxAdapter(
          child: Consumer(
            builder: (context, ref, _) {
              final market = ref.watch(marketOverviewProvider);
              // 登記的「是否已有今天正式資料」跟現在有關:跨過午夜等邊界時重算
              ref.watch(liveQuoteBoundaryProvider);
              return LiveQuoteScope(
                // 只登記兩個指數;訊號卡片維持盤後、不登記(spec §7)
                registrations: marketIndexRegistrations(
                  market,
                  ref.read(appClockProvider).now(),
                ),
                child: MarketSummaryStrip(
                  state: market,
                  live: ref.watch(marketLiveIndicesProvider),
                  onTap: () => context.push(AppRoutes.market),
                  onRetry: () =>
                      ref.read(marketOverviewProvider.notifier).loadData(),
                ),
              );
            },
          ),
        ),
```

   - 跑 `grep -n "StockCardLive\|watchlistLivePriceProvider\|WatchlistLiveView" lib/presentation/screens/today`，Expected：沒有輸出（守門測試 `live_quote_screen_scope_test` 照舊）。

- [ ] **Step 4: 確認通過**

Run: `flutter test test/presentation/screens/today/ test/presentation/live_quote_screen_scope_test.dart test/presentation/providers/market_index_live_provider_test.dart`
Expected: 全部 PASS；既有大盤列測試字串不變。

Run: `flutter test --tags golden test/presentation/screens/golden/today_screen_golden_test.dart`
Expected: PASS（golden 不變）

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 5: 記錄進度**（不 commit）

---

### Task 3: 大盤總覽頁 Hero 卡

**Files:**
- Modify: `lib/presentation/widgets/market_dashboard/hero_index_section.dart`
- Modify: `lib/presentation/widgets/market_dashboard/market_dashboard.dart`
- Modify: `lib/presentation/screens/market/market_overview_screen.dart`
- Test: `test/presentation/widgets/market_dashboard/hero_index_section_test.dart`、`test/presentation/widgets/market_dashboard/market_dashboard_test.dart`、`test/presentation/screens/market/market_overview_screen_test.dart`

**Interfaces:**
- Consumes：Task 1 的 `MarketLiveIndices`、`MarketIndexLive`、`marketLiveIndicesProvider`、`marketIndexRegistrations`；第 2 段的 `PriceFlash`、`LiveQuoteScope`、`liveQuoteBoundaryProvider`。
- Produces：
  - `HeroIndexSection({..., LiveQuoteFlash? flash, bool flashEnabled = true, String? statusText})`。
  - `MarketDashboard({required MarketOverviewState state, MarketLiveIndices? live})`。

- [ ] **Step 1: 寫失敗測試**

1. `test/presentation/widgets/market_dashboard/hero_index_section_test.dart`：
   - `import 'package:flutter/widgets.dart';` 換成 `import 'package:flutter/material.dart';`（要用 `Theme`）。
   - import 加：

```dart
import 'package:daredevil/core/constants/market_index_names.dart';
import 'package:daredevil/core/theme/color_contrast.dart';
import 'package:daredevil/domain/models/live_quote.dart';
import 'package:daredevil/presentation/widgets/price_flash.dart';
```

（`TwseMarketIndex` 經該檔既有的 `twse_client.dart` 取得。）

   - 在 `main()` 最後加：

```dart
  group('盤中即時報價', () {
    final idx = TwseMarketIndex(
      date: DateTime(2026, 10, 6),
      name: MarketIndexNames.taiex,
      close: 20200,
      change: 200,
      changePercent: 1.0,
    );

    testWidgets('報價狀態顯示在點數下方', (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          HeroIndexSection(index: idx, statusText: 'liveQuote.quoteTime'),
        ),
      );
      expect(find.text('liveQuote.quoteTime'), findsOneWidget);
    });

    for (final brightness in [Brightness.light, Brightness.dark]) {
      testWidgets('🚨 點數閃色最濃時 $brightness:對 Hero 卡實際底色 ≥ 4.5', (tester) async {
        Widget hero(int id) => buildTestApp(
          HeroIndexSection(
            index: idx,
            flash: LiveQuoteFlash(id: id, up: true),
          ),
          brightness: brightness,
        );
        await tester.pumpWidget(hero(1));
        await tester.pumpWidget(hero(2));
        await tester.pump();

        final tint =
            (tester.widget<DecoratedBox>(find.byKey(PriceFlash.tintKey)).decoration
                    as BoxDecoration)
                .color!;
        final cardColor = Theme.of(
          tester.element(find.byKey(PriceFlash.tintKey)),
        ).colorScheme.surfaceContainerLowest;
        final text = tester
            .widget<RichText>(
              find.descendant(
                of: find.byKey(PriceFlash.tintKey),
                matching: find.byType(RichText),
              ),
            )
            .text
            .style!
            .color!;
        expect(
          ColorContrast.ratio(
            text,
            ColorContrast.compositeOver(
              tint.withValues(alpha: 1),
              cardColor,
              tint.a,
            ),
          ),
          greaterThanOrEqualTo(4.5),
        );
      });
    }
  });
```

（Hero 卡外層的 `Container` 是 `colorScheme.surfaceContainerLowest` 的不透明底，就是點數的實際底色。）

2. `test/presentation/widgets/market_dashboard/market_dashboard_test.dart`：
   - import 加：

```dart
import 'package:daredevil/domain/services/market_reading_service.dart';
import 'package:daredevil/presentation/providers/market_index_live_provider.dart';
import 'package:daredevil/presentation/widgets/market_dashboard/hero_index_section.dart';
import 'package:daredevil/presentation/widgets/market_dashboard/market_reading_line.dart';
```

（已有的不重複加。）

   - 在 `main()` 最後加：

```dart
  group('盤中即時報價', () {
    // 盤後:指數微漲、家數偏多;即時:指數大跌——判讀若誤用即時會換句子
    final state = MarketOverviewState(
      indices: [
        TwseMarketIndex(
          date: DateTime(2026, 10, 5),
          name: MarketIndexNames.taiex,
          close: 20000,
          change: 40,
          changePercent: 0.2,
        ),
      ],
      advanceDeclineByMarket: const {
        MarketCode.twse: AdvanceDecline(advance: 800, decline: 200, unchanged: 50),
      },
    );
    final live = MarketLiveIndices(
      byMarket: {
        MarketCode.twse: MarketIndexLive(
          index: TwseMarketIndex(
            date: DateTime(2026, 10, 6),
            name: MarketIndexNames.taiex,
            close: 19400,
            change: -600,
            changePercent: -3.0,
          ),
          isLive: true,
          statusText: 'liveQuote.quoteTime',
        ),
      },
    );

    List<String> readings(WidgetTester tester) => [
      for (final line in tester.widgetList<MarketReadingLine>(
        find.byType(MarketReadingLine),
      ))
        '${line.reading?.messageKey}|${line.reading?.tone}|${line.reading?.args}',
    ];

    testWidgets('🚨 Hero 用即時點數;判讀文字仍用盤後指數漲跌幅(與沒有即時時完全相同)', (
      tester,
    ) async {
      // 前提:即時與盤後的漲跌幅會讓綜合判讀換句子,這條測試才有鑑別力
      MarketReading synthesis(double pct) =>
          MarketReadingService.interpretCompositeSynthesis(
            market: MarketCode.twse,
            indexChangePercent: pct,
            advance: 800,
            decline: 200,
            unchanged: 50,
            institutionalTotalNet: 0,
          );
      expect(
        synthesis(-3.0).messageKey,
        isNot(synthesis(0.2).messageKey),
        reason: '前提:fixture 要讓判讀對漲跌幅敏感',
      );

      tester.view.physicalSize = const Size(5000, 4000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(buildTestApp(MarketDashboard(state: state)));
      await tester.pump(const Duration(seconds: 1));
      final postMarket = readings(tester);
      expect(postMarket, isNotEmpty, reason: '前提:有判讀文字');

      await tester.pumpWidget(
        buildTestApp(MarketDashboard(state: state, live: live)),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(
        tester.widget<HeroIndexSection>(find.byType(HeroIndexSection).first).index.close,
        19400,
      );
      expect(readings(tester), postMarket);
    });
  });
```

   - 該檔已 import `twse_market_index.dart`、`market_codes.dart`、`market_overview_provider.dart`（匯出 `MarketIndexNames`、`AdvanceDecline`）、`market_reading_line.dart`。

3. `test/presentation/screens/market/market_overview_screen_test.dart`：
   - import 加：

```dart
import 'package:daredevil/core/utils/clock.dart';
import 'package:daredevil/data/models/twse/twse_market_index.dart';
import 'package:daredevil/domain/models/live_quote.dart';
import 'package:daredevil/presentation/providers/live_quote_provider.dart';
import 'package:daredevil/presentation/providers/providers.dart';
import 'package:daredevil/presentation/widgets/market_dashboard/hero_index_section.dart';
```

   - 檔尾加：

```dart

class _Clock implements AppClock {
  _Clock(this.value);
  final DateTime value;
  @override
  DateTime now() => value;
}

/// 記錄登記、不發請求的報價中心
class _LiveCenter extends LiveQuoteCenter {
  _LiveCenter(this.initial);
  final LiveQuoteState initial;
  final registered = <Object, List<LiveQuoteRegistration>>{};

  @override
  LiveQuoteState build() => initial;

  @override
  void register(Object owner, List<LiveQuoteRegistration> entries) =>
      registered[owner] = entries;

  @override
  void unregister(Object owner) => registered.remove(owner);

  @override
  void setAppVisible(bool visible) {}
}
```
   - 在 `main()` 最後加：

```dart
  group('盤中即時報價', () {
    testWidgets('🚨 登記兩個指數;Hero 顯示即時點數', (tester) async {
      tester.view.physicalSize = const Size(5000, 4000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final state = MarketOverviewState(
        indices: [
          TwseMarketIndex(
            date: DateTime(2026, 10, 5),
            name: MarketIndexNames.taiex,
            close: 20000,
            change: 100,
            changePercent: 0.5,
          ),
        ],
        advanceDeclineByMarket: _withData.advanceDeclineByMarket,
      );
      final center = _LiveCenter(
        LiveQuoteState(
          entries: {
            't00': LiveQuoteEntry(
              symbol: 't00',
              date: DateTime(2026, 10, 6),
              price: 20200,
              displaySource: LiveDisplaySource.trade,
              previousClose: 20000,
              quoteTime: '10:14:55',
              isClosingQuote: false,
            ),
          },
        ),
      );
      await tester.pumpWidget(
        buildProviderTestApp(
          const MarketOverviewScreen(),
          overrides: [
            marketOverviewProvider.overrideWith(() => _FakeMarket(state)),
            appClockProvider.overrideWithValue(
              _Clock(DateTime(2026, 10, 6, 10, 15)),
            ),
          ],
          liveQuoteCenter: () => center,
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(
        {
          for (final entries in center.registered.values)
            for (final r in entries) r.symbol,
        },
        {'t00', 'o00'},
      );
      expect(
        tester.widget<HeroIndexSection>(find.byType(HeroIndexSection).first).index.close,
        20200,
      );
    });
  });
```

- [ ] **Step 2: 確認紅燈**

Run: `flutter test test/presentation/widgets/market_dashboard/ test/presentation/screens/market/`
Expected: 編譯失敗（`HeroIndexSection.flash`／`statusText`、`MarketDashboard.live` 未定義）

- [ ] **Step 3: 實作**

1. `lib/presentation/widgets/market_dashboard/hero_index_section.dart`：
   - import 加：

```dart
import 'package:daredevil/domain/models/live_quote.dart';
import 'package:daredevil/presentation/widgets/price_flash.dart';
```

   - 建構子在 `this.isStale = false,` 之後加 `this.flash, this.flashEnabled = true, this.statusText,`。
   - 欄位加：

```dart

  /// 盤中即時報價的閃色事件(點數變動時底色閃一下);null = 不閃
  final LiveQuoteFlash? flash;

  /// 設定頁「價格閃色」
  final bool flashEnabled;

  /// 這個指數的報價狀態(已翻譯;點數下方一行小字);null = 不顯示
  final String? statusText;
```

   - 大數字 `Text(formatter.format(index.close), ...)` 整個包進 `PriceFlash(flash: flash, enabled: flashEnabled, child: Text(...))`，`Text` 內容不變。
   - 「大數字 + 漲跌」那個 `Row(...)` 之後、`..._buildStageRow(context, theme),` 之前加：

```dart
              if (statusText case final status?)
                Padding(
                  padding: const EdgeInsets.only(top: DesignTokens.spacing4),
                  child: Text(
                    status,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
```

2. `lib/presentation/widgets/market_dashboard/market_dashboard.dart`：
   - import 加 `import 'package:daredevil/presentation/providers/market_index_live_provider.dart';`。
   - 建構子改成 `const MarketDashboard({super.key, required this.state, this.live});`，欄位加：

```dart

  /// 盤中即時報價:只用在 Hero 卡的點數(判讀文字照舊讀 [state],spec §7)
  final MarketLiveIndices? live;
```

   - 三處 `HeroIndexSection(`（手機版上市、手機版上櫃、`_buildMarketHeader`）各自改成先取 `final shown = widget.live?.byMarket[<該市場>];`，再傳：
     - `index: shown?.index ?? <原本的 index>,`
     - `isStale: !(shown?.isLive ?? false) && <原本的 isStale 運算式>,`
     - `flash: shown?.flash,`
     - `flashEnabled: shown?.flashEnabled ?? true,`
     - `statusText: shown?.statusText,`

     其餘參數不變。手機版上市：

```dart
      if (taiex.isNotEmpty) {
        final shown = widget.live?.byMarket[MarketCode.twse];
        sections.add(
          HeroIndexSection(
            index: shown?.index ?? taiex.first,
            isStale:
                !(shown?.isLive ?? false) &&
                widget.state.indexStaleNames.contains(taiex.first.name),
            flash: shown?.flash,
            flashEnabled: shown?.flashEnabled ?? true,
            statusText: shown?.statusText,
            historyData: widget.state.indexHistory[taiex.first.name] ?? [],
            stageHistory:
                widget.state.indexStageHistory[taiex.first.name] ?? [],
            totalReturnHistory:
                widget.state.indexHistory[MarketIndexNames.totalReturnIndex] ??
                [],
          ),
        );
      }
```

     上櫃那處用 `MarketCode.tpex`。`_buildMarketHeader` 用參數 `market`（`widget.live?.byMarket[market]`）。
   - 沒有盤後指數（`taiex.isEmpty` 等兜底分支）時維持現狀：即時指數只取代已有的 Hero 卡。
   - **不改** `_indexChangePercent`、`_marginIndexChangePercent`、`_buildCompositeSynthesisLine`。

3. `lib/presentation/screens/market/market_overview_screen.dart`：
   - import 加：

```dart
import 'package:daredevil/presentation/providers/live_price_provider.dart';
import 'package:daredevil/presentation/providers/market_index_live_provider.dart';
import 'package:daredevil/presentation/providers/providers.dart';
import 'package:daredevil/presentation/widgets/live_quote_scope.dart';
```

   - `build` 裡 `final notifier = ...;` 之後加：

```dart
    // 登記的「是否已有今天正式資料」跟現在有關:跨過午夜等邊界時重算
    ref.watch(liveQuoteBoundaryProvider);
    final live = ref.watch(marketLiveIndicesProvider);
```

   - `body:` 改成 `body: LiveQuoteScope(registrations: marketIndexRegistrations(state, ref.read(appClockProvider).now()), child: ThemedRefreshIndicator(...))`，原本的 `ThemedRefreshIndicator(...)` 不變、結尾補 `)`。
   - `_content(context, state, notifier)` 加第四個參數 `live`，最後一行改成 `return MarketDashboard(state: state, live: live);`，方法簽名加 `MarketLiveIndices live`。

- [ ] **Step 4: 確認通過**

Run: `flutter test test/presentation/widgets/market_dashboard/ test/presentation/screens/market/ test/presentation/providers/`
Expected: 全部 PASS

Run: `flutter test --tags golden test/presentation/screens/golden/market_overview_screen_golden_test.dart`
Expected: PASS（golden 不變）

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 5: 記錄進度**（不 commit）

---

### Task 4: 持股資料補回價格日期與漲跌價差

**Files:**
- Modify: `lib/presentation/providers/portfolio_provider.dart`
- Test: `test/presentation/providers/portfolio_provider_test.dart`

**Interfaces:**
- Produces：
  - `PortfolioPositionData` 的新欄位 `DateTime? priceDate`、`double? priceChangeAmount`，以及 `PortfolioPositionData copyWithPrice(double? price)`。
  - `PortfolioPositionData? PortfolioState.positionOf(String symbol)`。
  - `DateTime? PortfolioState.priceDate`（在倉持股價格日期的最大值）。

- [ ] **Step 1: 寫失敗測試**

`test/presentation/providers/portfolio_provider_test.dart`：

1. `setUp` 最後加。資料缺價差時會查前一筆，預設回空，讓既有測試不受影響：

```dart
    when(
      () => mockDb.getRecentPrices(any(), count: any(named: 'count')),
    ).thenAnswer((_) async => const []);
```

2. `group('PortfolioPositionData', ...)` 內最後加：

```dart
    test('copyWithPrice:只換現價,其他欄位(含價格日期、價差)不變', () {
      final p = PortfolioPositionData(
        symbol: '2330',
        market: 'TWSE',
        quantity: 1000,
        avgCost: 500,
        realizedPnl: 10,
        totalDividendReceived: 5,
        currentPrice: 600,
        priceDate: DateTime(2026, 10, 5),
        priceChangeAmount: 6,
      );
      final live = p.copyWithPrice(612);
      expect(live.currentPrice, 612);
      expect(live.unrealizedPnl, closeTo(112000, 1e-6));
      expect(live.priceDate, DateTime(2026, 10, 5));
      expect(live.priceChangeAmount, 6);
      expect(live.market, 'TWSE');
      expect(live.realizedPnl, 10);
    });
```

3. `group('PortfolioState', ...)` 內最後加：

```dart
    test('positionOf 與 priceDate(在倉持股價格日期的最大值)', () {
      PortfolioPositionData p(String s, DateTime? d, {double qty = 1}) =>
          PortfolioPositionData(
            symbol: s,
            quantity: qty,
            avgCost: 1,
            realizedPnl: 0,
            totalDividendReceived: 0,
            currentPrice: 1,
            priceDate: d,
          );
      final state = PortfolioState(
        positions: [
          p('A', DateTime(2026, 10, 5)),
          p('B', DateTime(2026, 10, 6)),
          p('C', DateTime(2026, 10, 7), qty: 0),
          p('D', null),
        ],
      );
      expect(state.positionOf('B')!.symbol, 'B');
      expect(state.positionOf('X'), isNull);
      expect(state.priceDate, DateTime(2026, 10, 6));
      expect(const PortfolioState().priceDate, isNull);
    });
```

4. `group('PortfolioNotifier', ...)` 內，在 `'loadPositions loads positions with stock info and prices'` 之後加：

```dart
    test('🚨 載入時帶出價格那一筆的日期與漲跌價差(判斷是不是今天、今日損益的昨收)', () async {
      final positions = [
        createPosition(id: 1, symbol: '2330', quantity: 1000, avgCost: 500),
      ];
      when(
        () => mockDb.getPortfolioPositions(),
      ).thenAnswer((_) async => positions);
      when(() => mockDb.getStocksBatch(any())).thenAnswer(
        (_) async => {'2330': createStock(symbol: '2330')},
      );
      when(() => mockDb.getLatestPricesBatch(any())).thenAnswer(
        (_) async => {
          '2330': DailyPriceEntry(
            symbol: '2330',
            date: DateTime(2026, 10, 5),
            close: 600,
            priceChange: 6,
          ),
        },
      );
      when(
        () => mockDb.getAllPortfolioTransactions(),
      ).thenAnswer((_) async => []);
      stubDividendReads();

      await container.read(portfolioProvider.notifier).loadPositions();

      final p = container.read(portfolioProvider).positions.single;
      expect(p.priceDate, DateTime(2026, 10, 5));
      expect(p.priceChangeAmount, 6);
      verifyNever(
        () => mockDb.getRecentPrices(any(), count: any(named: 'count')),
      );
    });

    test('🚨 交易所價差缺(例如上櫃單檔走 FinMind 寫入)→ 以前一筆收盤推回價差', () async {
      final positions = [
        createPosition(id: 1, symbol: '6488', quantity: 100, avgCost: 400),
      ];
      when(
        () => mockDb.getPortfolioPositions(),
      ).thenAnswer((_) async => positions);
      when(() => mockDb.getStocksBatch(any())).thenAnswer(
        (_) async => {'6488': createStock(symbol: '6488', market: 'TPEx')},
      );
      final latest = DailyPriceEntry(
        symbol: '6488',
        date: DateTime(2026, 10, 5),
        close: 420,
      );
      when(
        () => mockDb.getLatestPricesBatch(any()),
      ).thenAnswer((_) async => {'6488': latest});
      when(() => mockDb.getRecentPrices('6488', count: 2)).thenAnswer(
        (_) async => [
          latest,
          DailyPriceEntry(
            symbol: '6488',
            date: DateTime(2026, 10, 2),
            close: 410,
          ),
        ],
      );
      when(
        () => mockDb.getAllPortfolioTransactions(),
      ).thenAnswer((_) async => []);
      stubDividendReads();

      await container.read(portfolioProvider.notifier).loadPositions();

      expect(
        container.read(portfolioProvider).positions.single.priceChangeAmount,
        10,
      );
    });
```

（`createStock({symbol, name, market, industry})` 與 `stubDividendReads()` 都是該檔既有輔助。）

- [ ] **Step 2: 確認紅燈**

Run: `flutter test test/presentation/providers/portfolio_provider_test.dart`
Expected: 編譯失敗（`priceDate`、`priceChangeAmount`、`copyWithPrice`、`positionOf`、`PortfolioState.priceDate` 未定義）

- [ ] **Step 3: 實作**

`lib/presentation/providers/portfolio_provider.dart`：

1. `PortfolioPositionData` 建構子在 `this.currentPrice,` 之後加 `this.priceDate, this.priceChangeAmount,`。欄位在 `currentPrice` 之後加：

```dart

  /// 現價那一筆的日期(合併規則據此判斷是不是今天的正式資料)
  final DateTime? priceDate;

  /// 交易所漲跌價差(金額);昨收 = 現價 − 價差(除權息日即為參考價)。
  /// 交易所沒給時以前一筆收盤推回;都沒有為 null
  final double? priceChangeAmount;

  /// 只換現價(盤中即時報價用);其他欄位不變。市值、未實現損益隨之以新
  /// 價格計算
  PortfolioPositionData copyWithPrice(double? price) => PortfolioPositionData(
    symbol: symbol,
    stockName: stockName,
    market: market,
    quantity: quantity,
    avgCost: avgCost,
    realizedPnl: realizedPnl,
    totalDividendReceived: totalDividendReceived,
    currentPrice: price,
    priceDate: priceDate,
    priceChangeAmount: priceChangeAmount,
  );
```

2. `PortfolioState` 在 `summary` getter 之前加：

```dart
  /// 依代號找持股;沒有回 null
  PortfolioPositionData? positionOf(String symbol) {
    for (final p in positions) {
      if (p.symbol == symbol) return p;
    }
    return null;
  }

  /// 在倉持股價格日期的最大值(績效、配置、股利的資料日期);沒有為 null
  DateTime? get priceDate {
    DateTime? latest;
    for (final p in positions) {
      final d = p.priceDate;
      if (p.quantity <= 0 || d == null) continue;
      if (latest == null || d.isAfter(latest)) latest = d;
    }
    return latest;
  }
```

3. `loadPositions`：在 `final List<PortfolioPositionData> positionData = [];` 之前加：

```dart
      // 交易所漲跌價差缺(例如上櫃單檔改走 FinMind 寫入)時,以前一筆收盤
      // 推回價差:今日損益要「收盤 − 價差」當昨收
      final previousCloses = await _previousCloses(pricesResult);
      if (!_active) return;
```

   `PortfolioPositionData(` 在 `currentPrice: price?.close,` 之後加：

```dart
            priceDate: price?.date,
            priceChangeAmount:
                price?.priceChange ??
                switch ((price?.close, previousCloses[pos.symbol])) {
                  (final close?, final previous?) => close - previous,
                  _ => null,
                },
```

   在 `loadPositions` 之後加：

```dart
  /// 價差缺的持股:取資料庫裡前一筆收盤(代號 → 收盤)。前一筆的日期要早於
  /// 最新那一筆,否則不算
  Future<Map<String, double>> _previousCloses(
    Map<String, DailyPriceEntry> latest,
  ) async {
    final missing = [
      for (final MapEntry(key: symbol, value: price) in latest.entries)
        if (price.close != null && price.priceChange == null) symbol,
    ];
    final recents = await Future.wait([
      for (final symbol in missing) _db.getRecentPrices(symbol, count: 2),
    ]);
    return {
      for (var i = 0; i < missing.length; i++)
        if (recents[i] case [final first, final second, ...]
            when second.close != null &&
                second.date.isBefore(first.date) &&
                DateContext.isSameDay(first.date, latest[missing[i]]!.date))
          missing[i]: second.close!,
    };
  }
```

（`DailyPriceEntry` 由已 import 的 `app_database.dart` 匯出；`pricesResult` 是 `getLatestPricesBatch` 回傳的 `Map<String, DailyPriceEntry>`。檔頭加 `import 'package:daredevil/core/utils/date_context.dart';`，這個檔原本沒有。）

- [ ] **Step 4: 確認通過**

Run: `flutter test test/presentation/providers/portfolio_provider_test.dart test/presentation/screens/portfolio/ test/domain/services/portfolio_analytics_service_test.dart`
Expected: 全部 PASS（既有測試在 `setUp` 的 `getRecentPrices` 預設下行為不變）

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 5: 記錄進度**（不 commit）

---

### Task 5: 今日損益規則

**Files:**
- Create: `lib/domain/services/live_quote/today_pnl.dart`
- Test: `test/domain/services/live_quote/today_pnl_test.dart`（新）

**Interfaces:**
- Consumes：`MergedPrice`、`MergedPriceKind`、`LiveQuoteLabel`、`MarketPhase`。
- Produces：
  - `class TodayPnl { double amount; int missingCount; bool includesNonClosing; }`。
  - `TodayPnlRule.compute(Iterable<({double quantity, MergedPrice merged})> holdings, {required MarketPhase phase}) → TodayPnl?`。

- [ ] **Step 1: 寫失敗測試**

建立 `test/domain/services/live_quote/today_pnl_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/domain/models/live_quote.dart';
import 'package:daredevil/domain/services/live_quote/live_quote_merge.dart';
import 'package:daredevil/domain/services/live_quote/live_quote_schedule.dart';
import 'package:daredevil/domain/services/live_quote/today_pnl.dart';

/// 今日損益(以昨收計)(2026-10-06,spec §7「今日損益」)。
void main() {
  final morning = DateTime(2026, 10, 6, 10, 15);
  final afterClose = DateTime(2026, 10, 6, 14, 10);

  MergedPrice live(
    double price, {
    double prev = 100,
    DateTime? now,
    bool closing = false,
    String time = '10:14:50',
  }) => LiveQuoteMerge.merge(
    official: OfficialPrice(date: DateTime(2026, 10, 5), close: prev),
    live: LiveQuoteEntry(
      symbol: 'A',
      date: DateTime(2026, 10, 6),
      price: price,
      displaySource: LiveDisplaySource.trade,
      previousClose: prev,
      quoteTime: time,
      isClosingQuote: closing,
    ),
    now: now ?? morning,
  );

  MergedPrice official(double close, double? change, {DateTime? date}) =>
      LiveQuoteMerge.merge(
        official: OfficialPrice(
          date: date ?? DateTime(2026, 10, 6),
          close: close,
          priceChange: change,
        ),
        live: null,
        now: afterClose,
      );

  MergedPrice yesterdayOnly() => LiveQuoteMerge.merge(
    official: OfficialPrice(date: DateTime(2026, 10, 5), close: 100),
    live: null,
    now: morning,
  );

  test('🚨 盤中:各持股股數 ×(即時價 − MIS 昨收)之和', () {
    final r = TodayPnlRule.compute([
      (quantity: 1000, merged: live(102)),
      (quantity: 500, merged: live(98)),
    ], phase: MarketPhase.open)!;
    expect(r.amount, closeTo(1000 * 2 + 500 * -2, 1e-9));
    expect(r.missingCount, 0);
    expect(r.includesNonClosing, isFalse);
  });

  test('🚨 沒有今天價格的持股不當 0、不默默略過:計數「無報價未計入」', () {
    final r = TodayPnlRule.compute([
      (quantity: 1000, merged: live(102)),
      (quantity: 300, merged: yesterdayOnly()),
    ], phase: MarketPhase.open)!;
    expect(r.amount, closeTo(2000, 1e-9));
    expect(r.missingCount, 1);
  });

  test('全部沒有今天價格 → 金額 0、計數全部(仍顯示,讓人知道沒算到)', () {
    final r = TodayPnlRule.compute([
      (quantity: 1000, merged: yesterdayOnly()),
    ], phase: MarketPhase.open)!;
    expect(r.amount, 0);
    expect(r.missingCount, 1);
  });

  test('🚨 盤後資料寫入後:昨收 = 收盤 − 交易所價差(除權息日即為參考價)', () {
    // 除息 3 元:前一日收 103、參考價 100、今日收 101,價差 +1
    final r = TodayPnlRule.compute([
      (quantity: 1000, merged: official(101, 1)),
    ], phase: MarketPhase.afterClose)!;
    expect(r.amount, closeTo(1000, 1e-9), reason: '不可用 103 當昨收而少掉股利');
  });

  test('正式資料沒有價差(推不回昨收)→ 計數無報價', () {
    final r = TodayPnlRule.compute([
      (quantity: 1000, merged: official(101, null)),
    ], phase: MarketPhase.afterClose)!;
    expect(r.missingCount, 1);
  });

  test('🚨 收盤後有持股用非收盤報價 → 標「含未收盤報價」;都是收盤報價則不標', () {
    final withNonClosing = TodayPnlRule.compute([
      (quantity: 1, merged: live(101, now: afterClose, closing: true, time: '13:30:00')),
      (quantity: 1, merged: live(99, now: afterClose, time: '13:29:40')),
    ], phase: MarketPhase.afterClose)!;
    expect(withNonClosing.includesNonClosing, isTrue);

    final allClosing = TodayPnlRule.compute([
      (quantity: 1, merged: live(101, now: afterClose, closing: true, time: '13:30:00')),
    ], phase: MarketPhase.afterClose)!;
    expect(allClosing.includesNonClosing, isFalse);
  });

  test('🚨 非交易日、盤前不顯示', () {
    final holdings = [(quantity: 1000.0, merged: live(102))];
    expect(TodayPnlRule.compute(holdings, phase: MarketPhase.closed), isNull);
    expect(TodayPnlRule.compute(holdings, phase: MarketPhase.preOpen), isNull);
  });

  test('已平倉(股數 0)不計;沒有在倉持股 → 不顯示', () {
    expect(
      TodayPnlRule.compute([
        (quantity: 0, merged: yesterdayOnly()),
      ], phase: MarketPhase.open),
      isNull,
    );
    final r = TodayPnlRule.compute([
      (quantity: 0, merged: yesterdayOnly()),
      (quantity: 10, merged: live(101)),
    ], phase: MarketPhase.open)!;
    expect(r.missingCount, 0);
    expect(r.amount, closeTo(10, 1e-9));
  });
}
```

- [ ] **Step 2: 確認紅燈**

Run: `flutter test test/domain/services/live_quote/today_pnl_test.dart`
Expected: 編譯失敗（`today_pnl.dart` 不存在）

- [ ] **Step 3: 實作**

建立 `lib/domain/services/live_quote/today_pnl.dart`：

```dart
import 'package:flutter/foundation.dart' show immutable;

import 'package:daredevil/domain/services/live_quote/live_quote_merge.dart';
import 'package:daredevil/domain/services/live_quote/live_quote_schedule.dart';

/// 今日損益(以昨收計)的計算結果
@immutable
class TodayPnl {
  const TodayPnl({
    required this.amount,
    required this.missingCount,
    required this.includesNonClosing,
  });

  /// 已計入的持股:股數 ×(顯示價 − 昨收)之和
  final double amount;

  /// 沒有今天有效價格(或推不回昨收)而未計入的在倉持股數
  final int missingCount;

  /// 收盤後有持股用的是非收盤的「最後報價」
  final bool includesNonClosing;
}

/// 今日損益(以昨收計)的規則(spec §7「今日損益」,純函式)
abstract final class TodayPnlRule {
  /// 依各持股的合併結果計算今日損益;非交易日、盤前或沒有在倉持股時回
  /// null(不顯示)。
  ///
  /// - 用即時報價:昨收 = MIS 的昨收;
  /// - 用今天的正式資料:昨收 = 收盤 − 交易所漲跌價差(除權息日即為參考價);
  /// - 沒有今天的價格(合併結果退回原本的資料)或推不回昨收:不當 0、不默默
  ///   略過,計入 [TodayPnl.missingCount]。
  static TodayPnl? compute(
    Iterable<({double quantity, MergedPrice merged})> holdings, {
    required MarketPhase phase,
  }) {
    if (phase == MarketPhase.closed || phase == MarketPhase.preOpen) {
      return null;
    }
    var amount = 0.0;
    var missing = 0;
    var nonClosing = false;
    var held = false;
    for (final (:quantity, :merged) in holdings) {
      if (quantity <= 0) continue;
      held = true;
      final price = merged.price;
      final previous = merged.previousClose;
      if (merged.kind == MergedPriceKind.fallback ||
          price == null ||
          previous == null) {
        missing++;
        continue;
      }
      amount += quantity * (price - previous);
      if (merged.label == LiveQuoteLabel.lastQuote) nonClosing = true;
    }
    if (!held) return null;
    return TodayPnl(
      amount: amount,
      missingCount: missing,
      includesNonClosing: nonClosing,
    );
  }
}
```

- [ ] **Step 4: 確認通過**

Run: `flutter test test/domain/services/live_quote/ test/domain/domain_layer_purity_test.dart`
Expected: 全部 PASS（domain 不 import presentation）

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 5: 記錄進度**（不 commit）

---

### Task 6: 投資組合的合併後價格與即時總覽

**Files:**
- Create: `lib/presentation/providers/portfolio_live_provider.dart`
- Test: `test/presentation/providers/portfolio_live_provider_test.dart`（新）

**Interfaces:**
- Consumes：
  - Task 4 的 `PortfolioPositionData.priceDate`／`priceChangeAmount`／`copyWithPrice`、`PortfolioState.positionOf`；
  - Task 5 的 `TodayPnlRule`、`TodayPnl`；
  - `LiveQuoteMerge`、`liveQuoteCenterProvider`、`liveQuoteBoundaryProvider`、`appClockProvider`、`LiveQuoteSchedule.phaseAt`、`LiveQuoteStatusRule`。
- Produces：
  - `final portfolioLivePriceProvider = Provider.autoDispose.family<MergedPrice?, String>`。
  - `class PortfolioLive { List<PortfolioPositionData> positions; PortfolioSummary summary; TodayPnl? todayPnl; String? status; }`。
  - `final portfolioLiveProvider = Provider.autoDispose<PortfolioLive>`。
  - `List<LiveQuoteRegistration> portfolioRegistrations(Iterable<PortfolioPositionData> positions, DateTime now)`。

- [ ] **Step 1: 寫失敗測試**

建立 `test/presentation/providers/portfolio_live_provider_test.dart`：

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/constants/market_codes.dart';
import 'package:daredevil/core/utils/clock.dart';
import 'package:daredevil/domain/models/live_quote.dart';
import 'package:daredevil/domain/services/live_quote/live_quote_merge.dart';
import 'package:daredevil/presentation/providers/live_quote_provider.dart';
import 'package:daredevil/presentation/providers/portfolio_live_provider.dart';
import 'package:daredevil/presentation/providers/portfolio_provider.dart';
import 'package:daredevil/presentation/providers/providers.dart';

class _Clock implements AppClock {
  _Clock(this.value);
  final DateTime value;
  @override
  DateTime now() => value;
}

class _SeededPortfolio extends PortfolioNotifier {
  _SeededPortfolio(this.seed);
  final PortfolioState seed;
  @override
  PortfolioState build() => seed;
}

class _FixedCenter extends LiveQuoteCenter {
  _FixedCenter(this.initial);
  final LiveQuoteState initial;
  @override
  LiveQuoteState build() => initial;
}

/// 投資組合的合併後價格與即時總覽(2026-10-06,spec §5、§7「投資組合」)。
void main() {
  final morning = DateTime(2026, 10, 6, 10, 15);

  PortfolioPositionData position(
    String symbol, {
    double quantity = 1000,
    double avgCost = 500,
    double? price = 600,
    DateTime? date,
    double? change = 6,
    String? market = MarketCode.twse,
  }) => PortfolioPositionData(
    symbol: symbol,
    market: market,
    quantity: quantity,
    avgCost: avgCost,
    realizedPnl: 0,
    totalDividendReceived: 0,
    currentPrice: price,
    priceDate: date ?? DateTime(2026, 10, 5),
    priceChangeAmount: change,
  );

  LiveQuoteEntry quote(String symbol, double price, {double prev = 600}) =>
      LiveQuoteEntry(
        symbol: symbol,
        date: DateTime(2026, 10, 6),
        price: price,
        displaySource: LiveDisplaySource.trade,
        previousClose: prev,
        quoteTime: '10:14:50',
        isClosingQuote: false,
      );

  ProviderContainer container(
    List<PortfolioPositionData> positions,
    LiveQuoteState live, {
    DateTime? now,
  }) {
    final c = ProviderContainer(
      overrides: [
        appClockProvider.overrideWithValue(_Clock(now ?? morning)),
        portfolioProvider.overrideWith(
          () => _SeededPortfolio(PortfolioState(positions: positions)),
        ),
        liveQuoteCenterProvider.overrideWith(() => _FixedCenter(live)),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  test('🚨 正式資料是昨天、有今天的即時 → 每檔用即時價', () {
    final c = container(
      [position('2330')],
      LiveQuoteState(entries: {'2330': quote('2330', 612)}),
    );
    final m = c.read(portfolioLivePriceProvider('2330'))!;
    expect(m.kind, MergedPriceKind.live);
    expect(m.price, 612);
    expect(c.read(portfolioLivePriceProvider('9999')), isNull);
  });

  test('🚨 即時總覽:總市值、未實現損益用即時價;今日損益以昨收計', () {
    final c = container(
      [position('2330'), position('2317', quantity: 2000, avgCost: 100, price: 120, change: 1)],
      LiveQuoteState(
        entries: {
          '2330': quote('2330', 612),
          '2317': quote('2317', 118, prev: 120),
        },
      ),
    );
    final live = c.read(portfolioLiveProvider);
    expect(live.summary.totalMarketValue, closeTo(1000 * 612 + 2000 * 118, 1e-6));
    expect(
      live.summary.totalUnrealizedPnl,
      closeTo(1000 * 112 + 2000 * 18, 1e-6),
    );
    expect(live.todayPnl!.amount, closeTo(1000 * 12 + 2000 * -2, 1e-6));
    expect(live.todayPnl!.missingCount, 0);
    expect(live.positions.first.currentPrice, 612);
  });

  test('🚨 有一檔沒有今天的價格 → 總市值照用原本資料(不當 0);今日損益計數未計入', () {
    final c = container(
      [position('2330'), position('6488', quantity: 100, avgCost: 400, price: 420, change: 5)],
      LiveQuoteState(entries: {'2330': quote('2330', 612)}),
    );
    final live = c.read(portfolioLiveProvider);
    expect(live.summary.totalMarketValue, closeTo(1000 * 612 + 100 * 420, 1e-6));
    expect(live.todayPnl!.missingCount, 1);
    expect(live.todayPnl!.amount, closeTo(12000, 1e-6));
  });

  test('非交易日 → 不顯示今日損益', () {
    final c = container(
      [position('2330')],
      const LiveQuoteState(),
      now: DateTime(2026, 10, 10, 11), // 國慶日
    );
    expect(c.read(portfolioLiveProvider).todayPnl, isNull);
  });

  test('盤中有即時 → 狀態為報價時間;全部用正式資料 → 沒有狀態', () {
    final live = container(
      [position('2330')],
      LiveQuoteState(entries: {'2330': quote('2330', 612)}),
    );
    expect(live.read(portfolioLiveProvider).status, 'liveQuote.quoteTime');

    final official = container(
      [position('2330', date: DateTime(2026, 10, 6))],
      const LiveQuoteState(),
      now: DateTime(2026, 10, 6, 15),
    );
    expect(official.read(portfolioLiveProvider).status, isNull);
  });

  test('🚨 登記在倉持股(有市場別);「已有今天正式資料」看價格日期', () {
    final regs = portfolioRegistrations([
      position('2330', date: DateTime(2026, 10, 6)),
      position('2317'),
      position('1101', quantity: 0),
      position('9999', market: null),
    ], morning);
    expect(regs, const [
      LiveQuoteRegistration(
        symbol: '2330',
        market: MarketCode.twse,
        hasOfficialToday: true,
      ),
      LiveQuoteRegistration(symbol: '2317', market: MarketCode.twse),
    ]);
  });
}
```

- [ ] **Step 2: 確認紅燈**

Run: `flutter test test/presentation/providers/portfolio_live_provider_test.dart`
Expected: 編譯失敗（`portfolio_live_provider.dart` 不存在）

- [ ] **Step 3: 實作**

建立 `lib/presentation/providers/portfolio_live_provider.dart`：

```dart
import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:daredevil/core/utils/date_context.dart';
import 'package:daredevil/domain/services/live_quote/live_quote_merge.dart';
import 'package:daredevil/domain/services/live_quote/live_quote_schedule.dart';
import 'package:daredevil/domain/services/live_quote/today_pnl.dart';
import 'package:daredevil/presentation/providers/live_price_provider.dart';
import 'package:daredevil/presentation/providers/live_quote_provider.dart';
import 'package:daredevil/presentation/providers/portfolio_provider.dart';
import 'package:daredevil/presentation/providers/providers.dart';
import 'package:daredevil/presentation/widgets/live_quote_status.dart';

/// 持股某一檔要顯示的價格(依合併規則;正式資料 = 該檔最新一筆)。持股列、
/// 總覽、持股詳情共用同一個結果。不在持股裡回 null
final portfolioLivePriceProvider = Provider.autoDispose
    .family<MergedPrice?, String>((ref, symbol) {
      ref.watch(liveQuoteBoundaryProvider);
      final official = ref.watch(
        portfolioProvider.select((s) {
          final p = s.positionOf(symbol);
          return p == null
              ? null
              : OfficialPrice(
                  date: p.priceDate,
                  close: p.currentPrice,
                  priceChange: p.priceChangeAmount,
                );
        }),
      );
      if (official == null) return null;
      final live = ref.watch(
        liveQuoteCenterProvider.select((s) => s.entries[symbol]),
      );
      return LiveQuoteMerge.merge(
        official: official,
        live: live,
        now: ref.read(appClockProvider).now(),
      );
    });

/// 投資組合的即時總覽
@immutable
class PortfolioLive {
  const PortfolioLive({
    required this.positions,
    required this.summary,
    this.todayPnl,
    this.status,
  });

  /// 持股(現價換成合併後的價格,順序同 `PortfolioState.positions`)
  final List<PortfolioPositionData> positions;

  /// 以 [positions] 計算的總市值、總損益等(同 `PortfolioState.summary` 的算法)
  final PortfolioSummary summary;

  /// 今日損益(以昨收計);非交易日、盤前為 null
  final TodayPnl? todayPnl;

  /// 持倉標題列的報價狀態(已翻譯);沒有為 null
  final String? status;
}

/// 投資組合的即時總覽。績效、配置、股利不走這裡,維持盤後(spec §7)
final portfolioLiveProvider = Provider.autoDispose<PortfolioLive>((ref) {
  ref.watch(liveQuoteBoundaryProvider);
  final positions = ref.watch(portfolioProvider.select((s) => s.positions));
  final center = ref.watch(liveQuoteCenterProvider);
  final now = ref.read(appClockProvider).now();
  final merged = <String, MergedPrice>{
    for (final p in positions)
      if (ref.watch(portfolioLivePriceProvider(p.symbol)) case final m?)
        p.symbol: m,
  };
  final livePositions = [
    for (final p in positions)
      if (merged[p.symbol] case final m?) p.copyWithPrice(m.price) else p,
  ];
  return PortfolioLive(
    positions: livePositions,
    summary: PortfolioState(positions: livePositions).summary,
    todayPnl: TodayPnlRule.compute([
      for (final p in positions)
        if (merged[p.symbol] case final m?) (quantity: p.quantity, merged: m),
    ], phase: LiveQuoteSchedule.phaseAt(now)),
    status: LiveQuoteStatusRule.header(
      state: center,
      merged: merged.values,
      intradayTime: null,
    )?.text(),
  );
});

/// 投資組合與持股詳情登記的股票:在倉、有市場別;「已有今天正式資料」看
/// 價格日期是不是今天
List<LiveQuoteRegistration> portfolioRegistrations(
  Iterable<PortfolioPositionData> positions,
  DateTime now,
) => [
  for (final p in positions)
    if (p.quantity > 0)
      if (p.market case final market?)
        LiveQuoteRegistration(
          symbol: p.symbol,
          market: market,
          hasOfficialToday:
              p.priceDate != null && DateContext.isSameDay(p.priceDate!, now),
        ),
];
```

- [ ] **Step 4: 確認通過**

Run: `flutter test test/presentation/providers/portfolio_live_provider_test.dart test/presentation/providers/portfolio_provider_test.dart`
Expected: 全部 PASS

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 5: 記錄進度**（不 commit）

---

### Task 7: 投資組合頁接上即時報價

**Files:**
- Modify: `lib/presentation/screens/portfolio/widgets/position_card.dart`
- Modify: `lib/presentation/screens/portfolio/widgets/portfolio_summary_card.dart`
- Modify: `lib/presentation/screens/portfolio/portfolio_tab.dart`
- Modify: `assets/translations/zh-TW.json`、`en.json`（`portfolio.todayPnl`、`todayPnlMissing`、`todayPnlNonClosing`、`postMarketAsOf`）
- Test: `test/presentation/screens/portfolio/widgets/position_card_test.dart`、`portfolio_summary_card_test.dart`、`test/presentation/screens/portfolio/portfolio_tab_test.dart`

**Interfaces:**
- Consumes：Task 6 的 `portfolioLiveProvider`、`portfolioLivePriceProvider`、`portfolioRegistrations`、`PortfolioLive`；Task 5 的 `TodayPnl`；第 2 段的 `PriceFlash`、`LiveQuoteScope`、`LiveQuoteStatusRule.card`、`liveQuoteBoundaryProvider`。
- Produces：
  - `class PositionCardLive { LiveQuoteFlash? flash; bool flashEnabled; String? caption; }`。
  - `PositionCard({..., PositionCardLive? live})`。
  - `PortfolioSummaryCard({required PortfolioSummary summary, TodayPnl? todayPnl})`。

- [ ] **Step 1: 寫失敗測試**

1. `test/presentation/screens/portfolio/widgets/position_card_test.dart`：
   - import 加：

```dart
import 'package:daredevil/core/theme/color_contrast.dart';
import 'package:daredevil/domain/models/live_quote.dart';
import 'package:daredevil/presentation/widgets/price_flash.dart';
```

（已有的不重複加。）

   - 在 `main()` 最後加（`PortfolioPositionData` 直接建構）：

```dart
  group('盤中即時報價', () {
    PortfolioPositionData p() => const PortfolioPositionData(
      symbol: '2330',
      stockName: '台積電',
      quantity: 1000,
      avgCost: 500,
      realizedPnl: 0,
      totalDividendReceived: 0,
      currentPrice: 612,
    );

    testWidgets('例外標示顯示在卡片上', (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          PositionCard(
            position: p(),
            live: const PositionCardLive(caption: 'liveQuote.cardPaused'),
            onTap: () {},
          ),
        ),
      );
      expect(find.text('liveQuote.cardPaused'), findsOneWidget);
    });

    for (final brightness in [Brightness.light, Brightness.dark]) {
      testWidgets('🚨 現價閃色最濃時 $brightness:對卡片實際底色 ≥ 4.5', (tester) async {
        Widget card(int id) => buildTestApp(
          PositionCard(
            position: p(),
            live: PositionCardLive(flash: LiveQuoteFlash(id: id, up: false)),
            onTap: () {},
          ),
          brightness: brightness,
        );
        await tester.pumpWidget(card(1));
        await tester.pumpWidget(card(2));
        await tester.pump();

        final tint =
            (tester.widget<DecoratedBox>(find.byKey(PriceFlash.tintKey)).decoration
                    as BoxDecoration)
                .color!;
        final cardColor = Theme.of(
          tester.element(find.byKey(PriceFlash.tintKey)),
        ).colorScheme.surfaceContainerLow;
        final text = tester
            .widget<RichText>(
              find.descendant(
                of: find.byKey(PriceFlash.tintKey),
                matching: find.byType(RichText),
              ),
            )
            .text
            .style!
            .color!;
        expect(
          ColorContrast.ratio(
            text,
            ColorContrast.compositeOver(
              tint.withValues(alpha: 1),
              cardColor,
              tint.a,
            ),
          ),
          greaterThanOrEqualTo(4.5),
        );
      });

      testWidgets('🚨 例外標示灰字 $brightness:對卡片實際底色 ≥ 4.5', (tester) async {
        await tester.pumpWidget(
          buildTestApp(
            PositionCard(
              position: p(),
              live: const PositionCardLive(caption: 'liveQuote.cardPaused'),
              onTap: () {},
            ),
            brightness: brightness,
          ),
        );
        final text = tester
            .widget<Text>(find.text('liveQuote.cardPaused'))
            .style!
            .color!;
        final cardColor = Theme.of(
          tester.element(find.text('liveQuote.cardPaused')),
        ).colorScheme.surfaceContainerLow;
        expect(ColorContrast.ratio(text, cardColor), greaterThanOrEqualTo(4.5));
      });
    }
  });
```

（持股卡片的底色是 `colorScheme.surfaceContainerLow` 的不透明 `Container`。）

2. `test/presentation/screens/portfolio/widgets/portfolio_summary_card_test.dart`：
   - import 加 `import 'package:daredevil/domain/services/live_quote/today_pnl.dart';`。
   - 在 `main()` 最後加（`PortfolioSummary` 照該檔既有寫法建構；這裡直接建構）：

```dart
  group('今日損益(以昨收計)', () {
    const summary = PortfolioSummary(
      totalMarketValue: 1000000,
      totalCostBasis: 900000,
      totalUnrealizedPnl: 100000,
      totalRealizedPnl: 0,
      totalDividends: 0,
      positionCount: 2,
    );

    testWidgets('有今日損益 → 顯示一列', (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          const PortfolioSummaryCard(
            summary: summary,
            todayPnl: TodayPnl(
              amount: 12000,
              missingCount: 0,
              includesNonClosing: false,
            ),
          ),
        ),
      );
      expect(find.text('portfolio.todayPnl'), findsOneWidget);
      expect(find.text('portfolio.todayPnlMissing'), findsNothing);
      expect(find.text('portfolio.todayPnlNonClosing'), findsNothing);
    });

    testWidgets('🚨 有未計入的持股與非收盤報價 → 兩個標示都在', (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          const PortfolioSummaryCard(
            summary: summary,
            todayPnl: TodayPnl(
              amount: 12000,
              missingCount: 1,
              includesNonClosing: true,
            ),
          ),
        ),
      );
      expect(
        find.textContaining('portfolio.todayPnlMissing'),
        findsOneWidget,
      );
      expect(
        find.textContaining('portfolio.todayPnlNonClosing'),
        findsOneWidget,
      );
    });

    testWidgets('沒有今日損益(非交易日、盤前)→ 不顯示', (tester) async {
      await tester.pumpWidget(
        buildTestApp(const PortfolioSummaryCard(summary: summary)),
      );
      expect(find.text('portfolio.todayPnl'), findsNothing);
    });
  });
```

3. `test/presentation/screens/portfolio/portfolio_tab_test.dart`：
   - import 加：

```dart
import 'package:daredevil/core/constants/market_codes.dart';
import 'package:daredevil/core/utils/clock.dart';
import 'package:daredevil/domain/models/live_quote.dart';
import 'package:daredevil/presentation/providers/live_quote_provider.dart';
import 'package:daredevil/presentation/providers/providers.dart';
import 'package:daredevil/presentation/screens/portfolio/widgets/allocation_pie_chart.dart';
import 'package:daredevil/presentation/screens/portfolio/widgets/portfolio_summary_card.dart';
```

   - `createPosition` 加參數 `String? market = MarketCode.twse, DateTime? priceDate, double? priceChangeAmount,`，傳進 `PortfolioPositionData(...)`。
   - 檔尾加：

```dart

class _Clock implements AppClock {
  _Clock(this.value);
  final DateTime value;
  @override
  DateTime now() => value;
}

/// 記錄登記、不發請求的報價中心
class _LiveCenter extends LiveQuoteCenter {
  _LiveCenter(this.initial);
  final LiveQuoteState initial;
  final registered = <Object, List<LiveQuoteRegistration>>{};

  @override
  LiveQuoteState build() => initial;

  @override
  void register(Object owner, List<LiveQuoteRegistration> entries) =>
      registered[owner] = entries;

  @override
  void unregister(Object owner) => registered.remove(owner);

  @override
  void setAppVisible(bool visible) {}
}
```
   - `buildTestWidget` 加參數 `_LiveCenter? liveCenter, DateTime? now,`。`overrides` 最後加 `if (now != null) appClockProvider.overrideWithValue(_Clock(now)),`，`brightness: brightness,` 之後加 `liveQuoteCenter: liveCenter == null ? null : () => liveCenter,`。
   - 在 `main()` 最後加：

```dart
  group('盤中即時報價', () {
    final morning = DateTime(2026, 10, 6, 10, 15);
    // 兩檔:只有 2330 有即時——配置比例若誤用即時價就會變(一檔時永遠 100%,
    // 測不出來)
    final state = PortfolioState(
      positions: [
        createPosition(
          priceDate: DateTime(2026, 10, 5),
          priceChangeAmount: 6,
        ),
        createPosition(
          symbol: '2317',
          stockName: '鴻海',
          avgCost: 90,
          currentPrice: 100,
          priceDate: DateTime(2026, 10, 5),
          priceChangeAmount: 1,
        ),
      ],
    );
    LiveQuoteEntry quote(double price) => LiveQuoteEntry(
      symbol: '2330',
      date: DateTime(2026, 10, 6),
      price: price,
      displaySource: LiveDisplaySource.trade,
      previousClose: 600,
      quoteTime: '10:14:50',
      isClosingQuote: false,
    );

    testWidgets('🚨 登記在倉持股', (tester) async {
      widenViewport(tester);
      final center = _LiveCenter(const LiveQuoteState());
      await tester.pumpWidget(
        buildTestWidget(portfolioState: state, liveCenter: center, now: morning),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(center.registered.values.single, const [
        LiveQuoteRegistration(symbol: '2330', market: MarketCode.twse),
        LiveQuoteRegistration(symbol: '2317', market: MarketCode.twse),
      ]);
    });

    testWidgets('🚨 總覽用即時價;配置圓餅維持盤後', (tester) async {
      widenViewport(tester);
      final center = _LiveCenter(LiveQuoteState(entries: {'2330': quote(612)}));
      await tester.pumpWidget(
        buildTestWidget(portfolioState: state, liveCenter: center, now: morning),
      );
      await tester.pump(const Duration(seconds: 1));

      final summary = tester
          .widget<PortfolioSummaryCard>(find.byType(PortfolioSummaryCard))
          .summary;
      expect(summary.totalMarketValue, closeTo(612000 + 100000, 1e-6));
      final today = tester
          .widget<PortfolioSummaryCard>(find.byType(PortfolioSummaryCard))
          .todayPnl!;
      expect(today.amount, closeTo(12000, 1e-6));
      expect(today.missingCount, 1, reason: '2317 沒有今天的價格');
      final pie = tester.widget<AllocationPieChart>(
        find.byType(AllocationPieChart),
      );
      expect(pie.allocationMap, state.allocationMap, reason: '圓餅維持盤後');
      expect(find.textContaining('612'), findsWidgets);
    });

    testWidgets('盤後卡片的資料日期說明', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(
        buildTestWidget(portfolioState: state, now: morning),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(find.textContaining('portfolio.postMarketAsOf'), findsOneWidget);
    });

    testWidgets('持倉標題列顯示報價狀態', (tester) async {
      widenViewport(tester);
      final center = _LiveCenter(LiveQuoteState(entries: {'2330': quote(612)}));
      await tester.pumpWidget(
        buildTestWidget(portfolioState: state, liveCenter: center, now: morning),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('liveQuote.quoteTime'), findsOneWidget);
    });
  });
```

- [ ] **Step 2: 確認紅燈**

Run: `flutter test test/presentation/screens/portfolio/`
Expected: 編譯失敗（`PositionCardLive`、`PositionCard.live`、`PortfolioSummaryCard.todayPnl` 未定義）

- [ ] **Step 3: 實作**

1. `lib/presentation/screens/portfolio/widgets/position_card.dart`：
   - import 加：

```dart
import 'package:flutter/foundation.dart' show immutable;

import 'package:daredevil/domain/models/live_quote.dart';
import 'package:daredevil/presentation/widgets/price_flash.dart';
```

   - 在 `class PositionCard` 之前加：

```dart
/// 持股卡片上與盤中即時報價有關的資料;null = 盤後行為
@immutable
class PositionCardLive {
  const PositionCardLive({this.flash, this.flashEnabled = true, this.caption});

  /// 本輪閃色事件(只閃現價)
  final LiveQuoteFlash? flash;

  /// 設定頁「價格閃色」
  final bool flashEnabled;

  /// 例外標示(已翻譯):報價暫停／無報價／最後報價 HH:MM:SS
  final String? caption;
}

```

   - 建構子改成 `const PositionCard({super.key, required this.position, required this.onTap, this.live});`，欄位加 `final PositionCardLive? live;`。
   - 均價／現價那個 `Text(...)` 換成：

```dart
                  Wrap(
                    spacing: DesignTokens.spacing8,
                    children: [
                      Text(
                        '${'portfolio.avgCost'.tr()}: ${AppNumberFormat.currency(position.avgCost, decimals: 1)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                      // 現價用一般文字色:閃色時疊在紅綠底上,灰字對比不夠
                      PriceFlash(
                        flash: live?.flash,
                        enabled: live?.flashEnabled ?? true,
                        child: Text(
                          '${'portfolio.currentPrice'.tr()}: ${AppNumberFormat.currency(position.currentPrice ?? 0, decimals: 1)}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (live?.caption case final caption?) ...[
                    const SizedBox(height: DesignTokens.spacing2),
                    Text(
                      caption,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
```

2. `lib/presentation/screens/portfolio/widgets/portfolio_summary_card.dart`：
   - import 加 `import 'package:daredevil/domain/services/live_quote/today_pnl.dart';`。
   - 建構子改成 `const PortfolioSummaryCard({super.key, required this.summary, this.todayPnl});`，欄位加：

```dart

  /// 今日損益(以昨收計);null = 不顯示(非交易日、盤前或盤後行為)
  final TodayPnl? todayPnl;
```

   - 「總損益」那個 `Row(...)` 之後、缺價警示 `if (summary.unpricedCount > 0) ...[` 之前加：

```dart
          if (todayPnl case final today?) ..._buildTodayPnl(
            theme,
            locale,
            today,
          ),
```

   - 在 `_formatNumber` 之前加：

```dart
  List<Widget> _buildTodayPnl(ThemeData theme, Locale locale, TodayPnl today) {
    final rounded = AppNumberFormat.roundForDisplay(today.amount, 0);
    final color = rounded == 0
        ? theme.colorScheme.onSurface
        : (rounded > 0 ? AppTheme.upColor : AppTheme.downColor);
    final notes = [
      if (today.includesNonClosing) 'portfolio.todayPnlNonClosing'.tr(),
      if (today.missingCount > 0)
        'portfolio.todayPnlMissing'.tr(
          namedArgs: {'count': '${today.missingCount}'},
        ),
    ];
    return [
      const SizedBox(height: DesignTokens.spacing4),
      Row(
        children: [
          Text(
            'portfolio.todayPnl'.tr(),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
          const SizedBox(width: DesignTokens.spacing8),
          Text(
            '${rounded > 0 ? "+" : ""}NT\$${_formatNumber(today.amount, locale)}',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
      if (notes.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: DesignTokens.spacing2),
          child: Text(
            notes.join('・'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
    ];
  }
```

3. `lib/presentation/screens/portfolio/portfolio_tab.dart`：
   - import 加：

```dart
import 'package:daredevil/domain/services/live_quote/live_quote_merge.dart';
import 'package:daredevil/presentation/providers/live_price_provider.dart';
import 'package:daredevil/presentation/providers/live_quote_provider.dart';
import 'package:daredevil/presentation/providers/portfolio_live_provider.dart';
import 'package:daredevil/presentation/providers/providers.dart';
import 'package:daredevil/presentation/providers/settings_provider.dart';
import 'package:daredevil/presentation/widgets/live_quote_scope.dart';
import 'package:daredevil/presentation/widgets/live_quote_status.dart';
```

（已有的不重複加。）

   - `build` 裡 `final theme = Theme.of(context);` 之後加：

```dart
    // 登記的「是否已有今天正式資料」跟現在有關:跨過午夜等邊界時重算
    ref.watch(liveQuoteBoundaryProvider);
```

   - `return Stack(` 改成 `return LiveQuoteScope(registrations: portfolioRegistrations(state.positions, ref.read(appClockProvider).now()), child: Stack(`，`Stack(...)` 結尾補一個 `)`。
   - 總覽卡片：`child: PortfolioSummaryCard(summary: state.summary),` 改成：

```dart
                  child: Consumer(
                    builder: (context, ref, _) {
                      final live = ref.watch(portfolioLiveProvider);
                      return PortfolioSummaryCard(
                        summary: live.summary,
                        todayPnl: live.todayPnl,
                      );
                    },
                  ),
```

   - 總覽卡片那個 `SliverPadding` 之後、績效指標卡片之前加：

```dart
              // 績效、配置、股利維持盤後:標資料日期(spec §7)
              if (state.priceDate case final date?)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  sliver: SliverToBoxAdapter(
                    child: Text(
                      'portfolio.postMarketAsOf'.tr(
                        namedArgs: {'date': '${date.month}/${date.day}'},
                      ),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
```

   - 持倉列表標題的 `const Spacer(),` 換成：

```dart
                      Expanded(
                        child: Consumer(
                          builder: (context, ref, _) {
                            final status = ref.watch(
                              portfolioLiveProvider.select((l) => l.status),
                            );
                            if (status == null) return const SizedBox.shrink();
                            return Text(
                              status,
                              textAlign: TextAlign.end,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
```

     （這個檔原本就用數字寫間距，沒有 import `DesignTokens`。）
   - 持倉卡片的 `itemBuilder` 換成：

```dart
                  itemBuilder: (_, i) {
                    final position = state.positions[i];
                    return Padding(
                      // 以代號為 key:清單重排時不把別檔的閃色狀態套到這一列
                      key: ValueKey(position.symbol),
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Consumer(
                        builder: (context, ref, _) {
                          final merged = ref.watch(
                            portfolioLivePriceProvider(position.symbol),
                          );
                          final status = ref.watch(
                            liveQuoteCenterProvider.select(
                              (s) => s.symbolStatus[position.symbol],
                            ),
                          );
                          final flashOn = ref.watch(
                            settingsProvider.select((s) => s.priceFlash),
                          );
                          return PositionCard(
                            position: merged == null
                                ? position
                                : position.copyWithPrice(merged.price),
                            live: merged == null
                                ? null
                                : PositionCardLive(
                                    flash: merged.kind == MergedPriceKind.live
                                        ? merged.live?.flash
                                        : null,
                                    flashEnabled: flashOn,
                                    caption: LiveQuoteStatusRule.card(
                                      status: status,
                                      merged: merged,
                                    )?.text(),
                                  ),
                            onTap: () {
                              HapticFeedback.lightImpact();
                              context.push(
                                AppRoutes.positionDetail(position.symbol),
                              );
                            },
                          );
                        },
                      ),
                    );
                  },
```

4. 翻譯（加引號的 heredoc；逐段 `assert` 只出現一次）：

```bash
python3 - <<'PY'
for path, old, new in [
    ('assets/translations/zh-TW.json',
     '    "unpricedWarning": "{count} 檔缺當日價,以成本價計"\n  },',
     '    "unpricedWarning": "{count} 檔缺當日價,以成本價計",\n'
     '    "todayPnl": "今日損益（以昨收計）",\n'
     '    "todayPnlMissing": "{count} 檔無報價未計入",\n'
     '    "todayPnlNonClosing": "含未收盤報價",\n'
     '    "postMarketAsOf": "績效、配置與股利以 {date} 收盤計"\n  },'),
    ('assets/translations/en.json',
     '    "unpricedWarning": "{count} positions unpriced; valued at cost"\n  },',
     '    "unpricedWarning": "{count} positions unpriced; valued at cost",\n'
     '    "todayPnl": "Today\'s P&L (vs. prev. close)",\n'
     '    "todayPnlMissing": "{count} without quote not included",\n'
     '    "todayPnlNonClosing": "Includes non-closing quotes",\n'
     '    "postMarketAsOf": "Performance, allocation and dividends as of {date} close"\n  },'),
]:
    s = open(path, encoding='utf-8').read()
    assert s.count(old) == 1, (path, s.count(old))
    open(path, 'w', encoding='utf-8').write(s.replace(old, new))
import json
for p in ('assets/translations/zh-TW.json', 'assets/translations/en.json'):
    json.load(open(p, encoding='utf-8'))
print('ok')
PY
```

- [ ] **Step 4: 確認通過**

Run: `flutter test test/presentation/screens/portfolio/ test/presentation/providers/ test/core/l10n/ test/core/theme/`
Expected: 全部 PASS（含 `presentation_color_discipline_test`、文案守門）

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 5: 記錄進度**（不 commit）

---

### Task 8: 持股詳情

**Files:**
- Modify: `lib/presentation/screens/portfolio/position_detail_screen.dart`
- Test: `test/presentation/screens/portfolio/position_detail_screen_test.dart`

**Interfaces:**
- Consumes：Task 6 的 `portfolioLivePriceProvider`、`portfolioRegistrations`；第 2 段的 `PriceFlash`、`LiveQuoteScope`、`LiveQuoteStatusRule.header`、`liveQuoteBoundaryProvider`。

- [ ] **Step 1: 寫失敗測試**

`test/presentation/screens/portfolio/position_detail_screen_test.dart`：
- import 加：

```dart
import 'package:daredevil/core/constants/market_codes.dart';
import 'package:daredevil/core/utils/clock.dart';
import 'package:daredevil/domain/models/live_quote.dart';
import 'package:daredevil/presentation/providers/live_quote_provider.dart';
import 'package:daredevil/presentation/providers/providers.dart';
```

- `createPosition` 加參數 `String? market = MarketCode.twse, DateTime? priceDate, double? priceChangeAmount,`，傳進 `PortfolioPositionData(...)`。
- 檔尾加：

```dart

class _Clock implements AppClock {
  _Clock(this.value);
  final DateTime value;
  @override
  DateTime now() => value;
}

/// 記錄登記、不發請求的報價中心
class _LiveCenter extends LiveQuoteCenter {
  _LiveCenter(this.initial);
  final LiveQuoteState initial;
  final registered = <Object, List<LiveQuoteRegistration>>{};

  @override
  LiveQuoteState build() => initial;

  @override
  void register(Object owner, List<LiveQuoteRegistration> entries) =>
      registered[owner] = entries;

  @override
  void unregister(Object owner) => registered.remove(owner);

  @override
  void setAppVisible(bool visible) {}
}
```
- `buildTestWidget` 的參數在 `String symbol = '2330',` 之後加 `_LiveCenter? liveCenter, DateTime? now,`；`overrides:` 清單最後加 `if (now != null) appClockProvider.overrideWithValue(_Clock(now)),`；`brightness: brightness,` 之後加 `liveQuoteCenter: liveCenter == null ? null : () => liveCenter,`。
- 在 `main()` 最後加：

```dart
  group('盤中即時報價', () {
    final morning = DateTime(2026, 10, 6, 10, 15);

    testWidgets('🚨 登記這一檔;現價、市值、未實現損益用即時價,並顯示報價狀態', (tester) async {
      final center = _LiveCenter(
        LiveQuoteState(
          entries: {
            '2330': LiveQuoteEntry(
              symbol: '2330',
              date: DateTime(2026, 10, 6),
              price: 612,
              displaySource: LiveDisplaySource.trade,
              previousClose: 600,
              quoteTime: '10:14:50',
              isClosingQuote: false,
            ),
          },
        ),
      );
      await tester.pumpWidget(
        buildTestWidget(
          portfolioState: PortfolioState(
            positions: [
              createPosition(
                quantity: 1000,
                avgCost: 500,
                currentPrice: 600,
                priceDate: DateTime(2026, 10, 5),
                priceChangeAmount: 6,
              ),
            ],
          ),
          liveCenter: center,
          now: morning,
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(center.registered.values.single, const [
        LiveQuoteRegistration(symbol: '2330', market: MarketCode.twse),
      ]);
      expect(find.textContaining('612'), findsWidgets);
      expect(find.text('+112000'), findsOneWidget, reason: '(612 − 500) × 1000');
      expect(find.text('liveQuote.quoteTime'), findsOneWidget);
    });
  });
```

（`buildTestWidget` 既有參數為 `portfolioState`、`txList`、`brightness`、`symbol`。未實現損益的格式同該檔既有斷言 `'-100000'`：`signedFixed` 不加千分位，正數帶 `+`。）

- [ ] **Step 2: 確認紅燈**

Run: `flutter test test/presentation/screens/portfolio/position_detail_screen_test.dart`
Expected: FAIL（沒有登記；現價仍是 600、未實現 +100000；沒有狀態文字）

- [ ] **Step 3: 實作**

`lib/presentation/screens/portfolio/position_detail_screen.dart`：

1. import 加：

```dart
import 'package:daredevil/domain/models/live_quote.dart';
import 'package:daredevil/domain/services/live_quote/live_quote_merge.dart';
import 'package:daredevil/presentation/providers/live_price_provider.dart';
import 'package:daredevil/presentation/providers/live_quote_provider.dart';
import 'package:daredevil/presentation/providers/portfolio_live_provider.dart';
import 'package:daredevil/presentation/providers/providers.dart';
import 'package:daredevil/presentation/providers/settings_provider.dart';
import 'package:daredevil/presentation/widgets/live_quote_scope.dart';
import 'package:daredevil/presentation/widgets/live_quote_status.dart';
import 'package:daredevil/presentation/widgets/price_flash.dart';
```

（已有的不重複加。）

2. `build` 裡 `final pos = ...;` 之後加：

```dart
    // 登記的「是否已有今天正式資料」跟現在有關:跨過午夜等邊界時重算
    ref.watch(liveQuoteBoundaryProvider);
    final merged = ref.watch(portfolioLivePriceProvider(symbol));
    final center = ref.watch(liveQuoteCenterProvider);
    final flashOn = ref.watch(settingsProvider.select((s) => s.priceFlash));
    final livePos = pos == null || merged == null
        ? pos
        : pos.copyWithPrice(merged.price);
    final liveFlash = merged?.kind == MergedPriceKind.live
        ? merged?.live?.flash
        : null;
    final statusText = merged == null || merged.kind == MergedPriceKind.official
        ? null
        : LiveQuoteStatusRule.header(
            state: center,
            merged: [merged],
            intradayTime: merged.quoteTime,
          )?.text();
```

3. `body:` 改成 `body: LiveQuoteScope(registrations: pos == null ? const [] : portfolioRegistrations([pos], ref.read(appClockProvider).now()), child: <原本的 body 運算式>)`。
4. `_buildPositionSummary(theme, pos)` 改成 `_buildPositionSummary(theme, livePos!, flash: liveFlash, flashEnabled: flashOn, statusText: statusText)`（這個分支 `pos != null`，`livePos` 也不為 null）。
5. `_buildPositionSummary` 簽名改成：

```dart
  Widget _buildPositionSummary(
    ThemeData theme,
    PortfolioPositionData pos, {
    LiveQuoteFlash? flash,
    bool flashEnabled = true,
    String? statusText,
  }) {
```

6. 現價那個 `_InfoTile(` 加 `flash: flash, flashEnabled: flashEnabled,`。
7. 第一個 `Row(...)`（股數、均價、現價）之後加：

```dart
          if (statusText != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Align(
                alignment: Alignment.centerRight,
                child: Text(
                  statusText,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
```

8. `_InfoTile` 加欄位與參數：

```dart
    this.flash,
    this.flashEnabled = true,
```

```dart
  /// 現價的閃色事件(只有現價那一格傳)
  final LiveQuoteFlash? flash;
  final bool flashEnabled;
```

   並把 value 的 `Text(...)` 包進 `PriceFlash(flash: flash, enabled: flashEnabled, child: Text(...))`。

- [ ] **Step 4: 確認通過**

Run: `flutter test test/presentation/screens/portfolio/ test/presentation/providers/`
Expected: 全部 PASS

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 5: 記錄進度**（不 commit）

---

### Task 9: CHANGELOG、golden、全套驗證、mutation、審查、經同意提交

- [ ] **Step 1: CHANGELOG**

`CHANGELOG.md` 的 `## [Unreleased]` → `### Added` 最前面加：

```markdown
- 盤中即時報價（大盤與投資組合）：今日頁大盤列與大盤總覽頁的加權、櫃買指數顯示即時點數與漲跌；上市情緒、漲跌家數與
  各項判讀維持前一交易日並標日期。投資組合與持股詳情的現價、市值、未實現損益、總計改用即時價，現價變動時閃色；
  新增「今日損益（以昨收計）」，標示無報價未計入的檔數與含未收盤報價；績效、配置與股利維持盤後並標資料日期
```

- [ ] **Step 2: golden**（不重產）

```bash
flutter test --tags golden test/presentation/screens/golden/
```

Expected：全部 PASS。有任何差異就是回歸：查原因，不重產。

- [ ] **Step 3: 靜態檢查與全套**（log 寫到 scratchpad；開工前先跑一次全套記基準）

```bash
dart format <本段改過的 .dart 檔>
flutter analyze
flutter test -r expanded > <scratchpad>/full_lq3.log 2>&1; tail -n 1 <scratchpad>/full_lq3.log
flutter test test/tool/tool_chain_pure_dart_test.dart
dart compile kernel tool/intraday_alert_check.dart -o build/intraday_alert_check.dill
dart compile kernel tool/daily_update.dart -o build/daily_update.dill
```

Expected:
- analyze 無 issue。
- 全套通過，測試數 = 基準 + 本段新增。
- 守門測試通過，兩個 kernel 編譯成功（本段新增的 domain 檔 `today_pnl.dart` 不在 CLI 閉包內，確認沒有誤動）。

- [ ] **Step 4: mutation**

在 scratchpad 的 repo 副本做（`rsync -rl`，排除 `.dart_tool/flutter_build`、`build/`、`.git/`、`.superpowers/`）。先確認副本的直接測試全綠。至少涵蓋：

| 檔案 | mutant | 直接測試 |
|:--|:--|:--|
| market_index_live_provider | 備援值也算正式資料（`_officialOf` 不看 stale）；漲跌不用 MIS 昨收（`change: price - official.close`）；official 時仍給狀態 | market_index_live_provider_test |
| market_summary_strip | 有即時仍掛「非即時」；`anyLive` 時不標日期；狀態不顯示 | market_summary_strip_test |
| market_dashboard | Hero 不用 `shown?.index`；`_indexChangePercent` 改讀即時 | market_dashboard_test |
| today_screen | 登記加上訊號卡片的代號；不包 `LiveQuoteScope` | today_screen_test |
| portfolio_provider | 不帶 `priceDate`；價差缺時不推回；前一筆日期檢查拿掉 | portfolio_provider_test |
| today_pnl | 盤前也顯示；fallback 當 0 計入；昨收用收盤；`lastQuote` 不標 | today_pnl_test |
| portfolio_live_provider | 總覽用盤後價；今日損益不傳 phase（一律顯示）；登記不看 quantity | portfolio_live_provider_test |
| portfolio_tab | 總覽傳 `state.summary`；不包 `LiveQuoteScope`；資料日期說明拿掉 | portfolio_tab_test |
| position_card | 現價不包 `PriceFlash`；caption 不顯示 | position_card_test |
| position_detail_screen | 不用 `livePos`；不登記 | position_detail_screen_test |

- [ ] **Step 5: 審查**

送 opus 審查（`pr-review-toolkit:code-reviewer`）：
- 範圍：`git diff` 加未追蹤新檔。
- 附上：
  - 本計畫與 spec 的路徑；
  - Review Focus 五條、「與 spec 的差異」九條；
  - 進度記錄裡的 Ruling；
  - Step 2–4 的輸出。
- 限制：不可 `dart run`、不可開背景任務、不可碰 scratchpad、不改檔。
- 修正 Critical 與 Important：每條先寫出會失敗的測試，再修到通過。Minor 記錄、不修。

- [ ] **Step 6: 報告並等「提交」**

報告內容：
- 全套測試數；
- golden 結果；
- mutation 結果；
- 審查與修正；
- 延後的 Minor 與已知限制；
- 裁定清單。

提醒：不在 09:00–13:30 提交。

Commit message 草稿：

```
feat: 大盤指數與投資組合顯示盤中即時報價

- 今日頁大盤列與大盤總覽頁的加權、櫃買指數顯示即時點數與漲跌；綜合判讀、
  量價、廣度仍用盤後指數漲跌幅，情緒與漲跌家數標前一交易日日期
- 投資組合與持股詳情的現價、市值、未實現損益、總計改用即時價，只有現價閃色
- 新增「今日損益（以昨收計）」：缺價持股不當 0、標示未計入檔數，收盤後含
  非收盤報價時標示；除權息日以收盤減漲跌價差當昨收
- 持股資料保留價格日期與漲跌價差，價差缺時以前一筆收盤推回
- 績效、配置與股利維持盤後並標資料日期
```

- [ ] **Step 7: 經同意後提交**（使用者說「提交」才做）

1. 確認不是 09:00–13:30。
2. 提交（直接在 main，純文字訊息）。
3. 確認兩支 CLI 的 `BUILD_INFO` 已更新為新 commit。

- [ ] **Step 8: 提交後**

1. 重編 GUI（macOS Debug），下一個交易日盤中實機驗證：
   - 大盤列與 Hero 卡的點數一致；與 MIS 原始回應、收盤後與 MI_INDEX 收盤值對照。
   - 投資組合：總覽、今日損益與手算一致；有持股沒報價時有標示；盤後卡片標日期。
   - 13:30 之後：指數與持股換成收盤報價；盤後資料寫入、重新整理後換回正式資料。
2. 更新路線圖記錄：第 1 項（盤中即時報價）完成，下一項「提醒顯示距現價多少」。

---

## 實作後的修正

上面各 task 的程式碼是修正前的版本，以 repo 為準。

**執行時對計畫的修正**：
- Task 2：大盤列的 `_indexGroup` 改收市場代碼後，`TwseMarketIndex` 的 import 用不到了，移除。
- Task 6、7：
  - 依 analyzer 改成 null-aware 的 map 寫法；
  - 狀態文字的 `if` 補大括號；
  - 移除與 `material.dart` 重複的 import。
- Task 8：腳本把持股詳情的 `body` 包進 `LiveQuoteScope` 時，誤把 `floatingActionButton` 一起包進去（analyzer 抓到），已移回 `Scaffold`。
- mutation：32 個突變，首輪殺掉 28 個。4 個存活，補強測試後全部殺掉：
  - 指數漲跌以 MIS 昨收為基準（盤後資料可能更舊）；
  - 用盤後正式資料的指數不標暫停；
  - 只有昨天的正式資料（含價差）仍算無報價，不把昨天的漲跌算成今天的損益；
  - 推回昨收時，前一筆日期不早於最新一筆就不用。

**opus 獨立審查**：0 Critical、1 Important、3 Minor。以下兩條都先寫出會失敗的測試再修：

1. **手機版切換上市／上櫃時，Hero 點數重播閃色**（Important）。
   - 問題：兩個分頁在同一個位置沿用閃色元件，切過去會把另一個指數的閃色事件當成變動。
   - 修法：閃色元件以指數名稱為 key。
2. **全部是今天的正式資料時，頁首仍可能寫「證交所今天尚無報價」**（原列 Minor，依影響改列 Important）。
   - 問題：報價中心的狀態是全 App 共用的，例如別的畫面那檔暫停交易時，會讓最近一輪「尚無報價」。
   - 修法（改共用的頁首規則，自選頁首同一個缺口一併修正）：
     - 畫面上全部是今天的正式資料時不顯示狀態；
     - 「尚無報價」只在沒有任何卡片顯示今天的價格（即時或正式資料）時才寫。

**已裁定、維持現狀**：
- 某個指數盤後資料整個缺（API 與資料庫備援都失敗）、但有即時報價時，大盤列顯示即時點數，Hero 卡顯示「無資料」。計畫的範圍是即時只取代已有的 Hero 卡。
- 今日損益在 09:00 後、或剛打開時，第一輪報價到之前（最多約 25 秒）顯示「NT$0・N 檔無報價未計入」。這是照 spec 字面做的，也如實說明了沒算到的檔數。

**延後的 Minor**：
- 並排檢視時，若只有一張 Hero 卡有狀態列，兩卡的走勢圖會錯開一行字的高度。可比照 `reserveBadgeSpace` 保留空間。
- 被蓋住的大盤總覽頁、持股詳情 watch 整個報價中心，看不見時仍會每輪重建。可改成只 select 頁首規則用到的欄位。
