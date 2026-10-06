# 盤中即時報價第 1 段：基礎層 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 建好盤中即時報價的基礎：報價模型補上日期、價格來源、最後成交；client 能回報每批有沒有回應；排程、顯示合併規則、記帳本三個純邏輯元件；全 App 唯一的報價中心（登記、輪詢、節流、暫停、退避、限流、紀錄去重）；畫面登記元件與 App 可見性接線。這一段沒有任何畫面使用報價中心，使用者看不到變化。

**Architecture:**
- **資料層**：`IntradayQuote` 新增 `date`、`priceSource`、`lastTradePrice`、`lastTradeTime`，`price` 的取值規則不變。`IntradayQuoteClient` 新增 `fetchQuotesDetailed`（逐代號回報有回應或失敗）與 `logBatchErrors` 參數；`fetchQuotes` 對盤中提醒與 CLI 的行為不變。
- **domain（純 Dart）**：
  - `LiveQuoteSchedule`：交易階段、輪詢間隔、暫停門檻、退避、CLI 避讓、請求節流、收盤報價判斷，都是純函式。
  - `LiveQuoteMerge`：「畫面原本的資料是今天 > 今天的即時報價 > 原本的資料」。
  - `LiveQuoteBook`：把每一輪的結果套進來，算出顯示價、閃色、卡片狀態，並記錄收盤後逐檔的嘗試次數。
- **presentation**：
  - `LiveQuoteCenter`：Riverpod `Notifier`，每秒一拍，逐批送請求，受滑動窗口節流。
  - `LiveQuoteScope`：以 `TickerMode` 判斷畫面可見與否，據此登記或取消。
  - `AppLifecycleCoordinator`：新增 App 可見性回呼。

**Tech Stack:** Flutter／Dart 3.10、flutter_riverpod 3（解析到 riverpod 3.3.2）、go_router 17.1.0、Dio、fake_async、mocktail、flutter_test

**Spec:** `docs/plans/2026-10-05-intraday-live-quotes-design.md`（已提交 75f215fb）。

本計畫實作 spec 的以下各節：
- §1：本功能新增的欄位。鎖住解析已在 `e9a625ca` 完成。
- §2 排程、§3 報價中心、§4 畫面登記與可見性、§5 顯示合併規則。
- §8 斷線、限流與錯誤（紀錄部分）。
- 「驗證」的 1–5、7、8。

整個功能分三段：
1. 基礎層（本計畫）。
2. 自選清單與個股頁：閃色、頁首狀態、卡片標示、「價格閃色」開關、CHANGELOG、i18n。
3. 大盤與投資組合。

2026-10-06 先用拋棄式測試驗過三個前提，測試檔已刪：
- Dio 在 `fakeAsync` 下可用：adapter 內 `Future.delayed` 照假時間完成。
- go_router 切分頁、推入頂層 route 時，底下頁面的 `TickerMode.of` 變 false，返回後變回 true；開底部面板不變。
- 在 `didChangeDependencies` 呼叫 notifier 方法（不改 state）不會被 Riverpod 擋。

## Global Constraints

- **盤中提醒與 CLI 行為不變**：
  - `fetchQuotes` 的回傳、逐批 warning、逾時（連線 30 秒、讀取 60 秒）都不變。
  - `IntradayPollSchedule.isMarketHours` 含 13:30 那一分鐘，這點不變。
  - 既有測試只有一處改動：盤中提醒測試的 `quote()` helper 補 `priceSource`。其餘不改。
- **tool 鏈純 Dart**：
  - 以下檔案在 `tool/intraday_alert_check.dart` 與 `tool/daily_update.dart` 的閉包內，只能 import 純 Dart（`package:meta` 可以）：`intraday_quote.dart`、`intraday_quote_client.dart`、`market_client_mixin.dart`、`intraday_poll_schedule.dart`、新的 `market_session.dart`。
  - domain 的新檔（`live_quote_*`、`domain/models/live_quote.dart`）也只用純 Dart。
  - 守門測試：`test/tool/tool_chain_pure_dart_test.dart`。
- **常數集中**：
  - 開收盤時間只寫在 `MarketSession`。
  - 即時報價的參數只寫在 `LiveQuoteParams`，值照 spec 參數表。
  - 不在程式裡寫魔術數字。
- **報價中心不改 state 的入口**：`register`／`unregister`／`setAppVisible` 會在 widget 的 `didChangeDependencies`／`dispose`（build 期間）被呼叫，只能改內部欄位與計時器，不可寫 `state`。
- **不寫資料庫**：本段不碰 live DB。
- **公開 repo**：
  - 測試資料用既有 fixture 或合成列，不放使用者的自選或持股。
  - 合成列不冒用公司名稱（代號用 `p1`、`A` 這類，或沿用既有測試的 `2330`／`6538` 但不帶名稱）。
- **無使用者可見變化**：不寫 CHANGELOG、不加 i18n 字串。這兩項在第 2 段。
- **提交**：
  - commit／push 只在使用者說「提交」時做。直接在 main，Conventional Commits、中文、純文字、不加 Co-Authored-By。
  - 每個 task 結尾「記錄進度」，整段在 Task 8 一次提交。
  - **不在 09:00–13:30 提交**：post-commit hook 會在背景重編 launchd CLI。
- **測試行程**：跑 `flutter test` 前，先用 `ps -axo pid=,ppid=,etime=,comm= | grep -E '/(dart|flutter)$'` 確認沒有其他 `dart run`／`flutter test`／`flutter run`。`comm` 只有執行檔名、不含參數。IDEA 的 analysis server 從 ppid 與執行時間認出來，不算。
- **mutation**：
  - 在 scratchpad 的 repo 副本做，還原用備份檔，不用 git checkout。
  - 先跑直接測試，存活者再跑全部消費者測試。
  - 記錄每個 mutant 被哪個斷言殺掉；被編譯錯誤或沒 stub 的 mock 殺掉的不算。
- **審查者**：不可 `dart run`、不可開背景任務、不可碰 scratchpad、不改檔。

## Review Focus

1. **電腦睡眠喚醒、App 開著過夜**。
   - 情境：時鐘一次跳好幾小時，或跨日。
   - 預期：
     - 醒來後下一拍照常抓。
     - 跨日時，昨天的報價、記住的成交價、收盤後的嘗試次數全部清掉，不當成今天。
     - 過夜那段不計入暫停時間。
   - 測試在 Task 6：時鐘跳 2 小時、過夜跳到隔天 09:01。
2. **自選很多檔**。
   - 情境：3 批以上（> 70 檔），甚至超過 8 批（> 280 檔）。
   - 預期：
     - 任何 60 秒內最多 8 個請求，相鄰請求至少隔 2 秒。
     - 每一檔都輪得到。
   - 測試在 Task 6：3、4、10 批三種，跑 6 分鐘逐窗口檢查。
3. **MIS 很慢或卡住**。
   - 情境：回應要 5–8 秒，或讀取逾時。
   - 預期：
     - 請求還在路上時不發下一個，不疊加。
     - 報價中心用 5 秒連線、8 秒讀取的逾時；盤中提醒維持 30／60 秒。
   - 測試在 Task 6：回應延遲 29.5 秒的不疊加測試；provider 的 client 逾時與 `logBatchErrors` 設定。
4. **切分頁、推頁、關畫面時，在 build 期間登記或取消**。
   - 預期：
     - 不觸發 Riverpod「build 期間修改 provider」的錯誤。
     - 不漏取消。
     - 底部面板開著時，底下畫面維持登記。
   - 測試在 Task 7：以真的 go_router 搭配真的報價中心；時鐘固定在週六，不會發請求。
5. **收盤後畫面拿到今天的正式資料**。
   - 情境：App 一直開著，15:30 盤後資料寫入後，畫面以 `hasOfficialToday: true` 重新登記。
   - 預期：報價中心停止抓這一檔；同一檔若有其他畫面還沒有今天的正式資料，照抓。
   - 測試在 Task 6。

## 與 spec 的差異（核可計畫時一併確認）

1. **請求量上限改由滑動窗口節流保證**。
   - spec 原本的保證方式：批數 > 2 時間隔拉長為批數 × 7.5 秒。
   - 問題：這只保證平均值。同一輪內批與批相隔 2 秒，3 批、22.5 秒一輪時，請求落在 0／2／4、22.5／24.5／26.5、45／47／49 秒，從 0 秒起的 60 秒內有 9 個。
   - 本計畫：
     - 報價中心逐批送出，每次呼叫 `fetchQuotesDetailed` 只帶一批（≤ 35 檔，等於 1 個請求）。
     - 送出前檢查兩條：最近 60 秒內的請求少於 8 個、距上一個請求至少 2 秒。兩條都成立才送。
     - 輪詢間隔仍照 spec 的公式。
   - 連帶：client 不做批間等待，也不加 `batchGap` 參數。
2. **收盤後的暫停門檻**。spec 寫 max(60 秒, 2 × 輪詢間隔)。收盤後的輪詢間隔是每檔 1 分鐘，所以門檻是 120 秒；不這樣算的話，CLI 避讓讓某次間隔變成 69 秒時，頁首會誤顯示暫停。
3. **限流發生在一輪中途**：該輪已拿到的批次結果捨棄，整輪視為限流。
4. **「非預期錯誤」的範圍**。
   - `fetchQuotesDetailed` 的解析不包在 try 內：解析拋例外會往上拋給報價中心，記 `AppLogger.error`。
   - `fetchQuotes` 維持舊行為，解析例外仍算該批失敗。
   - 目前解析程式是防禦式寫法，沒有已知會拋例外的輸入。這條路徑用一個會拋 `StateError` 的 client 測。
5. **恢復也記 warning**：spec 規定斷線與限流只用 warning，恢復那筆同樣用 warning，訊息附連續失敗輪數。
6. **大盤指數的市場別在報價中心硬對應**：`t00` 一律 `tse_`、`o00` 一律 `otc_`，不論登記時帶什麼市場別。
7. **頁首與卡片需要的資料，這一段只產出、不顯示**。
   - 報價中心產出：`symbolStatus`、`stalled`、`rateLimitedUntil`、`lastRespondedAt`、`latestResponseHadToday`、`latestQuoteTime`。
   - 第 2 段在畫面端組合，例如「收盤後全部是收盤報價」與「取最舊的那筆時間」，這兩項都要知道哪些卡片在用即時報價。
8. **App 從隱藏回到可見後的第一輪不閃色**。spec 只寫「畫面剛恢復登記的第一輪不閃」，App 重新可見同理：拿來比較的是很久以前的價格。
9. **CLI 避讓窗全天套用**。CLI 只在 09:00–13:30 跑；收盤後照樣讓開，規則比較簡單，代價只是最多延後 10 秒。
10. **收盤後的逐檔抓取同樣受節流、CLI 避讓、退避約束**。
11. **跨日時暫停計時歸零**，而且過夜那段時間不計入。
12. **分工**。spec 寫 `LiveQuoteSchedule`「輸入各已登記股票的報價狀態，輸出抓哪些」。本計畫把它拆成三塊：
    - `LiveQuoteSchedule`：只放判斷函式。
    - `LiveQuoteBook`：記每一檔的收盤後狀態（`pendingAfterClose`、`dueAfterClose`）。
    - 報價中心：組合以上兩者。

## 檔案結構

| 檔案 | 責任 | 動作 |
|:--|:--|:--|
| `lib/data/models/twse/intraday_quote.dart` | MIS 報價模型 | 加 `QuotePriceSource`、`date`、`priceSource`、`lastTradePrice`、`lastTradeTime` |
| `lib/data/remote/market_client_mixin.dart` | 共用 Dio | `createDio` 可傳逾時 |
| `lib/data/remote/intraday_quote_client.dart` | MIS client | `QuoteBatchReport`、`fetchQuotesDetailed`、`logBatchErrors`、兩個 `@visibleForTesting` getter |
| `lib/core/constants/market_session.dart` | 開收盤時間 | 新增 |
| `lib/core/constants/live_quote_params.dart` | 即時報價參數 | 新增 |
| `lib/domain/services/alert/intraday_poll_schedule.dart` | 盤中提醒排程 | 改用 `MarketSession` |
| `lib/domain/services/live_quote/live_quote_schedule.dart` | 排程純函式 | 新增 |
| `lib/domain/models/live_quote.dart` | 即時報價顯示結果的型別 | 新增 |
| `lib/domain/services/live_quote/live_quote_merge.dart` | 顯示合併規則 | 新增 |
| `lib/domain/services/live_quote/live_quote_book.dart` | 每輪結果的記帳 | 新增 |
| `lib/presentation/providers/live_quote_provider.dart` | 報價中心與 client provider | 新增 |
| `lib/presentation/widgets/live_quote_scope.dart` | 畫面登記 | 新增 |
| `lib/app/app_lifecycle_coordinator.dart` | 生命週期副作用 | 加 `onAppVisibilityChanged` |
| `lib/main.dart` | 接線 | 把可見性接到報價中心 |

測試：
- 改：`test/data/remote/intraday_quote_parsing_test.dart`、`test/data/remote/intraday_quote_client_test.dart`、`test/domain/services/alert/intraday_alert_monitor_test.dart`（只改 helper）、`test/app/app_lifecycle_coordinator_test.dart`。
- 新：`test/domain/services/live_quote/live_quote_schedule_test.dart`、`live_quote_merge_test.dart`、`live_quote_book_test.dart`、`test/presentation/providers/live_quote_provider_test.dart`、`test/presentation/widgets/live_quote_scope_test.dart`。

---

### Task 1: 報價模型補日期、價格來源、最後成交

**Files:**
- Modify: `lib/data/models/twse/intraday_quote.dart`
- Modify: `test/domain/services/alert/intraday_alert_monitor_test.dart:52-60`（`quote()` helper）
- Test: `test/data/remote/intraday_quote_parsing_test.dart`

**Interfaces:**
- Consumes: 既有 `IntradayQuote.parseResponse`、`_num`、`_lockedPrice`、`_midOrSide`。
- Produces:
  - `enum QuotePriceSource { trade, locked, trial, book }`
  - `IntradayQuote` 新欄位：`final QuotePriceSource priceSource`（必填）、`final DateTime? date`、`final double? lastTradePrice`、`final String? lastTradeTime`。
  - `price` 的取值與舊版完全相同。

- [ ] **Step 1: 寫失敗測試**

在 `test/data/remote/intraday_quote_parsing_test.dart` 的 `main()` 最後（`group('漲跌停鎖住', ...)` 之後、最外層 `}` 之前）加：

```dart
  /// 盤中即時報價(2026-10-06):顯示需要報價日期、價格來源與最後一筆成交。
  /// `price` 的取值規則不變(盤中提醒沿用),新欄位只供顯示。
  group('報價日期、價格來源、最後成交', () {
    Map<String, dynamic> load(String name) =>
        jsonDecode(File('test/fixtures/$name').readAsStringSync())
            as Map<String, dynamic>;
    final noon = IntradayQuote.parseResponse(
      load('twse_mis_intraday_limit_locked_20261005.json'),
    );

    test('🚨 當輪無成交 → 價格照舊取五檔中價,另帶最後一筆成交(12:13 的 2330)', () {
      final q = noon['2330']!;
      expect(q.price, 2562.5, reason: 'price 規則不變(盤中提醒用它比價)');
      expect(q.priceSource, QuotePriceSource.book);
      expect(q.lastTradePrice, 2560.0);
      expect(q.lastTradeTime, '12:13:25');
      expect(q.date, DateTime(2026, 10, 5));
    });

    test('價格來源:成交、鎖住;指數列沒有 trade', () {
      expect(
        noon['1303']!.priceSource,
        QuotePriceSource.trade,
        reason: 'z=286(同時鎖漲停,鎖住標記另算)',
      );
      expect(noon['2059']!.priceSource, QuotePriceSource.locked);
      expect(noon['2059']!.lastTradePrice, 13355.0);
      expect(noon['2059']!.lastTradeTime, '11:43:31');
      expect(noon['t00']!.priceSource, QuotePriceSource.trade);
      expect(noon['t00']!.lastTradePrice, isNull);
      expect(noon['t00']!.lastTradeTime, isNull);
    });

    test('收盤後的回應(2026-08-07)沒有 trade → 最後成交為 null', () {
      final q = IntradayQuote.parseResponse(load('twse_mis_intraday.json'));
      for (final s in const ['2330', '3231', '6538']) {
        expect(q[s]!.lastTradePrice, isNull, reason: s);
        expect(q[s]!.lastTradeTime, isNull, reason: s);
        expect(q[s]!.date, DateTime(2026, 8, 7), reason: s);
        expect(q[s]!.priceSource, QuotePriceSource.trade, reason: s);
      }
    });

    test('只有試撮價 → trial;收盤集合競價首格 0、pz 為 - → 五檔,最後成交另帶', () {
      final q = IntradayQuote.parseResponse({
        'rtcode': '0000',
        'msgArray': [
          {
            'c': 'p1',
            'z': '-',
            'pz': '101.5000',
            'y': '100.0000',
            'd': '20261006',
            't': '13:26:05',
          },
          {
            'c': 'p2',
            'z': '-',
            'pz': '-',
            'y': '100.0000',
            'u': '110.0000',
            'w': '90.0000',
            'b': '0.0000_100.5000_',
            'a': '101.0000_',
            'd': '20261006',
            't': '13:27:05',
            'trade': {'t': '13:24:58', 'z': '100.5000'},
          },
        ],
      });
      expect(q['p1']!.priceSource, QuotePriceSource.trial);
      expect(q['p1']!.price, 101.5);
      expect(q['p2']!.priceSource, QuotePriceSource.book);
      expect(q['p2']!.price, 101.0, reason: '首格 0 視為缺值、只剩賣方(原規則)');
      expect(q['p2']!.lastTradePrice, 100.5);
      expect(q['p2']!.lastTradeTime, '13:24:58');
    });

    test('d 缺漏或格式不符 → date 為 null;trade.z 為 - 或 trade 不是物件 → 最後成交為 null', () {
      final q = IntradayQuote.parseResponse({
        'rtcode': '0000',
        'msgArray': [
          {'c': 'x1', 'z': '10', 'y': '10'},
          {
            'c': 'x2',
            'z': '10',
            'y': '10',
            'd': '2026105',
            'trade': {'t': '10:00:00', 'z': '-'},
          },
          {'c': 'x3', 'z': '10', 'y': '10', 'd': '20261306', 'trade': '10.0'},
        ],
      });
      for (final s in const ['x1', 'x2', 'x3']) {
        expect(q[s]!.date, isNull, reason: s);
        expect(q[s]!.lastTradePrice, isNull, reason: s);
        expect(q[s]!.lastTradeTime, isNull, reason: s);
      }
    });
  });
```

並把 `test/domain/services/alert/intraday_alert_monitor_test.dart` 的 `quote()` helper 改成：

```dart
  IntradayQuote quote(String s, double price, {double prev = 183.5}) =>
      IntradayQuote(
        symbol: s,
        name: '測試$s',
        price: price,
        previousClose: prev,
        priceSource: QuotePriceSource.trade,
        hasBid: true,
        hasAsk: true,
      );
```

- [ ] **Step 2: 確認紅燈**

Run: `flutter test test/data/remote/intraday_quote_parsing_test.dart test/domain/services/alert/intraday_alert_monitor_test.dart`
Expected: 兩個檔都編譯失敗（`QuotePriceSource` 未定義、`priceSource`／`lastTradePrice`／`date` 不是 `IntradayQuote` 的成員）

- [ ] **Step 3: 實作**

`lib/data/models/twse/intraday_quote.dart`：

1. 在類別註解（`/// 盤中即時報價(TWSE MIS ...`）之前加：

```dart
/// [IntradayQuote.price] 取自哪個欄位(盤中即時報價判斷顯示來源與收盤報價用)
enum QuotePriceSource {
  /// 當輪成交價 `z`
  trade,

  /// 漲跌停鎖住、當輪沒有成交:取漲跌停價(見 `_lockedPrice`)
  locked,

  /// 試撮價 `pz`
  trial,

  /// 最佳一檔買賣中價或單邊
  book,
}

```

2. 建構子在 `required this.previousClose,` 之後加 `required this.priceSource,`，在 `this.time,` 之後加 `this.date, this.lastTradePrice, this.lastTradeTime,`。
3. 欄位：在 `final String? time;` 之後加：

```dart

  /// [price] 的來源
  final QuotePriceSource priceSource;

  /// 報價日期(`d`,yyyyMMdd);格式不符為 null。即時報價只有等於今天才可顯示
  final DateTime? date;

  /// 最後一筆成交價與時間(`trade.z`／`trade.t`,非官方欄位)。
  ///
  /// 當輪 `z='-'` 時仍記著最後一筆成交(2026-10-05 12:13 實測:2330 當輪
  /// z='-'、trade.z=2560 @ 12:13:25)。**只供顯示**,不參與 [price]——盤中
  /// 提醒的比價維持原規則。指數列與收盤後的回應沒有這個物件,為 null。
  final double? lastTradePrice;
  final String? lastTradeTime;
```

