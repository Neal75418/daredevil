# 資料保留期 Implementation Plan

> **狀態（2026-09-26）：暫緩實作。** 必要性是從 Mac 資料推估的（手機每年約增加 970 MB），
> 要先量測手機上 App 實際佔用空間與成長速度再決定；計畫已可直接執行，屆時先重新核對文中的程式碼位置與行號。

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 手機（精簡模式）DB 穩定在約 390 MB、不再無上限成長；Mac（研究模式）保留完整時間序列；每張表都有宣告的保留規則。

**Architecture:** `core/` 放保留政策宣告（`RetentionMode`、每表規則、參數）；`data/` 放共用連線設定（`auto_vacuum`）、財報寫入過濾、刪除 SQL（`RetentionDaoMixin`）；`domain/` 的 `DataRetentionService` 依政策分批刪除、受時間預算管制，並由 `UpdateService` 在步驟 10+ fail-safe 最後一步呼叫。模式只在組裝點由平台決定，其餘一律必填注入。

**Tech Stack:** Flutter／Dart 3、Drift 2.32（SQLite、WAL）、sqlite3 3.x、mocktail、flutter_test

**Spec:** `docs/plans/2026-09-26-data-retention-design.md`

## Global Constraints

- 模式：`RetentionMode.lean`（iOS、Android）、`RetentionMode.research`（macOS）；平台判斷只存在 `RetentionMode.forCurrentPlatform()`，只在 `UpdateServiceFactory.build`、`providers.dart`、`tool/backfill.dart` 呼叫；所有接收模式的參數**必填、無預設值**
- 精簡模式保留期：financial_data 7 種項目、每檔每種報表 14 季（無允許項目的組整組保留）；holding_distribution 每檔各自最新 2 期；daily_price 460 天；daily_reason／daily_analysis 365 天；market_index 400 天；insider_holding 430 天；daily_institutional 200 天；shareholding 120 天；margin_trading 90 天；day_trading 60 天；stock_valuation 60 天
- 研究模式：時間序列全部保留
- 兩種模式共同：trading_warning 刪 `is_active = 0` 且超過 30 天；update_run 留最近 200 筆；news_item／news_stock_map 外部管理（既有 `cleanupOldNews` 與 FK cascade），通用清理不碰
- 財報允許項目：`EPS`、`IncomeAfterTaxes`、`Revenue`、`GrossProfit`、`OperatingIncome`、`Equity`、`TotalAssets`
- 例外（不因期限刪）：天數型 per-symbol 表每檔最新一筆；daily_price 的 ACTIVE 論點 pinnedDate 起的價格；daily_price 與 stock_event 同檔同台北日的價格
- 日期比較一律 `date(欄位, '+8 hours') < 'YYYY-MM-DD'`（台北日曆日），不用 `substr`
- 分批：每批 5000 列、每批一個 statement（自成交易）；每輪時間預算 15 秒；預算用完即停、下一輪接續
- `auto_vacuum = INCREMENTAL` 只在全新空檔（`page_count = 0`）設定；setup 順序 `busy_timeout` → `auto_vacuum` → `journal_mode = WAL`
- 清理後：`auto_vacuum` 為 INCREMENTAL 時 `incremental_vacuum(2048)` 分步釋放空頁（同一時間預算）；一律 `wal_checkpoint(TRUNCATE)`，BUSY 不算失敗
- 既有 DB 不自動完整 VACUUM；Mac 用 `tool/vacuum_db.dart`（先以 `lsof` 確認無其他程序開著）
- tool 鏈純 Dart：`lib/` 新檔不得 import flutter；`connection_setup.dart` 只 import `package:sqlite3`
- commit 由 user 說「提交」才做、純文字訊息、不加 Co-Authored-By；每個 Task 結束先送 code-reviewer，通過才進下一個 Task
- 每個新增條件做 mutation 驗收：逐一拔掉、跑測試確認變紅，再從備份還原（不用 git checkout 還原）

## Review Focus

- Mac 跑完 `tool/vacuum_db.dart`（DB 變 INCREMENTAL）後，launchd CLI 盤中寫入時開 App：開啟 DB 不可拋 `database is locked` → Task 1「既有 INCREMENTAL DB＋另一連線持寫鎖」測試
- 手機第一次清理量大（實測 Mac 不分批約 5 秒、約 149 萬列）：預算用完要停在批次邊界並回報未完成，下一輪接著刪完，不可一次長交易 → Task 5「預算中途用完」測試
- 金融股（損益表用 `IncomeAfterTax`）精簡模式寫入後，新鮮度檢查看得到該季、不會每輪重抓 → Task 3「金融股整組保留且新鮮度可見」測試
- ACTIVE 論點釘選超過 460 天、早期曾站上參考價：清理後論點監控仍判定有效 → Task 5「論點監控在清理後結果不變」測試
- 研究模式（Mac 正式 DB）：清理後所有時間序列表列數不變，只動 update_run 與已失效警示 → Task 5「研究模式只修剪兩張表」測試

---

### Task 1: 共用連線設定＋`auto_vacuum`

**Files:**
- Create: `lib/data/database/connection_setup.dart`
- Modify: `lib/data/database/app_database_flutter.dart`（`setup` 約 39-42 行）
- Modify: `lib/data/database/app_database.dart`（`forToolFile` 的 `setup` 約 181-189 行）
- Modify: `pubspec.yaml`（`sqlite3` 從 dev_dependencies 移到 dependencies）
- Test: `test/data/database/connection_setup_test.dart`

**Interfaces:**
- Consumes: 無
- Produces: `void configureDatabaseConnection(Database db)`（`package:sqlite3` 的 `Database`）

- [ ] **Step 1: 搬依賴**

`pubspec.yaml`：把 dev_dependencies 下的

```yaml
  # Tool scripts (tool/*.dart) 直連 SQLite 用
  sqlite3: ^3.0.0
```

移到 `dependencies:`（放在 `drift_flutter` 之後），註解改為：

```yaml
  # lib/ 的連線設定（connection_setup.dart）與 tool/*.dart 直連 SQLite 用
  sqlite3: ^3.0.0
```

Run: `flutter pub get && grep -A3 "^  sqlite3:" pubspec.lock`
Expected: `dependency: "direct main"`，版本仍為 3.5.1（只換分類、不新增套件）

- [ ] **Step 2: 寫失敗測試**

```dart
// test/data/database/connection_setup_test.dart
// 共用連線設定：auto_vacuum 只在全新空檔設定、App 與 CLI 走同一個函式。
//
// 一律用檔案 DB：記憶體 DB 或跳過 setup 的測試量不到 auto_vacuum 與鎖。
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/data/database/connection_setup.dart';

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('conn_setup_'));
  tearDown(() => dir.deleteSync(recursive: true));

  Object? pragma(Database db, String name) =>
      db.select('PRAGMA $name').first.values.first;

  test('全新檔案經 AppDatabase 建表後 auto_vacuum 為 INCREMENTAL、journal 為 WAL', () async {
    final path = '${dir.path}/fresh.sqlite';
    final db = AppDatabase(
      NativeDatabase(File(path), setup: configureDatabaseConnection),
    );
    await db.customSelect('SELECT 1').get(); // 觸發開啟、onCreate 建表
    final autoVacuum = await db.customSelect('PRAGMA auto_vacuum').getSingle();
    final journal = await db.customSelect('PRAGMA journal_mode').getSingle();
    await db.close();

    expect(autoVacuum.data.values.first, 2);
    expect(journal.data.values.first, 'wal');
  });

  test('既有 auto_vacuum=0 的 DB 不被轉換（轉換交給 tool/vacuum_db.dart）', () {
    final path = '${dir.path}/legacy.sqlite';
    sqlite3.open(path)
      ..execute('CREATE TABLE t(x)')
      ..close();

    final db = sqlite3.open(path);
    configureDatabaseConnection(db);
    expect(pragma(db, 'auto_vacuum'), 0);
    db.close();
  });

  test('既有 INCREMENTAL DB：另一連線持寫鎖時，設定連線不等鎖也不拋錯', () {
    final path = '${dir.path}/incremental.sqlite';
    final seed = sqlite3.open(path);
    configureDatabaseConnection(seed);
    seed
      ..execute('CREATE TABLE t(x)')
      ..close();

    // 模擬 launchd CLI 盤中寫入：持有寫鎖不放
    final holder = sqlite3.open(path)
      ..execute('BEGIN IMMEDIATE')
      ..execute('INSERT INTO t VALUES (1)');
    addTearDown(() {
      holder
        ..execute('ROLLBACK')
        ..close();
    });

    final other = sqlite3.open(path);
    final sw = Stopwatch()..start();
    expect(() => configureDatabaseConnection(other), returnsNormally);
    sw.stop();
    expect(pragma(other, 'auto_vacuum'), 2);
    other.close();
    // 若 setup 對既有 DB 設 auto_vacuum 會開寫入交易，會等滿 busy_timeout（5 秒）再拋錯
    expect(sw.elapsed, lessThan(const Duration(seconds: 2)));
  });

  test('App 與 CLI 兩條開啟路徑都用共用設定', () {
    for (final file in [
      'lib/data/database/app_database_flutter.dart',
      'lib/data/database/app_database.dart',
    ]) {
      expect(
        File(file).readAsStringSync(),
        contains('setup: configureDatabaseConnection'),
        reason: file,
      );
    }
  });
}
```

- [ ] **Step 3: 跑測試確認失敗**

Run: `flutter test test/data/database/connection_setup_test.dart`
Expected: 編譯失敗，`connection_setup.dart` 不存在

- [ ] **Step 4: 實作共用設定**

```dart
// lib/data/database/connection_setup.dart
import 'package:sqlite3/sqlite3.dart';

/// App（`openDriftFlutterConnection`）與 CLI（`AppDatabase.forToolFile`）
/// 共用的連線設定。必須是頂層函式：drift_flutter 會把 setup 送進背景 isolate。
///
/// 順序有意義：
///
/// 1. **`busy_timeout` 最先，不可省**：預設 0 會讓寫寫衝突當場拋
///    `SqliteException(5)`。實機被咬過兩側——GUI 手動更新握寫鎖時 launchd
///    那輪整個死在 beforeOpen 的維護 UPDATE；反過來盤中 CLI 每 5 分鐘持一次
///    寫鎖，App 內的寫入也會當場失敗。WAL 只解決讀寫並行，寫寫仍需排隊。
/// 2. **`auto_vacuum` 只在全新空檔設定**：必須在第一張表建立前、切 WAL 前
///    才生效（放 `onCreate` 會因這裡已先切 WAL 而靜默變成 0）。對已是
///    INCREMENTAL 的既有 DB 再設一次會開寫入交易，另一程序持寫鎖時 App 會
///    開不了 DB——所以既有 DB 一律不碰，轉換交給 `tool/vacuum_db.dart`。
/// 3. `journal_mode = WAL`。
void configureDatabaseConnection(Database db) {
  db.execute('PRAGMA busy_timeout = 5000');
  final pageCount = db.select('PRAGMA page_count').first.values.first as int;
  if (pageCount == 0) {
    db.execute('PRAGMA auto_vacuum = INCREMENTAL');
  }
  db.execute('PRAGMA journal_mode = WAL');
}
```

`app_database_flutter.dart`：加 `import 'package:daredevil/data/database/connection_setup.dart';`，把

```dart
      setup: (db) {
        db.execute('PRAGMA journal_mode=WAL;');
        db.execute('PRAGMA busy_timeout=5000;');
      },
```

換成 `setup: configureDatabaseConnection,`。上方 `// 🔴 busy_timeout 不可省…` 那段註解縮成一行：`// pragma 順序與理由見 configureDatabaseConnection`（內容已搬進該函式 doc）。

`app_database.dart` 的 `forToolFile`：加同一個 import，把 `setup: (db) { … }` 整段（含註解）換成 `setup: configureDatabaseConnection,`。

- [ ] **Step 5: 跑測試確認通過**

Run: `flutter test test/data/database/connection_setup_test.dart`
Expected: 4 個測試全過

- [ ] **Step 6: Mutation 驗收**

逐一套用、各自跑 Step 5 的指令、確認變紅後還原：
1. 拿掉 `if (pageCount == 0)`（每次都設 auto_vacuum）→ 預期「另一連線持寫鎖」紅
2. 把 `auto_vacuum` 那行移到 `journal_mode = WAL` 之後 → 預期「全新檔案」紅
3. `app_database_flutter.dart` 改回 inline closure → 預期「兩條開啟路徑」紅

Expected: 三個都紅；還原後全綠

- [ ] **Step 7: 純 Dart 鏈與 analyze**

Run: `dart compile kernel tool/daily_update.dart -o $TMPDIR/du.dill && flutter analyze --no-fatal-infos lib/ && flutter test test/tool/tool_chain_pure_dart_test.dart`
Expected: 編譯成功、analyze 無 issue、守門測試通過

- [ ] **Step 8: 送審，等 user「提交」**

