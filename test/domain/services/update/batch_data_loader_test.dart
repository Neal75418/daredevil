import 'package:daredevil/core/constants/rule_params.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/data/repositories/news_repository.dart';
import 'package:daredevil/data/repositories/institutional_repository.dart';
import 'package:daredevil/domain/services/update/batch_data_loader.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockDb extends Mock implements AppDatabase {}

class _MockNewsRepo extends Mock implements NewsRepository {}

class _MockInstRepo extends Mock implements InstitutionalRepository {}

void main() {
  late _MockDb db;
  late _MockNewsRepo newsRepo;

  setUpAll(() {
    registerFallbackValue(DateTime(2026, 7, 9));
  });

  setUp(() {
    db = _MockDb();
    newsRepo = _MockNewsRepo();

    when(
      () => db.getPriceHistoryBatch(
        any(),
        startDate: any(named: 'startDate'),
        endDate: any(named: 'endDate'),
      ),
    ).thenAnswer((_) async => {});
    when(
      () => newsRepo.getNewsForStocksBatch(any(), days: any(named: 'days')),
    ).thenAnswer((_) async => {});
    when(
      () => db.getLatestMonthlyRevenuesBatch(any(), asOf: any(named: 'asOf')),
    ).thenAnswer((_) async => {});
    when(
      () => db.getLatestValuationsBatch(any(), asOf: any(named: 'asOf')),
    ).thenAnswer((_) async => {});
    when(
      () =>
          db.getRecentMonthlyRevenueBatch(any(), months: any(named: 'months')),
    ).thenAnswer((_) async => {});
    when(() => db.getDayTradingMapForDate(any())).thenAnswer((_) async => {});
    when(
      () => db.getLatestShareholdingsBatch(any(), asOf: any(named: 'asOf')),
    ).thenAnswer((_) async => {});
    when(
      () => db.getShareholdingsBeforeDateBatch(
        any(),
        beforeDate: any(named: 'beforeDate'),
      ),
    ).thenAnswer((_) async => {});
    when(() => db.getActiveWarningsMapBatch(any())).thenAnswer((_) async => {});
    when(
      () => db.getMarketsForSymbolsBatch(any()),
    ).thenAnswer((_) async => <String, String>{});
    when(
      () => db.getLatestInsiderHoldingsBatch(any(), asOf: any(named: 'asOf')),
    ).thenAnswer((_) async => {});
    when(() => db.getEPSHistoryBatch(any())).thenAnswer((_) async => {});
    when(() => db.getROEHistoryBatch(any())).thenAnswer((_) async => {});
    when(() => db.getDividendHistoryBatch(any())).thenAnswer((_) async => {});
    when(() => db.getMaxRevenueBatch(any())).thenAnswer((_) async => {});
    when(
      () => db.getInstitutionalHistoryBatch(
        any(),
        startDate: any(named: 'startDate'),
        endDate: any(named: 'endDate'),
      ),
    ).thenAnswer((_) async => {});
  });

  test('價格載入窗口必須與 syncer 充足性判斷窗（historyRequiredDays）同源', () async {
    // 回歸背景：loader 原用 lookbackPrice + 10（380 日曆日）、syncer 判斷
    // 「夠不夠」用 historyRequiredDays（400 日曆日）。2330 在 400 天窗有
    // 261 個交易日（syncer 判定夠、不回補），380 天窗只切出 247 個
    // → 52 週規則（需 250）對幾乎全市場長期「資料不足 (247/250)」。
    // 兩窗同源後此縫隙不再存在。
    final loader = BatchDataLoader(database: db, newsRepository: newsRepo);
    final date = DateTime(2026, 7, 9);

    await loader.loadBatchData(date, ['2330']);

    final captured = verify(
      () => db.getPriceHistoryBatch(
        any(),
        startDate: captureAny(named: 'startDate'),
        endDate: any(named: 'endDate'),
      ),
    ).captured;
    final startDate = captured.first as DateTime;

    expect(
      date.difference(startDate).inDays,
      RuleParams.historyRequiredDays,
      reason:
          '價格窗口與 historyRequiredDays 不同源，52 週規則會再次陷入'
          '「syncer 判定夠、規則拿不到」的縫隙',
    );
  });

  test('法人載入窗口必須用 streak 專用窗，不得用顯示窗', () async {
    // 回歸背景（P1-6）：loader 原用 institutionalLookbackDays（10 日曆日）
    // → 從 7/24 往回只含 9 個交易日，而連續買賣超規則掃到窗邊界為止。
    // DB 實證 streakDays 分布 4:82 / 5:58 / 6:49 / 7:41 / 8:39 / 9:17、
    // **10 以上 0 筆**——與窗大小完全吻合的硬牆。
    //
    // 真實資料實測放寬至 90 後：45 檔觸發者觸發結果零變動，8 檔天數被
    // 修正（2357/2884/6414 由 9 日 → 17 日）。
    final loader = BatchDataLoader(
      database: db,
      newsRepository: newsRepo,
      institutionalRepository: _MockInstRepo(),
    );
    final date = DateTime(2026, 7, 9);

    await loader.loadBatchData(date, ['2330']);

    final captured = verify(
      () => db.getInstitutionalHistoryBatch(
        any(),
        startDate: captureAny(named: 'startDate'),
        endDate: any(named: 'endDate'),
      ),
    ).captured;
    final instStart = captured.first as DateTime;

    expect(
      date.difference(instStart).inDays,
      InstitutionalParams.institutionalStreakLookbackDays,
      reason:
          '用顯示窗（10 日）載入會把長 streak 截斷成「剛好等於窗長」，'
          '讓「連買 9 日」與「連買 25 日」在畫面上長得一樣',
    );
  });

  test('法人「當日無進出」缺列必須在評分路徑補零', () async {
    // 補零函式本身的語意在 institutional_no_activity_fill_test.dart 釘住；
    // 此測試只確認 loader 真的有接上——否則規則仍會拿到帶缺口的資料。
    final d1 = DateTime(2026, 7, 20);
    final d2 = DateTime(2026, 7, 21);
    final d3 = DateTime(2026, 7, 22);

    when(
      () => db.getPriceHistoryBatch(
        any(),
        startDate: any(named: 'startDate'),
        endDate: any(named: 'endDate'),
      ),
    ).thenAnswer(
      (_) async => {
        'AAA': [
          for (final d in [d1, d2, d3])
            DailyPriceEntry(
              symbol: 'AAA',
              date: d,
              open: 50,
              high: 50,
              low: 50,
              close: 50,
              volume: 1000000,
            ),
        ],
      },
    );
    when(
      () => db.getInstitutionalHistoryBatch(
        any(),
        startDate: any(named: 'startDate'),
        endDate: any(named: 'endDate'),
      ),
    ).thenAnswer(
      (_) async => {
        // AAA 缺 7/21；BBB 在 7/21 有列 → 證明同步涵蓋該日
        'AAA': [
          DailyInstitutionalEntry(symbol: 'AAA', date: d1, foreignNet: 600000),
          DailyInstitutionalEntry(symbol: 'AAA', date: d3, foreignNet: 600000),
        ],
        'BBB': [
          DailyInstitutionalEntry(symbol: 'BBB', date: d2, foreignNet: 100000),
        ],
      },
    );

    final loader = BatchDataLoader(
      database: db,
      newsRepository: newsRepo,
      institutionalRepository: _MockInstRepo(),
    );

    final result = await loader.loadBatchData(DateTime(2026, 7, 22), ['AAA']);
    final aaa = result.institutional.institutionalMap!['AAA']!;

    expect(aaa.length, 3, reason: '缺列未補 → 規則會把 7/20 與 7/22 接成連續');
    expect(aaa.map((e) => e.date), [d1, d2, d3]);
    expect(aaa[1].foreignNet, 0);
  });
  test('基本面「最新值」查詢必須帶評分日為 as-of 上界', () async {
    // 純函式層的語意由 fundamental_as_of_test.dart 覆蓋；此測試釘住「loader
    // 真的有把評分日傳下去」—— 少傳就會在歷史重跑時把未來的估值/營收/
    // 外資持股寫進當日訊號，而那批列正是 rule_accuracy 的輸入。
    final loader = BatchDataLoader(database: db, newsRepository: newsRepo);
    final date = DateTime(2026, 7, 9);

    await loader.loadBatchData(date, ['2330']);

    for (final captured in [
      verify(
        () =>
            db.getLatestValuationsBatch(any(), asOf: captureAny(named: 'asOf')),
      ).captured,
      verify(
        () => db.getLatestMonthlyRevenuesBatch(
          any(),
          asOf: captureAny(named: 'asOf'),
        ),
      ).captured,
      verify(
        () => db.getLatestShareholdingsBatch(
          any(),
          asOf: captureAny(named: 'asOf'),
        ),
      ).captured,
    ]) {
      expect(captured.first, date);
    }
  });
}
