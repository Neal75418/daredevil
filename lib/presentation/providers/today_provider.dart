import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:daredevil/core/constants/api_config.dart';
import 'package:daredevil/core/constants/data_freshness.dart';
import 'package:daredevil/core/constants/rule_enums.dart';
import 'package:daredevil/core/utils/error_display.dart';
import 'package:daredevil/core/utils/sentinel.dart';
import 'package:daredevil/core/utils/logger.dart';
import 'package:daredevil/core/utils/taiwan_calendar.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/data/database/cached_accessor.dart';
import 'package:daredevil/data/repositories/market_data_repository.dart';
import 'package:daredevil/domain/services/data_sync_service.dart';
import 'package:daredevil/domain/services/update_service.dart';
import 'package:daredevil/presentation/providers/data_update_epoch_provider.dart';
import 'package:daredevil/presentation/providers/market_overview_provider.dart';
import 'package:daredevil/presentation/providers/notification_provider.dart';
import 'package:daredevil/presentation/providers/price_alert_provider.dart';
import 'package:daredevil/presentation/providers/providers.dart';

/// 每日更新作業的最大執行時間
const _updateTimeout = Duration(minutes: ApiConfig.updateTimeoutMin);

// ==================================================
// Today Screen State
// ==================================================

/// 今日推薦與市場總覽的 State
class TodayState {
  const TodayState({
    this.lastUpdate,
    this.dataDate,
    this.isLoading = false,
    this.isUpdating = false,
    this.updateProgress,
    this.error,
  });

  final DateTime? lastUpdate;

  /// 目前顯示資料的實際日期
  final DateTime? dataDate;
  final bool isLoading;
  final bool isUpdating;
  final UpdateProgress? updateProgress;
  final String? error;

  TodayState copyWith({
    DateTime? lastUpdate,
    DateTime? dataDate,
    bool? isLoading,
    bool? isUpdating,
    Object? updateProgress = sentinel,
    Object? error = sentinel,
  }) {
    return TodayState(
      lastUpdate: lastUpdate ?? this.lastUpdate,
      dataDate: dataDate ?? this.dataDate,
      isLoading: isLoading ?? this.isLoading,
      isUpdating: isUpdating ?? this.isUpdating,
      updateProgress: updateProgress == sentinel
          ? this.updateProgress
          : updateProgress as UpdateProgress?,
      error: error == sentinel ? this.error : error as String?,
    );
  }
}

/// 更新進度資訊
class UpdateProgress {
  const UpdateProgress({
    required this.currentStep,
    required this.totalSteps,
    required this.message,
  });

  final int currentStep;
  final int totalSteps;
  final String message;

  double get progress => totalSteps > 0 ? currentStep / totalSteps : 0;
}

// ==================================================
// Today Notifier
// ==================================================

class TodayNotifier extends Notifier<TodayState> {
  var _active = true;
  int _loadGeneration = 0;

  /// 其他頁（經 [dataUpdateEpochProvider]）已被告知的 DB 版本。
  ///
  /// 🚨 只在會 bump epoch 的地方前進（首次載入、App 內更新完成、
  /// [reloadAfterResume]）。不可拿「當下 state」當基準：下拉重整等 loadData
  /// 會先把 state 更新成新版本卻不通知其他頁，之後回前景就再也比不出差異。
  ({DateTime? lastUpdate, DateTime? dataDate})? _ackedSnapshot;

  /// 最近一次 loadData 讀到的最新 update_run 是否仍在執行（App 外寫到一半）
  bool _latestRunInProgress = false;

  ({DateTime? lastUpdate, DateTime? dataDate}) get _snapshot =>
      (lastUpdate: state.lastUpdate, dataDate: state.dataDate);

  @override
  TodayState build() {
    _active = true;
    _loadGeneration = 0;
    _ackedSnapshot = null;
    _latestRunInProgress = false;
    ref.onDispose(() => _active = false);
    return const TodayState();
  }

  CachedDatabaseAccessor get _cachedDb => ref.read(cachedDbProvider);
  UpdateService get _updateService => ref.read(updateServiceProvider);
  DataSyncService get _dataSyncService => ref.read(dataSyncServiceProvider);
  MarketDataRepository get _marketRepo =>
      ref.read(marketDataRepositoryProvider);