```bash
git add pubspec.yaml pubspec.lock lib/data/database/connection_setup.dart lib/data/database/app_database_flutter.dart lib/data/database/app_database.dart test/data/database/connection_setup_test.dart
git commit -m "feat: 新建 DB 啟用 incremental auto_vacuum，App 與 CLI 共用連線設定"
```

---

### Task 2: 保留政策宣告＋守門測試

**Files:**
- Create: `lib/core/constants/data_retention_policy.dart`
- Test: `test/core/constants/data_retention_policy_test.dart`

**Interfaces:**
- Consumes: 無
- Produces:
  - `enum RetentionMode { lean, research; static RetentionMode forCurrentPlatform() }`
  - `sealed class RetentionRule`：`KeepAll()`、`KeepDays(int days, {bool keepLatestPerSymbol = false})`、`LatestPeriodsPerSymbol(int periods)`、`CustomRule()`、`ExternallyManaged()`
  - `class TableRetention { RetentionRule lean; RetentionRule research; RetentionRule forMode(RetentionMode) }`
  - `DataRetentionPolicy.tables`（`Map<String, TableRetention>`，key＝SQL 表名，宣告順序＝清理順序）
  - 常數：`financialAllowedTypes`（`Set<String>`）、`financialQuarters = 14`、`dailyPriceDays = 460`、`tradingWarningInactiveDays = 30`、`updateRunKeep = 200`、`deleteBatchSize = 5000`、`timeBudget = Duration(seconds: 15)`、`vacuumPagesPerStep = 2048`

- [ ] **Step 1: 寫失敗測試**

```dart
// test/core/constants/data_retention_policy_test.dart
// 保留政策守門：每張 DB 表都要宣告保留規則。清單由 DB 推導（allTables），
// 新增表格忘了決定保留期 → 這裡紅。
//
// 日後讀者延長回看範圍時，必須同步更新 DataRetentionPolicy 的期限與依據註解。
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/constants/data_retention_policy.dart';
import 'package:daredevil/data/database/app_database.dart';

void main() {
  test('每張 DB 表都有保留宣告，且沒有宣告不存在的表', () async {
    final db = AppDatabase.forTesting();
    addTearDown(db.close);
    final names = db.allTables.map((t) => t.actualTableName).toSet();

    // 下限：列舉失敗（空集合）時不空轉通過
    expect(names.length, greaterThanOrEqualTo(30));
    expect(DataRetentionPolicy.tables.keys.toSet(), names);
  });

  test('研究模式只清 trading_warning、update_run，外部管理的表不碰，其餘全保留', () {
    for (final MapEntry(key: table, value: retention)
        in DataRetentionPolicy.tables.entries) {
      final rule = retention.forMode(RetentionMode.research);
      switch (table) {
        case 'trading_warning' || 'update_run':
          expect(rule, isA<CustomRule>(), reason: table);
        case 'news_item' || 'news_stock_map':
          expect(rule, isA<ExternallyManaged>(), reason: table);
        default:
          expect(rule, isA<KeepAll>(), reason: table);
      }
    }
  });

  test('精簡模式的天數型期限與 spec 一致', () {
    const expected = {
      'daily_reason': (365, false),
      'daily_analysis': (365, false),
      'market_index': (400, false),
      'insider_holding': (430, true),
      'daily_institutional': (200, true),
      'shareholding': (120, true),
      'margin_trading': (90, true),
      'day_trading': (60, true),
      'stock_valuation': (60, true),
    };
    for (final MapEntry(key: table, value: (days, keepLatest))
        in expected.entries) {
      final rule = DataRetentionPolicy.tables[table]!.forMode(RetentionMode.lean);
      expect(rule, isA<KeepDays>(), reason: table);
      rule as KeepDays;
      expect((rule.days, rule.keepLatestPerSymbol), (days, keepLatest),
          reason: table);
    }
    final holding = DataRetentionPolicy.tables['holding_distribution']!
        .forMode(RetentionMode.lean);
    expect((holding as LatestPeriodsPerSymbol).periods, 2);
    for (final table in ['financial_data', 'daily_price']) {
      expect(DataRetentionPolicy.tables[table]!.forMode(RetentionMode.lean),
          isA<CustomRule>(), reason: table);
    }
  });
}
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `flutter test test/core/constants/data_retention_policy_test.dart`
Expected: 編譯失敗，`data_retention_policy.dart` 不存在

- [ ] **Step 3: 實作政策**

```dart
// lib/core/constants/data_retention_policy.dart
import 'dart:io' show Platform;

/// 資料保留模式（設計：`docs/plans/2026-09-26-data-retention-design.md`）
enum RetentionMode {
  /// iOS、Android：只留功能需要的資料
  lean,

  /// macOS：時間序列全部保留（回測、校準、回補工具只在 Mac 執行；
  /// holding_distribution 官方不給歷史、上櫃當沖是花額度回補的，刪了拿不回來）
  research;

  /// 唯一的平台判斷點。只在組裝點呼叫：`UpdateServiceFactory.build`、
  /// `providers.dart` 的財報 repository、`tool/backfill.dart`。
  /// 其餘建構子把模式當必填參數——預設值若是這裡，測試在本機 Mac 與
  /// CI ubuntu 會跑出不同結果。
  static RetentionMode forCurrentPlatform() =>
      Platform.isMacOS ? RetentionMode.research : RetentionMode.lean;
}

/// 單張表的保留規則
sealed class RetentionRule {
  const RetentionRule();
}

/// 不清
final class KeepAll extends RetentionRule {
  const KeepAll();
}

/// 刪台北日曆日早於「今天 − [days]」的列（邊界當天保留）。
/// [keepLatestPerSymbol]：每檔最新一筆一律保留——「取最新一筆」的讀者不限
/// 日期（`getLatestPricesBatch`、`valuation_dao.dart:36`、個股頁
/// `getRecentPrices`），長期停牌股的最後資料不能因期限消失。
final class KeepDays extends RetentionRule {
  const KeepDays(this.days, {this.keepLatestPerSymbol = false});

  final int days;
  final bool keepLatestPerSymbol;
}

/// 每檔各自保留最新 [periods] 期（不是全市場同一個截止期）
final class LatestPeriodsPerSymbol extends RetentionRule {
  const LatestPeriodsPerSymbol(this.periods);

  final int periods;
}

/// 專屬邏輯（financial_data、daily_price、trading_warning、update_run），
/// 參數在 [DataRetentionPolicy]，實作在 `DataRetentionService`
final class CustomRule extends RetentionRule {
  const CustomRule();
}

/// 由既有機制管理，通用清理不下任何 SQL
final class ExternallyManaged extends RetentionRule {
  const ExternallyManaged();
}

class TableRetention {
  const TableRetention({required this.lean, required this.research});

  final RetentionRule lean;
  final RetentionRule research;

  RetentionRule forMode(RetentionMode mode) => switch (mode) {
    RetentionMode.lean => lean,
    RetentionMode.research => research,
  };
}

/// 每張 DB 表的保留規則（守門：`test/core/constants/data_retention_policy_test.dart`）。
///
/// 每個期限＝盤點出的讀者最長回看＋餘裕，依據寫在宣告旁。讀者延長回看時，
/// 必須同步更新這裡。
///
/// 不因期限刪除的例外（實作在 `RetentionDaoMixin`）：
/// - [KeepDays.keepLatestPerSymbol]：每檔最新一筆
/// - daily_price：ACTIVE 論點 pinnedDate 起的價格——`ThesisMonitorService`
///   讀 pinnedDate 起全部價格判斷「曾站上參考價」，站上後永不觸發 timeStop；
///   刪掉早期價格會誤判失效且不可逆
/// - daily_price：與 stock_event 同檔同台北日的價格——事件詳情以
///   `getPriceOnDate` 精確比對事件日（`price_dao.dart:72`），stock_event 全保留
abstract final class DataRetentionPolicy {
  /// 財報允許項目。前 6 種有讀者；TotalAssets 目前 lib/ 無讀者，但解析器
  /// 註解列為使用中，保守保留
  static const financialAllowedTypes = {
    'EPS',
    'IncomeAfterTaxes',
    'Revenue',
    'GrossProfit',
    'OperatingIncome',
    'Equity',
    'TotalAssets',
  };

  /// ROE 8 個點需 12 季（`financial_data_dao.dart:209-255`）＋2 季緩衝；
  /// 重抓下限 5 季（`api_config.dart:72`）
  static const financialQuarters = 14;

  /// 規則與 Phase 0 補抓下限 400 天（`rule_params.dart:49`、
  /// `historical_price_syncer.dart:220`）＋60 天餘裕；52 週高低只需 200 筆
  /// （`market_overview_dao.dart:636`）
  static const dailyPriceDays = 460;

  /// 籌碼異動查 30 天內的處置股、不看 is_active（`chip_scoring_params.dart:266`）
  static const tradingWarningInactiveDays = 30;

  /// 畫面只顯示 30 筆（`update_history_provider.dart:19`）
  static const updateRunKeep = 200;

  static const deleteBatchSize = 5000;

  /// 每輪清理＋空間回收的時間上限。手機背景任務時間很短；第一次清理量大
  /// （Mac 實測不分批約 5 秒），用完即停、下一輪接續
  static const timeBudget = Duration(seconds: 15);

  /// `incremental_vacuum(N)` 每步釋放的頁數（4 KB 頁 ≈ 8 MB）
  static const vacuumPagesPerStep = 2048;

  static const _keepAll = TableRetention(lean: KeepAll(), research: KeepAll());
  static const _external = TableRetention(
    lean: ExternallyManaged(),
    research: ExternallyManaged(),
  );

  /// 宣告順序＝清理順序：大表在前，時間預算先用在效果最大處
  static const tables = <String, TableRetention>{
    // 7 種項目、每檔每種報表 14 季；無允許項目的組整組保留（金融股）
    'financial_data': TableRetention(lean: CustomRule(), research: KeepAll()),
    // 讀者只看最新一期：個股用該檔自己的最新期（`holding_distribution_dao.dart:9-26`）
    'holding_distribution': TableRetention(
      lean: LatestPeriodsPerSymbol(2),
      research: KeepAll(),
    ),
    // [dailyPriceDays]＋每檔最新一筆＋ACTIVE 論點＋事件日
    'daily_price': TableRetention(lean: CustomRule(), research: KeepAll()),
    // 命中率讀全部（`rule_accuracy_service.dart:132/146`）；手機只有安裝後的歷史
    'daily_reason': TableRetention(lean: KeepDays(365), research: KeepAll()),
    'daily_analysis': TableRetention(lean: KeepDays(365), research: KeepAll()),
    // 大盤連買賣 180 天（`market_overview_dao.dart:401`）
    'daily_institutional': TableRetention(
      lean: KeepDays(200, keepLatestPerSymbol: true),
      research: KeepAll(),
    ),
    // 大盤融資 65 天（`market_overview_dao.dart:478`）
    'margin_trading': TableRetention(
      lean: KeepDays(90, keepLatestPerSymbol: true),
      research: KeepAll(),
    ),
    // 缺漏偵測下限 40 天（`api_config.dart:223`）
    'day_trading': TableRetention(
      lean: KeepDays(60, keepLatestPerSymbol: true),
      research: KeepAll(),
    ),
    // 個股籌碼 90 天（`data_freshness.dart:197`）
    'shareholding': TableRetention(
      lean: KeepDays(120, keepLatestPerSymbol: true),
      research: KeepAll(),
    ),
    // 30 天（`data_freshness.dart:204`）
    'stock_valuation': TableRetention(
      lean: KeepDays(60, keepLatestPerSymbol: true),
      research: KeepAll(),
    ),
    // 「12 個月」從起始月 1 日算，最長約 396 天（`insider_repository.dart:41`）
    'insider_holding': TableRetention(
      lean: KeepDays(430, keepLatestPerSymbol: true),
      research: KeepAll(),
    ),
    // syncer 要求最舊一筆早於 now−370（`market_index_syncer.dart:206-219`）
    'market_index': TableRetention(lean: KeepDays(400), research: KeepAll()),
    'trading_warning': TableRetention(lean: CustomRule(), research: CustomRule()),
    'update_run': TableRetention(lean: CustomRule(), research: CustomRule()),
    // 既有 `cleanupOldNews`（30 天、`published_at`）；map 隨 FK cascade
    'news_item': _external,
    'news_stock_map': _external,
    // 讀全部歷史、刻意保留、非時間序列或很小
    'stock_master': _keepAll,
    'news_mention_daily': _keepAll,
    'rule_accuracy': _keepAll,
    'watchlist_groups': _keepAll,
    'watchlist': _keepAll,
    'app_settings': _keepAll,
    'price_alert': _keepAll,
    'pinned_thesis': _keepAll,
    'monthly_revenue': _keepAll, // 歷史最高營收讀全部（`revenue_dao.dart:322-337`）
    'dividend_history': _keepAll,
    'insider_transfer': _keepAll,
    'portfolio_position': _keepAll,
    'portfolio_transaction': _keepAll,
    'stock_event': _keepAll,
    'quarterly_report': _keepAll,
  };
}
```

- [ ] **Step 4: 跑測試確認通過**

Run: `flutter test test/core/constants/data_retention_policy_test.dart test/core/core_layer_purity_test.dart`
Expected: 全過（core 純度守門也過：新檔只 import `dart:io`）

- [ ] **Step 5: Mutation 驗收**

1. 從 `tables` 刪掉 `'quarterly_report'` → 預期「每張 DB 表」紅
2. `'day_trading'` 研究模式改成 `KeepDays(60)` → 預期「研究模式」紅
3. `insider_holding` 改 400 → 預期「精簡模式天數」紅

Expected: 三個都紅；還原後全綠

- [ ] **Step 6: 送審，等 user「提交」**

```bash
git add lib/core/constants/data_retention_policy.dart test/core/constants/data_retention_policy_test.dart
git commit -m "feat: 資料保留政策宣告與每表守門測試"
```

---

### Task 3: 財報寫入過濾（精簡模式）

**Files:**
- Modify: `lib/data/database/dao/financial_data_dao.dart`（`insertFinancialData` 約 29-35 行，新增 `filterFinancialEntriesForLean`）
- Modify: `lib/data/repositories/fundamental_repository.dart`（建構子約 20-32 行、`insertFinancialData` 呼叫約 622 行）
- Modify: `lib/data/repositories/market_data_repository.dart`（建構子約 18-28 行、呼叫約 110、210 行）
- Modify: `lib/domain/services/update_service_factory.dart`、`lib/presentation/providers/providers.dart`（約 265-282 行）、`tool/backfill.dart`（約 1420 行）
- Modify（補參數、維持原行為）：所有建構 `FundamentalRepository`／`MarketDataRepository` 或呼叫 `insertFinancialData` 的測試
- Test: `test/data/database/dao/financial_retention_filter_test.dart`、`test/data/repositories/financial_write_retention_test.dart`

**Interfaces:**
- Consumes: Task 2 的 `RetentionMode`、`DataRetentionPolicy.financialAllowedTypes`
- Produces:
  - `Future<void> insertFinancialData(List<FinancialDataCompanion> entries, {required RetentionMode mode})`
  - `@visibleForTesting List<FinancialDataCompanion> filterFinancialEntriesForLean(List<FinancialDataCompanion> entries)`（頂層函式，`financial_data_dao.dart`）
  - `FundamentalRepository({…, required RetentionMode retentionMode})`、`MarketDataRepository({…, required RetentionMode retentionMode})`

- [ ] **Step 1: 寫 DAO 過濾的失敗測試**

```dart
// test/data/database/dao/financial_retention_filter_test.dart
// 精簡模式的財報寫入過濾：以「一檔、一種報表、一季」為一組，
// 組內有允許項目 → 只留允許項目；沒有 → 整組保留（金融股）。
import 'package:drift/drift.dart' show Value, Variable;
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/constants/data_retention_policy.dart';
import 'package:daredevil/data/database/app_database.dart';

