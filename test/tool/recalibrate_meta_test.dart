// recalibrate CLI 的 clustered 分流 loader 測試（sqlite3 in-memory，無 Drift）
//
// 驗證：
//   1. readRunMeta — meta 表缺失 → null；excess run → 解析 mode/threshold/baseline
//   2. loadDailyMeans — 依日期升序還原每 rule 的日均值序列

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import '../../tool/recalibrate.dart';

void main() {
  group('readRunMeta', () {
    test('calibration_run_meta 表不存在（舊 DB）→ null', () {
      final db = sqlite3.openInMemory();
      addTearDown(db.close);
      expect(readRunMeta(db), isNull);
    });

    test('excess run → 解析 mode / threshold / 兩個 baseline', () {
      final db = sqlite3.openInMemory();
      addTearDown(db.close);
      db.execute(
        'CREATE TABLE calibration_run_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
      );
      db.execute(
        "INSERT INTO calibration_run_meta VALUES ('return_mode', 'excess')",
      );
      db.execute(
        "INSERT INTO calibration_run_meta VALUES ('excess_success_threshold', '0.0')",
      );
      db.execute(
        "INSERT INTO calibration_run_meta VALUES ('universe_baseline_hit_5d', '0.4712')",
      );
      db.execute(
        "INSERT INTO calibration_run_meta VALUES ('universe_baseline_hit_60d', '0.4525')",
      );

      final meta = readRunMeta(db);
      expect(meta, isNotNull);
      expect(meta!.returnMode, 'excess');
      expect(meta.isExcess, isTrue);
      expect(meta.excessThreshold, 0.0);
      expect(meta.baselineHit5, closeTo(0.4712, 1e-9));
      expect(meta.baselineHit60, closeTo(0.4525, 1e-9));
    });

    test('absolute run → isExcess false、baseline null', () {
      final db = sqlite3.openInMemory();
      addTearDown(db.close);
      db.execute(
        'CREATE TABLE calibration_run_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
      );
      db.execute(
        "INSERT INTO calibration_run_meta VALUES ('return_mode', 'absolute')",
      );

      final meta = readRunMeta(db);
      expect(meta!.isExcess, isFalse);
      expect(meta.baselineHit5, isNull);
      expect(meta.baselineHit60, isNull);
    });
  });

  group('loadDailyMeans', () {
    test('依日期升序、按 period 過濾、多 rule 分組', () {
      final db = sqlite3.openInMemory();
      addTearDown(db.close);
      db.execute('''
        CREATE TABLE rule_daily_stats (
          rule_id TEXT NOT NULL, period TEXT NOT NULL, date TEXT NOT NULL,
          n INTEGER NOT NULL, mean_return REAL NOT NULL,
          PRIMARY KEY (rule_id, period, date))''');
      // 亂序插入 → 讀出必須升序
      db.execute(
        "INSERT INTO rule_daily_stats VALUES ('R1', '5D', '2025-01-03', 2, 3.0)",
      );
      db.execute(
        "INSERT INTO rule_daily_stats VALUES ('R1', '5D', '2025-01-01', 5, 1.0)",
      );
      db.execute(
        "INSERT INTO rule_daily_stats VALUES ('R1', '60D', '2025-01-01', 5, 9.9)",
      );
      db.execute(
        "INSERT INTO rule_daily_stats VALUES ('R2', '5D', '2025-01-02', 1, -0.5)",
      );

      final means = loadDailyMeans(db, '5D');
      expect(means['R1'], [1.0, 3.0]); // 升序，60D 那筆不混入
      expect(means['R2'], [-0.5]);
      expect(means.containsKey('R3'), isFalse);
    });

    test('rule_daily_stats 表不存在（舊 DB）→ 空 map', () {
      final db = sqlite3.openInMemory();
      addTearDown(db.close);
      expect(loadDailyMeans(db, '5D'), isEmpty);
    });
  });
  // ── replay 陳舊警告（2026-08-22）─────────────────────────────────
  //
  // **問題形狀**：`scripts/calibrate.sh` 串 backfill→replay→recalibrate 三
  // 階段，但 `docs/CALIBRATION.md` 只教手動跑第三階段。照文件走會拿**舊的
  // replay 結果**重算分數，而 exit code 0、candidate JSON 正常產出、無任何
  // 異常——與 CLAUDE.md 記載的 launchd CLI 落後是同一類 bug（產物過期但
  // 三個訊號全正常），也用同一種解法：把時間戳印出來。
  //
  // `calibration_run_meta.generated_at` 一直都在表裡，只是 `RunMeta` 沒取。
  group('replay 陳舊判定', () {
    Database metaDb(String? generatedAt) {
      final db = sqlite3.openInMemory();
      db.execute(
        'CREATE TABLE calibration_run_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
      );
      db.execute(
        "INSERT INTO calibration_run_meta VALUES ('return_mode', 'excess')",
      );
      if (generatedAt != null) {
        db.execute(
          "INSERT INTO calibration_run_meta VALUES ('generated_at', '$generatedAt')",
        );
      }
      return db;
    }

    test('readRunMeta 解析 generated_at（UTC）', () {
      final db = metaDb('2026-07-13T02:13:42.224620Z');
      addTearDown(db.close);

      final at = readRunMeta(db)!.generatedAt;
      expect(at, isNotNull);
      expect(at!.isUtc, isTrue, reason: '落庫是 UTC，比較前不得被當成本地時間');
      expect(at, DateTime.utc(2026, 7, 13, 2, 13, 42, 224, 620));
    });

    test('meta 缺 generated_at（舊 DB）→ null，不假裝新鮮', () {
      final db = metaDb(null);
      addTearDown(db.close);
      expect(readRunMeta(db)!.generatedAt, isNull);
    });

    test('generated_at 格式壞掉 → null 而非 crash', () {
      final db = metaDb('not-a-timestamp');
      addTearDown(db.close);
      expect(readRunMeta(db)!.generatedAt, isNull);
    });

    test('無時間戳 → 無判定（不知道就不下結論）', () {
      expect(classifyReplayAge(null, DateTime.utc(2026, 8, 22)), isNull);
    });

    test('當天跑完 → 0 天、不陳舊', () {
      final age = classifyReplayAge(
        DateTime.utc(2026, 8, 22, 2),
        DateTime.utc(2026, 8, 22, 10),
      )!;
      expect(age.days, 0);
      expect(age.isStale, isFalse);
    });

    test('邊界：剛好 30 天不警告、31 天才警告', () {
      final base = DateTime.utc(2026, 7, 1);
      expect(
        classifyReplayAge(base, base.add(const Duration(days: 30)))!.isStale,
        isFalse,
      );
      expect(
        classifyReplayAge(base, base.add(const Duration(days: 31)))!.isStale,
        isTrue,
      );
    });

    test('🚨 7/13 那份資料在今天確實會觸發警告（真實情境）', () {
      final age = classifyReplayAge(
        DateTime.utc(2026, 7, 13, 2, 13, 42),
        DateTime.utc(2026, 8, 22),
      )!;
      expect(age.days, 39);
      expect(age.isStale, isTrue);
    });

    test('時鐘偏移導致時間戳在未來 → 不誤報陳舊', () {
      final age = classifyReplayAge(
        DateTime.utc(2026, 9, 1),
        DateTime.utc(2026, 8, 22),
      )!;
      expect(age.days, lessThan(0));
      expect(age.isStale, isFalse, reason: '未來時間是時鐘問題，不是資料過期');
    });
  });
}
