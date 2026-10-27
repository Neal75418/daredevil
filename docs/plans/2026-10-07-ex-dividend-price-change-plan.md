# 除權息漲跌修正 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `daily_price.price_change` 在每一條寫入路徑都等於「收盤 − 交易所當天的平盤價」，平盤價不明時為空值、不再是 0；既有資料用修復工具修一次。

**Architecture:**
- **平盤價存在價格表**：`daily_price` 加 `base_price`，既有 DB 用 `beforeOpen` 的 `ALTER TABLE` 補欄、不 bump fingerprint。
- **唯一寫入入口**：`insertPrices` 由 insert-or-replace 改成 upsert，依 spec 第 2 節的第 0～3 條算 `price_change`；平盤價「有帶就用新的、否則保留舊的」。結構守門測試擋住其他寫入點。
- **整個市場某一天的三個寫入函式**（每日 `syncAllPricesForDate`、`backfillTwsePricesByDate`、`backfillTpexPricesByDate`）在價格之後抓同一天的平盤價（上市 TWT84U、上櫃 exDailyQ），寫進同一個 transaction；寫完查「需要平盤價的列」還缺幾列（N），依 spec 第 3 節的狀態表決定要不要向 ledger 回報定案。平盤價的錯誤放進回傳值 `BasePriceStatus`，不拋。
- **呼叫端照表處理**：每日路徑記 errors／設 `rateLimitedAbort`；步驟 5.5 記 `summary.errors`；Phase 0 記 warning；`tool/backfill.dart` 不抓平盤價。
- **每輪摘要**數「因缺平盤價而漲跌空值」的列。
- **讀取端**：漲跌幅提醒、族群排行「今日」改用漲跌價差；大盤家數排除配發表的列。
- **修復工具** `tool/backfill_base_prices.dart`：上市逐日 TWT84U、上櫃逐月 exDailyQ，只改兩欄。

**Tech Stack:** Flutter／Dart 3.10、drift（`store_date_time_values_as_text`）、dio、mocktail、flutter_test；純 Dart tool 鏈

**Spec:** `docs/plans/2026-10-07-ex-dividend-price-change-design.md`（第二版，`29191f54`；三輪 opus 審查 0 Critical／0 Important）。本計畫實作 spec「設計」第 1～6 節、「讀取端」、修復工具與「驗證」第 1～9 點；第 10 點（live）在提交後、經使用者同意才做（見文末）。

## Global Constraints

- **不改讀取端的退回邏輯**：`PriceCalculator.calculatePriceChange`、`LiveQuoteMerge`、今日損益、投資組合、個股顯示、掃描、自選都不動（spec 第 5 節）。
- **寫 `daily_price.price_change` 的地方只有 `PriceDaoMixin.insertPrices` 與 `PriceDaoMixin.applyBasePrices`**，外加既有兩個維護動作（`_ensureZeroPriceSanitized`、`cleanupInvalidStockCodes`）；Task 2 的結構守門測試擋住其他寫入點。
- **錯誤處理**：價格本身的抓取照舊 rethrow `RateLimitException`／`NetworkException`；**平盤價那一段的任何錯誤都不拋**，放進 `BasePriceStatus`（CLAUDE.md「錯誤處理」的新例外，Task 12 寫進去）。
- **純 Dart**：`lib/data/repositories/`、`lib/data/remote/`、`lib/domain/services/update/`、`tool/` 不得 import flutter（`test/tool/tool_chain_pure_dart_test.dart`；Task 12 跑 `dart compile kernel tool/daily_update.dart -o build/daily_update.dill`）。
- **Drift 改表後**跑 `dart run build_runner build --delete-conflicting-outputs`，`*.drift.dart` 一起提交。
- **不動 live DB**：`~/Library/Containers/com.neo.afterclose/Data/Documents/afterclose.sqlite` 全程唯讀；副本彩排在 `~/tmp/daredevil-rehearsal/`。
- **測試資料代號一律 99xx 虛構**；需要真實情境時照真實數值改代號（spec「平盤價來源」的樣本）。
- **文案**：通知內文的短句 zh-TW、en 都要有；不得出現 `no_investment_advice_copy_test` 的禁用詞。
- **提交**：commit／push 只在使用者說「提交」時做。直接在 main，Conventional Commits、型別英文、描述中文、不加 Co-Authored-By。每個 task 結尾只「記錄進度」（帳本在 `.superpowers/sdd/2026-10-07-ex-dividend-price-change-plan/progress.md`），整段在 Task 12 一次提交。**不在 09:00–13:30 提交**（post-commit hook 重編 launchd CLI）。
- **測試行程**：跑 `flutter test`／`dart run` 前，用 `ps -axo pid=,ppid=,etime=,comm= | grep -E '/(dart|flutter)$'` 確認沒有其他 `dart run`／`flutter test`／`flutter run`。IDEA 的 analysis server 不算。
- **mutation**：在 scratchpad 的 repo 副本做，還原用備份檔、不用 git checkout；先確認副本基線全綠；先跑直接測試，存活者再跑全部消費者測試；編譯錯誤殺掉的不算。
- **審查者**：不可 `dart run`、不可開背景任務、不可碰 scratchpad、不改檔。
- **網路請求**：測試一律 mock client；只有 Task 11 的副本彩排打真的交易所，間隔 `ApiConfig.repairToolCallDelayMs`（3 秒）。

## Review Focus

1. **同一輪上市平盤價失敗、上櫃成功**。預期：只有上市那天不回報定案，上櫃照常回報，兩個市場的狀態各自獨立。測試在 Task 6（`syncAllPricesForDate` 兩市場狀態獨立）。
2. **清單上有這檔、但「本日開盤競價基準」欄不可解析**（例：整列 `--`）。預期：解析時略過那一列、不拒收整批；合併時這檔沒有平盤價，需要平盤價的列算進 N。測試在 Task 3（parse 略過）與 Task 4（`mergeBasePrices` 不設值、N 計入）。
3. **價格回空（休市日、颱風日、端點還沒換日）**。預期：不打平盤價端點，狀態 `skipped`，行為與現在相同。測試在 Task 5（`backfillTwsePricesByDate` 價格空 → `verifyNever(getOpeningBasePrices)`）。
4. **限流發生在上櫃 exDailyQ、上市已經寫完**。預期：上市狀態 `fetched`、上櫃 `rateLimited`；每日路徑仍照常處理回傳值（`pricesUpdated`、候選股）後才設 `rateLimitedAbort`。測試在 Task 6（狀態）與 Task 7（`_syncDailyPrices`）。
5. **需要平盤價的檔不在清單上**（8908 型，來源前後不一致）。預期：MI_INDEX 路徑 `fetched`／N＞0 → 回報定案＋warning；`STOCK_DAY_ALL` 路徑 → 不回報（交給隔天 MI_INDEX）。測試在 Task 5。

---

### Task 1: 資料表加 `base_price`、既有 DB 補欄、收盤 0 清理一併清漲跌

**Files:**
- Modify: `lib/data/database/tables/daily_price.dart`
- Modify: `lib/data/database/app_database.dart`（`beforeOpen` 的 `_ensure*` 區段、`_ensureZeroPriceSanitized`、「何時 bump fingerprint」註解）
- Modify: `lib/data/database/dao/price_dao.dart:165-174`（`getLatestPricesBatch` 手動組 entry）
- Regenerate: `lib/data/database/tables/daily_price.drift.dart`、`lib/data/database/app_database.drift.dart`
- Test: `test/data/database/daily_price_base_price_column_test.dart`（新）、`test/data/database/zero_price_sanitize_test.dart`、`test/data/database/dao/price_dao_test.dart`

**Interfaces:**
- Produces：
  - `DailyPrice.basePrice`：`RealColumn get basePrice => real().named('base_price').nullable()();`，doc「交易所當天的平盤價（開盤競價基準）；只存來源直接給的值，沒取得為 null」。
  - `DailyPriceCompanion.insert(..., basePrice: Value<double?>)`、`DailyPriceEntry.basePrice`。
  - `AppDatabase._ensureDailyPriceBasePriceColumn()`：`PRAGMA table_info('daily_price')` 沒有 `base_price` 時 `ALTER TABLE daily_price ADD COLUMN base_price REAL`，記 `AppLogger.info`。排在 `_ensureDividendFactsSchema()` 之後、`_ensureRetiredSchemaDropped()` 之前。
  - `_ensureZeroPriceSanitized` 的 UPDATE 改成 `SET open = NULL, high = NULL, low = NULL, close = NULL, price_change = NULL WHERE close = 0`。
  - `getLatestPricesBatch` 回的 entry 帶 `basePrice`。

- [ ] **Step 1: 寫失敗測試**

`test/data/database/daily_price_base_price_column_test.dart`（照 `dividend_price_columns_migration_test.dart` 的升級模擬）：

```dart
test('🚨 舊 DB 開啟後補 base_price 欄：既有列保留、base_price 為 null、fingerprint 不變', () async {
  final db1 = AppDatabase(NativeDatabase(dbFile));
  await db1.upsertStocks([StockMasterCompanion.insert(symbol: '9901', name: '甲', market: 'TWSE')]);
  await db1.insertPrices([
    DailyPriceCompanion.insert(symbol: '9901', date: DateTime(2026, 9, 16),
      close: const Value(2380.0), priceChange: const Value(0.0)),
  ]);
  await db1.customStatement('ALTER TABLE daily_price DROP COLUMN base_price');
  final before = (await db1.customSelect('SELECT value FROM _drift_schema_fingerprint').getSingle()).read<String>('value');
  await db1.close();

  final db2 = AppDatabase(NativeDatabase(dbFile));
  final row = await db2.getLatestPrice('9901');
  expect(row!.close, 2380.0);
  expect(row.priceChange, 0.0);
  expect(row.basePrice, isNull);
  final after = (await db2.customSelect('SELECT value FROM _drift_schema_fingerprint').getSingle()).read<String>('value');
  expect(after, before);
  await db2.close();
});
```

`zero_price_sanitize_test.dart` 既有測試加斷言：被清的列 `priceChange` 也是 null；正常列的 `priceChange` 不動。

`price_dao_test.dart` 加：

