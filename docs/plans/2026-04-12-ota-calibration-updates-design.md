# OTA Calibration Updates — jsDelivr CDN 無版本發布的校準資料更新

> ⚠️ **三處已與實作不符，照抄會出錯：**
> 1. 所有 jsDelivr URL 寫 `gh/Neal75418/afterclose`，**實際是 `daredevil`**——
>    照抄會 404。以 `lib/data/network/calibration_updater.dart` 為準。
> 2. §2 Q3／§3.4／§4.2 的「AppSettings 加 6 個 nullable columns」**被推翻**：
>    實作走既有 key-value 表加 `calibration.` 前綴，刻意避開 schema 變更
>    （`lib/data/database/dao/calibration_cache_dao.dart`）。
> 3. §3.7／§4.2 的 `loadWithFallback` 已改名為 `loadWithOverride` 且依賴方向
>    反轉（2026-06-19 純 Dart 化重構）。
>
> 仍有效且不可從 code 還原的是：§2 各項被否決的替代方案、§7.3 的三層 rollback
> 階梯、§7.4／§7.5 首次啟動與離線行為。

**Date**: 2026-04-12
**Scope**: Over-The-Air 校準資料更新 — 讓 `tool/recalibrate.dart` 產出的新 calibration 能在不發 app 版本的前提下送到所有用戶
**Status**: Design locked via `/brainstorming` (Q1-Q7), ready for implementation
**Related**: [Stage 3+4 design](2026-04-12-stage3-4-design.md), [Stage 5a runtime loader design](2026-04-11-stage5a-runtime-loader-design.md), [`calibrated_scores_registry.dart`](../../lib/core/constants/calibrated_scores/calibrated_scores_registry.dart), [`tool/recalibrate.dart`](../../tool/recalibrate.dart)

---

## 1. Context & Motivation

Stage 5a 建立的 `CalibratedScoresRegistry` 目前從 `assets/rule_scores_calibrated_{short,long}.json` 載入 bundled asset。Stage 3+4 完成後，每次跑 `./scripts/calibrate.sh` → review candidate → rename 成 production JSON → **必須重 build app 並透過 store 發新版，用戶才能拿到新的校準資料**。

這對 AfterClose 這種 monthly recalibrate 節奏非常痛：
- 每個月發 app 版只為了更新一個 JSON 檔 → store review cycle 拖累節奏、增加出包風險
- 用戶不一定即時更新 app → 可能連續數個月跑在過期的 calibration
- 若某次 recalibrate 修 critical bug（例如某 rule 分數算錯），bug fix 跟著 store review 一起塞車

**OTA 目標**：讓 recalibrate pipeline 產出的新 JSON 透過 CDN 直送用戶端，在下次 cold start 時無感生效，完全脫離 app release cycle。

### 為什麼現在就做（而不是上線後再補）

1. **Architecture-level 決策** — OTA 牽涉 network / persistence / bootstrap 三層，上線後補會要動既有的冷啟動路徑，有 regression 風險
2. **Cold start 路徑本來就要改** — Q3 決定用 AppSettings Drift row 存 cached JSON，無論如何 `CalibratedScoresRegistry.loadFromAssets` 都要改成 `loadWithFallback(appSettingsDao)`。現在一起做比上線後動刀便宜
3. **Pre-launch = schemaVersion 還在 1** — 加 AppSettings 欄位不用寫 migration，post-launch 就要
4. **Stage 3+4 的 review workflow 已經設計成「人工 gate + candidate JSON」** — OTA 只是把「通過 review 的 JSON」的最後一哩從 `git commit + app release` 換成 `git commit + push → jsDelivr 自動 mirror`，其他 workflow 不動

### 明確 out of scope

- **Emergency hotfix channel** — OTA 設計的是 routine monthly update。若 calibration 真有 critical bug 到要小時級處理，仍應走 app hotfix release。理由：OTA 有 24h gate + self-healing retry，不保證即時性
- **Signed payload / integrity trust chain** — jsDelivr 走 HTTPS + SHA-256 content hash 足夠防中間人與 CDN cache 中毒。TLS 之外不做程式碼簽章
- **Rollback UI** — 用戶端不提供「回到上一版 calibration」的操作。若需 rollback，做在 developer 端：把舊版 JSON + hash 重新 push 到 manifest
- **多 channel / 分群部署** — 所有用戶吃同一個 manifest。A/B test 或 canary rollout 是 Stage 6+ 的決策
- **Telemetry 集中回報** — fetch 結果先寫 local log + Sentry transient error，不自建 metrics endpoint

---

## 2. Locked Decisions

Seven questions were resolved during brainstorming (2026-04-12):