  /// 載入今日畫面的「更新編排」狀態（最後更新時間 / 資料日期）+ 觸發冷啟自動更新
  ///
  /// **2026-06-21 退役舊推薦系統 Step 3**：推薦清單已改由
  /// [modeRecommendationsProvider] 獨立載入（3-mode tab）。此處不再載入舊
  /// daily_recommendation 清單，只負責 today 畫面共用的編排狀態
  /// （lastUpdate / dataDate / isLoading / 冷啟更新）。
  Future<void> loadData() async {
    final generation = ++_loadGeneration;
    state = state.copyWith(isLoading: true, error: null);

    try {
      // 取得最後更新執行記錄
      final lastRun = await _marketRepo.getLatestUpdateRun();

      // 取得實際資料日期（顯示用，也是冷啟動更新的新鮮度依據）
      final latestPriceDate = await _marketRepo.getLatestDataDate();
      final latestInstDate = await _marketRepo.getLatestInstitutionalDate();
      final dataDate = _dataSyncService.getDisplayDataDate(
        latestPriceDate,
        latestInstDate,
      );

      // B-lite cold-start auto-update（2026-06-18）：macOS 無 workmanager、
      // CLI 卡 Flutter binding，妥協做法是「user 一開 app 就背景跑」。
      // 資料落後交易日才跑、節流看「上次嘗試」、不阻塞 UI（fire-and-forget）
      // ——見 shouldTriggerColdStartUpdate。
      _maybeTriggerColdStartUpdate(
        dataDate: dataDate,
        lastAttemptAt: attemptAnchorOf(lastRun),
        latestRunSucceeded:
            lastRun?.status.toUpperCase() == UpdateStatus.success.code,
      );

      // 防禦性 guard：寫入前驗證 generation 沒被並發 reload 取代
      if (!_active || _loadGeneration != generation) return;

      state = state.copyWith(
        lastUpdate: lastRun?.finishedAt ?? lastRun?.startedAt,
        dataDate: dataDate,
        isLoading: false,
      );
      // 超過孤兒門檻的 RUNNING 是 CLI 中途崩潰的殘留，不算進行中——否則
      // 會擋住通知直到下一輪 launchd 建立新紀錄（最長約 18 小時）
      _latestRunInProgress =
          lastRun != null &&
          lastRun.status.toUpperCase() == UpdateStatus.running.code &&
          DateTime.now().difference(lastRun.startedAt) <
              DataFreshness.orphanRunningCutoff;
      // 首次載入時各頁也是從 DB 全新讀取，視為已同步
      _ackedSnapshot ??= _snapshot;
    } catch (e) {
      AppLogger.warning('TodayNotifier', '載入今日資料失敗', e);
      // race fix：runUpdate 完成後 await loadData() 跟 pull-to-refresh 並發時，
      // generation guard 確保只有最後一次能寫入 error state。
      if (!_active || _loadGeneration != generation) return;
      state = state.copyWith(isLoading: false, error: ErrorDisplay.message(e));
    }
  }

  /// 回到前景時重新載入（由 app 生命週期在離開超過門檻後呼叫）。
  ///
  /// 🚨 DB 可能已在 App 外被更新（launchd CLI、背景任務），這種更新不會
  /// bump [dataUpdateEpochProvider]。只 loadData 的話今日頁日期變新、訊號
  /// 清單與其他頁卻仍是舊的。最後更新或資料日與 [_ackedSnapshot]（其他頁
  /// 已被告知的版本）不同時，走與 App 內更新完成相同的收尾：清快取、
  /// bump epoch、重載大盤。
  /// App 內更新進行中時跳過——那一輪結束時本就會收尾。
  Future<void> reloadAfterResume() async {
    if (state.isUpdating) return;
    // 首次載入失敗時還不知道各頁看到哪個版本，保守視為「有變」
    final ackedUnknown = _ackedSnapshot == null;
    await loadData();
    // 載入途中可能觸發了冷啟動更新（交給那一輪收尾）；App 外的更新還在跑
    // 時先不通知，免得各頁讀到寫到一半的資料——跑完後下一次回前景會補上
    // 載入失敗（DB 出錯）時不通知：不叫其他頁在出錯時重讀，也不讓 acked 前進
    if (!_active || state.error != null) return;
    if (state.isUpdating || _latestRunInProgress) return;
    final current = _snapshot;
    if (!ackedUnknown && current == _ackedSnapshot) return;
    _ackedSnapshot = current;

    _cachedDb.invalidateCache();
    ref.read(dataUpdateEpochProvider.notifier).bump();
    await ref.read(marketOverviewProvider.notifier).loadData();
  }

