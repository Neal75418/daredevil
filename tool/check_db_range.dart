// tool/check_db_range.dart
//
// CLI tool — print 為預期輸出，關閉 avoid_print lint。
// ignore_for_file: avoid_print
//
// 盤點 Daredevil 本機 Drift SQLite 的資料現況。
//
// 用途：Scoring Overhaul Phase 0 盤點階段，確認：
//   1. 原始市場資料（daily_price 等）是否有 ≥ 2 年歷史
//   2. 衍生資料（daily_recommendation 等）要清多少
//   3. 每張表的實際範圍與筆數，作為後續 Phase 1 rule firing replay 的輸入基準
//
// 使用方式：
//   dart run tool/check_db_range.dart
//   dart run tool/check_db_range.dart --db /path/to/afterclose.sqlite
//
// 若未指定 --db，會在常見 macOS 位置自動搜尋 afterclose*.sqlite。

import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

/// 盤點目標表 — 依用途分組
const _tableGroups = <String, List<String>>{
  '原始市場資料（Phase 1 calibration 需要，禁止清除）': [
    'daily_price',
    'daily_institutional',
    'monthly_revenue',
    'stock_valuation',
    'day_trading',
    'shareholding',
    'trading_warning',
    'financial_data',
    'dividend_history',
    'insider_holding',
    'insider_transfer',
    'holding_distribution',
    'margin_trading',
    'market_index',
    'news_item',
    'stock_master',
  ],
  '衍生資料（Phase 0 會 wipe 後由 Phase 1 重算）': [
    'daily_analysis',
    'daily_recommendation',
    'daily_reason',
    'recommendation_validation',
    'rule_accuracy',
  ],
};

/// 嘗試找 date 欄位的 column name 候選，按優先度排序
const _dateColumnCandidates = <String>[
  'date',
  'recommendation_date',
  'report_date',
  'ex_right_date',
  'published_at',
  'month',
  'created_at',
  'updated_at',
];

void main(List<String> args) {
  final dbPath = _resolveDbPath(args);
  if (dbPath == null) exit(1);

  final file = File(dbPath);
  if (!file.existsSync()) {
    stderr.writeln('❌ DB file 不存在: $dbPath');
    exit(1);
  }

  print('📂 DB: $dbPath');
  final sizeMb = (file.lengthSync() / 1024 / 1024).toStringAsFixed(1);
  print('   Size: $sizeMb MB');
  print('');

  final db = sqlite3.open(dbPath, mode: OpenMode.readOnly);
  try {
    final existingTables = _listTables(db);

    for (final entry in _tableGroups.entries) {
      print('═══ ${entry.key} ═══');
      for (final table in entry.value) {
        _reportTable(db, table, existingTables);
      }
      print('');
    }

    print('═══ Sanity Check ═══');
    _checkDailyPriceCoverage(db, existingTables);
    print('');
    _checkOrphanTables(db, existingTables);
  } finally {
    db.dispose(); // ignore: deprecated_member_use
  }
}

/// 解析 DB path：優先用 `--db` arg，否則自動偵測
String? _resolveDbPath(List<String> args) {
  for (var i = 0; i < args.length - 1; i++) {
    if (args[i] == '--db') return args[i + 1];
  }
  final auto = _autoDetect();
  if (auto != null) {
    print('🔎 自動偵測到 DB: $auto');
    return auto;
  }
  stderr.writeln('❌ 找不到 DB 檔案，請手動指定：');
  stderr.writeln(
    '   dart run tool/check_db_range.dart --db /path/to/afterclose.sqlite',
  );
  stderr.writeln('');
  stderr.writeln('💡 搜尋指令：');
  stderr.writeln('   find ~/Library -name "afterclose*.sqlite" 2>/dev/null');
  return null;
}

