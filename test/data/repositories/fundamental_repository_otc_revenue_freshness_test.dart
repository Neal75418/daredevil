// 上櫃營收新鮮度檢查 — 發布行事曆感知
//
// bug：原檢查為「最新資料的 revenueYear/Month == 當下年月才算新鮮」，但台股
// 月營收於**次月 10 日前**公布。任何時候 DB 裡能有的最新月都不會是當月，
// 所以 `isCurrentMonth` 恆為 false → 每次更新都判定全部需要同步、白打
// TPEX API。與 `fundamental_repository_income_freshness_test.dart` 同一
// bug class（時間啟發式 vs 發布進度感知）。
//
// 判準刻意用「上一個月」而非 `TaiwanCalendar.expectedLatestRevenueMonth`：
// 後者在 1–10 日保守退兩個月（它服務 FinMind 回補，誤判缺月要付額度），
// 用在這裡會讓每月 1–10 日整批上櫃股跳過同步。TPEX 端點免費且 memoize，
// 誤抓只是一次快取內呼叫，故取 M-1 讓公布期逐輪重試、自動收斂。
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:daredevil/core/utils/clock.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/data/remote/finmind_client.dart';
import 'package:daredevil/data/remote/mops_client.dart';
import 'package:daredevil/data/remote/tpex_client.dart';
import 'package:daredevil/data/remote/twse_client.dart';
import 'package:daredevil/data/repositories/fundamental_repository.dart';

class MockAppDatabase extends Mock implements AppDatabase {}

class MockFinMindClient extends Mock implements FinMindClient {}

class MockTwseClient extends Mock implements TwseClient {}

class MockTpexClient extends Mock implements TpexClient {}

class MockMopsClient extends Mock implements MopsClient {}

class _FixedClock implements AppClock {
  const _FixedClock(this._now);
  final DateTime _now;

  @override
  DateTime now() => _now;
}

void main() {
  late MockAppDatabase mockDb;
  late MockTpexClient mockTpex;

  setUpAll(() {
    registerFallbackValue(<MonthlyRevenueCompanion>[]);
  });

  FundamentalRepository buildRepo(DateTime now) => FundamentalRepository(
    mops: MockMopsClient(),
    db: mockDb,
    finMind: MockFinMindClient(),
    twse: MockTwseClient(),
    tpex: mockTpex,
    clock: _FixedClock(now),
  );

  setUp(() {
    mockDb = MockAppDatabase();
    mockTpex = MockTpexClient();
    when(
      () => mockTpex.getAllMonthlyRevenue(),
    ).thenAnswer((_) async => <TpexMonthlyRevenue>[]);
    when(() => mockDb.insertMonthlyRevenue(any())).thenAnswer((_) async {});
  });

  /// DB 已有 [year]/[month] 的營收
  void dbHas(int year, int month) {
    when(() => mockDb.getLatestMonthlyRevenuesBatch(any())).thenAnswer(
      (_) async => {
        '5483': MonthlyRevenueEntry(
          symbol: '5483',
          date: DateTime(year, month, 1),
          revenueYear: year,
          revenueMonth: month,
          revenue: 1000,
        ),
      },
    );
  }

  test('🚨 已有應公布的最新月（8/20 有 7 月）→ 跳過、不打 TPEX', () async {
    dbHas(2026, 7);

    final count = await buildRepo(
      DateTime(2026, 8, 20),
    ).syncOtcRevenue(['5483']);

    expect(count, 0);
    verifyNever(() => mockTpex.getAllMonthlyRevenue());
  });

  test('缺應公布的最新月（8/20 只有 6 月）→ 重抓', () async {
    dbHas(2026, 6);

    await buildRepo(DateTime(2026, 8, 20)).syncOtcRevenue(['5483']);

    verify(() => mockTpex.getAllMonthlyRevenue()).called(1);
  });

  test('🚨 公布期（8/5 只有 6 月）→ 仍重抓，不得整批跳過十天', () async {
    dbHas(2026, 6);

    await buildRepo(DateTime(2026, 8, 5)).syncOtcRevenue(['5483']);

    verify(() => mockTpex.getAllMonthlyRevenue()).called(1);
  });

  test('公布期已追上（8/5 已有 7 月）→ 跳過', () async {
    dbHas(2026, 7);

    await buildRepo(DateTime(2026, 8, 5)).syncOtcRevenue(['5483']);

    verifyNever(() => mockTpex.getAllMonthlyRevenue());
  });

  test('🚨 跨年：1/5 已有前一年 12 月 → 跳過', () async {
    dbHas(2025, 12);

    await buildRepo(DateTime(2026, 1, 5)).syncOtcRevenue(['5483']);

    verifyNever(
      () => mockTpex.getAllMonthlyRevenue(),
      // year*100+month 的比較必須跨年正確：202512 >= 202512
    );
  });

  test('跨年：1/5 只有前一年 11 月 → 重抓', () async {
    dbHas(2025, 11);

    await buildRepo(DateTime(2026, 1, 5)).syncOtcRevenue(['5483']);

    verify(() => mockTpex.getAllMonthlyRevenue()).called(1);
  });

  test('force 略過新鮮度檢查', () async {
    dbHas(2026, 7);

    await buildRepo(
      DateTime(2026, 8, 20),
    ).syncOtcRevenue(['5483'], force: true);

    verify(() => mockTpex.getAllMonthlyRevenue()).called(1);
  });
}