```dart
test('getLatestPricesBatch 帶 basePrice', () async {
  await db.insertPrices([DailyPriceCompanion.insert(symbol: '9901', date: d,
    close: const Value(10.0), basePrice: const Value(9.5))]);
  expect((await db.getLatestPricesBatch(['9901']))['9901']!.basePrice, 9.5);
});
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `flutter test test/data/database/daily_price_base_price_column_test.dart test/data/database/zero_price_sanitize_test.dart test/data/database/dao/price_dao_test.dart`
Expected: 編譯失敗（`basePrice` 不存在）。

- [ ] **Step 3: 加欄、重產、補 `_ensure*`、改 UPDATE、改 `getLatestPricesBatch`、改註解**

- 「何時 bump fingerprint」註解加一條例外：「nullable 欄位用 `ALTER TABLE ADD COLUMN` 就地補、不 bump，先例 `_ensureDividendPriceColumns`、`_ensureDailyPriceBasePriceColumn`」。
- `getLatestPricesBatch` 的 SELECT 與手動組 entry 都加 `base_price`。

Run: `dart run build_runner build --delete-conflicting-outputs`

- [ ] **Step 4: 跑測試確認通過**

Run: 同 Step 2
Expected: PASS

- [ ] **Step 5: 記錄進度**

---

### Task 2: `insertPrices` upsert 規則、`applyBasePrices`、結構守門

**Files:**
- Modify: `lib/data/database/dao/price_dao.dart:181-188`
- Test: `test/data/database/dao/price_dao_upsert_rules_test.dart`（新）、`test/data/database/dao/price_dao_apply_base_prices_test.dart`（新）、`test/data/database/price_change_single_writer_guard_test.dart`（新）

**Interfaces:**
- Consumes：Task 1 的 `basePrice`。
- Produces（都在 `PriceDaoMixin`）：
  - `Future<void> insertPrices(List<DailyPriceCompanion> entries)`：簽名不變，語意改成依 `(symbol, date)` upsert。每一筆：
    - 開高低收、成交量：用新值。
    - `base_price`：`COALESCE(excluded.base_price, old.base_price)`。
    - `price_change`，依序：
      0. 新收盤 null → null。
      1. 合併後的 `base_price` 非 null → `ROUND(excluded.close − 合併後 base_price, 2)`。
      2. 否則，entry 的 `priceChange.present` → `excluded.price_change`。
      3. 否則 → `old.close IS excluded.close` 時 `old.price_change`，否則 null。
    - **分兩種 `DoUpdate.withExcluded`**，依 `entry.priceChange.present` 分批；insert 分支的值由 Dart 先依第 0、1、2 條算好（沒有舊列時合併後的 `base_price` 就是新值；`present` 為 false 時插入 null）。
  - `typedef BasePriceRow = ({String symbol, DateTime date, double basePrice});`
  - `Future<int> applyBasePrices(List<BasePriceRow> rows)`：只更新**已存在**的列：`base_price = ?`，`price_change = CASE WHEN close IS NULL THEN NULL ELSE ROUND(close − ?, 2) END`。回傳實際更新的列數。不 insert。
  - `Future<int> nullifyPriceChangeWithoutClose({required DateTime date, required String market})`：`UPDATE daily_price SET price_change = NULL WHERE date = ? AND close IS NULL AND price_change IS NOT NULL AND symbol IN (SELECT symbol FROM stock_master WHERE market = ?)`。
  - `Future<int> countMissingBasePrice({required DateTime date, required Set<String> symbols})`：`symbols` 為空回 0；否則 `COUNT(*)` where `date = ? AND base_price IS NULL AND symbol IN (...)`。

- [ ] **Step 1: 寫失敗測試**

`price_dao_upsert_rules_test.dart`（真 in-memory DB，`DateContext.normalize` 過的日期 `d`）：

```dart
DailyPriceCompanion row({double? close, Value<double?> change = const Value.absent(), double? base}) =>
  DailyPriceCompanion.insert(symbol: '9901', date: d, close: Value(close), priceChange: change,
    basePrice: base == null ? const Value.absent() : Value(base));
Future<DailyPriceEntry> get() async => (await db.getLatestPrice('9901'))!;

group('insert 分支（空表）', () {
  test('第 0 條：收盤 null → 漲跌 null，平盤價照存', () async {
    await db.insertPrices([row(close: null, change: const Value(0.0), base: 18.35)]);
    expect((await get()).priceChange, isNull); expect((await get()).basePrice, 18.35);
  });
  test('第 1 條：有平盤價 → 收盤 − 平盤價（STOCK_DAY_ALL 給的 0 被蓋掉）', () async {
    await db.insertPrices([row(close: 2380, change: const Value(0.0), base: 2385)]);
    expect((await get()).priceChange, -5.0);
  });
  test('第 1 條四捨五入到 0.01', () async {
    await db.insertPrices([row(close: 32.12, change: const Value.absent(), base: 32.44)]);
    expect((await get()).priceChange, -0.32);
  });
  test('第 2 條：沒平盤價、帶明確空值 → null', () async {
    await db.insertPrices([row(close: 10, change: const Value(null))]);
    expect((await get()).priceChange, isNull);
  });
  test('第 2 條：沒平盤價、帶數字 → 用它', () async {
    await db.insertPrices([row(close: 10, change: const Value(0.5))]);
    expect((await get()).priceChange, 0.5);
  });
  test('第 3 條：沒平盤價、沒帶漲跌欄、沒舊列 → null', () async {
    await db.insertPrices([row(close: 10)]);
    expect((await get()).priceChange, isNull);
  });
});

group('update 分支（已有列）', () {
  test('平盤價「有帶就用新的、否則保留舊的」', () async {
    await db.insertPrices([row(close: 10, base: 9.5)]);
    await db.insertPrices([row(close: 10.5)]);
    expect((await get()).basePrice, 9.5);
    await db.insertPrices([row(close: 10.5, base: 9.6)]);
    expect((await get()).basePrice, 9.6);
  });
  test('覆寫時保留平盤價、用新收盤重算（21:30 重寫）', () async {
    await db.insertPrices([row(close: 2380, change: const Value(0.0), base: 2385)]);
    await db.insertPrices([row(close: 2385, change: const Value(0.0))]);
    expect((await get()).priceChange, 0.0);
  });
  test('有平盤價時，明確空值（X0.00）也被第 1 條蓋掉', () async {
    await db.insertPrices([row(close: 2380, base: 2385)]);
    await db.insertPrices([row(close: 2380, change: const Value(null))]);
    expect((await get()).priceChange, -5.0);
  });
  test('沒平盤價、明確空值 → 寫空值、不保留舊的 0', () async {
    await db.insertPrices([row(close: 10, change: const Value(0.0))]);
    await db.insertPrices([row(close: 10, change: const Value(null))]);
    expect((await get()).priceChange, isNull);
  });
  test('FinMind（沒帶漲跌欄）收盤沒變 → 保留舊漲跌', () async {
    await db.insertPrices([row(close: 10, change: const Value(0.5))]);
    await db.insertPrices([row(close: 10)]);
    expect((await get()).priceChange, 0.5);
  });
  test('FinMind 收盤變了 → 空值', () async {
    await db.insertPrices([row(close: 10, change: const Value(0.5))]);
    await db.insertPrices([row(close: 10.5)]);
    expect((await get()).priceChange, isNull);
  });
  test('第 0 條優先：有平盤價但新收盤 null → 漲跌 null', () async {
    await db.insertPrices([row(close: 10, base: 9.5)]);
    await db.insertPrices([row(close: null, change: const Value(0.0))]);
    expect((await get()).priceChange, isNull); expect((await get()).basePrice, 9.5);
  });
  test('同一批混合 present／absent 都照各自規則', () async { /* 9901 present、9902 absent，各驗一條 */ });
});
```

`price_dao_apply_base_prices_test.dart`：

```dart
test('只更新已存在的列；收盤 null 的列漲跌 null；不存在的 (symbol, date) 不插入', () async {
  await db.insertPrices([row('9901', d, close: 2380, change: 0.0), row('9902', d, close: null, change: 0.0)]);
  final n = await db.applyBasePrices([
    (symbol: '9901', date: d, basePrice: 2385), (symbol: '9902', date: d, basePrice: 10),
    (symbol: '9903', date: d, basePrice: 1),
  ]);
  expect(n, 2);
  expect((await db.getLatestPrice('9901'))!.priceChange, -5.0);
  expect((await db.getLatestPrice('9902'))!.priceChange, isNull);
  expect(await db.getLatestPrice('9903'), isNull);
});
test('冪等：跑兩次結果相同', () async { ... });
test('nullifyPriceChangeWithoutClose 只動該日該市場、收盤 null 的列', () async {
  // 9901 TWSE close null change 0 → null；9902 TWSE close 10 change 0 → 不動；9903 TPEx close null change 0 → 不動
});
test('countMissingBasePrice：symbols 為空回 0；只數 base_price IS NULL 的列', () async { ... });
```

`price_change_single_writer_guard_test.dart`（照 `financial_backlog_single_entry_guard_test.dart` 的掃描寫法，掃 `lib/` 與 `tool/`）：

```dart
test('🚨 寫 daily_price 的地方只有 price_dao 的 insertPrices／applyBasePrices／nullifyPriceChangeWithoutClose、cleanupInvalidStockCodes 的 DELETE，以及 app_database 的 _ensureZeroPriceSanitized', () {
  // 掃描兩類寫入：
  //  (a) Drift API：`into(dailyPrice)`、`update(dailyPrice)`、`delete(dailyPrice)`、`b.insert(dailyPrice`、`b.update(dailyPrice`
  //  (b) 原始 SQL：/(INSERT\s+INTO|UPDATE|DELETE\s+FROM|REPLACE\s+INTO)\s+daily_price\b/i
  // 每個 match 記 `path@offset`；允許清單是 (檔案, 所在函式名) 的集合，用「match 往前最近的 `Future<...> name(`」判函式
  expect(files.length, greaterThan(100), reason: 'sanity floor');
  expect(violations, isEmpty, reason: '寫 daily_price 只能經唯一入口');
  expect(allowedHits, containsAll(['insertPrices', 'applyBasePrices', 'nullifyPriceChangeWithoutClose', 'cleanupInvalidStockCodes', '_ensureZeroPriceSanitized']),
    reason: '掃描器失效時這裡先紅');
});
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `flutter test test/data/database/dao/price_dao_upsert_rules_test.dart test/data/database/dao/price_dao_apply_base_prices_test.dart test/data/database/price_change_single_writer_guard_test.dart`
Expected: upsert 測試「有平盤價 → 收盤 − 平盤價」等 FAIL（現在整列覆寫、漲跌照來源）；`applyBasePrices` 編譯失敗；守門測試 allowedHits 缺 `applyBasePrices` FAIL。

- [ ] **Step 3: 實作 `insertPrices`、`applyBasePrices`、`nullifyPriceChangeWithoutClose`、`countMissingBasePrice`**

