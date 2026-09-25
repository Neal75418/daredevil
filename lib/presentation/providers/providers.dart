import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:daredevil/core/constants/api_config.dart';
import 'package:daredevil/core/utils/lru_cache.dart';
import 'package:daredevil/core/utils/logger.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/data/database/app_database_flutter.dart';
import 'package:daredevil/data/database/cached_accessor.dart';
import 'package:dio/dio.dart';

import 'package:daredevil/data/network/calibration_updater.dart';
import 'package:daredevil/data/remote/api_budget_tracker.dart';
import 'package:daredevil/data/remote/shared_prefs_api_budget_store.dart';
import 'package:daredevil/data/remote/finmind_client.dart';
import 'package:daredevil/data/remote/mops_client.dart';
import 'package:daredevil/presentation/providers/settings_provider.dart';
import 'package:daredevil/data/remote/rss_parser.dart';
import 'package:daredevil/data/remote/tpex_client.dart';
import 'package:daredevil/data/remote/tdcc_client.dart';
import 'package:daredevil/data/remote/twse_client.dart';
import 'package:daredevil/data/repositories/analysis_repository.dart';
import 'package:daredevil/data/repositories/fundamental_repository.dart';
import 'package:daredevil/data/repositories/market_data_repository.dart';
import 'package:daredevil/data/repositories/news_repository.dart';
import 'package:daredevil/data/repositories/price_repository.dart';
import 'package:daredevil/data/repositories/settings_repository.dart';
import 'package:daredevil/data/repositories/stock_repository.dart';
import 'package:daredevil/data/repositories/warning_repository.dart';
import 'package:daredevil/data/repositories/insider_repository.dart';
import 'package:daredevil/data/repositories/event_repository.dart';
import 'package:daredevil/data/repositories/portfolio_repository.dart';
import 'package:daredevil/core/utils/clock.dart';
import 'package:daredevil/data/database/cache_warmup_service.dart';
import 'package:daredevil/domain/services/api_connection_service.dart';
import 'package:daredevil/domain/services/data_sync_service.dart';
import 'package:daredevil/domain/services/rule_accuracy_service.dart';
import 'package:daredevil/domain/services/update_service.dart';
import 'package:daredevil/domain/services/update_service_factory.dart';

// ==================================================
// 核心基礎設施
// ==================================================

/// 時間抽象層，用於測試中注入假時間
final appClockProvider = Provider<AppClock>((ref) => const SystemClock());

/// 應用程式資料庫單例
final databaseProvider = Provider<AppDatabase>((ref) {
  // C 方案 refactor：AppDatabase 已移除 drift_flutter 依賴，Flutter runtime
  // 路徑改顯式注入 `openDriftFlutterConnection()`（純 Dart CLI 用
  // `AppDatabase.forToolFile`）。
  final db = AppDatabase(openDriftFlutterConnection());
  ref.onDispose(() => db.close());
  return db;
});

/// 批次查詢快取管理器（30 秒 TTL，優化更新週期）
final batchCacheProvider = Provider<BatchQueryCacheManager>((ref) {
  return BatchQueryCacheManager(
    maxSize: CacheConfig.batchQueryMaxSize,
    ttl: const Duration(seconds: CacheConfig.batchQueryTtlSec),
  );
});

/// 快取資料庫存取器，用於優化批次查詢
final cachedDbProvider = Provider<CachedDatabaseAccessor>((ref) {
  return CachedDatabaseAccessor(
    db: ref.watch(databaseProvider),
    cache: ref.watch(batchCacheProvider),
  );
});

/// M3：跨 syncer 共享的 API 預算追蹤器（per-vendor + process-local +
/// sliding 1hr）。目前僅 FinMindClient 整合（free-tier 600/hr 是實際
/// bottleneck），其他 vendor 後續視 PR 推進。
final apiBudgetTrackerProvider = Provider<ApiBudgetTracker>((ref) {
  // store 讓計數跨 app 重啟延續。**呼叫端必須在第一次 API 呼叫之前
  // `await restore()`**（見 main.dart）——建構與 checkBudget 都是同步的，
  // fire-and-forget 會讓早期呼叫看到空狀態，那正是本功能要修的 bug。
  return ApiBudgetTracker(
    clock: ref.watch(appClockProvider),
    store: const SharedPrefsApiBudgetStore(),
  );
});

