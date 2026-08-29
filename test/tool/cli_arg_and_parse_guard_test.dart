// CLI 參數驗證與日期解析的守門(2026-08-29 tool 稽核 #13 / #17)
//
// 這兩條的共同點是**錯得看起來像成功**:打錯的旗標被默默忽略、
// 2033 年後的秒級時戳「解析成功」但解成 1970。
import 'package:flutter_test/flutter_test.dart';

import '../../tool/backfill_tpex_day_trading.dart';
import '../../tool/check_db_range.dart';

void main() {
  group('未知旗標(稽核 #13)', () {
    test('🚨 --database 這種打錯字必須被抓出來,不得默默落回預設 DB', () {
      // 預設 DB 是 **production app DB**;`_strArg` 對「旗標不存在」與
      // 「旗標在最末」都回 null,於是打錯字的結果是無聲寫錯資料庫,
      // 而參數看起來像被接受了。
      expect(unknownFlags(['--database', '/tmp/x.db']), ['--database']);
    });

    test('已知旗標全部放行(不誤擋)', () {
      expect(
        unknownFlags(['--dry-run', '--all', '--years', '2', '--db', '/tmp/x']),
        isEmpty,
      );
    });

    test('值不是旗標,不得被當成未知旗標', () {
      expect(unknownFlags(['--db', '/tmp/--weird-path']), isEmpty);
    });

    test('🚨 帶值旗標出現在最末 → 報錯,不得與「沒給」混為一談', () {
      expect(danglingValueFlags(['--limit', '5', '--db']), ['--db']);
      expect(danglingValueFlags(['--db', '/tmp/x']), isEmpty);
    });
  });

  group('日期解析的 2033 時間炸彈(稽核 #17)', () {
    test('🚨 2033 年後的秒級時戳不得被當成毫秒', () {
      // 2035-01-01 的秒級時戳 = 2051222400 > 舊門檻 2000000000,
      // 舊碼會解成 1970-01-24 且**解析成功**——「無法解析」的分支不會
      // 觸發,錯的日期直接餵進兩年充足性判定。
      final d = parseFlexibleDateForTesting('2051222400');
      expect(d, isNotNull);
      expect(d!.year, 2035);
    });

    test('現在的秒級與毫秒級都解得對', () {
      expect(parseFlexibleDateForTesting('1772323200')?.year, 2026);
      expect(parseFlexibleDateForTesting('1772323200000')?.year, 2026);
    });

    test('ISO 字串照舊', () {
      expect(parseFlexibleDateForTesting('2026-08-29')?.month, 8);
    });

    test('🚨 離譜值回 null,不得給出錯的日期', () {
      // 寧可讓上游印「無法解析」,也不要一個看起來像日期的錯答案
      expect(parseFlexibleDateForTesting('1'), isNull);
      expect(parseFlexibleDateForTesting('999999999999999'), isNull);
    });
  });
}
