# 股利第 3-1 段：配發表補價與完整度事實 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 配發表補存列表的前收盤價與除權息參考價、記錄「列表已同步到哪一天」與「未解決的列」兩個完整度事實，並提供逐檔完整度讀取模型 `DividendCompleteness`；使用者可見行為不變。

**Architecture:** 兩市場列表解析帶出兩欄 → 寫入時一併存、已在庫的上市權／權息列以列表值補價；完成紀錄加 `prices_recorded`，舊紀錄的月份由回補重開一次補價。本月同步與回補在列表成功後，以一個 transaction 記錄兩個事實（未解決的列由 DB 現況推導）。讀取端只看 `DividendCompleteness`（兩個市場都查、有效列表日含完成紀錄）。3-2 起才有讀取端使用它。

**Tech Stack:** Flutter／Dart 3、Drift 2.32（SQLite 3.52、WAL、DateTime 存 ISO 文字）、mocktail、fake_async、flutter_test

**Spec:** `docs/plans/2026-10-01-dividend-read-side-design.md`（本計畫實作 §1–§3；3-2、3-3、3-4 在前一段提交後依當時程式碼另拆計畫）

## Global Constraints

- 不 bump schema fingerprint：新表以 `beforeOpen` 的 `Migrator.createTable` 補建；新欄以 `PRAGMA table_info` 檢查後 `ALTER TABLE ADD COLUMN`；新表不加進 `_userInputTableNames`
- 五張股利表（`dividend_distribution`、`dividend_month_ledger`、`dividend_month_failure`、`dividend_listing`、`dividend_unresolved`）同生共死：fingerprint reset 一起清空，保留規則必須一致
- DAO 的 transaction 第一句必須是寫入（drift 的 deferred BEGIN 下先讀後寫會拋 SQLITE_BUSY_SNAPSHOT）
- 日期一律當地午夜（`DateContext.normalize`／`CalendarMonth.firstDay`／`lastDay`）；`dividend_listing.listed_through` 本月同步寫 `min(今天, ctx.normalizedDate)`，回補寫月底
- update 鏈純 Dart：`lib/` 新檔不得 import flutter
- 本月同步的事實寫入失敗記進 errors、不往外拋；回補的 DB 錯誤照現行往外拋
- 每輪呼叫上限（30）與間隔（2 秒；修復工具 3 秒）不變
- live DB 只唯讀查詢（`file:...?mode=ro`，無 -wal 時加 `&immutable=1`）；寫入 live DB 只在副本彩排、備份、使用者同意之後；修復工具一律先 `--dry-run` 或對副本 `--db`
- commit／push 只在使用者說「提交」時做；Conventional Commits、中文、純文字、不加 Co-Authored-By。本計畫的 task 結尾一律「記錄進度」，整段在 Task 8 一次提交
- mutation 還原用備份檔，不用 git checkout；每個 mutant 跑所有消費者測試、timeout 300 秒

## Review Focus

1. **混用版本**：較舊的 build（例如 3-1 之前的 CLI 3c93c7ff；2026-09-27 的 GUI 更舊，連完成紀錄都不寫）只寫完成紀錄、不寫事實、不知道 `prices_recorded` → 新版必須自我修復：完成紀錄推導有效列表日、`prices_recorded` 預設 false 的紀錄被重開一次。測試在 Task 3（舊紀錄重開）與 Task 6（只有完成紀錄也算列過）
2. **凌晨補跑跨月**：10/1 01:00 執行、資料日是 9/30 → 不可替 10 月記任何列表日、9 月只記到 9/30。測試在 Task 5
3. **列表單列缺值（`--`）**：照收、該欄存 null，只讓那一檔在需要價格時判為不完整，不拖垮整個市場。測試在 Task 1（解析）、Task 6（條件 4）
4. **代號不在在市主檔**：列表上的未知代號記為 `notInMaster`；之後進了主檔，在重新列表前該檔都不完整（不可讀成「沒配息」）。測試在 Task 4、Task 6
5. **明細查到一半被限流**：已列表的事實照記（未查的列為 `pendingDetail`）、例外照常往外拋讓 UpdateService 翻中止旗標。測試在 Task 5

## 檔案結構

| 檔案 | 責任 | 動作 |
|:--|:--|:--|
| `lib/data/models/twse/exright_result.dart` | 列表／明細的資料模型 | 加 `referencePrice` |
| `lib/data/remote/twse_client.dart`、`tpex_client.dart` | 列表解析 | 兩欄必要、所有列帶值 |
| `lib/data/database/tables/market_data_tables.dart` | 表定義 | 配發表＋2 欄、完成紀錄＋1 欄、新表 `DividendListing`、`DividendUnresolved` |
| `lib/data/database/app_database.dart` | schema 補建、匯出 | `_ensureDividendPriceColumns`、`_ensureDividendFactsSchema`、表清單、export |
| `lib/data/database/dao/dividend_dao.dart` | 股利 DAO | 補價、完成紀錄寫 true、事實讀寫、原因列舉 |
| `lib/domain/services/update/dividend_syncer.dart` | 本月同步 | 寫兩欄、補價、記事實、`dataDate` |
| `lib/domain/services/update/dividend_backfiller.dart` | 歷史回補 | 補價、記事實 |
| `lib/domain/services/update/dividend_coverage.dart` | 回補完成判定 | 要求 `pricesRecorded` |
| `lib/domain/services/update_service.dart` | 步驟 6.6 | 傳 `dataDate` |
| `lib/domain/services/dividend_completeness.dart` | 逐檔完整度讀取模型（新檔） | 新增 |

---

### Task 1: 列表解析帶出前收盤價與除權息參考價

**Files:**
- Modify: `lib/data/models/twse/exright_result.dart`
- Modify: `lib/data/remote/twse_client.dart`（`TwseClient.parseExRightResults`）
- Modify: `lib/data/remote/tpex_client.dart`（`TpexClient.parseExRightResults`）
- Test: `test/data/remote/ex_right_result_parser_test.dart`

**Interfaces:**
- Produces: `ExRightResult.referencePrice`（`double?`，除權息參考價）；`ExRightResult.closeBefore` 改為兩市場所有列都帶值（缺值為 null）；`withDetail` 保留兩者

- [ ] **Step 1: 測試輔助函式加參數**

`_twseRow` 第 5 欄（`除權息參考價`）改為參數：

```dart
List<String> _twseRow(
  String date,
  String code,
  String value,
  String kind, {
  String close = '10.00',
  String reference = '9.50',
  String adjustedReference = '9.50',
}) => [
  date,
  code,
  '名稱',
  close,
  reference,
  value,
  kind,
  '11.00',
  '9.00',
  '9.50',
  adjustedReference,
  '$code,x',
  '',
  '',
  '',
];
```

`_tpexRow` 第 4、5 欄改為具名參數：

```dart
List<String> _tpexRow(
  String date,
  String code,
  String kind,
  String cash,
  String sharesPerThousand, {
  String close = '10.00',
  String reference = '9.50',
}) => [
  date,
  code,
  '名稱         ',
  close,
  reference,
  '0.000000',
  '0.000000',
  '0.000000',
  kind,
  '11.00',
  '9.00',
  '9.50',
  '9.50',
  cash,
  sharesPerThousand,
  '0',
  '0.00',
  '0',
  '0',
  '0',
  '0.00000000',
];
```

- [ ] **Step 2: 寫失敗測試**

在 `group('ExRightResult.withDetail', ...)` 之前加一組：

```dart
  group('列表帶出還原用的前收盤與除權息參考價（兩市場、所有列）', () {
    test('上市息、權、權息列都帶前收盤與除權息參考價（含千分位）', () {
      final rows = TwseClient.parseExRightResults(
        _twseBody([
          _twseRow(
            '114年03月18日',
            '2330',
            '4.500020',
            '息',
            close: '1,000.00',
            reference: '995.50',
          ),
          _twseRow(
            '114年01月05日',
            '4108',
            '0.916328',
            '權',
            close: '25.20',
            reference: '24.28',
          ),
          _twseRow(
            '114年01月13日',
            '2836',
            '0.600000',
            '權息',
            close: '10.60',
            reference: '10.00',
          ),
        ]),
        startDate: start,
        endDate: end,
      )!;
      expect([for (final r in rows) (r.closeBefore, r.referencePrice)], [
        (1000.0, 995.5),
        (25.2, 24.28),
        (10.6, 10.0),
      ]);
    });

    test('上市欄位清單缺除權息參考價：回 null', () {
      final body = _twseBody([
        _twseRow('114年03月18日', '2330', '4.500020', '息'),
      ]);
      body['fields'] = [
        for (final f in _twseFields) f == '除權息參考價' ? '其他' : f,
      ];
      expect(
        TwseClient.parseExRightResults(body, startDate: start, endDate: end),
        isNull,
      );
    });

    test('上市單列缺值：照收、該欄為 null（不讓一列拖垮整個市場）', () {
      final r = TwseClient.parseExRightResults(
        _twseBody([
          _twseRow(
            '114年03月18日',
            '2330',
            '4.500020',
            '息',
            close: '--',
            reference: '--',
          ),
        ]),
        startDate: start,
        endDate: end,
      )!.single;
      expect(r.cashDividend, 4.50002);
      expect(r.closeBefore, isNull);
      expect(r.referencePrice, isNull);
    });

    test('上櫃列帶前收盤與除權息參考價', () {
      final r = TpexClient.parseExRightResults(
        _tpexBody([
          _tpexRow(
            '114/06/18',
            '6762',
            '除權息',
            '0.30000000',
            '150.00000327',
            close: '1,200.00',
            reference: '1,043.22',
          ),
        ]),
        startDate: start,
        endDate: end,
      )!.single;
      expect(r.closeBefore, 1200);
      expect(r.referencePrice, 1043.22);
    });

    test('上櫃欄位清單缺前收盤或除權息參考價：回 null', () {
      for (final col in ['除權息前收盤價', '除權息參考價']) {
        final body = _tpexBody([
          _tpexRow('114/01/02', '6488', '除息', '3.00000000', '0.00000000'),
        ]);
        ((body['tables'] as List).first as Map)['fields'] = [
          for (final f in _tpexFields) f == col ? '其他' : f,
        ];
        expect(
          TpexClient.parseExRightResults(body, startDate: start, endDate: end),
          isNull,
          reason: col,
        );
      }
    });

    test('上櫃單列缺值：照收、該欄為 null', () {
      final r = TpexClient.parseExRightResults(
        _tpexBody([
          _tpexRow(
            '114/01/02',
            '6488',
            '除息',
            '3.00000000',
            '0.00000000',
            close: '--',
            reference: '--',
          ),
        ]),
        startDate: start,
        endDate: end,
      )!.single;
      expect(r.closeBefore, isNull);
      expect(r.referencePrice, isNull);
    });
  });
```

在既有測試「權息列補上明細後金額齊全」的最後加：

```dart
      expect(r.referencePrice, 9.5, reason: '除權息參考價照原列保留');
```

- [ ] **Step 3: 跑測試確認失敗**

Run: `flutter test test/data/remote/ex_right_result_parser_test.dart`
Expected: 編譯失敗，`The getter 'referencePrice' isn't defined for the class 'ExRightResult'`

- [ ] **Step 4: 實作**

`exright_result.dart`：建構子加 `this.referencePrice`，欄位與 `withDetail`：

```dart
  const ExRightResult({
    required this.symbol,
    required this.exDate,
    required this.cashDividend,
    required this.stockSharesPerThousand,
    this.closeBefore,
    this.referencePrice,
    this.dividendAdjustedReference,
  });
```

```dart
  /// 除權息前收盤價（兩市場列表；還原因子的分母，也用來核對明細）
  final double? closeBefore;

  /// 除權息參考價：交易所訂的除權息後參考價，含現金增資的影響（兩市場
  /// 列表）。還原因子＝[referencePrice] ÷ [closeBefore]
  final double? referencePrice;

  /// 減除股利參考價：只扣股利、不含現金增資的參考價（TWSE「權」「權息」
  /// 列；核對明細用，見 [matchesReference]）
  final double? dividendAdjustedReference;
```

```dart
  ExRightResult withDetail(ExRightDetail detail) => ExRightResult(
    symbol: symbol,
    exDate: exDate,
    cashDividend: detail.cashDividend,
    stockSharesPerThousand: detail.stockSharesPerThousand,
    closeBefore: closeBefore,
    referencePrice: referencePrice,
    dividendAdjustedReference: dividendAdjustedReference,
  );
```

`TwseClient.parseExRightResults`：

```dart
    final closeCol = fields.indexOf('除權息前收盤價');
    final referenceCol = fields.indexOf('除權息參考價');
    final adjustedCol = fields.indexOf('減除股利參考價');
    final cols = [
      dateCol,
      codeCol,
      valueCol,
      kindCol,
      closeCol,
      referenceCol,
      adjustedCol,
    ];
```

`parseRow` 內：

```dart
      final close = TwParseUtils.parseFormattedDouble(row[closeCol]);
      final reference = TwParseUtils.parseFormattedDouble(row[referenceCol]);
      final adjusted = TwParseUtils.parseFormattedDouble(row[adjustedCol]);
```

