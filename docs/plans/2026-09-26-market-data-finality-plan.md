# 盤後資料定案與重抓 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 讓價格、法人、當沖、融資券、外資持股的每日資料一直重抓到「隔天以後抓過一次」為止；上櫃歷史價格改為官方口徑；上市估值用回應中的日期；並提供一次性修復工具。

**Architecture:** 每輪更新建立一個 `MarketDayFetchLedger`（抓取時間＝本輪開始的台北時間）。它一路傳進各 repository，由 repository 在寫入資料的同一個 transaction 裡回報「實際寫入的市場、資料日、列數」。ledger 依逐組門檻決定是否寫入新表 `market_day_fetch`。「是否定案」由純函式依 `fetched_at` 與資料日算出，不存旗標。新的 `MarketDayRefetcher` 在每輪更新時重抓追蹤起始日以後、窗內未定案的日子；修復 CLI 直接重用它。

**Tech Stack:** Flutter／Dart 3.10、Drift（SQLite）、Dio、mocktail、flutter_test。

**Spec:** `docs/plans/2026-09-26-market-data-finality-design.md`

## Global Constraints

- **不 bump `appSchemaFingerprint`**。新表用 `Migrator(this).createTable(...)` 在 `beforeOpen` 補建（比照 `_ensureQuarterlyReportSchema`）。
- **tool 鏈純 Dart**：`lib/` 新檔不得 import flutter／easy_localization／flutter plugins。每個 stage 結束跑 `dart compile kernel tool/daily_update.dart -o /tmp/du.dill`，並跑 `flutter test test/tool/tool_chain_pure_dart_test.dart`。
- **例外慣例**：repository 層 `RateLimitException`／`NetworkException` 一律 rethrow，其餘包成 `DatabaseException`。
- **閾值集中**：新常數放 `lib/core/constants/api_config.dart`。
- **追蹤資料集**與記錄門檻比例（spec §4.2、§4.4），全部是「該市場在市股票數 × 比例」，比例皆為 0.5：
  - 價格：`ApiConfig.historicalMarketDayMinCoverageRatio`
  - 融資券：`ApiConfig.tradingBackfillMinCoverageRatio`
  - 外資持股：`ApiConfig.foreignShareholdingMinCoverageRatio`
  - 上市當沖、上櫃當沖、法人（兩市場）：新訂 `ApiConfig.finalityNewDatasetMinCoverageRatio = 0.5`
- **定案規則**：`fetched_at` 的台北日期 > 資料日。
- **重抓上限與窗口**：`M = ApiConfig.finalityRefetchMaxDaysPerRun = 10`；窗口 `ApiConfig.tradingBackfillLookbackDays = 40` 個**日曆天**；追蹤起始日 key 為 `finality_tracking_since`（寫入 `app_settings`，已存在不覆寫）。
- **註解與文件**：繁體中文，不寫 process noise，不寫本機路徑、不引用私人筆記。
- **實際 DB**（使用者的 app DB）只能唯讀檢查。任何寫入先在副本彩排，並取得使用者明確同意（Task 15）。
- **Commit 由使用者決定**：implementer 不 commit。每個 stage（A：Task 1–6、B：Task 7–11、C：Task 12–13、D：Task 14）結束時，controller 先跑全套測試、`flutter analyze`，再送 code review；審查通過後停下，請使用者說「提交」。commit message 用 Conventional Commits、純文字、不加 Co-Authored-By。
- 測試指令：單檔 `flutter test <path>`；全套 `flutter test`；靜態檢查 `flutter analyze`（info 也擋）。每寫完一個測試檔就先 `flutter analyze <檔案>`，不要把 info 留到 stage 閘門。
- **mocktail 具名參數**（2026-09-26 計畫審查實測）：`when`／`verify` 裡沒寫的具名參數，會被當成「期望該參數的預設值（通常是 null）」。實際呼叫若帶了非 null 的 `ledger`、`date`，stub 對不上、回 null 而拋 `TypeError`，verify 也會失敗。所以每個 Task 讓呼叫端開始傳新參數時，**同一個 Task 內**要把相關既有測試的 stub／verify 補上 `ledger: any(named: 'ledger')` 等。`ledger` 是 nullable 型別，`any` 不需要 `registerFallbackValue`；非 nullable 的必填參數（例如 `refetchPending(ledger:)`）才需要。
- **`MockAppDatabase` 的 transaction**：程式一律寫 `_db.transaction<void>(() async {...})`（不寫成推斷型別），既有測試的 stub 是 `when(() => mockDb.transaction<void>(any())).thenAnswer((inv) async { await (inv.positionalArguments[0] as Future<void> Function())(); });`（見 `trading_repository_backfill_test.dart`）。用 `MockAppDatabase` 的測試檔要補這個 stub，以及新呼叫到的 DB 方法 stub。
- **ledger 與 repository 必須共用同一個 `AppDatabase` 實例**：ledger 在 repository 的 transaction 內寫狀態表，Drift 的 transaction 綁在該實例的 zone 上；換成另一個實例會變成 transaction 外的獨立寫入。這點要寫進 `MarketDayFetchLedger` 的類別說明。

## Review Focus

1. **裝置時區不是台北**：`fetched_at` 存的是 `AppClock.now()`（台北牆鐘），定案判斷只比年月日欄位，不做時區換算。Task 1 的純函式測試釘住「只比 y/m/d」。
2. **常駐 App 跨午夜仍有前一輪快取**：每輪開始會清 client 快取，而且 `fetched_at` 取本輪開始時間。Task 11 測試清快取確實被呼叫、ledger 的時間等於本輪開始的時鐘值。
3. **轉市場、已下市股票遇到法人全 0 刪列**：只刪「回應中明確列出且全 0」的代號，其他列不動。Task 8 測試回應裡沒有的代號（含下市）舊列保留。
4. **颱風停市等日曆漏標日**：端點回 0 列，不記狀態，每輪重試但受 `M` 限制；滑出 40 日曆天窗後只記 warning（筆數與前 10 筆），不進 errors。Task 10 測試沒狀態的日子下輪仍是候選、滑出窗外只進 `staleOutOfWindow`。
5. **單一市場抓取失敗**：另一市場照常寫入與記錄，失敗那邊不記。Task 7（價格）與 Task 8（法人）各有測試。

---

## Task 0：量測閘門（不改程式）

spec §4.4、§4.5 有兩個推論要在寫程式前驗證。任一項不成立就停下、回報使用者，不進 Task 1。

**Files:** 無（腳本放在 session scratchpad，不進 repo）

- [ ] **Step 1：取最新 DB 快照（唯讀）**

WAL 不存在時用 immutable 模式。在 scratchpad 目錄執行，副本用相對路徑：

```bash
DB="<app DB 路徑>"   # 容器內 afterclose.sqlite
sqlite3 "file:$DB?immutable=1" "vacuum into 'finality_snap.db'"
sqlite3 finality_snap.db "pragma integrity_check;"
```

Expected：`ok`

- [ ] **Step 2：量各組最近 30 個交易日的列數 vs 門檻**

```bash
sqlite3 finality_snap.db <<'SQL'
.mode column
WITH stocks AS (SELECT market, COUNT(*) n FROM stock_master WHERE is_active=1 GROUP BY market),
days AS (SELECT DISTINCT substr(date,1,10) d FROM daily_price ORDER BY d DESC LIMIT 30),
per AS (
  SELECT 'prices' ds, m.market, substr(p.date,1,10) d, COUNT(*) c FROM daily_price p JOIN stock_master m USING(symbol) WHERE substr(p.date,1,10) IN (SELECT d FROM days) GROUP BY 1,2,3
  UNION ALL SELECT 'institutional', m.market, substr(t.date,1,10), COUNT(*) FROM daily_institutional t JOIN stock_master m USING(symbol) WHERE substr(t.date,1,10) IN (SELECT d FROM days) GROUP BY 1,2,3
  UNION ALL SELECT 'dayTrading', m.market, substr(t.date,1,10), COUNT(*) FROM day_trading t JOIN stock_master m USING(symbol) WHERE substr(t.date,1,10) IN (SELECT d FROM days) GROUP BY 1,2,3
  UNION ALL SELECT 'margin', m.market, substr(t.date,1,10), COUNT(*) FROM margin_trading t JOIN stock_master m USING(symbol) WHERE substr(t.date,1,10) IN (SELECT d FROM days) GROUP BY 1,2,3
  UNION ALL SELECT 'foreignShareholding', m.market, substr(t.date,1,10), COUNT(*) FROM shareholding t JOIN stock_master m USING(symbol) WHERE m.market='TWSE' AND substr(t.date,1,10) IN (SELECT d FROM days) GROUP BY 1,2,3
)
SELECT ds, per.market, MIN(c) min_rows, MAX(c) max_rows, CAST(stocks.n*0.5+0.999 AS INT) need
FROM per JOIN stocks USING(market) GROUP BY ds, per.market ORDER BY ds, per.market;
SQL
```

Expected：九組（價格、法人、當沖、融資券各兩市場；外資持股只有上市）的 `min_rows` 在健康日都 ≥ `need`。上櫃當沖 8/21 前覆蓋低，屬已知情況（spec 非目標），只看 8/21 以後。若有健康日低於 `need`，停下回報，連同該組實際列數分佈。

- [ ] **Step 3：驗證法人「初值有列、定案不發列」幾乎不會發生**

快照裡 7/16–8/19 的法人是初值。拿兩個有鉅額交易的日子比對官方定案值：

```python
# finality_inst_check.py（在 scratchpad 執行：python3 finality_inst_check.py）
import json, sqlite3, time, urllib.request
db = sqlite3.connect('finality_snap.db')
UA = {'User-Agent': 'Mozilla/5.0'}
def get(url):
    time.sleep(3.5)
    return json.load(urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=60))
def num(s):
    try: return float(str(s).replace(',', ''))
    except Exception: return None
for d in ['20260717', '20260805']:
    iso = f'{d[:4]}-{d[4:6]}-{d[6:]}'
    t86 = get(f'https://www.twse.com.tw/rwd/zh/fund/T86?date={d}&selectType=ALLBUT0999&response=json')
    t = t86['tables'][0] if 'tables' in t86 else t86
    f = t['fields']
    fi = [i for i, x in enumerate(f) if '外陸資買賣超股數' in x][0]
    ti = f.index('投信買賣超股數')
    tot = [i for i, x in enumerate(f) if '三大法人買賣超' in x][0]
    final = {r[0].strip(): (num(r[fi]), num(r[ti]), num(r[tot])) for r in t['data']}
    roc = f'{int(d[:4]) - 1911}/{d[4:6]}/{d[6:]}'
    tp = get(f'https://www.tpex.org.tw/web/stock/3insti/daily_trade/3itrade_hedge_result.php?l=zh-tw&d={roc}&t=D&o=json')
    for r in tp['tables'][0]['data']:
        final[r[0].strip()] = (num(r[4]), num(r[13]), num(r[23]))
    rows = db.execute("select symbol from daily_institutional where substr(date,1,10)=?", (iso,)).fetchall()
    absent = [s for (s,) in rows if s not in final]
    zero = [s for (s,) in rows if s in final and final[s] == (0.0, 0.0, 0.0)]
    print(iso, 'db rows', len(rows), 'absent in final', len(absent), absent[:10], 'final all-zero but db has row', len(zero), zero[:10])
```

Expected：`absent in final` 為 0（或只有已下市、轉市場股票，逐一說明）。`final all-zero but db has row` 可以大於 0，這正是 Task 8 刪列規則要處理的情況。若 `absent` 有在市股票，停下回報：spec 的「幾乎不會發生」不成立，需要改設計。

- [ ] **Step 4：把量測結果寫進 ledger（`.superpowers/sdd/<plan>/progress.md`）**，一行一組數字，當作後續 Task 的依據。

---

## Task 1：定案判定、狀態表、追蹤起始日

**Files:**
- Create: `lib/core/constants/market_dataset.dart`
- Create: `lib/core/utils/market_day_finality.dart`
- Create: `lib/data/database/dao/market_day_fetch_dao.dart`
- Modify: `lib/core/constants/api_config.dart`（新增常數，放在 `tradingBackfill*` 區段之後）
- Modify: `lib/data/database/tables/market_data_tables.dart`（新增 `MarketDayFetch` 表，放檔尾）
- Modify: `lib/data/database/app_database.dart`（tables 清單、`with` mixin、`beforeOpen` 補建、fingerprint 說明補一句例外）
- Modify: `lib/data/database/dao/user_dao.dart`（新增 `getOrInitSetting`）
- Test: `test/core/utils/market_day_finality_test.dart`
- Test: `test/data/database/market_day_fetch_dao_test.dart`
- Test: `test/data/database/market_day_fetch_schema_test.dart`

**Interfaces:**
- Produces:
  - `enum MarketDataset { prices, institutional, dayTrading, margin, foreignShareholding }`，含 `String code` 與 `double minCoverageRatio`
  - `typedef FinalityGroup = ({MarketDataset dataset, String market});`、`const List<FinalityGroup> finalityGroups`（9 組）
  - `bool isFetchFinal({required DateTime dataDate, required DateTime fetchedAtTaipei})`
  - `AppDatabase.upsertMarketDayFetch({required String dataset, required String market, required DateTime date, required DateTime fetchedAt, required int rowCount})`
  - `AppDatabase.getMarketDayFetch(String dataset, String market, DateTime date) → Future<MarketDayFetchEntry?>`
  - `AppDatabase.getMarketDayFetchesSince(DateTime since) → Future<List<MarketDayFetchEntry>>`
  - `AppDatabase.isMarketDayFinal({required MarketDataset dataset, required String market, required DateTime date}) → Future<bool>`
  - `AppDatabase.getOrInitSetting(String key, String initialValue) → Future<String>`
  - `ApiConfig.finalityNewDatasetMinCoverageRatio`、`ApiConfig.finalityRefetchMaxDaysPerRun`、`ApiConfig.finalityRefetchCallDelayMs`

- [ ] **Step 1：寫純函式的失敗測試**

`test/core/utils/market_day_finality_test.dart`：

```dart
// 定案規則：抓取時間的台北日期 > 資料日（spec §4.1）
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/utils/market_day_finality.dart';

void main() {
  final day = DateTime(2026, 9, 24);

  test('同日 21:30 抓的不算定案（鉅額交易可能還沒併入）', () {
    expect(
      isFetchFinal(dataDate: day, fetchedAtTaipei: DateTime(2026, 9, 24, 21, 30)),
      isFalse,
    );
  });

  test('同日 23:59:59 仍不算定案', () {
    expect(
      isFetchFinal(
        dataDate: day,
        fetchedAtTaipei: DateTime(2026, 9, 24, 23, 59, 59),
      ),
      isFalse,
    );
  });

  test('隔日 00:00 起算定案', () {
    expect(
      isFetchFinal(dataDate: day, fetchedAtTaipei: DateTime(2026, 9, 25)),
      isTrue,
    );
  });

  test('資料日帶時間成分時只看年月日', () {
    expect(
      isFetchFinal(
        dataDate: DateTime(2026, 9, 24, 8),
        fetchedAtTaipei: DateTime(2026, 9, 25, 0, 1),
      ),
      isTrue,
    );
  });

  test('抓取早於資料日（時鐘異常）不算定案', () {
    expect(
      isFetchFinal(dataDate: day, fetchedAtTaipei: DateTime(2026, 9, 23, 23)),
      isFalse,
    );
  });

  test('只比年月日欄位，不做時區換算（UTC 旗標的同一牆鐘值結果相同）', () {
    expect(
      isFetchFinal(
        dataDate: DateTime.utc(2026, 9, 24),
        fetchedAtTaipei: DateTime(2026, 9, 25, 0, 30),
      ),
      isTrue,
    );
    expect(
      isFetchFinal(
        dataDate: DateTime(2026, 9, 24),
        fetchedAtTaipei: DateTime.utc(2026, 9, 24, 23, 30),
      ),
      isFalse,
    );
  });
}
```

- [ ] **Step 2：跑測試，確認失敗**

Run: `flutter test test/core/utils/market_day_finality_test.dart`
Expected：編譯失敗，`market_day_finality.dart` 不存在。

- [ ] **Step 3：實作純函式與常數**

`lib/core/utils/market_day_finality.dart`：

```dart
/// 盤後資料是否已定案（設計見 docs/plans/2026-09-26-market-data-finality-design.md §4.1）
///
/// 交易所在收盤後一段時間內會更新當日數字（例如 17:30–18:00 才併入鉅額
/// 交易），而「隔天以後才抓到的值」經稽核全面與官方一致，所以只有抓取
/// 日期晚於資料日才算定案。
///
/// [fetchedAtTaipei] 是台北牆鐘時間（`AppClock.now()`）。這裡刻意只比
/// 年月日欄位、不做時區換算：兩個值都是以台北日曆記錄的，換算反而會在
/// 裝置時區不是台北時算錯。
bool isFetchFinal({
  required DateTime dataDate,
  required DateTime fetchedAtTaipei,
}) {
  final data = DateTime.utc(dataDate.year, dataDate.month, dataDate.day);
  final fetched = DateTime.utc(
    fetchedAtTaipei.year,
    fetchedAtTaipei.month,
    fetchedAtTaipei.day,
  );
  return fetched.isAfter(data);
}
```

`lib/core/constants/api_config.dart`，加在 `tradingBackfillMaxDaysPerRun` 所在區段之後：

```dart
  // ==================================================
  // 盤後資料定案（2026-09-26）
  //
  // 設計見 docs/plans/2026-09-26-market-data-finality-design.md。
  // ==================================================

  /// 沒有既有回補門檻可沿用的資料集（上市／上櫃當沖、法人兩市場），其定案
  /// 狀態的記錄門檻比例（相對該市場在市股票數）
  static const double finalityNewDatasetMinCoverageRatio = 0.5;

  /// 未定案日重抓：每組（資料集, 市場）每輪最多幾天
  static const int finalityRefetchMaxDaysPerRun = 10;

  /// 未定案日重抓的呼叫間隔（毫秒）
  static const int finalityRefetchCallDelayMs = 1000;
```

`lib/core/constants/market_dataset.dart`：

```dart
import 'package:daredevil/core/constants/api_config.dart';
import 'package:daredevil/core/constants/market_codes.dart';

/// 追蹤「是否已定案」的盤後資料集
///
/// [minCoverageRatio]：一次抓取寫入的列數達到「該市場在市股票數 × 比例」
/// 才記錄抓取狀態，未達視為尚未發布或抓取不完整。
enum MarketDataset {
  prices('prices', ApiConfig.historicalMarketDayMinCoverageRatio),
  institutional(
    'institutional',
    ApiConfig.finalityNewDatasetMinCoverageRatio,
  ),
  dayTrading('dayTrading', ApiConfig.finalityNewDatasetMinCoverageRatio),
  margin('margin', ApiConfig.tradingBackfillMinCoverageRatio),
  foreignShareholding(
    'foreignShareholding',
    ApiConfig.foreignShareholdingMinCoverageRatio,
  );

  const MarketDataset(this.code, this.minCoverageRatio);

  /// 寫入 `market_day_fetch.dataset` 的值（不可改名：既有資料以此為鍵）
  final String code;
  final double minCoverageRatio;
}

/// 一組追蹤對象（資料集 × 市場）
typedef FinalityGroup = ({MarketDataset dataset, String market});

/// 全部 9 組。外資持股只有上市（上櫃走 FinMind 逐檔，不在追蹤範圍）
const List<FinalityGroup> finalityGroups = [
  (dataset: MarketDataset.prices, market: MarketCode.twse),
  (dataset: MarketDataset.prices, market: MarketCode.tpex),
  (dataset: MarketDataset.institutional, market: MarketCode.twse),
  (dataset: MarketDataset.institutional, market: MarketCode.tpex),
  (dataset: MarketDataset.dayTrading, market: MarketCode.twse),
  (dataset: MarketDataset.dayTrading, market: MarketCode.tpex),
  (dataset: MarketDataset.margin, market: MarketCode.twse),
  (dataset: MarketDataset.margin, market: MarketCode.tpex),
  (dataset: MarketDataset.foreignShareholding, market: MarketCode.twse),
];
```

- [ ] **Step 4：跑測試，確認通過**

Run: `flutter test test/core/utils/market_day_finality_test.dart`
Expected：6 個測試全部 PASS。

- [ ] **Step 5：寫 DAO 與 schema 的失敗測試**

`test/data/database/market_day_fetch_dao_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/constants/market_codes.dart';
import 'package:daredevil/core/constants/market_dataset.dart';
import 'package:daredevil/data/database/app_database.dart';

void main() {
  late AppDatabase db;
  final day = DateTime(2026, 9, 24);

  setUp(() => db = AppDatabase.forTesting());
  tearDown(() => db.close());

  Future<void> record(DateTime fetchedAt, {int rows = 1200}) =>
      db.upsertMarketDayFetch(
        dataset: MarketDataset.prices.code,
        market: MarketCode.twse,
        date: day,
        fetchedAt: fetchedAt,
        rowCount: rows,
      );

  test('沒有狀態列時不算定案', () async {
    expect(
      await db.isMarketDayFinal(
        dataset: MarketDataset.prices,
        market: MarketCode.twse,
        date: day,
      ),
      isFalse,
    );
  });

  test('隔天抓的算定案，同日抓的不算', () async {
    await record(DateTime(2026, 9, 24, 21, 30));
    expect(
      await db.isMarketDayFinal(
        dataset: MarketDataset.prices,
        market: MarketCode.twse,
        date: day,
      ),
      isFalse,
    );
    await record(DateTime(2026, 9, 25, 15, 30));
    expect(
      await db.isMarketDayFinal(
        dataset: MarketDataset.prices,
        market: MarketCode.twse,
        date: day,
      ),
      isTrue,
    );
  });

  test('last-writer-wins：較晚寫入的同日初值讓該列回到未定案', () async {
    await record(DateTime(2026, 9, 25, 15, 30));
    await record(DateTime(2026, 9, 24, 23, 50));
    final row = await db.getMarketDayFetch(
      MarketDataset.prices.code,
      MarketCode.twse,
      day,
    );
    expect(row!.fetchedAt, DateTime(2026, 9, 24, 23, 50));
    expect(
      await db.isMarketDayFinal(
        dataset: MarketDataset.prices,
        market: MarketCode.twse,
        date: day,
      ),
      isFalse,
    );
  });

  test('分市場、分資料集各自獨立', () async {
    await record(DateTime(2026, 9, 25));
    expect(
      await db.isMarketDayFinal(
        dataset: MarketDataset.prices,
        market: MarketCode.tpex,
        date: day,
      ),
      isFalse,
    );
    expect(
      await db.isMarketDayFinal(
        dataset: MarketDataset.margin,
        market: MarketCode.twse,
        date: day,
      ),
      isFalse,
    );
  });

  test('getMarketDayFetchesSince 只回起始日（含）以後', () async {
    await record(DateTime(2026, 9, 25));
    await db.upsertMarketDayFetch(
      dataset: MarketDataset.prices.code,
      market: MarketCode.twse,
      date: DateTime(2026, 9, 22),
      fetchedAt: DateTime(2026, 9, 23),
      rowCount: 1200,
    );
    final rows = await db.getMarketDayFetchesSince(DateTime(2026, 9, 23));
    expect(rows.map((r) => r.date), [day]);
  });

  test('getOrInitSetting：第一次寫入，之後不覆寫', () async {
    expect(await db.getOrInitSetting('finality_tracking_since', '2026-09-29'),
        '2026-09-29');
    expect(await db.getOrInitSetting('finality_tracking_since', '2026-10-01'),
        '2026-09-29');
  });
}
```

`test/data/database/market_day_fetch_schema_test.dart`：

```dart
// market_day_fetch 以 Migrator.createTable 補建（不 bump fingerprint）
//
// 模擬真實升級：帶著行情資料、但沒有這張表的既有 DB 被新版開啟。
// 若改成 bump fingerprint，行情表會被 drop，這條會紅。
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/data/database/app_database.dart';

void main() {
  late Directory tempDir;
  late File dbFile;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('mdf_schema_test');
    dbFile = File('${tempDir.path}/mdf.sqlite');
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  test('既有 DB 沒有 market_day_fetch：開啟後補建，行情資料保留', () async {
    final db1 = AppDatabase(NativeDatabase(dbFile));
    await db1.upsertStocks([
      StockMasterCompanion.insert(symbol: '2330', name: '台積電', market: 'TWSE'),
    ]);
    await db1.insertPrices([
      DailyPriceCompanion.insert(
        symbol: '2330',
        date: DateTime(2026, 9, 24),
        close: const Value(100),
      ),
    ]);
    await db1.customStatement('DROP TABLE market_day_fetch');
    await db1.close();

    final db2 = AppDatabase(NativeDatabase(dbFile));
    final prices = await db2.getPricesForDate(DateTime(2026, 9, 24));
    expect(prices, hasLength(1), reason: '行情資料不得因補建而消失');
    expect(await db2.getMarketDayFetchesSince(DateTime(2000)), isEmpty);
    await db2.close();
  });
}
```

- [ ] **Step 6：跑測試，確認失敗**

Run: `flutter test test/data/database/market_day_fetch_dao_test.dart test/data/database/market_day_fetch_schema_test.dart`
Expected：編譯失敗，`upsertMarketDayFetch` 等方法不存在。

- [ ] **Step 7：實作表、DAO、補建、設定**

`lib/data/database/tables/market_data_tables.dart` 檔尾：

```dart
/// 盤後資料的抓取狀態（2026-09-26）
///
/// 每組（資料集, 市場, 資料日）記最後一次**全市場**抓取成功寫入的時間。
/// 「是否定案」由 `fetched_at` 與資料日算出（見 `isFetchFinal`），刻意不存
/// 旗標，避免旗標與事實不同步。只有全市場抓取會寫入；逐檔、部分股票的
/// 抓取不代表那天整個市場已抓過。
@DataClassName('MarketDayFetchEntry')
class MarketDayFetch extends Table {
  /// `MarketDataset.code`
  TextColumn get dataset => text()();

  /// `MarketCode.twse`／`MarketCode.tpex`
  TextColumn get market => text()();

  /// 資料日（與 daily_price.date 同樣正規化為當地午夜）
  DateTimeColumn get date => dateTime()();

  /// 抓取時間：台北牆鐘（`AppClock.now()`），取本輪更新開始的時刻。
  /// 比實際發出請求早，只會讓判定偏向「未定案」。
  DateTimeColumn get fetchedAt => dateTime()();

  /// 該次寫入的列數（診斷用）
  IntColumn get rowCount => integer()();

  @override
  Set<Column> get primaryKey => {dataset, market, date};
}
```

