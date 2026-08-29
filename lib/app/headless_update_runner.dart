import 'package:meta/meta.dart';

import 'package:daredevil/core/constants/calibrated_scores/calibrated_scores_registry.dart';
import 'package:daredevil/core/constants/reason_type.dart';
import 'package:daredevil/core/utils/clock.dart';
import 'package:daredevil/core/utils/logger.dart';
import 'package:daredevil/core/utils/taiwan_calendar.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/data/remote/api_budget_tracker.dart';
import 'package:daredevil/data/remote/finmind_client.dart';
import 'package:daredevil/data/remote/rss_parser.dart';
import 'package:daredevil/data/remote/tdcc_client.dart';
import 'package:daredevil/data/remote/tpex_client.dart';
import 'package:daredevil/data/remote/twse_client.dart';
import 'package:daredevil/domain/services/update_service.dart';
import 'package:daredevil/domain/services/update_service_factory.dart';

const _tag = 'HeadlessUpdateRunner';

/// Headless 跑一次每日更新，給 background isolate（WorkManager）+ macOS
/// launchd CLI（[tool/daily_update.dart]）共用。
///
/// 自管所有資源生命週期（DB、API clients、Registry seed）。可從任何
/// 沒有 Riverpod container / Flutter binding 的環境呼叫。
///
/// **非交易日 short-circuit**：建完整服務圖之前就 skip，回傳
/// `skipped=true` 的 [UpdateResult]。
///
/// **Token 來源**：透過 [SettingsRepository] 走預設 fallback chain
/// （SecureStorage → `FINMIND_TOKEN` env var → in-memory）。launchd
/// 跑 CLI 時要靠 env var 路徑（launchd 不讀 shell rc）。
///
/// **[database] 參數（C 方案 refactor 2026-06-19）**：caller 注入已建好的
/// [AppDatabase] 控制連線方式：
/// - WorkManager isolate / Flutter app：`AppDatabase(openDriftFlutterConnection())`
/// - macOS launchd CLI：`AppDatabase.forToolFile(sandboxDbPath)`
///
/// caller 也要負責**之前**設好 [CalibratedScoresRegistry.assetLoaderOverride]
/// （rootBundle 或 File-based loader）。
///
/// runner 自己管 DB 生命週期，**會在 finally 呼叫 `db.close()`**。
///
/// [finMindToken] 顯式注入 — 取代以前 [SettingsRepository.getFinMindToken]
/// 的 fallback chain（依賴 flutter_secure_storage 是 Flutter-only plugin）。
/// caller 規則：
/// - WorkManager isolate：caller 自己用 SettingsRepository 取 token 再傳進來
/// - macOS launchd CLI：直接讀 `FINMIND_TOKEN` env var 傳進來
/// - null 或空字串 → finMind client 沒 token，免費資料能跑、需 token 的
///   syncer 會在內部 skip
/// 測試 seam：runner 的價值在裝配與生命週期管理，測試需要攔截「建好的
/// 服務」同時保留 runner 對 clients／budget／DB 的真實管理。
typedef HeadlessServiceBuilder =
    UpdateService Function({
      required AppDatabase database,
      required FinMindClient finMindClient,
      required TwseClient twseClient,
      required TpexClient tpexClient,
      required TdccClient tdccClient,
      required RssParser rssParser,
      required AppClock clock,
    });

// 型別相容守衛(2026-08-29 review):seam 簽名與 factory 漂移時在**編譯期**
// 炸——factory 新增 required 參數或改型別,這行就不再可指派。clock 放進
// typedef 讓兩條分支共享同一個時鐘契約(review 實測:預設分支的
// clock 轉傳原本零覆蓋,刪掉也全綠)。
// ignore: unused_element
const HeadlessServiceBuilder _seamMatchesFactory = UpdateServiceFactory.build;