  /// 節流錨點:最後一筆 run 的**發起**時刻(不分 status)。
  ///
  /// 不可用 finishedAt——孤兒 RUNNING 被 beforeOpen 的
  /// `failOrphanRunningRuns` 收斂成 FAILED 時,finishedAt 會蓋成 sweep
  /// 當下(DB bookkeeping,非真實 API 行為)。app 被殺數小時後重開,
  /// 舊寫法會把「剛剛的 sweep」當成「剛剛嘗試過」,冷啟動重試被多擋
  /// 最多一整個 coldStartRetryThrottleMinutes 窗。
  @visibleForTesting
  static DateTime? attemptAnchorOf(UpdateRunEntry? run) => run?.startedAt;

  /// B-lite cold-start auto-update 全域開關
  ///
  /// **Production**：`main.dart` 在 startup 設為 true（個人 dev 機默認
  /// 行為，避免漏交易日）。
  /// **Tests**：預設 false 避免單元測試意外觸發 [runUpdate] → 未 stub
  /// 的 `_updateService.runDailyUpdate()` 鏈拋型別例外。需要驗證
  /// cold-start 行為的 test 自己改 true。
  /// **Workmanager 背景 isolate**：不需要設（路徑不經 TodayNotifier）。
  static bool autoColdStartUpdateEnabled = false;

  /// B-lite cold-start auto-update（2026-06-18）
  ///
  /// short-circuit（任一不通就 skip）：
  /// 1. [autoColdStartUpdateEnabled]=false → 整層關閉（主要給測試 / 未來
  ///    feature flag 用）
  /// 2. 已有 update 在進行 → [runUpdate] 自己會擋，提前 skip 省 log noise
  /// 3. [shouldTriggerColdStartUpdate] 不通過（資料未落後／已收斂／節流中）
  ///
  /// 通過則 fire-and-forget — UI 用 [TodayState.isUpdating] / updateProgress
  /// 顯示進度，user 可以繼續操作；完成後 [dataUpdateEpochProvider] 自然
  /// 觸發各 consumer reload。
  ///
  /// **注意**：catch 全部 error 進 log，因為這層是「**幫使用者順手做的**
  /// 背景行為」，失敗不該影響主要 [loadData] 流程。實際失敗會被 runUpdate
  /// 內部包成 UpdateResult.errors，後續 UI 會反映。
  /// 冷啟動自動更新的判斷（純函式，方便測試 —— 不看真實時鐘）
  ///
  /// 三個條件分開判斷，因為它們問的是不同問題：
  /// - **資料夠不夠新** → 資料日是否落後交易日
  ///   （[TaiwanCalendar.tradingDaysBehind]）
  /// - **是否已收斂** → 應有資料日的就緒時間後已成功跑過仍落後＝來源
  ///   沒有這天（颱風臨時停市、日曆未標的假日），不再重試
  /// - **是不是在狂打 API** → 距上次**嘗試**（不分成功與否）≥
  ///   [DataFreshness.coldStartRetryThrottleMinutes]
  ///
  /// 新鮮度曾用「距上次成功 ≥6 小時」：交易日早上昨晚已更新到昨天收盤、
  /// 落後 0 天，卻因 11.5h ≥ 6h 白跑一輪、燒 FinMind 額度（2026-09-25 改）。
  /// 失敗的嘗試只擋節流時間，不可冒充「資料已新」。
  @visibleForTesting
  static bool shouldTriggerColdStartUpdate({
    required DateTime now,
    required DateTime? dataDate,
    required DateTime? lastAttemptAt,
    required bool latestRunSucceeded,
  }) {
    // 沒有任何資料（新安裝）一律要跑；非交易日也跑——UpdateService 會自動
    // 改抓上一個交易日，週末發現週五沒抓到不必等到週一
    if (dataDate != null &&
        TaiwanCalendar.tradingDaysBehind(dataDate, now) < 1) {
      return false;
    }
    // 收斂：應有資料日的就緒時間之後已成功跑過一輪仍落後＝來源就是沒有
    // 這天（颱風臨時停市未入日曆、_maxYear 後的平日假日）。不收斂的話每
    // 60 分鐘白跑一輪、燒 FinMind 額度，等應有資料日往前推進才重新判斷。
    final expected = TaiwanCalendar.expectedLatestTradingDataDate(now);
    final readyAt = DateTime(
      expected.year,
      expected.month,
      expected.day,
      DataFreshness.dailyDataReadyHour,
    );
    if (latestRunSucceeded &&
        lastAttemptAt != null &&
        !lastAttemptAt.isBefore(readyAt)) {
      return false;
    }
    if (lastAttemptAt != null &&
        now.difference(lastAttemptAt).inMinutes <
            DataFreshness.coldStartRetryThrottleMinutes) {
      return false;
    }
    return true;
  }