`lib/data/database/dao/market_day_fetch_dao.dart`：

```dart
import 'package:drift/drift.dart';

import 'package:daredevil/core/constants/market_dataset.dart';
import 'package:daredevil/core/utils/date_context.dart';
import 'package:daredevil/core/utils/market_day_finality.dart';
import 'package:daredevil/data/database/app_database.drift.dart';
import 'package:daredevil/data/database/tables/market_data_tables.drift.dart';

/// 盤後資料抓取狀態（定案判斷）
mixin MarketDayFetchDaoMixin on $AppDatabase {
  /// 記錄一次全市場抓取。同鍵以最後寫入者為準（不取較大時間）：並行時
  /// 較晚寫入的若是初值，只會讓該列回到未定案，不會把初值誤標成定案。
  Future<void> upsertMarketDayFetch({
    required String dataset,
    required String market,
    required DateTime date,
    required DateTime fetchedAt,
    required int rowCount,
  }) {
    return into(marketDayFetch).insertOnConflictUpdate(
      MarketDayFetchCompanion.insert(
        dataset: dataset,
        market: market,
        date: DateContext.normalize(date),
        fetchedAt: fetchedAt,
        rowCount: rowCount,
      ),
    );
  }

  Future<MarketDayFetchEntry?> getMarketDayFetch(
    String dataset,
    String market,
    DateTime date,
  ) {
    final day = DateContext.normalize(date);
    return (select(marketDayFetch)..where(
          (t) =>
              t.dataset.equals(dataset) &
              t.market.equals(market) &
              t.date.equals(day),
        ))
        .getSingleOrNull();
  }

  /// 資料日 ≥ [since] 的所有狀態列
  Future<List<MarketDayFetchEntry>> getMarketDayFetchesSince(DateTime since) {
    final from = DateContext.normalize(since);
    return (select(
      marketDayFetch,
    )..where((t) => t.date.isBiggerOrEqualValue(from))).get();
  }

  Future<bool> isMarketDayFinal({
    required MarketDataset dataset,
    required String market,
    required DateTime date,
  }) async {
    final row = await getMarketDayFetch(dataset.code, market, date);
    return row != null &&
        isFetchFinal(dataDate: row.date, fetchedAtTaipei: row.fetchedAt);
  }
}
```

`lib/data/database/dao/user_dao.dart`，接在 `setSetting` 後：

```dart
  /// 不存在才寫入（已存在就回既有值、不覆寫）
  ///
  /// 給「第一次寫入後就不再變動」的設定用，例如定案追蹤起始日。用會覆寫的
  /// [setSetting] 時，App 與 launchd 同時首次執行會互相蓋掉。
  Future<String> getOrInitSetting(String key, String initialValue) async {
    await into(appSettings).insert(
      AppSettingsCompanion.insert(key: key, value: initialValue),
      mode: InsertMode.insertOrIgnore,
    );
    return (await getSetting(key))!;
  }
```

`lib/data/database/app_database.dart`：

1. import 區加 `import 'package:daredevil/data/database/dao/market_day_fetch_dao.dart';`
2. `@DriftDatabase(tables: [...])` 在 `QuarterlyReport,` 後加 `MarketDayFetch,`
3. `with` 清單在 `CalibrationCacheDaoMixin` 前加 `MarketDayFetchDaoMixin,`
4. `beforeOpen` 在 `await _ensureQuarterlyReportSchema();` 後加 `await _ensureMarketDayFetchSchema();`
5. 在 `_ensureQuarterlyReportSchema` 定義之後加：

```dart
  /// 盤後資料抓取狀態表（2026-09-26，additive）。
  ///
  /// 沿 [_ensureQuarterlyReportSchema] 先例：**不 bump fingerprint**。指紋
  /// bump 會 wipe 全部行情表，為加一張新表付這代價不成比例。createTable＝
  /// CREATE TABLE IF NOT EXISTS：既有 DB 冪等補建，新裝機由 createAll 先建好。
  Future<void> _ensureMarketDayFetchSchema() async {
    await Migrator(this).createTable(marketDayFetch);
  }
```

6. `_ensureSchemaFingerprint` 說明的「何時 bump fingerprint」清單後補一句：

```dart
  /// 例外：純新增、不動既有表的 table 可比照 `_ensureQuarterlyReportSchema`
  /// 用 `Migrator.createTable` 補建而不 bump（2026-08-06 起的先例）。
```

產生 Drift 程式碼：

Run: `dart run build_runner build --delete-conflicting-outputs`
Expected：成功，`market_data_tables.drift.dart` 出現 `MarketDayFetchCompanion`。

- [ ] **Step 8：跑測試，確認通過**

Run: `flutter test test/data/database/market_day_fetch_dao_test.dart test/data/database/market_day_fetch_schema_test.dart test/core/utils/market_day_finality_test.dart test/core/core_layer_purity_test.dart`
Expected：全部 PASS。

- [ ] **Step 9：把新條件逐條拔掉，確認測試會紅（mutation 自驗）**

逐一改動、跑測試、確認紅、再還原（**用編輯器還原，不用 `git checkout`**）：
- `isFetchFinal` 的 `isAfter` 改成 `!isBefore` → 「同日 21:30」測試要紅。
- `getOrInitSetting` 的 `InsertMode.insertOrIgnore` 改成 `InsertMode.insertOrReplace` → 「不覆寫」測試要紅。
- 拿掉 `_ensureMarketDayFetchSchema()` 呼叫 → schema 測試要紅。

---

## Task 2：MarketDayFetchLedger（抓取狀態記錄器）

**Files:**
- Create: `lib/data/repositories/market_day_fetch_ledger.dart`
- Test: `test/data/repositories/market_day_fetch_ledger_test.dart`

**Interfaces:**
- Consumes: Task 1 的 `MarketDataset`、`upsertMarketDayFetch`
- Produces:

```dart
class MarketDayFetchLedger {
  MarketDayFetchLedger({required AppDatabase database, required DateTime fetchedAt});
  final DateTime fetchedAt;
  List<LedgerRecord> get recorded;
  /// 在呼叫端的寫入 transaction 內呼叫。回傳是否記錄。
  Future<bool> report({required MarketDataset dataset, required String market, required DateTime date, required int rows});
}
typedef LedgerRecord = ({MarketDataset dataset, String market, DateTime date, int rows});
```

- [ ] **Step 1：寫失敗測試**

`test/data/repositories/market_day_fetch_ledger_test.dart`：

```dart
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/constants/market_codes.dart';
import 'package:daredevil/core/constants/market_dataset.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/data/repositories/market_day_fetch_ledger.dart';

void main() {
  late AppDatabase db;
  late MarketDayFetchLedger ledger;
  final day = DateTime(2026, 9, 24);
  final runStart = DateTime(2026, 9, 25, 15, 30);

  setUp(() async {
    db = AppDatabase.forTesting();
    // 上市 4 檔 → 門檻 ceil(4 × 0.5) = 2
    await db.upsertStocks([
      for (final s in ['1101', '1102', '1103', '1104'])
        StockMasterCompanion.insert(symbol: s, name: s, market: MarketCode.twse),
    ]);
    ledger = MarketDayFetchLedger(database: db, fetchedAt: runStart);
  });

  tearDown(() => db.close());

  Future<MarketDayFetchEntry?> row(MarketDataset ds) =>
      db.getMarketDayFetch(ds.code, MarketCode.twse, day);

  test('列數達門檻：記錄，fetchedAt 取本輪開始時間', () async {
    final ok = await ledger.report(
      dataset: MarketDataset.prices,
      market: MarketCode.twse,
      date: day,
      rows: 2,
    );
    expect(ok, isTrue);
    final r = await row(MarketDataset.prices);
    expect(r!.fetchedAt, runStart);
    expect(r.rowCount, 2);
    expect(ledger.recorded.single.dataset, MarketDataset.prices);
  });

  test('列數未達門檻：不記錄（尚未發布或抓取不完整）', () async {
    final ok = await ledger.report(
      dataset: MarketDataset.prices,
      market: MarketCode.twse,
      date: day,
      rows: 1,
    );
    expect(ok, isFalse);
    expect(await row(MarketDataset.prices), isNull);
    expect(ledger.recorded, isEmpty);
  });

  test('該市場沒有在市股票：不記錄', () async {
    final ok = await ledger.report(
      dataset: MarketDataset.prices,
      market: MarketCode.tpex,
      date: day,
      rows: 900,
    );
    expect(ok, isFalse);
  });

  test('當沖：價格覆蓋不足時即使當沖列數夠也不記錄', () async {
    final ok = await ledger.report(
      dataset: MarketDataset.dayTrading,
      market: MarketCode.twse,
      date: day,
      rows: 4,
    );
    expect(ok, isFalse, reason: '分母缺失時比例全是 0，記成定案就永遠不會重抓');
    expect(await row(MarketDataset.dayTrading), isNull);
  });

  test('當沖：價格覆蓋達門檻才記錄', () async {
    await db.insertPrices([
      for (final s in ['1101', '1102'])
        DailyPriceCompanion.insert(
          symbol: s,
          date: day,
          close: const Value(10),
          volume: const Value(1000),
        ),
    ]);
    final ok = await ledger.report(
      dataset: MarketDataset.dayTrading,
      market: MarketCode.twse,
      date: day,
      rows: 2,
    );
    expect(ok, isTrue);
  });
}
```

- [ ] **Step 2：跑測試，確認失敗**

Run: `flutter test test/data/repositories/market_day_fetch_ledger_test.dart`
Expected：編譯失敗，`market_day_fetch_ledger.dart` 不存在。

- [ ] **Step 3：實作**

`lib/data/repositories/market_day_fetch_ledger.dart`：

```dart
import 'package:daredevil/core/constants/api_config.dart';
import 'package:daredevil/core/constants/market_dataset.dart';
import 'package:daredevil/core/utils/date_context.dart';
import 'package:daredevil/core/utils/logger.dart';
import 'package:daredevil/data/database/app_database.dart';

/// 一筆成功記錄的抓取
typedef LedgerRecord = ({
  MarketDataset dataset,
  String market,
  DateTime date,
  int rows,
});

/// 一輪更新（或一次修復工具執行）的盤後資料抓取記錄器
///
/// 由 repository 在**寫入資料的同一個 transaction** 內呼叫 [report]，回報實際
/// 寫入的市場、資料日、列數（事實由源頭回報，不由呼叫端回推）。只有全市場
/// 抓取會拿到 ledger；逐檔或部分股票的寫入路徑傳 null，不記錄。
///
/// [fetchedAt] 是本輪開始的台北時間，比實際請求早。它只可能讓判定偏向
/// 「未定案」，不會把初值誤判成定案。
///
/// ⚠️ 必須與呼叫它的 repository 共用同一個 [AppDatabase] 實例：狀態寫入要
/// 落在 repository 的 transaction 內，而 Drift 的 transaction 綁在實例上。
class MarketDayFetchLedger {
  MarketDayFetchLedger({required AppDatabase database, required this.fetchedAt})
    : _db = database;

  final AppDatabase _db;
  final DateTime fetchedAt;
  final Map<String, int> _stockCounts = {};
  final List<LedgerRecord> _recorded = [];

  List<LedgerRecord> get recorded => List.unmodifiable(_recorded);

  Future<bool> report({
    required MarketDataset dataset,
    required String market,
    required DateTime date,
    required int rows,
  }) async {
    final day = DateContext.normalize(date);
    final label = '${dataset.code}/$market ${DateContext.formatYmd(day)}';
    final stocks = _stockCounts[market] ??= await _db.countStocksByMarket(
      market,
    );
    final need = (stocks * dataset.minCoverageRatio).ceil();
    if (stocks == 0 || rows < need) {
      AppLogger.info('FetchLedger', '$label 寫入 $rows 列 < 門檻 $need，不記錄抓取狀態');
      return false;
    }
    if (dataset == MarketDataset.dayTrading) {
      // 當沖比例的分母是同日成交量；價格覆蓋不足時比例整片是 0，
      // 記成定案就永遠不會重抓（spec §4.6）
      final priced = await _db.countPricesInDayAndMarket(day, market);
      final priceNeed = (stocks * ApiConfig.tradingBackfillMinCoverageRatio)
          .ceil();
      if (priced < priceNeed) {
        AppLogger.info(
          'FetchLedger',
          '$label 價格覆蓋不足（$priced < $priceNeed），不記錄當沖抓取狀態',
        );
        return false;
      }
    }
    await _db.upsertMarketDayFetch(
      dataset: dataset.code,
      market: market,
      date: day,
      fetchedAt: fetchedAt,
      rowCount: rows,
    );
    _recorded.add((dataset: dataset, market: market, date: day, rows: rows));
    return true;
  }
}
```

- [ ] **Step 4：跑測試，確認通過**

Run: `flutter test test/data/repositories/market_day_fetch_ledger_test.dart`
Expected：5 個測試全部 PASS。

- [ ] **Step 5：mutation 自驗**：拿掉 `rows < need` 條件，「未達門檻」測試要紅；拿掉當沖的價格覆蓋區塊，「價格覆蓋不足」測試要紅。逐一還原。

---

## Task 3：追蹤端點的日期守衛（fail-closed）與清快取

spec §4.4 第 3 點。只改追蹤資料集的呼叫點，不改 `extractTpexTable`／`TwParseUtils.parseAdDate` 本身。

**Files:**
- Modify: `lib/data/remote/twse_client.dart`（`getAllDailyPrices`、`getAllInstitutionalData`、`getAllMarginTradingData`、`getAllForeignShareholding`、新增 `clearCache`）
- Modify: `lib/data/remote/tpex_client.dart`（`getAllDailyPrices`、`getAllInstitutionalData`、`getAllMarginTradingData`、新增 `clearCache`）
- Test: `test/data/remote/tracked_endpoint_date_guard_test.dart`

**Interfaces:**
- Produces: `TwseClient.clearCache()`、`TpexClient.clearCache()`（`void`）

- [ ] **Step 1：寫失敗測試**

每個負向測試都配一個正向對照（同一份 body，只差日期）。沒有對照的話，「回空」可能只是 body 本身解析不出來。

`test/data/remote/tracked_endpoint_date_guard_test.dart`：

```dart
// 追蹤資料集的端點：回應日期缺失或與請求不符 → 整批丟棄（fail-closed）
//
// 每個負向案例都有同 body 的正向對照；沒有對照，「回空」可能只是 body
// 本身解析不出來，測試形同虛設。
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:daredevil/core/utils/clock.dart';
import 'package:daredevil/data/remote/tpex_client.dart';
import 'package:daredevil/data/remote/twse_client.dart';

class MockDio extends Mock implements Dio {}

class _FixedClock implements AppClock {
  const _FixedClock(this._now);
  final DateTime _now;
  @override
  DateTime now() => _now;
}

void main() {
  late MockDio dio;

  void stub(Map<String, dynamic> body) {
    when(
      () => dio.get<dynamic>(
        any(),
        queryParameters: any(named: 'queryParameters'),
        options: any(named: 'options'),
      ),
    ).thenAnswer(
      (_) async => Response<dynamic>(
        requestOptions: RequestOptions(path: '/x'),
        statusCode: 200,
        data: body,
      ),
    );
  }

  Map<String, dynamic> withoutKey(Map<String, dynamic> m, String key) =>
      Map.of(m)..remove(key);

  group('TWSE', () {
    late TwseClient client;
    setUp(() {
      dio = MockDio();
      client = TwseClient(dio: dio);
    });

    // STOCK_DAY_ALL JSON 形狀：[代號, 名稱, 成交股數, 成交金額, 開, 高, 低, 收, 漲跌, 筆數]
    final dailyBody = <String, dynamic>{
      'stat': 'OK',
      'date': '20260924',
      'data': [
        ['2330', '台積電', '1,000', '100,500', '100', '101', '99', '100.5', '0.5', '500'],
      ],
    };

    test('每日價格：有日期 → 正常', () async {
      stub(dailyBody);
      expect(await client.getAllDailyPrices(), hasLength(1));
    });

    test('每日價格：回應沒有日期 → 整批丟棄（不退回今天）', () async {
      stub(withoutKey(dailyBody, 'date'));
      expect(await client.getAllDailyPrices(), isEmpty);
    });

    // T86 19 欄
    final t86Body = <String, dynamic>{
      'stat': 'OK',
      'date': '20260924',
      'data': [
        ['2330', '台積電', '1,000', '500', '500', '0', '0', '0', '200', '100',
          '100', '20', '50', '20', '30', '5', '15', '-10', '620'],
      ],
    };

    test('法人：回應日期 = 請求日期 → 正常', () async {
      stub(t86Body);
      expect(
        await client.getAllInstitutionalData(date: DateTime(2026, 9, 24)),
        hasLength(1),
      );
    });

    test('法人：回應日期 ≠ 請求日期 → 整批丟棄', () async {
      stub(t86Body);
      expect(
        await client.getAllInstitutionalData(date: DateTime(2026, 9, 23)),
        isEmpty,
      );
    });

    test('法人：回應沒有日期 → 整批丟棄', () async {
      stub(withoutKey(t86Body, 'date'));
      expect(
        await client.getAllInstitutionalData(date: DateTime(2026, 9, 24)),
        isEmpty,
      );
    });

    // MI_MARGN：tables[1] 為個股明細（16 欄）
    final marginBody = <String, dynamic>{
      'stat': 'OK',
      'date': '20260924',
      'tables': [
        {'title': '信用交易統計', 'data': <dynamic>[]},
        {
          'title': '融資融券彙總',
          'data': [
            ['2330', '台積電', '100', '50', '0', '900', '950', '99999', '10',
              '20', '0', '30', '40', '99999', '0', ''],
          ],
        },
      ],
    };

    test('融資券（不帶日期）：有日期 → 正常', () async {
      stub(marginBody);
      expect(await client.getAllMarginTradingData(), hasLength(1));
    });

    test('融資券（不帶日期）：回應沒有日期 → 整批丟棄', () async {
      stub(withoutKey(marginBody, 'date'));
      expect(await client.getAllMarginTradingData(), isEmpty);
    });

    // MI_QFIIS 12 欄
    final qfiisBody = <String, dynamic>{
      'stat': 'OK',
      'date': '20260924',
      'data': [
        ['2330', '台積電', 'TW0002330008', '25,932,733,242', '5,000,000,000',
          '18,662,165,009', '19.28', '71.96', '100.00', '100.00', '', ''],
      ],
    };

    test('外資持股：有日期 → 正常', () async {
      stub(qfiisBody);
      expect(
        await client.getAllForeignShareholding(date: DateTime(2026, 9, 24)),
        hasLength(1),
      );
    });

    test('外資持股：回應沒有日期 → 整批丟棄', () async {
      stub(withoutKey(qfiisBody, 'date'));
      expect(
        await client.getAllForeignShareholding(date: DateTime(2026, 9, 24)),
        isEmpty,
      );
    });

    test('clearCache 後同一請求重新打 API', () async {
      stub(dailyBody);
      await client.getAllDailyPrices();
      await client.getAllDailyPrices();
      client.clearCache();
      await client.getAllDailyPrices();
      verify(
        () => dio.get<dynamic>(
          any(),
          queryParameters: any(named: 'queryParameters'),
          options: any(named: 'options'),
        ),
      ).called(2);
    });
  });

  group('TPEx', () {
    late TpexClient client;
    setUp(() {
      dio = MockDio();
      client = TpexClient(dio: dio, clock: _FixedClock(DateTime(2026, 9, 24, 21)));
    });

    Map<String, dynamic> tpexBody(List<dynamic> row, {String? date}) => {
      'stat': 'ok',
      'tables': [
        {'date': ?date, 'data': [row]},
      ],
    };

    final dailyRow = ['3624', '光頡', '144.00', '+4.00', '144.00', '147.00',
      '143.00', '145.07', '1,581,074', '229,365,406', '1,902', '144.00', '13',
      '144.50', '3', '117,340,842', '144.00', '158.00', '130.00'];

    test('每日價格：表格有日期 → 正常', () async {
      stub(tpexBody(dailyRow, date: '115/09/24'));
      expect(await client.getAllDailyPrices(), hasLength(1));
    });

    test('每日價格：表格沒有日期 → 整批丟棄（不退回請求日期）', () async {
      stub(tpexBody(dailyRow));
      expect(await client.getAllDailyPrices(), isEmpty);
    });

    final instRow = ['3624', '光頡', '7,797,033', '10,424,745', '-2,627,712',
      '0', '0', '0', '7,797,033', '10,424,745', '-2,627,712', '0', '0', '0',
      '5,000', '39,437', '-34,437', '104,231', '139,081', '-34,850', '109,231',
      '178,518', '-69,287', '-2,696,999'];

    test('法人：回應日期 = 請求日期 → 正常', () async {
      stub(tpexBody(instRow, date: '115/09/24'));
      expect(
        await client.getAllInstitutionalData(date: DateTime(2026, 9, 24)),
        hasLength(1),
      );
    });

    test('法人：回應日期 ≠ 請求日期 → 整批丟棄', () async {
      stub(tpexBody(instRow, date: '115/09/23'));
      expect(
        await client.getAllInstitutionalData(date: DateTime(2026, 9, 24)),
        isEmpty,
      );
    });

    test('法人：回應沒有日期 → 整批丟棄', () async {
      stub(tpexBody(instRow));
      expect(
        await client.getAllInstitutionalData(date: DateTime(2026, 9, 24)),
        isEmpty,
      );
    });

    test('法人（不帶日期請求）：表格有日期 → 正常；沒有日期 → 整批丟棄', () async {
      stub(tpexBody(instRow, date: '115/09/24'));
      expect(await client.getAllInstitutionalData(), hasLength(1));
      client.clearCache();
      stub(tpexBody(instRow));
      expect(await client.getAllInstitutionalData(), isEmpty);
    });

    final marginRow = ['3624', '光頡', '11,070', '1,297', '1,201', '0', '11,166',
      '167', '38.06', '29,335', '832', '210', '230', '0', '812', '6', '2.76',
      '29,335', '52', '11   A'];

    test('融資券（不帶日期）：有日期 → 正常', () async {
      stub(tpexBody(marginRow, date: '115/09/23'));
      expect(await client.getAllMarginTradingData(), hasLength(1));
    });

    test('融資券（不帶日期）：沒有日期 → 整批丟棄（不退回今天）', () async {
      stub(tpexBody(marginRow));
      expect(await client.getAllMarginTradingData(), isEmpty);
    });
  });
}
```

`'date': ?date` 是 Dart 3.8 的 null-aware map entry（pubspec 是 `sdk: ^3.10.7`，可用）。

- [ ] **Step 2：跑測試，確認失敗**

Run: `flutter test test/data/remote/tracked_endpoint_date_guard_test.dart`
Expected：編譯失敗（`clearCache` 不存在）。先暫時註解掉 clearCache 測試跑一次：各「沒有日期／日期不符」測試 FAIL（目前會退回今天或請求日期而回 1 筆），正向對照 PASS。確認後取消註解。

- [ ] **Step 3：實作 TWSE**

⚠️ 下列要替換的原始片段有些在檔內**不只一處**（例如 `getAllDailyPrices` 與 `getAllMarginTradingData` 的日期解析兩行逐字相同）。一律先定位到該方法內再改，不要全域取代。

`lib/data/remote/twse_client.dart`：

1. `getAllDailyPrices`，把

```dart
      final dateStr = data['date']?.toString() ?? '';
      final responseDate = TwParseUtils.parseAdDate(dateStr);
```

換成

```dart
      // 回應日期是寫入日期的唯一依據：解析不出就整批丟棄，不可退回今天
      // （寫錯日期比沒資料糟，且會騙過定案判斷）
      final responseDate = TwParseUtils.parseAdDateOrNull(
        data['date']?.toString(),
      );
      if (responseDate == null) {
        AppLogger.warning(_tag, '全市場價格回應缺日期或無法解析，整批丟棄');
        return <TwseDailyPrice>[];
      }
```

2. `getAllInstitutionalData`，把

```dart
      final dateStr = data['date']?.toString() ?? '';
      final parsedDate = TwParseUtils.parseAdDate(dateStr);
```

換成

```dart
      final parsedDate = TwParseUtils.parseAdDateOrNull(
        data['date']?.toString(),
      );
      if (parsedDate == null ||
          (date != null && !DateContext.isSameDay(parsedDate, date))) {
        AppLogger.warning(
          _tag,
          '法人回應日期 ${data['date']} 缺失或 ≠ 請求 $date，整批丟棄',
        );
        return <TwseInstitutional>[];
      }
```

3. `getAllMarginTradingData`，把

```dart
      final dateStr = data['date']?.toString() ?? '';
      final responseDate = TwParseUtils.parseAdDate(dateStr);
```

換成

```dart
      final responseDate = TwParseUtils.parseAdDateOrNull(
        data['date']?.toString(),
      );
      if (responseDate == null) {
        AppLogger.warning(_tag, '融資融券回應缺日期或無法解析，整批丟棄');
        return <TwseMarginTrading>[];
      }
```

4. `getAllForeignShareholding`，把

```dart
      final parsedDate = TwParseUtils.parseAdDate(
        data['date']?.toString() ?? '',
      );
```

換成

```dart
      final parsedDate = TwParseUtils.parseAdDateOrNull(
        data['date']?.toString(),
      );
      if (parsedDate == null) {
        AppLogger.warning(_tag, '外資持股回應缺日期或無法解析，整批丟棄');
        return <TwseForeignShareholding>[];
      }
```

5. 在 `close()`（若無則在 class 內其他 public 方法旁）加：

```dart
  /// 清除回應快取。每輪更新開始時呼叫：常駐的 App 跨午夜時，前一輪的
  /// 快取會讓舊資料被當成本輪抓的，進而誤判定案。
  void clearCache() => _cache.clear();
```

