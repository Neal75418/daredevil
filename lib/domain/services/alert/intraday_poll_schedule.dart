import 'package:daredevil/core/constants/market_session.dart';
import 'package:daredevil/core/constants/rule_params_alert.dart';
import 'package:daredevil/core/utils/taiwan_calendar.dart';

/// 盤中輪詢排程(2026-08-07 設計、2026-08-08 實作)。
///
/// 決策核心——**現在該不該打 API、多久打一次**:
/// - 完全沒掛條件 → 不輪詢,只在四個決策時刻檢查一次
/// - 有掛條件(armed) → [AlertParams.armedPollMinutes],使用者已明示在意
///   這些價位,檔數自限所以噪音有界
///
/// 原設計還有第三段「觸價後升為 1 分鐘緊盯」,**2026-08-08 移除**:觸發
/// 即停用提醒(`claimAlertTrigger`),結構上不存在「已觸價但仍在監控」的
/// 狀態,該段永遠不可能啟動。要復活它需要先有「觀察中」的資料模型與
/// 消費它的 UI,不是調參數的事。
///
/// 為什麼不一律高頻:v3.3 的判定是「收盤才定案」,盤中破了又拉回是常態
/// (2026-08-07 實例:貿聯盤中 −7.8% 觸 10MA 又收復、緯創破 5MA 又站回)。
/// 每 5 分鐘掃全部自選會噴出一堆「跌破又收復」的假警報,一週後使用者
/// 就會關掉通知——那才是真正的錯過。
abstract final class IntradayPollSchedule {
  /// [now] 是否落在可輪詢的盤中時段(交易日 + 交易時間)。13:30 那一分鐘
  /// 也算;盤中即時報價則以 13:30 起為收盤後(`LiveQuoteSchedule.phaseAt`)。
  static bool isMarketHours(DateTime now) {
    if (!TaiwanCalendar.isTradingDay(now)) return false;
    final minutes = now.hour * 60 + now.minute;
    return minutes >= MarketSession.openMinutes &&
        minutes <= MarketSession.closeMinutes;
  }

  /// 下一次輪詢間隔;null=此刻不需要主動輪詢(交給決策時刻)
  static Duration? nextInterval({required int armedCount}) {
    if (armedCount > 0) {
      return const Duration(minutes: AlertParams.armedPollMinutes);
    }
    return null;
  }

  /// [now] 是否為背景決策時刻(見 [AlertParams.backgroundCheckpoints])。
  ///
  /// 對齊決策而非固定頻率:09:15=跳空是否讓條件單作廢(v3.3 L5)、
  /// 11:00=午盤中段、13:00=收盤前還來得及動作、13:25=最接近定案。
  static bool isCheckpoint(DateTime now) {
    if (!isMarketHours(now)) return false;
    return AlertParams.backgroundCheckpoints.any(
      (cp) => cp.$1 == now.hour && cp.$2 == now.minute,
    );
  }
}