| # | Question | Decision | Rationale |
|---|---|---|---|
| Q1 | 分發架構 | **乙** — Manifest + versioned JSONs on jsDelivr | Atomic update（manifest 是 single source of truth）、CDN cache 友善（版本號在檔名）、rollback 容易（改 manifest 指回舊版即可） |
| Q2 | 觸發時機 | **C** — Non-blocking + 24h interval gate | Zero UX friction、~1 req/user/day 流量極省、24h 延遲對月頻 calibration 無感、self-healing（下次 cold start 會重試）、D（background cron）屬 premature optimization |
| Q3 | Cache 存哪 | **甲** — AppSettings Drift row | Drift transaction 保證 atomic、cold start 單點 read 無額外 I/O、測試 in-memory Drift 就能 cover、跟既有架構一致（其他 persistent state 都走 Drift）、schemaVersion 仍停在 1（pre-launch） |
| Q4 | Version 比對 | **C** — Hash 比對（SHA-256 per JSON） | 內容定義「是否需要更新」、integrity check 免費附贈、rollback 與同日多跑 edge case 天然支援、比 A 多 ~30 行但換到完全正確的語意 |
| Q5 | Hot swap 語義 | **B** — Deferred swap（下次 cold start 才生效） | Session 穩定性 > 新鮮度、calibration 本質是月頻慢變數、實作最簡（不用 invalidate Riverpod provider）、符合「同 session 內推薦排序穩定」的 UX 原則 |
| Q6 | 失敗處理 | **C** — 分類失敗（transient vs permanent） | Permanent 失敗（hash mismatch / parse error）標記 `lastCheckedAt` 避免 24h loop 無止境重撞、transient 失敗（網路 / 5xx）**不**動 `lastCheckedAt` 讓下次 tick 早點重試、telemetry friendly |
| Q7 | 整合點 | **A** — `main.dart` fire-and-forget | 分層乾淨（OTA 是 app-level concern 不是 feature-level）、測試好控制（widget test 永遠不打網路）、zero 重複呼叫、一行程式碼 |

---

## 3. Architecture

### 3.1 End-to-end flow

```
┌──────────────────────────────────────────────────────────────────┐
│ Developer machine (monthly)                                       │
│                                                                   │
│   export FINMIND_TOKEN=...                                        │
│   ./scripts/calibrate.sh                                          │
│     └─ backfill → replay → recalibrate                            │
│          └─ produces:                                             │
│             assets/rule_scores_calibrated_short_YYYY-MM-DD.json   │
│             assets/rule_scores_calibrated_long_YYYY-MM-DD.json    │
│             assets/calibration_manifest.json                      │
│                { version, short_url, long_url,                    │
│                  short_sha256, long_sha256, generated_at }        │
│                                                                   │
│   Human review → git commit → git push origin main                │
└──────────────────────────────────────────────────────────────────┘
                         │
                         ▼
┌──────────────────────────────────────────────────────────────────┐
│ jsDelivr CDN (auto-mirrors GitHub raw, no config needed)          │
│                                                                   │
│   cdn.jsdelivr.net/gh/Neal75418/afterclose@main/assets/           │
│     ├── calibration_manifest.json                                 │
│     ├── rule_scores_calibrated_short_2026-04-12.json              │
│     └── rule_scores_calibrated_long_2026-04-12.json               │
└──────────────────────────────────────────────────────────────────┘
                         │
                         ▼
┌──────────────────────────────────────────────────────────────────┐
│ AfterClose app (every cold start)                                 │
│                                                                   │
│ Phase 1 — Bootstrap (main.dart)                                   │
│   1. WidgetsFlutterBinding.ensureInitialized()                    │
│   2. container = ProviderContainer()                              │
│   3. CalibratedScoresRegistry.loadWithFallback(                   │
│        appSettingsDao: container.read(appSettingsDaoProvider),    │
│        knownRuleIds: ReasonType.values.map((r) => r.code).toSet() │
│      )                                                            │
│      ├─ try AppSettings DB row first (last OTA fetch)             │
│      ├─ if empty / parse fails → fall back to bundled asset       │
│      └─ if asset also fails → empty table (hardcoded fallback)    │
│   4. runApp(...)                                                  │
│                                                                   │
│ Phase 2 — Background OTA check (fire-and-forget)                  │
│   5. unawaited(                                                   │
│        container.read(calibrationUpdaterProvider)                 │
│                 .checkAndUpdate()                                 │
│      )                                                            │
│                                                                   │
│      Inside checkAndUpdate():                                     │
│        a. read AppSettings.calibrationLastCheckedAt               │
│        b. if now - lastCheckedAt < 24h → return UpToDate          │
│        c. fetch manifest from jsDelivr                            │
│        d. if manifest.shortHash == cached.shortHash AND           │
│              manifest.longHash == cached.longHash:                │
│             update lastCheckedAt → return UpToDate                │
│        e. fetch short + long JSON (parallel)                      │
│        f. verify SHA-256 of each JSON == manifest hash            │
│           └─ mismatch → PermanentFailure(hash_mismatch)           │
│        g. parse both JSONs into CalibratedScoresTable             │
│           └─ parse fail → PermanentFailure(parse_error)           │
│        h. write to AppSettings in one Drift transaction:          │
│             calibrationVersion = manifest.version                 │
│             calibrationShortJson = raw short JSON string          │
│             calibrationLongJson = raw long JSON string            │
│             calibrationShortHash = manifest.shortHash             │
│             calibrationLongHash = manifest.longHash               │
│             calibrationLastCheckedAt = now                        │
│        i. return Success(manifest.version)                        │
│                                                                   │
│   ⚠️ Current session CONTINUES to use the OLD                     │
│      CalibratedScoresRegistry — new data takes effect only on     │
│      NEXT cold start (Q5 = B, Deferred swap)                      │
└──────────────────────────────────────────────────────────────────┘
```

