# 股利第 3-3 段：個股頁股利表、ETF 殖利率、投資組合改讀配發表 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 個股頁股利表、ETF 殖利率卡、投資組合預估年股利與趨勢，全部改讀除權除息配發表（`dividend_distribution`）與完整度事實；資料不完整一律顯示「建置中」，不顯示部分加總、不再打 FinMind 股利 API，也不再因為沒有股利資料在頁首顯示紅字錯誤。

**Architecture:**
- **彙總**：新的純 Dart 模型 `DividendSummary.compute` 吃一檔股票的配發列、股票名稱與 `DividendCompleteness`，算出今年與前 5 年的年度列、平均列、近一年殖利率。三個讀取端共用它，不各自解讀完整度。
- **個股頁**：`StockFundamentalsLoader` 只讀 DB 建摘要（讀取失敗才是 null）；`FundamentalsState.dividendSummary` 取代 `dividendHistory`；新的 `DividendSummaryTable` 取代 `DividendTable`；ETF 的殖利率卡改顯示近一年殖利率。
- **投資組合**：`PortfolioNotifier` 讀完整度、配發表、官方估值與估值日收盤，替每檔建摘要後交給改寫的 `DividendIntelligenceService`；任一持股建置中時合計為 null。

**Tech Stack:** Flutter／Dart 3（sealed class、record、pattern）、Drift 2.32、Riverpod 3、easy_localization、mocktail、flutter_test

**Spec:** `docs/plans/2026-10-01-dividend-read-side-design.md`。本計畫實作 §6、§7，以及「驗證」一節的 3-3。3-1（a29602b5）、3-2（66133fc9）已提交。

## Global Constraints

- **寧可漏、不可錯**：不完整一律顯示「建置中」；不顯示部分加總、不拿過時或部分資料湊數字。完整度只問 `DividendCompleteness`，不在讀取端另訂規則。
- **只讀 DB**：個股頁股利不打 FinMind、不寫舊表 `dividend_history`。
- **不改 schema、不 bump fingerprint**：3-3 只讀股利表。
- **舊東西留到 3-4**：`dividend_history` 表、DAO 的 `getDividendHistory`／`getDividendHistoryBatch`／`insertDividendData`、`DividendSyncer.sync()` 的舊表寫入、`FinMindClient.getDividends`、`FinMindDividend` 都不動（spec §8）。
- **純 Dart**：`dividend_summary.dart` 放 domain，不 import flutter。改完照例跑 `dart compile kernel tool/daily_update.dart -o build/daily_update.dill`。
- **翻譯**：新 key 兩個語系都要有，畫面上一律寫成字面 `'key'.tr(` 讓 `test/core/l10n/app_strings_keys_test.dart` 掃得到（不要把 key 放進變數再 `.tr()`）；文案不得含 `test/core/l10n/no_investment_advice_copy_test.dart` 禁用的字眼。
- **live DB 只唯讀查詢**：`file:...?mode=ro`，沒有 -wal 檔時加 `&immutable=1`。
- **提交**：
  - commit／push 只在使用者說「提交」時做。
  - Conventional Commits、中文、純文字、不加 Co-Authored-By。
  - 每個 task 結尾一律「記錄進度」，整段在 Task 6 一次提交。
- **mutation**：在 scratchpad 的 repo 副本做；還原用備份檔，不用 git checkout；每個 mutant 都跑所有消費者測試，timeout 300 秒。
- **GUI**：3-3 的畫面要重編 GUI 才看得到。提交後先問使用者，同意才重編；重編後才可以進 3-4（spec §8 的前提）。

## Review Focus

1. **新安裝、手機回補中，完整度事實全空**（`displayEnd` 為 null）。
   - 預期：個股頁股利區只顯示「股利資料建置中」、頁首沒有紅字；ETF 殖利率卡顯示建置中；投資組合中要走近一年殖利率的持股（ETF、沒有可用官方估值）顯示建置中，合計與兩個殖利率也顯示建置中（官方估值那條路與完整度無關，照常計算）。
   - 不可以：頁首出現「部分基本面資料暫無法取得（股利）」，或顯示 0 元。
   - 測試在 Task 1（`allBuilding`）、Task 3（頁首）、Task 4（合計 null）。
2. **1 月初、當年第一輪更新之前**（顯示終點還停在去年 12/31）。
   - 預期：今年列建置中；去年照常顯示完整的金額。
   - 不可以：今年顯示「尚未除息　截至 12/31」。
   - 測試在 Task 1。
3. **名稱帶 `*` 的股票**（面額不是 10 元；例：世紀* 2026-08-14 每千股配 3,157 股），以及主檔查不到名稱。
   - 預期：配股顯示「每千股 X 股」、合計「—」；查不到名稱時同樣不假設面額。
   - 不可以：把每千股 3,157 股換算成 31.57 元。
   - 測試在 Task 1、Task 2、Task 3。
4. **ETF 跨分割與停止配息**：0050 於 2025-06-18 分割；0054、00742、00920 最近除息超過 400 天。
   - 預期：近一年殖利率逐次以除息前收盤正規化（0050 在 2025-08 約 2.06%，不是總額 ÷ 現價的約 6%）；停止配息顯示「近一年無配息」，投資組合預估 0。
   - 不可以：停配 ETF 顯示建置中或舊配息算出的殖利率。
   - 測試在 Task 1、Task 4。
5. **只有配股、沒有現金的除權**。
   - 預期：不算除息、不計次數、不當近一年殖利率的「最近一次除息日」。
   - 不可以：一筆只有配股的除權讓停配 ETF 或股票的近一年殖利率變成 0%，而不是「近一年無配息」。
   - 測試在 Task 1。

## 與 spec 的差異（核可計畫時一併確認）

1. **今年列在顯示終點仍在去年時為建置中**
   - spec 的寫法：「本年度至顯示終點」。
   - 問題：1 月初、當年第一輪更新前，顯示終點是去年 12/31，「今年 1/1 至去年 12/31」是空範圍；`isComplete` 對空範圍回傳 true，會變成「尚未除息」。
   - 做法：顯示終點的年份早於今年時，今年列為建置中。
2. **「股利資料建置中」的觸發條件**
   - spec 的寫法：「新增『股利資料建置中』狀態與文案」，沒寫何時用。
   - 做法：今年與前 5 年全部建置中時，整區只顯示這一句、不畫表；只有部分年度建置中時照常畫表，各列標「建置中」。
3. **投資組合合計在任一持股建置中時為 null**
   - spec 沒寫合計。部分加總會是錯的數字，所以預估年股利與兩個組合殖利率一律顯示建置中；各持股列照常顯示自己的數字。
4. **官方估值路徑需要近期估值與估值日的收盤價**
   - spec 的寫法：「官方殖利率 × 同一天收盤價」。
   - 做法：估值日查不到收盤價（2026-10-04 live 有 7 檔），或估值的殖利率欄是 null（237 檔），改走近一年殖利率。
   - 估值早於 `DataFreshness.valuationDbLookbackDays`（30 天，與個股頁同一個下限）也改走近一年殖利率（審查後加）：上櫃估值只同步自選與候選股，持股可能停在很久以前的一筆；中間若有分割，舊的每股股利 × 現在的股數會放大好幾倍。
5. **近一年殖利率對所有股票計算**
   - spec 在 §6 寫的是 ETF。§7 的投資組合要求「無估值」的一般股票也用近一年殖利率，所以摘要一律計算；個股頁只有 ETF 顯示。
6. **股利表年數直接用回補年數**
   - 用 `ApiConfig.dividendBackfillYears`（5），不另設常數：更早的年度沒有回補，列出也只會是建置中。
7. **提早移除與留給 3-4 的東西**
   - 隨讀取端改寫一起拿掉：個股頁的 FinMind 股利回退（spec §7「資料只讀 DB」）；`FundamentalsResult.dividendData`、`FundamentalsState.dividendHistory`；`DividendTable`；`S.dividendYearAverage` 與它的 key、`stockDetail.dividendComingSoon`；`AnalysisParams.dividendLookbackYears`（唯一讀者被改寫）。
   - 留給 3-4：見 Global Constraints「舊東西留到 3-4」。

**不在本段（記錄、不修）**：ETF 本來就沒有營收、EPS、官方估值（2026-10-04 live：ETF 的估值 0 筆）。依 `loadFundamentals` 的程式推斷（未在 GUI 實測），ETF 個股頁頁首一直顯示「部分基本面資料暫無法取得（營收、每股盈餘、估值）」；3-3 之後少了「股利」，紅字仍在。Task 6 重編 GUI 後目視確認。

## 檔案結構

| 檔案 | 責任 | 動作 |
|:--|:--|:--|
| `lib/domain/services/dividend_summary.dart` | 股利摘要：年度狀態、平均、近一年殖利率 | 新增 |
| `lib/core/constants/analysis_params.dart` | 分析參數 | 新增近一年殖利率兩個窗口、趨勢門檻；移除 `dividendLookbackYears` |
| `lib/presentation/screens/stock_detail/tabs/fundamentals/dividend_summary_table.dart` | 個股頁股利表 | 新增（取代 `dividend_table.dart`） |
| `assets/translations/zh-TW.json`、`en.json` | 翻譯 | 新增股利表、ETF 卡、投資組合文案；移除舊 key |
| `lib/data/loaders/stock_fundamentals_loader.dart` | 基本面載入 | 股利改讀 DB 建摘要；移除 FinMind 股利回退 |
| `lib/presentation/providers/stock_detail_state.dart`、`stock_detail_provider.dart` | 個股頁狀態 | `dividendSummary`；`missingParts`、`hasSomeData` |
| `lib/presentation/screens/stock_detail/tabs/fundamentals/fundamentals_tab.dart` | 基本面分頁 | 股利區三種狀態；ETF 殖利率卡 |
| `lib/core/l10n/app_strings.dart` | 字串 | 移除 `dividendYearAverage` |
| `lib/domain/services/dividend_intelligence_service.dart` | 投資組合股利分析 | 改寫 |
| `lib/presentation/providers/portfolio_provider.dart` | 投資組合狀態 | 讀完整度、配發表、估值與估值日收盤 |
| `lib/presentation/screens/portfolio/widgets/dividend_analysis_card.dart` | 投資組合股利卡 | 建置中顯示；趨勢可缺 |
| `lib/core/constants/api_config.dart`、`CHANGELOG.md` | 文件與註解 | 更新 |

---

### Task 1: 股利摘要 `DividendSummary`

**Files:**
- Create: `lib/domain/services/dividend_summary.dart`
- Modify: `lib/core/constants/analysis_params.dart`（`dividendLookbackYears` 之前加兩個常數）
- Test: `test/domain/services/dividend_summary_test.dart`（新檔）

**Interfaces:**
- Consumes: `DividendCompleteness`（`now`、`displayEnd`、`isComplete(symbol, from, to, requirePrices:)`）、`ApiConfig.dividendBackfillYears`
- Produces（後面三個 task 都用）：
  - `enum DividendYearStatus { paid, none, noRecord, notYet, building }`
  - `DividendYearRow({required int year, required DividendYearStatus status, double cash = 0, double stockShares = 0, int cashCount = 0})`
  - `sealed class DividendAverage`：`DividendAverageBuilding()`、`DividendAverageValue({required int fromYear, required int years, required double cash, required double stockShares})`
  - `sealed class TrailingYield`：`TrailingYieldBuilding()`、`TrailingYieldNone()`、`TrailingYieldValue(double ratio)`（0.02＝2%）
  - `DividendSummary({required DateTime? displayEnd, required bool parValueTen, required DividendYearRow current, required List<DividendYearRow> pastYears, required DividendAverage? average, required TrailingYield trailingYield})`
  - `DividendSummary.compute({required String symbol, required String? name, required Iterable<DividendDistributionEntry> rows, required DividendCompleteness completeness})`
  - `bool get allBuilding`、`double? stockYuan(double stockShares)`、`double? totalYuan(double cash, double stockShares)`
  - `AnalysisParams.trailingYieldWindowDays`（350）、`AnalysisParams.trailingYieldStaleDays`（400）

- [ ] **Step 1: 寫失敗測試**

`test/domain/services/dividend_summary_test.dart`：