三個 `case` 的 `ExRightResult(...)` 都加上 `closeBefore: close, referencePrice: reference,`（「息」列原本沒有 `closeBefore`，要補上；「權」「權息」列保留 `dividendAdjustedReference: adjusted`）。

doc 的拒收條件改為：

```dart
  /// 回傳 `[]`＝區間內沒有除權息；`null`＝回應不可信：stat 異常、回應的
  /// `strDate`/`endDate` 與請求不符、缺必要欄位（含除權息前收盤價、除權息
  /// 參考價、減除股利參考價），或**任何一列**解析不了（日期無效、代號空白、
  /// 類別不明、「息」列金額缺漏、「權」「權息」列缺除權息前收盤價或減除股利
  /// 參考價——這兩欄用來核對明細，見 [ExRightResult.matchesReference]）。
  /// 前收盤與除權息參考價單列缺值時照收、存 null：它們只供還原用，讀取端以
  /// 完整度判斷，不讓一列拖垮整個市場的列表。
```

`TpexClient.parseExRightResults`：

```dart
    final closeCol = fields.indexOf('除權息前收盤價');
    final referenceCol = fields.indexOf('除權息參考價');
    final cols = [dateCol, codeCol, cashCol, sharesCol, closeCol, referenceCol];
```

```dart
      return ExRightResult(
        symbol: code,
        exDate: exDate,
        cashDividend: cash,
        stockSharesPerThousand: shares,
        closeBefore: TwParseUtils.parseFormattedDouble(row[closeCol]),
        referencePrice: TwParseUtils.parseFormattedDouble(row[referenceCol]),
      );
```

doc 加一句：`前收盤與除權息參考價為必要欄位；單列缺值時照收、存 null（理由同 TWSE）。`

- [ ] **Step 5: 跑測試確認通過**

Run: `flutter test test/data/remote/ex_right_result_parser_test.dart`
Expected: 全部通過

- [ ] **Step 6: 記錄進度（不 commit）**

---

### Task 2: 配發表與完成紀錄補欄、寫入列帶價格

**Files:**
- Modify: `lib/data/database/tables/market_data_tables.dart`
- Regenerate: `lib/data/database/tables/market_data_tables.drift.dart`、`lib/data/database/app_database.drift.dart`
- Modify: `lib/data/database/app_database.dart`
- Modify: `lib/data/database/dao/dividend_dao.dart`
- Modify: `lib/domain/services/update/dividend_syncer.dart`（`dividendDistributionCompanion`、新增 `dividendListedPrice`）
- Test: `test/data/database/dividend_price_columns_migration_test.dart`（新檔）
- Test: `test/data/database/dao/dividend_month_dao_test.dart`
- Test: `test/domain/services/update/dividend_distribution_sync_test.dart`

**Interfaces:**
- Consumes: Task 1 的 `ExRightResult.closeBefore`／`referencePrice`
- Produces:
  - `DividendDistributionEntry.closeBefore`／`referencePrice`（`double?`）
  - `DividendMonthLedgerEntry.pricesRecorded`（`bool`）
  - `typedef DividendListedPrice = ({String symbol, DateTime exDate, double? closeBefore, double? referencePrice});`（`app_database.dart` 匯出）
  - `Future<void> AppDatabase.updateDividendDistributionPrices(List<DividendListedPrice> rows)`
  - `DividendListedPrice dividendListedPrice(ExRightResult row)`（`dividend_syncer.dart`）

- [ ] **Step 1: 寫失敗測試（遷移）**

新檔 `test/data/database/dividend_price_columns_migration_test.dart`：

```dart
// dividend_distribution 補 close_before／reference_price、dividend_month_ledger
// 補 prices_recorded 的 ALTER 升級路徑（2026-10-03）
//
// bump fingerprint 會 wipe 全部行情表，所以加欄走 beforeOpen 的 idempotent
// ALTER。這條測試模擬真實升級：帶舊 schema＋資料的 DB 被新版開啟。
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/utils/calendar_month.dart';
import 'package:daredevil/data/database/app_database.dart';

void main() {
  late Directory tempDir;
  late File dbFile;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('dividend_price_cols');
    dbFile = File('${tempDir.path}/db.sqlite');
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  test('🚨 舊 DB 開啟後補欄：配發列保留、價格為 null；完成紀錄保留、prices_recorded 為 false', () async {
    final db1 = AppDatabase(NativeDatabase(dbFile));
    await db1.upsertStocks([
      StockMasterCompanion.insert(symbol: '2330', name: '台積電', market: 'TWSE'),
    ]);
    await db1.upsertDividendDistributions([
      DividendDistributionCompanion.insert(
        symbol: '2330',
        exDate: DateTime(2025, 9, 16),
        cashDividend: 5,
        stockSharesPerThousand: 0,
      ),
    ]);
    await db1.completeDividendMonth(
      market: 'TWSE',
      month: const CalendarMonth(2025, 9),
      rows: const [],
      expectedKeys: {('2330', DateTime(2025, 9, 16))},
      listedRows: 1,
      skippedSymbols: const {},
      completedAt: DateTime(2026, 9, 30),
    );
    for (final column in ['close_before', 'reference_price']) {
      await db1.customStatement(
        'ALTER TABLE dividend_distribution DROP COLUMN $column',
      );
    }
    await db1.customStatement(
      'ALTER TABLE dividend_month_ledger DROP COLUMN prices_recorded',
    );
    await db1.close();

    final db2 = AppDatabase(NativeDatabase(dbFile));
    final row = (await db2.getDividendDistributions('2330')).single;
    expect(row.cashDividend, 5);
    expect(row.closeBefore, isNull);
    expect(row.referencePrice, isNull);
    final ledger = (await db2.getDividendMonthLedgerEntries()).single;
    expect(ledger.pricesRecorded, isFalse, reason: '舊完成紀錄要讓回補重開補價');
    await db2.close();
  });
}
```

- [ ] **Step 2: 寫失敗測試（DAO）**

`test/data/database/dao/dividend_month_dao_test.dart` 的 `main()` 最後（`月份超出 1–12` 之前）加：

```dart
  test('completeDividendMonth 寫下的完成紀錄記為「已存價格」', () async {
    expect(await complete(expected: const {}), isEmpty);
    expect(
      (await db.getDividendMonthLedgerEntries()).single.pricesRecorded,
      isTrue,
    );
  });

  test('updateDividendDistributionPrices：只更新已在庫列的兩欄，不動金額、不新增', () async {
    await db.upsertDividendDistributions([row('2330', DateTime(2025, 9, 16))]);

    await db.updateDividendDistributionPrices([
      (
        symbol: '2330',
        exDate: DateTime(2025, 9, 16),
        closeBefore: 1000.0,
        referencePrice: 995.0,
      ),
      (
        symbol: '6488',
        exDate: DateTime(2025, 9, 17),
        closeBefore: 300.0,
        referencePrice: 297.0,
      ),
    ]);

    final stored = (await db.getDividendDistributions('2330')).single;
    expect(
      (stored.cashDividend, stored.closeBefore, stored.referencePrice),
      (1.0, 1000.0, 995.0),
    );
    expect(await db.getDividendDistributions('6488'), isEmpty);
  });
```

- [ ] **Step 3: 寫失敗測試（同步寫入列帶價格）**

`test/domain/services/update/dividend_distribution_sync_test.dart` 加：

```dart
  test('寫入列帶列表的前收盤與除權息參考價（上櫃、上市息列、查過明細的列）', () async {
    stubTwse([
      ExRightResult(
        symbol: '2330',
        exDate: DateTime(2026, 9, 16),
        cashDividend: 5.0,
        stockSharesPerThousand: 0,
        closeBefore: 1000,
        referencePrice: 995,
      ),
      ExRightResult(
        symbol: '2836',
        exDate: DateTime(2026, 9, 17),
        cashDividend: null,
        stockSharesPerThousand: null,
        closeBefore: 10.6,
        referencePrice: 10.0,
      ),
    ]);
    stubDetail('2836', 0.15, 45);
    when(
      () => tpex.getExRightResults(
        startDate: any(named: 'startDate'),
        endDate: any(named: 'endDate'),
      ),
    ).thenAnswer(
      (_) async => [
        ExRightResult(
          symbol: '6762',
          exDate: DateTime(2026, 9, 18),
          cashDividend: 0.3,
          stockSharesPerThousand: 150,
          closeBefore: 120,
          referencePrice: 104.08,
        ),
      ],
    );

    await syncer.syncDistributions(today: today, maxCalls: 30);

    Future<(double?, double?)> prices(String symbol) async {
      final r = (await db.getDividendDistributions(symbol)).single;
      return (r.closeBefore, r.referencePrice);
    }

    expect(await prices('2330'), (1000.0, 995.0));
    expect(await prices('2836'), (10.6, 10.0));
    expect(await prices('6762'), (120.0, 104.08));
  });
```

- [ ] **Step 4: 跑測試確認失敗**

Run: `flutter test test/data/database/dividend_price_columns_migration_test.dart test/data/database/dao/dividend_month_dao_test.dart test/domain/services/update/dividend_distribution_sync_test.dart`
Expected: 編譯失敗（`closeBefore`／`pricesRecorded`／`updateDividendDistributionPrices` 未定義）

- [ ] **Step 5: 表定義加欄**

`DividendDistribution`（`stockSharesPerThousand` 之後）：

```dart
  /// 除權息前收盤價（列表）。還原因子的分母。null＝列表缺值，或 2026-10
  /// 以前寫入、尚未由回補補價的列
  RealColumn get closeBefore => real().nullable()();

  /// 除權息參考價（列表）：交易所訂的除權息後參考價，含現金增資的影響。
  /// 還原因子＝[referencePrice] ÷ [closeBefore]
  RealColumn get referencePrice => real().nullable()();
```

`DividendMonthLedger`（`skippedSymbols` 之後）：

```dart
  /// 完成時是否已以列表記錄該月各列的前收盤與除權息參考價。2026-10 以前
  /// 寫下的紀錄為 false，回補重開這些月份一次（只打列表）補價
  BoolColumn get pricesRecorded =>
      boolean().withDefault(const Constant(false))();
```

- [ ] **Step 6: 重產 drift 程式碼**

先確認沒有其他 `dart run`／`flutter test` 行程（`pgrep -f "flutter_tester|dart run" | wc -l` 為 0；不要用 `-fl`）。
Run: `dart run build_runner build --delete-conflicting-outputs`
Expected: 成功；`market_data_tables.drift.dart` 出現 `closeBefore`、`referencePrice`、`pricesRecorded`

- [ ] **Step 7: 既有 DB 補欄**

`app_database.dart` 的 `beforeOpen` 在 `await _ensureDividendBackfillSchema();` 之後加 `await _ensureDividendPriceColumns();`，並在 `_ensureDividendBackfillSchema` 之後新增：

```dart
  /// 股利配發表補前收盤與除權息參考價、完成紀錄補「已存價格」
  /// （2026-10-03，additive）。
  ///
  /// 沿 [_ensureDealerSelfNetColumn] 先例：PRAGMA 檢查後 ALTER TABLE ADD
  /// COLUMN，不 bump fingerprint。既有配發列補進來是 null、既有完成紀錄是
  /// false：回補據此把那些月份重開一次、只打列表補價（見
  /// `isDividendMonthComplete`）。
  Future<void> _ensureDividendPriceColumns() async {
    Future<Set<String>> columnsOf(String table) async => {
      for (final row in await customSelect(
        "PRAGMA table_info('$table')",
      ).get())
        row.read<String>('name'),
    };

    final distribution = await columnsOf('dividend_distribution');
    for (final column in const ['close_before', 'reference_price']) {
      if (distribution.contains(column)) continue;
      await customStatement(
        'ALTER TABLE dividend_distribution ADD COLUMN $column REAL',
      );
      AppLogger.info(
        'AppDatabase',
        '既有 DB 補上 dividend_distribution.$column 欄（既有列為 null）',
      );
    }
    if (!(await columnsOf('dividend_month_ledger')).contains(
      'prices_recorded',
    )) {
      await customStatement(
        'ALTER TABLE dividend_month_ledger ADD COLUMN prices_recorded '
        'INTEGER NOT NULL DEFAULT 0 CHECK (prices_recorded IN (0, 1))',
      );
      AppLogger.info(
        'AppDatabase',
        '既有 DB 補上 dividend_month_ledger.prices_recorded 欄（既有紀錄為 false）',
      );
    }
  }
```

- [ ] **Step 8: DAO**

`dividend_dao.dart`：在 `completeDividendMonth` 的 `DividendMonthLedgerCompanion.insert(...)` 加 `pricesRecorded: const Value(true),`。檔尾（`encodeDividendSymbols` 之前）加：

```dart
/// 列表上一列的前收盤與除權息參考價（補價用）
typedef DividendListedPrice = ({
  String symbol,
  DateTime exDate,
  double? closeBefore,
  double? referencePrice,
});
```

mixin 內（`deleteDividendDistribution` 之後）加：