### 3.2 Fallback chain (冷啟動讀 calibration 的優先順序)

```
1. AppSettings Drift row  ← last successful OTA fetch (最新)
   │
   ├─ row exists AND JSON parses AND hash matches stored hash → USE
   │
   └─ 任一條件失敗 → fall through
       │
       ▼
2. Bundled asset (assets/rule_scores_calibrated_{short,long}.json)
   │  ← 最後一次 release 時 commit 進 repo 的 JSON
   │
   ├─ asset exists AND JSON parses → USE
   │
   └─ asset 缺失或 JSON malformed → fall through
       │
       ▼
3. Empty CalibratedScoresTable
   │
   └─ 所有 lookup 回 null → rule_engine 用 hardcoded RuleScores constants
```

三層 fallback 的設計意圖：
- **第 1 層**給 OTA update 用，是 happy path
- **第 2 層**給初次安裝 / OTA 還沒成功過的用戶用，也是所有既有 Stage 5a 測試依賴的路徑
- **第 3 層**是最後保底 —— 就算所有 JSON 都爛掉，app 仍能跑，只是回到 pre-calibration 的分數

---

### 3.3 Manifest schema

`assets/calibration_manifest.json`（由 `tool/recalibrate.dart` 產出，跟兩個 horizon JSON 一起 commit）：

```json
{
  "version": "2026-04-12",
  "generated_at": "2026-04-12T14:32:18+08:00",
  "short": {
    "url": "https://cdn.jsdelivr.net/gh/Neal75418/afterclose@main/assets/rule_scores_calibrated_short_2026-04-12.json",
    "sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
    "rule_count": 58
  },
  "long": {
    "url": "https://cdn.jsdelivr.net/gh/Neal75418/afterclose@main/assets/rule_scores_calibrated_long_2026-04-12.json",
    "sha256": "a665a45920422f9d417e4867efdc4fb8a04a1f3fff1fa07e998e86f7f7a27ae3",
    "rule_count": 61
  },
  "minimum_app_version": "1.0.0"
}
```

欄位語意：
- `version` —— human-readable 日期 tag，僅用於 logging / debug UI / telemetry。**不**參與比對邏輯（Q4 = C，比對走 hash）
- `generated_at` —— ISO 8601 with timezone，給人看的
- `short.url` / `long.url` —— jsDelivr 絕對 URL，讓 client 不用組 URL template
- `short.sha256` / `long.sha256` —— SHA-256 of raw JSON file bytes，比對 + integrity check 都靠這個
- `short.rule_count` / `long.rule_count` —— sanity check + debug 用。Client 可以在 parse 完後對照
- `minimum_app_version` —— 若未來某次 recalibrate 依賴新 rule 定義（例如 ReasonType 新增），這個欄位讓舊版 app 跳過 fetch。**Client 目前版本**（`1.0.0`）以下都會吃；未來可用

### 3.4 AppSettings schema 擴充

`lib/data/database/tables/app_settings.dart` 新增六個欄位（全部 nullable，讓首次啟動時 row 無內容的情況自然 fall through）：

```dart
// OTA calibration cache (Stage 4+ OTA)
TextColumn get calibrationVersion => text().nullable()();
TextColumn get calibrationShortJson => text().nullable()();
TextColumn get calibrationLongJson => text().nullable()();
TextColumn get calibrationShortHash => text().nullable()();
TextColumn get calibrationLongHash => text().nullable()();
DateTimeColumn get calibrationLastCheckedAt => dateTime().nullable()();
```