4. `parseResponse` 內，把

```dart
      final price =
          _num(row['z']) ??
          _num(row['pz']) ??
          _lockedPrice(row) ??
          _midOrSide(row['b'], row['a']);
      if (price == null) continue;
```

換成（上方的「🚨 不可退回開盤價」註解保留不動）：

```dart
      final (price, priceSource) = switch ((
        _num(row['z']),
        _num(row['pz']),
        _lockedPrice(row),
      )) {
        (final z?, _, _) => (z, QuotePriceSource.trade),
        (_, final pz?, _) => (pz, QuotePriceSource.trial),
        (_, _, final locked?) => (locked, QuotePriceSource.locked),
        _ => (_midOrSide(row['b'], row['a']), QuotePriceSource.book),
      };
      if (price == null) continue;

      // 最後一筆成交(非官方的 trade 物件):只供顯示,不參與 price
      final (lastTradePrice, lastTradeTime) = switch (row['trade']) {
        final Map<dynamic, dynamic> t when _num(t['z']) != null => (
          _num(t['z']),
          t['t']?.toString(),
        ),
        _ => (null, null),
      };
```

5. `result[symbol] = IntradayQuote(` 的參數在 `time: row['t']?.toString(),` 之後加：

```dart
        priceSource: priceSource,
        date: _date(row['d']),
        lastTradePrice: lastTradePrice,
        lastTradeTime: lastTradeTime,
```

6. 在 `_num` 之後加：

```dart

  /// `d`(yyyyMMdd)→ 當天午夜;格式不符回 null
  static DateTime? _date(Object? v) {
    final s = v?.toString().trim() ?? '';
    if (s.length != 8) return null;
    final y = int.tryParse(s.substring(0, 4));
    final m = int.tryParse(s.substring(4, 6));
    final d = int.tryParse(s.substring(6));
    if (y == null || m == null || d == null) return null;
    if (m < 1 || m > 12 || d < 1 || d > 31) return null;
    return DateTime(y, m, d);
  }
```

- [ ] **Step 4: 確認通過**

Run: `flutter test test/data/remote/ test/domain/services/alert/`
Expected: 全部 PASS。「漲跌停鎖住」group 不變，證明 price 規則沒動：其餘 9 列逐列等於修正前基準。

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 5: 記錄進度**（不 commit）

---

### Task 2: client 逐批回報有沒有回應、可關閉逐批 warning、可傳逾時

**Files:**
- Modify: `lib/data/remote/market_client_mixin.dart:23-41`（`createDio`）
- Modify: `lib/data/remote/intraday_quote_client.dart`
- Test: `test/data/remote/intraday_quote_client_test.dart`

**Interfaces:**
- Consumes: Task 1 的 `IntradayQuote`。
- Produces:
  - `MarketClientMixin.createDio(String baseUrl, {Duration connectTimeout = 30 秒, Duration receiveTimeout = 60 秒})`。
  - `IntradayQuoteClient({Dio? dio, bool logBatchErrors = true})`。
  - `class QuoteBatchReport { Map<String, IntradayQuote> quotes; List<String> errors; Set<String> respondedSymbols; Set<String> failedSymbols; }`（const 建構子，四個都必填）。
  - `Future<QuoteBatchReport> fetchQuotesDetailed(Map<String, String> markets)`：限流拋 `RateLimitException`。
  - `fetchQuotes` 簽名與語意不變。

- [ ] **Step 1: 寫失敗測試**

`test/data/remote/intraday_quote_client_test.dart`：

1. import 區加：

```dart
import 'package:daredevil/core/constants/api_config.dart';
import 'package:daredevil/core/utils/logger.dart';
import 'package:daredevil/data/remote/market_client_mixin.dart';
```

2. 在 `main()` 最後（`test('MIS 回應前綴空行仍能解析...')` 之後）加：

```dart
  group('fetchQuotesDetailed(盤中即時報價)', () {
    final forty = {for (var i = 0; i < 40; i++) '${2000 + i}': 'TWSE'};

    test('🚨 逐批回報:成功批的代號算有回應,網路失敗批的代號算失敗', () async {
      final adapter = _FakeAdapter((i, _) {
        if (i == 0) throw const FakeSocketException('batch 0 down');
        return _misBody(['2035']);
      });
      final r = await clientWith(adapter).fetchQuotesDetailed(forty);

      expect(r.failedSymbols, {for (var i = 0; i < 35; i++) '${2000 + i}'});
      expect(r.respondedSymbols, {
        for (var i = 35; i < 40; i++) '${2000 + i}',
      });
      expect(r.errors, hasLength(1));
      expect(r.quotes.keys, ['2035']);
    });

    test('🚨 rtcode 非 0000、msgArray 沒有列、無法解碼 → 該批失敗,不產生 errors 字串', () async {
      for (final body in const [
        '{"rtcode":"5000","msgArray":[]}',
        '{"rtcode":"0000","msgArray":[]}',
        '{"rtcode":"0000"}',
        'not json',
      ]) {
        final r = await clientWith(
          _FakeAdapter((_, _) => body),
        ).fetchQuotesDetailed({'2330': 'TWSE'});
        expect(r.failedSymbols, {'2330'}, reason: body);
        expect(r.respondedSymbols, isEmpty, reason: body);
        expect(r.errors, isEmpty, reason: body);
      }
    });

    test('🚨 有回應但列全被解析丟掉(暫停交易)→ 仍算有回應', () async {
      final adapter = _FakeAdapter(
        (_, _) => jsonEncode({
          'rtcode': '0000',
          'msgArray': [
            {'c': '2330', 'z': '-', 'pz': '-'},
          ],
        }),
      );
      final r = await clientWith(
        adapter,
      ).fetchQuotesDetailed({'2330': 'TWSE'});
      expect(r.respondedSymbols, {'2330'});
      expect(r.failedSymbols, isEmpty);
      expect(r.quotes, isEmpty);
    });

    test('限流照樣往上拋', () async {
      final adapter = _FakeAdapter((_, _) => '<!doctype html><html></html>');
      await expectLater(
        clientWith(adapter).fetchQuotesDetailed({'2330': 'TWSE'}),
        throwsA(isA<RateLimitException>()),
      );
    });

    test('空輸入 → 不打 API', () async {
      final adapter = _FakeAdapter((_, _) => _misBody(const []));
      final r = await clientWith(adapter).fetchQuotesDetailed(const {});
      expect(r.quotes, isEmpty);
      expect(adapter.requests, isEmpty);
    });
  });

  group('逐批 warning(即時報價關掉,盤中提醒與 CLI 維持)', () {
    late List<String> crumbs;
    setUp(() {
      crumbs = [];
      AppLogger.setSentryDelegates(
        breadcrumb: (message, category, level, data) => crumbs.add(message),
      );
    });
    tearDown(() => AppLogger.setSentryDelegates());

    test('🚨 logBatchErrors: false → 批次失敗不記 warning', () async {
      final adapter = _FakeAdapter(
        (_, _) => throw const FakeSocketException('down'),
      );
      final client = IntradayQuoteClient(
        dio: Dio()..httpClientAdapter = adapter,
        logBatchErrors: false,
      );
      await client.fetchQuotes({'2330': 'TWSE'});
      await client.fetchQuotesDetailed({'2330': 'TWSE'});
      expect(crumbs, isEmpty);
    });

    test('預設照記(盤中提醒與 CLI 不變)', () async {
      final adapter = _FakeAdapter(
        (_, _) => throw const FakeSocketException('down'),
      );
      await clientWith(adapter).fetchQuotes({'2330': 'TWSE'});
      expect(crumbs, hasLength(1));
      expect(crumbs.single, contains('盤中報價批次失敗'));
    });
  });

  test('createDio 可傳短逾時;不傳維持 ApiConfig(盤中提醒與 CLI 不變)', () {
    final quick = MarketClientMixin.createDio(
      'https://example.invalid',
      connectTimeout: const Duration(seconds: 5),
      receiveTimeout: const Duration(seconds: 8),
    );
    expect(quick.options.connectTimeout, const Duration(seconds: 5));
    expect(quick.options.receiveTimeout, const Duration(seconds: 8));

    final normal = MarketClientMixin.createDio('https://example.invalid');
    expect(
      normal.options.connectTimeout,
      const Duration(seconds: ApiConfig.twseConnectTimeoutSec),
    );
    expect(
      normal.options.receiveTimeout,
      const Duration(seconds: ApiConfig.twseReceiveTimeoutSec),
    );
  });
```

- [ ] **Step 2: 確認紅燈**

Run: `flutter test test/data/remote/intraday_quote_client_test.dart`
Expected: 編譯失敗（`fetchQuotesDetailed`、`logBatchErrors`、`createDio` 的 `connectTimeout` 未定義）

- [ ] **Step 3: 實作**

1. `lib/data/remote/market_client_mixin.dart` 的 `createDio` 改成：

```dart
  /// 建立市場 API 用的 [Dio] 實例。
  ///
  /// 兩個市場共用相同的超時、Header 與回應類型設定;盤中即時報價另傳
  /// 短逾時(見 `LiveQuoteParams`)。
  static Dio createDio(
    String baseUrl, {
    Duration connectTimeout = const Duration(
      seconds: ApiConfig.twseConnectTimeoutSec,
    ),
    Duration receiveTimeout = const Duration(
      seconds: ApiConfig.twseReceiveTimeoutSec,
    ),
  }) {
    return Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: connectTimeout,
        receiveTimeout: receiveTimeout,
        headers: {
          'Accept': 'application/json',
          'User-Agent':
              'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36',
        },
        responseType: ResponseType.json,
      ),
    );
  }
```

2. `lib/data/remote/intraday_quote_client.dart` 整檔改成以下內容（原有註解原文保留，搬到新位置）：

```dart
import 'package:dio/dio.dart';

import 'package:daredevil/core/constants/api_endpoints.dart';
import 'package:daredevil/core/constants/market_codes.dart';
import 'package:daredevil/core/exceptions/app_exception.dart';
import 'package:daredevil/core/utils/logger.dart';
import 'package:daredevil/data/models/twse/intraday_quote.dart';
import 'package:daredevil/data/remote/market_client_mixin.dart';

/// 一輪報價抓取的結果:成功的報價 + 失敗批次的錯誤摘要
typedef QuoteFetchResult = ({
  Map<String, IntradayQuote> quotes,
  List<String> errors,
});

/// 一輪報價抓取的逐批明細(盤中即時報價用,2026-10-06)。
///
/// 每個送出的代號恰好落在 [respondedSymbols] 或 [failedSymbols] 其中之一:
/// - **有回應**:HTTP 200、`rtcode` 為 `0000`、`msgArray` 有列。列可能全被
///   解析丟掉(例如暫停交易),那仍算有回應——報價中心據此區分「證交所
///   今天尚無報價」與「網路斷了」。
/// - **失敗**:網路錯誤、非 200、無法解碼、`rtcode` 非 `0000`、`msgArray`
///   沒有列。
class QuoteBatchReport {
  const QuoteBatchReport({
    required this.quotes,
    required this.errors,
    required this.respondedSymbols,
    required this.failedSymbols,
  });

  final Map<String, IntradayQuote> quotes;

  /// 例外造成的批次失敗摘要(同 [QuoteFetchResult] 的 errors);`rtcode`
  /// 非 `0000`、沒有列、無法解碼不產生字串,只計入 [failedSymbols]
  final List<String> errors;
  final Set<String> respondedSymbols;
  final Set<String> failedSymbols;
}

/// 盤中即時報價 client(TWSE MIS,2026-08-08)。
///
/// **不快取**:這支的存在理由就是即時性,快取等於自我否定。
/// 分批送出(單次上限 [ApiEndpoints.misBatchSize] 檔),任何一批失敗
/// 不影響其他批——盤中提醒缺一檔比整批沒有好。
class IntradayQuoteClient {
  IntradayQuoteClient({Dio? dio, bool logBatchErrors = true})
    : _dio = dio ?? MarketClientMixin.createDio(ApiEndpoints.twseMisIntraday),
      _logBatchErrors = logBatchErrors;

  static const String _tag = 'MIS';
  final Dio _dio;

  /// 單批失敗是否記 `AppLogger.warning`。盤中即時報價每 15 秒一輪,失敗改
  /// 由報價中心統一記(一段連續失敗只記開始與恢復),所以傳 false;盤中
  /// 提醒與 CLI 維持預設。
  final bool _logBatchErrors;

  /// [markets] 為 symbol → 市場別(`TWSE`/`TPEx`),決定 `tse_`/`otc_` 前綴。
  /// 猜錯前綴會回不到報價(2026-08-07 實測:大量 3167 是上市不是上櫃)。
  ///
  /// [errors] 是失敗批次的「型別+訊息」摘要,錯誤是結果的一部分而非側信道:
  /// 批次錯誤原本只進 `AppLogger.warning`,而 launchd 跑的是 AOT 編譯 CLI
  /// ——AppLogger 靠 assert 判定 debug,AOT 下**全靜默**。結果 8/11–8/12
  /// 共 21 輪早盤失敗,日誌只有「報價全滅」,無從分辨 timeout/DNS/限流
  /// (2026-08-12 盲區調查)。
  Future<QuoteFetchResult> fetchQuotes(Map<String, String> markets) async {
    if (markets.isEmpty) {
      return (
        quotes: const <String, IntradayQuote>{},
        errors: const <String>[],
      );
    }
    final symbols = markets.keys.toList();
    final result = <String, IntradayQuote>{};
    final errors = <String>[];

    for (final batch in _batches(symbols)) {
      try {
        final data = await _requestBatch(batch, markets);
        if (data != null) result.addAll(IntradayQuote.parseResponse(data));
      } on RateLimitException {
        rethrow;
      } catch (e) {
        // 單批失敗不影響其他批:盤中缺一檔報價 > 整批沒有
        _warnBatchFailed(batch.length, e);
        errors.add(_describeError(e));
      }
    }
    AppLogger.debug(_tag, '盤中報價: ${result.length}/${symbols.length} 檔');
    return (quotes: result, errors: errors);
  }

  /// 同 [fetchQuotes],另回報每個代號所在的批次有沒有回應(見
  /// [QuoteBatchReport])。限流照樣拋 [RateLimitException]。
  ///
  /// 解析不包在 try 內:解析拋例外是程式錯誤、不是網路狀況,往上拋給報價
  /// 中心記 error;[fetchQuotes] 為維持盤中提醒的行為,仍把它當成該批失敗。
  Future<QuoteBatchReport> fetchQuotesDetailed(
    Map<String, String> markets,
  ) async {
    final quotes = <String, IntradayQuote>{};
    final errors = <String>[];
    final responded = <String>{};
    final failed = <String>{};

    for (final batch in _batches(markets.keys.toList())) {
      Map<String, dynamic>? data;
      try {
        data = await _requestBatch(batch, markets);
      } on RateLimitException {
        rethrow;
      } catch (e) {
        _warnBatchFailed(batch.length, e);
        errors.add(_describeError(e));
        failed.addAll(batch);
        continue;
      }
      final rows = data?['msgArray'];
      if (data == null ||
          data['rtcode'] != '0000' ||
          rows is! List ||
          rows.isEmpty) {
        failed.addAll(batch);
        continue;
      }
      responded.addAll(batch);
      quotes.addAll(IntradayQuote.parseResponse(data));
    }
    return QuoteBatchReport(
      quotes: quotes,
      errors: errors,
      respondedSymbols: responded,
      failedSymbols: failed,
    );
  }

  /// 送出一批(≤ [ApiEndpoints.misBatchSize] 檔)並解碼:無法解碼回 null,
  /// 限流拋 [RateLimitException],非 200 拋 [ApiException]
  Future<Map<String, dynamic>?> _requestBatch(
    List<String> batch,
    Map<String, String> markets,
  ) async {
    final exCh = batch
        .map((s) => '${markets[s] == MarketCode.twse ? 'tse' : 'otc'}_$s.tw')
        .join('|');
    final response = await _dio.get(
      ApiEndpoints.twseMisIntraday,
      queryParameters: {'ex_ch': exCh, 'json': 1, 'delay': 0},
      // 一律取原始字串自行解碼(2026-08-08 code review):讓 Dio 解析
      // 有兩個坑——①MIS 回應前綴帶空行,json 模式會解析失敗;②限流
      // 時回 HTML,若 Dio 先拋解析錯,就會被下面的 catch 吞成「這批
      // 失敗」而繼續猛打。交給 decodeResponseData 才看得出是限流。
      options: Options(responseType: ResponseType.plain),
    );
    if (response.statusCode != 200) {
      throw ApiException(
        '$_tag error: ${response.statusCode}',
        response.statusCode,
      );
    }
    // MIS 回應前面帶一串空行,Dio 的 responseType.json 因此解析失敗
    // 退回 String(2026-08-08 實測)——走專案既有的統一解碼 helper,
    // 它同時處理 String 情況與限流時的 HTML 回應。
    return MarketClientMixin.decodeResponseData(
      response.data,
      _tag,
      '盤中報價',
    );
  }

  static Iterable<List<String>> _batches(List<String> symbols) sync* {
    for (var i = 0; i < symbols.length; i += ApiEndpoints.misBatchSize) {
      yield symbols.skip(i).take(ApiEndpoints.misBatchSize).toList();
    }
  }

  void _warnBatchFailed(int size, Object e) {
    if (_logBatchErrors) {
      AppLogger.warning(_tag, '盤中報價批次失敗($size 檔)', e);
    }
  }

  /// 錯誤 → 「型別+訊息」一行摘要(進 CLI 日誌,型別是診斷的第一線索)
  static String _describeError(Object e) {
    final s = switch (e) {
      // DioException.toString() 冗長且訊息常為 null;type.name(connectionError
      // /connectionTimeout/receiveTimeout…)才是分類 timeout vs DNS vs 重置的
      // 關鍵,再帶上底層 error(通常是 SocketException 原文)
      DioException(:final type, :final message, :final error) =>
        'DioException.${type.name}: ${message ?? error}',
      _ => '${e.runtimeType}: $e',
    };
    return s.length > 200 ? s.substring(0, 200) : s;
  }

  /// 釋放底層 HttpClient 連線池(專案其他 5 支 client 皆有,見
  /// providers.dart 的「避免每次設定變動都洩漏一個底層 socket」)
  void close() => _dio.close(force: true);
}
```

- [ ] **Step 4: 確認通過**

Run: `flutter test test/data/remote/ test/domain/services/alert/ test/tool/tool_chain_pure_dart_test.dart`
Expected: 全部 PASS。原有的 client 測試（前綴、分批、單批失敗、限流、空輸入、errors、前綴空行）一行都沒改，照樣通過。

Run: `dart compile kernel tool/intraday_alert_check.dart -o build/intraday_alert_check.dill`
Expected: 編譯成功

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 5: 記錄進度**（不 commit）

---

### Task 3: 開收盤時間共用、即時報價參數、排程純函式

**Files:**
- Create: `lib/core/constants/market_session.dart`
- Create: `lib/core/constants/live_quote_params.dart`
- Modify: `lib/domain/services/alert/intraday_poll_schedule.dart:21-31`
- Create: `lib/domain/services/live_quote/live_quote_schedule.dart`
- Test: `test/domain/services/live_quote/live_quote_schedule_test.dart`

**Interfaces:**
- Consumes: Task 1 的 `IntradayQuote.date`、`priceSource`、`time`；`TaiwanCalendar.isTradingDay`、`DateContext.isSameDay`。
- Produces:
  - `MarketSession.openMinutes`、`MarketSession.closeMinutes`（int，自午夜起算的分鐘數）。
  - `LiveQuoteParams` 的各常數（名稱見 Step 3）。
  - `enum MarketPhase { closed, preOpen, open, afterClose }`。
  - `LiveQuoteSchedule` 的靜態方法：
    - `phaseAt(DateTime)`；
    - `pollInterval(int batchCount)`；
    - `stallThreshold(int batchCount, {bool afterClose = false})`；
    - `backoffInterval(int batchCount, int failuresSinceStall)`；
    - `inCliAvoidWindow(DateTime)`；
    - `canSendRequest(Iterable<DateTime> recent, DateTime now)`；
    - `isClosingQuote(IntradayQuote, DateTime today)`；
    - `afterClosePending({required bool hasClosingQuote, required int attempts})`；
    - `afterCloseDue({required bool hasClosingQuote, required int attempts, required DateTime? lastAttemptAt, required DateTime now})`；
    - `secondsOfDay(String?)`。

- [ ] **Step 1: 寫失敗測試**