```dart
  /// 以列表的值更新已在庫列的前收盤與除權息參考價；不動金額，不在庫的鍵
  /// 不新增。上市「權」「權息」列明細已查過、不再重查時用它補價。
  Future<void> updateDividendDistributionPrices(
    List<DividendListedPrice> rows,
  ) async {
    if (rows.isEmpty) return;
    await batch((b) {
      for (final r in rows) {
        b.update(
          dividendDistribution,
          DividendDistributionCompanion(
            closeBefore: Value(r.closeBefore),
            referencePrice: Value(r.referencePrice),
          ),
          where: (t) => t.symbol.equals(r.symbol) & t.exDate.equals(r.exDate),
        );
      }
    });
  }
```

`app_database.dart` 的 dividend_dao export 加上 `DividendListedPrice`：

```dart
export 'package:daredevil/data/database/dao/dividend_dao.dart'
    show
        DividendListedPrice,
        DividendMonthLedgerEntryX,
        DividendMonthFailureEntryX,
        encodeDividendSymbols;
```

- [ ] **Step 9: 寫入列帶價格**

`dividend_syncer.dart`：

```dart
/// 已拆開現金與配股的除權除息列 → 股利配發表的寫入列（本月同步與歷史回補
/// 共用），含列表的前收盤與除權息參考價。列表拆不出、尚未補明細的列
/// （[ExRightResult.needsDetail]）不可傳入。
DividendDistributionCompanion dividendDistributionCompanion(
  ExRightResult row,
) => DividendDistributionCompanion.insert(
  symbol: row.symbol,
  exDate: row.exDate,
  cashDividend: row.cashDividend!,
  stockSharesPerThousand: row.stockSharesPerThousand!,
  closeBefore: Value(row.closeBefore),
  referencePrice: Value(row.referencePrice),
);

/// 列表上的前收盤與除權息參考價（已在庫列補價用，見
/// `AppDatabase.updateDividendDistributionPrices`）
DividendListedPrice dividendListedPrice(ExRightResult row) => (
  symbol: row.symbol,
  exDate: row.exDate,
  closeBefore: row.closeBefore,
  referencePrice: row.referencePrice,
);
```

- [ ] **Step 10: 跑測試確認通過**

Run: `flutter test test/data/database/ test/domain/services/update/dividend_distribution_sync_test.dart`
Expected: 全部通過

- [ ] **Step 11: 記錄進度（不 commit）**

---

### Task 3: 舊完成紀錄重開補價；已在庫的上市權／權息列以列表值補價

**Files:**
- Modify: `lib/domain/services/update/dividend_coverage.dart`（`isDividendMonthComplete`）
- Modify: `lib/domain/services/update/dividend_backfiller.dart`（`_processTwse`）
- Modify: `lib/domain/services/update/dividend_syncer.dart`（`syncDistributions` 的上市段）
- Test: `test/domain/services/update/dividend_coverage_test.dart`
- Test: `test/domain/services/update/dividend_backfiller_test.dart`
- Test: `test/domain/services/update/dividend_distribution_sync_test.dart`
- Test: `test/domain/services/update_service_test.dart`（mock stub）

**Interfaces:**
- Consumes: Task 2 的 `pricesRecorded`、`updateDividendDistributionPrices`、`dividendListedPrice`
- Produces: `isDividendMonthComplete` 要求 `entry.pricesRecorded`

- [ ] **Step 1: 測試輔助函式**

`dividend_coverage_test.dart` 的 `_ledger` 加參數 `bool pricesRecorded = true`，建構時傳 `pricesRecorded: pricesRecorded`。

`dividend_backfiller_test.dart` 的三個列建構函式帶價格（金額不變）：

```dart
ExRightResult _cash(String symbol, DateTime exDate, double cash) =>
    ExRightResult(
      symbol: symbol,
      exDate: exDate,
      cashDividend: cash,
      stockSharesPerThousand: 0,
      closeBefore: 100,
      referencePrice: 100 - cash,
    );

/// 權息列（2836 2021-01-13 的真實數字：前收 10.60、減除股利參考價 10.00，
/// 明細 0.15 元／45 股；沒有現金增資，除權息參考價同為 10.00）
ExRightResult _rightsAndCash(String symbol, DateTime exDate) => ExRightResult(
  symbol: symbol,
  exDate: exDate,
  cashDividend: null,
  stockSharesPerThousand: null,
  closeBefore: 10.60,
  referencePrice: 10.00,
  dividendAdjustedReference: 10.00,
);

/// 只有現金增資的權列（前收＝減除股利參考價，明細 0 元／0 股；除權息
/// 參考價反映增資，低於前收）
ExRightResult _rightsIssue(String symbol, DateTime exDate) => ExRightResult(
  symbol: symbol,
  exDate: exDate,
  cashDividend: 0,
  stockSharesPerThousand: null,
  closeBefore: 25.20,
  referencePrice: 24.80,
  dividendAdjustedReference: 25.20,
);
```

`dividend_backfiller_test.dart`、`dividend_distribution_sync_test.dart` 與 `update_service_test.dart` 的 `setUpAll` 加 `registerFallbackValue(<DividendListedPrice>[]);`。三個檔案中以 `MockAppDatabase` 建立的 mock（同步的 2 秒間隔測試、回補的兩條 mock 測試、`update_service_test.dart` 的 `setUp`）都加：

```dart
      when(
        () => mockDb.updateDividendDistributionPrices(any()),
      ).thenAnswer((_) async {});
```

- [ ] **Step 2: 寫失敗測試**

`dividend_coverage_test.dart` 的 `group('isDividendMonthComplete', ...)` 加：

```dart
    test('完成時尚未記錄價格（2026-10 以前的紀錄）→ 未完成（重開補價）', () {
      expect(
        isDividendMonthComplete(
          _ledger(MarketCode.twse, aug, pricesRecorded: false),
          knownSymbols: {'2330'},
          currentMonth: current,
        ),
        isFalse,
      );
    });
```

`dividend_backfiller_test.dart` 加一組（放在 `group('排程：完成、退避、重開', ...)` 之後）：

```dart
  group('補價：2026-10 以前的完成紀錄', () {
    Future<void> legacyComplete(String market, CalendarMonth m) => db
        .into(db.dividendMonthLedger)
        .insert(
          DividendMonthLedgerCompanion.insert(
            market: market,
            year: m.year,
            month: m.month,
            completedAt: now,
            listedRows: 1,
            knownRows: 1,
            skippedSymbols: '',
          ),
        );

    const twseAug = DividendBackfillScope(
      from: aug,
      to: aug,
      markets: {MarketCode.twse},
    );
    const tpexAug = DividendBackfillScope(
      from: aug,
      to: aug,
      markets: {MarketCode.tpex},
    );

    test('上市：重開只打列表、不重查明細，已在庫列補上兩欄並記為已存價格', () async {
      await db.upsertDividendDistributions([
        DividendDistributionCompanion.insert(
          symbol: '2836',
          exDate: DateTime(2026, 8, 13),
          cashDividend: 0.15,
          stockSharesPerThousand: 45,
        ),
      ]);
      await legacyComplete(MarketCode.twse, aug);
      listTwse(aug, [_rightsAndCash('2836', DateTime(2026, 8, 13))]);

      final summary = await run(scope: twseAug);

      expect(summary.calls, 1);
      verifyNever(() => twse.getExRightDetail(any(), any()));
      final r = (await db.getDividendDistributions('2836')).single;
      expect(
        (r.cashDividend, r.closeBefore, r.referencePrice),
        (0.15, 10.60, 10.00),
      );
      expect(
        (await db.getDividendMonthLedgerEntries()).single.pricesRecorded,
        isTrue,
      );
    });

    test('上櫃：重開只打 1 次列表，列以列表值重寫並記為已存價格', () async {
      await db.upsertDividendDistributions([
        DividendDistributionCompanion.insert(
          symbol: '6488',
          exDate: DateTime(2026, 8, 10),
          cashDividend: 3,
          stockSharesPerThousand: 0,
        ),
      ]);
      await legacyComplete(MarketCode.tpex, aug);
      listTpex(aug, [_cash('6488', DateTime(2026, 8, 10), 3)]);

      final summary = await run(scope: tpexAug);

      expect(summary.calls, 1);
      final r = (await db.getDividendDistributions('6488')).single;
      expect((r.closeBefore, r.referencePrice), (100.0, 97.0));
      expect(
        (await db.getDividendMonthLedgerEntries()).single.pricesRecorded,
        isTrue,
      );
    });

    test('重開過一次後不再重開（即使列表本身缺值）', () async {
      await legacyComplete(MarketCode.tpex, aug);
      listTpex(aug, [
        ExRightResult(
          symbol: '6488',
          exDate: DateTime(2026, 8, 10),
          cashDividend: 3,
          stockSharesPerThousand: 0,
        ),
      ]);

      await run(scope: tpexAug);
      await run(scope: tpexAug);

      verify(
        () => tpex.getExRightResults(
          startDate: aug.firstDay,
          endDate: aug.lastDay,
        ),
      ).called(1);
    });
  });
```

`dividend_distribution_sync_test.dart` 加：

```dart
  test('已查過明細的權息列不重查，但以列表值補上前收盤與參考價', () async {
    await db.upsertDividendDistributions([
      DividendDistributionCompanion.insert(
        symbol: '2836',
        exDate: DateTime(2026, 9, 17),
        cashDividend: 0.15,
        stockSharesPerThousand: 45,
      ),
    ]);
    stubTwse([
      ExRightResult(
        symbol: '2836',
        exDate: DateTime(2026, 9, 17),
        cashDividend: null,
        stockSharesPerThousand: null,
        closeBefore: 10.6,
        referencePrice: 10.0,
      ),
    ]);

    await syncer.syncDistributions(today: today, maxCalls: 30);

    verifyNever(() => twse.getExRightDetail(any(), any()));
    final r = (await db.getDividendDistributions('2836')).single;
    expect((r.cashDividend, r.closeBefore, r.referencePrice), (0.15, 10.6, 10.0));
  });
```

- [ ] **Step 3: 跑測試確認失敗**

Run: `flutter test test/domain/services/update/dividend_coverage_test.dart test/domain/services/update/dividend_backfiller_test.dart test/domain/services/update/dividend_distribution_sync_test.dart`
Expected: 新增的 5 條失敗（重開沒發生、兩欄為 null）

- [ ] **Step 4: 實作**

`dividend_coverage.dart`：

```dart
/// 某（市場, 月）的完成紀錄是否仍涵蓋現況：有紀錄、月份早於本月、紀錄是
/// 在該月結束之後才寫的（月中寫的只涵蓋到寫入當下，下個月起不能當成整月；
/// 也涵蓋時鐘回撥）、當時略過的代號如今都不在 [knownSymbols]（在市主檔）內，
/// 而且完成時已以列表記錄各列的前收盤與除權息參考價（2026-10 以前的紀錄
/// 沒有，回補重開一次補價）。
bool isDividendMonthComplete(
  DividendMonthLedgerEntry? entry, {
  required Set<String> knownSymbols,
  required CalendarMonth currentMonth,
}) =>
    entry != null &&
    entry.pricesRecorded &&
    entry.calendarMonth.isBefore(currentMonth) &&
    entry.calendarMonth.isBefore(CalendarMonth.of(entry.completedAt)) &&
    !entry.skippedSymbolSet.any(knownSymbols.contains);
```

`dividend_backfiller.dart` 的 `_processTwse`，在 `await _db.upsertDividendDistributions([... if (!r.needsDetail) ...]);` 之後加：

```dart
    // 明細已查過的權／權息列不重查，但以這次列表的值補上前收盤與參考價
    // （2026-10 以前寫入的列沒有；不在庫的鍵不受影響，查明細時帶著寫入）
    await _db.updateDividendDistributionPrices([
      for (final r in known)
        if (r.needsDetail) dividendListedPrice(r),
    ]);
```

`dividend_syncer.dart` 的 `syncDistributions` 上市段，在 `written += await _writeDistributions([... if (!row.needsDetail) row ...]);` 之後加：

```dart
        await _db.updateDividendDistributionPrices([
          for (final row in known)
            if (row.needsDetail) dividendListedPrice(row),
        ]);
```

- [ ] **Step 5: 跑測試確認通過**

Run: `flutter test test/domain/services/update/ test/domain/services/update_service_test.dart`
Expected: 全部通過（含既有測試：`completeDividendMonth` 寫 true，既有「已完成跳過」照舊）

- [ ] **Step 6: 記錄進度（不 commit）**

---

### Task 4: 完整度事實兩張表與 `recordDividendListing`

**Files:**
- Modify: `lib/data/database/tables/market_data_tables.dart`（新表 `DividendListing`、`DividendUnresolved`）
- Regenerate: drift 產生碼
- Modify: `lib/data/database/app_database.dart`（表清單、`_ensureDividendFactsSchema`、export）
- Modify: `lib/data/database/dao/dividend_dao.dart`
- Test: `test/data/database/dao/dividend_listing_dao_test.dart`（新檔）
- Test: `test/data/database/dividend_backfill_schema_test.dart`

