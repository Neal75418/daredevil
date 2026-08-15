import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/data/database/app_database.dart';

/// 索引衛生 ensure-step 的回歸測試(2026-07-29 多角色審查 Fix 1)。
///
/// 背景:27 條顯式索引與複合 PK 的 autoindex 完全重複、為其左前綴、或與
/// uniqueKeys autoindex 重複(daily_price 3.1M 列實測索引空間 ~2 倍膨脹);
/// 同時 `daily_reason` 缺 date-leading 索引,三個 mode 消費者全表掃描。
///
/// 修法沿用 `_ensureDealerSelfNetColumn` 先例:**不 bump fingerprint**
/// (bump 會 wipe 非白名單表,價格深度要 19 天才補得回來),在 beforeOpen
/// 用冪等 `DROP INDEX IF EXISTS`/`CREATE INDEX IF NOT EXISTS` 收斂,
/// 既有 DB 零資料損失、每次開啟可安全重跑。
///
/// **2026-07-29 對抗審查教訓**:第一版 drop 清單誤把兩條仍在宣告中的活
/// 複合索引(idx_daily_analysis_date_score_short/long,服務
/// getAnalysisForDate 的 WHERE date= ORDER BY score DESC)列為殭屍——
/// 肇因是盤點工具的 regex 不吃跨行 @TableIndex。本檔的「不變量」測試
/// 直接斷言 drop 清單與現行宣告零交集,永久守住這類分類錯誤。
void main() {
  late Directory tempDir;
  late File dbFile;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('index_hygiene_test');
    dbFile = File('${tempDir.path}/idx_test.sqlite');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  Future<Set<String>> indexNames(AppDatabase db) async {
    final rows = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type='index' "
          "AND name NOT LIKE 'sqlite_autoindex%'",
        )
        .get();
    return rows.map((r) => r.read<String>('name')).toSet();
  }

  /// drop 清單全 27 條的重建 DDL——模擬「舊版 schema 的既有 DB」。
  /// 對抗審查 mutation 實測:第一版測試只建回 4 條,其餘 23 條的 DROP
  /// 拿掉任一條都不會紅;此表讓每一條 DROP 都被守住。
  const legacyDdl = <String, String>{
    'idx_daily_analysis_symbol_date': 'daily_analysis (symbol, date)',
    'idx_daily_price_symbol_date': 'daily_price (symbol, date)',
    'idx_shareholding_symbol_date': 'shareholding (symbol, date)',
    'idx_monthly_revenue_symbol_date': 'monthly_revenue (symbol, date)',
    'idx_margin_trading_symbol_date': 'margin_trading (symbol, date)',
    'idx_insider_holding_symbol_date': 'insider_holding (symbol, date)',
    'idx_daily_reason_symbol_date': 'daily_reason (symbol, date)',
    'idx_rule_accuracy_rule': 'rule_accuracy (rule_id)',
    'idx_daily_institutional_symbol': 'daily_institutional (symbol)',
    'idx_daily_price_symbol': 'daily_price (symbol)',
    'idx_shareholding_symbol': 'shareholding (symbol)',
    'idx_day_trading_symbol': 'day_trading (symbol)',
    'idx_financial_data_symbol': 'financial_data (symbol)',
    'idx_holding_dist_symbol': 'holding_distribution (symbol)',
    'idx_dividend_history_symbol': 'dividend_history (symbol)',
    'idx_monthly_revenue_symbol': 'monthly_revenue (symbol)',
    'idx_stock_valuation_symbol': 'stock_valuation (symbol)',
    'idx_margin_trading_symbol': 'margin_trading (symbol)',
    'idx_trading_warning_symbol': 'trading_warning (symbol)',
    'idx_trading_warning_symbol_date': 'trading_warning (symbol, date)',
    'idx_insider_holding_symbol': 'insider_holding (symbol)',
    'idx_insider_transfer_symbol': 'insider_transfer (symbol)',
    'idx_news_stock_map_news_id': 'news_stock_map (news_id)',
    'idx_news_mention_daily_date': 'news_mention_daily (date)',
    'idx_daily_institutional_symbol_date': 'daily_institutional (symbol, date)',
    // (daily_recommendation 兩條已隨表退役刪除,2026-08-15 健檢:
    // 表被 DROP 時索引一併消失,fixture 無法也無需再建)
  };

  test('不變量:drop 清單與現行宣告索引零交集(分類錯誤即紅)', () async {
    final db = AppDatabase(NativeDatabase(dbFile));
    await db.customSelect('SELECT 1').get();
    final declared = db.allSchemaEntities
        .whereType<Index>()
        .map((i) => i.entityName)
        .toSet();
    final overlap = declared.intersection(
      AppDatabase.legacyRedundantIndexes.toSet(),
    );
    expect(
      overlap,
      isEmpty,
      reason: 'drop 清單包含仍在 schema 宣告中的索引——會建了又刪、宣告與 DB 永久分歧',
    );
    // DDL 表與 drop 清單同步(漏一條 = 該條 DROP 無 mutation 防護)
    expect(
      legacyDdl.keys.toSet(),
      AppDatabase.legacyRedundantIndexes.toSet(),
      reason: '測試的重建 DDL 表必須鏡射完整 drop 清單',
    );
    await db.close();
  });

  test('既有 DB(含全部 27 條舊索引)重開後:逐條清除、date 索引補上、資料零損失', () async {
    // 1. 初次開啟建 schema,建回全部舊索引,寫入資料
    final db1 = AppDatabase(NativeDatabase(dbFile));
    await db1.customSelect('SELECT 1').get();
    for (final e in legacyDdl.entries) {
      await db1.customStatement(
        'CREATE INDEX IF NOT EXISTS ${e.key} ON ${e.value}',
      );
    }
    await db1
        .into(db1.stockMaster)
        .insert(
          StockMasterCompanion.insert(
            symbol: '2330',
            name: '台積電',
            market: 'TWSE',
          ),
        );
    await db1
        .into(db1.dailyPrice)
        .insert(
          DailyPriceCompanion.insert(
            symbol: '2330',
            date: DateTime(2026, 7, 29),
            close: const Value(600.0),
          ),
        );
    await db1
        .into(db1.dailyReason)
        .insert(
          DailyReasonCompanion.insert(
            symbol: '2330',
            date: DateTime(2026, 7, 29),
            rank: 1,
            reasonType: 'KD_GOLDEN_CROSS',
            evidenceJson: '{}',
          ),
        );
    await db1.close();

    // 2. 重開 → beforeOpen 收斂索引且不動資料
    final db2 = AppDatabase(NativeDatabase(dbFile));
    await db2.customSelect('SELECT 1').get();
    final names = await indexNames(db2);

    for (final legacy in legacyDdl.keys) {
      expect(names, isNot(contains(legacy)), reason: '$legacy 應被清除');
    }
    // date-leading / 複合活索引保留
    expect(names, contains('idx_daily_price_date'));
    expect(names, contains('idx_daily_analysis_date_score_short'));
    expect(names, contains('idx_daily_analysis_date_score_long'));
    // daily_reason 補上 date 索引(mode tab 三個消費者按日查)
    expect(names, contains('idx_daily_reason_date'));

    // 資料零損失
    final priceCount = await db2
        .customSelect('SELECT COUNT(*) AS c FROM daily_price')
        .getSingle();
    expect(priceCount.read<int>('c'), 1);
    final reasonCount = await db2
        .customSelect('SELECT COUNT(*) AS c FROM daily_reason')
        .getSingle();
    expect(reasonCount.read<int>('c'), 1);
    await db2.close();
  });

  test('全新安裝:無任何 drop 清單索引、活複合索引與 date 索引存在', () async {
    final db = AppDatabase(NativeDatabase(dbFile));
    await db.customSelect('SELECT 1').get();
    final names = await indexNames(db);

    for (final legacy in legacyDdl.keys) {
      expect(names, isNot(contains(legacy)), reason: '$legacy 不應存在於新裝機');
    }
    expect(names, contains('idx_daily_reason_date'));
    expect(names, contains('idx_daily_analysis_date_score_short'));
    expect(names, contains('idx_daily_analysis_date_score_long'));
    await db.close();
  });
}
