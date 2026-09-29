/// 西元年月（值型別）
///
/// 月份運算只用整數與 `DateTime(y, m, d)` 建構子，不用 [Duration]：跨月的
/// 天數不固定。[firstDay]／[lastDay] 是當地午夜，與 `DateContext.normalize`
/// 同一口徑。
class CalendarMonth implements Comparable<CalendarMonth> {
  const CalendarMonth(this.year, this.month)
    : assert(month >= 1 && month <= 12, 'month 必須在 1–12');

  /// [date] 所在的本地年月
  factory CalendarMonth.of(DateTime date) =>
      CalendarMonth(date.year, date.month);

  final int year;

  /// 1–12
  final int month;

  static final _pattern = RegExp(r'^(\d{4})-(0[1-9]|1[0-2])$');

  /// 解析 `YYYY-MM`（月份必須補零），其他格式回 null
  static CalendarMonth? tryParse(String text) {
    final match = _pattern.firstMatch(text);
    if (match == null) return null;
    return CalendarMonth(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
    );
  }

  /// [from]～[to]（含頭尾），由新到舊；[from] 晚於 [to] 時回空清單
  static List<CalendarMonth> descending({
    required CalendarMonth from,
    required CalendarMonth to,
  }) => [for (var m = to; !m.isBefore(from); m = m.previous) m];

  CalendarMonth addMonths(int months) {
    final index = year * 12 + (month - 1) + months;
    return CalendarMonth(index ~/ 12, index % 12 + 1);
  }

  CalendarMonth get previous => addMonths(-1);

  /// 當月 1 日（當地午夜）
  DateTime get firstDay => DateTime(year, month);

  /// 當月最後一天（當地午夜）
  DateTime get lastDay => DateTime(year, month + 1, 0);

  bool isBefore(CalendarMonth other) => compareTo(other) < 0;

  bool isAfter(CalendarMonth other) => compareTo(other) > 0;

  @override
  int compareTo(CalendarMonth other) =>
      (year * 12 + month) - (other.year * 12 + other.month);

  @override
  bool operator ==(Object other) =>
      other is CalendarMonth && other.year == year && other.month == month;

  @override
  int get hashCode => Object.hash(year, month);

  @override
  String toString() => '$year-${month.toString().padLeft(2, '0')}';
}