/// 目前生效的 FinMind token（記憶體中的唯一來源）。
///
/// 啟動時由 main 從安全儲存載入；設定頁存／清 token 時更新。
/// [finMindClientProvider] watch 它，所以 client 不論因何重建都帶著當下的 token。
class FinMindTokenNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  /// 設定目前的 token。格式無效時以匿名模式運作。
  ///
  /// 🚨 驗證必須在這裡：client 以建構子收 token、不經 setter 的驗證。
  /// FINMIND_TOKEN 環境變數與舊版遷移來源未必驗過（repository 註明不 trim），
  /// 帶換行的 token 放進 header 會讓每個請求都失敗，錯誤字串還含 token 原文。
  /// 空字串不必特別處理：FinMindClient.hasToken 已視同沒有 token。
  void set(String? token) {
    if (token != null &&
        token.isNotEmpty &&
        !FinMindClient.isValidTokenFormat(token)) {
      AppLogger.warning('FinMindToken', 'token 格式無效，以匿名模式運作');
      state = null;
      return;
    }
    state = token;
  }

  /// App 啟動時從安全儲存載入。讀取失敗不影響啟動，以匿名模式運作。
  Future<void> loadFrom(SettingsRepository repo) async {
    try {
      set(await repo.getFinMindToken());
    } catch (e) {
      AppLogger.warning('FinMindToken', '載入 FinMind Token 失敗', e);
    }
  }
}

final finMindTokenProvider = NotifierProvider<FinMindTokenNotifier, String?>(
  FinMindTokenNotifier.new,
);

/// FinMind API 客戶端（用於取得歷史資料）
///
/// 當使用者變更快取時間設定時，此 provider 會被 invalidate 並重建；
/// `ref.onDispose` 呼叫 `client.close()` 釋放舊 Dio 連線與 LRU cache，
/// 避免每次設定變動都洩漏一個底層 socket。
final finMindClientProvider = Provider<FinMindClient>((ref) {
  final cacheDuration = ref.watch(cacheDurationProvider);
  final client = FinMindClient(
    token: ref.watch(finMindTokenProvider),
    cacheTtl: Duration(minutes: cacheDuration),
    budgetTracker: ref.watch(apiBudgetTrackerProvider),
  );
  ref.onDispose(client.close);
  return client;
});

/// TWSE 開放資料客戶端（用於取得每日全市場上市價格）
final twseClientProvider = Provider<TwseClient>((ref) {
  final client = TwseClient();
  ref.onDispose(client.close);
  return client;
});

/// MOPS(舊版)月營收公布期 client Provider
final mopsClientProvider = Provider<MopsClient>((ref) {
  return MopsClient();
});

/// TPEX 開放資料客戶端（用於取得每日全市場上櫃價格）
final tpexClientProvider = Provider<TpexClient>((ref) {
  final client = TpexClient();
  ref.onDispose(client.close);
  return client;
});

/// TDCC 集保中心 Open Data 客戶端（股權分散表，每週更新）
final tdccClientProvider = Provider<TdccClient>((ref) {
  final client = TdccClient();
  ref.onDispose(client.close);
  return client;
});

/// RSS 解析器
final rssParserProvider = Provider<RssParser>((ref) {
  final parser = RssParser();
  ref.onDispose(parser.close);
  return parser;
});

// ==================================================
// OTA Calibration updater (Stage 4 OTA)
// ==================================================

/// 當前 app 版本字串（Stage 4 OTA minimum_app_version 比對用）
///
/// 由 [main.dart] 在 startup 用 `PackageInfo.fromPlatform()` 取得真實
/// 版本，透過 `ProviderContainer.overrides` 注入。Default `'0.0.0'`
/// 是「未注入」signal — `CalibrationUpdater._isAppVersionSufficient` 對
/// 任何非空 `minimum_app_version` 判定不足，**安全側偏保守**，避免測試
/// 或 dev 環境意外接受所有 OTA 推送。Production 不應該 reach default；
/// main.dart 的 `_loadAppVersion()` fallback 路徑用 `'0.0.0-fallback'`
/// 讓 ELK 能區分「未注入」vs「PackageInfo 壞掉」。
///
/// 這個 provider 分開是為了避免 [calibrationUpdaterProvider] 每次
/// 被 read 都要等 `PackageInfo.fromPlatform()` 的非同步結果。
final currentAppVersionProvider = Provider<String>((ref) => '0.0.0');

/// OTA calibration updater — 讀取 jsDelivr 的 manifest 並把新版
/// calibration JSON 寫入 app_settings 快取（下次 cold start 生效）。
///
/// 由 `main.dart` 在 `runApp` 之後 fire-and-forget 呼叫：
///
/// ```dart
/// unawaited(container.read(calibrationUpdaterProvider).checkAndUpdate());
/// ```
///
/// 所有失敗都在 service 內部 catch 後分類為 Transient/Permanent，
/// 永遠不會 throw 到 caller。詳見 [CalibrationUpdater] 與
/// design doc §3.5。
final calibrationUpdaterProvider = Provider<CalibrationUpdater>((ref) {
  // Updater 的 Dio 由 provider 擁有；container dispose 時必須 close()
  // 才能釋放 keep-alive socket（L1 / L2 lifecycle contract）。
  final dio = Dio();
  ref.onDispose(() => dio.close(force: false));
  return CalibrationUpdater(
    dio: dio,
    database: ref.watch(databaseProvider),
    clock: ref.watch(appClockProvider),
    appVersion: ref.watch(currentAppVersionProvider),
  );
});

// ==================================================
// 資料儲存庫
// ==================================================

