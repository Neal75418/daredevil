import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:daredevil/core/exceptions/app_exception.dart';
import 'package:daredevil/core/utils/clock.dart';
import 'package:daredevil/core/utils/logger.dart';

/// API 供應商列舉（per-vendor budget）。
enum ApiVendor { finMind, twse, tpex, tdcc }

/// [ApiBudgetTracker] 的持久層抽象（實作：GUI 與 WorkManager 背景 isolate 用
/// `SharedPrefsApiBudgetStore`、launchd CLI 用 `FileApiBudgetStore`，兩者各存
/// 一份、不互通）。
///
/// 存在的理由：tracker 原本是純 process-local，**app 重啟即歸零**，但
/// FinMind 伺服器端的 hourly 額度不會忘記。2026-07-27 19:20 實測，重啟後
/// 本地計數 42/600、伺服器直接回 402——前一小時的約 560 次仍在它的窗內。
abstract class ApiBudgetStore {
  /// 讀回上次的狀態；無資料回 null。失敗請拋出，由 tracker fail-open 處理。
  Future<String?> load();

  /// 覆寫儲存的狀態。
  Future<void> save(String json);
}

/// 跨 syncer 共享的 API 配額追蹤器，sliding 1hr 視窗，狀態經 [ApiBudgetStore]
/// 跨重啟保存。
///
/// ## 動機
///
/// 過去各 syncer / repo 自己估配額消耗（[ApiConfig] 內常數 + per-syncer
/// circuit-breaker），且 `update_service` 平行跑 4 組 syncer 共用同一個
/// FinMind token — 2026-06 實測案例：HistoricalPriceSyncer 預算 300、
/// 實際各 syncer 加總打了 1125 calls，撞 hourly cap 整套 abort。
///
/// ## 設計選項（user 拍板）
///
/// - **per-vendor** 而非 per-endpoint：簡單，避免每個 method 都要查表
/// - **跨重啟保存**而非寫 DB：最初是 process-local、重啟即歸零，2026-07-27
///   實測重啟後伺服器仍記得前一小時的用量（見 [ApiBudgetStore]），改為經
///   store 保存
/// - **sliding 1hr** 視窗：FinMind free tier 是 rolling 600/hr，固定時段
///   reset 會撞 thundering herd。Sliding 比較準。
///
/// ## 整合方式
///
/// 1. Client（[FinMindClient] 等）建構時注入 tracker，呼叫前 `checkBudget`
///    用完即拋 [RateLimitException]、呼叫後 `recordCall` 紀錄。
/// 2. 偵測到 429 response 時 `markRateLimited` 翻 cooldown 旗標，往後 1hr
///    內 checkBudget 直接拒。
///
/// 暫定先掛 FinMindClient（600/hr free tier，實際 bottleneck）；
/// TWSE/TPEx OpenAPI 無實質限額、TDCC 用量極低，留 follow-up 評估。
class ApiBudgetTracker {
  ApiBudgetTracker({
    Map<ApiVendor, int>? hourlyBudget,
    AppClock clock = const SystemClock(),
    ApiBudgetStore? store,
  }) : _budget = hourlyBudget ?? _defaultBudget,
       _clock = clock,
       _store = store;

  final Map<ApiVendor, int> _budget;
  final AppClock _clock;
  final ApiBudgetStore? _store;

  /// 距上次落盤累積的 [recordCall] 次數。熱路徑每小時最多 600 次，
  /// 每次都寫 SharedPreferences 是浪費，故每 [_persistEveryNCalls] 次才寫。
  ///
  /// **遺失方向是放寬不是保守(2026-08-01 複審修正)**:崩潰/未 flush 漏記
  /// 的 ≤N-1 次會讓重啟後的本地計數**低估**真實用量 → checkBudget 放行
  /// 更多呼叫 → 正是持久化要防的 402 方向。因此 run 收尾必須顯式
  /// [flush](headless_update_runner 的 finally 已接),每 N 次的自動落盤
  /// 只是熱路徑的節流,不是完整性保證。
  int _callsSincePersist = 0;
  static const int _persistEveryNCalls = 10;