void main() {
  late AppDatabase db;

  FinancialDataCompanion row(
    String symbol,
    DateTime date,
    String statement,
    String type,
  ) => FinancialDataCompanion.insert(
    symbol: symbol,
    date: date,
    statementType: statement,
    dataType: type,
    value: const Value(1.0),
  );

  Future<Set<String>> stored(String symbol, String statement) async {
    final rows = await db
        .customSelect(
          'SELECT data_type FROM financial_data '
          'WHERE symbol = ? AND statement_type = ?',
          variables: [Variable.withString(symbol), Variable.withString(statement)],
        )
        .get();
    return rows.map((r) => r.read<String>('data_type')).toSet();
  }

  final q2 = DateTime(2026, 6, 30);

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.upsertStocks([
      StockMasterCompanion.insert(symbol: '2330', name: '台積電', market: 'TWSE'),
      StockMasterCompanion.insert(symbol: '2801', name: '彰銀', market: 'TWSE'),
    ]);
  });

  tearDown(() => db.close());

  test('精簡：組內有允許項目 → 只寫允許項目', () async {
    await db.insertFinancialData([
      row('2330', q2, 'INCOME', 'EPS'),
      row('2330', q2, 'INCOME', 'CostOfGoodsSold'),
    ], mode: RetentionMode.lean);
    expect(await stored('2330', 'INCOME'), {'EPS'});
  });

  test('精簡：金融股組內沒有允許項目 → 整組保留，且新鮮度檢查看得到該季', () async {
    await db.insertFinancialData([
      row('2801', q2, 'INCOME', 'IncomeAfterTax'),
      row('2801', q2, 'INCOME', 'NetInterestIncome'),
    ], mode: RetentionMode.lean);
    expect(await stored('2801', 'INCOME'), {'IncomeAfterTax', 'NetInterestIncome'});
    // 新鮮度檢查只看「該季有沒有任一列」；濾光會讓它每輪重抓
    expect(await db.getLatestFinancialDataDate('2801', 'INCOME'), q2);
  });

  test('分組含報表類型：INCOME 有允許項目不影響同季 BALANCE 的判斷', () async {
    await db.insertFinancialData([
      row('2330', q2, 'INCOME', 'EPS'),
      row('2330', q2, 'BALANCE', 'OtherAssets'),
    ], mode: RetentionMode.lean);
    expect(await stored('2330', 'BALANCE'), {'OtherAssets'});
  });

  test('研究：全寫', () async {
    await db.insertFinancialData([
      row('2330', q2, 'INCOME', 'EPS'),
      row('2330', q2, 'INCOME', 'CostOfGoodsSold'),
    ], mode: RetentionMode.research);
    expect(await stored('2330', 'INCOME'), {'EPS', 'CostOfGoodsSold'});
  });
}
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `flutter test test/data/database/dao/financial_retention_filter_test.dart`
Expected: 編譯失敗，`insertFinancialData` 沒有 `mode` 參數

- [ ] **Step 3: 實作 DAO 過濾**

`financial_data_dao.dart` 加 import `package:meta/meta.dart` 的 `visibleForTesting`、`package:daredevil/core/constants/data_retention_policy.dart`，把 `insertFinancialData` 換成：

```dart
  /// 寫入財報。[mode] 為精簡時先套 [filterFinancialEntriesForLean]——
  /// 三條寫入路徑（FinMind 損益表、FinMind 資產負債表、官方全市場資產負債表）
  /// 都經過這裡，所以過濾放這裡而不是某一條路徑。
  Future<void> insertFinancialData(
    List<FinancialDataCompanion> entries, {
    required RetentionMode mode,
  }) async {
    final kept = switch (mode) {
      RetentionMode.lean => filterFinancialEntriesForLean(entries),
      RetentionMode.research => entries,
    };
    if (kept.isEmpty) return;
    await batch((b) {
      for (final entry in kept) {
        b.insert(financialData, entry, mode: InsertMode.insertOrReplace);
      }
    });
  }
```

檔案底部（mixin 之外）加頂層函式：

```dart
/// 精簡模式的財報寫入過濾。以「一檔、一種報表、一季」為一組：
/// 組內有 [DataRetentionPolicy.financialAllowedTypes] → 只留允許項目；
/// 組內沒有 → 整組保留。金融股損益表用 `IncomeAfterTax` 等不同名稱，濾光會讓
/// 只看「該季有沒有任一列」的新鮮度檢查（`fundamental_syncer.dart:484-503`、
/// `fundamental_repository.dart:586-591`）每輪重抓。
///
/// 事後清理 `RetentionDaoMixin.deleteDisallowedFinancialTypes` 是同一規則的
/// SQL 版，兩者由 `financial_retention_equivalence_test` 綁住。
@visibleForTesting
List<FinancialDataCompanion> filterFinancialEntriesForLean(
  List<FinancialDataCompanion> entries,
) {
  const allowed = DataRetentionPolicy.financialAllowedTypes;
  (String, DateTime, String) group(FinancialDataCompanion e) =>
      (e.symbol.value, e.date.value, e.statementType.value);
  final groupsWithAllowed = {
    for (final e in entries)
      if (allowed.contains(e.dataType.value)) group(e),
  };
  return [
    for (final e in entries)
      if (allowed.contains(e.dataType.value) ||
          !groupsWithAllowed.contains(group(e)))
        e,
  ];
}
```

- [ ] **Step 4: 跑 DAO 測試確認通過**

Run: `flutter test test/data/database/dao/financial_retention_filter_test.dart`
Expected: 4 個測試全過（其他檔此時編譯失敗是預期，下一步處理）

- [ ] **Step 5: 寫 repository 傳遞模式的失敗測試**

```dart
// test/data/repositories/financial_write_retention_test.dart
// 三條財報寫入路徑都把注入的模式帶到 insertFinancialData：
// 只過濾其中一條，佔 80% 的資產負債表就會照寫。
import 'package:drift/drift.dart' show Variable;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:daredevil/core/constants/data_retention_policy.dart';
import 'package:daredevil/core/utils/clock.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/data/models/finmind/balance_sheet.dart';
import 'package:daredevil/data/models/finmind/financial_statement.dart';
import 'package:daredevil/data/models/twse/market_wide_financial.dart';
import 'package:daredevil/data/remote/finmind_client.dart';
import 'package:daredevil/data/remote/mops_client.dart';
import 'package:daredevil/data/remote/tpex_client.dart';
import 'package:daredevil/data/remote/twse_client.dart';
import 'package:daredevil/data/repositories/fundamental_repository.dart';
import 'package:daredevil/data/repositories/market_data_repository.dart';

class MockFinMindClient extends Mock implements FinMindClient {}

class MockTwseClient extends Mock implements TwseClient {}

class MockTpexClient extends Mock implements TpexClient {}

class MockMopsClient extends Mock implements MopsClient {}

class _FixedClock implements AppClock {
  const _FixedClock(this._now);
  final DateTime _now;

  @override
  DateTime now() => _now;
}

void main() {
  late AppDatabase db;
  late MockFinMindClient finMind;
  late MockTwseClient twse;
  final clock = _FixedClock(DateTime(2026, 9, 26));

  Future<Set<String>> storedTypes(String statement) async {
    final rows = await db
        .customSelect(
          'SELECT data_type FROM financial_data WHERE statement_type = ?',
          variables: [Variable.withString(statement)],
        )
        .get();
    return rows.map((r) => r.read<String>('data_type')).toSet();
  }

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.upsertStocks([
      StockMasterCompanion.insert(symbol: '2330', name: '台積電', market: 'TWSE'),
    ]);
    finMind = MockFinMindClient();
    twse = MockTwseClient();
  });

  tearDown(() => db.close());

  test('FinMind 損益表（精簡）只寫允許項目', () async {
    when(
      () => finMind.getFinancialStatements(
        stockId: any(named: 'stockId'),
        startDate: any(named: 'startDate'),
        endDate: any(named: 'endDate'),
      ),
    ).thenAnswer(
      (_) async => const [
        FinMindFinancialStatement(
          stockId: '2330', date: '2026-06-30', type: 'EPS', value: 5, origin: 'EPS',
        ),
        FinMindFinancialStatement(
          stockId: '2330', date: '2026-06-30', type: 'CostOfGoodsSold', value: 1, origin: 'x',
        ),
      ],
    );
    final repo = FundamentalRepository(
      db: db,
      finMind: finMind,
      twse: twse,
      tpex: MockTpexClient(),
      mops: MockMopsClient(),
      clock: clock,
      retentionMode: RetentionMode.lean,
    );

    await repo.syncFinancialStatements(
      symbol: '2330',
      startDate: DateTime(2024, 1, 1),
      endDate: DateTime(2026, 9, 26),
    );

    expect(await storedTypes('INCOME'), {'EPS'});
  });

  test('FinMind 資產負債表（精簡）只寫允許項目', () async {
    when(
      () => finMind.getBalanceSheet(
        stockId: any(named: 'stockId'),
        startDate: any(named: 'startDate'),
        endDate: any(named: 'endDate'),
      ),
    ).thenAnswer(
      (_) async => const [
        FinMindBalanceSheet(
          stockId: '2330', date: '2026-06-30', type: 'Equity', value: 9, origin: 'x',
        ),
        FinMindBalanceSheet(
          stockId: '2330', date: '2026-06-30', type: 'CashAndCashEquivalents', value: 1, origin: 'x',
        ),
      ],
    );
    final repo = MarketDataRepository(
      database: db,
      finMindClient: finMind,
      clock: clock,
      retentionMode: RetentionMode.lean,
    );

    await repo.syncBalanceSheet('2330', startDate: DateTime(2024, 1, 1));

    expect(await storedTypes('BALANCE'), {'Equity'});
  });

  test('官方全市場資產負債表（精簡）只寫允許項目', () async {
    when(() => twse.getAllBalanceSheets()).thenAnswer(
      (_) async => [
        MarketWideFinancial(
          symbol: '2330', date: DateTime(2026, 6, 30),
          statementType: 'BALANCE', dataType: 'Equity', value: 9,
        ),
        MarketWideFinancial(
          symbol: '2330', date: DateTime(2026, 6, 30),
          statementType: 'BALANCE', dataType: 'TotalLiabilities', value: 1,
        ),
      ],
    );
    final repo = MarketDataRepository(
      database: db,
      finMindClient: finMind,
      twseClient: twse,
      clock: clock,
      retentionMode: RetentionMode.lean,
    );

    await repo.syncMarketWideBalanceSheets();

    expect(await storedTypes('BALANCE'), {'Equity'});
  });

  test('研究模式照舊全寫（官方全市場路徑）', () async {
    when(() => twse.getAllBalanceSheets()).thenAnswer(
      (_) async => [
        MarketWideFinancial(
          symbol: '2330', date: DateTime(2026, 6, 30),
          statementType: 'BALANCE', dataType: 'Equity', value: 9,
        ),
        MarketWideFinancial(
          symbol: '2330', date: DateTime(2026, 6, 30),
          statementType: 'BALANCE', dataType: 'TotalLiabilities', value: 1,
        ),
      ],
    );
    final repo = MarketDataRepository(
      database: db,
      finMindClient: finMind,
      twseClient: twse,
      clock: clock,
      retentionMode: RetentionMode.research,
    );

    await repo.syncMarketWideBalanceSheets();

    expect(await storedTypes('BALANCE'), {'Equity', 'TotalLiabilities'});
  });
}
```

