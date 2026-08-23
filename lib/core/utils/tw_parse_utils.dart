import 'package:daredevil/core/constants/api_config.dart';
import 'package:daredevil/core/utils/date_context.dart';

/// 台灣股市 API 回應的共用解析工具
///
/// 提供 TWSE 與 TPEX API 回應中常見的日期與數字格式解析。
/// 統一由 [TwseClient] 和 [TpexClient] 使用，避免重複邏輯。
abstract final class TwParseUtils {
  /// 解析含逗號的數字字串（例如 "1,234,567"）
  ///
  /// 支援 TWSE/TPEX 回傳的各種格式：
  /// - "1,234,567" → 1234567.0
  /// - "--" / "X" / "---" → null
  /// - null / 空字串 → null
  /// [parseFormattedDouble] 的整數版——千分位、哨兵(`--`/`X`/`---`)、
  /// 前後空白一併處理。
  ///
  /// 2026-08-15 數值稽核:19 處土製 `replaceAll(',','')+tryParse` 中只有
  /// 2 處先 trim,其餘遇到帶空白的欄位會整個 parse 失敗、靜靜落 0。
  static int? parseFormattedInt(dynamic value) {
    if (value == null) return null;
    final str = value.toString().replaceAll(',', '').trim();
    if (str.isEmpty || str == '--' || str == 'X' || str == '---') return null;
    return int.tryParse(str);
  }

  static double? parseFormattedDouble(dynamic value) {
    if (value == null) return null;
    final str = value.toString().replaceAll(',', '').trim();
    if (str.isEmpty || str == '--' || str == 'X' || str == '---') return null;
    return double.tryParse(str);
  }

  /// 解析**價格欄位**（開高低收）：在 [parseFormattedDouble] 之上把 0 也
  /// 視為無價 → null。
  ///
  /// TWSE 端點對「無成交」的表達不一致：MI_INDEX 用 `--`、STOCK_DAY_ALL
  /// （CSV/JSON）用 `0.00`。台股價格下限 0.01，0 不可能是真值——存 0 會
  /// 污染 52 週窗（min 永遠 0）與漲跌計算（顯示 -100%）。
  /// **僅限價格欄**：volume=0（無量）與 change=0（平盤）是合法值，
  /// 維持 [parseFormattedDouble]。
  static double? parsePrice(dynamic value) {
    final parsed = parseFormattedDouble(value);
    if (parsed == null || parsed == 0) return null;
    return parsed;
  }

  /// 解析 YYYYMMDD 格式的西元日期（例如 "20260121"），**無效時回 null**。
  ///
  /// 回傳本地時間午夜以匹配資料庫儲存格式。無效的定義：長度非 8、非數字、
  /// 年份早於 [ApiConfig.minSaneAdYear]、月日越界，或日期被 `DateTime`
  /// 正規化（例如 2/30 → 3/2）。
  ///
  /// **防護動機**：API 偶爾回傳髒日期字串（例如 `00001218`），早期僅檢查長度
  /// 而未驗證內容，導致 `0000-12-18` 等錯誤年份寫入 DB 並污染走勢圖與均線。
  ///
  /// [parseAdDate] 的嚴格版。當日期本身就是「這批資料屬於哪天」的唯一依據時
  /// （例如上櫃當沖端點無視請求日期、只能信回應的 `date`），回退成今天會把
  /// 最新資料寫成錯誤日期且毫無訊號——那種情況必須拿 null 整批丟棄。
  static DateTime? parseAdDateOrNull(String? dateStr) {
    if (dateStr == null || dateStr.length != 8) return null;

    final year = int.tryParse(dateStr.substring(0, 4));
    final month = int.tryParse(dateStr.substring(4, 6));
    final day = int.tryParse(dateStr.substring(6, 8));
    if (year == null || month == null || day == null) return null;

    if (year < ApiConfig.minSaneAdYear) return null;
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;

    final date = DateTime(year, month, day);
    // 驗證日期未被正規化（例如 2/30 會變成 3/2，表示原始日期無效）
    if (date.month != month || date.day != day) return null;
    return date;
  }

  /// [parseAdDateOrNull] 的寬鬆版：無效時回**今日午夜**。
  ///
  /// 適用於「日期只是輔助、資料本身另有來源」的路徑。若日期就是「這批資料
  /// 屬於哪天」的唯一依據（例如上櫃當沖端點無視請求日期、只能信回應的
  /// `date`），必須用嚴格版——回退成今天會把最新資料寫成錯誤日期且毫無訊號。
  static DateTime parseAdDate(String dateStr) =>
      parseAdDateOrNull(dateStr) ?? DateContext.normalize(DateTime.now());

  /// 解析含斜線的民國日期（例如 "115/01/02"）
  ///
  /// 包含日期驗證（月份 1-12、日期不被正規化）。
  /// 無效日期時回傳 null，由呼叫端決定如何處理。
  static DateTime? parseSlashRocDate(String dateStr) {
    final parts = dateStr.split('/');
    if (parts.length != 3) return null;

    final rocYear = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final day = int.tryParse(parts[2]);

    if (rocYear == null || month == null || day == null) return null;
    if (rocYear <= 0 || month < 1 || month > 12 || day < 1 || day > 31) {
      return null;
    }

    final date = DateTime(rocYear + ApiConfig.rocYearOffset, month, day);
    // 驗證日期未被正規化（例如 2/30 會變成 3/2，表示原始日期無效）
    if (date.month != month || date.day != day) return null;
    return date;
  }

  /// 解析緊湊格式民國日期（例如 "1150120" → 民國 115 年 01 月 20 日）
  ///
  /// 包含完整日期驗證。無效日期時回傳 null。
  static DateTime? parseCompactRocDate(String? dateStr) {
    if (dateStr == null || dateStr.length < 7) return null;

    final rocYear = int.tryParse(dateStr.substring(0, 3));
    final month = int.tryParse(dateStr.substring(3, 5));
    final day = int.tryParse(dateStr.substring(5, 7));

    if (rocYear == null || month == null || day == null) return null;
    if (rocYear <= 0 || month < 1 || month > 12 || day < 1 || day > 31) {
      return null;
    }

    final date = DateTime(rocYear + ApiConfig.rocYearOffset, month, day);
    if (date.month != month || date.day != day) return null;
    return date;
  }

  /// 將 DateTime 轉為民國日期字串（格式: "114/01/24"）
  static String toRocDateString(DateTime date) {
    final rocYear = date.year - ApiConfig.rocYearOffset;
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$rocYear/$month/$day';
  }

  /// 格式化日期為 ISO 風格字串（"2024-01-24"）
  static String formatDateYmd(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  /// 格式化日期為緊湊西元格式（"20240124"），供 TWSE API 查詢用
  static String formatDateCompact(DateTime date) {
    return '${date.year}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}';
  }
}