```dart
// 股利摘要（dividend_summary.dart）：個股頁股利表、ETF 近一年殖利率、投資組合
// 預估共用。年度依除權息日的年份；不完整一律建置中，不顯示部分加總
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/constants/market_codes.dart';
import 'package:daredevil/core/utils/calendar_month.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/domain/services/dividend_completeness.dart';
import 'package:daredevil/domain/services/dividend_summary.dart';

final _now = DateTime(2026, 10, 2, 21, 30);
const _markets = [MarketCode.twse, MarketCode.tpex];

/// [now] 當下：回補範圍（今年往前 5 年的 1 月）到 [ledgerTo]（預設上個月）
/// 兩市場都有完成紀錄，[listedThrough]（預設 now 當天）所在月份列到那一天
DividendCompleteness _facts(
  DateTime now, {
  DateTime? listedThrough,
  CalendarMonth? ledgerTo,
  List<DividendUnresolvedEntry> unresolved = const [],
  List<(String, DateTime)> missingPrices = const [],
}) {
  final thisMonth = CalendarMonth.of(now);
  final through = listedThrough ?? DateTime(now.year, now.month, now.day);
  final listedMonth = CalendarMonth.of(through);
  return DividendCompleteness.compute(
    now: now,
    listings: [
      for (final market in _markets)
        DividendListingEntry(
          market: market,
          year: listedMonth.year,
          month: listedMonth.month,
          listedThrough: through,
        ),
    ],
    ledger: [
      for (final market in _markets)
        for (final m in CalendarMonth.descending(
          from: CalendarMonth(now.year - 5, 1),
          to: ledgerTo ?? thisMonth.previous,
        ))
          DividendMonthLedgerEntry(
            market: market,
            year: m.year,
            month: m.month,
            completedAt: thisMonth.firstDay,
            listedRows: 1,
            knownRows: 1,
            skippedSymbols: '',
            pricesRecorded: true,
          ),
    ],
    unresolved: unresolved,
    missingPriceKeys: missingPrices,
  );
}

DividendUnresolvedEntry _unresolved(String symbol, DateTime exDate) =>
    DividendUnresolvedEntry(
      market: MarketCode.twse,
      symbol: symbol,
      exDate: exDate,
      reason: DividendUnresolvedReason.pendingDetail.code,
      recordedAt: _now,
    );

DividendDistributionEntry _row(
  DateTime exDate, {
  String symbol = '2330',
  double cash = 0,
  double shares = 0,
  double? close = 100,
  double? reference = 95,
}) => DividendDistributionEntry(
  symbol: symbol,
  exDate: exDate,
  cashDividend: cash,
  stockSharesPerThousand: shares,
  closeBefore: close,
  referencePrice: reference,
);

DividendSummary _summary(
  List<DividendDistributionEntry> rows, {
  DividendCompleteness? facts,
  String symbol = '2330',
  String? name = '台積電',
}) => DividendSummary.compute(
  symbol: symbol,
  name: name,
  rows: rows,
  completeness: facts ?? _facts(_now),
);

void main() {
  group('年度狀態（依除權息日的年份）', () {
    test('今年＋前 5 個完整年度：去年到 5 年前新到舊', () {
      final s = _summary(const []);
      expect(s.current.year, 2026);
      expect(s.pastYears.map((r) => r.year), [2025, 2024, 2023, 2022, 2021]);
    });

    test('有配發：現金與配股各自加總；次數只數有現金的除權息', () {
      final s = _summary([
        _row(DateTime(2025, 3, 20), cash: 2.5),
        _row(DateTime(2025, 9, 18), cash: 2.5),
        _row(DateTime(2025, 9, 25), shares: 50), // 同一年的權另一天除
      ]);
      final y2025 = s.pastYears.first;
      expect(y2025.status, DividendYearStatus.paid);
      expect(y2025.cash, 5.0);
      expect(y2025.stockShares, 50);
      expect(y2025.cashCount, 2);
    });

    test('第一次除權息之前的空年是「無除權息紀錄」、之後的是「無除權息」', () {
      final s = _summary([_row(DateTime(2023, 7, 13), cash: 3)]);
      expect({for (final r in s.pastYears) r.year: r.status}, {
        2025: DividendYearStatus.none,
        2024: DividendYearStatus.none,
        2023: DividendYearStatus.paid,
        2022: DividendYearStatus.noRecord,
        2021: DividendYearStatus.noRecord,
      });
    });

    test('第一次除權息在今年：前 5 年都是「無除權息紀錄」', () {
      final s = _summary([_row(DateTime(2026, 8, 1), cash: 1)]);
      expect(s.pastYears.map((r) => r.status).toSet(), {
        DividendYearStatus.noRecord,
      });
    });

    test('不完整的年度是建置中：DB 裡已有的列也不顯示（不顯示部分加總）', () {
      final s = _summary(
        [_row(DateTime(2024, 7, 11), cash: 4)],
        facts: _facts(
          _now,
          unresolved: [_unresolved('2330', DateTime(2024, 3, 20))],
        ),
      );
      final y2024 = s.pastYears.firstWhere((r) => r.year == 2024);
      expect(y2024.status, DividendYearStatus.building);
      expect(y2024.cash, 0);
    });

    test('只有現金增資的 0/0 列不算配發', () {
      final s = _summary([_row(DateTime(2025, 7, 17))]);
      expect(s.pastYears.first.status, DividendYearStatus.noRecord);
    });

    test('年度表只看金額（requirePrices: false）：缺價格欄的年度照常顯示', () {
      final s = _summary(
        [_row(DateTime(2025, 7, 17), cash: 3, close: null, reference: null)],
        facts: _facts(_now, missingPrices: [('2330', DateTime(2025, 7, 17))]),
      );
      expect(s.pastYears.first.status, DividendYearStatus.paid);
    });
  });

  group('今年', () {
    // 真實情況：2026-10-03 的 live DB 已有舊版 CLI 寫入的 10/1、10/2 列，
    // 10 月的列表事實要等新版第一輪才寫，顯示終點停在 9/30
    test('有除權息：算到顯示終點當天為止', () {
      final s = _summary([
        _row(DateTime(2026, 7, 16), cash: 3),
        _row(DateTime(2026, 10, 2), cash: 0.5), // 顯示終點當天：算
        _row(DateTime(2026, 10, 5), cash: 1), // 顯示終點之後：不算
      ]);
      expect(s.displayEnd, DateTime(2026, 10, 2));
      expect(s.current.status, DividendYearStatus.paid);
      expect(s.current.cash, 3.5);
      expect(s.current.cashCount, 2);
    });

    test('至顯示終點完整、還沒有除權息：尚未除息', () {
      expect(_summary(const []).current.status, DividendYearStatus.notYet);
    });

    test('今年不完整：建置中', () {
      final s = _summary(
        [_row(DateTime(2026, 7, 16), cash: 3)],
        facts: _facts(
          _now,
          unresolved: [_unresolved('2330', DateTime(2026, 8, 20))],
        ),
      );
      expect(s.current.status, DividendYearStatus.building);
    });

    test('年度表只看金額：今年缺價格欄照常顯示', () {
      final s = _summary(
        [_row(DateTime(2026, 7, 21), cash: 1, close: null, reference: null)],
        facts: _facts(_now, missingPrices: [('2330', DateTime(2026, 7, 21))]),
      );
      expect(s.current.status, DividendYearStatus.paid);
    });

    test('🚨 1 月初、當年第一輪更新前（顯示終點還在去年）：今年建置中，去年照常', () {
      final now = DateTime(2027, 1, 2, 8);
      final s = _summary(
        [_row(DateTime(2026, 7, 16), cash: 3)],
        facts: _facts(
          now,
          listedThrough: DateTime(2026, 12, 31),
          ledgerTo: const CalendarMonth(2026, 11),
        ),
      );
      expect(s.displayEnd, DateTime(2026, 12, 31));
      expect(s.current.year, 2027);
      expect(s.current.status, DividendYearStatus.building);
      expect(s.pastYears.first.year, 2026);
      expect(s.pastYears.first.status, DividendYearStatus.paid);
    });
  });

  group('整區建置中', () {
    test('🚨 完全沒有完整度事實（新安裝、手機回補中）：全部建置中', () {
      final s = DividendSummary.compute(
        symbol: '2330',
        name: '台積電',
        rows: [_row(DateTime(2025, 7, 17), cash: 3)],
        completeness: DividendCompleteness.compute(
          now: _now,
          listings: const [],
          ledger: const [],
          unresolved: const [],
          missingPriceKeys: const [],
        ),
      );
      expect(s.displayEnd, isNull);
      expect(s.allBuilding, isTrue);
      expect(s.average, isA<DividendAverageBuilding>());
      expect(s.trailingYield, isA<TrailingYieldBuilding>());
    });

    test('前 5 年都建置中、今年不是：不是整區建置中', () {
      final s = _summary(
        const [],
        facts: _facts(
          _now,
          unresolved: [
            for (final y in [2021, 2022, 2023, 2024, 2025])
              _unresolved('2330', DateTime(y, 6, 1)),
          ],
        ),
      );
      expect(s.current.status, DividendYearStatus.notYet);
      expect(s.allBuilding, isFalse);
    });

    test('今年建置中、前幾年有不是建置中的：不是整區建置中', () {
      final s = _summary(
        const [],
        facts: _facts(
          _now,
          unresolved: [
            _unresolved('2330', DateTime(2026, 6, 1)),
            _unresolved('2330', DateTime(2024, 6, 1)),
          ],
        ),
      );
      expect(s.current.status, DividendYearStatus.building);
      expect(s.allBuilding, isFalse);
    });
  });

  group('平均（從第一次有除權息的完整年度到去年）', () {
    test('5 年都有配發：5 年平均', () {
      final s = _summary([
        for (final y in [2021, 2022, 2023, 2024, 2025])
          _row(DateTime(y, 7, 15), cash: y - 2020.0),
      ]);
      final avg = s.average as DividendAverageValue;
      expect(avg.fromYear, 2021);
      expect(avg.years, 5);
      expect(avg.cash, 3.0); // (1+2+3+4+5)/5
    });

    test('第一次除權息在 2023：2023 起 3 年平均，其間無除權息的年度計 0', () {
      final s = _summary([
        _row(DateTime(2023, 7, 13), cash: 3, shares: 30),
        _row(DateTime(2025, 7, 17), cash: 6),
      ]);
      final avg = s.average as DividendAverageValue;
      expect(avg.fromYear, 2023);
      expect(avg.years, 3);
      expect(avg.cash, 3.0); // (3 + 0 + 6) / 3
      expect(avg.stockShares, 10.0);
      // 第一次是 2023（不是最近有配發的 2025）：夾在中間的 2024 是無除權息
      expect(
        s.pastYears.firstWhere((r) => r.year == 2024).status,
        DividendYearStatus.none,
      );
    });

    test('今年的配發不計入平均', () {
      final s = _summary([
        _row(DateTime(2025, 7, 17), cash: 2),
        _row(DateTime(2026, 7, 16), cash: 10),
      ]);
      final avg = s.average as DividendAverageValue;
      expect(avg.fromYear, 2025);
      expect(avg.years, 1);
      expect(avg.cash, 2.0);
    });

    test('前 5 年任一年建置中：平均建置中（含第一次除權息之前的年度）', () {
      final s = _summary(
        [_row(DateTime(2024, 7, 11), cash: 4)],
        facts: _facts(
          _now,
          unresolved: [_unresolved('2330', DateTime(2021, 5, 5))],
        ),
      );
      expect(s.average, isA<DividendAverageBuilding>());
    });

    test('前 5 年都沒有除權息：沒有平均', () {
      expect(_summary([_row(DateTime(2026, 8, 1), cash: 1)]).average, isNull);
    });
  });

  group('面額（名稱帶 * 表示不是 10 元）', () {
    test('不帶 *：配股換算成元（每千股 ÷ 100），合計＝現金＋股票', () {
      final s = _summary(const [], name: '台積電');
      expect(s.parValueTen, isTrue);
      expect(s.stockYuan(50), 0.5);
      expect(s.totalYuan(2, 50), 2.5);
    });

    test('🚨 帶 *：不換算、合計為 null（畫面顯示「—」）', () {
      final s = _summary(const [], name: '世紀*');
      expect(s.parValueTen, isFalse);
      expect(s.stockYuan(3157.03), isNull);
      expect(s.totalYuan(0, 3157.03), isNull);
    });

    test('主檔查不到名稱：不假設面額', () {
      expect(_summary(const [], name: null).parValueTen, isFalse);
    });
  });

  group('近一年殖利率', () {
    test('🚨 0050 跨分割（2025-06-18）：逐次以前收盤正規化，不是總額 ÷ 現價', () {
      // 2025-08-01 當下：最近一次除息 2025-07-21，窗口從 2024-08-05 起
      final s = _summary(
        [
          _row(DateTime(2024, 7, 16), cash: 1.0, close: 196.7),
          _row(DateTime(2025, 1, 17), cash: 2.7, close: 198.05),
          _row(DateTime(2025, 7, 21), cash: 0.36, close: 51.45),
        ],
        symbol: '0050',
        name: '元大台灣50',
        facts: _facts(DateTime(2025, 8, 1, 21)),
      );
      final ratio = (s.trailingYield as TrailingYieldValue).ratio;
      expect(ratio, closeTo(2.7 / 198.05 + 0.36 / 51.45, 1e-12)); // 約 2.06%
      // 總額 ÷ 分割後股價（約 51）會是 6% 上下
      expect(ratio, lessThan(0.03));
    });

    test('窗口：最近一次除息日往前 350 天含、351 天不含', () {
      // 最近一次 2026-07-21；350 天前＝2025-08-05、351 天前＝2025-08-04
      final s = _summary([
        _row(DateTime(2025, 8, 4), cash: 5, close: 100),
        _row(DateTime(2025, 8, 5), cash: 1, close: 100),
        _row(DateTime(2026, 7, 21), cash: 0.6, close: 99.2),
      ]);
      expect(
        (s.trailingYield as TrailingYieldValue).ratio,
        closeTo(1 / 100 + 0.6 / 99.2, 1e-12),
      );
    });

    test('最近一次除息早於顯示終點 400 天：近一年無配息', () {
      // 顯示終點 2026-10-02；400 天前＝2025-08-28
      final s = _summary([_row(DateTime(2025, 8, 28), cash: 1)]);
      expect(s.trailingYield, isA<TrailingYieldNone>());
    });

    test('399 天：仍計算', () {
      final s = _summary([_row(DateTime(2025, 8, 29), cash: 1, close: 50)]);
      expect(
        (s.trailingYield as TrailingYieldValue).ratio,
        closeTo(0.02, 1e-12),
      );
    });

    test('沒有任何除息紀錄、近 400 天完整：近一年無配息', () {
      expect(_summary(const []).trailingYield, isA<TrailingYieldNone>());
    });

    test('🚨 只有配股的除權（現金 0）不是除息：不當最近一次除息日', () {
      final s = _summary([
        _row(DateTime(2025, 8, 20), cash: 1), // 400 天以上
        _row(DateTime(2026, 8, 14), shares: 3157), // 只有配股
      ]);
      expect(s.trailingYield, isA<TrailingYieldNone>());
    });

    test('顯示終點之後的除息不算（不前視）；顯示終點當天的要算', () {
      final after = _summary([
        _row(DateTime(2025, 8, 20), cash: 1),
        _row(DateTime(2026, 10, 5), cash: 1),
      ]);
      expect(after.trailingYield, isA<TrailingYieldNone>());

      final onEnd = _summary([_row(DateTime(2026, 10, 2), cash: 1, close: 100)]);
      expect(
        (onEnd.trailingYield as TrailingYieldValue).ratio,
        closeTo(0.01, 1e-12),
      );
    });

    test('完整度窗口從最近除息日往前 350 天起：窗口內有未解決的列是建置中', () {
      final rows = [_row(DateTime(2026, 7, 21), cash: 1, close: 100)];
      // 窗口＝[2025-08-05, 2026-10-02]
      expect(
        _summary(
          rows,
          facts: _facts(
            _now,
            unresolved: [_unresolved('2330', DateTime(2025, 8, 5))],
          ),
        ).trailingYield,
        isA<TrailingYieldBuilding>(),
      );
      expect(
        _summary(
          rows,
          facts: _facts(
            _now,
            unresolved: [_unresolved('2330', DateTime(2025, 8, 4))],
          ),
        ).trailingYield,
        isA<TrailingYieldValue>(),
      );
    });

    test('近一年無配息也要近 400 天完整：窗口內有未解決的列是建置中', () {
      // 窗口＝[2025-08-28, 2026-10-02]
      expect(
        _summary(
          const [],
          facts: _facts(
            _now,
            unresolved: [_unresolved('2330', DateTime(2025, 8, 28))],
          ),
        ).trailingYield,
        isA<TrailingYieldBuilding>(),
      );
      expect(
        _summary(
          const [],
          facts: _facts(
            _now,
            unresolved: [_unresolved('2330', DateTime(2025, 8, 27))],
          ),
        ).trailingYield,
        isA<TrailingYieldNone>(),
      );
    });

    test('需要價格（requirePrices: true）：窗口內的配發列缺價格是建置中', () {
      final s = _summary(
        [_row(DateTime(2026, 7, 21), cash: 1, close: null, reference: null)],
        facts: _facts(_now, missingPrices: [('2330', DateTime(2026, 7, 21))]),
      );
      expect(s.trailingYield, isA<TrailingYieldBuilding>());
    });

    test('近一年無配息的窗口也要求價格', () {
      // 窗口內只有一筆只有配股、缺價格的除權
      final s = _summary(
        [_row(DateTime(2026, 8, 14), shares: 50, close: null, reference: null)],
        facts: _facts(_now, missingPrices: [('2330', DateTime(2026, 8, 14))]),
      );
      expect(s.trailingYield, isA<TrailingYieldBuilding>());
    });

    test('配發列缺前收盤、完整度卻沒記到（兩次查詢之間被改寫）：建置中，不拋例外', () {
      final s = _summary([_row(DateTime(2026, 7, 21), cash: 1, close: null)]);
      expect(s.trailingYield, isA<TrailingYieldBuilding>());
    });
  });
}
```

- [ ] **Step 2: 確認失敗**

Run: `flutter test test/domain/services/dividend_summary_test.dart`
Expected: FAIL，編譯錯誤 `Error when reading 'lib/domain/services/dividend_summary.dart'`

- [ ] **Step 3: 實作**

`lib/core/constants/analysis_params.dart`，在 `dividendLookbackYears` 的文件註解之前加：

```dart
  /// 近一年殖利率的事件窗：以最近一次除息日為終點，往前這麼多天內（含）的
  /// 除息。2026-10-01 以 54 檔 2024–2025 固定頻率 ETF 逐日回測配息次數：
  /// 350 天誤差 0.05%、355 天 0.98%、365 天 28%
  static const int trailingYieldWindowDays = 350;

  /// 近一年殖利率：最近一次除息早於顯示終點這麼多天以上，視為近一年無配息
  /// （固定年配相鄰間隔 352–377 天；在市 ETF 超過 400 天者均已停止配息）
  static const int trailingYieldStaleDays = 400;

```

`lib/domain/services/dividend_summary.dart`：

