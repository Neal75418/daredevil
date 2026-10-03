# 股利第 3-2 段：52 週新高／新低改用還原價 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 52 週新高／新低規則改用交易所除權息參考價還原歷史價格後再判斷；股利資料不完整，或還原後仍有水位斷點時，一律不觸發。新舊差異量測完、經使用者同意後才提交。

**Architecture:**
- **載入**：主 isolate 的 `BatchDataLoader` 讀取完整度事實與價格窗內的除權除息事件，替每檔股票建立 `DividendContext`（`complete(events)` 或 `incomplete`），放進 `ScoringBatchData`。
- **傳遞**：isolate 與主執行緒回退兩條評分路徑，都把它放進 `StockData.dividends`（必填）。
- **判斷**：規則透過共用的 `week52AdjustedPrices` 取得還原價（`DividendAdjuster`）並套用閘門。每輪的觀測計數也用同一個函式，所以「不評估的原因」和規則的實際行為不會分岔。

**Tech Stack:** Flutter／Dart 3（sealed class、record、pattern）、Drift 2.32、mocktail、flutter_test

**Spec:** `docs/plans/2026-10-01-dividend-read-side-design.md`。本計畫實作 §4、§5，以及「驗證」一節的 3-2。3-1 已提交（a29602b5），live DB 已補齊 2021-01～2026-09 的價格欄。

## Global Constraints

- **update 鏈純 Dart**：lib 新檔（`dividend_context.dart`、`dividend_adjuster.dart`）會進 CLI 的 import 閉包，不得 import flutter。守門測試是 `test/tool/tool_chain_pure_dart_test.dart`；改完跑 `dart compile kernel tool/daily_update.dart -o build/daily_update.dill` 做終驗。
- **不改 schema、不 bump fingerprint**：3-2 只讀股利表。
- **兩條評分路徑同一結論**：`evaluateStocksIsolated` 與 `ScoringService.scoreStocks` 吃同一份輸入，必須得到同一結論。isolate 輸入只放可跨界的純資料；sendability 測試的每個元素型別都要放真實例。
- **寧可漏、不可錯**：股利情境不完整、或還原後仍有斷點時，52 週一律不觸發。查不到某檔的情境時，一律視為不完整。
- **不前視**：評分日之後的除權除息不得套用（只套用 `d < 除權息日 ≤ 評分日` 的事件）。
- **範圍限縮**：其他規則、均線、RSI 不改用還原價；WEEK_52 分數不重新校準（spec 非目標）。
- **舊股利資料留到 3-3／3-4**：`dividend_history` 表、它的 DAO 方法（`getDividendHistory`、`getDividendHistoryBatch`、`insertDividendData`）與 `AnalysisParams.dividendLookbackYears` 不動，因為投資組合和股利情報還在用。
- **live DB 只唯讀查詢**：用 `file:...?mode=ro`，沒有 -wal 檔時加 `&immutable=1`。量測用 `VACUUM INTO` 做出的副本。
- **提交**：
  - commit／push 只在使用者說「提交」時做。
  - Conventional Commits、中文、純文字、不加 Co-Authored-By。
  - 每個 task 結尾一律「記錄進度」，整段在 Task 8 一次提交。
  - **52 週量測結果經使用者同意前不提交。**
- **mutation**：還原用備份檔，不用 git checkout；每個 mutant 都跑所有消費者測試，timeout 300 秒。
- **測試檔批次改寫**：一律用本計畫附的腳本，跑完接 `dart format` 與 `flutter analyze`。腳本靠括號配對；註解或字串裡若有不成對的括號會造成語法錯誤，交給 analyze 抓、手動修正。

## Review Focus

1. **本月同步沒把列表日推進到資料日的那一輪**（步驟 6.6 被前面的限流跳過，或本身失敗）。
   - 預期：評分日不在列表範圍內，當輪所有股票的 52 週都不觸發；日誌「52 週：完整度不足 N 檔」的 N 接近「走到規則評估、且價格有 250 根以上」的檔數；下一輪本月同步成功後恢復。
   - 不可以：拿過時的完整度照樣觸發。
   - 測試在 Task 2、Task 3。
2. **凌晨補跑（資料日＝前一交易日），而今天的除權除息列已在庫**。
   - 預期：今天的事件不套到資料日以前的價格。
   - 測試在 Task 1（`asOf`）、Task 2（`priceContext` 的 `asOf`）。
3. **除權息跳空讓原始均線看似空頭排列**。
   - 預期：新低的過濾改用還原後收盤的 MA20／MA60。原始價格 `收盤 < MA20 < MA60` 成立、還原後不成立時，不觸發。
   - 測試在 Task 4。
4. **停牌期間除權息**（窗內有收盤為 null 的列，除權息日落在停牌中）。
   - 預期：停牌前的價格照樣還原；null 維持 null；斷點偵測跳過 null。
   - 測試在 Task 1。
5. **只有現金增資的 0/0 列，以及因子大於 1 的列**（認購價高於市價）。
   - 預期：還原要包含 0/0 列；因子大於 1 時，舊價格往上調。
   - 測試在 Task 1（因子）、Task 2（DAO 含 0/0 列）。

## 與 spec 的差異（核可計畫時一併確認）

1. **舊欄位提早在 3-2 移除**
   - spec 的安排：§8 把 `StockData.dividendHistory` 與評分 DTO 的 `dividendHistoryMap` 列在 3-4 移除。
   - 為什麼提早：§5 要求 3-2「取代 dividendHistoryMap」，取代之後它們就沒有任何讀者了。
   - 不動的部分：`dividend_history` 表與它的 DAO 方法，照 spec 留給 3-3／3-4。
2. **「必填」擴及兩個批次容器**
   - spec 的要求：只有 `StockData.dividends` 必填。
   - 本計畫：`ScoringBatchData.dividendContexts` 與 `ScoringIsolateInput.dividendContexts` 也設為必填。
   - 為什麼：既有的一致性測試直接建 isolate 輸入，攔不到「`scoreStocksInIsolate` 忘了把情境轉交進去」這種漏接；設成必填就交給編譯器擋。
3. **校準回放傳 `incomplete`**
   - 背景：校準 DB 沒有除權除息配發資料。
   - 做法：`ReplayCalibrator` 傳 `DividendContext.incomplete()`，所以 52 週在回放中不觸發。同時把 `WEEK_52_HIGH`／`WEEK_52_LOW` 加進 `CalibrationThresholds.notBackfillableReasons`；不加的話，下次重新校準會給出「重跑 replay」這種無效建議。
   - WEEK_52 分數重新校準仍是另案。
4. **量測的回放終點改用完整度的顯示終點**
   - spec 的寫法：「最近約 62 個交易日」。
   - 問題：10 月的列表日要等新版第一輪本月同步才會寫入，在那之前回放 10 月的日子只會得到「不完整」。
   - 做法：回放取 `DividendCompleteness.displayEnd` 以前最近的 62 個交易日。
5. **還原截止日用被判斷那一根的日期**
   - spec 的寫法：「評分日」。
   - 本計畫：規則內以 `prices.last.date` 當 `asOf`。
   - 為什麼等價：production 由候選資格的 staleBar 檢查保證這一根就是評分日；回放切到過去某一天時也自然成立。

## 檔案結構

| 檔案 | 責任 | 動作 |
|:--|:--|:--|
| `lib/domain/models/dividend_context.dart` | `DividendPriceEvent`、`DividendContext`（sealed） | 新增 |
| `lib/domain/models/models.dart` | domain model barrel | 匯出新檔 |
| `lib/domain/services/dividend_adjuster.dart` | 除權息還原 | 新增 |
| `lib/data/database/dao/dividend_dao.dart` | 股利 DAO | 新增 `getDividendEventsBatch` |
| `lib/domain/services/dividend_completeness.dart` | 逐檔完整度 | 新增 `priceContext` |
| `lib/domain/services/update/batch_data_builder.dart` | 評分資料 map 建構 | 新增 `buildDividendContexts` |
| `lib/domain/services/update/batch_data_loader.dart` | 評分批次載入 | 讀完整度與事件、建情境；移除舊股利載入 |
| `lib/domain/models/scoring_batch_data.dart`、`scoring_data_groups.dart` | 評分批次容器 | 新增 `dividendContexts`；移除 `dividendHistoryMap` |
| `lib/domain/services/scoring_isolate.dart` | isolate 評分 | 輸入加 `dividendContexts`；`StockData.dividends`；觀測計數 |
| `lib/domain/services/scoring_service.dart` | 評分服務（含回退） | 同上；日誌 |
| `lib/domain/services/rules/stock_rules.dart` | `StockData` | `dividends` 必填；移除 `dividendHistory` |
| `lib/domain/services/rules/indicator_rules.dart` | 52 週規則 | 還原、閘門、`week52AdjustedPrices` |
| `tool/replay_calibrator.dart`、`lib/core/constants/calibration_thresholds.dart` | 校準回放 | 傳 `incomplete`；更新 `notBackfillableReasons` |
| `test/tools/scoring_snapshot.dart` | 評分快照與量測 | 帶股利情境；新增 52 週新舊對照回放 |
| `lib/domain/services/price_continuity.dart`、`analysis/analysis_coordinator_service.dart`、`docs/RULE_ENGINE.md`、`.claude/rules/update-pipeline.md`、`tool/backfill.dart` | 文件與註解 | 改正「52 週本來就處理除息」等過時敘述 |

---

### Task 1: 股利情境型別與還原函式 `DividendAdjuster`

**Files:**
- Create: `lib/domain/models/dividend_context.dart`
- Modify: `lib/domain/models/models.dart`
- Create: `lib/domain/services/dividend_adjuster.dart`
- Test: `test/domain/services/dividend_adjuster_test.dart`

**Interfaces:**
- Produces:
  - `DividendPriceEvent({required DateTime exDate, required double closeBefore, required double referencePrice})`，`double get factor`＝參考價 ÷ 前收盤
  - `sealed class DividendContext`：`const DividendContext.incomplete()`、`const DividendContext.complete(List<DividendPriceEvent> events)`、`static const DividendContext noEvents`；子類別 `DividendIncomplete`、`DividendComplete`（欄位 `events`）
  - `DividendAdjuster.adjust(List<DailyPriceEntry> prices, List<DividendPriceEvent> events, {required DateTime asOf}) → List<DailyPriceEntry>`

- [ ] **Step 1: 寫失敗測試**

`test/domain/services/dividend_adjuster_test.dart`：

```dart
// 除權息還原（DividendAdjuster）：日期 d 的開高低收乘上所有
// d < 除權息日 ≤ asOf 事件的因子（除權息參考價 ÷ 除權息前收盤）
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/domain/models/dividend_context.dart';
import 'package:daredevil/domain/services/dividend_adjuster.dart';

DailyPriceEntry _bar(DateTime date, double close) => DailyPriceEntry(
  symbol: 'T',
  date: date,
  open: close,
  high: close + 1,
  low: close - 1,
  close: close,
  volume: 1000,
  priceChange: 0.5,
);

DividendPriceEvent _event(DateTime exDate, double close, double reference) =>
    DividendPriceEvent(
      exDate: exDate,
      closeBefore: close,
      referencePrice: reference,
    );

void main() {
  final d14 = DateTime(2026, 9, 14);
  final d15 = DateTime(2026, 9, 15);
  final d16 = DateTime(2026, 9, 16);
  final d17 = DateTime(2026, 9, 17);

  group('交易所實例：除權息前一天的收盤還原後等於除權息參考價', () {
    // 前收盤就是除權息前一天的收盤，因子＝參考價 ÷ 前收盤
    for (final (name, close, reference) in [
      ('純現金 2330 2026-09-16', 2385.0, 2377.99),
      ('配股 6669 2026-09-02（每千股 1,982.8 股）', 7800.0, 2614.99),
      ('只有現金增資 3149 2026-07-17', 93.5, 86.68),
    ]) {
      test(name, () {
        final prices = [
          _bar(d14, close),
          _bar(d15, close),
          _bar(d16, reference),
        ];

        final adjusted = DividendAdjuster.adjust(prices, [
          _event(d16, close, reference),
        ], asOf: d16);

        expect(adjusted[0].close, closeTo(reference, 1e-9));
        expect(adjusted[1].close, closeTo(reference, 1e-9));
        expect(adjusted[2].close, reference, reason: '除權息當天已是除權息後，不調整');
      });
    }
  });

  test('多次除權息：較舊的日子乘上之後每一次的因子', () {
    final prices = [_bar(d14, 100), _bar(d15, 90), _bar(d16, 81)];

    final adjusted = DividendAdjuster.adjust(prices, [
      _event(d15, 100, 90),
      _event(d16, 90, 81),
    ], asOf: d16);

    expect(adjusted[0].close, closeTo(81, 1e-9));
    expect(adjusted[1].close, closeTo(81, 1e-9));
    expect(adjusted[2].close, 81);
  });

  test('開高低收都調整；成交量、漲跌價差、代號與日期不動；缺值維持 null', () {
    final prices = [
      DailyPriceEntry(
        symbol: 'T',
        date: d14,
        high: 110,
        close: 100,
        volume: 5000,
        priceChange: 2,
      ),
      _bar(d15, 90),
    ];

    final p = DividendAdjuster.adjust(prices, [
      _event(d15, 100, 90),
    ], asOf: d15).first;

    expect(p.open, isNull);
    expect(p.high, closeTo(99, 1e-9));
    expect(p.low, isNull);
    expect(p.close, closeTo(90, 1e-9));
    expect((p.symbol, p.date, p.volume, p.priceChange), ('T', d14, 5000.0, 2.0));
  });

  test('🚨 評分日之後的事件不套用（換日回退不得前視）', () {
    final prices = [_bar(d14, 100), _bar(d15, 100)];

    final adjusted = DividendAdjuster.adjust(prices, [
      _event(d16, 100, 90),
    ], asOf: d15);

    expect(adjusted, same(prices));
  });

  test('除權息日帶時刻：以日期比較（評分日當天的事件照套、除權息當天不調整）', () {
    final prices = [_bar(d15, 100), _bar(d16, 90)];

    final adjusted = DividendAdjuster.adjust(prices, [
      _event(DateTime(2026, 9, 16, 8), 100, 90),
    ], asOf: d16);

    expect(adjusted[0].close, closeTo(90, 1e-9));
    expect(adjusted[1].close, 90);
  });

  test('因子大於 1（認購價高於市價的現金增資）：較舊的價格往上調', () {
    final prices = [_bar(d14, 50), _bar(d15, 52.5)];

    final adjusted = DividendAdjuster.adjust(prices, [
      _event(d15, 50, 52.5),
    ], asOf: d15);

    expect(adjusted[0].close, closeTo(52.5, 1e-9));
  });

  test('停牌期間除權息：停牌前的價格照樣還原，停牌列維持 null', () {
    final prices = [
      _bar(d14, 100),
      DailyPriceEntry(symbol: 'T', date: d15),
      _bar(d17, 90),
    ];

    final adjusted = DividendAdjuster.adjust(prices, [
      _event(d16, 100, 90),
    ], asOf: d17);

    expect(adjusted[0].close, closeTo(90, 1e-9));
    expect(adjusted[1].close, isNull);
    expect(adjusted[2].close, 90);
  });

  test('不受任何事件影響的日子沿用原物件；沒有要套用的事件時回傳原序列', () {
    final prices = [_bar(d14, 100), _bar(d15, 90), _bar(d16, 90)];

    final adjusted = DividendAdjuster.adjust(prices, [
      _event(d15, 100, 90),
    ], asOf: d16);

    expect(adjusted[1], same(prices[1]));
    expect(adjusted[2], same(prices[2]));
    expect(DividendAdjuster.adjust(prices, const [], asOf: d16), same(prices));
  });
}
```