對應 DAO method（`app_settings_dao.dart`）：

```dart
/// 讀取當前 cached calibration 狀態（cold start 用）
Future<CachedCalibration?> getCachedCalibration() { ... }

/// Atomic write — 寫入一組完整的 calibration 到 AppSettings
/// 在 single transaction 內更新六個欄位
Future<void> writeCalibration({
  required String version,
  required String shortJson,
  required String longJson,
  required String shortHash,
  required String longHash,
  required DateTime checkedAt,
}) { ... }

/// 只更新 lastCheckedAt（UpToDate / PermanentFailure 時用）
/// Transient 失敗不呼叫此 method，讓下次 tick 早點重試
Future<void> touchCalibrationLastCheckedAt(DateTime now) { ... }
```

### 3.5 CalibrationUpdater service

`lib/data/network/calibration_updater.dart`：

```dart
class CalibrationUpdater {
  CalibrationUpdater({
    required http.Client httpClient,
    required AppSettingsDao appSettingsDao,
    required Clock clock,  // testability: inject DateTime.now() source
    required Logger logger,
    this.manifestUrl = _defaultManifestUrl,
    this.checkInterval = const Duration(hours: 24),
  });

  static const _defaultManifestUrl =
      'https://cdn.jsdelivr.net/gh/Neal75418/afterclose@main/assets/calibration_manifest.json';

  /// 主入口 — 由 main.dart unawaited 呼叫
  Future<CalibrationFetchResult> checkAndUpdate() async {
    try {
      final cached = await _appSettingsDao.getCachedCalibration();
      final now = _clock.now();

      // 24h gate
      if (cached?.lastCheckedAt != null &&
          now.difference(cached!.lastCheckedAt!) < checkInterval) {
        return const CalibrationFetchResult.upToDate(reason: 'within_24h_gate');
      }

      // Fetch manifest
      final manifest = await _fetchManifest();

      // Hash compare (Q4 = C)
      if (manifest.shortHash == cached?.shortHash &&
          manifest.longHash == cached?.longHash) {
        await _appSettingsDao.touchCalibrationLastCheckedAt(now);
        return CalibrationFetchResult.upToDate(reason: 'hash_match_${manifest.version}');
      }

      // Fetch both JSONs in parallel
      final (shortJson, longJson) = await (
        _fetchJson(manifest.shortUrl),
        _fetchJson(manifest.longUrl),
      ).wait;

      // Verify integrity (Q4 = C)
      final shortActualHash = sha256.convert(utf8.encode(shortJson)).toString();
      final longActualHash = sha256.convert(utf8.encode(longJson)).toString();
      if (shortActualHash != manifest.shortHash || longActualHash != manifest.longHash) {
        await _appSettingsDao.touchCalibrationLastCheckedAt(now);  // permanent → avoid tight loop
        return const CalibrationFetchResult.permanentFailure(reason: 'hash_mismatch');
      }

      // Parse sanity check (fail fast if malformed)
      try {
        CalibratedScoresTable.fromJsonString(shortJson);
        CalibratedScoresTable.fromJsonString(longJson);
      } on FormatException catch (e) {
        await _appSettingsDao.touchCalibrationLastCheckedAt(now);  // permanent
        return CalibrationFetchResult.permanentFailure(reason: 'parse_error: ${e.message}');
      }

      // Atomic write (Q3 = 甲)
      await _appSettingsDao.writeCalibration(
        version: manifest.version,
        shortJson: shortJson,
        longJson: longJson,
        shortHash: manifest.shortHash,
        longHash: manifest.longHash,
        checkedAt: now,
      );

      return CalibrationFetchResult.success(version: manifest.version);

    } on SocketException catch (e) {
      return CalibrationFetchResult.transientFailure(cause: 'network: $e');
    } on TimeoutException catch (e) {
      return CalibrationFetchResult.transientFailure(cause: 'timeout: $e');
    } on http.ClientException catch (e) {
      return CalibrationFetchResult.transientFailure(cause: 'http: $e');
    } on FormatException catch (e) {
      // Manifest parse fail → permanent, but do touch lastCheckedAt
      await _appSettingsDao.touchCalibrationLastCheckedAt(_clock.now());
      return CalibrationFetchResult.permanentFailure(reason: 'manifest_parse: ${e.message}');
    } catch (e, st) {
      _logger.error('CalibrationUpdater', 'unexpected error', e, st);
      return CalibrationFetchResult.transientFailure(cause: 'unexpected: $e');
    }
  }
}
```

### 3.6 Sealed result type