- [ ] **Step 6: 跑測試確認失敗**

Run: `flutter test test/data/repositories/financial_write_retention_test.dart`
Expected: 編譯失敗，repository 沒有 `retentionMode` 參數

- [ ] **Step 7: repository 接模式**

`FundamentalRepository`：建構子加 `required RetentionMode retentionMode`，存成 `final RetentionMode _retentionMode;`（初始化列 `_retentionMode = retentionMode`），約 622 行改為 `await _db.insertFinancialData(entries, mode: _retentionMode);`。

`MarketDataRepository`：同樣加 `required RetentionMode retentionMode` 與 `_retentionMode`，約 110、210 行兩處都改為 `await _db.insertFinancialData(entries, mode: _retentionMode);`。

組裝點：
- `update_service_factory.dart` 的 `build` 開頭加 `final retentionMode = RetentionMode.forCurrentPlatform();`，`MarketDataRepository(…)`、`FundamentalRepository(…)` 各加 `retentionMode: retentionMode,`（Task 6 也會用同一個變數）
- `providers.dart` 的 `marketDataRepositoryProvider`、`fundamentalRepositoryProvider` 各加 `retentionMode: RetentionMode.forCurrentPlatform(),`
- `tool/backfill.dart` 約 1420 行的 `FundamentalRepository(…)` 加 `retentionMode: RetentionMode.forCurrentPlatform(),`

測試（維持原行為＝全寫，一律 `RetentionMode.research`）：

Run: `grep -rln "FundamentalRepository(\|MarketDataRepository(\|insertFinancialData(" test/`

每個建構點加 `retentionMode: RetentionMode.research,`；每個直接呼叫 `db.insertFinancialData([...])` 加 `, mode: RetentionMode.research`；`fundamental_repository_income_freshness_test.dart` 的 mock stub 改為

```dart
    when(
      () => mockDb.insertFinancialData(any(), mode: any(named: 'mode')),
    ).thenAnswer((_) async {});
```

並在該檔 `setUpAll` 加 `registerFallbackValue(RetentionMode.research);`。各檔補 `import 'package:daredevil/core/constants/data_retention_policy.dart';`。

- [ ] **Step 8: 跑相關測試與 analyze**

Run: `flutter analyze --no-fatal-infos lib/ test/ tool/ && flutter test test/data/ test/domain/services/update/ test/domain/services/update_service_test.dart`
Expected: analyze 無 issue；測試全過

- [ ] **Step 9: Mutation 驗收**

1. `filterFinancialEntriesForLean` 的 `|| !groupsWithAllowed.contains(group(e))` 拿掉 → 預期「金融股整組保留」紅
2. `group` 的 key 拿掉 statementType（只用 symbol、date）→ 預期「分組含報表類型」紅
3. `market_data_repository.dart` 約 110 行改傳 `mode: RetentionMode.research` → 預期「官方全市場」紅
4. 約 210 行同樣改 → 預期「FinMind 資產負債表」紅

Expected: 四個都紅；還原後全綠

- [ ] **Step 10: 送審，等 user「提交」**

```bash
git add lib/data/database/dao/financial_data_dao.dart lib/data/repositories/fundamental_repository.dart lib/data/repositories/market_data_repository.dart lib/domain/services/update_service_factory.dart lib/presentation/providers/providers.dart tool/backfill.dart test/
git commit -m "feat: 精簡模式財報只寫有讀者的項目，三條寫入路徑共用過濾"
```

（`git add test/` 前先 `git status --short test/` 確認只有本 Task 動到的檔）

---

### Task 4: 刪除 SQL（`RetentionDaoMixin`）

**Files:**
- Create: `lib/data/database/dao/retention_dao.dart`
- Modify: `lib/data/database/app_database.dart`（import 與 `with …` 清單加 `RetentionDaoMixin`）
- Test: `test/data/database/dao/retention_dao_test.dart`、`test/data/database/dao/financial_retention_equivalence_test.dart`

**Interfaces:**
- Consumes: Task 2 的 `DataRetentionPolicy.financialAllowedTypes`；Task 3 的 `filterFinancialEntriesForLean`
- Produces（皆為 `AppDatabase` 方法；`cutoffDay` 為台北日 `YYYY-MM-DD`，刪 `台北日 < cutoffDay`；回傳刪除筆數，`< limit` 表示該項已清完）：
  - `Future<int> deleteExpiredRows(String table, {required String cutoffDay, required bool keepLatestPerSymbol, required int limit})`
  - `Future<int> deleteExpiredDailyPrices({required String cutoffDay, required int limit})`
  - `Future<int> deleteBeyondLatestPeriods(String table, {required int periods, required int limit})`
  - `Future<int> deleteDisallowedFinancialTypes({required int limit})`
  - `Future<int> deleteFinancialQuartersBeyond({required int quarters, required int limit})`
  - `Future<int> deleteInactiveTradingWarnings({required String cutoffDay, required int limit})`
  - `Future<int> trimUpdateRuns({required int keep})`
  - `Future<int> autoVacuumMode()`、`Future<int> freelistCount()`、`Future<void> incrementalVacuum(int pages)`、`Future<bool> checkpointTruncate()`

- [ ] **Step 1: 寫失敗測試**

```dart
// test/data/database/dao/retention_dao_test.dart
// 保留期刪除 SQL。日期一律以原始字串寫入，固定時區字尾，不受測試機時區影響。
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/data/database/app_database.dart';

void main() {
  late AppDatabase db;

  Future<void> exec(String sql, [List<Object?> args = const []]) =>
      db.customStatement(sql, args);

  Future<List<String>> days(String table, String symbol) async {
    final rows = await db
        .customSelect(
          "SELECT date(date, '+8 hours') AS d FROM $table "
          "WHERE symbol = '$symbol' ORDER BY date",
        )
        .get();
    return rows.map((r) => r.read<String>('d')).toList();
  }

  Future<void> price(String symbol, String raw, [double close = 100]) => exec(
    'INSERT INTO daily_price(symbol, date, close) VALUES (?, ?, ?)',
    [symbol, raw, close],
  );

  String tp(String day) => '${day}T00:00:00.000 +08:00';

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.upsertStocks([
      for (final s in ['2330', '2317', '2801', '9999'])
        StockMasterCompanion.insert(symbol: s, name: s, market: 'TWSE'),
    ]);
  });

  tearDown(() => db.close());

  group('deleteExpiredRows', () {
    test('邊界當天保留、前一天刪除', () async {
      for (final d in ['2025-12-31', '2026-01-01', '2026-01-02']) {
        await price('2330', tp(d));
      }
      final n = await db.deleteExpiredRows(
        'daily_price',
        cutoffDay: '2026-01-01',
        keepLatestPerSymbol: false,
        limit: 100,
      );
      expect(n, 1);
      expect(await days('daily_price', '2330'), ['2026-01-01', '2026-01-02']);
    });

    test('Z 字尾以台北日判斷：UTC 16:00 屬於台北隔天', () async {
      await price('2330', '2025-12-31T16:00:00.000Z'); // 台北 2026-01-01 00:00
      await price('2330', '2025-12-31T15:59:59.000Z'); // 台北 2025-12-31 23:59
      await price('2330', tp('2026-02-01'));
      await db.deleteExpiredRows(
        'daily_price',
        cutoffDay: '2026-01-01',
        keepLatestPerSymbol: false,
        limit: 100,
      );
      expect(await days('daily_price', '2330'), ['2026-01-01', '2026-02-01']);
    });

    test('keepLatestPerSymbol：只有舊資料的股票保留最新一筆', () async {
      await price('9999', tp('2025-01-01'));
      await price('9999', tp('2025-01-02'));
      await db.deleteExpiredRows(
        'daily_price',
        cutoffDay: '2026-01-01',
        keepLatestPerSymbol: true,
        limit: 100,
      );
      expect(await days('daily_price', '9999'), ['2025-01-02']);
    });

    test('keepLatestPerSymbol=false：舊資料全刪', () async {
      await price('9999', tp('2025-01-01'));
      await price('9999', tp('2025-01-02'));
      await db.deleteExpiredRows(
        'daily_price',
        cutoffDay: '2026-01-01',
        keepLatestPerSymbol: false,
        limit: 100,
      );
      expect(await days('daily_price', '9999'), isEmpty);
    });

    test('每批最多刪 limit 筆', () async {
      for (final d in ['2025-01-01', '2025-01-02', '2025-01-03']) {
        await price('2330', tp(d));
      }
      Future<int> once() => db.deleteExpiredRows(
        'daily_price',
        cutoffDay: '2026-01-01',
        keepLatestPerSymbol: false,
        limit: 2,
      );
      expect(await once(), 2);
      expect(await once(), 1);
      expect(await once(), 0);
    });

    test('非法表名直接拒絕', () async {
      expect(
        () => db.deleteExpiredRows(
          'daily_price; DROP TABLE stock_master',
          cutoffDay: '2026-01-01',
          keepLatestPerSymbol: false,
          limit: 1,
        ),
        throwsArgumentError,
      );
    });
  });

  group('deleteExpiredDailyPrices', () {
    Future<void> thesis(String symbol, String pinnedDay, String status) => exec(
      'INSERT INTO pinned_thesis(symbol, pinned_date, reference_price, mode, '
      'triggered_rules, score_short, score_long, status) '
      "VALUES (?, ?, 100, 'short', '[]', 0, 0, ?)",
      [symbol, tp(pinnedDay), status],
    );

    Future<int> run() => db.deleteExpiredDailyPrices(
      cutoffDay: '2026-01-01',
      limit: 100,
    );

    test('ACTIVE 論點：pinnedDate 起的價格保留、之前照刪', () async {
      await thesis('2330', '2025-06-01', 'ACTIVE');
      for (final d in ['2025-05-31', '2025-06-01', '2025-06-02', '2026-02-01']) {
        await price('2330', tp(d));
      }
      await run();
      expect(
        await days('daily_price', '2330'),
        ['2025-06-01', '2025-06-02', '2026-02-01'],
      );
    });

    test('INVALIDATED 論點不受保護', () async {
      await thesis('2317', '2025-06-01', 'INVALIDATED');
      for (final d in ['2025-06-02', '2026-02-01']) {
        await price('2317', tp(d));
      }
      await run();
      expect(await days('daily_price', '2317'), ['2026-02-01']);
    });

    test('事件當天價格保留，同檔前後日照刪', () async {
      await exec(
        'INSERT INTO stock_event(symbol, event_type, event_date, title) '
        "VALUES ('2330', 'EARNINGS', ?, '法說會')",
        [tp('2025-03-10')],
      );
      for (final d in ['2025-03-09', '2025-03-10', '2025-03-11', '2026-02-01']) {
        await price('2330', tp(d));
      }
      await run();
      expect(await days('daily_price', '2330'), ['2025-03-10', '2026-02-01']);
    });

    test('每檔最新一筆保留', () async {
      await price('9999', tp('2025-01-01'));
      await run();
      expect(await days('daily_price', '9999'), ['2025-01-01']);
    });
  });

  test('deleteBeyondLatestPeriods：每檔各自最新 N 期（停更股保留自己的最新期）', () async {
    Future<void> holding(String symbol, String day) async {
      for (final level in ['1', '2']) {
        await exec(
          'INSERT INTO holding_distribution(symbol, date, level) VALUES (?, ?, ?)',
          [symbol, tp(day), level],
        );
      }
    }

    for (final d in ['2026-08-01', '2026-08-08', '2026-08-15', '2026-08-22']) {
      await holding('2330', d);
    }
    await holding('9999', '2026-07-01');
    await holding('9999', '2026-07-08');

    await db.deleteBeyondLatestPeriods('holding_distribution', periods: 2, limit: 100);

    expect(
      await days('holding_distribution', '2330'),
      ['2026-08-15', '2026-08-15', '2026-08-22', '2026-08-22'],
    );
    expect(
      await days('holding_distribution', '9999'),
      ['2026-07-01', '2026-07-01', '2026-07-08', '2026-07-08'],
    );
  });

  group('financial_data', () {
    Future<void> fin(String symbol, String day, String statement, String type) =>
        exec(
          'INSERT INTO financial_data(symbol, date, statement_type, data_type, value) '
          'VALUES (?, ?, ?, ?, 1)',
          [symbol, tp(day), statement, type],
        );

    Future<Set<String>> types(String symbol, String statement) async {
      final rows = await db
          .customSelect(
            'SELECT data_type FROM financial_data '
            "WHERE symbol = '$symbol' AND statement_type = '$statement'",
          )
          .get();
      return rows.map((r) => r.read<String>('data_type')).toSet();
    }

    test('deleteDisallowedFinancialTypes：有允許項目的組刪非允許項目，沒有的組整組保留', () async {
      await fin('2330', '2026-06-30', 'INCOME', 'EPS');
      await fin('2330', '2026-06-30', 'INCOME', 'CostOfGoodsSold');
      await fin('2330', '2026-06-30', 'BALANCE', 'OtherAssets');
      await fin('2801', '2026-06-30', 'INCOME', 'IncomeAfterTax');

      await db.deleteDisallowedFinancialTypes(limit: 100);

      expect(await types('2330', 'INCOME'), {'EPS'});
      expect(await types('2330', 'BALANCE'), {'OtherAssets'});
      expect(await types('2801', 'INCOME'), {'IncomeAfterTax'});
    });

    test('deleteFinancialQuartersBeyond：每檔每種報表各自保留最新 N 季', () async {
      // 2330 INCOME 16 季、2317 INCOME 只有 3 季（最新季較舊）
      final quarters = [
        for (var y = 2022; y <= 2025; y++)
          for (final md in ['03-31', '06-30', '09-30', '12-31']) '$y-$md',
      ];
      for (final q in quarters) {
        await fin('2330', q, 'INCOME', 'EPS');
      }
      for (final q in quarters.take(3)) {
        await fin('2317', q, 'INCOME', 'EPS');
      }
      await fin('2330', quarters.first, 'BALANCE', 'Equity');

      await db.deleteFinancialQuartersBeyond(quarters: 14, limit: 100);

      final kept2330 = await days('financial_data', '2330');
      // INCOME 保留最新 14 季（刪最舊 2 季）＋BALANCE 1 季自成一組不受影響
      expect(kept2330.where((d) => d == '2022-03-31').length, 1); // 只剩 BALANCE
      expect(kept2330.contains('2022-06-30'), isFalse);
      expect(kept2330.length, 15);
      expect((await days('financial_data', '2317')).length, 3);
    });
  });

  test('deleteInactiveTradingWarnings：只刪已失效且超過期限', () async {
    Future<void> warning(String day, String type, int active) => exec(
      'INSERT INTO trading_warning(symbol, date, warning_type, is_active) '
      'VALUES (?, ?, ?, ?)',
      ['2330', tp(day), type, active],
    );
    await warning('2025-01-01', 'DISPOSAL', 0);
    await warning('2025-01-01', 'ATTENTION', 1);
    await warning('2026-02-01', 'DISPOSAL', 0);

    await db.deleteInactiveTradingWarnings(cutoffDay: '2026-01-01', limit: 100);

    final rows = await db
        .customSelect(
          "SELECT date(date, '+8 hours') AS d, warning_type AS t FROM trading_warning "
          'ORDER BY d, t',
        )
        .get();
    expect(
      rows.map((r) => '${r.read<String>('d')} ${r.read<String>('t')}'),
      ['2025-01-01 ATTENTION', '2026-02-01 DISPOSAL'],
    );
  });

  test('trimUpdateRuns：保留最新 N 筆', () async {
    for (var i = 0; i < 205; i++) {
      await exec(
        "INSERT INTO update_run(run_date, status) VALUES (?, 'SUCCESS')",
        [tp('2026-01-01')],
      );
    }
    expect(await db.trimUpdateRuns(keep: 200), 5);
    final minId = await db
        .customSelect('SELECT MIN(id) AS m, COUNT(*) AS c FROM update_run')
        .getSingle();
    expect(minId.read<int>('c'), 200);
    expect(minId.read<int>('m'), 6);
  });

  test('空間回收查詢在記憶體 DB 上可執行', () async {
    expect(await db.autoVacuumMode(), 0);
    expect(await db.freelistCount(), greaterThanOrEqualTo(0));
    await db.incrementalVacuum(10);
    expect(await db.checkpointTruncate(), isTrue);
  });
}
```