/// 在常見的 Flutter 本機儲存位置搜尋 afterclose*.sqlite
///
/// macOS Flutter desktop 透過 path_provider 會存在：
///   - `~/Library/Containers/[bundle]/Data/Documents/`
///   - `~/Library/Application Support/[bundle]/`
///   - `~/Documents/`（非 sandbox debug build）
String? _autoDetect() {
  final home = Platform.environment['HOME'];
  if (home == null) return null;

  final searchRoots = <String>[
    '$home/Library/Containers',
    '$home/Library/Application Support',
    '$home/Documents',
  ];

  final candidates = <String>[];
  var scanIncomplete = false;
  for (final root in searchRoots) {
    final dir = Directory(root);
    if (!dir.existsSync()) continue;
    try {
      for (final entity in dir.listSync(recursive: true, followLinks: false)) {
        if (entity is! File) continue;
        final path = entity.path;
        if (!path.endsWith('.sqlite')) continue;
        final base = path.toLowerCase();
        if (base.contains('afterclose')) {
          candidates.add(path);
        }
      }
    } catch (e) {
      // 稽核 #14:整段 listSync(recursive) 包在一個 catch 裡,權限錯誤會
      // **中止該 root 的掃描**、留下不完整的候選清單——然後自信地對一個
      // 可能是舊的/錯的 DB 出報告。這支工具正是你懷疑資料出事時會拿來
      // 用的,那是最不該給錯答案的時刻。
      scanIncomplete = true;
      stderr.writeln('⚠️  掃描 $root 時中斷(可能是權限),候選清單可能不完整: $e');
    }
  }

  if (scanIncomplete && candidates.isNotEmpty) {
    stderr.writeln('⚠️  以下判斷基於**不完整**的候選清單');
  }
  if (candidates.isEmpty) return null;
  if (candidates.length > 1) {
    print('⚠️  偵測到多個候選，使用第一個：');
    for (final c in candidates) {
      print('   - $c');
    }
  }
  return candidates.first;
}

/// 列出所有使用者表（排除 sqlite_* 系統表與 drift 內部表）
Set<String> _listTables(Database db) {
  final rows = db.select(
    'SELECT name FROM sqlite_master '
    "WHERE type='table' "
    "AND name NOT LIKE 'sqlite_%' "
    "AND name NOT LIKE '%_drift_%'",
  );
  return rows.map((r) => r['name'] as String).toSet();
}

/// 報告單一表：筆數 + 日期範圍
void _reportTable(Database db, String table, Set<String> existingTables) {
  if (!existingTables.contains(table)) {
    print('  ⚠️  $table: (表不存在)');
    return;
  }

  try {
    final countRow = db.select('SELECT COUNT(*) AS c FROM "$table"').first;
    final count = countRow['c'] as int;

    final dateCol = _findDateColumn(db, table);
    if (dateCol == null) {
      print('  $table: ${_formatCount(count)}');
      return;
    }

    final rangeRow = db
        .select(
          'SELECT MIN("$dateCol") AS min_d, MAX("$dateCol") AS max_d FROM "$table"',
        )
        .first;
    final minD = rangeRow['min_d']?.toString() ?? '-';
    final maxD = rangeRow['max_d']?.toString() ?? '-';
    print('  $table: ${_formatCount(count)}, $minD → $maxD  (by $dateCol)');
  } catch (e) {
    print('  ❌ $table: 查詢失敗 — $e');
  }
}

String? _findDateColumn(Database db, String table) {
  final cols = db.select('PRAGMA table_info("$table")');
  final colNames = cols.map((r) => (r['name'] as String).toLowerCase()).toSet();
  for (final cand in _dateColumnCandidates) {
    if (colNames.contains(cand)) return cand;
  }
  return null;
}