`insertPrices`：先依 `priceChange.present` 把 entries 分兩組；insert 值用 Dart 算（第 0、1、2 條）；`batch` 內 `b.insert(dailyPrice, entry, onConflict: DoUpdate.withExcluded((old, excluded) => DailyPriceCompanion.custom(...)))`，`price_change` 的 CASE 用 `CustomExpression<double>` 寫 SQL。doc 寫明四條規則與兩個分支。

- [ ] **Step 4: 跑測試確認通過；跑既有消費者**

Run: 同 Step 2，再 `flutter test test/data/database test/data/repositories`
Expected: 全 PASS。既有測試若有「覆寫後沒帶的欄位變 null」的前提而紅，逐一讀該測試的意圖：是在測 REPLACE 語意的（改成帶明確值），還是真的回歸（修實作）。改掉的測試列進帳本。

- [ ] **Step 5: 記錄進度**

---

### Task 3: 解析器：TWT84U 平盤價、MI_INDEX 的 X、上櫃文字標記、exDailyQ 開始交易基準價

**Files:**
- Modify: `lib/core/constants/api_endpoints.dart`（`twseDailyPricesAll` 旁）
- Modify: `lib/data/remote/twse_client.dart`（`parseMiIndexDailyPrices:200-210`、新增 `getOpeningBasePrices`／`parseOpeningBasePrices`，放在 `getAllDailyPricesHistorical` 之後）
- Modify: `lib/data/models/tpex/tpex_daily_price.dart`、`lib/data/remote/tpex_client.dart:188-207`（`parseDailyPriceRow`）、`:750-813`（`parseExRightResults`）
- Modify: `lib/data/models/twse/exright_result.dart`
- Create: `test/fixtures/remote/twse_twt84u.json`
- Test: `test/data/remote/twse_opening_base_price_parser_test.dart`（新）、`test/data/remote/historical_daily_price_parser_test.dart`、`test/data/remote/tpex_daily_price_no_comparison_test.dart`（新）、`test/data/remote/ex_right_result_parser_test.dart`

**Interfaces:**
- Produces：
  - `ApiEndpoints.twsePriceLimits = '/exchangeReport/TWT84U'`，doc「股價升降幅度：每檔當天的漲停、開盤競價基準（平盤價）、跌停；帶 `date=YYYYMMDD&selectType=ALLBUT0999&response=json`；可查歷史（2025-06-10 起實測）」。
  - `Future<Map<String, double>> TwseClient.getOpeningBasePrices(DateTime date)`：`executeRequest` 包住；回應經 `decodeResponseData`；`parseOpeningBasePrices` 回 null 時拋 `ApiException('$_tag 股價升降幅度: 回應不可信 (yyyy-MM-dd)')`（與 `getExRightResults` 同政策：不可信不回空）。快取鍵 `openingBase:$dateStr`。
  - `static Map<String, double>? TwseClient.parseOpeningBasePrices(Map<dynamic, dynamic> json, DateTime requestedDate)`：
    - `stat` 不是 `OK`（大小寫不計）、`date != formatDateCompact(requestedDate)`、`groups` 裡沒有 `title == '本日'` 的組、`fields` 在該組範圍內沒有「開盤競價基準」、`total` 解析後 ≠ `data.length` → null。
    - 每列：代號 `trim`、基準欄 `TwParseUtils.parsePrice`；代號空或基準 null → **略過該列**（不拒收）。
  - `parseMiIndexDailyPrices`：方向 html 含 `X` → `change = null`；含 `-`→負；含 `+`→正；其餘（空白）→ 0.0。判斷順序：先 `X`。
  - `TpexDailyPrice.noComparison`（`bool`，建構子 `this.noComparison = false`）：「漲跌欄是文字（除息／除權／除權息）；`---`、`--`、空白不算」。
  - `TpexClient.parseDailyPriceRow`：`raw = row[3]?.toString().trim()`；`change = parseFormattedDouble(raw)`；`noComparison = change == null && raw.isNotEmpty && raw != '---' && raw != '--'`。
  - `ExRightResult.tradingBasePrice`（`double?`，建構子具名可選；`withDetail` 帶過去）：「開始交易基準價（exDailyQ）：上櫃除權息日的平盤價」。
  - `TpexClient.parseExRightResults`：欄位「開始交易基準價」**可選**（`indexOf` 為 −1 時整批照收、該欄 null）；有欄時 `parseFormattedDouble`，解析不了存 null、不拒收。

- [ ] **Step 1: 建 fixture `test/fixtures/remote/twse_twt84u.json`**

照 `ALLBUT0999` 真實回應的形狀（`stat`、`date`、`selectType`、`title`、`fields` 11 欄、`groups` 4 組、`data`、`hints`、`total`），`date` 用 `20261027`，5 列，代號虛構、數值取自真實樣本：

| 代號 | 漲停價 | 本日開盤競價基準 | 跌停價 | 前日開盤競價基準 | 前日收盤價 | 買進 | 賣出 | 最近成交日 | 零股 | 來源 |
|:--|--:|--:|--:|--:|--:|--:|--:|:--|:--|:--|
| 9901 | 2,620.00 | 2,385.00 | 2,150.00 | 2,420.00 | 2,385.00 | 2,385.00 | 2,390.00 | 115.10.22 | 可 | 2330 10/27（本日≠前日基準，能分辨取錯組） |
| 9902 | 15.70 | 14.30 | 12.90 | 14.30 | 0.00 | 14.15 | 14.30 | 115.09.14 | 可 | 3432 9/16（前收 0） |
| 9903 | 27.20 | 24.75 | 22.30 | -- | -- | -- | -- | 115.10.21 | 可 | 1516 10/27（前日欄空白） |
| 9904 | 9,999.95 | 7.86 | 0.01 | 7.94 | 0.00 | 7.78 | 7.86 | 115.10.16 | 可 | 00625K 10/27 |
| 9905 | -- | -- | -- | -- | -- | -- | -- | 115.09.15 | 可 | 虛構：本日基準不可解析 |

`groups`：`[{"start":0,"span":2,"title":""},{"start":2,"span":3,"title":"本日"},{"start":5,"span":4,"title":"前日"},{"start":9,"span":2,"title":""}]`；`total: 5`。

- [ ] **Step 2: 寫失敗測試**

`twse_opening_base_price_parser_test.dart`：

```dart
final json = jsonDecode(File('test/fixtures/remote/twse_twt84u.json').readAsStringSync());
test('取「本日」那組的開盤競價基準；不可解析的列略過', () {
  final m = TwseClient.parseOpeningBasePrices(json, DateTime(2026, 10, 27))!;
  expect(m, {'9901': 2385.0, '9902': 14.3, '9903': 24.75, '9904': 7.86});
});
test('用前日那組會紅', () {
  expect(TwseClient.parseOpeningBasePrices(json, DateTime(2026, 10, 27))!['9901'], isNot(2420.0));
});
test('日期不符 → null', () => expect(TwseClient.parseOpeningBasePrices(json, DateTime(2026, 10, 26)), isNull));
test('stat 非 OK → null', ...); test('total 與列數不符 → null', ...); test('沒有「本日」group → null', ...);
test('getOpeningBasePrices：回應不可信拋 ApiException；HTML 回應拋 RateLimitException', () { /* MockDio 照 ex_right_result_parser_test */ });
```

`historical_daily_price_parser_test.dart` 的 MI_INDEX group 加兩列：方向 `<p style= color:red>+</p>`／`<p>X</p>` 與 `<p> </p>`：

```dart
test('方向 X → change null；空白 → 0.0；+ → 正', () { ... });
```

`tpex_daily_price_no_comparison_test.dart`（`parseDailyPriceRow` 直接餵列）：

```dart
for (final (raw, change, flag) in [('除息', null, true), ('除權', null, true), ('除權息', null, true),
  ('---', null, false), ('--', null, false), ('', null, false), ('+9.80', 9.8, false), ('-0.46', -0.46, false)]) { ... }
```

`ex_right_result_parser_test.dart` 的 TPEx group 加：

```dart
test('有「開始交易基準價」欄 → tradingBasePrice；該欄不可解析 → null、整批照收', ...);
test('沒有該欄 → 整批照收、tradingBasePrice 全 null', ...);
```

- [ ] **Step 3: 跑測試確認失敗**

Run: `flutter test test/data/remote/twse_opening_base_price_parser_test.dart test/data/remote/historical_daily_price_parser_test.dart test/data/remote/tpex_daily_price_no_comparison_test.dart test/data/remote/ex_right_result_parser_test.dart`
Expected: 編譯失敗（`parseOpeningBasePrices`、`noComparison`、`tradingBasePrice` 不存在）；MI_INDEX 的 X 測試 FAIL（現在回 0.0）。

- [ ] **Step 4: 實作四處解析與端點常數**

- [ ] **Step 5: 跑測試確認通過；跑 `test/data/remote` 與 `test/domain/services/update`（`DividendSyncer`、`DividendBackfiller` 讀 `ExRightResult`）**

Expected: 全 PASS。

- [ ] **Step 6: 記錄進度**

---

### Task 4: 狀態型別與平盤價合併的純函式

**Files:**
- Modify: `lib/domain/repositories/price_repository.dart`（`MarketSyncResult` 旁）
- Create: `lib/data/repositories/base_price_merge.dart`
- Modify: `lib/core/constants/api_config.dart`（`finalityRefetchCallDelayMs` 旁；`historicalMarketDayMaxCallsPerRun` 註解）
- Test: `test/domain/repositories/base_price_status_test.dart`（新）、`test/data/repositories/base_price_merge_test.dart`（新）

**Interfaces:**
- Produces（`lib/domain/repositories/price_repository.dart`）：

```dart
/// 平盤價抓取結果（spec 第 3 節狀態表）
enum BasePriceFetch { fetched, failed, rateLimited, notNeeded, skipped }

class BasePriceStatus {
  const BasePriceStatus({required this.fetch, this.missing = 0, this.withheld = false, this.reason, this.error});
  final BasePriceFetch fetch;
  /// 需要平盤價、合併後仍沒有的列數（N）
  final int missing;
  /// 本函式因平盤價而沒向 ledger 回報定案
  final bool withheld;
  final String? reason;
  final Object? error;
  bool get rateLimited => fetch == BasePriceFetch.rateLimited;
  /// 呼叫端要記 errors 的情況（spec 呼叫端表的「缺」）
  bool get shouldRecordError => withheld && !rateLimited;
  static const notNeeded = BasePriceStatus(fetch: BasePriceFetch.notNeeded);
  static const skipped = BasePriceStatus(fetch: BasePriceFetch.skipped);
}

class MarketDayBackfillResult {
  const MarketDayBackfillResult({required this.rows, required this.basePrice});
  final int rows;
  final BasePriceStatus basePrice;
}
```

  `MarketSyncResult` 加 `this.basePrices = const {}`（`Map<String, BasePriceStatus>`，鍵 `MarketCode`）。
