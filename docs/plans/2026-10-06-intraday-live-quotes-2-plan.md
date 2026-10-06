# 盤中即時報價第 2 段：自選清單與個股頁 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 自選清單（含長按預覽）與個股頁在盤中顯示即時價、漲跌幅、閃色、漲跌停鎖住標示、例外標示與頁首狀態；收盤後到盤後資料寫入前顯示今日收盤；設定頁新增「價格閃色」開關。大盤與投資組合留給第 3 段。

**Architecture:**
- **報價中心先補四條延後的 Minor**（頁首會用到）：
  - 換日或已無待抓時，不對外顯示限流時刻與最後更新時間；
  - 限流期間不判網路暫停；
  - 請求跨午夜時照樣換日；
  - 啟動時同步生命週期狀態。
- **一個合併結果，多處共用**：
  - 自選每一檔的「要顯示的價格」由 `watchlistLivePriceProvider(symbol)` 依 `LiveQuoteMerge` 算出，卡片、長按預覽、排序都讀它。
  - 個股頁讀 `stockDetailLivePriceProvider(symbol)`。
- **元件不依賴 Riverpod**：`StockCard`、`StockDetailHeader`、`StockPreviewSheet` 都改成接收已算好的值（`StockCardLive`、`StockHeaderLive`、`StockPreviewData`）。畫面端用 `Consumer` 算好再傳進去，掃描與今日訊號不傳，行為不變。
- **漲跌停判斷集中在 `PriceLimit.statusOf`**：
  - 盤中即時報價有交易所的漲跌停價，以價格精確比對，鎖住加「鎖」。
  - 盤後資料照舊以漲跌幅推算。
- **閃色元件 `PriceFlash`**：
  - 只在新的閃色事件出現時閃，第一次建立時不補閃。
  - 以下任一成立就不閃：「價格閃色」開關關閉、`MediaQuery.disableAnimations`、iOS `reduceMotion`。

**Tech Stack:** Flutter／Dart 3.10、flutter_riverpod 3（riverpod 3.3.2）、go_router 17.1.0、easy_localization、fake_async、mocktail、flutter_test

**Spec:** `docs/plans/2026-10-05-intraday-live-quotes-design.md`（75f215fb）。本計畫實作以下部分：
- §5 合併規則的畫面端套用；
- §6 閃色；
- §7 的共通規則（頁首狀態、卡片標示、漲跌停）、自選清單與長按預覽、個股頁上方、自選清單排序、其他使用 `StockCard` 的畫面不登記；
- 「驗證」第 6 項中屬於自選與個股頁的部分。

第 1 段基礎層已提交 aeccdba4。它的計畫 `docs/plans/2026-10-06-intraday-live-quotes-1-plan.md` 末尾「實作後的修正」列了延後的 Minor，其中跟頁首有關的四條在本段 Task 1 處理。

## Global Constraints

- **評分、訊號、籌碼、技術指標、趨勢維持盤後**。自選的「狀態分組」（`WatchlistStatus.volatile`：漲跌幅 ≥ 3%）仍用盤後漲跌幅，不隨即時變動。
- **掃描、今日訊號的 `StockCard` 不登記、不讀即時報價**。即使報價中心已有該檔報價，仍顯示資料庫的值。
- **同一個數字只有一個來源**：自選的卡片、長按預覽、排序都讀 `watchlistLivePriceProvider`；個股頁的上方區塊與背景漸層都讀 `stockDetailLivePriceProvider`。
- **不寫資料庫、不動 live DB。**
- **色彩**：
  - 漲跌色只用 `PriceColors`／`AppTheme.getPriceColor`，不寫 `Colors.red`／`Colors.green`（`presentation_color_discipline_test`）。
  - 閃色底色與「報價暫停」等灰字都要有對比度測試：兩種主題，用實際渲染的顏色與實際底色驗。
- **文案**：
  - 新字串 zh-TW、en 都要有（`app_strings_keys_test`）；
  - 不得出現 `no_investment_advice_copy_test` 的禁用詞；
  - 時間用 `{time}` 具名參數。
- **測試裡的報價中心**：
  - `buildProviderTestApp` 預設換成不發請求、不登記的 `InertLiveQuoteCenter`。否則畫面測試會隨執行時間是否在盤中而不同：盤中跑時會真的去抓 MIS。
  - 需要即時資料的測試改用 `liveQuoteCenter:` 參數傳入假的報價中心，不要再放進 `overrides`（會重複 override）。
  - 時間一律 override `appClockProvider`。
- **golden**：
  - 只有設定頁的 golden 會變（多一個開關），要重產並目視檢查。
  - 自選頁與個股頁的 golden 應該不變：報價中心預設為惰性，沒有任何即時資料；個股頁 golden 是空狀態，不會出現開高低量列。這兩組有差異就是回歸，不可重產。
  - CI 排除 golden tag，只在本機跑。
- **提交**：
  - commit／push 只在使用者說「提交」時做。直接在 main，Conventional Commits、中文、純文字、不加 Co-Authored-By。
  - 每個 task 結尾「記錄進度」，整段在 Task 9 一次提交。
  - 不在 09:00–13:30 提交，因為 post-commit hook 會重編 launchd CLI。
- **測試行程**：跑 `flutter test` 前，用 `ps -axo pid=,ppid=,etime=,comm= | grep -E '/(dart|flutter)$'` 確認沒有其他 `dart run`／`flutter test`／`flutter run`。IDEA 的 analysis server 不算。
- **mutation**：
  - 在 scratchpad 的 repo 副本做，還原用備份檔、不用 git checkout。
  - 先確認副本基線全綠。
  - 先跑直接測試，存活者再跑全部消費者測試。
  - 編譯錯誤殺掉的不算。
- **審查者**：不可 `dart run`、不可開背景任務、不可碰 scratchpad、不改檔。

## Review Focus

1. **清單捲動時卡片被回收重建，以及同一個閃色事件重複出現**。
   - 預期：
     - 捲回來重建的卡片不補閃；
     - 同一個 id 重建不再閃；
     - 只有新的 id 才閃。
   - 測試在 Task 3（`PriceFlash` 第一次建立、同 id 重建）。
2. **App 開著過夜**。
   - 預期：隔天盤前，卡片與個股頁不顯示昨天的即時價、不標「今日收盤」，頁首不顯示限流或暫停。
   - 測試在 Task 1（報價中心換日清欄位）、Task 6（隔天盤前卡片顯示資料庫價）。
3. **13:30 前後切換**。
   - 預期：盤中頁首寫「報價時間」，收盤後依卡片是不是都已拿到收盤報價，改寫「今日收盤・待盤後更新」或「最後報價 HH:MM:SS（最舊的）」。
   - 測試在 Task 5（規則）、Task 6（頁首）。
4. **同一檔同時出現在多處**：卡片、長按預覽、排序；清單、格狀、分組視圖。
   - 預期：價格、漲跌幅一致，預覽隨每輪更新。
   - 測試在 Task 4（排序讀同一個合併結果）、Task 7（預覽與卡片同價、隨下一輪更新）。
5. **個股頁上下滑換股**。
   - 預期：登記跟著換到新的代號，上方區塊顯示新代號的即時價，不殘留上一檔。
   - 測試在 Task 8。

## 與 spec 的差異（核可計畫時一併確認）

1. **卡片例外標示放在名稱列**。spec 只說「卡片只標例外」。名稱列和名稱同一行，放在那裡不增加卡片高度；格狀模式的卡片是固定高度，多一行會溢位。
2. **「漲停鎖」標示的位置**：放在卡片名稱列既有的漲跌停徽章（文字從「漲停」變「漲停鎖」）。個股頁上方新增同樣的徽章（spec 沒寫個股頁要不要標，目標一節要求鎖住要標「鎖」）。
3. **個股頁的狀態文字**：放在原「資料日期」的位置。用即時報價時，跟自選頁首用同一條規則：暫停、尚無報價、報價時間、今日收盤、最後報價；時間取這一檔自己的報價時間。
4. **「自選畫面變為可見」只看分頁切換與推頁返回**（`TickerMode`）。App 從背景回到前景不算：回到前景時清單還在畫面上，順序保留，數字照常更新。
5. **閃色底色的透明度 0.2**。spec 沒有指定。實算後確認現價數字是一般文字色、不是紅綠色，疊在 20% 的紅綠底上，兩種主題的對比度都遠高於 4.5；由 Task 3 的測試釘住。
6. **長按預覽不閃色**。spec 只要求與卡片同價、隨每輪更新。
7. **個股頁的開高低量列在盤後也顯示**：用正式資料那一筆，成交量股數除以 1,000 換成張。spec 只寫「新增一行」，沒有限制時段。

## 檔案結構

| 檔案 | 責任 | 動作 |
|:--|:--|:--|
| `lib/presentation/providers/live_quote_provider.dart` | 報價中心 | 換日、待抓、限流期間計時的修正 |
| `lib/app/app_lifecycle_coordinator.dart`、`lib/main.dart` | 生命週期 | `isVisible`；啟動時同步 |
| `lib/core/utils/price_limit.dart`、`lib/core/l10n/app_strings.dart` | 漲跌停判斷與文字 | `PriceLimitStatus`、`statusOf`、`priceLimitLabel` |
| `lib/presentation/widgets/stock_card_live.dart` | 卡片的即時資料 | 新增 `StockCardLive` |
| `lib/presentation/widgets/stock_card.dart`、`stock_card_price.dart` | 卡片 | 漲跌停走 `statusOf`、例外標示、閃色 |
| `lib/presentation/widgets/price_flash.dart` | 閃色 | 新增 |
| `lib/core/constants/live_quote_params.dart` | 參數 | `flashTintAlpha` |
| `lib/presentation/providers/settings_provider.dart`、`lib/presentation/screens/settings/settings_screen.dart` | 設定 | `priceFlash` |
| `lib/domain/services/live_quote/live_quote_merge.dart` | 合併規則 | `OfficialPrice` 相等比較、`MergedPrice.changePercent` |
| `lib/presentation/providers/watchlist_types.dart`、`watchlist_provider.dart` | 自選資料 | 價格日期、價差、合併、排序、重排 |
| `lib/presentation/providers/live_price_provider.dart` | 合併後價格 | 新增（自選、自選頁首、個股頁） |
| `lib/presentation/widgets/live_quote_status.dart` | 頁首狀態與卡片標示規則 | 新增 |
| `lib/presentation/screens/watchlist/watchlist_live_view.dart` | 自選列的即時顯示結果 | 新增 |
| `lib/presentation/screens/watchlist/watchlist_screen.dart`、`watchlist_stock_item.dart` | 自選畫面 | 登記、卡片、頁首、重排、預覽 |
| `lib/presentation/widgets/stock_preview_sheet.dart` | 長按預覽 | `liveData` |
| `lib/presentation/screens/stock_detail/stock_detail_screen.dart`、`widgets/stock_detail_header.dart` | 個股頁 | 登記、即時價、開高低量、狀態、徽章、漸層 |
| `assets/translations/zh-TW.json`、`en.json`、`CHANGELOG.md` | 文案 | 新增 |
| `test/helpers/provider_test_helpers.dart` | 測試輔助 | `InertLiveQuoteCenter`、`liveQuoteCenter:` |

---

### Task 1: 報價中心的頁首前置修正（第 1 段延後的四條 Minor）

**Files:**
- Modify: `lib/presentation/providers/live_quote_provider.dart`
- Modify: `lib/app/app_lifecycle_coordinator.dart`
- Modify: `lib/main.dart`（`_DaredevilAppState.initState`）
- Test: `test/presentation/providers/live_quote_provider_test.dart`、`test/app/app_lifecycle_coordinator_test.dart`

**Interfaces:**
- Consumes：第 1 段的報價中心內部欄位，以及 `_Harness`（測試）。
- Produces：
  - `static bool AppLifecycleCoordinator.isVisible(AppLifecycleState state)`。
  - `LiveQuoteState.rateLimitedUntil` 只在排程還有要抓的時候才有值。
  - 換日時 `rateLimitedUntil`、`lastRespondedAt` 清空。
  - 限流期間 `stalled` 不會變 true。

- [ ] **Step 1: 寫失敗測試**

1. 在 `test/presentation/providers/live_quote_provider_test.dart` 的 `main()` 最後（`group('可見性、睡眠、換日、釋放', ...)` 之後）加：

```dart
  group('頁首前置修正(第 1 段延後的 Minor)', () {
    test('🚨 換日時清掉限流時刻與最後更新時間(App 開著過夜)', () {
      fakeAsync((async) {
        var round = 0;
        final h = _Harness(async, weekdayMorning)
          ..respond = (exCh, now) async {
            round++;
            if (round == 2) return '<!doctype html><html></html>';
            if (round >= 3) {
              await Future<void>.delayed(const Duration(seconds: 5));
              throw const _NetworkDown();
            }
            return _tradeEach(exCh, now);
          };
        h.center.register('A', const [tsmc]);
        h.elapse(const Duration(seconds: 16)); // 1 成功、16 限流
        expect(h.state.lastRespondedAt, isNotNull);
        expect(h.state.rateLimitedUntil, isNotNull);

        h.jump = const Duration(hours: 23); // 10/7 09:01:17
        h.elapse(const Duration(seconds: 1)); // 隔天第一輪還在路上
        expect(h.state.rateLimitedUntil, isNull, reason: '昨天的限流不帶到今天');
        expect(h.state.lastRespondedAt, isNull, reason: '「最後更新」不可是昨天');
        h.dispose();
      });
    });

    test('🚨 限流後已沒有要抓的(收盤後畫面都已有今天正式資料)→ 不對外顯示限流', () {
      fakeAsync((async) {
        final h = _Harness(async, afterCloseStart)
          ..respond = (_, _) async => '<!doctype html><html></html>';
        h.center.register('A', const [tsmc]);
        h.elapse(const Duration(seconds: 2));
        expect(h.state.rateLimitedUntil, isNotNull);

        h.center.register('A', const [
          LiveQuoteRegistration(
            symbol: '2330',
            market: MarketCode.twse,
            hasOfficialToday: true,
          ),
        ]);
        h.elapse(const Duration(seconds: 1));
        expect(h.state.rateLimitedUntil, isNull);
        h.dispose();
      });
    });

    test('🚨 限流暫停期間不判網路暫停(頁首只說限流)', () {
      fakeAsync((async) {
        final h = _Harness(async, weekdayMorning)
          ..respond = (_, _) async => '<!doctype html><html></html>';
        h.center.register('A', const [tsmc]);
        h.elapse(const Duration(minutes: 3));
        expect(h.state.rateLimitedUntil, isNotNull);
        expect(h.state.stalled, isFalse);
        h.dispose();
      });
    });

    test('🚨 請求跨午夜、回應比下一拍早到 → 照樣換日,昨天的暫停計時不帶到隔天開盤', () {
      fakeAsync((async) {
        // 拍子落在每秒 .900:23:59:59.900 送出的請求在 00:00:00.100 回來,
        // 比 00:00:00.900 那一拍早——換日先發生在套用結果的時候
        final h = _Harness(async, DateTime(2026, 10, 6, 23, 58, 57, 900))
          ..respond = (_, _) async {
            await Future<void>.delayed(const Duration(milliseconds: 200));
            throw const _NetworkDown();
          };
        h.center.register('A', const [tsmc]);
        h.elapse(const Duration(seconds: 63));
        expect(
          [for (final r in h.requests) r.at],
          [
            DateTime(2026, 10, 6, 23, 58, 58, 900),
            DateTime(2026, 10, 6, 23, 59, 59, 900),
          ],
          reason: '前提:第 2 個請求跨午夜',
        );

        h.jump = const Duration(hours: 9, seconds: 20); // 10/7 09:00:21.9 起
        h.elapse(const Duration(seconds: 3));
        expect(h.requests.length, greaterThan(2), reason: '開盤後照常抓');
        expect(h.state.stalled, isFalse, reason: '開盤才 2 秒,不可帶著昨晚的 61 秒');
        h.dispose();
      });
    });
  });
```

2. 在 `test/app/app_lifecycle_coordinator_test.dart` 的 `group('即時報價可見性', ...)` 內最後加：

```dart
    test('isVisible:啟動時同步報價中心用,與 onStateChanged 同一條規則', () {
      for (final (state, expected) in const [
        (AppLifecycleState.resumed, true),
        (AppLifecycleState.inactive, true),
        (AppLifecycleState.hidden, false),
        (AppLifecycleState.paused, false),
        (AppLifecycleState.detached, false),
      ]) {
        expect(
          AppLifecycleCoordinator.isVisible(state),
          expected,
          reason: state.name,
        );
      }
    });
```

- [ ] **Step 2: 確認紅燈**

Run: `flutter test test/presentation/providers/live_quote_provider_test.dart test/app/app_lifecycle_coordinator_test.dart`

Expected:
- coordinator 測試編譯失敗：`isVisible` 未定義。
- provider 的四條新測試失敗：
  - 換日那條：`rateLimitedUntil` 與 `lastRespondedAt` 仍是昨天。
  - 無待抓那條：`rateLimitedUntil` 仍有值。
  - 限流那條：`stalled` 變 true。
  - 跨午夜那條：`stalled` 變 true。

- [ ] **Step 3: 實作**

1. `lib/presentation/providers/live_quote_provider.dart`：
   - 欄位：在 `bool _stalled = false;` 之後加：

```dart

  /// 排程還有沒有要抓的;沒有時(例如收盤後都已有正式資料)不對外顯示限流
  bool _pending = false;
```

   - `_step` 開頭換日的那段：

```dart
    if (_book.rollDay(now)) {
      // App 開著過夜:昨天的暫停計時不帶到今天,過夜那段也不算
      _unresponsive = Duration.zero;
      _lastCountedTick = null;
      _publish();
    }
```

     換成：

```dart
    if (_rollDay(now)) _publish();
```

   - 同一個方法中，從 `_countStall(now, pending: plan.pending, afterClose: afterClose);` 起，到 `final until = _rateLimitedUntil;`、`if (until != null && now.isBefore(until)) return;` 為止，換成：

```dart
    final until = _rateLimitedUntil;
    final rateLimited = until != null && now.isBefore(until);
    // 限流暫停期間不計網路暫停:頁首已顯示限流,兩者同時為真時畫面不知該說哪一個
    _countStall(
      now,
      pending: rateLimited ? 0 : plan.pending,
      afterClose: afterClose,
    );
    _setPending(plan.pending > 0);

    if (_inFlight) return; // 上一個請求還沒回來:跳過,不疊加
    if (rateLimited) return;
```

   - 在 `_countStall` 之前加：

```dart
  /// 換日(App 開著過夜):清掉記帳本與所有跟「今天」有關的狀態,回傳是否換了日。
  /// `_step` 與 `_finishRound` 都先呼叫——請求跨午夜時,回應可能比下一拍早到,
  /// 換日不能只靠 `_step`
  bool _rollDay(DateTime now) {
    if (!_book.rollDay(now)) return false;
    _unresponsive = Duration.zero;
    _lastCountedTick = null;
    _stalled = false;
    _failuresSinceStall = 0;
    _rateLimitedUntil = null;
    _probing = false;
    _lastRespondedAt = null;
    return true;
  }

  void _setPending(bool pending) {
    if (pending == _pending) return;
    _pending = pending;
    _publish();
  }
```

   - `_finishRound` 第一行（`final outcome = _book.apply(` 之前）加 `_rollDay(now);`。
   - `_publish` 的 `rateLimitedUntil: _rateLimitedUntil,` 改成 `rateLimitedUntil: _pending ? _rateLimitedUntil : null,`。
   - `LiveQuoteState.rateLimitedUntil` 的註解改成：

```dart
  /// 報價暫停(證交所限流):到這個時刻後試探;試探完成前不清。排程已沒有
  /// 要抓的(例如收盤後都已有正式資料)或換日時為 null
```