建立 `test/domain/services/live_quote/live_quote_schedule_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/constants/live_quote_params.dart';
import 'package:daredevil/data/models/twse/intraday_quote.dart';
import 'package:daredevil/domain/services/live_quote/live_quote_schedule.dart';

/// 盤中即時報價的排程規則(2026-10-06,spec §2、參數表)。
void main() {
  Duration s(num seconds) =>
      Duration(milliseconds: (seconds * 1000).round());

  group('phaseAt', () {
    for (final (label, t, phase) in [
      ('08:59:59 盤前', DateTime(2026, 10, 6, 8, 59, 59), MarketPhase.preOpen),
      ('09:00:00 開盤', DateTime(2026, 10, 6, 9), MarketPhase.open),
      ('13:29:59 仍是盤中', DateTime(2026, 10, 6, 13, 29, 59), MarketPhase.open),
      ('13:30:00 起收盤後', DateTime(2026, 10, 6, 13, 30), MarketPhase.afterClose),
      ('14:10 收盤後(沒有時間上限)', DateTime(2026, 10, 6, 14, 10), MarketPhase.afterClose),
      ('週六休市', DateTime(2026, 10, 3, 10), MarketPhase.closed),
      ('2026-10-09 國慶補假休市', DateTime(2026, 10, 9, 10), MarketPhase.closed),
    ]) {
      test(label, () => expect(LiveQuoteSchedule.phaseAt(t), phase));
    }
  });

  test('🚨 輪詢間隔:2 批以內 15 秒;批數 > 2 為批數 × 7.5 秒', () {
    for (final (batches, expected) in [
      (0, s(15)),
      (1, s(15)),
      (2, s(15)),
      (3, s(22.5)),
      (4, s(30)),
      (10, s(75)),
    ]) {
      expect(
        LiveQuoteSchedule.pollInterval(batches),
        expected,
        reason: '$batches 批',
      );
    }
  });

  test('🚨 暫停門檻:max(60 秒, 2 × 輪詢間隔);收盤後以 1 分鐘為間隔', () {
    expect(LiveQuoteSchedule.stallThreshold(1), s(60));
    expect(LiveQuoteSchedule.stallThreshold(4), s(60));
    expect(LiveQuoteSchedule.stallThreshold(5), s(75));
    expect(LiveQuoteSchedule.stallThreshold(10), s(150));
    expect(LiveQuoteSchedule.stallThreshold(1, afterClose: true), s(120));
    expect(LiveQuoteSchedule.stallThreshold(10, afterClose: true), s(150));
  });

  test('🚨 退避:暫停後每次失敗加倍,最長 2 分鐘', () {
    expect(LiveQuoteSchedule.backoffInterval(1, 0), s(15));
    expect(LiveQuoteSchedule.backoffInterval(1, 1), s(30));
    expect(LiveQuoteSchedule.backoffInterval(1, 2), s(60));
    expect(LiveQuoteSchedule.backoffInterval(1, 3), s(120));
    expect(LiveQuoteSchedule.backoffInterval(1, 9), s(120));
    expect(LiveQuoteSchedule.backoffInterval(10, 1), s(120), reason: '75×2 也封頂');
  });

  test('🚨 CLI 避讓:每 5 分鐘整點後 10 秒內', () {
    for (final (t, expected) in [
      (DateTime(2026, 10, 6, 10, 5), true),
      (DateTime(2026, 10, 6, 10, 5, 9, 999), true),
      (DateTime(2026, 10, 6, 10, 5, 10), false),
      (DateTime(2026, 10, 6, 10, 4, 59), false),
      (DateTime(2026, 10, 6, 10, 0, 3), true),
      (DateTime(2026, 10, 6, 10, 1, 5), false),
      (DateTime(2026, 10, 6, 13, 25, 5), true),
    ]) {
      expect(LiveQuoteSchedule.inCliAvoidWindow(t), expected, reason: '$t');
    }
  });

  group('canSendRequest', () {
    final now = DateTime(2026, 10, 6, 10, 2);
    List<DateTime> ago(List<num> seconds) => [
      for (final x in seconds) now.subtract(s(x)),
    ];

    test('沒有紀錄 → 可以', () {
      expect(LiveQuoteSchedule.canSendRequest(const [], now), isTrue);
    });

    test('🚨 距上一個請求不到 2 秒 → 不行', () {
      expect(LiveQuoteSchedule.canSendRequest(ago([1.9]), now), isFalse);
      expect(LiveQuoteSchedule.canSendRequest(ago([2]), now), isTrue);
    });

    test('🚨 最近 60 秒內已有 8 個 → 不行;最舊的滿 60 秒就不算', () {
      expect(
        LiveQuoteSchedule.canSendRequest(ago([59, 50, 40, 30, 20, 10, 5, 3]), now),
        isFalse,
      );
      expect(
        LiveQuoteSchedule.canSendRequest(ago([60, 50, 40, 30, 20, 10, 5, 3]), now),
        isTrue,
      );
      expect(
        LiveQuoteSchedule.canSendRequest(ago([50, 40, 30, 20, 10, 5, 3]), now),
        isTrue,
      );
    });
  });

  group('isClosingQuote', () {
    final today = DateTime(2026, 10, 6);
    IntradayQuote q(Map<String, Object?> extra) =>
        IntradayQuote.parseResponse({
          'rtcode': '0000',
          'msgArray': [
            {'c': 'A', 'y': '100.0000', 'd': '20261006', 't': '13:30:00', ...extra},
          ],
        })['A']!;

    test('🚨 今天、t ≥ 13:30:00、成交 → 收盤報價', () {
      expect(LiveQuoteSchedule.isClosingQuote(q({'z': '101.0000'}), today), isTrue);
    });

    test('鎖住(z、pz 都是 -)也算', () {
      final locked = q({'z': '-', 'pz': '-', 'b': '0.0000_110.0000_', 'a': '-', 'u': '110.0000'});
      expect(locked.priceSource, QuotePriceSource.locked);
      expect(LiveQuoteSchedule.isClosingQuote(locked, today), isTrue);
    });

    test('🚨 延緩收盤(z=-、v>0、t<13:30:00)不算', () {
      final delayed = q({'z': '-', 'pz': '-', 'v': '1234', 't': '13:29:40', 'b': '99.5000_', 'a': '100.5000_'});
      expect(LiveQuoteSchedule.isClosingQuote(delayed, today), isFalse);
    });

    test('t 早一秒、日期不是今天、試撮、五檔、t 格式不符、沒有日期 → 都不算', () {
      expect(LiveQuoteSchedule.isClosingQuote(q({'z': '101.0000', 't': '13:29:59'}), today), isFalse);
      expect(LiveQuoteSchedule.isClosingQuote(q({'z': '101.0000', 'd': '20261005'}), today), isFalse);
      expect(LiveQuoteSchedule.isClosingQuote(q({'z': '-', 'pz': '101.0000'}), today), isFalse);
      expect(LiveQuoteSchedule.isClosingQuote(q({'z': '-', 'b': '99.5000_', 'a': '100.5000_'}), today), isFalse);
      expect(LiveQuoteSchedule.isClosingQuote(q({'z': '101.0000', 't': '1330'}), today), isFalse);
      expect(LiveQuoteSchedule.isClosingQuote(q({'z': '101.0000', 'd': ''}), today), isFalse);
    });
  });

  group('收盤後逐檔', () {
    final now = DateTime(2026, 10, 6, 14);

    test('🚨 拿到收盤報價 → 不再抓', () {
      expect(LiveQuoteSchedule.afterClosePending(hasClosingQuote: true, attempts: 0), isFalse);
    });

    test('🚨 第 10 次「有回應但不是收盤報價」之後不再抓', () {
      expect(LiveQuoteSchedule.afterClosePending(hasClosingQuote: false, attempts: 9), isTrue);
      expect(
        LiveQuoteSchedule.afterClosePending(hasClosingQuote: false, attempts: LiveQuoteParams.afterCloseMaxAttempts),
        isFalse,
      );
    });

    test('每檔 1 分鐘一次', () {
      bool due(DateTime? last) => LiveQuoteSchedule.afterCloseDue(
        hasClosingQuote: false,
        attempts: 3,
        lastAttemptAt: last,
        now: now,
      );
      expect(due(null), isTrue);
      expect(due(now.subtract(s(59))), isFalse);
      expect(due(now.subtract(s(60))), isTrue);
    });

    test('已停的不會因為過了 1 分鐘又變成該抓', () {
      expect(
        LiveQuoteSchedule.afterCloseDue(hasClosingQuote: true, attempts: 0, lastAttemptAt: null, now: now),
        isFalse,
      );
    });
  });

  test('secondsOfDay:HH:mm:ss 才解析', () {
    expect(LiveQuoteSchedule.secondsOfDay('13:30:00'), 48600);
    expect(LiveQuoteSchedule.secondsOfDay('9:05:00'), 32700);
    expect(LiveQuoteSchedule.secondsOfDay('1330'), isNull);
    expect(LiveQuoteSchedule.secondsOfDay(null), isNull);
  });
}
```

- [ ] **Step 2: 確認紅燈**

Run: `flutter test test/domain/services/live_quote/live_quote_schedule_test.dart`
Expected: 編譯失敗（`live_quote_params.dart`、`live_quote_schedule.dart` 不存在）

- [ ] **Step 3: 實作**

1. 建立 `lib/core/constants/market_session.dart`：

```dart
/// 台股盤中交易時段(盤中提醒與盤中即時報價共用的單一來源)
abstract final class MarketSession {
  /// 09:00 開盤(自午夜起算的分鐘數)
  static const int openMinutes = 9 * 60;

  /// 13:30 收盤(含尾盤集合競價)
  static const int closeMinutes = 13 * 60 + 30;
}
```

2. 建立 `lib/core/constants/live_quote_params.dart`：

```dart
/// 盤中即時報價參數(2026-10-05 設計,值見設計文件的參數表)
abstract final class LiveQuoteParams {
  /// 盤中輪詢間隔(批數 > 2 時由 `LiveQuoteSchedule.pollInterval` 拉長)
  static const Duration pollInterval = Duration(seconds: 15);

  /// 任何 60 秒內最多幾個 MIS 請求(盤中提醒 CLI 另計,約每分鐘 0.4 次)
  static const int maxRequestsPerMinute = 8;

  /// 相鄰兩個請求至少間隔(同一輪內批與批之間)
  static const Duration minRequestGap = Duration(seconds: 2);

  /// 盤中提醒 CLI 每幾分鐘跑一次(`ops/launchd/com.neo.daredevil.intraday.plist`
  /// 的 StartCalendarInterval:交易日 09:00–13:30 每 5 分鐘)
  static const int cliEveryMinutes = 5;

  /// CLI 整點後讓開多久
  static const Duration cliAvoidWindow = Duration(seconds: 10);

  /// 收盤後每檔抓取間隔
  static const Duration afterCloseRetryInterval = Duration(minutes: 1);

  /// 收盤後每檔最多幾次「有回應但不是收盤報價」(網路失敗、限流不計)
  static const int afterCloseMaxAttempts = 10;

  /// 視為暫停的無回應時間下限(實際取 max(此值, 2 × 輪詢間隔))
  static const Duration stallFloor = Duration(seconds: 60);

  /// 暫停後每次失敗間隔加倍的上限
  static const Duration maxBackoff = Duration(minutes: 2);

  /// 撞到限流後整個報價中心暫停多久(之後先用 1 個請求試探)
  static const Duration rateLimitPause = Duration(minutes: 5);

  /// 報價中心專用逾時(盤中提醒與 CLI 維持 ApiConfig 的 30／60 秒)
  static const Duration connectTimeout = Duration(seconds: 5);
  static const Duration receiveTimeout = Duration(seconds: 8);

  /// 報價中心的節拍:登記變動、可見性變動都等下一拍才動作
  static const Duration tick = Duration(seconds: 1);

  /// 閃色淡出(第 2 段畫面使用)
  static const Duration flashFade = Duration(milliseconds: 600);

  /// 大盤指數在 MIS 的代號(市場別硬對應,不查主檔)
  static const String twseIndexSymbol = 't00';
  static const String tpexIndexSymbol = 'o00';
}
```

3. `lib/domain/services/alert/intraday_poll_schedule.dart`：
   - import 改：`import 'package:daredevil/core/constants/market_session.dart';` 加在 `rule_params_alert.dart` 之前。
   - 刪除 `_openMinutes`、`_closeMinutes` 兩個私有常數與上方註解。
   - `isMarketHours` 改成：

```dart
  /// [now] 是否落在可輪詢的盤中時段(交易日 + 交易時間)。13:30 那一分鐘
  /// 也算;盤中即時報價則以 13:30 起為收盤後(`LiveQuoteSchedule.phaseAt`)。
  static bool isMarketHours(DateTime now) {
    if (!TaiwanCalendar.isTradingDay(now)) return false;
    final minutes = now.hour * 60 + now.minute;
    return minutes >= MarketSession.openMinutes &&
        minutes <= MarketSession.closeMinutes;
  }
```

4. 建立 `lib/domain/services/live_quote/live_quote_schedule.dart`：

```dart
import 'package:daredevil/core/constants/live_quote_params.dart';
import 'package:daredevil/core/constants/market_session.dart';
import 'package:daredevil/core/utils/date_context.dart';
import 'package:daredevil/core/utils/taiwan_calendar.dart';
import 'package:daredevil/data/models/twse/intraday_quote.dart';

/// 交易階段(依台北時間與交易日曆)
enum MarketPhase { closed, preOpen, open, afterClose }

/// 盤中即時報價的排程規則(純函式,2026-10-06)。
///
/// 只回答「現在是什麼階段、多久抓一次、這個請求能不能發、這筆是不是收盤
/// 報價」;要抓哪些股票、何時發,由 `LiveQuoteCenter` 組合。
abstract final class LiveQuoteSchedule {
  static MarketPhase phaseAt(DateTime now) {
    if (!TaiwanCalendar.isTradingDay(now)) return MarketPhase.closed;
    final minutes = now.hour * 60 + now.minute;
    if (minutes < MarketSession.openMinutes) return MarketPhase.preOpen;
    if (minutes < MarketSession.closeMinutes) return MarketPhase.open;
    return MarketPhase.afterClose;
  }

  /// 一輪 [batchCount] 批時的輪詢間隔:平常 15 秒;批數 > 2 時拉長為
  /// 批數 × 7.5 秒,平均請求率維持每分鐘 8 次(瞬間的上限由
  /// [canSendRequest] 守住)
  static Duration pollInterval(int batchCount) {
    final spread = Duration(
      microseconds:
          Duration.microsecondsPerMinute *
          batchCount ~/
          LiveQuoteParams.maxRequestsPerMinute,
    );
    return spread > LiveQuoteParams.pollInterval
        ? spread
        : LiveQuoteParams.pollInterval;
  }

  /// 距上一次有回應的一輪超過多久視為暫停:max(60 秒, 2 × 輪詢間隔)。
  /// 收盤後每檔 1 分鐘才抓一次,間隔以 1 分鐘計,否則 CLI 避讓讓某次間隔
  /// 變成 69 秒時就會誤判暫停。
  static Duration stallThreshold(int batchCount, {bool afterClose = false}) {
    var interval = pollInterval(batchCount);
    if (afterClose && interval < LiveQuoteParams.afterCloseRetryInterval) {
      interval = LiveQuoteParams.afterCloseRetryInterval;
    }
    final twice = interval * 2;
    return twice > LiveQuoteParams.stallFloor
        ? twice
        : LiveQuoteParams.stallFloor;
  }

  /// 暫停後第 [failuresSinceStall] 次失敗之後的間隔:輪詢間隔逐次加倍,
  /// 最長 2 分鐘
  static Duration backoffInterval(int batchCount, int failuresSinceStall) {
    var interval = pollInterval(batchCount);
    for (
      var i = 0;
      i < failuresSinceStall && interval < LiveQuoteParams.maxBackoff;
      i++
    ) {
      interval *= 2;
    }
    return interval < LiveQuoteParams.maxBackoff
        ? interval
        : LiveQuoteParams.maxBackoff;
  }

  /// 盤中提醒 CLI 每 5 分鐘整點後 10 秒內不發請求(讓給 CLI)。CLI 只在
  /// 交易時段跑,收盤後照樣讓開:規則簡單,代價只是延後最多 10 秒。
  static bool inCliAvoidWindow(DateTime now) =>
      now.minute % LiveQuoteParams.cliEveryMinutes == 0 &&
      Duration(seconds: now.second, milliseconds: now.millisecond) <
          LiveQuoteParams.cliAvoidWindow;

  /// 現在能不能再發一個請求([recent] 是先前請求的送出時刻):最近 60 秒
  /// 內少於 8 個,而且距上一個至少 2 秒。送出前都檢查,就保證任何 60 秒
  /// 的窗口內不超過 8 個。
  static bool canSendRequest(Iterable<DateTime> recent, DateTime now) {
    var inLastMinute = 0;
    for (final t in recent) {
      final ago = now.difference(t);
      if (ago < LiveQuoteParams.minRequestGap) return false;
      if (ago < const Duration(minutes: 1)) inLastMinute++;
    }
    return inLastMinute < LiveQuoteParams.maxRequestsPerMinute;
  }

  /// 收盤報價:日期是今天、時間 ≥ 13:30:00、價格來自成交或鎖住。
  /// 不依賴非官方的 trade 物件。
  static bool isClosingQuote(IntradayQuote quote, DateTime today) {
    final date = quote.date;
    if (date == null || !DateContext.isSameDay(date, today)) return false;
    final seconds = secondsOfDay(quote.time);
    if (seconds == null || seconds < MarketSession.closeMinutes * 60) {
      return false;
    }
    return quote.priceSource == QuotePriceSource.trade ||
        quote.priceSource == QuotePriceSource.locked;
  }

  /// 收盤後這一檔是否還要抓:還沒拿到收盤報價,而且「有回應但不是收盤
  /// 報價」未滿 10 次
  static bool afterClosePending({
    required bool hasClosingQuote,
    required int attempts,
  }) => !hasClosingQuote && attempts < LiveQuoteParams.afterCloseMaxAttempts;

  /// 收盤後這一檔現在該不該抓:還要抓,而且距上次嘗試滿 1 分鐘
  static bool afterCloseDue({
    required bool hasClosingQuote,
    required int attempts,
    required DateTime? lastAttemptAt,
    required DateTime now,
  }) =>
      afterClosePending(hasClosingQuote: hasClosingQuote, attempts: attempts) &&
      (lastAttemptAt == null ||
          now.difference(lastAttemptAt) >=
              LiveQuoteParams.afterCloseRetryInterval);

  /// `HH:mm:ss` → 當天第幾秒;格式不符回 null
  static int? secondsOfDay(String? hms) {
    final parts = (hms ?? '').split(':');
    if (parts.length != 3) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final s = int.tryParse(parts[2]);
    if (h == null || m == null || s == null) return null;
    return h * 3600 + m * 60 + s;
  }
}
```

- [ ] **Step 4: 確認通過**

Run: `flutter test test/domain/services/live_quote/ test/domain/services/alert/ test/tool/tool_chain_pure_dart_test.dart`
Expected: 全部 PASS（`intraday_poll_schedule_test` 的 13:30 為盤中、13:31 不是，照舊）

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 5: 記錄進度**（不 commit）

---

### Task 4: 即時報價的型別與顯示合併規則

**Files:**
- Create: `lib/domain/models/live_quote.dart`
- Create: `lib/domain/services/live_quote/live_quote_merge.dart`
- Test: `test/domain/services/live_quote/live_quote_merge_test.dart`

**Interfaces:**
- Consumes: Task 3 的 `LiveQuoteSchedule.phaseAt`、`MarketPhase`；`DateContext.isSameDay`。
- Produces:
  - 列舉：`enum LiveDisplaySource { trade, lastTrade, locked, trialOrBook }`、`enum LiveSymbolStatus { ok, noQuote, batchFailed }`。
  - `class LiveQuoteFlash { int id; bool up; }`。
  - `class LiveQuoteEntry`：
    - 必填欄位：`symbol`、`date`、`price`、`displaySource`、`previousClose`、`quoteTime`、`isClosingQuote`。
    - 選填欄位：`open`、`high`、`low`、`volumeLots`、`limitUp`、`limitDown`、`isLimitUpLocked`、`isLimitDownLocked`、`flash`。
    - 方法：`withoutFlash()`。
  - `class OfficialPrice { DateTime? date; double? close; double? priceChange; }`。
  - 列舉：`enum MergedPriceKind { official, live, fallback }`、`enum LiveQuoteLabel { quoteTime, closingPending, lastQuote }`。
  - `class MergedPrice { kind; double? price; double? previousClose; LiveQuoteLabel? label; LiveQuoteEntry? live; String? get quoteTime; }`。
  - `LiveQuoteMerge.merge({required OfficialPrice? official, required LiveQuoteEntry? live, required DateTime now}) → MergedPrice`。

- [ ] **Step 1: 寫失敗測試**