若檔案尚未 import `DateContext`，補 `import 'package:daredevil/core/utils/date_context.dart';`。

- [ ] **Step 4：實作 TPEx**

`lib/data/remote/tpex_client.dart`：

1. `getAllDailyPrices`，把 `extractTpexTable(data, targetDate, _tag, '全市場價格')` 的第二個參數改成 `_unknownDateSentinel`，並在 `if (table == null) return [];` 後加：

```dart
      // 端點無視請求日期，寫入日期只能信回應；回應沒帶日期就整批丟棄，
      // 不可退回請求日期（fail-closed）
      if (table.date == _unknownDateSentinel) {
        AppLogger.warning(_tag, '全市場價格回應缺日期，整批丟棄');
        return [];
      }
```

2. `getAllInstitutionalData`，`extractTpexTable` 第二參數改成 `_unknownDateSentinel`，並在 `if (table == null) return [];` 後加：

```dart
      if (table.date == _unknownDateSentinel ||
          (date != null && !DateContext.isSameDay(table.date, date))) {
        AppLogger.warning(_tag, '法人回應日期 ${table.date} 缺失或 ≠ 請求 $date，整批丟棄');
        return [];
      }
```

3. `getAllMarginTradingData`，把 `date != null ? _unknownDateSentinel : _clock.now()` 改成 `_unknownDateSentinel`，並在既有「回應日期不符」守衛**之前**加：

```dart
      if (table.date == _unknownDateSentinel) {
        AppLogger.warning(_tag, '融資融券回應缺日期，整批丟棄');
        return [];
      }
```

4. 在 `close()` 旁加：

```dart
  /// 清除回應快取（每輪更新開始時呼叫，理由同 TwseClient.clearCache）
  void clearCache() => _cache.clear();
```

- [ ] **Step 5：跑測試，確認通過**

Run: `flutter test test/data/remote/tracked_endpoint_date_guard_test.dart`
Expected：全部 PASS。

- [ ] **Step 6：跑受影響的既有 client 測試**

Run: `flutter test test/data/remote/`
Expected：全部 PASS。若既有 fixture 缺日期而被新守衛擋掉，**先確認真實端點確實會回日期**（對照 `test/fixtures/remote/` 的真實回應），再補 fixture 的日期；不可放寬守衛。

- [ ] **Step 7：mutation 自驗**：逐一拿掉每個新守衛，確認對應的負向測試變紅，再還原。

---

## Task 4：上櫃歷史價格改走 `dailyQuotes`

spec §4.7。

**Files:**
- Modify: `lib/data/remote/tpex_client.dart`（`getAllDailyPricesHistorical` 改端點；`_parseDailyPriceRow` 改成 public static `parseDailyPriceRow`；新增 `parseDailyQuotesPrices`；刪除 `parseAfterTradingOtcDailyPrices`）
- Modify: `lib/data/repositories/tpex_price_source.dart`、`lib/data/repositories/price_repository.dart`（註解改寫）
- Create: `test/data/remote/fixtures/tpex_daily_quotes_20260709.json`
- Modify: `test/data/remote/historical_daily_price_parser_test.dart`（移除 afterTrading/otc 的 group，新增 dailyQuotes group）

**Interfaces:**
- Produces: `static List<TpexDailyPrice> TpexClient.parseDailyQuotesPrices(Map<dynamic, dynamic> json, DateTime requestedDate)`、`static TpexDailyPrice? TpexClient.parseDailyPriceRow(List<dynamic> row, DateTime date)`

- [ ] **Step 1：建立 fixture（取自 2026-07-09 實際回應，節錄三列）**

`test/data/remote/fixtures/tpex_daily_quotes_20260709.json`：

```json
{
  "date": "20260709",
  "stat": "ok",
  "tables": [
    {
      "title": "上櫃股票行情",
      "date": "115/07/09",
      "fields": ["代號", "名稱", "收盤", "漲跌", "開盤", "最高", "最低", "均價", "成交股數", "成交金額(元)", "成交筆數", "最後買價", "最後買量(張數)", "最後賣價", "最後賣量(張數)", "發行股數", "次日 參考價", "次日 漲停價", "次日 跌停價"],
      "data": [
        ["006201", "元大富櫃50", "46.85", "+0.51", "46.52", "47.80", "46.52", "47.20", "200,019", "9,440,357", "197", "46.77", "1", "46.90", "15", "20,446,000", "46.85", "51.50", "42.17"],
        ["3624", "光頡", "144.00", "+4.00", "144.00", "147.00", "143.00", "145.07", "1,581,074", "229,365,406", "1,902", "144.00", "13", "144.50", "3", "117,340,842", "144.00", "158.00", "130.00"],
        ["700019", "宏捷科統一5C購01", " ---", "--- ", "---", "---", "---", "0.34", "0", "0", "0", "0.31", "10", "0.37", "2", "5,000,000", "0.34", "0.51", "0.17"]
      ]
    },
    {"title": "管理股票", "data": []}
  ]
}
```

- [ ] **Step 2：寫失敗測試**

在 `test/data/remote/historical_daily_price_parser_test.dart` 刪除 `parseAfterTradingOtcDailyPrices` 的 group，新增：

```dart
  group('TpexClient.parseDailyQuotesPrices（afterTrading/dailyQuotes，官方口徑）', () {
    Map<String, dynamic> fixture() => jsonDecode(
      File('test/data/remote/fixtures/tpex_daily_quotes_20260709.json')
          .readAsStringSync(),
    ) as Map<String, dynamic>;

    test('成交股數取 index 8（含定價與零股，＝官方個股日成交資訊）', () {
      final rows = TpexClient.parseDailyQuotesPrices(
        fixture(),
        DateTime(2026, 7, 9),
      );
      final c = rows.firstWhere((r) => r.code == '3624');
      expect(c.volume, 1581074, reason: '官方 1,581 張；afterTrading/otc 是 1,436,000');
      expect(c.close, 144.0);
      expect(c.date, DateTime(2026, 7, 9));
    });

    test('權證被 isTpexPriceCode 濾掉，ETF 保留', () {
      final codes = TpexClient.parseDailyQuotesPrices(
        fixture(),
        DateTime(2026, 7, 9),
      ).map((r) => r.code);
      expect(codes, containsAll(['3624', '006201']));
      expect(codes, isNot(contains('700019')));
    });

    test('回應日期 ≠ 請求日期 → 整批丟棄', () {
      expect(
        TpexClient.parseDailyQuotesPrices(fixture(), DateTime(2026, 7, 8)),
        isEmpty,
      );
    });
  });
```

檔頭若缺 `dart:convert`、`dart:io` import，補上。

另在 `test/data/remote/tracked_endpoint_date_guard_test.dart` 的 TPEx group 加端點釘樁：

```dart
    test('歷史價格打 afterTrading/dailyQuotes，日期格式 YYYY/MM/DD', () async {
      stub({
        'date': '20260709',
        'stat': 'ok',
        'tables': [
          {'date': '115/07/09', 'data': [dailyRow]},
        ],
      });
      final rows = await client.getAllDailyPricesHistorical(DateTime(2026, 7, 9));
      expect(rows, hasLength(1));
      final captured = verify(
        () => dio.get<dynamic>(
          captureAny(),
          queryParameters: captureAny(named: 'queryParameters'),
          options: any(named: 'options'),
        ),
      ).captured;
      expect(captured[0], '/www/zh-tw/afterTrading/dailyQuotes');
      expect((captured[1] as Map)['date'], '2026/07/09');
    });
```

- [ ] **Step 3：跑測試，確認失敗**

Run: `flutter test test/data/remote/historical_daily_price_parser_test.dart test/data/remote/tracked_endpoint_date_guard_test.dart`
Expected：編譯失敗（`parseDailyQuotesPrices` 不存在）。

- [ ] **Step 4：實作**

`lib/data/remote/tpex_client.dart`：

1. `_parseDailyPriceRow` 改名為 public static，並更新 `getAllDailyPrices` 的呼叫（`parser: (row) => parseDailyPriceRow(row, table.date)`）：

```dart
  /// 解析每日行情列（daily_close_quotes 與 dailyQuotes 共用，兩者欄位相同）
  ///
  /// 列格式: [代號, 名稱, 收盤, 漲跌, 開盤, 最高, 最低, 均價, 成交股數, 成交金額, 成交筆數, 最後買價, 最後買量, 最後賣價, 最後賣量, 發行股數, 次日參考價, 次日漲停價, 次日跌停價]
  static TpexDailyPrice? parseDailyPriceRow(List<dynamic> row, DateTime date) {
    // 內容與原 _parseDailyPriceRow 相同
  }
```

2. `getAllDailyPricesHistorical` 整段換成：

```dart
  /// 歷史全市場行情（`/www/zh-tw/afterTrading/dailyQuotes`；回補與未定案重抓用）
  ///
  /// 口徑與每日端點 daily_close_quotes 相同（含定價交易、含零股，＝官方
  /// 個股日成交資訊）。舊的 `afterTrading/otc` 是「不含定價、整張」口徑，
  /// 只有官方的 91–98%，已停用（2026-09-26 實測）。
  Future<List<TpexDailyPrice>> getAllDailyPricesHistorical(DateTime date) {
    return MarketClientMixin.executeRequest(_tag, '歷史全市場價格', () async {
      final dateStr =
          '${date.year.toString().padLeft(4, '0')}/'
          '${date.month.toString().padLeft(2, '0')}/'
          '${date.day.toString().padLeft(2, '0')}';
      final cacheKey = 'dailyQuotesHist:$dateStr';
      final cached = _cache.get(cacheKey) as List<TpexDailyPrice>?;
      if (cached != null) return cached;

      final response = await _dio.get(
        '/www/zh-tw/afterTrading/dailyQuotes',
        queryParameters: {'date': dateStr, 'response': 'json'},
      );
      if (response.statusCode != 200) {
        throw ApiException(
          '$_tag API error: ${response.statusCode}',
          response.statusCode,
        );
      }
      final data = MarketClientMixin.decodeResponseData(
        response.data,
        _tag,
        '歷史全市場價格',
      );
      if (data == null) return <TpexDailyPrice>[];

      final result = parseDailyQuotesPrices(data, date);
      if (result.isNotEmpty) _cache.put(cacheKey, result);
      return result;
    });
  }

  /// dailyQuotes 回應 → 行情列。頂層 `date`（YYYYMMDD）≠ 請求日期就整批
  /// 丟棄（端點失效防護）。刻意不走 `extractTpexTable`：它在回應沒帶日期時
  /// 會退回請求日期（fail-open）。public 供測試。
  static List<TpexDailyPrice> parseDailyQuotesPrices(
    Map<dynamic, dynamic> json,
    DateTime requestedDate,
  ) {
    final expected =
        '${requestedDate.year.toString().padLeft(4, '0')}'
        '${requestedDate.month.toString().padLeft(2, '0')}'
        '${requestedDate.day.toString().padLeft(2, '0')}';
    if (json['date']?.toString() != expected) return const [];

    final tables = json['tables'];
    if (tables is! List || tables.isEmpty) return const [];
    final first = tables.first;
    if (first is! Map) return const [];
    final rows = first['data'];
    if (rows is! List) return const [];

    final day = DateContext.normalize(requestedDate);
    final result = <TpexDailyPrice>[];
    for (final raw in rows) {
      if (raw is! List) continue;
      final parsed = parseDailyPriceRow(raw, day);
      if (parsed != null) result.add(parsed);
    }
    return result;
  }
```

3. 刪除 `parseAfterTradingOtcDailyPrices`，並 grep 確認沒有其他呼叫點：

Run: `grep -rn "parseAfterTradingOtcDailyPrices\|afterTrading/otc" lib test tool`
Expected：`parseAfterTradingOtcDailyPrices` 無結果；`afterTrading/otc` 只剩本 Task 新寫的說明註解（「舊的 `afterTrading/otc` … 已停用」），沒有任何呼叫。

4. `lib/data/repositories/tpex_price_source.dart` 的 `fetchAllDailyPricesHistorical` 註解改成 `/// 歷史全市場行情（afterTrading/dailyQuotes，官方口徑；回補與重抓用）`。`lib/data/repositories/price_repository.dart` 的 `backfillTpexPricesByDate` 說明中「afterTrading 歷史端點」「afterTrading/otc」改成「afterTrading/dailyQuotes（官方口徑，與每日端點相同）」。

- [ ] **Step 5：跑測試，確認通過**

Run: `flutter test test/data/remote/ test/data/repositories/price_repository_test.dart test/domain/services/update/historical_price_syncer_test.dart`
Expected：全部 PASS。

---

## Task 5：上櫃當沖可帶日期

spec §4.9（client 與 repository 部分；回補接線在 Task 9）。

**Files:**
- Modify: `lib/data/remote/tpex_client.dart`（`getAllDayTradingData({DateTime? date})`）
- Modify: `lib/data/repositories/trading_repository.dart`（`syncAllDayTradingFromTpex({DateTime? date, bool force})`，ledger 在 Task 9 加）
- Modify: `lib/domain/repositories/trading_repository.dart`（介面同步）
- Modify: `test/data/remote/tpex_day_trading_parser_test.dart`

**Interfaces:**
- Produces: `TpexClient.getAllDayTradingData({DateTime? date})`、`TradingRepository.syncAllDayTradingFromTpex({DateTime? date, bool force = false})`

- [ ] **Step 1：寫失敗測試**（加在 `tpex_day_trading_parser_test.dart` 末端的 `main` 內）

```dart
  group('帶日期請求（2026-09-26 實測端點吃 date=YYYY/MM/DD）', () {
    test('帶 date 參數、快取 key 含日期', () async {
      stub(body(date: '20260821'));
      await client.getAllDayTradingData(date: DateTime(2026, 8, 21));
      await client.getAllDayTradingData(date: DateTime(2026, 8, 20));
      final captured = verify(
        () => dio.get<dynamic>(
          any(),
          queryParameters: captureAny(named: 'queryParameters'),
          options: any(named: 'options'),
        ),
      ).captured;
      expect(captured, hasLength(2), reason: '不同日期不得共用快取');
      expect((captured[0] as Map)['date'], '2026/08/21');
    });

    test('回應日期 = 請求日期 → 正常（不套過期守衛）', () async {
      // 時鐘 8/23、資料 8/21；請求歷史日時過期守衛不適用
      final c = TpexClient(dio: dio, clock: _FixedClock(DateTime(2026, 9, 26)));
      stub(body(date: '20260821'));
      expect(await c.getAllDayTradingData(date: DateTime(2026, 8, 21)), hasLength(3));
    });

    test('回應日期 ≠ 請求日期 → 整批丟棄', () async {
      stub(body(date: '20260821'));
      expect(
        await client.getAllDayTradingData(date: DateTime(2026, 8, 20)),
        isEmpty,
      );
    });
  });
```

- [ ] **Step 2：跑測試，確認失敗**

Run: `flutter test test/data/remote/tpex_day_trading_parser_test.dart`
Expected：編譯失敗（`date` 參數不存在）。

- [ ] **Step 3：實作**

`getAllDayTradingData`：

```dart
  Future<List<TpexDayTrading>> getAllDayTradingData({DateTime? date}) {
    return MarketClientMixin.executeRequest(_tag, '當沖資料', () async {
      final cacheKey = date == null
          ? 'tpexDayTrading'
          : 'tpexDayTrading:${TwParseUtils.formatDateCompact(date)}';
      final cached = _cache.get(cacheKey) as List<TpexDayTrading>?;
      if (cached != null) return cached;

      final response = await _dio.get(
        ApiEndpoints.tpexDayTrading,
        queryParameters: {
          'type': 'Daily',
          'response': 'json',
          if (date != null)
            'date':
                '${date.year.toString().padLeft(4, '0')}/'
                '${date.month.toString().padLeft(2, '0')}/'
                '${date.day.toString().padLeft(2, '0')}',
        },
        options: Options(headers: {'Accept': 'application/json'}),
      );
      // …（狀態碼、decode、stat 檢查不變）

      final dataDate = TwParseUtils.parseAdDateOrNull(data['date']?.toString());
      if (dataDate == null) {
        AppLogger.warning(_tag, '當沖回應缺 date 欄位，整批丟棄');
        return const <TpexDayTrading>[];
      }

      if (date != null) {
        // 帶日期請求：回應日期必須相等（與上市 TWTB4U 相同的守衛）
        if (!DateContext.isSameDay(dataDate, date)) {
          AppLogger.warning(_tag, '當沖回應日期 $dataDate ≠ 請求 $date，整批丟棄');
          return const <TpexDayTrading>[];
        }
      } else {
        // 不帶日期（取最新）：沒有請求日期可比，保留未來／過期守衛兼任
        // 端點凍結偵測
        // …（原本的 future／stale 兩段守衛，原封不動搬進這個 else）
      }
      // …（其餘解析不變）
```

同時把方法上方的說明改寫：拿掉「無視 `date` 參數、永遠回最新交易日」，改成「帶 `date=YYYY/MM/DD` 回指定日（2026-09-26 實測回到 2024-01）；不帶時回最新交易日」。

`TradingRepository.syncAllDayTradingFromTpex`：

```dart
  Future<int> syncAllDayTradingFromTpex({DateTime? date, bool force = false}) async {
    try {
      final data = await _tpexClient.getAllDayTradingData(date: date);
      // …其餘不變
```

說明文字把「呼叫端不傳日期正是為此」改成「不傳日期時取最新交易日，寫入日期一律取自回應」。介面 `ITradingRepository.syncAllDayTradingFromTpex` 簽章同步改。

- [ ] **Step 4：跑測試，確認通過**

Run: `flutter test test/data/remote/tpex_day_trading_parser_test.dart test/data/repositories/trading_repository_tpex_day_trading_test.dart test/domain/services/update/tpex_day_trading_wiring_test.dart`
Expected：全部 PASS。每日路徑呼叫 `getAllDayTradingData()` 時 `date` 仍是 null，既有 stub 照常命中；只有新增的帶日期呼叫需要 `date: any(named: 'date')`（規則見 Global Constraints「mocktail 具名參數」）。

---

## Task 6：當沖比例共用函式與重算

spec §4.6。

**Files:**
- Create: `lib/core/utils/day_trading_ratio.dart`
- Modify: `lib/data/repositories/trading_repository.dart`（`_persistDayTrading` 改用共用函式）
- Modify: `lib/data/database/dao/day_trading_dao.dart`（新增 `recomputeDayTradingRatios`）
- Modify: `tool/backfill_tpex_day_trading.dart`（改用共用函式）
- Test: `test/core/utils/day_trading_ratio_test.dart`
- Test: `test/data/database/day_trading_ratio_recompute_test.dart`

**Interfaces:**
- Produces:
  - `double? computeDayTradingRatio({required double? tradeVolume, required double? totalVolume})`：分母缺失或 ≤ 0 回 null，否則回夾限在 `[0, dayTradingMaxValidRatio]` 的百分比
  - `AppDatabase.recomputeDayTradingRatios({required DateTime day, required Set<String> symbols}) → Future<int>`（回傳實際更新列數）

- [ ] **Step 1：寫失敗測試**

`test/core/utils/day_trading_ratio_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/constants/data_freshness.dart';
import 'package:daredevil/core/utils/day_trading_ratio.dart';

void main() {
  test('一般情況：當沖股數 ÷ 成交量 × 100', () {
    expect(computeDayTradingRatio(tradeVolume: 250, totalVolume: 1000), 25.0);
  });

  test('超過上限夾到 dayTradingMaxValidRatio', () {
    expect(
      computeDayTradingRatio(tradeVolume: 3000, totalVolume: 1000),
      DataFreshness.dayTradingMaxValidRatio,
    );
  });

  test('分母缺失或為 0 → null（由呼叫端決定寫 0、保留或跳過）', () {
    expect(computeDayTradingRatio(tradeVolume: 10, totalVolume: null), isNull);
    expect(computeDayTradingRatio(tradeVolume: 10, totalVolume: 0), isNull);
    expect(computeDayTradingRatio(tradeVolume: null, totalVolume: 100), isNull);
  });

  test('負值夾到 0', () {
    expect(computeDayTradingRatio(tradeVolume: -5, totalVolume: 100), 0.0);
  });
}
```

`test/data/database/day_trading_ratio_recompute_test.dart`：

```dart
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/data/database/app_database.dart';

void main() {
  late AppDatabase db;
  final day = DateTime(2026, 9, 24);

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.upsertStocks([
      StockMasterCompanion.insert(symbol: '2330', name: '台積電', market: 'TWSE'),
      StockMasterCompanion.insert(symbol: '2317', name: '鴻海', market: 'TWSE'),
    ]);
    await db.insertDayTradingData([
      DayTradingCompanion.insert(
        symbol: '2330',
        date: day,
        dayTradingRatio: const Value(50),
        tradeVolume: const Value(500),
      ),
      DayTradingCompanion.insert(
        symbol: '2317',
        date: day,
        dayTradingRatio: const Value(40),
        tradeVolume: const Value(400),
      ),
    ]);
  });

  tearDown(() => db.close());

  Future<double?> ratio(String s) async => (await db.getDayTradingHistory(
    s,
    startDate: day,
  )).single.dayTradingRatio;

  test('成交量被更正後重算比例', () async {
    await db.insertPrices([
      DailyPriceCompanion.insert(symbol: '2330', date: day, volume: const Value(2000)),
    ]);
    final n = await db.recomputeDayTradingRatios(day: day, symbols: {'2330'});
    expect(n, 1);
    expect(await ratio('2330'), 25.0);
  });

  test('分母缺失時保留原比例，不改寫成 0', () async {
    final n = await db.recomputeDayTradingRatios(day: day, symbols: {'2317'});
    expect(n, 0);
    expect(await ratio('2317'), 40.0);
  });

  test('只動指定代號', () async {
    await db.insertPrices([
      DailyPriceCompanion.insert(symbol: '2330', date: day, volume: const Value(2000)),
      DailyPriceCompanion.insert(symbol: '2317', date: day, volume: const Value(4000)),
    ]);
    await db.recomputeDayTradingRatios(day: day, symbols: {'2330'});
    expect(await ratio('2317'), 40.0);
  });

  test('價格列是同日變體時間戳也對得上（範圍查詢）', () async {
    await db.insertPrices([
      DailyPriceCompanion.insert(
        symbol: '2330',
        date: DateTime(2026, 9, 24, 8),
        volume: const Value(2000),
      ),
    ]);
    await db.recomputeDayTradingRatios(day: day, symbols: {'2330'});
    // 原比例 50；對上變體時間戳的分母 2000 才會變 25（用精確相等查詢會對不上而保留 50）
    expect(await ratio('2330'), 25.0);
  });
}
```

`getDayTradingHistory` 簽章請先 grep `day_trading_dao.dart` 確認；若名稱或參數不同，改用該檔既有的單檔查詢方法。

- [ ] **Step 2：跑測試，確認失敗**

Run: `flutter test test/core/utils/day_trading_ratio_test.dart test/data/database/day_trading_ratio_recompute_test.dart`
Expected：編譯失敗。

- [ ] **Step 3：實作**

`lib/core/utils/day_trading_ratio.dart`：

```dart
import 'package:daredevil/core/constants/data_freshness.dart';

/// 當沖比例（%）＝當沖成交股數 ÷ 當日成交量 × 100，夾在
/// `[0, DataFreshness.dayTradingMaxValidRatio]`。
///
/// 分母缺失或 ≤ 0 時回 null，由呼叫端決定語意：每日寫入寫 0（沿用既有
/// 行為）、重算保留原值、回補工具跳過該列。三處共用此函式，避免公式分岐。
double? computeDayTradingRatio({
  required double? tradeVolume,
  required double? totalVolume,
}) {
  if (tradeVolume == null || totalVolume == null || totalVolume <= 0) {
    return null;
  }
  final ratio = tradeVolume / totalVolume * 100;
  return ratio.clamp(0.0, DataFreshness.dayTradingMaxValidRatio).toDouble();
}
```

`_persistDayTrading` 內，把

```dart
      final total = volumeMap[item.code] ?? 0;
      var ratio = total > 0 ? (item.volume / total) * 100 : 0.0;
      if (ratio > DataFreshness.dayTradingMaxValidRatio) {
        ratio = DataFreshness.dayTradingMaxValidRatio;
      }
      if (ratio < 0) ratio = 0;
```

換成

```dart
      // 分母缺失寫 0：0 在當沖語意下是「無當沖」，分母未知時給非零值是編造
      final ratio =
          computeDayTradingRatio(
            tradeVolume: item.volume,
            totalVolume: volumeMap[item.code],
          ) ??
          0.0;
```

`day_trading_dao.dart` 新增（檔頭補 `import 'package:daredevil/core/utils/day_trading_ratio.dart';`，以及 daily_price 表的 generated import，若尚未存在）：

```dart
  /// 成交量更正後，重算 [day] 當天 [symbols] 的當沖比例
  ///
  /// 分母用同日（整天範圍，涵蓋歷史上的變體時間戳）價格成交量；分母缺失
  /// 或為 0 時**保留原比例**，不改寫成 0。回傳實際更新的列數。
  Future<int> recomputeDayTradingRatios({
    required DateTime day,
    required Set<String> symbols,
  }) async {
    if (symbols.isEmpty) return 0;
    final start = DateTime(day.year, day.month, day.day);
    final end = DateTime(day.year, day.month, day.day + 1);
    final rows = await (select(dayTrading)..where(
          (t) =>
              t.date.isBiggerOrEqualValue(start) &
              t.date.isSmallerThanValue(end) &
              t.symbol.isIn(symbols),
        ))
        .get();
    if (rows.isEmpty) return 0;
    final prices = await (select(dailyPrice)..where(
          (t) =>
              t.date.isBiggerOrEqualValue(start) &
              t.date.isSmallerThanValue(end) &
              t.symbol.isIn(rows.map((r) => r.symbol)),
        ))
        .get();
    final volumes = {
      for (final p in prices)
        if (p.volume != null) p.symbol: p.volume!.toDouble(),
    };
    var updated = 0;
    await batch((b) {
      for (final r in rows) {
        final ratio = computeDayTradingRatio(
          tradeVolume: r.tradeVolume,
          totalVolume: volumes[r.symbol],
        );
        if (ratio == null) continue;
        b.update(
          dayTrading,
          DayTradingCompanion(dayTradingRatio: Value(ratio)),
          where: (t) => t.symbol.equals(r.symbol) & t.date.equals(r.date),
        );
        updated++;
      }
    });
    return updated;
  }
```