/// 針對 Phase 1 最關鍵的 daily_price 做 2 年歷史 sanity check
void _checkDailyPriceCoverage(Database db, Set<String> existingTables) {
  if (!existingTables.contains('daily_price')) {
    print('  ❌ daily_price 表不存在 — 無法進行歷史盤點');
    return;
  }

  final row = db
      .select(
        'SELECT MIN(date) AS min_d, MAX(date) AS max_d, '
        'COUNT(*) AS total_rows, COUNT(DISTINCT symbol) AS stocks '
        'FROM daily_price',
      )
      .first;

  final rawMin = row['min_d'];
  final rawMax = row['max_d'];
  final totalRows = row['total_rows'] as int;
  final stocks = row['stocks'] as int;

  if (rawMin == null || rawMax == null || totalRows == 0) {
    print('  ❌ daily_price 為空');
    return;
  }

  final minDate = _parseFlexibleDate(rawMin.toString());
  final maxDate = _parseFlexibleDate(rawMax.toString());
  if (minDate == null || maxDate == null) {
    print('  ⚠️  daily_price 日期欄位格式無法解析: min=$rawMin max=$rawMax');
    return;
  }

  final days = maxDate.difference(minDate).inDays;
  final years = (days / 365).toStringAsFixed(1);

  print('  daily_price 歷史:');
  print(
    '    • 範圍: ${_formatDate(minDate)} → ${_formatDate(maxDate)} ($days 天 / 約 $years 年)',
  );
  print('    • 總筆數: ${_formatCount(totalRows)}');
  print('    • 涵蓋股票: $stocks 檔');
  if (stocks > 0) {
    final avgDays = (totalRows / stocks).toStringAsFixed(0);
    print('    • 平均每檔天數: $avgDays');
  }

  print('');
  if (days >= 730) {
    print('  ✅ 歷史 ≥ 2 年 — 可進 Phase 1（rule firing replay 有充足 sample）');
  } else if (days >= 365) {
    print('  ⚠️  歷史 1–2 年 — Phase 1 可跑，但 60D horizon 的樣本會較弱');
    print('     60D horizon 需要的資料: entry date + 60 交易日 ≈ 需多出 85 日曆日才能驗證');
  } else {
    print('  ❌ 歷史 < 1 年 — 不足以做有意義的 calibration');
    print('     建議: 先跑歷史同步補齊資料，或把 Phase 1 的 backtest window 縮短');
  }
}

/// 掃描其他「非計畫目標」的表 — 幫助我瞭解 DB 全貌
void _checkOrphanTables(Database db, Set<String> existingTables) {
  final plannedTables = <String>{};
  for (final group in _tableGroups.values) {
    plannedTables.addAll(group);
  }
  final orphans = existingTables.difference(plannedTables).toList()..sort();
  if (orphans.isEmpty) return;

  print('其他表（未納入盤點計畫，僅供參考）:');
  for (final table in orphans) {
    try {
      final count =
          db.select('SELECT COUNT(*) AS c FROM "$table"').first['c'] as int;
      print('  $table: ${_formatCount(count)}');
    } catch (e) {
      // 例外物件不能丟掉(稽核 #14):鎖住 / 損壞 / 不可查詢的 view
      // 原本收斂成同一句「查詢失敗」,而且印在 stdout
      stderr.writeln('  $table: (查詢失敗) $e');
    }
  }
}

/// [_parseFlexibleDate] 的測試出口——秒/毫秒判別與範圍守衛有真實的
/// 失效模式(2033 時間炸彈),不能只靠 CLI 端到端驗。
DateTime? parseFlexibleDateForTesting(String raw) => _parseFlexibleDate(raw);

/// 嘗試解析多種 date 字串格式（ISO、YYYY-MM-DD、Drift int timestamp）
DateTime? _parseFlexibleDate(String raw) {
  // Drift DateTimeColumn 可能存 ISO 字串或 Unix timestamp int
  final asInt = int.tryParse(raw);
  if (asInt != null) {
    // 以**位數**判別秒/毫秒,不用量級門檻(稽核 #17):原本的
    // `asInt > 2000000000` 是 2033-05-18,之後的秒級時戳會被當成毫秒
    // 解成 1970-01-24——而且是**解析成功**,「無法解析」的分支不會觸發,
    // 錯的答案直接餵進兩年充足性判定。
    final digits = raw.trim().replaceFirst('-', '').length;
    final ms = digits >= 13 ? asInt : asInt * 1000;
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    // 超出合理範圍寧可回 null 讓上游印「無法解析」,不要給錯的日期
    if (dt.year < 1990 || dt.year > 2100) return null;
    return dt;
  }
  return DateTime.tryParse(raw);
}

String _formatDate(DateTime d) {
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '${d.year}-$m-$day';
}

String _formatCount(int n) {
  // 加千分位
  final s = n.toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return '${buf.toString()} 筆';
}