- Produces（`lib/data/repositories/base_price_merge.dart`，全部 top-level 純函式）：
  - `Set<String> twseDailyNeedsBasePrice(Iterable<TwseDailyPrice> prices)`：`close != null && change == 0`。
  - `Set<String> twseHistoricalNeedsBasePrice(Iterable<TwseDailyPrice> prices)`：`close != null && change == null`。
  - `Set<String> tpexNeedsBasePrice(Iterable<TpexDailyPrice> prices)`：`close != null && noComparison`。
  - `List<DailyPriceCompanion> mergeBasePrices(List<DailyPriceCompanion> entries, {required Map<String, double> bases, required Set<String> needs, required bool zeroToNull})`：每筆 `bases[symbol]` 有值 → `basePrice: Value(v)`；`zeroToNull && needs.contains(symbol) && bases[symbol] == null` → `priceChange: const Value(null)`；其餘欄不動、順序不動。
- Produces（`ApiConfig`）：`static const int basePriceCallDelayMs = 1000;` doc「平盤價請求前的等待，保守值同 `finalityRefetchCallDelayMs`；已知 0.5 秒間隔連打約 50 次會被證交所擋」。`historicalMarketDayMaxCallsPerRun` 註解補「上市每一天是 2 個請求（MI_INDEX＋TWT84U）」。

- [ ] **Step 1: 寫失敗測試**

```dart
// base_price_status_test.dart
test('shouldRecordError 只在 withheld 且非限流', () {
  expect(const BasePriceStatus(fetch: BasePriceFetch.failed, missing: 3, withheld: true).shouldRecordError, isTrue);
  expect(const BasePriceStatus(fetch: BasePriceFetch.rateLimited, missing: 3, withheld: true).shouldRecordError, isFalse);
  expect(const BasePriceStatus(fetch: BasePriceFetch.fetched, missing: 3).shouldRecordError, isFalse);
  expect(const BasePriceStatus(fetch: BasePriceFetch.failed).shouldRecordError, isFalse);
});
// base_price_merge_test.dart
test('twseDailyNeedsBasePrice：change 0 且收盤非 null', ...);   // 0 → 需要；0.5 → 不需要；null → 不需要；收盤 null → 不需要
test('twseHistoricalNeedsBasePrice：change null 且收盤非 null', ...); // null → 需要；0 → 不需要
test('tpexNeedsBasePrice：noComparison 且收盤非 null', ...);
test('mergeBasePrices：有基準設 basePrice；zeroToNull 時需要而沒基準的列 priceChange 改 null；不需要的列不動；Review Focus 2：清單缺該檔 → 不設值', () {
  final out = mergeBasePrices([e('9901', change: 0), e('9902', change: 0), e('9903', change: 0.5)],
    bases: {'9901': 9.5}, needs: {'9901', '9902'}, zeroToNull: true);
  expect(out[0].basePrice.value, 9.5); expect(out[0].priceChange.value, 0);   // 第 1 條在 DAO 才算
  expect(out[1].basePrice.present, isFalse); expect(out[1].priceChange, const Value<double?>(null));
  expect(out[2].priceChange.value, 0.5);
});
test('zeroToNull=false 時需要而沒基準的列 priceChange 不動', ...);
```

- [ ] **Step 2: 跑測試確認失敗**（編譯失敗）
- [ ] **Step 3: 實作**
- [ ] **Step 4: 跑測試確認通過**

Run: `flutter test test/domain/repositories/base_price_status_test.dart test/data/repositories/base_price_merge_test.dart`

- [ ] **Step 5: 記錄進度**

---

### Task 5: 上市的市場日寫入帶平盤價（每日路徑的上市半邊、MI_INDEX 回補）

**Files:**
- Modify: `lib/domain/repositories/price_repository.dart`（三個方法簽名）
- Modify: `lib/data/repositories/price_repository.dart`（建構子、`syncAllPricesForDate:321-467`、`backfillTwsePricesByDate:214-253`、`_afterMarketDayWrite:471-489`）
- Test: `test/data/repositories/price_repository_base_price_twse_test.dart`（新）、`test/data/repositories/price_repository_test.dart`（STOCK_DAY 路徑的覆寫測試）

**Interfaces:**
- Consumes：Task 2 的 `insertPrices`／`countMissingBasePrice`；Task 3 的 `getOpeningBasePrices`；Task 4 的型別與純函式。
- Produces：
  - `IPriceRepository`：
    - `Future<MarketSyncResult> syncAllPricesForDate(DateTime date, {bool force = false, MarketDayFetchLedger? ledger, bool withBasePrices = true})`
    - `Future<MarketDayBackfillResult> backfillTwsePricesByDate({required DateTime date, required Set<String> targetSymbols, MarketDayFetchLedger? ledger, bool withBasePrices = true})`
    - `Future<MarketDayBackfillResult> backfillTpexPricesByDate({...同上})`（本 task 只改簽名與回傳 `BasePriceStatus.skipped`，Task 6 補邏輯）
    - 三者 doc 加：「`withBasePrices: false` 不得與 `ledger` 同時傳（assert）」。
  - `PriceRepository` 建構子加 `Duration basePriceDelay = const Duration(milliseconds: ApiConfig.basePriceCallDelayMs)`。
  - 私有 `Future<({Map<String, double> bases, BasePriceFetch fetch, Object? error, String? reason})> _fetchTwseBasePrices(DateTime day)`：先 `await Future<void>.delayed(basePriceDelay)`；`RateLimitException` → `rateLimited`；`NetworkException`／`ApiException`／其他 → `failed`（記 `AppLogger.warning`，不拋）。
  - 私有 `Future<BasePriceStatus> _writeMarketDay({required String market, required DateTime day, required List<DailyPriceCompanion> entries, required Set<String> needs, required BasePriceFetch fetch, Object? error, String? reason, required bool fromDailyEndpoint, required MarketDayFetchLedger? ledger})`：在**呼叫端的 transaction 內**執行：`insertPrices` → `missing = needs.isEmpty ? 0 : countMissingBasePrice(date: day, symbols: needs)` → 決定 `withheld`（spec 狀態表）：
    - `fetch == fetched && missing > 0`：`fromDailyEndpoint` → `withheld = true`（例外二）；否則 `withheld = false`、warning「清單不全 N 列」。
    - `fetch == failed || rateLimited`：`withheld = missing > 0`。
    - `notNeeded`／`skipped`：`withheld = false`。
    → `recomputeDayTradingRatios` 照舊 → `!withheld && ledger != null` 才 `ledger.report`。回傳 `BasePriceStatus`。
  - `_afterMarketDayWrite` 併入 `_writeMarketDay`（刪掉）。

- 上市每日路徑（`syncAllPricesForDate`）：`twsePrices` 非空且 `withBasePrices` → `needs = twseDailyNeedsBasePrice(twsePrices) ∩ 寫入的代號`，以 `twseResult.dataDate` 抓 `_fetchTwseBasePrices`；`entries = mergeBasePrices(..., zeroToNull: true)`；transaction 內呼叫 `_writeMarketDay(fromDailyEndpoint: true)`。`twsePrices` 空 → `skipped`。回傳 `basePrices: {MarketCode.twse: status, MarketCode.tpex: ...}`；提早回傳的兩個分支（已定案跳過、兩市場皆空）`basePrices` 留預設。
- `backfillTwsePricesByDate`：`filtered` 非空且 `withBasePrices` → `needs = twseHistoricalNeedsBasePrice(prices)` ∩ `filtered` 代號；`mergeBasePrices(zeroToNull: false)`（X 已是 null）；`_writeMarketDay(fromDailyEndpoint: false)`。`filtered` 空 → `MarketDayBackfillResult(rows: 0, basePrice: skipped)`。
- 平盤價抓取在 transaction **外**。

- [ ] **Step 1: 寫失敗測試**

`price_repository_base_price_twse_test.dart`（harness 照 `price_repository_finality_test.dart`：真 DB、`MockTwseClient`、`MockTpexClient`、`basePriceDelay: Duration.zero`、真 `MarketDayFetchLedger`；主檔 9901～9904 上市、9911 上櫃；`tpex.getAllDailyPrices` 預設回 `[]`）：