`tool/backfill_tpex_day_trading.dart` 約 249–257 行，把

```dart
            var ratio = (d.volume / total) * 100;
            if (ratio > DataFreshness.dayTradingMaxValidRatio) {
              ratio = DataFreshness.dayTradingMaxValidRatio;
            }
            if (ratio < 0) ratio = 0;
```

換成

```dart
            final ratio = computeDayTradingRatio(
              tradeVolume: d.volume,
              totalVolume: total,
            )!; // total 已排除 null 與 ≤ 0（volByDay 只收 volume > 0）
```

並 import `package:daredevil/core/utils/day_trading_ratio.dart`；若 `DataFreshness` import 因此變成未使用，移除。

- [ ] **Step 4：跑測試，確認通過**

Run: `flutter test test/core/utils/day_trading_ratio_test.dart test/data/database/day_trading_ratio_recompute_test.dart test/data/repositories/trading_repository_daytrading_ratio_test.dart test/tool/`
Expected：全部 PASS。`trading_repository_daytrading_ratio_test.dart` 是既有的行為釘樁，必須不動就綠。

- [ ] **Step 5：Stage A 閘門**

Run: `flutter analyze && flutter test && dart compile kernel tool/daily_update.dart -o /tmp/du.dill`
Expected：analyze 0 issue、全套 PASS、編譯成功。
送 code review（Task 1–6 的變更）；通過後停下，請使用者說「提交」。建議 commit message：`feat: 盤後資料定案的基礎：抓取狀態表、記錄器、端點日期守衛、上櫃歷史價格改官方口徑`

---

## Task 7：價格路徑接上定案判斷

spec §4.5(a)、§4.4、§4.6。

**Files:**
- Modify: `lib/domain/repositories/price_repository.dart`（介面加 `ledger`）
- Modify: `lib/data/repositories/price_repository.dart`
- Modify: `lib/domain/services/update/historical_price_syncer.dart`（`syncHistoricalPrices` 與 `_syncMissingMarketDays` 加 `ledger`，Phase 0 傳下去）
- Test: `test/data/repositories/price_repository_finality_test.dart`
- Modify（若 stub 對不上）：`test/data/repositories/price_repository_test.dart`、`test/domain/services/update/historical_price_syncer_test.dart`、`test/domain/services/update_service_test.dart`

**Interfaces:**
- Consumes: Task 1 `isMarketDayFinal`；Task 2 `MarketDayFetchLedger.report`；Task 6 `recomputeDayTradingRatios`
- Produces:
  - `IPriceRepository.syncAllPricesForDate(DateTime date, {bool force = false, MarketDayFetchLedger? ledger})`
  - `IPriceRepository.backfillTwsePricesByDate({required DateTime date, required Set<String> targetSymbols, MarketDayFetchLedger? ledger})`（TPEx 同）
  - `HistoricalPriceSyncer.syncHistoricalPrices({..., MarketDayFetchLedger? ledger})`

- [ ] **Step 1：寫失敗測試**

`test/data/repositories/price_repository_finality_test.dart`：

```dart
// 價格同步的定案判斷（spec §4.5(a)）
//
// 回歸測試：當天已有遠超舊門檻的列數、但還沒定案時，必須重抓。
// 舊邏輯（列數 > 1500 就跳過）正是 7 月起上市成交量停在 15:30 初值的原因。
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:daredevil/core/constants/market_codes.dart';
import 'package:daredevil/core/constants/market_dataset.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/data/remote/finmind_client.dart';
import 'package:daredevil/data/remote/tpex_client.dart';
import 'package:daredevil/data/remote/twse_client.dart';
import 'package:daredevil/data/repositories/market_day_fetch_ledger.dart';
import 'package:daredevil/data/repositories/price_repository.dart';

class MockTwseClient extends Mock implements TwseClient {}

class MockTpexClient extends Mock implements TpexClient {}

class MockFinMindClient extends Mock implements FinMindClient {}

void main() {
  late AppDatabase db;
  late MockTwseClient twse;
  late MockTpexClient tpex;
  late PriceRepository repo;
  final day = DateTime(2026, 9, 24);

  setUpAll(() => registerFallbackValue(DateTime(2026)));

  TwseDailyPrice twsePrice(String code, double volume) => TwseDailyPrice(
    date: day, code: code, name: code, open: 10, high: 10, low: 10,
    close: 10, volume: volume, change: 0,
  );
  TpexDailyPrice tpexPrice(String code, double volume) => TpexDailyPrice(
    date: day, code: code, name: code, open: 10, high: 10, low: 10,
    close: 10, volume: volume, change: 0,
  );

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.upsertStocks([
      for (final s in ['1101', '1102'])
        StockMasterCompanion.insert(symbol: s, name: s, market: MarketCode.twse),
      for (final s in ['3624', '6488'])
        StockMasterCompanion.insert(symbol: s, name: s, market: MarketCode.tpex),
    ]);
    twse = MockTwseClient();
    tpex = MockTpexClient();
    when(() => twse.getAllDailyPrices(date: any(named: 'date'))).thenAnswer(
      (_) async => [twsePrice('1101', 2000), twsePrice('1102', 3000)],
    );
    when(() => tpex.getAllDailyPrices(date: any(named: 'date'))).thenAnswer(
      (_) async => [tpexPrice('3624', 4000), tpexPrice('6488', 5000)],
    );
    repo = PriceRepository(
      database: db,
      finMindClient: MockFinMindClient(),
      twseClient: twse,
      tpexClient: tpex,
    );
  });

  tearDown(() => db.close());

  Future<void> markFinal(String market) => db.upsertMarketDayFetch(
    dataset: MarketDataset.prices.code,
    market: market,
    date: day,
    fetchedAt: DateTime(2026, 9, 25),
    rowCount: 2,
  );

  test('🚨 回歸：已有大量列但未定案 → 仍要重抓', () async {
    // 舊閘門：getPriceCountForDate(day) > fullMarketThreshold(1500) 就跳過。
    // 用其他市場代碼的 1501 檔塞滿列數，才不會改變上市／上櫃的 ledger 門檻。
    // 修改前這條必須紅（舊邏輯會跳過、不打 API）。
    await db.upsertStocks([
      for (var i = 0; i < 1501; i++)
        StockMasterCompanion.insert(
          symbol: 'X$i',
          name: 'X$i',
          market: 'OTHER',
        ),
    ]);
    await db.insertPrices([
      for (var i = 0; i < 1501; i++)
        DailyPriceCompanion.insert(symbol: 'X$i', date: day),
    ]);
    expect(await db.getPriceCountForDate(day), greaterThan(1500));
    await repo.syncAllPricesForDate(day);
    verify(() => twse.getAllDailyPrices(date: any(named: 'date'))).called(1);
    verify(() => tpex.getAllDailyPrices(date: any(named: 'date'))).called(1);
  });

  test('兩市場都已定案 → 跳過、不打 API', () async {
    await markFinal(MarketCode.twse);
    await markFinal(MarketCode.tpex);
    final r = await repo.syncAllPricesForDate(day);
    expect(r.skipped, isTrue);
    verifyNever(() => twse.getAllDailyPrices(date: any(named: 'date')));
  });

  test('只有上市定案 → 仍重抓', () async {
    await markFinal(MarketCode.twse);
    await repo.syncAllPricesForDate(day);
    verify(() => tpex.getAllDailyPrices(date: any(named: 'date'))).called(1);
  });

  test('只有上櫃定案 → 仍重抓（對稱，防止只檢查一個市場）', () async {
    await markFinal(MarketCode.tpex);
    await repo.syncAllPricesForDate(day);
    verify(() => twse.getAllDailyPrices(date: any(named: 'date'))).called(1);
  });

  test('ledger 逐市場記錄實際資料日與列數', () async {
    final ledger = MarketDayFetchLedger(
      database: db,
      fetchedAt: DateTime(2026, 9, 24, 21, 30),
    );
    await repo.syncAllPricesForDate(day, ledger: ledger);
    expect(
      ledger.recorded.map((r) => (r.market, r.date, r.rows)),
      containsAll([(MarketCode.twse, day, 2), (MarketCode.tpex, day, 2)]),
    );
  });

  test('單一市場回空：只記錄有資料的市場', () async {
    when(() => tpex.getAllDailyPrices(date: any(named: 'date')))
        .thenAnswer((_) async => []);
    final ledger = MarketDayFetchLedger(database: db, fetchedAt: day);
    await repo.syncAllPricesForDate(day, ledger: ledger);
    expect(ledger.recorded.map((r) => r.market), [MarketCode.twse]);
  });

  test('寫入價格後重算同日當沖比例', () async {
    await db.insertDayTradingData([
      DayTradingCompanion.insert(
        symbol: '1101',
        date: day,
        dayTradingRatio: const Value(90),
        tradeVolume: const Value(500),
      ),
    ]);
    await repo.syncAllPricesForDate(day);
    final dt = await db.getDayTradingHistory('1101', startDate: day);
    expect(dt.single.dayTradingRatio, 25.0, reason: '500 ÷ 2000 × 100');
  });

  test('回補（backfillTwsePricesByDate）也記錄並重算', () async {
    when(() => twse.getAllDailyPricesHistorical(any())).thenAnswer(
      (_) async => [twsePrice('1101', 2000), twsePrice('1102', 3000)],
    );
    final ledger = MarketDayFetchLedger(database: db, fetchedAt: DateTime(2026, 9, 25));
    await repo.backfillTwsePricesByDate(
      date: day,
      targetSymbols: {'1101', '1102'},
      ledger: ledger,
    );
    expect(ledger.recorded.single.market, MarketCode.twse);
    expect(
      await db.isMarketDayFinal(
        dataset: MarketDataset.prices,
        market: MarketCode.twse,
        date: day,
      ),
      isTrue,
    );
  });
}
```

若 `PriceRepository` 內部以 `TwsePriceSource`／`TpexPriceSource` 包裝 client，確認 mock 的方法名與 source 呼叫的 client 方法一致（`getAllDailyPrices`、`getAllDailyPricesHistorical`）。

- [ ] **Step 2：跑測試，確認失敗**

Run: `flutter test test/data/repositories/price_repository_finality_test.dart`
Expected：編譯失敗（`ledger` 參數不存在）。先讓它能編譯（加參數但不用）再跑一次：「🚨 回歸」測試 FAIL（舊邏輯跳過了），其餘依實作狀態失敗。

- [ ] **Step 3：實作**

`lib/data/repositories/price_repository.dart` 的 `syncAllPricesForDate`：

1. 簽章加 `MarketDayFetchLedger? ledger`。
2. 把

```dart
      if (!force) {
        final existingCount = await _db.getPriceCountForDate(normalizedDate);
        if (existingCount > DataFreshness.fullMarketThreshold) {
```

到該 `if (!force) { ... }` 區塊結尾的整段，換成

```dart
      // 定案才跳過（spec §4.5(a)）。舊邏輯用「列數 > 門檻」，但 15:30 抓到的
      // 是未含鉅額交易的初值，列數夠不代表數值已定案。當天的資料在當天不會
      // 定案，所以交易日當天實際上每次都抓。
      if (!force &&
          await _db.isMarketDayFinal(
            dataset: MarketDataset.prices,
            market: MarketCode.twse,
            date: normalizedDate,
          ) &&
          await _db.isMarketDayFinal(
            dataset: MarketDataset.prices,
            market: MarketCode.tpex,
            date: normalizedDate,
          )) {
        final existingCount = await _db.getPriceCountForDate(normalizedDate);
        final candidates = await quickFilterCandidatesFromDb(
          _db,
          normalizedDate,
        );
        AppLogger.info(
          'PriceRepo',
          '價格同步: $existingCount 筆 (${DateContext.formatYmd(normalizedDate)}, 已定案)',
        );
        return MarketSyncResult(
          count: existingCount,
          candidates: candidates,
          dataDate: normalizedDate,
          skipped: true,
        );
      }
```

3. 把

```dart
      if (allStockEntries.isNotEmpty) {
        await _db.upsertStocks(allStockEntries);
      }
      await _db.insertPrices(allPriceEntries);
```

換成

```dart
      // 資料、當沖比例重算、抓取狀態在同一個 transaction：App 與 launchd
      // 並行時，最後寫入者的資料與狀態一致
      await _db.transaction<void>(() async {
        if (allStockEntries.isNotEmpty) {
          await _db.upsertStocks(allStockEntries);
        }
        await _db.insertPrices(allPriceEntries);
        await _afterMarketDayWrite(
          market: MarketCode.twse,
          entries: twseResult.priceEntries,
          ledger: ledger,
        );
        await _afterMarketDayWrite(
          market: MarketCode.tpex,
          entries: tpexResult.priceEntries,
          ledger: ledger,
        );
      });
```

4. 新增私有方法：

```dart
  /// 全市場價格寫入後：重算同日當沖比例（成交量可能被更正），並向 ledger
  /// 回報實際寫入的資料日與列數。[entries] 為空（該市場抓取失敗）時不動作。
  Future<void> _afterMarketDayWrite({
    required String market,
    required List<DailyPriceCompanion> entries,
    required MarketDayFetchLedger? ledger,
  }) async {
    if (entries.isEmpty) return;
    final day = DateContext.normalize(entries.first.date.value);
    await _db.recomputeDayTradingRatios(
      day: day,
      symbols: {for (final e in entries) e.symbol.value},
    );
    await ledger?.report(
      dataset: MarketDataset.prices,
      market: market,
      date: day,
      rows: entries.length,
    );
  }
```

5. `backfillTwsePricesByDate`／`backfillTpexPricesByDate` 簽章加 `MarketDayFetchLedger? ledger`，把 `await _db.insertPrices(filtered);` 換成：

```dart
      await _db.transaction<void>(() async {
        await _db.insertPrices(filtered);
        await _afterMarketDayWrite(
          market: MarketCode.twse, // TPEx 版本用 MarketCode.tpex
          entries: filtered,
          ledger: ledger,
        );
      });
```

6. import `market_dataset.dart`、`market_day_fetch_ledger.dart`。`DataFreshness` 若只剩這裡用、改完變成未使用，就移除 import（`flutter analyze` 會提示）。

`lib/domain/repositories/price_repository.dart`：三個方法的介面簽章同步加 `MarketDayFetchLedger? ledger`。

`lib/domain/services/update/historical_price_syncer.dart`：`syncHistoricalPrices` 加 `MarketDayFetchLedger? ledger` 並傳給 `_syncMissingMarketDays(date: date, onProgress: ..., ledger: ledger)`；Phase 0 兩個 `backfill*PricesByDate` 呼叫加 `ledger: ledger`（Phase 0 的 targetSymbols 是該市場全部股票，屬全市場抓取）。

- [ ] **Step 4：跑測試，確認通過**

`test/data/repositories/price_repository_test.dart` 用 `MockAppDatabase`，setUp 補：

```dart
    when(
      () => mockDb.isMarketDayFinal(
        dataset: any(named: 'dataset'),
        market: any(named: 'market'),
        date: any(named: 'date'),
      ),
    ).thenAnswer((_) async => false);
    when(
      () => mockDb.recomputeDayTradingRatios(
        day: any(named: 'day'),
        symbols: any(named: 'symbols'),
      ),
    ).thenAnswer((_) async => 0);
    when(() => mockDb.transaction<void>(any())).thenAnswer((inv) async {
      await (inv.positionalArguments[0] as Future<void> Function())();
    });
```

`setUpAll` 補 `registerFallbackValue(MarketDataset.prices);` 與 `registerFallbackValue(<String>{});`。

Run: `flutter test test/data/repositories/price_repository_finality_test.dart test/data/repositories/price_repository_test.dart test/domain/services/update/historical_price_syncer_test.dart test/domain/services/update_service_test.dart`
Expected：全部 PASS（`update_service_test` 在本 Task 還不傳 ledger，stub 不受影響；它的 stub 在 Task 11 才要改）。既有測試若因「列數夠就跳過」的舊語意而紅，改測試前先確認它斷言的是**舊的錯誤行為**（例如「有 1600 列就不打 API」），再依新語意改寫（先把兩市場 `isMarketDayFinal` stub 成 true，再斷言跳過），並在 ledger 記 `Ruling:`。

- [ ] **Step 5：mutation 自驗**：分別拿掉上市、上櫃的 `isMarketDayFinal` 條件，對應的「只有上市／上櫃定案 → 仍重抓」要紅；拿掉 `_afterMarketDayWrite` 內的 `recomputeDayTradingRatios`，重算測試要紅。

---

## Task 8：法人路徑接上定案判斷

spec §4.5(a)、§4.5 覆寫語意。

**Files:**
- Modify: `lib/data/repositories/institutional_repository.dart`
- Modify: `lib/domain/repositories/institutional_repository.dart`
- Modify: `lib/data/database/dao/institutional_dao.dart`（新增 `deleteInstitutionalRows`）
- Modify: `lib/core/constants/api_config.dart`（新增 `institutionalZeroDeleteMaxRatio = 0.1`，放在 Task 1 新增的「盤後資料定案」區段內，說明：法人全 0 刪列的安全閥；106 個交易日實測上市最高 2.4%、上櫃平均 2.7%、最高 5.5%）
- Modify: `test/data/repositories/institutional_repository_test.dart`（MockAppDatabase 補 stub）
- Modify: `lib/domain/services/update/institutional_syncer.dart`
- Test: `test/data/repositories/institutional_finality_test.dart`
- Modify: `test/domain/services/update/institutional_syncer_test.dart`

**Interfaces:**
- Produces:
  - `IInstitutionalRepository.syncAllMarketInstitutional(DateTime date, {bool force = false, MarketDayFetchLedger? ledger})`
  - `IInstitutionalRepository.isDayFinal(DateTime date) → Future<bool>`（兩市場都定案才 true）
  - `InstitutionalSyncer.syncInstitutionalData({..., MarketDayFetchLedger? ledger})`
  - `AppDatabase.deleteInstitutionalRows({required DateTime day, required Set<String> symbols}) → Future<int>`

- [ ] **Step 1：寫失敗測試**

`test/data/repositories/institutional_finality_test.dart`：

```dart
import 'package:drift/drift.dart' show Value, Variable;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:daredevil/core/constants/market_codes.dart';
import 'package:daredevil/core/constants/market_dataset.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/data/remote/finmind_client.dart';
import 'package:daredevil/data/remote/tpex_client.dart';
import 'package:daredevil/data/remote/twse_client.dart';
import 'package:daredevil/data/repositories/institutional_repository.dart';
import 'package:daredevil/data/repositories/market_day_fetch_ledger.dart';

class MockTwseClient extends Mock implements TwseClient {}

class MockTpexClient extends Mock implements TpexClient {}

class MockFinMindClient extends Mock implements FinMindClient {}

void main() {
  late AppDatabase db;
  late MockTwseClient twse;
  late MockTpexClient tpex;
  late InstitutionalRepository repo;
  final day = DateTime(2026, 7, 17);

  TwseInstitutional twseRow(String code, double foreign) => TwseInstitutional(
    date: day, code: code, name: code, foreignBuy: 0, foreignSell: 0,
    foreignNet: foreign, investmentTrustBuy: 0, investmentTrustSell: 0,
    investmentTrustNet: 0, dealerBuy: 0, dealerSell: 0, dealerNet: 0,
    totalNet: foreign,
  );
  TpexInstitutional tpexRow(String code, double foreign) => TpexInstitutional(
    date: day, code: code, name: code, foreignBuy: 0, foreignSell: 0,
    foreignNet: foreign, investmentTrustBuy: 0, investmentTrustSell: 0,
    investmentTrustNet: 0, dealerBuy: 0, dealerSell: 0, dealerNet: 0,
    totalNet: foreign,
  );

  setUpAll(() => registerFallbackValue(DateTime(2026)));

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.upsertStocks([
      for (final s in ['1101', '1102'])
        StockMasterCompanion.insert(symbol: s, name: s, market: MarketCode.twse),
      for (final s in ['3624', '6488'])
        StockMasterCompanion.insert(symbol: s, name: s, market: MarketCode.tpex),
      // 已下市（is_active=false）
      StockMasterCompanion.insert(
        symbol: '9999', name: '下市股', market: MarketCode.twse,
        isActive: const Value(false),
      ),
    ]);
    twse = MockTwseClient();
    tpex = MockTpexClient();
    repo = InstitutionalRepository(
      database: db,
      finMindClient: MockFinMindClient(),
      twseClient: twse,
      tpexClient: tpex,
    );
  });

  tearDown(() => db.close());

  Future<void> seedPrelim(String symbol, double foreign) =>
      db.insertInstitutionalData([
        DailyInstitutionalCompanion.insert(
          symbol: symbol,
          date: day,
          foreignNet: Value(foreign),
          investmentTrustNet: const Value(0),
          dealerNet: const Value(0),
        ),
      ]);

  Future<List<String>> symbolsOnDay() async => [
    for (final r in await db.customSelect(
      'SELECT symbol FROM daily_institutional WHERE date >= ? AND date < ?',
      variables: [
        Variable.withDateTime(day),
        Variable.withDateTime(DateTime(day.year, day.month, day.day + 1)),
      ],
    ).get())
      r.read<String>('symbol'),
  ];

  void stubBoth(List<TwseInstitutional> t, List<TpexInstitutional> p) {
    when(() => twse.getAllInstitutionalData(date: any(named: 'date')))
        .thenAnswer((_) async => t);
    when(() => tpex.getAllInstitutionalData(date: any(named: 'date')))
        .thenAnswer((_) async => p);
  }

  /// 補滿回應列數：全 0 比例要低於安全閥（10%）才會刪。填充代號不在
  /// stock_master，寫入時被濾掉，不影響其他斷言
  List<TwseInstitutional> padTwse(List<TwseInstitutional> rows) => [
    ...rows,
    for (var i = 0; i < 20; i++) twseRow('P$i', 100),
  ];

  test('定案回應明確列出且全 0 → 刪除該股的初值列', () async {
    await seedPrelim('1101', 3000000);
    stubBoth(padTwse([twseRow('1101', 0), twseRow('1102', 500)]), [tpexRow('3624', 100), tpexRow('6488', 200)]);
    await repo.syncAllMarketInstitutional(day, force: true);
    expect(await symbolsOnDay(), isNot(contains('1101')));
    expect(await symbolsOnDay(), containsAll(['1102', '3624', '6488']));
  });

  test('回應裡沒有的代號（含下市股）舊列不動', () async {
    await seedPrelim('9999', 100);
    await seedPrelim('1101', 100);
    stubBoth([twseRow('1102', 500)], [tpexRow('3624', 100), tpexRow('6488', 200)]);
    await repo.syncAllMarketInstitutional(day, force: true);
    expect(await symbolsOnDay(), containsAll(['9999', '1101']));
  });

  test('🚨 安全閥：全 0 比例異常（整個市場都是 0）→ 不刪舊列', () async {
    await seedPrelim('1101', 100);
    await seedPrelim('1102', 100);
    stubBoth([twseRow('1101', 0), twseRow('1102', 0)], []);
    await repo.syncAllMarketInstitutional(day, force: true);
    expect(await symbolsOnDay(), containsAll(['1101', '1102']),
        reason: '欄位改版讓 parser 全部退成 0 時，不可整批刪掉');
  });

  test('DB 不寫入全 0 列', () async {
    stubBoth(padTwse([twseRow('1101', 0), twseRow('1102', 500)]), []);
    await repo.syncAllMarketInstitutional(day, force: true);
    expect(await symbolsOnDay(), isNot(contains('1101')));
  });

  test('單邊失敗（回空）：另一市場照常寫入與記錄，失敗那邊不記錄、也不刪列', () async {
    await seedPrelim('3624', 100);
    stubBoth([twseRow('1101', 100), twseRow('1102', 500)], []);
    final ledger = MarketDayFetchLedger(database: db, fetchedAt: DateTime(2026, 7, 18));
    await repo.syncAllMarketInstitutional(day, force: true, ledger: ledger);
    expect(ledger.recorded.map((r) => r.market), [MarketCode.twse]);
    expect(await symbolsOnDay(), contains('3624'));
  });

  test('isDayFinal：兩市場都定案才 true', () async {
    Future<void> mark(String m) => db.upsertMarketDayFetch(
      dataset: MarketDataset.institutional.code, market: m, date: day,
      fetchedAt: DateTime(2026, 7, 18), rowCount: 2,
    );
    await mark(MarketCode.tpex);
    expect(await repo.isDayFinal(day), isFalse, reason: '只有上櫃定案');
    await db.customStatement('DELETE FROM market_day_fetch');
    await mark(MarketCode.twse);
    expect(await repo.isDayFinal(day), isFalse, reason: '只有上市定案');
    await mark(MarketCode.tpex);
    expect(await repo.isDayFinal(day), isTrue);
  });
}
```

`symbolsOnDay()` 刻意寫在測試檔內，不為測試在 lib 新增查詢。

- [ ] **Step 2：跑測試，確認失敗**

Run: `flutter test test/data/repositories/institutional_finality_test.dart`
Expected：編譯失敗（`isDayFinal`、`ledger` 不存在）。

- [ ] **Step 3：實作**

`institutional_dao.dart` 新增：

```dart
  /// 刪除 [day] 當天指定代號的法人列（整天範圍，涵蓋變體時間戳）
  ///
  /// 給「定案回應明確列出、但三法人淨額全為 0」的代號用：DB 不存全 0 列，
  /// 讀取端把「沒有列」當成 0，所以初值非 0 的舊列必須刪掉。
  Future<int> deleteInstitutionalRows({
    required DateTime day,
    required Set<String> symbols,
  }) {
    if (symbols.isEmpty) return Future.value(0);
    final start = DateTime(day.year, day.month, day.day);
    final end = DateTime(day.year, day.month, day.day + 1);
    return (delete(dailyInstitutional)..where(
          (t) =>
              t.date.isBiggerOrEqualValue(start) &
              t.date.isSmallerThanValue(end) &
              t.symbol.isIn(symbols),
        ))
        .go();
  }
```