- [ ] **Step 2: 確認失敗**

Run: `flutter test test/domain/services/dividend_adjuster_test.dart`
Expected: FAIL，訊息是 `Target of URI doesn't exist`（兩個新檔還不存在）

- [ ] **Step 3: 實作**

`lib/domain/models/dividend_context.dart`：

```dart
/// 一次除權除息的還原資料：交易所列表的除權息前收盤價與除權息參考價
class DividendPriceEvent {
  const DividendPriceEvent({
    required this.exDate,
    required this.closeBefore,
    required this.referencePrice,
  });

  /// 除權息日
  final DateTime exDate;

  /// 除權息前收盤價（> 0）
  final double closeBefore;

  /// 除權息參考價（> 0）
  final double referencePrice;

  /// 還原因子＝除權息參考價 ÷ 除權息前收盤價：交易所的除權息調整比例，涵蓋
  /// 現金股利、配股與現金增資（認購價高於市價的現金增資會大於 1）
  double get factor => referencePrice / closeBefore;
}

/// 用到還原價的規則（52 週新高／新低）所需的股利情境。
///
/// 不以 null 表示：「資料不完整」與「完整、窗口內沒有除權除息」必須分得開，
/// 前者規則不觸發，後者照原始價格判斷。
sealed class DividendContext {
  const DividendContext();

  /// 窗口內除權除息資料不完整（含缺價格）：用到還原價的規則不觸發
  const factory DividendContext.incomplete() = DividendIncomplete;

  /// 窗口內除權除息資料完整；[events] 是窗口內、評分日以前（含）的全部事件
  const factory DividendContext.complete(List<DividendPriceEvent> events) =
      DividendComplete;

  /// 完整、窗口內沒有除權除息
  static const DividendContext noEvents = DividendComplete([]);
}

/// 見 [DividendContext.incomplete]
final class DividendIncomplete extends DividendContext {
  const DividendIncomplete();
}

/// 見 [DividendContext.complete]
final class DividendComplete extends DividendContext {
  const DividendComplete(this.events);

  final List<DividendPriceEvent> events;
}
```

`lib/domain/models/models.dart`：在 `export 'analysis_result.dart';` 之後加一行：

```dart
export 'dividend_context.dart';
```

`lib/domain/services/dividend_adjuster.dart`：

```dart
import 'package:drift/drift.dart' show Value;

import 'package:daredevil/core/utils/date_context.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/domain/models/dividend_context.dart';

/// 除權息還原：以交易所的除權息調整比例（[DividendPriceEvent.factor]）把
/// 歷史價格換算到評分日的價格水位，涵蓋現金股利、配股與現金增資。
///
/// 目前只有 52 週新高／新低規則使用；均線、RSI 等指標仍用原始價格（另案）。
/// 分割、減資、面額變更不在除權除息列表內，還原後仍會留下水位斷點，由呼叫端
/// 以 `contiguousSuffix` 偵測。
abstract final class DividendAdjuster {
  /// [prices] 為升冪價格序列；回傳同長度、同順序的序列：日期 d 的開高低收
  /// 乘上所有 d < 除權息日 ≤ [asOf] 事件的因子（皆以日期比較）。
  ///
  /// - 除權息當天的價格已是除權息後，不調整；[asOf] 之後的事件不套用，避免
  ///   換日回退時的前視
  /// - 成交量與漲跌價差不動，缺值維持 null
  /// - 不受任何事件影響的日子沿用原物件；沒有要套用的事件時回傳 [prices] 本身
  static List<DailyPriceEntry> adjust(
    List<DailyPriceEntry> prices,
    List<DividendPriceEvent> events, {
    required DateTime asOf,
  }) {
    final cutoff = DateContext.normalize(asOf);
    // 由新到舊排：由新到舊走價格時，「除權息日晚於這一天」的事件恰是清單前綴
    final applicable = [
      for (final e in events)
        if (!DateContext.normalize(e.exDate).isAfter(cutoff))
          (exDate: DateContext.normalize(e.exDate), factor: e.factor),
    ]..sort((a, b) => b.exDate.compareTo(a.exDate));
    if (applicable.isEmpty) return prices;

    final adjusted = List<DailyPriceEntry>.of(prices);
    var factor = 1.0;
    var next = 0;
    for (var i = prices.length - 1; i >= 0; i--) {
      final day = DateContext.normalize(prices[i].date);
      while (next < applicable.length &&
          day.isBefore(applicable[next].exDate)) {
        factor *= applicable[next].factor;
        next++;
      }
      if (next > 0) adjusted[i] = _scale(prices[i], factor);
    }
    return adjusted;
  }

  static DailyPriceEntry _scale(DailyPriceEntry p, double factor) {
    double? scale(double? value) => value == null ? null : value * factor;
    return p.copyWith(
      open: Value(scale(p.open)),
      high: Value(scale(p.high)),
      low: Value(scale(p.low)),
      close: Value(scale(p.close)),
    );
  }
}
```

- [ ] **Step 4: 確認通過**

Run: `flutter test test/domain/services/dividend_adjuster_test.dart test/tool/tool_chain_pure_dart_test.dart`
Expected: 全部 PASS（還原測試 10 條）

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 5: 記錄進度**（不 commit）

---

### Task 2: 還原用的事件查詢與 `DividendCompleteness.priceContext`

**Files:**
- Modify: `lib/data/database/dao/dividend_dao.dart`（`getDividendDistributionsBatch` 之後新增方法）
- Modify: `lib/domain/services/dividend_completeness.dart`
- Test: `test/data/database/dao/dividend_events_dao_test.dart`（新檔）
- Test: `test/domain/services/dividend_completeness_test.dart`（新 group）

**Interfaces:**
- Consumes: Task 1 的 `DividendPriceEvent`、`DividendContext`
- Produces:
  - `AppDatabase.getDividendEventsBatch(List<String> symbols, {required DateTime from, required DateTime to}) → Future<Map<String, List<DividendDistributionEntry>>>`：含 0/0 列，各檔依除息日由舊到新
  - `DividendCompleteness.priceContext(String symbol, {required DateTime from, required DateTime asOf, required Iterable<DividendDistributionEntry> rows}) → DividendContext`

- [ ] **Step 1: 寫失敗測試**

`test/data/database/dao/dividend_events_dao_test.dart`：

```dart
// 還原用的除權除息事件查詢：含只有現金增資的 0/0 列與價格兩欄，
// 只回除權息日在範圍內的列
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/data/database/app_database.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.upsertStocks([
      StockMasterCompanion.insert(symbol: '3149', name: '正達', market: 'TWSE'),
      StockMasterCompanion.insert(symbol: '2330', name: '台積電', market: 'TWSE'),
    ]);
    await db.upsertDividendDistributions([
      DividendDistributionCompanion.insert(
        symbol: '3149',
        exDate: DateTime(2026, 7, 17),
        cashDividend: 0,
        stockSharesPerThousand: 0,
        closeBefore: const Value(93.5),
        referencePrice: const Value(86.68),
      ),
      DividendDistributionCompanion.insert(
        symbol: '2330',
        exDate: DateTime(2026, 9, 16),
        cashDividend: 7,
        stockSharesPerThousand: 0,
        closeBefore: const Value(2385),
        referencePrice: const Value(2377.99),
      ),
      DividendDistributionCompanion.insert(
        symbol: '2330',
        exDate: DateTime(2026, 6, 11),
        cashDividend: 6,
        stockSharesPerThousand: 0,
        closeBefore: const Value(1100),
        referencePrice: const Value(1094),
      ),
      DividendDistributionCompanion.insert(
        symbol: '2330',
        exDate: DateTime(2025, 6, 12),
        cashDividend: 4.5,
        stockSharesPerThousand: 0,
      ),
    ]);
  });

  tearDown(() => db.close());

  test('含 0/0 列與價格兩欄；只回除權息日在範圍內（含頭尾）的列，各檔由舊到新', () async {
    final events = await db.getDividendEventsBatch(
      ['3149', '2330', '9999'],
      from: DateTime(2026, 6, 11),
      to: DateTime(2026, 9, 16),
    );

    expect(
      {
        for (final e in events.entries)
          e.key: [for (final r in e.value) r.exDate],
      },
      {
        '3149': [DateTime(2026, 7, 17)],
        '2330': [DateTime(2026, 6, 11), DateTime(2026, 9, 16)],
      },
    );
    final rights = events['3149']!.single;
    expect(
      (
        rights.cashDividend,
        rights.stockSharesPerThousand,
        rights.closeBefore,
        rights.referencePrice,
      ),
      (0.0, 0.0, 93.5, 86.68),
    );
  });

  test('沒有代號時回空', () async {
    expect(
      await db.getDividendEventsBatch(
        const [],
        from: DateTime(2026),
        to: DateTime(2027),
      ),
      isEmpty,
    );
  });
}
```

`test/domain/services/dividend_completeness_test.dart`：
1. 在 import 區加 `import 'package:daredevil/domain/models/dividend_context.dart';`。
2. 在頂層 helper（`_unresolved` 之後）加：

```dart
DividendDistributionEntry _row(
  DateTime exDate, {
  double? close = 100,
  double? reference = 95,
}) => DividendDistributionEntry(
  symbol: '2330',
  exDate: exDate,
  cashDividend: 5,
  stockSharesPerThousand: 0,
  closeBefore: close,
  referencePrice: reference,
);
```

3. 在 `main()` 最後一個 test 之前加這個 group：

```dart
  group('priceContext：用到還原價的讀取端（52 週）', () {
    final from = DateTime(2025, 9, 1);
    final asOf = DateTime(2026, 10, 2);

    test('完整：帶窗口內、評分日以前（含）的事件；除權息日等於窗口首日或晚於評分日的不帶', () {
      final c = _compute(listings: octListed);

      final context = c.priceContext(
        '2330',
        from: from,
        asOf: asOf,
        rows: [
          _row(from),
          _row(DateTime(2026, 6, 11), close: 1100, reference: 1094),
          _row(asOf, close: 1500, reference: 1490),
          _row(DateTime(2026, 10, 5)),
        ],
      );

      expect(context, isA<DividendComplete>());
      expect(
        [
          for (final e in (context as DividendComplete).events)
            (e.exDate, e.closeBefore, e.referencePrice),
        ],
        [(DateTime(2026, 6, 11), 1100.0, 1094.0), (asOf, 1500.0, 1490.0)],
      );
    });

    test('🚨 本月列表日還沒到評分日（本月同步沒跑成的那一輪）→ incomplete', () {
      final c = _compute(
        listings: [
          _listing(MarketCode.twse, _oct, DateTime(2026, 10, 1)),
          _listing(MarketCode.tpex, _oct, DateTime(2026, 10, 2)),
        ],
      );

      expect(
        c.priceContext('2330', from: from, asOf: asOf, rows: const []),
        isA<DividendIncomplete>(),
      );
    });

    test('窗內有缺價格的列（完整度條件 4，requirePrices）→ incomplete', () {
      final c = _compute(
        listings: octListed,
        missingPrices: [('2330', DateTime(2026, 9, 16))],
      );

      expect(
        c.priceContext('2330', from: from, asOf: asOf, rows: const []),
        isA<DividendIncomplete>(),
      );
    });

    test('列在完整度讀取之後才變成缺價格或 ≤ 0（兩次讀取之間被改寫）→ incomplete，不拋例外', () {
      final c = _compute(listings: octListed);

      for (final row in [
        _row(DateTime(2026, 9, 16), close: null),
        _row(DateTime(2026, 9, 16), reference: null),
        _row(DateTime(2026, 9, 16), close: 0),
        _row(DateTime(2026, 9, 16), reference: -1),
      ]) {
        expect(
          c.priceContext('2330', from: from, asOf: asOf, rows: [row]),
          isA<DividendIncomplete>(),
        );
      }
    });
  });
```

- [ ] **Step 2: 確認失敗**

Run: `flutter test test/data/database/dao/dividend_events_dao_test.dart test/domain/services/dividend_completeness_test.dart`
Expected: FAIL，訊息是 `The method 'getDividendEventsBatch' isn't defined` 與 `The method 'priceContext' isn't defined`

- [ ] **Step 3: 實作**

`lib/data/database/dao/dividend_dao.dart`，在 `getDividendDistributionsBatch` 之後加：

