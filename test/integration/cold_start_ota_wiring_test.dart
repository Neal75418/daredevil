// L3 regression — cold-start OTA calibration wiring
//
// Stage 5a OTA 的 cold-start 路徑由 3 個元件接力組成：
//   CalibrationCacheDao.writeCalibration   ← Updater 寫 DB cache
//   AppDatabase.getCachedCalibration       ← main.dart 讀 cache
//   CalibratedScoresRegistry.loadWithOverride ← 喂進 registry
// 每個元件都有 unit test，但「三段接得起來、cache 真的會傳遞到
// `registry.lookup`」這條 end-to-end 假設一直沒有 integration test 守著。
// 這個檔案補上：寫一份 OTA JSON 進 DB，cold-start 路徑走完後 lookup 應
// 回 OTA 值，而不是 hardcoded fallback。
//
// 也順帶覆蓋一個 fallback 邊界：
//   - DB cache 半成品（only short）→ loadWithOverride 走 asset 路徑（本測試
//     把 asset 讀取換成會拋錯的替身，所以是 empty）

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/constants/calibrated_scores/calibrated_scores_registry.dart';
import 'package:daredevil/core/constants/calibrated_scores/horizon.dart';
import 'package:daredevil/core/constants/reason_type.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/data/database/dao/calibration_cache_dao.dart';

const _shortJsonOta = '''
{
  "schema_version": 1,
  "horizon": "5d",
  "rules": {
    "TECH_BREAKOUT": {"score": 33},
    "VOLUME_SPIKE": {"score": 28}
  }
}
''';

const _longJsonOta = '''
{
  "schema_version": 1,
  "horizon": "60d",
  "rules": {
    "TECH_BREAKOUT": {"score": 22},
    "VOLUME_SPIKE": {"score": 18}
  }
}
''';

void main() {
  late AppDatabase db;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    // C 方案 refactor 2026-06-19：registry 不再直接 import rootBundle，
    // test 顯式注入 loader（half-state fallback test 會 hit loader）。
    CalibratedScoresRegistry.instance.assetLoaderOverride =
        rootBundle.loadString;
  });

  setUp(() {
    db = AppDatabase.forTesting();
    CalibratedScoresRegistry.instance.resetForTesting();
  });

  tearDown(() async {
    CalibratedScoresRegistry.instance.resetForTesting();
    await db.close();
  });

  group('cold-start OTA wiring (CalibrationUpdater → DB → registry.lookup)', () {
    test(
      'OTA JSON written via writeCalibration surfaces in registry.lookup',
      () async {
        // 1. Updater 把 OTA JSON 寫進 DB cache（模擬 cold-start 前一次成功 fetch）
        await db.writeCalibration(
          version: '2026-06-01',
          shortJson: _shortJsonOta,
          longJson: _longJsonOta,
          shortHash: 'deadbeef-short',
          longHash: 'deadbeef-long',
          checkedAt: DateTime.utc(2026, 6, 1, 9, 0, 0),
        );

        // 2. main.dart cold-start 路徑：讀 DB cache → 餵 registry
        final cached = await db.getCachedCalibration();
        await CalibratedScoresRegistry.instance.loadWithOverride(
          shortJsonOverride: cached.shortJson,
          longJsonOverride: cached.longJson,
          knownRuleIds: ReasonType.values.map((r) => r.code).toSet(),
          hardcodedScores: {for (final r in ReasonType.values) r.code: r.score},
        );

        // 3. registry.lookup 應該回 OTA JSON 內的值，而不是 hardcoded fallback
        expect(
          CalibratedScoresRegistry.instance.lookup(
            Horizon.short,
            'TECH_BREAKOUT',
          ),
          33,
          reason: 'short OTA value for TECH_BREAKOUT should reach registry',
        );
        expect(
          CalibratedScoresRegistry.instance.lookup(
            Horizon.long,
            'TECH_BREAKOUT',
          ),
          22,
          reason: 'long OTA value for TECH_BREAKOUT should reach registry',
        );
        expect(
          CalibratedScoresRegistry.instance.lookup(
            Horizon.short,
            'VOLUME_SPIKE',
          ),
          28,
        );
        expect(
          CalibratedScoresRegistry.instance.lookup(
            Horizon.long,
            'VOLUME_SPIKE',
          ),
          18,
        );
      },
    );

    test(
      'half-state cache (only short present) does NOT override; lookup is null',
      () async {
        // 模擬髒資料：DB 有 short 但 long 缺。`loadWithOverride` 應該直接走
        // asset fallback。本 test 顯式把 assetLoaderOverride 換成「always
        // 拋 FileSystemException」stub 模擬「test 環境沒 bundled asset」
        // 的狀態 — registry 會回 empty table，lookup 一律 null。
        //
        // C 方案 refactor 2026-06-19 後 setUpAll 注入了真 rootBundle，會
        // 成功載到 bundled JSON，本 test 必須個別 override。
        CalibratedScoresRegistry.instance.assetLoaderOverride = (path) async {
          throw StateError('test stub: no assets available');
        };

        final cached = CachedCalibration(
          version: '2026-06-01',
          shortJson: _shortJsonOta,
          longJson: null,
          shortHash: 'deadbeef-short',
          longHash: null,
          lastCheckedAt: DateTime.utc(2026, 6, 1, 9, 0, 0),
        );

        await CalibratedScoresRegistry.instance.loadWithOverride(
          shortJsonOverride: cached.shortJson,
          longJsonOverride: cached.longJson,
          knownRuleIds: ReasonType.values.map((r) => r.code).toSet(),
          hardcodedScores: {for (final r in ReasonType.values) r.code: r.score},
        );

        // half-state → asset fallback → test 環境 asset bundle 不可用 →
        // empty table → lookup 回 null。
        expect(
          CalibratedScoresRegistry.instance.lookup(
            Horizon.short,
            'TECH_BREAKOUT',
          ),
          isNull,
          reason:
              'half-state cache must not bind half a horizon — '
              'short OTA value must NOT leak through',
        );
      },
    );
  });
}