`institutional_repository.dart` 檔頭補 import：`core/constants/api_config.dart`、`core/constants/market_codes.dart`、`core/constants/market_dataset.dart`、`data/repositories/market_day_fetch_ledger.dart`（已有的就略過）。`institutional_syncer.dart` 補 `data/repositories/market_day_fetch_ledger.dart`。

`institutional_repository.dart` 的 `syncAllMarketInstitutional`：

1. 簽章加 `MarketDayFetchLedger? ledger`。
2. `if (!force) {...}` 閘門保留（回補路徑仍用它判斷完整）。
3. 在兩個 `valid*Data` 過濾之後、組 entries 之前加：

```dart
      // 回應明確列出、但三法人淨額全為 0 的代號（與上方過濾條件互補）
      bool allZero(num total, num foreign, num trust) =>
          total == 0 && foreign == 0 && trust == 0;
      // 安全閥：parser 對解析不出的數字會退成 0（欄位改版時整個市場都會
      // 變成「明確全 0」）。106 個交易日實測：上市最高 2.4%，上櫃平均 2.7%、
      // 最高 5.5%（2026-09 量測）；比例超過門檻就不刪、只記 warning
      Set<String> zeroSetOf(String market, List<({String code, bool zero})> rows) {
        final zeros = {for (final r in rows) if (r.zero) r.code};
        if (rows.isNotEmpty &&
            zeros.length >
                rows.length * ApiConfig.institutionalZeroDeleteMaxRatio) {
          AppLogger.warning(
            'InstitutionalRepo',
            '$market 法人回應 ${zeros.length}/${rows.length} 列三法人全 0，'
                '比例異常（疑似欄位解析失敗），本次不刪舊列',
          );
          return const {};
        }
        return zeros;
      }

      final zeroSymbols = {
        ...zeroSetOf(MarketCode.twse, [
          for (final i in twseData)
            (
              code: i.code,
              zero: allZero(i.totalNet, i.foreignNet, i.investmentTrustNet),
            ),
        ]),
        ...zeroSetOf(MarketCode.tpex, [
          for (final i in tpexData)
            (
              code: i.code,
              zero: allZero(i.totalNet, i.foreignNet, i.investmentTrustNet),
            ),
        ]),
      };
```

4. 把 `await _db.insertInstitutionalData(allEntries);` 換成：

```dart
      await _db.transaction<void>(() async {
        // 定案值全 0 的股票：刪掉初值列（DB 不存全 0 列；讀取端把沒有列當 0）
        await _db.deleteInstitutionalRows(day: date, symbols: zeroSymbols);
        await _db.insertInstitutionalData(allEntries);
        // 兩市場各自回報；抓取失敗（回空）那邊的 entries 為空，不回報
        if (twseEntries.isNotEmpty) {
          await ledger?.report(
            dataset: MarketDataset.institutional,
            market: MarketCode.twse,
            date: twseEntries.first.date.value,
            rows: twseEntries.length,
          );
        }
        if (tpexEntries.isNotEmpty) {
          await ledger?.report(
            dataset: MarketDataset.institutional,
            market: MarketCode.tpex,
            date: tpexEntries.first.date.value,
            rows: tpexEntries.length,
          );
        }
      });
```

（`twseEntries`／`tpexEntries` 的元素型別是 `DailyInstitutionalCompanion`，`date.value` 取資料日；若 `_toInstitutionalEntries` 回傳型別不同，依實際型別取日期。）

5. 新增：

```dart
  /// 該日法人兩市場是否都已定案（當日路徑的跳過判斷）
  @override
  Future<bool> isDayFinal(DateTime date) async =>
      await _db.isMarketDayFinal(
        dataset: MarketDataset.institutional,
        market: MarketCode.twse,
        date: date,
      ) &&
      await _db.isMarketDayFinal(
        dataset: MarketDataset.institutional,
        market: MarketCode.tpex,
        date: date,
      );
```

介面 `IInstitutionalRepository` 同步加 `isDayFinal` 與 `ledger` 參數。

`institutional_syncer.dart`：

1. `syncInstitutionalData` 加 `MarketDayFetchLedger? ledger`。
2. 當日段落改成：

```dart
    // 1. 當日：已定案才跳過（spec §4.5(a)）。當天的資料在當天不會定案，
    //    所以交易日當天實際上每次都抓；決定要抓就傳 force: true，讓
    //    repository 內的列數閘門不再二次攔截。
    if (force || !await _isFinal(date)) {
      try {
        await _institutionalRepo.syncAllMarketInstitutional(
          date,
          force: true,
          ledger: ledger,
        );
        syncedDays++;
      } // …catch 區塊不變
    }
```

3. 回補迴圈維持 `_isComplete` 與 `force: false`，只加 `ledger: ledger`（回補多半隔天以後才抓，記下去就是定案）。
4. 新增：

```dart
  /// 定案預檢；查詢失敗視為未定案（fail-open 朝抓取）
  Future<bool> _isFinal(DateTime date) async {
    try {
      return await _institutionalRepo.isDayFinal(date);
    } catch (e) {
      AppLogger.warning('InstitutionalSyncer', '法人定案預檢失敗，視為未定案', e);
      return false;
    }
  }
```

`test/domain/services/update/institutional_syncer_test.dart`：

- setUp 加 `when(() => mockRepo.isDayFinal(any())).thenAnswer((_) async => false);`（syncer 測試不傳 ledger，既有 `syncAllMarketInstitutional(any(), force: any(named: 'force'))` stub 照常命中）。
- 既有測試「日常更新（!force）當日已完整也跳過（同晚二次更新 0 抓取）」（約 :156）在新語意下會紅：當日改看定案，不看列數。改寫成下面兩條，並在 ledger 記 `Ruling:`：

```dart
    test('日常更新（!force）當日已定案才跳過（同晚二次更新、隔天重跑 0 抓取）', () async {
      when(() => mockRepo.isDayComplete(any())).thenAnswer((_) async => true);
      when(() => mockRepo.isDayFinal(any())).thenAnswer((_) async => true);

      final result = await syncer.syncInstitutionalData(
        date: date,
        force: false,
        backfillDays: 4,
      );

      verifyNever(
        () => mockRepo.syncAllMarketInstitutional(
          any(),
          force: any(named: 'force'),
        ),
      );
      expect(result.syncedDays, 0);
    });

    test('🚨 回歸：當日列數已完整但未定案 → 仍以 force: true 重抓', () async {
      // 7/16–8/19 投信欄錯誤的成因：15:30 抓到初值、21:30 因列數夠而跳過
      when(() => mockRepo.isDayComplete(any())).thenAnswer((_) async => true);

      await syncer.syncInstitutionalData(
        date: date,
        force: false,
        backfillDays: 4,
      );

      verify(
        () => mockRepo.syncAllMarketInstitutional(date, force: true),
      ).called(1);
    });
```

`test/data/repositories/institutional_repository_test.dart` 用 `MockAppDatabase`：setUp 補 `transaction<void>` stub（見 Global Constraints）與 `when(() => mockDb.deleteInstitutionalRows(day: any(named: 'day'), symbols: any(named: 'symbols'))).thenAnswer((_) async => 0);`，`setUpAll` 補 `registerFallbackValue(<String>{});`。

- [ ] **Step 4：跑測試，確認通過**

Run: `flutter test test/data/repositories/institutional_finality_test.dart test/data/repositories/institutional_repository_test.dart test/domain/services/update/institutional_syncer_test.dart test/domain/services/update/institutional_no_activity_fill_test.dart`
Expected：全部 PASS。

- [ ] **Step 5：mutation 自驗**：拿掉安全閥判斷（「安全閥」測試紅）；`isDayFinal` 只留一個市場的條件（對稱斷言紅）；拿掉 `deleteInstitutionalRows` 呼叫（刪列測試紅）；把 `zeroSymbols` 改成「DB 有、回應沒有的代號」（下市股測試紅）；syncer 的 `_isFinal` 換回 `_isComplete`（回歸測試紅）。

---

## Task 9：當沖、融資券、外資持股接上 ledger；上櫃當沖缺漏回補

spec §4.4、§4.5(c)、§4.9。

**Files:**
- Modify: `lib/data/repositories/trading_repository.dart`（`syncAllDayTradingFromTwse`、`syncAllDayTradingFromTpex`、`_persistDayTrading`、`syncAllMarginTrading`、`backfillMarginTradingByDate` 加 `ledger`）
- Modify: `lib/domain/repositories/trading_repository.dart`
- Modify: `lib/data/repositories/shareholding_repository.dart`（`syncAllMarketShareholding`、`backfillForeignShareholding` 加 `ledger`）
- Modify: `lib/domain/services/update/market_data_updater.dart`（`syncMarketWideData` 加 `ledger` 並往下傳；`_backfillMissingTradingDays` 加上櫃當沖；缺口警告改寫）
- Test: `test/data/repositories/trading_finality_ledger_test.dart`
- Modify: `test/domain/services/update/trading_backfill_test.dart`

**Interfaces:**
- Produces:
  - `syncAllDayTradingFromTwse({DateTime? date, bool force = false, MarketDayFetchLedger? ledger})`
  - `syncAllDayTradingFromTpex({DateTime? date, bool force = false, MarketDayFetchLedger? ledger})`
  - `syncAllMarginTrading({DateTime? date, bool force = false, MarketDayFetchLedger? ledger})`
  - `backfillMarginTradingByDate({required DateTime date, required Set<String> markets, MarketDayFetchLedger? ledger})`
  - `ShareholdingRepository.syncAllMarketShareholding({required DateTime date, bool force = false, MarketDayFetchLedger? ledger})`
  - `ShareholdingRepository.backfillForeignShareholding({required DateTime asOf, int days = 5, MarketDayFetchLedger? ledger})`
  - `MarketDataUpdater.syncMarketWideData({required DateTime date, bool force = false, MarketDayFetchLedger? ledger})`

- [ ] **Step 1：寫失敗測試**

`test/data/repositories/trading_finality_ledger_test.dart`：

```dart
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:daredevil/core/constants/market_codes.dart';
import 'package:daredevil/core/constants/market_dataset.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/data/remote/tpex_client.dart';
import 'package:daredevil/data/remote/twse_client.dart';
import 'package:daredevil/data/repositories/market_day_fetch_ledger.dart';
import 'package:daredevil/data/repositories/trading_repository.dart';

class MockTwseClient extends Mock implements TwseClient {}

class MockTpexClient extends Mock implements TpexClient {}

void main() {
  late AppDatabase db;
  late MockTwseClient twse;
  late MockTpexClient tpex;
  late TradingRepository repo;
  final day = DateTime(2026, 9, 24);
  final prevDay = DateTime(2026, 9, 23);

  TwseMarginTrading twseMargin(String code, DateTime d) => TwseMarginTrading(
    date: d, code: code, name: code, marginBuy: 1, marginSell: 1,
    marginBalance: 10, shortBuy: 0, shortSell: 0, shortBalance: 0,
  );
  TpexMarginTrading tpexMargin(String code, DateTime d) => TpexMarginTrading(
    date: d, code: code, name: code, marginBuy: 1, marginSell: 1,
    marginBalance: 10, shortBuy: 0, shortSell: 0, shortBalance: 0,
  );

  setUpAll(() => registerFallbackValue(DateTime(2026)));

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.upsertStocks([
      for (final s in ['1101', '1102'])
        StockMasterCompanion.insert(symbol: s, name: s, market: MarketCode.twse),
      for (final s in ['3624', '6488'])
        StockMasterCompanion.insert(symbol: s, name: s, market: MarketCode.tpex),
    ]);
    twse = MockTwseClient();
    tpex = MockTpexClient();
    repo = TradingRepository(database: db, twseClient: twse, tpexClient: tpex);
  });

  tearDown(() => db.close());

  test('上市當沖：寫入後回報 (dayTrading, TWSE, 資料日, 列數)', () async {
    await db.insertPrices([
      for (final s in ['1101', '1102'])
        DailyPriceCompanion.insert(symbol: s, date: day, volume: const Value(1000)),
    ]);
    when(() => twse.getAllDayTradingData(date: any(named: 'date'))).thenAnswer(
      (_) async => [
        for (final s in ['1101', '1102'])
          TwseDayTrading(
            date: day, code: s, name: s, buyVolume: 1, sellVolume: 1,
            totalVolume: 100,
          ),
      ],
    );
    final ledger = MarketDayFetchLedger(database: db, fetchedAt: DateTime(2026, 9, 25));
    await repo.syncAllDayTradingFromTwse(date: day, force: true, ledger: ledger);
    final r = ledger.recorded.single;
    expect((r.dataset, r.market, r.date, r.rows),
        (MarketDataset.dayTrading, MarketCode.twse, day, 2));
  });

  test('融資券（每日，不帶日期）：兩市場回應日期不同時各自以回應日期回報', () async {
    when(() => twse.getAllMarginTradingData(date: any(named: 'date'))).thenAnswer(
      (_) async => [twseMargin('1101', day), twseMargin('1102', day)],
    );
    when(() => tpex.getAllMarginTradingData(date: any(named: 'date'))).thenAnswer(
      (_) async => [tpexMargin('3624', prevDay), tpexMargin('6488', prevDay)],
    );
    final ledger = MarketDayFetchLedger(
      database: db,
      fetchedAt: DateTime(2026, 9, 24, 15, 30),
    );
    await repo.syncAllMarginTrading(date: day, force: true, ledger: ledger);
    expect(
      ledger.recorded.map((r) => (r.market, r.date)),
      unorderedEquals([(MarketCode.twse, day), (MarketCode.tpex, prevDay)]),
    );
  });

  test('融資券回補：只回報有抓的市場', () async {
    when(() => tpex.getAllMarginTradingData(date: any(named: 'date'))).thenAnswer(
      (_) async => [tpexMargin('3624', prevDay), tpexMargin('6488', prevDay)],
    );
    final ledger = MarketDayFetchLedger(database: db, fetchedAt: day);
    await repo.backfillMarginTradingByDate(
      date: prevDay,
      markets: {MarketCode.tpex},
      ledger: ledger,
    );
    expect(ledger.recorded.map((r) => r.market), [MarketCode.tpex]);
    verifyNever(() => twse.getAllMarginTradingData(date: any(named: 'date')));
  });
}
```

`test/data/repositories/foreign_shareholding_market_wide_test.dart` 末端新增（沿用該檔的 `db`、`twse`、`repo`、`row()`、`date`）：

```dart
  test('寫入後回報 (foreignShareholding, TWSE, 請求日, 列數)', () async {
    when(
      () => twse.getAllForeignShareholding(date: any(named: 'date')),
    ).thenAnswer((_) async => [row('2330', 69.17), row('2317', 40.69)]);
    final ledger = MarketDayFetchLedger(
      database: db,
      fetchedAt: DateTime(2026, 8, 15),
    );
    final n = await repo.syncAllMarketShareholding(date: date, ledger: ledger);
    final r = ledger.recorded.single;
    expect(
      (r.dataset, r.market, r.rows),
      (MarketDataset.foreignShareholding, MarketCode.twse, n),
    );
    expect(DateContext.isSameDay(r.date, date), isTrue);
  });
```

該檔需補 import：`market_codes.dart`、`market_dataset.dart`、`date_context.dart`、`market_day_fetch_ledger.dart`。

`test/domain/services/update/trading_backfill_test.dart`（沿用該檔的 `mockDb`、`mockTradingRepo`、`updater`、`today`＝7/14、`d13`、`stubCoverage`；上櫃門檻 `tpexThreshold`＝400、價格預設 900）：

1. `stubTodaySync` 裡 `syncAllDayTradingFromTpex(force: any(named: 'force'))` 改成 `syncAllDayTradingFromTpex(date: any(named: 'date'), force: any(named: 'force'), ledger: any(named: 'ledger'))`，**回傳值維持 0**（改成非 0 會讓 `stubCoverage` 不分市場的既有測試，約 :378、:505，變紅）。同檔其他對 `syncAllDayTradingFromTwse`、`backfillMarginTradingByDate` 的 stub 也補 `ledger: any(named: 'ledger')`（updater 回補時會傳 ledger 過去；本檔呼叫 `syncMarketWideData` 不帶 ledger，傳下去是 null，但補上較不脆弱）。
2. 在 `group('syncMarketWideData — 缺漏日回補', ...)` 內新增（第一條在測試內把上櫃回補的回傳值 stub 成 700）：

```dart
    test('上櫃當沖缺漏日：價格覆蓋達標時以官方端點帶日期回補', () async {
      // 只有上櫃 7/13 缺當沖；上市與其他日子都完整
      when(
        () => mockDb.getDayTradingCountForDateAndMarket(any(), any()),
      ).thenAnswer((inv) async {
        final d = inv.positionalArguments[0] as DateTime;
        final m = inv.positionalArguments[1] as String;
        return (m == MarketCode.tpex && d == d13)
            ? 0
            : DataFreshness.twseBatchThreshold + 1;
      });
      when(
        () => mockTradingRepo.syncAllDayTradingFromTpex(
          date: d13,
          force: true,
          ledger: any(named: 'ledger'),
        ),
      ).thenAnswer((_) async => 700);
      await updater.syncMarketWideData(date: today);
      verify(
        () => mockTradingRepo.syncAllDayTradingFromTpex(
          date: d13,
          force: true,
          ledger: any(named: 'ledger'),
        ),
      ).called(1);
    });

    test('上櫃當沖缺漏日：價格覆蓋不足時不回補', () async {
      // stubCoverage 會重設當沖計數 stub，所以先呼叫它、再覆寫當沖計數
      stubCoverage(priceCounts: {d13: tpexThreshold - 1});
      when(
        () => mockDb.getDayTradingCountForDateAndMarket(any(), any()),
      ).thenAnswer((inv) async {
        final d = inv.positionalArguments[0] as DateTime;
        final m = inv.positionalArguments[1] as String;
        return (m == MarketCode.tpex && d == d13)
            ? 0
            : DataFreshness.twseBatchThreshold + 1;
      });
      await updater.syncMarketWideData(date: today);
      verifyNever(
        () => mockTradingRepo.syncAllDayTradingFromTpex(
          date: d13,
          force: any(named: 'force'),
          ledger: any(named: 'ledger'),
        ),
      );
    });
```

第二條的對照是第一條：兩條只差 7/13 的價格覆蓋，第一條會回補、第二條不會。

- [ ] **Step 2：跑測試，確認失敗**

Run: `flutter test test/data/repositories/trading_finality_ledger_test.dart test/domain/services/update/trading_backfill_test.dart test/data/repositories/foreign_shareholding_market_wide_test.dart`
Expected：編譯失敗（`ledger` 參數不存在）。

- [ ] **Step 3：實作 repository**

`_persistDayTrading` 加 `MarketDayFetchLedger? ledger`，把 transaction 改成：

```dart
    await _db.transaction<void>(() async {
      await _db.deleteDayTradingForDateRange(
        deleteStart,
        deleteEnd,
        market: market,
        batchSymbols: {for (final e in entries) e.symbol.value},
      );
      await _db.insertDayTradingData(entries);
      await ledger?.report(
        dataset: MarketDataset.dayTrading,
        market: market,
        date: dataDate,
        rows: entries.length,
      );
    });
```

`syncAllDayTradingFromTwse`、`syncAllDayTradingFromTpex` 加 `ledger` 並傳給 `_persistDayTrading`。

`syncAllMarginTrading` 加 `ledger`，把寫入改成：

```dart
      await _db.transaction<void>(() async {
        await _db.insertMarginTradingData(allEntries);
        // 不帶日期請求：兩市場可能回不同日期，各自以回應日期回報
        for (final (market, entries) in [
          (MarketCode.twse, twseEntries),
          (MarketCode.tpex, tpexEntries),
        ]) {
          if (entries.isEmpty) continue;
          await ledger?.report(
            dataset: MarketDataset.margin,
            market: market,
            date: entries.first.date.value,
            rows: entries.length,
          );
        }
      });
```

`backfillMarginTradingByDate` 加 `ledger`，transaction 內在 insert 後同樣逐市場回報（`date` 用 `targetDate`）。

`shareholding_repository.dart`：`syncAllMarketShareholding` 加 `ledger`，`await _db.insertShareholdingData(entries);` 換成

```dart
      await _db.transaction<void>(() async {
        await _db.insertShareholdingData(entries);
        await ledger?.report(
          dataset: MarketDataset.foreignShareholding,
          market: MarketCode.twse,
          date: targetDate,
          rows: entries.length,
        );
      });
```

`backfillForeignShareholding` 加 `ledger` 並傳給 `syncAllMarketShareholding(date: day, ledger: ledger)`。

介面 `ITradingRepository` 同步所有簽章。

- [ ] **Step 4：實作 MarketDataUpdater**

1. `syncMarketWideData` 加 `MarketDayFetchLedger? ledger`，傳給 `syncAllDayTradingFromTwse`、`syncAllDayTradingFromTpex`（不帶日期、取最新）、`syncAllMarginTrading`、`syncAllMarketShareholding`、`backfillForeignShareholding`、`_backfillMissingTradingDays(date, ledger)`。
2. `_backfillMissingTradingDays` 加 `ledger` 參數，並新增上櫃當沖來源：

```dart
    const srcTpexDayTrading = 'tpexDayTrading';
    // …迴圈內，在「當沖（上市）」段落之後：

      // 當沖（上櫃）：端點帶 date 可取歷史（2026-09-26 實測）。與上市同樣
      // 要求該日上櫃價格覆蓋達門檻，否則比例整片是 0
      var canBackfillTpexDayTrading = false;
      if (!dead.contains(srcTpexDayTrading) &&
          tpexStocks > 0 &&
          countOf(dayTradingCounts, day, MarketCode.tpex) <=
              DataFreshness.twseBatchThreshold) {
        canBackfillTpexDayTrading =
            countOf(priceCounts, day, MarketCode.tpex) >= tpexThreshold;
      }
```

`if (!canBackfillDayTrading && missingMarkets.isEmpty) continue;` 改成 `if (!canBackfillDayTrading && !canBackfillTpexDayTrading && missingMarkets.isEmpty) continue;`。在上市當沖回補區塊之後加：

```dart
      if (canBackfillTpexDayTrading) {
        var rows = 0;
        try {
          rows = await _tradingRepo.syncAllDayTradingFromTpex(
            date: day,
            force: true,
            ledger: ledger,
          );
        } on RateLimitException {
          rethrow;
        } on NetworkException {
          rethrow;
        } on Exception catch (e) {
          AppLogger.warning(
            'MarketDataUpdater',
            '上櫃當沖回補失敗 ${DateContext.formatYmd(day)}',
            e,
          );
        }
        final progressed = rows > DataFreshness.twseBatchThreshold;
        recordAttempt(srcTpexDayTrading, progressed: progressed);
        dayProgressed |= progressed;
      }
```

上市當沖回補與融資券回補呼叫加 `ledger: ledger`。

3. 上櫃當沖缺口偵測區塊**搬到** `_backfillMissingTradingDays` 之後，警告文字改成：

```dart
          '上櫃當沖回補後仍缺 ${gaps.length} 個交易日'
              '（最近: ${DateContext.formatYmd(gaps.last)}）；價格覆蓋不足的日子'
              '會等價格補齊後再回補',
```

並刪掉該區塊上方「端點只給最新交易日，漏一天就永久少一天」「刻意只偵測不自動補」的說明，改成一句「回補後仍缺的日子計入摘要」。方法說明中「當沖（僅上市，上櫃無全市場快照端點）」改成「當沖（兩市場，各自要求價格覆蓋達門檻）」。

- [ ] **Step 5：跑測試，確認通過**

Run: `flutter test test/data/repositories/ test/domain/services/update/`
Expected：全部 PASS。stub 對不上時補 `ledger: any(named: 'ledger')`。

- [ ] **Step 6：mutation 自驗**：拿掉上櫃當沖回補的價格覆蓋條件（「覆蓋不足時不回補」要紅）；融資券回報改用 `targetDate`（「兩市場回應日期不同」要紅）。

---

## Task 10：MarketDayRefetcher（重抓未定案日）

spec §4.5(b)。

**Files:**
- Create: `lib/domain/services/update/market_day_refetcher.dart`
- Test: `test/domain/services/update/market_day_refetcher_test.dart`

**Interfaces:**
- Consumes: Task 1、2、7、8、9 的簽章
- Produces:

```dart
List<DateTime> refetchCandidateDays({required DateTime today, required DateTime trackingSince});
Map<FinalityGroup, List<DateTime>> selectRefetchDays({
  required List<DateTime> candidateDays,
  required List<MarketDayFetchEntry> fetches,
  required int maxPerGroup,
});
class RefetchSummary { … String toLogLine(); bool get rateLimited; Object? rateLimitError; List<String> errors; List<String> staleOutOfWindow; }
class MarketDayRefetcher {
  MarketDayRefetcher({required AppDatabase database, required IPriceRepository priceRepository, IInstitutionalRepository? institutionalRepository, ITradingRepository? tradingRepository, ShareholdingRepository? shareholdingRepository, Duration callDelay});
  static const String trackingSinceKey = 'finality_tracking_since';
  Future<RefetchSummary> refetchPending({required DateTime today, required MarketDayFetchLedger ledger});
  Future<RefetchSummary> refetchRange({required MarketDataset dataset, required String market, required DateTime from, required DateTime to, required MarketDayFetchLedger ledger});
}
```

- [ ] **Step 1：寫純函式的失敗測試**

`test/domain/services/update/market_day_refetcher_test.dart` 第一部分：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:daredevil/core/constants/market_codes.dart';
import 'package:daredevil/core/constants/market_dataset.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/domain/services/update/market_day_refetcher.dart';

