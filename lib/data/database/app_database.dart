import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
// meta 而非 flutter/foundation:本檔需維持純 Dart 可用(forToolFile 走
// `dart run`,不可引入 dart:ui 依賴鏈,見 forToolFile doc)
import 'package:meta/meta.dart' show visibleForTesting;

import 'package:daredevil/core/utils/logger.dart';

import 'package:daredevil/data/database/tables/stock_master.dart';
import 'package:daredevil/data/database/tables/daily_price.dart';
import 'package:daredevil/data/database/tables/daily_institutional.dart';
import 'package:daredevil/data/database/tables/news_tables.dart';
import 'package:daredevil/data/database/tables/analysis_tables.dart';
import 'package:daredevil/data/database/tables/user_tables.dart';
import 'package:daredevil/data/database/tables/market_data_tables.dart';
import 'package:daredevil/data/database/tables/portfolio_tables.dart';
import 'package:daredevil/data/database/tables/event_tables.dart';
import 'package:daredevil/data/database/tables/market_index_tables.dart';

// Drift modular generated code
import 'package:daredevil/data/database/app_database.drift.dart';

// Re-export generated types for backward compatibility
export 'package:daredevil/data/database/app_database.drift.dart';
export 'package:daredevil/data/database/dao/price_dao.dart' show PriceCoverage;
export 'package:daredevil/data/database/tables/stock_master.drift.dart';
export 'package:daredevil/data/database/tables/daily_price.drift.dart';
export 'package:daredevil/data/database/tables/daily_institutional.drift.dart';
export 'package:daredevil/data/database/tables/news_tables.drift.dart';
export 'package:daredevil/data/database/tables/analysis_tables.drift.dart';
export 'package:daredevil/data/database/tables/user_tables.drift.dart';
export 'package:daredevil/data/database/tables/market_data_tables.drift.dart';
export 'package:daredevil/data/database/tables/portfolio_tables.drift.dart';
export 'package:daredevil/data/database/tables/event_tables.drift.dart';
export 'package:daredevil/data/database/tables/market_index_tables.drift.dart';

// DAO files (standalone)
import 'package:daredevil/data/database/dao/analysis_dao.dart';
import 'package:daredevil/data/database/dao/calibration_cache_dao.dart';
import 'package:daredevil/data/database/dao/day_trading_dao.dart';
import 'package:daredevil/data/database/dao/dividend_dao.dart';
import 'package:daredevil/data/database/dao/event_dao.dart';
import 'package:daredevil/data/database/dao/financial_data_dao.dart';
import 'package:daredevil/data/database/dao/holding_distribution_dao.dart';
import 'package:daredevil/data/database/dao/insider_holding_dao.dart';
import 'package:daredevil/data/database/dao/insider_transfer_dao.dart';
import 'package:daredevil/data/database/dao/institutional_dao.dart';
import 'package:daredevil/data/database/dao/margin_trading_dao.dart';
import 'package:daredevil/data/database/dao/market_index_dao.dart';
import 'package:daredevil/data/database/dao/market_overview_dao.dart';
import 'package:daredevil/data/database/dao/news_dao.dart';
import 'package:daredevil/data/database/dao/portfolio_dao.dart';
import 'package:daredevil/data/database/dao/price_dao.dart';
import 'package:daredevil/data/database/dao/quarterly_report_dao.dart';
import 'package:daredevil/data/database/dao/revenue_dao.dart';
import 'package:daredevil/data/database/dao/shareholding_dao.dart';
import 'package:daredevil/data/database/dao/stock_dao.dart';
import 'package:daredevil/data/database/dao/trading_warning_dao.dart';
import 'package:daredevil/data/database/dao/thesis_dao.dart';
import 'package:daredevil/data/database/dao/user_dao.dart';
import 'package:daredevil/data/database/dao/valuation_dao.dart';

