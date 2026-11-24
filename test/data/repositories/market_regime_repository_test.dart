import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/data/repositories/analysis_repository.dart';
import 'package:daredevil/domain/models/market_regime.dart';

void main() {
  late AppDatabase db;
  late AnalysisRepository repo;

  setUp(() {
    db = AppDatabase.forTesting();
    repo = AnalysisRepository(database: db);
  });

  tearDown(() => db.close());

  const bear = MarketRegimeReading(
    eligibleCount: 455,
    upCount: 132,
    medianReturn: -0.1609,
    isUptrend: false,
    lookbackDays: 120,
  );
  const bull = MarketRegimeReading(
    eligibleCount: 537,
    upCount: 294,
    medianReturn: 0.0394,
    isUptrend: true,
    lookbackDays: 120,
  );

  test('沒有存過：null', () async {
    expect(await repo.getMarketRegime(DateTime(2026, 11, 24)), isNull);
  });

  test('寫入後讀回同一份讀數；日期帶時間也對到同一天', () async {
    await repo.replaceMarketRegimeForDate(DateTime(2026, 11, 24, 21, 30), bear);
    expect(await repo.getMarketRegime(DateTime(2026, 11, 24)), bear);
  });

  test('同一天再寫一次會換掉', () async {
    final day = DateTime(2026, 11, 24);
    await repo.replaceMarketRegimeForDate(day, bear);
    await repo.replaceMarketRegimeForDate(day, bull);
    expect(await repo.getMarketRegime(day), bull);
  });

  test('讀數是 null：刪掉那一天原本的讀數', () async {
    final day = DateTime(2026, 11, 24);
    await repo.replaceMarketRegimeForDate(day, bear);
    await repo.replaceMarketRegimeForDate(day, null);
    expect(await repo.getMarketRegime(day), isNull);
  });

  test('只動那一天，別天的讀數不受影響', () async {
    await repo.replaceMarketRegimeForDate(DateTime(2026, 11, 23), bear);
    await repo.replaceMarketRegimeForDate(DateTime(2026, 11, 24), bull);
    await repo.replaceMarketRegimeForDate(DateTime(2026, 11, 24), null);
    expect(await repo.getMarketRegime(DateTime(2026, 11, 23)), bear);
  });
}