```dart
import 'package:daredevil/core/constants/analysis_params.dart';
import 'package:daredevil/core/constants/api_config.dart';
import 'package:daredevil/core/utils/date_context.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/domain/services/dividend_completeness.dart';

/// 除息年度在股利表上的狀態
enum DividendYearStatus {
  /// 完整且有除權息：顯示金額
  paid,

  /// 完整、沒有除權息，且在第一次除權息之後：計入平均為 0
  none,

  /// 完整、沒有除權息，且不在第一次除權息之後（可能尚未上市）：不計入平均
  noRecord,

  /// 今年：至顯示終點完整，還沒有除權息
  notYet,

  /// 不完整：不顯示金額
  building,
}

/// 股利表的一列：一個除息年度（依除權息日的年份，不是股利所屬年度）
class DividendYearRow {
  const DividendYearRow({
    required this.year,
    required this.status,
    this.cash = 0,
    this.stockShares = 0,
    this.cashCount = 0,
  });

  final int year;
  final DividendYearStatus status;

  /// 每股現金股利合計（元）；只有 [DividendYearStatus.paid] 有值
  final double cash;

  /// 每千股無償配股合計（股）；同上
  final double stockShares;

  /// 有現金的除權息次數：同一年息、權分兩天除只算一次
  final int cashCount;
}

/// 股利表的平均列
sealed class DividendAverage {
  const DividendAverage();
}

/// 前幾個完整年度中有建置中的年度：無法判定第一次除權息在哪一年，也無法
/// 排除建置中的年度其實是 0
final class DividendAverageBuilding extends DividendAverage {
  const DividendAverageBuilding();
}

/// 從第一次有除權息的完整年度 [fromYear] 到去年、共 [years] 年的平均；
/// 其間無除權息的年度計為 0
final class DividendAverageValue extends DividendAverage {
  const DividendAverageValue({
    required this.fromYear,
    required this.years,
    required this.cash,
    required this.stockShares,
  });

  final int fromYear;
  final int years;

  /// 每股現金股利（元）
  final double cash;

  /// 每千股無償配股（股）
  final double stockShares;
}

/// 近一年殖利率
sealed class TrailingYield {
  const TrailingYield();
}

/// 完整度不足
final class TrailingYieldBuilding extends TrailingYield {
  const TrailingYieldBuilding();
}

/// 近一年無配息：最近一次除息早於顯示終點
/// [AnalysisParams.trailingYieldStaleDays] 天以上，或沒有除息紀錄
final class TrailingYieldNone extends TrailingYield {
  const TrailingYieldNone();
}

/// Σ(現金股利 ÷ 除息前收盤)，事件取最近一次除息日往前
/// [AnalysisParams.trailingYieldWindowDays] 天內（含）者。逐次以當時的前收盤
/// 正規化，不受分割影響
final class TrailingYieldValue extends TrailingYield {
  const TrailingYieldValue(this.ratio);

  /// 比例（0.02＝2%）
  final double ratio;
}

/// 個股股利摘要：個股頁股利表、ETF 殖利率卡、投資組合預估共用
class DividendSummary {
  const DividendSummary({
    required this.displayEnd,
    required this.parValueTen,
    required this.current,
    required this.pastYears,
    required this.average,
    required this.trailingYield,
  });

  /// 依 [symbol] 的配發列與完整度彙總；今年＝[DividendCompleteness.now] 的
  /// 年份。
  ///
  /// [rows]：該檔的配發列，順序不拘；只有現金增資的 0/0 列不算配發，略過。
  /// [name]：股票名稱，帶 `*` 表示面額不是 10 元；null（主檔查不到）時不假設
  /// 面額
  factory DividendSummary.compute({
    required String symbol,
    required String? name,
    required Iterable<DividendDistributionEntry> rows,
    required DividendCompleteness completeness,
  }) {
    final thisYear = completeness.now.year;
    final end = completeness.displayEnd;
    final byYear = <int, List<DividendDistributionEntry>>{};
    for (final row in rows) {
      if (row.cashDividend <= 0 && row.stockSharesPerThousand <= 0) continue;
      byYear.putIfAbsent(row.exDate.year, () => []).add(row);
    }
    final firstYear = thisYear - ApiConfig.dividendBackfillYears;
    int? firstEventYear;
    for (var year = firstYear; year <= thisYear; year++) {
      if (byYear.containsKey(year)) {
        firstEventYear = year;
        break;
      }
    }

    // 顯示終點還在去年（1 月初、當年第一輪更新前）時，今年沒有可判斷的範圍
    final DividendYearRow current;
    if (end == null ||
        end.year < thisYear ||
        !completeness.isComplete(
          symbol,
          DateTime(thisYear),
          end,
          requirePrices: false,
        )) {
      current = DividendYearRow(
        year: thisYear,
        status: DividendYearStatus.building,
      );
    } else {
      final events = [
        for (final row in byYear[thisYear] ?? const <DividendDistributionEntry>[])
          if (!DateContext.normalize(row.exDate).isAfter(end)) row,
      ];
      current = events.isEmpty
          ? DividendYearRow(year: thisYear, status: DividendYearStatus.notYet)
          : _paid(thisYear, events);
    }

    final pastYears = [
      for (var year = thisYear - 1; year >= firstYear; year--)
        if (!completeness.isComplete(
          symbol,
          DateTime(year),
          DateTime(year, 12, 31),
          requirePrices: false,
        ))
          DividendYearRow(year: year, status: DividendYearStatus.building)
        else if (byYear[year] case final events?)
          _paid(year, events)
        else
          DividendYearRow(
            year: year,
            status: firstEventYear != null && year > firstEventYear
                ? DividendYearStatus.none
                : DividendYearStatus.noRecord,
          ),
    ];

    return DividendSummary(
      displayEnd: end,
      parValueTen: name != null && !name.contains('*'),
      current: current,
      pastYears: pastYears,
      average: _average(pastYears),
      trailingYield: _trailingYield(
        symbol,
        byYear.values.expand((e) => e),
        completeness,
      ),
    );
  }

  /// 畫面「截至 M/D」；null＝連回補起點的月份都沒列過（全部建置中）
  final DateTime? displayEnd;

  /// 面額 10 元（名稱不帶 `*`）：配股可換算成元，合計＝現金＋股票
  final bool parValueTen;

  /// 今年（至 [displayEnd]）
  final DividendYearRow current;

  /// 去年起往前 [ApiConfig.dividendBackfillYears] 個完整年度，新到舊。更早的
  /// 年度不在回補範圍內，列出也只會是建置中
  final List<DividendYearRow> pastYears;

  /// null＝前幾個完整年度都沒有除權息，沒有可平均的年度
  final DividendAverage? average;

  final TrailingYield trailingYield;

  /// 今年與前幾年全部建置中：整區改顯示「股利資料建置中」
  bool get allBuilding =>
      current.status == DividendYearStatus.building &&
      pastYears.every((r) => r.status == DividendYearStatus.building);

  /// 配股換算成每股元（面額 10 元：每千股 X 股＝X ÷ 100 元）；面額不是 10 元
  /// 時 null
  double? stockYuan(double stockShares) =>
      parValueTen ? stockShares / 100 : null;

  /// 合計（元）＝現金＋配股換算的元；面額不是 10 元時 null（畫面顯示「—」）
  double? totalYuan(double cash, double stockShares) =>
      parValueTen ? cash + stockShares / 100 : null;

  static DividendYearRow _paid(
    int year,
    Iterable<DividendDistributionEntry> events,
  ) {
    var cash = 0.0;
    var stockShares = 0.0;
    var cashCount = 0;
    for (final e in events) {
      cash += e.cashDividend;
      stockShares += e.stockSharesPerThousand;
      if (e.cashDividend > 0) cashCount++;
    }
    return DividendYearRow(
      year: year,
      status: DividendYearStatus.paid,
      cash: cash,
      stockShares: stockShares,
      cashCount: cashCount,
    );
  }

  static DividendAverage? _average(List<DividendYearRow> pastYears) {
    if (pastYears.any((r) => r.status == DividendYearStatus.building)) {
      return const DividendAverageBuilding();
    }
    // pastYears 新到舊：最後一個有配發的就是第一次除權息的年度
    int? fromYear;
    for (final row in pastYears) {
      if (row.status == DividendYearStatus.paid) fromYear = row.year;
    }
    if (fromYear == null) return null;
    final counted = [
      for (final row in pastYears)
        if (row.year >= fromYear) row,
    ];
    var cash = 0.0;
    var stockShares = 0.0;
    for (final row in counted) {
      cash += row.cash;
      stockShares += row.stockShares;
    }
    return DividendAverageValue(
      fromYear: fromYear,
      years: counted.length,
      cash: cash / counted.length,
      stockShares: stockShares / counted.length,
    );
  }

  /// 有事件時完整度窗口＝[最近除息日 − 350 天, 顯示終點]；沒有（或最近一次
  /// 已超過 400 天）時＝[顯示終點 − 400 天, 顯示終點]；兩者都要求價格
  static TrailingYield _trailingYield(
    String symbol,
    Iterable<DividendDistributionEntry> rows,
    DividendCompleteness completeness,
  ) {
    final end = completeness.displayEnd;
    if (end == null) return const TrailingYieldBuilding();
    final events = [
      for (final row in rows)
        if (row.cashDividend > 0 &&
            !DateContext.normalize(row.exDate).isAfter(end))
          row,
    ];
    DateTime? latest;
    for (final e in events) {
      final exDate = DateContext.normalize(e.exDate);
      if (latest == null || exDate.isAfter(latest)) latest = exDate;
    }
    final staleCutoff = DateTime(
      end.year,
      end.month,
      end.day - AnalysisParams.trailingYieldStaleDays,
    );
    if (latest == null || !latest.isAfter(staleCutoff)) {
      return completeness.isComplete(
            symbol,
            staleCutoff,
            end,
            requirePrices: true,
          )
          ? const TrailingYieldNone()
          : const TrailingYieldBuilding();
    }
    final from = DateTime(
      latest.year,
      latest.month,
      latest.day - AnalysisParams.trailingYieldWindowDays,
    );
    if (!completeness.isComplete(symbol, from, end, requirePrices: true)) {
      return const TrailingYieldBuilding();
    }
    var ratio = 0.0;
    for (final e in events) {
      if (DateContext.normalize(e.exDate).isBefore(from)) continue;
      // 配發列與完整度是兩次查詢，中間可能被改寫：缺價時視為建置中
      final close = e.closeBefore;
      if (close == null || close <= 0) return const TrailingYieldBuilding();
      ratio += e.cashDividend / close;
    }
    return TrailingYieldValue(ratio);
  }
}
```

- [ ] **Step 4: 確認通過**

Run: `flutter test test/domain/services/dividend_summary_test.dart`
Expected: 全部 PASS

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 5: 記錄進度**（不 commit）

---

### Task 2: 個股頁股利表 `DividendSummaryTable` 與文案

**Files:**
- Create: `lib/presentation/screens/stock_detail/tabs/fundamentals/dividend_summary_table.dart`
- Modify: `assets/translations/zh-TW.json`、`assets/translations/en.json`（`stockDetail` 區塊）
- Test: `test/presentation/screens/stock_detail/tabs/fundamentals/dividend_summary_table_test.dart`（新檔）
- Test: `test/presentation/screens/stock_detail/tabs/fundamentals/dividend_summary_table_zh_test.dart`（新檔）

**Interfaces:**
- Consumes: Task 1 的 `DividendSummary`、`DividendYearRow`、`DividendYearStatus`、`DividendAverage*`、`TrailingYield*`
- Produces:
  - `DividendSummaryTable({Key? key, required DividendSummary summary, required bool showROCYear})`
  - 翻譯 key（Task 3 也用）：`stockDetail.dividendBuilding`、`stockDetail.dividendUnavailable`、`stockDetail.dividendStatusBuilding`、`stockDetail.trailingYieldLabel`、`stockDetail.trailingYieldNone`

- [ ] **Step 1: 寫失敗測試**

`test/presentation/screens/stock_detail/tabs/fundamentals/dividend_summary_table_test.dart`：

```dart
// 個股頁股利表：依 DividendSummary 畫今年＋前 5 年與平均列。翻譯未載入時
// 畫面顯示 key 字面，這裡以 key 比對；實際中文與參數見同目錄的 _zh_test
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/domain/services/dividend_summary.dart';
import 'package:daredevil/presentation/screens/stock_detail/tabs/fundamentals/dividend_summary_table.dart';

import '../../../../../helpers/widget_test_helpers.dart';

DividendSummary _summary({
  bool parValueTen = true,
  DividendYearRow current = const DividendYearRow(
    year: 2026,
    status: DividendYearStatus.notYet,
  ),
  List<DividendYearRow>? pastYears,
  DividendAverage? average,
}) => DividendSummary(
  displayEnd: DateTime(2026, 10, 2),
  parValueTen: parValueTen,
  current: current,
  pastYears:
      pastYears ??
      [
        for (var y = 2025; y >= 2021; y--)
          DividendYearRow(year: y, status: DividendYearStatus.noRecord),
      ],
  average: average,
  trailingYield: const TrailingYieldNone(),
);

void main() {
  setUpAll(() async {
    await setupTestLocalization();
  });

  Future<void> pump(
    WidgetTester tester,
    DividendSummary summary, {
    bool showROCYear = false,
  }) async {
    tester.view.physicalSize = const Size(5000, 4000);
    addTearDown(() => tester.view.resetPhysicalSize());
    await tester.pumpWidget(
      buildTestApp(
        DividendSummaryTable(summary: summary, showROCYear: showROCYear),
      ),
    );
  }

  testWidgets('有配發：現金、配股換算成元、合計', (tester) async {
    await pump(
      tester,
      _summary(
        current: const DividendYearRow(
          year: 2026,
          status: DividendYearStatus.paid,
          cash: 5,
          stockShares: 50,
          cashCount: 1,
        ),
      ),
    );
    expect(find.text('NT\$5.00'), findsOneWidget);
    expect(find.text('NT\$0.50'), findsOneWidget);
    expect(find.text('NT\$5.50'), findsOneWidget);
  });

  testWidgets('多次配息才標次數', (tester) async {
    await pump(
      tester,
      _summary(
        current: const DividendYearRow(
          year: 2026,
          status: DividendYearStatus.paid,
          cash: 4,
          cashCount: 4,
        ),
        pastYears: [
          const DividendYearRow(
            year: 2025,
            status: DividendYearStatus.paid,
            cash: 3,
            cashCount: 1,
          ),
          for (var y = 2024; y >= 2021; y--)
            DividendYearRow(year: y, status: DividendYearStatus.noRecord),
        ],
      ),
    );
    expect(find.text('stockDetail.dividendCashCount'), findsOneWidget);
  });

  testWidgets('🚨 面額不是 10 元：配股顯示每千股、合計顯示「—」', (tester) async {
    await pump(
      tester,
      _summary(
        parValueTen: false,
        current: const DividendYearRow(
          year: 2026,
          status: DividendYearStatus.paid,
          stockShares: 3157.03,
        ),
      ),
    );
    expect(find.text('stockDetail.dividendSharesPerThousand'), findsOneWidget);
    expect(find.text('—'), findsOneWidget);
    expect(find.textContaining('NT\$31'), findsNothing);
  });

  testWidgets('各年度狀態的文案', (tester) async {
    await pump(
      tester,
      _summary(
        pastYears: const [
          DividendYearRow(year: 2025, status: DividendYearStatus.none),
          DividendYearRow(year: 2024, status: DividendYearStatus.building),
          DividendYearRow(year: 2023, status: DividendYearStatus.noRecord),
          DividendYearRow(year: 2022, status: DividendYearStatus.noRecord),
          DividendYearRow(year: 2021, status: DividendYearStatus.noRecord),
        ],
      ),
    );
    expect(find.text('stockDetail.dividendStatusNotYet'), findsOneWidget);
    expect(find.text('stockDetail.dividendStatusNone'), findsOneWidget);
    expect(find.text('stockDetail.dividendStatusBuilding'), findsOneWidget);
    expect(find.text('stockDetail.dividendStatusNoRecord'), findsNWidgets(3));
  });

  testWidgets('今年標截至；今年建置中時不標', (tester) async {
    await pump(tester, _summary());
    expect(find.text('stockDetail.dividendAsOf'), findsOneWidget);

    await pump(
      tester,
      _summary(
        current: const DividendYearRow(
          year: 2026,
          status: DividendYearStatus.building,
        ),
      ),
    );
    expect(find.text('stockDetail.dividendAsOf'), findsNothing);
  });

  testWidgets('平均列：滿 5 年、不足 5 年、建置中、沒有平均', (tester) async {
    await pump(
      tester,
      _summary(
        average: const DividendAverageValue(
          fromYear: 2021,
          years: 5,
          cash: 3,
          stockShares: 0,
        ),
      ),
    );
    expect(find.text('stockDetail.dividendAverageFull'), findsOneWidget);
    expect(find.text('NT\$3.00'), findsNWidgets(2)); // 現金與合計

    await pump(
      tester,
      _summary(
        average: const DividendAverageValue(
          fromYear: 2023,
          years: 3,
          cash: 3,
          stockShares: 10,
        ),
      ),
    );
    expect(find.text('stockDetail.dividendAverageSince'), findsOneWidget);

    await pump(tester, _summary(average: const DividendAverageBuilding()));
    expect(find.text('stockDetail.dividendAverage'), findsOneWidget);
    expect(find.text('stockDetail.dividendStatusBuilding'), findsOneWidget);

    await pump(tester, _summary());
    expect(find.text('stockDetail.dividendAverage'), findsNothing);
    expect(find.text('stockDetail.dividendAverageFull'), findsNothing);
  });

  testWidgets('民國年', (tester) async {
    await pump(tester, _summary(), showROCYear: true);
    expect(find.text('2026 (民115)'), findsOneWidget);
  });
}
```

`test/presentation/screens/stock_detail/tabs/fundamentals/dividend_summary_table_zh_test.dart`：

