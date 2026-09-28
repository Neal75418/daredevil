import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:daredevil/core/utils/logger.dart';
import 'package:daredevil/core/utils/taiwan_time.dart';
import 'package:daredevil/data/remote/intraday_quote_client.dart';
import 'package:daredevil/domain/services/alert/intraday_alert_monitor.dart';
import 'package:daredevil/domain/services/alert/intraday_poll_schedule.dart';
import 'package:daredevil/presentation/providers/notification_provider.dart';
import 'package:daredevil/presentation/providers/price_alert_provider.dart';
import 'package:daredevil/presentation/providers/providers.dart';

/// 盤中提醒輪詢(2026-08-08)。
///
/// **誠實的能力邊界**:這是 app 在前景時的計時器。iOS/macOS 不保證背景
/// 常駐執行,所以「app 關著也會提醒」做不到——要那個等級的守候,正確
/// 工具是券商的到價通知(毫秒級且能直接成交)。這裡的價值不是速度,是
/// **懂你的規則**(均線、守門價)並在觸價時把判讀材料一起端出來。
///
/// 節流:沒掛條件時完全不輪詢(見 [IntradayPollSchedule.nextInterval]),
/// 只在四個決策時刻各檢查一次。
class IntradayMonitorNotifier extends Notifier<DateTime?> {
  Timer? _timer;

  /// 「無通知權限」每個 session 只報一次——它是穩態不是事件(五次審查 I-3)
  bool _permissionDeniedReported = false;
  bool _running = false;

  /// 提升為欄位:原本每輪 new 一個(盤中 4.5 小時 ≈ 54 個),每個自帶
  /// keep-alive 連線池且永不關閉(2026-08-08 code review)。專案其他
  /// client 一律 provider 持有 + onDispose 關閉,這裡比照。
  IntradayQuoteClient? _client;

  @override
  DateTime? build() {
    ref.onDispose(() {
      _timer?.cancel();
      _client?.close();
    });
    return null;
  }