```dart
group('backfillTwsePricesByDate（MI_INDEX）', () {
  test('X 列拿到平盤價 → 漲跌＝收盤−平盤價、fetched／N=0、回報定案', () async {
    stubHist([p('9901', close: 2380, change: null), p('9902', close: 10, change: 0.5)]);
    stubBase({'9901': 2385, '9902': 9.5});
    final r = await repo.backfillTwsePricesByDate(date: day, targetSymbols: {'9901','9902'}, ledger: ledger);
    expect(r.rows, 2);
    expect(r.basePrice.fetch, BasePriceFetch.fetched); expect(r.basePrice.missing, 0);
    expect(price('9901').priceChange, -5.0); expect(price('9902').priceChange, 0.5); expect(price('9902').basePrice, 9.5);
    expect(ledger.recorded.single.market, MarketCode.twse);
  });
  test('Review Focus 3：價格回空 → 不打 TWT84U、skipped、不回報', () async {
    stubHist([]); final r = await repo.backfillTwsePricesByDate(...);
    verifyNever(() => twse.getOpeningBasePrices(any())); expect(r.basePrice.fetch, BasePriceFetch.skipped); expect(ledger.recorded, isEmpty);
  });
  test('平盤價網路錯誤、N>0 → 價格照寫、X 列空值、failed／withheld、不回報、當沖比例照算', () async {
    when(() => twse.getOpeningBasePrices(any())).thenThrow(const NetworkException('x'));
    ... expect(price('9901').priceChange, isNull); expect(r.basePrice.withheld, isTrue); expect(r.basePrice.shouldRecordError, isTrue); expect(ledger.recorded, isEmpty);
  });
  test('平盤價失敗、但 X 列先前已有平盤價（N=0）→ 回報、shouldRecordError=false', () async {
    await db.insertPrices([e('9901', close: 2370, basePrice: 2385)]); // 先前 15:30
    stubHist([p('9901', close: 2380, change: null)]); when(...getOpeningBasePrices).thenThrow(const NetworkException('x'));
    ... expect(price('9901').priceChange, -5.0); expect(r.basePrice.fetch, BasePriceFetch.failed); expect(r.basePrice.withheld, isFalse); expect(ledger.recorded, hasLength(1));
  });
  test('平盤價限流 → 價格照寫、rateLimited、函式不拋；N>0 不回報', () async {
    when(...).thenThrow(const RateLimitException('r')); ... expect(r.basePrice.rateLimited, isTrue); expect(r.basePrice.shouldRecordError, isFalse);
  });
  test('Review Focus 5：X 列不在清單（fetched／N>0）→ 回報定案、withheld=false', () async {
    stubHist([p('9901', close: 2380, change: null)]); stubBase({'9902': 9.5});
    ... expect(r.basePrice.missing, 1); expect(r.basePrice.withheld, isFalse); expect(ledger.recorded, hasLength(1));
  });
  test('漲跌是非 0 數字、不在清單 → 不影響 N', ...);
  test('價格本身限流／網路錯誤照舊拋', ...);
  test('withBasePrices=false → 不打 TWT84U、skipped、照舊回報；與 ledger 同時傳 → assert', ...);
  test('請求順序：先價格、再等 basePriceDelay、再 TWT84U（注入可量的 delay 或用 verifyInOrder）', ...);
});

group('syncAllPricesForDate 上市半邊（STOCK_DAY_ALL）', () {
  test('0 列拿到平盤價 → 第 1 條；非 0 列照來源；回報定案；basePrices[TWSE].fetched', ...);
  test('平盤價失敗 → 0 列存空值（不是 0）、非 0 列照來源、withheld、不回報', () async {
    stubDaily([p('9901', close: 2380, change: 0), p('9902', close: 10, change: 0.5)]); when(...).thenThrow(const NetworkException('x'));
    ... expect(price('9901').priceChange, isNull); expect(price('9902').priceChange, 0.5); expect(r.basePrices[MarketCode.twse]!.withheld, isTrue);
  });
  test('Review Focus 5 例外二：0 列不在清單（fetched／N>0）→ 不回報（交給 MI_INDEX）', () async {
    ... expect(r.basePrices[MarketCode.twse]!.fetch, BasePriceFetch.fetched); expect(...withheld, isTrue); expect(ledger.recorded, isEmpty);
  });
  test('21:30 重寫：先前已有平盤價、這次 TWT84U 失敗 → 用新收盤重算、N=0、回報', ...);
  test('以 STOCK_DAY_ALL 回應的資料日抓 TWT84U（端點還是前一天時抓前一天）', () { verify(() => twse.getOpeningBasePrices(previousDay)).called(1); });
  test('已定案跳過／兩市場皆空 → basePrices 為空 Map', ...);
});
```

`price_repository_test.dart` 加（驗證第 4 點的 STOCK_DAY 月資料路徑）：