@DriftDatabase(
  tables: [
    // 主檔資料
    StockMaster,
    // 每日市場資料
    DailyPrice,
    DailyInstitutional,
    // 新聞
    NewsItem,
    NewsStockMap,
    NewsMentionDaily,
    // 分析結果
    DailyAnalysis,
    DailyReason,
    // 規則準確度追蹤
    RuleAccuracy,
    // 使用者資料
    // WatchlistGroups 必須排在 Watchlist 之前：Watchlist.groupId 以 FK 參照
    // WatchlistGroups，createAll 依序建表時 parent 必須先存在。
    WatchlistGroups,
    Watchlist,
    UpdateRun,
    AppSettings,
    PriceAlert,
    PinnedThesis,
    // 擴充市場資料（Phase 1）
    Shareholding,
    DayTrading,
    FinancialData,
    HoldingDistribution,
    // 基本面資料（Phase 3）
    MonthlyRevenue,
    StockValuation,
    // 股利歷史
    DividendHistory,
    // 融資融券資料（Phase 4）
    MarginTrading,
    // 風險控管資料（Killer Features）
    TradingWarning,
    InsiderHolding,
    // 內部人股權轉讓（Feature 4）
    InsiderTransfer,
    // 自訂選股策略（Phase 2.2）
    // 投資組合（Phase 4.4）
    PortfolioPosition,
    PortfolioTransaction,
    // 事件行事曆（Phase 4.3）
    StockEvent,
    // 大盤指數歷史（Phase 5.2）
    MarketIndex,
    QuarterlyReport,
  ],
)
class AppDatabase extends $AppDatabase
    with
        StockDaoMixin,
        PriceDaoMixin,
        ThesisDaoMixin,
        AnalysisDaoMixin,
        InstitutionalDaoMixin,
        UserDaoMixin,
        PortfolioDaoMixin,
        EventDaoMixin,
        MarketIndexDaoMixin,
        NewsDaoMixin,
        ShareholdingDaoMixin,
        DayTradingDaoMixin,
        MarginTradingDaoMixin,
        FinancialDataDaoMixin,
        RevenueDaoMixin,
        ValuationDaoMixin,
        DividendDaoMixin,
        HoldingDistributionDaoMixin,
        TradingWarningDaoMixin,
        InsiderHoldingDaoMixin,
        InsiderTransferDaoMixin,
        QuarterlyReportDaoMixin,
        MarketOverviewDaoMixin,
        CalibrationCacheDaoMixin {
  /// 純 Dart constructor — caller 注入 [QueryExecutor]
  ///
  /// **C 方案 refactor 2026-06-19**：移除原本 `AppDatabase() : super(_openConnection())`
  /// 把 `drift_flutter` 鏈拉進整個檔的 default 構造。`drift_flutter` →
  /// `path_provider` → `package:flutter/foundation.dart` → `dart:ui`，
  /// 連鎖讓所有 import AppDatabase 的純 Dart CLI 無法 `dart run`
  /// （包括 `tool/backfill.dart`、`tool/replay_calibrator.dart`）。
  ///
  /// Flutter 路徑（runtime app / WorkManager isolate）改顯式呼叫
  /// `openDriftFlutterConnection()` from `app_database_flutter.dart`：
  ///
  /// ```dart
  /// final db = AppDatabase(openDriftFlutterConnection());
  /// ```
  ///
  /// 純 Dart 路徑改用 [AppDatabase.forToolFile] / [AppDatabase.forTesting]。
  AppDatabase(super.executor);

  /// 測試用 - 建立記憶體內 Database
  AppDatabase.forTesting() : super(NativeDatabase.memory());

  /// Tool / CLI 用 — 開啟指定路徑的 SQLite 檔案作為獨立 DB
  ///
  /// 用途：
  /// - macOS launchd CLI（`tool/daily_update.dart`）直接讀寫 GUI app sandbox
  ///   的 DB
  /// - Stage 3+4 backfill + calibration（`tool/backfill.dart`、
  ///   `tool/replay_calibrator.dart`、`tool/recalibrate.dart`）走獨立
  ///   `tool/calibration.db` 路徑避免污染正式 dev DB
  ///
  /// 若 [path] 不存在會自動建立，schema 透過既有的 `onCreate` +
  /// fingerprint 機制建好。**純 Dart**：不經 `drift_flutter`，可在
  /// `dart run` 環境正常運作。
  AppDatabase.forToolFile(String path)
    : super(
        NativeDatabase(
          File(path),
          setup: (db) {
            // 🔴 2026-08-08 code review 實測重現:預設 busy_timeout=0,
            // GUI 在盤中做一次手動更新握住寫鎖,launchd 的盤中檢查就整輪
            // 死在 beforeOpen 的維護 UPDATE(SqliteException(5) database
            // is locked),連報價都沒抓就 exit 1。WAL 只解決讀寫並行,
            // 寫寫仍需排隊——給它等,不要當場放棄。
            db.execute('PRAGMA busy_timeout = 5000');
            db.execute('PRAGMA journal_mode = WAL');
          },
        ),
      );

  /// 產品尚未上線前使用 version 1，所有 table 和 index 在 onCreate 一次建好。
  /// 正式上線後，每次 schema 變更遞增 version 並在 onUpgrade 加 migration。
  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
    },
    beforeOpen: (details) async {
      // Pre-launch schema drift auto-reset: 在啟用 FK 前執行，讓 DROP TABLE
      // 不會因為 CASCADE 連鎖觸發非預期刪除。若偵測到 fingerprint mismatch，
      // 會把所有 Drift managed table drop 後由 Migrator 重建。
      await _ensureSchemaFingerprint();
      await _ensureDealerSelfNetColumn();
      await _ensureMonthlyRevenueYtdColumn();
      await _ensureRuleAccuracyDistinctDatesColumn();
      await _ensureWatchlistGroupsSchema();
      await _ensurePinnedThesisSchema();
      await _ensureQuarterlyReportSchema();
      await _ensureRetiredSchemaDropped();
      await _ensureIndexHygiene();
      // 歷史零價列收斂(2026-07-30):TWSE STOCK_DAY_ALL 對「無成交」
      // 用 0.00 表達,parser 修正(TwParseUtils.parsePrice)前已有 41 列
      // close=0 落庫。0 污染 52 週窗(min 永遠 0)與漲跌顯示(-100%),
      // 冪等 NULL 化;volume 不動(0 量合法)。
      await _ensureZeroPriceSanitized();
      // 過期的 RUNNING run 收斂成 FAILED(app 被殺/崩潰後遺留)。
      // age cutoff 防跨 process 誤殺:macOS CLI(tool/daily_update.dart,
      // launchd 排程)與 GUI 共用同一份 DB、各開獨立連線,CLI 的 beforeOpen
      // 若無條件清 RUNNING 會誤殺 GUI 正在進行的 run。
      await failOrphanRunningRuns();
      // 回收逾期未結案的提醒認領——process 被殺會讓該筆卡在
      // 「已認領未消費」,兩條路徑都撿不到(2026-08-08 五次審查 I-1)
      await reclaimStaleAlertClaims();
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  /// 歷史零價列 NULL 化(2026-07-30,冪等)。
  ///
  /// 只動 close=0 的列(實測 41 列全為此型、無部分欄位 0),四個價格欄
  /// 一律 NULL;volume 保留(0=無量、17=零股 皆合法)。新資料由
  /// [TwParseUtils.parsePrice] 在解析層擋,此步收斂存量+兜底。
  Future<void> _ensureZeroPriceSanitized() async {
    // partial index(2026-08-01 複審):daily_price 3.5M+ 列且逐日成長,
    // close 無索引時這條 UPDATE 每次啟動都全表掃描。穩態下索引為空
    // (清過的列 close=NULL 即離開索引),UPDATE 趨近 O(1);建索引本身
    // 只有首次要掃全表,之後 IF NOT EXISTS no-op。保留 UPDATE 的
    // 「持續兜底」語意——parser 之外若再混入 0,下次啟動仍會被清。
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_daily_price_zero_close '
      'ON daily_price (close) WHERE close = 0',
    );
    await customStatement(
      'UPDATE daily_price SET open = NULL, high = NULL, low = NULL, '
      'close = NULL WHERE close = 0',
    );
  }

  /// Pre-launch idempotent 建表：為既有 DB 補上 `pinned_thesis`（出場層
  /// Phase 2），零資料損失、可安全重跑——沿用 [_ensureWatchlistGroupsSchema]
  /// 的先例（Drift [Migrator.createTable] 內建 CREATE TABLE IF NOT EXISTS，
  /// 既有 DB 已建過 no-op、全新安裝由 createAll 先建好這裡也 no-op）。
  Future<void> _ensurePinnedThesisSchema() async {
    await Migrator(this).createTable(pinnedThesis);
  }

  /// 季報快照表(2026-08-06,additive)。
  ///
  /// 沿 [_ensurePinnedThesisSchema] 先例:**不 bump fingerprint**——指紋
  /// bump 會 wipe 非白名單表,價格/財報等 350 萬列衍生資料要重抓數日額度,
  /// 為加一張新表付這代價不成比例。createTable=CREATE TABLE IF NOT EXISTS,
  /// 既有 DB 冪等補建、新裝機由 createAll 先建好此處 no-op,零資料損失。
  Future<void> _ensureQuarterlyReportSchema() async {
    await Migrator(this).createTable(quarterlyReport);
  }

  /// 2026-07-29 索引衛生（多角色審查 Fix 1）：清除與複合 PK autoindex 完全
  /// 重複或為其左前綴的 24 條顯式索引，並為 `daily_reason` 補 date-leading
  /// 索引（mode tab 三個消費者按日查詢，PK (symbol,date,rank) 幫不上）。
  ///
  /// **不 bump [appSchemaFingerprint]**：指紋 bump 會 wipe 非白名單表，
  /// 價格深度重建約需 19 次每日更新，為索引整理付這代價不成比例。沿用
  /// [_ensureDealerSelfNetColumn] 先例：DROP/CREATE 皆冪等、只動索引
  /// metadata、資料零損失、每次開啟安全重跑（新裝機為 no-op——createAll
  /// 已不再建這些索引）。
  ///
  /// 判定依據：Drift 複合 primaryKey 會生成 sqlite_autoindex UNIQUE 索引，
  /// 任何等於它或為其左前綴的顯式索引都是純寫入稅（daily_price 3.1M 列
  /// 實測索引空間 ~2 倍膨脹）。date-leading 與非前綴索引全數保留
  /// （含 idx_daily_analysis_date_score_short/long——(date, score) 複合
  /// 服務 getAnalysisForDate 的 WHERE date= ORDER BY score DESC，非冗餘，
  /// 2026-07-29 對抗審查曾抓到誤列 drop 清單，已移除並以不變量測試守住：
  /// drop 清單 ∩ 現行宣告索引 = ∅，見 index_hygiene_test）。
  Future<void> _ensureIndexHygiene() async {
    for (final name in legacyRedundantIndexes) {
      await customStatement('DROP INDEX IF EXISTS "$name"');
    }
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_daily_reason_date '
      'ON daily_reason (date)',
    );
  }

  /// [_ensureIndexHygiene] 的清除名單。@visibleForTesting 供不變量測試
  /// 斷言「與現行宣告索引零交集」。
  @visibleForTesting
  static const List<String> legacyRedundantIndexes = [
    // = PK
    'idx_daily_analysis_symbol_date',
    'idx_daily_price_symbol_date',
    'idx_shareholding_symbol_date',
    'idx_monthly_revenue_symbol_date',
    'idx_margin_trading_symbol_date',
    'idx_insider_holding_symbol_date',
    // PK 左前綴
    'idx_daily_reason_symbol_date',
    'idx_rule_accuracy_rule',
    'idx_daily_institutional_symbol',
    'idx_daily_price_symbol',
    'idx_shareholding_symbol',
    'idx_day_trading_symbol',
    'idx_financial_data_symbol',
    'idx_holding_dist_symbol',
    'idx_dividend_history_symbol',
    'idx_monthly_revenue_symbol',
    'idx_stock_valuation_symbol',
    'idx_margin_trading_symbol',
    'idx_trading_warning_symbol',
    'idx_trading_warning_symbol_date',
    'idx_insider_holding_symbol',
    'idx_insider_transfer_symbol',
    'idx_news_stock_map_news_id',
    'idx_news_mention_daily_date',
    // 2026-07-29 審查後自 schema 宣告除役的三條(annotation 已移除,
    // 既有 DB 由此清除;誤殺教訓見 _ensureIndexHygiene doc)
    'idx_daily_institutional_symbol_date', // = PK,雙重冗餘
    // daily_recommendation 兩條已無須列管(2026-08-15 健檢:整張表 DROP,
    // 索引隨表消失;見 _ensureRetiredSchemaDropped)
  ];

  /// Pre-launch idempotent 加欄：在「不」bump schema fingerprint（不 wipe 既有
  /// derived 資料）的前提下，為既有 DB 補上 `daily_institutional.dealer_self_net`。
  ///
  /// - 全新安裝：`createAll` 已依表定義建出此欄，這裡 PRAGMA 查到便 no-op。
  /// - 既有 DB：fingerprint 未變→不 wipe，這裡偵測缺欄並 `ALTER TABLE ADD COLUMN`，
  ///   既有 47 天法人資料與其餘 derived 表全部保留。
  /// - 未來若有人 bump fingerprint 觸發 wipe：createAll 重建已含此欄，這裡 no-op。
  ///
  /// SQLite 的 `ALTER TABLE ADD COLUMN` 不支援 `IF NOT EXISTS`，故先以
  /// `PRAGMA table_info` 判斷欄位是否存在，確保 idempotent（每次開啟可安全重跑）。
  /// Pre-launch idempotent 加欄：為既有 DB 補上 `rule_accuracy.distinct_dates`。
  ///
  /// **不走 [appSchemaFingerprint] bump**：指紋機制會 drop 全部非 whitelist
  /// 表重建，而 `daily_price` 不在 whitelist —— 實測使用者 live DB 有 275 個
  /// 交易日 / 565,570 列，wipe 後 Phase 0 市場日快照單次上限 30 次呼叫
  /// （[ApiConfig.historicalMarketDayMaxCalls]），回到原深度約需 19 次每日
  /// 更新。為了一個純附加欄位付這個代價不成比例。
  ///
  /// 沿用 [_ensureDealerSelfNetColumn] 的先例：`PRAGMA table_info` 檢查後
  /// `ALTER TABLE ADD COLUMN`，既有 DB 零損失、全新安裝由 createAll 先建好
  /// 這裡 no-op、重跑安全。
  Future<void> _ensureRuleAccuracyDistinctDatesColumn() async {
    final columns = await customSelect(
      "PRAGMA table_info('rule_accuracy')",
    ).get();
    final hasColumn = columns.any(
      (row) => row.read<String>('name') == 'distinct_dates',
    );
    if (hasColumn) return;

    await customStatement(
      'ALTER TABLE rule_accuracy ADD COLUMN distinct_dates '
      'INTEGER NOT NULL DEFAULT 0',
    );
    AppLogger.info(
      'AppDatabase',
      'rule_accuracy.distinct_dates 欄位已補上（idempotent ALTER，未 wipe）',
    );
  }

  /// Pre-launch idempotent 退役清理(2026-08-15 全專案健檢):三張零讀零寫的
  /// 殭屍表與 `insider_holding` 三個 production 永遠 NULL 的欄位,已自 schema
  /// 宣告移除;此路徑清掉既有 DB 的殘留。
  ///
  /// 沿 [_ensureDealerSelfNetColumn] 先例:**不 bump fingerprint**——指紋變更
  /// 會 wipe 全部非白名單表(59.7 萬列價格),而這裡刪的東西實測零價值。
  ///
  /// **彩排實證**(2026-08-15,真實 DDL 跑 production 副本):三表各 0 列、
  /// 三欄非 NULL 列數 0、DDL 後六項基準指標(價格/自選/警示/事件/新聞/設定)
  /// 逐項一致、`integrity_check` ok、FK 無違規。
  ///
  /// **fail-soft**:清理是整潔工作不是正確性——殘留欄位無人讀取(Drift 以
  /// 具名欄位查詢,多餘欄位不影響),但啟動失敗是災難。捆綁 SQLite 實測
  /// 3.52.0 支援 `DROP COLUMN`(3.35+),仍全段防禦以防其他平台版本落後。
  Future<void> _ensureRetiredSchemaDropped() async {
    try {
      for (final table in const [
        'daily_recommendation',
        'recommendation_validation',
        'screening_strategy_table',
      ]) {
        await customStatement('DROP TABLE IF EXISTS $table');
      }

      final columns = await customSelect(
        "PRAGMA table_info('insider_holding')",
      ).get();
      final existing = columns.map((row) => row.read<String>('name')).toSet();
      for (final column in const [
        'director_shares',
        'supervisor_shares',
        'manager_shares',
      ]) {
        if (!existing.contains(column)) continue;
        await customStatement(
          'ALTER TABLE insider_holding DROP COLUMN $column',
        );
      }
    } catch (e) {
      AppLogger.warning('AppDatabase', '退役 schema 清理失敗(忽略,殘留無害)', e);
    }
  }

  Future<void> _ensureDealerSelfNetColumn() async {
    final columns = await customSelect(
      "PRAGMA table_info('daily_institutional')",
    ).get();
    final hasColumn = columns.any(
      (row) => row.read<String>('name') == 'dealer_self_net',
    );
    if (hasColumn) return;

    await customStatement(
      'ALTER TABLE daily_institutional ADD COLUMN dealer_self_net REAL',
    );
    AppLogger.info(
      'AppDatabase',
      '既有 DB 補上 daily_institutional.dealer_self_net 欄（保留既有資料）',
    );
  }

  /// 為既有 monthly_revenue 補 ytd_yoy_growth 欄(2026-08-13 累計年增)。
  ///
  /// 沿用 [_ensureDealerSelfNetColumn] 前例:idempotent、缺才加、
  /// 不 bump fingerprint(bump 會 wipe 全部非白名單表,58.7 萬列價格
  /// 重抓要燒數天 FinMind 配額)。舊列為 null——歷史月份的累計值
  /// 本來就沒抓過,下次公布期起自然填充。
  Future<void> _ensureMonthlyRevenueYtdColumn() async {
    final columns = await customSelect(
      "PRAGMA table_info('monthly_revenue')",
    ).get();
    final hasColumn = columns.any(
      (row) => row.read<String>('name') == 'ytd_yoy_growth',
    );
    if (hasColumn) return;

    await customStatement(
      'ALTER TABLE monthly_revenue ADD COLUMN ytd_yoy_growth REAL',
    );
    AppLogger.info(
      'AppDatabase',
      '既有 DB 補上 monthly_revenue.ytd_yoy_growth 欄（保留既有資料）',
    );
  }

  /// Pre-launch idempotent schema 套用：在「不」bump schema fingerprint（不 wipe
  /// 既有 watchlist / 行情資料）的前提下，為既有 DB 補上 watchlist 自訂分組
  /// 功能與預設分組旗標。
  ///
  /// 沿用 [_ensureDealerSelfNetColumn] 的先例（零資料損失、可安全重跑），分三步：
  ///
  /// 1. **建新表 `watchlist_groups`**：直接用 Drift 自己的 [Migrator.createTable]，
  ///    讓 DDL 與 generated schema 完全一致（避免手寫 CREATE TABLE 造成欄位/型別
  ///    漂移）。Drift 的 `createTable` 內部用 `CREATE TABLE IF NOT EXISTS`，
  ///    既有 DB 已建過便 no-op、全新安裝由 `createAll` 先建好這裡也是 no-op。
  ///
  /// 2. **為 `watchlist` 加 `group_id` 欄**：SQLite `ALTER TABLE ADD COLUMN`
  ///    不支援 `IF NOT EXISTS`，故先以 `PRAGMA table_info('watchlist')` 判斷
  ///    欄位是否存在，缺才補。既有自選股資料全部保留（新欄對既有列為 null =
  ///    未分組）。
  ///
  /// 3. **為 `watchlist_groups` 加 `is_default` 欄**（2026-08-12 預設分組）：
  ///    同樣以 `PRAGMA table_info` 判斷缺才補。既有分組一律 false——升級
  ///    不得憑空指定預設分組。DDL 與 generated schema 的一致性由
  ///    `watchlist_groups_default_column_migration_test` 鎖住。
  ///
  /// 必須在 `PRAGMA foreign_keys = ON` 之前執行：欄位帶 FK 參照 watchlist_groups，
  /// 在 FK 關閉狀態下做 DDL 較安全；且步驟 1 先於步驟 2，確保 FK 參照的 parent
  /// 表已存在。
  Future<void> _ensureWatchlistGroupsSchema() async {
    // 步驟 1：建分組表（Drift 內建 CREATE TABLE IF NOT EXISTS，idempotent）
    await createMigrator().createTable(watchlistGroups);

    // 步驟 2：為既有 watchlist 表補 group_id 欄（缺才加）
    final columns = await customSelect("PRAGMA table_info('watchlist')").get();
    final hasGroupId = columns.any(
      (row) => row.read<String>('name') == 'group_id',
    );
    if (!hasGroupId) {
      await customStatement(
        'ALTER TABLE watchlist ADD COLUMN group_id INTEGER '
        'REFERENCES watchlist_groups(id) ON DELETE SET NULL',
      );
      AppLogger.info(
        'AppDatabase',
        '既有 DB 補上 watchlist.group_id 欄與 watchlist_groups 表（保留既有自選股）',
      );
    }

    // 步驟 3（2026-08-12）：為既有 watchlist_groups 補 is_default 欄
    // （預設分組功能）。DDL 需與 generated schema 一致：NOT NULL DEFAULT 0
    // + CHECK。既有分組一律補 false——升級不得憑空指定預設分組。
    final groupColumns = await customSelect(
      "PRAGMA table_info('watchlist_groups')",
    ).get();
    final hasIsDefault = groupColumns.any(
      (row) => row.read<String>('name') == 'is_default',
    );
    if (!hasIsDefault) {
      await customStatement(
        'ALTER TABLE watchlist_groups ADD COLUMN is_default INTEGER '
        'NOT NULL DEFAULT 0 CHECK (is_default IN (0, 1))',
      );
      AppLogger.info(
        'AppDatabase',
        '既有 DB 補上 watchlist_groups.is_default 欄（保留既有分組）',
      );
    }
  }

  /// 檢查 schema fingerprint 是否與當前 code 一致，若不一致則 drop 全部 table 重建
  ///
  /// ## 設計動機
  ///
  /// Pre-launch 階段我們刻意把 [schemaVersion] 鎖在 1（避免每次改 schema 都
  /// 要維護 migration ladder）。但 Drift 的 `onUpgrade` 是 version-driven，
  /// version 沒變就不會觸發 migration。結果：developer 改了 table 定義、
  /// 跑了 `build_runner` 後，舊的 `.sqlite` 檔案仍保有舊 schema，app 啟動
  /// 時會炸 `no such column` 之類的錯誤。
  ///
  /// 此 method 在 `beforeOpen` 執行，透過一個不受 Drift 管理的 meta table
  /// 儲存當前 schema 的指紋字串。啟動時比對，不一致就把**非使用者輸入**的
  /// Drift 表 drop 後呼叫 `Migrator.createAll` 重建。Drift `createTable`
  /// 本身用 `CREATE TABLE IF NOT EXISTS`，所以 whitelist 內已存在的表會
  /// 直接 skip、保留資料。
  ///
  /// ## 何時 bump fingerprint
  ///
  /// **任何 schema 改動都要 bump `appSchemaFingerprint` 的字串值**：
  /// - 新增 / 刪除 / 重命名 column
  /// - 改 primary key / unique key / index
  /// - 新增 / 刪除 table
  ///
  /// 字串值是不透明的，只要跟前一個版本不同就會觸發 reset。建議用
  /// `<stage>-<feature>-<date>` 格式，方便看 git blame 追歷史。
  ///
  /// ## 使用者輸入表 whitelist（不會被 wipe）
  ///
  /// [_userInputTableNames] 內列出的表在 reset 時被跳過，避免使用者**手動
  /// 輸入**的資料（自選股、價格警示、自訂篩選、portfolio、自訂事件、app 偏好）
  /// 被洗掉。
  ///
  /// ## ⚠️ Whitelist 的已知限制
  ///
  /// Whitelist 內的表若**schema 改動**（加欄位、改 PK），此機制不會自動
  /// migrate — `CREATE TABLE IF NOT EXISTS` 看到既存表就放著不動，新 column
  /// 不會出現、舊 column 也不會被刪。
  ///
  /// 解法：若要動 whitelist 表的 schema，必須**同時加一段 ALTER TABLE 路徑**
  /// 處理現有 DB；或臨時把該表從 whitelist 拿掉接受該次 wipe。長期該換
  /// Drift `schemaVersion` + `onUpgrade` migration ladder 治本。
  ///
  /// ## 不在 whitelist 的表為何安全
  ///
  /// 其餘表都是 derived data（每日 syncer 重抓即可）。`update_run` 也不
  /// 進 whitelist — wipe 後首次啟動會被當成「沒跑過」觸發一次全量同步，
  /// 沒資料損失。
  ///
  /// ## 正式上線後的遷移路徑
  ///
  /// 上線之後此機制**仍建議移除**，改回 Drift 標準的 `schemaVersion` 遞增 +
  /// `onUpgrade` migration。此 whitelist fix 只是**避免 pre-launch 期間自
  /// 己 dogfooding 時被洗掉資料**的權宜之計。
  static const Set<String> _userInputTableNames = {
    'pinned_thesis', // 釘選論點（含 INVALIDATED/ARCHIVED 歷史——凍結紀錄不可洗）
    'portfolio_position',
    'portfolio_transaction',
    'watchlist',
    'watchlist_groups',
    'price_alert',
    'stock_event',
    'app_settings',
    'news_mention_daily', // 熱度快照：歷史不可重建，fingerprint reset 不得 wipe
    // 新聞非嚴格「使用者輸入」但同屬不可重建：RSS feed 只供應當下窗口，
    // 30 天存量 wipe 後補不回（2026-07-15 reset 實際損失 ~6,200 筆，
    // 熱度分析基準窗因此空窗數週）。schema 改動需走 ALTER 路徑。
    'news_item',
    'news_stock_map',
  };

  Future<void> _ensureSchemaFingerprint() async {
    // 建立 meta table（不屬於 Drift schema，不會被 allTables 列出來）
    await customStatement('''
      CREATE TABLE IF NOT EXISTS _drift_schema_fingerprint (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        value TEXT NOT NULL
      )
    ''');

    final result = await customSelect(
      'SELECT value FROM _drift_schema_fingerprint WHERE id = 1',
    ).get();
    final stored = result.isEmpty ? null : result.first.read<String>('value');

    if (stored == appSchemaFingerprint) {
      return; // fingerprint 一致，跳過
    }

    if (stored != null) {
      // 偵測到 schema drift — drop 所有非 whitelist 的 Drift managed table
      // 後重建。
      //
      // ⚠️ 承重不變量：此時 foreign_keys pragma 必須仍為 OFF（Drift 預設，
      // beforeOpen 稍後才 ON）。若 FK 已 ON，SQLite 的 DROP TABLE 會對子表
      // 觸發 ON DELETE CASCADE——drop stock_master 會**靜默清空保留中的
      // news_stock_map**（白名單形同虛設）。日後任何人調整 pragma 順序前，
      // 先看 schema_fingerprint_reset_test.dart 的保留斷言。
      final preserved = <String>[];
      final dropped = <String>[];
      AppLogger.warning(
        'AppDatabase',
        'Schema fingerprint mismatch — resetting tables '
            '(stored=$stored, expected=$appSchemaFingerprint)',
      );
      for (final table in allTables.toList().reversed) {
        final name = table.actualTableName;
        if (_userInputTableNames.contains(name)) {
          preserved.add(name);
          continue;
        }
        await customStatement('DROP TABLE IF EXISTS "$name"');
        dropped.add(name);
      }
      // createAll 用 CREATE TABLE IF NOT EXISTS（drift 2.x 內建），保留的
      // user input 表既存資料不會被動到。
      //
      // ⚠️ 但 createAll 建**索引**不帶 IF NOT EXISTS：whitelist 表未被
      // drop、其索引仍存在，直接 createAll 會炸 "index already exists"
      // （2026-07-15 生產事故：idx_portfolio_position_symbol）。索引皆可
      // 安全重建——先全數 DROP 再交給 createAll 重建。
      for (final index in allSchemaEntities.whereType<Index>()) {
        await customStatement('DROP INDEX IF EXISTS "${index.entityName}"');
      }
      await Migrator(this).createAll();
      AppLogger.info(
        'AppDatabase',
        'Schema reset complete — dropped=${dropped.length} '
            '(${dropped.join(",")}), preserved=${preserved.length} '
            '(${preserved.join(",")})',
      );
    } else {
      // 第一次建立 DB — onCreate 已經跑過 createAll，這邊只需記錄 fingerprint
      AppLogger.info(
        'AppDatabase',
        'Initial schema fingerprint: $appSchemaFingerprint',
      );
    }

    await customStatement(
      'INSERT OR REPLACE INTO _drift_schema_fingerprint (id, value) VALUES (1, ?)',
      [appSchemaFingerprint],
    );
  }
}

/// Schema fingerprint for pre-launch drift auto-reset
///
/// **Bump this string whenever any Drift table definition changes**. See
/// [AppDatabase._ensureSchemaFingerprint] for the full rationale and the
/// post-launch migration path.
///
/// Format: `<stage>-<feature>-<YYYY-MM-DD>`. Any string change triggers a
/// reset — the value itself is opaque.
///
/// Public（而非 private）是因為 `tool/backfill.dart` 要在**開啟 DB 之前**
/// 比對它：對 app 而言 reset 只是重抓 derived data，對 `tool/calibration.db`
/// 卻是九年歷史當場歸零。見該檔的 `_checkSchemaFingerprint`。
const String appSchemaFingerprint = 'stage5b-news-mention-daily-2026-07-15';

// 原 `QueryExecutor _openConnection()` 已搬到 `app_database_flutter.dart`
// 並改為 public `openDriftFlutterConnection()`，避免 `drift_flutter` import
// 把 `dart:ui` 拉進整個 type graph，讓 `tool/` 的純 Dart CLI 可以跑。
