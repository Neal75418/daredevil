import 'package:timezone/data/latest.dart' as tz_data;
import 'package:meta/meta.dart';
import 'package:timezone/timezone.dart' as tz;

import 'package:daredevil/core/utils/device_time.dart';

/// 台灣時區工具
///
/// 確保交易日計算使用 Asia/Taipei (UTC+8) 時區，
/// 避免使用者設備在不同時區時導致交易日判斷錯誤。
///
/// 時區資料庫會在首次使用時自動初始化。
class TaiwanTime {
  TaiwanTime._();

  /// Asia/Taipei 時區（首次存取時自動初始化）
  static final tz.Location _location = _initLocation();

  static tz.Location _initLocation() {
    tz_data.initializeTimeZones();
    return tz.getLocation('Asia/Taipei');
  }

  /// 測試用時鐘覆寫(2026-08-14):公布期入口等日期閘控 widget 沒有
  /// 時鐘縫就永遠測不了(測試會隨月曆日期變綠變紅)。production 恆為
  /// null,零開銷;測試設定後必須在 tearDown 歸還 null。
  ///
  /// 三個時間縫的分工,不要再開第四個:
  /// - `AppClock`(core/utils/clock.dart):DI 縫,能注入的新程式碼優先用它;
  /// - 本欄位:呼叫本類 static 的 widget 注入不到時,單一測試固定時間;
  /// - `DeviceTime.debugShift`:整套測試一起往後撥(找時間炸彈),本類的
  ///   [now] 也從它換算。
  @visibleForTesting
  static DateTime Function()? debugNowOverride;

  /// 取得目前台灣時間
  ///
  /// 回傳一般 DateTime（非 TZDateTime），避免 TZDateTime 在
  /// Drift 等框架中傳播造成非預期行為。
  static DateTime now() {
    final override = debugNowOverride;
    if (override != null) return override();
    final tzNow = tz.TZDateTime.from(DeviceTime.now(), _location);
    return DateTime(
      tzNow.year,
      tzNow.month,
      tzNow.day,
      tzNow.hour,
      tzNow.minute,
      tzNow.second,
    );
  }

  /// 取得今日台灣日期（午夜）
  static DateTime today() {
    final n = now(); // 經由 now() 讓 debugNowOverride 一併生效
    return DateTime(n.year, n.month, n.day);
  }
}