void main() {
  group('refetchCandidateDays', () {
    test('早於今天、不早於追蹤起始日、只含交易日，新→舊', () {
      final days = refetchCandidateDays(
        today: DateTime(2026, 9, 29, 15, 30),
        trackingSince: DateTime(2026, 9, 23),
      );
      // 9/25 中秋、9/26–27 週末、9/28 教師節
      expect(days, [DateTime(2026, 9, 24), DateTime(2026, 9, 23)]);
    });

    test('追蹤起始日早於 40 日曆天窗時以窗口為界', () {
      final days = refetchCandidateDays(
        today: DateTime(2026, 9, 29),
        trackingSince: DateTime(2026, 1, 1),
      );
      expect(days.last.isBefore(DateTime(2026, 8, 20)), isFalse);
    });

    test('第一次執行（起始日＝今天）沒有候選日', () {
      expect(
        refetchCandidateDays(
          today: DateTime(2026, 9, 29),
          trackingSince: DateTime(2026, 9, 29),
        ),
        isEmpty,
      );
    });
  });

  group('selectRefetchDays', () {
    MarketDayFetchEntry fetch(MarketDataset ds, String m, DateTime d, DateTime at) =>
        MarketDayFetchEntry(dataset: ds.code, market: m, date: d, fetchedAt: at, rowCount: 1);

    final d1 = DateTime(2026, 9, 24);
    final d2 = DateTime(2026, 9, 23);

    test('沒有狀態列或未定案的日子入選；已定案的不入選', () {
      final plan = selectRefetchDays(
        candidateDays: [d1, d2],
        fetches: [
          fetch(MarketDataset.prices, MarketCode.twse, d1, DateTime(2026, 9, 24, 21, 30)),
          fetch(MarketDataset.prices, MarketCode.twse, d2, DateTime(2026, 9, 24, 15, 30)),
        ],
        maxPerGroup: 10,
      );
      expect(plan[(dataset: MarketDataset.prices, market: MarketCode.twse)], [d1]);
      expect(plan[(dataset: MarketDataset.prices, market: MarketCode.tpex)], [d1, d2]);
    });

    test('每組最多 maxPerGroup 天（取最新的）', () {
      final plan = selectRefetchDays(
        candidateDays: [d1, d2],
        fetches: const [],
        maxPerGroup: 1,
      );
      expect(plan[(dataset: MarketDataset.margin, market: MarketCode.tpex)], [d1]);
    });

    test('9 組都有計畫（外資持股只有上市）', () {
      final plan = selectRefetchDays(candidateDays: [d1], fetches: const [], maxPerGroup: 10);
      expect(plan.keys, hasLength(9));
      expect(
        plan.containsKey((dataset: MarketDataset.foreignShareholding, market: MarketCode.tpex)),
        isFalse,
      );
    });
  });
}
```

- [ ] **Step 2：跑測試，確認失敗**

Run: `flutter test test/domain/services/update/market_day_refetcher_test.dart`
Expected：編譯失敗。

- [ ] **Step 3：實作純函式與 RefetchSummary**

`lib/domain/services/update/market_day_refetcher.dart`（前半）：

```dart
import 'package:daredevil/core/constants/api_config.dart';
import 'package:daredevil/core/constants/market_codes.dart';
import 'package:daredevil/core/constants/market_dataset.dart';
import 'package:daredevil/core/exceptions/app_exception.dart';
import 'package:daredevil/core/utils/date_context.dart';
import 'package:daredevil/core/utils/logger.dart';
import 'package:daredevil/core/utils/market_day_finality.dart';
import 'package:daredevil/core/utils/taiwan_calendar.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/data/repositories/market_day_fetch_ledger.dart';
import 'package:daredevil/data/repositories/shareholding_repository.dart';
import 'package:daredevil/domain/repositories/institutional_repository.dart';
import 'package:daredevil/domain/repositories/price_repository.dart';
import 'package:daredevil/domain/repositories/trading_repository.dart';

/// 重抓候選日：早於台北今天、不早於追蹤起始日、在回補窗（日曆天）內的
/// 交易日，新→舊。當天的資料交給每日路徑，避免同一輪用歷史端點再抓一次。
List<DateTime> refetchCandidateDays({
  required DateTime today,
  required DateTime trackingSince,
}) {
  final todayDay = DateTime(today.year, today.month, today.day);
  final windowStart = DateTime(
    todayDay.year,
    todayDay.month,
    todayDay.day - ApiConfig.tradingBackfillLookbackDays,
  );
  final since = DateTime(
    trackingSince.year,
    trackingSince.month,
    trackingSince.day,
  );
  final from = since.isAfter(windowStart) ? since : windowStart;
  return [
    for (
      var d = DateTime(todayDay.year, todayDay.month, todayDay.day - 1);
      !d.isBefore(from);
      d = DateTime(d.year, d.month, d.day - 1)
    )
      if (TaiwanCalendar.isTradingDay(d)) d,
  ];
}

String _key(String dataset, String market, DateTime day) =>
    '$dataset|$market|${DateContext.formatYmd(day)}';

/// 每組（資料集, 市場）要重抓的日子：候選日中沒有定案狀態列者（含完全
/// 沒有狀態列），每組最多 [maxPerGroup] 天，取最新的。
Map<FinalityGroup, List<DateTime>> selectRefetchDays({
  required List<DateTime> candidateDays,
  required List<MarketDayFetchEntry> fetches,
  required int maxPerGroup,
}) {
  final fetchedAt = {
    for (final f in fetches) _key(f.dataset, f.market, f.date): f.fetchedAt,
  };
  return {
    for (final g in finalityGroups)
      g: [
        for (final day in candidateDays)
          if (!_isFinal(fetchedAt[_key(g.dataset.code, g.market, day)], day))
            day,
      ].take(maxPerGroup).toList(),
  };
}

bool _isFinal(DateTime? fetchedAt, DateTime day) =>
    fetchedAt != null && isFetchFinal(dataDate: day, fetchedAtTaipei: fetchedAt);

/// 一次重抓的結果（進更新日誌與 UpdateResult）
class RefetchSummary {
  final Map<FinalityGroup, int> attempted = {};
  final Map<FinalityGroup, int> finalized = {};

  /// 超過每輪上限、留給下一輪的天數
  final Map<FinalityGroup, int> deferred = {};
  final List<String> errors = [];

  /// 追蹤起始日以後、已超出回補窗仍未定案的（資料集/市場 日期）
  final List<String> staleOutOfWindow = [];
  Object? rateLimitError;

  bool get rateLimited => rateLimitError != null;

  String toLogLine() {
    final parts = [
      for (final g in finalityGroups)
        if ((attempted[g] ?? 0) > 0 || (deferred[g] ?? 0) > 0)
          '${g.dataset.code}/${g.market} ${finalized[g] ?? 0}/${attempted[g] ?? 0}${(deferred[g] ?? 0) > 0 ? '（剩 ${deferred[g]} 天）' : ''}',
    ];
    return '未定案重抓: ${parts.isEmpty ? '無' : parts.join(', ')}'
        '${errors.isEmpty ? '' : '；失敗 ${errors.length}'}'
        '${rateLimited ? '；限流中止' : ''}';
  }
}
```

- [ ] **Step 4：跑純函式測試，確認通過**

Run: `flutter test test/domain/services/update/market_day_refetcher_test.dart`
Expected：refetchCandidateDays、selectRefetchDays 兩組 PASS。

- [ ] **Step 5：寫執行流程的失敗測試**（同檔新增 group）

```dart
class MockPriceRepository extends Mock implements IPriceRepository {}
class MockInstitutionalRepository extends Mock implements IInstitutionalRepository {}
class MockTradingRepository extends Mock implements ITradingRepository {}
class MockShareholdingRepository extends Mock implements ShareholdingRepository {}

// ↑ 四個 mock 類別放在檔案頂層（main 之外）；檔頭補 import
// api_config.dart、market_day_fetch_ledger.dart、shareholding_repository.dart、app_exception.dart、
// 以及三個 domain repository 介面。

  group('MarketDayRefetcher', () {
    late AppDatabase db;
    late MockPriceRepository price;
    late MockInstitutionalRepository inst;
    late MockTradingRepository trading;
    late MockShareholdingRepository sh;
    late MarketDayRefetcher refetcher;
    late MarketDayFetchLedger ledger;
    final today = DateTime(2026, 9, 29, 15, 30);
    final d = DateTime(2026, 9, 24);
    final calls = <String>[];

    setUpAll(() {
      registerFallbackValue(DateTime(2026));
      registerFallbackValue(<String>{});
    });

    setUp(() async {
      db = AppDatabase.forTesting();
      await db.upsertStocks([
        StockMasterCompanion.insert(symbol: '1101', name: 'a', market: MarketCode.twse),
        StockMasterCompanion.insert(symbol: '3624', name: 'b', market: MarketCode.tpex),
      ]);
      await db.setSetting(MarketDayRefetcher.trackingSinceKey, '2026-09-24');
      price = MockPriceRepository();
      inst = MockInstitutionalRepository();
      trading = MockTradingRepository();
      sh = MockShareholdingRepository();
      calls.clear();
      when(() => price.backfillTwsePricesByDate(date: any(named: 'date'), targetSymbols: any(named: 'targetSymbols'), ledger: any(named: 'ledger')))
          .thenAnswer((_) async { calls.add('prices/TWSE'); return 1; });
      when(() => price.backfillTpexPricesByDate(date: any(named: 'date'), targetSymbols: any(named: 'targetSymbols'), ledger: any(named: 'ledger')))
          .thenAnswer((_) async { calls.add('prices/TPEx'); return 1; });
      when(() => inst.syncAllMarketInstitutional(any(), force: any(named: 'force'), ledger: any(named: 'ledger')))
          .thenAnswer((_) async { calls.add('institutional'); return 1; });
      when(() => trading.syncAllDayTradingFromTwse(date: any(named: 'date'), force: any(named: 'force'), ledger: any(named: 'ledger')))
          .thenAnswer((_) async { calls.add('dayTrading/TWSE'); return 1; });
      when(() => trading.syncAllDayTradingFromTpex(date: any(named: 'date'), force: any(named: 'force'), ledger: any(named: 'ledger')))
          .thenAnswer((_) async { calls.add('dayTrading/TPEx'); return 1; });
      when(() => trading.backfillMarginTradingByDate(date: any(named: 'date'), markets: any(named: 'markets'), ledger: any(named: 'ledger')))
          .thenAnswer((_) async { calls.add('margin'); return (twseRows: 1, tpexRows: 1); });
      when(() => sh.syncAllMarketShareholding(date: any(named: 'date'), force: any(named: 'force'), ledger: any(named: 'ledger')))
          .thenAnswer((_) async { calls.add('foreignShareholding'); return 1; });
      refetcher = MarketDayRefetcher(
        database: db,
        priceRepository: price,
        institutionalRepository: inst,
        tradingRepository: trading,
        shareholdingRepository: sh,
        callDelay: Duration.zero,
      );
      ledger = MarketDayFetchLedger(database: db, fetchedAt: today);
    });

    tearDown(() => db.close());

    test('順序：價格 → 法人 → 當沖 → 融資券 → 外資持股', () async {
      await refetcher.refetchPending(today: today, ledger: ledger);
      expect(calls.indexOf('prices/TWSE'), lessThan(calls.indexOf('dayTrading/TWSE')));
      expect(calls.indexOf('prices/TPEx'), lessThan(calls.indexOf('dayTrading/TPEx')));
      expect(calls.last, 'foreignShareholding');
    });

    test('法人兩市場同一天只打一次', () async {
      await refetcher.refetchPending(today: today, ledger: ledger);
      expect(calls.where((c) => c == 'institutional'), hasLength(1));
    });

    test('已定案的組不重抓', () async {
      await db.upsertMarketDayFetch(dataset: MarketDataset.prices.code, market: MarketCode.twse, date: d, fetchedAt: DateTime(2026, 9, 25), rowCount: 1);
      await refetcher.refetchPending(today: today, ledger: ledger);
      expect(calls, isNot(contains('prices/TWSE')));
      expect(calls, contains('prices/TPEx'));
    });

    test('追蹤起始日不存在時寫入今天，且不回頭抓舊日子', () async {
      await db.deleteSetting(MarketDayRefetcher.trackingSinceKey);
      await refetcher.refetchPending(today: today, ledger: ledger);
      expect(calls, isEmpty);
      expect(await db.getSetting(MarketDayRefetcher.trackingSinceKey), '2026-09-29');
    });

    test('限流：中止其餘重抓並回報', () async {
      when(() => price.backfillTwsePricesByDate(date: any(named: 'date'), targetSymbols: any(named: 'targetSymbols'), ledger: any(named: 'ledger')))
          .thenThrow(const RateLimitException('429'));
      final s = await refetcher.refetchPending(today: today, ledger: ledger);
      expect(s.rateLimited, isTrue);
      expect(calls, isEmpty);
    });

    test('一般錯誤：記錄並繼續下一組', () async {
      when(() => price.backfillTwsePricesByDate(date: any(named: 'date'), targetSymbols: any(named: 'targetSymbols'), ledger: any(named: 'ledger')))
          .thenThrow(const DatabaseException('x'));
      final s = await refetcher.refetchPending(today: today, ledger: ledger);
      expect(s.errors, isNotEmpty);
      expect(calls, contains('prices/TPEx'));
    });

    test('沒有記錄到狀態的日子（例如颱風停市回 0 列），下輪仍是候選', () async {
      // 「回 0 列不寫狀態」由 ledger 的門檻負責（Task 2 測試）；這裡釘的是
      // refetcher 這一側：沒狀態的日子不會因為「這輪抓過」就被跳過
      await refetcher.refetchPending(today: today, ledger: ledger);
      calls.clear();
      await refetcher.refetchPending(today: today, ledger: ledger);
      expect(calls, contains('prices/TWSE'));
    });

    test('法人：上市已定案、上櫃未定案 → 仍打一次（取聯集，不是交集）', () async {
      await db.upsertMarketDayFetch(dataset: MarketDataset.institutional.code, market: MarketCode.twse, date: d, fetchedAt: DateTime(2026, 9, 25), rowCount: 1);
      await refetcher.refetchPending(today: today, ledger: ledger);
      expect(calls.where((c) => c == 'institutional'), hasLength(1));
    });

    test('滑出回補窗仍未定案（含完全沒有狀態列）→ 只列入 staleOutOfWindow，不進 errors', () async {
      // 起始日 8/03：9/29 的 40 日曆天窗從 8/20 起，8/03–8/19 已滑出窗外
      await db.setSetting(MarketDayRefetcher.trackingSinceKey, '2026-08-03');
      final s = await refetcher.refetchPending(today: today, ledger: ledger);
      expect(s.staleOutOfWindow, isNotEmpty);
      expect(s.staleOutOfWindow.any((e) => e.contains('2026-08-19')), isTrue);
      expect(s.errors, isEmpty);
    });

    test('每組每輪最多 finalityRefetchMaxDaysPerRun 天，其餘記入 deferred', () async {
      // 追蹤起始日拉到 8/24：9/29 往回 40 日曆天內的交易日遠多於 10 天
      await db.setSetting(MarketDayRefetcher.trackingSinceKey, '2026-08-24');
      final s = await refetcher.refetchPending(today: today, ledger: ledger);
      expect(
        calls.where((c) => c == 'prices/TWSE'),
        hasLength(ApiConfig.finalityRefetchMaxDaysPerRun),
      );
      final g = (dataset: MarketDataset.prices, market: MarketCode.twse);
      final candidates = refetchCandidateDays(
        today: today,
        trackingSince: DateTime(2026, 8, 24),
      ).length;
      expect(s.deferred[g], candidates - ApiConfig.finalityRefetchMaxDaysPerRun);
      expect(s.toLogLine(), contains('剩 ${s.deferred[g]} 天'));
    });

    test('refetchRange：範圍內交易日不論狀態一律重抓', () async {
      await db.upsertMarketDayFetch(dataset: MarketDataset.prices.code, market: MarketCode.twse, date: d, fetchedAt: DateTime(2026, 9, 25), rowCount: 1);
      await refetcher.refetchRange(dataset: MarketDataset.prices, market: MarketCode.twse, from: DateTime(2026, 9, 23), to: d, ledger: ledger);
      expect(calls.where((c) => c == 'prices/TWSE'), hasLength(2));
    });
  });
```

（已確認：`RateLimitException([message, cause])`、`DatabaseException(message, cause)` 皆為位置參數；`deleteSetting(String key)` 存在於 `user_dao.dart`。）

- [ ] **Step 6：跑測試，確認失敗**

Run: `flutter test test/domain/services/update/market_day_refetcher_test.dart`
Expected：MarketDayRefetcher group 編譯失敗。

- [ ] **Step 7：實作 MarketDayRefetcher**（同檔後半）

```dart
/// 重抓未定案的日子（spec §4.5(b)）
///
/// 每輪更新在當日路徑與既有回補之後執行；修復工具以 [refetchRange] 重用
/// 同一套抓取邏輯。每個抓取都傳 [MarketDayFetchLedger]，由 repository 在
/// 寫入時回報，這裡只負責挑日子與依序呼叫。
class MarketDayRefetcher {
  MarketDayRefetcher({
    required AppDatabase database,
    required IPriceRepository priceRepository,
    IInstitutionalRepository? institutionalRepository,
    ITradingRepository? tradingRepository,
    ShareholdingRepository? shareholdingRepository,
    this.callDelay = const Duration(
      milliseconds: ApiConfig.finalityRefetchCallDelayMs,
    ),
  }) : _db = database,
       _priceRepo = priceRepository,
       _institutionalRepo = institutionalRepository,
       _tradingRepo = tradingRepository,
       _shareholdingRepo = shareholdingRepository;

  /// app_settings key：第一次執行更新的台北日期，之後不再變動
  static const String trackingSinceKey = 'finality_tracking_since';

  final AppDatabase _db;
  final IPriceRepository _priceRepo;
  final IInstitutionalRepository? _institutionalRepo;
  final ITradingRepository? _tradingRepo;
  final ShareholdingRepository? _shareholdingRepo;
  final Duration callDelay;

  Future<RefetchSummary> refetchPending({
    required DateTime today,
    required MarketDayFetchLedger ledger,
  }) async {
    final todayDay = DateContext.normalize(today);
    final since = DateTime.parse(
      await _db.getOrInitSetting(
        trackingSinceKey,
        DateContext.formatYmd(todayDay),
      ),
    );
    final candidates = refetchCandidateDays(today: todayDay, trackingSince: since);
    final summary = RefetchSummary();
    final fetches = await _db.getMarketDayFetchesSince(since);

    // 追蹤起始日以後、已滑出回補窗仍未定案（含完全沒有狀態列）的日子：
    // 這些資料會一直停在初值，必須看得見。只記 warning、不進 errors——
    // 它們不會自己消失，進 errors 會讓之後每一輪 launchd 都 exit 1。
    final windowStart = DateTime(
      todayDay.year,
      todayDay.month,
      todayDay.day - ApiConfig.tradingBackfillLookbackDays,
    );
    final outOfWindow = <DateTime>[
      for (
        var d = DateTime(
          windowStart.year,
          windowStart.month,
          windowStart.day - 1,
        );
        !d.isBefore(since);
        d = DateTime(d.year, d.month, d.day - 1)
      )
        if (TaiwanCalendar.isTradingDay(d)) d,
    ];
    const noCap = 1 << 30;
    for (final e in selectRefetchDays(
      candidateDays: outOfWindow,
      fetches: fetches,
      maxPerGroup: noCap,
    ).entries) {
      for (final d in e.value) {
        summary.staleOutOfWindow.add(
          '${e.key.dataset.code}/${e.key.market} ${DateContext.formatYmd(d)}',
        );
      }
    }
    if (summary.staleOutOfWindow.isNotEmpty) {
      // 這些日子會一直留著，只印筆數與前 10 筆，避免日誌行無限變長
      final list = summary.staleOutOfWindow;
      AppLogger.warning(
        'MarketDayRefetcher',
        '超出回補窗仍未定案 ${list.length} 筆（會停在初值，需用 '
            'tool/refetch_market_days.dart 修）: ${list.take(10).join(', ')}'
            '${list.length > 10 ? ' …' : ''}',
      );
    }

    final plan = selectRefetchDays(
      candidateDays: candidates,
      fetches: fetches,
      maxPerGroup: ApiConfig.finalityRefetchMaxDaysPerRun,
    );
    // 超過每輪上限、留給下一輪的天數（進摘要）
    final all = selectRefetchDays(
      candidateDays: candidates,
      fetches: fetches,
      maxPerGroup: noCap,
    );
    for (final g in finalityGroups) {
      summary.deferred[g] = (all[g]?.length ?? 0) - (plan[g]?.length ?? 0);
    }
    await _execute(plan, ledger, summary);
    return summary;
  }

  /// 修復工具用：[from]～[to] 的交易日不論狀態一律重抓，不受每輪上限、
  /// 回補窗與追蹤起始日限制。法人一次請求涵蓋兩市場，[market] 被忽略。
  Future<RefetchSummary> refetchRange({
    required MarketDataset dataset,
    required String market,
    required DateTime from,
    required DateTime to,
    required MarketDayFetchLedger ledger,
  }) async {
    final days = <DateTime>[
      for (
        var d = DateContext.normalize(to);
        !d.isBefore(DateContext.normalize(from));
        d = DateTime(d.year, d.month, d.day - 1)
      )
        if (TaiwanCalendar.isTradingDay(d)) d,
    ];
    final plan = <FinalityGroup, List<DateTime>>{
      if (dataset == MarketDataset.institutional) ...{
        (dataset: dataset, market: MarketCode.twse): days,
        (dataset: dataset, market: MarketCode.tpex): days,
      } else
        (dataset: dataset, market: market): days,
    };
    final summary = RefetchSummary();
    await _execute(plan, ledger, summary);
    return summary;
  }

  Future<void> _execute(
    Map<FinalityGroup, List<DateTime>> plan,
    MarketDayFetchLedger ledger,
    RefetchSummary summary,
  ) async {
    var calls = 0;
    Future<bool> attempt(
      List<FinalityGroup> groups,
      DateTime day,
      Future<void> Function() fetch,
    ) async {
      if (calls > 0) await Future<void>.delayed(callDelay);
      calls++;
      for (final g in groups) {
        summary.attempted[g] = (summary.attempted[g] ?? 0) + 1;
      }
      try {
        await fetch();
      } on RateLimitException catch (e) {
        summary.rateLimitError = e;
        return false;
      } on NetworkException catch (e) {
        // 網路異常：中止整個重抓（後續呼叫必然同樣失敗），記錯誤、不設限流
        summary.errors.add(
          '${groups.first.dataset.code} ${DateContext.formatYmd(day)}: $e',
        );
        return false;
      } on Exception catch (e) {
        summary.errors.add(
          '${groups.map((g) => '${g.dataset.code}/${g.market}').join('+')} '
          '${DateContext.formatYmd(day)}: $e',
        );
      }
      for (final g in groups) {
        final done = ledger.recorded.any(
          (r) =>
              r.dataset == g.dataset &&
              r.market == g.market &&
              DateContext.isSameDay(r.date, day),
        );
        if (done) summary.finalized[g] = (summary.finalized[g] ?? 0) + 1;
      }
      return true;
    }

    List<DateTime> daysOf(MarketDataset ds, String market) =>
        plan[(dataset: ds, market: market)] ?? const [];

    // 1. 價格（當沖比例的分母，必須先於當沖）
    for (final market in [MarketCode.twse, MarketCode.tpex]) {
      final days = daysOf(MarketDataset.prices, market);
      if (days.isEmpty) continue;
      final symbols = {
        for (final s in await _db.getStocksByMarket(market)) s.symbol,
      };
      for (final day in days) {
        final ok = await attempt(
          [(dataset: MarketDataset.prices, market: market)],
          day,
          () => market == MarketCode.twse
              ? _priceRepo.backfillTwsePricesByDate(
                  date: day,
                  targetSymbols: symbols,
                  ledger: ledger,
                )
              : _priceRepo.backfillTpexPricesByDate(
                  date: day,
                  targetSymbols: symbols,
                  ledger: ledger,
                ),
        );
        if (!ok) return;
      }
    }

    // 2. 法人：一次請求兩市場，任一市場未定案就一起抓
    final inst = _institutionalRepo;
    if (inst != null) {
      final twseDays = daysOf(MarketDataset.institutional, MarketCode.twse);
      final tpexDays = daysOf(MarketDataset.institutional, MarketCode.tpex);
      final union = {...twseDays, ...tpexDays}.toList()
        ..sort((a, b) => b.compareTo(a));
      for (final day in union) {
        final groups = [
          if (twseDays.contains(day))
            (dataset: MarketDataset.institutional, market: MarketCode.twse),
          if (tpexDays.contains(day))
            (dataset: MarketDataset.institutional, market: MarketCode.tpex),
        ];
        final ok = await attempt(
          groups,
          day,
          () => inst.syncAllMarketInstitutional(day, force: true, ledger: ledger),
        );
        if (!ok) return;
      }
    }

    // 3. 當沖、4. 融資券
    final trading = _tradingRepo;
    if (trading != null) {
      for (final market in [MarketCode.twse, MarketCode.tpex]) {
        for (final day in daysOf(MarketDataset.dayTrading, market)) {
          final ok = await attempt(
            [(dataset: MarketDataset.dayTrading, market: market)],
            day,
            () => market == MarketCode.twse
                ? trading.syncAllDayTradingFromTwse(
                    date: day,
                    force: true,
                    ledger: ledger,
                  )
                : trading.syncAllDayTradingFromTpex(
                    date: day,
                    force: true,
                    ledger: ledger,
                  ),
          );
          if (!ok) return;
        }
      }
      for (final market in [MarketCode.twse, MarketCode.tpex]) {
        for (final day in daysOf(MarketDataset.margin, market)) {
          final ok = await attempt(
            [(dataset: MarketDataset.margin, market: market)],
            day,
            () => trading.backfillMarginTradingByDate(
              date: day,
              markets: {market},
              ledger: ledger,
            ),
          );
          if (!ok) return;
        }
      }
    }

    // 5. 外資持股（僅上市）
    final sh = _shareholdingRepo;
    if (sh != null) {
      for (final day in daysOf(
        MarketDataset.foreignShareholding,
        MarketCode.twse,
      )) {
        final ok = await attempt(
          [(dataset: MarketDataset.foreignShareholding, market: MarketCode.twse)],
          day,
          () => sh.syncAllMarketShareholding(
            date: day,
            force: true,
            ledger: ledger,
          ),
        );
        if (!ok) return;
      }
    }
  }
}
```

- [ ] **Step 8：跑測試，確認通過**

Run: `flutter test test/domain/services/update/market_day_refetcher_test.dart`
Expected：全部 PASS。

- [ ] **Step 9：mutation 自驗**：法人聯集改成交集（「上市已定案、上櫃未定案」紅）；`maxPerGroup` 改傳 `noCap`（上限測試紅）；法人改成逐市場各打一次（「只打一次」紅）；拿掉 `trackingSince` 下界（「不回頭抓舊日子」紅）；價格與當沖順序對調（順序測試紅）。

---

## Task 11：UpdateService 接線

spec §4.5、§6。

**Files:**
- Modify: `lib/domain/services/update_service.dart`
- Modify: `lib/domain/services/update_service_deps.dart`（`UpdateServices` 加可選 `marketDayRefetcher`，測試注入用）
- Modify: `test/domain/services/update_service_test.dart`（`buildService` 加參數與預設 refetcher mock；新增 group）

**Interfaces:**
- Consumes: Task 3 `clearCache`；Task 7–10 的簽章
- Produces: `_UpdateContext.ledger`；更新日誌新增「步驟 5.5: 未定案重抓: …」

- [ ] **Step 1：寫失敗測試**

`test/domain/services/update_service_test.dart`：

1. 新增 mock 與 fake：

```dart
class MockTwseClient extends Mock implements TwseClient {}