  /// 每個 vendor 的呼叫時間戳記隊列（FIFO，舊的會被踢出）
  final Map<ApiVendor, Queue<DateTime>> _callTimestamps = {};

  /// 因 429 翻起的 rate-limit cooldown 起點；null 代表未限流
  final Map<ApiVendor, DateTime?> _rateLimitedAt = {};

  /// FinMind free tier 600/hr 是實際 bottleneck；其餘 vendor 不會撞牆，
  /// 設大值僅作 safety net。
  static const Map<ApiVendor, int> _defaultBudget = {
    ApiVendor.finMind: 600,
    ApiVendor.twse: 10000,
    ApiVendor.tpex: 10000,
    ApiVendor.tdcc: 1000,
  };

  /// 取得指定 vendor 的 hourly budget。
  int budgetFor(ApiVendor vendor) =>
      _budget[vendor] ?? _defaultBudget[vendor] ?? 1000;

  /// 取得指定 vendor 過去 1hr 內已呼叫的次數（test/debug 用）。
  int callsInLastHourFor(ApiVendor vendor) {
    final queue = _callTimestamps[vendor];
    if (queue == null) return 0;
    _expireOldEntries(vendor);
    return queue.length;
  }

  /// 是否處於 cooldown（被 [markRateLimited] 翻起後 1hr 內）。
  bool isRateLimited(ApiVendor vendor) {
    final at = _rateLimitedAt[vendor];
    if (at == null) return false;
    if (_clock.now().difference(at) >= const Duration(hours: 1)) {
      _rateLimitedAt[vendor] = null;
      return false;
    }
    return true;
  }

  /// 在打 API 之前呼叫。被限流或預算用完拋 [RateLimitException]。
  void checkBudget(ApiVendor vendor) {
    if (isRateLimited(vendor)) {
      throw RateLimitException(
        '${vendor.name} API 已於 ${_rateLimitedAt[vendor]} 撞限流，1hr cooldown 中',
      );
    }

    _expireOldEntries(vendor);
    final used = _callTimestamps[vendor]?.length ?? 0;
    final budget = budgetFor(vendor);
    if (used >= budget) {
      throw RateLimitException(
        '${vendor.name} API hourly budget 已用完: $used/$budget calls',
      );
    }
  }

  /// 在 API call 發出後紀錄（成功或失敗都要記，否則 retry 也吃配額）。
  void recordCall(ApiVendor vendor) {
    final queue = _callTimestamps.putIfAbsent(vendor, () => Queue<DateTime>());
    queue.addLast(_clock.now());
    if (++_callsSincePersist >= _persistEveryNCalls) {
      unawaited(flush());
    }
  }

  /// 在收到 429 / 配額拒絕時呼叫，翻 cooldown 旗標、warning log。
  void markRateLimited(ApiVendor vendor) {
    _rateLimitedAt[vendor] = _clock.now();
    // 撞牆是關鍵事件：立即落盤，不等湊滿 N 次。否則重啟後會再打一輪才發現。
    unawaited(flush());
    AppLogger.warning(
      'ApiBudgetTracker',
      '${vendor.name} 撞 rate limit，1hr cooldown 開始 '
          '(已用 ${callsInLastHourFor(vendor)}/${budgetFor(vendor)})',
    );
  }

  /// 清掉 vendor queue 內超過 1hr 的舊 timestamp。
  void _expireOldEntries(ApiVendor vendor) {
    final queue = _callTimestamps[vendor];
    if (queue == null || queue.isEmpty) return;
    final cutoff = _clock.now().subtract(const Duration(hours: 1));
    while (queue.isNotEmpty && queue.first.isBefore(cutoff)) {
      queue.removeFirst();
    }
  }