/// 股票資料儲存庫 Provider
final stockRepositoryProvider = Provider<StockRepository>((ref) {
  return StockRepository(
    database: ref.watch(databaseProvider),
    finMindClient: ref.watch(finMindClientProvider),
    twseClient: ref.watch(twseClientProvider),
  );
});

/// 價格資料儲存庫 Provider
/// 使用 TWSE/TPEX 取得每日價格，使用 FinMind 取得歷史資料
final priceRepositoryProvider = Provider<PriceRepository>((ref) {
  return PriceRepository(
    database: ref.watch(databaseProvider),
    finMindClient: ref.watch(finMindClientProvider),
    twseClient: ref.watch(twseClientProvider),
    tpexClient: ref.watch(tpexClientProvider),
  );
});

/// 新聞資料儲存庫 Provider
final newsRepositoryProvider = Provider<NewsRepository>((ref) {
  return NewsRepository(
    database: ref.watch(databaseProvider),
    rssParser: ref.watch(rssParserProvider),
    twseClient: ref.watch(twseClientProvider),
  );
});

/// 分析資料儲存庫 Provider
final analysisRepositoryProvider = Provider<AnalysisRepository>((ref) {
  return AnalysisRepository(
    database: ref.watch(databaseProvider),
    clock: ref.watch(appClockProvider),
  );
});

/// 設定資料儲存庫 Provider（使用安全儲存空間存放敏感資料）
final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  return SettingsRepository(database: ref.watch(databaseProvider));
});

/// 市場資料儲存庫 Provider（第一階段：擴展市場資料）
final marketDataRepositoryProvider = Provider<MarketDataRepository>((ref) {
  return MarketDataRepository(
    database: ref.watch(databaseProvider),
    finMindClient: ref.watch(finMindClientProvider),
  );
});

/// 基本面資料儲存庫 Provider（第六階段：營收、本益比、股價淨值比、殖利率）
final fundamentalRepositoryProvider = Provider<FundamentalRepository>((ref) {
  return FundamentalRepository(
    mops: ref.watch(mopsClientProvider),
    db: ref.watch(databaseProvider),
    finMind: ref.watch(finMindClientProvider),
    twse: ref.watch(twseClientProvider),
    tpex: ref.watch(tpexClientProvider),
  );
});

/// 警示資料儲存庫 Provider（Killer Features：注意股票/處置股票）
final warningRepositoryProvider = Provider<WarningRepository>((ref) {
  return WarningRepository(
    database: ref.watch(databaseProvider),
    tpexClient: ref.watch(tpexClientProvider),
    twseClient: ref.watch(twseClientProvider),
  );
});

/// 董監持股資料儲存庫 Provider（Killer Features：內部人持股變化）
final insiderRepositoryProvider = Provider<InsiderRepository>((ref) {
  return InsiderRepository(
    database: ref.watch(databaseProvider),
    twseClient: ref.watch(twseClientProvider),
    tpexClient: ref.watch(tpexClientProvider),
  );
});

/// 投資組合儲存庫 Provider（Phase 4.4）
final portfolioRepositoryProvider = Provider<PortfolioRepository>((ref) {
  return PortfolioRepository(database: ref.watch(databaseProvider));
});

/// 事件日曆儲存庫 Provider（Phase 4.3）
final eventRepositoryProvider = Provider<EventRepository>((ref) {
  return EventRepository(
    database: ref.watch(databaseProvider),
    twseClient: ref.watch(twseClientProvider),
    tpexClient: ref.watch(tpexClientProvider),
  );
});

// ==================================================
// 服務
// ==================================================

/// 資料同步服務 Provider（確保價格與法人資料日期一致）
final dataSyncServiceProvider = Provider<DataSyncService>((ref) {
  return const DataSyncService();
});

/// API 連線測試服務 Provider
final apiConnectionServiceProvider = Provider<ApiConnectionService>((ref) {
  return const ApiConnectionService();
});

/// 更新服務 Provider
///
/// 透過 [UpdateServiceFactory] 統一裝配，避免與 BackgroundUpdateService
/// 兩條路徑漂移（M9 fix）。
final updateServiceProvider = Provider<UpdateService>((ref) {
  return UpdateServiceFactory.build(
    database: ref.watch(databaseProvider),
    finMindClient: ref.watch(finMindClientProvider),
    twseClient: ref.watch(twseClientProvider),
    tpexClient: ref.watch(tpexClientProvider),
    tdccClient: ref.watch(tdccClientProvider),
    rssParser: ref.watch(rssParserProvider),
    clock: ref.watch(appClockProvider),
    ruleAccuracyService: ref.watch(ruleAccuracyServiceProvider),
  );
});

/// 規則準確度追蹤服務 Provider（Sprint 10）
final ruleAccuracyServiceProvider = Provider<RuleAccuracyService>((ref) {
  return RuleAccuracyService(database: ref.watch(databaseProvider));
});

/// 快取預熱服務 Provider
final cacheWarmupServiceProvider = Provider<CacheWarmupService>((ref) {
  return CacheWarmupService(
    cachedDb: ref.watch(cachedDbProvider),
    db: ref.watch(databaseProvider),
  );
});