```dart
test('🚨 syncStockPrices（上市 STOCK_DAY）覆寫已有平盤價的列：X0.00 不會洗掉正確值', () async {
  await db.insertPrices([e('9901', date: d, close: 2380, basePrice: 2385)]);  // 已補正 −5
  stubMonthly([TwseDailyPrice(date: d, code: '9901', close: 2380, change: null, ...)]);
  await repository.syncStockPrices('9901', startDate: ..., endDate: ...);
  expect((await db.getLatestPrice('9901'))!.priceChange, -5.0);
});
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `flutter test test/data/repositories/price_repository_base_price_twse_test.dart test/data/repositories/price_repository_test.dart`
Expected: 編譯失敗（回傳型別、`getOpeningBasePrices` stub）。

- [ ] **Step 3: 實作**（介面、`_fetchTwseBasePrices`、`_writeMarketDay`、兩個函式；`backfillTpexPricesByDate` 先只改簽名、回 `skipped`）

- [ ] **Step 4: 跑測試確認通過；跑 `test/data/repositories` 與所有 mock `IPriceRepository`／`PriceRepository` 的測試**

Run: `flutter test test/data/repositories test/domain/services/update test/domain/services/update_service_test.dart test/tool`
Expected: 新測試 PASS；呼叫端測試因回傳型別改變而編譯失敗是**預期**（Task 7 修），把紅的檔案列進帳本。

- [ ] **Step 5: 記錄進度**

---

### Task 6: 上櫃的市場日寫入帶平盤價（文字標記才抓 exDailyQ 單日）

**Files:**
- Modify: `lib/data/repositories/price_repository.dart`（`syncAllPricesForDate` 上櫃半邊、`backfillTpexPricesByDate:264-310`）
- Test: `test/data/repositories/price_repository_base_price_tpex_test.dart`（新）、`test/data/repositories/price_repository_test.dart`（FinMind 路徑的覆寫測試）

**Interfaces:**
- Consumes：Task 5 的 `_writeMarketDay`、`MarketDayBackfillResult`；Task 3 的 `noComparison`、`tradingBasePrice`。
- Produces：
  - 私有 `Future<({Map<String, double> bases, BasePriceFetch fetch, Object? error, String? reason})> _fetchTpexBasePrices(DateTime day, Set<String> needs)`：`needs` 空 → `notNeeded`、不打；否則等 `basePriceDelay` 後 `_tpexClient.getExRightResults(startDate: day, endDate: day)`，`bases = {r.symbol: r.tradingBasePrice!}`（只收 `exDate == day` 且 `tradingBasePrice != null` 的列）；**例外一**：`needs ∩ bases.keys` 為空（含回空清單）→ `fetch = failed`、`reason = '除權除息結果一列都對不上'`；錯誤分類同上市。
  - 上櫃每日路徑與 `backfillTpexPricesByDate`：`needs = tpexNeedsBasePrice(prices) ∩ 寫入的代號`；`mergeBasePrices(zeroToNull: false)`；`_writeMarketDay(fromDailyEndpoint: false)`（上櫃沒有例外二）。

- [ ] **Step 1: 寫失敗測試**

```dart
group('backfillTpexPricesByDate', () {
  test('有文字標記 → 抓 exDailyQ 單日（startDate==endDate==day）、漲跌＝收盤−開始交易基準價、回報', () async {
    stubHist([tp('9911', close: 32.12, change: null, noComparison: true), tp('9912', close: 814, change: -12)]);
    stubEx([ex('9911', day, base: 32.44)]);
    ... expect(price('9911').priceChange, -0.32); expect(price('9912').priceChange, -12); verify(() => tpex.getExRightResults(startDate: day, endDate: day)).called(1);
  });
  test('沒有文字標記 → 不打 exDailyQ、notNeeded、回報', () { verifyNever(() => tpex.getExRightResults(...)); });
  test('不比價以 targetSymbols 過濾後的列判斷：唯一的文字標記列不在 targetSymbols → notNeeded', ...);
  test('例外一：有文字標記、exDailyQ 回空清單 → failed、不回報', ...);
  test('例外一：回了別檔、需要的一列都對不上 → failed、不回報', ...);
  test('部分對上（清單不全）→ fetched／N>0、回報＋warning', ...);
  test('exDailyQ 限流 → rateLimited、不拋、N>0 不回報', ...);
  test('tradingBasePrice 為 null 的列不算對上', ...);
});
group('syncAllPricesForDate 兩市場', () {
  test('Review Focus 1：上市平盤價失敗、上櫃成功 → 只有上櫃回報；basePrices 兩個鍵各自正確', ...);
  test('Review Focus 4：上市 fetched、上櫃 exDailyQ 限流 → basePrices[TPEx].rateLimited、上市照常回報、函式不拋', ...);
});
```

`price_repository_test.dart` 加（驗證第 4 點的 FinMind 路徑）：

```dart
test('🚨 syncStockPrices（上櫃 FinMind）覆寫已有平盤價的列：收盤沒變保留正確值；收盤變了用新收盤重算', ...);
```

- [ ] **Step 2: 跑測試確認失敗**
- [ ] **Step 3: 實作**
- [ ] **Step 4: 跑測試確認通過**

Run: `flutter test test/data/repositories`

- [ ] **Step 5: 記錄進度**

---

### Task 7: 呼叫端照表處理（每日路徑、步驟 5.5、Phase 0、`tool/backfill.dart`）

**Files:**
- Modify: `lib/domain/services/update_service.dart:769-818`（`_syncDailyPrices`）
- Modify: `lib/domain/services/update/market_day_refetcher.dart:282-363`（`attempt`、價格迴圈）
- Modify: `lib/domain/services/update/historical_price_syncer.dart:240-300`（Phase 0 迴圈）
- Modify: `tool/backfill.dart:909`、`:1031`
- Test: `test/domain/services/update_service_test.dart`、`test/domain/services/update/market_day_refetcher_test.dart`、`test/domain/services/update/historical_price_syncer_test.dart`、`test/tool/backfill_test.dart`、`test/tool/refetch_market_days_test.dart`（mock 回傳型別）

**Interfaces:**
- Consumes：Task 5／6 的回傳型別。
- Produces：
  - `_syncDailyPrices`：既有處理（資料日校正、`pricesUpdated`、候選股、缺市場警告）**之後**，對 `syncResult.basePrices` 每個市場：`rateLimited` → `ctx.rateLimitedAbort = true; recordError('$market 平盤價抓取失敗 (rate limit): ${status.error}', status.error)`；`shouldRecordError` → `recordError('$market 平盤價缺 ${status.missing} 列，漲跌暫存空值（${status.reason}）')`。
  - `MarketDayRefetcher.attempt` 的 `fetch` 改成 `Future<BasePriceStatus?> Function()`；價格迴圈傳 `(r) => r.basePrice`，其他資料集回 null。`attempt` 內 `await fetch()` 之後：先算定案數（既有迴圈）；再 `status?.rateLimited == true` → `summary.rateLimitError = status.error as RateLimitException`，**只在這一天沒進 `finalized` 時** `summary.stoppedAt ??= day`，回 `rateLimitAbort`；`status?.shouldRecordError == true` → `summary.errors.add('prices/$market ${ymd}: 平盤價缺 ${missing} 列（reason）')`，回 `ok`。
  - Phase 0：`result.basePrice.rateLimited` → warning「市場日回補平盤價限流，中止 phase 0」並 `break`；`shouldRecordError` → `missingBaseDays++`；迴圈後 `missingBaseDays > 0` 記 warning「市場日回補：N 天平盤價缺，漲跌暫存空值，由每輪摘要計數追蹤」。`added` 改讀 `result.rows`。
  - `tool/backfill.dart` 兩處傳 `withBasePrices: false`（不傳 ledger，既有）。

- [ ] **Step 1: 先修 mock（編譯綠）**：五個測試檔的 `IPriceRepository` mock／fake 改回傳 `MarketDayBackfillResult(rows: n, basePrice: BasePriceStatus.skipped)`。跑五檔確認基線綠。

- [ ] **Step 2: 寫失敗測試**

```dart
// update_service_test.dart
test('🚨 每日：平盤價缺 → 先照常處理回傳值（pricesUpdated、候選股）再 recordError、本輪 PARTIAL、不設 rateLimitedAbort', () async {
  stub syncAllPricesForDate → MarketSyncResult(count: 2, candidates: ['9901'], dataDate: day,
    basePrices: {MarketCode.twse: const BasePriceStatus(fetch: BasePriceFetch.failed, missing: 3, withheld: true, reason: '網路錯誤')});
  final result = await service.runDailyUpdate(...);
  expect(result.pricesUpdated, 2); expect(result.errors, contains(contains('平盤價缺 3 列'))); expect(result.hasRateLimitError, isFalse);
});
test('🚨 每日（Review Focus 4）：上櫃平盤價限流 → 照常處理回傳值後設 rateLimitedAbort；後續 API 步驟跳過', ...);
test('每日：fetched／N>0 不 withheld、failed／N=0 → 不記 errors', ...);
// market_day_refetcher_test.dart
test('🚨 價格 attempt：平盤價缺 → summary.errors 有一筆、這天不算 finalized、繼續下一天', ...);
test('🚨 價格 attempt：平盤價限流、N=0（已定案）→ finalized 計入、stoppedAt 不是這一天、回 rateLimitAbort', ...);
test('價格 attempt：平盤價限流、N>0 → stoppedAt 是這一天', ...);
// historical_price_syncer_test.dart
test('Phase 0：平盤價缺 → 不中止、不進 errors、記 warning 天數', ...);
test('Phase 0：平盤價限流 → 中止 phase 0（phase 1 照常）', ...);
// backfill_test.dart
test('🚨 tool/backfill 呼叫兩個 backfill 時 withBasePrices=false 且不傳 ledger', () { verify(() => priceRepo.backfillTwsePricesByDate(date: any(named: 'date'), targetSymbols: any(named: 'targetSymbols'), withBasePrices: false)).called(...); });
test('🚨 tool/backfill 的 FinMind 逐檔回補覆寫已有平盤價的列：值不變（驗證第 4 點第 6 條路徑，真 DB）', ...);
```

- [ ] **Step 3: 跑測試確認失敗**
- [ ] **Step 4: 實作四處呼叫端**
- [ ] **Step 5: 跑測試確認通過**

Run: `flutter test test/domain/services test/tool`

- [ ] **Step 6: 記錄進度**

---

### Task 8: 每輪摘要計數

**Files:**
- Modify: `lib/data/database/dao/price_dao.dart`
- Modify: `lib/domain/services/update_service.dart`（`UpdateResult`、`runOutcome:475-490`、`summary:1536-1543`、`calendarNotice` 計算處 `:411-415` 附近）
- Modify: `lib/app/background_update_service.dart:226-240`
- Test: `test/data/database/dao/price_dao_base_price_gap_test.dart`（新）、`test/domain/services/update_service_test.dart`、`test/app/background_update_notification_text_test.dart`

**Interfaces:**
- Produces：
  - `typedef BasePriceGap = ({int twseRows, int tpexRows, DateTime? earliest, DateTime? latest});`
  - `Future<BasePriceGap> PriceDaoMixin.getBasePriceGap()`：
    - 上市：`daily_price dp JOIN stock_master sm ... WHERE sm.market = 'TWSE' AND dp.close IS NOT NULL AND dp.price_change IS NULL`；
    - 上櫃：同上 `sm.market = 'TPEx'` 且 `EXISTS (SELECT 1 FROM dividend_distribution dd WHERE dd.symbol = dp.symbol AND dd.ex_date = dp.date)`；
    - `earliest`／`latest` 為兩組的 `MIN`／`MAX(dp.date)`。一次 `customSelect` 或兩次都可。
  - `UpdateResult.basePriceNotice`（`String?`，不算錯誤、不影響 `hasErrors`）：格式「上市 N 列、上櫃 M 列漲跌缺平盤價（最早 yyyy-MM-dd、最近 yyyy-MM-dd）」；兩個都 0 時 null。在算 `calendarNotice` 的同一處計算，`Stopwatch` 計時記 `AppLogger.debug`。
  - `runOutcome(List<String> errors, {required bool calendarStale, String? basePriceNotice})`：suffix 在「；交易日曆待更新」之後再接「；$basePriceNotice」。
  - `summary`：`calendarNotice`、`basePriceNotice` 各自接在後面。
  - 通知 `parts`：`result.basePriceNotice != null` → `isChinese ? '${twse+tpex} 筆漲跌缺平盤價' : '${n} price changes missing base price'`；為了拿到數字，`UpdateResult` 另存 `int basePriceGapRows`。

- [ ] **Step 1: 寫失敗測試**

```dart
// price_dao_base_price_gap_test.dart（真 DB）
test('上市：收盤非空、漲跌空值才數；收盤空不數；漲跌 0 不數', ...);
test('上櫃：只數配發表有這檔這天的列；只有 FinMind 價格的股票（無配發列）不數', ...);
test('轉市場（主檔上市、資料是上櫃）的文字標記列算在上市', ...);
test('earliest／latest 跨兩市場；全 0 時都 null', ...);
// update_service_test.dart
test('basePriceNotice：有缺時 summary、runOutcome 訊息尾巴都附；為 0 時不附', ...);
test('basePriceNotice 不進 errors、不影響 hasErrors', ...);
// 通知
test('通知內文有缺時附短句（zh／en）；為 0 時不附', ...);
```

- [ ] **Step 2: 跑測試確認失敗**
- [ ] **Step 3: 實作**
- [ ] **Step 4: 跑測試確認通過**；`flutter test test/core/l10n`（禁用詞守門）
- [ ] **Step 5: 記錄進度**

---

### Task 9: 讀取端：漲跌幅提醒、族群排行「今日」、大盤家數排除配發表

**Files:**
- Modify: `lib/domain/services/update_service.dart:1417-1456`（`_fetchAlertPrices`）
- Modify: `lib/domain/services/analysis/industry_ranking_service.dart:14-40`（class doc 與 `retOf`）
- Modify: `lib/data/database/dao/market_overview_dao.dart`（`getAdvanceDeclineCountsByMarket`、`getLimitUpDownCountsByMarket`、漲跌家數歷史查詢 `:570-590`、`getIndustrySummaryByMarket`）
- Test: `test/domain/services/update_service_test.dart`、`test/domain/services/analysis/industry_ranking_service_test.dart`、`test/data/database/dao/market_overview_dao_test.dart`

**Interfaces:**
- Produces：
  - `_fetchAlertPrices`：`result.priceChanges[symbol] = PriceCalculator.calculatePriceChange(priceHistories[symbol] ?? const [], latestPrices[symbol])`（非 null 才放）。
  - `IndustryRankingService.rank` 的 `retOf`：`RankingWindow.d1 => (h) => h == null || h.isEmpty ? null : PriceCalculator.calculatePriceChange(h, h.last)`。class doc 的「歷史不足視窗需求（21／6／2 筆）」改成「d20／d5 需 21／6 筆；d1 用漲跌價差，空值才退回前後收盤（那時需 2 筆）」。
  - **`RankingWindow.d1.minHistoryRows` 維持 2、不改**：它另供 `industry_ranking_provider.dart` 的 `_marketReturnPct` 取指數「第 2 筆前」的收盤，改成 1 會讓大盤同窗報酬變 0。成員那邊不再經它判斷。
  - 四個家數查詢：`advance`／`decline`／`unchanged`／`limit_up`／`limit_down`／`up_turnover`／`down_turnover` 的 `CASE` 條件加 `AND NOT EXISTS (SELECT 1 FROM dividend_distribution dd WHERE dd.symbol = dp.symbol AND dd.ex_date = dp.date)`；`getIndustrySummaryByMarket` 的 `avg_change_pct`、`COUNT(*)`、`HAVING` **不加**（全部列）。`readsFrom` 加 `dividendDistribution`。

- [ ] **Step 1: 寫失敗測試**

```dart
// update_service_test.dart
test('🚨 漲跌幅提醒用漲跌價差：除權息日 priceChange=−0.32、收盤 32.12 → −0.986%，不是前後收盤的 −5.4%', () {
  // getActiveAlerts 回一筆 9901（照本檔既有的提醒建構）；getLatestPricesBatch 回 entry(close 32.12, priceChange −0.32)；
  // getPriceHistoryBatch 回 [前一天 close 33.94, 今天 32.12]
  expect(result.priceChanges['9901'], closeTo(-0.986, 0.001));
});
test('漲跌價差空值時退回前後收盤（行為同 PriceCalculator）', ...);
// industry_ranking_service_test.dart（d1 group）
test('🚨 d1 用漲跌價差：成員只有 1 筆歷史但有 priceChange 也計入；除權息日不含股息', ...);
test('d1 的 priceChange 空值時退回前後收盤（1 筆歷史 → 不計入）', ...);
// 既有 `expect(RankingWindow.d1.minHistoryRows, 2)` 不動
// market_overview_dao_test.dart
test('🚨 四個家數查詢排除配發表有這檔這天的列（含 cash 0／shares 0 列）；產業平均與檔數門檻仍含它', () async {
  // 9901 TWSE 除息日 priceChange +0.5（配發表有列）、9902 TWSE +1（無）、9903 TWSE 0/0 列 priceChange −1
  // 漲跌家數：advance 1、decline 0、unchanged 0；漲跌停：不計 9901；歷史：up_turnover 只含 9902；
  // 產業（同產業、minStockCount 3）：stock_count 3、avg 含三檔、advance 1、decline 0
});
```

- [ ] **Step 2: 跑測試確認失敗**
- [ ] **Step 3: 實作**
- [ ] **Step 4: 跑測試確認通過**

Run: `flutter test test/domain/services/update_service_test.dart test/domain/services/analysis test/data/database/dao/market_overview_dao_test.dart test/presentation`（情緒、大盤總覽的 provider 測試是家數查詢的消費者）

- [ ] **Step 5: 記錄進度**

---

### Task 10: 修復工具 `tool/backfill_base_prices.dart`

**Files:**
- Create: `tool/backfill_base_prices.dart`
- Modify: `lib/data/database/dao/price_dao.dart`（`getTwseDaysWithoutBasePrice`）
- Test: `test/tool/backfill_base_prices_test.dart`（新）、`test/tool/tool_db_guard_test.dart`（新 tool 自動納入掃描）

**Interfaces:**
- Consumes：Task 2 的 `applyBasePrices`、`nullifyPriceChangeWithoutClose`；Task 3 的 `getOpeningBasePrices`、`getExRightResults`＋`tradingBasePrice`。
- Produces：
  - `Future<List<DateTime>> PriceDaoMixin.getTwseDaysWithoutBasePrice({DateTime? from, DateTime? to})`：`SELECT dp.date FROM daily_price dp JOIN stock_master sm ... WHERE sm.market='TWSE' [AND dp.date BETWEEN ? AND ?] GROUP BY dp.date HAVING MAX(dp.base_price IS NOT NULL) = 0 ORDER BY dp.date`（本地午夜 `DateTime`，舊→新）。
  - `class BasePriceBackfillArgs({required String dbPath, required String market /* 'TWSE'|'TPEx'|'both' */, DateTime? from, DateTime? to, required bool dryRun})`；`BasePriceBackfillArgs? parseBasePriceArgs(List<String> args, void Function(String) err)`：`--db`（預設同 `refetch_market_days.dart` 的 live 路徑）、`--market`（預設 both）、`--from`／`--to`（可選，yyyy-MM-dd）、`--dry-run`。
  - `Future<int> runBasePriceBackfill(List<String> args, {TwseClient? twse, TpexClient? tpex, AppDatabase? db, Duration? callDelay})`（測試注入；預設 `openToolDatabase` 與真 client、`ApiConfig.repairToolCallDelayMs`）；`main` 呼叫它後 `exit`。
  - 流程：
    1. 上市：`getTwseDaysWithoutBasePrice(from, to)` 逐日：等 `callDelay`（第一次不等）→ `getOpeningBasePrices(day)` → 一個 transaction 內 `applyBasePrices([... 只含該日已存在的上市列])` ＋ `nullifyPriceChangeWithoutClose(date: day, market: 'TWSE')` → 印一行「[base] TWSE yyyy-MM-dd: 更新 N 列」。`RateLimitException` → 印中止、回 4；`NetworkException`／`ApiException` → 記失敗、繼續下一天。
    2. 上櫃：價格表有上櫃列的每個月（`SELECT DISTINCT substr(date,1,7)`，可由 `getPriceCountsByDayAndMarket` 推或新查詢）：`getExRightResults(startDate: 月初, endDate: 月底)` → `applyBasePrices` 列為 `(symbol, exDate, tradingBasePrice)` 中 `tradingBasePrice != null` 者，**不依目前市場過濾**（8908 型）。
    3. 結尾印摘要（上市天數、更新列數、失敗天；上櫃月數、更新列數）與 `getBasePriceGap()`。失敗 > 0 回 1，否則 0。
  - `--dry-run`：只印上市要抓的天數、上櫃月數，不開網路。

- [ ] **Step 1: 寫失敗測試**

```dart
test('parseBasePriceArgs：預設 both、live 路徑；--from 晚於 --to 報錯', ...);
test('🚨 上市：只挑「沒有任何一列有平盤價」的日子；跑第二次 0 個請求（冪等、可中斷接續）', () async {
  // 真 DB：9/16 兩列無平盤價、9/17 一列有平盤價一列無 → 只抓 9/16
  verify(() => twse.getOpeningBasePrices(DateTime(2026, 9, 16))).called(1); verifyNever(() => twse.getOpeningBasePrices(DateTime(2026, 9, 17)));
  await run(); verifyNever(第二次任何 getOpeningBasePrices);
});
test('上市：套用後 X 列 0 → 收盤−平盤價；收盤 null 的列漲跌 → null；一般列值不變；ledger／其他欄不動', ...);
test('上市：某天網路錯誤 → 記失敗、繼續下一天、exit 1；限流 → exit 4、已做的天保留', ...);
test('🚨 上櫃：逐月抓 exDailyQ，套用到 (symbol, exDate) 已存在的列；主檔是上市的轉市場列也套（8908 型）', ...);
test('上櫃：tradingBasePrice null 的列不套；不存在的 (symbol, date) 不插入', ...);
test('--dry-run 不開網路', ...);
```

- [ ] **Step 2: 跑測試確認失敗**（編譯失敗）
- [ ] **Step 3: 實作 DAO 查詢與工具**（照 `tool/refetch_market_days.dart` 的結構：`openToolDatabase`、exit code 2 的分支、`finally` 關 client 與 DB）
- [ ] **Step 4: 跑測試確認通過**

Run: `flutter test test/tool/backfill_base_prices_test.dart test/tool/tool_db_guard_test.dart test/tool/tool_chain_pure_dart_test.dart`

- [ ] **Step 5: 記錄進度**

---

### Task 11: 副本彩排與整表比對（spec 驗證第 9 點）

**Files:**
- Create（scratchpad，不進 repo）：`base_price_compare.py`（整表比對）、`base_price_rehearsal.sh`
- 彩排副本：`~/tmp/daredevil-rehearsal/`（`cp` live DB 的 `.sqlite`；**開副本前確認 live 沒有 `-wal`、或用 `sqlite3 '.backup'`**）

- [ ] **Step 1: 建副本與修前快照**

```bash
R=~/tmp/daredevil-rehearsal; sqlite3 ~/Library/Containers/com.neo.afterclose/Data/Documents/afterclose.sqlite ".backup '$R/base_before.db'"; cp "$R/base_before.db" "$R/base_after.db"
```

- [ ] **Step 2: 先用新版程式開副本一次（補欄）**：`dart run tool/backfill_base_prices.dart --db $R/base_after.db --dry-run`，Expected：印出「上市 N 天、上櫃 17 個月」，N 約 336；DB 已有 `base_price` 欄。

- [ ] **Step 3: 跑工具（約 353 次請求、3 秒間隔，約 18 分鐘）**

Run: `dart run tool/backfill_base_prices.dart --db $R/base_after.db 2>&1 | tee $R/logs/base_rehearsal.log`
Expected: exit 0；摘要上市 336 天全部更新、失敗 0；結尾 `getBasePriceGap` 上市 0、上櫃 0。限流（exit 4）就等 10 分鐘再跑一次，條件會自己接續。

- [ ] **Step 4: 整表比對（python3 -I，兩個 DB 都 `mode=ro`）**

逐列比對 `price_change`，有變動的列分類：
- A：上市、不在「沒成交」類、原值 0 或 null → 新值＝`ROUND(close − base_price, 2)`；
- B：上櫃、配發表有這檔這天、原值 null → 新值非 null；
- C：上市、收盤 null、原值 0 → null（預期 873 列）；
- D：其他 → 逐筆印出，必須為 0 筆。
另外：上市一般日（原值非 0 非 null）新值必須等於原值（0 筆不同）；`market_day_fetch`、其他欄 `md5` 相同；`PRAGMA integrity_check` ok。
抽查：9901 → 用真代號：2330 2026-09-16 `price_change` 0.0；6225 2026-08-18 `(48.8−44.4)/44.4 ≈ +9.91%`；2947 2026-10-07 等於收盤 − exDailyQ 開始交易基準價。

- [ ] **Step 5: 官方家數比對（2026-10-07 上市）**

用修後副本跑 `getAdvanceDeclineCountsByMarket` 等價 SQL（排除 ETF：代號 `00` 開頭）；被排除的無比價檔數必須等於官方 3 檔；上漲、下跌、持平與官方 588／387／99 只求接近，差異逐檔列出原因。

- [ ] **Step 6: 記錄進度**（請求數、執行時間、A／B／C／D 筆數、抽查值、家數差異）。D 不為 0 或抽查不符 → 回對應 task 修，重跑 Step 3～5。

---

### Task 12: 文件、CHANGELOG、全套驗證、mutation、審查、經同意提交

**Files:**
- Modify: `CLAUDE.md`（「錯誤處理」）、`.claude/rules/update-pipeline.md`（`MarketDayRefetcher` 一節之後加「平盤價」小節）、`CHANGELOG.md`（Unreleased → Fixed）
- Modify: `docs/plans/2026-10-07-market-heatmap-design.md`（若實作與 10/27 同步的敘述有出入才改）

- [ ] **Step 1: 文件**

- CLAUDE.md「錯誤處理」加一行：「例外：市場日價格寫入的平盤價抓取（`PriceRepository._fetchTwseBasePrices`／`_fetchTpexBasePrices`）把限流與失敗放進回傳的 `BasePriceStatus`、不拋——價格已寫入，拋出會讓呼叫端丟掉整個回傳值」。用 claude-md-management skill 改。
- update-pipeline.md 加「平盤價（2026-10）」：`base_price` 來源、三個函式同 transaction、狀態表摘要、呼叫端表、每輪摘要計數、修復工具一行、Phase 0 每天 2 個請求。
- CHANGELOG `### Fixed`：「除權息、減資恢復買賣、新股首日等不比價日的漲跌：改用交易所公告的平盤價計算（上市股價升降幅度、上櫃除權除息結果），不再顯示 0% 或把股息算成跌幅；大盤家數照官方口徑排除除權息股；漲跌幅提醒與族群排行「今日」改用同一個漲跌。既有資料用 `tool/backfill_base_prices.dart` 修一次」。