```dart
// test/data/database/dao/financial_retention_equivalence_test.dart
// 財報規則的兩個實作（寫入過濾 Dart、事後清理 SQL）必須得到同一個結果：
// 「精簡模式從頭寫入」＝「全寫後跑事後清理」。
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/constants/data_retention_policy.dart';
import 'package:daredevil/data/database/app_database.dart';

void main() {
  final q1 = DateTime(2026, 3, 31);
  final q2 = DateTime(2026, 6, 30);

  final entries = [
    for (final (symbol, date, statement, type) in [
      ('2330', q2, 'INCOME', 'EPS'),
      ('2330', q2, 'INCOME', 'CostOfGoodsSold'),
      ('2330', q2, 'BALANCE', 'Equity'),
      ('2330', q2, 'BALANCE', 'OtherAssets'),
      ('2330', q1, 'BALANCE', 'OtherAssets'),
      ('2801', q2, 'INCOME', 'IncomeAfterTax'),
      ('2801', q2, 'INCOME', 'NetInterestIncome'),
      ('2801', q1, 'INCOME', 'EPS'),
      ('2801', q1, 'INCOME', 'IncomeAfterTax'),
    ])
      FinancialDataCompanion.insert(
        symbol: symbol,
        date: date,
        statementType: statement,
        dataType: type,
        value: const Value(1.0),
      ),
  ];

  Future<Set<String>> snapshot(AppDatabase db) async {
    final rows = await db
        .customSelect(
          "SELECT symbol || '|' || date || '|' || statement_type || '|' || data_type AS k "
          'FROM financial_data',
        )
        .get();
    return rows.map((r) => r.read<String>('k')).toSet();
  }

  Future<AppDatabase> freshDb() async {
    final db = AppDatabase.forTesting();
    await db.upsertStocks([
      StockMasterCompanion.insert(symbol: '2330', name: '台積電', market: 'TWSE'),
      StockMasterCompanion.insert(symbol: '2801', name: '彰銀', market: 'TWSE'),
    ]);
    return db;
  }

  test('精簡寫入過濾＝全寫＋事後清理', () async {
    final filtered = await freshDb();
    final cleaned = await freshDb();
    addTearDown(filtered.close);
    addTearDown(cleaned.close);

    await filtered.insertFinancialData(entries, mode: RetentionMode.lean);
    await cleaned.insertFinancialData(entries, mode: RetentionMode.research);
    while (await cleaned.deleteDisallowedFinancialTypes(limit: 2) > 0) {}

    final expected = await snapshot(filtered);
    expect(expected.length, lessThan(entries.length)); // 確實有濾掉東西
    expect(await snapshot(cleaned), expected);
  });
}
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `flutter test test/data/database/dao/retention_dao_test.dart test/data/database/dao/financial_retention_equivalence_test.dart`
Expected: 編譯失敗，`deleteExpiredRows` 等方法不存在

- [ ] **Step 3: 實作 mixin**

```dart
// lib/data/database/dao/retention_dao.dart
import 'package:drift/drift.dart';

import 'package:daredevil/core/constants/data_retention_policy.dart';
import 'package:daredevil/data/database/app_database.drift.dart';