**Interfaces:**
- Produces:
  - `enum DividendUnresolvedReason { pendingDetail, detailFailed, referenceMismatch, notInMaster }`，`code` 為存庫字串（`app_database.dart` 匯出）
  - `Future<List<DividendListingEntry>> getDividendListings()`
  - `Future<List<DividendUnresolvedEntry>> getDividendUnresolved()`
  - `Future<Set<(String, DateTime)>> getDividendMissingPriceKeys()`
  - `Future<void> recordDividendListing({required String market, required DateTime from, required DateTime to, required DateTime listedThrough, required Set<(String, DateTime)> listedKnownKeys, required Set<(String, DateTime)> notInMasterKeys, Map<(String, DateTime), DividendUnresolvedReason> reasons = const {}, required DateTime recordedAt})`

- [ ] **Step 1: 寫失敗測試**

新檔 `test/data/database/dao/dividend_listing_dao_test.dart`：

```dart
// 除權除息完整度事實（dividend_listing、dividend_unresolved）的寫入
//
// 列表成功後以一個 transaction 記錄：未解決的列由 DB 現況推導、整批取代；
// 列表日只能連續前進，有效列表日含完成紀錄（完成＝列到月底）。
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/utils/calendar_month.dart';
import 'package:daredevil/data/database/app_database.dart';

void main() {
  late AppDatabase db;
  final recordedAt = DateTime(2026, 10, 2, 15, 30);

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.upsertStocks([
      StockMasterCompanion.insert(symbol: '2330', name: '台積電', market: 'TWSE'),
      StockMasterCompanion.insert(symbol: '2836', name: '高雄銀', market: 'TWSE'),
    ]);
  });

  tearDown(() => db.close());

  Future<void> record({
    String market = 'TWSE',
    required DateTime from,
    required DateTime to,
    DateTime? listedThrough,
    Set<(String, DateTime)> known = const {},
    Set<(String, DateTime)> notInMaster = const {},
    Map<(String, DateTime), DividendUnresolvedReason> reasons = const {},
  }) => db.recordDividendListing(
    market: market,
    from: from,
    to: to,
    listedThrough: listedThrough ?? to,
    listedKnownKeys: known,
    notInMasterKeys: notInMaster,
    reasons: reasons,
    recordedAt: recordedAt,
  );

  Future<Map<String, DateTime>> listings() async => {
    for (final e in await db.getDividendListings())
      '${e.market} ${CalendarMonth(e.year, e.month)}': e.listedThrough,
  };

  Future<Map<String, String>> unresolved() async => {
    for (final u in await db.getDividendUnresolved())
      '${u.market} ${u.symbol} ${u.exDate.month}/${u.exDate.day}': u.reason,
  };

  group('未解決的列', () {
    test('列表上的已知列減去在庫的列；原因依傳入，沒有的記 pendingDetail；未知代號記 notInMaster', () async {
      await db.upsertDividendDistributions([
        DividendDistributionCompanion.insert(
          symbol: '2330',
          exDate: DateTime(2026, 9, 16),
          cashDividend: 5,
          stockSharesPerThousand: 0,
        ),
      ]);

      await record(
        from: DateTime(2026, 9, 1),
        to: DateTime(2026, 9, 30),
        known: {
          ('2330', DateTime(2026, 9, 16)),
          ('2836', DateTime(2026, 9, 17)),
          ('2836', DateTime(2026, 9, 18)),
        },
        notInMaster: {('00950B', DateTime(2026, 9, 18))},
        reasons: {
          ('2836', DateTime(2026, 9, 17)):
              DividendUnresolvedReason.referenceMismatch,
        },
      );

      expect(await unresolved(), {
        'TWSE 2836 9/17': 'REFERENCE_MISMATCH',
        'TWSE 2836 9/18': 'PENDING_DETAIL',
        'TWSE 00950B 9/18': 'NOT_IN_MASTER',
      });
    });

    test('整批取代：範圍內舊的未解決列被清掉，範圍外與另一市場的不動', () async {
      await record(
        from: DateTime(2026, 9, 1),
        to: DateTime(2026, 9, 30),
        known: {('2836', DateTime(2026, 9, 17))},
      );
      await record(
        market: 'TPEx',
        from: DateTime(2026, 9, 1),
        to: DateTime(2026, 9, 30),
        notInMaster: {('6762', DateTime(2026, 9, 17))},
      );
      await record(
        from: DateTime(2026, 8, 1),
        to: DateTime(2026, 8, 31),
        known: {('2836', DateTime(2026, 8, 13))},
      );

      await record(from: DateTime(2026, 9, 1), to: DateTime(2026, 9, 30));

      expect(await unresolved(), {
        'TPEx 6762 9/17': 'NOT_IN_MASTER',
        'TWSE 2836 8/13': 'PENDING_DETAIL',
      });
    });

    test('未知代號的列若已在庫（之前在主檔時寫入）不記為未解決', () async {
      await db.upsertDividendDistributions([
        DividendDistributionCompanion.insert(
          symbol: '2330',
          exDate: DateTime(2026, 9, 16),
          cashDividend: 5,
          stockSharesPerThousand: 0,
        ),
      ]);

      await record(
        from: DateTime(2026, 9, 1),
        to: DateTime(2026, 9, 30),
        notInMaster: {('2330', DateTime(2026, 9, 16))},
      );

      expect(await unresolved(), isEmpty);
    });
  });

  group('列表日', () {
    test('回補整月：列到月底', () async {
      await record(from: DateTime(2026, 8, 1), to: DateTime(2026, 8, 31));
      expect(await listings(), {'TWSE 2026-08': DateTime(2026, 8, 31)});
    });

    test('本月同步：記到列表日（資料日），範圍跨上個月尾巴時上個月要連續才前進', () async {
      await record(
        from: DateTime(2026, 9, 1),
        to: DateTime(2026, 9, 26),
      );

      // 10/2 的本月同步：範圍 9/25～10/2，資料日 10/2
      await record(
        from: DateTime(2026, 9, 25),
        to: DateTime(2026, 10, 2),
      );

      expect(await listings(), {
        'TWSE 2026-09': DateTime(2026, 9, 30),
        'TWSE 2026-10': DateTime(2026, 10, 2),
      });
    });

    test('上個月中間有一段沒列過：不前進（本月照記）', () async {
      await record(
        from: DateTime(2026, 9, 1),
        to: DateTime(2026, 9, 20),
      );

      await record(
        from: DateTime(2026, 9, 25),
        to: DateTime(2026, 10, 2),
      );

      expect(await listings(), {
        'TWSE 2026-09': DateTime(2026, 9, 20),
        'TWSE 2026-10': DateTime(2026, 10, 2),
      });
    });

    test('上個月有完成紀錄（舊版只寫完成紀錄）：視為列到月底，不需要再寫列表日', () async {
      await db.completeDividendMonth(
        market: 'TWSE',
        month: const CalendarMonth(2026, 8),
        rows: const [],
        expectedKeys: const {},
        listedRows: 0,
        skippedSymbols: const {},
        completedAt: DateTime(2026, 9, 1),
      );

      await record(
        from: DateTime(2026, 8, 26),
        to: DateTime(2026, 9, 2),
      );

      expect(await listings(), {'TWSE 2026-09': DateTime(2026, 9, 2)});
    });

    test('凌晨補跑跨月：資料日 9/30、今天 10/1，不替 10 月記列表日', () async {
      await record(
        from: DateTime(2026, 9, 1),
        to: DateTime(2026, 9, 29),
      );

      await record(
        from: DateTime(2026, 9, 24),
        to: DateTime(2026, 10, 1),
        listedThrough: DateTime(2026, 9, 30),
      );

      expect(await listings(), {'TWSE 2026-09': DateTime(2026, 9, 30)});
    });

    test('不倒退：較短的列表不覆蓋較長的列表日', () async {
      await record(from: DateTime(2026, 9, 1), to: DateTime(2026, 9, 26));
      await record(from: DateTime(2026, 9, 1), to: DateTime(2026, 9, 20));
      expect(await listings(), {'TWSE 2026-09': DateTime(2026, 9, 26)});
    });
  });

  test('缺前收盤或除權息參考價的配發列', () async {
    await db.upsertDividendDistributions([
      DividendDistributionCompanion.insert(
        symbol: '2330',
        exDate: DateTime(2026, 9, 16),
        cashDividend: 5,
        stockSharesPerThousand: 0,
        closeBefore: const Value(1000),
        referencePrice: const Value(995),
      ),
      DividendDistributionCompanion.insert(
        symbol: '2836',
        exDate: DateTime(2026, 9, 17),
        cashDividend: 0.15,
        stockSharesPerThousand: 45,
        closeBefore: const Value(10.6),
      ),
    ]);

    expect(await db.getDividendMissingPriceKeys(), {
      ('2836', DateTime(2026, 9, 17)),
    });
  });
}
```

（此檔需 `import 'package:drift/drift.dart' show Value;`。）

`test/data/database/dividend_backfill_schema_test.dart`：

- 第一條測試改名為「既有 DB 沒有四張股利紀錄表：開啟後補建，行情資料保留」，`DROP TABLE` 加上 `dividend_listing`、`dividend_unresolved`，並斷言 `getDividendListings()`、`getDividendUnresolved()` 為空
- 第二條（fingerprint reset）在 `db1.close()` 之前加：

```dart
    await db1.recordDividendListing(
      market: 'TWSE',
      from: DateTime(2026, 10, 1),
      to: DateTime(2026, 10, 2),
      listedThrough: DateTime(2026, 10, 2),
      listedKnownKeys: {('2330', DateTime(2026, 10, 2))},
      notInMasterKeys: const {},
      recordedAt: DateTime(2026, 10, 2),
    );
    expect(await db1.getDividendListings(), hasLength(1));
    expect(await db1.getDividendUnresolved(), hasLength(1));
```

  reset 後加 `expect(await db2.getDividendListings(), isEmpty); expect(await db2.getDividendUnresolved(), isEmpty);`，測試名改為「fingerprint reset：五張股利表一起清空」

- [ ] **Step 2: 跑測試確認失敗**

Run: `flutter test test/data/database/dao/dividend_listing_dao_test.dart test/data/database/dividend_backfill_schema_test.dart`
Expected: 編譯失敗（`recordDividendListing`、`DividendUnresolvedReason` 等未定義）

- [ ] **Step 3: 表定義**

`market_data_tables.dart`，在 `DividendMonthFailure` 之後：

```dart
/// 除權除息列表已同步到哪一天：一列＝某市場某月的列表已涵蓋到
/// [listedThrough]（含）
///
/// 本月同步與歷史回補在列表成功後寫入（DAO `recordDividendListing`），只能
/// 連續前進。讀取端的「有效列表日」另把完成紀錄算進去（完成＝列到月底），
/// 只寫完成紀錄的舊版程式寫下的完成也算數。與 [DividendDistribution] 同生
/// 共死，不可加進保留白名單。
@DataClassName('DividendListingEntry')
class DividendListing extends Table {
  /// `MarketCode.twse`／`MarketCode.tpex`
  TextColumn get market => text()();

  /// 西元年
  IntColumn get year => integer()();

  /// 1–12
  // Drift 文件的欄位 CHECK 寫法，產生碼處理自我引用，不會遞迴
  // ignore: recursive_getters
  IntColumn get month => integer().check(month.isBetweenValues(1, 12))();

  /// 列表已涵蓋到的日期（含），當地午夜
  DateTimeColumn get listedThrough => dateTime()();

  @override
  Set<Column> get primaryKey => {market, year, month};
}

/// 列表上有、但不在 [DividendDistribution] 的除權除息列
///
/// 列表成功後以範圍內的現況整批取代（DAO `recordDividendListing`）。讀取端
/// 據此逐檔判斷完整度：清單上的代號在那段期間不完整。與
/// [DividendDistribution] 同生共死，不可加進保留白名單。
@DataClassName('DividendUnresolvedEntry')
class DividendUnresolved extends Table {
  /// `MarketCode.twse`／`MarketCode.tpex`
  TextColumn get market => text()();

  /// 不加外鍵：可能是不在股票主檔的代號
  TextColumn get symbol => text()();

  /// 除權息交易日（當地午夜）
  DateTimeColumn get exDate => dateTime()();

  /// `DividendUnresolvedReason.code`
  TextColumn get reason => text()();

  /// 這次判定的時間（台北牆鐘，診斷用）
  DateTimeColumn get recordedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {market, symbol, exDate};
}
```

- [ ] **Step 4: 資料庫註冊與補建**

`app_database.dart` 的 `@DriftDatabase(tables: [...])` 在 `DividendMonthFailure,` 之後加 `DividendListing,`、`DividendUnresolved,`。`beforeOpen` 在 `await _ensureDividendPriceColumns();` 之後加 `await _ensureDividendFactsSchema();`，並新增：

```dart
  /// 除權除息完整度事實兩張表（2026-10-03，additive）。
  ///
  /// 沿 [_ensureDividendBackfillSchema] 先例：**不 bump fingerprint**，也
  /// **不加進 [_userInputTableNames]**——reset 時要與 dividend_distribution
  /// 一起清，否則事實留著、資料沒了，會被讀成「完整而沒配息」。
  Future<void> _ensureDividendFactsSchema() async {
    await Migrator(this).createTable(dividendListing);
    await Migrator(this).createTable(dividendUnresolved);
  }
```

先確認沒有其他 `dart run`／`flutter test` 行程，再跑 `dart run build_runner build --delete-conflicting-outputs`。

- [ ] **Step 5: DAO**