```dart
// 股利表以真實 zh-TW 翻譯驗文案參數（{date}、{count}、{shares}、{year}、
// {years}）與手機寬度不溢位。真實翻譯寫入全域 Localization.instance、會污染
// 同檔其他測試，故獨立成檔
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/domain/services/dividend_summary.dart';
import 'package:daredevil/presentation/screens/stock_detail/tabs/fundamentals/dividend_summary_table.dart';

import '../../../../../helpers/provider_test_helpers.dart';
import '../../../../../helpers/widget_test_helpers.dart';

void main() {
  setUpAll(() async {
    await setupTestLocalization();
  });

  testWidgets('手機寬度、民國年：截至、次數、每千股、起算年平均', (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      buildProviderTestApp(
        SingleChildScrollView(
          child: DividendSummaryTable(
            summary: DividendSummary(
              displayEnd: DateTime(2026, 10, 2),
              parValueTen: false,
              current: const DividendYearRow(
                year: 2026,
                status: DividendYearStatus.paid,
                cash: 2.4,
                stockShares: 3157.03,
                cashCount: 4,
              ),
              pastYears: const [
                DividendYearRow(
                  year: 2025,
                  status: DividendYearStatus.paid,
                  cash: 6,
                  cashCount: 1,
                ),
                DividendYearRow(year: 2024, status: DividendYearStatus.none),
                DividendYearRow(
                  year: 2023,
                  status: DividendYearStatus.paid,
                  cash: 3,
                  stockShares: 30,
                  cashCount: 1,
                ),
                DividendYearRow(year: 2022, status: DividendYearStatus.noRecord),
                DividendYearRow(year: 2021, status: DividendYearStatus.noRecord),
              ],
              average: const DividendAverageValue(
                fromYear: 2023,
                years: 3,
                cash: 3,
                stockShares: 10,
              ),
              trailingYield: const TrailingYieldNone(),
            ),
            showROCYear: true,
          ),
        ),
        zhTranslations: true,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(tester.takeException(), isNull);
    expect(find.text('除息年度'), findsOneWidget);
    expect(find.text('截至 10/2'), findsOneWidget);
    expect(find.text('4 次'), findsOneWidget);
    expect(find.text('每千股 3,157.03 股'), findsOneWidget);
    expect(find.text('每千股 10 股'), findsOneWidget); // 平均列
    expect(find.text('2023 起 3 年平均'), findsOneWidget);
    expect(find.text('無除權息紀錄'), findsNWidgets(2));
  });
}
```

- [ ] **Step 2: 確認失敗**

Run: `flutter test test/presentation/screens/stock_detail/tabs/fundamentals/dividend_summary_table_test.dart test/presentation/screens/stock_detail/tabs/fundamentals/dividend_summary_table_zh_test.dart`
Expected: FAIL，編譯錯誤 `Error when reading '.../dividend_summary_table.dart'`

- [ ] **Step 3: 翻譯**

`assets/translations/zh-TW.json` 的 `stockDetail` 區塊，把

```json
    "dividendYear": "年度",
    "cashDividend": "現金股利",
    "stockDividend": "股票股利",
    "totalDividend": "合計",
```

換成

```json
    "dividendYear": "除息年度",
    "cashDividend": "現金股利",
    "stockDividend": "股票股利",
    "totalDividend": "合計",
    "dividendAverage": "平均",
    "dividendAverageFull": "近 {years} 年平均",
    "dividendAverageSince": "{year} 起 {years} 年平均",
    "dividendAsOf": "截至 {date}",
    "dividendCashCount": "{count} 次",
    "dividendSharesPerThousand": "每千股 {shares} 股",
    "dividendStatusNone": "無除權息",
    "dividendStatusNoRecord": "無除權息紀錄",
    "dividendStatusNotYet": "尚未除息",
    "dividendStatusBuilding": "建置中",
    "dividendBuilding": "股利資料建置中",
    "dividendUnavailable": "暫無法取得股利資料",
    "trailingYieldLabel": "近一年殖利率",
    "trailingYieldNone": "無配息",
```

`assets/translations/en.json` 的 `stockDetail` 區塊，把

```json
    "dividendYear": "Year",
    "cashDividend": "Cash",
    "stockDividend": "Stock",
    "totalDividend": "Total",
```

換成

```json
    "dividendYear": "Ex-div Year",
    "cashDividend": "Cash",
    "stockDividend": "Stock",
    "totalDividend": "Total",
    "dividendAverage": "Average",
    "dividendAverageFull": "{years}Y average",
    "dividendAverageSince": "{years}Y average since {year}",
    "dividendAsOf": "As of {date}",
    "dividendCashCount": "{count} payouts",
    "dividendSharesPerThousand": "{shares} sh per 1,000",
    "dividendStatusNone": "None",
    "dividendStatusNoRecord": "No record",
    "dividendStatusNotYet": "Not yet",
    "dividendStatusBuilding": "Building",
    "dividendBuilding": "Dividend data is being built",
    "dividendUnavailable": "Dividend data unavailable",
    "trailingYieldLabel": "Trailing 1Y yield",
    "trailingYieldNone": "None",
```

- [ ] **Step 4: 實作**

`lib/presentation/screens/stock_detail/tabs/fundamentals/dividend_summary_table.dart`：

```dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;

import 'package:daredevil/core/constants/api_config.dart';
import 'package:daredevil/core/theme/app_theme.dart';
import 'package:daredevil/core/theme/design_tokens.dart';
import 'package:daredevil/core/utils/number_formatter.dart';
import 'package:daredevil/core/utils/taiwan_date_formatter.dart';
import 'package:daredevil/domain/services/dividend_summary.dart';
import 'package:daredevil/presentation/screens/stock_detail/tabs/fundamentals/fundamentals_helpers.dart';

/// 個股頁股利表：今年＋前幾個完整年度與平均列。年度依除權息日的年份
/// （除息年度），金額與狀態的定義見 [DividendSummary]
class DividendSummaryTable extends StatelessWidget {
  const DividendSummaryTable({
    super.key,
    required this.summary,
    required this.showROCYear,
  });

  final DividendSummary summary;
  final bool showROCYear;

  static final _sharesFormat = intl.NumberFormat('#,##0.##');

  @override
  Widget build(BuildContext context) {
    final rows = [summary.current, ...summary.pastYears];
    final average = summary.average;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(DesignTokens.spacing12),
        child: Column(
          children: [
            buildTableHeader(context, [
              buildHeaderCell(context, 'stockDetail.dividendYear'.tr()),
              buildHeaderCell(
                context,
                'stockDetail.cashDividend'.tr(),
                textAlign: TextAlign.end,
              ),
              buildHeaderCell(
                context,
                'stockDetail.stockDividend'.tr(),
                textAlign: TextAlign.end,
              ),
              buildHeaderCell(
                context,
                'stockDetail.totalDividend'.tr(),
                textAlign: TextAlign.end,
              ),
            ]),
            const SizedBox(height: DesignTokens.spacing8),
            for (final (index, row) in rows.indexed)
              buildTableDataRow(context, index, [
                Expanded(
                  flex: 2,
                  child: _yearCell(context, row, isCurrent: index == 0),
                ),
                ..._rowCells(context, row),
              ]),
            if (average != null) ...[
              const Divider(height: DesignTokens.spacing16),
              buildTableDataRow(
                context,
                rows.length,
                _averageCells(context, average),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _yearCell(
    BuildContext context,
    DividendYearRow row, {
    required bool isCurrent,
  }) {
    final theme = Theme.of(context);
    final end = summary.displayEnd;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          showROCYear
              ? TaiwanDateFormatter.formatDualYear(row.year)
              : '${row.year}',
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        if (isCurrent &&
            end != null &&
            row.status != DividendYearStatus.building)
          Text(
            'stockDetail.dividendAsOf'.tr(
              namedArgs: {'date': '${end.month}/${end.day}'},
            ),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
      ],
    );
  }

  List<Widget> _rowCells(BuildContext context, DividendYearRow row) {
    final status = switch (row.status) {
      DividendYearStatus.paid => null,
      DividendYearStatus.none => 'stockDetail.dividendStatusNone'.tr(),
      DividendYearStatus.noRecord => 'stockDetail.dividendStatusNoRecord'.tr(),
      DividendYearStatus.notYet => 'stockDetail.dividendStatusNotYet'.tr(),
      DividendYearStatus.building => 'stockDetail.dividendStatusBuilding'.tr(),
    };
    if (status != null) return [_statusCell(context, status)];
    return _amountCells(
      context,
      cash: row.cash,
      stockShares: row.stockShares,
      cashCount: row.cashCount,
    );
  }

  List<Widget> _averageCells(BuildContext context, DividendAverage average) {
    final theme = Theme.of(context);
    final labelStyle = theme.textTheme.bodySmall?.copyWith(
      fontWeight: FontWeight.bold,
    );
    return switch (average) {
      DividendAverageValue(
        :final fromYear,
        :final years,
        :final cash,
        :final stockShares,
      ) =>
        [
          Expanded(
            flex: 2,
            child: Text(
              years == ApiConfig.dividendBackfillYears
                  ? 'stockDetail.dividendAverageFull'.tr(
                      namedArgs: {'years': '$years'},
                    )
                  : 'stockDetail.dividendAverageSince'.tr(
                      namedArgs: {'year': '$fromYear', 'years': '$years'},
                    ),
              style: labelStyle,
            ),
          ),
          ..._amountCells(context, cash: cash, stockShares: stockShares),
        ],
      DividendAverageBuilding() => [
        Expanded(
          flex: 2,
          child: Text('stockDetail.dividendAverage'.tr(), style: labelStyle),
        ),
        _statusCell(context, 'stockDetail.dividendStatusBuilding'.tr()),
      ],
    };
  }

  Widget _statusCell(BuildContext context, String text) {
    final theme = Theme.of(context);
    return Expanded(
      flex: 6,
      child: Text(
        text,
        textAlign: TextAlign.end,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  List<Widget> _amountCells(
    BuildContext context, {
    required double cash,
    required double stockShares,
    int cashCount = 0,
  }) {
    final theme = Theme.of(context);
    final stockYuan = summary.stockYuan(stockShares);
    final total = summary.totalYuan(cash, stockShares);
    return [
      Expanded(
        flex: 2,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              cash > 0 ? AppNumberFormat.currency(cash, decimals: 2) : '-',
              textAlign: TextAlign.end,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w500,
                color: cash > 0 ? AppTheme.dividendColor : null,
              ),
            ),
            if (cashCount > 1)
              Text(
                'stockDetail.dividendCashCount'.tr(
                  namedArgs: {'count': '$cashCount'},
                ),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
          ],
        ),
      ),
      Expanded(
        flex: 2,
        child: Text(
          stockShares <= 0
              ? '-'
              : stockYuan != null
              ? AppNumberFormat.currency(stockYuan, decimals: 2)
              : 'stockDetail.dividendSharesPerThousand'.tr(
                  namedArgs: {'shares': _sharesFormat.format(stockShares)},
                ),
          textAlign: TextAlign.end,
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      Expanded(
        flex: 2,
        child: Text(
          total == null
              ? '—'
              : total > 0
              ? AppNumberFormat.currency(total, decimals: 2)
              : '-',
          textAlign: TextAlign.end,
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.primary,
          ),
        ),
      ),
    ];
  }
}
```

- [ ] **Step 5: 確認通過**

Run: `flutter test test/presentation/screens/stock_detail/tabs/fundamentals/ test/core/l10n/`
Expected: 全部 PASS（`app_strings_keys_test` 確認新 key 兩個語系都有；`no_investment_advice_copy_test` 確認文案）

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6: 記錄進度**（不 commit）

---

### Task 3: 個股頁接上摘要（載入器、狀態、頁首錯誤、股利區、ETF 殖利率卡）

**Files:**
- Modify: `lib/data/loaders/stock_fundamentals_loader.dart`
- Modify: `lib/presentation/providers/stock_detail_state.dart`
- Modify: `lib/presentation/providers/stock_detail_provider.dart`（`loadFundamentals`）
- Modify: `lib/presentation/screens/stock_detail/tabs/fundamentals/fundamentals_tab.dart`
- Modify: `lib/core/l10n/app_strings.dart`（移除「基本面」段）
- Modify: `assets/translations/zh-TW.json`、`en.json`（移除舊 key）
- Delete: `lib/presentation/screens/stock_detail/tabs/fundamentals/dividend_table.dart`
- Delete: `test/presentation/screens/stock_detail/tabs/fundamentals/dividend_table_test.dart`
- Test: `test/data/loaders/stock_fundamentals_loader_dividend_test.dart`（新檔）
- Test: `test/data/loaders/stock_fundamentals_loader_test.dart`
- Test: `test/presentation/providers/stock_detail_notifier_test.dart`
- Test: `test/presentation/providers/stock_detail_state_test.dart`
- Test: `test/presentation/screens/stock_detail/tabs/fundamentals_tab_test.dart`

**Interfaces:**
- Consumes: Task 1 的 `DividendSummary.compute`、`allBuilding`、`trailingYield`；Task 2 的 `DividendSummaryTable` 與翻譯 key；`loadDividendCompleteness(AppDatabase db, {required DateTime now})`；`AppDatabase.getStock`、`getDividendDistributions`
- Produces:
  - `FundamentalsResult.dividendSummary`（`DividendSummary?`；取代 `dividendData`）
  - `FundamentalsState.dividendSummary`（`DividendSummary?`；取代 `dividendHistory`）
  - `StockDetailState.copyWith({DividendSummary? dividendSummary, ...})`（取代 `dividendHistory:`）

- [ ] **Step 1: 寫失敗測試**

1. `test/data/loaders/stock_fundamentals_loader_dividend_test.dart`（真的記憶體 DB）：

```dart
// 個股頁股利摘要的載入：只讀 DB（配發表、完整度事實、股票名稱），不打
// FinMind 股利 API；資料不完整是摘要裡的建置中，只有讀取失敗回 null
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:daredevil/core/constants/market_codes.dart';
import 'package:daredevil/core/utils/calendar_month.dart';
import 'package:daredevil/core/utils/clock.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/data/loaders/stock_fundamentals_loader.dart';
import 'package:daredevil/data/remote/finmind_client.dart';
import 'package:daredevil/domain/services/dividend_summary.dart';

class _MockFinMind extends Mock implements FinMindClient {}

class _MockDb extends Mock implements AppDatabase {}

class _Clock implements AppClock {
  @override
  DateTime now() => DateTime(2026, 10, 2, 21, 30);
}

void main() {
  late AppDatabase db;
  late _MockFinMind finMind;
  late StockFundamentalsLoader loader;

  setUp(() async {
    db = AppDatabase.forTesting();
    finMind = _MockFinMind();
    when(
      () => finMind.getMonthlyRevenue(
        stockId: any(named: 'stockId'),
        startDate: any(named: 'startDate'),
        endDate: any(named: 'endDate'),
      ),
    ).thenAnswer((_) async => []);
    when(
      () => finMind.getPERData(
        stockId: any(named: 'stockId'),
        startDate: any(named: 'startDate'),
        endDate: any(named: 'endDate'),
      ),
    ).thenAnswer((_) async => []);
    loader = StockFundamentalsLoader(db: db, finMind: finMind, clock: _Clock());
    await db.upsertStocks([
      StockMasterCompanion.insert(symbol: '2330', name: '台積電', market: 'TWSE'),
      StockMasterCompanion.insert(symbol: '5314', name: '世紀*', market: 'TPEx'),
    ]);
  });

  tearDown(() => db.close());

  /// 兩市場自回補起點 2021-01 到 2026-09 都完成、10 月列到 10/2（顯示終點
  /// 要從回補起點連續才算得出來）
  Future<void> seedFacts() async {
    for (final market in [MarketCode.twse, MarketCode.tpex]) {
      for (final m in CalendarMonth.descending(
        from: const CalendarMonth(2021, 1),
        to: const CalendarMonth(2026, 9),
      )) {
        await db.completeDividendMonth(
          market: market,
          month: m,
          rows: const [],
          expectedKeys: const {},
          listedRows: 0,
          skippedSymbols: const {},
          completedAt: DateTime(2026, 10, 1),
        );
      }
      await db.recordDividendListing(
        market: market,
        from: DateTime(2026, 10, 1),
        to: DateTime(2026, 10, 2),
        listedThrough: DateTime(2026, 10, 2),
        listedKnownKeys: const {},
        notInMasterKeys: const {},
        recordedAt: DateTime(2026, 10, 2, 15),
      );
    }
  }

  test('配發表＋完整度事實 → 摘要；不打 FinMind 股利 API', () async {
    await seedFacts();
    await db.upsertDividendDistributions([
      DividendDistributionCompanion.insert(
        symbol: '2330',
        exDate: DateTime(2025, 9, 16),
        cashDividend: 5,
        stockSharesPerThousand: 0,
        closeBefore: const Value(1200),
        referencePrice: const Value(1195),
      ),
    ]);

    final result = await loader.loadAll('2330');

    final summary = result.dividendSummary!;
    expect(summary.displayEnd, DateTime(2026, 10, 2));
    expect(summary.parValueTen, isTrue); // 名稱來自主檔「台積電」
    expect(summary.pastYears.first.status, DividendYearStatus.paid);
    expect(summary.pastYears.first.cash, 5);
    final average = summary.average as DividendAverageValue;
    expect(average.fromYear, 2025);
    expect(average.cash, 5);
    // 兩種呼叫形狀都驗：mocktail 依具名參數的組合比對
    verifyNever(() => finMind.getDividends(stockId: any(named: 'stockId')));
    verifyNever(
      () => finMind.getDividends(
        stockId: any(named: 'stockId'),
        startDate: any(named: 'startDate'),
      ),
    );
  });

  test('名稱帶 *：摘要不假設面額 10 元', () async {
    await seedFacts();
    final result = await loader.loadAll('5314');
    expect(result.dividendSummary!.parValueTen, isFalse);
  });

  test('🚨 尚無任何完整度事實（新安裝）：摘要全部建置中，不是讀取失敗', () async {
    final result = await loader.loadAll('2330');
    expect(result.dividendSummary, isNotNull);
    expect(result.dividendSummary!.allBuilding, isTrue);
  });

  test('讀取失敗：摘要為 null，不往外拋', () async {
    final brokenDb = _MockDb();
    when(() => brokenDb.getStock(any())).thenThrow(Exception('db locked'));
    final brokenLoader = StockFundamentalsLoader(
      db: brokenDb,
      finMind: finMind,
      clock: _Clock(),
    );

    final result = await brokenLoader.loadAll('2330');

    expect(result.dividendSummary, isNull);
  });
}
```