```dart
  /// 批次取得除權息日在 [from]～[to]（含頭尾）的除權除息列，**含只有現金
  /// 增資的 0/0 列**與前收盤、除權息參考價——還原價格用（畫面用
  /// [getDividendDistributionsBatch]，只回有配發的列）。各檔依除息日由舊到新。
  Future<Map<String, List<DividendDistributionEntry>>> getDividendEventsBatch(
    List<String> symbols, {
    required DateTime from,
    required DateTime to,
  }) async {
    if (symbols.isEmpty) return {};
    final rows =
        await (select(dividendDistribution)
              ..where(
                (t) =>
                    t.symbol.isIn(symbols) & t.exDate.isBetweenValues(from, to),
              )
              ..orderBy([(t) => OrderingTerm.asc(t.exDate)]))
            .get();
    final map = <String, List<DividendDistributionEntry>>{};
    for (final row in rows) {
      map.putIfAbsent(row.symbol, () => []).add(row);
    }
    return map;
  }
```

`lib/domain/services/dividend_completeness.dart`：
1. import 區加 `import 'package:daredevil/domain/models/dividend_context.dart';`。
2. 在 `isComplete` 之後加：

```dart
  /// 用到還原價的讀取端（52 週規則）所需的股利情境：[symbol] 在
  /// [from]～[asOf] 完整（[isComplete]，含價格）時回傳 complete，帶 [rows]
  /// 中除權息日在 [from] 之後、[asOf] 以前（含）的事件；否則 incomplete。
  ///
  /// 除權息日不晚於 [from] 的事件不影響窗內任何一天（還原只調整除權息日之前
  /// 的價格），所以不帶。[rows] 是另一次查詢讀的，中間可能被改寫：要帶的列
  /// 缺價格或價格 ≤ 0 時也回 incomplete，不拋例外。
  DividendContext priceContext(
    String symbol, {
    required DateTime from,
    required DateTime asOf,
    required Iterable<DividendDistributionEntry> rows,
  }) {
    final start = DateContext.normalize(from);
    final end = DateContext.normalize(asOf);
    if (!isComplete(symbol, start, end, requirePrices: true)) {
      return const DividendContext.incomplete();
    }
    final events = <DividendPriceEvent>[];
    for (final row in rows) {
      final exDate = DateContext.normalize(row.exDate);
      if (!exDate.isAfter(start) || exDate.isAfter(end)) continue;
      final close = row.closeBefore;
      final reference = row.referencePrice;
      if (close == null || reference == null || close <= 0 || reference <= 0) {
        return const DividendContext.incomplete();
      }
      events.add(
        DividendPriceEvent(
          exDate: exDate,
          closeBefore: close,
          referencePrice: reference,
        ),
      );
    }
    return DividendContext.complete(events);
  }
```

- [ ] **Step 4: 確認通過**

Run: `flutter test test/data/database/dao/dividend_events_dao_test.dart test/domain/services/dividend_completeness_test.dart`
Expected: 全部 PASS

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 5: 記錄進度**（不 commit）

---

### Task 3: 評分批次資料帶股利情境（載入器、batch data、isolate 輸入）

這個 task 只把股利情境接進批次資料，行為不變：規則還沒讀它，`dividendHistoryMap` 也還在，留到 Task 4 才移除。

**Files:**
- Modify: `lib/domain/services/update/batch_data_builder.dart`
- Modify: `lib/domain/services/update/batch_data_loader.dart`
- Modify: `lib/domain/models/scoring_batch_data.dart`
- Modify: `lib/domain/services/scoring_isolate.dart`（`ScoringIsolateInput`）
- Modify: `lib/domain/services/scoring_service.dart`（`scoreStocksInIsolate`）
- Create: `test/domain/services/update/batch_data_loader_dividend_test.dart`
- Modify（測試）：建構 `ScoringBatchData(`／`ScoringIsolateInput(` 的測試檔（用腳本處理），以及 `batch_data_loader_test.dart`、`update_service_test.dart`、`scoring_watchlist_zero_reason_test.dart`

**Interfaces:**
- Consumes: Task 2 的 `getDividendEventsBatch`、`priceContext`；3-1 的 `loadDividendCompleteness(AppDatabase db, {required DateTime now})`
- Produces:
  - `BatchDataBuilder.buildDividendContexts({required Map<String, List<DailyPriceEntry>> pricesMap, required DividendCompleteness completeness, required Map<String, List<DividendDistributionEntry>> events, required DateTime date}) → Map<String, DividendContext>`
  - `ScoringBatchData.dividendContexts`（`Map<String, DividendContext>`，兩個建構子都必填）
  - `ScoringIsolateInput.dividendContexts`（同型別，必填）

- [ ] **Step 1: 寫失敗測試**

`test/domain/services/update/batch_data_loader_dividend_test.dart`：

```dart
// 評分批次的股利情境（52 週規則用）：載入器讀完整度事實與價格窗內的
// 除權除息，以「價格窗首日～評分日」判斷每檔是否完整
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:daredevil/core/constants/market_codes.dart';
import 'package:daredevil/core/utils/calendar_month.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/data/repositories/news_repository.dart';
import 'package:daredevil/domain/models/dividend_context.dart';
import 'package:daredevil/domain/services/update/batch_data_loader.dart';

class _MockNewsRepo extends Mock implements NewsRepository {}

void main() {
  late AppDatabase db;
  late BatchDataLoader loader;
  final date = DateTime(2026, 10, 2);

  setUp(() async {
    db = AppDatabase.forTesting();
    final news = _MockNewsRepo();
    when(
      () => news.getNewsForStocksBatch(any(), days: any(named: 'days')),
    ).thenAnswer((_) async => {});
    loader = BatchDataLoader(database: db, newsRepository: news);
    await db.upsertStocks([
      for (final s in ['2330', '2836', '6669'])
        StockMasterCompanion.insert(symbol: s, name: s, market: 'TWSE'),
    ]);
  });

  tearDown(() => db.close());

  /// [first]～評分日逐日一根：價格窗首日＝[first]
  Future<void> seedPrices(String symbol, DateTime first) => db.insertPrices([
    for (
      var d = first;
      !d.isAfter(date);
      d = DateTime(d.year, d.month, d.day + 1)
    )
      DailyPriceCompanion.insert(
        symbol: symbol,
        date: d,
        close: const Value(100),
        volume: const Value(1000),
      ),
  ]);

  /// 兩市場 2025-09～2026-09 完成，10 月列到 [octThrough]
  Future<void> seedFacts({required DateTime octThrough}) async {
    for (final market in [MarketCode.twse, MarketCode.tpex]) {
      for (final m in CalendarMonth.descending(
        from: const CalendarMonth(2025, 9),
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
        to: octThrough,
        listedThrough: octThrough,
        listedKnownKeys: const {},
        notInMasterKeys: const {},
        recordedAt: DateTime(2026, 10, 2, 15),
      );
    }
  }

  test('窗口完整且有價格：complete，帶窗內事件', () async {
    await seedPrices('2330', DateTime(2025, 9, 1));
    await seedFacts(octThrough: date);
    await db.upsertDividendDistributions([
      DividendDistributionCompanion.insert(
        symbol: '2330',
        exDate: DateTime(2026, 9, 16),
        cashDividend: 7,
        stockSharesPerThousand: 0,
        closeBefore: const Value(2385),
        referencePrice: const Value(2377.99),
      ),
    ]);

    final batch = await loader.loadBatchData(date, ['2330']);

    final context = batch.dividendContexts['2330'];
    expect(context, isA<DividendComplete>());
    final event = (context as DividendComplete).events.single;
    expect(event.exDate, DateTime(2026, 9, 16));
    expect(event.factor, closeTo(2377.99 / 2385, 1e-12));
  });

  test('價格窗首日早於完整範圍（價格比事實早幾天）→ incomplete：完整度看整個價格窗', () async {
    await seedPrices('6669', DateTime(2025, 8, 29));
    await seedFacts(octThrough: date);

    final batch = await loader.loadBatchData(date, ['6669']);

    expect(batch.dividendContexts['6669'], isA<DividendIncomplete>());
  });

  test('🚨 本月列表日落後評分日（本月同步沒跑成的那一輪）→ incomplete', () async {
    await seedPrices('2330', DateTime(2025, 9, 1));
    await seedFacts(octThrough: DateTime(2026, 10, 1));

    final batch = await loader.loadBatchData(date, ['2330']);

    expect(batch.dividendContexts['2330'], isA<DividendIncomplete>());
  });

  test('窗內有缺價格的列 → incomplete；沒有價格的代號不列入', () async {
    await seedPrices('2836', DateTime(2025, 9, 1));
    await seedFacts(octThrough: date);
    await db.upsertDividendDistributions([
      DividendDistributionCompanion.insert(
        symbol: '2836',
        exDate: DateTime(2026, 9, 17),
        cashDividend: 0.15,
        stockSharesPerThousand: 45,
      ),
    ]);

    final batch = await loader.loadBatchData(date, ['2836', '2330']);

    expect(batch.dividendContexts['2836'], isA<DividendIncomplete>());
    expect(batch.dividendContexts.containsKey('2330'), isFalse);
  });
}
```

`test/domain/services/scoring_watchlist_zero_reason_test.dart` 的 sendability 測試（`ScoringIsolateInput(` 第二處，`candidates: const ['1111']` 那個）：
1. 在 `maxHistoricalRevenueMap: const {'1111': 1.0},` 之前加入：

```dart
        dividendContexts: {
          '1111': DividendContext.complete([
            DividendPriceEvent(
              exDate: today,
              closeBefore: 100,
              referencePrice: 95,
            ),
          ]),
          '2330': const DividendContext.incomplete(),
        },
```

2. import 區加 `import 'package:daredevil/domain/models/dividend_context.dart';`。

- [ ] **Step 2: 確認失敗**

Run: `flutter test test/domain/services/update/batch_data_loader_dividend_test.dart test/domain/services/scoring_watchlist_zero_reason_test.dart`
Expected: FAIL，訊息是 `The getter 'dividendContexts' isn't defined` 與 `No named parameter with the name 'dividendContexts'`

- [ ] **Step 3: 實作**

`lib/domain/services/update/batch_data_builder.dart`：
1. import 區加：

```dart
import 'package:daredevil/domain/models/dividend_context.dart';
import 'package:daredevil/domain/services/dividend_completeness.dart';
```

2. 在 class 內 `fillNoActivityDays` 之前加：

```dart
  /// 每檔用到還原價的規則（52 週）所需的股利情境：價格窗首日～[date] 的
  /// 除權除息完整（含價格）時帶窗內事件，否則 incomplete（見
  /// [DividendCompleteness.priceContext]）。沒有價格的代號不列入。
  static Map<String, DividendContext> buildDividendContexts({
    required Map<String, List<DailyPriceEntry>> pricesMap,
    required DividendCompleteness completeness,
    required Map<String, List<DividendDistributionEntry>> events,
    required DateTime date,
  }) => {
    for (final MapEntry(key: symbol, value: prices) in pricesMap.entries)
      if (prices.isNotEmpty)
        symbol: completeness.priceContext(
          symbol,
          from: prices.first.date,
          asOf: date,
          rows: events[symbol] ?? const [],
        ),
  };
```

`lib/domain/models/scoring_batch_data.dart`：
1. import 區加 `import 'package:daredevil/domain/models/dividend_context.dart';`。
2. 兩個建構子都在 `required this.newsMap,` 之後加 `required this.dividendContexts,`。
3. 在 `newsMap` 欄位之後加：

```dart
  /// 用到還原價的規則（52 週新高／新低）所需的股利情境（symbol → 情境），
  /// 由 `BatchDataLoader` 依完整度事實算好；沒有的代號視為不完整
  final Map<String, DividendContext> dividendContexts;
```

`lib/domain/services/update/batch_data_loader.dart`：
1. import 區加 `import 'package:daredevil/domain/services/dividend_completeness.dart';`。
2. 在 `final maxRevenueFuture = ...;` 之後加：

```dart
    // 52 週規則的股利情境：完整度事實＋價格窗內的除權除息（含 0/0 列）
    final dividendCompletenessFuture = timed(
      'dividendCompleteness',
      loadDividendCompleteness(_db, now: date),
    );
    final dividendEventsFuture = timed(
      'dividendEvents',
      _db.getDividendEventsBatch(candidates, from: startDate, to: date),
    );
```

3. 第三組 `.wait` 擴成 9 個：

```dart
    final (
      prevShareholdingEntries,
      warningEntries,
      insiderEntries,
      epsHistoryMap,
      roeHistoryMap,
      dividendHistoryMap,
      maxHistoricalRevenueMap,
      dividendCompleteness,
      dividendEvents,
    ) = await (
      prevShareholdingFuture,
      warningFuture,
      insiderFuture,
      epsFuture,
      roeFuture,
      dividendFuture,
      maxRevenueFuture,
      dividendCompletenessFuture,
      dividendEventsFuture,
    ).wait;
```

4. 在 `return ScoringBatchData.grouped(` 之前加：

```dart
    final dividendContexts = BatchDataBuilder.buildDividendContexts(
      pricesMap: pricesMap,
      completeness: dividendCompleteness,
      events: dividendEvents,
      date: date,
    );
```

5. `ScoringBatchData.grouped(` 的引數在 `newsMap: newsMap,` 之後加 `dividendContexts: dividendContexts,`。

`lib/domain/services/scoring_isolate.dart`（`ScoringIsolateInput`）：
1. 建構子在 `required this.institutionalMap,` 之後加 `required this.dividendContexts,`。
2. 在 `institutionalMap` 欄位之後加：

```dart
  /// 用到還原價的規則（52 週新高／新低）所需的股利情境（symbol → 情境）；
  /// 沒有的代號視為不完整（見 `ScoringBatchData.dividendContexts`）
  final Map<String, DividendContext> dividendContexts;
```

`lib/domain/services/scoring_service.dart`（`scoreStocksInIsolate` 建 `ScoringIsolateInput(` 處）：在 `institutionalMap:` 引數之後加 `dividendContexts: batchData.dividendContexts,`。

- [ ] **Step 4: 既有測試補參數**

1. 建構 `ScoringBatchData(` 或 `ScoringIsolateInput(` 的測試都補上 `dividendContexts: {}`。在 repo 根目錄存成 `<scratchpad>/add_arg.py` 後執行（Task 4 也會用到）：