`dividend_dao.dart` 檔尾加：

```dart
/// 列表上有、但不在配發表的原因（存 [code]）
enum DividendUnresolvedReason {
  /// 尚未查明細（預算用完、被中斷）
  pendingDetail('PENDING_DETAIL'),

  /// 明細查詢失敗或回應不可信
  detailFailed('DETAIL_FAILED'),

  /// 明細推算的參考價與列表不符（可能查到別次除權息）
  referenceMismatch('REFERENCE_MISMATCH'),

  /// 列表當時不在在市股票主檔
  notInMaster('NOT_IN_MASTER');

  const DividendUnresolvedReason(this.code);

  final String code;
}
```

mixin 內加：

```dart
  /// 全部列表日
  Future<List<DividendListingEntry>> getDividendListings() =>
      select(dividendListing).get();

  /// 全部未解決的列
  Future<List<DividendUnresolvedEntry>> getDividendUnresolved() =>
      select(dividendUnresolved).get();

  /// 缺前收盤或除權息參考價的配發列 (symbol, exDate)
  Future<Set<(String, DateTime)>> getDividendMissingPriceKeys() async {
    final rows =
        await (select(dividendDistribution)..where(
              (t) => t.closeBefore.isNull() | t.referencePrice.isNull(),
            ))
            .get();
    return {for (final r in rows) (r.symbol, r.exDate)};
  }

  /// 列表成功後記錄完整度事實，一個 transaction：
  ///
  /// 1. 刪除 [market] 在 [from]～[to] 的未解決列（第一句是寫入，理由同
  ///    [completeDividendMonth]）
  /// 2. 讀範圍內已在庫的鍵；未解決＝[listedKnownKeys] − 在庫（原因取
  ///    [reasons]，沒有的記 pendingDetail），加上 [notInMasterKeys] − 在庫
  ///    （記 notInMaster）。「不在清單＝在庫」是交易當下查核的事實
  /// 3. 範圍涵蓋的每個月，列表日前進到 min([listedThrough], 月底)；只能連續
  ///    前進：該月的範圍起點不是 1 日時，現有有效列表日（列表日或完成紀錄的
  ///    月底）必須 ≥ 起點前一天，否則中間有一段沒列過，不前進；也不倒退
  ///
  /// [from]、[to]、[listedThrough] 為當地午夜，[listedThrough] ≤ [to]。
  Future<void> recordDividendListing({
    required String market,
    required DateTime from,
    required DateTime to,
    required DateTime listedThrough,
    required Set<(String, DateTime)> listedKnownKeys,
    required Set<(String, DateTime)> notInMasterKeys,
    Map<(String, DateTime), DividendUnresolvedReason> reasons = const {},
    required DateTime recordedAt,
  }) async {
    await transaction<void>(() async {
      // 順序是正確性的一部分：這句寫入必須在任何讀取之前
      await (delete(dividendUnresolved)..where(
            (t) => t.market.equals(market) & t.exDate.isBetweenValues(from, to),
          ))
          .go();
      final stored = await getDividendDistributionKeys(from: from, to: to);
      DividendUnresolvedCompanion entry(
        (String, DateTime) key,
        DividendUnresolvedReason reason,
      ) => DividendUnresolvedCompanion.insert(
        market: market,
        symbol: key.$1,
        exDate: key.$2,
        reason: reason.code,
        recordedAt: recordedAt,
      );
      final unresolved = [
        for (final key in listedKnownKeys.difference(stored))
          entry(key, reasons[key] ?? DividendUnresolvedReason.pendingDetail),
        for (final key in notInMasterKeys.difference(stored))
          entry(key, DividendUnresolvedReason.notInMaster),
      ];
      if (unresolved.isNotEmpty) {
        await batch(
          (b) => b.insertAll(
            dividendUnresolved,
            unresolved,
            mode: InsertMode.insertOrReplace,
          ),
        );
      }
      await _advanceDividendListing(
        market: market,
        from: from,
        listedThrough: listedThrough,
      );
    });
  }

  Future<void> _advanceDividendListing({
    required String market,
    required DateTime from,
    required DateTime listedThrough,
  }) async {
    final listed = {
      for (final e in await (select(
        dividendListing,
      )..where((t) => t.market.equals(market))).get())
        CalendarMonth(e.year, e.month): e.listedThrough,
    };
    final completed = {
      for (final e in await (select(
        dividendMonthLedger,
      )..where((t) => t.market.equals(market))).get())
        if (e.calendarMonth.isBefore(CalendarMonth.of(e.completedAt)))
          e.calendarMonth,
    };
    if (listedThrough.isBefore(from)) return;
    for (final month in CalendarMonth.descending(
      from: CalendarMonth.of(from),
      to: CalendarMonth.of(listedThrough),
    )) {
      final start = from.isAfter(month.firstDay) ? from : month.firstDay;
      final through = listedThrough.isBefore(month.lastDay)
          ? listedThrough
          : month.lastDay;
      final stored = listed[month];
      final existing = completed.contains(month) ? month.lastDay : stored;
      final dayBeforeStart = DateTime(start.year, start.month, start.day - 1);
      final contiguous =
          start == month.firstDay ||
          (existing != null && !existing.isBefore(dayBeforeStart));
      if (!contiguous) continue;
      if (existing != null && !through.isAfter(existing)) continue;
      await into(dividendListing).insertOnConflictUpdate(
        DividendListingCompanion.insert(
          market: market,
          year: month.year,
          month: month.month,
          listedThrough: through,
        ),
      );
    }
  }
```

`app_database.dart` 的 dividend_dao export 加 `DividendUnresolvedReason`（依字母序）：

```dart
export 'package:daredevil/data/database/dao/dividend_dao.dart'
    show
        DividendListedPrice,
        DividendMonthLedgerEntryX,
        DividendMonthFailureEntryX,
        DividendUnresolvedReason,
        encodeDividendSymbols;
```

- [ ] **Step 6: 跑測試確認通過**

Run: `flutter test test/data/database/`
Expected: 全部通過

- [ ] **Step 7: 記錄進度（不 commit）**

---

### Task 5: 本月同步與回補寫入事實；步驟 6.6 傳資料日

**Files:**
- Modify: `lib/domain/services/update/dividend_syncer.dart`
- Modify: `lib/domain/services/update/dividend_backfiller.dart`
- Modify: `lib/domain/services/update_service.dart`（`_syncDividendDistributions`）
- Test: `test/domain/services/update/dividend_distribution_sync_test.dart`
- Test: `test/domain/services/update/dividend_backfiller_test.dart`
- Test: `test/domain/services/update_service_test.dart`

**Interfaces:**
- Consumes: Task 4 的 `recordDividendListing`、`DividendUnresolvedReason`
- Produces: `DividendSyncer.syncDistributions({required DateTime today, required int maxCalls, DateTime? dataDate})`

- [ ] **Step 1: mock stub 與 fallback**

`dividend_distribution_sync_test.dart`、`dividend_backfiller_test.dart`、`update_service_test.dart` 的 `setUpAll` 加：

```dart
    registerFallbackValue(<(String, DateTime)>{});
    registerFallbackValue(<(String, DateTime), DividendUnresolvedReason>{});
```

三個檔案中以 `MockAppDatabase` 建立的 mock（同 Task 3 Step 1 的位置）都加：

```dart
      when(
        () => mockDb.recordDividendListing(
          market: any(named: 'market'),
          from: any(named: 'from'),
          to: any(named: 'to'),
          listedThrough: any(named: 'listedThrough'),
          listedKnownKeys: any(named: 'listedKnownKeys'),
          notInMasterKeys: any(named: 'notInMasterKeys'),
          reasons: any(named: 'reasons'),
          recordedAt: any(named: 'recordedAt'),
        ),
      ).thenAnswer((_) async {});
```

- [ ] **Step 2: 寫失敗測試（本月同步）**

`dividend_distribution_sync_test.dart` 加一組：

```dart
  group('完整度事實', () {
    Future<Map<String, String>> unresolved() async => {
      for (final u in await db.getDividendUnresolved())
        '${u.market} ${u.symbol}': u.reason,
    };

    test('兩市場列表成功：列表日記到資料日；預算用完、明細失敗、參考價不符、未知代號各記原因', () async {
      await db.upsertStocks([
        StockMasterCompanion.insert(symbol: '1101', name: '台泥', market: 'TWSE'),
      ]);
      stubTwse([
        _row('2836', DateTime(2026, 9, 17)),
        ExRightResult(
          symbol: '4108',
          exDate: DateTime(2026, 9, 18),
          cashDividend: null,
          stockSharesPerThousand: null,
          closeBefore: 10.6,
          dividendAdjustedReference: 10.0,
        ),
        _row('1101', DateTime(2026, 9, 19)),
        _row('910322', DateTime(2026, 9, 19), cash: 1, shares: 0),
      ]);
      when(
        () => twse.getExRightDetail('2836', any()),
      ).thenThrow(const ApiException('改版', 200));
      // (10.6 − 0.5) ÷ 1 = 10.1，與列表的 10.0 不符
      stubDetail('4108', 0.5, 0);

      final result = await syncer.syncDistributions(
        today: today,
        maxCalls: 4,
        dataDate: DateTime(2026, 9, 29),
      );

      expect(result.pendingDetails, 1);
      expect(await unresolved(), {
        'TWSE 2836': 'DETAIL_FAILED',
        'TWSE 4108': 'REFERENCE_MISMATCH',
        'TWSE 1101': 'PENDING_DETAIL',
        'TWSE 910322': 'NOT_IN_MASTER',
      });
      expect({
        for (final e in await db.getDividendListings())
          e.market: e.listedThrough,
      }, {'TPEx': end, 'TWSE': end});
    });

    test('凌晨補跑：資料日早於今天時列表日記資料日，不替 10 月記任何列表日', () async {
      for (final market in ['TWSE', 'TPEx']) {
        await db.recordDividendListing(
          market: market,
          from: DateTime(2026, 9, 1),
          to: DateTime(2026, 9, 29),
          listedThrough: DateTime(2026, 9, 29),
          listedKnownKeys: const {},
          notInMasterKeys: const {},
          recordedAt: today,
        );
      }

      await syncer.syncDistributions(
        today: DateTime(2026, 10, 1, 1, 0),
        maxCalls: 30,
        dataDate: DateTime(2026, 9, 30),
      );

      expect({
        for (final e in await db.getDividendListings())
          '${e.market} ${e.month}': e.listedThrough,
      }, {
        'TWSE 9': DateTime(2026, 9, 30),
        'TPEx 9': DateTime(2026, 9, 30),
      });
    });

    test('🚨 明細查到一半被限流：事實照記（未查的列為 pendingDetail），例外照常往外拋', () async {
      stubTwse([
        _row('2836', DateTime(2026, 9, 17)),
        _row('4108', DateTime(2026, 9, 18)),
      ]);
      when(
        () => twse.getExRightDetail('2836', any()),
      ).thenThrow(const RateLimitException('redirect loop'));

      await expectLater(
        syncer.syncDistributions(today: today, maxCalls: 30),
        throwsA(isA<RateLimitException>()),
      );

      expect(await unresolved(), {
        'TWSE 2836': 'PENDING_DETAIL',
        'TWSE 4108': 'PENDING_DETAIL',
      });
      expect(
        (await db.getDividendListings()).map((e) => e.market),
        contains('TWSE'),
      );
    });

    test('列表失敗：不記事實', () async {
      when(
        () => twse.getExRightResults(
          startDate: any(named: 'startDate'),
          endDate: any(named: 'endDate'),
        ),
      ).thenThrow(const ApiException('改版', 200));

      await syncer.syncDistributions(today: today, maxCalls: 30);

      expect(
        (await db.getDividendListings()).map((e) => e.market),
        isNot(contains('TWSE')),
      );
    });

    test('事實寫入失敗：記進 errors、不往外拋，配發列照寫', () async {
      final failing = _FactsFailingDb();
      addTearDown(failing.close);
      await failing.upsertStocks([
        StockMasterCompanion.insert(symbol: '2330', name: '台積電', market: 'TWSE'),
      ]);
      stubTwse([_row('2330', DateTime(2026, 9, 16), cash: 5, shares: 0)]);

      final result = await DividendSyncer(
        database: failing,
        twseClient: twse,
        detailCallDelay: Duration.zero,
      ).syncDistributions(today: today, maxCalls: 30);

      expect(result.errors.single, contains('完整度紀錄'));
      expect(await failing.getDividendDistributions('2330'), hasLength(1));
    });
  });
```

檔案頂層（`_row` 之後）加：

```dart
/// 事實寫入一律失敗的 DB（其餘照常），驗證本月同步不因此往外拋
class _FactsFailingDb extends AppDatabase {
  _FactsFailingDb() : super(NativeDatabase.memory());

  @override
  Future<void> recordDividendListing({
    required String market,
    required DateTime from,
    required DateTime to,
    required DateTime listedThrough,
    required Set<(String, DateTime)> listedKnownKeys,
    required Set<(String, DateTime)> notInMasterKeys,
    Map<(String, DateTime), DividendUnresolvedReason> reasons = const {},
    required DateTime recordedAt,
  }) => throw Exception('disk I/O error');
}
```

（此檔需 `import 'package:drift/native.dart';`。）