/// 資料保留期的刪除 SQL（政策：[DataRetentionPolicy]）。
///
/// 每個方法一次最多刪 `limit` 列；單一 statement 自成交易，大量刪除不會
/// 長時間握寫鎖。回傳實際刪除筆數，呼叫端以「回傳 < limit」判斷已清完。
///
/// 日期一律比台北日曆日：`date(欄位, '+8 hours')` 先依字尾轉 UTC 再加 8 小時，
/// `' +08:00'`、`Z` 字尾都得到正確台北日（`substr` 對 `Z` 會差一天）。
/// `cutoffDay` 為 `YYYY-MM-DD`，刪 `台北日 < cutoffDay`（邊界當天保留）。
///
/// 「每檔最新一筆」以同檔字串 MAX 判斷：同一張表的日期字串格式一致。
mixin RetentionDaoMixin on $AppDatabase {
  static final _identifier = RegExp(r'^[a-z_]+$');

  TableInfo<Table, Object?> _tableNamed(String name) {
    if (!_identifier.hasMatch(name)) {
      throw ArgumentError.value(name, 'name', '非法表名');
    }
    return allTables.firstWhere((t) => t.actualTableName == name);
  }

  Future<int> _delete(String table, String sql, List<Variable> variables) {
    final info = _tableNamed(table); // 先驗表名，再執行組好的 SQL
    return customUpdate(
      sql,
      variables: variables,
      updates: {info},
      updateKind: UpdateKind.delete,
    );
  }

  /// 天數型表。[keepLatestPerSymbol]：每檔最新一筆一律保留
  Future<int> deleteExpiredRows(
    String table, {
    required String cutoffDay,
    required bool keepLatestPerSymbol,
    required int limit,
  }) {
    _tableNamed(table);
    final latestGuard = keepLatestPerSymbol
        ? 'AND p.date < (SELECT MAX(q.date) FROM $table q WHERE q.symbol = p.symbol)'
        : '';
    return _delete(table, '''
      DELETE FROM $table WHERE rowid IN (
        SELECT p.rowid FROM $table p
        WHERE date(p.date, '+8 hours') < ? $latestGuard
        LIMIT ?)''', [Variable.withString(cutoffDay), Variable.withInt(limit)]);
  }

  /// daily_price：天數＋每檔最新一筆＋ACTIVE 論點 pinnedDate 起＋事件當天
  Future<int> deleteExpiredDailyPrices({
    required String cutoffDay,
    required int limit,
  }) => _delete('daily_price', '''
      DELETE FROM daily_price WHERE rowid IN (
        SELECT p.rowid FROM daily_price p
        WHERE date(p.date, '+8 hours') < ?
          AND p.date < (SELECT MAX(q.date) FROM daily_price q WHERE q.symbol = p.symbol)
          AND NOT EXISTS (
            SELECT 1 FROM pinned_thesis t
            WHERE t.symbol = p.symbol AND t.status = 'ACTIVE'
              AND date(p.date, '+8 hours') >= date(t.pinned_date, '+8 hours'))
          AND NOT EXISTS (
            SELECT 1 FROM stock_event e
            WHERE e.symbol = p.symbol
              AND date(e.event_date, '+8 hours') = date(p.date, '+8 hours'))
        LIMIT ?)''', [Variable.withString(cutoffDay), Variable.withInt(limit)]);

  /// 每檔各自保留最新 [periods] 期
  Future<int> deleteBeyondLatestPeriods(
    String table, {
    required int periods,
    required int limit,
  }) {
    _tableNamed(table);
    return _delete(table, '''
      WITH keep AS (
        SELECT symbol, date FROM (
          SELECT symbol, date,
                 ROW_NUMBER() OVER (PARTITION BY symbol ORDER BY date DESC) AS rn
          FROM (SELECT DISTINCT symbol, date FROM $table))
        WHERE rn <= ?)
      DELETE FROM $table WHERE rowid IN (
        SELECT h.rowid FROM $table h
        WHERE NOT EXISTS (
          SELECT 1 FROM keep k WHERE k.symbol = h.symbol AND k.date = h.date)
        LIMIT ?)''', [Variable.withInt(periods), Variable.withInt(limit)]);
  }

  /// 財報事後清理：組內有允許項目 → 刪非允許項目；沒有 → 整組保留。
  /// 與寫入過濾 `filterFinancialEntriesForLean` 同一規則
  /// （`financial_retention_equivalence_test` 綁住）
  Future<int> deleteDisallowedFinancialTypes({required int limit}) {
    final allowed = DataRetentionPolicy.financialAllowedTypes.toList();
    final placeholders = List.filled(allowed.length, '?').join(', ');
    return _delete('financial_data', '''
      DELETE FROM financial_data WHERE rowid IN (
        SELECT f.rowid FROM financial_data f
        WHERE f.data_type NOT IN ($placeholders)
          AND EXISTS (
            SELECT 1 FROM financial_data g
            WHERE g.symbol = f.symbol AND g.date = f.date
              AND g.statement_type = f.statement_type
              AND g.data_type IN ($placeholders))
        LIMIT ?)''', [
      for (final t in allowed) Variable.withString(t),
      for (final t in allowed) Variable.withString(t),
      Variable.withInt(limit),
    ]);
  }

  /// 每檔、每種報表保留自己最新的 [quarters] 季
  Future<int> deleteFinancialQuartersBeyond({
    required int quarters,
    required int limit,
  }) => _delete('financial_data', '''
      WITH ranked AS (
        SELECT symbol, statement_type, date,
               ROW_NUMBER() OVER (
                 PARTITION BY symbol, statement_type ORDER BY date DESC) AS rn
        FROM (SELECT DISTINCT symbol, statement_type, date FROM financial_data))
      DELETE FROM financial_data WHERE rowid IN (
        SELECT f.rowid FROM financial_data f
        JOIN ranked r ON r.symbol = f.symbol
          AND r.statement_type = f.statement_type AND r.date = f.date
        WHERE r.rn > ?
        LIMIT ?)''', [Variable.withInt(quarters), Variable.withInt(limit)]);

  /// 刪「已失效且早於 cutoffDay」的警示；仍生效的舊列保留
  Future<int> deleteInactiveTradingWarnings({
    required String cutoffDay,
    required int limit,
  }) => _delete('trading_warning', '''
      DELETE FROM trading_warning WHERE rowid IN (
        SELECT rowid FROM trading_warning
        WHERE is_active = 0 AND date(date, '+8 hours') < ?
        LIMIT ?)''', [Variable.withString(cutoffDay), Variable.withInt(limit)]);

  /// 保留最新 [keep] 筆（本輪進行中的那筆是最新的，不會被刪）
  Future<int> trimUpdateRuns({required int keep}) => _delete(
    'update_run',
    'DELETE FROM update_run WHERE id NOT IN '
        '(SELECT id FROM update_run ORDER BY id DESC LIMIT ?)',
    [Variable.withInt(keep)],
  );

  /// 0 = NONE、1 = FULL、2 = INCREMENTAL
  Future<int> autoVacuumMode() async =>
      (await customSelect('PRAGMA auto_vacuum').getSingle()).read<int>('auto_vacuum');

  Future<int> freelistCount() async =>
      (await customSelect('PRAGMA freelist_count').getSingle())
          .read<int>('freelist_count');

  /// 只在 INCREMENTAL 模式有作用
  Future<void> incrementalVacuum(int pages) =>
      customStatement('PRAGMA incremental_vacuum($pages)');

  /// true＝完成；false＝有讀者佔用（BUSY），下輪再做。WAL 模式下不
  /// checkpoint，incremental_vacuum 後主檔不會變小
  Future<bool> checkpointTruncate() async {
    final row = await customSelect('PRAGMA wal_checkpoint(TRUNCATE)').getSingle();
    return row.read<int>('busy') == 0;
  }
}
```

`app_database.dart`：DAO import 區加 `import 'package:daredevil/data/database/dao/retention_dao.dart';`，`class AppDatabase extends $AppDatabase with …` 清單最後加 `RetentionDaoMixin`。

- [ ] **Step 4: 跑測試確認通過**

Run: `flutter test test/data/database/dao/retention_dao_test.dart test/data/database/dao/financial_retention_equivalence_test.dart`
Expected: 全過

- [ ] **Step 5: Mutation 驗收**

1. `deleteExpiredRows` 的 `date(p.date, '+8 hours')` 改 `substr(p.date, 1, 10)` → 預期「Z 字尾」紅
2. 拿掉 `latestGuard`（永遠空字串）→ 預期「keepLatestPerSymbol：保留最新一筆」紅
3. `deleteExpiredDailyPrices` 拿掉 pinned_thesis 的 `NOT EXISTS` → 預期「ACTIVE 論點」紅
4. 把 `t.status = 'ACTIVE'` 拿掉 → 預期「INVALIDATED 不受保護」紅
5. 拿掉 stock_event 的 `NOT EXISTS` → 預期「事件當天」紅
6. `deleteBeyondLatestPeriods` 的 `PARTITION BY symbol` 拿掉（變全市場排序）→ 預期「停更股」紅
7. `deleteDisallowedFinancialTypes` 拿掉 `AND EXISTS (…)` → 預期「整組保留」與等價測試紅
8. `deleteFinancialQuartersBeyond` 的 PARTITION 拿掉 `statement_type` → 預期「每種報表各自」紅
9. `deleteInactiveTradingWarnings` 拿掉 `is_active = 0` → 預期紅
10. `_identifier` 改成 `RegExp(r'.*')` → 預期「非法表名」紅

Expected: 十個都紅；還原後全綠

- [ ] **Step 6: 送審，等 user「提交」**

```bash
git add lib/data/database/dao/retention_dao.dart lib/data/database/app_database.dart test/data/database/dao/retention_dao_test.dart test/data/database/dao/financial_retention_equivalence_test.dart
git commit -m "feat: 資料保留期刪除 SQL（分批、台北日、最新一筆／論點／事件例外）"
```

---

### Task 5: `DataRetentionService`

**Files:**
- Create: `lib/domain/services/data_retention_service.dart`
- Test: `test/domain/services/data_retention_service_test.dart`

**Interfaces:**
- Consumes: Task 2 的政策；Task 4 的 `RetentionDaoMixin` 方法；Task 1 的 `configureDatabaseConnection`（測試用）
- Produces:
  - `class RetentionReport { const RetentionReport({required Map<String, int> deletedByTable, required bool completed}); int get totalDeleted; }`
  - `DataRetentionService({required AppDatabase database, required RetentionMode mode, AppClock clock = const SystemClock(), Duration timeBudget = DataRetentionPolicy.timeBudget, int batchSize = DataRetentionPolicy.deleteBatchSize, Duration Function()? elapsed})`
  - `Future<RetentionReport> run()`

- [ ] **Step 1: 寫失敗測試**

```dart
// test/domain/services/data_retention_service_test.dart
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/constants/data_retention_policy.dart';
import 'package:daredevil/core/utils/clock.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/data/database/connection_setup.dart';
import 'package:daredevil/domain/services/data_retention_service.dart';
import 'package:daredevil/domain/services/thesis/thesis_monitor_service.dart';

class _FixedClock implements AppClock {
  const _FixedClock(this._now);
  final DateTime _now;

  @override
  DateTime now() => _now;
}

void main() {
  late AppDatabase db;
  final now = DateTime(2026, 9, 26, 15);
  final clock = _FixedClock(now);

  Future<int> count(String table) async => (await db
          .customSelect('SELECT COUNT(*) AS c FROM $table')
          .getSingle())
      .read<int>('c');

  Future<void> prices(String symbol, List<(DateTime, double)> rows) =>
      db.insertPrices([
        for (final (date, close) in rows)
          DailyPriceCompanion.insert(
            symbol: symbol,
            date: date,
            close: Value(close),
          ),
      ]);

  /// 各表各一筆過期列＋一筆新列；update_run 205 筆；一筆已失效的舊警示
  Future<void> seedAll() async {
    final old = DateTime(2024, 1, 2);
    final fresh = DateTime(2026, 9, 25);
    await prices('2330', [(old, 1.0), (fresh, 1.0)]);
    for (final table in [
      'daily_institutional',
      'margin_trading',
      'day_trading',
      'shareholding',
      'stock_valuation',
      'insider_holding',
    ]) {
      for (final d in [old, fresh]) {
        await db.customStatement(
          'INSERT INTO $table(symbol, date) VALUES (?, ?)',
          ['2330', d.toIso8601String()],
        );
      }
    }
    for (var i = 0; i < 205; i++) {
      await db.customStatement(
        "INSERT INTO update_run(run_date, status) VALUES ('2026-01-01', 'SUCCESS')",
      );
    }
    await db.customStatement(
      'INSERT INTO trading_warning(symbol, date, warning_type, is_active) '
      "VALUES ('2330', ?, 'DISPOSAL', 0)",
      [old.toIso8601String()],
    );
  }

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.upsertStocks([
      StockMasterCompanion.insert(symbol: '2330', name: '台積電', market: 'TWSE'),
    ]);
  });

  tearDown(() => db.close());

  DataRetentionService service(
    RetentionMode mode, {
    Duration timeBudget = const Duration(minutes: 1),
    int batchSize = 5000,
    Duration Function()? elapsed,
  }) => DataRetentionService(
    database: db,
    mode: mode,
    clock: clock,
    timeBudget: timeBudget,
    batchSize: batchSize,
    elapsed: elapsed,
  );

  test('精簡模式：各表過期列刪除（最新一筆保留）、回報刪除筆數', () async {
    await seedAll();
    final report = await service(RetentionMode.lean).run();

    expect(report.completed, isTrue);
    expect(await count('daily_price'), 1);
    expect(await count('margin_trading'), 1);
    expect(await count('update_run'), 200);
    expect(await count('trading_warning'), 0);
    expect(report.deletedByTable['daily_price'], 1);
    expect(report.deletedByTable['update_run'], 5);
    expect(report.totalDeleted, greaterThanOrEqualTo(9));
  });

  test('研究模式只修剪 update_run 與已失效警示，時間序列不動', () async {
    await seedAll();
    final report = await service(RetentionMode.research).run();

    expect(report.completed, isTrue);
    expect(await count('daily_price'), 2);
    expect(await count('margin_trading'), 2);
    expect(await count('insider_holding'), 2);
    expect(await count('update_run'), 200);
    expect(await count('trading_warning'), 0);
    expect(report.deletedByTable.keys.toSet(), {'update_run', 'trading_warning'});
  });

  test('空 DB 上兩種模式都跑得完（每個 CustomRule 都有實作）', () async {
    for (final mode in RetentionMode.values) {
      final report = await service(mode).run();
      expect(report.completed, isTrue, reason: mode.name);
      expect(report.totalDeleted, 0, reason: mode.name);
    }
  });

  test('預算一開始就用完：不刪任何列、回報未完成；下一輪清完', () async {
    await seedAll();
    final first = await service(
      RetentionMode.lean,
      timeBudget: Duration.zero,
    ).run();
    expect(first.completed, isFalse);
    expect(first.totalDeleted, 0);

    final second = await service(RetentionMode.lean).run();
    expect(second.completed, isTrue);
    expect(await count('update_run'), 200);
  });

  test('預算中途用完：停在批次邊界、回報未完成，下一輪接續', () async {
    await prices('2330', [
      for (var i = 0; i < 10; i++) (DateTime(2024, 1, 2 + i), 1.0),
      (DateTime(2026, 9, 25), 1.0),
    ]);
    // 每次預算檢查前進 1ms：財報兩步、股權分散一步各耗一次檢查（0、1、2），
    // daily_price 在 3、4 各刪一批（2 筆），第 5 次檢查時預算用完
    var ticks = 0;
    final first = await service(
      RetentionMode.lean,
      batchSize: 2,
      timeBudget: const Duration(milliseconds: 5),
      elapsed: () => Duration(milliseconds: ticks++),
    ).run();

    expect(first.completed, isFalse);
    expect(first.totalDeleted, greaterThan(0));
    expect(await count('daily_price'), greaterThan(1));

    final second = await service(RetentionMode.lean, batchSize: 2).run();
    expect(second.completed, isTrue);
    expect(await count('daily_price'), 1);
  });

  test('論點監控在清理後結果不變：早期曾站上參考價的 ACTIVE 論點不被誤判失效', () async {
    final pinned = DateTime(2024, 12, 2);
    await db.pinThesis(
      symbol: '2330',
      pinnedDate: pinned,
      referencePrice: 100,
      mode: 'short',
      triggeredRules: '[]',
      scoreShort: 0,
      scoreLong: 0,
    );
    await prices('2330', [
      (pinned, 100),
      (DateTime(2024, 12, 3), 110), // 曾站上參考價 → timeStop 永不觸發
      for (var i = 0; i < 45; i++) (DateTime(2024, 12, 4 + i), 90.0),
      for (var i = 0; i < 45; i++) (DateTime(2026, 8, 1 + i), 90.0),
    ]);

    await service(RetentionMode.lean).run();
    final invalidated = await ThesisMonitorService(
      database: db,
    ).checkActiveTheses(asOf: now);

    expect(invalidated, 0);
    expect(await db.getActiveTheses(), hasLength(1));
  });

  test('INCREMENTAL 檔案 DB：清理後主檔實際變小', () async {
    await db.close();
    final dir = Directory.systemTemp.createTempSync('retention_file_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/r.sqlite');
    db = AppDatabase(NativeDatabase(file, setup: configureDatabaseConnection));
    await db.upsertStocks([
      StockMasterCompanion.insert(symbol: '2330', name: '台積電', market: 'TWSE'),
    ]);
    await prices('2330', [
      for (var i = 0; i < 2000; i++) // 2020-01 ~ 2025-06，全早於 460 天期限
        (DateTime(2020, 1, 1).add(Duration(days: i)), i.toDouble()),
    ]);
    await db.checkpointTruncate();
    final before = file.lengthSync();

    await service(RetentionMode.lean).run();

    expect(file.lengthSync(), lessThan(before));
  });
}
```

注意：`seedAll` 的日期用 `toIso8601String()`（無時區字尾，SQLite 視為 UTC），台北日與原日期相同；`2024-01-02` 早於所有精簡期限，`2026-09-25` 晚於所有期限。

- [ ] **Step 2: 跑測試確認失敗**

Run: `flutter test test/domain/services/data_retention_service_test.dart`
Expected: 編譯失敗，`data_retention_service.dart` 不存在

- [ ] **Step 3: 實作**

```dart
// lib/domain/services/data_retention_service.dart
import 'package:meta/meta.dart';

