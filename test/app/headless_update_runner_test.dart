// runHeadlessUpdate 的裝配與生命週期契約(2026-08-29 稽核:13 天斷更事故
// 的那條路徑此前零測試)。
//
// 測的是 runner 的**自有職責**——短路判斷、registry seed、token 注入、
// 配額 restore/flush、DB 生命週期——不是 UpdateService 的內容(由
// buildService seam 換成 stub;真裝配路徑由 UpdateServiceFactory 自己的
// 測試與 tool_chain_pure_dart_test 把關)。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:daredevil/app/headless_update_runner.dart';
import 'package:daredevil/core/constants/calibrated_scores/calibrated_scores_registry.dart';
import 'package:daredevil/core/constants/calibrated_scores/horizon.dart';
import 'package:daredevil/core/utils/clock.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/data/remote/api_budget_tracker.dart';
import 'package:daredevil/domain/services/update_service.dart';

class _MockUpdateService extends Mock implements UpdateService {}

class _FixedClock implements AppClock {
  const _FixedClock(this.fixed);
  final DateTime fixed;
  @override
  DateTime now() => fixed;
}

class _RecordingBudgetStore implements ApiBudgetStore {
  final saves = <String>[];
  @override
  Future<String?> load() async => null;
  @override
  Future<void> save(String json) async => saves.add(json);
}

void main() {
  // 2026-08-28(五)為交易日、2026-08-30(日)非交易日
  final tradingDay = DateTime(2026, 8, 28, 7, 30);
  final sunday = DateTime(2026, 8, 30, 7, 30);

  late AppDatabase db;
  late _RecordingBudgetStore store;

  setUp(() {
    db = AppDatabase.forTesting();
    store = _RecordingBudgetStore();
    // 預設把 registry 綁成已載入的空表,讓 runner 的 loadWithOverride
    // no-op——避免每個測試都去讀 rootBundle 資產(T4 例外,自行 reset)
    CalibratedScoresRegistry.instance.resetForTesting();
    CalibratedScoresRegistry.instance.bindForTesting();
  });

  tearDown(() {
    // singleton 跨測試檔存活,不清會污染其他吃 registry 的測試
    CalibratedScoresRegistry.instance.resetForTesting();
  });

  Future<void> expectDbClosed() async {
    await expectLater(
      db.getAllActiveStocks(),
      throwsA(anything),
      reason: 'docstring 契約:runner 管 DB 生命週期,結束時必須已 close',
    );
  }

  test('非交易日:短路 skip、不建服務圖、DB 照樣關閉', () async {
    // 暖機:先開過 DB(貼近呼叫端現實)——close 對從未開啟的 lazy
    // executor 是 no-op,之後的探針查詢反而會把它打開,測不到東西
    await db.getAllActiveStocks();
    final result = await runHeadlessUpdate(
      database: db,
      budgetStore: store,
      clock: _FixedClock(sunday),
      buildService:
          ({
            required database,
            required finMindClient,
            required twseClient,
            required tpexClient,
            required tdccClient,
            required rssParser,
          }) => fail('非交易日不得建服務圖'),
    );
    expect(result.skipped, isTrue);
    expect(result.success, isTrue);
    await expectDbClosed();
  });

  test('交易日:token 注入到 finMind client、結果原樣傳回、flush 收尾、DB 關閉', () async {
    final mockService = _MockUpdateService();
    final canned = UpdateResult(date: tradingDay)
      ..success = true
      ..message = 'stub';
    when(() => mockService.runDailyUpdate()).thenAnswer((_) async => canned);

    String? capturedToken;
    final result = await runHeadlessUpdate(
      database: db,
      budgetStore: store,
      finMindToken: 'test-token-12345678901234567890',
      clock: _FixedClock(tradingDay),
      buildService:
          ({
            required database,
            required finMindClient,
            required twseClient,
            required tpexClient,
            required tdccClient,
            required rssParser,
          }) {
            capturedToken = finMindClient.token;
            return mockService;
          },
    );

    expect(identical(result, canned), isTrue, reason: '結果不得被包裝或改寫');
    expect(
      capturedToken,
      'test-token-12345678901234567890',
      reason: 'token 沒掛上 client = 需 token 的 syncer 整批靜默 skip',
    );
    expect(
      store.saves,
      isNotEmpty,
      reason: '收尾 flush 丟掉尾端記帳 → 下輪超發 → 402(2026-08-01 複審)',
    );
    await expectDbClosed();
  });

  test('🚨 服務丟例外:照樣 flush + 關 DB,例外向上傳', () async {
    final mockService = _MockUpdateService();
    when(
      () => mockService.runDailyUpdate(),
    ).thenThrow(StateError('mid-run crash'));

    await expectLater(
      runHeadlessUpdate(
        database: db,
        budgetStore: store,
        clock: _FixedClock(tradingDay),
        buildService:
            ({
              required database,
              required finMindClient,
              required twseClient,
              required tpexClient,
              required tdccClient,
              required rssParser,
            }) => mockService,
      ),
      throwsStateError,
    );
    expect(store.saves, isNotEmpty, reason: 'crash 路徑最容易漏 flush');
    await expectDbClosed();
  });

  test('🚨 registry seed:DB cache 有校準 → 背景評分用它,不得靜默退回資產', () async {
    // 不 seed 的話 background isolate 是 fresh _loaded=false,所有規則
    // fallback 到 hardcoded——寫入的 recommendations 與前景看到的靜默
    // 分歧(runner 註解記載的事故形狀)。用「真資產 JSON 改一條 active
    // 規則的分數當哨兵」證明走的是 DB cache 而非 asset fallback。
    CalibratedScoresRegistry.instance.resetForTesting();

    final shortJson =
        jsonDecode(
              File(
                'assets/rule_scores_calibrated_short.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    ((shortJson['rules'] as Map<String, dynamic>)['WEEK_52_HIGH']
            as Map<String, dynamic>)['score'] =
        37;
    final longJson = File(
      'assets/rule_scores_calibrated_long.json',
    ).readAsStringSync();
    await db.writeCalibration(
      version: 'test-1',
      shortJson: jsonEncode(shortJson),
      longJson: longJson,
      shortHash: 'x',
      longHash: 'y',
      checkedAt: tradingDay,
    );

    final mockService = _MockUpdateService();
    when(
      () => mockService.runDailyUpdate(),
    ).thenAnswer((_) async => UpdateResult(date: tradingDay)..success = true);
    await runHeadlessUpdate(
      database: db,
      budgetStore: store,
      clock: _FixedClock(tradingDay),
      buildService:
          ({
            required database,
            required finMindClient,
            required twseClient,
            required tpexClient,
            required tdccClient,
            required rssParser,
          }) => mockService,
    );

    expect(
      CalibratedScoresRegistry.instance.lookup(Horizon.short, 'WEEK_52_HIGH'),
      37,
      reason: '哨兵分數 37 只存在 DB cache;資產值不同——查到 37 = seed 生效',
    );
  });
}