Future<UpdateResult> runHeadlessUpdate({
  required AppDatabase database,
  required ApiBudgetStore budgetStore,
  String? finMindToken,
  AppClock clock = const SystemClock(),
  @visibleForTesting HeadlessServiceBuilder? buildService,
}) async {
  final now = clock.now();
  if (!TaiwanCalendar.isTradingDay(now)) {
    AppLogger.info(_tag, '非交易日，跳過更新');
    // docstring 契約「runner 會在 finally 呼叫 db.close()」原本在這條
    // 早退路徑漏掉。⚠️ 別以為 CLI 端的 finally 是兜底——tool/daily_update
    // 以 exit() 收尾,Dart 的 exit() **不 unwind**,那個 finally 在每條
    // 路徑都不可達(review 實測);修好前兩個呼叫端實際都靠 process
    // teardown。補上讓契約在每條路徑成立(2026-08-29 稽核+review)。
    await database.close();
    return UpdateResult(date: now)
      ..success = true
      ..skipped = true
      ..message = '非交易日';
  }

  try {
    // Stage 5a OTA：seed CalibratedScoresRegistry。background isolate
    // / CLI process 是 fresh `_loaded=false` 狀態；若不 seed，
    // `scoreStocksInIsolate` 取到的 `snapshotForIsolate()` 是空 map，
    // 所有規則 fallback 到 hardcoded `RuleScores`，跟前景路徑使用的
    // calibrated 分數靜默分歧 — 寫入的 recommendations 跟 user 開 app
    // 看到的不一致。對齊 `main.dart` 的初始化邏輯。
    final cachedCalibration = await database.getCachedCalibration();
    await CalibratedScoresRegistry.instance.loadWithOverride(
      shortJsonOverride: cachedCalibration.shortJson,
      longJsonOverride: cachedCalibration.longJson,
      knownRuleIds: ReasonType.values.map((r) => r.code).toSet(),
      hardcodedScores: {for (final r in ReasonType.values) r.code: r.score},
    );

    // 初始化 API 客戶端（hoist 到 try 外讓 finally 可見）。
    // process-local ApiBudgetTracker，跨 isolate 不共享是有意設計。
    // store 由 caller 注入：flutter 環境給 SharedPreferences 版、launchd
    // CLI 給 FileApiBudgetStore——shared_preferences 是 flutter plugin，
    // import 進本檔會把 dart:ui 拉進 tool 純 Dart 鏈（2026-07-27 事故）。
    final budgetTracker = ApiBudgetTracker(store: budgetStore);
    // 跨 process 延續配額計數。讀取失敗 restore 會 fail-open 回「無歷史」
    // ——與加入持久化之前的行為相同，不會更糟。
    final budgetRestore = await budgetTracker.restore();
    if (budgetRestore.restoredCalls > 0 ||
        budgetRestore.cooldownVendors.isNotEmpty) {
      AppLogger.info(
        'ApiBudgetTracker',
        '配額狀態已還原: ${budgetRestore.restoredCalls} 次呼叫在窗內'
            '${budgetRestore.cooldownVendors.isEmpty ? "" : "，cooldown 中: "
                      '${budgetRestore.cooldownVendors.map((v) => v.name).join(",")}'}',
      );
    }
    final finMindClient = FinMindClient(budgetTracker: budgetTracker);
    final twseClient = TwseClient();
    final tpexClient = TpexClient();
    final tdccClient = TdccClient();
    final rssParser = RssParser();

    try {
      // 由 caller 顯式注入 token，避免在此處 import flutter_secure_storage
      // 把 dart:ui 拉進整個 type graph（C 方案 refactor 2026-06-19）。
      if (finMindToken != null && finMindToken.isNotEmpty) {
        finMindClient.token = finMindToken;
      } else {
        AppLogger.info(_tag, 'FinMind token 未注入，需 token 的 syncer 將 skip');
      }

      // 透過 UpdateServiceFactory 統一裝配，與 foreground
      // `updateServiceProvider` 共享同一條 wiring 路徑避免漂移。
      final updateService = (buildService ?? UpdateServiceFactory.build)(
        database: database,
        finMindClient: finMindClient,
        twseClient: twseClient,
        tpexClient: tpexClient,
        tdccClient: tdccClient,
        rssParser: rssParser,
        clock: clock,
      );

      return await updateService.runDailyUpdate();
    } finally {
      // 配額狀態收尾 flush(2026-08-01 複審 Critical):tracker 只在每
      // 10 次呼叫時自動存檔,run 結束不 flush 會丟掉尾端 ≤9 次記帳——
      // 遺失=重啟後低估=放行更多呼叫,正是持久化要防的 402 方向
      // (CLI 的 exit() 更會截斷 in-flight 寫入)。失敗 fail-open 不擋收尾。
      try {
        await budgetTracker.flush();
      } catch (e) {
        AppLogger.warning('ApiBudgetTracker', '收尾 flush 失敗(fail-open)', e);
      }
      // 釋放所有 API client 的 Dio 連線。本質是 hygiene 而非累積 leak
      //（isolate / process 結束自然回收），但顯式 close 在 iOS
      // BGProcessingTask 時間緊 / launchd 短任務時值得做。
      finMindClient.close();
      twseClient.close();
      tpexClient.close();
      tdccClient.close();
      rssParser.close();
    }
  } finally {
    await database.close();
  }
}