- [ ] **Step 3: 寫失敗測試（回補）**

`dividend_backfiller_test.dart` 加一組：

```dart
  group('完整度事實', () {
    Future<Map<String, String>> unresolved() async => {
      for (final u in await db.getDividendUnresolved())
        '${u.market} ${u.symbol}': u.reason,
    };

    test('上櫃整月完成：只剩未知代號；列表日由完成紀錄推導、不另寫', () async {
      listTpex(aug, [
        _cash('6488', DateTime(2026, 8, 10), 3),
        _cash('00950B', DateTime(2026, 8, 11), 0.08),
      ]);

      await run(
        scope: const DividendBackfillScope(
          from: aug,
          to: aug,
          markets: {MarketCode.tpex},
        ),
      );

      expect(await unresolved(), {'TPEx 00950B': 'NOT_IN_MASTER'});
      expect(await db.getDividendListings(), isEmpty);
      expect(await ledgerKeys(), {'TPEx 2026-08'});
    });

    test('上市預算中途用完：已查的明細在庫，未查的記 pendingDetail，列表日記到月底', () async {
      listTwse(aug, [
        _rightsAndCash('2836', DateTime(2026, 8, 13)),
        _rightsIssue('4108', DateTime(2026, 8, 14)),
      ]);
      detail('2836', _detailOk);

      await run(
        maxCalls: 2,
        scope: const DividendBackfillScope(
          from: aug,
          to: aug,
          markets: {MarketCode.twse},
        ),
      );

      expect(await unresolved(), {'TWSE 4108': 'PENDING_DETAIL'});
      expect(
        (await db.getDividendListings()).single.listedThrough,
        aug.lastDay,
      );
    });

    test('上市明細失敗與參考價不符：各記原因', () async {
      await db.upsertStocks([
        StockMasterCompanion.insert(symbol: '1101', name: '1101', market: 'TWSE'),
      ]);
      listTwse(aug, [
        _rightsAndCash('2836', DateTime(2026, 8, 13)),
        _rightsAndCash('1101', DateTime(2026, 8, 14)),
      ]);
      when(
        () => twse.getExRightDetail('2836', any()),
      ).thenThrow(const ApiException('改版', 200));
      detail(
        '1101',
        const ExRightDetail(
          symbol: '',
          cashDividend: 0.5,
          stockSharesPerThousand: 0,
        ),
      );

      await run(
        scope: const DividendBackfillScope(
          from: aug,
          to: aug,
          markets: {MarketCode.twse},
        ),
      );

      expect(await unresolved(), {
        'TWSE 2836': 'DETAIL_FAILED',
        'TWSE 1101': 'REFERENCE_MISMATCH',
      });
    });

    test('列表失敗：不記事實', () async {
      when(
        () => twse.getExRightResults(
          startDate: aug.firstDay,
          endDate: aug.lastDay,
        ),
      ).thenThrow(const ApiException('改版', 200));

      await run(
        scope: const DividendBackfillScope(
          from: aug,
          to: aug,
          markets: {MarketCode.twse},
        ),
      );

      expect(await db.getDividendListings(), isEmpty);
      expect(await db.getDividendUnresolved(), isEmpty);
    });
  });
```

- [ ] **Step 4: 寫失敗測試（步驟 6.6 傳資料日）**

`update_service_test.dart` 的 `group('步驟 6.6 歷史回補', ...)` 加：

```dart
    test('本月同步的列表日記資料日，不是牆鐘（凌晨補跑）', () async {
      await buildService(
        tpex: healthyTpex(),
        clock: _Clock(DateTime(2026, 7, 7, 1, 0)),
      ).runDailyUpdate(forDate: tradingDay);

      final listedThrough =
          verify(
                () => mockDb.recordDividendListing(
                  market: 'TPEx',
                  from: any(named: 'from'),
                  to: any(named: 'to'),
                  listedThrough: captureAny(named: 'listedThrough'),
                  listedKnownKeys: any(named: 'listedKnownKeys'),
                  notInMasterKeys: any(named: 'notInMasterKeys'),
                  reasons: any(named: 'reasons'),
                  recordedAt: any(named: 'recordedAt'),
                ),
              ).captured.single
              as DateTime;
      expect(listedThrough, DateTime(2026, 7, 6));
    });
```

- [ ] **Step 5: 跑測試確認失敗**

Run: `flutter test test/domain/services/update/dividend_distribution_sync_test.dart test/domain/services/update/dividend_backfiller_test.dart test/domain/services/update_service_test.dart`
Expected: 新增的測試失敗（`dataDate` 參數不存在、沒有事實）

- [ ] **Step 6: 實作本月同步**

`syncDistributions` 簽名與開頭：

```dart
  /// [dataDate]：本輪更新的資料日（`UpdateService` 的 `ctx.normalizedDate`）。
  /// 列表日記 min(今天, [dataDate])——凌晨補跑時資料日是前一個交易日，
  /// 不可多宣稱一天。省略時為今天。
  Future<DividendDistributionSyncResult> syncDistributions({
    required DateTime today,
    required int maxCalls,
    DateTime? dataDate,
  }) async {
    final end = DateContext.normalize(today);
    final dataEnd = dataDate == null ? end : DateContext.normalize(dataDate);
    final listedThrough = dataEnd.isAfter(end) ? end : dataEnd;
```

上櫃段：

```dart
    if (_tpex != null && calls < maxCalls) {
      try {
        calls++;
        final rows = await _tpex.getExRightResults(
          startDate: start,
          endDate: end,
        );
        written += await _writeDistributions([
          for (final row in rows)
            if (knownSymbols.contains(row.symbol)) row,
        ]);
        await _recordListing(
          market: MarketCode.tpex,
          listed: rows,
          knownSymbols: knownSymbols,
          from: start,
          to: end,
          listedThrough: listedThrough,
          recordedAt: today,
          errors: errors,
        );
      } on RateLimitException {
```

上市段：列表與「息」列寫入、補價之後，明細迴圈包進 `try`／`finally`：

```dart
        final reasons = <(String, DateTime), DividendUnresolvedReason>{};
        try {
          for (final row in pending) {
            if (calls >= maxCalls) {
              pendingDetails++;
              continue;
            }
            await Future<void>.delayed(_detailCallDelay);
            calls++;
            final key = (row.symbol, row.exDate);
            try {
              final detail = await _twse.getExRightDetail(
                row.symbol,
                row.exDate,
              );
              if (!row.matchesReference(detail)) {
                reasons[key] = DividendUnresolvedReason.referenceMismatch;
                errors.add(
                  'TWSE 除權除息明細 ${row.symbol} '
                  '${_dateFormat.format(row.exDate)}: 明細推算的參考價與列表不符'
                  '（查到的可能是別次除權息）',
                );
                continue;
              }
              written += await _writeDistributions([row.withDetail(detail)]);
            } on RateLimitException {
              rethrow;
            } on NetworkException {
              rethrow;
            } catch (e) {
              reasons[key] = DividendUnresolvedReason.detailFailed;
              AppLogger.warning(
                'DividendSyncer',
                'TWSE 除權除息明細失敗: ${row.symbol}',
                e,
              );
              errors.add(
                'TWSE 除權除息明細 ${row.symbol} '
                '${_dateFormat.format(row.exDate)}: $e',
              );
            }
          }
        } finally {
          // 列表成功就記事實：明細被限流或斷線打斷也要記，未查的列以
          // pendingDetail 留在未解決清單；本身失敗只進 errors，不蓋過例外
          await _recordListing(
            market: MarketCode.twse,
            listed: rows,
            knownSymbols: knownSymbols,
            reasons: reasons,
            from: start,
            to: end,
            listedThrough: listedThrough,
            recordedAt: today,
            errors: errors,
          );
        }
```

新增私有方法（`_writeDistributions` 之後）：

```dart
  /// 記錄完整度事實；失敗只記 errors 與 warning，不往外拋（本月同步的
  /// 失敗一律進 errors，不中斷其他市場）
  Future<void> _recordListing({
    required String market,
    required List<ExRightResult> listed,
    required Set<String> knownSymbols,
    Map<(String, DateTime), DividendUnresolvedReason> reasons = const {},
    required DateTime from,
    required DateTime to,
    required DateTime listedThrough,
    required DateTime recordedAt,
    required List<String> errors,
  }) async {
    try {
      await _db.recordDividendListing(
        market: market,
        from: from,
        to: to,
        listedThrough: listedThrough,
        listedKnownKeys: {
          for (final r in listed)
            if (knownSymbols.contains(r.symbol)) (r.symbol, r.exDate),
        },
        notInMasterKeys: {
          for (final r in listed)
            if (!knownSymbols.contains(r.symbol)) (r.symbol, r.exDate),
        },
        reasons: reasons,
        recordedAt: recordedAt,
      );
    } catch (e) {
      AppLogger.warning('DividendSyncer', '$market 除權除息完整度紀錄失敗', e);
      errors.add('$market 除權除息完整度紀錄: $e');
    }
  }
```

（`dividend_syncer.dart` 需 `import 'package:daredevil/core/constants/market_codes.dart';`。）

- [ ] **Step 7: 實作回補**

`_processTpex`：`_complete(...)` 之後加 `await _recordListing(run, key, listed: rows);`。

`_processTwse` 拆成兩段：列表後的處理移到 `_processTwseRows`，外層以 `try`／`finally` 記事實：

```dart
  Future<void> _processTwse(
    _Run run,
    DividendMonthKey key, {
    required bool recheck,
  }) async {
    final month = key.month;
    final rows = await _list(run, key, () {
      return _twse!.getExRightResults(
        startDate: month.firstDay,
        endDate: month.lastDay,
      );
    });
    if (rows == null) return;
    final reasons = <(String, DateTime), DividendUnresolvedReason>{};
    try {
      await _processTwseRows(run, key, rows, reasons, recheck: recheck);
    } finally {
      // 列表成功就記事實：預算、網路、限流中斷也要記，未查的列以
      // pendingDetail 留在未解決清單（DB 錯誤照常往外拋）
      await _recordListing(run, key, listed: rows, reasons: reasons);
    }
  }
```

`_processTwseRows(_Run run, DividendMonthKey key, List<ExRightResult> rows, Map<(String, DateTime), DividendUnresolvedReason> reasons, {required bool recheck})` 的內容＝原本 `_processTwse` 在 `if (rows == null) return;` 之後的全部程式碼，另加兩處：

- `on _GeneralFailure catch (e) {` 區塊第一行：`reasons[(row.symbol, row.exDate)] = DividendUnresolvedReason.detailFailed;`
- `if (!row.matchesReference(detail)) {` 區塊在 `deleteDividendDistribution` 之後：`reasons[(row.symbol, row.exDate)] = DividendUnresolvedReason.referenceMismatch;`

新增：

```dart
  /// 記錄這個（市場, 月）的完整度事實：列到月底，未解決的列由 DB 現況推導
  Future<void> _recordListing(
    _Run run,
    DividendMonthKey key, {
    required List<ExRightResult> listed,
    Map<(String, DateTime), DividendUnresolvedReason> reasons = const {},
  }) => _db.recordDividendListing(
    market: key.market,
    from: key.month.firstDay,
    to: key.month.lastDay,
    listedThrough: key.month.lastDay,
    listedKnownKeys: {
      for (final r in listed)
        if (run.knownSymbols.contains(r.symbol)) (r.symbol, r.exDate),
    },
    notInMasterKeys: {
      for (final r in listed)
        if (!run.knownSymbols.contains(r.symbol)) (r.symbol, r.exDate),
    },
    reasons: reasons,
    recordedAt: run.now,
  );
```

- [ ] **Step 8: 步驟 6.6 傳資料日**

`update_service.dart` 的 `_syncDividendDistributions`：

```dart
      result = await syncer.syncDistributions(
        today: now,
        maxCalls: ApiConfig.dividendSyncMaxCallsPerRun,
        dataDate: ctx.normalizedDate,
      );
```

- [ ] **Step 9: 跑測試確認通過**

Run: `flutter test test/domain/services/update/ test/domain/services/update_service_test.dart test/domain/services/update_service_contract_guard_test.dart test/tool/`
Expected: 全部通過

- [ ] **Step 10: 記錄進度（不 commit）**

---

### Task 6: 逐檔完整度讀取模型 `DividendCompleteness`

**Files:**
- Create: `lib/domain/services/dividend_completeness.dart`
- Test: `test/domain/services/dividend_completeness_test.dart`（新檔）

**Interfaces:**
- Consumes: Task 4 的 `getDividendListings`／`getDividendUnresolved`／`getDividendMissingPriceKeys`、Task 2 的完成紀錄；`dividendMarkets`、`dividendBackfillTarget`（`dividend_coverage.dart`）
- Produces（3-2、3-3 使用）：
  - `DividendCompleteness.compute({required DateTime now, required Iterable<DividendListingEntry> listings, required Iterable<DividendMonthLedgerEntry> ledger, required Iterable<DividendUnresolvedEntry> unresolved, required Iterable<(String, DateTime)> missingPriceKeys})`
  - `bool isComplete(String symbol, DateTime from, DateTime to, {required bool requirePrices})`（最終審查後改為必填；Task 6 的程式碼區塊是原計畫版本）
  - `DateTime? get displayEnd`、`DateTime get coverageStart`
  - `Future<DividendCompleteness> loadDividendCompleteness(AppDatabase db, {required DateTime now})`

