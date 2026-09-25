import 'package:daredevil/core/constants/data_freshness.dart';
import 'package:daredevil/core/utils/logger.dart';

/// 台灣股市交易日曆
///
/// 提供台灣證券交易所（TWSE）與櫃買中心（TPEx）的交易日驗證。
///
/// 資料來源：
/// - 台灣證券交易所官方休市公告
/// - https://www.twse.com.tw/
class TaiwanCalendar {
  TaiwanCalendar._();

  /// 是否已記錄過期警告（避免重複警告）
  static bool _hasLoggedExpiryWarning = false;

  /// 2024 年台股休市日
  static final Set<DateTime> _holidays2024 = {
    // 元旦
    DateTime.utc(2024, 1, 1),
    // 農曆春節 (2/8-2/14)
    DateTime.utc(2024, 2, 8),
    DateTime.utc(2024, 2, 9),
    DateTime.utc(2024, 2, 10),
    DateTime.utc(2024, 2, 11),
    DateTime.utc(2024, 2, 12),
    DateTime.utc(2024, 2, 13),
    DateTime.utc(2024, 2, 14),
    // 228 和平紀念日
    DateTime.utc(2024, 2, 28),
    // 兒童節/清明節 (4/4-4/5)
    DateTime.utc(2024, 4, 4),
    DateTime.utc(2024, 4, 5),
    // 勞動節
    DateTime.utc(2024, 5, 1),
    // 端午節 (6/10)
    DateTime.utc(2024, 6, 10),
    // 中秋節 (9/17)
    DateTime.utc(2024, 9, 17),
    // 國慶日
    DateTime.utc(2024, 10, 10),
  };

  /// 2025 年台股休市日
  static final Set<DateTime> _holidays2025 = {
    // 元旦
    DateTime.utc(2025, 1, 1),
    // 農曆春節 (1/27-2/4)
    DateTime.utc(2025, 1, 27),
    DateTime.utc(2025, 1, 28),
    DateTime.utc(2025, 1, 29),
    DateTime.utc(2025, 1, 30),
    DateTime.utc(2025, 1, 31),
    DateTime.utc(2025, 2, 1),
    DateTime.utc(2025, 2, 2),
    DateTime.utc(2025, 2, 3),
    DateTime.utc(2025, 2, 4),
    // 228 和平紀念日
    DateTime.utc(2025, 2, 28),
    // 兒童節/清明節 (4/3-4/4)
    DateTime.utc(2025, 4, 3),
    DateTime.utc(2025, 4, 4),
    // 勞動節
    DateTime.utc(2025, 5, 1),
    // 端午節 (5/30-6/2)
    DateTime.utc(2025, 5, 30),
    DateTime.utc(2025, 5, 31),
    DateTime.utc(2025, 6, 1),
    DateTime.utc(2025, 6, 2),
    // 教師節（9/28 週日，補假 9/29 週一；2025 新增國定假日）
    DateTime.utc(2025, 9, 29),
    // 中秋節 (10/6-10/7)
    DateTime.utc(2025, 10, 6),
    DateTime.utc(2025, 10, 7),
    // 國慶日
    DateTime.utc(2025, 10, 10),
    // 光復節（10/25 週六，補假 10/24 週五；2025 新增國定假日）
    DateTime.utc(2025, 10, 24),
    // 行憲紀念日（2025 新增國定假日）
    DateTime.utc(2025, 12, 25),
  };

  /// 2026 年台股休市日（預估）
  static final Set<DateTime> _holidays2026 = {
    // 元旦
    DateTime.utc(2026, 1, 1),
    // 農曆春節 (封關日 2/11 週三，2/12-2/20 休市)
    DateTime.utc(2026, 2, 12),
    DateTime.utc(2026, 2, 13),
    DateTime.utc(2026, 2, 14),
    DateTime.utc(2026, 2, 15),
    DateTime.utc(2026, 2, 16),
    DateTime.utc(2026, 2, 17),
    DateTime.utc(2026, 2, 18),
    DateTime.utc(2026, 2, 19),
    DateTime.utc(2026, 2, 20),
    // 228 和平紀念日（2/28 週六，補假 2/27 週五）
    DateTime.utc(2026, 2, 27),
    DateTime.utc(2026, 2, 28),
    // 兒童節/清明節 (4/3-4/6 estimated)
    DateTime.utc(2026, 4, 3),
    DateTime.utc(2026, 4, 4),
    DateTime.utc(2026, 4, 5),
    DateTime.utc(2026, 4, 6),
    // 勞動節
    DateTime.utc(2026, 5, 1),
    // 端午節 (6/19 estimated)
    DateTime.utc(2026, 6, 19),
    // 颱風停市（TWSE 證實 20260710 無交易資料）
    DateTime.utc(2026, 7, 10),
    // 中秋節 (9/25 estimated)
    DateTime.utc(2026, 9, 25),
    // 教師節（9/28 週一）
    DateTime.utc(2026, 9, 28),
    // 國慶日（10/10 週六，補假 10/9 週五）
    DateTime.utc(2026, 10, 9),
    DateTime.utc(2026, 10, 10),
    // 光復節（10/25 週日，補假 10/26 週一）
    DateTime.utc(2026, 10, 26),
    // 行憲紀念日（12/25 週五）
    DateTime.utc(2026, 12, 25),
  };