import 'package:daredevil/core/constants/data_retention_policy.dart';
import 'package:daredevil/core/utils/clock.dart';
import 'package:daredevil/core/utils/date_context.dart';
import 'package:daredevil/core/utils/logger.dart';
import 'package:daredevil/data/database/app_database.dart';

/// 一輪清理的結果
class RetentionReport {
  const RetentionReport({required this.deletedByTable, required this.completed});

  /// 有刪除的表才出現
  final Map<String, int> deletedByTable;

  /// false＝時間預算用完、還有過期資料沒刪（下一輪接續）
  final bool completed;

  int get totalDeleted => deletedByTable.values.fold(0, (a, b) => a + b);
}

/// 依 [DataRetentionPolicy] 清理過期資料並回收空間。
///
/// - 分批：每批最多 [batchSize] 列、單一 statement 自成交易
/// - 時間預算：每批前檢查，用完即停並回報未完成；清理冪等，下一輪接續。
///   手機第一次清理量大（Mac 實測不分批約 5 秒），背景任務時間很短
/// - 空間回收：只在 `auto_vacuum = INCREMENTAL` 時 `incremental_vacuum`，
///   同一預算內分步做；最後一律 `wal_checkpoint(TRUNCATE)`（BUSY 下輪再做）
class DataRetentionService {
  DataRetentionService({
    required AppDatabase database,
    required RetentionMode mode,
    AppClock clock = const SystemClock(),
    Duration timeBudget = DataRetentionPolicy.timeBudget,
    int batchSize = DataRetentionPolicy.deleteBatchSize,
    @visibleForTesting Duration Function()? elapsed,
  }) : _db = database,
       _mode = mode,
       _clock = clock,
       _timeBudget = timeBudget,
       _batchSize = batchSize,
       _elapsedOverride = elapsed;

  final AppDatabase _db;
  final RetentionMode _mode;
  final AppClock _clock;
  final Duration _timeBudget;
  final int _batchSize;
  final Duration Function()? _elapsedOverride;

  Future<RetentionReport> run() async {
    final stopwatch = Stopwatch()..start();
    final elapsed = _elapsedOverride ?? () => stopwatch.elapsed;
    bool budgetLeft() => elapsed() < _timeBudget;

    final deleted = <String, int>{};
    var completed = true;

    tables:
    for (final MapEntry(key: table, value: retention)
        in DataRetentionPolicy.tables.entries) {
      for (final step in _stepsFor(table, retention.forMode(_mode))) {
        while (true) {
          if (!budgetLeft()) {
            completed = false;
            break tables;
          }
          final n = await step();
          if (n > 0) deleted[table] = (deleted[table] ?? 0) + n;
          if (n < _batchSize) break;
        }
      }
    }

    await _reclaimSpace(budgetLeft);

    final report = RetentionReport(deletedByTable: deleted, completed: completed);
    AppLogger.info(
      'DataRetention',
      '${_mode.name}：刪除 ${report.totalDeleted} 筆'
          '${completed ? '' : '（預算用完，下輪繼續）'} $deleted',
    );
    return report;
  }

  List<Future<int> Function()> _stepsFor(String table, RetentionRule rule) =>
      switch (rule) {
        KeepAll() || ExternallyManaged() => const [],
        KeepDays(:final days, :final keepLatestPerSymbol) => [
          () => _db.deleteExpiredRows(
            table,
            cutoffDay: _cutoffDay(days),
            keepLatestPerSymbol: keepLatestPerSymbol,
            limit: _batchSize,
          ),
        ],
        LatestPeriodsPerSymbol(:final periods) => [
          () => _db.deleteBeyondLatestPeriods(
            table,
            periods: periods,
            limit: _batchSize,
          ),
        ],
        CustomRule() => _customSteps(table),
      };

  List<Future<int> Function()> _customSteps(String table) => switch (table) {
    'financial_data' => [
      () => _db.deleteDisallowedFinancialTypes(limit: _batchSize),
      () => _db.deleteFinancialQuartersBeyond(
        quarters: DataRetentionPolicy.financialQuarters,
        limit: _batchSize,
      ),
    ],
    'daily_price' => [
      () => _db.deleteExpiredDailyPrices(
        cutoffDay: _cutoffDay(DataRetentionPolicy.dailyPriceDays),
        limit: _batchSize,
      ),
    ],
    'trading_warning' => [
      () => _db.deleteInactiveTradingWarnings(
        cutoffDay: _cutoffDay(DataRetentionPolicy.tradingWarningInactiveDays),
        limit: _batchSize,
      ),
    ],
    'update_run' => [
      () => _db.trimUpdateRuns(keep: DataRetentionPolicy.updateRunKeep),
    ],
    _ => throw StateError('CustomRule 沒有實作：$table'),
  };

  /// 台北日曆日「今天 − days」（clock 回傳台北牆鐘時間）
  String _cutoffDay(int days) {
    final now = _clock.now();
    return DateContext.formatYmd(DateTime(now.year, now.month, now.day - days));
  }

  Future<void> _reclaimSpace(bool Function() budgetLeft) async {
    // auto_vacuum=0 的既有 DB：incremental_vacuum 不動作、freelist 不會降，
    // 不先判斷會一路空轉到預算用完
    if (await _db.autoVacuumMode() == 2) {
      var free = await _db.freelistCount();
      while (free > 0 && budgetLeft()) {
        await _db.incrementalVacuum(DataRetentionPolicy.vacuumPagesPerStep);
        final after = await _db.freelistCount();
        if (after >= free) break; // 沒有進展就停，不空轉
        free = after;
      }
    }
    if (!await _db.checkpointTruncate()) {
      AppLogger.info('DataRetention', 'WAL checkpoint 遇讀者佔用，下輪再做');
    }
  }
}
```

- [ ] **Step 4: 跑測試確認通過**

Run: `flutter test test/domain/services/data_retention_service_test.dart`
Expected: 7 個測試全過

- [ ] **Step 5: Mutation 驗收**

1. `if (!budgetLeft())` 整段拿掉 → 預期兩個預算測試紅
2. `if (n < _batchSize) break;` 改成永遠 `break`（每步只跑一批）→ 預期「預算中途用完」第二輪清不完而紅
3. `_customSteps` 拿掉 `'daily_price'` 分支 → 預期「空 DB 上兩種模式都跑得完」紅（StateError）
4. `_reclaimSpace` 拿掉 `autoVacuumMode() == 2` 判斷改為 `true` 並拿掉「沒有進展就停」→ 預期精簡模式測試逾時（記憶體 DB 為 0）
5. 拿掉 `checkpointTruncate()` 呼叫 → 預期「主檔實際變小」紅
6. Task 4 的 pinned_thesis `NOT EXISTS` 再拿一次 → 預期「論點監控在清理後結果不變」紅

Expected: 六個都紅；還原後全綠

- [ ] **Step 6: 送審，等 user「提交」**

```bash
git add lib/domain/services/data_retention_service.dart test/domain/services/data_retention_service_test.dart
git commit -m "feat: DataRetentionService 依政策分批清理並回收空間"
```

---

### Task 6: 接上 `UpdateService`

**Files:**
- Modify: `lib/domain/services/update_service.dart`（建構子約 44-60 行、步驟 10+ 約 359-366 行、新增 `_applyDataRetentionFailSafe`、`UpdateResult` 約 1329-1374 行）
- Modify: `lib/domain/services/update_service_factory.dart`
- Modify: `lib/domain/services/rule_accuracy_service.dart`（約 460-461 行註解）
- Modify: `.claude/rules/update-pipeline.md`（Post-Update 段落與 Mermaid 節點）
- Modify: `CLAUDE.md`（關鍵路徑表加一列）
- Test: `test/domain/services/update_service_test.dart`

**Interfaces:**
- Consumes: Task 5 的 `DataRetentionService`、`RetentionReport`；Task 3 在 factory 建立的 `retentionMode` 變數
- Produces: `UpdateService({…, required DataRetentionService dataRetention})`；`UpdateResult.retentionDeleted`（int）、`UpdateResult.retentionIncomplete`（bool）

- [ ] **Step 1: 寫失敗測試**

`update_service_test.dart` 檔頭 import `data_retention_service.dart`，加替身：

```dart
class _FakeRetention implements DataRetentionService {
  RetentionReport report = const RetentionReport(deletedByTable: {}, completed: true);
  Object? error;
  int calls = 0;