- [ ] **Step 1: 寫失敗測試**

新檔 `test/domain/services/dividend_completeness_test.dart`：

```dart
// 除權除息逐檔完整度（dividend_completeness.dart）：讀取端唯一定義
//
// 兩個市場都查；有效列表日＝max(列表日, 完成紀錄的月底)；未解決的列、
// 當時略過的代號、（需要時）缺價格的列都讓該檔該期間不完整。
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/constants/market_codes.dart';
import 'package:daredevil/core/utils/calendar_month.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/domain/services/dividend_completeness.dart';

final _now = DateTime(2026, 10, 2, 21, 30);
const _sep = CalendarMonth(2026, 9);
const _oct = CalendarMonth(2026, 10);

DividendListingEntry _listing(String market, CalendarMonth m, DateTime through) =>
    DividendListingEntry(
      market: market,
      year: m.year,
      month: m.month,
      listedThrough: through,
    );

DividendMonthLedgerEntry _ledger(
  String market,
  CalendarMonth m, {
  String skipped = '',
  DateTime? completedAt,
}) => DividendMonthLedgerEntry(
  market: market,
  year: m.year,
  month: m.month,
  completedAt: completedAt ?? DateTime(2026, 10, 1),
  listedRows: 1,
  knownRows: 1,
  skippedSymbols: skipped,
  pricesRecorded: true,
);

DividendUnresolvedEntry _unresolved(String market, String symbol, DateTime d) =>
    DividendUnresolvedEntry(
      market: market,
      symbol: symbol,
      exDate: d,
      reason: DividendUnresolvedReason.pendingDetail.code,
      recordedAt: _now,
    );

/// 回補範圍（2021-01）至 [through] 兩市場都完整：過去月份用完成紀錄，
/// 本月用列表日
List<DividendMonthLedgerEntry> _ledgerThroughSep() => [
  for (final market in [MarketCode.twse, MarketCode.tpex])
    for (final m in CalendarMonth.descending(
      from: const CalendarMonth(2021, 1),
      to: _sep,
    ))
      _ledger(market, m),
];

DividendCompleteness _compute({
  List<DividendListingEntry> listings = const [],
  List<DividendMonthLedgerEntry>? ledger,
  List<DividendUnresolvedEntry> unresolved = const [],
  List<(String, DateTime)> missingPrices = const [],
}) => DividendCompleteness.compute(
  now: _now,
  listings: listings,
  ledger: ledger ?? _ledgerThroughSep(),
  unresolved: unresolved,
  missingPriceKeys: missingPrices,
);

void main() {
  final octListed = [
    _listing(MarketCode.twse, _oct, DateTime(2026, 10, 2)),
    _listing(MarketCode.tpex, _oct, DateTime(2026, 10, 2)),
  ];

  group('條件 1：兩個市場的有效列表日', () {
    test('完成紀錄＝列到月底；本月以列表日為準', () {
      final c = _compute(listings: octListed);
      expect(c.isComplete('2330', DateTime(2025, 10, 2), DateTime(2026, 10, 2)), isTrue);
      expect(c.isComplete('2330', DateTime(2025, 10, 2), DateTime(2026, 10, 3)), isFalse);
    });

    test('只有一個市場列到：不完整（轉板代號可能在另一個市場）', () {
      final c = _compute(listings: [octListed.first]);
      expect(c.isComplete('2330', DateTime(2026, 10, 1), DateTime(2026, 10, 2)), isFalse);
    });

    test('完成紀錄是在該月結束前寫的：不算列到月底', () {
      final ledger = _ledgerThroughSep()
        ..removeWhere((e) => e.market == MarketCode.twse && e.year == 2026 && e.month == 9)
        ..add(_ledger(MarketCode.twse, _sep, completedAt: DateTime(2026, 9, 20)));
      final c = _compute(ledger: ledger);
      expect(c.isComplete('2330', DateTime(2026, 9, 1), DateTime(2026, 9, 30)), isFalse);
    });

    test('沒有完成紀錄但有列到月底的列表日：算列過（同步寫的上個月）', () {
      final ledger = _ledgerThroughSep()
        ..removeWhere((e) => e.market == MarketCode.twse && e.year == 2026 && e.month == 9);
      final c = _compute(
        ledger: ledger,
        listings: [_listing(MarketCode.twse, _sep, DateTime(2026, 9, 30))],
      );
      expect(c.isComplete('2330', DateTime(2026, 9, 1), DateTime(2026, 9, 30)), isTrue);
    });

    test('回補範圍以前一律不完整', () {
      final c = _compute(listings: octListed);
      expect(c.isComplete('2330', DateTime(2020, 12, 1), DateTime(2021, 1, 31)), isFalse);
    });
  });

  test('條件 2：該檔有未解決的列（任一市場）→ 期間內不完整，期間外不受影響', () {
    final c = _compute(
      listings: octListed,
      unresolved: [_unresolved(MarketCode.tpex, '2330', DateTime(2026, 9, 17))],
    );
    expect(c.isComplete('2330', DateTime(2026, 9, 1), DateTime(2026, 9, 30)), isFalse);
    expect(c.isComplete('2330', DateTime(2026, 10, 1), DateTime(2026, 10, 2)), isTrue);
    expect(c.isComplete('2836', DateTime(2026, 9, 1), DateTime(2026, 9, 30)), isTrue);
  });

  test('條件 3：當時略過的代號 → 該月不完整', () {
    final ledger = _ledgerThroughSep()
      ..removeWhere((e) => e.market == MarketCode.tpex && e.year == 2026 && e.month == 9)
      ..add(_ledger(MarketCode.tpex, _sep, skipped: '00950B'));
    final c = _compute(ledger: ledger, listings: octListed);
    expect(c.isComplete('00950B', DateTime(2026, 9, 1), DateTime(2026, 9, 30)), isFalse);
    expect(c.isComplete('2330', DateTime(2026, 9, 1), DateTime(2026, 9, 30)), isTrue);
  });

  test('條件 4：需要價格時，缺前收盤或參考價的列 → 不完整；不需要時不影響', () {
    final c = _compute(
      listings: octListed,
      missingPrices: [('2330', DateTime(2026, 9, 16))],
    );
    expect(
      c.isComplete('2330', DateTime(2026, 9, 1), DateTime(2026, 9, 30), requirePrices: true),
      isFalse,
    );
    expect(c.isComplete('2330', DateTime(2026, 9, 1), DateTime(2026, 9, 30)), isTrue);
  });

  group('displayEnd：兩個市場自回補起點連續列過的最後一天，夾在今天以內', () {
    test('兩市場都列到 10/2 → 10/2', () {
      expect(_compute(listings: octListed).displayEnd, DateTime(2026, 10, 2));
    });

    test('本月尚未列表 → 上個月底', () {
      expect(_compute().displayEnd, DateTime(2026, 9, 30));
    });

    test('取兩市場較早者', () {
      final c = _compute(listings: [
        _listing(MarketCode.twse, _oct, DateTime(2026, 10, 2)),
        _listing(MarketCode.tpex, _oct, DateTime(2026, 10, 1)),
      ]);
      expect(c.displayEnd, DateTime(2026, 10, 1));
    });

    test('中間有一個月沒列完 → 停在那個月之前', () {
      final ledger = _ledgerThroughSep()
        ..removeWhere((e) => e.market == MarketCode.twse && e.year == 2025 && e.month == 3);
      expect(_compute(ledger: ledger).displayEnd, DateTime(2025, 2, 28));
    });

    test('任一市場連回補起點的月份都沒列 → null', () {
      final ledger = _ledgerThroughSep()
        ..removeWhere((e) => e.market == MarketCode.tpex && e.year == 2021 && e.month == 1);
      expect(_compute(ledger: ledger).displayEnd, isNull);
    });
  });

  test('loadDividendCompleteness：列表日、未解決的列、缺價格的列都從 DB 讀進來', () async {
    final db = AppDatabase.forTesting();
    addTearDown(db.close);
    await db.upsertStocks([
      StockMasterCompanion.insert(symbol: '2330', name: '台積電', market: 'TWSE'),
      StockMasterCompanion.insert(symbol: '2836', name: '高雄銀', market: 'TWSE'),
    ]);
    await db.upsertDividendDistributions([
      DividendDistributionCompanion.insert(
        symbol: '2836',
        exDate: DateTime(2026, 10, 1),
        cashDividend: 0.15,
        stockSharesPerThousand: 45,
      ),
    ]);
    for (final market in [MarketCode.twse, MarketCode.tpex]) {
      await db.recordDividendListing(
        market: market,
        from: DateTime(2026, 10, 1),
        to: DateTime(2026, 10, 2),
        listedThrough: DateTime(2026, 10, 2),
        listedKnownKeys: market == MarketCode.twse
            ? {
                ('2330', DateTime(2026, 10, 2)),
                ('2836', DateTime(2026, 10, 1)),
              }
            : const {},
        notInMasterKeys: const {},
        recordedAt: _now,
      );
    }

    final c = await loadDividendCompleteness(db, now: _now);
    final oct1 = DateTime(2026, 10, 1);
    final oct2 = DateTime(2026, 10, 2);

    expect(c.isComplete('2836', oct1, oct2), isTrue, reason: '兩市場都列過、已在庫');
    expect(c.isComplete('2330', oct1, oct2), isFalse, reason: '未解決的列');
    expect(
      c.isComplete('2836', oct1, oct2, requirePrices: true),
      isFalse,
      reason: '在庫但缺前收盤與參考價',
    );
    expect(c.displayEnd, isNull, reason: '回補起點的月份沒列過');
  });
}
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `flutter test test/domain/services/dividend_completeness_test.dart`
Expected: 編譯失敗（`dividend_completeness.dart` 不存在）

- [ ] **Step 3: 實作**

新檔 `lib/domain/services/dividend_completeness.dart`：

```dart
import 'package:daredevil/core/utils/calendar_month.dart';
import 'package:daredevil/core/utils/date_context.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/domain/services/update/dividend_coverage.dart';

/// 除權除息資料的逐檔完整度：讀取端（52 週規則、個股頁股利表、ETF 近一年
/// 殖利率）判斷「某檔在某段期間的除權除息是否都在庫」的唯一定義。
///
/// **不帶市場參數、兩個市場都查**：配發表沒有市場欄，上櫃轉上市的代號在
/// 期間內會出現在兩個市場的列表，股票主檔的市場在轉板當天也可能還沒更新。
///
/// [isComplete] 為真的條件：
/// 1. 與期間重疊的每個月，兩個市場的有效列表日都 ≥ min(期間迄, 月底)；
///    有效列表日＝max(列表日, 完成紀錄在該月結束後寫下時的月底)——只寫
///    完成紀錄的舊版程式寫下的完成也算數
/// 2. 該代號在期間內沒有未解決的列（任一市場）
/// 3. 與期間重疊的完成紀錄，該代號不在當時略過的代號內
/// 4. `requirePrices` 時，該代號在期間內的配發列都有前收盤與除權息參考價
///
/// 回補範圍（[coverageStart] 起）以前的期間一律不完整。
class DividendCompleteness {
  DividendCompleteness._({
    required this.now,
    required this.coverageStart,
    required this.displayEnd,
    required Map<(String, CalendarMonth), DateTime> effective,
    required Map<String, List<DateTime>> unresolved,
    required Map<String, Set<CalendarMonth>> skipped,
    required Map<String, List<DateTime>> missingPrices,
  }) : _effective = effective,
       _unresolved = unresolved,
       _skipped = skipped,
       _missingPrices = missingPrices;

  factory DividendCompleteness.compute({
    required DateTime now,
    required Iterable<DividendListingEntry> listings,
    required Iterable<DividendMonthLedgerEntry> ledger,
    required Iterable<DividendUnresolvedEntry> unresolved,
    required Iterable<(String, DateTime)> missingPriceKeys,
  }) {
    final effective = <(String, CalendarMonth), DateTime>{};
    void raise(String market, CalendarMonth month, DateTime through) {
      final key = (market, month);
      final current = effective[key];
      if (current == null || through.isAfter(current)) {
        effective[key] = through;
      }
    }

    for (final e in listings) {
      raise(
        e.market,
        CalendarMonth(e.year, e.month),
        DateContext.normalize(e.listedThrough),
      );
    }
    final skipped = <String, Set<CalendarMonth>>{};
    for (final e in ledger) {
      if (e.calendarMonth.isBefore(CalendarMonth.of(e.completedAt))) {
        raise(e.market, e.calendarMonth, e.calendarMonth.lastDay);
      }
      for (final symbol in e.skippedSymbolSet) {
        skipped.putIfAbsent(symbol, () => {}).add(e.calendarMonth);
      }
    }
    final unresolvedBySymbol = <String, List<DateTime>>{};
    for (final u in unresolved) {
      unresolvedBySymbol
          .putIfAbsent(u.symbol, () => [])
          .add(DateContext.normalize(u.exDate));
    }
    final missing = <String, List<DateTime>>{};
    for (final (symbol, exDate) in missingPriceKeys) {
      missing.putIfAbsent(symbol, () => []).add(DateContext.normalize(exDate));
    }

    final target = dividendBackfillTarget(now);
    final today = DateContext.normalize(now);
    DateTime? displayEnd = today;
    for (final market in dividendMarkets) {
      DateTime? contiguous;
      for (
        var month = target.from;
        !month.isAfter(CalendarMonth.of(today));
        month = month.addMonths(1)
      ) {
        final through = effective[(market, month)];
        if (through == null) break;
        contiguous = through;
        if (through.isBefore(month.lastDay)) break;
      }
      if (contiguous == null) {
        displayEnd = null;
        break;
      }
      if (contiguous.isBefore(displayEnd!)) displayEnd = contiguous;
    }

    return DividendCompleteness._(
      now: now,
      coverageStart: target.from.firstDay,
      displayEnd: displayEnd,
      effective: effective,
      unresolved: unresolvedBySymbol,
      skipped: skipped,
      missingPrices: missing,
    );
  }