建立 `test/domain/services/live_quote/live_quote_merge_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/domain/models/live_quote.dart';
import 'package:daredevil/domain/services/live_quote/live_quote_merge.dart';

/// 顯示合併規則(2026-10-06,spec §5):以「該畫面原本要顯示的那筆資料」
/// 為基準——它是今天且有收盤價就用它,否則用今天的即時報價,都沒有就維持
/// 原本的資料。
void main() {
  final morning = DateTime(2026, 10, 6, 10, 15, 40);
  final afterClose = DateTime(2026, 10, 6, 14, 10);

  LiveQuoteEntry live({
    DateTime? date,
    double price = 101,
    bool closing = false,
    String time = '10:15:30',
  }) => LiveQuoteEntry(
    symbol: 'A',
    date: date ?? DateTime(2026, 10, 6),
    price: price,
    displaySource: LiveDisplaySource.trade,
    previousClose: 100,
    quoteTime: time,
    isClosingQuote: closing,
  );

  OfficialPrice official(DateTime? date, double? close, {double? change}) =>
      OfficialPrice(date: date, close: close, priceChange: change);

  test('🚨 原本的資料是今天且有收盤價 → 正式資料,不看即時', () {
    final m = LiveQuoteMerge.merge(
      official: official(DateTime(2026, 10, 6), 98, change: -2),
      live: live(),
      now: morning,
    );
    expect(m.kind, MergedPriceKind.official);
    expect(m.price, 98);
    expect(m.previousClose, 100, reason: '收盤 − priceChange');
    expect(m.label, isNull);
  });

  test('🚨 原本的資料是昨天 + 今天的即時 → 即時,盤中標報價時間', () {
    final m = LiveQuoteMerge.merge(
      official: official(DateTime(2026, 10, 5), 100, change: 1),
      live: live(),
      now: morning,
    );
    expect(m.kind, MergedPriceKind.live);
    expect(m.price, 101);
    expect(m.previousClose, 100, reason: 'MIS 昨收 y');
    expect(m.label, LiveQuoteLabel.quoteTime);
    expect(m.quoteTime, '10:15:30');
  });

  test('🚨 部分寫入:日期是今天但收盤價為 null → 不算正式資料', () {
    final m = LiveQuoteMerge.merge(
      official: official(DateTime(2026, 10, 6), null),
      live: live(),
      now: morning,
    );
    expect(m.kind, MergedPriceKind.live);
  });

  test('過期指數(呼叫端把日期傳 null)→ 不算正式資料', () {
    final m = LiveQuoteMerge.merge(
      official: official(null, 100),
      live: live(),
      now: morning,
    );
    expect(m.kind, MergedPriceKind.live);
  });

  test('🚨 即時報價日期不是今天 → 不用,維持原本的資料', () {
    final m = LiveQuoteMerge.merge(
      official: official(DateTime(2026, 10, 5), 100, change: 1),
      live: live(date: DateTime(2026, 10, 5)),
      now: morning,
    );
    expect(m.kind, MergedPriceKind.fallback);
    expect(m.price, 100);
    expect(m.previousClose, 99);
  });

  test('🚨 跨日:App 開著過夜,隔天盤前不把昨天的收盤標成今日收盤', () {
    final m = LiveQuoteMerge.merge(
      official: official(DateTime(2026, 10, 5), 100),
      live: live(closing: true),
      now: DateTime(2026, 10, 7, 8, 30),
    );
    expect(m.kind, MergedPriceKind.fallback);
    expect(m.label, isNull);
  });

  test('🚨 收盤後三種標示:收盤報價、非收盤報價;盤中為報價時間', () {
    LiveQuoteLabel? label(bool closing, DateTime now) => LiveQuoteMerge.merge(
      official: official(DateTime(2026, 10, 5), 100),
      live: live(closing: closing, time: closing ? '13:30:00' : '13:29:40'),
      now: now,
    ).label;
    expect(label(true, afterClose), LiveQuoteLabel.closingPending);
    expect(label(false, afterClose), LiveQuoteLabel.lastQuote);
    expect(label(false, morning), LiveQuoteLabel.quoteTime);
  });

  test('priceChange 為 null → previousClose 交給呼叫端(null)', () {
    final m = LiveQuoteMerge.merge(
      official: official(DateTime(2026, 10, 6), 105),
      live: null,
      now: afterClose,
    );
    expect(m.kind, MergedPriceKind.official);
    expect(m.previousClose, isNull);
  });

  test('都沒有 → 原本的資料(可能是 null)', () {
    final m = LiveQuoteMerge.merge(official: null, live: null, now: morning);
    expect(m.kind, MergedPriceKind.fallback);
    expect(m.price, isNull);
    expect(m.live, isNull);
  });
}
```

- [ ] **Step 2: 確認紅燈**

Run: `flutter test test/domain/services/live_quote/live_quote_merge_test.dart`
Expected: 編譯失敗（`live_quote.dart`、`live_quote_merge.dart` 不存在）

- [ ] **Step 3: 實作**

1. 建立 `lib/domain/models/live_quote.dart`：

```dart
import 'package:meta/meta.dart';

/// 即時報價的顯示價取自哪裡(依序判斷,見 `LiveQuoteBook`)
enum LiveDisplaySource {
  /// 本輪成交價 z
  trade,

  /// 最後一筆成交:本輪的 trade.z,或報價中心今天記住的成交價／鎖住價
  lastTrade,

  /// 漲跌停鎖住:漲停價或跌停價
  locked,

  /// 試撮價或五檔價(今天還沒有任何成交可用)
  trialOrBook,
}

/// 某一檔最近一次被請求的結果(卡片上的例外標示用)
enum LiveSymbolStatus {
  /// 拿到今天的報價
  ok,

  /// 有回應但沒有可用報價(暫停交易、整天無成交無五檔、日期不是今天)
  noQuote,

  /// 所在批次失敗(網路、rtcode、格式)
  batchFailed,
}

/// 閃色事件:[id] 每次閃色都不同,畫面據此判斷是不是新的事件
@immutable
class LiveQuoteFlash {
  const LiveQuoteFlash({required this.id, required this.up});

  final int id;

  /// 方向比上一輪(不比昨收)
  final bool up;
}

/// 報價中心對某一檔的顯示結果(只存在記憶體,不寫資料庫)
@immutable
class LiveQuoteEntry {
  const LiveQuoteEntry({
    required this.symbol,
    required this.date,
    required this.price,
    required this.displaySource,
    required this.previousClose,
    required this.quoteTime,
    required this.isClosingQuote,
    this.open,
    this.high,
    this.low,
    this.volumeLots,
    this.limitUp,
    this.limitDown,
    this.isLimitUpLocked = false,
    this.isLimitDownLocked = false,
    this.flash,
  });

  final String symbol;

  /// 報價日期(MIS d);只有等於今天才可顯示,見 `LiveQuoteMerge`
  final DateTime date;
  final double price;
  final LiveDisplaySource displaySource;

  /// MIS 昨收 y(除權息日為參考價)
  final double previousClose;

  /// 顯示價對應的時間 HH:mm:ss:最後成交用 trade.t 或記住的時間,其餘用本輪 t
  final String? quoteTime;

  /// 收盤報價(見 `LiveQuoteSchedule.isClosingQuote`)
  final bool isClosingQuote;
  final double? open;
  final double? high;
  final double? low;

  /// 累計成交量(張,MIS v)
  final int? volumeLots;
  final double? limitUp;
  final double? limitDown;
  final bool isLimitUpLocked;
  final bool isLimitDownLocked;

  /// 本輪的閃色事件,沒有為 null;只活一輪。畫面第一次建立時把現有的
  /// id 當作已看過,不補閃
  final LiveQuoteFlash? flash;

  /// 同一筆、拿掉閃色
  LiveQuoteEntry withoutFlash() => LiveQuoteEntry(
    symbol: symbol,
    date: date,
    price: price,
    displaySource: displaySource,
    previousClose: previousClose,
    quoteTime: quoteTime,
    isClosingQuote: isClosingQuote,
    open: open,
    high: high,
    low: low,
    volumeLots: volumeLots,
    limitUp: limitUp,
    limitDown: limitDown,
    isLimitUpLocked: isLimitUpLocked,
    isLimitDownLocked: isLimitDownLocked,
  );
}
```

2. 建立 `lib/domain/services/live_quote/live_quote_merge.dart`：

```dart
import 'package:meta/meta.dart';

import 'package:daredevil/core/utils/date_context.dart';
import 'package:daredevil/domain/models/live_quote.dart';
import 'package:daredevil/domain/services/live_quote/live_quote_schedule.dart';

/// 畫面原本要顯示的那筆正式資料(盤後):
/// - 自選:綁分析日期的那筆。
/// - 個股頁:對齊法人日期的那筆。
/// - 投資組合:最新一筆。
/// - 指數:`MarketOverviewState` 的該指數;在 `staleNames` 裡時呼叫端把
///   [date] 傳 null。
@immutable
class OfficialPrice {
  const OfficialPrice({
    required this.date,
    required this.close,
    this.priceChange,
  });

  final DateTime? date;
  final double? close;

  /// 交易所漲跌價差;昨收 = 收盤 − 價差(除權息日即為參考價)
  final double? priceChange;
}

enum MergedPriceKind {
  /// 畫面原本的資料是今天且有收盤價
  official,

  /// 今天的有效即時報價
  live,

  /// 都沒有:畫面原本的資料(不改變現行行為)
  fallback,
}

/// 用即時報價時的標示
enum LiveQuoteLabel {
  /// 盤中:報價時間
  quoteTime,

  /// 收盤報價:「今日收盤・待盤後更新」
  closingPending,

  /// 收盤後但不是收盤報價:「最後報價 HH:MM:SS」
  lastQuote,
}

@immutable
class MergedPrice {
  const MergedPrice._({
    required this.kind,
    required this.price,
    required this.previousClose,
    this.label,
    this.live,
  });

  final MergedPriceKind kind;
  final double? price;

  /// 漲跌幅與今日損益的基準:即時為 MIS 的 y;正式與原樣為「收盤 −
  /// priceChange」,priceChange 為 null 時為 null(呼叫端退回前一交易日收盤)
  final double? previousClose;
  final LiveQuoteLabel? label;

  /// 用即時報價時的那一筆(鎖住、開高低量等)
  final LiveQuoteEntry? live;

  String? get quoteTime => live?.quoteTime;
}

/// 顯示合併規則(純函式,2026-10-06)。
///
/// 每檔、每個指數以「該畫面原本要顯示的那筆資料」為基準:部分寫入時
/// (價格已到、分析或法人還沒到)畫面繼續用即時報價,直到它自己的資料
/// 到齊,不會出現「判定已有今天資料、實際卻顯示昨天」。
abstract final class LiveQuoteMerge {
  static MergedPrice merge({
    required OfficialPrice? official,
    required LiveQuoteEntry? live,
    required DateTime now,
  }) {
    final officialDate = official?.date;
    final officialClose = official?.close;
    final officialChange = official?.priceChange;
    final officialPrevious = officialClose != null && officialChange != null
        ? officialClose - officialChange
        : null;

    if (officialDate != null &&
        officialClose != null &&
        DateContext.isSameDay(officialDate, now)) {
      return MergedPrice._(
        kind: MergedPriceKind.official,
        price: officialClose,
        previousClose: officialPrevious,
      );
    }
    if (live != null && DateContext.isSameDay(live.date, now)) {
      final label = switch (LiveQuoteSchedule.phaseAt(now)) {
        MarketPhase.open => LiveQuoteLabel.quoteTime,
        _ when live.isClosingQuote => LiveQuoteLabel.closingPending,
        _ => LiveQuoteLabel.lastQuote,
      };
      return MergedPrice._(
        kind: MergedPriceKind.live,
        price: live.price,
        previousClose: live.previousClose,
        label: label,
        live: live,
      );
    }
    return MergedPrice._(
      kind: MergedPriceKind.fallback,
      price: officialClose,
      previousClose: officialPrevious,
    );
  }
}
```

- [ ] **Step 4: 確認通過**

Run: `flutter test test/domain/services/live_quote/`
Expected: 全部 PASS

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 5: 記錄進度**（不 commit）

---

### Task 5: 記帳本 LiveQuoteBook（顯示價、閃色、卡片狀態、收盤後逐檔、換日）

**Files:**
- Create: `lib/domain/services/live_quote/live_quote_book.dart`
- Test: `test/domain/services/live_quote/live_quote_book_test.dart`

**Interfaces:**
- Consumes:
  - Task 1：`IntradayQuote`、`QuotePriceSource`。
  - Task 2：`QuoteBatchReport`。
  - Task 3：`LiveQuoteSchedule.isClosingQuote`／`afterClosePending`／`afterCloseDue`／`secondsOfDay`。
  - Task 4：`LiveQuoteEntry`、`LiveDisplaySource`、`LiveSymbolStatus`、`LiveQuoteFlash`。
- Produces:
  - `enum RoundOutcome { success, respondedNoToday, failed }`。
  - `class LiveQuoteBook`：
    - getter：`Map<String, LiveQuoteEntry> get entries`、`Map<String, LiveSymbolStatus> get symbolStatus`、`bool? get latestResponseHadToday`、`String? get latestQuoteTime`。
    - `bool rollDay(DateTime now)`：日期變了就清空，回傳是否清了。
    - `void forgetLastRound()`。
    - `List<String> pendingAfterClose(Iterable<String> candidates)`、`List<String> dueAfterClose(Iterable<String> candidates, DateTime now)`。
    - `RoundOutcome apply(QuoteBatchReport report, {required Iterable<String> requested, required DateTime now, required bool afterClose})`。

- [ ] **Step 1: 寫失敗測試**

建立 `test/domain/services/live_quote/live_quote_book_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/data/models/twse/intraday_quote.dart';
import 'package:daredevil/data/remote/intraday_quote_client.dart';
import 'package:daredevil/domain/models/live_quote.dart';
import 'package:daredevil/domain/services/live_quote/live_quote_book.dart';

/// 報價中心的記帳本(2026-10-06,spec §3 顯示價與閃色、§2 收盤後逐檔、
/// §8 一輪的結果)。報價一律經真的 IntradayQuote.parseResponse。
void main() {
  DateTime at(int h, int m, [int s = 0]) => DateTime(2026, 10, 6, h, m, s);

  Map<String, Object?> row(
    String c, {
    String z = '-',
    String pz = '-',
    String y = '100.0000',
    String d = '20261006',
    String t = '10:00:00',
    String b = '-',
    String a = '-',
    String? u,
    String? w,
    Map<String, String>? trade,
    Map<String, Object?> extra = const {},
  }) => {
    'c': c,
    'z': z,
    'pz': pz,
    'y': y,
    'd': d,
    't': t,
    'b': b,
    'a': a,
    if (u != null) 'u': u,
    if (w != null) 'w': w,
    if (trade != null) 'trade': trade,
    ...extra,
  };

  /// 每列所在的批次都有回應
  QuoteBatchReport responded(List<Map<String, Object?>> rows) =>
      QuoteBatchReport(
        quotes: IntradayQuote.parseResponse({
          'rtcode': '0000',
          'msgArray': rows,
        }),
        errors: const [],
        respondedSymbols: {for (final r in rows) r['c'] as String},
        failedSymbols: const <String>{},
      );

  QuoteBatchReport failed(Set<String> symbols) => QuoteBatchReport(
    quotes: const {},
    errors: const ['DioException.connectionTimeout: 模擬'],
    respondedSymbols: const <String>{},
    failedSymbols: symbols,
  );

  late LiveQuoteBook book;
  setUp(() => book = LiveQuoteBook());

  /// 盤中套一輪,回傳 A 的顯示結果
  LiveQuoteEntry? round(
    QuoteBatchReport r, {
    List<String> requested = const ['A'],
    DateTime? now,
  }) {
    book.apply(
      r,
      requested: requested,
      now: now ?? at(10, 0, 5),
      afterClose: false,
    );
    return book.entries['A'];
  }

  group('顯示價順序', () {
    test('🚨 鎖住 → 漲停價,即使 trade 記著鎖住前較低的成交', () {
      round(responded([row('A', z: '109.5000', u: '110.0000')]));
      final e = round(
        responded([
          row(
            'A',
            b: '0.0000_110.0000_',
            u: '110.0000',
            trade: const {'t': '10:00:01', 'z': '109.5000'},
          ),
        ]),
      )!;
      expect(e.price, 110.0);
      expect(e.displaySource, LiveDisplaySource.locked);
      expect(e.isLimitUpLocked, isTrue);
    });

    test('跌停鎖住鏡像 → 跌停價', () {
      final e = round(
        responded([row('A', a: '0.0000_90.0000_', w: '90.0000')]),
      )!;
      expect(e.price, 90.0);
      expect(e.displaySource, LiveDisplaySource.locked);
      expect(e.isLimitDownLocked, isTrue);
    });

    test('本輪有成交 → 成交價', () {
      final e = round(
        responded([row('A', z: '101.0000', b: '100.5000_', a: '101.5000_')]),
      )!;
      expect(e.price, 101.0);
      expect(e.displaySource, LiveDisplaySource.trade);
    });

    test('🚨 本輪 z 為 - 但有 trade.z → 最後成交價與它的時間,不用五檔中價', () {
      final e = round(
        responded([
          row(
            'A',
            b: '100.5000_',
            a: '101.5000_',
            t: '10:00:09',
            trade: const {'t': '10:00:05', 'z': '100.0000'},
          ),
        ]),
      )!;
      expect(e.price, 100.0);
      expect(e.displaySource, LiveDisplaySource.lastTrade);
      expect(e.quoteTime, '10:00:05');
    });

    test('🚨 沒有 trade 時沿用今天記住的成交價(不是五檔中價)', () {
      round(responded([row('A', z: '100.0000', t: '10:00:00')]));
      final e = round(
        responded([row('A', b: '102.0000_', a: '103.0000_', t: '10:00:20')]),
      )!;
      expect(e.price, 100.0);
      expect(e.displaySource, LiveDisplaySource.lastTrade);
      expect(e.quoteTime, '10:00:00');
    });

    test('今天還沒有任何成交 → 試撮或五檔', () {
      final e = round(responded([row('A', pz: '99.5000')]))!;
      expect(e.price, 99.5);
      expect(e.displaySource, LiveDisplaySource.trialOrBook);
    });

    test('開高低、成交量(張)、昨收照搬 MIS', () {
      final e = round(
        responded([
          row(
            'A',
            z: '101.0000',
            y: '99.0000',
            extra: const {
              'o': '100.0000',
              'h': '102.0000',
              'l': '98.5000',
              'v': '12345',
            },
          ),
        ]),
      )!;
      expect(
        (e.open, e.high, e.low, e.volumeLots, e.previousClose),
        (100.0, 102.0, 98.5, 12345, 99.0),
      );
    });
  });

  group('閃色', () {
    test('🚨 連續兩輪都是成交且價格改變 → 閃,方向比上一輪', () {
      round(responded([row('A', z: '100.0000')]));
      final up = round(responded([row('A', z: '101.0000')]))!.flash;
      final down = round(responded([row('A', z: '100.5000')]))!.flash;
      expect(up?.up, isTrue);
      expect(down?.up, isFalse);
      expect(down!.id, isNot(up!.id));
    });

    test('價格沒變不閃', () {
      round(responded([row('A', z: '100.0000')]));
      expect(round(responded([row('A', z: '101.0000')]))!.flash, isNotNull);
      expect(round(responded([row('A', z: '101.0000')]))!.flash, isNull);
    });

    test('閃色只活一輪:沒被請求的那檔下一輪也清掉', () {
      round(
        responded([row('A', z: '100.0000'), row('B', z: '50.0000')]),
        requested: const ['A', 'B'],
      );
      round(
        responded([row('A', z: '101.0000'), row('B', z: '50.0000')]),
        requested: const ['A', 'B'],
      );
      expect(book.entries['A']!.flash, isNotNull);
      round(responded([row('B', z: '50.0000')]), requested: const ['B']);
      expect(book.entries['A']!.flash, isNull);
    });

    test('🚨 五檔價換成成交價那一下不閃', () {
      round(responded([row('A', b: '99.0000_', a: '100.0000_')]));
      expect(round(responded([row('A', z: '101.0000')]))!.flash, isNull);
    });

    test('最後成交與鎖住也算成交類', () {
      round(responded([row('A', z: '100.0000')]));
      final lastTrade = round(
        responded([
          row(
            'A',
            b: '100.0000_',
            a: '101.0000_',
            trade: const {'t': '10:00:03', 'z': '100.5000'},
          ),
        ]),
      )!;
      expect(lastTrade.flash?.up, isTrue);
      final locked = round(
        responded([row('A', b: '0.0000_110.0000_', u: '110.0000')]),
      )!;
      expect(locked.flash?.up, isTrue);
    });

    test('🚨 中間隔一輪沒抓到(批次失敗)→ 不閃', () {
      round(responded([row('A', z: '100.0000')]));
      round(failed({'A'}));
      expect(round(responded([row('A', z: '101.0000')]))!.flash, isNull);
    });

    test('🚨 畫面剛恢復登記的第一輪不閃', () {
      round(
        responded([row('A', z: '100.0000'), row('B', z: '50.0000')]),
        requested: const ['A', 'B'],
      );
      round(responded([row('B', z: '50.0000')]), requested: const ['B']);
      round(
        responded([row('A', z: '101.0000'), row('B', z: '50.0000')]),
        requested: const ['A', 'B'],
      );
      expect(book.entries['A']!.flash, isNull);
    });

    test('App 重新可見(forgetLastRound)後第一輪不閃', () {
      round(responded([row('A', z: '100.0000')]));
      book.forgetLastRound();
      expect(round(responded([row('A', z: '101.0000')]))!.flash, isNull);
    });
  });

  group('一輪的結果與卡片狀態', () {
    test('🚨 至少一筆今天的報價 → success;失敗批標 batchFailed、有回應沒報價標 noQuote', () {
      final outcome = book.apply(
        QuoteBatchReport(
          quotes: IntradayQuote.parseResponse({
            'rtcode': '0000',
            'msgArray': [row('A', z: '100.0000')],
          }),
          errors: const ['DioException.connectionTimeout: 模擬'],
          respondedSymbols: const {'A', 'B'},
          failedSymbols: const {'C'},
        ),
        requested: const ['A', 'B', 'C'],
        now: at(10, 0, 5),
        afterClose: false,
      );
      expect(outcome, RoundOutcome.success);
      expect(book.symbolStatus, {
        'A': LiveSymbolStatus.ok,
        'B': LiveSymbolStatus.noQuote,
        'C': LiveSymbolStatus.batchFailed,
      });
      expect(book.latestResponseHadToday, isTrue);
    });

    test('🚨 有回應但日期全不是今天 → respondedNoToday,不顯示、卡片標無報價', () {
      final outcome = book.apply(
        responded([row('A', z: '100.0000', d: '20261005')]),
        requested: const ['A'],
        now: at(9, 0, 3),
        afterClose: false,
      );
      expect(outcome, RoundOutcome.respondedNoToday);
      expect(book.entries, isEmpty);
      expect(book.symbolStatus['A'], LiveSymbolStatus.noQuote);
      expect(book.latestResponseHadToday, isFalse);
    });

    test('🚨 列全被解析丟掉(暫停交易)仍是 respondedNoToday', () {
      final outcome = book.apply(
        responded([row('A')]),
        requested: const ['A'],
        now: at(10, 0, 5),
        afterClose: false,
      );
      expect(outcome, RoundOutcome.respondedNoToday);
      expect(book.symbolStatus['A'], LiveSymbolStatus.noQuote);
    });

    test('全部批次失敗 → failed;已有的價格留著(卡片標報價暫停)', () {
      round(responded([row('A', z: '100.0000')]));
      final outcome = book.apply(
        failed({'A'}),
        requested: const ['A'],
        now: at(10, 0, 20),
        afterClose: false,
      );
      expect(outcome, RoundOutcome.failed);
      expect(book.entries['A']!.price, 100.0);
      expect(book.symbolStatus['A'], LiveSymbolStatus.batchFailed);
      expect(
        book.latestResponseHadToday,
        isTrue,
        reason: '失敗不改「最近一次有回應」的判斷',
      );
    });

    test('latestQuoteTime 取本輪各筆 t 的最大值,格式不符的不算', () {
      round(
        responded([
          row('A', z: '1.0000', t: '10:00:05'),
          row('B', z: '1.0000', t: '10:00:12'),
          row('C', z: '1.0000', t: '9:9'),
        ]),
        requested: const ['A', 'B', 'C'],
      );
      expect(book.latestQuoteTime, '10:00:12');
    });

    test('請求清單以外的報價不收', () {
      round(responded([row('A', z: '1.0000'), row('X', z: '2.0000')]));
      expect(book.entries.keys, ['A']);
    });
  });

  group('收盤後逐檔', () {
    QuoteBatchReport notClosing() =>
        responded([row('A', b: '99.5000_', a: '100.5000_', t: '13:29:40')]);

    test('🚨 拿到收盤報價就不再抓', () {
      book.apply(
        responded([row('A', z: '100.0000', t: '13:30:00')]),
        requested: const ['A'],
        now: at(13, 31),
        afterClose: true,
      );
      expect(book.entries['A']!.isClosingQuote, isTrue);
      expect(book.pendingAfterClose(const ['A']), isEmpty);
      expect(book.dueAfterClose(const ['A'], at(13, 40)), isEmpty);
    });

    test('🚨 有回應但不是收盤報價:每分鐘一次,第 10 次後停', () {
      var now = at(13, 31);
      for (var i = 0; i < 10; i++) {
        expect(book.dueAfterClose(const ['A'], now), ['A'], reason: '第 ${i + 1} 次');
        book.apply(notClosing(), requested: const ['A'], now: now, afterClose: true);
        expect(
          book.dueAfterClose(const ['A'], now.add(const Duration(seconds: 59))),
          isEmpty,
          reason: '未滿 1 分鐘',
        );
        now = now.add(const Duration(minutes: 1));
      }
      expect(book.dueAfterClose(const ['A'], now), isEmpty);
      expect(book.pendingAfterClose(const ['A']), isEmpty);
    });

    test('暫停交易(列被丟掉)也計入嘗試', () {
      for (var i = 0; i < 10; i++) {
        book.apply(
          responded([row('A')]),
          requested: const ['A'],
          now: at(13, 31 + i),
          afterClose: true,
        );
      }
      expect(book.pendingAfterClose(const ['A']), isEmpty);
    });

    test('🚨 網路失敗不計入 10 次', () {
      for (var i = 0; i < 12; i++) {
        book.apply(
          failed({'A'}),
          requested: const ['A'],
          now: at(13, 31 + i),
          afterClose: true,
        );
      }
      expect(book.pendingAfterClose(const ['A']), ['A']);
      expect(book.dueAfterClose(const ['A'], at(13, 43)), ['A']);
    });

    test('盤中的回合不計收盤後嘗試', () {
      for (var i = 0; i < 12; i++) {
        round(notClosing());
      }
      expect(book.pendingAfterClose(const ['A']), ['A']);
    });
  });

  group('換日', () {
    test('🚨 App 開著過夜:隔天 rollDay 清空所有記憶', () {
      book.apply(
        responded([row('A', z: '100.0000', t: '13:30:00')]),
        requested: const ['A'],
        now: at(13, 31),
        afterClose: true,
      );
      expect(book.rollDay(DateTime(2026, 10, 7, 8, 30)), isTrue);
      expect(book.entries, isEmpty);
      expect(book.symbolStatus, isEmpty);
      expect(book.latestResponseHadToday, isNull);
      expect(book.latestQuoteTime, isNull);
      expect(book.pendingAfterClose(const ['A']), ['A']);
    });

    test('同一天 rollDay 不清', () {
      round(responded([row('A', z: '100.0000')]));
      expect(book.rollDay(at(12, 0)), isFalse);
      expect(book.entries, hasLength(1));
    });

    test('🚨 記住的成交價也清掉:隔天沒成交時顯示五檔,不沿用昨天的成交', () {
      round(responded([row('A', z: '100.0000')]));
      book.apply(
        responded([row('A', b: '102.0000_', a: '103.0000_', d: '20261007')]),
        requested: const ['A'],
        now: DateTime(2026, 10, 7, 9, 1, 5),
        afterClose: false,
      );
      expect(book.entries['A']!.displaySource, LiveDisplaySource.trialOrBook);
      expect(book.entries['A']!.price, 102.5);
    });
  });
}
```

