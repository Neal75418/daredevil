// recalibrate CLI 的 clustered 分流 loader 測試（sqlite3 in-memory，無 Drift）
//
// 驗證：
//   1. readRunMeta — meta 表缺失 → null；excess run → 解析 mode/threshold/baseline
//   2. loadDailyMeans — 依日期升序還原每 rule 的日均值序列

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:daredevil/core/constants/reason_type.dart';
import 'package:daredevil/domain/services/rule_registry.dart';

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
  // ── 規則涵蓋差集（2026-08-22）──────────────────────────────────
  //
  // **為什麼從「時間」改成「涵蓋」**：原本用「replay 超過 30 天」示警，但
  // 量測後那個軸是錯的——DB 有 1468 交易日，多等一個月只增 1.4% 樣本、
  // t-stat 只改善 0.71%；一條卡在 t=1.5 的規則要靠時間推過門檻得再等 4.1
  // 年。而 73 個被 cut 的規則裡 61 個是 t_stat 不足、只有 4 個是樣本不足。
  // 時間幾乎不改變任何結論。
  //
  // 真正會讓 replay 樣本失效的是**規則集變動**：新規則在舊 replay 裡一筆
  // 觸發都沒有，拿到的必然是手調分。首次跑就抓到 31/70 條無樣本，其中
  // BREAK_MA20／BREAK_MA60／RECLAIM_MA20／RECLAIM_MA60 是 2026-08 才做的
  // 四階均線階梯。
  //
  // 反方向也要抓：replay 有、註冊表已無的規則（改名或刪除）會在 candidate
  // JSON 留下永遠查不到的死列。
  group('規則涵蓋差集', () {
    test('大小寫不一致不得算成差異（DB 存大寫、rule.id 是小寫）', () {
      final c = compareRuleCoverage(
        {'break_ma20', 'week_52_high'},
        {'BREAK_MA20', 'WEEK_52_HIGH'},
      );
      expect(c.uncalibrated, isEmpty);
      expect(c.orphaned, isEmpty);
      expect(c.registrySize, 2);
    });

    test('🚨 註冊表新增的規則 → 列為未校準', () {
      final c = compareRuleCoverage(
        {'week_52_high', 'reclaim_ma20'},
        {'WEEK_52_HIGH'},
      );
      expect(c.uncalibrated, ['RECLAIM_MA20']);
      expect(c.orphaned, isEmpty);
    });

    test('🚨 註冊表已移除但樣本仍有 → 列為孤兒', () {
      final c = compareRuleCoverage(
        {'week_52_high'},
        {'WEEK_52_HIGH', 'INSTITUTIONAL_BUY'},
      );
      expect(c.uncalibrated, isEmpty);
      expect(c.orphaned, ['INSTITUTIONAL_BUY']);
    });

    test('輸出排序穩定（同一份輸入不得每次印不同順序）', () {
      final c = compareRuleCoverage({'c_rule', 'a_rule', 'b_rule'}, const {});
      expect(c.uncalibrated, ['A_RULE', 'B_RULE', 'C_RULE']);
    });

    test('replay 樣本全空（沒跑過 replay）→ 全部未校準，不是 crash', () {
      final c = compareRuleCoverage({'a_rule', 'b_rule'}, const {});
      expect(c.uncalibrated, hasLength(2));
      expect(c.registrySize, 2);
    });

    test('🚨 真實情境：本專案的四階均線規則確實無樣本', () {
      // 7/13 replay 之後才新增，rule_accuracy 列數實測為 0
      final c = compareRuleCoverage(
        {
          'break_ma20',
          'break_ma60',
          'reclaim_ma20',
          'reclaim_ma60',
          'week_52_high',
        },
        {'WEEK_52_HIGH', 'PRICE_SPIKE'},
      );
      expect(c.uncalibrated, [
        'BREAK_MA20',
        'BREAK_MA60',
        'RECLAIM_MA20',
        'RECLAIM_MA60',
      ]);
      expect(c.orphaned, ['PRICE_SPIKE']);
    });
  });

  // ── replay 落檔時間（僅背景資訊，不下判決）──────────────────────
  group('replay 落檔時間', () {
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

    test('meta 缺 generated_at（舊 DB）→ null，不假裝知道', () {
      final db = metaDb(null);
      addTearDown(db.close);
      expect(readRunMeta(db)!.generatedAt, isNull);
    });

    test('generated_at 格式壞掉 → null 而非 crash', () {
      final db = metaDb('not-a-timestamp');
      addTearDown(db.close);
      expect(readRunMeta(db)!.generatedAt, isNull);
    });

    test('年齡計算：以天為單位，未來時間戳為負數', () {
      expect(
        replayAgeInDays(DateTime.utc(2026, 7, 13), DateTime.utc(2026, 8, 22)),
        40,
      );
      expect(
        replayAgeInDays(DateTime.utc(2026, 9, 1), DateTime.utc(2026, 8, 22)),
        lessThan(0),
      );
      expect(replayAgeInDays(null, DateTime.utc(2026, 8, 22)), isNull);
    });
  });
  // ── promote 影響摘要（2026-08-22）────────────────────────────────
  //
  // **為什麼不能比 active/score**：同日先寫進 docs 的 jq 摘要就是這樣比，
  // 結果短線報「無變動」，實際有 9 條有效分數改變。`active:false, score:0`
  // 與「規則根本不在 JSON 裡」在 App 眼中完全不同——前者可能被負證據歸零
  // （lookup 回 0），後者 fallback 到 hardcoded 分。同一天 walk-forward gate
  // 也栽在這個坑（見 walkforward_validate_test.dart）。
  //
  // 所以摘要一律走 `CalibratedScoresTable.lookup`，不重寫語意。
  group('promote 影響摘要', () {
    const hard = {'BULL': 20, 'BEAR': -8, 'CAL': 99};
    String js(String rules) => '{"schema_version":1,"rules":{$rules}}';

    test('🚨 前提：JSON 真的被載入（缺 schema_version 會整份拒載）', () {
      final d = diffEffectiveScores(
        js('"CAL":{"score":30,"active":true}'),
        js('"CAL":{"score":40,"active":true}'),
        hardcodedScores: hard,
      );
      expect(d, isNotEmpty, reason: '若為空代表兩份都被拒載，測試無效');
    });

    test('🚨 「缺席 → 被 cut」不是無變動（jq 版漏掉的正是這個）', () {
      final d = diffEffectiveScores(
        js('"CAL":{"score":30,"active":true}'),
        js(
          '"CAL":{"score":30,"active":true},'
          '"BULL":{"score":0,"active":false,"cut_reason":"t",'
          '"avg_return":-0.5,"t_stat":-6.0}',
        ),
        hardcodedScores: hard,
        applyZeroing: true,
      );
      expect(d.map((e) => e.ruleId), contains('BULL'));
      final b = d.firstWhere((e) => e.ruleId == 'BULL');
      expect(b.before, 20, reason: '缺席 → fallback 手調 20');
      expect(b.after, 0, reason: '被 cut 且有負證據 → 歸零');
    });

    test('active 分數變動照樣列出', () {
      final d = diffEffectiveScores(
        js('"CAL":{"score":30,"active":true}'),
        js('"CAL":{"score":40,"active":true}'),
        hardcodedScores: hard,
      );
      final c = d.single;
      expect(c.ruleId, 'CAL');
      expect(c.before, 30);
      expect(c.after, 40);
    });

    test('真的沒變就是空清單', () {
      final same = js('"CAL":{"score":30,"active":true}');
      expect(diffEffectiveScores(same, same, hardcodedScores: hard), isEmpty);
    });

    test('輸出依 ruleId 排序（同輸入不得每次印不同順序）', () {
      final d = diffEffectiveScores(
        js('"CAL":{"score":1,"active":true},"BULL":{"score":1,"active":true}'),
        js('"CAL":{"score":2,"active":true},"BULL":{"score":2,"active":true}'),
        hardcodedScores: hard,
      );
      expect(d.map((e) => e.ruleId).toList(), ['BULL', 'CAL']);
    });
  });
  // ── 命名空間必須對齊（2026-08-22 二次修正）─────────────────────────
  //
  // 首版 `compareRuleCoverage` 拿 `RuleRegistry.defaultRules.map((r) => r.id)`
  // 去比 `rule_accuracy.rule_id`，但那是**兩個不同的命名空間**：
  //   - rule.id：`pattern_doji`、`institutional_shift`（規則自己的識別碼）
  //   - rule_accuracy.rule_id：`PATTERN_DOJI_BEARISH`、`INSTITUTIONAL_BUY`
  //     （replay 依 **ReasonType code** 記錄觸發）
  // 一條規則可依情境發出不同的 ReasonType（`pattern_doji` 會發
  // `patternDoji` 或 `patternDojiBearish`），兩者本來就不是一對一。
  //
  // 後果：把 3 個正常運作的 ReasonType 誤報成「已不在註冊表的死列」，
  // 未校準數也多算 1 條。用真實的 ReasonType 集合斷言，合成 ID 測不出來。
  group('涵蓋差集的命名空間', () {
    test('🚨 真實 ReasonType 與 replay 樣本不得出現孤兒', () {
      final codes = ReasonType.values.map((r) => r.code.toUpperCase()).toSet();
      // 這三個曾被誤報為孤兒——它們是 pattern_doji / 法人規則依情境發出的
      for (final c in [
        'PATTERN_DOJI_BEARISH',
        'INSTITUTIONAL_BUY',
        'INSTITUTIONAL_SELL',
      ]) {
        expect(codes, contains(c), reason: '$c 是有效的 ReasonType，不得被當成死列');
      }
    });

    test('🚨 rule.id 與 ReasonType.code 確實是不同集合（比錯會誤報）', () {
      final ruleIds = RuleRegistry.defaultRules
          .map((r) => r.id.toUpperCase())
          .toSet();
      final codes = ReasonType.values.map((r) => r.code.toUpperCase()).toSet();
      expect(
        ruleIds.difference(codes),
        isNotEmpty,
        reason: '若兩者相同，這條測試與整個修正就沒有意義了',
      );
    });

    test('🚨 涵蓋檢查取的必須是 ReasonType code,不是 rule.id', () {
      // 這是首版真正的錯處:呼叫端餵了 RuleRegistry 的 rule.id。
      // 純集合函式對命名空間無感,所以要在「取哪個集合」這一步斷言。
      final codes = coverageReferenceIds();
      expect(codes, contains('PATTERN_DOJI_BEARISH'));
      expect(codes, contains('INSTITUTIONAL_BUY'));
      expect(
        codes.length,
        ReasonType.values.length,
        reason: 'ReasonType 全集;若等於 RuleRegistry.defaultRules.length 就是又比錯了',
      );
    });

    test('compareRuleCoverage 的輸入應為 ReasonType code 集合', () {
      final c = compareRuleCoverage(
        {'pattern_doji_bearish', 'institutional_buy'},
        {'PATTERN_DOJI_BEARISH', 'INSTITUTIONAL_BUY'},
      );
      expect(c.orphaned, isEmpty);
      expect(c.uncalibrated, isEmpty);
    });
  });
}