  /// 啟動輪詢(app 進前景時呼叫)。冪等。
  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => _tick());
    unawaited(_tick());
  }

  /// 停止(app 退背景時呼叫)——背景燒流量沒有意義,系統也可能隨時凍結
  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _tick() async {
    if (_running) return; // 前一輪還沒跑完就跳過,不堆疊請求
    final now = TaiwanTime.now();
    if (!IntradayPollSchedule.isMarketHours(now)) return;

    // 🚨 armed 必須查 DB,不能讀 UI 快取(2026-08-08 code review):
    // priceAlertProvider.alerts 在 loadAlerts() 跑過之前是空的,而畫面上
    // 只有提醒頁與個股警示分頁會呼叫它——使用者開在「今日」分頁就 armed=0,5 分鐘節奏
    // 靜默退化成一天四次,通知遲到最多兩小時。
    final int armed;
    try {
      armed = (await ref.read(databaseProvider).getActiveAlerts())
          .where((a) => a.triggeredAt == null)
          .length;
    } catch (e) {
      // _tick 是 fire-and-forget:例外不接住會逸出到 Sentry 的 appRunner
      // zone,而非走本方法其餘部分一致的 warning 路徑(2026-08-08 二次審查)
      AppLogger.warning('IntradayMonitor', '讀取待監控提醒失敗', e);
      return;
    }
    final interval = IntradayPollSchedule.nextInterval(armedCount: armed);
    // 沒掛條件時只在決策時刻檢查;有掛條件則依間隔節流
    final last = state;
    if (interval == null) {
      if (!IntradayPollSchedule.isCheckpoint(now)) return;
    } else if (last != null && now.difference(last) < interval) {
      return;
    }

    _running = true;
    try {
      // 🚨 通知必須先就緒才可以檢查(2026-08-08 code review HIGH-1)。
      // check() 會把觸價的提醒標成已觸發且停用——若之後才發現通知發不
      // 出去(provider 未 initialize / 無權限),提醒就被**靜默燒掉**:
      // 使用者沒收到通知,而收盤那條路徑也再也看不到它(已非 active)。
      // 因此順序必須是「先確認能通知 → 再檢查」,不能反過來。
      final notifier = ref.read(notificationProvider.notifier);
      await notifier.initialize();
      if (!ref.read(notificationProvider).hasPermission) {
        // ⚠️ 必須先前進 state 再 return(四次審查 I-2):節流條件看的是
        // state,不前進的話 Timer 每分鐘 tick 都會走到這裡。
        state = now;
        // 🔴 error 且**帶例外物件**(五次審查 I-3):`AppLogger._log` 對
        // 所有等級在 release build 都直接 return(輸出包在 assert 內),
        // 而 warning 只產生 Sentry breadcrumb——breadcrumb 要等別的 event
        // 被 capture 才會附帶送出,而這條路徑是乾淨 return、永遠不會有
        // 那個 event。降成 warning 等於讓「功能整個停擺」完全不可觀察。
        //
        // 量的問題不靠降級解決,靠**每個 session 只報一次**:上面補了
        // state = now 之後節流已生效,再加旗標就不會洗版。
        if (!_permissionDeniedReported) {
          _permissionDeniedReported = true;
          AppLogger.error(
            'IntradayMonitor',
            '無通知權限,盤中提醒全部跳過——使用者不會收到任何通知',
            StateError('notification permission denied'),
          );
        }
        return;
      }

      final monitor = IntradayAlertMonitor(
        database: ref.read(databaseProvider),
        client: _client ??= IntradayQuoteClient(),
      );
      final fired = (await monitor.check(now: now)).fired;
      state = now;
      // 逐筆獨立 try:check() 已把 fired 全部認領掉,若第 3 筆丟例外而
      // 讓迴圈中斷,第 4、5 筆連試都沒試就永久遺失(2026-08-08 三次審查)
      for (final f in fired) {
        try {
          // 依**回傳值**而非例外決定(四次審查 C-1):最常見的失敗
          // (無權限、設定關掉)是靜默 return,靠 catch 補償不會啟動。
          final sent = await ref
              .read(notificationProvider.notifier)
              .showPriceAlertNotification(f.alert, currentPrice: f.quote.price);
          // ⚠️ DB 寫入必須**也在 try 內**(五次審查 I-2):原本只包住通知,
          // 而這次改動讓 consume/release 從「只在罕見失敗路徑跑」變成
          // 「每一筆都跑」,曝險放大一個數量級。SqliteException(5) 在兩
          // process 共用同一檔的拓撲下是實際風險,一丟出來迴圈就中斷,
          // 剩餘已認領的提醒全部卡在 (isActive=true, triggeredAt≠null)。
          if (sent) {
            await ref
                .read(databaseProvider)
                .consumeAlertClaim(f.alert.id, stamp: f.claimStamp);
          } else {
            await ref
                .read(databaseProvider)
                .releaseAlertClaim(f.alert.id, stamp: f.claimStamp);
          }
        } catch (e, st) {
          AppLogger.error(
            'IntradayMonitor',
            '通知或狀態寫入失敗 id=${f.alert.id} ${f.alert.symbol}'
                '(該筆可能卡在已認領未消費,由 reclaim 回收)',
            e,
            st,
          );
        }
      }
      if (fired.isNotEmpty) {
        await ref.read(priceAlertProvider.notifier).loadAlerts();
      }
    } catch (e, s) {
      // error 而非 warning:AppLogger._log 對**所有等級**在 release build
      // 都直接 return(輸出包在 assert 內),只有 error 且帶例外物件才會
      // 走 _sentryCapture 產生真的 Sentry event(2026-08-08 三次審查 H-1)
      AppLogger.error('IntradayMonitor', '盤中輪詢失敗', e, s);
    } finally {
      _running = false;
    }
  }
}

final intradayMonitorProvider =
    NotifierProvider<IntradayMonitorNotifier, DateTime?>(
      IntradayMonitorNotifier.new,
    );