- [ ] **Step 2: 確認紅燈**

Run: `flutter test test/domain/services/live_quote/live_quote_book_test.dart`
Expected: 編譯失敗（`live_quote_book.dart` 不存在）

- [ ] **Step 3: 實作**

建立 `lib/domain/services/live_quote/live_quote_book.dart`：

```dart
import 'package:daredevil/data/models/twse/intraday_quote.dart';
import 'package:daredevil/data/remote/intraday_quote_client.dart';
import 'package:daredevil/domain/models/live_quote.dart';
import 'package:daredevil/domain/services/live_quote/live_quote_schedule.dart';

/// 一輪的結果(spec §3)
enum RoundOutcome {
  /// 至少拿到 1 筆今天的報價
  success,

  /// 有回應,但沒有任何今天的報價(開盤頭幾秒、日曆漏標的停市日、列全被
  /// 解析丟掉)。不算網路失敗、不退避
  respondedNoToday,

  /// 沒有任何一批有回應
  failed,
}

/// 報價中心的記帳本(純邏輯,不碰網路與時鐘;2026-10-06)。
///
/// 每一輪把 client 的逐批結果套進來,算出各檔的顯示價、顯示來源、閃色、
/// 卡片狀態,以及收盤後逐檔的嘗試次數。所有記憶都以「今天」為範圍,換日
/// 由 [rollDay] 清空。
class LiveQuoteBook {
  DateTime? _day;
  final Map<String, LiveQuoteEntry> _entries = {};
  final Map<String, LiveSymbolStatus> _status = {};

  /// 今天記到的最後成交價(含鎖住價)與時間
  final Map<String, ({double price, String? time})> _lastTraded = {};
  final Map<String, ({int attempts, DateTime lastAttemptAt})> _afterClose = {};

  /// 上一輪拿到今天報價的代號(閃色要連續兩輪都有)
  Set<String> _fetchedLastRound = {};
  int _flashSeq = 0;
  bool? _latestResponseHadToday;
  String? _latestQuoteTime;

  Map<String, LiveQuoteEntry> get entries => Map.unmodifiable(_entries);
  Map<String, LiveSymbolStatus> get symbolStatus => Map.unmodifiable(_status);

  /// 最近一次有回應的一輪有沒有今天的報價;還沒有任何回應為 null
  bool? get latestResponseHadToday => _latestResponseHadToday;

  /// 最近一次成功的一輪中,各筆報價時間的最大值
  String? get latestQuoteTime => _latestQuoteTime;

  /// 日期變了就清空所有記憶(App 開著過夜)。回傳是否清掉了前一天的資料
  bool rollDay(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    if (_day == today) return false;
    final hadDay = _day != null;
    _day = today;
    _entries.clear();
    _status.clear();
    _lastTraded.clear();
    _afterClose.clear();
    _fetchedLastRound = {};
    _latestResponseHadToday = null;
    _latestQuoteTime = null;
    return hadDay;
  }

  /// App 重新可見:下一輪不閃色(拿來比較的是隱藏前的價格)
  void forgetLastRound() => _fetchedLastRound = {};

  /// 收盤後 [candidates] 中還要抓的代號(保持輸入順序)
  List<String> pendingAfterClose(Iterable<String> candidates) => [
    for (final s in candidates)
      if (LiveQuoteSchedule.afterClosePending(
        hasClosingQuote: _entries[s]?.isClosingQuote ?? false,
        attempts: _afterClose[s]?.attempts ?? 0,
      ))
        s,
  ];

  /// 收盤後 [candidates] 中現在該抓的代號(保持輸入順序)
  List<String> dueAfterClose(Iterable<String> candidates, DateTime now) => [
    for (final s in candidates)
      if (LiveQuoteSchedule.afterCloseDue(
        hasClosingQuote: _entries[s]?.isClosingQuote ?? false,
        attempts: _afterClose[s]?.attempts ?? 0,
        lastAttemptAt: _afterClose[s]?.lastAttemptAt,
        now: now,
      ))
        s,
  ];

  /// 套用一輪的結果。[requested] 是這一輪送出的代號;[afterClose] 為收盤後
  /// 的逐檔抓取(要記嘗試次數)。
  RoundOutcome apply(
    QuoteBatchReport report, {
    required Iterable<String> requested,
    required DateTime now,
    required bool afterClose,
  }) {
    rollDay(now);
    final today = DateTime(now.year, now.month, now.day);
    // 閃色只活一輪
    for (final e in _entries.entries.toList()) {
      if (e.value.flash != null) _entries[e.key] = e.value.withoutFlash();
    }

    final fetchedThisRound = <String>{};
    String? maxTime;
    for (final symbol in requested) {
      final quote = report.quotes[symbol];
      final date = quote?.date;
      if (quote != null && date != null && date == today) {
        _entries[symbol] = _display(symbol, quote, today);
        _status[symbol] = LiveSymbolStatus.ok;
        fetchedThisRound.add(symbol);
        if (_later(quote.time, maxTime)) maxTime = quote.time;
      } else {
        _status[symbol] = report.failedSymbols.contains(symbol)
            ? LiveSymbolStatus.batchFailed
            : LiveSymbolStatus.noQuote;
      }
      if (afterClose) _recordAfterCloseAttempt(symbol, report, now);
    }
    _fetchedLastRound = fetchedThisRound;

    if (fetchedThisRound.isNotEmpty) {
      _latestResponseHadToday = true;
      _latestQuoteTime = maxTime;
      return RoundOutcome.success;
    }
    if (requested.any(report.respondedSymbols.contains)) {
      _latestResponseHadToday = false;
      return RoundOutcome.respondedNoToday;
    }
    return RoundOutcome.failed;
  }

  LiveQuoteEntry _display(String symbol, IntradayQuote q, DateTime today) {
    final pick = _pick(symbol, q);
    if (pick.source != LiveDisplaySource.trialOrBook) {
      _lastTraded[symbol] = (price: pick.price, time: pick.time);
    }
    final previous = _entries[symbol];
    LiveQuoteFlash? flash;
    if (previous != null &&
        _fetchedLastRound.contains(symbol) &&
        _flashable(previous.displaySource) &&
        _flashable(pick.source) &&
        pick.price != previous.price) {
      flash = LiveQuoteFlash(id: ++_flashSeq, up: pick.price > previous.price);
    }
    return LiveQuoteEntry(
      symbol: symbol,
      date: today,
      price: pick.price,
      displaySource: pick.source,
      previousClose: q.previousClose,
      quoteTime: pick.time,
      isClosingQuote: LiveQuoteSchedule.isClosingQuote(q, today),
      open: q.open,
      high: q.high,
      low: q.low,
      volumeLots: q.volume,
      limitUp: q.limitUp,
      limitDown: q.limitDown,
      isLimitUpLocked: q.isLimitUpLocked,
      isLimitDownLocked: q.isLimitDownLocked,
      flash: flash,
    );
  }

  /// 顯示價(spec §3,依序)
  ({double price, LiveDisplaySource source, String? time}) _pick(
    String symbol,
    IntradayQuote q,
  ) {
    // 1. 本輪判為鎖住 → 漲停價或跌停價
    final limitUp = q.limitUp;
    if (q.isLimitUpLocked && limitUp != null) {
      return (price: limitUp, source: LiveDisplaySource.locked, time: q.time);
    }
    final limitDown = q.limitDown;
    if (q.isLimitDownLocked && limitDown != null) {
      return (price: limitDown, source: LiveDisplaySource.locked, time: q.time);
    }
    // 2. 本輪有成交價
    if (q.priceSource == QuotePriceSource.trade) {
      return (price: q.price, source: LiveDisplaySource.trade, time: q.time);
    }
    // 3. 本輪有 trade.z
    final lastTrade = q.lastTradePrice;
    if (lastTrade != null) {
      return (
        price: lastTrade,
        source: LiveDisplaySource.lastTrade,
        time: q.lastTradeTime,
      );
    }
    // 4. 今天記到的成交價或鎖住價
    final memory = _lastTraded[symbol];
    if (memory != null) {
      return (
        price: memory.price,
        source: LiveDisplaySource.lastTrade,
        time: memory.time,
      );
    }
    // 5. 試撮或五檔
    return (price: q.price, source: LiveDisplaySource.trialOrBook, time: q.time);
  }

  static bool _flashable(LiveDisplaySource s) =>
      s != LiveDisplaySource.trialOrBook;

  void _recordAfterCloseAttempt(
    String symbol,
    QuoteBatchReport report,
    DateTime now,
  ) {
    final responded = report.respondedSymbols.contains(symbol);
    final closing = _entries[symbol]?.isClosingQuote ?? false;
    final attempts = _afterClose[symbol]?.attempts ?? 0;
    _afterClose[symbol] = (
      // 只計「有回應但不是收盤報價」;網路失敗、限流不計
      attempts: attempts + (responded && !closing ? 1 : 0),
      lastAttemptAt: now,
    );
  }

  /// [a] 是否比 [b] 晚;[a] 格式不符一律 false
  static bool _later(String? a, String? b) {
    final sa = LiveQuoteSchedule.secondsOfDay(a);
    if (sa == null) return false;
    final sb = LiveQuoteSchedule.secondsOfDay(b);
    return sb == null || sa > sb;
  }
}
```

- [ ] **Step 4: 確認通過**

Run: `flutter test test/domain/services/live_quote/`
Expected: 全部 PASS

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 5: 記錄進度**（不 commit）

---

### Task 6: 報價中心 LiveQuoteCenter

**Files:**
- Create: `lib/presentation/providers/live_quote_provider.dart`
- Modify: `lib/data/remote/intraday_quote_client.dart`（加兩個 `@visibleForTesting` getter）
- Test: `test/presentation/providers/live_quote_provider_test.dart`

**Interfaces:**
- Consumes:
  - Task 2：`IntradayQuoteClient`、`fetchQuotesDetailed`、`QuoteBatchReport`、`MarketClientMixin.createDio`。
  - Task 3：`LiveQuoteParams`、`LiveQuoteSchedule`、`MarketPhase`。
  - Task 4：`LiveQuoteEntry`、`LiveSymbolStatus`。
  - Task 5：`LiveQuoteBook`、`RoundOutcome`。
  - 既有：`appClockProvider`（`lib/presentation/providers/providers.dart`）、`AppLogger`。
- Produces:
  - `class LiveQuoteRegistration { String symbol; String market; bool hasOfficialToday = false; }`：const 建構子，實作 `==`／`hashCode`。
  - `class LiveQuoteState`：`entries`、`symbolStatus`、`stalled`、`rateLimitedUntil`、`lastRespondedAt`、`latestResponseHadToday`、`latestQuoteTime`。
  - `class LiveQuoteCenter extends Notifier<LiveQuoteState>`：
    - `register(Object owner, List<LiveQuoteRegistration> entries)`、`unregister(Object owner)`、`setAppVisible(bool visible)`；
    - `@visibleForTesting Map<String, String> get registeredMarkets`。
  - `liveQuoteCenterProvider`（`NotifierProvider`，非 autoDispose）、`liveQuoteClientProvider`（`Provider<IntradayQuoteClient>`，onDispose 關閉）。
  - `IntradayQuoteClient` 的 `@visibleForTesting Dio get dio`、`@visibleForTesting bool get logsBatchErrors`。

- [ ] **Step 1: 寫失敗測試**

建立 `test/presentation/providers/live_quote_provider_test.dart`：

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/constants/live_quote_params.dart';
import 'package:daredevil/core/constants/market_codes.dart';
import 'package:daredevil/core/utils/clock.dart';
import 'package:daredevil/core/utils/logger.dart';
import 'package:daredevil/data/remote/intraday_quote_client.dart';
import 'package:daredevil/domain/models/live_quote.dart';
import 'package:daredevil/presentation/providers/live_quote_provider.dart';
import 'package:daredevil/presentation/providers/providers.dart';