2. `test/presentation/providers/stock_detail_state_test.dart`：`FundamentalsState` 的 'default values' 裡 `expect(state.dividendHistory, isEmpty);` 改成 `expect(state.dividendSummary, isNull);`。

3. `test/presentation/providers/stock_detail_notifier_test.dart`，group `'StockDetailNotifier.loadFundamentals'` 內、既有的 'handles error gracefully' 之後加（斷言只用到 `allBuilding`，不需新增 import）：

```dart
    /// 營收（6 個月）、EPS、估值都有：頁首錯誤只會來自股利
    void stubFundamentalsReads({Exception? dividendError}) {
      when(
        () => mockDb.getValuationHistory(
          _testSymbol,
          startDate: any(named: 'startDate'),
        ),
      ).thenAnswer(
        (_) async => [
          StockValuationEntry(
            symbol: _testSymbol,
            date: _defaultDate,
            per: 20,
            pbr: 5,
            dividendYield: 2,
          ),
        ],
      );
      when(
        () => mockDb.getMonthlyRevenueHistory(
          _testSymbol,
          startDate: any(named: 'startDate'),
        ),
      ).thenAnswer(
        (_) async => [
          for (var m = 1; m <= 6; m++)
            MonthlyRevenueEntry(
              symbol: _testSymbol,
              date: DateTime(2025, m + 1, 10),
              revenueYear: 2025,
              revenueMonth: m,
              revenue: 1e9,
            ),
        ],
      );
      when(() => mockDb.getEPSHistory(_testSymbol)).thenAnswer(
        (_) async => [
          FinancialDataEntry(
            symbol: _testSymbol,
            date: DateTime(2025, 11, 14),
            statementType: 'INCOME',
            dataType: 'EPS',
            value: 5,
          ),
        ],
      );
      when(
        () => mockDb.getLatestQuarterMetrics(_testSymbol),
      ).thenAnswer((_) async => {'ROE': 20.0});
      when(
        () => mockDb.getDividendDistributions(_testSymbol),
      ).thenAnswer((_) async => []);
      if (dividendError != null) {
        when(() => mockDb.getDividendListings()).thenThrow(dividendError);
      } else {
        when(() => mockDb.getDividendListings()).thenAnswer((_) async => []);
      }
      when(
        () => mockDb.getDividendMonthLedgerEntries(),
      ).thenAnswer((_) async => []);
      when(() => mockDb.getDividendUnresolved()).thenAnswer((_) async => []);
      when(
        () => mockDb.getDividendMissingPriceKeys(),
      ).thenAnswer((_) async => <(String, DateTime)>{});
    }

    test('🚨 股利資料建置中（新安裝、尚無完整度事實）：頁首不出現錯誤', () async {
      setupLoadDataMocks();
      stubFundamentalsReads();

      final notifier = container.read(
        stockDetailProvider(_testSymbol).notifier,
      );
      await notifier.loadData();
      await notifier.loadFundamentals();

      final state = container.read(stockDetailProvider(_testSymbol));
      expect(state.fundamentals.dividendSummary!.allBuilding, isTrue);
      expect(state.fundamentalsError, isNull);
    });

    test('股利讀取失敗：頁首錯誤含「股利」（可重試）', () async {
      setupLoadDataMocks();
      stubFundamentalsReads(dividendError: Exception('db locked'));

      final notifier = container.read(
        stockDetailProvider(_testSymbol).notifier,
      );
      await notifier.loadData();
      await notifier.loadFundamentals();

      final state = container.read(stockDetailProvider(_testSymbol));
      expect(state.fundamentals.dividendSummary, isNull);
      expect(state.fundamentalsError, contains('股利'));
    });
```

4. `test/presentation/screens/stock_detail/tabs/fundamentals_tab_test.dart`：
   - import 區加：

```dart
import 'package:daredevil/domain/services/dividend_summary.dart';
import 'package:daredevil/presentation/screens/stock_detail/tabs/fundamentals/dividend_summary_table.dart';
```

   - `buildTestWidget` 加 `String symbol = '2330'` 參數，`const FundamentalsTab(symbol: '2330')` 改成 `FundamentalsTab(symbol: symbol)`。
   - `main()` 開頭（`setUpAll` 之前）加：

```dart
  DividendSummary summary({
    DividendYearStatus status = DividendYearStatus.paid,
    TrailingYield trailing = const TrailingYieldNone(),
  }) => DividendSummary(
    displayEnd: DateTime(2026, 10, 2),
    parValueTen: true,
    current: DividendYearRow(year: 2026, status: status, cash: 1),
    pastYears: [
      for (var y = 2025; y >= 2021; y--)
        DividendYearRow(year: y, status: status, cash: 1),
    ],
    average: null,
    trailingYield: trailing,
  );
```

   - group `'FundamentalsTab'` 最後加：

```dart
    testWidgets('股利摘要已載入：顯示股利表', (tester) async {
      widenViewport(tester);
      final state = const StockDetailState().copyWith(
        dividendSummary: summary(),
      );
      await tester.pumpWidget(buildTestWidget(stockState: state));
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(DividendSummaryTable), findsOneWidget);
    });

    testWidgets('🚨 全部建置中：顯示「股利資料建置中」、不畫表', (tester) async {
      widenViewport(tester);
      final state = const StockDetailState().copyWith(
        dividendSummary: summary(status: DividendYearStatus.building),
      );
      await tester.pumpWidget(buildTestWidget(stockState: state));
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('stockDetail.dividendBuilding'), findsOneWidget);
      expect(find.byType(DividendSummaryTable), findsNothing);
    });

    testWidgets('股利讀取失敗（沒有摘要、有錯誤）：顯示暫無法取得', (tester) async {
      widenViewport(tester);
      final state = const StockDetailState().copyWith(
        fundamentalsError: '部分基本面資料暫無法取得（股利）',
      );
      await tester.pumpWidget(buildTestWidget(stockState: state));
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('stockDetail.dividendUnavailable'), findsOneWidget);
      expect(find.byType(DividendSummaryTable), findsNothing);
    });

    testWidgets('ETF：殖利率卡顯示近一年殖利率', (tester) async {
      widenViewport(tester);
      final state = const StockDetailState().copyWith(
        dividendSummary: summary(trailing: const TrailingYieldValue(0.0209)),
      );
      await tester.pumpWidget(
        buildTestWidget(stockState: state, symbol: '0050'),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('2.09%'), findsOneWidget);
      expect(find.text('stockDetail.trailingYieldLabel'), findsOneWidget);
      expect(find.text('stockDetail.yieldLabel'), findsNothing);
    });

    testWidgets('ETF：近一年無配息', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(
        buildTestWidget(
          stockState: const StockDetailState().copyWith(
            dividendSummary: summary(trailing: const TrailingYieldNone()),
          ),
          symbol: '0050',
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('stockDetail.trailingYieldNone'), findsOneWidget);
    });

    // 同一個測試內重 pump 新的 override 不會重建已建立的 notifier，所以分開
    testWidgets('ETF：近一年殖利率建置中', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(
        buildTestWidget(
          stockState: const StockDetailState().copyWith(
            dividendSummary: summary(trailing: const TrailingYieldBuilding()),
          ),
          symbol: '0050',
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('stockDetail.dividendStatusBuilding'), findsOneWidget);
    });

    testWidgets('一般股票：殖利率卡照舊用官方估值、不看近一年殖利率', (tester) async {
      widenViewport(tester);
      final state = const StockDetailState().copyWith(
        latestPER: const FinMindPER(
          stockId: '2330',
          date: '2026-02-20',
          per: 18.5,
          pbr: 4.32,
          dividendYield: 2.15,
        ),
        dividendSummary: summary(trailing: const TrailingYieldValue(0.05)),
      );
      await tester.pumpWidget(buildTestWidget(stockState: state));
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('2.15%'), findsOneWidget);
      expect(find.text('5.00%'), findsNothing);
      expect(find.text('stockDetail.yieldLabel'), findsOneWidget);
    });
```

- [ ] **Step 2: 拿掉過時的測試**

1. `test/data/loaders/stock_fundamentals_loader_test.dart`：
   - 四個 group 的 setUp 裡各有一段 `when(() => mockDb.getDividendHistory(any())).thenAnswer((_) async => <DividendHistoryEntry>[]);`（約第 110、210、351、480 行），全部刪掉。
   - group `'RateLimit rethrow 契約'` 的 setUp 刪掉 `when(() => mockFinMind.getDividends(stockId: any(named: 'stockId'))).thenAnswer((_) async => <FinMindDividend>[]);`。
   - 刪掉整個 test `'股利 API 限流:rethrow'`：股利不再打 API，限流契約只剩營收與估值。
2. 刪除 `test/presentation/screens/stock_detail/tabs/fundamentals/dividend_table_test.dart`。

- [ ] **Step 3: 確認失敗**

Run: `flutter test test/data/loaders/ test/presentation/providers/stock_detail_notifier_test.dart test/presentation/providers/stock_detail_state_test.dart test/presentation/screens/stock_detail/tabs/fundamentals_tab_test.dart`
Expected: FAIL，編譯錯誤 `The getter 'dividendSummary' isn't defined` 與 `No named parameter with the name 'dividendSummary'`

- [ ] **Step 4: 實作**

1. `lib/data/loaders/stock_fundamentals_loader.dart`：
   - import 區刪掉 `import 'dart:async';` 與 `import 'package:drift/drift.dart';`，加：

```dart
import 'package:daredevil/domain/services/dividend_completeness.dart';
import 'package:daredevil/domain/services/dividend_summary.dart';
```

   - `FundamentalsResult` 的 `List<FinMindDividend> dividendData,` 改成：

```dart
  /// 股利摘要；null＝讀取失敗（資料不完整是摘要裡的建置中，不是 null）
  DividendSummary? dividendSummary,
```

   - 類別註解第一段改成：

```dart
/// 基本面資料載入器
///
/// 負責載入營收、股利、估值、EPS 等基本面資料：營收與估值在 DB 不足時改打
/// FinMind；股利只讀 DB（除權除息配發表與完整度事實）。純資料取得邏輯，不
/// 管理 UI 狀態。
```

   - `loadAll` 的第 3 步改成：

```dart
    // 3. 股利摘要：只讀配發表與完整度事實
    final dividendSummary = await _loadDividendSummary(symbol, today);
```

     回傳的 `dividendData: dividendData,` 改成 `dividendSummary: dividendSummary,`。
   - 整個 `_loadDividendHistory` 換成：

```dart
  /// 載入股利摘要：只讀 DB（股票名稱、配發表、完整度事實）。資料不完整的
  /// 年度在摘要裡是「建置中」，不是錯誤；只有讀取失敗回傳 null，頁首才提示
  /// 「股利」並可重試
  Future<DividendSummary?> _loadDividendSummary(
    String symbol,
    DateTime today,
  ) async {
    try {
      final stock = await _db.getStock(symbol);
      final rows = await _db.getDividendDistributions(symbol);
      final completeness = await loadDividendCompleteness(_db, now: today);
      return DividendSummary.compute(
        symbol: symbol,
        name: stock?.name,
        rows: rows,
        completeness: completeness,
      );
    } catch (e) {
      AppLogger.warning('StockFundamentalsLoader', '$symbol: 讀取股利資料失敗', e);
      return null;
    }
  }
```

2. `lib/presentation/providers/stock_detail_state.dart`：
   - import 區加 `import 'package:daredevil/domain/services/dividend_summary.dart';`。
   - `FundamentalsState`：建構子的 `this.dividendHistory = const [],` 改成 `this.dividendSummary,`；欄位改成：

```dart
  /// 股利摘要；null＝尚未載入或讀取失敗（資料不完整是摘要裡的建置中）
  final DividendSummary? dividendSummary;
```

     `copyWith` 的參數改成 `DividendSummary? dividendSummary,`，內容改成 `dividendSummary: dividendSummary ?? this.dividendSummary,`。
   - `StockDetailState.copyWith`：參數 `List<FinMindDividend>? dividendHistory,` 改成 `DividendSummary? dividendSummary,`；`needsFundamentalsUpdate` 的 `dividendHistory != null ||` 改成 `dividendSummary != null ||`；`fundamentals.copyWith(` 內的 `dividendHistory: dividendHistory,` 改成 `dividendSummary: dividendSummary,`。

3. `lib/presentation/providers/stock_detail_provider.dart` 的 `loadFundamentals`：
   - `state.fundamentals.dividendHistory.isNotEmpty;` 改成 `state.fundamentals.dividendSummary != null;`。
   - `missingParts` 改成：

```dart
      // 股利資料不完整是摘要裡的「建置中」，不是缺漏：只有讀取失敗（null）
      // 才列入，避免頁首紅字與無效的重試
      final missingParts = <String>[
        if (result.revenueData.isEmpty) '營收',
        if (result.epsData.isEmpty) '每股盈餘',
        if (result.dividendSummary == null) '股利',
        if (result.latestPER == null) '估值',
      ];
```

   - `state.copyWith(` 內的 `dividendHistory: result.dividendData,` 改成 `dividendSummary: result.dividendSummary,`。

4. `lib/presentation/screens/stock_detail/tabs/fundamentals/fundamentals_tab.dart`：
   - import 區刪掉 `dividend_table.dart`，加：

```dart
import 'package:daredevil/core/constants/stock_patterns.dart';
import 'package:daredevil/domain/services/dividend_summary.dart';
import 'package:daredevil/presentation/screens/stock_detail/tabs/fundamentals/dividend_summary_table.dart';
```

   - 股利區段 `SectionHeader` 與其後 `SizedBox` 之後，從 `if (isLoadingFundamentals)` 到 `DividendTable(...)` 的整段換成：

```dart
          if (isLoadingFundamentals)
            buildLoadingState(context)
          else if (fundamentals.dividendSummary case final summary?)
            summary.allBuilding
                ? buildEmptyState(context, 'stockDetail.dividendBuilding'.tr())
                : DividendSummaryTable(
                    summary: summary,
                    showROCYear: showROCYear,
                  )
          else if (fundamentalsError != null)
            buildEmptyState(context, 'stockDetail.dividendUnavailable'.tr()),
```

   - `_buildMetricsRow` 的第三張卡（殖利率）整個 `Expanded(child: MetricCard(...))` 換成 `Expanded(child: _buildYieldCard(fundamentals, brightness)),`，並在 `_buildMetricsRow` 之後加：

```dart
  /// 殖利率卡：一般股票用官方估值；ETF 沒有官方估值，改顯示近一年殖利率
  Widget _buildYieldCard(FundamentalsState fundamentals, Brightness brightness) {
    if (!StockPatterns.isEtfCode(widget.symbol)) {
      final per = fundamentals.latestPER;
      return MetricCard(
        label: 'stockDetail.yield'.tr(),
        value: per != null && per.dividendYield > 0
            ? '${per.dividendYield.toStringAsFixed(2)}%'
            : '-',
        icon: Icons.percent,
        accentColor: _kYieldColor(brightness),
        subtitle: 'stockDetail.yieldLabel'.tr(),
      );
    }
    return MetricCard(
      label: 'stockDetail.yield'.tr(),
      value: switch (fundamentals.dividendSummary?.trailingYield) {
        TrailingYieldValue(:final ratio) =>
          '${(ratio * 100).toStringAsFixed(2)}%',
        TrailingYieldNone() => 'stockDetail.trailingYieldNone'.tr(),
        TrailingYieldBuilding() => 'stockDetail.dividendStatusBuilding'.tr(),
        null => '-',
      },
      icon: Icons.percent,
      accentColor: _kYieldColor(brightness),
      subtitle: 'stockDetail.trailingYieldLabel'.tr(),
    );
  }
```

5. 刪除 `lib/presentation/screens/stock_detail/tabs/fundamentals/dividend_table.dart`。
6. `lib/core/l10n/app_strings.dart`：刪掉「基本面」整段（分隔註解三行與 `dividendYearAverage` 方法），它唯一的使用者是剛刪的 `DividendTable`。
7. 兩個翻譯檔：
   - 刪掉 `stockDetail` 的 `"dividendComingSoon": ...` 一行。
   - 刪掉整個 `"fundamental": { "dividendYearAverage": ... },` 區塊（三行）。