- [ ] **Step 2: 全套**

```bash
ps -axo pid=,ppid=,etime=,comm= | grep -E '/(dart|flutter)$'   # 必須空
flutter analyze                                                 # 0 issues
flutter test                                                    # 全綠
dart compile kernel tool/daily_update.dart -o build/daily_update.dill   # 純 Dart 終驗
```

- [ ] **Step 3: mutation（spec 驗證第 8 點，照風險分級：本項是全 App 的漲跌來源，照嚴格）**

在 scratchpad 副本逐一拔，每拔一次跑直接測試、存活者跑全部消費者：
- 第 2 節：第 0 條（拿掉收盤 null 判斷）、第 1 條（`ROUND` 改不取整、`COALESCE` 改只用 excluded）、第 2 條（present 改用 absent 分支）、第 3 條（`old.close IS excluded.close` 改恆真／恆假）、insert 分支（Dart 預算改直接用 companion 原值）。
- 第 3 節：三個 `needs` 函式各改條件（`== 0` → `!= null`；`noComparison` 拔掉）；N 判斷（`countMissingBasePrice` 回 0）；`withheld` 的每個分支（`fromDailyEndpoint` 反相、`missing > 0` 改 `>= 0`）；例外一（交集為空的判斷拔掉）。
- 呼叫端：`_syncDailyPrices` 不設 `rateLimitedAbort`；`attempt` 的 `stoppedAt` 條件反相；Phase 0 不 `break`。
- 讀取端：家數查詢的 `NOT EXISTS` 拔掉；產業平均誤加 `NOT EXISTS`。
每條記錄「紅在哪個測試」；存活的補測試。