  /// 2027 年台股休市日（預估）
  ///
  /// 農曆日期根據萬年曆推算，實際日期以證交所公告為準
  static final Set<DateTime> _holidays2027 = {
    // 元旦
    DateTime.utc(2027, 1, 1),
    // 農曆春節 (2/5-2/11 estimated，農曆初一約 2/6)
    DateTime.utc(2027, 2, 5),
    DateTime.utc(2027, 2, 6),
    DateTime.utc(2027, 2, 7),
    DateTime.utc(2027, 2, 8),
    DateTime.utc(2027, 2, 9),
    DateTime.utc(2027, 2, 10),
    DateTime.utc(2027, 2, 11),
    // 228 和平紀念日（週日，補假週一）
    DateTime.utc(2027, 2, 28),
    DateTime.utc(2027, 3, 1),
    // 兒童節/清明節 (4/4-4/5 estimated)
    DateTime.utc(2027, 4, 4),
    DateTime.utc(2027, 4, 5),
    // 勞動節 (5/1 週六，不需列入，週末本來就休市)
    // 端午節 (6/9 estimated)
    DateTime.utc(2027, 6, 9),
    // 中秋節 (10/15 estimated)
    DateTime.utc(2027, 10, 15),
    // 國慶日（週日，補假週一）
    DateTime.utc(2027, 10, 10),
    DateTime.utc(2027, 10, 11),
  };

  /// 所有休市日彙總
  static final Set<DateTime> _allHolidays = {
    ..._holidays2024,
    ..._holidays2025,
    ..._holidays2026,
    ..._holidays2027,
  };

  /// 日曆資料涵蓋的最大年份
  static const int _maxYear = 2027;

  /// 檢查日期是否為台股交易日
  ///
  /// 符合以下條件回傳 true：
  /// - 非週末（週六、週日）
  /// - 非國定假日
  ///
  /// 若日期超出日曆資料範圍，會回落到週末判斷並記錄警告。
  static bool isTradingDay(DateTime date) {
    if (date.weekday == DateTime.saturday || date.weekday == DateTime.sunday) {
      return false;
    }

    // 檢查是否超出日曆資料範圍
    if (date.year > _maxYear) {
      _logExpiryWarningOnce(date.year);
      // 回落到週末判斷（假設平日都是交易日）
      return true;
    }

    final normalized = DateTime.utc(date.year, date.month, date.day);
    return !_allHolidays.contains(normalized);
  }

  /// 記錄過期警告（只記錄一次）
  static void _logExpiryWarningOnce(int year) {
    if (!_hasLoggedExpiryWarning) {
      _hasLoggedExpiryWarning = true;
      AppLogger.warning(
        'TaiwanCalendar',
        '日曆資料已過期：目前年份 $year 超出資料範圍 (最大 $_maxYear)，'
            '將回落到週末判斷。請更新日曆資料。',
      );
    }
  }

  /// 取得前一個交易日
  ///
  /// 若給定日期為交易日則直接回傳，否則回傳前一個交易日。
  static DateTime getPreviousTradingDay(DateTime date) {
    var current = date;
    while (!isTradingDay(current)) {
      current = current.subtract(const Duration(days: 1));
    }
    return current;
  }

  /// 從指定日期往前推 N 個交易日
  ///
  /// [addTradingDays] 的對稱操作——它的迴圈條件 `count < tradingDays` 對負值
  /// 立即為 false、會原樣回傳，故往前推必須用本方法。
  ///
  /// 資料新鮮度必須以**交易日**為單位：週一評估用上週五資料是 3 個日曆天但
  /// 只隔 1 個交易日，用日曆天判斷會把合法資料誤判為過期。
  static DateTime subtractTradingDays(DateTime date, int tradingDays) {
    if (tradingDays <= 0) return date;
    var current = date;
    var count = 0;
    var iterations = 0;
    final maxIterations = tradingDays * 5 + 14; // 安全上限（含 14 天連假緩衝）
    while (count < tradingDays && iterations < maxIterations) {
      current = current.subtract(const Duration(days: 1));
      iterations++;
      if (isTradingDay(current)) {
        count++;
      }
    }
    return current;
  }