`lib/data/network/calibration_fetch_result.dart`：

```dart
sealed class CalibrationFetchResult {
  const CalibrationFetchResult();

  const factory CalibrationFetchResult.success({required String version}) = _Success;
  const factory CalibrationFetchResult.upToDate({required String reason}) = _UpToDate;
  const factory CalibrationFetchResult.transientFailure({required String cause}) = _TransientFailure;
  const factory CalibrationFetchResult.permanentFailure({required String reason}) = _PermanentFailure;
}

class _Success extends CalibrationFetchResult { ... }
class _UpToDate extends CalibrationFetchResult { ... }
class _TransientFailure extends CalibrationFetchResult { ... }
class _PermanentFailure extends CalibrationFetchResult { ... }
```

失敗分類對照（Q6 = C）：

| Category    | Cases                                                      | `touch lastCheckedAt`? | Retry timing        |
|:------------|:-----------------------------------------------------------|:-----------------------|:--------------------|
| `Success`   | 正常流程                                                    | ✅ (via writeCalibration) | next 24h tick       |
| `UpToDate`  | 24h gate skip / hash match                                 | ✅                       | next 24h tick       |
| `Transient` | SocketException / TimeoutException / http.ClientException | ❌                       | next cold start     |
| `Permanent` | hash mismatch / JSON parse fail / manifest malformed      | ✅                       | next 24h tick       |

**關鍵設計**：`Transient` 不 touch `lastCheckedAt` 的用意是「用戶剛才可能在地鐵裡 / 換網路 / CDN 5xx」，下次 cold start（可能幾分鐘後）就重試；`Permanent` 必須 touch 避免每次 24h 都重撞同個壞掉的 manifest、浪費流量。

### 3.7 main.dart 整合