- [ ] **Step 5: 確認通過**

Run: `flutter test test/data/loaders/ test/presentation/providers/stock_detail_notifier_test.dart test/presentation/providers/stock_detail_state_test.dart test/presentation/screens/stock_detail/ test/core/l10n/`
Expected: 全部 PASS

Run: `grep -rn "dividendComingSoon\|dividendYearAverage\|DividendTable\b\|fundamentals\.dividendHistory\|dividendData\b\|dividendHistory:" lib test --include='*.dart'`
Expected: 沒有輸出（翻譯 key `stockDetail.dividendHistory`「股利紀錄」是區段標題，保留）

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6: 記錄進度**（不 commit）

---

### Task 4: 投資組合預估年股利與趨勢

**Files:**
- Modify: `lib/core/constants/analysis_params.dart`（`dividendLookbackYears` 換成趨勢門檻）
- Modify: `lib/domain/services/dividend_intelligence_service.dart`（改寫）
- Modify: `lib/presentation/providers/portfolio_provider.dart`
- Modify: `lib/presentation/screens/portfolio/widgets/dividend_analysis_card.dart`
- Modify: `assets/translations/zh-TW.json`、`en.json`（`portfolio` 區塊）
- Test: `test/domain/services/dividend_intelligence_service_test.dart`（整檔改寫）
- Test: `test/presentation/providers/portfolio_provider_test.dart`
- Test: `test/presentation/screens/portfolio/widgets/dividend_analysis_card_test.dart`

**Interfaces:**
- Consumes: Task 1 的 `DividendSummary.compute`、`pastYears`、`trailingYield`；`loadDividendCompleteness`；`AppDatabase.getDividendDistributionsBatch`、`getLatestValuationsBatch`、`getPriceOnDate`；`appClockProvider`
- Produces:
  - `typedef OfficialYield = ({double yieldPercent, double close});`
  - `const DividendIntelligenceService()`（不再帶 clock）
  - `DividendAnalysis analyzeDividends({required List<PortfolioPositionEntry> positions, required Map<String, DividendSummary> summaries, required Map<String, OfficialYield> officialYields, required Map<String, double> currentPrices})`
  - `DividendAnalysis.totalExpectedDividend`／`portfolioYieldOnCost`／`portfolioYieldOnMarket` 改成 `double?`
  - `StockDividendInfo.estimatedDividendPerShare`／`expectedYearlyAmount`／`personalYield` 改成 `double?`，`trend` 改成 `DividendTrend?`
  - `AnalysisParams.dividendTrendChangePercent`（10.0）

- [ ] **Step 1: 寫失敗測試**

1. `test/domain/services/dividend_intelligence_service_test.dart` 整檔換成：

```dart
// 投資組合股利分析：預估年股利＝官方殖利率 × 同一天收盤價，其餘（ETF、無
// 估值）＝近一年殖利率 × 最新收盤價；趨勢比最近兩個完整年度的現金股利。
// 資料建置中一律 null（畫面顯示建置中），不加部分總和
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/domain/services/dividend_intelligence_service.dart';
import 'package:daredevil/domain/services/dividend_summary.dart';

import '../../helpers/portfolio_data_builders.dart';

/// [pastCash]：去年起往前的現金股利，null＝建置中
DividendSummary _summary({
  TrailingYield trailing = const TrailingYieldBuilding(),
  List<double?> pastCash = const [null, null, null, null, null],
  List<double> pastShares = const [0, 0, 0, 0, 0],
}) => DividendSummary(
  displayEnd: DateTime(2026, 10, 2),
  parValueTen: true,
  current: const DividendYearRow(
    year: 2026,
    status: DividendYearStatus.notYet,
  ),
  pastYears: [
    for (final (i, cash) in pastCash.indexed)
      cash == null
          ? DividendYearRow(year: 2025 - i, status: DividendYearStatus.building)
          : DividendYearRow(
              year: 2025 - i,
              status: cash > 0 || pastShares[i] > 0
                  ? DividendYearStatus.paid
                  : DividendYearStatus.none,
              cash: cash,
              stockShares: pastShares[i],
            ),
  ],
  average: null,
  trailingYield: trailing,
);

const _svc = DividendIntelligenceService();

StockDividendInfo _single({
  OfficialYield? official,
  DividendSummary? summary,
  double? latestClose,
  double avgCost = 50,
}) {
  final result = _svc.analyzeDividends(
    positions: [
      createTestPortfolioPosition(
        symbol: '1111',
        quantity: 1000,
        avgCost: avgCost,
      ),
    ],
    summaries: {'1111': ?summary},
    officialYields: {'1111': ?official},
    currentPrices: {'1111': ?latestClose},
  );
  return result.stockDividends.single;
}

void main() {
  group('預估年股利（每股）', () {
    test('🚨 有官方估值：官方殖利率 × 同一天收盤價，不是最新收盤', () {
      final info = _single(
        official: (yieldPercent: 2.0, close: 500),
        summary: _summary(trailing: const TrailingYieldValue(0.05)),
        latestClose: 600,
      );
      expect(info.estimatedDividendPerShare, closeTo(10, 1e-9));
      expect(info.expectedYearlyAmount, closeTo(10000, 1e-6));
    });

    test('有官方估值時，近一年殖利率建置中也不影響', () {
      final info = _single(
        official: (yieldPercent: 2.0, close: 500),
        summary: _summary(),
        latestClose: 600,
      );
      expect(info.estimatedDividendPerShare, closeTo(10, 1e-9));
    });

    test('沒有官方估值（ETF、無估值）：近一年殖利率 × 最新收盤價', () {
      final info = _single(
        summary: _summary(trailing: const TrailingYieldValue(0.04)),
        latestClose: 50,
      );
      expect(info.estimatedDividendPerShare, closeTo(2, 1e-9));
    });

    test('🚨 近一年無配息：預估 0（不是建置中）', () {
      final info = _single(
        summary: _summary(trailing: const TrailingYieldNone()),
        latestClose: 50,
      );
      expect(info.estimatedDividendPerShare, 0);
      expect(info.expectedYearlyAmount, 0);
      expect(info.personalYield, 0);
    });

    test('近一年殖利率建置中、沒有最新收盤、沒有摘要：null', () {
      expect(
        _single(summary: _summary(), latestClose: 50).estimatedDividendPerShare,
        isNull,
      );
      expect(
        _single(
          summary: _summary(trailing: const TrailingYieldValue(0.04)),
        ).estimatedDividendPerShare,
        isNull,
      );
      expect(_single(latestClose: 50).estimatedDividendPerShare, isNull);
    });

    test('個人殖利率＝預估金額 ÷ 成本', () {
      final info = _single(
        official: (yieldPercent: 2.0, close: 500),
        avgCost: 400,
      );
      expect(info.personalYield, closeTo(2.5, 1e-9)); // 10 ÷ 400
    });
  });

  group('組合合計', () {
    test('全部有預估：加總與兩種殖利率', () {
      final result = _svc.analyzeDividends(
        positions: [
          createTestPortfolioPosition(
            id: 1,
            symbol: 'A',
            quantity: 1000,
            avgCost: 100,
          ),
          createTestPortfolioPosition(
            id: 2,
            symbol: 'B',
            quantity: 2000,
            avgCost: 50,
          ),
        ],
        summaries: {'B': _summary(trailing: const TrailingYieldValue(0.05))},
        officialYields: {'A': (yieldPercent: 4.0, close: 125)},
        currentPrices: {'A': 125, 'B': 40},
      );
      // A：4% × 125＝5 元 × 1000＝5000；B：5% × 40＝2 元 × 2000＝4000
      expect(result.totalExpectedDividend, closeTo(9000, 1e-6));
      expect(result.portfolioYieldOnCost, closeTo(4.5, 1e-9)); // ÷ 200,000
      expect(
        result.portfolioYieldOnMarket,
        closeTo(9000 / 205000 * 100, 1e-9),
      );
    });

    test('🚨 任一持股建置中：合計與兩種殖利率都是 null（不加部分總和）', () {
      final result = _svc.analyzeDividends(
        positions: [
          createTestPortfolioPosition(
            id: 1,
            symbol: 'A',
            quantity: 1000,
            avgCost: 100,
          ),
          createTestPortfolioPosition(
            id: 2,
            symbol: '0050',
            quantity: 1000,
            avgCost: 100,
          ),
        ],
        summaries: {'0050': _summary()},
        officialYields: {'A': (yieldPercent: 4.0, close: 125)},
        currentPrices: {'A': 125, '0050': 110},
      );
      expect(result.totalExpectedDividend, isNull);
      expect(result.portfolioYieldOnCost, isNull);
      expect(result.portfolioYieldOnMarket, isNull);
      expect(
        result.stockDividends.first.expectedYearlyAmount,
        closeTo(5000, 1e-6),
      );
    });

    test('依預估金額由大到小，建置中排最後', () {
      final result = _svc.analyzeDividends(
        positions: [
          createTestPortfolioPosition(id: 1, symbol: 'X'),
          createTestPortfolioPosition(id: 2, symbol: 'S'),
          createTestPortfolioPosition(id: 3, symbol: 'L'),
        ],
        summaries: {'X': _summary()},
        officialYields: {
          'S': (yieldPercent: 1.0, close: 100),
          'L': (yieldPercent: 5.0, close: 100),
        },
        currentPrices: const {},
      );
      expect(result.stockDividends.map((s) => s.symbol), ['L', 'S', 'X']);
    });

    test('已出清的持股（數量 0）不列入', () {
      final result = _svc.analyzeDividends(
        positions: [createTestPortfolioPosition(symbol: 'A', quantity: 0)],
        summaries: const {},
        officialYields: const {},
        currentPrices: const {},
      );
      expect(result.stockDividends, isEmpty);
      expect(result.totalExpectedDividend, 0);
    });

    test('沒有持股：empty', () {
      final result = _svc.analyzeDividends(
        positions: const [],
        summaries: const {},
        officialYields: const {},
        currentPrices: const {},
      );
      expect(result, same(DividendAnalysis.empty));
    });
  });

  group('趨勢（最近兩個完整年度的現金股利）', () {
    DividendTrend? trend(
      List<double?> pastCash, {
      List<double> pastShares = const [0, 0, 0, 0, 0],
    }) => _single(
      summary: _summary(pastCash: pastCash, pastShares: pastShares),
    ).trend;

    test('現金增加超過 10%：增加；減少超過 10%：減少；其餘持平', () {
      expect(trend([1.125, 1, 0, 0, 0]), DividendTrend.increasing);
      expect(trend([1.09375, 1, 0, 0, 0]), DividendTrend.stable);
      expect(trend([0.875, 1, 0, 0, 0]), DividendTrend.decreasing);
      expect(trend([0.90625, 1, 0, 0, 0]), DividendTrend.stable);
    });

    test('只比現金、不看配股（面額不一定 10 元）', () {
      expect(
        trend([1, 1, 0, 0, 0], pastShares: [100, 0, 0, 0, 0]),
        DividendTrend.stable,
      );
    });

    test('前一年沒有配發：今年有就是增加，都沒有就是持平', () {
      expect(trend([1, 0, 0, 0, 0]), DividendTrend.increasing);
      expect(trend([0, 0, 0, 0, 0]), DividendTrend.stable);
    });

    test('🚨 任一年建置中：不顯示趨勢（null）', () {
      expect(trend([null, 1, 0, 0, 0]), isNull);
      expect(trend([1, null, 0, 0, 0]), isNull);
    });

    test('只看去年與前年：更早的年度不影響', () {
      expect(trend([1, 1, null, 9, 9]), DividendTrend.stable);
    });

    test('沒有摘要：不顯示趨勢', () {
      expect(_single(official: (yieldPercent: 2.0, close: 500)).trend, isNull);
    });
  });
}
```

2. `test/presentation/screens/portfolio/widgets/dividend_analysis_card_test.dart`，group `'DividendAnalysisCard'` 最後加：

```dart
    testWidgets('🚨 合計建置中：三個總覽值都顯示建置中', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(
        buildTestApp(
          DividendAnalysisCard(
            analysis: DividendAnalysis(
              totalExpectedDividend: null,
              portfolioYieldOnCost: null,
              portfolioYieldOnMarket: null,
              stockDividends: [createStockInfo()],
            ),
          ),
        ),
      );

      expect(find.text('portfolio.dividendBuilding'), findsNWidgets(3));
    });

    testWidgets('單檔建置中：每股顯示建置中、預期與殖利率「—」、不顯示趨勢', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(
        buildTestApp(
          const DividendAnalysisCard(
            analysis: DividendAnalysis(
              totalExpectedDividend: null,
              portfolioYieldOnCost: null,
              portfolioYieldOnMarket: null,
              stockDividends: [
                StockDividendInfo(
                  symbol: '0050',
                  estimatedDividendPerShare: null,
                  expectedYearlyAmount: null,
                  personalYield: null,
                  trend: null,
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.text('portfolio.dividendBuilding'), findsNWidgets(4));
      expect(find.text('—'), findsNWidgets(2));
      expect(find.byIcon(Icons.trending_up), findsNothing);
      expect(find.byIcon(Icons.trending_flat), findsNothing);
      expect(find.byIcon(Icons.trending_down), findsNothing);
    });
```

3. `test/presentation/providers/portfolio_provider_test.dart`：
   - import 區加：

```dart
import 'package:daredevil/core/constants/market_codes.dart';
import 'package:daredevil/core/utils/calendar_month.dart';
import 'package:daredevil/core/utils/clock.dart';
```

   - Mocks 區加：

```dart
class _FixedClock implements AppClock {
  @override
  DateTime now() => DateTime(2026, 10, 2, 21, 30);
}
```

   - `main()` 的 `setUp` 之前加 `setUpAll(() => registerFallbackValue(DateTime(2026)));`；`ProviderContainer` 的 overrides 加 `appClockProvider.overrideWithValue(_FixedClock()),`。
   - group `'PortfolioNotifier'` 開頭加兩個 helper：

```dart
    void stubPositions(
      List<PortfolioPositionEntry> positions, {
      required double close,
    }) {
      when(
        () => mockDb.getPortfolioPositions(),
      ).thenAnswer((_) async => positions);
      when(() => mockDb.getStocksBatch(any())).thenAnswer(
        (_) async => {
          for (final p in positions) p.symbol: createStock(symbol: p.symbol),
        },
      );
      when(() => mockDb.getLatestPricesBatch(any())).thenAnswer(
        (_) async => {
          for (final p in positions)
            p.symbol: createPrice(symbol: p.symbol, close: close),
        },
      );
      when(
        () => mockDb.getAllPortfolioTransactions(),
      ).thenAnswer((_) async => []);
    }

    /// 股利分析的讀取：完整度事實、配發表、官方估值與估值日收盤
    void stubDividendReads({
      List<DividendListingEntry> listings = const [],
      List<DividendMonthLedgerEntry> ledger = const [],
      Map<String, List<DividendDistributionEntry>> distributions = const {},
      Map<String, StockValuationEntry> valuations = const {},
      Map<(String, DateTime), DailyPriceEntry> pricesOnDate = const {},
    }) {
      when(
        () => mockDb.getDividendListings(),
      ).thenAnswer((_) async => listings);
      when(
        () => mockDb.getDividendMonthLedgerEntries(),
      ).thenAnswer((_) async => ledger);
      when(() => mockDb.getDividendUnresolved()).thenAnswer((_) async => []);
      when(
        () => mockDb.getDividendMissingPriceKeys(),
      ).thenAnswer((_) async => <(String, DateTime)>{});
      when(
        () => mockDb.getDividendDistributionsBatch(any()),
      ).thenAnswer((_) async => distributions);
      when(
        () => mockDb.getLatestValuationsBatch(any()),
      ).thenAnswer((_) async => valuations);
      when(() => mockDb.getPriceOnDate(any(), any())).thenAnswer(
        (inv) async => pricesOnDate[(
          inv.positionalArguments[0] as String,
          inv.positionalArguments[1] as DateTime,
        )],
      );
    }
```

   - 'loadPositions loads positions with stock info and prices' 裡的 `when(() => mockDb.getDividendHistoryBatch(any())).thenAnswer((_) async => {});` 換成 `stubDividendReads();`。
   - group 最後加：

