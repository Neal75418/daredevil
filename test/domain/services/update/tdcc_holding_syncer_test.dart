import 'package:daredevil/core/utils/clock.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/data/remote/tdcc_client.dart';
import 'package:daredevil/domain/services/update/tdcc_holding_syncer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockAppDatabase extends Mock implements AppDatabase {}

class MockTdccClient extends Mock implements TdccClient {}

class _FixedClock implements AppClock {
  const _FixedClock(this.fixed);
  final DateTime fixed;
  @override
  DateTime now() => fixed;
}

/// TDCC 股權分散表每週公布一次（資料日＝當週最後交易日），一次下載約
/// 9.8 MB。原本的新鮮度判斷是 `isSameWeek(資料日, 今天)`——資料日是上週五、
/// 今天是本週一到五，永遠不同週，於是每一輪更新都重抓（日誌 26 輪下載 19
/// 次、跳過 0 次；同一天 15:30 與 21:30 各抓一次）。
void main() {
  late MockAppDatabase db;
  late MockTdccClient tdcc;

  setUp(() {
    db = MockAppDatabase();
    tdcc = MockTdccClient();
    when(() => tdcc.getAllHoldingDistribution()).thenAnswer((_) async => {});
  });

  Future<void> syncAt(DateTime now, {required DateTime? latestDataDate}) {
    when(
      () => db.getLatestHoldingDistributionDate(any()),
    ).thenAnswer((_) async => latestDataDate);
    return TdccHoldingSyncer(
      database: db,
      tdccClient: tdcc,
      clock: _FixedClock(now),
    ).sync();
  }

  final lastFriday = DateTime(2026, 9, 18);

  test('🚨 上週五的資料、本週四晚上：未滿一週不重抓', () async {
    await syncAt(DateTime(2026, 9, 24, 21, 30), latestDataDate: lastFriday);
    verifyNever(() => tdcc.getAllHoldingDistribution());
  });

  test('上週五的資料、本週一：不重抓', () async {
    await syncAt(DateTime(2026, 9, 21, 15, 30), latestDataDate: lastFriday);
    verifyNever(() => tdcc.getAllHoldingDistribution());
  });

  test('滿一週（本週五）就該抓新一期', () async {
    await syncAt(DateTime(2026, 9, 25, 15, 30), latestDataDate: lastFriday);
    verify(() => tdcc.getAllHoldingDistribution()).called(1);
  });

  test('週五休市、資料日落在週四：下週四就該抓', () async {
    await syncAt(
      DateTime(2026, 9, 24, 15, 30),
      latestDataDate: DateTime(2026, 9, 17),
    );
    verify(() => tdcc.getAllHoldingDistribution()).called(1);
  });

  test('DB 還沒有資料：一定要抓', () async {
    await syncAt(DateTime(2026, 9, 24, 15, 30), latestDataDate: null);
    verify(() => tdcc.getAllHoldingDistribution()).called(1);
  });
}