現有 `_runApp(container)`（[lib/main.dart:72](../../lib/main.dart#L72)）會 await `CalibratedScoresRegistry.instance.loadFromAssets(...)`。這段換成 `loadWithFallback`：

```dart
// BEFORE (Stage 5a)
await CalibratedScoresRegistry.instance.loadFromAssets(
  knownRuleIds: ReasonType.values.map((r) => r.code).toSet(),
);

// AFTER (OTA)
await CalibratedScoresRegistry.instance.loadWithFallback(
  appSettingsDao: container.read(appSettingsDaoProvider),
  knownRuleIds: ReasonType.values.map((r) => r.code).toSet(),
);

runApp(...);

// NEW — fire-and-forget OTA check (Q7 = A)
unawaited(
  container.read(calibrationUpdaterProvider).checkAndUpdate().then((result) {
    AppLogger.info('CalibrationUpdater', 'OTA check result: $result');
  }),
);
```

`CalibratedScoresRegistry.loadWithFallback` 新 method 的行為：

```dart
Future<void> loadWithFallback({
  required AppSettingsDao appSettingsDao,
  Set<String>? knownRuleIds,
}) async {
  if (_loaded) return;  // idempotent

  // Tier 1: try DB cache
  final cached = await appSettingsDao.getCachedCalibration();
  if (cached != null && cached.shortJson != null && cached.longJson != null) {
    try {
      _short = CalibratedScoresTable.fromJsonString(cached.shortJson!, knownRuleIds: knownRuleIds);
      _long = CalibratedScoresTable.fromJsonString(cached.longJson!, knownRuleIds: knownRuleIds);
      _loaded = true;
      AppLogger.info('CalibratedScoresRegistry', 'loaded from DB cache: ${cached.version}');
      return;
    } on FormatException catch (e) {
      AppLogger.warning('CalibratedScoresRegistry', 'DB cache malformed, falling back to assets', e);
      // fall through to Tier 2
    }
  }

  // Tier 2: bundled asset (existing loadFromAssets logic)
  await loadFromAssets(knownRuleIds: knownRuleIds);
}
```

`loadFromAssets` 保留原狀，因為 Stage 5a 的測試都 call 它；`loadWithFallback` 是新 entry point，主要給 production `main.dart` 用。

---

## 4. What changes where

### 4.1 New files

```
lib/data/network/
├── calibration_updater.dart                   [NEW] 核心 fetch + verify + write 邏輯
└── calibration_fetch_result.dart              [NEW] Sealed result type

lib/data/providers/
└── calibration_updater_provider.dart          [NEW] Riverpod provider 接好 httpClient + dao + clock + logger

test/data/network/
└── calibration_updater_test.dart              [NEW] Unit tests (mocktail mock http + dao + clock)

docs/plans/
└── 2026-04-12-ota-calibration-updates-design.md  [NEW] 這份設計
```

### 4.2 Modified files

| File | Change |
|:---|:---|
| [`lib/data/database/tables/app_settings.dart`](../../lib/data/database/tables/app_settings.dart) | 加 6 個 nullable columns (`calibration*`) |
| `lib/data/database/app_database.g.dart` | build_runner regenerate |
| [`lib/data/database/daos/app_settings_dao.dart`](../../lib/data/database/daos/app_settings_dao.dart) | 加 `getCachedCalibration()`, `writeCalibration(...)`, `touchCalibrationLastCheckedAt(...)` |
| [`lib/core/constants/calibrated_scores/calibrated_scores_registry.dart`](../../lib/core/constants/calibrated_scores/calibrated_scores_registry.dart) | 加 `loadWithFallback({appSettingsDao, knownRuleIds})` method |
| [`lib/main.dart`](../../lib/main.dart) | `loadFromAssets` → `loadWithFallback`；`runApp` 後加 `unawaited(calibrationUpdater.checkAndUpdate())` |
| [`tool/recalibrate.dart`](../../tool/recalibrate.dart) | 產出 JSON 時順便算 SHA-256、產出 `calibration_manifest.json` |

### 4.3 Blast radius

- **New code**: ~400 LOC（CalibrationUpdater 160 + result type 40 + provider 30 + tests 170）
- **Modified code**: ~100 LOC（AppSettings + DAO + Registry + main.dart + recalibrate.dart）
- **Schema change**: 6 nullable columns in single table（pre-launch = no migration）
- **Runtime impact**: cold start 多一次 DAO read（幾毫秒，已在 path 上）；fire-and-forget 一次 HTTP call/24h
- **Test impact**: `test/data/network/calibration_updater_test.dart` 新增；既有 `calibrated_scores_registry_test.dart` 不動（loadFromAssets 還在）

---

## 5. Commit sequencing

Three commits, each independently testable + build-green:

### OTA C1 — Schema & manifest foundation

**Scope**:
- AppSettings 加 6 columns + build_runner regenerate
- AppSettingsDao 三個新 method + unit tests
- `tool/recalibrate.dart` 產 manifest + SHA-256 + unit tests
- `CalibratedScoresRegistry.loadWithFallback` method + test for DB-cache-hit path

**Why first**: 這層完全沒 network 依賴，純 local infra。完成後 `./scripts/calibrate.sh` 就能產出完整 manifest，但還沒人 consume 它。Test 用 in-memory Drift + mock file system。

**Verification**: `flutter test test/data/database/ test/core/constants/calibrated_scores/ test/tool/` 全綠。

### OTA C2 — CalibrationUpdater + fetch result

**Scope**:
- `CalibrationFetchResult` sealed class
- `CalibrationUpdater` 主 service
- `calibrationUpdaterProvider` Riverpod provider
- 大量 unit test：24h gate / hash match / fetch success / hash mismatch / parse error / network error / timeout / DB write failure

**Why second**: 這是最大塊的 pure logic，可以 完全 mock httpClient + dao + clock 在單元測試層驗 happy + 所有 failure branches，不需要動 main.dart。

**Verification**: `flutter test test/data/network/calibration_updater_test.dart` 全綠 + `flutter analyze` 無 warning。

### OTA C3 — main.dart bootstrap integration

**Scope**:
- `main.dart`：`loadFromAssets` → `loadWithFallback`
- `main.dart`：加 `unawaited(container.read(calibrationUpdaterProvider).checkAndUpdate())`
- Integration smoke test (`flutter run` 手動驗證冷啟動 log 有 `CalibrationUpdater: OTA check result: ...`)
- 更新 `memory/afterclose_scoring_overhaul_plan.md` 把 OTA 標為完成

**Why last**: 只有這一步碰到 production 啟動路徑。前兩個 commit 都獨立可驗，這個 commit 負責把線接起來。萬一出問題也容易定位。

**Verification**:
- `flutter test` 全綠（2300+ tests）
- `flutter analyze --no-fatal-infos` 乾淨
- Manual cold start：確認 log 有 OTA 結果、AppSettings row 有寫入
- Second cold start within 24h：確認 log 顯示 `within_24h_gate`
- Modify lastCheckedAt to 25h ago：確認 log 顯示 hash match / fetch new

---

## 6. Test strategy

### 6.1 CalibrationUpdater unit tests (the main TDD surface)

Mock 對象：`http.Client`, `AppSettingsDao`, `Clock`, `Logger`。

必測 scenarios：

| # | Scenario | Setup | Expected result | Side effects |
|:-|:-|:-|:-|:-|
| 1 | 24h gate skip | lastCheckedAt = now - 1h | `UpToDate(within_24h_gate)` | no HTTP, no DB write |
| 2 | First run (no cache) | lastCheckedAt = null, manifest valid | `Success(version)` | HTTP: manifest + 2 JSONs; DB: full write |
| 3 | Hash match (cached up to date) | cached hashes == manifest hashes | `UpToDate(hash_match_*)` | HTTP: manifest only; DB: touch lastCheckedAt |
| 4 | Hash updated (new version) | cached hashes != manifest hashes | `Success(version)` | HTTP: manifest + 2 JSONs; DB: full write |
| 5 | SocketException on manifest | network mocked to throw | `TransientFailure(network: ...)` | **no** DB write (lastCheckedAt 不動) |
| 6 | TimeoutException on JSON fetch | short JSON mocked to timeout | `TransientFailure(timeout: ...)` | no DB write |
| 7 | Manifest 500 | 5xx | `TransientFailure(http: ...)` | no DB write |
| 8 | Hash mismatch on short | shortActualHash != manifest.shortHash | `PermanentFailure(hash_mismatch)` | DB: touch lastCheckedAt |
| 9 | Parse fail on long | longJson = `"not json"` | `PermanentFailure(parse_error: ...)` | DB: touch lastCheckedAt |
| 10 | Manifest malformed | manifest missing field | `PermanentFailure(manifest_parse: ...)` | DB: touch lastCheckedAt |
| 11 | DB write failure | dao.writeCalibration throws | `TransientFailure(unexpected: ...)` | best-effort |
| 12 | `minimum_app_version` exceeds current | manifest says `2.0.0`, app is `1.0.0` | `UpToDate(min_version_skip)` | DB: touch lastCheckedAt |

Scenario 5 vs 8 特別重要：**transient 不 touch，permanent 必須 touch**，這是 Q6 設計的核心，lock 住避免未來 regression。

### 6.2 CalibratedScoresRegistry.loadWithFallback tests

- Tier 1 hit: AppSettings 有 valid JSON → registry loads from DB（不讀 asset）
- Tier 1 malformed fallthrough: DB JSON corrupt → falls through to asset（既有 `loadFromAssets` 測試已 cover asset path）
- Tier 1 empty: `cached == null` → falls through to asset
- Idempotent: `loadWithFallback` 呼叫兩次只跑一次

### 6.3 AppSettingsDao tests

- `getCachedCalibration` 回傳 null when columns all null
- `writeCalibration` 寫入後 `getCachedCalibration` 讀得到
- `touchCalibrationLastCheckedAt` 只動 timestamp 不影響其他欄位
- Transaction rollback：若 write 中途 throw，前面欄位不會留下半成品（靠 Drift 內建 transaction 保證）

### 6.4 recalibrate.dart tests

- Produces manifest with correct schema
- SHA-256 calculation matches `openssl sha256`
- Manifest `short_url` / `long_url` 用正確 base URL
- Manifest `generated_at` 為 valid ISO 8601

### 6.5 What we explicitly DON'T test

- **Real jsDelivr fetch** —— unit test 全 mock，避免 CI 依賴外部網路
- **Real SHA-256 on real JSON file**（integration-level）—— recalibrate test 用 fixture 驗 hash 計算正確即可
- **Widget test 打網路** —— 所有 widget test 應透過 `ProviderScope.overrides` 把 `calibrationUpdaterProvider` 替成 noop

---

## 7. Operational considerations

### 7.1 jsDelivr CDN trust model

- **jsDelivr 自動 mirror GitHub raw**，no config needed。Push 到 `origin/main` 後 1-3 分鐘內 CDN 可用
- **Cache TTL**: jsDelivr 預設 12h。想強制 invalidate 走 `cdn.jsdelivr.net/gh/...@{commit}/` 用 commit SHA 鎖版。我們**不用 commit SHA**，因為：
  - 月頻更新自然不受 12h cache 影響（下一次 recalibrate 至少 2 週後）
  - 若真要緊急 rollback，改 manifest 內容 + 新 commit hash → 下次 fetch 就拿到新 manifest
- **TLS** 由 jsDelivr 處理，client 不需自帶 cert

### 7.2 Monitoring & observability

- **Local log**: `AppLogger.info('CalibrationUpdater', 'OTA check result: $result')` 每次 cold start 留一行
- **Sentry**: `PermanentFailure` 走 `captureMessage(level: warning)`，`Success` / `UpToDate` 不上報
- **Debug UI**: 未來可在 Settings 頁顯示「上次校準版本 / 上次檢查時間 / 上次結果」，但不在 OTA scope 內
- **No metrics endpoint**: 明確 out-of-scope

### 7.3 Rollback procedure（運維文件）

若某次 OTA 發現 JSON bug：

1. **Best path**: git revert 該次 calibration commit，push 到 main。jsDelivr 1-3 分鐘後 pull 新 manifest，用戶下次 cold start（24h gate 內）回到前一版。
2. **Fast path**: 直接改 `assets/calibration_manifest.json` 指回舊版 JSON URL + 舊版 hash，commit + push。不用動 JSON 檔本身。
3. **Nuclear**: 若 OTA infra 本身有 bug 到不能信任 client 的 fallback chain → 發 app hotfix release + 停用 OTA URL（讓 manifest 404），全部用戶下次 cold start 走 bundled asset 路徑

### 7.4 First launch (fresh install) behaviour

- 用戶安裝 app → 第一次 cold start → AppSettings 全空 → `loadWithFallback` 走 Tier 2 bundled asset（跟 Stage 5a 一樣）
- Cold start 完 → `checkAndUpdate` 跑，fetch manifest + 2 JSONs → 寫進 AppSettings
- 用戶關 app → 重啟 → cold start 走 Tier 1 DB cache → 拿到最新 OTA 版本

**關鍵**：首次啟動仍然用 bundled asset，不會卡在 network fetch。這是 Q2 = C non-blocking 的核心保證。

### 7.5 Offline / airplane mode

- Cold start 永遠成功（fallback chain 全在 local）
- `checkAndUpdate` → `SocketException` → `TransientFailure` → 不 touch `lastCheckedAt` → 下次 cold start 重試
- 用戶完全無感

---

## 8. Known risks & mitigations

| Risk | Likelihood | Mitigation |
|:---|:---|:---|
| jsDelivr 長時間 outage（罕見但發生過） | Low | Fallback chain 保證 app 繼續用 DB cache / bundled asset；下次 outage 結束後自動恢復 |
| GitHub repo private 化 → jsDelivr 拿不到 | Very Low | Repo 是 public，變動時會看到；影響時 manual rollback |
| JSON 被手誤 push 壞掉（hash 跟實際不符） | Medium | Client hash 檢查直接 reject；pre-commit hook 可加 sanity check |
| 用戶改手機時間往前（24h gate 被 bypass） | Low | 流量不痛（jsDelivr 免費 + manifest 小 ~1KB） |
| `minimum_app_version` 設太嚴格讓舊用戶被鎖在舊 calibration | Medium | 謹慎 bump；預設永遠設成當前最低支援版本，非本次 recalibrate 用新 rule 不 bump |
| AppSettings JSON 欄位累積肥大（每次 write 整個 row 重寫） | Very Low | Drift page-level update，~20KB row 寫入是 noise |
| Fire-and-forget 的 `unawaited` future 在 Sentry crash 時沒捕到 | Low | `checkAndUpdate` 內部已全 try/catch；最外層再加一層 `.catchError` 保底 |

---

## 9. Post-design acceptance checklist

實作前確認：
- [ ] 7 題決策全部對齊（本文 §2）
- [ ] 三個 commit 的 scope 無重疊、都可獨立 build 綠
- [ ] `loadFromAssets` 保留（向下相容），新的是 `loadWithFallback`
- [ ] AppSettings 新 columns 全 nullable
- [ ] Test scenarios 覆蓋 4 種 result type × 主要 failure mode

實作後驗收：
- [ ] `flutter test` 全綠（含新增 ~20 個 OTA test）
- [ ] `flutter analyze --no-fatal-infos` 乾淨
- [ ] Manual cold start：log 顯示 `OTA check result: Success/UpToDate/...`
- [ ] Manual 24h-gate 驗證（把 `calibrationLastCheckedAt` 往回改）
- [ ] jsDelivr URL 手動 curl 驗證 manifest + JSON 可達
- [ ] 模擬 hash mismatch（手動改 manifest 的 hash 欄位）驗證 PermanentFailure 路徑
- [ ] 斷網 → 冷啟動 → app 正常啟動 + log 顯示 TransientFailure

---

## 10. Out of scope (explicit deferrals)

- **Background WorkManager / BackgroundFetch** —— 更新頻率不需要。月頻 + cold-start-triggered 已足夠
- **Partial update**（只更新 short 或 long）—— atomic 寫雙份比較安全，且 recalibrate pipeline 本來就一次產雙份
- **Delta sync / binary diff** —— JSON 本身 ~10KB，delta 沒意義
- **Version comparison UI** —— 用戶不該需要知道 calibration 版本
- **Signed payload** —— TLS + SHA-256 足夠（design doc §7.1）
- **A/B rollout** —— Stage 6+ 決定
- **Server-side control panel** —— Git push 就是 control panel

---

**End of design. Ready to implement OTA C1.**