```dart
    test('股利分析：官方殖利率 × 估值日收盤（不是最新收盤）', () async {
      stubPositions([
        createPosition(id: 1, symbol: '2330', quantity: 1000, avgCost: 500),
      ], close: 1200);
      stubDividendReads(
        valuations: {
          '2330': StockValuationEntry(
            symbol: '2330',
            date: DateTime(2026, 9, 30),
            per: 20,
            pbr: 5,
            dividendYield: 2.0,
          ),
        },
        pricesOnDate: {
          ('2330', DateTime(2026, 9, 30)): createPrice(
            symbol: '2330',
            close: 1000,
          ),
        },
      );

      await container.read(portfolioProvider.notifier).loadPositions();

      final info = container
          .read(portfolioProvider)
          .dividendAnalysis!
          .stockDividends
          .single;
      expect(info.estimatedDividendPerShare, closeTo(20, 1e-9));
    });

    test('🚨 股利分析：估值日沒有收盤→改走近一年殖利率；完整度不足時合計 null', () async {
      stubPositions([
        createPosition(id: 1, symbol: '2330', quantity: 1000, avgCost: 500),
      ], close: 1200);
      stubDividendReads(
        valuations: {
          '2330': StockValuationEntry(
            symbol: '2330',
            date: DateTime(2026, 9, 30),
            per: 20,
            pbr: 5,
            dividendYield: 2.0,
          ),
        },
      );

      await container.read(portfolioProvider.notifier).loadPositions();

      final state = container.read(portfolioProvider);
      expect(state.error, isNull);
      final analysis = state.dividendAnalysis!;
      expect(analysis.stockDividends.single.estimatedDividendPerShare, isNull);
      expect(analysis.totalExpectedDividend, isNull);
    });

    test('股利分析：ETF 以配發表算近一年殖利率 × 最新收盤', () async {
      stubPositions([
        createPosition(id: 1, symbol: '0050', quantity: 1000, avgCost: 100),
      ], close: 112.8);
      stubDividendReads(
        listings: [
          for (final market in [MarketCode.twse, MarketCode.tpex])
            DividendListingEntry(
              market: market,
              year: 2026,
              month: 10,
              listedThrough: DateTime(2026, 10, 2),
            ),
        ],
        ledger: [
          for (final market in [MarketCode.twse, MarketCode.tpex])
            for (final m in CalendarMonth.descending(
              from: const CalendarMonth(2021, 1),
              to: const CalendarMonth(2026, 9),
            ))
              DividendMonthLedgerEntry(
                market: market,
                year: m.year,
                month: m.month,
                completedAt: DateTime(2026, 10, 1),
                listedRows: 1,
                knownRows: 1,
                skippedSymbols: '',
                pricesRecorded: true,
              ),
        ],
        distributions: {
          '0050': [
            DividendDistributionEntry(
              symbol: '0050',
              exDate: DateTime(2026, 7, 21),
              cashDividend: 0.6,
              stockSharesPerThousand: 0,
              closeBefore: 99.2,
              referencePrice: 98.6,
            ),
            DividendDistributionEntry(
              symbol: '0050',
              exDate: DateTime(2026, 1, 22),
              cashDividend: 1.0,
              stockSharesPerThousand: 0,
              closeBefore: 71.85,
              referencePrice: 70.85,
            ),
          ],
        },
      );

      await container.read(portfolioProvider.notifier).loadPositions();

      final info = container
          .read(portfolioProvider)
          .dividendAnalysis!
          .stockDividends
          .single;
      expect(
        info.estimatedDividendPerShare,
        closeTo((0.6 / 99.2 + 1.0 / 71.85) * 112.8, 1e-9),
      );
    });
```

- [ ] **Step 2: 確認失敗**

Run: `flutter test test/domain/services/dividend_intelligence_service_test.dart test/presentation/providers/portfolio_provider_test.dart test/presentation/screens/portfolio/widgets/dividend_analysis_card_test.dart`
Expected: FAIL，編譯錯誤（`OfficialYield`、`summaries:`、`officialYields:` 未定義；`null` 不能指派給 `double`）

- [ ] **Step 3: 實作**

1. `lib/core/constants/analysis_params.dart`：刪掉 `dividendLookbackYears` 與它的文件註解（唯一讀者在下面改寫），在同一位置加：

```dart
  /// 投資組合的股利趨勢：最近兩個完整年度的現金股利變化超過這個百分比，
  /// 才算增加或減少
  static const double dividendTrendChangePercent = 10.0;
```

2. `lib/domain/services/dividend_intelligence_service.dart` 整檔換成：

```dart
import 'package:daredevil/core/constants/analysis_params.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/domain/services/dividend_summary.dart';

/// 官方估值的殖利率（%）與同一天的收盤價：兩者相乘＝交易所計算殖利率用的
/// 每股股利
typedef OfficialYield = ({double yieldPercent, double close});

/// 投資組合的股利分析
///
/// - 預估年股利（每股）：有官方估值者＝官方殖利率 × 同一天收盤價；其餘
///   （ETF、無估值）＝近一年殖利率 × 最新收盤價。資料建置中為 null
/// - 趨勢：最近兩個完整年度的現金股利（不受面額影響）；任一年建置中為 null
class DividendIntelligenceService {
  const DividendIntelligenceService();

  /// [summaries]、[officialYields]、[currentPrices] 都以 symbol 為鍵；
  /// [officialYields] 只放估值日查得到收盤價的股票
  DividendAnalysis analyzeDividends({
    required List<PortfolioPositionEntry> positions,
    required Map<String, DividendSummary> summaries,
    required Map<String, OfficialYield> officialYields,
    required Map<String, double> currentPrices,
  }) {
    if (positions.isEmpty) return DividendAnalysis.empty;

    double? totalExpected = 0;
    double totalCostBasis = 0;
    double totalMarketValue = 0;
    final stockDividends = <StockDividendInfo>[];

    for (final pos in positions) {
      if (pos.quantity <= 0) continue;

      final latestClose = currentPrices[pos.symbol];
      final costBasis = pos.quantity * pos.avgCost;
      totalCostBasis += costBasis;
      totalMarketValue += pos.quantity * (latestClose ?? pos.avgCost);

      final summary = summaries[pos.symbol];
      final perShare = _estimatePerShare(
        officialYields[pos.symbol],
        summary,
        latestClose,
      );
      final expected = perShare == null ? null : perShare * pos.quantity;
      // 任一持股建置中，合計就不可知：不加部分總和
      totalExpected = totalExpected == null || expected == null
          ? null
          : totalExpected + expected;

      stockDividends.add(
        StockDividendInfo(
          symbol: pos.symbol,
          estimatedDividendPerShare: perShare,
          expectedYearlyAmount: expected,
          personalYield: expected == null
              ? null
              : costBasis > 0
              ? expected / costBasis * 100
              : 0.0,
          trend: _trend(summary),
        ),
      );
    }

    stockDividends.sort(_byExpectedDesc);

    return DividendAnalysis(
      totalExpectedDividend: totalExpected,
      portfolioYieldOnCost: totalExpected == null
          ? null
          : totalCostBasis > 0
          ? totalExpected / totalCostBasis * 100
          : 0.0,
      portfolioYieldOnMarket: totalExpected == null
          ? null
          : totalMarketValue > 0
          ? totalExpected / totalMarketValue * 100
          : 0.0,
      stockDividends: stockDividends,
    );
  }

  double? _estimatePerShare(
    OfficialYield? official,
    DividendSummary? summary,
    double? latestClose,
  ) {
    if (official != null) return official.yieldPercent / 100 * official.close;
    return switch (summary?.trailingYield) {
      TrailingYieldValue(:final ratio) =>
        latestClose == null ? null : ratio * latestClose,
      TrailingYieldNone() => 0.0,
      TrailingYieldBuilding() || null => null,
    };
  }

  DividendTrend? _trend(DividendSummary? summary) {
    if (summary?.pastYears case [final recent, final previous, ...]) {
      if (recent.status == DividendYearStatus.building ||
          previous.status == DividendYearStatus.building) {
        return null;
      }
      if (previous.cash == 0) {
        return recent.cash > 0 ? DividendTrend.increasing : DividendTrend.stable;
      }
      final changePercent = (recent.cash - previous.cash) / previous.cash * 100;
      if (changePercent > AnalysisParams.dividendTrendChangePercent) {
        return DividendTrend.increasing;
      }
      if (changePercent < -AnalysisParams.dividendTrendChangePercent) {
        return DividendTrend.decreasing;
      }
      return DividendTrend.stable;
    }
    return null;
  }

  /// 預期金額由大到小；建置中（null）排最後
  static int _byExpectedDesc(StockDividendInfo a, StockDividendInfo b) {
    final x = a.expectedYearlyAmount;
    final y = b.expectedYearlyAmount;
    if (x == null) return y == null ? 0 : 1;
    if (y == null) return -1;
    return y.compareTo(x);
  }
}

/// 股利分析結果
class DividendAnalysis {
  const DividendAnalysis({
    required this.totalExpectedDividend,
    required this.portfolioYieldOnCost,
    required this.portfolioYieldOnMarket,
    required this.stockDividends,
  });

  /// 預期年度股利總額；任一持股建置中時為 null
  final double? totalExpectedDividend;

  /// 組合殖利率（以成本計算，%）；同上
  final double? portfolioYieldOnCost;

  /// 組合殖利率（以市價計算，%）；同上
  final double? portfolioYieldOnMarket;

  /// 各持股的股利資訊：預期金額由大到小，建置中排最後
  final List<StockDividendInfo> stockDividends;

  static const empty = DividendAnalysis(
    totalExpectedDividend: 0,
    portfolioYieldOnCost: 0,
    portfolioYieldOnMarket: 0,
    stockDividends: [],
  );
}

/// 單一持股的股利資訊
class StockDividendInfo {
  const StockDividendInfo({
    required this.symbol,
    required this.estimatedDividendPerShare,
    required this.expectedYearlyAmount,
    required this.personalYield,
    required this.trend,
  });

  final String symbol;

  /// 預估每股年股利（元）；建置中為 null
  final double? estimatedDividendPerShare;

  /// 預期年度股利金額；建置中為 null
  final double? expectedYearlyAmount;

  /// 個人殖利率（以成本計算，%）；建置中為 null
  final double? personalYield;

  /// 股利趨勢；最近兩個完整年度任一年建置中時為 null（不顯示）
  final DividendTrend? trend;
}

/// 股利趨勢
enum DividendTrend { increasing, stable, decreasing }
```

3. `lib/presentation/providers/portfolio_provider.dart`：
   - import 區加：

```dart
import 'package:daredevil/domain/services/dividend_completeness.dart';
import 'package:daredevil/domain/services/dividend_summary.dart';
```

   - `loadPositions` 的

```dart
      // 取得股利歷史並計算股利分析
      final dividendHistories = await _db.getDividendHistoryBatch(symbols);
      final dividendAnalysis = _dividendService.analyzeDividends(
        positions: positions,
        dividendHistories: dividendHistories,
        currentPrices: currentPrices,
      );
```

     換成

```dart
      final dividendAnalysis = await _analyzeDividends(
        positions,
        symbols,
        stocksMap,
        currentPrices,
      );
```

   - `loadPositions` 之後加：

```dart
  /// 股利分析：配發表與完整度事實建每檔的股利摘要，官方估值配上估值日的收盤
  Future<DividendAnalysis> _analyzeDividends(
    List<PortfolioPositionEntry> positions,
    List<String> symbols,
    Map<String, StockMasterEntry> stocksMap,
    Map<String, double> currentPrices,
  ) async {
    final completeness = await loadDividendCompleteness(
      _db,
      now: ref.read(appClockProvider).now(),
    );
    final distributions = await _db.getDividendDistributionsBatch(symbols);
    final valuations = await _db.getLatestValuationsBatch(symbols);
    final officialYields = <String, OfficialYield>{};
    for (final MapEntry(key: symbol, value: valuation) in valuations.entries) {
      final yieldPercent = valuation.dividendYield;
      if (yieldPercent == null) continue;
      // 官方殖利率＝每股股利 ÷ 估值日收盤：乘回同一天的收盤才是交易所用的股利
      final close = (await _db.getPriceOnDate(symbol, valuation.date))?.close;
      if (close != null) {
        officialYields[symbol] = (yieldPercent: yieldPercent, close: close);
      }
    }
    return _dividendService.analyzeDividends(
      positions: positions,
      summaries: {
        for (final symbol in symbols)
          symbol: DividendSummary.compute(
            symbol: symbol,
            name: stocksMap[symbol]?.name,
            rows: distributions[symbol] ?? const [],
            completeness: completeness,
          ),
      },
      officialYields: officialYields,
      currentPrices: currentPrices,
    );
  }
```

4. `lib/presentation/screens/portfolio/widgets/dividend_analysis_card.dart`：
   - 總覽列的三個 `_SummaryItem` 換成：

```dart
              Expanded(
                child: _SummaryItem(
                  label: 'portfolio.expectedDividend'.tr(),
                  value: switch (analysis.totalExpectedDividend) {
                    final total? =>
                      'NT\$${LocalizedNumberFormat.compact(total, Localizations.localeOf(context))}',
                    null => 'portfolio.dividendBuilding'.tr(),
                  },
                  subValue: 'portfolio.yearly'.tr(),
                  theme: theme,
                ),
              ),
              Expanded(
                child: _yieldItem(
                  'portfolio.yieldOnCost'.tr(),
                  analysis.portfolioYieldOnCost,
                  theme,
                ),
              ),
              Expanded(
                child: _yieldItem(
                  'portfolio.yieldOnMarket'.tr(),
                  analysis.portfolioYieldOnMarket,
                  theme,
                ),
              ),
```

   - `DividendAnalysisCard` 類別內加：

```dart
  Widget _yieldItem(String label, double? yield_, ThemeData theme) =>
      _SummaryItem(
        label: label,
        value: yield_ == null
            ? 'portfolio.dividendBuilding'.tr()
            : '${yield_.toStringAsFixed(2)}%',
        valueColor: yield_ == null ? null : _getYieldColor(yield_),
        theme: theme,
      );
```

   - `_StockDividendRow`：
     - 代號旁的 `const SizedBox(width: DesignTokens.spacing4), _TrendIcon(trend: info.trend),` 換成：

```dart
                if (info.trend case final trend?) ...[
                  const SizedBox(width: DesignTokens.spacing4),
                  _TrendIcon(trend: trend),
                ],
```

     - 每股股利的 `AppNumberFormat.currency(info.estimatedDividendPerShare, decimals: 2),` 換成：

```dart
                  switch (info.estimatedDividendPerShare) {
                    final perShare? => AppNumberFormat.currency(
                      perShare,
                      decimals: 2,
                    ),
                    null => 'portfolio.dividendBuilding'.tr(),
                  },
```

     - 預期金額的文字換成：

```dart
                  switch (info.expectedYearlyAmount) {
                    final amount? =>
                      'NT\$${LocalizedNumberFormat.compact(amount, Localizations.localeOf(context))}',
                    null => '—',
                  },
```

     - 個人殖利率欄的第一個 `Text(...)`（`'${info.personalYield.toStringAsFixed(1)}%'` 那個）整個換成：

```dart
                Text(
                  switch (info.personalYield) {
                    final y? => '${y.toStringAsFixed(1)}%',
                    null => '—',
                  },
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: switch (info.personalYield) {
                      final y? => _getYieldColor(y),
                      null => null,
                    },
                  ),
                ),
```

5. 兩個翻譯檔的 `portfolio` 區塊，`"yield": ...` 之後加一行：zh-TW `"dividendBuilding": "建置中",`、en `"dividendBuilding": "Building",`。

- [ ] **Step 4: 確認通過**

Run: `flutter test test/domain/services/dividend_intelligence_service_test.dart test/presentation/providers/portfolio_provider_test.dart test/presentation/screens/portfolio/ test/core/l10n/`
Expected: 全部 PASS

Run: `grep -rn "dividendLookbackYears\|getDividendHistoryBatch" lib test tool --include='*.dart' | grep -v "lib/data/database/dao/dividend_dao.dart"`
Expected: 只剩 `test/tools/scoring_snapshot.dart` 一行（52 週新舊對照的舊版；它與 DAO 方法本身都留給 3-4）

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 5: 記錄進度**（不 commit）

---

### Task 5: 文件與註解

**Files:**
- Modify: `CHANGELOG.md`（`[Unreleased]` 的 `### Changed`）
- Modify: `lib/core/constants/api_config.dart`（`dividendBackfillYears` 註解）

- [ ] **Step 1: 先找讀這些文件的測試**

Run: `grep -rln "CHANGELOG\|api_config.dart" test`
Expected: 列出的測試在 Step 3 一併跑

- [ ] **Step 2: 改寫**

1. `CHANGELOG.md`，`[Unreleased]` 的 `### Changed` 第一條（52 週）之後加：

```markdown
- 個股頁股利表改讀除權除息配發表：依除息日年份列出今年（截至最近一次更新）與前 5 年的現金、配股、合計與配息次數，
  另有平均列（不足 5 年時標示起算年）；面額不是 10 元的股票（名稱帶 `*`）配股以每千股股數顯示。資料尚未補齊的年度
  顯示「建置中」，不再因此在頁首顯示錯誤，也不再向 FinMind 查詢股利。ETF 的殖利率卡改顯示近一年殖利率（逐次以除息前
  收盤計算，不受分割影響）
- 投資組合的預估年股利改為官方殖利率 × 同一天收盤價，ETF 與沒有官方估值的股票以近一年殖利率 × 最新收盤價；任一持股
  資料建置中時合計顯示「建置中」。股利趨勢改比最近兩個完整年度的現金股利（原本把配股的面額元與現金相加）
```