2. `lib/app/app_lifecycle_coordinator.dart`：
   - `onStateChanged` 最後那段改成 `onAppVisibilityChanged?.call(isVisible(state));`。
   - 在 `onExitRequested` 之前加：

```dart
  /// 這個生命週期狀態下 App 看不看得到(盤中即時報價用;規則見
  /// [onAppVisibilityChanged])
  static bool isVisible(AppLifecycleState state) =>
      state == AppLifecycleState.resumed || state == AppLifecycleState.inactive;
```

3. `lib/main.dart`：在 `_DaredevilAppState.initState` 的 `WidgetsBinding.instance.addObserver(this);` 之後加：

```dart
    // 啟動時的生命週期狀態:observer 掛上之前若已送過 hidden(以隱藏狀態
    // 啟動),報價中心預設「可見」就會在背景照抓
    final initialLifecycle = WidgetsBinding.instance.lifecycleState;
    if (initialLifecycle != null) {
      ref
          .read(liveQuoteCenterProvider.notifier)
          .setAppVisible(AppLifecycleCoordinator.isVisible(initialLifecycle));
    }
```

- [ ] **Step 4: 確認通過**

Run: `flutter test test/presentation/providers/live_quote_provider_test.dart test/app/ test/presentation/widgets/live_quote_scope_test.dart`
Expected: 全部 PASS。第 1 段既有的報價中心測試一條都不改：限流測試的 `rateLimitedUntil` 斷言發生在還有待抓時。

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 5: 記錄進度**（不 commit）

---

### Task 2: 漲跌停判斷統一、卡片的即時資料與例外標示

**Files:**
- Modify: `lib/core/utils/price_limit.dart`、`lib/core/l10n/app_strings.dart`
- Create: `lib/presentation/widgets/stock_card_live.dart`
- Modify: `lib/presentation/widgets/stock_card.dart`、`lib/presentation/widgets/stock_card_price.dart`
- Modify: `assets/translations/zh-TW.json`、`assets/translations/en.json`（`price.limitUpLocked`、`price.limitDownLocked`）
- Test: `test/core/utils/price_limit_test.dart`、`test/presentation/widgets/stock_card_test.dart`、`test/presentation/widgets/stock_card_price_test.dart`

**Interfaces:**
- Consumes：第 1 段的 `LiveQuoteFlash`（`lib/domain/models/live_quote.dart`）。
- Produces：
  - `enum PriceLimitStatus { none, limitUp, limitUpLocked, limitDown, limitDownLocked }`，附 getter `isUp`、`isDown`、`isLocked`。
  - `static PriceLimitStatus PriceLimit.statusOf({required double? changePercent, double? price, double? limitUp, double? limitDown, bool limitUpLocked = false, bool limitDownLocked = false})`。
  - `S.priceLimitLabel(PriceLimitStatus)`、`S.priceLimitUpLocked`、`S.priceLimitDownLocked`。
  - `class StockCardLive { double? limitUp, limitDown; bool limitUpLocked, limitDownLocked; LiveQuoteFlash? flash; bool flashEnabled; String? caption; }`。
  - `StockCard({..., StockCardLive? live})`。
  - `StockCardPriceSection({..., PriceLimitStatus limitStatus = PriceLimitStatus.none})`：取代 `showLimitMarkers`。

- [ ] **Step 1: 寫失敗測試**

1. `test/core/utils/price_limit_test.dart` 最後（`main` 的最外層 `}` 之前）加：

```dart
  group('statusOf(畫面上所有漲跌停標示的唯一判斷)', () {
    test('盤後:以漲跌幅推算,推算不出鎖住', () {
      expect(
        PriceLimit.statusOf(changePercent: 9.85),
        PriceLimitStatus.limitUp,
      );
      expect(
        PriceLimit.statusOf(changePercent: -9.85),
        PriceLimitStatus.limitDown,
      );
      expect(PriceLimit.statusOf(changePercent: 9.84), PriceLimitStatus.none);
      expect(PriceLimit.statusOf(changePercent: null), PriceLimitStatus.none);
    });

    test('🚨 盤中有交易所漲跌停價:低價股差一檔(40→43.95,+9.875%)不判漲停', () {
      expect(
        PriceLimit.statusOf(
          changePercent: 9.875,
          price: 43.95,
          limitUp: 44.0,
          limitDown: 36.0,
        ),
        PriceLimitStatus.none,
        reason: '推算會誤判成漲停',
      );
      expect(
        PriceLimit.statusOf(
          changePercent: 10.0,
          price: 44.0,
          limitUp: 44.0,
          limitDown: 36.0,
        ),
        PriceLimitStatus.limitUp,
      );
    });

    test('🚨 鎖住加「鎖」;跌停鏡像', () {
      expect(
        PriceLimit.statusOf(
          changePercent: 10.0,
          price: 44.0,
          limitUp: 44.0,
          limitDown: 36.0,
          limitUpLocked: true,
        ),
        PriceLimitStatus.limitUpLocked,
      );
      expect(
        PriceLimit.statusOf(
          changePercent: -10.0,
          price: 36.0,
          limitUp: 44.0,
          limitDown: 36.0,
          limitDownLocked: true,
        ),
        PriceLimitStatus.limitDownLocked,
      );
      expect(PriceLimitStatus.limitUpLocked.isUp, isTrue);
      expect(PriceLimitStatus.limitDownLocked.isDown, isTrue);
      expect(PriceLimitStatus.limitUp.isLocked, isFalse);
    });
  });
```

2. `test/presentation/widgets/stock_card_price_test.dart`：
   - import 區加 `import 'package:daredevil/core/utils/price_limit.dart';`。
   - 三條漲跌停測試改寫如下，取代原本 `'shows limit-up marker for 10% change'`、`'shows limit-down marker for -10% change'`、`'hides limit markers when showLimitMarkers is false'` 三條：

```dart
    testWidgets('limitStatus 為漲停 → 顯示漲停標記', (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          const StockCardPriceSection(
            latestClose: 110.00,
            priceChange: 10.0,
            priceColor: Colors.red,
            limitStatus: PriceLimitStatus.limitUp,
          ),
        ),
      );

      expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget);
    });

    testWidgets('limitStatus 為跌停鎖 → 顯示跌停標記', (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          const StockCardPriceSection(
            latestClose: 90.00,
            priceChange: -10.0,
            priceColor: Colors.green,
            limitStatus: PriceLimitStatus.limitDownLocked,
          ),
        ),
      );

      expect(find.byIcon(Icons.arrow_downward_rounded), findsOneWidget);
    });

    testWidgets('🚨 價格區塊自己不推算:limitStatus 為 none 時漲 10% 也不標', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildTestApp(
          const StockCardPriceSection(
            latestClose: 110.00,
            priceChange: 10.0,
            priceColor: Colors.red,
          ),
        ),
      );

      expect(find.byIcon(Icons.arrow_upward_rounded), findsNothing);
      expect(find.byIcon(Icons.arrow_downward_rounded), findsNothing);
    });
```

3. `test/presentation/widgets/stock_card_test.dart`：
   - import 區加：

```dart
import 'package:daredevil/core/theme/color_contrast.dart';
import 'package:daredevil/presentation/widgets/stock_card_live.dart';
```

   - 在 `group('StockCard', () {` 內最後加：

```dart
    group('漲跌停與即時資料(盤中即時報價)', () {
      testWidgets('盤後:漲 10% 標「漲停」(推算)', (tester) async {
        await tester.pumpWidget(
          buildTestApp(
            const StockCard(
              symbol: '2330',
              stockName: '測試',
              latestClose: 110,
              priceChange: 10,
            ),
          ),
        );
        expect(find.text('price.limitUp'), findsOneWidget);
      });

      testWidgets('🚨 有交易所漲跌停價時以價格判斷:差一檔不標漲停', (tester) async {
        await tester.pumpWidget(
          buildTestApp(
            const StockCard(
              symbol: 'A',
              stockName: '測試',
              latestClose: 43.95,
              priceChange: 9.875,
              live: StockCardLive(limitUp: 44.0, limitDown: 36.0),
            ),
          ),
        );
        expect(find.text('price.limitUp'), findsNothing);
        expect(find.byIcon(Icons.arrow_upward_rounded), findsNothing);
      });

      testWidgets('🚨 鎖漲停 → 名稱列標「漲停鎖」、價格區塊有漲停標記', (tester) async {
        await tester.pumpWidget(
          buildTestApp(
            const StockCard(
              symbol: 'A',
              stockName: '測試',
              latestClose: 44.0,
              priceChange: 10.0,
              live: StockCardLive(
                limitUp: 44.0,
                limitDown: 36.0,
                limitUpLocked: true,
              ),
            ),
          ),
        );
        expect(find.text('price.limitUpLocked'), findsOneWidget);
        expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget);
      });

      testWidgets('設定關閉漲跌停提示 → 名稱列與價格區塊都不標', (tester) async {
        await tester.pumpWidget(
          buildTestApp(
            const StockCard(
              symbol: '2330',
              stockName: '測試',
              latestClose: 110,
              priceChange: 10,
              showLimitMarkers: false,
            ),
          ),
        );
        expect(find.text('price.limitUp'), findsNothing);
        expect(find.byIcon(Icons.arrow_upward_rounded), findsNothing);
      });

      testWidgets('例外標示顯示在名稱列;沒有名稱時照樣顯示', (tester) async {
        await tester.pumpWidget(
          buildTestApp(
            const StockCard(
              symbol: '2330',
              latestClose: 100,
              priceChange: 1,
              live: StockCardLive(caption: 'liveQuote.cardPaused'),
            ),
          ),
        );
        expect(find.text('liveQuote.cardPaused'), findsOneWidget);
      });

      for (final brightness in [Brightness.light, Brightness.dark]) {
        testWidgets('🚨 例外標示灰字 $brightness:對卡片實際底色 ≥ 4.5', (tester) async {
          await tester.pumpWidget(
            buildTestApp(
              const StockCard(
                symbol: '2330',
                stockName: '測試',
                latestClose: 100,
                priceChange: 1,
                live: StockCardLive(caption: 'liveQuote.cardPaused'),
              ),
              brightness: brightness,
            ),
          );
          final cardColor = tester
              .widgetList<Container>(find.byType(Container))
              .map((c) => c.decoration)
              .whereType<BoxDecoration>()
              .firstWhere((d) => d.borderRadius == BorderRadius.circular(16))
              .color!;
          final textColor = tester
              .widget<Text>(find.text('liveQuote.cardPaused'))
              .style!
              .color!;
          expect(
            ColorContrast.ratio(textColor, cardColor),
            greaterThanOrEqualTo(4.5),
          );
        });
      }
    });
```

- [ ] **Step 2: 確認紅燈**

Run: `flutter test test/core/utils/price_limit_test.dart test/presentation/widgets/stock_card_test.dart test/presentation/widgets/stock_card_price_test.dart`
Expected: 編譯失敗（`statusOf`、`PriceLimitStatus`、`StockCardLive`、`StockCardPriceSection.limitStatus` 未定義）

- [ ] **Step 3: 實作**

1. `lib/core/utils/price_limit.dart`：
   - 在 `class PriceLimit` 之前加：

```dart
/// 漲跌停狀態(見 [PriceLimit.statusOf])
enum PriceLimitStatus {
  none,
  limitUp,
  limitUpLocked,
  limitDown,
  limitDownLocked;

  bool get isUp => this == limitUp || this == limitUpLocked;
  bool get isDown => this == limitDown || this == limitDownLocked;
  bool get isLocked => this == limitUpLocked || this == limitDownLocked;
}

```

   - 在 `isLimitDown` 之後加：

```dart

  /// 漲跌停狀態——畫面上所有漲跌停標示都走這一個判斷。
  ///
  /// 有交易所給的漲跌停價([limitUp]／[limitDown],盤中即時報價才有)時以
  /// 價格精確比對,鎖住與否看委買委賣([limitUpLocked]／[limitDownLocked]);
  /// 沒有時(盤後資料)以漲跌幅推算([isLimitUp]／[isLimitDown]),推算不出
  /// 鎖住。低價股差一檔未達漲停也會被推算判成漲停(例:昨收 40、漲停
  /// 44.00,43.95 為 +9.875%),所以有漲跌停價時不看漲跌幅。
  static PriceLimitStatus statusOf({
    required double? changePercent,
    double? price,
    double? limitUp,
    double? limitDown,
    bool limitUpLocked = false,
    bool limitDownLocked = false,
  }) {
    if (limitUp != null || limitDown != null) {
      if (price != null && price == limitUp) {
        return limitUpLocked
            ? PriceLimitStatus.limitUpLocked
            : PriceLimitStatus.limitUp;
      }
      if (price != null && price == limitDown) {
        return limitDownLocked
            ? PriceLimitStatus.limitDownLocked
            : PriceLimitStatus.limitDown;
      }
      return PriceLimitStatus.none;
    }
    if (isLimitUp(changePercent)) return PriceLimitStatus.limitUp;
    if (isLimitDown(changePercent)) return PriceLimitStatus.limitDown;
    return PriceLimitStatus.none;
  }
```

2. `lib/core/l10n/app_strings.dart`：
   - import 加 `import 'package:daredevil/core/utils/price_limit.dart';`。
   - 在 `priceLimitDown` 之後加：

```dart
  static String get priceLimitUpLocked => 'price.limitUpLocked'.tr();
  static String get priceLimitDownLocked => 'price.limitDownLocked'.tr();

  /// 漲跌停標示文字;[PriceLimitStatus.none] 回空字串
  static String priceLimitLabel(PriceLimitStatus status) => switch (status) {
    PriceLimitStatus.limitUp => priceLimitUp,
    PriceLimitStatus.limitUpLocked => priceLimitUpLocked,
    PriceLimitStatus.limitDown => priceLimitDown,
    PriceLimitStatus.limitDownLocked => priceLimitDownLocked,
    PriceLimitStatus.none => '',
  };
```

3. 翻譯：用下面的腳本插入（逐段 `assert` 只出現一次再取代；不用 json.dump，以免重排整個檔）：

```bash
python3 - <<'PY'
for path, old, new in [
    ('assets/translations/zh-TW.json',
     '    "limitDown": "跌停"\n  },',
     '    "limitDown": "跌停",\n    "limitUpLocked": "漲停鎖",\n    "limitDownLocked": "跌停鎖"\n  },'),
    ('assets/translations/en.json',
     '    "limitDown": "Limit Down"\n  },',
     '    "limitDown": "Limit Down",\n    "limitUpLocked": "Locked Limit Up",\n    "limitDownLocked": "Locked Limit Down"\n  },'),
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

4. 建立 `lib/presentation/widgets/stock_card_live.dart`：

```dart
import 'package:flutter/foundation.dart' show immutable;

import 'package:daredevil/domain/models/live_quote.dart';

/// 卡片上與盤中即時報價有關的資料。只有自選清單會傳;掃描、今日訊號不傳,
/// 行為維持盤後。
@immutable
class StockCardLive {
  const StockCardLive({
    this.limitUp,
    this.limitDown,
    this.limitUpLocked = false,
    this.limitDownLocked = false,
    this.flash,
    this.flashEnabled = true,
    this.caption,
  });

  /// 交易所的漲跌停價(用即時報價時才有);有值時漲跌停以價格精確判斷
  final double? limitUp;
  final double? limitDown;
  final bool limitUpLocked;
  final bool limitDownLocked;

  /// 本輪的閃色事件(見 [LiveQuoteFlash])
  final LiveQuoteFlash? flash;

  /// 設定頁「價格閃色」
  final bool flashEnabled;

  /// 卡片上的例外標示(已翻譯):報價暫停／無報價／最後報價 HH:MM:SS
  final String? caption;
}
```

5. `lib/presentation/widgets/stock_card.dart`：
   - import 加 `import 'package:daredevil/presentation/widgets/stock_card_live.dart';`。
   - 建構子在 `this.showLimitMarkers = true,` 之後加 `this.live,`。
   - 欄位在 `final bool showLimitMarkers;` 之後加：

```dart

  /// 盤中即時報價(自選清單才傳;null = 盤後行為)
  final StockCardLive? live;
```

   - `_StockCardState` 加 getter（放在 `_buildSemanticLabel` 之前）：

```dart
  /// 漲跌停狀態——語意標籤、名稱列徽章、價格區塊三處共用
  PriceLimitStatus get _limitStatus {
    if (!widget.showLimitMarkers) return PriceLimitStatus.none;
    final live = widget.live;
    return PriceLimit.statusOf(
      changePercent: widget.priceChange,
      price: widget.latestClose,
      limitUp: live?.limitUp,
      limitDown: live?.limitDown,
      limitUpLocked: live?.limitUpLocked ?? false,
      limitDownLocked: live?.limitDownLocked ?? false,
    );
  }
```

   - `_buildSemanticLabel` 裡

```dart
      if (widget.showLimitMarkers) {
        if (PriceLimit.isLimitUp(widget.priceChange)) {
          parts.add(S.priceLimitUp);
        } else if (PriceLimit.isLimitDown(widget.priceChange)) {
          parts.add(S.priceLimitDown);
        }
      }
    }
```

     換成：

```dart
      final limit = _limitStatus;
      if (limit != PriceLimitStatus.none) parts.add(S.priceLimitLabel(limit));
    }
    final caption = widget.live?.caption;
    if (caption != null) parts.add(caption);
