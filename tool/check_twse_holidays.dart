// tool/check_twse_holidays.dart
//
// CLI tool — print 為預期輸出，關閉 avoid_print lint。
// ignore_for_file: avoid_print
//
// 以證交所官方「市場開休市日期」核對 TaiwanCalendar 的休市日。
//
// 用途：每年證交所公告隔年休市日後（通常在年底），跑一次，把差異補進
// lib/core/utils/taiwan_calendar.dart，並把該年來源改成 CalendarSource.twse。
// 靠人工推算不可靠：2026-09 核對時，原本推估的 2027 清單錯了 10 天。
//
// 使用方式：
//   dart run tool/check_twse_holidays.dart 2027
//
// 以 `date=<年>0101` 指定年份（`queryYear` 參數會被 API 忽略、一律回今年）。
// 證交所尚未公告的年份回傳空清單；工具偵測到空清單或年份不符會直接說明、
// 不做比對。颱風停市等臨時休市不在年度公告裡，會列為「只在程式裡」。

import 'dart:convert';
import 'dart:io';

import 'package:meta/meta.dart';

import 'package:daredevil/core/utils/taiwan_calendar.dart';

/// 證交所回應（每列：日期、名稱、說明）中的平日休市日。
///
/// 「開始交易日」「最後交易日」是有交易的日子，週末本來就休市，都不列。
@visibleForTesting
Set<DateTime> twseClosedWeekdays(List<List<dynamic>> rows) => {
  for (final row in rows)
    if (_isClosure(row[1] as String))
      if (DateTime.parse(row[0] as String) case final d
          when d.weekday <= DateTime.friday)
        DateTime.utc(d.year, d.month, d.day),
};

bool _isClosure(String name) =>
    !name.contains('開始交易') && !name.contains('最後交易');

@visibleForTesting
({List<DateTime> missingInCode, List<DateTime> extraInCode}) diffHolidays({
  required Set<DateTime> code,
  required Set<DateTime> twse,
}) => (
  missingInCode: (twse.difference(code).toList()..sort()),
  extraInCode: (code.difference(twse).toList()..sort()),
);

/// 證交所「市場開休市日期」API 網址。年份要用 `date=<年>0101` 指定：
/// `queryYear` 參數會被忽略、一律回今年（2026-09-26 實測）。
@visibleForTesting
Uri twseHolidayUri(int year) => Uri.https(
  'www.twse.com.tw',
  '/holidaySchedule/holidaySchedule',
  {'response': 'json', 'date': '${year}0101'},
);

/// 程式判定的平日休市日（逐日問 [TaiwanCalendar.isTradingDay]，不讀私有清單）
Set<DateTime> _codeClosedWeekdays(int year) => {
  for (
    var d = DateTime.utc(year, 1, 1);
    d.year == year;
    d = d.add(const Duration(days: 1))
  )
    if (d.weekday <= DateTime.friday && !TaiwanCalendar.isTradingDay(d)) d,
};

String _ymd(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

Future<void> main(List<String> args) async {
  final year = args.isEmpty ? null : int.tryParse(args.first);
  if (year == null) {
    stderr.writeln('用法: dart run tool/check_twse_holidays.dart <西元年>');
    exit(64);
  }

  final uri = twseHolidayUri(year);
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
  final Map<String, dynamic> body;
  try {
    final res = await (await client.getUrl(
      uri,
    )).close().timeout(const Duration(seconds: 30));
    final text = await res.transform(utf8.decoder).join();
    if (res.statusCode != 200) {
      stderr.writeln('[check_twse_holidays] 證交所回應 HTTP ${res.statusCode}');
      exit(3);
    }
    try {
      body = json.decode(text) as Map<String, dynamic>;
    } on FormatException {
      stderr.writeln('[check_twse_holidays] 證交所回應不是 JSON（可能被限流），稍後再試');
      exit(3);
    }
  } finally {
    client.close();
  }

  final rows = (body['data'] as List).cast<List<dynamic>>();
  final years = {for (final r in rows) DateTime.parse(r[0] as String).year};
  if (!years.contains(year)) {
    final got = years.isEmpty ? '空清單' : '${years.join('、')} 年資料';
    print('證交所尚未公告 $year 年休市日（API 回傳$got）。');
    exit(2);
  }

  final diff = diffHolidays(
    code: _codeClosedWeekdays(year),
    twse: twseClosedWeekdays(rows),
  );
  final names = {for (final r in rows) r[0] as String: r[1] as String};

  print('$year 年平日休市日核對（證交所 vs TaiwanCalendar）');
  if (diff.missingInCode.isEmpty && diff.extraInCode.isEmpty) {
    print('✅ 一致');
    return;
  }
  for (final d in diff.missingInCode) {
    print('❌ 程式漏列：${_ymd(d)} ${names[_ymd(d)] ?? ''}');
  }
  for (final d in diff.extraInCode) {
    print('⚠️ 只在程式裡：${_ymd(d)}（颱風停市等臨時休市屬正常；否則是多列）');
  }
  exit(1);
}