  /// 從指定日期往後推 N 個交易日
  ///
  /// 例如：週五 +1 交易日 = 下週一（跳過週末）。
  static DateTime addTradingDays(DateTime date, int tradingDays) {
    var current = date;
    var count = 0;
    var iterations = 0;
    final maxIterations = tradingDays * 5 + 14; // 安全上限（含 14 天連假緩衝）
    while (count < tradingDays && iterations < maxIterations) {
      current = current.add(const Duration(days: 1));
      iterations++;
      if (isTradingDay(current)) {
        count++;
      }
    }
    return current;
  }

  /// 此刻應已發布的最新一季財報的**季度起始日**
  ///
  /// 依台股申報期限（Q1→5/15、Q2→8/14、Q3→11/14、年報→3/31）取保守月界。
  /// 與 financial_data 儲存的**季度截止日**（如 Q1 = 3/31）比較時，用
  /// `!latestDate.isBefore(expected)` 判斷「已有該季」——截止日必不早於
  /// 自身季度起始日、且早於下一季起始日。
  ///
  /// 新鮮度檢查必須用這個（發布行事曆感知），不能用「距今 N 天」啟發式：
  /// 財報日期是季度截止日，發布後只有 ~2-6 週會通過天數檢查，其餘時間
  /// 每次更新都會重抓（2026-07-14 實測損益表因此每輪多燒 54 檔 FinMind）。
  static DateTime expectedLatestReportQuarter(DateTime now) {
    final month = now.month;
    if (month >= 5 && month < 8) {
      return DateTime(now.year, 1, 1); // Q1（5/15 截止申報）
    } else if (month >= 8 && month < 11) {
      return DateTime(now.year, 4, 1); // Q2（8/14）
    } else if (month >= 11) {
      return DateTime(now.year, 7, 1); // Q3（11/14）
    } else if (month == 4) {
      return DateTime(now.year - 1, 10, 1); // Q4/年報（3/31 已截止）
    }
    // 1-3 月：年報 3/31 尚未截止，只能期待前一年 Q3。
    // ⚠️ 必須回 Q3 自身起始 7/1、不能回 10/1——Q3 截止日 9/30 < 10/1
    // 會被判「缺最新季」，1-3 月每輪更新都重抓（繼承 bug，review 修正）。
    return DateTime(now.year - 1, 7, 1);
  }

  /// 此刻應已有的最新一個交易日收盤資料日（回傳該日 0 點）
  ///
  /// 交易日 [DataFreshness.dailyDataReadyHour] 點後是當天；之前、或非交易日，
  /// 是前一個交易日。與 [expectedLatestReportQuarter] 同理由：「資料落後」
  /// 必須行事曆感知——週一早上的上週五資料、連假後的節前資料都不算過期。
  static DateTime expectedLatestTradingDataDate(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    if (isTradingDay(today) && now.hour >= DataFreshness.dailyDataReadyHour) {
      return today;
    }
    return getPreviousTradingDay(today.subtract(const Duration(days: 1)));
  }

  /// [dataDate] 比此刻應有的最新收盤資料落後幾個交易日（不為負）
  static int tradingDaysBehind(DateTime dataDate, DateTime now) {
    final expected = expectedLatestTradingDataDate(now);
    var day = DateTime(dataDate.year, dataDate.month, dataDate.day);
    var behind = 0;
    while (day.isBefore(expected)) {
      day = DateTime(day.year, day.month, day.day + 1);
      if (isTradingDay(day)) behind++;
    }
    return behind;
  }

  /// 此刻應已公布的最新一個「月營收」月份（回傳該月 1 日）
  ///
  /// 台股月營收於次月 10 日前公布。10 日當天視為未截止（保守：避免當天
  /// 早上尚未公布就誤判「缺最新月」而重抓），故 10 日含以前只能期待上上月。
  /// 與 [expectedLatestReportQuarter] 同理由：新鮮度檢查必須行事曆感知，
  /// 不能用「距今 N 天」啟發式。
  static DateTime expectedLatestRevenueMonth(DateTime now) {
    final monthsBack = now.day > 10 ? 1 : 2;
    return DateTime(now.year, now.month - monthsBack, 1);
  }
}