/// 報價中心(2026-10-06,spec §3、§8、驗證 4)。
///
/// 真的 IntradayQuoteClient 接假 HTTP adapter、假時鐘、fakeAsync:請求字串、
/// 批數、節流、暫停、退避都量在 HTTP 那一層。時鐘 = 起點 + 經過時間(+ 跳動)。
void main() {
  late List<String> crumbs; // category 為 LiveQuote 的 breadcrumb
  late List<String> misCrumbs; // category 為 MIS(client 逐批 warning)
  late List<Object> captured;

  setUp(() {
    crumbs = [];
    misCrumbs = [];
    captured = [];
    AppLogger.setSentryDelegates(
      breadcrumb: (message, category, level, data) {
        if (category == 'LiveQuote') crumbs.add(message);
        if (category == 'MIS') misCrumbs.add(message);
      },
      capture: (error, stackTrace, tag, message) => captured.add(error),
    );
  });
  tearDown(() => AppLogger.setSentryDelegates());

  const tsmc = LiveQuoteRegistration(symbol: '2330', market: MarketCode.twse);
  final weekdayMorning = DateTime(2026, 10, 6, 10, 1); // 週二 10:01:00
  final afterCloseStart = DateTime(2026, 10, 6, 13, 31);
  List<Duration> secs(List<int> s) => [for (final x in s) Duration(seconds: x)];

  test('🚨 報價中心的 client:短逾時、不逐批記 warning', () {
    final container = ProviderContainer();
    final client = container.read(liveQuoteClientProvider);
    expect(client.dio.options.connectTimeout, LiveQuoteParams.connectTimeout);
    expect(client.dio.options.receiveTimeout, LiveQuoteParams.receiveTimeout);
    expect(client.logsBatchErrors, isFalse);
    container.dispose();
  });

  group('何時抓', () {
    test('只抓登記的聯集;登記後等下一拍才發', () {
      fakeAsync((async) {
        final h = _Harness(async, weekdayMorning);
        h.center.register('A', const [tsmc]);
        h.center.register('B', const [
          tsmc,
          LiveQuoteRegistration(symbol: '6538', market: MarketCode.tpex),
        ]);
        async.flushMicrotasks();
        expect(h.requests, isEmpty, reason: '登記不會立刻觸發請求');

        h.elapse(const Duration(seconds: 1));
        expect(h.requests, hasLength(1));
        expect(h.requests.single.exCh, ['tse_2330.tw', 'otc_6538.tw']);
        h.dispose();
      });
    });

    test('🚨 大盤指數硬對應市場別(不論登記時帶什麼)', () {
      fakeAsync((async) {
        final h = _Harness(async, weekdayMorning);
        h.center.register('index', const [
          LiveQuoteRegistration(
            symbol: LiveQuoteParams.twseIndexSymbol,
            market: MarketCode.tpex,
          ),
          LiveQuoteRegistration(
            symbol: LiveQuoteParams.tpexIndexSymbol,
            market: MarketCode.twse,
          ),
        ]);
        h.elapse(const Duration(seconds: 1));
        expect(h.requests.single.exCh, ['tse_t00.tw', 'otc_o00.tw']);
        h.dispose();
      });
    });

    test('沒有登記、週六、國慶補假、盤前都不發請求', () {
      for (final (label, start, register) in [
        ('沒有登記', weekdayMorning, false),
        ('週六', DateTime(2026, 10, 3, 10, 1), true),
        ('國慶補假', DateTime(2026, 10, 9, 10, 1), true),
        ('盤前', DateTime(2026, 10, 6, 8, 30), true),
      ]) {
        fakeAsync((async) {
          final h = _Harness(async, start);
          if (register) h.center.register('A', const [tsmc]);
          h.elapse(const Duration(minutes: 20));
          expect(h.requests, isEmpty, reason: label);
          h.dispose();
        });
      }
    });

    test('盤前登記 → 09:00 起抓(先讓過 CLI 的 10 秒)', () {
      fakeAsync((async) {
        final h = _Harness(async, DateTime(2026, 10, 6, 8, 59, 50));
        h.center.register('A', const [tsmc]);
        h.elapse(const Duration(seconds: 19)); // 到 09:00:09
        expect(h.requests, isEmpty);
        h.elapse(const Duration(seconds: 1)); // 09:00:10
        expect(h.sentAt, secs([20]));
        h.dispose();
      });
    });

    test('🚨 App 隱藏時不抓;回到可見 → 下一拍照常', () {
      fakeAsync((async) {
        final h = _Harness(async, weekdayMorning);
        h.center.register('A', const [tsmc]);
        h.center.setAppVisible(false);
        h.elapse(const Duration(minutes: 2));
        expect(h.requests, isEmpty);
        h.center.setAppVisible(true);
        h.elapse(const Duration(seconds: 1));
        expect(h.requests, hasLength(1));
        h.dispose();
      });
    });

    test('🚨 上一個請求還沒回來 → 跳過,不疊加', () {
      fakeAsync((async) {
        final h = _Harness(async, weekdayMorning)
          ..respond = (exCh, now) => Future.delayed(
            const Duration(milliseconds: 29500),
            () => _tradeEach(exCh, now),
          );
        h.center.register('A', const [tsmc]);
        h.elapse(const Duration(seconds: 30));
        expect(h.sentAt, secs([1]), reason: '請求還在路上時不發第二個');
        h.elapse(const Duration(seconds: 2));
        expect(h.sentAt, secs([1, 31]), reason: '30.5 秒回來,下一拍補發');
        h.dispose();
      });
    });

    test('🚨 快速登記與取消(切分頁)不造成連發', () {
      fakeAsync((async) {
        final h = _Harness(async, weekdayMorning);
        h.center.register('A', const [tsmc]);
        h.elapse(const Duration(seconds: 1));
        for (var i = 0; i < 5; i++) {
          h.center.unregister('A');
          h.elapse(const Duration(milliseconds: 100));
          h.center.register('A', const [tsmc]);
          h.elapse(const Duration(milliseconds: 100));
        }
        h.elapse(const Duration(milliseconds: 14500)); // 到第 16.5 秒
        expect(h.requests, hasLength(1));
        h.elapse(const Duration(milliseconds: 500)); // 第 17 秒
        expect(h.requests, hasLength(2), reason: '距上一輪滿 15 秒才發');
        h.dispose();
      });
    });
  });

  group('請求量', () {
    test('2 批:一輪內兩批相隔 2 秒,15 秒一輪', () {
      fakeAsync((async) {
        final h = _Harness(async, weekdayMorning);
        h.center.register('A', [
          for (var i = 0; i < 40; i++)
            LiveQuoteRegistration(symbol: '${2000 + i}', market: MarketCode.twse),
        ]);
        h.elapse(const Duration(seconds: 20));
        expect(h.sentAt, secs([1, 3, 16, 18]));
        expect([for (final r in h.requests) r.exCh.length], [35, 5, 35, 5]);
        h.dispose();
      });
    });

    for (final batches in const [3, 4, 10]) {
      test('🚨 $batches 批:任何 60 秒內 ≤ 8 個請求、相鄰 ≥ 2 秒、每檔都輪得到', () {
        fakeAsync((async) {
          final h = _Harness(async, weekdayMorning);
          final symbols = [for (var i = 0; i < batches * 35; i++) '${1000 + i}'];
          h.center.register('A', [
            for (final s in symbols)
              LiveQuoteRegistration(symbol: s, market: MarketCode.twse),
          ]);
          h.elapse(const Duration(minutes: 6));

          final at = h.sentAt;
          for (var i = 0; i < at.length; i++) {
            final window = at
                .where((t) => t >= at[i] && t < at[i] + const Duration(minutes: 1))
                .length;
            expect(
              window,
              lessThanOrEqualTo(LiveQuoteParams.maxRequestsPerMinute),
              reason: '從 ${at[i]} 起的 60 秒',
            );
            if (i > 0) {
              expect(at[i] - at[i - 1], greaterThanOrEqualTo(LiveQuoteParams.minRequestGap));
            }
          }
          expect({for (final r in h.requests) ...r.exCh.map(_symbolOf)}, symbols.toSet());
          h.dispose();
        });
      });
    }

    test('🚨 每 5 分鐘整點後 10 秒內不發請求(讓給盤中提醒 CLI)', () {
      fakeAsync((async) {
        final h = _Harness(async, DateTime(2026, 10, 6, 10, 4));
        h.center.register('A', const [tsmc]);
        h.elapse(const Duration(minutes: 7));
        final times = [for (final r in h.requests) r.at];
        expect(times.where((t) => t.minute % 5 == 0 && t.second < 10), isEmpty);
        expect(times, contains(DateTime(2026, 10, 6, 10, 5, 10)), reason: '窗口一過就補發');
        h.dispose();
      });
    });
  });

  group('結果分類、暫停與退避', () {
    test('🚨 rtcode 非 0000 算失敗;距上一次有回應超過 60 秒才判暫停', () {
      fakeAsync((async) {
        final h = _Harness(async, weekdayMorning)
          ..respond = (_, _) async => '{"rtcode":"5000"}';
        h.center.register('A', const [tsmc]);
        h.elapse(const Duration(seconds: 61)); // 從第 1 拍起計 60 秒
        expect(h.state.stalled, isFalse);
        expect(h.state.symbolStatus['2330'], LiveSymbolStatus.batchFailed);
        h.elapse(const Duration(seconds: 1));
        expect(h.state.stalled, isTrue);
        h.dispose();
      });
    });

    test('🚨 連續多輪日期不是今天 → 「今天尚無報價」,不變成網路暫停、不退避', () {
      fakeAsync((async) {
        final h = _Harness(async, weekdayMorning)
          ..respond = (exCh, now) async => _mis([
            for (final e in exCh) _row(_symbolOf(e), now, d: '20261005'),
          ]);
        h.center.register('A', const [tsmc]);
        h.elapse(const Duration(minutes: 3));
        expect(h.requests, hasLength(12), reason: '照 15 秒節奏,沒有退避');
        expect(h.state.stalled, isFalse);
        expect(h.state.latestResponseHadToday, isFalse);
        expect(h.state.entries, isEmpty);
        expect(h.state.symbolStatus['2330'], LiveSymbolStatus.noQuote);
        h.dispose();
      });
    });

    test('🚨 只登記一檔而那檔被解析丟掉(暫停交易)→ 卡片標無報價、不退避', () {
      fakeAsync((async) {
        final h = _Harness(async, weekdayMorning)
          ..respond = (exCh, now) async => _mis([
            {'c': '2330', 'z': '-', 'pz': '-', 'd': _ymd(now), 't': _hms(now)},
          ]);
        h.center.register('A', const [tsmc]);
        h.elapse(const Duration(minutes: 2));
        expect(h.requests, hasLength(8));
        expect(h.state.stalled, isFalse);
        expect(h.state.symbolStatus['2330'], LiveSymbolStatus.noQuote);
        h.dispose();
      });
    });

    test('🚨 暫停後每次失敗間隔加倍,最長 2 分鐘', () {
      fakeAsync((async) {
        final h = _Harness(async, weekdayMorning)
          ..respond = (_, _) async => throw const _NetworkDown();
        h.center.register('A', const [tsmc]);
        h.elapse(const Duration(seconds: 420));
        // 第 61 秒那輪送出時計時剛好 60 秒,還不算暫停;第 62 秒起暫停,
        // 之後間隔 15 → 30 → 60 → 120 → 120
        expect(h.sentAt, secs([1, 16, 31, 46, 61, 76, 106, 166, 286, 406]));
        h.dispose();
      });
    });

    test('恢復後解除暫停、回到 15 秒節奏', () {
      fakeAsync((async) {
        final h = _Harness(async, weekdayMorning)
          ..respond = (_, _) async => throw const _NetworkDown();
        h.center.register('A', const [tsmc]);
        h.elapse(const Duration(seconds: 63));
        expect(h.state.stalled, isTrue);
        h.respond = _tradeEach;
        h.elapse(const Duration(seconds: 29)); // 到第 92 秒
        expect(h.sentAt, secs([1, 16, 31, 46, 61, 76, 91]));
        expect(h.state.stalled, isFalse);
        expect(h.state.lastRespondedAt, weekdayMorning.add(const Duration(seconds: 91)));
        h.dispose();
      });
    });

    test('🚨 限流:停 5 分鐘,之後只發 1 個試探請求;試探成功才恢復整輪', () {
      fakeAsync((async) {
        final h = _Harness(async, weekdayMorning);
        h.respond = (exCh, now) async {
          if (h.requests.length == 1) {
            return '<!doctype html><html>Too many requests</html>';
          }
          return _tradeEach(exCh, now);
        };
        h.center.register('A', [
          for (var i = 0; i < 40; i++)
            LiveQuoteRegistration(symbol: '${2000 + i}', market: MarketCode.twse),
        ]);
        h.elapse(const Duration(seconds: 2));
        expect(h.state.rateLimitedUntil, weekdayMorning.add(const Duration(seconds: 301)));

        h.elapse(const Duration(seconds: 298)); // 到第 300 秒
        expect(h.requests, hasLength(1));
        h.elapse(const Duration(seconds: 1)); // 第 301 秒:試探
        expect(h.requests, hasLength(2));
        expect(h.requests.last.exCh, hasLength(35), reason: '試探只送第一批');
        expect(h.state.rateLimitedUntil, isNull);

        h.elapse(const Duration(seconds: 20));
        expect(h.sentAt, secs([1, 301, 316, 318]), reason: '試探成功後恢復兩批');
        h.dispose();
      });
    });
  });

  group('收盤後', () {
    String notClosing(List<String> exCh, DateTime now) => _mis([
      for (final e in exCh)
        _row(_symbolOf(e), now, z: '-', b: '99.5000_', a: '100.5000_', t: '13:29:40'),
    ]);

    test('🚨 全部拿到收盤報價、不再發請求 → 不會變成暫停', () {
      fakeAsync((async) {
        final h = _Harness(async, afterCloseStart)
          ..respond = (exCh, now) async => _mis([
            for (final e in exCh) _row(_symbolOf(e), now, t: '13:30:00'),
          ]);
        h.center.register('A', const [tsmc]);
        h.elapse(const Duration(minutes: 5));
        expect(h.requests, hasLength(1));
        expect(h.state.entries['2330']!.isClosingQuote, isTrue);
        expect(h.state.stalled, isFalse);
        h.dispose();
      });
    });

    test('14:10 才打開仍會抓(收盤後沒有時間上限)', () {
      fakeAsync((async) {
        final h = _Harness(async, DateTime(2026, 10, 6, 14, 10));
        h.center.register('A', const [tsmc]);
        h.elapse(const Duration(seconds: 9)); // 14:10:00–09 是 CLI 避讓窗
        expect(h.requests, isEmpty);
        h.elapse(const Duration(seconds: 1)); // 14:10:10
        expect(h.requests, hasLength(1));
        h.dispose();
      });
    });

    test('🚨 畫面已有今天正式資料就不抓;任一畫面還沒有就抓;盤後資料寫入後重新登記 → 停', () {
      fakeAsync((async) {
        final h = _Harness(async, afterCloseStart)
          ..respond = (exCh, now) async => notClosing(exCh, now);
        const official = LiveQuoteRegistration(
          symbol: '2330',
          market: MarketCode.twse,
          hasOfficialToday: true,
        );
        h.center.register('A', const [official]);
        h.elapse(const Duration(minutes: 2));
        expect(h.requests, isEmpty);

        h.center.register('B', const [tsmc]);
        h.elapse(const Duration(seconds: 61));
        expect(h.requests, hasLength(2), reason: '收盤報價還沒出來:每分鐘一次');

        h.center.register('B', const [official]);
        h.elapse(const Duration(minutes: 3));
        expect(h.requests, hasLength(2));
        h.dispose();
      });
    });

    test('🚨 拿不到收盤報價:每分鐘一次,10 次後停,之後不判暫停', () {
      fakeAsync((async) {
        final h = _Harness(async, afterCloseStart)
          ..respond = (exCh, now) async => notClosing(exCh, now);
        h.center.register('A', const [tsmc]);
        h.elapse(const Duration(minutes: 20));
        expect(h.requests, hasLength(LiveQuoteParams.afterCloseMaxAttempts));
        expect(h.state.stalled, isFalse);
        h.dispose();
      });
    });

    test('🚨 網路失敗不計入 10 次;還要抓的期間會判暫停', () {
      fakeAsync((async) {
        final h = _Harness(async, afterCloseStart)
          ..respond = (_, _) async => throw const _NetworkDown();
        h.center.register('A', const [tsmc]);
        h.elapse(const Duration(minutes: 30));
        expect(h.requests.length, greaterThan(LiveQuoteParams.afterCloseMaxAttempts));
        expect(h.state.stalled, isTrue);
        h.dispose();
      });
    });
  });

  group('顯示價與閃色(經真的解析)', () {
    test('🚨 本輪 z 為 - 但有 trade.z → 最後成交價;沒有 trade 時沿用記住的成交價', () {
      fakeAsync((async) {
        var round = 0;
        final h = _Harness(async, weekdayMorning)
          ..respond = (exCh, now) async => _mis([
            switch (++round) {
              1 => _row('2330', now, z: '100.0000'),
              2 => _row(
                '2330',
                now,
                z: '-',
                b: '100.5000_',
                a: '101.5000_',
                trade: const {'t': '10:01:15', 'z': '101.0000'},
              ),
              _ => _row('2330', now, z: '-', b: '102.0000_', a: '103.0000_'),
            },
          ]);
        h.center.register('A', const [tsmc]);

        h.elapse(const Duration(seconds: 1));
        expect(h.state.entries['2330']!.price, 100.0);

        h.elapse(const Duration(seconds: 15));
        final second = h.state.entries['2330']!;
        expect(second.price, 101.0);
        expect(second.displaySource, LiveDisplaySource.lastTrade);
        expect(second.quoteTime, '10:01:15');

        h.elapse(const Duration(seconds: 15));
        expect(h.state.entries['2330']!.price, 101.0, reason: '不是五檔中價 102.5');
        h.dispose();
      });
    });

    test('🚨 閃色只在連續兩輪都是成交類且價格改變,方向比上一輪', () {
      fakeAsync((async) {
        const prices = ['100.0000', '101.0000', '101.0000', '100.5000'];
        var round = 0;
        final h = _Harness(async, weekdayMorning)
          ..respond = (exCh, now) async => _mis([_row('2330', now, z: prices[round++])]);
        h.center.register('A', const [tsmc]);
        LiveQuoteFlash? flashAfter(int seconds) {
          h.elapse(Duration(seconds: seconds));
          return h.state.entries['2330']!.flash;
        }

        expect(flashAfter(1), isNull, reason: '第一輪沒有上一輪可比');
        final up = flashAfter(15);
        expect(up?.up, isTrue);
        expect(flashAfter(15), isNull, reason: '價格沒變');
        final down = flashAfter(15);
        expect(down?.up, isFalse);
        expect(down!.id, isNot(up!.id));
        h.dispose();
      });
    });
  });

  group('紀錄', () {
    test('🚨 一段連續失敗只在開始與恢復各記一筆;中心的 client 不逐批記', () {
      fakeAsync((async) {
        final h = _Harness(async, weekdayMorning)
          ..respond = (_, _) async => throw const _NetworkDown();
        h.center.register('A', const [tsmc]);
        h.elapse(const Duration(seconds: 65)); // 1、16、31、46、61 五輪失敗
        h.respond = _tradeEach;
        h.elapse(const Duration(seconds: 15)); // 76 恢復
        expect(crumbs, hasLength(2));
        expect(crumbs.first, contains('即時報價中斷'));
        expect(crumbs.last, contains('連續失敗 5 輪'));
        expect(misCrumbs, isEmpty, reason: 'logBatchErrors: false');
        h.dispose();
      });
    });

    test('🚨 非預期錯誤送 Sentry(帶例外物件),同一段失敗只送一次', () {
      fakeAsync((async) {
        var broken = true;
        final client = _ScriptedClient((batch) async {
          if (broken) throw StateError('解析爆了');
          return QuoteBatchReport(
            quotes: const {},
            errors: const [],
            respondedSymbols: batch.keys.toSet(),
            failedSymbols: const <String>{},
          );
        });
        final h = _Harness(async, weekdayMorning, client: client);
        h.center.register('A', const [tsmc]);
        h.elapse(const Duration(seconds: 50)); // 1、16、31、46 四輪
        expect(captured, hasLength(1));
        expect(captured.single, isA<StateError>());

        broken = false;
        h.elapse(const Duration(seconds: 15)); // 61:有回應 → 這一段結束
        broken = true;
        h.elapse(const Duration(seconds: 15)); // 76:新的一段
        expect(captured, hasLength(2));
        h.dispose();
      });
    });
  });

  group('可見性、睡眠、換日、釋放', () {
    test('🚨 隱藏期間不計暫停時間', () {
      fakeAsync((async) {
        final h = _Harness(async, weekdayMorning)
          ..respond = (_, _) async => throw const _NetworkDown();
        h.center.register('A', const [tsmc]);
        h.elapse(const Duration(seconds: 30));
        h.center.setAppVisible(false);
        h.elapse(const Duration(minutes: 10));
        h.center.setAppVisible(true);
        h.elapse(const Duration(seconds: 20));
        expect(h.state.stalled, isFalse, reason: '可見時累計約 48 秒');
        h.elapse(const Duration(seconds: 15));
        expect(h.state.stalled, isTrue);
        h.dispose();
      });
    });

    test('🚨 電腦睡眠喚醒:時鐘跳 2 小時 → 下一拍照常抓', () {
      fakeAsync((async) {
        final h = _Harness(async, weekdayMorning);
        h.center.register('A', const [tsmc]);
        h.elapse(const Duration(seconds: 20));
        expect(h.requests, hasLength(2));
        h.jump = const Duration(hours: 2);
        h.elapse(const Duration(seconds: 1));
        expect(h.requests, hasLength(3));
        expect(h.requests.last.at, DateTime(2026, 10, 6, 12, 1, 21));
        expect(h.state.stalled, isFalse, reason: '醒來那一輪有回應');
        h.dispose();
      });
    });

    test('🚨 App 開著過夜:隔天第一拍清掉昨天的報價,不當成今天', () {
      fakeAsync((async) {
        final h = _Harness(async, weekdayMorning);
        h.center.register('A', const [tsmc]);
        h.elapse(const Duration(seconds: 1));
        expect(h.state.entries['2330']!.date, DateTime(2026, 10, 6));

        h.jump = const Duration(hours: 23); // 10/7 09:01:02
        h.respond = (_, _) async => throw const _NetworkDown();
        h.elapse(const Duration(seconds: 1));
        expect(h.state.entries, isEmpty);
        expect(h.state.latestResponseHadToday, isNull);
        expect(h.state.stalled, isFalse, reason: '過夜那段不計入暫停時間');
        h.dispose();
      });
    });

    test('🚨 請求途中 dispose → 回來後不碰 state、不留計時器', () {
      fakeAsync((async) {
        final h = _Harness(async, weekdayMorning)
          ..respond = (exCh, now) => Future.delayed(
            const Duration(seconds: 5),
            () => _tradeEach(exCh, now),
          );
        h.center.register('A', const [tsmc]);
        h.elapse(const Duration(seconds: 2));
        h.dispose();
        h.elapse(const Duration(seconds: 10));
        expect(async.periodicTimerCount, 0);
        expect(captured, isEmpty, reason: 'dispose 後不可再讀 ref 或寫 state');
      });
    });
  });
}