class MockMarketDayRefetcher extends Mock implements MarketDayRefetcher {}

class _FakeLedger extends Fake implements MarketDayFetchLedger {}
```

`setUpAll` 加 `registerFallbackValue(_FakeLedger());`，並 import `twse_client.dart`、`market_day_fetch_ledger.dart`、`market_day_refetcher.dart`。

2. `main()` 內新增 `late MockMarketDayRefetcher mockRefetcher;`；`setUp` 最後加：

```dart
    mockRefetcher = MockMarketDayRefetcher();
    when(
      () => mockRefetcher.refetchPending(
        today: any(named: 'today'),
        ledger: any(named: 'ledger'),
      ),
    ).thenAnswer((_) async => RefetchSummary());
```

3. 既有對 `mockPriceRepo.syncAllPricesForDate(any())` 的 stub 與 verify（約 :105、:536、:561、:926、:981、:1077、:1221，以 grep 為準）全部改成 `syncAllPricesForDate(any(), force: any(named: 'force'), ledger: any(named: 'ledger'))`：本 Task 起 UpdateService 會傳非 null 的 ledger，沒寫的具名參數會被當成期望 null 而對不上（見 Global Constraints）。其他被 UpdateService 帶上 ledger 的 mock 呼叫同樣處理。

4. `buildService` 加兩個參數 `TwseClient? twse`、`MarketDayRefetcher? refetcher`，`clients:` 改成 `UpdateClients(tdcc: mockTdcc, twse: twse, tpex: tpex, finMind: finMind)`，`services:` 加 `marketDayRefetcher: refetcher ?? mockRefetcher`。預設注入 mock 的原因：refetcher 預設會對 DB 讀寫 `app_settings` 與 `market_day_fetch`，而本檔的 DB 是未 stub 的 mock，既有測試的狀態斷言會被這一步的錯誤污染。

5. 新增 group：

```dart
  group('盤後資料定案接線（2026-09-26）', () {
    test('每輪開始清兩個 client 的快取', () async {
      final twse = MockTwseClient();
      final tpex = MockTpexClient();
      await buildService(twse: twse, tpex: tpex).runDailyUpdate(
        forDate: tradingDay,
      );
      verify(() => twse.clearCache()).called(1);
      verify(() => tpex.clearCache()).called(1);
    });

    test('清快取發生在第一次抓取之前', () async {
      final twse = MockTwseClient();
      final tpex = MockTpexClient();
      await buildService(twse: twse, tpex: tpex).runDailyUpdate(
        forDate: tradingDay,
      );
      verifyInOrder([
        () => twse.clearCache(),
        () => tpex.clearCache(),
        () => mockPriceRepo.syncAllPricesForDate(
          any(),
          force: any(named: 'force'),
          ledger: any(named: 'ledger'),
        ),
      ]);
    });

    test('價格同步收到 ledger，時間＝本輪開始的時鐘值', () async {
      await buildService().runDailyUpdate(forDate: tradingDay);
      final captured = verify(
        () => mockPriceRepo.syncAllPricesForDate(
          any(),
          force: any(named: 'force'),
          ledger: captureAny(named: 'ledger'),
        ),
      ).captured;
      final ledger = captured.single as MarketDayFetchLedger;
      expect(ledger.fetchedAt, DateTime(2026, 7, 6, 15, 30));
    });

    test('重抓被呼叫；限流時結果帶限流錯誤', () async {
      final summary = RefetchSummary()
        ..rateLimitError = const RateLimitException('429');
      when(
        () => mockRefetcher.refetchPending(
          today: any(named: 'today'),
          ledger: any(named: 'ledger'),
        ),
      ).thenAnswer((_) async => summary);
      final result = await buildService().runDailyUpdate(forDate: tradingDay);
      verify(
        () => mockRefetcher.refetchPending(
          today: any(named: 'today'),
          ledger: any(named: 'ledger'),
        ),
      ).called(1);
      expect(result.hasRateLimitError, isTrue);
    });

    test('非交易日提早結束：不清快取、不重抓', () async {
      final twse = MockTwseClient();
      await buildService(twse: twse).runDailyUpdate(
        forDate: DateTime(2026, 7, 11), // 週六
      );
      verifyNever(() => twse.clearCache());
      verifyNever(
        () => mockRefetcher.refetchPending(
          today: any(named: 'today'),
          ledger: any(named: 'ledger'),
        ),
      );
    });
  });
```

第一條傳入 `twse` 會讓大盤指數、股利等 syncer 被建立，它們打到未 stub 的 client 方法會失敗並被記成錯誤；這條只驗證 `clearCache`，不看更新狀態。

- [ ] **Step 2：跑測試，確認失敗**

Run: `flutter test test/domain/services/update_service_test.dart`
Expected：編譯失敗（`clearCache`、`marketDayRefetcher` 參數不存在）。

- [ ] **Step 3：實作**

1. `UpdateServices` 加 `final MarketDayRefetcher? marketDayRefetcher;`（constructor 可選參數）。
2. `UpdateService` 加欄位：

```dart
  final TwseClient? _twseClient;
  final TpexClient? _tpexClient;
  final MarketDayRefetcher? _marketDayRefetcher;
```

初始化：

```dart
       _twseClient = clients.twse,
       _tpexClient = clients.tpex,
       _marketDayRefetcher =
           services.marketDayRefetcher ??
           MarketDayRefetcher(
             database: database,
             priceRepository: repositories.price,
             institutionalRepository: repositories.institutional,
             tradingRepository: repositories.trading,
             shareholdingRepository: repositories.shareholding,
           ),
```

3. `_UpdateContext` 加 `required this.ledger` 與 `final MarketDayFetchLedger ledger;`；`_executeUpdate` 建 ctx 時傳 `ledger: MarketDayFetchLedger(database: _db, fetchedAt: _clock.now())`。
4. 步驟 1（交易日檢查）之後、步驟 1.5 之前加：

```dart
      // 清 client 快取：常駐 App 跨午夜時，前一輪的快取會被當成本輪抓的，
      // 進而誤判定案（ledger 的時間是本輪開始時刻）
      _twseClient?.clearCache();
      _tpexClient?.clearCache();
```

5. 傳 ledger：
   - `_syncDailyPrices`：`syncAllPricesForDate(normalizedDate, force: ctx.force, ledger: ctx.ledger)`
   - `_syncHistoricalData`：`syncHistoricalPrices(..., ledger: ctx.ledger)`
   - `_syncInstitutionalData`：`syncInstitutionalData(..., ledger: ctx.ledger)`
   - `_syncDayTradingAndMarginData`：`syncMarketWideData(date: normalizedDate, force: true, ledger: ctx.ledger)`（`_syncMarketAndFundamentalData` 若是呼叫它的上層，逐層把 ctx 傳到）
6. 平行組 `await (...).wait;` 之後、步驟 6 之前加 `await _refetchNonFinalDays(ctx);`，並新增：

```dart
  /// 步驟 5.5：重抓未定案的日子（spec §4.5(b)）。放在所有當日同步之後，
  /// 讓當日路徑先寫入；放在評分之前，讓回補的歷史進得了本輪評分。
  Future<void> _refetchNonFinalDays(_UpdateContext ctx) async {
    if (ctx.rateLimitedAbort) return;
    final refetcher = _marketDayRefetcher;
    if (refetcher == null) return;
    try {
      final summary = await refetcher.refetchPending(
        today: _clock.now(),
        ledger: ctx.ledger,
      );
      AppLogger.info('UpdateService', '步驟 5.5: ${summary.toLogLine()}');
      for (final e in summary.errors) {
        ctx.result.recordError('未定案重抓失敗: $e');
      }
      // staleOutOfWindow 只由 refetcher 記 warning、不進 errors：那些日子
      // 不會自己消失，進 errors 會讓之後每一輪 launchd 都 exit 1（spec §6）
      if (summary.rateLimited) {
        ctx.rateLimitedAbort = true;
        ctx.result.recordError(
          '未定案重抓中止 (rate limit): ${summary.rateLimitError}',
          summary.rateLimitError,
        );
      }
    } catch (e) {
      AppLogger.warning('UpdateService', '未定案重抓失敗', e);
      ctx.result.recordError('未定案重抓失敗: $e', e);
    }
  }
```

- [ ] **Step 4：跑測試，確認通過**

Run: `flutter test test/domain/services/`
Expected：全部 PASS。若其他以 `MockAppDatabase` 建 `UpdateService` 的測試檔因新流程呼叫未 stub 的 DB 方法而紅，比照本 Task 在該檔注入回傳空 `RefetchSummary` 的 refetcher mock；不要在 lib 放寬錯誤處理。

- [ ] **Step 4.5：全市場寫入路徑都有接 ledger（附 grep 證據）**

Run: `grep -rn "backfillTwsePricesByDate(\|backfillTpexPricesByDate(\|syncAllPricesForDate(\|syncAllMarketInstitutional(\|syncAllDayTradingFromTwse(\|syncAllDayTradingFromTpex(\|syncAllMarginTrading(\|backfillMarginTradingByDate(\|syncAllMarketShareholding(\|backfillForeignShareholding(" lib tool | grep -v "Future<"`
Expected：逐條檢查，並把結果寫進 ledger。
- `lib/` 內每個呼叫都帶 `ledger:`。
- `tool/backfill.dart` 的呼叫**不帶**：它傳的是部分股票，不是全市場抓取。
- `tool/refetch_market_days.dart` 經由 refetcher 間接帶 ledger。

- [ ] **Step 5：Stage B 閘門**

Run: `flutter analyze && flutter test && dart compile kernel tool/daily_update.dart -o /tmp/du.dill`
Expected：全部通過。送 code review（Task 7–11）；通過後停下，請使用者說「提交」。建議 commit message：`fix: 價格與法人改以「隔天以後抓過」判斷定案，每輪重抓未定案日，不再停在 15:30 初值`

---

## Task 12：上市估值讀回應日期；新增 BWIBBU_d 歷史估值

spec §4.8。

**Files:**
- Modify: `lib/data/remote/twse_client.dart`（`parseValuationRows`、`getAllStockValuation`、新增 `getStockValuationForDate`、`parseBwibbuDaily`）
- Modify: `lib/data/repositories/fundamental_repository.dart`（`syncAllMarketValuation` 註解；新增 `syncTwseValuationForDate`）
- Modify: `test/data/remote/twse_valuation_null_test.dart`
- Test: `test/data/remote/twse_valuation_date_test.dart`

**Interfaces:**
- Produces:
  - `static List<TwseValuation>? TwseClient.parseValuationRows(List<dynamic> data)`（日期取每列 `Date`；缺欄、解析失敗、多個日期 → null）
  - `Future<List<TwseValuation>> TwseClient.getStockValuationForDate(DateTime date)`
  - `static List<TwseValuation> TwseClient.parseBwibbuDaily(Map<dynamic, dynamic> json, DateTime requestedDate)`
  - `Future<int> FundamentalRepository.syncTwseValuationForDate(DateTime date)`

- [ ] **Step 1：寫失敗測試**

`test/data/remote/twse_valuation_date_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/data/remote/twse_client.dart';

void main() {
  Map<String, dynamic> row(String code, String date) => {
    'Date': date, 'Code': code, 'Name': code,
    'PEratio': '10.5', 'DividendYield': '3.17', 'PBratio': '0.82',
  };

  group('parseValuationRows（OpenAPI BWIBBU_ALL）', () {
    test('日期取回應每列的 Date（民國 YYYMMDD），不用呼叫當天', () {
      final r = TwseClient.parseValuationRows([row('1101', '1150924')])!;
      expect(r.single.date, DateTime(2026, 9, 24));
    });

    test('整批出現多個日期 → null（整批丟棄）', () {
      expect(
        TwseClient.parseValuationRows([row('1101', '1150924'), row('1102', '1150923')]),
        isNull,
      );
    });

    test('缺 Date 或無法解析 → null', () {
      expect(TwseClient.parseValuationRows([row('1101', '')]), isNull);
      expect(
        TwseClient.parseValuationRows([
          {'Code': '1101', 'PEratio': '1'},
        ]),
        isNull,
      );
    });
  });

  group('parseBwibbuDaily（BWIBBU_d 歷史）', () {
    Map<String, dynamic> body(String date) => {
      'stat': 'OK',
      'date': date,
      'fields': ['證券代號', '證券名稱', '收盤價', '殖利率(%)', '股利年度', '本益比', '股價淨值比', '財報年/季'],
      'data': [
        ['1101', '台泥', '23.10', '3.17', '114', '-', '0.82', '115/2'],
      ],
    };

    test('依欄位名取值，`-` 為 null，日期用請求日', () {
      final r = TwseClient.parseBwibbuDaily(body('20260924'), DateTime(2026, 9, 24));
      expect(r.single.code, '1101');
      expect(r.single.per, isNull);
      expect(r.single.pbr, 0.82);
      expect(r.single.dividendYield, 3.17);
      expect(r.single.date, DateTime(2026, 9, 24));
    });

    test('回應日期 ≠ 請求日期 → 空', () {
      expect(TwseClient.parseBwibbuDaily(body('20260923'), DateTime(2026, 9, 24)), isEmpty);
    });

    test('欄數不足的列略過，不丟 RangeError', () {
      final b = body('20260924');
      (b['data'] as List).add(['1102', '亞泥', '30.00']);
      expect(
        TwseClient.parseBwibbuDaily(b, DateTime(2026, 9, 24)).map((r) => r.code),
        ['1101'],
      );
    });

    test('回應包在 tables 內也能解析', () {
      final wrapped = {
        'stat': 'OK',
        'date': '20260924',
        'tables': [
          {'fields': body('20260924')['fields'], 'data': body('20260924')['data']},
        ],
      };
      expect(TwseClient.parseBwibbuDaily(wrapped, DateTime(2026, 9, 24)), hasLength(1));
    });
  });
}
```

另在同檔新增 client 與 repository 層的釘樁（以 `MockDio` 與 in-memory DB，寫法同 Task 3）：

```dart
  test('getStockValuationForDate 打 BWIBBU_d，帶 date 與 selectType=ALL', () async {
    final dio = MockDio();
    when(
      () => dio.get<dynamic>(
        any(),
        queryParameters: any(named: 'queryParameters'),
        options: any(named: 'options'),
      ),
    ).thenAnswer(
      (_) async => Response<dynamic>(
        requestOptions: RequestOptions(path: '/x'),
        statusCode: 200,
        data: body('20260924'),
      ),
    );
    final rows = await TwseClient(dio: dio).getStockValuationForDate(
      DateTime(2026, 9, 24),
    );
    expect(rows, hasLength(1));
    final captured = verify(
      () => dio.get<dynamic>(
        captureAny(),
        queryParameters: captureAny(named: 'queryParameters'),
        options: any(named: 'options'),
      ),
    ).captured;
    expect(captured[0], '/rwd/zh/afterTrading/BWIBBU_d');
    expect(captured[1], {
      'date': '20260924',
      'selectType': 'ALL',
      'response': 'json',
    });
  });
```

（`body()` 從上面 group 內提到 `main` 層級共用；檔頭補 `dio`、`mocktail` import 與 `class MockDio extends Mock implements Dio {}`。）

`test/data/repositories/fundamental_repository_test.dart` 新增一條：mock `TwseClient.getStockValuationForDate` 回一筆 9/24 的 `TwseValuation`，呼叫 `syncTwseValuationForDate(DateTime(2026, 9, 24))` 後，以 `db.getLatestValuationsBatch(['1101'])` 讀回，斷言日期為 9/24、`per` 與 mock 相同（該檔若用 in-memory DB 就沿用；若用 `MockAppDatabase` 則改為 verify `insertValuationData` 收到一筆日期為 9/24 的 companion）。

`test/data/remote/twse_valuation_null_test.dart`：每個 row map 補 `'Date': '1150814'`，`parseValuationRows([...], d)` 改成 `parseValuationRows([...])!`。`d = DateTime(2026, 8, 14)` 改當斷言用：每個測試加 `expect(r.single.date, d);`（否則 `d` 變成未使用變數，analyze 會擋）。

- [ ] **Step 2：跑測試，確認失敗**

Run: `flutter test test/data/remote/twse_valuation_date_test.dart test/data/remote/twse_valuation_null_test.dart`
Expected：編譯失敗（簽章不同、`parseBwibbuDaily` 不存在）。

- [ ] **Step 3：實作**

`parseValuationRows`：

```dart
  /// OpenAPI BWIBBU_ALL → 估值列。
  ///
  /// 日期取每列的 `Date`（民國 YYYMMDD）。15:30／21:30 時這個端點仍是前一
  /// 交易日的資料；舊實作用呼叫當天的日期標記，2026-07-15 起 52 個交易日
  /// 裡 35 天整批標成隔天。整批應只有一個日期：缺欄、解析失敗或出現多個
  /// 日期 → 回 null、整批丟棄（寫錯日期比沒資料糟）。
  ///
  /// （保留原本關於 `-` 與 0.00 語意的說明）
  static List<TwseValuation>? parseValuationRows(List<dynamic> data) {
    DateTime? batchDate;
    final result = <TwseValuation>[];
    for (final item in data) {
      final map = item as Map<String, dynamic>;
      final date = TwParseUtils.parseCompactRocDate(map['Date']?.toString());
      if (date == null) return null;
      if (batchDate != null && !DateContext.isSameDay(batchDate, date)) {
        return null;
      }
      batchDate = date;
      double? num(String key) {
        final raw = map[key]?.toString().replaceAll(',', '');
        if (raw == null || raw.isEmpty) return null;
        return double.tryParse(raw);
      }

      result.add(
        TwseValuation(
          code: map['Code']?.toString() ?? '',
          date: date,
          per: num('PEratio'),
          pbr: num('PBratio'),
          dividendYield: num('DividendYield'),
        ),
      );
    }
    return result;
  }
```

`getAllStockValuation`：刪掉 `resDate` 那段（連同「Open Data 不回傳交易日」的註解），改成：

```dart
      final results = parseValuationRows(data);
      if (results == null) {
        AppLogger.warning(_tag, '估值資料: 回應日期缺失、無法解析或不一致，整批丟棄');
        return <TwseValuation>[];
      }
      final dateLabel = results.isEmpty
          ? '無'
          : DateContext.formatYmd(results.first.date);
      AppLogger.info(_tag, '估值資料: ${results.length} 筆 ($dateLabel)');
```

`date` 參數保留在簽章上但不再用來標記（呼叫端不必改），說明文字寫明「只用於快取 key 以外不使用；資料日一律取自回應」。若 `date` 完全未被使用、analyzer 報未使用參數，改為從簽章移除並同步修正 `FundamentalRepository` 呼叫點。

新增：

```dart
  /// 指定日期的上市估值（`/rwd/zh/afterTrading/BWIBBU_d`；修復工具用）
  Future<List<TwseValuation>> getStockValuationForDate(DateTime date) {
    return MarketClientMixin.executeRequest(_tag, '歷史估值', () async {
      final dateStr = TwParseUtils.formatDateCompact(date);
      final response = await _dio.get(
        '/rwd/zh/afterTrading/BWIBBU_d',
        queryParameters: {
          'date': dateStr,
          'selectType': 'ALL',
          'response': 'json',
        },
      );
      if (response.statusCode != 200) {
        throw ApiException(
          '$_tag API error: ${response.statusCode}',
          response.statusCode,
        );
      }
      final data = MarketClientMixin.decodeResponseData(
        response.data,
        _tag,
        '歷史估值',
      );
      if (data == null) return <TwseValuation>[];
      return parseBwibbuDaily(data, date);
    });
  }

  /// BWIBBU_d 回應 → 估值列（需 `import 'dart:math' show max;`）。依欄位名取值（欄序曾變動）；`-` 為 null；
  /// 頂層 `date` ≠ 請求日期回空。資料可能直接在頂層或包在 `tables[0]`。
  static List<TwseValuation> parseBwibbuDaily(
    Map<dynamic, dynamic> json,
    DateTime requestedDate,
  ) {
    if (json['date']?.toString() !=
        TwParseUtils.formatDateCompact(requestedDate)) {
      return const [];
    }
    final tables = json['tables'];
    final Map<dynamic, dynamic> table =
        (tables is List && tables.isNotEmpty && tables.first is Map)
        ? tables.first as Map<dynamic, dynamic>
        : json;
    final fields = (table['fields'] as List?)?.map((f) => f.toString()).toList();
    final rows = table['data'];
    if (fields == null || rows is! List) return const [];
    int col(String name) => fields.indexWhere((f) => f.contains(name));
    final code = col('證券代號');
    final per = col('本益比');
    final pbr = col('股價淨值比');
    final yieldCol = col('殖利率');
    if ([code, per, pbr, yieldCol].any((i) => i < 0)) return const [];
    double? num(dynamic v) {
      final raw = v?.toString().replaceAll(',', '').trim();
      if (raw == null || raw.isEmpty || raw == '-') return null;
      return double.tryParse(raw);
    }

    final day = DateContext.normalize(requestedDate);
    return [
      for (final r in rows)
        if (r is List && r.length > [code, per, pbr, yieldCol].reduce(max))
          TwseValuation(
            code: r[code].toString().trim(),
            date: day,
            per: num(r[per]),
            pbr: num(r[pbr]),
            dividendYield: num(r[yieldCol]),
          ),
    ];
  }
```

`TwParseUtils.formatDateCompact` 回傳格式請確認是 `YYYYMMDD`；不是的話改用 Task 4 的手寫格式。

`fundamental_repository.dart`：

1. `syncAllMarketValuation` 上方註解「使用 TWSE BWIBBU_d」改成「使用 TWSE OpenAPI BWIBBU_ALL（最新一個交易日，日期取自回應）」。
2. 新增：

```dart
  /// 用 BWIBBU_d 寫入指定日期的上市估值（修復工具用）
  Future<int> syncTwseValuationForDate(DateTime date) async {
    try {
      final data = await _twse.getStockValuationForDate(date);
      if (data.isEmpty) return 0;
      await _db.insertValuationData([
        for (final r in data)
          StockValuationCompanion.insert(
            symbol: r.code,
            date: r.date,
            per: Value(r.per),
            pbr: Value(r.pbr),
            dividendYield: Value(r.dividendYield),
          ),
      ]);
      return data.length;
    } on RateLimitException {
      rethrow;
    } on NetworkException {
      rethrow;
    } catch (e) {
      throw DatabaseException(
        'Failed to sync TWSE valuation for ${DateContext.formatYmd(date)}',
        e,
      );
    }
  }
```

`insertValuationData` 對不在 `stock_master` 的代號若會觸發 FK 錯誤，先以 `syncAllMarketValuation` 的既有寫入方式為準（它目前直接寫、沒有過濾，代表可行；若實測失敗，比照法人以在市股票過濾並記 `Ruling:`）。

- [ ] **Step 4：跑測試，確認通過**

Run: `flutter test test/data/remote/twse_valuation_date_test.dart test/data/remote/twse_valuation_null_test.dart test/data/repositories/fundamental_repository_test.dart`
Expected：全部 PASS。

- [ ] **Step 5：mutation 自驗**：`parseValuationRows` 拿掉多日期檢查（多日期測試紅）；`parseBwibbuDaily` 拿掉日期比對（日期不符測試紅）。

---

## Task 13：修復 CLI `tool/refetch_market_days.dart`

spec §5。

**Files:**
- Create: `tool/refetch_market_days.dart`
- Test: `test/tool/refetch_market_days_test.dart`

**Interfaces:**
- Consumes: Task 10 `MarketDayRefetcher.refetchRange`；Task 12 `FundamentalRepository.syncTwseValuationForDate`
- Produces: `RefetchArgs? parseRefetchArgs(List<String> args, void Function(String) err)`、`Future<int> runRefetchCli(List<String> args)`

- [ ] **Step 1：寫失敗測試**

`test/tool/refetch_market_days_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/constants/market_codes.dart';
import 'package:daredevil/core/constants/market_dataset.dart';

import 'dart:io';

import '../../tool/refetch_market_days.dart';