  void _maybeTriggerColdStartUpdate({
    required DateTime? dataDate,
    required DateTime? lastAttemptAt,
    required bool latestRunSucceeded,
  }) {
    if (!autoColdStartUpdateEnabled) return;
    if (state.isUpdating) return;
    if (!shouldTriggerColdStartUpdate(
      // 與資料落後提示同一個時鐘（也讓接線可測）
      now: ref.read(appClockProvider).now(),
      dataDate: dataDate,
      lastAttemptAt: lastAttemptAt,
      latestRunSucceeded: latestRunSucceeded,
    )) {
      return;
    }
    AppLogger.info(
      'TodayNotifier',
      'B-lite cold-start auto-update：資料日 ${dataDate ?? "無"}（落後交易日）、'
          '上次嘗試 ${lastAttemptAt ?? "從未"}'
          '（≥${DataFreshness.coldStartRetryThrottleMinutes}min），背景觸發',
    );
    // unawaited — 不阻塞 loadData 主流程
    unawaited(
      runUpdate().catchError((Object e, StackTrace s) {
        AppLogger.warning('TodayNotifier', 'cold-start auto-update 失敗', e, s);
        return UpdateResult(date: DateTime.now())..message = '$e';
      }),
    );
  }

  void clearError() {
    state = state.copyWith(error: null);
  }

  /// 執行每日更新，具備逾時保護機制
  ///
  /// 若更新時間超過 [_updateTimeout] 將拋出 [TimeoutException]
  /// 若已有更新在進行中，直接返回以避免並發 DB 寫入衝突。
  Future<UpdateResult> runUpdate({bool force = false}) async {
    if (state.isUpdating) {
      return UpdateResult(date: DateTime.now())
        ..skipped = true
        ..message = '更新已在進行中，請稍候';
    }

    state = state.copyWith(
      isUpdating: true,
      updateProgress: const UpdateProgress(
        currentStep: 0,
        totalSteps: 10,
        message: '開始更新...',
      ),
    );

    try {
      final pending = _updateService.runDailyUpdate(
        force: force,
        onProgress: (current, total, message) {
          state = state.copyWith(
            updateProgress: UpdateProgress(
              currentStep: current,
              totalSteps: total,
              message: message,
            ),
          );
        },
      );
      // 手動 race 取代 Future.timeout:SDK 的 timeout 內部 handler 在嚴格
      // custom zone(如 fakeAsync)會觸發「error handler must return a value
      // of the returned future's type」;Future.any + 可取消 Timer 語意相同
      // 且 zone-safe。
      final timeoutSignal = Completer<UpdateResult?>();
      final timeoutTimer = Timer(_updateTimeout, () {
        if (!timeoutSignal.isCompleted) timeoutSignal.complete(null);
      });
      final UpdateResult result;
      try {
        final winner = await Future.any<UpdateResult?>([
          pending,
          timeoutSignal.future,
        ]);
        if (winner == null) {
          // 逾時只放棄等待,底層 runDailyUpdate 不可取消、仍在跑
          // (2026-07-30 審查):它日後成功時必須補跑快取失效 + epoch
          // bump,否則各 provider 永遠不知道 DB 已有新一輪資料、UI 停在
          // 逾時錯誤。失敗則靜默(比照 market_overview 的背景收尾模式)。
          unawaited(() async {
            try {
              await pending;
              _cachedDb.invalidateCache();
              ref.read(dataUpdateEpochProvider.notifier).bump();
            } catch (_) {
              // 底層更新最終失敗:逾時錯誤已呈現給使用者,這裡靜默
            }
          }());
          throw TimeoutException('更新作業超時，請檢查網路連線後重試', _updateTimeout);
        }
        result = winner;
      } finally {
        timeoutTimer.cancel();
      }

      state = state.copyWith(isUpdating: false, updateProgress: null);

      // 更新後使快取失效（資料已變更）
      _cachedDb.invalidateCache();

      // 檢查價格警示並觸發通知
      final alertsTriggered = await _checkPriceAlerts(
        result.currentPrices,
        result.priceChanges,
      );

      // 若有警示被觸發，顯示更新完成通知
      if (alertsTriggered > 0) {
        final notificationNotifier = ref.read(notificationProvider.notifier);
        await notificationNotifier.showUpdateCompleteNotification(
          alertsTriggered: alertsTriggered,
        );
      }

      // 通知其他依賴 daily_* 表的 provider（scan / watchlist / performance
      // 等）資料已寫入新一輪，讓它們透過 ref.listen(dataUpdateEpochProvider)
      // 自行 reload。在 await loadData 前 bump 確保 listener 邏輯與 today
      // 本地 reload 並行。
      ref.read(dataUpdateEpochProvider.notifier).bump();

      // 更新後重新載入資料（含大盤總覽 Dashboard）
      await Future.wait([
        loadData(),
        ref.read(marketOverviewProvider.notifier).loadData(),
      ]);
      _ackedSnapshot = _snapshot;

      // loadData() / marketOverview.loadData() 內部 catch 不會 rethrow，
      // 但會設定各自的 state.error。若重新載入失敗，加入 errors 讓
      // summary 顯示警告而非純成功
      if (state.error != null) {
        result.errors.add(state.error!);
      }
      final marketError = ref.read(marketOverviewProvider).error;
      if (marketError != null) {
        result.errors.add(marketError);
      }

      return result;
    } on TimeoutException catch (e) {
      state = state.copyWith(
        isUpdating: false,
        updateProgress: null,
        error: e.message ?? '更新超時',
      );
      rethrow;
    } catch (e) {
      state = state.copyWith(
        isUpdating: false,
        updateProgress: null,
        error: ErrorDisplay.message(e),
      );
      rethrow;
    }
  }