class _Clock implements AppClock {
  _Clock(this._now);
  final DateTime Function() _now;

  @override
  DateTime now() => _now();
}

/// 在 fakeAsync 裡建一個報價中心
class _Harness {
  _Harness(this.async, this.t0, {IntradayQuoteClient? client}) {
    container = ProviderContainer(
      overrides: [
        appClockProvider.overrideWithValue(_Clock(now)),
        liveQuoteClientProvider.overrideWithValue(
          client ??
              IntradayQuoteClient(
                dio: Dio()..httpClientAdapter = _MisAdapter(_serve),
                logBatchErrors: false,
              ),
        ),
      ],
    );
  }

  final FakeAsync async;
  final DateTime t0;
  late final ProviderContainer container;

  /// 時鐘跳動(模擬電腦睡眠):加在經過時間之上
  Duration jump = Duration.zero;

  /// 每個請求:送出時刻與 ex_ch 各項(例:tse_2330.tw)
  final requests = <({DateTime at, List<String> exCh})>[];

  /// 回應內容;預設每檔都回一筆當下時間的成交
  Future<String> Function(List<String> exCh, DateTime now) respond =
      _tradeEach;

  DateTime now() => t0.add(async.elapsed + jump);
  LiveQuoteCenter get center => container.read(liveQuoteCenterProvider.notifier);
  LiveQuoteState get state => container.read(liveQuoteCenterProvider);
  List<Duration> get sentAt => [for (final r in requests) r.at.difference(t0)];

  Future<String> _serve(List<String> exCh) {
    requests.add((at: now(), exCh: exCh));
    return respond(exCh, now());
  }

  void elapse(Duration d) => async.elapse(d);
  void dispose() => container.dispose();
}

class _MisAdapter implements HttpClientAdapter {
  _MisAdapter(this.serve);

  final Future<String> Function(List<String> exCh) serve;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final exCh = options.uri.queryParameters['ex_ch']!.split('|');
    return ResponseBody.fromString(
      await serve(exCh),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _ScriptedClient extends IntradayQuoteClient {
  _ScriptedClient(this.script) : super(dio: Dio(), logBatchErrors: false);

  final Future<QuoteBatchReport> Function(Map<String, String> batch) script;

  @override
  Future<QuoteBatchReport> fetchQuotesDetailed(Map<String, String> markets) =>
      script(markets);
}

class _NetworkDown implements Exception {
  const _NetworkDown();

  @override
  String toString() => 'NetworkDown: 模擬斷線';
}

String _two(int v) => v.toString().padLeft(2, '0');
String _ymd(DateTime t) => '${t.year}${_two(t.month)}${_two(t.day)}';
String _hms(DateTime t) =>
    '${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}';

/// tse_2330.tw → 2330
String _symbolOf(String exCh) => exCh.substring(4, exCh.length - 3);

String _mis(List<Map<String, Object?>> rows) =>
    jsonEncode({'rtcode': '0000', 'msgArray': rows});

Map<String, Object?> _row(
  String c,
  DateTime now, {
  String z = '100.0000',
  String y = '99.0000',
  String? d,
  String? t,
  String b = '-',
  String a = '-',
  Map<String, String>? trade,
}) => {
  'c': c,
  'z': z,
  'pz': '-',
  'y': y,
  'd': d ?? _ymd(now),
  't': t ?? _hms(now),
  'b': b,
  'a': a,
  if (trade != null) 'trade': trade,
};

Future<String> _tradeEach(List<String> exCh, DateTime now) async =>
    _mis([for (final e in exCh) _row(_symbolOf(e), now)]);
```

- [ ] **Step 2: 確認紅燈**

Run: `flutter test test/presentation/providers/live_quote_provider_test.dart`
Expected: 編譯失敗（`live_quote_provider.dart` 不存在；`dio`、`logsBatchErrors` 不是 `IntradayQuoteClient` 的成員）

- [ ] **Step 3: 實作**

1. `lib/data/remote/intraday_quote_client.dart`：import 區加 `import 'package:meta/meta.dart';`，`_logBatchErrors` 欄位之後加：

```dart

  @visibleForTesting
  Dio get dio => _dio;

  @visibleForTesting
  bool get logsBatchErrors => _logBatchErrors;
```

2. 建立 `lib/presentation/providers/live_quote_provider.dart`：

```dart
import 'dart:async';

import 'package:flutter/foundation.dart' show immutable, visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:daredevil/core/constants/api_endpoints.dart';
import 'package:daredevil/core/constants/live_quote_params.dart';
import 'package:daredevil/core/constants/market_codes.dart';
import 'package:daredevil/core/exceptions/app_exception.dart';
import 'package:daredevil/core/utils/logger.dart';
import 'package:daredevil/data/models/twse/intraday_quote.dart';
import 'package:daredevil/data/remote/intraday_quote_client.dart';
import 'package:daredevil/data/remote/market_client_mixin.dart';
import 'package:daredevil/domain/models/live_quote.dart';
import 'package:daredevil/domain/services/live_quote/live_quote_book.dart';
import 'package:daredevil/domain/services/live_quote/live_quote_schedule.dart';
import 'package:daredevil/presentation/providers/providers.dart';

/// 畫面登記的一檔
@immutable
class LiveQuoteRegistration {
  const LiveQuoteRegistration({
    required this.symbol,
    required this.market,
    this.hasOfficialToday = false,
  });

  final String symbol;

  /// 市場別(`MarketCode.twse`／`MarketCode.tpex`),個股取自股票主檔;
  /// 大盤指數由報價中心硬對應,這裡帶什麼都不影響
  final String market;

  /// 這個畫面這一檔是否已有今天的正式資料(收盤後逐檔判斷要不要抓)
  final bool hasOfficialToday;

  @override
  bool operator ==(Object other) =>
      other is LiveQuoteRegistration &&
      other.symbol == symbol &&
      other.market == market &&
      other.hasOfficialToday == hasOfficialToday;

  @override
  int get hashCode => Object.hash(symbol, market, hasOfficialToday);
}

/// 報價中心對外的狀態(第 2、3 段的畫面讀它)
@immutable
class LiveQuoteState {
  const LiveQuoteState({
    this.entries = const {},
    this.symbolStatus = const {},
    this.stalled = false,
    this.rateLimitedUntil,
    this.lastRespondedAt,
    this.latestResponseHadToday,
    this.latestQuoteTime,
  });

  /// 各檔今天的即時報價(換日清空;顯示前一律經 `LiveQuoteMerge` 檢查日期)
  final Map<String, LiveQuoteEntry> entries;

  /// 各檔最近一次被請求的結果(卡片的「報價暫停」「無報價」)
  final Map<String, LiveSymbolStatus> symbolStatus;

  /// 報價暫停(網路):計時中,距上一次有回應的一輪超過門檻
  final bool stalled;

  /// 報價暫停(證交所限流):到這個時刻後試探;試探完成前不清
  final DateTime? rateLimitedUntil;

  /// 上一次有回應的一輪(頁首「最後更新」)
  final DateTime? lastRespondedAt;

  /// 最近一次有回應的一輪有沒有今天的報價;還沒有回應為 null
  /// (頁首「證交所今天尚無報價」)
  final bool? latestResponseHadToday;

  /// 最近一次成功的一輪中,各筆報價時間的最大值(頁首盤中顯示)
  final String? latestQuoteTime;
}

/// 報價中心專用 client:短逾時(MIS 卡住時 5 秒／8 秒就放棄、下一輪再來),
/// 不逐批記 warning(失敗由中心統一記)
final liveQuoteClientProvider = Provider<IntradayQuoteClient>((ref) {
  final client = IntradayQuoteClient(
    dio: MarketClientMixin.createDio(
      ApiEndpoints.twseMisIntraday,
      connectTimeout: LiveQuoteParams.connectTimeout,
      receiveTimeout: LiveQuoteParams.receiveTimeout,
    ),
    logBatchErrors: false,
  );
  ref.onDispose(client.close);
  return client;
});

final liveQuoteCenterProvider =
    NotifierProvider<LiveQuoteCenter, LiveQuoteState>(LiveQuoteCenter.new);

/// 盤中即時報價中心(全 App 唯一,2026-10-06)。
///
/// 畫面以 `LiveQuoteScope` 登記要看的股票;中心每秒一拍,在「有登記、App
/// 可見、排程說該抓」時逐批發請求(任何 60 秒內 ≤ 8 個、相鄰 ≥ 2 秒、
/// 避開 CLI),結果經 [LiveQuoteBook] 算成各檔顯示價放進 state。只存在
/// 記憶體,不寫資料庫;任何錯誤都不影響盤後資料的顯示。
///
/// 🚨 [register]／[unregister]／[setAppVisible] 會在 widget 的
/// didChangeDependencies／dispose(build 期間)被呼叫,**不可寫 state**
/// ——Riverpod 不允許 build 期間修改 provider。它們只改內部欄位與計時器,
/// 結果等下一拍才反映。
class LiveQuoteCenter extends Notifier<LiveQuoteState> {
  static const String _tag = 'LiveQuote';

  final Map<Object, List<LiveQuoteRegistration>> _registrations = {};
  final LiveQuoteBook _book = LiveQuoteBook();

  /// 最近一分鐘內各請求的送出時刻(節流用)
  final List<DateTime> _sentAt = [];
  Timer? _ticker;

  /// 啟動時生命週期狀態可能是 null → 視為可見
  bool _appVisible = true;

  _Round? _round;
  bool _inFlight = false;
  DateTime? _lastRoundStartedAt;

  // 暫停計時:只在「排程要抓、App 可見、有登記」的相鄰拍子之間累計
  DateTime? _lastCountedTick;
  Duration _unresponsive = Duration.zero;
  bool _stalled = false;
  int _failuresSinceStall = 0;

  DateTime? _rateLimitedUntil;
  bool _probing = false;
  DateTime? _lastRespondedAt;

  // 紀錄去重:一段連續失敗只記開始與恢復;非預期錯誤一段只送一次
  int _failStreak = 0;
  bool _unexpectedReported = false;

  @override
  LiveQuoteState build() {
    ref.onDispose(_stopTicker);
    return const LiveQuoteState();
  }

  /// 登記 [owner] 要看的股票(同一 owner 再登記即取代)。等下一拍才抓
  void register(Object owner, List<LiveQuoteRegistration> entries) {
    _registrations[owner] = List.unmodifiable(entries);
    _syncTicker();
  }

  void unregister(Object owner) {
    if (_registrations.remove(owner) == null) return;
    _syncTicker();
  }

  /// App 生命週期:resumed／inactive 可見,hidden／paused 不可見
  void setAppVisible(bool visible) {
    if (_appVisible == visible) return;
    _appVisible = visible;
    // 重新可見後第一輪不閃色:拿來比較的是隱藏前的價格
    if (visible) _book.forgetLastRound();
    _syncTicker();
  }

  /// 目前登記的聯集:代號 → 市場別(已套用指數硬對應)
  @visibleForTesting
  Map<String, String> get registeredMarkets => {
    for (final r in _union().values) r.symbol: _marketOf(r),
  };

  void _syncTicker() {
    final shouldRun =
        _appVisible && _registrations.values.any((l) => l.isNotEmpty);
    if (shouldRun && _ticker == null) {
      _ticker = Timer.periodic(LiveQuoteParams.tick, (_) => unawaited(_tick()));
    } else if (!shouldRun && _ticker != null) {
      _stopTicker();
    }
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
    // 停拍期間不計暫停時間
    _lastCountedTick = null;
  }

  Future<void> _tick() async {
    try {
      await _step();
    } catch (e, st) {
      _reportUnexpected((error: e, stackTrace: st));
    }
  }

  Future<void> _step() async {
    final now = _now();
    if (_book.rollDay(now)) {
      // App 開著過夜:昨天的暫停計時不帶到今天,過夜那段也不算
      _unresponsive = Duration.zero;
      _lastCountedTick = null;
      _publish();
    }
    final phase = LiveQuoteSchedule.phaseAt(now);
    final afterClose = phase == MarketPhase.afterClose;
    final plan = _plan(phase, now);
    _countStall(now, pending: plan.pending, afterClose: afterClose);

    if (_inFlight) return; // 上一個請求還沒回來:跳過,不疊加
    final until = _rateLimitedUntil;
    if (until != null && now.isBefore(until)) return;
    if (_round == null &&
        (plan.due.isEmpty || !_roundDue(now, _batchCount(plan.due.length)))) {
      return;
    }
    if (LiveQuoteSchedule.inCliAvoidWindow(now)) return;
    _sentAt.removeWhere(
      (t) => now.difference(t) >= const Duration(minutes: 1),
    );
    if (!LiveQuoteSchedule.canSendRequest(_sentAt, now)) return;

    final round = _round ??= _startRound(plan.due, afterClose, now);
    final batch = round.nextBatch();
    _sentAt.add(now);
    final report = await _fetchBatch(batch, round);
    if (!ref.mounted) return;
    final after = _now();
    if (report == null) {
      _round = null;
      _enterRateLimit(after);
      return;
    }
    round.add(report);
    if (round.isDone) {
      _round = null;
      _finishRound(round, after);
    }
  }

  DateTime _now() => ref.read(appClockProvider).now();

  /// 這一拍的計畫:[due] 是若要開新的一輪該抓的代號 → 市場別(保持登記
  /// 順序);[pending] 是排程還要抓的檔數(暫停計時與門檻用)
  ({Map<String, String> due, int pending}) _plan(
    MarketPhase phase,
    DateTime now,
  ) {
    final union = _union();
    switch (phase) {
      case MarketPhase.closed:
      case MarketPhase.preOpen:
        return (due: const {}, pending: 0);
      case MarketPhase.open:
        return (
          due: {for (final r in union.values) r.symbol: _marketOf(r)},
          pending: union.length,
        );
      case MarketPhase.afterClose:
        final candidates = [
          for (final r in union.values)
            if (!r.hasOfficialToday) r.symbol,
        ];
        return (
          due: {
            for (final s in _book.dueAfterClose(candidates, now))
              s: _marketOf(union[s]!),
          },
          pending: _book.pendingAfterClose(candidates).length,
        );
    }
  }

  /// 所有畫面登記的聯集;同一檔只要有任一畫面還沒有今天的正式資料,
  /// 收盤後就要抓
  Map<String, LiveQuoteRegistration> _union() {
    final union = <String, LiveQuoteRegistration>{};
    for (final list in _registrations.values) {
      for (final r in list) {
        final seen = union[r.symbol];
        if (seen == null || (seen.hasOfficialToday && !r.hasOfficialToday)) {
          union[r.symbol] = r;
        }
      }
    }
    return union;
  }

  static String _marketOf(LiveQuoteRegistration r) => switch (r.symbol) {
    LiveQuoteParams.twseIndexSymbol => MarketCode.twse,
    LiveQuoteParams.tpexIndexSymbol => MarketCode.tpex,
    _ => r.market,
  };

  static int _batchCount(int symbols) =>
      (symbols + ApiEndpoints.misBatchSize - 1) ~/ ApiEndpoints.misBatchSize;

  bool _roundDue(DateTime now, int batchCount) {
    final last = _lastRoundStartedAt;
    if (last == null) return true;
    final interval = _stalled
        ? LiveQuoteSchedule.backoffInterval(batchCount, _failuresSinceStall)
        : LiveQuoteSchedule.pollInterval(batchCount);
    return now.difference(last) >= interval;
  }

  void _countStall(
    DateTime now, {
    required int pending,
    required bool afterClose,
  }) {
    final counting = pending > 0;
    final last = _lastCountedTick;
    if (counting && last != null) _unresponsive += now.difference(last);
    _lastCountedTick = counting ? now : null;
    final stalled =
        counting &&
        _unresponsive >
            LiveQuoteSchedule.stallThreshold(
              _batchCount(pending),
              afterClose: afterClose,
            );
    if (stalled == _stalled) return;
    _stalled = stalled;
    if (!stalled) _failuresSinceStall = 0;
    _publish();
  }

  _Round _startRound(
    Map<String, String> due,
    bool afterClose,
    DateTime now,
  ) {
    final entries = due.entries.toList();
    final batches = [
      for (var i = 0; i < entries.length; i += ApiEndpoints.misBatchSize)
        Map.fromEntries(entries.skip(i).take(ApiEndpoints.misBatchSize)),
    ];
    _lastRoundStartedAt = now;
    // 限流後的試探只送第一批
    return _Round(
      _probing ? batches.sublist(0, 1) : batches,
      probe: _probing,
      afterClose: afterClose,
    );
  }

  /// 送一批;限流回 null
  Future<QuoteBatchReport?> _fetchBatch(
    Map<String, String> batch,
    _Round round,
  ) async {
    _inFlight = true;
    try {
      return await ref.read(liveQuoteClientProvider).fetchQuotesDetailed(batch);
    } on RateLimitException {
      return null;
    } catch (e, st) {
      round.unexpected ??= (error: e, stackTrace: st);
      return QuoteBatchReport(
        quotes: const {},
        errors: ['${e.runtimeType}: $e'],
        respondedSymbols: const <String>{},
        failedSymbols: batch.keys.toSet(),
      );
    } finally {
      _inFlight = false;
    }
  }

  void _finishRound(_Round round, DateTime now) {
    final outcome = _book.apply(
      round.report,
      requested: round.requested,
      now: now,
      afterClose: round.afterClose,
    );
    if (round.probe) {
      _probing = false;
      _rateLimitedUntil = null;
    }
    if (outcome == RoundOutcome.failed) {
      if (_stalled) _failuresSinceStall++;
      _noteFailure(round.firstError ?? '回應無效(rtcode、格式或沒有列)');
    } else {
      _lastRespondedAt = now;
      _unresponsive = Duration.zero;
      _stalled = false;
      _failuresSinceStall = 0;
      _noteRecovery();
    }
    final unexpected = round.unexpected;
    if (unexpected == null) {
      _unexpectedReported = false;
    } else {
      _reportUnexpected(unexpected);
    }
    _publish();
  }

  void _enterRateLimit(DateTime now) {
    _rateLimitedUntil = now.add(LiveQuoteParams.rateLimitPause);
    _probing = true;
    _noteFailure(
      '證交所限流,暫停 ${LiveQuoteParams.rateLimitPause.inMinutes} 分鐘後試探',
    );
    _publish();
  }

  // 斷線與限流是預期中的環境狀況、畫面已標示 → 只用 warning(release 只留
  // breadcrumb);一段連續失敗只記開始與恢復
  void _noteFailure(String reason) {
    _failStreak++;
    if (_failStreak == 1) AppLogger.warning(_tag, '即時報價中斷:$reason');
  }

  void _noteRecovery() {
    if (_failStreak > 0) {
      AppLogger.warning(_tag, '即時報價恢復(連續失敗 $_failStreak 輪)');
    }
    _failStreak = 0;
  }

  /// 非預期錯誤 → error 帶例外物件(送 Sentry);一段只送一次
  void _reportUnexpected(({Object error, StackTrace stackTrace}) u) {
    if (_unexpectedReported) return;
    _unexpectedReported = true;
    AppLogger.error(_tag, '即時報價非預期錯誤', u.error, u.stackTrace);
  }

  void _publish() {
    state = LiveQuoteState(
      entries: _book.entries,
      symbolStatus: _book.symbolStatus,
      stalled: _stalled,
      rateLimitedUntil: _rateLimitedUntil,
      lastRespondedAt: _lastRespondedAt,
      latestResponseHadToday: _book.latestResponseHadToday,
      latestQuoteTime: _book.latestQuoteTime,
    );
  }
}

/// 進行中的一輪:逐批送出,全部回來才套進記帳本
class _Round {
  _Round(this.batches, {required this.probe, required this.afterClose});

  final List<Map<String, String>> batches;
  final bool probe;
  final bool afterClose;
  int _next = 0;
  final Map<String, IntradayQuote> _quotes = {};
  final List<String> _errors = [];
  final Set<String> _responded = {};
  final Set<String> _failed = {};
  ({Object error, StackTrace stackTrace})? unexpected;

  bool get isDone => _next >= batches.length;
  Map<String, String> nextBatch() => batches[_next++];
  List<String> get requested => [for (final b in batches) ...b.keys];
  String? get firstError => _errors.isEmpty ? null : _errors.first;

  void add(QuoteBatchReport r) {
    _quotes.addAll(r.quotes);
    _errors.addAll(r.errors);
    _responded.addAll(r.respondedSymbols);
    _failed.addAll(r.failedSymbols);
  }

  QuoteBatchReport get report => QuoteBatchReport(
    quotes: _quotes,
    errors: _errors,
    respondedSymbols: _responded,
    failedSymbols: _failed,
  );
}
```

- [ ] **Step 4: 確認通過**

Run: `flutter test test/presentation/providers/live_quote_provider_test.dart test/data/remote/ test/domain/services/live_quote/`
Expected: 全部 PASS

若時間序列的斷言差 1 秒：
- 先確認 fakeAsync 的 tick 順序：計時器在登記那一刻建立，第 1 拍在 +1 秒。
- 再確認暫停判斷用的是 `>`（不是 `>=`）。
- 不要為了對上數字而改常數；照 spec 的參數重算預期，在 ledger 記 Ruling。

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 5: 記錄進度**（不 commit）

---

### Task 7: 畫面登記 LiveQuoteScope 與 App 可見性

**Files:**
- Modify: `lib/app/app_lifecycle_coordinator.dart`
- Modify: `lib/main.dart:242-254`（coordinator 接線）與 import
- Create: `lib/presentation/widgets/live_quote_scope.dart`
- Test: `test/app/app_lifecycle_coordinator_test.dart`、`test/presentation/widgets/live_quote_scope_test.dart`

**Interfaces:**
- Consumes：Task 6 的 `LiveQuoteCenter.register`／`unregister`／`setAppVisible`、`registeredMarkets`、`LiveQuoteRegistration`、`liveQuoteCenterProvider`；`appClockProvider`。
- Produces：
  - `AppLifecycleCoordinator({..., ValueChanged<bool>? onAppVisibilityChanged})`。
  - `LiveQuoteScope({Key? key, required List<LiveQuoteRegistration> registrations, required Widget child})`。

- [ ] **Step 1: 寫失敗測試**

1. `test/app/app_lifecycle_coordinator_test.dart` 在 `main()` 最後（`group('手機', ...)` 之後）加：

```dart
  group('即時報價可見性', () {
    late List<bool> visible;

    setUp(() {
      visible = [];
      c = AppLifecycleCoordinator(
        staleAfter: const Duration(minutes: 30),
        reload: () {},
        flushBudget: () async {},
        stopIntraday: () {},
        startIntraday: () {},
        onAppVisibilityChanged: visible.add,
      );
    });

    test('resumed、inactive 看得到;hidden、paused、detached 看不到', () {
      for (final (state, expected) in const [
        (AppLifecycleState.resumed, true),
        (AppLifecycleState.inactive, true),
        (AppLifecycleState.hidden, false),
        (AppLifecycleState.paused, false),
        (AppLifecycleState.detached, false),
      ]) {
        visible.clear();
        go(state);
        expect(visible, [expected], reason: state.name);
      }
    });

    test('🚨 macOS 視窗失焦但看得到(inactive)→ 繼續更新', () {
      go(AppLifecycleState.inactive);
      expect(visible, [true]);
    });

    test('🚨 macOS 啟動先 hidden 再 resumed → 看得到', () {
      go(AppLifecycleState.hidden);
      go(AppLifecycleState.resumed);
      expect(visible, [false, true]);
    });

    test('🚨 resumed → hidden → resumed 也正確', () {
      go(AppLifecycleState.resumed);
      go(AppLifecycleState.hidden);
      go(AppLifecycleState.resumed);
      expect(visible, [true, false, true]);
    });
  });
```

2. 建立 `test/presentation/widgets/live_quote_scope_test.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:daredevil/core/constants/market_codes.dart';
import 'package:daredevil/core/utils/clock.dart';
import 'package:daredevil/presentation/providers/live_quote_provider.dart';
import 'package:daredevil/presentation/providers/providers.dart';
import 'package:daredevil/presentation/widgets/live_quote_scope.dart';

/// 週六:報價中心照常登記、計時,但不會發請求
class _SaturdayClock implements AppClock {
  @override
  DateTime now() => DateTime(2026, 10, 3, 10);
}

/// 畫面登記與可見性(2026-10-06,spec §4)。
///
/// 用真的 go_router 與真的報價中心:套件升級改了 TickerMode 行為會先紅;
/// 報價中心若在 build 期間寫 state,Riverpod 會在這裡拋錯。
void main() {
  late ProviderContainer container;
  late GoRouter router;

  Set<String> registered() =>
      container.read(liveQuoteCenterProvider.notifier).registeredMarkets.keys.toSet();

  setUp(() {
    container = ProviderContainer(
      overrides: [appClockProvider.overrideWithValue(_SaturdayClock())],
    );
    router = GoRouter(
      initialLocation: '/watchlist',
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (context, state, shell) => Scaffold(body: shell),
          branches: [
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/watchlist',
                  builder: (_, _) => const LiveQuoteScope(
                    registrations: [
                      LiveQuoteRegistration(symbol: '2330', market: MarketCode.twse),
                    ],
                    child: Text('watchlist'),
                  ),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(path: '/news', builder: (_, _) => const Text('news')),
              ],
            ),
          ],
        ),
        // 個股頁在 shell 外(同 lib/app/router.dart)
        GoRoute(
          path: '/stock',
          builder: (_, _) => const Scaffold(body: Text('stock')),
        ),
      ],
    );
  });

  tearDown(() {
    router.dispose();
    container.dispose();
  });

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 拆掉整棵樹:scope dispose → 取消登記 → 報價中心停拍
  Future<void> unmount(WidgetTester tester) =>
      tester.pumpWidget(const SizedBox());

  testWidgets('🚨 切到別的分頁 → 取消登記;切回來 → 重新登記', (tester) async {
    await pumpApp(tester);
    expect(registered(), {'2330'});

    router.go('/news');
    await tester.pumpAndSettle();
    expect(registered(), isEmpty);

    router.go('/watchlist');
    await tester.pumpAndSettle();
    expect(registered(), {'2330'});
    await unmount(tester);
  });

  testWidgets('🚨 推入不透明頁面(個股頁)→ 底下的頁面取消登記;返回 → 重新登記', (tester) async {
    await pumpApp(tester);
    router.push('/stock');
    await tester.pumpAndSettle();
    expect(find.text('stock'), findsOneWidget);
    expect(registered(), isEmpty);

    router.pop();
    await tester.pumpAndSettle();
    expect(registered(), {'2330'});
    await unmount(tester);
  });

  testWidgets('開底部面板 → 底下的畫面維持登記', (tester) async {
    await pumpApp(tester);
    showModalBottomSheet<void>(
      context: tester.element(find.text('watchlist')),
      builder: (_) => const Text('sheet'),
    );
    await tester.pumpAndSettle();
    expect(find.text('sheet'), findsOneWidget);
    expect(registered(), {'2330'});
    await unmount(tester);
  });

  testWidgets('離開畫面(dispose)→ 取消登記', (tester) async {
    await pumpApp(tester);
    await unmount(tester);
    expect(registered(), isEmpty);
  });

  testWidgets('清單改變 → 以新清單重新登記', (tester) async {
    Widget scope(List<String> symbols) => UncontrolledProviderScope(
      container: container,
      child: LiveQuoteScope(
        registrations: [
          for (final s in symbols)
            LiveQuoteRegistration(symbol: s, market: MarketCode.twse),
        ],
        child: const SizedBox(),
      ),
    );
    await tester.pumpWidget(scope(['2330']));
    expect(registered(), {'2330'});
    await tester.pumpWidget(scope(['2330', '2317']));
    expect(registered(), {'2330', '2317'});
    await unmount(tester);
  });
}
```

- [ ] **Step 2: 確認紅燈**

Run: `flutter test test/app/app_lifecycle_coordinator_test.dart test/presentation/widgets/live_quote_scope_test.dart`
Expected: 兩個檔都編譯失敗（`onAppVisibilityChanged` 不是具名參數、`live_quote_scope.dart` 不存在）

- [ ] **Step 3: 實作**

1. `lib/app/app_lifecycle_coordinator.dart`：
   - 類別註解第一行改成「App 生命週期的副作用：回前景重載、配額落盤、盤中輪詢啟停、即時報價的可見性。」
   - 建構子在 `required this.startIntraday,` 之後加 `this.onAppVisibilityChanged,`。
   - 欄位在 `final VoidCallback startIntraday;` 之後加：

```dart

  /// App 看不看得到(盤中即時報價用):resumed、inactive 看得到;hidden、
  /// paused、detached 看不到。macOS 視窗失焦但看得到(例如放在第二個螢幕)
  /// 是 inactive,要繼續更新;最小化、被遮住、Cmd+H 是 hidden。
  /// 和盤中提醒不同:提醒只在 paused 停。
  final ValueChanged<bool>? onAppVisibilityChanged;
