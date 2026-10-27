// 上櫃每日行情的「不比價」標記（除權息漲跌修正 spec 第 3 節）
//
// daily_close_quotes 與 dailyQuotes 共用的列解析：漲跌欄在除權息日是文字
// （除息／除權／除權息；2026-10-27 兩個端點都實測），沒成交是 `---`。
// 兩者原本都解析成 null，分不開；市場日寫入要靠這個標記決定要不要抓
// exDailyQ 的開始交易基準價。
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/data/remote/tpex_client.dart';

void main() {
  final day = DateTime(2026, 10, 27);

  List<dynamic> row(String change) => [
    '9911',
    '測試',
    '32.12',
    change,
    '32.62',
    '32.70',
    '32.00',
    '32.30',
    '707,978',
    '22,000,000',
    '1,200',
    '32.11',
    '5',
    '32.12',
    '3',
    '707,978,000',
    '32.12',
    '35.33',
    '28.91',
  ];

  for (final (raw, change, flag) in const [
    ('除息', null, true),
    ('除權', null, true),
    ('除權息', null, true),
    ('---', null, false),
    ('--', null, false),
    ('', null, false),
    ('  ', null, false),
    ('+9.80', 9.8, false),
    ('-0.46', -0.46, false),
    ('0.00', 0.0, false),
  ]) {
    test('漲跌欄「$raw」→ change $change、noComparison $flag', () {
      final p = TpexClient.parseDailyPriceRow(row(raw), day)!;
      expect(p.change, change);
      expect(p.noComparison, flag);
    });
  }
}