  /// 從 [ApiBudgetStore] 讀回上次的呼叫紀錄與 cooldown。
  ///
  /// **必須在第一次 API 呼叫之前 await**（不可 fire-and-forget）：
  /// 建構是同步的、`checkBudget` 也是同步的，若讓載入與呼叫賽跑，
  /// 早期呼叫會看到空狀態——那正是本功能要修的 bug。
  ///
  /// 載入時一併丟掉超過 1 小時的紀錄：舊紀錄復活會永久壓低可用額度，
  /// 那是另一個方向的錯。
  ///
  /// **fail-open**：讀不到就當作沒有歷史（＝現況行為）。儲存故障不該讓
  /// 整個 app 打不了 API。
  ///
  /// 回傳實際載入了什麼，讓呼叫端能記到日誌。**沒有這個回報就無法驗證
  /// restore 有沒有生效**——「同一 session 累積」與「重啟後成功還原」在
  /// 磁碟狀態上完全相同（2026-07-27 實測 290 筆，兩種解釋都成立）。
  Future<({int restoredCalls, Set<ApiVendor> cooldownVendors})>
  restore() async {
    var restoredCalls = 0;
    final cooldownVendors = <ApiVendor>{};
    final store = _store;
    if (store == null) {
      return (restoredCalls: 0, cooldownVendors: cooldownVendors);
    }
    try {
      final raw = await store.load();
      if (raw == null || raw.isEmpty) {
        return (restoredCalls: 0, cooldownVendors: cooldownVendors);
      }
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final now = _clock.now();

      final calls = decoded['calls'] as Map<String, dynamic>? ?? const {};
      for (final entry in calls.entries) {
        final vendor = _vendorByName(entry.key);
        if (vendor == null) continue;
        // 過期判定只由 [_expireOldEntries] 一處負責——在此再濾一次是語意
        // 冗餘（2026-07-27 mutation 實測：拿掉這層過濾 17 條測試全綠，
        // 因為 callsInLastHourFor / checkBudget 都會先 expire）。留著會變成
        // 無人能區分的假保護。
        final stamps =
            (entry.value as List<dynamic>)
                .map((e) => DateTime.fromMillisecondsSinceEpoch(e as int))
                .toList()
              ..sort();
        if (stamps.isEmpty) continue;
        _callTimestamps[vendor] = Queue<DateTime>.from(stamps);
        _expireOldEntries(vendor);
        restoredCalls += _callTimestamps[vendor]?.length ?? 0;
      }

      final limited = decoded['rateLimitedAt'] as Map<String, dynamic>? ?? {};
      for (final entry in limited.entries) {
        final vendor = _vendorByName(entry.key);
        if (vendor == null) continue;
        final at = DateTime.fromMillisecondsSinceEpoch(entry.value as int);
        if (now.difference(at) >= const Duration(hours: 1)) continue;
        _rateLimitedAt[vendor] = at;
        cooldownVendors.add(vendor);
      }
    } catch (e) {
      AppLogger.warning('ApiBudgetTracker', '配額狀態載入失敗，本次視為無歷史', e);
    }
    return (restoredCalls: restoredCalls, cooldownVendors: cooldownVendors);
  }

  /// 把目前狀態寫回 [ApiBudgetStore]。失敗只記 warning（fail-open）。
  Future<void> flush() async {
    final store = _store;
    if (store == null) return;
    _callsSincePersist = 0;
    try {
      final cutoff = _clock.now().subtract(const Duration(hours: 1));
      await store.save(
        jsonEncode({
          'calls': {
            for (final e in _callTimestamps.entries)
              e.key.name: [
                for (final d in e.value)
                  if (!d.isBefore(cutoff)) d.millisecondsSinceEpoch,
              ],
          },
          'rateLimitedAt': {
            for (final e in _rateLimitedAt.entries)
              if (e.value != null) e.key.name: e.value!.millisecondsSinceEpoch,
          },
        }),
      );
    } catch (e) {
      AppLogger.warning('ApiBudgetTracker', '配額狀態寫入失敗', e);
    }
  }

  static ApiVendor? _vendorByName(String name) {
    for (final v in ApiVendor.values) {
      if (v.name == name) return v;
    }
    return null;
  }
}