```python
import pathlib, re, subprocess, sys

def add_arg(path, ctor, arg):
    """在 path 每個 `ctor(` 呼叫的參數尾端補上 arg；已有同名參數的略過。回傳補了幾處"""
    p = pathlib.Path(path)
    s = p.read_text()
    name = arg.split(':')[0].strip()
    pat = re.compile(r'(?<![A-Za-z0-9_.])' + re.escape(ctor) + r'\(')
    out, i, n = [], 0, 0
    for m in pat.finditer(s):
        if m.start() < i:
            continue
        k = j = m.end()
        depth = 1
        while depth:
            depth += {'(': 1, ')': -1}.get(s[j], 0)
            j += 1
        args = s[k:j - 1]
        if re.search(r'\b' + re.escape(name) + r'\s*:', args) is None:
            body = args.rstrip()
            tail = args[len(body):]
            args = body + ('' if body.endswith(',') else ',') + ' ' + arg + ',' + tail
            n += 1
        out.append(s[i:k] + args + ')')
        i = j
    out.append(s[i:])
    p.write_text(''.join(out))
    return n

if __name__ == '__main__':
    pattern, ctors, arg = sys.argv[1], sys.argv[2].split(','), sys.argv[3]
    files = subprocess.run(['grep', '-rlE', '--include=*.dart', pattern, 'test'],
                           capture_output=True, text=True).stdout.split()
    total = 0
    for f in sorted(files):
        for ctor in ctors:
            n = add_arg(f, ctor, arg)
            if n:
                print(f, ctor, n)
                total += n
    print('total', total)
```

Run: `python3 <scratchpad>/add_arg.py 'ScoringBatchData\(|ScoringIsolateInput\(' 'ScoringBatchData,ScoringIsolateInput' 'dividendContexts: {}'`
Expected: 逐檔印出補了幾處，最後是 `total N`。sendability 那處已手寫，會被略過。

2. `test/domain/services/update/batch_data_loader_test.dart` 的 `setUp`，在 `getDividendHistoryBatch` 的 stub 之後加：

```dart
    when(
      () => db.getDividendEventsBatch(
        any(),
        from: any(named: 'from'),
        to: any(named: 'to'),
      ),
    ).thenAnswer((_) async => {});
    when(() => db.getDividendListings()).thenAnswer((_) async => []);
    when(() => db.getDividendMonthLedgerEntries()).thenAnswer((_) async => []);
    when(() => db.getDividendUnresolved()).thenAnswer((_) async => []);
    when(() => db.getDividendMissingPriceKeys()).thenAnswer((_) async => {});
```

3. `test/domain/services/update_service_test.dart` 的 `setUp`（UpdateService 內部用 mock DB 建了真的 `BatchDataLoader`）：在 `mockDb.getDividendHistoryBatch` 的 stub 之後加入同樣五個 stub，`db` 換成 `mockDb`。

Run: `dart format test`
Run: `flutter analyze`
Expected: `No issues found!`。若出現語法錯誤，多半是註解或字串裡有不成對的括號，手動修正後重跑。

- [ ] **Step 5: 確認通過**

Run: `flutter test test/domain/services/update/ test/domain/services/scoring_service_test.dart test/domain/services/scoring_watchlist_zero_reason_test.dart test/domain/services/scoring_isolate_dual_horizon_test.dart test/domain/services/scoring_isolate_accounting_test.dart test/domain/services/update_service_test.dart`
Expected: 全部 PASS

- [ ] **Step 6: 記錄進度**（不 commit）

---

### Task 4: 52 週規則改用還原價（`StockData.dividends` 必填、所有建構點、校準回放）

**Files:**
- Modify: `lib/domain/services/rules/stock_rules.dart`
- Modify: `lib/domain/services/rules/indicator_rules.dart`
- Modify: `lib/domain/services/scoring_isolate.dart`、`lib/domain/services/scoring_service.dart`
- Modify: `lib/domain/models/scoring_batch_data.dart`、`lib/domain/models/scoring_data_groups.dart`
- Modify: `lib/domain/services/update/batch_data_loader.dart`
- Modify: `tool/replay_calibrator.dart`、`lib/core/constants/calibration_thresholds.dart`
- Modify: `test/tools/scoring_snapshot.dart`、`test/helpers/stock_data_builders.dart`
- Test: `test/domain/services/rules/indicator_rules_test.dart`（兩組 52 週測試改寫，新增 `week52AdjustedPrices` 一組）
- Test: `test/tool/replay_production_parity_test.dart`、`test/tool/recalibrate_meta_test.dart`
- Modify（測試）：其餘建構 `StockData(` 的測試檔（用腳本處理）

**Interfaces:**
- Consumes: Task 1 的 `DividendAdjuster`、`DividendContext`；Task 3 的 `dividendContexts`
- Produces:
  - `StockData.dividends`（`DividendContext`，必填）；移除 `StockData.dividendHistory`
  - `enum Week52Block { incomplete, discontinuity }`
  - `week52AdjustedPrices(StockData data) → ({List<DailyPriceEntry>? adjusted, Week52Block? block})`

- [ ] **Step 1: 寫失敗測試**

`test/domain/services/rules/indicator_rules_test.dart`：
1. import 區加 `import 'package:daredevil/domain/models/dividend_context.dart';`（若已 import `models.dart` 則略過）。
2. 在 `void main() {` 之前加頂層 helper：

```dart
/// 從 2025-01-01 起逐日一根，高低為收盤 ±2%
List<DailyPriceEntry> _daily(List<double> closes) =>
    generatePriceHistoryFromList(
      prices: closes,
      startDate: DateTime(2025, 1, 1),
    );

/// 第 [i] 根的日期
DateTime _day(int i) => DateTime(2025, 1, 1).add(Duration(days: i));

List<double> _flat(int n, double value) => List.filled(n, value);

/// 第 200 根除息（前收 100 → 參考價 90，因子 0.9）的 260 根：第 50 根是原始
/// 高點 104（高 106.08），還原後只剩 95.47；第 230 根的 97（高 98.94）才是
/// 還原後的高點。今天收 99：原始差 6.7% 不觸發，還原後創新高
List<double> _adjustOnlyHighCloses() =>
    [..._flat(200, 100), ..._flat(59, 95), 99.0]
      ..[50] = 104
      ..[230] = 97;

final _exAt200 = DividendPriceEvent(
  exDate: _day(200),
  closeBefore: 100,
  referencePrice: 90,
);

AnalysisContext _ctx() => AnalysisContext(
  evaluationTime: _day(259),
  trendState: TrendState.range,
);
```

3. 把 `group('Week52HighRule', ...)` 與 `group('Week52LowRule', ...)` 整段換成下面的內容。原本與股利無關的測試保留，只加上 `dividends: DividendContext.noEvents`；舊的「現金股利扣除」兩條刪掉。

```dart
  // ==========================================
  // Week52HighRule
  // ==========================================
  group('Week52HighRule', () {
    const rule = Week52HighRule();

    test('triggers when close is a new 52-week high', () {
      final prices = generateConstantPrices(days: 249, basePrice: 100.0);
      prices.add(
        createTestPrice(
          date: DateTime.now(),
          open: 104.0,
          high: 106.0,
          low: 103.0,
          close: 105.0,
          volume: 1000,
        ),
      );
      final data = StockData(
        symbol: 'TEST',
        prices: prices,
        dividends: DividendContext.noEvents,
      );

      final result = rule.evaluate(_ctx(), data);

      expect(result, isNotNull);
      expect(result!.type, equals(ReasonType.week52High));
      expect(result.score, equals(RuleScores.week52High));
      expect(result.evidence!['isNewHigh'], isTrue);
    });

    test('triggers when close is near 52-week high (within threshold)', () {
      final prices = generateConstantPrices(days: 249, basePrice: 100.0);
      prices.add(
        createTestPrice(date: DateTime.now(), close: 100.5, volume: 1000),
      );
      final data = StockData(
        symbol: 'TEST',
        prices: prices,
        dividends: DividendContext.noEvents,
      );

      final result = rule.evaluate(_ctx(), data);

      expect(result, isNotNull);
      expect(result!.evidence!['isNewHigh'], isFalse);
    });

    test('does not trigger when close is far from 52-week high', () {
      final prices = generateConstantPrices(days: 249, basePrice: 100.0);
      prices.add(
        createTestPrice(date: DateTime.now(), close: 90.0, volume: 1000),
      );
      final data = StockData(
        symbol: 'TEST',
        prices: prices,
        dividends: DividendContext.noEvents,
      );

      expect(rule.evaluate(_ctx(), data), isNull);
    });

    test('does not trigger with insufficient data (< 250 days)', () {
      final data = StockData(
        symbol: 'TEST',
        prices: generateConstantPrices(days: 100, basePrice: 100.0),
        dividends: DividendContext.noEvents,
      );

      expect(rule.evaluate(_ctx(), data), isNull);
    });

    test('does not trigger when close is null', () {
      final prices = generateConstantPrices(days: 249, basePrice: 100.0);
      prices.add(createTestPrice(date: DateTime.now()));
      final data = StockData(
        symbol: 'TEST',
        prices: prices,
        dividends: DividendContext.noEvents,
      );

      expect(rule.evaluate(_ctx(), data), isNull);
    });

    test('🚨 還原後才創新高：極值以還原後價格判斷，evidence 保留原始極值與兩者差', () {
      final prices = _daily(_adjustOnlyHighCloses());

      expect(
        rule.evaluate(
          _ctx(),
          StockData(
            symbol: 'T',
            prices: prices,
            dividends: DividendContext.noEvents,
          ),
        ),
        isNull,
        reason: '前提：沒有除權息事件時，原始高點 106.08 讓今天的 99 差太遠',
      );

      final result = rule.evaluate(
        _ctx(),
        StockData(
          symbol: 'T',
          prices: prices,
          dividends: DividendContext.complete([_exAt200]),
        ),
      );

      expect(result, isNotNull);
      expect(result!.description, '創 52 週新高');
      final e = result.evidence!;
      expect(e['week52High'], closeTo(106.08, 1e-9), reason: '原始極值（第 50 根）');
      expect(e['adjustedHigh'], closeTo(98.94, 1e-9), reason: '還原後極值（第 230 根）');
      expect(e['dividendAdjustment'], closeTo(7.14, 1e-9));
      expect(e['isNewHigh'], isTrue);
    });

    test('🚨 股利資料不完整：原始價格會觸發也不觸發', () {
      final prices = _daily([..._flat(259, 100), 103.0]);

      expect(
        rule.evaluate(
          _ctx(),
          StockData(
            symbol: 'T',
            prices: prices,
            dividends: DividendContext.noEvents,
          ),
        ),
        isNotNull,
        reason: '前提：資料完整時照原始價格會觸發',
      );
      expect(
        rule.evaluate(
          _ctx(),
          StockData(
            symbol: 'T',
            prices: prices,
            dividends: const DividendContext.incomplete(),
          ),
        ),
        isNull,
      );
    });

    test('🚨 還原後仍有水位斷點（減資、分割等不在除權除息列表）→ 不觸發', () {
      // 第 200 根起從 50 跳到 100；今天 101.5 在原始高點 102 的 1% 內
      final data = StockData(
        symbol: 'T',
        prices: _daily([..._flat(200, 50), ..._flat(59, 100), 101.5]),
        dividends: DividendContext.noEvents,
      );

      expect(week52AdjustedPrices(data).block, Week52Block.discontinuity);
      expect(rule.evaluate(_ctx(), data), isNull);
    });

    test('🚨 除權息日在今天之後的事件不套用（不得前視）', () {
      final data = StockData(
        symbol: 'T',
        prices: _daily(_adjustOnlyHighCloses()),
        dividends: DividendContext.complete([
          DividendPriceEvent(
            exDate: _day(260),
            closeBefore: 100,
            referencePrice: 90,
          ),
        ]),
      );

      expect(rule.evaluate(_ctx(), data), isNull);
    });
  });

  // ==========================================
  // Week52LowRule
  // ==========================================
  group('Week52LowRule', () {
    const rule = Week52LowRule();

    test('triggers in downtrend with close near 52-week low', () {
      final prices = _generateDowntrendWithVolume(
        days: 250,
        startPrice: 200.0,
        dailyLoss: 0.3,
      );
      final data = StockData(
        symbol: 'TEST',
        prices: prices,
        dividends: DividendContext.noEvents,
      );

      final result = rule.evaluate(_ctx(), data);

      expect(result, isNotNull);
      expect(result!.type, equals(ReasonType.week52Low));
      expect(result.score, equals(RuleScores.week52Low));
    });

    test('does not trigger when close is far from 52-week low', () {
      final prices = generateConstantPrices(days: 249, basePrice: 100.0);
      prices.add(
        createTestPrice(date: DateTime.now(), close: 200.0, volume: 1000),
      );
      final data = StockData(
        symbol: 'TEST',
        prices: prices,
        dividends: DividendContext.noEvents,
      );

      expect(rule.evaluate(_ctx(), data), isNull);
    });

    test('does not trigger when MA filter not confirmed (close >= MA20)', () {
      // 持平 100：收盤＝MA20，未確認空頭
      final data = StockData(
        symbol: 'TEST',
        prices: generateConstantPrices(days: 250, basePrice: 100.0),
        dividends: DividendContext.noEvents,
      );

      expect(rule.evaluate(_ctx(), data), isNull);
    });

    test('does not trigger with insufficient data', () {
      final data = StockData(
        symbol: 'TEST',
        prices: generateConstantPrices(days: 100, basePrice: 100.0),
        dividends: DividendContext.noEvents,
      );

      expect(rule.evaluate(_ctx(), data), isNull);
    });

    test('🚨 均線用還原後收盤：除權息跳空造成的原始空頭排列不算數', () {
      // 第 250 根除息（因子 0.9），之後持平 90。原始 MA20＝95、MA60≈98.3，
      // 收盤 90 < MA20 < MA60 看似空頭；還原後整段持平 90，收盤不低於 MA20
      final prices = _daily([..._flat(250, 100), ..._flat(10, 90)]);
      final context = AnalysisContext(
        evaluationTime: _day(259),
        trendState: TrendState.down,
        indicators: indicatorsFromPrices(prices),
      );
      expect(
        context.indicators!.ma20! < context.indicators!.ma60!,
        isTrue,
        reason: '前提：原始均線呈空頭排列',
      );

      final data = StockData(
        symbol: 'T',
        prices: prices,
        dividends: DividendContext.complete([
          DividendPriceEvent(
            exDate: _day(250),
            closeBefore: 100,
            referencePrice: 90,
          ),
        ]),
      );

      expect(rule.evaluate(context, data), isNull);
    });
  });

  // ==========================================
  // week52AdjustedPrices（規則與每輪觀測共用）
  // ==========================================
  group('week52AdjustedPrices', () {
    test('不足 250 根：不評估、不計入觀測', () {
      final r = week52AdjustedPrices(
        StockData(
          symbol: 'T',
          prices: _daily(_flat(249, 100)),
          dividends: const DividendContext.incomplete(),
        ),
      );

      expect((r.adjusted, r.block), (null, null));
    });

    test('不完整 → incomplete', () {
      final r = week52AdjustedPrices(
        StockData(
          symbol: 'T',
          prices: _daily(_flat(260, 100)),
          dividends: const DividendContext.incomplete(),
        ),
      );

      expect((r.adjusted, r.block), (null, Week52Block.incomplete));
    });

    test('除權息解釋得了的跳空可用（截止日＝最後一根）；解釋不了的是斷點', () {
      final prices = _daily([..._flat(200, 100), ..._flat(60, 80)]); // −20%

      expect(
        week52AdjustedPrices(
          StockData(
            symbol: 'T',
            prices: prices,
            dividends: DividendContext.noEvents,
          ),
        ).block,
        Week52Block.discontinuity,
      );

      final r = week52AdjustedPrices(
        StockData(
          symbol: 'T',
          prices: prices,
          dividends: DividendContext.complete([
            DividendPriceEvent(
              exDate: _day(200),
              closeBefore: 100,
              referencePrice: 80,
            ),
          ]),
        ),
      );
      expect(r.block, isNull);
      expect(r.adjusted, hasLength(260));
      expect(r.adjusted!.first.close, closeTo(80, 1e-9));
    });
  });
```

`test/tool/replay_production_parity_test.dart`：在 `(c)` 那條測試之後加：

```dart
  test('🚨 (d) 股利情境一律 incomplete：校準 DB 沒有除權除息配發資料，52 週在回放中不觸發（與生產刻意不同）', () async {
    await seedPrices('1111', 120);

    await makeCalibrator().run();

    final snapshots = capturedFor('1111');
    expect(snapshots, isNotEmpty);
    expect(
      snapshots.map((s) => s.dividends),
      everyElement(isA<DividendIncomplete>()),
    );
  });
```

`test/tool/recalibrate_meta_test.dart`：在 `group('notBackfillableReasons', ...)` 內加：

```dart
    test('🚨 52 週新高／新低歸「抓不到」：回放沒有除權除息配發資料', () {
      expect(
        CalibrationThresholds.notBackfillableReasons,
        containsAll(['WEEK_52_HIGH', 'WEEK_52_LOW']),
      );
    });
```

- [ ] **Step 2: 確認失敗**

Run: `flutter test test/domain/services/rules/indicator_rules_test.dart test/tool/recalibrate_meta_test.dart`
Expected: FAIL。indicator 測試是編譯錯誤（`No named parameter with the name 'dividends'`、`week52AdjustedPrices` 未定義）；meta 測試是 `containsAll` 不成立。

- [ ] **Step 3: `StockData` 與規則**

`lib/domain/services/rules/stock_rules.dart`：
1. 建構子在 `required this.prices,` 之後加 `required this.dividends,`，並刪除 `this.dividendHistory,`。
2. 刪除 `dividendHistory` 欄位與它的註解，在 `prices` 欄位之後加：

```dart
  /// 除權除息情境（52 週新高／新低還原價格用）：完整時帶窗口內、評分日以前
  /// 的事件；不完整時用到還原價的規則不觸發。刻意必填——評分兩條路徑與工具
  /// 都必須明確決定，漏傳會讓 52 週規則用原始價格判斷或靜默停發
  final DividendContext dividends;
```

`lib/domain/services/rules/indicator_rules.dart`：
1. import 區換成：

```dart
import 'package:daredevil/core/constants/rule_params.dart';
import 'package:daredevil/core/utils/logger.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/domain/services/dividend_adjuster.dart';
import 'package:daredevil/domain/services/price_calculator.dart';
import 'package:daredevil/domain/services/price_continuity.dart';
import 'package:daredevil/domain/services/technical_indicator_service.dart';
import 'package:daredevil/domain/models/models.dart';
import 'package:daredevil/domain/services/rules/stock_rules.dart';
```

2. 從 `/// 計算價格歷史期間內的累計現金股利` 開始，到 `Week52LowRule` class 的結尾，整段換成：

```dart
/// 52 週規則不評估的原因（每輪觀測計數用）
enum Week52Block {
  /// 窗口內除權除息資料不完整（含缺價格）
  incomplete,

  /// 還原後仍有水位斷點（減資、分割、面額變更等不在除權除息列表的事件）
  discontinuity,
}

/// 52 週新高／新低用的還原價格與閘門，規則與每輪觀測共用同一個判斷：
///
/// - 不足 [IndicatorParams.week52Days] 根：兩者皆 null（規則本來就不評估，
///   不計入觀測）
/// - 股利情境不完整：block 為 [Week52Block.incomplete]
/// - 以交易所除權息參考價還原（[DividendAdjuster]，截止日＝最後一根的日期，
///   評分時由候選資格保證它就是評分日）後仍有水位斷點：block 為
///   [Week52Block.discontinuity]
/// - 其餘：adjusted 為還原後的整段價格
({List<DailyPriceEntry>? adjusted, Week52Block? block}) week52AdjustedPrices(
  StockData data,
) {
  if (data.prices.length < IndicatorParams.week52Days) {
    return (adjusted: null, block: null);
  }
  final dividends = data.dividends;
  if (dividends is! DividendComplete) {
    return (adjusted: null, block: Week52Block.incomplete);
  }
  final adjusted = DividendAdjuster.adjust(
    data.prices,
    dividends.events,
    asOf: data.prices.last.date,
  );
  if (adjusted.contiguousSuffix().length < adjusted.length) {
    return (adjusted: null, block: Week52Block.discontinuity);
  }
  return (adjusted: adjusted, block: null);
}

/// 52 週新高/新低的方向
enum _Week52Direction { high, low }

/// [series] 排除最後一根（今日）的極值與有效根數；沒有有效值時回 null
({double value, int validCount})? _week52Extreme(
  List<DailyPriceEntry> series, {
  required bool isHigh,
}) {
  double? extreme;
  var validCount = 0;
  for (var i = 0; i < series.length - 1; i++) {
    final p = series[i];
    final value = isHigh ? (p.high ?? p.close) : (p.low ?? p.close);
    if (value == null || value <= 0) continue;
    validCount++;
    if (extreme == null || (isHigh ? value > extreme : value < extreme)) {
      extreme = value;
    }
  }
  return extreme == null ? null : (value: extreme, validCount: validCount);
}

/// 52 週新高/新低規則的共用基底類別
///
/// 極值以 [week52AdjustedPrices] 還原後的價格計算（2026-10 起；之前從極值扣掉
/// 窗內現金股利，但除息日幾乎全空，扣除額實際為 0），evidence 同時保留原始
/// 極值。股利資料不完整或還原後仍有水位斷點時不觸發。
abstract class _Week52RuleBase extends StockRule {
  const _Week52RuleBase({
    required _Week52Direction direction,
    required String ruleId,
    required String ruleName,
    required ReasonType reasonType,
    required int ruleScore,
    required double threshold,
  }) : _direction = direction,
       _ruleId = ruleId,
       _ruleName = ruleName,
       _reasonType = reasonType,
       _ruleScore = ruleScore,
       _threshold = threshold;

  final _Week52Direction _direction;
  final String _ruleId;
  final String _ruleName;
  final ReasonType _reasonType;
  final int _ruleScore;
  final double _threshold;

  @override
  String get id => _ruleId;

  /// 子類別可覆寫以加入額外過濾條件（例如 MA 空頭確認）；[adjusted] 是還原後
  /// 的整段價格。回傳 true 表示應過濾掉（不觸發）。
  bool additionalFilter(
    String symbol,
    List<DailyPriceEntry> adjusted,
    double close,
  ) => false;

  @override
  TriggeredReason? evaluate(AnalysisContext context, StockData data) {
    final isHigh = _direction == _Week52Direction.high;

    // 診斷：資料不足時記錄
    if (data.prices.length < IndicatorParams.week52Days) {
      if (data.prices.length >= IndicatorParams.historicalDataMinDays) {
        AppLogger.debug(
          _ruleName,
          '${data.symbol}: 資料不足 (${data.prices.length}/${IndicatorParams.week52Days})',
        );
      }
      return null;
    }

    final close = data.prices.last.close;
    if (close == null) return null;

    final adjusted = week52AdjustedPrices(data).adjusted;
    if (adjusted == null) return null;

    // 從「過去」的價格歷史計算 52 週極值（排除今日），避免前瞻偏差
    final adj = _week52Extreme(adjusted, isHigh: isHigh);
    if (adj == null || adj.validCount < IndicatorParams.week52MinValidBars) {
      return null;
    }
    // 還原只乘正數因子、不改變哪幾根有效，所以原始極值必有值
    final raw = _week52Extreme(data.prices, isHigh: isHigh)!;

    // 收盤是否處於或接近還原後的 52 週極值（在門檻範圍內）；今日不受任何
    // 事件影響，收盤就是還原後的收盤
    final extreme = adj.value;
    final thresholdPrice = isHigh
        ? extreme * (1 - _threshold)
        : extreme * (1 + _threshold);
    final isInRange = isHigh
        ? close >= thresholdPrice
        : close <= thresholdPrice;
    if (!isInRange) return null;

    // 子類別額外過濾（例如 Week52Low 的 MA 空頭趨勢確認）
    if (additionalFilter(data.symbol, adjusted, close)) return null;

    final isNew = isHigh ? close >= extreme : close <= extreme;
    final extremeLabel = isHigh ? '高' : '低';
    AppLogger.debug(
      _ruleName,
      '${data.symbol}: 收盤=${close.toStringAsFixed(2)}, '
      '52週$extremeLabel=${raw.value.toStringAsFixed(2)}, '
      '還原後=${extreme.toStringAsFixed(2)}, '
      '新$extremeLabel=$isNew',
    );
    return TriggeredReason(
      type: _reasonType,
      score: _ruleScore,
      description: isNew ? '創 52 週新$extremeLabel' : '接近 52 週新$extremeLabel',
      evidence: {
        'close': close,
        if (isHigh) 'week52High': raw.value else 'week52Low': raw.value,
        if (isHigh) 'adjustedHigh': extreme else 'adjustedLow': extreme,
        'dividendAdjustment': raw.value - extreme,
        if (isHigh) 'isNewHigh': isNew else 'isNewLow': isNew,
      },
    );
  }
}

/// 規則：52 週新高偵測
///
/// 當收盤價處於或接近 52 週高點時觸發
class Week52HighRule extends _Week52RuleBase {
  const Week52HighRule()
    : super(
        direction: _Week52Direction.high,
        ruleId: 'week_52_high',
        ruleName: '52週新高',
        reasonType: ReasonType.week52High,
        ruleScore: RuleScores.week52High,
        threshold: IndicatorParams.week52HighThreshold,
      );
}

/// 規則：52 週新低偵測
///
/// 當收盤價處於或接近 52 週低點時觸發
class Week52LowRule extends _Week52RuleBase {
  const Week52LowRule()
    : super(
        direction: _Week52Direction.low,
        ruleId: 'week_52_low',
        ruleName: '52週新低',
        reasonType: ReasonType.week52Low,
        ruleScore: RuleScores.week52Low,
        threshold: IndicatorParams.week52LowThreshold,
      );

  /// 精準度過濾：確認近期確實處於下跌趨勢，避免長期盤整在低檔區的股票誤觸發。
  /// 均線以還原後收盤計算——原始價格的 MA60 含除權息前的較高價格，除權息的
  /// 跳空會讓「收盤 < MA20 < MA60」看似成立
  @override
  bool additionalFilter(
    String symbol,
    List<DailyPriceEntry> adjusted,
    double close,
  ) {
    final ma20 = TechnicalIndicatorService.latestSMA(adjusted, 20);
    final ma60 = TechnicalIndicatorService.latestSMA(adjusted, 60);

    // 過濾條件：收盤價 < MA20 且 MA20 < MA60（空頭趨勢確認）
    if (ma20 != null && ma60 != null) {
      if (close >= ma20 || ma20 >= ma60) {
        AppLogger.debug(
          _ruleName,
          '$symbol: 過濾（未確認空頭趨勢 close=$close, MA20=$ma20, MA60=$ma60）',
        );
        return true;
      }
    }
    return false;
  }
}
```

- [ ] **Step 4: 所有 `StockData` 建構點決定股利情境，移除舊欄位**

`lib/domain/services/scoring_isolate.dart`：
1. `ScoringIsolateInput`：刪除 `this.dividendHistoryMap,`、`dividendHistoryMap` 欄位與它的註解。
2. `StockData(`：刪除 `dividendHistory: batchData.dividendHistory,`，在 `prices: prices,` 之後加：

```dart
      // 找不到情境＝不完整：寧可 52 週不觸發，也不拿原始價格判斷
      dividends:
          input.dividendContexts[symbol] ?? const DividendContext.incomplete(),
```

3. `_convertBatchData`：
   - 回傳 record 型別刪除 `List<DividendHistoryEntry>? dividendHistory,`。
   - 函式本體刪除 `final dividendHistory = ...;` 與 `dividendHistory: ...` 兩處。
   - doc 的「（法人、新聞、營收、估值、EPS、ROE、股利）」改成「（法人、新聞、營收、估值、EPS、ROE）」。
4. 檔頭附近 `evaluateStocksInIsolate` 註解裡的「九個元素型別各放一顆真實例」改成「各元素型別各放一顆真實例」。

`lib/domain/services/scoring_service.dart`：
1. `scoreStocks` 的 `StockData(`：刪除 `dividendHistory: batchData.dividendHistoryMap?[symbol],`，在 `prices: prices,` 之後加：

```dart
        // 找不到情境＝不完整：寧可 52 週不觸發，也不拿原始價格判斷
        dividends:
            batchData.dividendContexts[symbol] ??
            const DividendContext.incomplete(),
```

2. `scoreStocksInIsolate` 的 `ScoringIsolateInput(`：刪除 `dividendHistoryMap: batchData.dividendHistoryMap,`。

`lib/domain/models/scoring_batch_data.dart`：
1. 刪除未具名建構子的 `Map<String, List<DividendHistoryEntry>>? dividendHistoryMap,` 參數、`FinancialHealthGroup(` 裡的 `dividendHistoryMap: dividendHistoryMap,`，以及 `dividendHistoryMap` getter 與它的註解。
2. class doc 的「[financialHealth] 財務健康（EPS + ROE + 股利）」與欄位 doc 的「財務健康（EPS + ROE + 股利）資料」，都改成「（EPS + ROE）」。

`lib/domain/models/scoring_data_groups.dart`（`FinancialHealthGroup`）：
1. 刪除 `this.dividendHistoryMap,` 與欄位、註解。
2. class doc 改成：

```dart
/// 財務健康（EPS + ROE）資料群組
///
/// 包含近 8 季 EPS/ROE 趨勢，用於評估公司長期獲利能力。
```

`lib/domain/services/update/batch_data_loader.dart`：
1. 刪除 `dividendFuture`。
2. 第三組 `.wait` 刪除 `dividendHistoryMap`／`dividendFuture`，變成 8 個。
3. `FinancialHealthGroup(` 刪除 `dividendHistoryMap: dividendHistoryMap,`。

`tool/replay_calibrator.dart`（`_buildStockData`）：
1. `return StockData(` 在 `prices: pricesUpToDay,` 之後加：

```dart
      // 校準 DB 沒有除權除息配發資料：52 週新高／新低在回放中不觸發（見
      // CalibrationThresholds.notBackfillableReasons）
      dividends: const DividendContext.incomplete(),
```

2. 結尾註解 `// news / dividendHistory — not backfilled, leave null` 改成 `// news — not backfilled, leave null`。
3. 方法 doc 的「非 backfillable 的欄位（dividendHistory / news）傳 null，讓對應 rules 自然 no-fire。」改成「非 backfillable 的 news 傳 null、股利情境傳 incomplete，讓對應 rules 自然 no-fire。」
4. 若 import 區沒有 `domain/models/models.dart`，加 `import 'package:daredevil/domain/models/dividend_context.dart';`。

`lib/core/constants/calibration_thresholds.dart`（`notBackfillableReasons`）：
1. 在 `'NEWS_RELATED',` 之後加：

```dart
    // 除權除息配發（52 週新高／新低以還原價判斷；回補管線沒有配發資料，
    // ReplayCalibrator 傳 DividendContext.incomplete，兩條規則在回放中不觸發）
    'WEEK_52_HIGH',
    'WEEK_52_LOW',
```

2. 常數 doc 的「`ReplayCalibrator` 對應的 context 欄位一律傳 null」改成「`ReplayCalibrator` 對應的 context 欄位一律傳 null（股利情境傳 incomplete）」。

`test/tools/scoring_snapshot.dart`：
1. import 區加：

```dart
import 'package:daredevil/domain/models/dividend_context.dart';
import 'package:daredevil/domain/services/dividend_completeness.dart';
```

2. 把 `final dividendHistoryMap = await db.getDividendHistoryBatch(symbols);` 換成：

```dart
    // 52 週規則的股利情境：與 production（BatchDataLoader）同一個 builder
    final dividendContexts = BatchDataBuilder.buildDividendContexts(
      pricesMap: pricesMap,
      completeness: await loadDividendCompleteness(db, now: date),
      events: await db.getDividendEventsBatch(symbols, from: start, to: date),
      date: date,
    );
```

3. `ScoringBatchData(`：刪除 `dividendHistoryMap: dividendHistoryMap,`，並把 Task 3 補的 `dividendContexts: {}` 換成 `dividendContexts: dividendContexts`。
4. `StockData(`：刪除 `dividendHistory: ...`，在 `prices: prices,` 之後加 `dividends: batch.dividendContexts[symbol] ?? const DividendContext.incomplete(),`。

測試裡已不再被呼叫的 stub 一併刪除：
- `test/domain/services/update/batch_data_loader_test.dart` 的 `when(() => db.getDividendHistoryBatch(any()))...;`
- `test/domain/services/update_service_test.dart` 的 `mockDb.getDividendHistoryBatch` 那段 `when(...)`
- `scoring_watchlist_zero_reason_test.dart` sendability 輸入裡的 `dividendHistoryMap: const {...}` 整段

另外，`scoring_watchlist_zero_reason_test.dart` sendability 測試的註解「這裡的九個元素型別正是本次刪掉手寫 mapper 的那批」改成：「元素型別是本次刪掉手寫 mapper 的那批，加上 2026-10 的 `DividendContext`（complete 帶 `DividendPriceEvent`、incomplete 各一）」。

- [ ] **Step 5: 其餘 `StockData(` 補參數**

1. `test/helpers/stock_data_builders.dart`：
   - `createTestStockData` 加參數 `DividendContext dividends = DividendContext.noEvents,`。
   - `StockData(` 在 `prices:` 之後加 `dividends: dividends,`。
   - import 區加 `import 'package:daredevil/domain/models/dividend_context.dart';`。
2. 執行腳本。已手寫 `dividends:` 的呼叫會被略過：

Run: `python3 <scratchpad>/add_arg.py 'StockData\(' 'StockData' 'dividends: DividendContext.noEvents'`
Expected: 逐檔印出補了幾處，最後是 `total N`

3. 用到 `DividendContext` 但沒有 import `domain/models/models.dart` 的檔，補直接 import（不重複 import barrel，避免 `unnecessary_import`）：

```python
import pathlib, subprocess
for f in subprocess.run(['grep', '-rl', '--include=*.dart', 'DividendContext', 'test'],
                        capture_output=True, text=True).stdout.split():
    p = pathlib.Path(f)
    s = p.read_text()
    if "domain/models/models.dart'" in s or "domain/models/dividend_context.dart'" in s:
        continue
    lines = s.split('\n')
    last = max(i for i, l in enumerate(lines) if l.startswith("import 'package:daredevil/"))
    lines.insert(last + 1, "import 'package:daredevil/domain/models/dividend_context.dart';")
    p.write_text('\n'.join(lines))
    print('import added:', f)
```

Run: `dart format lib test tool`
Run: `flutter analyze`
Expected: `No issues found!`。缺 `dividends` 的呼叫會是編譯錯誤，analyze 會列出來，逐一補上。

- [ ] **Step 6: 確認通過**

Run: `flutter test test/domain/services/rules/ test/domain/services/ test/tool/ test/app/`
Expected: 全部 PASS。

若 52 週以外的既有測試失敗：
1. 先確認失敗的原因，是不是新的斷點閘門或均線過濾在該測試資料上改變了 52 週結果。
2. 若是，而且新行為符合 spec §5，就改測試的期望值，並在測試註解寫明原因。
3. 若不是，就是改壞了，回頭查。

Run: `dart compile kernel tool/daily_update.dart -o build/daily_update.dill`
Expected: 編譯成功

- [ ] **Step 7: 記錄進度**（不 commit）

---

### Task 5: 兩條評分路徑一致、每輪 52 週觀測

**Files:**
- Modify: `lib/domain/services/scoring_isolate.dart`（`ScoringBatchResult`、計數）
- Modify: `lib/domain/services/scoring_service.dart`（回退路徑計數、兩條路徑的日誌）
- Test: `test/domain/services/scoring_week52_paths_test.dart`（新檔）

**Interfaces:**
- Consumes: Task 4 的 `week52AdjustedPrices`、`Week52Block`
- Produces: `ScoringBatchResult.week52Incomplete`、`ScoringBatchResult.week52Discontinuity`（`int`，預設 0，不屬於略過帳目）；兩條路徑各記一行日誌：`52 週：完整度不足 N 檔、斷點 M 檔`

- [ ] **Step 1: 寫失敗測試**

`test/domain/services/scoring_week52_paths_test.dart`：

```dart
// 52 週規則在兩條評分路徑（isolate、主執行緒回退）結果一致，且各自記錄
// 每輪觀測（完整度不足、斷點）
//
// 同一份 ScoringBatchData 分別走 scoreStocksInIsolate（真的開 isolate，含
// batch data → isolate 輸入的轉交）與 scoreStocks（回退），比對落庫的
// reasons。資料刻意設計成「原始價格不觸發、還原後才觸發」：任一條路徑沒把
// 股利情境帶進 StockData，都會少一筆 WEEK_52_HIGH。
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/domain/models/dividend_context.dart';
import 'package:daredevil/domain/models/scoring_batch_data.dart';
import 'package:daredevil/domain/repositories/analysis_repository.dart';
import 'package:daredevil/domain/services/analysis_service.dart';
import 'package:daredevil/domain/services/rule_engine.dart';
import 'package:daredevil/domain/services/scoring_isolate.dart';
import 'package:daredevil/domain/services/scoring_service.dart';

import '../../helpers/price_data_generators.dart';

/// 記錄每檔落庫的 reason 代碼（只記非空的清單）
class _RecordingRepo extends Mock implements IAnalysisRepository {
  final reasons = <String, List<String>>{};

  @override
  Future<T> runInTransaction<T>(Future<T> Function() action) => action();

  @override
  Future<int> clearReasonsForDate(DateTime date) async => 0;

  @override
  Future<int> clearAnalysisForDate(DateTime date) async => 0;

  @override
  Future<void> saveReasons(
    String symbol,
    DateTime date,
    List<ReasonData> list,
  ) async {
    if (list.isNotEmpty) reasons[symbol] = [for (final r in list) r.type]..sort();
  }

  @override
  Future<void> saveAnalysis({
    required String symbol,
    required DateTime date,
    required String trendState,
    required String reversalState,
    double? supportLevel,
    double? resistanceLevel,
    required double scoreShort,
    required double scoreLong,
  }) async {}
}

/// 從 2025-01-01 起逐日一根、每根 200 萬股（過得了單檔流動性門檻）
List<DailyPriceEntry> _daily(String symbol, List<double> closes) => [
  for (var i = 0; i < closes.length; i++)
    createTestPrice(
      symbol: symbol,
      date: DateTime(2025, 1, 1).add(Duration(days: i)),
      close: closes[i],
      volume: 2000000,
    ),
];

List<double> _flat(int n, double value) => List.filled(n, value);

/// 原始價格不觸發、還原後創新高（見 indicator_rules_test 的同名資料）
List<double> _adjustOnlyHighCloses() =>
    [..._flat(200, 100), ..._flat(59, 95), 99.0]
      ..[50] = 104
      ..[230] = 97;

Future<List<String>> _capturePrints(Future<void> Function() body) async {
  final lines = <String>[];
  await runZoned(
    body,
    zoneSpecification: ZoneSpecification(
      print: (self, parent, zone, line) => lines.add(line),
    ),
  );
  return lines;
}

void main() {
  // 第 259 根（今天）的日期：候選資格要求最後一根就是評分日
  final date = DateTime(2025, 9, 17);
  const symbols = ['ADJ', 'INC', 'NOMAP', 'GAP'];

  final pricesMap = {
    'ADJ': _daily('ADJ', _adjustOnlyHighCloses()),
    'INC': _daily('INC', _adjustOnlyHighCloses()),
    'NOMAP': _daily('NOMAP', _adjustOnlyHighCloses()),
    // 第 200 根起從 50 跳到 100（不在除權除息列表）：還原後仍有斷點
    'GAP': _daily('GAP', [..._flat(200, 50), ..._flat(59, 100), 101.5]),
  };
  final contexts = <String, DividendContext>{
    'ADJ': DividendContext.complete([
      DividendPriceEvent(
        exDate: DateTime(2025, 1, 1).add(const Duration(days: 200)),
        closeBefore: 100,
        referencePrice: 90,
      ),
    ]),
    'INC': const DividendContext.incomplete(),
    'GAP': DividendContext.noEvents,
    // NOMAP 刻意不放：找不到情境要視為不完整
  };

  ScoringBatchData batch() => ScoringBatchData(
    pricesMap: pricesMap,
    newsMap: const {},
    institutionalMap: const {},
    dividendContexts: contexts,
  );

  ScoringService service(_RecordingRepo repo) => ScoringService(
    analysisService: AnalysisService(),
    ruleEngine: RuleEngine(),
    analysisRepository: repo,
  );

  test('🚨 兩條路徑落庫的 reasons 相同；還原後才觸發的那檔兩邊都有 WEEK_52_HIGH', () async {
    final viaIsolate = _RecordingRepo();
    final viaFallback = _RecordingRepo();

    await service(viaIsolate).scoreStocksInIsolate(
      candidates: symbols,
      date: date,
      batchData: batch(),
      watchlistSymbols: symbols,
    );
    await service(viaFallback).scoreStocks(
      candidates: symbols,
      date: date,
      batchData: batch(),
      watchlistSymbols: symbols,
    );

    expect(viaIsolate.reasons, viaFallback.reasons);
    expect(viaIsolate.reasons['ADJ'], contains('WEEK_52_HIGH'));
    for (final s in ['INC', 'NOMAP', 'GAP']) {
      expect(
        viaIsolate.reasons[s] ?? const <String>[],
        isNot(contains('WEEK_52_HIGH')),
        reason: s,
      );
    }
  });

  test('🚨 isolate 結果帶 52 週觀測：完整度不足 2 檔（含找不到情境的）、斷點 1 檔；帳目仍平', () {
    final result = evaluateStocksIsolated(
      ScoringIsolateInput(
        candidates: symbols,
        pricesMap: pricesMap,
        newsMap: const {},
        institutionalMap: const {},
        dividendContexts: contexts,
        date: date,
      ),
    );

    expect((result.week52Incomplete, result.week52Discontinuity), (2, 1));
    expect(result.accountingBalances, isTrue);
  });

  for (final (name, run) in [
    (
      'isolate',
      (ScoringService s) =>
          s.scoreStocksInIsolate(candidates: symbols, date: date, batchData: batch()),
    ),
    (
      '主執行緒回退',
      (ScoringService s) =>
          s.scoreStocks(candidates: symbols, date: date, batchData: batch()),
    ),
  ]) {
    test('🚨 $name 路徑每輪記一行 52 週觀測', () async {
      final lines = await _capturePrints(() => run(service(_RecordingRepo())));

      expect(
        lines.where((l) => l.contains('52 週：完整度不足 2 檔、斷點 1 檔')),
        hasLength(1),
      );
    });
  }
}
```

- [ ] **Step 2: 確認失敗**

Run: `flutter test test/domain/services/scoring_week52_paths_test.dart`
Expected:
- 第一條：PASS。路徑一致已由 Task 4 完成，這條是迴歸防線；它對拔掉任一條路徑情境的突變是否有效，在 Task 8 的 mutation 驗證。
- 其餘：FAIL。`week52Incomplete` 未定義，日誌也找不到那一行。

- [ ] **Step 3: 實作**

`lib/domain/services/scoring_isolate.dart`：
1. import 區加 `import 'package:daredevil/domain/services/rules/indicator_rules.dart';`。
2. `ScoringBatchResult` 建構子在 `required this.skippedLowScore,` 之後加：

```dart
    this.week52Incomplete = 0,
    this.week52Discontinuity = 0,
```

3. 欄位（`skippedLowScore` 之後）：

```dart
  /// 52 週規則因股利資料不完整而不評估的檔數。觀測用、不屬於略過帳目（這些
  /// 股票照常評其他規則）；本月同步沒跑成的那一輪會接近評分檔數
  final int week52Incomplete;

  /// 52 週規則因還原後仍有水位斷點（減資、分割等）而不評估的檔數（觀測用）
  final int week52Discontinuity;
```

4. `evaluateStocksIsolated`：在 `var skippedLowScore = 0;` 之後加：

```dart
  var week52Incomplete = 0;
  var week52Discontinuity = 0;
```

5. 在 `final reasons = ruleEngine.evaluateStock(context, stockData);` 之前加：

```dart
    // 52 週觀測：與規則共用同一個判斷（week52AdjustedPrices）
    final week52Block = week52AdjustedPrices(stockData).block;
    if (week52Block == Week52Block.incomplete) week52Incomplete++;
    if (week52Block == Week52Block.discontinuity) week52Discontinuity++;
```

6. 結尾的 `return ScoringBatchResult(` 在 `skippedLowScore: skippedLowScore,` 之後加：

```dart
    week52Incomplete: week52Incomplete,
    week52Discontinuity: week52Discontinuity,
```

`lib/domain/services/scoring_service.dart`：
1. import 區加 `import 'package:daredevil/domain/services/rules/indicator_rules.dart';`。
2. `scoreStocks`：在 `var skippedLowScore = 0;` 之後加：

```dart
    var week52Incomplete = 0;
    var week52Discontinuity = 0;
```

3. 在 `final reasons = _ruleEngine.evaluateStock(context, stockData);` 之前加：

```dart
      // 52 週觀測：與 isolate 路徑逐字對應
      final week52Block = week52AdjustedPrices(stockData).block;
      if (week52Block == Week52Block.incomplete) week52Incomplete++;
      if (week52Block == Week52Block.discontinuity) week52Discontinuity++;
```

4. `_logScoringResults(` 呼叫在 `candidateCount: candidates.length,` 之後加：

```dart
      week52Incomplete: week52Incomplete,
      week52Discontinuity: week52Discontinuity,
```

5. `_logScoringResults` 簽名在 `required int candidateCount,` 之後加：

```dart
    required int week52Incomplete,
    required int week52Discontinuity,
```

6. 在 `_logScoringResults` 的「評分完成」那個 `AppLogger.info(...)` 之後加：

```dart
    // 52 週停發不能靜默：每輪都記，0 也記
    AppLogger.info(
      'ScoringService',
      '52 週：完整度不足 $week52Incomplete 檔、斷點 $week52Discontinuity 檔',
    );
```

7. 在 `_logScoringResultsFromIsolate` 的「評分完成」那個 `AppLogger.info(...)` 之後加：

```dart
    // 52 週停發不能靜默：每輪都記，0 也記（與主執行緒路徑同一行）
    AppLogger.info(
      'ScoringService',
      '52 週：完整度不足 ${result.week52Incomplete} 檔、'
          '斷點 ${result.week52Discontinuity} 檔',
    );
```

- [ ] **Step 4: 確認通過**

Run: `flutter test test/domain/services/scoring_week52_paths_test.dart test/domain/services/scoring_isolate_accounting_test.dart test/domain/services/scoring_service_test.dart test/domain/services/scoring_watchlist_zero_reason_test.dart`
Expected: 全部 PASS

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 5: 記錄進度**（不 commit）

---

### Task 6: 文件與註解

**Files:**
- Modify: `lib/domain/services/price_continuity.dart`
- Modify: `lib/domain/services/analysis/analysis_coordinator_service.dart`
- Modify: `docs/RULE_ENGINE.md`
- Modify: `.claude/rules/update-pipeline.md`
- Modify: `tool/backfill.dart`

- [ ] **Step 1: 先找讀這些文件的測試**

Run: `grep -rln "RULE_ENGINE.md\|update-pipeline.md\|price_continuity.dart\|analysis_coordinator_service.dart\|tool/backfill.dart" test`
Expected: 列出的測試檔在 Step 3 一起跑

- [ ] **Step 2: 改寫**

`lib/domain/services/price_continuity.dart`，把：

```dart
/// 最後一項是決定性的：52 週規則**本來就正確處理除息**
/// （`_sumDividendsInPeriod` 把窗內現金股利從極值扣掉，見 evidence 的
/// `adjustedHigh`/`dividendAdjustment`）——入口截斷等於用一個粗糙的工具
/// 破壞一條已經解好的規則。
```

改成：

```dart
/// 最後一項是決定性的：52 週規則自己處理除權息——以交易所除權息參考價還原
/// 整段價格後取極值（`DividendAdjuster`，2026-10 起），只在還原後仍有水位
/// 斷點（減資、分割等）時不觸發。入口截斷會讓它在上述 142 檔永不觸發。
```

`lib/domain/services/analysis/analysis_coordinator_service.dart`，把：

```dart
  /// `daily_analysis` 列都不寫）。而 52 週規則**本來就正確處理除息**
  /// （`_sumDividendsInPeriod` 把窗內現金股利從極值扣掉，見 evidence 的
  /// `adjustedHigh`/`dividendAdjustment`）——入口截斷等於破壞一條已經解好的
  /// 規則。放在這裡則外層閘門（[_minIndicatorDataPoints]）仍看完整歷史，
```

改成：

```dart
  /// `daily_analysis` 列都不寫）。而 52 週規則自己以交易所除權息參考價還原
  /// 整段價格（`DividendAdjuster`，2026-10 起），需要完整歷史——入口截斷會讓
  /// 它永不觸發。放在這裡則外層閘門（[_minIndicatorDataPoints]）仍看完整歷史，
```

`docs/RULE_ENGINE.md`，兩列改成：

```markdown
| WEEK_52_HIGH           | +28 | 距 52 週新高 **1% 內**——「接近新高」也會觸發。極值以交易所除權息參考價還原後計算；股利資料不完整或還原後仍有水位斷點（減資、分割）時不觸發 |
| WEEK_52_LOW            |  +8 | 距 52 週新低 **3% 內** **且** close < MA20 < MA60（空方確認，均線用還原後收盤）；不觸發條件同上 |
```

`.claude/rules/update-pipeline.md`：
1. 在「**完整度事實**」那一點的結尾（「…有效列表日把完成紀錄算成列到月底」之後）接上：

```markdown
。評分的 52 週規則也讀這些事實（`BatchDataLoader` 以
  `BatchDataBuilder.buildDividendContexts` 替每檔建股利情境）：本月同步沒把列表日推進到
  資料日的那一輪，52 週對所有股票都不觸發（評分日誌「52 週：完整度不足 N 檔」），下一輪補回
```

2. Helpers 表的 `BatchDataBuilder` 列改成「建構外資／董監等評分資料 Map，含衍生欄位；52 週的股利情境」。

`tool/backfill.dart`，把：

```dart
// `dividend_history` 暫不 backfill — 它只用於 52 週新高/新低的股息
// 調整，非 calibration 的必要輸入。
```

改成：

```dart
// 除權除息不 backfill：52 週新高／新低改用配發表的除權息參考價還原
// （2026-10 起）後，回放傳 `DividendContext.incomplete`，這兩條規則在
// 回放中不觸發（見 `CalibrationThresholds.notBackfillableReasons`）。
```

- [ ] **Step 3: 驗證**

逐句回讀每段新文字對應的實作（`week52AdjustedPrices`、`buildDividendContexts`、`ReplayCalibrator`），確認沒有超出程式碼的宣稱。

Run: `flutter test <Step 1 列出的測試檔>`；`flutter analyze`
Expected: PASS／`No issues found!`

- [ ] **Step 4: 記錄進度**（不 commit）

---

### Task 7: 量測工具：52 週新舊對照回放

**Files:**
- Modify: `test/tools/scoring_snapshot.dart`

這支是量測腳本，不進全套測試，所以本身不寫測試。正確性靠兩件事：
- **自我對帳**：落庫的 WEEK_52_*（`daily_reason`）都應能由舊版重現。
- **Step 3 的試跑**。

- [ ] **Step 1: 加入回放**

1. import 區加：

```dart
import 'package:daredevil/core/utils/date_context.dart';
import 'package:daredevil/domain/services/rules/indicator_rules.dart';
```

2. `main()` 內，既有 `test('產生評分快照', ...)` 之後加：

```dart
  // ── 52 週新舊對照回放（3-2 提交前的量測，spec「驗證」3-2）─────────────
  //
  //   WEEK52_REPLAY=1 SNAPSHOT_DB=<副本> WEEK52_OUT=<輸出.json> \
  //     flutter test test/tools/scoring_snapshot.dart --plain-name '52 週新舊對照回放'
  //
  // 逐日回放最近 WEEK52_DAYS（預設 62）個交易日；母體＝當日通過候選分類
  // （classifyCandidate）的全部在市股票，不只 daily_analysis 內者。只跑新舊
  // 兩版 52 週規則：
  // - 舊版＝3-2 之前的實作（_legacyWeek52，凍結副本）
  // - 新版＝現行規則，股利情境與 production 同一個判斷（priceContext）；事件
  //   只取除權息日 ≤ 當日。完整度用的是副本當下的事實（現況），不是當時的
  // 回放終點＝兩市場連續列過的最後一天（DividendCompleteness.displayEnd）：
  // 之後的日子新版一律判不完整，比了沒有意義。
  // 自我檢查：落庫的 WEEK_52_*（daily_reason）都應由舊版重現。
  test(
    '52 週新舊對照回放',
    () async {
      final dbPath = Platform.environment['SNAPSHOT_DB'] ?? _defaultDb;
      final outPath =
          Platform.environment['WEEK52_OUT'] ?? '/tmp/week52_replay.json';
      final dayCount =
          int.tryParse(Platform.environment['WEEK52_DAYS'] ?? '') ?? 62;
      // ⚠️ 開 DB 會跑 beforeOpen：只能對副本跑
      final db = AppDatabase(NativeDatabase(File(dbPath)));

      final latestRow = await db
          .customSelect('SELECT MAX(date) d FROM daily_price')
          .getSingle();
      final latest = DateTime.parse(
        latestRow.read<String>('d').substring(0, 10),
      );
      final completeness = await loadDividendCompleteness(db, now: latest);
      final end = completeness.displayEnd;
      if (end == null) fail('任一市場連回補起點的月份都沒列過，無從量測');

      String ymd(DateTime d) => d.toIso8601String().substring(0, 10);
      final days =
          [
                for (final r in await db
                    .customSelect(
                      'SELECT DISTINCT substr(date, 1, 10) d FROM daily_price '
                      'ORDER BY d DESC',
                    )
                    .get())
                  DateContext.normalize(DateTime.parse(r.read<String>('d'))),
              ]
              .where((d) => !d.isAfter(end))
              .take(dayCount)
              .toList()
            ..sort();

      const window = Duration(days: RuleParams.historyRequiredDays);
      final symbols = [
        for (final s in await db.getAllActiveStocks()) s.symbol,
      ]..sort();
      final watchlist = {for (final w in await db.getWatchlist()) w.symbol};
      final pricesAll = await db.getPriceHistoryBatch(
        symbols,
        startDate: days.first.subtract(window),
        endDate: days.last,
      );
      final eventsAll = await db.getDividendEventsBatch(
        symbols,
        from: days.first.subtract(window),
        to: days.last,
      );
      final legacyDividends = await db.getDividendHistoryBatch(symbols);
      final persisted = <String, Set<String>>{};
      for (final r in await db
          .customSelect(
            'SELECT symbol, substr(date, 1, 10) d, reason_type t '
            'FROM daily_reason '
            "WHERE reason_type IN ('WEEK_52_HIGH', 'WEEK_52_LOW')",
          )
          .get()) {
        persisted
            .putIfAbsent(
              '${r.read<String>('d')} ${r.read<String>('symbol')}',
              () => {},
            )
            .add(r.read<String>('t'));
      }

      final analysis = AnalysisService();
      final rules = <(String, StockRule, bool)>[
        ('WEEK_52_HIGH', const Week52HighRule(), true),
        ('WEEK_52_LOW', const Week52LowRule(), false),
      ];
      final counts = {
        for (final (type, _, _) in rules)
          type: {
            'old': 0,
            'new': 0,
            'disappeared': 0,
            'added': 0,
            'persisted': 0,
            'persistedReproduced': 0,
            'persistedDisappeared': 0,
          },
      };
      void bump(String type, String key) =>
          counts[type]![key] = counts[type]![key]! + 1;
      final examples = <String, List<Map<String, Object?>>>{};
      final unreproduced = <String>[];
      final perDay = <Map<String, Object?>>[];

      for (final day in days) {
        final from = day.subtract(window);
        var evaluated = 0;
        var incomplete = 0;
        var discontinuity = 0;
        for (final symbol in symbols) {
          final prices = [
            for (final p in pricesAll[symbol] ?? const <DailyPriceEntry>[])
              if (!p.date.isBefore(from) && !p.date.isAfter(day)) p,
          ];
          if (classifyCandidate(
                prices,
                asOf: day,
                exemptFromLiquidity: watchlist.contains(symbol),
              ) !=
              null) {
            continue;
          }
          final result = analysis.analyzeStock(prices);
          if (result == null) continue;
          evaluated++;
          final context = analysis.buildContext(
            result,
            priceHistory: prices,
            evaluationTime: day,
          );
          final data = StockData(
            symbol: symbol,
            prices: prices,
            dividends: completeness.priceContext(
              symbol,
              from: prices.first.date,
              asOf: day,
              rows: eventsAll[symbol] ?? const [],
            ),
          );
          final block = week52AdjustedPrices(data).block;
          if (block == Week52Block.incomplete) incomplete++;
          if (block == Week52Block.discontinuity) discontinuity++;

          for (final (type, rule, isHigh) in rules) {
            final before = _legacyWeek52(
              context,
              prices,
              legacyDividends[symbol],
              isHigh: isHigh,
            );
            final after = rule.evaluate(context, data);
            if (before != null) bump(type, 'old');
            if (after != null) bump(type, 'new');
            final wasPersisted =
                persisted['${ymd(day)} $symbol']?.contains(type) ?? false;
            if (wasPersisted) {
              bump(type, 'persisted');
              if (before != null) {
                bump(type, 'persistedReproduced');
              } else {
                unreproduced.add('${ymd(day)} $symbol $type');
              }
              if (before != null && after == null) {
                bump(type, 'persistedDisappeared');
              }
            }
            if ((before == null) == (after == null)) continue;
            final kind = before != null ? 'disappeared' : 'added';
            bump(type, kind);
            (examples['$type $kind'] ??= []).add({
              'day': ymd(day),
              'symbol': symbol,
              'persisted': wasPersisted,
              'close': prices.last.close,
              'old': before == null
                  ? null
                  : {
                      'extreme': before.extreme,
                      'adjusted': before.adjusted,
                      'isNew': before.isNew,
                    },
              'new': after?.evidence,
              'block': block?.name,
              'events': [
                if (data.dividends case DividendComplete(:final events))
                  for (final e in events)
                    '${ymd(e.exDate)} ×${e.factor.toStringAsFixed(4)}',
              ],
            });
          }
        }
        perDay.add({
          'day': ymd(day),
          'evaluated': evaluated,
          'incomplete': incomplete,
          'discontinuity': discontinuity,
        });
      }

      final report = {
        'range': '${ymd(days.first)}～${ymd(days.last)}',
        'days': days.length,
        'displayEnd': ymd(end),
        'note':
            '完整度用的是 DB 副本當下的事實（現況），不是當時的事實；'
            '舊版的股利扣除照 3-2 前的實作（含其前視）',
        'counts': counts,
        'unreproducedPersisted': unreproduced.take(30).toList(),
        'perDay': perDay,
        'examples': {
          for (final e in examples.entries) e.key: e.value.take(15).toList(),
        },
      };
      File(
        outPath,
      ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(report));
      // ignore: avoid_print
      print(
        'WEEK52 ${report['range']}（${days.length} 天，顯示終點 '
        '${report['displayEnd']}）→ $outPath',
      );
      for (final e in counts.entries) {
        // ignore: avoid_print
        print('${e.key} ${e.value}');
      }
      await db.close();
    },
    skip: Platform.environment['WEEK52_REPLAY'] == null
        ? '設 WEEK52_REPLAY=1 才跑（讀 DB 副本、數分鐘）'
        : false,
    timeout: const Timeout(Duration(minutes: 30)),
  );
```

3. 檔案最後（`main` 之外）加入舊版規則的凍結副本：

```dart
/// 3-2 之前的 52 週規則（凍結副本，只供量測對照，不得修改）：原始極值扣掉
/// dividend_history 的窗內現金股利；新低以 context.indicators 的均線過濾
({bool isNew, double extreme, double adjusted})? _legacyWeek52(
  AnalysisContext context,
  List<DailyPriceEntry> prices,
  List<DividendHistoryEntry>? dividends, {
  required bool isHigh,
}) {
  if (prices.length < IndicatorParams.week52Days) return null;
  final close = prices.last.close;
  if (close == null) return null;

  double extreme = isHigh ? 0 : double.infinity;
  var validCount = 0;
  for (var i = 0; i < prices.length - 1; i++) {
    final p = prices[i];
    final value = isHigh ? (p.high ?? p.close) : (p.low ?? p.close);
    if (value == null || value <= 0) continue;
    validCount++;
    if (isHigh ? value > extreme : value < extreme) extreme = value;
  }
  final invalid = isHigh
      ? extreme <= 0
      : (extreme == double.infinity || extreme <= 0);
  if (invalid || validCount < IndicatorParams.week52MinValidBars) return null;

  var totalDividend = 0.0;
  if (dividends != null && dividends.isNotEmpty) {
    final lookbackStart = prices.first.date;
    for (final div in dividends) {
      if (div.exDividendDate == null) continue;
      final exDate = DateTime.tryParse(div.exDividendDate!);
      if (exDate != null && exDate.isAfter(lookbackStart)) {
        totalDividend += div.cashDividend;
      }
    }
  }
  final adjusted = extreme - totalDividend;
  if (adjusted <= 0) return null;

  final threshold = isHigh
      ? IndicatorParams.week52HighThreshold
      : IndicatorParams.week52LowThreshold;
  final thresholdPrice = isHigh
      ? adjusted * (1 - threshold)
      : adjusted * (1 + threshold);
  if (isHigh ? close < thresholdPrice : close > thresholdPrice) return null;
  if (!isHigh) {
    final ma20 = context.indicators?.ma20;
    final ma60 = context.indicators?.ma60;
    if (ma20 != null && ma60 != null && (close >= ma20 || ma20 >= ma60)) {
      return null;
    }
  }
  return (
    isNew: isHigh ? close >= adjusted : close <= adjusted,
    extreme: extreme,
    adjusted: adjusted,
  );
}
```

Run: `dart format test/tools/scoring_snapshot.dart`；`flutter analyze`
Expected: `No issues found!`

- [ ] **Step 2: 確認舊版副本與 3-2 前的實作逐行一致**

Run: `git show HEAD:lib/domain/services/rules/indicator_rules.dart | sed -n '11,209p'`

把輸出與 `_legacyWeek52` 逐條對照，確認以下各點完全相同：
- 極值迴圈
- 有效根數門檻
- 股利扣除的篩選條件（`exDate.isAfter(lookbackStart)`、不看評分日）
- 門檻
- 新低的均線過濾

- [ ] **Step 3: 試跑**

1. 用唯讀方式從 live DB 做副本：
   - 有 -wal 檔時：`sqlite3 "file:<live>?mode=ro" "VACUUM INTO '<scratchpad>/week52_src.sqlite'"`。
   - 沒有 -wal 檔時：URI 加上 `&immutable=1`。
2. 跑 3 天：

```bash
WEEK52_REPLAY=1 WEEK52_DAYS=3 SNAPSHOT_DB=<scratchpad>/week52_src.sqlite \
  WEEK52_OUT=<scratchpad>/week52_trial.json \
  flutter test test/tools/scoring_snapshot.dart --plain-name '52 週新舊對照回放'
```

Expected:
- 印出 `WEEK52 …（3 天，顯示終點 …）`，以及兩行 counts。
- `persistedReproduced` 等於或接近 `persisted`。差距要逐筆看 `unreproducedPersisted`，查出原因（例如價格之後被定案重抓改過）後再進 Task 8。
- `perDay` 的 `incomplete` 遠小於 `evaluated`。若接近 `evaluated`，代表完整度或回放終點有問題。

- [ ] **Step 4: 記錄進度**（不 commit）

---

### Task 8: 全套驗證、mutation、審查、量測、經同意提交

- [ ] **Step 1: 靜態檢查與全套測試**（log 寫到 scratchpad）

```bash
dart format lib test tool
flutter analyze
flutter test > <scratchpad>/full_3_2.log 2>&1; tail -c 300 <scratchpad>/full_3_2.log
dart compile kernel tool/daily_update.dart -o build/daily_update.dill
dart compile kernel tool/backfill_dividend_distributions.dart -o build/backfill_dividend_distributions.dill
```

Expected: analyze 無 issue；全套通過；兩個 kernel 編譯成功

- [ ] **Step 2: mutation**

做法同 3-1：
- 在 scratchpad 建 repo 副本（`rsync -rl`）。
- 原始檔先備份，還原一律用備份檔。
- 每個 mutant 開跑前，先檢查必要檔案存在。
- 每個 mutant 都跑全部消費者測試：`test/domain/services test/data/database test/tool test/app`；timeout 300 秒；用 `python3 -u`。

至少涵蓋：

| 檔案 | mutant |
|:--|:--|
| dividend_adjuster | `asOf` 篩選拿掉；`day.isBefore(exDate)` 改成 `!day.isAfter(exDate)`；因子倒過來（前收盤 ÷ 參考價）；`applicable.isEmpty` 提早回傳拿掉；`if (next > 0)` 改成 `if (true)`；篩選處的 `DateContext.normalize(e.exDate)` 拿掉；`_scale` 不調 high |
| dividend_dao | `getDividendEventsBatch` 範圍條件拿掉；加上 `_isDistribution`（排除 0/0 列）；排序改成由新到舊 |
| dividend_completeness | `priceContext` 的 `requirePrices: true` 改成 false；`!exDate.isAfter(start)` 改成 `exDate.isBefore(start)`；`exDate.isAfter(end)` 拿掉；缺價或 ≤ 0 的檢查拿掉 |
| batch_data_builder | `from: prices.first.date` 改成 `from: date` |
| batch_data_loader | 傳空的 `dividendContexts` |
| scoring_isolate | `?? const DividendContext.incomplete()` 改成 `?? DividendContext.noEvents`；查表改成固定 incomplete；兩個計數器互換；計數器不加 |
| scoring_service | 回退路徑同上；`scoreStocksInIsolate` 傳 `{}`；兩條日誌各自拿掉 |
| indicator_rules | 閘門 incomplete 拿掉；閘門 discontinuity 拿掉；`asOf: data.prices.last.date` 改成 `DateTime(9999)`；判斷改用原始極值；evidence 原始與還原後互換；`dividendAdjustment` 正負號反過來；`additionalFilter(data.symbol, adjusted, close)` 改成傳 `data.prices` |
| replay_calibrator | incomplete 改成 noEvents |
| calibration_thresholds | 拿掉 WEEK_52 兩項 |

存活者逐一判斷：補測試，或證明等價並刪掉多餘的程式碼。

- [ ] **Step 3: 審查**

送 opus 審查（`pr-review-toolkit:code-reviewer`）：
- 範圍：`git diff` 加未追蹤新檔。
- 附本計畫與 spec 的路徑、Review Focus 五條、「與 spec 的差異」五條。
- 限制：不可 `dart run`、不可開背景任務、不可碰 scratchpad。

修正後，以 SendMessage 請同一位審查者複審，直到 Ready。

- [ ] **Step 4: 量測（完整 62 天）**

1. 從 live DB 重新做一份副本（唯讀，同 Task 7 Step 3），跑：

```bash
WEEK52_REPLAY=1 SNAPSHOT_DB=<scratchpad>/week52_src.sqlite \
  WEEK52_OUT=<scratchpad>/week52_replay.json \
  flutter test test/tools/scoring_snapshot.dart --plain-name '52 週新舊對照回放'
```

2. 整理給使用者的報告：
   - 回放範圍與顯示終點；註明完整度用的是現況。
   - 舊版與 `daily_reason` 的對帳率，以及無法重現的筆數與原因。
   - 兩條規則各自的：舊版觸發、新版觸發、消失、新增；落庫訊號中會消失的筆數。可與 spec 的粗估對照：近 55 個交易日，落庫的新低 461 筆中約 227 筆會消失，新高約新增 213 筆。
   - 閘門統計：每天的完整度不足、斷點檔數。
   - 消失與新增各舉 2～3 個實例：原始極值、還原後極值、當期事件。
3. **停下來等使用者同意**。不同意就依指示調整，再回到 Step 1。

- [ ] **Step 5: 經同意後提交**（使用者說「提交」才做）

Commit message 草稿：

```
feat: 52 週新高／新低改用除權息參考價還原後判斷

- DividendAdjuster：以交易所除權息參考價 ÷ 前收盤還原歷史價格（含現金股利、
  配股、現金增資），評分日之後的事件不套用
- 52 週規則以還原後極值判斷，新低的均線過濾改用還原後收盤；股利資料不完整或
  還原後仍有水位斷點（減資、分割）時不觸發，evidence 保留原始極值
- 評分批次由 BatchDataLoader 依完整度事實替每檔建股利情境，StockData.dividends
  必填，isolate 與主執行緒回退兩條路徑一致；每輪記一行「52 週：完整度不足 N 檔、
  斷點 M 檔」
- 校準回放沒有配發資料：股利情境傳 incomplete，52 週列入無法回補的規則
- 量測工具：scoring_snapshot 加 52 週新舊對照回放
```

- [ ] **Step 6: 提交後**

1. 確認 post-commit hook 已把 CLI 重編到新 commit（`~/Library/Logs/daredevil-cli-rebuild.log` 的最後一行、兩支 CLI 的 `BUILD_INFO`）。
2. 下一輪 launchd 日誌確認以下幾行：
   - build SHA
   - 步驟 6.6 的本月同步（列表日推進到資料日）
   - 評分的「52 週：完整度不足 N 檔、斷點 M 檔」：N 應遠小於評分檔數
3. 同一輪跑完後，唯讀查 live 的 `daily_reason`：WEEK_52_* 的 evidence 帶有 `adjustedHigh`／`adjustedLow`；抽幾檔原始極值落在除權息日之前的股票，確認 `dividendAdjustment` 不為 0（新高的極值在最後一次除權息之後時，原始與還原後是同一根，差為 0）。