  @override
  Future<RetentionReport> run() async {
    calls++;
    if (error != null) throw error!;
    return report;
  }
}
```

`main()` 內加 `late _FakeRetention retention;`，`setUp` 裡 `retention = _FakeRetention();`，`buildService` 的 `UpdateService(` 加 `dataRetention: retention,`。新增 group。下列測試假設 `buildService().runDailyUpdate(forDate: …)` 會走到步驟 10+；若預設 stub 走不到（例如被判非交易日提早結束），照抄檔內「全數成功時 message 維持「更新完成」」測試的 arrange 段：

```dart
  group('資料保留期清理（步驟 10+ 最後一步）', () {
    test('成功更新後執行一次，刪除筆數附在摘要', () async {
      retention.report = const RetentionReport(
        deletedByTable: {'daily_price': 12, 'update_run': 3},
        completed: true,
      );
      final result = await buildService().runDailyUpdate(
        forDate: DateTime(2026, 7, 28),
      );

      expect(retention.calls, 1);
      expect(result.retentionDeleted, 15);
      expect(result.summary, contains('清理 15 筆'));
    });

    test('未做完時摘要標示下輪繼續', () async {
      retention.report = const RetentionReport(
        deletedByTable: {'financial_data': 5000},
        completed: false,
      );
      final result = await buildService().runDailyUpdate(
        forDate: DateTime(2026, 7, 28),
      );

      expect(result.retentionIncomplete, isTrue);
      expect(result.summary, contains('未完成'));
    });

    test('清理拋錯不中斷更新，但記入 errors', () async {
      retention.error = StateError('disk I/O');
      final result = await buildService().runDailyUpdate(
        forDate: DateTime(2026, 7, 28),
      );

      expect(result.success, isTrue);
      expect(result.errors, contains(startsWith('資料保留期清理失敗')));
    });

    test('沒有刪除時摘要不變', () async {
      final result = await buildService().runDailyUpdate(
        forDate: DateTime(2026, 7, 28),
      );
      expect(result.summary, isNot(contains('清理')));
    });
  });
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `flutter test test/domain/services/update_service_test.dart`
Expected: 編譯失敗，`UpdateService` 沒有 `dataRetention` 參數

- [ ] **Step 3: 實作**

`update_service.dart`：
- 建構子加 `required DataRetentionService dataRetention,`，初始化列 `_dataRetentionService = dataRetention,`，欄位 `final DataRetentionService _dataRetentionService;`
- 步驟 10+ 在 `await _refreshTrailingAlertsFailSafe(ctx);` 之後、`await _finishUpdate(ctx, result);` 之前加 `await _applyDataRetentionFailSafe(ctx);`
- 在 `_refreshTrailingAlertsFailSafe` 之後新增：

```dart
  /// 資料保留期清理（精簡模式刪過期資料；研究模式只修剪 update_run 與
  /// 已失效警示）。**fail-safe**：失敗只 log、不影響 update result（與
  /// [_updateRuleAccuracyStatsFailSafe] 同模式）。
  ///
  /// 放在 fail-safe 最後、`_finishUpdate` 之前：錯誤才反映在 update_run 狀態。
  /// 必填注入而非可選：可選的 fail-safe service 為 null 時整段靜默跳過，
  /// 本專案有「自動更新靜默斷 13 天」的前科。
  Future<void> _applyDataRetentionFailSafe(_UpdateContext ctx) async {
    try {
      final report = await _dataRetentionService.run();
      ctx.result
        ..retentionDeleted = report.totalDeleted
        ..retentionIncomplete = !report.completed;
      AppLogger.info(
        'UpdateService',
        '步驟 10+: 資料保留期清理完成（刪除 ${report.totalDeleted} 筆'
            '${report.completed ? '' : '，未完成、下輪繼續'}）',
      );
    } catch (e, stack) {
      AppLogger.error('UpdateService', '資料保留期清理失敗（fail-safe）', e, stack);
      ctx.result.recordError('資料保留期清理失敗: $e', e);
    }
  }
```

- `UpdateResult` 加欄位與摘要：

```dart
  /// 本輪資料保留期清理刪除的筆數
  int retentionDeleted = 0;

  /// 清理因時間預算未做完（下輪繼續）
  bool retentionIncomplete = false;

  String get summary {
    if (skipped) return message ?? '跳過更新';
    if (!success) return '更新失敗: ${errors.join(', ')}';
    final base = errors.isNotEmpty
        ? '分析 $stocksAnalyzed 檔（${errors.length} 項警告）'
        : '分析 $stocksAnalyzed 檔';
    return '$base$_retentionSuffix';
  }

  String get _retentionSuffix {
    if (retentionIncomplete) return '，清理 $retentionDeleted 筆（未完成，下輪繼續）';
    if (retentionDeleted > 0) return '，清理 $retentionDeleted 筆';
    return '';
  }
```

`update_service_factory.dart` 的 `UpdateService(` 加：

```dart
      dataRetention: DataRetentionService(
        database: database,
        mode: retentionMode,
        clock: clock,
      ),
```

`rule_accuracy_service.dart` 約 460-461 行：`distinct_dates 上限 = 資料深度 − 持有窗，會隨天數單調成長。` 改為 `distinct_dates 上限 = 資料深度 − 持有窗；精簡模式下訊號歷史只留 365 天，上限固定在約一年，不再單調成長。`

`.claude/rules/update-pipeline.md`：Mermaid 的 Post 節點加 `DataRetention`；標題改「6 個 fail-safe service」；段落末加：

```markdown
**`DataRetentionService`** — 依 `DataRetentionPolicy` 清理過期資料（精簡模式＝手機；
研究模式＝Mac，只修剪 update_run 與已失效警示）。分批、每輪 15 秒預算、用完下輪接續；
最後一步、`_finishUpdate` 之前。**必填注入**（`UpdateService` 建構子），不是可選。
```

`CLAUDE.md` 關鍵路徑表加一列：

```markdown
| `lib/core/constants/data_retention_policy.dart`  | 每表保留規則（精簡＝手機、研究＝Mac；守門測試要求每張表宣告）；刪除 SQL 在 `dao/retention_dao.dart` |
```

- [ ] **Step 4: 跑測試確認通過**

Run: `flutter test test/domain/services/update_service_test.dart test/app/ test/presentation/providers/`
Expected: 全過

- [ ] **Step 5: Mutation 驗收**

1. 拿掉 `await _applyDataRetentionFailSafe(ctx);` → 預期「成功更新後執行一次」紅
2. catch 內拿掉 `recordError` → 預期「清理拋錯」紅
3. `_retentionSuffix` 拿掉 `retentionIncomplete` 分支 → 預期「未做完」紅

Expected: 三個都紅；還原後全綠

- [ ] **Step 6: 送審，等 user「提交」**

```bash
git add lib/domain/services/update_service.dart lib/domain/services/update_service_factory.dart lib/domain/services/rule_accuracy_service.dart .claude/rules/update-pipeline.md CLAUDE.md test/domain/services/update_service_test.dart
git commit -m "feat: 每日更新最後一步執行資料保留期清理，結果附在摘要"
```

---

### Task 7: `tool/vacuum_db.dart`（既有 Mac DB 轉 INCREMENTAL）

**Files:**
- Create: `tool/vacuum_db.dart`
- Test: `test/tool/vacuum_db_test.dart`

**Interfaces:**
- Consumes: 無（純 Dart、`package:sqlite3`）
- Produces:
  - `Set<int> parseLsofPids(String stdout, {required int selfPid})`
  - `bool convertToIncremental(Database db)`（已是 INCREMENTAL 回 false、轉換後回 true）

- [ ] **Step 1: 寫失敗測試**

```dart
// test/tool/vacuum_db_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import '../../tool/vacuum_db.dart';

void main() {
  group('parseLsofPids', () {
    test('排除自己、去重、忽略空行', () {
      expect(parseLsofPids('123\n456\n123\n\n999\n', selfPid: 999), {123, 456});
    });

    test('沒有其他程序 → 空集合', () {
      expect(parseLsofPids('', selfPid: 1), isEmpty);
    });
  });

  group('convertToIncremental', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('vacuum_db_'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('auto_vacuum=0 的 WAL DB 轉成 INCREMENTAL，資料完整', () {
      final path = '${dir.path}/legacy.sqlite';
      final seed = sqlite3.open(path)
        ..execute('PRAGMA journal_mode = WAL')
        ..execute('CREATE TABLE t(x)');
      for (var i = 0; i < 1000; i++) {
        seed.execute('INSERT INTO t VALUES (?)', [i]);
      }
      seed.close();

      final db = sqlite3.open(path);
      expect(convertToIncremental(db), isTrue);
      expect(db.select('PRAGMA auto_vacuum').first.values.first, 2);
      expect(db.select('PRAGMA integrity_check').first.values.first, 'ok');
      expect(db.select('SELECT COUNT(*) FROM t').first.values.first, 1000);
      db.close();
    });

    test('已是 INCREMENTAL → 不動', () {
      final path = '${dir.path}/incr.sqlite';
      sqlite3.open(path)
        ..execute('PRAGMA auto_vacuum = INCREMENTAL')
        ..execute('CREATE TABLE t(x)')
        ..close();

      final db = sqlite3.open(path);
      expect(convertToIncremental(db), isFalse);
      db.close();
    });
  });
}
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `flutter test test/tool/vacuum_db_test.dart`
Expected: 編譯失敗，`tool/vacuum_db.dart` 不存在

- [ ] **Step 3: 實作**

```dart
// tool/vacuum_db.dart
//
// 既有 DB 轉為 auto_vacuum=INCREMENTAL 並完整 VACUUM（一次性）。
// 之後每日更新的清理會自己 incremental_vacuum 回收空間。
//
// 執行前必須停掉 launchd 兩支 CLI 並關閉 App：
//   launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/<兩支 plist>
//   dart run tool/vacuum_db.dart [DB 路徑]
//   ops/launchd/install.sh（重新掛回 launchd）
//
// 完整 VACUUM 需約一倍 DB 大小的暫存空間。
import 'dart:io';

import 'package:meta/meta.dart';
import 'package:sqlite3/sqlite3.dart';

@visibleForTesting
Set<int> parseLsofPids(String stdout, {required int selfPid}) => {
  for (final line in stdout.split('\n'))
    if (int.tryParse(line.trim()) case final pid? when pid != selfPid) pid,
};

/// 已是 INCREMENTAL 回 false；否則轉換並完整 VACUUM 後回 true
@visibleForTesting
bool convertToIncremental(Database db) {
  if (db.select('PRAGMA auto_vacuum').first.values.first == 2) return false;
  db
    ..execute('PRAGMA auto_vacuum = INCREMENTAL')
    ..execute('VACUUM')
    ..execute('PRAGMA wal_checkpoint(TRUNCATE)');
  return true;
}

Future<void> main(List<String> args) async {
  final path = args.isNotEmpty
      ? args.first
      : '${Platform.environment['HOME']}'
            '/Library/Containers/com.neo.afterclose/Data/Documents/afterclose.sqlite';
  if (!File(path).existsSync()) {
    stderr.writeln('[vacuum_db] 找不到 DB：$path');
    exit(2);
  }

  // WAL 模式下閒置連線不持有鎖，BEGIN EXCLUSIVE／locking_mode=EXCLUSIVE
  // 都偵測不到還開著的 App，只能看誰開著檔案
  final lsof = await Process.run('lsof', ['-t', path, '$path-wal', '$path-shm']);
  final others = parseLsofPids('${lsof.stdout}', selfPid: pid);
  if (others.isNotEmpty) {
    stderr.writeln('[vacuum_db] DB 仍被其他程序開著（pid ${others.join(', ')}），'
        '先停 launchd、關 App 再跑');
    exit(3);
  }

  final before = File(path).lengthSync();
  final db = sqlite3.open(path);
  try {
    if (!convertToIncremental(db)) {
      stdout.writeln('[vacuum_db] 已是 INCREMENTAL，不需轉換');
      return;
    }
  } finally {
    db.close();
  }
  final after = File(path).lengthSync();
  stdout.writeln('[vacuum_db] 完成：${before ~/ 1048576} MB → ${after ~/ 1048576} MB');
}
```

- [ ] **Step 4: 跑測試確認通過**

Run: `flutter test test/tool/vacuum_db_test.dart && dart compile kernel tool/vacuum_db.dart -o $TMPDIR/vac.dill`
Expected: 4 個測試全過；純 Dart 編譯成功

- [ ] **Step 5: 在副本上彩排（不碰正式 DB）**

```bash
S=$(mktemp -d)
DB="$HOME/Library/Containers/com.neo.afterclose/Data/Documents/afterclose.sqlite"
rm -f "$S/rehearse.db"*; sqlite3 "file:$DB?immutable=1" "vacuum into '$S/rehearse.db'"
dart run tool/vacuum_db.dart "$S/rehearse.db"
sqlite3 "$S/rehearse.db" "pragma auto_vacuum; pragma integrity_check;"
```

Expected: 印出「完成：… MB → … MB」；`2`、`ok`

- [ ] **Step 6: Mutation 驗收**

1. `parseLsofPids` 拿掉 `when pid != selfPid` → 預期「排除自己」紅
2. `convertToIncremental` 拿掉 `VACUUM` → 預期「轉成 INCREMENTAL」紅（auto_vacuum 仍為 0）

Expected: 兩個都紅；還原後全綠

- [ ] **Step 7: 送審，等 user「提交」**

```bash
git add tool/vacuum_db.dart test/tool/vacuum_db_test.dart
git commit -m "feat: vacuum_db 工具把既有 DB 轉為 incremental auto_vacuum"
```

---

### Task 8: 收尾驗證

**Files:** 無新增（只驗證；發現問題回對應 Task 修）

- [ ] **Step 1: 全套測試與靜態檢查**

Run: `flutter analyze --no-fatal-infos lib/ test/ tool/ && flutter test --exclude-tags golden > $TMPDIR/retention_full.txt 2>&1; tail -5 $TMPDIR/retention_full.txt`
Expected: analyze 無 issue；最後一行 `All tests passed!`

- [ ] **Step 2: CLI 純 Dart 終驗**

Run: `dart compile kernel tool/daily_update.dart -o $TMPDIR/du.dill && dart compile kernel tool/intraday_alert_check.dart -o $TMPDIR/ia.dill`
Expected: 兩支都編譯成功

- [ ] **Step 3: 精簡模式在正式資料副本上的實際效果**

在 Task 7 Step 5 的 `rehearse.db`（已 INCREMENTAL）上跑精簡模式到做完。腳本不進 repo（`dart run` 需在 repo 內解析 package，故暫放 `tool/_rehearse_retention.dart`，跑完即刪）：

```dart
// tool/_rehearse_retention.dart（驗證用，跑完刪除，不提交）
import 'dart:io';

import 'package:daredevil/core/constants/data_retention_policy.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/domain/services/data_retention_service.dart';

Future<void> main(List<String> args) async {
  final path = args.single;
  final db = AppDatabase.forToolFile(path);
  final service = DataRetentionService(database: db, mode: RetentionMode.lean);
  for (var round = 1; ; round++) {
    final sw = Stopwatch()..start();
    final report = await service.run();
    stdout.writeln('round $round: deleted ${report.totalDeleted} '
        'in ${sw.elapsedMilliseconds} ms, completed=${report.completed}, '
        'file ${File(path).lengthSync() ~/ 1048576} MB');
    if (report.completed) break;
  }
  final ok = await db.customSelect('PRAGMA integrity_check').getSingle();
  stdout.writeln('integrity: ${ok.data.values.first}');
  await db.close();
}
```

Run: `dart run tool/_rehearse_retention.dart "$S/rehearse.db"; rm tool/_rehearse_retention.dart`

Expected: 首輪在 15 秒預算內停下或完成；總刪除約 149 萬列（與 2026-09-26 實測同量級）；最終檔案明顯小於 564 MB（實測完整 VACUUM 後約 244 MB）；`integrity_check` 為 ok

- [ ] **Step 4: 研究模式在 Mac 正式 DB 的第一輪（由 user 觸發一般更新）**

user 在 App 或等 launchd 下次更新後，查日誌與 DB：

Run: `grep "資料保留期清理" ~/Library/Logs/daredevil-daily-update.stdout.log | tail -3; sqlite3 "file:$HOME/Library/Containers/com.neo.afterclose/Data/Documents/afterclose.sqlite?immutable=1" "select count(*) from update_run; select count(*) from daily_price;"`
Expected: 日誌有「資料保留期清理完成」；update_run ≤ 200；daily_price 列數不減少（研究模式不動時間序列）

- [ ] **Step 5: 回報 user 待辦**

告知 user 兩件要自己做的事：
- Mac：停 launchd、關 App 後跑 `dart run tool/vacuum_db.dart`，再 `ops/launchd/install.sh` 掛回
- 手機：已安裝的 DB 不會縮小（停止成長）；要縮只能刪 App 資料重新同步