```

   - `onStateChanged` 最後（盤中輪詢那段 if／else if 之後）加：

```dart

    onAppVisibilityChanged?.call(
      state == AppLifecycleState.resumed ||
          state == AppLifecycleState.inactive,
    );
```

2. `lib/main.dart`：
   - import 區加 `import 'package:daredevil/presentation/providers/live_quote_provider.dart';`（照字母順序放）。
   - `_lifecycle` 的建構參數在 `startIntraday: ...,` 之後加：

```dart
    onAppVisibilityChanged: (visible) =>
        ref.read(liveQuoteCenterProvider.notifier).setAppVisible(visible),
```

3. 建立 `lib/presentation/widgets/live_quote_scope.dart`：

```dart
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:daredevil/presentation/providers/live_quote_provider.dart';

/// 把畫面要看的股票登記到報價中心(2026-10-06)。
///
/// **可見性 = `TickerMode.of(context)`**:go_router 沒在看的分頁包在
/// `TickerMode(enabled: false)`,被不透明頁面蓋住的頁面也是(Overlay 以
/// `tickerEnabled: false` 建構);底部面板、對話框不是不透明頁面,底下
/// 畫面維持登記。行為由 `test/presentation/widgets/live_quote_scope_test.dart`
/// 以真的 go_router 釘住,套件升級改了行為會先紅。
class LiveQuoteScope extends ConsumerStatefulWidget {
  const LiveQuoteScope({
    super.key,
    required this.registrations,
    required this.child,
  });

  final List<LiveQuoteRegistration> registrations;
  final Widget child;

  @override
  ConsumerState<LiveQuoteScope> createState() => _LiveQuoteScopeState();
}

class _LiveQuoteScopeState extends ConsumerState<LiveQuoteScope> {
  /// initState 先拿:dispose 時不能 ref.read(Riverpod 3 會拋 StateError)
  late final LiveQuoteCenter _center;
  bool _registered = false;

  @override
  void initState() {
    super.initState();
    _center = ref.read(liveQuoteCenterProvider.notifier);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(LiveQuoteScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.registrations, widget.registrations)) _sync();
  }

  void _sync() {
    if (TickerMode.of(context)) {
      _center.register(this, widget.registrations);
      _registered = true;
    } else if (_registered) {
      _center.unregister(this);
      _registered = false;
    }
  }

  @override
  void dispose() {
    if (_registered) _center.unregister(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
```

- [ ] **Step 4: 確認通過**

Run: `flutter test test/app/ test/presentation/widgets/live_quote_scope_test.dart test/presentation/providers/live_quote_provider_test.dart`
Expected: 全部 PASS（原有 coordinator 測試的 `calls` 斷言不受影響：它們建的 coordinator 沒有傳可見性回呼）

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 5: 記錄進度**（不 commit）

---

### Task 8: 全套驗證、mutation、審查、經同意提交

- [ ] **Step 1: 靜態檢查與全套測試**（log 寫到 scratchpad）

```bash
dart format lib test
flutter analyze
flutter test > <scratchpad>/full_lq1.log 2>&1; tail -c 300 <scratchpad>/full_lq1.log
flutter test test/tool/tool_chain_pure_dart_test.dart
dart compile kernel tool/intraday_alert_check.dart -o build/intraday_alert_check.dill
dart compile kernel tool/daily_update.dart -o build/daily_update.dill
```

Expected:
- analyze 無 issue。
- 全套通過，測試數比開工前基準多出本段新增的數目。開工前先跑一次全套，記下基準。
- 守門測試通過。
- 兩個 kernel 編譯成功。

- [ ] **Step 2: 閉包與殘留檢查**

```bash
grep -rn "live_quote" tool bin lib/data lib/core lib/domain/services/alert
grep -rn "_openMinutes\|_closeMinutes" lib test
grep -rln "IntradayPollSchedule\|IntradayQuoteClient\|intraday_quote_client" docs .claude CLAUDE.md README.md test/CLAUDE.md
```

Expected:
- 第一條：只有 `lib/core/constants/live_quote_params.dart` 這個檔名本身會出現（`market_client_mixin.dart` 註解提到 `LiveQuoteParams` 不含底線，不會中）。`tool`、`bin` 沒有任何 import 指向 `live_quote`。
- 第二條：沒有輸出。
- 第三條：只有 `docs/plans/2026-10-05-intraday-live-quotes-design.md`。文件不需要同步更新：
  - `.claude/rules/architecture.md` 的數字是快照，註明會漂移；
  - 本段沒有使用者可見變化，所以沒有 CHANGELOG。

- [ ] **Step 3: mutation**

在 scratchpad 的 repo 副本做（`rsync -rl`，含 `.dart_tool`，排除 `.dart_tool/flutter_build`、`build/`、`.git/`）。

做法：
- 先跑直接測試。
- 存活者再跑全部消費者測試：`test/data/remote test/domain/services test/presentation/providers/live_quote_provider_test.dart test/presentation/widgets/live_quote_scope_test.dart test/app`。
- 還原用備份檔，不用 git checkout。

至少涵蓋：

| 檔案 | mutant | 直接測試 |
|:--|:--|:--|
| intraday_quote | trial 與 book 的來源對調；`lastTradePrice` 改成不讀 trade；`_date` 拿掉月份範圍檢查 | parsing_test |
| intraday_quote_client | 拿掉 `rows.isEmpty`；拿掉 `rtcode != '0000'`；`_warnBatchFailed` 拿掉 `_logBatchErrors` 判斷；`responded.addAll` 改成 `failed.addAll` | client_test |
| live_quote_schedule | `pollInterval` 的 `>` 改 `>=` 並把 maxRequestsPerMinute 換成 4；`canSendRequest` 的 `<` 改 `<=`；拿掉 2 秒間隔檢查；`inCliAvoidWindow` 的 `<` 改 `<=`；`stallThreshold` 拿掉 afterClose 分支；`backoffInterval` 拿掉上限；`isClosingQuote` 的 `<` 改 `<=`、拿掉 locked；`afterClosePending` 的 `<` 改 `<=` | schedule_test |
| live_quote_merge | 拿掉 `officialClose != null`；拿掉即時報價的日期檢查；label 的 open 與 closing 對調 | merge_test |
| live_quote_book | 顯示價第 3、4 步對調；記憶也存 trialOrBook；拿掉 `_fetchedLastRound` 檢查；拿掉 `_flashable` 檢查；`respondedNoToday` 改回 `failed`；收盤後嘗試改成連失敗也計；`rollDay` 不清 `_lastTraded` | book_test |
| live_quote_provider | 拿掉 `_inFlight` 檢查；拿掉 CLI 避讓；試探不 `sublist(0, 1)`；`_countStall` 改成不看 `counting`；`_failuresSinceStall` 不論是否暫停都加；`_reportUnexpected` 拿掉去重；`_noteFailure` 每次都記；`_marketOf` 拿掉指數對應；`_union` 改成先到先贏；`if (!ref.mounted) return;` 拿掉；`_stopTicker` 不清 `_lastCountedTick`；rollDay 時不清 `_lastCountedTick` | provider_test |
| live_quote_scope | `_sync` 不看 `TickerMode`（一律登記） | scope_test |
| app_lifecycle_coordinator | `inactive` 改成看不到 | coordinator_test |

- [ ] **Step 4: 審查**

送 opus 審查（`pr-review-toolkit:code-reviewer`）：
- 範圍：`git diff` 加未追蹤新檔。
- 附上：
  - 本計畫與 spec 的路徑；
  - Review Focus 五條、「與 spec 的差異」十二條；
  - Step 1–3 的輸出。
- 限制：不可 `dart run`、不可開背景任務、不可碰 scratchpad、不改檔。
- 修正後以 SendMessage 請同一位審查者複審，直到 Ready。

- [ ] **Step 5: 報告並等「提交」**

報告內容：
- 全套測試數；
- mutation 結果（殺掉幾個、存活者的理由）；
- 審查輪數與修正；
- 「與 spec 的差異」的最終版。

提醒：
- 不在 09:00–13:30 提交（post-commit hook 會重編 CLI）。
- 本段不動 live DB，不需要備份。

Commit message 草稿：

```
feat: 盤中即時報價基礎層（報價中心、排程、合併規則）

- IntradayQuote 補報價日期、價格來源與最後一筆成交（trade.z，只供顯示，
  price 規則不變）
- IntradayQuoteClient 新增 fetchQuotesDetailed，逐批回報有沒有回應；
  即時報價用短逾時並關閉逐批 warning，盤中提醒與 CLI 行為不變
- 開收盤時間抽成 MarketSession 共用；新增 LiveQuoteParams、
  LiveQuoteSchedule、LiveQuoteMerge、LiveQuoteBook
- 新增 LiveQuoteCenter：只抓登記且看得到的股票，任何 60 秒內最多 8 個
  請求、避開盤中提醒 CLI，處理暫停、退避、限流試探與紀錄去重
- 新增 LiveQuoteScope 與 App 可見性接線；畫面尚未使用，使用者看不到變化
```

- [ ] **Step 6: 經同意後提交**（使用者說「提交」才做）

1. 確認現在不是 09:00–13:30。
2. 提交（直接在 main，純文字訊息）。

- [ ] **Step 7: 提交後**

1. 確認 post-commit hook 已把兩支 CLI 重編到新 commit：看 `~/Library/Logs/daredevil-cli-rebuild.log` 最後一行與兩支 `BUILD_INFO`。`-dirty` 標記應該消失。
2. 下一個交易日盤中，看盤中提醒 CLI 日誌：每輪照常，沒有新的失敗型態。本段的 client 改動對 CLI 是純重構。
3. 接著寫第 2 段（自選清單與個股頁）的計畫。

---

## 實作後的修正（2026-10-06 審查）

opus 獨立審查結論為「修正後可合併」：0 Critical、4 Important、8 Minor。4 條 Important 都先寫出會失敗的測試再修。上面各 task 的程式碼是修正前的版本，以 repo 為準。

1. **切走再切回、限流試探時不閃色**（差異第 8 條的延伸）。
   - 問題：「上一輪有抓到」的紀錄只在 App 重新可見時清掉。全部畫面離開期間沒有任何一輪，回來的第一輪就拿很久以前的價格比較而閃色；限流暫停 5 分鐘後的試探那一輪也一樣。
   - 修法：
     - 登記變動時，離開聯集的代號從紀錄中移除（`LiveQuoteBook.forget`）；
     - 進入限流時清空紀錄。
2. **進行中的一輪跟著可見性與登記變動調整**。
   - 問題：原本一輪的批次在開始時就固定。App 隱藏時，第一批的舊報價會等恢復後和新批次一起套用；換畫面後要等舊清單整輪送完，新畫面才拿得到報價。
   - 修法：
     - 停拍時那一輪作廢，還在路上的請求回來後丟棄。
     - 一輪記下開始時的登記版本。送下一批前若版本不同（聯集真的變了），只套用已送出的批次並結束這一輪，下一拍依新的登記重新規劃。
     - 畫面重建時用同一份清單再登記，不換版本。
3. **節流考慮時鐘解析度**（差異第 1 條的實作精度）。
   - 問題：`TaiwanTime.now()` 只到整秒，記下的送出時刻最多比實際早 1 秒。模擬（相位 .999、部分拍晚 2 毫秒）重現了實際間隔只有 1.002 秒。
   - 修法：新增 `LiveQuoteParams.clockResolution`（1 秒）與 `requestWindow`。
     - 間隔要紀錄上差 3 秒，實際才一定 ≥ 2 秒。
     - 窗口算到紀錄上的 61 秒，實際 60 秒內的才不會漏算。
     - 報價中心只保留最近 8 筆送出時刻，不按時間修剪：「窗口內是否已滿」與「離上一個多久」都只看它們，修剪與計數的窗口就不可能不一致。
   - 節奏因此變成：2 批時兩批相隔 3 秒。
4. **補測試**：前一天用滿 10 次嘗試的那檔，跨日後收盤後照樣會抓。

延後的 Minor（第 2 段使用頁首狀態前要先處理前幾條）：
- 換日或已無待抓時，不清 `rateLimitedUntil`、`lastRespondedAt`。
- 限流期間 `stalled` 也會是 true。
- `book.apply` 內的換日會吃掉報價中心的換日訊號（請求跨午夜時短暫誤報暫停）。
- 啟動時的生命週期狀態沒有同步給報價中心。
- ≥ 17 批時退避間隔比輪詢間隔短。
- 無待抓時 ticker 仍每秒醒來。
- `_date` 不檢查該月實際天數。