  final DateTime now;

  /// 回補範圍的第一天；更早的期間一律不完整
  final DateTime coverageStart;

  /// 畫面「截至 M/D」：min(今天, 兩個市場自回補範圍起點連續列過的最後
  /// 一天)。任一市場連回補起點的月份都沒列過時為 null（全部視為建置中）
  final DateTime? displayEnd;

  final Map<(String, CalendarMonth), DateTime> _effective;
  final Map<String, List<DateTime>> _unresolved;
  final Map<String, Set<CalendarMonth>> _skipped;
  final Map<String, List<DateTime>> _missingPrices;

  /// [symbol] 在 [from]～[to]（含頭尾，取日期）的除權除息是否都在庫；
  /// [requirePrices] 另要求每列都有前收盤與除權息參考價（還原、殖利率用）
  bool isComplete(
    String symbol,
    DateTime from,
    DateTime to, {
    bool requirePrices = false,
  }) {
    final start = DateContext.normalize(from);
    final end = DateContext.normalize(to);
    if (start.isBefore(coverageStart)) return false;
    for (
      var month = CalendarMonth.of(start);
      !month.isAfter(CalendarMonth.of(end));
      month = month.addMonths(1)
    ) {
      final needed = end.isBefore(month.lastDay) ? end : month.lastDay;
      for (final market in dividendMarkets) {
        final through = _effective[(market, month)];
        if (through == null || through.isBefore(needed)) return false;
      }
      if (_skipped[symbol]?.contains(month) ?? false) return false;
    }
    bool within(DateTime d) => !d.isBefore(start) && !d.isAfter(end);
    if (_unresolved[symbol]?.any(within) ?? false) return false;
    if (requirePrices && (_missingPrices[symbol]?.any(within) ?? false)) {
      return false;
    }
    return true;
  }
}

/// 從 DB 讀出完整度（兩張事實表、完成紀錄、缺價格的列）
Future<DividendCompleteness> loadDividendCompleteness(
  AppDatabase db, {
  required DateTime now,
}) async {
  // 依序讀：同一條連線本來就序列執行；record .wait 會把例外包成
  // ParallelWaitError，呼叫端的分型 catch 接不到
  final listings = await db.getDividendListings();
  final ledger = await db.getDividendMonthLedgerEntries();
  final unresolved = await db.getDividendUnresolved();
  final missing = await db.getDividendMissingPriceKeys();
  return DividendCompleteness.compute(
    now: now,
    listings: listings,
    ledger: ledger,
    unresolved: unresolved,
    missingPriceKeys: missing,
  );
}
```

- [ ] **Step 4: 跑測試確認通過**

Run: `flutter test test/domain/services/dividend_completeness_test.dart test/tool/tool_chain_pure_dart_test.dart`
Expected: 全部通過

- [ ] **Step 5: 記錄進度（不 commit）**

---

### Task 7: 文件與註解同步

**Files:**
- Modify: `.claude/rules/update-pipeline.md`（步驟 6.6 兩段）
- Modify: `lib/domain/services/update/dividend_coverage.dart`（給第 3 段的注意事項）
- Modify: `lib/data/database/tables/market_data_tables.dart`（`DividendMonthFailure.failedSymbols` 的 doc）
- Modify: `docs/plans/2026-09-26-data-retention-plan.md`（Global Constraints 的股利表條目）
- Modify: `tool/backfill_dividend_distributions.dart`（檔頭）

- [ ] **Step 1: 改文件**

`update-pipeline.md` 步驟 6.6「歷史回補」段，把最後一條「⚠️ 三張表…」換成：

```markdown
- 配發表另存列表的**前收盤價與除權息參考價**（`close_before`、`reference_price`；
  還原因子＝參考價 ÷ 前收盤，含現金增資）。完成紀錄的 `prices_recorded` 為 false
  （2026-10 以前寫的）時回補重開該月一次、只打列表補價；明細已在庫的權／權息列以
  `updateDividendDistributionPrices` 補價，不重查
- **完整度事實**：本月同步與回補在列表成功後以一個 transaction 寫
  `dividend_listing`（列表已同步到哪一天；本月同步記 min(今天, 資料日)，只能連續前進）
  與 `dividend_unresolved`（列表上有、不在配發表的列與原因，由 DB 現況推導、範圍內
  整批取代）。明細中斷（預算、網路、限流）也照記，未查的列為 `pendingDetail`；本月
  同步的事實寫入失敗只進 errors。讀取端一律用 `DividendCompleteness`
  （`lib/domain/services/dividend_completeness.dart`）：兩個市場都查，有效列表日把
  完成紀錄算成列到月底
- ⚠️ 五張表（`dividend_distribution`、`dividend_month_ledger`、`dividend_month_failure`、
  `dividend_listing`、`dividend_unresolved`）同生共死：fingerprint reset 一起清空；若之後
  加保留期清理，五張表的規則必須一致——只刪配發資料而留下完成紀錄或事實，缺洞會被
  當成已完成、永遠補不回來
```

`dividend_coverage.dart` 的 class doc，把「給第 3 段讀取端的注意事項」三點換成：

```dart
/// 讀取端不用這裡的判定：逐檔完整度見 `DividendCompleteness`
/// （`lib/domain/services/dividend_completeness.dart`），它另外看列表日與
/// 未解決的列，兩個市場都查。
```

`DividendMonthFailure.failedSymbols` 的 doc 改為：

```dart
  /// 最後一次失敗時明細查不到或核對不符的代號：排序、去重、逗號分隔。
  /// 給退避與 warning 用；預算用完而中斷時未查的列不在這裡，判斷哪些列
  /// 不在庫要看 `dividend_unresolved`。
```

`2026-09-26-data-retention-plan.md` 的 Global Constraints，把「除權除息三張表…」那條改為：

```markdown
- 除權除息五張表（`dividend_distribution`、`dividend_month_ledger`、`dividend_month_failure`、`dividend_listing`、
  `dividend_unresolved`，2026-09～10 加入，本計畫寫成時還沒有）的規則必須一致：只刪配發資料而留下完成紀錄或
  完整度事實，回補與讀取端會把缺洞當成已完成、永遠補不回來。實作前先把五張表加進 Task 2 的政策宣告
```

`tool/backfill_dividend_distributions.dart` 檔頭第 8 行之後加：

```dart
// 2026-10 以前完成的月份沒有記錄前收盤與除權息參考價，第一次執行會把它們
// 重開一次（每個單位只打 1 次列表、不重查明細）。
```

- [ ] **Step 2: 檢查文件消費者**

Run: `grep -rn "三張表\|failedSymbols 可據此\|其餘都在庫" lib test docs .claude tool`
Expected: 沒有殘留（若 test/ 有測試把這些文件當原始碼讀，一併更新）

- [ ] **Step 3: 記錄進度（不 commit）**

---

### Task 8: 全套驗證、mutation、審查、副本彩排

- [ ] **Step 1: 靜態檢查與全套測試**

Run（log 寫到 scratchpad）：

```bash
dart format lib test tool
flutter analyze
flutter test > <scratchpad>/full_3_1.log 2>&1; tail -c 300 <scratchpad>/full_3_1.log
dart compile kernel tool/daily_update.dart -o build/daily_update.dill
dart compile kernel tool/backfill_dividend_distributions.dart -o build/backfill_dividend_distributions.dill
```

Expected: analyze 無 issue；全套通過；兩個 kernel 編譯成功

- [ ] **Step 2: mutation**

在 scratchpad 建 repo 副本（`rsync -rl`，不保留 mtime，含 `.dart_tool` 但不含 `flutter_build`），原始檔先備份，每個 mutant 開跑前檢查必要檔案存在，跑全部消費者測試（`test/data/remote test/data/database test/domain/services/update test/domain/services/update_service_test.dart test/domain/services/update_service_contract_guard_test.dart test/domain/services/dividend_completeness_test.dart test/tool test/app`），timeout 300 秒，用 `python3 -u`。至少涵蓋：

| 檔案 | mutant |
|:--|:--|
| twse_client | 欄位清單拿掉 `referenceCol`；「息」列不帶 `closeBefore`／`referencePrice` |
| tpex_client | 欄位清單拿掉 `closeCol` 或 `referenceCol`；不帶兩欄 |
| exright_result | `withDetail` 不保留 `referencePrice` |
| dividend_syncer | companion 不帶兩欄；上市不補價；`listedThrough` 用 `end`；`finally` 改成只在成功時記事實；`_recordListing` 吞錯改成往外拋；reasons 不記 |
| dividend_backfiller | 不補價；TPEx 不記事實；TWSE `finally` 改成只在成功時記；reasons 不記 |
| dividend_coverage | 拿掉 `entry.pricesRecorded` |
| dividend_dao | `completeDividendMonth` 不寫 true；`updateDividendDistributionPrices` 改成 upsert；未解決不減在庫；notInMaster 不減在庫；預設原因改 detailFailed；連續性條件拿掉；不倒退條件拿掉；`through` 不夾月底 |
| app_database | `_ensureDividendPriceColumns` 不補 `prices_recorded`；`_ensureDividendFactsSchema` 少建一張 |
| dividend_completeness | 只查一個市場；完成紀錄不推導列表日；完成紀錄時間條件拿掉；不查未解決；不查略過；`requirePrices` 不查；`displayEnd` 不取較早者；回補起點條件拿掉 |

存活者逐一判斷：補測試，或證明等價並刪掉多餘程式碼。

- [ ] **Step 3: 審查**

送 opus 審查（`pr-review-toolkit:code-reviewer`，範圍＝`git diff`＋未追蹤新檔），附本計畫與 spec 路徑、Review Focus 五條；限制：不可 `dart run`、不可背景任務、不可碰 scratchpad。修正後以 SendMessage 請同一位複審。

- [ ] **Step 4: 副本彩排**

1. `sqlite3 "file:<live>?mode=ro" "VACUUM INTO '<scratchpad>/rehearsal_3_1.sqlite'"`（無 -wal 時加 `&immutable=1`）
2. 對副本開一次 DB（觸發補欄、建表），`--dry-run` 確認計畫，再
   `dart run tool/backfill_dividend_distributions.dart --db <scratchpad>/rehearsal_3_1.sqlite`
3. 驗證（副本上 SQL）：
   - `SELECT count(*), sum(prices_recorded) FROM dividend_month_ledger` → 兩數相等（全部 138 個單位）
   - `SELECT count(*) FROM dividend_distribution WHERE close_before IS NULL OR reference_price IS NULL` → 0，或逐列列出並回報
   - `SELECT reason, count(*) FROM dividend_unresolved GROUP BY 1` → 只有 `NOT_IN_MASTER`
   - 抽三筆（純現金、配股 6669、現金增資 3149）比對 `reference_price ÷ close_before` 與官方列表
   - 呼叫次數約 138、無失敗
4. 回報結果與 commit message，等使用者說「提交」

- [ ] **Step 5: 提交後**

1. 確認 post-commit hook 已把 CLI 重編到新 commit（`~/Library/Logs/daredevil-cli-rebuild.log` 最後一行）
2. 經使用者同意、先備份 live DB，再以修復工具補價（或交給每輪回補：每輪約 28 個單位，約 5 輪）
3. 下一輪 launchd 日誌確認 build sha 與「除權除息回補」行；補價完成前回補累計會顯示未完成，屬預期
4. 3-1 補價完成後才進 3-2（3-2 的 52 週規則需要完整的價格欄）

Commit message 草稿：

```
feat: 除權除息配發表補存前收盤與參考價，並記錄完整度事實

- 上市、上櫃列表解析帶出除權息前收盤價與除權息參考價（所有列；單列缺值
  照收、存 null），配發表新增兩欄，已在庫的權／權息列以列表值補價
- 完成紀錄新增 prices_recorded：既有紀錄為 false，回補重開一次、只打列表補價
- 新表 dividend_listing（列表已同步到哪一天）與 dividend_unresolved（列表上有、
  不在配發表的列與原因）：本月同步與回補在列表成功後以一個 transaction 記錄，
  明細中斷也照記；本月同步記資料日而非牆鐘
- DividendCompleteness：逐檔完整度讀取模型，兩個市場都查、完成紀錄算列到月底，
  供 52 週規則與個股頁使用
```