2. `lib/core/constants/api_config.dart` 的

```dart
  /// 除權除息歷史回補的深度：今年往前這麼多個完整年度的 1 月起。個股頁
  /// 股利表顯示最近 5 年，其他讀取端最多用 2–3 年。
```

   改成

```dart
  /// 除權除息歷史回補的深度：今年往前這麼多個完整年度的 1 月起。個股頁
  /// 股利表的年數直接用這個值（`DividendSummary`：更早的年度沒有回補，列出
  /// 也只會是建置中），其他讀取端最多用 2–3 年。
```

   （後半句保留原文：52 週約 400 天；近一年殖利率的完整度窗口最長約 750 天（最近除息日可到 399 天前，再往前 350 天）；趨勢回看到前年 1/1，約 2.75 年。）

- [ ] **Step 3: 驗證**

Run: Step 1 列出的測試
Expected: 全部 PASS

Run: `grep -n "\[Unreleased\]" -A 80 CHANGELOG.md | grep -c "個股頁股利表改讀"`
Expected: `1`

- [ ] **Step 4: 記錄進度**（不 commit）

---

### Task 6: 全套驗證、mutation、審查、經同意提交、重編 GUI

- [ ] **Step 1: 靜態檢查與全套測試**（log 寫到 scratchpad）

```bash
dart format lib test tool
flutter analyze
flutter test > <scratchpad>/full_3_3.log 2>&1; tail -c 300 <scratchpad>/full_3_3.log
dart compile kernel tool/daily_update.dart -o build/daily_update.dill
```

Expected: analyze 無 issue；全套通過；kernel 編譯成功

- [ ] **Step 2: 真資料試跑**（不進 repo、不改 live DB）

單元測試的資料是造的；這一步用真資料走一次同一條程式路徑，在重編 GUI 之前發現「真資料讓整片都變建置中」這類問題。

1. 在 scratchpad 建 repo 副本（`rsync -rl`，Step 3 的 mutation 也用它）。
2. 唯讀做 live DB 副本：有 -wal 檔時 `sqlite3 "file:<live>?mode=ro" "VACUUM INTO '<scratchpad>/div33_src.sqlite'"`；沒有 -wal 檔時 URI 加 `&immutable=1`。
3. 在 repo 副本放 `test/_div33_dry_run_test.dart`：

```dart
// 3-3 真資料試跑：只在 scratchpad 的 repo 副本跑，不進 repo
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/constants/stock_patterns.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/domain/services/dividend_completeness.dart';
import 'package:daredevil/domain/services/dividend_summary.dart';

String _yield(TrailingYield t) => switch (t) {
  TrailingYieldValue(:final ratio) => '${(ratio * 100).toStringAsFixed(2)}%',
  TrailingYieldNone() => '無配息',
  TrailingYieldBuilding() => '建置中',
};

String _row(DividendYearRow r) =>
    '${r.year}:${r.status.name}:${r.cash}:${r.stockShares}:${r.cashCount}';

void main() {
  final dbPath = Platform.environment['DIV33_DB'];
  test('3-3 真資料試跑', skip: dbPath == null, () async {
    final db = AppDatabase.forToolFile(dbPath!);
    addTearDown(db.close);
    final completeness = await loadDividendCompleteness(
      db,
      now: DateTime.now(),
    );
    final stocks = await db.getAllActiveStocks();
    final rows = await db.getDividendDistributionsBatch([
      for (final s in stocks) s.symbol,
    ]);
    final summaries = {
      for (final s in stocks)
        s.symbol: DividendSummary.compute(
          symbol: s.symbol,
          name: s.name,
          rows: rows[s.symbol] ?? const [],
          completeness: completeness,
        ),
    };

    print('顯示終點 ${completeness.displayEnd}；在市 ${stocks.length} 檔');
    print('整區建置中 ${summaries.values.where((s) => s.allBuilding).length} 檔');
    final byYear = <int, Map<String, int>>{};
    for (final s in summaries.values) {
      for (final r in [s.current, ...s.pastYears]) {
        final counts = byYear.putIfAbsent(r.year, () => {});
        counts[r.status.name] = (counts[r.status.name] ?? 0) + 1;
      }
    }
    byYear.forEach((year, counts) => print('$year $counts'));
    final etfYields = <String, int>{};
    final odd = <String>[];
    for (final MapEntry(key: symbol, value: s) in summaries.entries) {
      if (!StockPatterns.isEtfCode(symbol)) continue;
      final label = switch (s.trailingYield) {
        TrailingYieldValue(:final ratio) when ratio <= 0 || ratio > 0.15 =>
          '異常',
        TrailingYieldValue() => '有值',
        TrailingYieldNone() => '無配息',
        TrailingYieldBuilding() => '建置中',
      };
      etfYields[label] = (etfYields[label] ?? 0) + 1;
      if (label == '異常') odd.add('$symbol ${_yield(s.trailingYield)}');
    }
    print('ETF 近一年殖利率 $etfYields；異常 $odd');
    for (final symbol in ['2330', '5314', '0050', '0054']) {
      final s = summaries[symbol];
      if (s == null) {
        print('$symbol 不在在市清單');
        continue;
      }
      final average = switch (s.average) {
        DividendAverageValue(:final fromYear, :final years, :final cash) =>
          '$fromYear 起 $years 年 $cash',
        DividendAverageBuilding() => '建置中',
        null => '無',
      };
      print(
        '$symbol 面額10=${s.parValueTen} 今年 ${_row(s.current)} '
        '過去 ${s.pastYears.map(_row).toList()} 平均 $average '
        '近一年 ${_yield(s.trailingYield)}',
      );
    }
  });
}
```

4. 在 repo 副本跑：`DIV33_DB=<scratchpad>/div33_src.sqlite flutter test test/_div33_dry_run_test.dart`

Expected:
- 顯示終點等於最近一輪更新的資料日（10/5 以前的副本是 9/30：10 月的列表事實要等新版第一輪才寫）。
- 整區建置中 0 檔；過去 5 年沒有 `building`（2021-01～2026-09 兩市場都有完成紀錄，未解決的列只有不在主檔的代號）。不符就先查原因，再進下一步。
- ETF「異常」為空。0054、00742、00920 是「無配息」。
- 2330、5314、0050、0054 的數字與官方公告逐一核對，結果寫進 Step 5 的報告。

- [ ] **Step 3: mutation**

做法同 3-1／3-2：
- 用 Step 2 的 repo 副本；原始檔先備份，還原一律用備份檔。
- 每個 mutant 開跑前，先檢查必要檔案存在。
- 先跑該檔的直接測試（下表「直接測試」欄）：殺掉就結案；**存活者**再跑全部消費者測試確認：`test/domain/services test/data/loaders test/presentation/providers test/presentation/screens/stock_detail test/presentation/screens/portfolio test/core/l10n`。被直接測試殺掉的，結論不會因為多跑其他測試而改變，所以只有存活者需要整組。timeout 300 秒；用 `python3 -u`。
- 記錄每個 mutant 是被哪一條測試、哪一個斷言殺掉的。被編譯錯誤、或沒 stub 的 mock 拋錯殺掉的不算數：換一種 mutant 寫法再跑。

| 檔案 | 直接測試 |
|:--|:--|
| dividend_summary | `test/domain/services/dividend_summary_test.dart` |
| stock_fundamentals_loader | `test/data/loaders/` |
| stock_detail_provider | `test/presentation/providers/stock_detail_notifier_test.dart` |
| fundamentals_tab | `test/presentation/screens/stock_detail/tabs/fundamentals_tab_test.dart` |
| dividend_summary_table | `test/presentation/screens/stock_detail/tabs/fundamentals/` |
| dividend_intelligence_service | `test/domain/services/dividend_intelligence_service_test.dart` |
| portfolio_provider | `test/presentation/providers/portfolio_provider_test.dart` |
| dividend_analysis_card | `test/presentation/screens/portfolio/widgets/dividend_analysis_card_test.dart` |

至少涵蓋：

| 檔案 | mutant |
|:--|:--|
| dividend_summary | 0/0 列的過濾拿掉；`end.year < thisYear` 拿掉；今年與過去年度的 `requirePrices: false` 各自改成 true；今年事件的 `!isAfter(end)` 拿掉、改成 `isBefore(end)`；`firstEventYear` 改取最新的有事件年度；`_paid` 的 `if (e.cashDividend > 0)` 拿掉；平均的建置中檢查拿掉；`fromYear` 改取最新的有配發年度；`row.year >= fromYear` 改成 `>`；`allBuilding` 的兩個條件各自拿掉；`parValueTen` 的 `name != null &&` 拿掉（改成 `name == null \|\|`）；`!name.contains('*')` 拿掉；`stockYuan` 的 `/ 100` 改成 `/ 10`；近一年：`cashDividend > 0` 過濾拿掉、`!isAfter(end)` 拿掉、`!isAfter(end)` 改成 `isBefore(end)`、`!latest.isAfter(staleCutoff)` 改成 `latest.isBefore(staleCutoff)`、停配分支直接回 None（不查完整度）、窗口完整度的起點改成 `latest`、`isBefore(from)` 改成 `!isAfter(from)`、缺前收盤檢查拿掉（改成 `close!`）、兩處 `requirePrices: true` 各自改成 false |
| stock_fundamentals_loader | `catch` 改成 rethrow；`name: stock?.name` 改成 `name: null` |
| stock_detail_provider | 股利條件改成 `result.dividendSummary?.allBuilding ?? true`；`hasSomeData` 的 `dividendSummary != null` 拿掉（預期等價：載入完成且沒有錯誤時營收必定非空，載入前兩者都空；存活就在報告裡說明） |
| fundamentals_tab | `allBuilding` 分支拿掉（一律畫表）；ETF 判斷改成一律官方；ETF 判斷改成一律近一年 |
| dividend_summary_table | `cashCount > 1` 改成 `> 0`；`stockYuan != null` 的兩個分支互換；今年「截至」的建置中條件拿掉 |
| dividend_intelligence_service | 官方路徑改乘最新收盤；`TrailingYieldNone() => 0` 改成 null；合計的 null 傳播拿掉（略過 null）；排序把 null 排最前；趨勢的建置中檢查拿掉；趨勢改比現金＋配股；門檻的正負號互換 |
| portfolio_provider | 估值日收盤改用 `currentPrices`；`distributions` 傳空；`officialYields` 傳空（`name` 只影響面額，投資組合不用，不列） |
| dividend_analysis_card | 合計 null 時顯示 `NT$0` |

存活者逐一判斷：補測試，或證明等價並刪掉多餘的程式碼。

- [ ] **Step 4: 審查**

送 opus 審查（`pr-review-toolkit:code-reviewer`）：
- 範圍：`git diff` 加未追蹤新檔。
- 附本計畫與 spec 的路徑、Review Focus 五條、「與 spec 的差異」七條、Step 2 試跑的輸出。
- 限制：不可 `dart run`、不可開背景任務、不可碰 scratchpad。

修正後，以 SendMessage 請同一位審查者複審，直到 Ready。修正若動到 `dividend_summary.dart`，重跑 Step 2。

- [ ] **Step 5: 報告並等「提交」**

給使用者的報告：
- 全套測試數、mutation 結果（殺掉／存活與處置）、審查輪數與修正。
- Step 2 試跑：顯示終點、整區建置中檔數、各年度狀態分布、ETF 近一年殖利率分布，以及 2330、5314、0050、0054 的預期畫面與官方核對結果。
- 提醒：畫面要重編 GUI 才看得到。

Commit message 草稿：

```
feat: 個股頁股利表、ETF 殖利率與投資組合股利改讀除權除息配發表

- DividendSummary：依除息日年份彙總今年與前 5 年（現金、配股、次數），年度
  狀態分有配發／無除權息／無除權息紀錄／尚未除息／建置中，平均從第一次有
  除權息的完整年度起算；近一年殖利率逐次以除息前收盤正規化
- 個股頁股利表只讀 DB、不再打 FinMind；全部建置中時顯示「股利資料建置中」，
  資料不完整不再列入頁首錯誤；面額非 10 元的股票配股以每千股股數顯示
- ETF 殖利率卡顯示近一年殖利率
- 投資組合預估年股利改為官方殖利率 × 同日收盤，其餘以近一年殖利率 × 最新
  收盤；任一持股建置中時合計顯示建置中；趨勢改比最近兩個完整年度的現金股利
```

- [ ] **Step 6: 經同意後提交**（使用者說「提交」才做）

- [ ] **Step 7: 提交後**

1. 確認 post-commit hook 已把 CLI 重編到新 commit（`~/Library/Logs/daredevil-cli-rebuild.log` 的最後一行、兩支 CLI 的 `BUILD_INFO`）。
2. 問使用者是否現在重編 GUI（macOS Debug）。同意後重編，目視檢查：
   - 2330：股利表 6 列＋平均列，今年標「截至 M/D」，頁首沒有「（股利）」。
   - 5314 世紀*：配股欄「每千股 X 股」、合計「—」。
   - 0050：殖利率卡「近一年殖利率」約 2.0%。
   - 0054：殖利率卡「無配息」。
   - 任一檔 ETF 的頁首：確認「不在本段」那條紅字是否真的存在，結果記進報告。
3. GUI 重編到這個 commit 之後，3-4（移除舊表）的前提才成立。

---

## 執行後的修正

本節以前各 task 的程式碼是執行前寫的；執行中與審查後的修正如下，以 commit 為準。

- **計畫本身的缺陷（執行中）**：載入器測試改從回補起點 2021-01 種事實（顯示終點要連續）；分頁的 ETF 測試拆成兩條（同一個測試內重 pump 不會重建 notifier）；服務測試改用 `{k: ?x}`（lint）；`api_config.dart` 的註解保留「其他讀取端最多用 2–3 年」（近一年殖利率的完整度窗口最長約 750 天）。
- **mutation 補的測試**：近一年殖利率有除息時，窗口內「不是除息的列」缺價格也要建置中（原本只靠逐筆檢查前收盤，擋不到）。
- **審查（opus）**：
  - 投資組合的官方估值加新鮮度下限（見「與 spec 的差異」第 4 點）。
  - 個股頁改成先讀完整度事實、再讀配發列（與投資組合同序）：一般更新只新增或取代列（會刪在庫列的只有修復工具的 `--recheck`），事實讀取當下已在庫的列之後一定讀得到，中間新寫入的列只會多讀到（顯示終點之後的照樣濾掉）；反過來先讀列，會讀到「事實說完整、列卻還沒讀到」。兩個讀取端都以呼叫順序的測試釘住。
  - 不包 transaction：`--recheck` 從刪掉不符的在庫列到該月寫入事實之間，DB 本身就是「舊事實說完整、列已刪」，任何快照都讀到同樣的狀態；這段期間個股頁、投資組合、52 週規則（3-2）都會把該期間判為完整、少那一筆。這是 3-1 寫入端的既有行為，3-3 不修。
  - 股利表現金欄文字改用主題的 `primary`（品牌藍對淺色底不到 3:1）。
  - 補測試：官方殖利率空白、估值日沒有收盤（種完整事實，斷言等於近一年殖利率 × 最新收盤）、官方估值 30 天下限的兩側（9/3 用、9/2 不用）、建置中的年度在庫的列也算第一次除權息；改正兩條測試名稱與幾句註解。
- **提交後目視發現**：今年那列的「截至 M/D」「N 次」幾乎看不見——次要文字用 `outline` 色，疊在今年那列的 primary 半透明底色上，實測只有 1.12:1（深色）／1.24:1（淺色）。改成一般列 `onSurfaceVariant`、今年那列 `onSurface`（今年那列若也用 `onSurfaceVariant` 實測 3.38／3.40:1，仍不夠）；測試以實際畫出的底色（疊色先合成在卡片上）在兩個主題各算一次，修正後最低 5.27:1。
- **保留的等價條件**：`loadFundamentals` 的 `hasSomeData` 仍含 `dividendSummary != null`（spec §7 要求一併調整）。mutation 存活，推理可證它目前不可觀察——載入完成且沒有錯誤時營收必定非空，fundamentals 只在 `loadFundamentals` 寫入——但哪天 `missingParts` 不再要求營收時，它讓跳過重載的判斷仍然正確。
- **記錄、不修**：股利表第一列（今年）的底色是 `primaryContainer`（兩個主題都退回 `primary`）30%，現金與合計欄的 `primary` 文字疊在上面的對比依 WCAG 公式推算約 3.4–4.1:1（未實測），低於 4.5:1。底色來自共用的 `getRowColor`，營收、EPS 表共用同一個底色，但文字色不同、對比未算；另案處理。