  /// 檢查目前價格是否觸發價格警示並發送通知
  ///
  /// 回傳已觸發的警示數量
  Future<int> _checkPriceAlerts(
    Map<String, double> currentPrices,
    Map<String, double> priceChanges,
  ) async {
    if (currentPrices.isEmpty) return 0;

    try {
      // 確保通知服務已初始化
      final notificationState = ref.read(notificationProvider);
      if (!notificationState.isInitialized) {
        await ref.read(notificationProvider.notifier).initialize();
      }

      // 🚨 先確認能通知,再檢查(2026-08-08 三次審查 C-2)。
      // checkAndTriggerAlerts 內部走 claimAlertTrigger,會把到價的提醒
      // 標成 isActive=false + triggeredAt=now。若之後才發現通知發不出去
      // (showPriceAlertNotification 在無權限時是靜默 return),該筆就
      // **兩條路徑都撿不到**:使用者沒收到,盤中 CLI 的 pending 過濾也
      // 會永久跳過它。盤中輪詢與 launchd CLI 都有這道守門,只有這條漏了。
      if (!ref.read(notificationProvider).hasPermission) {
        AppLogger.error(
          'TodayNotifier',
          '無通知權限,跳過價格警示檢查——不可先認領再發現叫不出來',
          StateError('notification permission denied'),
        );
        return 0;
      }

      final alertNotifier = ref.read(priceAlertProvider.notifier);
      final notificationNotifier = ref.read(notificationProvider.notifier);

      // 檢查並觸發警示
      final triggered = await alertNotifier.checkAndTriggerAlerts(
        currentPrices,
        priceChanges,
      );

      // 為每個被觸發的警示發送通知。逐筆獨立 try:一筆失敗不可讓後面的
      // 連 try 都沒 try(它們已經被 claim 掉,漏掉就是永久遺失)。
      var notified = 0;
      for (final c in triggered) {
        final alert = c.alert;
        try {
          // 依**回傳值**而非例外(四次審查 C-1):最常見的失敗(無權限、
          // 設定把該類通知關掉)是靜默 return,靠 catch 補償不會啟動。
          // 舊版還把靜默 no-op 算進 notified,「更新完成」報灌水數字。
          final sent = await notificationNotifier.showPriceAlertNotification(
            alert,
            currentPrice: currentPrices[alert.symbol],
          );
          // DB 寫入也要在 try 內(五次審查 I-2),理由見 intraday_monitor
          if (sent) {
            notified++;
            await ref
                .read(databaseProvider)
                .consumeAlertClaim(alert.id, stamp: c.claimStamp);
          } else {
            await ref
                .read(databaseProvider)
                .releaseAlertClaim(alert.id, stamp: c.claimStamp);
          }
        } catch (e, s) {
          AppLogger.error(
            'TodayNotifier',
            '通知或狀態寫入失敗 id=${alert.id} ${alert.symbol}',
            e,
            s,
          );
        }
      }

      return notified;
    } catch (e) {
      // 非關鍵錯誤：警示檢查失敗不應導致更新失敗
      AppLogger.warning('TodayNotifier', '價格警示檢查失敗', e);
      return 0;
    }
  }
}

/// 今日畫面 State 的 Provider
final todayProvider = NotifierProvider<TodayNotifier, TodayState>(
  TodayNotifier.new,
);