```

   - 呼叫 `_buildStockName` 的地方

```dart
                                    if (widget.stockName != null) ...[
```

     改成：

```dart
                                    if (widget.stockName != null ||
                                        widget.live?.caption != null) ...[
```

   - `StockCardPriceSection(` 的 `showLimitMarkers: widget.showLimitMarkers,` 改成 `limitStatus: _limitStatus,`。
   - `_buildStockName` 整個方法換成：

```dart
  Widget _buildStockName(ThemeData theme) {
    final marketLabel = widget.market == MarketCode.tpex ? '櫃' : null;
    final limit = _limitStatus;
    final name = widget.stockName;
    final caption = widget.live?.caption;

    return Row(
      children: [
        if (name != null)
          Flexible(
            child: Text(
              name,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        if (marketLabel != null) ...[
          const SizedBox(width: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: theme.colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(DesignTokens.radiusXs),
            ),
            child: Text(
              marketLabel,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSecondaryContainer,
                fontSize: DesignTokens.fontSizeXs,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
        // 漲停/跌停醒目標籤(鎖住加「鎖」)
        if (limit != PriceLimitStatus.none) ...[
          const SizedBox(width: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: AppTheme.getPriceColor(
                limit.isUp ? 1 : -1,
                Theme.of(context).brightness,
              ),
              borderRadius: BorderRadius.circular(DesignTokens.radiusXs),
            ),
            child: Text(
              S.priceLimitLabel(limit),
              style: theme.textTheme.labelSmall?.copyWith(
                color: Colors.white,
                fontSize: DesignTokens.fontSizeXs,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
        // 即時報價的例外標示(報價暫停／無報價／最後報價):放在名稱列,
        // 不增加卡片高度(格狀模式的卡片是固定高度)
        if (caption != null) ...[
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              caption,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: DesignTokens.fontSizeXs,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ],
    );
  }
```

6. `lib/presentation/widgets/stock_card_price.dart`：
   - 建構子的 `this.showLimitMarkers = true,` 換成 `this.limitStatus = PriceLimitStatus.none,`。
   - 欄位 `final bool showLimitMarkers;` 換成：

```dart
  /// 漲跌停狀態(由 StockCard 以 `PriceLimit.statusOf` 算好傳入;本元件不自行推算)
  final PriceLimitStatus limitStatus;
```

   - `build` 裡

```dart
    final isLimitUp = showLimitMarkers && PriceLimit.isLimitUp(priceChange);
    final isLimitDown = showLimitMarkers && PriceLimit.isLimitDown(priceChange);
```

     換成：

```dart
    final isLimitUp = limitStatus.isUp;
    final isLimitDown = limitStatus.isDown;
```

7. 掃一次 `StockCardPriceSection(` 與 `showLimitMarkers:` 的其他使用者：

```bash
grep -rn "StockCardPriceSection(" lib test
grep -rn "showLimitMarkers" lib/presentation/widgets/stock_card_price.dart test/presentation/widgets/stock_card_price_test.dart
```

Expected:
- 第一條只有 `stock_card.dart` 與 `stock_card_price_test.dart`。
- 第二條沒有輸出。

- [ ] **Step 4: 確認通過**

Run: `flutter test test/core/utils/price_limit_test.dart test/presentation/widgets/ test/core/l10n/`
Expected: 全部 PASS（`app_strings_keys_test` 抓到新 key 在兩個語系都存在）

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 5: 記錄進度**（不 commit）

---

### Task 3: 價格閃色（設定開關、閃色元件、對比度）

**Files:**
- Modify: `lib/core/constants/live_quote_params.dart`（`flashTintAlpha`）
- Create: `lib/presentation/widgets/price_flash.dart`
- Modify: `lib/presentation/widgets/stock_card_price.dart`、`lib/presentation/widgets/stock_card.dart`
- Modify: `lib/presentation/providers/settings_provider.dart`、`lib/presentation/screens/settings/settings_screen.dart`
- Modify: `assets/translations/zh-TW.json`、`en.json`（`settings.priceFlash`、`settings.priceFlashDesc`）
- Modify：設定頁的兩個 `FakeSettingsNotifier`（`test/presentation/screens/settings/settings_screen_test.dart`、`test/presentation/screens/golden/settings_screen_golden_test.dart`）
- Test: `test/presentation/widgets/price_flash_test.dart`（新）、`test/presentation/providers/settings_provider_test.dart`、`test/presentation/screens/settings/settings_screen_test.dart`、`test/presentation/widgets/stock_card_test.dart`

**Interfaces:**
- Consumes：Task 2 的 `StockCardLive.flash`／`flashEnabled`、`StockCardPriceSection`；第 1 段的 `LiveQuoteParams.flashFade`。
- Produces：
  - `LiveQuoteParams.flashTintAlpha`（0.2）。
  - `PriceFlash({required LiveQuoteFlash? flash, required bool enabled, required Widget child})`，以及 `static const Key PriceFlash.tintKey`。
  - `SettingsState.priceFlash`（預設 true）、`SettingsNotifier.setPriceFlash(bool)`。
  - `StockCardPriceSection({..., LiveQuoteFlash? flash, bool flashEnabled = true})`。

- [ ] **Step 1: 寫失敗測試**

1. 建立 `test/presentation/widgets/price_flash_test.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/constants/live_quote_params.dart';
import 'package:daredevil/core/theme/semantic_colors.dart';
import 'package:daredevil/domain/models/live_quote.dart';
import 'package:daredevil/presentation/widgets/price_flash.dart';

import '../../helpers/widget_test_helpers.dart';

/// 價格閃色(2026-10-06,spec §6)。
void main() {
  Widget host(
    LiveQuoteFlash? flash, {
    bool enabled = true,
    bool disableAnimations = false,
  }) => buildTestApp(
    Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(disableAnimations: disableAnimations),
        child: PriceFlash(
          flash: flash,
          enabled: enabled,
          child: const Text('100.00'),
        ),
      ),
    ),
  );

  Color? tint(WidgetTester tester) =>
      (tester.widget<DecoratedBox>(find.byKey(PriceFlash.tintKey)).decoration
              as BoxDecoration)
          .color;

  testWidgets('🚨 新的閃色事件 → 底色閃一下,淡出後消失', (tester) async {
    await tester.pumpWidget(host(const LiveQuoteFlash(id: 1, up: true)));
    expect(tint(tester), isNull, reason: '第一次建立不補閃');

    await tester.pumpWidget(host(const LiveQuoteFlash(id: 2, up: true)));
    await tester.pump();
    final peak = tint(tester)!;
    expect(peak.a, closeTo(LiveQuoteParams.flashTintAlpha, 0.02));
    expect(
      peak.withValues(alpha: 1),
      PriceColors.forChange(1, Brightness.light),
    );

    await tester.pump(LiveQuoteParams.flashFade);
    expect(tint(tester), isNull);
  });

  testWidgets('跌 → 跌色', (tester) async {
    await tester.pumpWidget(host(const LiveQuoteFlash(id: 1, up: false)));
    await tester.pumpWidget(host(const LiveQuoteFlash(id: 2, up: false)));
    await tester.pump();
    expect(
      tint(tester)!.withValues(alpha: 1),
      PriceColors.forChange(-1, Brightness.light),
    );
  });

  testWidgets('🚨 第一次建立就帶著事件(清單捲回來重建卡片)→ 不補閃', (tester) async {
    await tester.pumpWidget(host(const LiveQuoteFlash(id: 5, up: true)));
    await tester.pump();
    expect(tint(tester), isNull);
  });

  testWidgets('🚨 同一個事件再重建 → 不再閃', (tester) async {
    await tester.pumpWidget(host(const LiveQuoteFlash(id: 1, up: true)));
    await tester.pumpWidget(host(const LiveQuoteFlash(id: 2, up: true)));
    await tester.pump(LiveQuoteParams.flashFade);
    await tester.pumpWidget(host(const LiveQuoteFlash(id: 2, up: true)));
    await tester.pump();
    expect(tint(tester), isNull);
  });

  testWidgets('設定頁「價格閃色」關閉 → 不閃', (tester) async {
    await tester.pumpWidget(
      host(const LiveQuoteFlash(id: 1, up: true), enabled: false),
    );
    await tester.pumpWidget(
      host(const LiveQuoteFlash(id: 2, up: true), enabled: false),
    );
    await tester.pump();
    expect(tint(tester), isNull);
  });

  testWidgets('系統要求停用動畫(disableAnimations)→ 不閃', (tester) async {
    await tester.pumpWidget(
      host(const LiveQuoteFlash(id: 1, up: true), disableAnimations: true),
    );
    await tester.pumpWidget(
      host(const LiveQuoteFlash(id: 2, up: true), disableAnimations: true),
    );
    await tester.pump();
    expect(tint(tester), isNull);
  });

  testWidgets('🚨 iOS「減少動態效果」(reduceMotion)→ 不閃', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(reduceMotion: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pumpWidget(host(const LiveQuoteFlash(id: 1, up: true)));
    await tester.pumpWidget(host(const LiveQuoteFlash(id: 2, up: true)));
    await tester.pump();
    expect(tint(tester), isNull);
  });
}
```

2. `test/presentation/widgets/stock_card_test.dart`：
   - import 加：

```dart
import 'package:daredevil/domain/models/live_quote.dart';
import 'package:daredevil/presentation/widgets/price_flash.dart';
```

   - 在 Task 2 加的 group 內最後加：

```dart
      for (final brightness in [Brightness.light, Brightness.dark]) {
        for (final up in [true, false]) {
          testWidgets('🚨 閃色最濃時 $brightness ${up ? '漲' : '跌'}:現價數字對實際底色 ≥ 4.5', (
            tester,
          ) async {
            Widget card(int id) => buildTestApp(
              StockCard(
                symbol: '2330',
                stockName: '測試',
                latestClose: 100,
                priceChange: up ? 1 : -1,
                live: StockCardLive(flash: LiveQuoteFlash(id: id, up: up)),
              ),
              brightness: brightness,
            );
            await tester.pumpWidget(card(1));
            await tester.pumpWidget(card(2));
            await tester.pump();

            final tint =
                (tester
                            .widget<DecoratedBox>(
                              find.byKey(PriceFlash.tintKey),
                            )
                            .decoration
                        as BoxDecoration)
                    .color!;
            final cardColor = tester
                .widgetList<Container>(find.byType(Container))
                .map((c) => c.decoration)
                .whereType<BoxDecoration>()
                .firstWhere((d) => d.borderRadius == BorderRadius.circular(16))
                .color!;
            final textColor = tester
                .widget<RichText>(
                  find.descendant(
                    of: find.byKey(PriceFlash.tintKey),
                    matching: find.byType(RichText),
                  ),
                )
                .text
                .style!
                .color!;
            final composite = ColorContrast.compositeOver(
              tint.withValues(alpha: 1),
              cardColor,
              tint.a,
            );
            expect(
              ColorContrast.ratio(textColor, composite),
              greaterThanOrEqualTo(4.5),
            );
          });
        }
      }
```

3. `test/presentation/providers/settings_provider_test.dart`：
   - `'has correct default values'` 測試裡加一行 `expect(state.priceFlash, isTrue);`。
   - 在 `setShowROCYear changes value` 之後加：

```dart
    test('setPriceFlash changes value', () {
      final notifier = container.read(settingsProvider.notifier);
      notifier.setPriceFlash(false);
      expect(container.read(settingsProvider).priceFlash, isFalse);
    });

    test('🚨 setPriceFlash 寫入 SharedPreferences(重開 App 仍是關)', () async {
      container.read(settingsProvider.notifier).setPriceFlash(false);
      for (var i = 0; i < 10; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('settings_price_flash'), isFalse);
    });
```

   - `'loads settings from SharedPreferences'` 的 `setMockInitialValues({...})` 最後加一行 `'settings_price_flash': false,`，斷言區最後加 `expect(state.priceFlash, isFalse);`。

4. `test/presentation/screens/settings/settings_screen_test.dart`：
   - `FakeSettingsNotifier` 在 `setShowROCYear` 之後加：

```dart

  @override
  void setPriceFlash(bool value) {}
```

   - 在 `'shows ROC year switch'` 之後加：

```dart
    testWidgets('shows price flash switch', (tester) async {
      widenViewport(tester);

      await tester.pumpWidget(buildTestWidget());
      await tester.pump(const Duration(seconds: 1));

      expect(find.byIcon(Icons.flash_on_rounded), findsOneWidget);
    });
```

5. `test/presentation/screens/golden/settings_screen_golden_test.dart` 的 `FakeSettingsNotifier` 同樣在 `setShowROCYear` 之後加 `setPriceFlash` 的空覆寫。其他測試檔的 `FakeSettingsNotifier` 不需要加：它們不點這個開關。

- [ ] **Step 2: 確認紅燈**

Run: `flutter test test/presentation/widgets/price_flash_test.dart test/presentation/widgets/stock_card_test.dart test/presentation/providers/settings_provider_test.dart test/presentation/screens/settings/settings_screen_test.dart`
Expected: 編譯失敗（`price_flash.dart`、`flashTintAlpha`、`priceFlash`、`setPriceFlash` 未定義）

- [ ] **Step 3: 實作**

1. `lib/core/constants/live_quote_params.dart` 的 `flashFade` 之後加：

```dart

  /// 閃色底色最濃時的透明度。現價數字是一般文字色(不是紅綠),疊在 20% 的
  /// 紅綠底上兩種主題對比都遠高於 4.5(`stock_card_test` 的閃色對比度測試)
  static const double flashTintAlpha = 0.2;
```

2. 建立 `lib/presentation/widgets/price_flash.dart`：

```dart
import 'package:flutter/material.dart';

import 'package:daredevil/core/constants/live_quote_params.dart';
import 'package:daredevil/core/theme/design_tokens.dart';
import 'package:daredevil/core/theme/semantic_colors.dart';
import 'package:daredevil/domain/models/live_quote.dart';

/// 現價的閃色(盤中即時報價變動時,底色閃一下後淡出;2026-10-06)。
///
/// 只在收到新的閃色事件([flash] 的 id 變了)時閃。第一次建立時把現有的
/// id 當作已看過——清單捲回來重建卡片時不補閃。以下任一成立就不閃、只換
/// 數字:
/// - [enabled] 為 false(設定頁「價格閃色」);
/// - 系統要求停用動畫(`MediaQuery.disableAnimations`);
/// - iOS「減少動態效果」(`accessibilityFeatures.reduceMotion`)。
///
/// macOS 不回報系統的減少動態效果,只能靠設定頁的開關。
class PriceFlash extends StatefulWidget {
  const PriceFlash({
    super.key,
    required this.flash,
    required this.enabled,
    required this.child,
  });

  /// 閃色底色那一層的 key(測試讀實際渲染的顏色用)
  static const Key tintKey = ValueKey('priceFlashTint');

  final LiveQuoteFlash? flash;
  final bool enabled;
  final Widget child;

  @override
  State<PriceFlash> createState() => _PriceFlashState();
}

class _PriceFlashState extends State<PriceFlash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: LiveQuoteParams.flashFade,
  );
  int? _seenId;
  bool _up = true;

  @override
  void initState() {
    super.initState();
    _seenId = widget.flash?.id;
  }

  @override
  void didUpdateWidget(PriceFlash oldWidget) {
    super.didUpdateWidget(oldWidget);
    final flash = widget.flash;
    if (flash == null || flash.id == _seenId) return;
    _seenId = flash.id;
    if (!_motionAllowed) return;
    _up = flash.up;
    _controller.forward(from: 0);
  }

  bool get _motionAllowed =>
      widget.enabled &&
      !MediaQuery.disableAnimationsOf(context) &&
      !View.of(context).platformDispatcher.accessibilityFeatures.reduceMotion;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = PriceColors.forChange(
      _up ? 1 : -1,
      Theme.of(context).brightness,
    );
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final alpha = _controller.isAnimating
            ? LiveQuoteParams.flashTintAlpha * (1 - _controller.value)
            : 0.0;
        return DecoratedBox(
          key: PriceFlash.tintKey,
          decoration: BoxDecoration(
            color: alpha > 0 ? base.withValues(alpha: alpha) : null,
            borderRadius: BorderRadius.circular(DesignTokens.radiusXs),
          ),
          child: child,
        );
      },
    );
  }
}
```

3. `lib/presentation/widgets/stock_card_price.dart`：
   - import 加：

```dart
import 'package:daredevil/domain/models/live_quote.dart';
import 'package:daredevil/presentation/widgets/price_flash.dart';
```

   - 建構子在 `this.compact = false,` 之後加 `this.flash, this.flashEnabled = true,`。
   - 欄位加：

```dart

  /// 本輪閃色事件(盤中即時報價;見 [PriceFlash])
  final LiveQuoteFlash? flash;

  /// 設定頁「價格閃色」
  final bool flashEnabled;
```

   - `if (latestClose != null)` 底下的 `Text(latestClose!.toStringAsFixed(2), ...)` 整個包進 `PriceFlash(flash: flash, enabled: flashEnabled, child: Text(...))`（`Text` 內容不變）。

4. `lib/presentation/widgets/stock_card.dart` 的 `StockCardPriceSection(` 加兩個參數：

```dart
                                flash: widget.live?.flash,
                                flashEnabled: widget.live?.flashEnabled ?? true,
```

5. `lib/presentation/providers/settings_provider.dart`：
   - 鍵：`const _keyPriceFlash = 'settings_price_flash';`，放在 `_keyShowROCYear` 之後。
   - `SettingsState` 建構子：在 `this.showROCYear = true,` 之後加 `this.priceFlash = true,`。
   - 欄位：在 `showROCYear` 之後加：

```dart

  /// 盤中即時報價變動時,現價底色閃一下
  final bool priceFlash;
```

   - `copyWith`：參數加 `bool? priceFlash,`，body 加 `priceFlash: priceFlash ?? this.priceFlash,`。
   - `_loadSettings`：
     - 在 `final showROCYear = ...;` 之後加 `final priceFlash = prefs.getBool(_keyPriceFlash) ?? true;`；
     - `state = SettingsState(` 加 `priceFlash: priceFlash,`。
   - `_performSave`：在 `showROCYear` 那行之後加 `await prefs.setBool(_keyPriceFlash, snapshot.priceFlash);`。
   - setter：在 `setShowROCYear` 之後加：

```dart

  /// 設定價格閃色
  void setPriceFlash(bool value) {
    state = state.copyWith(priceFlash: value);
    _saveSettings();
    AppLogger.debug('SettingsNotifier', '價格閃色: $value');
  }
```

6. `lib/presentation/screens/settings/settings_screen.dart`：在 `settings.showROCYear` 那個 `_buildFeatureTile(...)` 之後加：

```dart
            _buildFeatureTile(
              context,
              settings.priceFlash,
              Icons.flash_on_rounded,
              Colors.amber,
              'settings.priceFlash'.tr(),
              (v) => ref.read(settingsProvider.notifier).setPriceFlash(v),
            ),
```

7. 翻譯（同 Task 2 的腳本寫法）：

```bash
python3 - <<'PY'
for path, old, new in [
    ('assets/translations/zh-TW.json',
     '    "showROCYearDesc": "在財報頁面使用民國年格式",\n',
     '    "showROCYearDesc": "在財報頁面使用民國年格式",\n    "priceFlash": "價格閃色",\n    "priceFlashDesc": "即時報價變動時，現價底色閃一下",\n'),
    ('assets/translations/en.json',
     '    "showROCYearDesc": "Use ROC calendar year in fundamentals tab",\n',
     '    "showROCYearDesc": "Use ROC calendar year in fundamentals tab",\n    "priceFlash": "Price Flash",\n    "priceFlashDesc": "Briefly tint the price when a live quote changes",\n'),
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

Run: `flutter test test/presentation/widgets/ test/presentation/providers/settings_provider_test.dart test/presentation/screens/settings/ test/core/`
Expected: 全部 PASS（閃色對比度八種組合都 ≥ 4.5）

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 5: 記錄進度**（不 commit）

---

### Task 4: 自選的合併後價格與排序

**Files:**
- Modify: `lib/domain/services/live_quote/live_quote_merge.dart`（`OfficialPrice` 相等比較、`MergedPrice.changePercent`）
- Modify: `lib/presentation/providers/watchlist_types.dart`、`lib/presentation/providers/watchlist_provider.dart`
- Create: `lib/presentation/providers/live_price_provider.dart`
- Test: `test/domain/services/live_quote/live_quote_merge_test.dart`、`test/presentation/providers/watchlist_live_price_test.dart`（新）、`test/presentation/providers/watchlist_provider_test.dart`、`test/presentation/providers/watchlist_provider_single_load_badge_test.dart`

**Interfaces:**
- Consumes：第 1 段的 `LiveQuoteMerge`、`MergedPrice`、`OfficialPrice`、`LiveQuoteEntry`、`liveQuoteCenterProvider`；`appClockProvider`。
- Produces：
  - `OfficialPrice` 的 `==`／`hashCode`；`double? MergedPrice.changePercent`。
  - `WatchlistItemData` 的新欄位 `DateTime? priceDate`、`double? priceChangeAmount`，以及方法 `MergedPrice mergedWith(LiveQuoteEntry? live, DateTime now)`、`double? changePercentWith(MergedPrice merged)`。
  - `WatchlistItemData? WatchlistState.itemOf(String symbol)`。
  - `void WatchlistNotifier.resortWithLive()`。排序（`priceChangeDesc`／`Asc`）改用合併後的漲跌幅。
  - `final watchlistLivePriceProvider = Provider.autoDispose.family<MergedPrice?, String>`。

- [ ] **Step 1: 寫失敗測試**

1. `test/domain/services/live_quote/live_quote_merge_test.dart` 最後加：

```dart
  test('MergedPrice.changePercent:以 previousClose 計;沒有昨收為 null', () {
    final m = LiveQuoteMerge.merge(
      official: official(DateTime(2026, 10, 5), 100),
      live: live(price: 102),
      now: morning,
    );
    expect(m.changePercent, closeTo(2.0, 1e-9));
    final none = LiveQuoteMerge.merge(official: null, live: null, now: morning);
    expect(none.changePercent, isNull);
  });

  test('OfficialPrice 值相等(讓 provider 的 select 不因新實例而重算)', () {
    expect(
      official(DateTime(2026, 10, 5), 100, change: 1),
      official(DateTime(2026, 10, 5), 100, change: 1),
    );
    expect(
      official(DateTime(2026, 10, 5), 100, change: 1),
      isNot(official(DateTime(2026, 10, 5), 100, change: 2)),
    );
  });
```

2. 建立 `test/presentation/providers/watchlist_live_price_test.dart`：

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/utils/clock.dart';
import 'package:daredevil/domain/models/live_quote.dart';
import 'package:daredevil/domain/services/live_quote/live_quote_merge.dart';
import 'package:daredevil/presentation/providers/live_price_provider.dart';
import 'package:daredevil/presentation/providers/live_quote_provider.dart';
import 'package:daredevil/presentation/providers/providers.dart';
import 'package:daredevil/presentation/providers/watchlist_provider.dart';

class _Clock implements AppClock {
  _Clock(this.value);
  final DateTime value;
  @override
  DateTime now() => value;
}

class _SeededWatchlist extends WatchlistNotifier {
  _SeededWatchlist(this.seed);
  final WatchlistState seed;

  @override
  WatchlistState build() {
    super.build();
    return seed;
  }
}

class _FixedCenter extends LiveQuoteCenter {
  _FixedCenter(this.initial);
  final LiveQuoteState initial;

  @override
  LiveQuoteState build() => initial;

  void emit(LiveQuoteState s) => state = s;
}

/// 自選的合併後價格與排序(2026-10-06,spec §5、§7「自選清單排序」)。
void main() {
  final morning = DateTime(2026, 10, 6, 10, 15);

  WatchlistItemData item(
    String symbol, {
    double close = 100,
    double pct = 1,
    DateTime? date,
  }) => WatchlistItemData(
    symbol: symbol,
    market: 'TWSE',
    latestClose: close,
    priceChange: pct,
    priceDate: date ?? DateTime(2026, 10, 5),
    priceChangeAmount: close - close / (1 + pct / 100),
  );

  LiveQuoteEntry entry(String symbol, double price, {double prev = 100}) =>
      LiveQuoteEntry(
        symbol: symbol,
        date: DateTime(2026, 10, 6),
        price: price,
        displaySource: LiveDisplaySource.trade,
        previousClose: prev,
        quoteTime: '10:14:50',
        isClosingQuote: false,
      );

  ({ProviderContainer c, _FixedCenter center}) setup(
    WatchlistState seed,
    LiveQuoteState live,
  ) {
    final center = _FixedCenter(live);
    final c = ProviderContainer(
      overrides: [
        appClockProvider.overrideWithValue(_Clock(morning)),
        watchlistProvider.overrideWith(() => _SeededWatchlist(seed)),
        liveQuoteCenterProvider.overrideWith(() => center),
      ],
    );
    addTearDown(c.dispose);
    return (c: c, center: center);
  }

  test('🚨 正式資料是昨天、有今天的即時 → 用即時價與以 MIS 昨收算的漲跌幅', () {
    final s = setup(
      WatchlistState(items: [item('A')]),
      LiveQuoteState(entries: {'A': entry('A', 105)}),
    );
    final m = s.c.read(watchlistLivePriceProvider('A'))!;
    expect(m.kind, MergedPriceKind.live);
    expect(m.price, 105);
    final row = s.c.read(watchlistProvider).itemOf('A')!;
    expect(row.changePercentWith(m), closeTo(5.0, 1e-9));
  });

  test('正式資料是今天 → 不看即時,漲跌幅沿用盤後', () {
    final s = setup(
      WatchlistState(
        items: [item('A', close: 101, pct: 1, date: DateTime(2026, 10, 6))],
      ),
      LiveQuoteState(entries: {'A': entry('A', 105)}),
    );
    final m = s.c.read(watchlistLivePriceProvider('A'))!;
    expect(m.kind, MergedPriceKind.official);
    expect(m.price, 101);
    expect(s.c.read(watchlistProvider).itemOf('A')!.changePercentWith(m), 1);
  });

  test('不在自選 → null', () {
    final s = setup(WatchlistState(), const LiveQuoteState());
    expect(s.c.read(watchlistLivePriceProvider('X')), isNull);
  });

  test('🚨 依漲跌幅排序用合併後的漲跌幅(與卡片顯示一致)', () {
    final s = setup(
      WatchlistState(items: [item('A', pct: 3), item('B', pct: 1)]),
      LiveQuoteState(
        entries: {'A': entry('A', 99), 'B': entry('B', 104)},
      ), // A 即時 -1%、B 即時 +4%
    );
    s.c.read(watchlistProvider.notifier).setSort(WatchlistSort.priceChangeDesc);
    expect([for (final i in s.c.read(watchlistProvider).items) i.symbol], [
      'B',
      'A',
    ]);
  });

  test('🚨 resortWithLive:依漲跌幅排序時用最新即時重排;其他排序不動', () {
    final s = setup(
      WatchlistState(
        items: [item('A', pct: 3), item('B', pct: 1)],
        sort: WatchlistSort.priceChangeDesc,
      ),
      const LiveQuoteState(),
    );
    final notifier = s.c.read(watchlistProvider.notifier);
    s.center.emit(
      LiveQuoteState(entries: {'A': entry('A', 99), 'B': entry('B', 104)}),
    );
    notifier.resortWithLive();
    expect([for (final i in s.c.read(watchlistProvider).items) i.symbol], [
      'B',
      'A',
    ]);

    final other = setup(
      WatchlistState(
        items: [item('A', pct: 3), item('B', pct: 1)],
        sort: WatchlistSort.addedDesc,
      ),
      LiveQuoteState(entries: {'A': entry('A', 99), 'B': entry('B', 104)}),
    );
    other.c.read(watchlistProvider.notifier).resortWithLive();
    expect([for (final i in other.c.read(watchlistProvider).items) i.symbol], [
      'A',
      'B',
    ]);
  });

  test('copyWith(改分組)保留價格日期與價差', () {
    final row = item('A').copyWith(groupId: 3, groupName: 'G');
    expect(row.priceDate, DateTime(2026, 10, 5));
    expect(row.priceChangeAmount, isNotNull);
  });
}
```

3. `test/presentation/providers/watchlist_provider_test.dart`：
   - import 加：

```dart
import 'package:daredevil/data/database/dao/user_dao.dart';
import 'package:daredevil/presentation/providers/settings_provider.dart';
```

   - 在 `class MockInsiderRepository ...` 之後加（`loadData` 讀 `settingsProvider`，不換成假的會去碰 SharedPreferences）：

```dart

class _FakeSettings extends SettingsNotifier {
  @override
  SettingsState build() => const SettingsState();
}
```

   - `group('WatchlistNotifier loadData', ...)` 內加（放在 `'handles error gracefully'` 之後）：

```dart
    test('🚨 項目帶出價格那一筆的日期與漲跌價差(合併規則判斷「是不是今天」用)', () async {
      final mockAnalysisRepo = MockAnalysisRepository();
      when(
        () => mockAnalysisRepo.findLatestAnalysisDate(),
      ).thenAnswer((_) async => DateTime(2026, 10, 5));
      final c = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(mockDb),
          cachedDbProvider.overrideWithValue(mockCachedDb),
          warningRepositoryProvider.overrideWithValue(mockWarningRepo),
          insiderRepositoryProvider.overrideWithValue(mockInsiderRepo),
          analysisRepositoryProvider.overrideWithValue(mockAnalysisRepo),
          settingsProvider.overrideWith(_FakeSettings.new),
        ],
      );
      addTearDown(c.dispose);
      when(() => mockDb.getWatchlistWithGroups()).thenAnswer(
        (_) async => [
          WatchlistWithGroup(
            entry: WatchlistEntry(
              symbol: '2330',
              createdAt: DateTime(2026, 9, 1),
            ),
          ),
        ],
      );
      when(() => mockDb.getWatchlistGroups()).thenAnswer((_) async => []);
      final price = DailyPriceEntry(
        symbol: '2330',
        date: DateTime(2026, 10, 5),
        close: 2575,
        priceChange: 15,
      );
      when(
        () => mockCachedDb.loadStockListData(
          symbols: any(named: 'symbols'),
          analysisDate: any(named: 'analysisDate'),
          historyStart: any(named: 'historyStart'),
        ),
      ).thenAnswer(
        (_) async => (
          stocks: <String, StockMasterEntry>{},
          latestPrices: {'2330': price},
          analyses: <String, DailyAnalysisEntry>{},
          reasons: <String, List<DailyReasonEntry>>{},
          priceHistories: {
            '2330': [price],
          },
        ),
      );
      when(
        () => mockWarningRepo.getWatchlistWarnings(any()),
      ).thenAnswer((_) async => {});
      when(
        () => mockInsiderRepo.getWatchlistHighPledgeStocks(
          any(),
          threshold: any(named: 'threshold'),
        ),
      ).thenAnswer((_) async => {});

      await c.read(watchlistProvider.notifier).loadData();

      final row = c.read(watchlistProvider).items.single;
      expect(row.priceDate, DateTime(2026, 10, 5));
      expect(row.priceChangeAmount, 15);
    });
```

（`WatchlistWithGroup` 在 `user_dao.dart`，`app_database.dart` 沒有匯出它；資料列型別 `StockMasterEntry` 等由 `app_database.dart` 匯出。）

4. `test/presentation/providers/watchlist_provider_single_load_badge_test.dart`：在 `group('單筆載入的警示徽章 gate（與批次 loadData 對齊）', ...)` 內最後加一條。`setUp` 預設 `getLatestPrice('2330')` 回 null，這條改成回傳有日期與價差的一筆（mocktail 以最後一次 `when` 為準）：

```dart
    test('🚨 單筆載入(新增/復原)同樣帶出價格日期與漲跌價差', () async {
      when(() => mockDb.getLatestPrice('2330')).thenAnswer(
        (_) async => DailyPriceEntry(
          symbol: '2330',
          date: DateTime(2026, 7, 22),
          close: 1000,
          priceChange: -5,
        ),
      );
      final container = buildContainer(showBadges: true);
      await container.read(watchlistProvider.notifier).addStock('2330');

      final row = container.read(watchlistProvider).itemOf('2330')!;
      expect(row.priceDate, DateTime(2026, 7, 22));
      expect(row.priceChangeAmount, -5);
    });
```

- [ ] **Step 2: 確認紅燈**

Run: `flutter test test/domain/services/live_quote/live_quote_merge_test.dart test/presentation/providers/watchlist_live_price_test.dart test/presentation/providers/watchlist_provider_test.dart test/presentation/providers/watchlist_provider_single_load_badge_test.dart`
Expected: 編譯失敗（`changePercent`、`priceDate`、`priceChangeAmount`、`itemOf`、`resortWithLive`、`live_price_provider.dart` 未定義）

- [ ] **Step 3: 實作**

1. `lib/domain/services/live_quote/live_quote_merge.dart`：
   - `OfficialPrice` 加：

```dart

  @override
  bool operator ==(Object other) =>
      other is OfficialPrice &&
      other.date == date &&
      other.close == close &&
      other.priceChange == priceChange;

  @override
  int get hashCode => Object.hash(date, close, priceChange);
```

   - `MergedPrice` 的 `quoteTime` getter 之後加：

```dart

  /// 以 [previousClose] 計的漲跌幅(%);沒有昨收為 null
  double? get changePercent {
    final p = price;
    final prev = previousClose;
    if (p == null || prev == null || prev <= 0) return null;
    return (p / prev - 1) * 100;
  }
```

2. `lib/presentation/providers/watchlist_types.dart`：
   - import 加：

```dart
import 'package:daredevil/domain/models/live_quote.dart';
import 'package:daredevil/domain/services/live_quote/live_quote_merge.dart';
```

   - `WatchlistItemData` 建構子在 `this.groupName,` 之後加 `this.priceDate, this.priceChangeAmount,`。
   - 欄位在 `groupName` 之後加：

```dart

  /// 價格那一筆的日期(批次載入綁分析日期的那一筆;新增/復原時為最新一筆)。
  /// 合併規則據此判斷畫面上是不是今天的正式資料
  final DateTime? priceDate;

  /// 交易所漲跌價差(金額,不是百分比);昨收 = 收盤 − 價差
  final double? priceChangeAmount;

  /// 依合併規則決定這一列要顯示的價格(見 `LiveQuoteMerge`)
  MergedPrice mergedWith(LiveQuoteEntry? live, DateTime now) =>
      LiveQuoteMerge.merge(
        official: OfficialPrice(
          date: priceDate,
          close: latestClose,
          priceChange: priceChangeAmount,
        ),
        live: live,
        now: now,
      );

  /// 要顯示的漲跌幅:用即時報價時以 MIS 昨收計,否則沿用盤後算好的 [priceChange]
  double? changePercentWith(MergedPrice merged) =>
      merged.kind == MergedPriceKind.live ? merged.changePercent : priceChange;
```

   - `copyWith` 的 `return WatchlistItemData(` 加 `priceDate: priceDate, priceChangeAmount: priceChangeAmount,`。

3. `lib/presentation/providers/watchlist_provider.dart`：
   - import 加 `import 'package:daredevil/presentation/providers/live_quote_provider.dart';`（`providers.dart` 已有，`appClockProvider` 從那裡來）。
   - `WatchlistState`：在 `filteredItems` getter 附近加：

```dart
  /// 依代號找項目;沒有回 null
  WatchlistItemData? itemOf(String symbol) {
    for (final item in items) {
      if (item.symbol == symbol) return item;
    }
    return null;
  }
```

   - `loadData` 建 `WatchlistItemData(` 時，在 `groupName: item.groupName,` 之後加：

```dart
          priceDate: latestPrice?.date,
          priceChangeAmount: latestPrice?.priceChange,
```

   - `_loadSingleStockData` 的 `return WatchlistItemData(` 在 `warningType: warningType,` 之後加同樣兩行。
   - `_sortItems` 的兩個漲跌幅 case 換成：

```dart
      case WatchlistSort.priceChangeDesc:
      case WatchlistSort.priceChangeAsc:
        // 與卡片顯示同一個值:有今天的即時報價時用合併後的漲跌幅
        final live = ref.read(liveQuoteCenterProvider).entries;
        final now = ref.read(appClockProvider).now();
        double change(WatchlistItemData i) =>
            i.changePercentWith(i.mergedWith(live[i.symbol], now)) ?? 0;
        sorted.sort(
          (a, b) => sort == WatchlistSort.priceChangeDesc
              ? change(b).compareTo(change(a))
              : change(a).compareTo(change(b)),
        );
```

   - `setSort` 之後加：

```dart

  /// 依目前的即時報價重新排序(只在依漲跌幅排序時有作用)。畫面在變為可見
  /// 後、第一輪即時資料完成時呼叫;其餘時間順序不動、只更新數字
  void resortWithLive() {
    if (state.sort != WatchlistSort.priceChangeDesc &&
        state.sort != WatchlistSort.priceChangeAsc) {
      return;
    }
    state = state.copyWith(items: _sortItems(state.items, state.sort));
  }
```


4. 建立 `lib/presentation/providers/live_price_provider.dart`：

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:daredevil/domain/services/live_quote/live_quote_merge.dart';
import 'package:daredevil/presentation/providers/live_quote_provider.dart';
import 'package:daredevil/presentation/providers/providers.dart';
import 'package:daredevil/presentation/providers/watchlist_provider.dart';

/// 自選某一檔要顯示的價格(依合併規則)。卡片、長按預覽、排序共用同一個
/// 結果,避免同一個數字兩個來源。不在自選清單裡回 null。
final watchlistLivePriceProvider = Provider.autoDispose
    .family<MergedPrice?, String>((ref, symbol) {
      final item = ref.watch(watchlistProvider.select((s) => s.itemOf(symbol)));
      if (item == null) return null;
      final live = ref.watch(
        liveQuoteCenterProvider.select((s) => s.entries[symbol]),
      );
      return item.mergedWith(live, ref.read(appClockProvider).now());
    });
```

- [ ] **Step 4: 確認通過**

Run: `flutter test test/domain/services/live_quote/ test/presentation/providers/`
Expected: 全部 PASS

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 5: 記錄進度**（不 commit）

---

### Task 5: 頁首狀態與卡片例外標示的規則

**Files:**
- Create: `lib/presentation/widgets/live_quote_status.dart`
- Modify: `lib/presentation/providers/live_price_provider.dart`（`watchlistLiveHeaderProvider`）
- Modify: `assets/translations/zh-TW.json`、`en.json`（`liveQuote.*`）
- Test: `test/presentation/widgets/live_quote_status_test.dart`（新）

**Interfaces:**
- Consumes：
  - 第 1 段的 `LiveQuoteState`、`LiveSymbolStatus`、`LiveQuoteSchedule.secondsOfDay`；
  - Task 4 的 `MergedPrice`、`watchlistProvider.itemOf`、`WatchlistItemData.mergedWith`。
- Produces：
  - `enum LiveHeaderKind { pausedRateLimit, pausedNetwork, noQuotesToday, quoteTime, closingPending, lastQuote }`。
  - `class LiveHeaderStatus { LiveHeaderKind kind; String? time; String text(); }`。
  - `enum LiveCardCaptionKind { paused, noQuote, lastQuote }`。
  - `class LiveCardCaption { kind; time; String text(); }`。
  - `LiveQuoteStatusRule.header({required LiveQuoteState state, required Iterable<MergedPrice> merged, required String? intradayTime}) → LiveHeaderStatus?`。
  - `LiveQuoteStatusRule.card({required LiveSymbolStatus? status, required MergedPrice merged}) → LiveCardCaption?`。
  - `final watchlistLiveHeaderProvider = Provider.autoDispose<LiveHeaderStatus?>`。

- [ ] **Step 1: 寫失敗測試**

建立 `test/presentation/widgets/live_quote_status_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/domain/models/live_quote.dart';
import 'package:daredevil/domain/services/live_quote/live_quote_merge.dart';
import 'package:daredevil/presentation/providers/live_quote_provider.dart';
import 'package:daredevil/presentation/widgets/live_quote_status.dart';

/// 頁首狀態與卡片例外標示(2026-10-06,spec §7「共通」)。
void main() {
  final morning = DateTime(2026, 10, 6, 10, 15);
  final afterClose = DateTime(2026, 10, 6, 14, 10);

  MergedPrice live(
    DateTime now, {
    bool closing = false,
    String time = '10:14:50',
  }) => LiveQuoteMerge.merge(
    official: OfficialPrice(date: DateTime(2026, 10, 5), close: 100),
    live: LiveQuoteEntry(
      symbol: 'A',
      date: DateTime(2026, 10, 6),
      price: 101,
      displaySource: LiveDisplaySource.trade,
      previousClose: 100,
      quoteTime: time,
      isClosingQuote: closing,
    ),
    now: now,
  );

  MergedPrice official(DateTime now) => LiveQuoteMerge.merge(
    official: OfficialPrice(date: DateTime(2026, 10, 6), close: 101),
    live: null,
    now: now,
  );

  LiveHeaderStatus? header(
    LiveQuoteState state,
    List<MergedPrice> merged, {
    String? intraday,
  }) => LiveQuoteStatusRule.header(
    state: state,
    merged: merged,
    intradayTime: intraday,
  );

  group('頁首(依序取第一個成立的)', () {
    test('🚨 限流優先於網路暫停,時間只到分', () {
      final s = header(
        LiveQuoteState(
          stalled: true,
          rateLimitedUntil: DateTime(2026, 10, 6, 10, 20, 31),
        ),
        [live(morning)],
      );
      expect(
        s,
        const LiveHeaderStatus(LiveHeaderKind.pausedRateLimit, '10:20'),
      );
    });

    test('網路暫停附最後更新時間;從沒回應過則不附時間', () {
      expect(
        header(
          LiveQuoteState(
            stalled: true,
            lastRespondedAt: DateTime(2026, 10, 6, 10, 13, 5),
          ),
          [live(morning)],
        ),
        const LiveHeaderStatus(LiveHeaderKind.pausedNetwork, '10:13:05'),
      );
      expect(
        header(const LiveQuoteState(stalled: true), const []),
        const LiveHeaderStatus(LiveHeaderKind.pausedNetwork),
      );
    });

    test('🚨 第一輪回應前不顯示「尚無報價」;最近一輪全不是今天才顯示', () {
      expect(header(const LiveQuoteState(), const []), isNull);
      expect(
        header(const LiveQuoteState(latestResponseHadToday: false), const []),
        const LiveHeaderStatus(LiveHeaderKind.noQuotesToday),
      );
    });

    test('盤中有卡片用即時 → 本輪報價時間', () {
      expect(
        header(
          const LiveQuoteState(latestResponseHadToday: true),
          [live(morning), official(morning)],
          intraday: '10:14:58',
        ),
        const LiveHeaderStatus(LiveHeaderKind.quoteTime, '10:14:58'),
      );
    });

    test('🚨 收盤後用即時的卡片全是收盤報價 → 今日收盤', () {
      expect(
        header(const LiveQuoteState(latestResponseHadToday: true), [
          live(afterClose, closing: true, time: '13:30:00'),
          official(afterClose),
        ]),
        const LiveHeaderStatus(LiveHeaderKind.closingPending),
      );
    });

    test('🚨 收盤後有一張不是收盤報價 → 最後報價,取最舊的時間,不寫今日收盤', () {
      expect(
        header(const LiveQuoteState(latestResponseHadToday: true), [
          live(afterClose, closing: true, time: '13:30:00'),
          live(afterClose, time: '13:29:40'),
          live(afterClose, time: '13:25:00'),
        ]),
        const LiveHeaderStatus(LiveHeaderKind.lastQuote, '13:25:00'),
      );
    });

    test('全部用正式資料 → 不顯示', () {
      expect(
        header(const LiveQuoteState(latestResponseHadToday: true), [
          official(afterClose),
        ]),
        isNull,
      );
    });
  });

  group('卡片例外標示', () {
    test('🚨 已有今天正式資料 → 不標(即使最近一輪批次失敗)', () {
      expect(
        LiveQuoteStatusRule.card(
          status: LiveSymbolStatus.batchFailed,
          merged: official(afterClose),
        ),
        isNull,
      );
    });

    test('批次失敗 → 報價暫停;有回應沒報價 → 無報價', () {
      expect(
        LiveQuoteStatusRule.card(
          status: LiveSymbolStatus.batchFailed,
          merged: live(morning),
        ),
        const LiveCardCaption(LiveCardCaptionKind.paused),
      );
      expect(
        LiveQuoteStatusRule.card(
          status: LiveSymbolStatus.noQuote,
          merged: live(morning),
        ),
        const LiveCardCaption(LiveCardCaptionKind.noQuote),
      );
    });

    test('收盤後不是收盤報價 → 最後報價 HH:MM:SS;盤中與收盤報價不標', () {
      expect(
        LiveQuoteStatusRule.card(
          status: LiveSymbolStatus.ok,
          merged: live(afterClose, time: '13:29:40'),
        ),
        const LiveCardCaption(LiveCardCaptionKind.lastQuote, '13:29:40'),
      );
      expect(
        LiveQuoteStatusRule.card(
          status: LiveSymbolStatus.ok,
          merged: live(morning),
        ),
        isNull,
      );
      expect(
        LiveQuoteStatusRule.card(
          status: LiveSymbolStatus.ok,
          merged: live(afterClose, closing: true, time: '13:30:00'),
        ),
        isNull,
      );
    });
  });

  test('文字走 i18n key(未載入翻譯時回 key)', () {
    expect(
      const LiveHeaderStatus(LiveHeaderKind.noQuotesToday).text(),
      'liveQuote.noQuotesToday',
    );
    expect(
      const LiveCardCaption(LiveCardCaptionKind.paused).text(),
      'liveQuote.cardPaused',
    );
  });
}
```

- [ ] **Step 2: 確認紅燈**

Run: `flutter test test/presentation/widgets/live_quote_status_test.dart`
Expected: 編譯失敗（`live_quote_status.dart` 不存在）

- [ ] **Step 3: 實作**

1. 建立 `lib/presentation/widgets/live_quote_status.dart`：

```dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart' show immutable;

import 'package:daredevil/domain/models/live_quote.dart';
import 'package:daredevil/domain/services/live_quote/live_quote_merge.dart';
import 'package:daredevil/domain/services/live_quote/live_quote_schedule.dart';
import 'package:daredevil/presentation/providers/live_quote_provider.dart';

enum LiveHeaderKind {
  pausedRateLimit,
  pausedNetwork,
  noQuotesToday,
  quoteTime,
  closingPending,
  lastQuote,
}

/// 頁首(自選)或價格下方(個股頁)的即時報價狀態
@immutable
class LiveHeaderStatus {
  const LiveHeaderStatus(this.kind, [this.time]);

  final LiveHeaderKind kind;

  /// 限流的再試時刻為 HH:MM,其餘為 HH:MM:SS;沒有時間為 null
  final String? time;

  String text() {
    final t = time;
    return switch (kind) {
      LiveHeaderKind.pausedRateLimit => 'liveQuote.pausedRateLimit'.tr(
        namedArgs: {'time': t ?? ''},
      ),
      LiveHeaderKind.pausedNetwork =>
        t == null
            ? 'liveQuote.pausedNetworkNoTime'.tr()
            : 'liveQuote.pausedNetwork'.tr(namedArgs: {'time': t}),
      LiveHeaderKind.noQuotesToday => 'liveQuote.noQuotesToday'.tr(),
      LiveHeaderKind.quoteTime => 'liveQuote.quoteTime'.tr(
        namedArgs: {'time': t ?? ''},
      ),
      LiveHeaderKind.closingPending => 'liveQuote.closingPending'.tr(),
      LiveHeaderKind.lastQuote => 'liveQuote.lastQuote'.tr(
        namedArgs: {'time': t ?? ''},
      ),
    };
  }

  @override
  bool operator ==(Object other) =>
      other is LiveHeaderStatus && other.kind == kind && other.time == time;

  @override
  int get hashCode => Object.hash(kind, time);

  @override
  String toString() => 'LiveHeaderStatus($kind, $time)';
}

enum LiveCardCaptionKind { paused, noQuote, lastQuote }

/// 卡片上的例外標示
@immutable
class LiveCardCaption {
  const LiveCardCaption(this.kind, [this.time]);

  final LiveCardCaptionKind kind;
  final String? time;

  String text() => switch (kind) {
    LiveCardCaptionKind.paused => 'liveQuote.cardPaused'.tr(),
    LiveCardCaptionKind.noQuote => 'liveQuote.cardNoQuote'.tr(),
    LiveCardCaptionKind.lastQuote => 'liveQuote.lastQuote'.tr(
      namedArgs: {'time': time ?? ''},
    ),
  };

  @override
  bool operator ==(Object other) =>
      other is LiveCardCaption && other.kind == kind && other.time == time;

  @override
  int get hashCode => Object.hash(kind, time);

  @override
  String toString() => 'LiveCardCaption($kind, $time)';
}

/// 即時報價的頁首狀態與卡片標示規則(spec §7「共通」)
abstract final class LiveQuoteStatusRule {
  /// 頁首狀態,依序取第一個成立的:
  /// 1. 報價暫停(限流優先於網路);
  /// 2. 證交所今天尚無報價(最近一輪有回應、但全部不是今天;第一輪回應前不顯示);
  /// 3. 有卡片用即時報價:盤中為 [intradayTime];收盤後全是收盤報價為
  ///    「今日收盤」,否則「最後報價」取最舊的那筆時間;
  /// 4. 都沒有 → null。
  static LiveHeaderStatus? header({
    required LiveQuoteState state,
    required Iterable<MergedPrice> merged,
    required String? intradayTime,
  }) {
    final until = state.rateLimitedUntil;
    if (until != null) {
      return LiveHeaderStatus(LiveHeaderKind.pausedRateLimit, hm(until));
    }
    if (state.stalled) {
      final at = state.lastRespondedAt;
      return LiveHeaderStatus(
        LiveHeaderKind.pausedNetwork,
        at == null ? null : hms(at),
      );
    }
    if (state.latestResponseHadToday == false) {
      return const LiveHeaderStatus(LiveHeaderKind.noQuotesToday);
    }
    final live = [
      for (final m in merged)
        if (m.kind == MergedPriceKind.live) m,
    ];
    if (live.isEmpty) return null;
    if (live.any((m) => m.label == LiveQuoteLabel.quoteTime)) {
      return LiveHeaderStatus(
        LiveHeaderKind.quoteTime,
        intradayTime ?? _latest(live),
      );
    }
    final lastQuotes = [
      for (final m in live)
        if (m.label == LiveQuoteLabel.lastQuote) m,
    ];
    if (lastQuotes.isEmpty) {
      return const LiveHeaderStatus(LiveHeaderKind.closingPending);
    }
    return LiveHeaderStatus(LiveHeaderKind.lastQuote, _oldest(lastQuotes));
  }

  /// 卡片例外標示:畫面已有今天的正式資料時不標;否則批次失敗 → 報價暫停、
  /// 有回應沒報價 → 無報價、收盤後不是收盤報價 → 最後報價 HH:MM:SS
  static LiveCardCaption? card({
    required LiveSymbolStatus? status,
    required MergedPrice merged,
  }) {
    if (merged.kind == MergedPriceKind.official) return null;
    switch (status) {
      case LiveSymbolStatus.batchFailed:
        return const LiveCardCaption(LiveCardCaptionKind.paused);
      case LiveSymbolStatus.noQuote:
        return const LiveCardCaption(LiveCardCaptionKind.noQuote);
      case LiveSymbolStatus.ok:
      case null:
        break;
    }
    if (merged.label == LiveQuoteLabel.lastQuote) {
      return LiveCardCaption(LiveCardCaptionKind.lastQuote, merged.quoteTime);
    }
    return null;
  }

  static String hms(DateTime t) =>
      '${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}';

  static String hm(DateTime t) => '${_two(t.hour)}:${_two(t.minute)}';

  static String _two(int v) => v.toString().padLeft(2, '0');

  static String? _latest(List<MergedPrice> ms) => _pick(ms, (a, b) => a > b);

  static String? _oldest(List<MergedPrice> ms) => _pick(ms, (a, b) => a < b);

  static String? _pick(List<MergedPrice> ms, bool Function(int, int) better) {
    String? best;
    int? bestSeconds;
    for (final m in ms) {
      final s = LiveQuoteSchedule.secondsOfDay(m.quoteTime);
      if (s == null) continue;
      if (bestSeconds == null || better(s, bestSeconds)) {
        best = m.quoteTime;
        bestSeconds = s;
      }
    }
    return best;
  }
}
```

2. `lib/presentation/providers/live_price_provider.dart`：
   - import 加 `import 'package:daredevil/presentation/widgets/live_quote_status.dart';`。
   - 檔尾加：

```dart

/// 自選頁首的即時報價狀態(見 [LiveQuoteStatusRule.header])
final watchlistLiveHeaderProvider = Provider.autoDispose<LiveHeaderStatus?>((
  ref,
) {
  final items = ref.watch(watchlistProvider.select((s) => s.items));
  final center = ref.watch(liveQuoteCenterProvider);
  final now = ref.read(appClockProvider).now();
  return LiveQuoteStatusRule.header(
    state: center,
    merged: [
      for (final item in items)
        item.mergedWith(center.entries[item.symbol], now),
    ],
    intradayTime: center.latestQuoteTime,
  );
});
```

3. 翻譯（新增最上層的 `liveQuote` 區段，放在 `price` 之後；同 Task 2 的腳本寫法）：

```bash
python3 - <<'PY'
zh = '''  "liveQuote": {
    "pausedRateLimit": "報價暫停（證交所限流，{time} 再試）",
    "pausedNetwork": "報價暫停（網路）・最後更新 {time}",
    "pausedNetworkNoTime": "報價暫停（網路）",
    "noQuotesToday": "證交所今天尚無報價",
    "quoteTime": "報價時間 {time}",
    "closingPending": "今日收盤・待盤後更新",
    "lastQuote": "最後報價 {time}",
    "cardPaused": "報價暫停",
    "cardNoQuote": "無報價"
  },
'''
en = '''  "liveQuote": {
    "pausedRateLimit": "Quotes paused (exchange rate limit, retrying at {time})",
    "pausedNetwork": "Quotes paused (network) · last update {time}",
    "pausedNetworkNoTime": "Quotes paused (network)",
    "noQuotesToday": "No quotes from the exchange yet today",
    "quoteTime": "Quoted at {time}",
    "closingPending": "Today's close · after-hours data pending",
    "lastQuote": "Last quote {time}",
    "cardPaused": "Quote paused",
    "cardNoQuote": "No quote"
  },
'''
for path, block in [('assets/translations/zh-TW.json', zh), ('assets/translations/en.json', en)]:
    s = open(path, encoding='utf-8').read()
    anchor = '  "reasons": {\n'
    assert s.count(anchor) == 1, (path, s.count(anchor))
    open(path, 'w', encoding='utf-8').write(s.replace(anchor, block + anchor))
import json
for p in ('assets/translations/zh-TW.json', 'assets/translations/en.json'):
    d = json.load(open(p, encoding='utf-8'))
    assert len(d['liveQuote']) == 9
print('ok')
PY
```

- [ ] **Step 4: 確認通過**

Run: `flutter test test/presentation/widgets/live_quote_status_test.dart test/core/l10n/`
Expected: 全部 PASS（`no_investment_advice_copy_test` 不受新文案影響）

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 5: 記錄進度**（不 commit）

---

### Task 6: 自選畫面接上即時報價

**Files:**
- Modify: `test/helpers/provider_test_helpers.dart`（`InertLiveQuoteCenter`、`liveQuoteCenter:`）
- Create: `lib/presentation/screens/watchlist/watchlist_live_view.dart`
- Modify: `lib/presentation/screens/watchlist/watchlist_stock_item.dart`、`watchlist_screen.dart`
- Test: `test/presentation/screens/watchlist/watchlist_live_view_test.dart`（新）、`test/presentation/screens/watchlist/watchlist_screen_test.dart`、`test/presentation/live_quote_screen_scope_test.dart`（新）

**Interfaces:**
- Consumes：
  - Task 2：`StockCardLive`、`StockCard.live`。
  - Task 3：`SettingsState.priceFlash`。
  - Task 4：`watchlistLivePriceProvider`、`WatchlistItemData.priceDate`／`changePercentWith`、`WatchlistNotifier.resortWithLive`。
  - Task 5：`LiveQuoteStatusRule`、`watchlistLiveHeaderProvider`。
  - 第 1 段：`LiveQuoteScope`、`LiveQuoteRegistration`。
- Produces：
  - `class WatchlistLiveView { double? price; double? changePercent; List<double> recentPrices; StockCardLive? card; factory WatchlistLiveView.of({required WatchlistItemData item, required MergedPrice merged, required bool flashEnabled, String? caption}) }`。
  - `WatchlistStockItem`／`WatchlistStockGridItem` 的選填參數 `WatchlistLiveView? live`。
  - 測試輔助：`class InertLiveQuoteCenter extends LiveQuoteCenter`；`buildProviderTestApp(..., LiveQuoteCenter Function()? liveQuoteCenter)`。

- [ ] **Step 1: 寫失敗測試**

1. 建立 `test/presentation/screens/watchlist/watchlist_live_view_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/domain/models/live_quote.dart';
import 'package:daredevil/domain/services/live_quote/live_quote_merge.dart';
import 'package:daredevil/presentation/providers/watchlist_provider.dart';
import 'package:daredevil/presentation/screens/watchlist/watchlist_live_view.dart';

/// 自選列的即時顯示結果(2026-10-06,spec §7 自選清單)。
void main() {
  final morning = DateTime(2026, 10, 6, 10, 15);
  final row = WatchlistItemData(
    symbol: 'A',
    market: 'TWSE',
    latestClose: 100,
    priceChange: 1,
    priceDate: DateTime(2026, 10, 5),
    priceChangeAmount: 1,
    recentPrices: const [97, 98, 99, 100],
  );

  LiveQuoteEntry entry({bool locked = false, int? flashId}) => LiveQuoteEntry(
    symbol: 'A',
    date: DateTime(2026, 10, 6),
    price: locked ? 110 : 103,
    displaySource: locked ? LiveDisplaySource.locked : LiveDisplaySource.trade,
    previousClose: 100,
    quoteTime: '10:14:50',
    isClosingQuote: false,
    limitUp: 110,
    limitDown: 90,
    isLimitUpLocked: locked,
    flash: flashId == null ? null : LiveQuoteFlash(id: flashId, up: true),
  );

  test('🚨 用即時:價格、以 MIS 昨收算的漲跌幅、走勢小圖接上即時價、帶漲跌停價與閃色', () {
    final v = WatchlistLiveView.of(
      item: row,
      merged: row.mergedWith(entry(flashId: 3), morning),
      flashEnabled: true,
    );
    expect(v.price, 103);
    expect(v.changePercent, closeTo(3.0, 1e-9));
    expect(v.recentPrices, [97, 98, 99, 100, 103]);
    expect(v.card!.limitUp, 110);
    expect(v.card!.flash!.id, 3);
    expect(v.card!.flashEnabled, isTrue);
  });

  test('🚨 鎖漲停 → 帶鎖住旗標', () {
    final v = WatchlistLiveView.of(
      item: row,
      merged: row.mergedWith(entry(locked: true), morning),
      flashEnabled: false,
    );
    expect(v.card!.limitUpLocked, isTrue);
    expect(v.card!.flashEnabled, isFalse);
  });

  test('🚨 畫面已有今天正式資料 → 走勢小圖不重複接、不帶即時欄位', () {
    final today = WatchlistItemData(
      symbol: 'A',
      market: 'TWSE',
      latestClose: 101,
      priceChange: 1,
      priceDate: DateTime(2026, 10, 6),
      priceChangeAmount: 1,
      recentPrices: const [99, 100, 101],
    );
    final v = WatchlistLiveView.of(
      item: today,
      merged: today.mergedWith(entry(), morning),
      flashEnabled: true,
    );
    expect(v.price, 101);
    expect(v.changePercent, 1);
    expect(v.recentPrices, [99, 100, 101]);
    expect(v.card, isNull);
  });

  test('沒有即時但有例外標示 → 只帶標示', () {
    final v = WatchlistLiveView.of(
      item: row,
      merged: row.mergedWith(null, morning),
      flashEnabled: true,
      caption: 'liveQuote.cardPaused',
    );
    expect(v.price, 100);
    expect(v.card!.caption, 'liveQuote.cardPaused');
    expect(v.card!.limitUp, isNull);
  });
}
```

2. `test/presentation/screens/watchlist/watchlist_screen_test.dart`：

   - import 加：

```dart
import 'package:daredevil/core/theme/color_contrast.dart';
import 'package:daredevil/core/utils/clock.dart';
import 'package:daredevil/domain/models/live_quote.dart';
import 'package:daredevil/presentation/providers/live_quote_provider.dart';
import 'package:daredevil/presentation/providers/providers.dart';
import 'package:daredevil/presentation/widgets/stock_card_sparkline.dart';
```

   - `FakeWatchlistNotifier` 加計數：

```dart
  int resortCalls = 0;

  @override
  void resortWithLive() => resortCalls++;
```

   - 檔內加兩個假物件（放在 `FakeWatchlistNotifier` 之後）：

```dart
class _Clock implements AppClock {
  _Clock(this.value);
  final DateTime value;
  @override
  DateTime now() => value;
}

/// 記錄登記、可推送新狀態的報價中心(不發請求)
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

  void emit(LiveQuoteState s) => state = s;
}
```

   - `buildTestWidget` 的參數在 `Widget Function(Widget screen)? wrap,` 之後加 `_LiveCenter? liveCenter, DateTime? now,`；`overrides:` 清單最後（`settingsProvider.overrideWith(...)` 之後）加 `if (now != null) appClockProvider.overrideWithValue(_Clock(now)),`；`brightness: brightness,` 之後加 `liveQuoteCenter: liveCenter == null ? null : () => liveCenter,`。
   - 在 `main()` 最後加：

```dart
  group('盤中即時報價', () {
    final morning = DateTime(2026, 10, 6, 10, 15);

    WatchlistItemData row({String symbol = '2330', DateTime? date}) =>
        WatchlistItemData(
          symbol: symbol,
          stockName: '測試$symbol',
          market: 'TWSE',
          latestClose: 100,
          priceChange: -1,
          priceDate: date ?? DateTime(2026, 10, 5),
          priceChangeAmount: -1.01,
          recentPrices: const [95, 96, 97, 98, 99, 100, 101, 100],
        );

    LiveQuoteEntry entry({
      double price = 101,
      DateTime? date,
      bool closing = false,
      String time = '10:14:50',
      bool lockedUp = false,
    }) => LiveQuoteEntry(
      symbol: '2330',
      date: date ?? DateTime(2026, 10, 6),
      price: price,
      displaySource: LiveDisplaySource.trade,
      previousClose: 100,
      quoteTime: time,
      isClosingQuote: closing,
      limitUp: 110,
      limitDown: 90,
      isLimitUpLocked: lockedUp,
    );

    testWidgets('🚨 登記自選的每一檔(市場別、是否已有今天正式資料)', (tester) async {
      widenViewport(tester);
      final center = _LiveCenter(const LiveQuoteState());
      await tester.pumpWidget(
        buildTestWidget(
          watchlistState: WatchlistState(
            items: [
              row(),
              row(symbol: '6538', date: DateTime(2026, 10, 6)),
            ],
          ),
          liveCenter: center,
          now: morning,
        ),
      );
      await tester.pump();

      final regs = center.registered.values.single;
      expect(regs, const [
        LiveQuoteRegistration(symbol: '2330', market: 'TWSE'),
        LiveQuoteRegistration(
          symbol: '6538',
          market: 'TWSE',
          hasOfficialToday: true,
        ),
      ]);
    });

    testWidgets('🚨 卡片顯示即時價與以昨收算的漲跌幅;走勢小圖最後一點接即時價', (tester) async {
      widenViewport(tester);
      final center = _LiveCenter(
        LiveQuoteState(entries: {'2330': entry(price: 103)}),
      );
      await tester.pumpWidget(
        buildTestWidget(
          watchlistState: WatchlistState(items: [row()]),
          liveCenter: center,
          now: morning,
        ),
      );
      await tester.pump();

      expect(find.text('103.00'), findsOneWidget);
      expect(find.text('100.00'), findsNothing);
      expect(
        tester.widget<MiniSparkline>(find.byType(MiniSparkline)).prices.last,
        103,
      );
    });

    testWidgets('🚨 App 開著過夜:隔天盤前不顯示昨天的即時價', (tester) async {
      widenViewport(tester);
      final center = _LiveCenter(
        LiveQuoteState(
          entries: {
            '2330': entry(price: 103, closing: true, time: '13:30:00'),
          },
        ),
      );
      await tester.pumpWidget(
        buildTestWidget(
          watchlistState: WatchlistState(items: [row()]),
          liveCenter: center,
          now: DateTime(2026, 10, 7, 8, 30),
        ),
      );
      await tester.pump();

      expect(find.text('100.00'), findsOneWidget);
      expect(find.text('103.00'), findsNothing);
      expect(find.textContaining('liveQuote.closingPending'), findsNothing);
    });

    testWidgets('鎖漲停 → 名稱列「漲停鎖」', (tester) async {
      widenViewport(tester);
      final center = _LiveCenter(
        LiveQuoteState(entries: {'2330': entry(price: 110, lockedUp: true)}),
      );
      await tester.pumpWidget(
        buildTestWidget(
          watchlistState: WatchlistState(items: [row()]),
          liveCenter: center,
          now: morning,
        ),
      );
      await tester.pump();

      expect(find.text('price.limitUpLocked'), findsOneWidget);
    });

    testWidgets('批次失敗 → 卡片標「報價暫停」', (tester) async {
      widenViewport(tester);
      final center = _LiveCenter(
        LiveQuoteState(
          entries: {'2330': entry()},
          symbolStatus: const {'2330': LiveSymbolStatus.batchFailed},
        ),
      );
      await tester.pumpWidget(
        buildTestWidget(
          watchlistState: WatchlistState(items: [row()]),
          liveCenter: center,
          now: morning,
        ),
      );
      await tester.pump();

      expect(find.text('liveQuote.cardPaused'), findsOneWidget);
    });

    // 頁首兩種狀態分兩條:同一個測試裡換報價中心再 pump,ProviderScope
    // 不會重建已建立的 override,第二段會讀到第一段的報價中心
    testWidgets('頁首:盤中顯示本輪報價時間', (tester) async {
      widenViewport(tester);
      final center = _LiveCenter(
        LiveQuoteState(
          entries: {'2330': entry()},
          latestResponseHadToday: true,
          latestQuoteTime: '10:14:58',
        ),
      );
      await tester.pumpWidget(
        buildTestWidget(
          watchlistState: WatchlistState(items: [row()]),
          liveCenter: center,
          now: morning,
        ),
      );
      await tester.pump();
      expect(find.textContaining('liveQuote.quoteTime'), findsOneWidget);
    });

    testWidgets('🚨 頁首:收盤後全是收盤報價 → 今日收盤・待盤後更新', (tester) async {
      widenViewport(tester);
      final center = _LiveCenter(
        LiveQuoteState(
          entries: {'2330': entry(closing: true, time: '13:30:00')},
          latestResponseHadToday: true,
        ),
      );
      await tester.pumpWidget(
        buildTestWidget(
          watchlistState: WatchlistState(items: [row()]),
          liveCenter: center,
          now: DateTime(2026, 10, 6, 14, 10),
        ),
      );
      await tester.pump();
      expect(find.textContaining('liveQuote.closingPending'), findsOneWidget);
    });

    for (final brightness in [Brightness.light, Brightness.dark]) {
      testWidgets('🚨 頁首「報價暫停」灰字 $brightness:對實際底色 ≥ 4.5', (tester) async {
        widenViewport(tester);
        final center = _LiveCenter(
          LiveQuoteState(
            stalled: true,
            lastRespondedAt: DateTime(2026, 10, 6, 10, 13, 5),
          ),
        );
        await tester.pumpWidget(
          buildTestWidget(
            watchlistState: WatchlistState(items: [row()]),
            liveCenter: center,
            now: morning,
            brightness: brightness,
          ),
        );
        await tester.pump();

        final text = find.textContaining('liveQuote.pausedNetwork');
        expect(text, findsOneWidget);
        final color = tester.widget<Text>(text).style!.color!;
        final background = Theme.of(
          tester.element(text),
        ).scaffoldBackgroundColor;
        expect(
          ColorContrast.ratio(color, background),
          greaterThanOrEqualTo(4.5),
        );
      });
    }

    testWidgets('🚨 進入時已有夠新的報價 → 立刻重排一次', (tester) async {
      widenViewport(tester);
      final center = _LiveCenter(
        LiveQuoteState(
          entries: {'2330': entry()},
          lastRespondedAt: morning.subtract(const Duration(seconds: 5)),
        ),
      );
      await tester.pumpWidget(
        buildTestWidget(
          watchlistState: WatchlistState(items: [row()]),
          liveCenter: center,
          now: morning,
        ),
      );
      await tester.pump();
      expect(lastWatchlistNotifier!.resortCalls, 1);
    });

    testWidgets('🚨 進入時沒有夠新的報價 → 第一輪資料到了重排一次,之後不動', (tester) async {
      widenViewport(tester);
      final center = _LiveCenter(const LiveQuoteState());
      await tester.pumpWidget(
        buildTestWidget(
          watchlistState: WatchlistState(items: [row()]),
          liveCenter: center,
          now: morning,
        ),
      );
      await tester.pump();
      expect(lastWatchlistNotifier!.resortCalls, 0);

      center.emit(
        LiveQuoteState(entries: {'2330': entry()}, lastRespondedAt: morning),
      );
      await tester.pump();
      expect(lastWatchlistNotifier!.resortCalls, 1);

      center.emit(
        LiveQuoteState(
          entries: {'2330': entry(price: 102)},
          lastRespondedAt: morning.add(const Duration(seconds: 15)),
        ),
      );
      await tester.pump();
      expect(lastWatchlistNotifier!.resortCalls, 1, reason: '之後順序不動、只更新數字');
    });
  });
```

（`widenViewport`、`lastWatchlistNotifier`、`buildTestWidget` 的 `brightness:` 都是該檔既有的。頁首灰字對比用 `scaffoldBackgroundColor`：自選畫面的 `Scaffold` 沒有自訂底色，頁首那列也沒有自己的底色。）

3. 建立 `test/presentation/live_quote_screen_scope_test.dart`：

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 掃描、今日訊號的 StockCard 不帶即時報價(spec §7「其他使用 StockCard 的
/// 畫面」):即使報價中心已有該檔報價,仍顯示資料庫的值。今日頁大盤列的
/// 指數在第 3 段另行登記,不在此限。
void main() {
  test('🚨 掃描、今日訊號不使用自選的即時價格與卡片即時資料', () {
    final files = [
      for (final dir in [
        'lib/presentation/screens/scan',
        'lib/presentation/screens/today',
      ])
        ...Directory(dir)
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart')),
    ];
    expect(files.length, greaterThan(5), reason: 'sanity:目錄有檔案');
    for (final f in files) {
      final src = f.readAsStringSync();
      for (final banned in [
        'StockCardLive',
        'watchlistLivePriceProvider',
        'WatchlistLiveView',
      ]) {
        expect(src.contains(banned), isFalse, reason: '${f.path} 用了 $banned');
      }
    }
  });
}
```

- [ ] **Step 2: 確認紅燈**

Run: `flutter test test/presentation/screens/watchlist/ test/presentation/live_quote_screen_scope_test.dart`
Expected: 編譯失敗（`watchlist_live_view.dart`、`buildProviderTestApp` 的 `liveQuoteCenter` 參數不存在）；scope 守門測試 PASS（現在本來就沒用）。

- [ ] **Step 3: 實作**

1. `test/helpers/provider_test_helpers.dart`：
   - import 加 `import 'package:daredevil/presentation/providers/live_quote_provider.dart';`。
   - 檔尾加：

```dart

/// 不發請求、不登記的報價中心(預設用它):畫面測試不可隨執行時間是否在
/// 盤中而不同。需要即時資料的測試用 [buildProviderTestApp] 的
/// `liveQuoteCenter:` 傳入假的報價中心。
class InertLiveQuoteCenter extends LiveQuoteCenter {
  @override
  LiveQuoteState build() => const LiveQuoteState();

  @override
  void register(Object owner, List<LiveQuoteRegistration> entries) {}

  @override
  void unregister(Object owner) {}

  @override
  void setAppVisible(bool visible) {}
}
```

   - `buildProviderTestApp` 加參數 `LiveQuoteCenter Function()? liveQuoteCenter,`，傳給 `_buildProviderApp`（兩處呼叫都要傳）。`_buildProviderApp` 加同名參數，`ProviderScope.overrides` 改成：

```dart
    overrides: [
      databaseProvider.overrideWithValue(_testDb),
      liveQuoteCenterProvider.overrideWith(
        liveQuoteCenter ?? InertLiveQuoteCenter.new,
      ),
      ...overrides,
    ],
```

   - `buildProviderTestApp` 的文件註解補一句：「報價中心預設為 [InertLiveQuoteCenter]；要即時資料時傳 `liveQuoteCenter:`，不要放進 [overrides]」。

2. 建立 `lib/presentation/screens/watchlist/watchlist_live_view.dart`：

```dart
import 'package:flutter/foundation.dart' show immutable;

import 'package:daredevil/domain/services/live_quote/live_quote_merge.dart';
import 'package:daredevil/presentation/providers/watchlist_provider.dart';
import 'package:daredevil/presentation/widgets/stock_card_live.dart';

/// 自選列要顯示的即時結果(依合併規則算出;見 `watchlistLivePriceProvider`)
@immutable
class WatchlistLiveView {
  const WatchlistLiveView({
    required this.price,
    required this.changePercent,
    required this.recentPrices,
    this.card,
  });

  /// [caption] 由呼叫端翻譯好傳入(本函式不碰 i18n)
  factory WatchlistLiveView.of({
    required WatchlistItemData item,
    required MergedPrice merged,
    required bool flashEnabled,
    String? caption,
  }) {
    final live = merged.kind == MergedPriceKind.live ? merged.live : null;
    final price = merged.price;
    return WatchlistLiveView(
      price: price,
      changePercent: item.changePercentWith(merged),
      // 走勢小圖最後一點接上即時價;畫面已有今天正式資料時不重複接
      recentPrices: live != null && price != null
          ? [...item.recentPrices, price]
          : item.recentPrices,
      card: live == null && caption == null
          ? null
          : StockCardLive(
              limitUp: live?.limitUp,
              limitDown: live?.limitDown,
              limitUpLocked: live?.isLimitUpLocked ?? false,
              limitDownLocked: live?.isLimitDownLocked ?? false,
              flash: live?.flash,
              flashEnabled: flashEnabled,
              caption: caption,
            ),
    );
  }

  final double? price;
  final double? changePercent;
  final List<double> recentPrices;
  final StockCardLive? card;
}
```

3. `lib/presentation/screens/watchlist/watchlist_stock_item.dart`：
   - 兩個類別的建構子都加 `this.live,`，欄位加：

```dart

  /// 盤中即時報價的顯示結果;null = 盤後行為
  final WatchlistLiveView? live;
```

   - 兩處 `StockCard(` 的 `latestClose:`、`priceChange:`、`recentPrices:` 改成下面這樣，並加上 `live:`：

```dart
      latestClose: live == null ? item.latestClose : live!.price,
      priceChange: live == null ? item.priceChange : live!.changePercent,
      ...
      recentPrices: live == null ? item.recentPrices : live!.recentPrices,
      ...
      live: live?.card,
```

（`WatchlistStockItem._buildCard` 與 `WatchlistStockGridItem.build`；`live` 是欄位，用 `final live = this.live;` 收窄型別也可以。）

   - import 加 `import 'package:daredevil/presentation/screens/watchlist/watchlist_live_view.dart';`。

4. `lib/presentation/screens/watchlist/watchlist_screen.dart`：
   - import 加：

```dart
import 'package:daredevil/core/constants/api_endpoints.dart';
import 'package:daredevil/core/utils/date_context.dart';
import 'package:daredevil/domain/services/live_quote/live_quote_schedule.dart';
import 'package:daredevil/presentation/providers/live_price_provider.dart';
import 'package:daredevil/presentation/providers/live_quote_provider.dart';
import 'package:daredevil/presentation/providers/providers.dart';
import 'package:daredevil/presentation/screens/watchlist/watchlist_live_view.dart';
import 'package:daredevil/presentation/widgets/live_quote_scope.dart';
import 'package:daredevil/presentation/widgets/live_quote_status.dart';
```

   - `_WatchlistScreenState` 欄位加：

```dart

  // 依漲跌幅排序時:畫面變為可見後,第一輪即時資料完成時重排一次
  // (spec §7「自選清單排序」)。可見性看 TickerMode(切分頁、推頁返回)
  bool _visible = false;
  bool _awaitingLiveRound = false;
  DateTime? _respondedAtWhenShown;
```

   - 加方法（放在 `initState` 之後）：

```dart
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visible = TickerMode.of(context);
    if (visible && !_visible) _onBecameVisible();
    _visible = visible;
  }

  void _onBecameVisible() {
    final respondedAt = ref.read(liveQuoteCenterProvider).lastRespondedAt;
    final count = ref.read(watchlistProvider).items.length;
    final batches =
        (count + ApiEndpoints.misBatchSize - 1) ~/ ApiEndpoints.misBatchSize;
    final fresh =
        respondedAt != null &&
        ref.read(appClockProvider).now().difference(respondedAt) <=
            LiveQuoteSchedule.pollInterval(batches);
    if (fresh) {
      // 已有不超過一個輪詢間隔的報價:先用它排(build 期間不可改 provider)
      _awaitingLiveRound = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.read(watchlistProvider.notifier).resortWithLive();
      });
    } else {
      _awaitingLiveRound = true;
      _respondedAtWhenShown = respondedAt;
    }
  }

  List<LiveQuoteRegistration> _registrations(List<WatchlistItemData> items) {
    final now = ref.read(appClockProvider).now();
    return [
      for (final item in items)
        if (item.market case final market?)
          LiveQuoteRegistration(
            symbol: item.symbol,
            market: market,
            hasOfficialToday:
                item.priceDate != null &&
                DateContext.isSameDay(item.priceDate!, now),
          ),
    ];
  }

  /// 一列自選:依合併規則算出即時顯示結果再交給 [build]
  Widget _withLive(
    WatchlistItemData item,
    Widget Function(WatchlistLiveView? live) build,
  ) {
    return Consumer(
      builder: (context, ref, _) {
        final merged = ref.watch(watchlistLivePriceProvider(item.symbol));
        if (merged == null) return build(null);
        final status = ref.watch(
          liveQuoteCenterProvider.select((s) => s.symbolStatus[item.symbol]),
        );
        final flashEnabled = ref.watch(
          settingsProvider.select((s) => s.priceFlash),
        );
        return build(
          WatchlistLiveView.of(
            item: item,
            merged: merged,
            flashEnabled: flashEnabled,
            caption: LiveQuoteStatusRule.card(
              status: status,
              merged: merged,
            )?.text(),
          ),
        );
      },
    );
  }
```

   - `build` 開頭（`final state = ref.watch(watchlistProvider);` 之後）加：

```dart
    ref.listen(liveQuoteCenterProvider.select((s) => s.lastRespondedAt), (
      _,
      next,
    ) {
      if (!_awaitingLiveRound || next == null || next == _respondedAtWhenShown) {
        return;
      }
      _awaitingLiveRound = false;
      ref.read(watchlistProvider.notifier).resortWithLive();
    });
```

   - `_buildWatchlistBody` 最後一個分支 `: Column(` 改成 `: LiveQuoteScope(registrations: _registrations(state.items), child: Column(`，對應的結尾補一個 `)`。
   - 股票數量那個 `Row` 的 `children:`，在 `if (state.searchQuery.isNotEmpty) ...[ ... ],` 之後加：

```dart
                      Expanded(
                        child: Consumer(
                          builder: (context, ref, _) {
                            final status = ref.watch(
                              watchlistLiveHeaderProvider,
                            );
                            if (status == null) return const SizedBox.shrink();
                            return Text(
                              status.text(),
                              textAlign: TextAlign.end,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            );
                          },
                        ),
                      ),
```

   - 四個建卡片的地方（`_buildFlatList`、`_buildFlatGrid`、`_buildGroupedList`、`_buildCategoryGroupedList`）都把 `WatchlistStockItem(...)`／`WatchlistStockGridItem(...)` 包成 `_withLive(item, (live) => WatchlistStockItem(..., live: live))`，原本的參數不變。例如 `_buildFlatList`：

```dart
        final item = items[index];
        return RepaintBoundary(
          child: _withLive(
            item,
            (live) => WatchlistStockItem(
              item: item,
              index: index,
              showLimitMarkers: showLimitMarkers,
              live: live,
              onView: () => _openStockDetail(item.symbol),
              onRemove: () => _removeFromWatchlist(item.symbol),
              onLongPress: () => _showStockPreview(item),
            ),
          ),
        );
```

- [ ] **Step 4: 確認通過**

Run: `flutter test test/presentation/screens/watchlist/ test/presentation/live_quote_screen_scope_test.dart test/presentation/widgets/ test/presentation/providers/`
Expected: 全部 PASS。既有的自選畫面測試、golden 外的測試，在惰性報價中心下行為不變。

Run: `flutter test --tags golden test/presentation/screens/golden/watchlist_screen_golden_test.dart`
Expected: PASS（自選 golden 不變：惰性報價中心沒有任何即時資料）

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 5: 記錄進度**（不 commit）

---

### Task 7: 長按預覽（從自選開啟）隨每輪更新

**Files:**
- Modify: `lib/presentation/widgets/stock_preview_sheet.dart`
- Modify: `lib/presentation/screens/watchlist/watchlist_screen.dart`（`_showStockPreview`）
- Test: `test/presentation/screens/watchlist/watchlist_screen_test.dart`、`test/presentation/widgets/stock_preview_sheet_test.dart`

**Interfaces:**
- Consumes：Task 4 的 `watchlistLivePriceProvider`、`WatchlistState.itemOf`、`WatchlistItemData.changePercentWith`；Task 6 的 `_LiveCenter`（測試）。
- Produces：`showStockPreviewSheet({..., StockPreviewData Function(WidgetRef ref)? liveData})`。

- [ ] **Step 1: 寫失敗測試**

`test/presentation/screens/watchlist/watchlist_screen_test.dart` 的 `group('盤中即時報價', ...)` 內加：

```dart
    testWidgets('🚨 從自選開啟的長按預覽與卡片同價,下一輪更新後仍同價', (tester) async {
      widenViewport(tester);
      final center = _LiveCenter(
        LiveQuoteState(entries: {'2330': entry(price: 101)}),
      );
      await tester.pumpWidget(
        buildTestWidget(
          watchlistState: WatchlistState(items: [row()]),
          liveCenter: center,
          now: morning,
        ),
      );
      await tester.pump();

      await tester.longPress(find.text('101.00'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('101.00'), findsNWidgets(2), reason: '卡片＋預覽');

      center.emit(LiveQuoteState(entries: {'2330': entry(price: 102)}));
      await tester.pump();
      expect(find.text('102.00'), findsNWidgets(2));
      expect(find.text('101.00'), findsNothing);
    });
```

`test/presentation/widgets/stock_preview_sheet_test.dart` 的既有測試不改：沒有 `liveData` 時行為不變。

- [ ] **Step 2: 確認紅燈**

Run: `flutter test test/presentation/screens/watchlist/watchlist_screen_test.dart --plain-name "長按預覽"`
Expected: FAIL。預覽是開啟時的快照，下一輪更新後預覽仍是 `101.00`：`102.00` 只找到 1 個。

- [ ] **Step 3: 實作**

1. `lib/presentation/widgets/stock_preview_sheet.dart`：
   - import 加 `import 'package:flutter_riverpod/flutter_riverpod.dart';`。
   - `showStockPreviewSheet` 加參數，並把 `builder:` 改成依 `liveData` 分流：

```dart
/// [liveData] 非 null 時,預覽依它每次重建時的結果顯示(自選長按:套與卡片
/// 相同的合併規則並隨每輪即時報價更新);null 時為開啟當下的快照(掃描、
/// 今日訊號)。
Future<void> showStockPreviewSheet({
  required BuildContext context,
  required StockPreviewData data,
  VoidCallback? onViewDetails,
  VoidCallback? onToggleWatchlist,
  VoidCallback? onMoveToGroup,
  StockPreviewData Function(WidgetRef ref)? liveData,
}) {
  HapticFeedback.mediumImpact();

  Widget sheet(StockPreviewData d) => StockPreviewSheet(
    data: d,
    onViewDetails: onViewDetails,
    onToggleWatchlist: onToggleWatchlist,
    onMoveToGroup: onMoveToGroup,
  );

  return showAppBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => liveData == null
        ? sheet(data)
        : Consumer(builder: (context, ref, _) => sheet(liveData(ref))),
  );
}
```

2. `lib/presentation/screens/watchlist/watchlist_screen.dart` 的 `_showStockPreview`：在 `showStockPreviewSheet(` 的參數加：

```dart
      liveData: (ref) {
        final current =
            ref.watch(watchlistProvider.select((s) => s.itemOf(item.symbol))) ??
            item;
        final merged = ref.watch(watchlistLivePriceProvider(item.symbol));
        return StockPreviewData(
          symbol: current.symbol,
          stockName: current.stockName,
          latestClose: merged == null ? current.latestClose : merged.price,
          priceChange: merged == null
              ? current.priceChange
              : current.changePercentWith(merged),
          score: current.score,
          trendState: current.trendState,
          reasons: current.reasons,
          isInWatchlist: true,
        );
      },
```

- [ ] **Step 4: 確認通過**

Run: `flutter test test/presentation/screens/watchlist/ test/presentation/widgets/stock_preview_sheet_test.dart test/presentation/screens/today/ test/presentation/screens/scan/`
Expected: 全部 PASS（今日頁、掃描頁的預覽照舊）

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 5: 記錄進度**（不 commit）

---

### Task 8: 個股頁上方的即時報價

**Files:**
- Modify: `lib/presentation/providers/live_price_provider.dart`（`stockDetailLivePriceProvider`）
- Modify: `lib/presentation/screens/stock_detail/widgets/stock_detail_header.dart`
- Modify: `lib/presentation/screens/stock_detail/stock_detail_screen.dart`
- Test: `test/presentation/screens/stock_detail/widgets/stock_detail_header_test.dart`、`test/presentation/screens/stock_detail/stock_detail_screen_test.dart`

**Interfaces:**
- Consumes：
  - Task 2：`PriceLimit.statusOf`、`S.priceLimitLabel`。
  - Task 3：`PriceFlash`、`SettingsState.priceFlash`。
  - Task 4：`MergedPrice.changePercent`、`OfficialPrice` 的相等比較。
  - Task 5：`LiveQuoteStatusRule.header`。
  - Task 6：測試輔助的 `liveQuoteCenter:`。
  - 第 1 段：`LiveQuoteScope`。
- Produces：
  - `final stockDetailLivePriceProvider = Provider.autoDispose.family<MergedPrice, String>`。
  - `class StockHeaderLive { double price; double? changePercent; double change; String statusText; double? open, high, low; int? volumeLots; LiveQuoteFlash? flash; bool flashEnabled; }`，以及 `static StockHeaderLive? StockHeaderLive.from({required MergedPrice merged, required LiveQuoteState state, required bool flashEnabled})`。
  - `StockHeaderData` 的新欄位 `open`、`high`、`low`、`volumeShares`。
  - `StockDetailHeader({..., StockHeaderLive? live, PriceLimitStatus limitStatus = PriceLimitStatus.none})`。

- [ ] **Step 1: 寫失敗測試**

1. `test/presentation/screens/stock_detail/widgets/stock_detail_header_test.dart`：
   - import 加（`app_theme.dart` 該檔已有）：

```dart
import 'package:daredevil/core/theme/color_contrast.dart';
import 'package:daredevil/core/utils/price_limit.dart';
import 'package:daredevil/domain/models/live_quote.dart';
import 'package:daredevil/presentation/screens/stock_detail/tabs/chip/chip_helpers.dart';
import 'package:daredevil/presentation/widgets/price_flash.dart';
```

   - 在 `main()` 最後加（直接以 `StockHeaderData(...)` 建構，才能帶新欄位）：

```dart
  group('盤中即時報價與開高低量', () {
    const en = Locale('en', 'US');

    testWidgets('🚨 盤後:開高低量列,成交量股數除以 1,000 以「張」顯示', (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          StockDetailHeader(
            data: StockHeaderData(
              stockName: '台積電',
              latestClose: 100,
              priceChange: 1,
              dataDate: DateTime(2026, 10, 5),
              open: 99,
              high: 101,
              low: 98.5,
              volumeShares: 1234000,
            ),
            symbol: '2330',
          ),
        ),
      );
      expect(find.textContaining('stockDetail.open'), findsOneWidget);
      expect(find.textContaining('98.50'), findsOneWidget);
      expect(find.textContaining(formatLots(1234, en)), findsOneWidget);
      // 資料日期標示(今日/昨日/M/D 資料)照常顯示——下一條的對照組
      expect(find.textContaining('stockDetail.data'), findsOneWidget);
    });

    testWidgets('🚨 即時:現價、漲跌、狀態取代資料日期;成交量直接用 MIS 張數', (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          StockDetailHeader(
            data: StockHeaderData(
              stockName: '台積電',
              latestClose: 100,
              priceChange: -1,
              dataDate: DateTime(2026, 10, 5),
            ),
            symbol: '2330',
            live: const StockHeaderLive(
              price: 103,
              changePercent: 3,
              change: 3,
              statusText: 'liveQuote.quoteTime',
              open: 100,
              high: 104,
              low: 99.5,
              volumeLots: 5678,
            ),
          ),
        ),
      );
      expect(find.text('103.00'), findsOneWidget);
      expect(find.textContaining('+3.00'), findsOneWidget);
      expect(find.text('liveQuote.quoteTime'), findsOneWidget);
      // 不寫死今日/昨日:`_formatDataDate` 依執行當天判斷,三種 key 都以
      // stockDetail.data 開頭(dataMissing 只在 missingDomains 非空時出現)
      expect(find.textContaining('stockDetail.data'), findsNothing);
      expect(find.textContaining(formatLots(5678, en)), findsOneWidget);
    });

    testWidgets('漲停鎖 → 徽章', (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          const StockDetailHeader(
            data: StockHeaderData(stockName: '測試', latestClose: 44),
            symbol: 'A',
            live: StockHeaderLive(
              price: 44,
              changePercent: 10,
              change: 4,
              statusText: 'liveQuote.quoteTime',
            ),
            limitStatus: PriceLimitStatus.limitUpLocked,
          ),
        ),
      );
      expect(find.text('price.limitUpLocked'), findsOneWidget);
    });

    for (final brightness in [Brightness.light, Brightness.dark]) {
      testWidgets('🚨 閃色最濃時 $brightness:現價對頁面漸層頂端的實際底色 ≥ 4.5', (
        tester,
      ) async {
        Widget header(int id) => buildTestApp(
          StockDetailHeader(
            data: const StockHeaderData(stockName: '測試', latestClose: 100),
            symbol: 'A',
            live: StockHeaderLive(
              price: 101,
              changePercent: 1,
              change: 1,
              statusText: 'liveQuote.quoteTime',
              flash: LiveQuoteFlash(id: id, up: true),
            ),
          ),
          brightness: brightness,
        );
        await tester.pumpWidget(header(1));
        await tester.pumpWidget(header(2));
        await tester.pump();

        final theme = brightness == Brightness.dark
            ? AppTheme.darkTheme
            : AppTheme.lightTheme;
        // 個股頁背景頂端是漲色 15% 疊在 surface 上(stock_detail_screen 的漸層)
        final pageTop = ColorContrast.compositeOver(
          AppTheme.upColor,
          theme.colorScheme.surface,
          0.15,
        );
        final tint =
            (tester.widget<DecoratedBox>(find.byKey(PriceFlash.tintKey)).decoration
                    as BoxDecoration)
                .color!;
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
              pageTop,
              tint.a,
            ),
          ),
          greaterThanOrEqualTo(4.5),
        );
      });
    }
  });
```

2. `test/presentation/screens/stock_detail/stock_detail_screen_test.dart`：
   - import 加：

```dart
import 'package:daredevil/core/theme/app_theme.dart';
import 'package:daredevil/core/utils/clock.dart';
import 'package:daredevil/domain/models/live_quote.dart';
import 'package:daredevil/presentation/providers/live_quote_provider.dart';
import 'package:daredevil/presentation/providers/providers.dart';
import 'package:daredevil/presentation/widgets/live_quote_scope.dart';
```

   - 在 `_FixedBrowsingContext` 之後加（每個測試檔各自宣告假物件，見 `test/CLAUDE.md`）：

```dart

class _Clock implements AppClock {
  _Clock(this.value);
  final DateTime value;
  @override
  DateTime now() => value;
}

/// 記錄登記、可推送新狀態的報價中心(不發請求)
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

   - `buildTestWidget` 的參數在 `List<String> browsingContext = const [],` 之後加 `_LiveCenter? liveCenter, DateTime? now,`；`overrides:` 清單最後（`stockBrowsingContextProvider.overrideWith(...)` 之後）加 `if (now != null) appClockProvider.overrideWithValue(_Clock(now)),`；`brightness: brightness,` 之後加 `liveQuoteCenter: liveCenter == null ? null : () => liveCenter,`。
   - 在 `main()` 最後加：

```dart
  group('盤中即時報價', () {
    final morning = DateTime(2026, 10, 6, 10, 15);
    final content = StockDetailState(
      price: StockPriceState(
        stock: StockMasterEntry(
          symbol: '2330',
          name: '台積電',
          market: 'TWSE',
          isActive: true,
          updatedAt: DateTime(2026, 10, 5),
        ),
        latestPrice: DailyPriceEntry(
          symbol: '2330',
          date: DateTime(2026, 10, 5),
          close: 100,
          priceChange: -1,
        ),
      ),
      dataDate: DateTime(2026, 10, 5),
    );

    LiveQuoteEntry entry(String symbol, double price) => LiveQuoteEntry(
      symbol: symbol,
      date: DateTime(2026, 10, 6),
      price: price,
      displaySource: LiveDisplaySource.trade,
      previousClose: 100,
      quoteTime: '10:14:50',
      isClosingQuote: false,
    );

    testWidgets('🚨 登記這一檔(市場別、還沒有今天的正式資料)', (tester) async {
      widenViewport(tester);
      final center = _LiveCenter(const LiveQuoteState());
      await tester.pumpWidget(
        buildTestWidget(stockState: content, liveCenter: center, now: morning),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(center.registered.values.single, const [
        LiveQuoteRegistration(symbol: '2330', market: 'TWSE'),
      ]);
    });

    testWidgets('🚨 有即時:上方顯示即時價,背景漸層方向跟著即時(資料庫是跌)', (tester) async {
      widenViewport(tester);
      final center = _LiveCenter(
        LiveQuoteState(entries: {'2330': entry('2330', 103)}),
      );
      await tester.pumpWidget(
        buildTestWidget(stockState: content, liveCenter: center, now: morning),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('103.00'), findsOneWidget);
      // 背景是 LiveQuoteScope 底下的第一個 Container(上方區塊的漲跌膠囊
      // 也有漸層,不可用「第一個有漸層的 Container」找)
      final body = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(LiveQuoteScope),
              matching: find.byType(Container),
            )
            .first,
      );
      final gradient =
          (body.decoration! as BoxDecoration).gradient! as LinearGradient;
      expect(gradient.colors.first, AppTheme.upColor.withValues(alpha: 0.15));
    });

    testWidgets('🚨 上下滑換股 → 登記與上方價格換到新的代號', (tester) async {
      widenViewport(tester);
      final center = _LiveCenter(
        LiveQuoteState(
          entries: {'2330': entry('2330', 103), '2317': entry('2317', 257)},
        ),
      );
      await tester.pumpWidget(
        buildTestWidget(
          stockState: content,
          liveCenter: center,
          now: morning,
          browsingContext: const ['2330', '2317'],
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('103.00'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.chevron_right));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(
        [for (final r in center.registered.values.single) r.symbol],
        ['2317'],
      );
      expect(find.text('257.00'), findsOneWidget);
      expect(find.text('103.00'), findsNothing);
    });
  });
```

- [ ] **Step 2: 確認紅燈**

Run: `flutter test test/presentation/screens/stock_detail/`
Expected: 編譯失敗（`StockHeaderLive`、`StockHeaderData.open` 等、`StockDetailHeader.live`／`limitStatus` 未定義）

- [ ] **Step 3: 實作**

1. `lib/presentation/providers/live_price_provider.dart`：
   - import 加 `import 'package:daredevil/presentation/providers/stock_detail_provider.dart';`。
   - 檔尾加：

```dart

/// 個股頁要顯示的價格(依合併規則;正式資料 = 對齊法人日期的那一筆)。上方
/// 區塊與背景漸層共用同一個結果
final stockDetailLivePriceProvider = Provider.autoDispose
    .family<MergedPrice, String>((ref, symbol) {
      final official = ref.watch(
        stockDetailProvider(symbol).select((s) {
          final p = s.price.latestPrice;
          return OfficialPrice(
            date: p?.date,
            close: p?.close,
            priceChange: p?.priceChange,
          );
        }),
      );
      final live = ref.watch(
        liveQuoteCenterProvider.select((s) => s.entries[symbol]),
      );
      return LiveQuoteMerge.merge(
        official: official,
        live: live,
        now: ref.read(appClockProvider).now(),
      );
    });
```

2. `lib/presentation/screens/stock_detail/widgets/stock_detail_header.dart`：
   - import 加：

```dart
import 'package:daredevil/core/utils/price_limit.dart';
import 'package:daredevil/domain/models/live_quote.dart';
import 'package:daredevil/domain/services/live_quote/live_quote_merge.dart';
import 'package:daredevil/presentation/providers/live_quote_provider.dart';
import 'package:daredevil/presentation/screens/stock_detail/tabs/chip/chip_helpers.dart';
import 'package:daredevil/presentation/widgets/live_quote_status.dart';
import 'package:daredevil/presentation/widgets/price_flash.dart';
```

   - `StockHeaderData`：
     - 建構子在 `this.missingDomains = const [],` 之後加 `this.open, this.high, this.low, this.volumeShares,`；
     - 欄位加：

```dart

  /// 正式資料那一筆的開高低與成交量(股);上方「開高低量」列用
  final double? open;
  final double? high;
  final double? low;
  final double? volumeShares;
```

     - `fromState` 加：

```dart
    open: s.price.latestPrice?.open,
    high: s.price.latestPrice?.high,
    low: s.price.latestPrice?.low,
    volumeShares: s.price.latestPrice?.volume,
```

     - `==` 加 `open == other.open && high == other.high && low == other.low && volumeShares == other.volumeShares &&`；
     - `hashCode` 的 `Object.hash(` 加 `open, high, low, volumeShares,`。
   - 在 `StockDetailHeader` 之前加：

```dart
/// 個股頁上方的即時報價(只有用即時報價時才有;見 `LiveQuoteMerge`)
@immutable
class StockHeaderLive {
  const StockHeaderLive({
    required this.price,
    required this.changePercent,
    required this.change,
    required this.statusText,
    this.open,
    this.high,
    this.low,
    this.volumeLots,
    this.flash,
    this.flashEnabled = true,
  });

  final double price;
  final double? changePercent;

  /// 漲跌金額(現價 − MIS 昨收)
  final double change;

  /// 放在原「資料日期」位置的狀態(報價時間／今日收盤／最後報價／暫停)
  final String statusText;
  final double? open;
  final double? high;
  final double? low;

  /// 累計成交量(張,MIS v)
  final int? volumeLots;
  final LiveQuoteFlash? flash;
  final bool flashEnabled;

  /// 合併結果是即時報價時建立;否則 null(上方維持盤後資料)
  static StockHeaderLive? from({
    required MergedPrice merged,
    required LiveQuoteState state,
    required bool flashEnabled,
  }) {
    final live = merged.live;
    final price = merged.price;
    final previous = merged.previousClose;
    if (merged.kind != MergedPriceKind.live ||
        live == null ||
        price == null ||
        previous == null) {
      return null;
    }
    return StockHeaderLive(
      price: price,
      changePercent: merged.changePercent,
      change: price - previous,
      statusText:
          LiveQuoteStatusRule.header(
            state: state,
            merged: [merged],
            intradayTime: merged.quoteTime,
          )?.text() ??
          '',
      open: live.open,
      high: live.high,
      low: live.low,
      volumeLots: live.volumeLots,
      flash: live.flash,
      flashEnabled: flashEnabled,
    );
  }
}
```

（`immutable` 由 `package:flutter/material.dart` 匯出。）

   - `StockDetailHeader` 建構子加 `this.live, this.limitStatus = PriceLimitStatus.none,`，欄位加：

```dart

  /// 盤中即時報價;null = 盤後資料
  final StockHeaderLive? live;

  /// 漲跌停狀態(由畫面以 `PriceLimit.statusOf` 算好傳入)
  final PriceLimitStatus limitStatus;

  double? get _close => live?.price ?? data.latestClose;

  double? get _changePercent {
    final l = live;
    return l != null ? l.changePercent : data.priceChange;
  }

  double? get _absChange {
    final l = live;
    return l != null
        ? l.change
        : _calculateAbsoluteChange(data.latestClose, data.priceChange);
  }
```

   - `build` 第二行 `final priceChange = data.priceChange;` 改成 `final priceChange = _changePercent;`。
   - `_buildSemanticLabel`：
     - `final close = data.latestClose;` 改成 `final close = _close;`；
     - `final change = data.priceChange;` 改成 `final change = _changePercent;`；
     - `final absChange = _calculateAbsoluteChange(close, change);` 改成 `final absChange = _absChange;`。
   - `_buildPriceColumn`：
     - `final absChange = _calculateAbsoluteChange(data.latestClose, priceChange);` 改成 `final absChange = _absChange;`；
     - 現價 `Text(data.latestClose?.toStringAsFixed(2) ?? '-', ...)` 改成：

```dart
        PriceFlash(
          flash: live?.flash,
          enabled: live?.flashEnabled ?? true,
          child: Text(
            _close?.toStringAsFixed(2) ?? '-',
            style: theme.textTheme.displaySmall?.copyWith(
              fontWeight: FontWeight.w800,
              fontFamily: 'RobotoMono',
              fontSize: 32,
              letterSpacing: -1,
            ),
          ),
        ),
```

     - 漲跌 `Container`（`if (priceChange != null) Container(...)`）之後加：

```dart
        if (limitStatus != PriceLimitStatus.none)
          Padding(
            padding: const EdgeInsets.only(top: DesignTokens.spacing4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: AppTheme.getPriceColor(
                  limitStatus.isUp ? 1 : -1,
                  theme.brightness,
                ),
                borderRadius: BorderRadius.circular(DesignTokens.radiusXs),
              ),
              child: Text(
                S.priceLimitLabel(limitStatus),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
```

     - 資料日期那段 `if (data.dataDate != null) Padding(...)` 改成先判斷即時：

```dart
        if (live != null)
          Padding(
            padding: const EdgeInsets.only(top: DesignTokens.spacing4),
            child: Text(
              live!.statusText,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          )
        else if (data.dataDate != null)
          Padding( /* 原內容不變 */ ),
        _buildTradingRow(theme),
```

（`live` 是欄位，`live!` 也可以改成在方法開頭 `final live = this.live;` 收窄。）

   - 加方法（放在 `_formatDetailChangeText` 之前）：

```dart
  /// 開盤、最高、最低、成交量(張)。即時用 MIS 的張數;盤後把股數除以 1,000
  Widget _buildTradingRow(ThemeData theme) {
    final l = live;
    final open = l != null ? l.open : data.open;
    final high = l != null ? l.high : data.high;
    final low = l != null ? l.low : data.low;
    final lots = l != null
        ? l.volumeLots?.toDouble()
        : (data.volumeShares == null ? null : data.volumeShares! / 1000);
    if (open == null && high == null && low == null && lots == null) {
      return const SizedBox.shrink();
    }
    String price(double? v) => v?.toStringAsFixed(2) ?? '-';
    return Builder(
      builder: (context) {
        final locale = Localizations.localeOf(context);
        return Padding(
          padding: const EdgeInsets.only(top: DesignTokens.spacing4),
          child: Text(
            '${'stockDetail.open'.tr()} ${price(open)}  '
            '${'stockDetail.high'.tr()} ${price(high)}  '
            '${'stockDetail.low'.tr()} ${price(low)}  '
            '${'stockDetail.volume'.tr()} ${lots == null ? '-' : formatLots(lots, locale)}',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        );
      },
    );
  }
```

3. `lib/presentation/screens/stock_detail/stock_detail_screen.dart`：
   - import 加：

```dart
import 'package:daredevil/core/utils/date_context.dart';
import 'package:daredevil/core/utils/price_limit.dart';
import 'package:daredevil/domain/services/live_quote/live_quote_merge.dart';
import 'package:daredevil/presentation/providers/live_price_provider.dart';
import 'package:daredevil/presentation/providers/live_quote_provider.dart';
import 'package:daredevil/presentation/providers/providers.dart';
import 'package:daredevil/presentation/providers/settings_provider.dart';
import 'package:daredevil/presentation/widgets/live_quote_scope.dart';
```

   - `build` 裡 `final priceChangeRaw = ref.watch(provider.select((s) => s.priceChange));` 之後加：

```dart
    // 只取正負號:build 刻意只 watch 少數欄位,watch 整個合併結果會讓
    // 整頁每輪報價(15 秒)都重建
    final liveSign = ref.watch(
      stockDetailLivePriceProvider(_symbol).select(
        (m) => m.kind == MergedPriceKind.live ? m.changePercent?.sign : null,
      ),
    );
    final market = ref.watch(provider.select((s) => s.stockMarket));
    final officialDate = ref.watch(
      provider.select((s) => s.price.latestPrice?.date),
    );
```

   - `final priceChange = priceChangeRaw ?? 0;` 改成：

```dart
    // 漸層方向與上方區塊同一個來源(用即時報價時跟著即時)
    final priceChange = liveSign ?? priceChangeRaw ?? 0;
```

   - `body: Container(` 改成：

```dart
      body: LiveQuoteScope(
        registrations: [
          if (market != null)
            LiveQuoteRegistration(
              symbol: _symbol,
              market: market,
              hasOfficialToday:
                  officialDate != null &&
                  DateContext.isSameDay(
                    officialDate,
                    ref.read(appClockProvider).now(),
                  ),
            ),
        ],
        child: Container(
```

     並在 `body:` 的 `Container(...)` 結尾補一個 `)`。
   - 上方區塊的 `Consumer`（`StockHeaderData.fromState` 那段）改成：

```dart
                    child: Consumer(
                      builder: (context, ref, _) {
                        final headerData = ref.watch(
                          provider.select((s) => StockHeaderData.fromState(s)),
                        );
                        final merged = ref.watch(
                          stockDetailLivePriceProvider(_symbol),
                        );
                        final center = ref.watch(liveQuoteCenterProvider);
                        final flashOn = ref.watch(
                          settingsProvider.select((s) => s.priceFlash),
                        );
                        final limitOn = ref.watch(
                          settingsProvider.select((s) => s.limitAlerts),
                        );
                        final live = StockHeaderLive.from(
                          merged: merged,
                          state: center,
                          flashEnabled: flashOn,
                        );
                        final limit = limitOn
                            ? PriceLimit.statusOf(
                                changePercent:
                                    live?.changePercent ??
                                    headerData.priceChange,
                                price: live?.price ?? headerData.latestClose,
                                limitUp: merged.live?.limitUp,
                                limitDown: merged.live?.limitDown,
                                limitUpLocked:
                                    merged.live?.isLimitUpLocked ?? false,
                                limitDownLocked:
                                    merged.live?.isLimitDownLocked ?? false,
                              )
                            : PriceLimitStatus.none;
                        return StockDetailHeader(
                          data: headerData,
                          symbol: _symbol,
                          live: live,
                          limitStatus: limit,
                        );
                      },
                    ),
```

   注意：沒有即時報價時 `merged.live` 為 null，`limitUp`／`limitDown` 傳 null，`statusOf` 回到以漲跌幅推算，與 `StockCard` 一致。

- [ ] **Step 4: 確認通過**

Run: `flutter test test/presentation/screens/stock_detail/ test/presentation/providers/`
Expected: 全部 PASS

Run: `flutter test --tags golden test/presentation/screens/golden/stock_detail_screen_golden_test.dart`
Expected: PASS（golden 是空狀態，上方區塊不變）

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 5: 記錄進度**（不 commit）

---

### Task 9: CHANGELOG、golden、全套驗證、mutation、審查、經同意提交

- [ ] **Step 1: CHANGELOG**

`CHANGELOG.md` 的 `## [Unreleased]` → `### Added` 最前面加：

```markdown
- 盤中即時報價（自選清單、長按預覽、個股頁）：交易時間每 15 秒更新畫面上看得到的股票，現價變動時底色閃一下
  （設定頁「價格閃色」可關閉，系統要求減少動態效果時也不閃）；漲跌停鎖住時標「漲停鎖」「跌停鎖」；收盤後到盤後資料
  寫入前顯示「今日收盤・待盤後更新」；斷線或證交所限流時標示「報價暫停」，不把舊價格當成即時。依漲跌幅排序的自選
  清單在回到畫面、第一輪報價到齊時重排一次；個股頁上方新增開盤、最高、最低、成交量（張）
```

先找讀 CHANGELOG 的測試：`grep -rln "CHANGELOG" test`；有的話跑它們。

- [ ] **Step 2: golden**

```bash
flutter test --tags golden test/presentation/screens/golden/ > <scratchpad>/golden_before.log 2>&1; grep -E "^\d|failed|Failed" <scratchpad>/golden_before.log | tail -5
flutter test --update-goldens --tags golden test/presentation/screens/golden/settings_screen_golden_test.dart
flutter test --tags golden test/presentation/screens/golden/
```

Expected:
- 第一行（重產前）只有 `settings_screen_{light,dark}` 失敗。其他 golden 失敗就是回歸：不重產，先查原因。自選與個股頁的 golden 應該不變，理由見 Global Constraints。
- 第二行只重產設定頁。
- 第三行全部 PASS。
- 用 Read 打開 `settings_screen_{light,dark}.png` 目視：多一個「價格閃色」開關，其他位置沒有跑版。

- [ ] **Step 3: 靜態檢查與全套**（log 寫到 scratchpad）

```bash
dart format lib test
flutter analyze
flutter test > <scratchpad>/full_lq2.log 2>&1; tail -c 300 <scratchpad>/full_lq2.log
flutter test test/tool/tool_chain_pure_dart_test.dart
dart compile kernel tool/intraday_alert_check.dart -o build/intraday_alert_check.dill
dart compile kernel tool/daily_update.dart -o build/daily_update.dill
```

注意：`dart format lib test` 若格式化到本段沒有動的檔案，就改成只格式化本段改過的檔案，不留無關 diff。

Expected:
- analyze 無 issue。
- 全套通過，測試數比開工前基準多出本段新增的數目。開工前先跑一次全套，記下基準。
- 守門測試通過，兩個 kernel 編譯成功。本段沒有動 CLI 閉包，這兩步是確認沒有誤動。

- [ ] **Step 4: mutation**

在 scratchpad 的 repo 副本做（`rsync -rl`，排除 `.dart_tool/flutter_build`、`build/`、`.git/`）。先跑直接測試，存活者再跑 `test/presentation test/core test/domain/services/live_quote`。至少涵蓋：

| 檔案 | mutant | 直接測試 |
|:--|:--|:--|
| live_quote_provider | `_rollDay` 拿掉 `_rateLimitedUntil = null`；`_finishRound` 不呼叫 `_rollDay`；`_publish` 不看 `_pending`；`_countStall` 的 `rateLimited ? 0 :` 拿掉 | live_quote_provider_test |
| price_limit | 有漲跌停價時改成仍看漲跌幅；鎖住旗標對調 | price_limit_test |
| stock_card | `_limitStatus` 不傳 `limitUp`；例外標示不放 | stock_card_test |
| price_flash | `initState` 不記 `_seenId`；不檢查 `reduceMotion`；不檢查 `disableAnimations` | price_flash_test |
| watchlist_types／provider | `changePercentWith` 一律回 `priceChange`；排序不用合併值；`resortWithLive` 不看排序方式；`loadData` 不帶 `priceDate` | watchlist_live_price_test、watchlist_provider_test |
| live_quote_status | 限流與網路暫停順序對調；收盤後取最新而非最舊；`card` 不檢查 official | live_quote_status_test |
| watchlist_live_view | 走勢小圖一律接即時價 | watchlist_live_view_test |
| watchlist_screen | `_onBecameVisible` 一律等下一輪；`ref.listen` 拿掉 `_awaitingLiveRound` 檢查；登記不帶 `hasOfficialToday` | watchlist_screen_test |
| stock_detail_screen | 漸層改回 `priceChangeRaw`；登記用 `widget.symbol` 而不是 `_symbol` | stock_detail_screen_test |
| stock_detail_header | 即時成交量又除以 1,000；狀態文字不取代資料日期 | stock_detail_header_test |

- [ ] **Step 5: 審查**

送 opus 審查（`pr-review-toolkit:code-reviewer`）：
- 範圍：`git diff` 加未追蹤新檔。
- 附上：
  - 本計畫與 spec 的路徑；
  - Review Focus 五條、「與 spec 的差異」七條；
  - Step 2–4 的輸出。
- 限制：不可 `dart run`、不可開背景任務、不可碰 scratchpad、不改檔。
- 修正 Critical 與 Important：每條先寫出會失敗的測試，再修到通過。Minor 記錄、不修。

- [ ] **Step 6: 報告並等「提交」**

報告內容：
- 全套測試數；
- golden 目視結果；
- mutation 結果；
- 審查與修正；
- 延後的 Minor。

提醒：不在 09:00–13:30 提交。

Commit message 草稿：

```
feat: 自選清單與個股頁顯示盤中即時報價

- 自選卡片、長按預覽與個股頁上方改用合併後的價格：畫面原本的資料是今天就用
  它，否則用今天的即時報價；收盤後顯示今日收盤、待盤後更新
- 現價變動時底色閃一下，設定頁新增「價格閃色」開關，系統要求停用動畫或
  iOS 減少動態效果時不閃
- 漲跌停改以交易所的漲跌停價判斷，鎖住標「漲停鎖」「跌停鎖」；卡片例外
  標示報價暫停、無報價、最後報價；自選頁首顯示報價時間、今日收盤或暫停狀態
- 依漲跌幅排序的自選清單在回到畫面、第一輪報價到齊時重排一次
- 個股頁上方新增開盤、最高、最低、成交量（張）
- 報價中心：換日或已無待抓時不顯示限流與最後更新時間、限流期間不判網路
  暫停、請求跨午夜時照樣換日、啟動時同步生命週期狀態
```

- [ ] **Step 7: 經同意後提交**（使用者說「提交」才做）

1. 確認現在不是 09:00–13:30。
2. 提交（直接在 main，純文字訊息）。

- [ ] **Step 8: 提交後**

1. 確認 post-commit hook 已把兩支 CLI 重編到新 commit：看 `~/Library/Logs/daredevil-cli-rebuild.log` 最後一行與兩支 `BUILD_INFO`。
2. 重編 GUI（macOS Debug），下一個交易日盤中實機驗證：
   - 自選 ≥ 36 檔（至少 2 批），跨過數個 5 分鐘整點；CLI 日誌沒有限流、沒有新增的請求失敗。
   - 抽幾檔對照畫面價格與 MIS 原始回應；有漲跌停鎖住的股票時看顯示。
   - 中斷網路：60 秒後頁首顯示「報價暫停（網路）」，恢復後自動接上。
   - 13:30 之後出現收盤報價、該檔停止抓；14:00 之後才打開 App 也看到「今日收盤・待盤後更新」；盤後資料寫入後換回正式資料。
   - macOS 視窗失焦但看得到時繼續更新，最小化時停止。
   - 「價格閃色」關閉後不閃。
3. 接著寫第 3 段（大盤與投資組合）的計畫。

---

## 實作後的修正

上面各 task 的程式碼是修正前的版本，以 repo 為準。

**執行時對計畫的修正**：

- Task 4：`resortWithLive` 的測試在報價中心建立前就推送狀態（Riverpod 回報未初始化），改成先讀一次再推送。
- Task 6：
  - 畫面測試原本用 `pump()`，卡片進場動畫會留下計時器，改成 `pump(1 秒)`，跟既有測試一致。
  - 走勢小圖的斷言改成驗證傳給 `StockCard` 的 `recentPrices`。寬畫面是格狀、卡片窄，小圖本身不顯示。
- Task 8：開高低量原本放在右側價格欄，寫成一行文字，會把標頭那一列撐爆（測試寬度溢位 578 px，手機也會）。改成標頭列下方獨立一列，四項分開用 `Wrap` 換行，並新增手機版面測試（字級 1.0）。
  - 字級 2、3 時，股名／價格那一列本來就會溢位，與本段無關，未修。
- mutation：42 個突變，首輪殺掉 36 個。5 個存活，補強測試後全部殺掉：
  - 重建時事件 id 相同；
  - 非漲跌幅排序不發新狀態；
  - 只有一筆非收盤報價；
  - 設定頁關閉閃色；
  - 個股頁鎖漲停。
- 「換日時不重設 `_stalled`」判為等價：同一拍的 `_countStall` 會重算。只有請求跨午夜又失敗的那條路徑，會殘留不到 1 拍。

**opus 獨立審查**：0 Critical、4 Important、2 Minor。4 條 Important 都先寫出會失敗的測試再修。

1. **收盤後頁首卡在「證交所今天尚無報價」**。
   - 問題：收盤後逐檔抓，最近一輪可能只剩一檔，例如暫停交易、列被丟掉；其他卡片早已顯示今天的收盤報價。
   - 修法：只有在沒有卡片用今天的即時報價時，才顯示這句。
2. **閃色在位置變動時重播**（Review Focus 1）。
   - 問題：格狀模式依位置沿用元件，重排、搜尋或增刪時，會把別檔的閃色狀態套到這一格；個股頁原地換股也一樣。
   - 修法：
     - 格狀卡片以代號為 key；
     - 個股頁上方元件以代號為 key。
3. **回到自選時「已有夠新的報價」看錯對象**。
   - 問題：原本只看報價中心最近有沒有回應。在個股頁待幾分鐘再返回時，中心一直在抓那一檔，於是用其他自選股離開當下的舊價格立刻重排，之後也不再重排。
   - 修法：
     - 必須是這個畫面離開不超過一個輪詢間隔，才算夠新；
     - 第一次進入一律等第一輪。
4. **跨過午夜、開盤、收盤而資料沒變時，跟時間有關的值不重算**。
   - 問題：App 整天停在自選頁、畫面沒有重建時，「是否已有今天正式資料」停在前一天的判斷，隔天收盤後不去抓收盤報價。卡片的「最後報價」標示也停在 13:30 之前的判斷。
   - 修法：新增 `liveQuoteBoundaryProvider`，在 09:00、13:30、00:00 各換一次值。三個合併價格／頁首 provider 和兩個畫面都 watch 它。

**已裁定、維持現狀**：
- 個股頁用即時報價時，狀態文字取代整列資料日期，包括「價格與法人日期不一致」的圖示。這時上方顯示的是今天的即時價，那個提示已經不描述它。
- 自選頁首對全部自選股計算，不是只算搜尋過濾後的結果。頁首描述的是整份自選的報價狀態。
- 從個股頁返回後的最多一輪內，頁首的報價時間是報價中心全域的值。

**延後的 Minor 與已知限制**：
- App 開著過夜而 ticker 沒在跑時，回到畫面的第一拍（不超過 1 秒），頁首可能還顯示報價中心昨天的暫停或限流狀態。卡片的合併結果已經會在午夜重算。
- 畫面變為可見時，若有一輪是在登記之前就規劃好、剛好在之後完成，那一次重排會用到較舊的價格。這種情況少見；下拉重新整理或切換排序會再排一次。
- 設定頁「漲跌停提示」的說明寫的是「自選股」，實際也控制個股頁徽章（掃描、今日訊號原本就受它控制）。
- `main.dart` 啟動時同步生命週期那段沒有測試（沒有測試會建立整個 App）；判斷規則 `AppLifecycleCoordinator.isVisible` 有測試。