void main() {
  List<String> errs = [];
  RefetchArgs? parse(List<String> a) {
    errs = [];
    return parseRefetchArgs(a, errs.add);
  }

  test('完整參數', () {
    final a = parse(['--dataset', 'prices', '--market', 'TPEx', '--from', '2025-06-10', '--to', '2026-09-24', '--dry-run']);
    expect(a!.dataset, MarketDataset.prices);
    expect(a.market, MarketCode.tpex);
    expect(a.from, DateTime(2025, 6, 10));
    expect(a.to, DateTime(2026, 9, 24));
    expect(a.dryRun, isTrue);
    expect(a.valuation, isFalse);
  });

  test('valuation 與 institutional 不需要 --market', () {
    expect(parse(['--dataset', 'valuation', '--from', '2026-07-15', '--to', '2026-09-24'])!.valuation, isTrue);
    expect(parse(['--dataset', 'institutional', '--from', '2026-07-16', '--to', '2026-08-19']), isNotNull);
  });

  test('未知旗標被拒（打錯字不可默默落回預設 DB）', () {
    expect(parse(['--dataset', 'prices', '--market', 'TWSE', '--from', '2026-07-16', '--to', '2026-09-24', '--database', 'x']), isNull);
    expect(errs.join(), contains('--database'));
  });

  test('缺 --to、from 晚於 to、未知資料集、缺必要的 --market 都被拒', () {
    expect(parse(['--dataset', 'prices', '--market', 'TWSE', '--from', '2026-07-16']), isNull);
    expect(parse(['--dataset', 'prices', '--market', 'TWSE', '--from', '2026-09-24', '--to', '2026-07-16']), isNull);
    expect(parse(['--dataset', 'foo', '--from', '2026-07-16', '--to', '2026-09-24']), isNull);
    expect(parse(['--dataset', 'margin', '--from', '2026-07-16', '--to', '2026-09-24']), isNull);
  });

  test('🚨 --db 缺值（在最末或後接旗標）被拒，不可落回實際 app DB', () {
    expect(parse(['--dataset', 'prices', '--market', 'TWSE', '--from', '2026-07-16', '--to', '2026-09-24', '--db']), isNull);
    expect(parse(['--dataset', 'prices', '--market', 'TWSE', '--from', '2026-07-16', '--to', '2026-09-24', '--db', '--dry-run']), isNull);
    expect(errs.join(), contains('--db'));
    // 對照：有給值時接受
    expect(parse(['--dataset', 'prices', '--market', 'TWSE', '--from', '2026-07-16', '--to', '2026-09-24', '--db', 'copy.db'])!.dbPath, 'copy.db');
  });

  test('--db 指到不存在的檔案 → 退出碼 2，不建立新 DB、不打 API', () async {
    const path = '/tmp/refetch_market_days_test_nonexistent.db';
    expect(
      await runRefetchCli(['--dataset', 'prices', '--market', 'TWSE', '--from', '2026-07-16', '--to', '2026-07-16', '--db', path]),
      2,
    );
    expect(File(path).existsSync(), isFalse);
  });

  test('外資持股只有上市', () {
    expect(parse(['--dataset', 'foreignShareholding', '--market', 'TPEx', '--from', '2026-07-16', '--to', '2026-09-24']), isNull);
  });
}
```

- [ ] **Step 2：跑測試，確認失敗**

Run: `flutter test test/tool/refetch_market_days_test.dart`
Expected：編譯失敗。

- [ ] **Step 3：實作**

`tool/refetch_market_days.dart`：

```dart
// tool/refetch_market_days.dart
//
// CLI tool — print 為預期輸出，關閉 avoid_print lint。
// ignore_for_file: avoid_print
//
// 盤後資料一次性修復：指定範圍內的交易日不論狀態一律以官方歷史端點重抓，
// 並記錄抓取狀態（設計見 docs/plans/2026-09-26-market-data-finality-design.md §5）。
// 重抓邏輯與每日更新的「未定案重抓」共用 MarketDayRefetcher，不另寫一套。
//
// ⚠️ 對實際 DB 執行前，先用 --db 對副本彩排並比對官方資料，經同意才跑實際 DB；
// 避開 15:30／21:30 的 launchd 排程時段。
//
// 使用方式：
//   dart run tool/refetch_market_days.dart --dataset prices --market TPEx \
//     --from 2025-06-10 --to 2026-09-24 [--db <path>] [--dry-run]
//   dart run tool/refetch_market_days.dart --dataset valuation \
//     --from 2026-07-15 --to 2026-09-24
//
// --dataset  prices | institutional | dayTrading | margin | foreignShareholding | valuation
// --market   TWSE | TPEx（institutional、valuation 不需要；foreignShareholding 只能 TWSE）
//
// 退出碼：0 成功／1 有失敗日／2 參數錯誤／4 限流中止

import 'dart:io';

import 'package:daredevil/core/constants/market_codes.dart';
import 'package:daredevil/core/constants/market_dataset.dart';
import 'package:daredevil/core/utils/date_context.dart';
import 'package:daredevil/core/utils/taiwan_calendar.dart';
import 'package:daredevil/core/utils/taiwan_time.dart';
import 'package:daredevil/core/exceptions/app_exception.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/data/remote/finmind_client.dart';
import 'package:daredevil/data/remote/mops_client.dart';
import 'package:daredevil/data/remote/tpex_client.dart';
import 'package:daredevil/data/remote/twse_client.dart';
import 'package:daredevil/data/repositories/fundamental_repository.dart';
import 'package:daredevil/data/repositories/institutional_repository.dart';
import 'package:daredevil/data/repositories/market_day_fetch_ledger.dart';
import 'package:daredevil/data/repositories/price_repository.dart';
import 'package:daredevil/data/repositories/shareholding_repository.dart';
import 'package:daredevil/data/repositories/trading_repository.dart';
import 'package:daredevil/domain/services/update/market_day_refetcher.dart';

import 'tool_db.dart';

class RefetchArgs {
  const RefetchArgs({
    required this.dataset,
    required this.market,
    required this.from,
    required this.to,
    required this.dbPath,
    required this.dryRun,
  });

  /// null＝valuation（估值不在定案追蹤範圍，走獨立分支）
  final MarketDataset? dataset;
  final String market;
  final DateTime from;
  final DateTime to;
  final String dbPath;
  final bool dryRun;

  bool get valuation => dataset == null;
}

const _knownFlags = {'--dataset', '--market', '--from', '--to', '--db', '--dry-run'};

String? _arg(List<String> args, String name) {
  final i = args.indexOf(name);
  if (i < 0 || i + 1 >= args.length) return null;
  return args[i + 1];
}

RefetchArgs? parseRefetchArgs(List<String> args, void Function(String) err) {
  final unknown = [
    for (final a in args)
      if (a.startsWith('--') && !_knownFlags.contains(a)) a,
  ];
  if (unknown.isNotEmpty) {
    err('未知旗標: ${unknown.join(', ')}（已知: ${_knownFlags.join(', ')}）');
    return null;
  }
  // 帶值旗標取不到值（在最末、或下一個也是旗標）一律拒絕：`--db` 漏值時若
  // 默默落回預設值，就是寫進實際 app DB
  final dangling = [
    for (final name in const ['--dataset', '--market', '--from', '--to', '--db'])
      if (args.contains(name) &&
          (args.indexOf(name) + 1 >= args.length ||
              args[args.indexOf(name) + 1].startsWith('--')))
        name,
  ];
  if (dangling.isNotEmpty) {
    err('旗標缺值: ${dangling.join(', ')}');
    return null;
  }
  final ds = _arg(args, '--dataset');
  final isValuation = ds == 'valuation';
  final dataset = isValuation
      ? null
      : MarketDataset.values.where((d) => d.code == ds).firstOrNull;
  if (!isValuation && dataset == null) {
    err('--dataset 必須是 ${MarketDataset.values.map((d) => d.code).join(' | ')} | valuation');
    return null;
  }
  final from = DateTime.tryParse(_arg(args, '--from') ?? '');
  final to = DateTime.tryParse(_arg(args, '--to') ?? '');
  if (from == null || to == null || from.isAfter(to)) {
    err('--from／--to 必須是 YYYY-MM-DD，且 from ≤ to');
    return null;
  }
  final needsMarket =
      !isValuation && dataset != MarketDataset.institutional;
  final market = _arg(args, '--market');
  if (needsMarket && market != MarketCode.twse && market != MarketCode.tpex) {
    err('--market 必須是 ${MarketCode.twse} 或 ${MarketCode.tpex}');
    return null;
  }
  if (dataset == MarketDataset.foreignShareholding && market != MarketCode.twse) {
    err('foreignShareholding 只有上市（上櫃走 FinMind，不在修復範圍）');
    return null;
  }
  return RefetchArgs(
    dataset: dataset,
    market: market ?? MarketCode.twse,
    from: DateContext.normalize(from),
    to: DateContext.normalize(to),
    dbPath:
        _arg(args, '--db') ??
        '${Platform.environment['HOME']}/Library/Containers/'
            'com.neo.afterclose/Data/Documents/afterclose.sqlite',
    dryRun: args.contains('--dry-run'),
  );
}

Future<void> main(List<String> args) async {
  exit(await runRefetchCli(args));
}

Future<int> runRefetchCli(List<String> args) async {
  final a = parseRefetchArgs(args, stderr.writeln);
  if (a == null) return 2;

  final days = [
    for (var d = a.to; !d.isBefore(a.from); d = DateTime(d.year, d.month, d.day - 1))
      if (TaiwanCalendar.isTradingDay(d)) d,
  ];
  final label = a.valuation ? 'valuation' : '${a.dataset!.code}/${a.market}';
  print('[refetch] $label ${DateContext.formatYmd(a.from)}～${DateContext.formatYmd(a.to)}：'
      '${days.length} 個交易日（約 ${days.length} 次呼叫）；DB=${a.dbPath}');
  if (a.dryRun) return 0;

  if (!File(a.dbPath).existsSync()) {
    stderr.writeln('[refetch] DB 不存在: ${a.dbPath}（修復工具不建立新 DB）');
    return 2;
  }
  // 一律經 openToolDatabase（tool_db_guard_test 把關）：fingerprint 不符時在
  // 開 DB 前中止。不開 allowSchemaReset——修復工具不得觸發行情表 DROP。
  final AppDatabase db;
  try {
    db = openToolDatabase(a.dbPath);
  } on SchemaFingerprintMismatch catch (e) {
    stderr.writeln('[refetch] $e');
    return 2;
  }
  final twse = TwseClient();
  final tpex = TpexClient();
  final finMind = FinMindClient();
  try {
    if (a.valuation) {
      final fundamental = FundamentalRepository(
        mops: MopsClient(),
        db: db,
        finMind: finMind,
        twse: twse,
        tpex: tpex,
      );
      var failed = 0;
      for (final day in days) {
        try {
          final n = await fundamental.syncTwseValuationForDate(day);
          print('[refetch] valuation ${DateContext.formatYmd(day)}: $n 筆');
        } on RateLimitException catch (e) {
          stderr.writeln('[refetch] 限流中止: $e');
          return 4;
        } catch (e) {
          failed++;
          stderr.writeln('[refetch] valuation ${DateContext.formatYmd(day)} 失敗: $e');
        }
        await Future<void>.delayed(const Duration(seconds: 3));
      }
      return failed == 0 ? 0 : 1;
    }

    final refetcher = MarketDayRefetcher(
      database: db,
      priceRepository: PriceRepository(
        database: db,
        finMindClient: finMind,
        twseClient: twse,
        tpexClient: tpex,
      ),
      institutionalRepository: InstitutionalRepository(
        database: db,
        finMindClient: finMind,
        twseClient: twse,
        tpexClient: tpex,
      ),
      tradingRepository: TradingRepository(
        database: db,
        twseClient: twse,
        tpexClient: tpex,
      ),
      shareholdingRepository: ShareholdingRepository(
        database: db,
        finMindClient: finMind,
        twseClient: twse,
      ),
      callDelay: const Duration(seconds: 3),
    );
    final ledger = MarketDayFetchLedger(
      database: db,
      fetchedAt: TaiwanTime.now(),
    );
    final summary = await refetcher.refetchRange(
      dataset: a.dataset!,
      market: a.market,
      from: a.from,
      to: a.to,
      ledger: ledger,
    );
    print('[refetch] ${summary.toLogLine()}');
    for (final e in summary.errors) {
      stderr.writeln('[refetch] $e');
    }
    if (summary.rateLimited) return 4;
    return summary.errors.isEmpty ? 0 : 1;
  } finally {
    twse.close();
    tpex.close();
    finMind.close();
    await db.close();
  }
}
```

各 repository 建構子參數與 `UpdateServiceFactory.build` 相同（已對照）。

- [ ] **Step 4：跑測試與編譯**

Run: `flutter test test/tool/refetch_market_days_test.dart && dart compile kernel tool/refetch_market_days.dart -o /tmp/rmd.dill`
Expected：測試 PASS；編譯成功（證明 import 閉包是純 Dart）。

- [ ] **Step 5：Stage C 閘門**

Run: `flutter analyze && flutter test && dart compile kernel tool/daily_update.dart -o /tmp/du.dill`
Expected：全部通過。送 code review（Task 12–13）；通過後停下，請使用者說「提交」。建議 commit message：`fix: 上市估值改用回應日期標記，新增盤後資料修復工具`

---

## Task 14：文件與過時說法

spec §4.9 與專案文件同步。

**Files:**
- Modify: `.claude/rules/update-pipeline.md`
- Modify: `tool/backfill_tpex_day_trading.dart`（檔頭「為什麼需要這支」）
- Modify: `lib/data/database/dao/day_trading_dao.dart`、`lib/data/repositories/trading_repository.dart`、`lib/data/remote/tpex_client.dart`、`lib/domain/services/update/market_data_updater.dart` 殘留的「上櫃當沖端點無視日期」說法
- Modify: `lib/data/repositories/price_repository.dart:308` 附近「正規化日期至 UTC 午夜」註解（實際是裝置本地午夜）
- Modify: `docs/plans/2026-09-26-market-data-finality-design.md`（§4.3、§4.4 對齊實作：`fetched_at` 取本輪開始的台北時間；快取在每輪開始清除）
- Modify: `CLAUDE.md`「關鍵路徑」表新增一列 `lib/domain/services/update/market_day_refetcher.dart`

- [ ] **Step 1：列出所有過時說法**

Run: `grep -rn "無視.*date\|無視請求日期\|只給最新交易日\|端點不給歷史\|afterTrading/otc\|不含定價\|UTC 午夜" lib tool .claude docs/plans/2026-09-26-market-data-finality-design.md`
Expected：列出待改位置，逐一改寫；改完再跑一次，只剩刻意保留的歷史敘述（例如設計文件 §2.1 的量測表）。

- [ ] **Step 2：改 `.claude/rules/update-pipeline.md`**

- `MarketDataUpdater` 的「上櫃當沖」段改成：端點帶 `date=YYYY/MM/DD` 可取歷史（2026-09-26 實測回到 2024-01）；每日不帶日期取最新、寫入日期取自回應；40 天缺漏回補兩市場都做、各自要求價格覆蓋達門檻。刪除「歷史回補不走這條」一句。
- `HistoricalPriceSyncer` Phase 0 的端點改成「TWSE MI_INDEX／TPEx afterTrading/dailyQuotes 歷史端點」。
- 在 `InstitutionalSyncer` 段後新增 `MarketDayRefetcher` 段：定案規則（抓取日期 > 資料日）、`market_day_fetch` 表、ledger 在寫入 transaction 內回報、每輪步驟 5.5 重抓（追蹤起始日以後、40 日曆天窗、每組每輪 ≤10 天）、修復工具 `tool/refetch_market_days.dart`。
- 「11 Syncer / Updater」數量不變（refetcher 不是 syncer），但在 Post-Update 之前的流程敘述加一行「步驟 5.5 未定案重抓」。

- [ ] **Step 3：改 `tool/backfill_tpex_day_trading.dart` 檔頭**

「為什麼需要這支」改成：上櫃官方端點帶日期可取歷史（2026-09-26 實測），每日更新已會自動回補 40 天內的缺漏；本工具只在需要回補更久以前（例如 8/21 前覆蓋率低的那段）時使用，走 FinMind 逐檔。

- [ ] **Step 4：改設計文件**

- §4.3 表格 `fetched_at` 說明改成「本輪更新開始時的台北牆鐘時間（`AppClock.now()`）；比實際請求早，只會讓判定偏向未定案」。
- §4.4 開頭改成「由發起全市場抓取的呼叫端決定是否傳入 ledger（部分股票的路徑不傳）；repository 在寫入資料的同一個 transaction 內回報實際寫入的市場、資料日、列數」。原句「在呼叫端記錄，不在 repository 裡記」的顧慮（repository 分不出是不是全市場）由「呼叫端決定傳不傳」解決，事實則由寫入端回報。
- §4.4 第 2 點改成「每輪更新開始時清空兩個 client 的快取，並以本輪開始時間作為 `fetched_at`，所以不會有前一輪的快取被記成本輪抓取」。
- §9「在 repository 內記錄狀態」一條改成「由 repository 自行判斷是否全市場並記錄：分不出來，改由呼叫端傳入 ledger 決定」。
- §4.5(b) 的「每輪都會重試，直到滑出窗外」補一句：滑出窗外仍未定案的日子只記 warning（筆數與前 10 筆），要用修復工具處理。
- §8 風險表新增一列：「App 的畫面與更新共用同一個 client。若某個請求在本輪開始**之前**發出、清快取**之後**才回來，舊回應會被寫進快取，本輪再讀到就會以本輪開始時間記錄。要發生必須剛好有一個跨越午夜、又跨越更新開始的在途請求，機率極低；若要消除，可給 client 快取加世代號（清快取時遞增、寫入前比對）」。

- [ ] **Step 5：Stage D 閘門**

Run: `flutter analyze && flutter test`
Expected：全部通過。送 code review（文件改動；請 reviewer 對照程式逐條驗證文件中的事實陳述）；通過後停下，請使用者說「提交」。建議 commit message：`docs: 更新管線文件與過時的上櫃當沖說明，對齊定案機制實作`

---

## Task 15：既有資料修復（彩排 → 同意 → 實跑）

spec §5。不改程式；每一步都唯讀或只寫副本，直到使用者同意。副本一律放在 repo 外的絕對路徑，避免被誤加進版控。

- [ ] **Step 1：確認 launchd 產物已含本次修改**

Run: `grep "build=" <launchd stdout 日誌> | tail -1`（日誌路徑見 `ops/launchd/com.neo.daredevil.daily.plist` 的 `StandardOutPath`）
Expected：build SHA 等於**最後一個動到 `lib/`、`bin/`、`tool/`、`ops/launchd/`、`pubspec` 的 commit**（只改文件的 commit 不會觸發重編）。不是的話先跑 `ops/launchd/install.sh --cli-only`。

- [ ] **Step 2：建立彩排副本、決定修復的結束日**

```bash
R="$HOME/tmp/daredevil-rehearsal"; mkdir -p "$R"
DB="<app DB 路徑>"
# 容器目錄沒有 -wal 檔時用 immutable；有 -wal 時改用 mode=ro（需 -shm 存在）
sqlite3 "file:$DB?immutable=1" "vacuum into '$R/rehearsal.db'"
cp "$R/rehearsal.db" "$R/rehearsal_before.db"
SINCE=$(sqlite3 "$R/rehearsal.db" "select value from app_settings where key='finality_tracking_since'")
echo "SINCE=$SINCE"
```

修復範圍的結束日有兩個：

- `TO`：價格與法人用，＝追蹤起始日的前一天：`TO=$(date -j -v-1d -f %Y-%m-%d "$SINCE" +%Y-%m-%d)`。工具只處理交易日，取日曆前一天即等於前一個交易日；起始日以後由每日重抓負責。`SINCE` 查不到（Stage B 尚未上線）就停下、不要進行修復。
- `VAL_TO`：估值用，＝**Stage C 提交日之前的最後一個交易日**（舊程式最後一次替估值標錯日期的那天；Stage C 在 9/29 前提交時是 9/24）。修到更晚無害，只是多打幾次呼叫。工具會拒絕 `--to` ≥ 台北今天。

- [ ] **Step 3：執行前置條件（`dart run` 曾卡在 build-hook lock 超過 20 分鐘）**

1. 關掉 IDE 或終端機裡正在跑的 `flutter test`／`flutter run`，以及 App 本身；確認沒有其他 dart 行程：`pgrep -f "flutter_tester|dart run" | wc -l` 應為 0（不要用 `pgrep -fl`，會印出其他行程的環境變數）。
2. 確認有網路（`dart run` 的 build hook 需要抓 sqlite3 預編譯檔）。
3. 避開 15:30／21:30 launchd 排程時段。
4. 下面第一條 dry-run 兼作暖機：**2 分鐘內沒有任何 `[refetch]` 輸出就 Ctrl-C 中止**，檢查是否有其他 dart 行程後再試，不要一直等。

- [ ] **Step 4：先 dry-run 看呼叫數**

```bash
# 逐條寫出，不用 for 迴圈：zsh 不會拆開未加引號的 $args，整串會變成一個參數
dart run tool/refetch_market_days.dart --dataset prices --market TPEx --from 2025-06-10 --to "$TO" --db "$R/rehearsal.db" --dry-run
dart run tool/refetch_market_days.dart --dataset prices --market TWSE --from 2026-07-16 --to "$TO" --db "$R/rehearsal.db" --dry-run
dart run tool/refetch_market_days.dart --dataset institutional --from 2026-07-16 --to 2026-08-19 --db "$R/rehearsal.db" --dry-run
dart run tool/refetch_market_days.dart --dataset valuation --from 2026-07-15 --to "$VAL_TO" --db "$R/rehearsal.db" --dry-run
```

Expected：以 `TO`＝`VAL_TO`＝9/24 計為 319／51／25／52 個交易日（`TO` 越晚越多）。法人一天一次請求涵蓋兩市場。記下每條的交易日數，Step 5 的覆蓋檢查要用。

- [ ] **Step 5：對副本實跑**：把 Step 4 的四條指令去掉 `--dry-run`，逐條執行，每條結束用 `echo $?` 看退出碼。

退出碼 0 不代表完整（某天回 0 列不算錯誤），每條都要做覆蓋檢查；非 0 時依下表處理：

| 結果 | 處理 |
|:--|:--|
| 退出碼 1 或 4，且印出「下次可用 --to X 續跑」 | 原指令把 `--to` 換成 X 再跑（被限流時先等幾分鐘） |
| 退出碼 1，沒有續跑提示（一般錯誤） | 依 stderr 列出的日子，逐日以 `--from D --to D` 補跑 |
| 估值印出「回 0 筆: …」 | 逐日以 `--from D --to D` 補跑；仍為 0 筆就記下日期，交給使用者判斷 |

覆蓋檢查（價格與法人；估值看「回 0 筆」清單為空即可）：

```bash
sqlite3 "$R/rehearsal.db" "select dataset, market, count(*), min(substr(date,1,10)), max(substr(date,1,10))
  from market_day_fetch where substr(fetched_at,1,10) >= '<執行日 YYYY-MM-DD>' group by 1,2;"
```

Expected：prices/TPEx、prices/TWSE、institutional 兩市場的列數各等於 Step 4 該條的交易日數。少的日子就是寫入列數未達門檻或沒寫成功的日子，逐日補跑或記下原因。

- [ ] **Step 6：驗收**

(a) **範圍內與官方比對，不符列數歸零**。以 Task 0 的比對腳本改讀 `$R/rehearsal.db`：TPEx 價格用 `dailyQuotes` 抽 10 個分散在範圍內的日子全市場比對成交量；TWSE 價格用 MI_INDEX 抽 10 天；法人抽 5 天比 T86／上櫃；估值逐日比 BWIBBU_d。

- 只比 `stock_master.market` **等於該修復市場**、且 `is_active=1` 的股票。
- **轉市場股票另列**：工具只重抓目前屬於該市場的股票，2025-06 以後由上櫃轉上市的股票，上櫃期間的價格仍是舊口徑。用兩個分散日期（例如 2025-06-12 與 2026-07-14）的 `dailyQuotes` 回應取得當時的上櫃代號，與 `stock_master` 中目前 `market='TWSE'` 的代號取交集，列出檔數與代號，交給使用者決定是否處理。

(b) **範圍外不得變動**——依（市場, 日期）雙向比對，並含 `day_trading`：

```bash
for t in daily_price daily_institutional stock_valuation margin_trading shareholding day_trading; do
  sqlite3 "$R/rehearsal_before.db" "attach '$R/rehearsal.db' as n;
    select '$t -', coalesce(m.market,'?'), substr(x.date,1,10), count(*) from (select * from $t except select * from n.$t) x left join stock_master m on m.symbol=x.symbol group by 2,3
    union all
    select '$t +', coalesce(m.market,'?'), substr(x.date,1,10), count(*) from (select * from n.$t except select * from $t) x left join stock_master m on m.symbol=x.symbol group by 2,3;"
done
```

判準：

- `daily_price`：上櫃列只能落在 [2025-06-10, TO]，上市列只能落在 [2026-07-16, TO]。
- `daily_institutional`：只能落在 [2026-07-16, 2026-08-19]。
- `stock_valuation`：只能有上市列，且落在 [2026-07-15, VAL_TO]。
- `day_trading`：日期落在價格修復範圍內，且只有 `day_trading_ratio` 欄不同（抽 3 筆比對確認）。
- `margin_trading`、`shareholding`：不得有任何差異。

(c) **當沖比例**：抽查 3 檔在修復範圍內的日子，`day_trading_ratio` ＝ `trade_volume ÷ 新成交量 × 100`。

(d) **順便檢查三件事**：
- 同一天有沒有兩列（變體時間戳）：對 `daily_price`、`daily_institutional`、`stock_valuation` 跑 `select symbol, substr(date,1,10), count(*) from <表> group by 1,2 having count(*)>1`，應為 0。
- `stock_valuation` 在 2026-07-15 以前有沒有列：有的話那些是舊邏輯寫的、不在修復範圍，列出筆數交給使用者。
- 估值寫入有外鍵：有代號不在 `stock_master` 時那一天整批失敗，會以「失敗日、退出碼 1」出現，Step 5 已處理。

- [ ] **Step 7：把彩排結果交給使用者，停下等同意**

回報內容：
- 各範圍的呼叫數、耗時、補跑紀錄；
- 比對結果（修前／修後不符列數）；
- 範圍外差異的檢查結果；
- 轉市場股票的檔數與代號，請使用者決定是否處理；
- 7/15 以前舊估值列的筆數；
- 預計對實際 DB 執行的時段（避開 15:30／21:30）。

**沒有明確同意不得進行 Step 8。**

- [ ] **Step 8：（經同意後）對實際 DB 執行**

1. 關閉 App，確認 Step 3 的前置條件，避開排程時段。
2. **先備份實際 DB**，出問題時可整檔還原：`sqlite3 "file:$DB?immutable=1" "vacuum into '$R/live_backup_before_repair.db'"`（有 -wal 時改 `mode=ro`）；確認 `pragma integrity_check` 為 `ok`。
3. 執行 Step 5 的四條指令，**不帶 `--db`**（預設即實際 app DB），照 Step 5 的表處理非 0 退出碼並做覆蓋檢查（改查實際 DB）。
4. 再跑一次 Step 6(a) 的比對，驗證實際 DB。