- [ ] **Step 4: 審查**：`pr-review-toolkit:code-reviewer`（opus），給整段 diff、spec、本計畫、帳本的 `Ruling:`；Critical／Important 當段修完（每條修法 RED→GREEN＋全套綠）再送窄範圍複審；Minor 記帳本。

- [ ] **Step 5: 經使用者同意提交**（一個 commit，`fix:` 前綴；訊息寫改了什麼、為什麼；不在 09:00–13:30）。

- [ ] **Step 6: 記錄進度**

---

## 提交後（需使用者同意，不在本計畫自動執行）

照 spec 第 4 節「部署順序」：
1. 提交後 post-commit 重編 CLI；從 launchd 日誌的 `[build=<sha>]` 確認已換新。
2. GUI 重編並重開。
3. 兩步都完成後，**使用者同意**才對 live DB 跑 `dart run tool/backfill_base_prices.dart`（預設路徑）；跑前 `.backup` 一份；跑完在 live 的副本上重做 Task 11 Step 4 的整表比對（spec 驗證第 10 點）。
4. 之後幾輪觀察每輪摘要：`basePriceNotice` 應為 0；除權息日（例：下一個有上市除權息的交易日）15:30 後確認那檔的 `price_change`＝收盤 − `base_price`、熱力圖 spec 驗證「除權息日」一項可做。

## 實作後的修正

### 彩排數字（Task 11，2026-10-27 對 live 副本，資料到 10/27）

- `tool/backfill_base_prices.dart --db <副本>`：exit 0；354 次請求（上市 337 天、上櫃 17 個月）、間隔 3 秒、26.5 分鐘、失敗 0；
  上市更新 403,622 列、上櫃 1,272 列；結尾缺平盤價計數上市 0、上櫃 0。
- 整表比對：integrity ok；`market_day_fetch` 與開高低收量不變；列數 703,618 不變；變動只有三類：上市不比價日 2,773 列、
  上櫃除權息日 1,258 列、上市沒成交 0→null 875 列；其他變動 0 列；上市一般日 399,865 列「收盤 − 平盤價」＝原漲跌、零誤差；
  每個上市交易日有平盤價的列數÷列數最低 0.9983。抽查 2330 9/16 0.000%、6225 8/18 +9.910%、2947 10/7 −1.786%。
- 官方家數 2026-10-07（上市、排除 00 開頭，套 DAO 同一條「配發表有這檔這天就排除」）：我們上漲 591／下跌 388／持平 100／未成交 5、
  被排除 3 檔 vs 官方「股票」588／387／99／5／無比價 3。被排除的正好是官方無比價的 2890、6108、6947（配發表有列；它們的
  `price_change` 依設計用平盤價算出，只是不計家數）；逐檔對官方 MI_INDEX 1,087 檔方向全部一致；母體多 4 檔存託憑證（官方
  「股票」口徑不含：上漲 3、持平 1）與 8908（轉上市股的上櫃列，下跌）。四個家數全部對平，沒有資料錯誤。
  （最終審查 M2：第一版紀錄沒套 DAO 的排除條件、寫成 592／390／100／無比價 0，已改。）
- 開 DB 就會跑 `beforeOpen` 補欄：`--dry-run` 之後副本的 schema 已變，「沒動過」要看資料比對，不能 `cmp` 檔案。

### 帳本的 Ruling

- Task 2：upsert 逐筆 `DoUpdate.withExcluded`（計畫寫先分兩組；drift batch 保順序，同批重複鍵以前一筆當 old）；CASE 用型別化的
  `CaseWhenExpression`／`coalesce`／`FunctionCallExpression`（計畫寫 `CustomExpression` 寫 SQL；欄名由編譯器檢查）。
- Task 5：「清單整個對不上」的覆蓋判斷用 coverage 集合——上市＝實際寫入的全部代號（TWT84U 是全市場清單）、上櫃＝needs
  （exDailyQ 只列除權息列）；用 needs 時上市只有一個 X 列會把「清單不全」誤判成「整個對不上」。STOCK_DAY 月資料的覆寫測試放真 DB
  的 `price_repository_base_price_twse_test.dart`；transaction 維持 `transaction<void>`、狀態用 late 變數帶出。
- Task 6：例外一的 reason 共用「清單整個對不上（N 檔沒有一檔在清單上，清單 M 檔）」，不用計畫寫的上櫃專屬文案。
- Task 7：`MarketDayRefetcher.attempt` 的 fetch 型別改 `Future<dynamic> Function()`＋`is MarketDayBackfillResult`（不改七個呼叫點）；
  `tool/backfill.dart` FinMind「覆寫已有平盤價的列值不變」改成原始碼掃描測試（companion 不帶 priceChange／basePrice）；每日路徑
  「限流後後續步驟跳過」的訊號用 `getStocksByMarket`（計畫寫的 `getSymbolsWithSufficientData` 另有不受閘門的呼叫者）。
- Task 10：上櫃逐月的月份清單加 DAO `getTpexMonthsWithPrices`；「做過沒」從「沒有任何一列有平盤價」改成「有平盤價的列不到
  `ApiConfig.basePriceBackfillDoneRatio`（50%）」（spec 第 4 節同步；轉市場列被上櫃那輪寫了平盤價會讓整天漏掉）；上櫃當月的
  exDailyQ `endDate` 夾到今天。
- 流程：審查進行中只寫下一段的測試、實作等審查回來（Task 2、Task 5 各違反一次，結果都 0 Critical／0 Important）。

### 審查的 deferred Minor（各段 0 Critical；Important 都已當段修完）

- 註解／文件：`withheld`「會被 5.5 重抓」說太滿、`shouldRecordError` 補「Phase 0 記 warning 不進 errors」、「一列都對不上」三份文字對齊
  coverage 定義；`_notExDividend` 常數插在 mixin doc 與 mixin 之間，說明補「15:30 那輪在 6.6 之前照漲跌計入」；`update_service.dart`
  步驟 5.5 註解「其餘皆 recordError」要加新例外；`runOutcome` doc 沒提新 suffix；`RefetchSummary.stoppedAt` doc 兩段有出入；
  `IPriceRepository.syncAllPricesForDate` doc 沒寫「平盤價錯誤不拋」；`api_config` 的「每一天 2 個請求」精確是「價格非空的每一天」；
  `insertPrices` doc「有帶」→「帶非 null」；`trading_warning_dao.dart` 的 insertOrReplace 註解過時；`exright_result.dart`「依升降單位取整」
  只有 TWSE 旁證；spec 實作注意「沒帶的欄位不再被清成空值」只對 base_price／price_change 成立。
- 程式：`market_overview_dao` 的 `readsFrom` 多加了 3 處不讀配發表的查詢；`PriceCalculator.ret1d` 已無呼叫者；`BasePriceStatus` const
  建構子加 assert 擋不合法組合（rateLimited 不帶 error、withheld 搭 missing 0）；`mergeBasePrices` 的 `zeroToNull` 可從路徑推導；
  缺平盤價計數的 fail-safe 失敗時摘要無訊號；修復工具 DB 錯誤後仍繼續打後面幾天的 API、`--dry-run` 仍開 DB、`ownsClients` 命名、
  每天 log 的「沒成交改空值 N 列」只數 nullify 那步（`applyBasePrices` 的 CASE 已先改掉大多數）。
- 測試缺口：`nullifyPriceChangeWithoutClose` 的 `IS NOT NULL`；TWT84U 快取鍵帶日期；`twsePriceLimits` 常數值；`noComparison` 尾端空白
  形式；MI_INDEX needs 補非 0 數字列；`skipped`／`notNeeded` 常數斷言；「上市回空、上櫃有資料 → 不打 TWT84U」；上櫃 coverage＝needs
  與＝written 沒測試能分辨；`notNeeded` 不等 delay；Phase 0 迴圈後 warning 與限流 warning 沒帶 N；refetcher「N=0 已定案」缺「回報了還
  不算定案」對照；`--market TWSE` 沒 `verifyNever(tpex)`；update_run 訊息 500 字截斷含 suffix；`update_service_test` setUp 預設 stub
  `getBasePriceGap`。
- 已知限制（不改）：漲跌幅提醒會用過期漲跌（停止買賣或當天沒同步到時是最後一個交易日的）；TWT84U 任一列解析不了整批拒收 →
  那天在重抓窗內 withheld（spec 已接受）；兩市場同輪都限流會記兩筆 errors；轉上市股掛牌前的 FinMind 空值列會算進上市缺平盤價計數、
  修復工具修不掉（最終審查 M1；已寫進 spec 已知限制與 `update-pipeline.md`，發生時清掛牌前的列）。
- 順帶發現（spec 層，信心 60，未處理）：每日路徑只看「請求日」判定案、不看資料日——D-1 已被 MI_INDEX 記定案後，同一天再跑每日
  而 `STOCK_DAY_ALL` 仍停在 D-1 時，不在清單上的 0 列會被 zeroToNull 改成 null、蓋掉真平盤 0，之後不再重抓。

### 最終審查（Task 12 Step 4）

- 整段審查（opus，fresh context）：0 Critical／0 Important／4 Minor——M1 轉上市股轉市場前的空值列會算進上市缺平盤價計數、修復工具
  修不掉（寫成已知限制，見上）；M2 本節官方家數的第一版紀錄沒套 DAO 的排除條件（已改）；M3 六處文件句子說錯（已改）；M4 計數查詢
  的 isolate 內計時沒留數字——Dart VM 在副本量：第一次 1,435 ms（含開 DB），之後 42–44 ms；CLI 的 `AppLogger.debug` 會印
  「缺平盤價計數 Nms」，之後幾輪可直接讀。審查者自驗：改動的 29 個測試檔 539 綠、全套 6160 綠、analyze 0、兩支工具 kernel exit 0、
  Review Focus 5 條各突變一次全紅。
- 修法複審（opus）：0 Critical／0 Important／5 Minor，全是措辭（`stoppedAt` 的「下一天」是 `days` 新→舊的下一個、守門只管寫在哪裡、
  CHANGELOG 漏上漲／下跌成交值、計數條件補轉市場空值列的例外、本節補 M3），已一併改。
- **M3 注意**：本計畫 Task 12 Step 1 寫的理由「價格已寫入，拋出會讓呼叫端丟掉整個回傳值」是錯的——平盤價在 transaction 之前抓，拋出
  時價格也還沒寫入。三份文件與程式碼註解都已改成「價格已抓到、要和平盤價寫進同一個 transaction；在這裡拋出價格也寫不進去、呼叫端
  也拿不到回傳值」。照計畫抄時用新句子，Step 1 原文不改。
