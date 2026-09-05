// 財報回填目標的挑選——單一「最舊優先」佇列（2026-09-05）
//
// 之前是兩條佇列：上市 `selectFinancialSyncTargets` 取候選前 N，上櫃
// `selectOtcFinancialBacklog` 最舊優先。上市那條的候選在 live 路徑依波動度
// 降冪（`quickFilterPrices`），名額窗每天都給當日最會動的股票——低波動大型股
// 永遠排不進去。app DB 實查（2026-09-05）：460 檔只有官方批次給的資產負債表、
// 零 EPS；其中 18 檔當天有評分且全是上市大型低波動股（台灣大 3045、群光 2385、
// 佳世達 2352、統一證 2855、統一超 2912…）。7 條 EPS／ROE 規則對它們無聲不
// 觸發，而 9/04 觸發至少一條這類規則的 235 檔平均從中拿到 short 16.4／long 21.2 分
// （這 235 檔的平均總分 24.8／35.8）。五輪日誌實測：被回填的 102 檔裡 0 檔來自那 460 檔。
//
// 修法：把已在上櫃驗證過會收斂的「最舊優先＋ETF 先排除」推廣成全市場單一佇列。
// 分開兩條佇列的唯一理由是上市名額窗把上櫃餓死；最舊優先下餓死在結構上不可能
// 發生，所以兩條佇列與「上市先拿、上櫃吃剩」的配額拆分一併移除。
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:daredevil/core/constants/api_config.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/data/repositories/fundamental_repository.dart';
import 'package:daredevil/domain/services/update/fundamental_syncer.dart';

class MockAppDatabase extends Mock implements AppDatabase {}

class MockFundamentalRepository extends Mock implements FundamentalRepository {}

void main() {
  DateTime? q(int? month) => month == null ? null : DateTime(2026, month, 31);

  group('selectStaleFinancialTargets（純排序）', () {
    test('🚨 ETF 不得佔用配額（無財報 → 排序鍵恆為最舊 → 每輪霸佔名額且永遠排最前）', () {
      final picked = selectStaleFinancialTargets(
        candidates: ['00679B', '00687B', '00929', '3088', '5471'],
        latestDates: {'3088': q(3)},
        limit: 3,
      );

      expect(picked.where((s) => s.startsWith('00')), isEmpty);
      expect(picked, ['5471', '3088'], reason: '扣掉 ETF 後仍應取滿可取的部分，名額不得空轉');
    });

    test('🚨 無財報者最優先，其次才是最舊的', () {
      final picked = selectStaleFinancialTargets(
        candidates: ['3088', '8069', '5471', '6488'],
        latestDates: {'3088': q(3), '8069': q(3), '6488': q(1)},
        limit: 2,
      );

      expect(picked, ['5471', '6488']);
    });

    test('🚨 低波動、無資料的上市股必須排在「已新鮮但排在候選前段」的股票前面', () {
      // 候選順序模擬 live 路徑的波動度降冪：高波動已新鮮者在前，台灣大在最後
      final volatileFresh = [for (var i = 0; i < 120; i++) '${2000 + i}'];
      final picked = selectStaleFinancialTargets(
        candidates: [...volatileFresh, '3045'],
        latestDates: {for (final s in volatileFresh) s: q(6)},
        limit: 1,
      );

      expect(picked, ['3045'], reason: '排序鍵是財報新舊，不是候選（波動度）順序');
    });

    test('🚨 補完者必須排到後面，否則跨輪不會收斂', () {
      final done = [for (var i = 0; i < 3; i++) 'D$i'];
      final pending = [for (var i = 0; i < 3; i++) 'P$i'];

      final picked = selectStaleFinancialTargets(
        candidates: [...done, ...pending],
        latestDates: {for (final s in done) s: q(3)},
        limit: 3,
      );

      expect(picked, pending, reason: '若補完者仍排前面，每輪都同步同一批 → 永遠補不完');
    });

    test('排序具決定性：同一份輸入不得因 Map 迭代序而漂移', () {
      final picked = selectStaleFinancialTargets(
        candidates: ['9999', '1111', '5555'],
        latestDates: {'9999': q(3), '1111': q(3), '5555': q(3)},
        limit: 2,
      );

      expect(picked, ['1111', '5555'], reason: '日期相同時以代號升冪決勝，保證跨輪可重現');
    });

    test('對照組：候選少於上限時取全部；候選為空回空', () {
      expect(
        selectStaleFinancialTargets(
          candidates: ['5471', '6488'],
          latestDates: const {},
          limit: 100,
        ),
        ['5471', '6488'],
      );
      expect(
        selectStaleFinancialTargets(
          candidates: const [],
          latestDates: const {},
          limit: 100,
        ),
        isEmpty,
      );
    });
  });

  group('selectFinancialBacklog（接 DB 的挑選）', () {
    late MockAppDatabase mockDb;
    late FundamentalSyncer syncer;

    setUp(() {
      mockDb = MockAppDatabase();
      syncer = FundamentalSyncer(
        database: mockDb,
        fundamentalRepository: MockFundamentalRepository(),
      );
      when(
        () => mockDb.getLatestFinancialDataDatesBatch(any(), any()),
      ).thenAnswer((_) async => {'3088': q(3)!, '6488': q(1)!});
    });

    test('🚨 上市與上櫃同一條佇列：無資料者優先，不分市場、不靠專屬名額', () async {
      final picked = await syncer.selectFinancialBacklog(
        // 上市 3045（無資料）、上櫃 5471（無資料）、3088 已補到 03-31
        candidates: ['3088', '5471', '3045', '6488'],
        prioritySymbols: const {},
        limit: 2,
      );

      expect(picked, ['3045', '5471'], reason: '兩市場一起依新舊排，無資料者以代號決勝');
    });

    test('🚨 自選＋熱門排最前且計入上限，其餘名額才給最舊優先', () async {
      final picked = await syncer.selectFinancialBacklog(
        candidates: ['3088', '5471', '2330', '6488'],
        prioritySymbols: const {'2330', '0050'},
        limit: 3,
      );

      expect(picked.take(2), [
        '2330',
        '0050',
      ], reason: '自選裡的 ETF 不被剔除——那是使用者主動追蹤的');
      expect(picked, [
        '2330',
        '0050',
        '5471',
      ], reason: '剩 1 個名額給最舊的非 priority 候選');
      final queried =
          verify(
                () => mockDb.getLatestFinancialDataDatesBatch(
                  captureAny(),
                  'INCOME',
                ),
              ).captured.single
              as List<String>;
      expect(
        queried,
        isNot(contains('2330')),
        reason: 'priority 不參與排序，不該進 IN 清單',
      );
    });

    test('🚨 ETF 候選在查 DB 之前就剔除（不撐大 IN 清單、不佔名額）', () async {
      when(
        () => mockDb.getLatestFinancialDataDatesBatch(any(), any()),
      ).thenAnswer((_) async => const {});

      final picked = await syncer.selectFinancialBacklog(
        candidates: ['00878', '0056', '5471'],
        prioritySymbols: const {},
        limit: 3,
      );

      expect(picked, ['5471']);
      final queried =
          verify(
                () => mockDb.getLatestFinancialDataDatesBatch(
                  captureAny(),
                  any(),
                ),
              ).captured.single
              as List<String>;
      expect(queried, ['5471']);
    });

    test('🚨 DB 查詢失敗時 fail-closed：只回 priority，不得把整包候選放出去', () async {
      when(
        () => mockDb.getLatestFinancialDataDatesBatch(any(), any()),
      ).thenThrow(Exception('db down'));

      final picked = await syncer.selectFinancialBacklog(
        candidates: ['5471', '6488', '3088'],
        prioritySymbols: const {'2330'},
        limit: 100,
      );

      expect(
        picked,
        ['2330'],
        reason:
            '拿不到最新財報日就無從排序；fail-open 會讓整包候選逐檔打 FinMind。'
            'priority 有界且下游仍套新鮮度過濾，保住自選覆蓋、放棄這一輪回填',
      );
    });

    test('上限 ≤ priority 數時只取 priority 前段，不查 DB', () async {
      final picked = await syncer.selectFinancialBacklog(
        candidates: ['5471', '6488'],
        prioritySymbols: const {'2330', '2317', '2454'},
        limit: 2,
      );

      expect(picked, ['2330', '2317']);
      verifyNever(() => mockDb.getLatestFinancialDataDatesBatch(any(), any()));
    });

    test('對照組：候選為空回 priority；上限 0 回空', () async {
      expect(
        await syncer.selectFinancialBacklog(
          candidates: const [],
          prioritySymbols: const {'2330'},
          limit: 10,
        ),
        ['2330'],
      );
      expect(
        await syncer.selectFinancialBacklog(
          candidates: const ['5471'],
          prioritySymbols: const {'2330'},
          limit: 0,
        ),
        isEmpty,
      );
      verifyNever(() => mockDb.getLatestFinancialDataDatesBatch(any(), any()));
    });

    test('對照組：預設上限取自 ApiConfig，不得在函式內寫死', () async {
      when(
        () => mockDb.getLatestFinancialDataDatesBatch(any(), any()),
      ).thenAnswer((_) async => const {});

      final picked = await syncer.selectFinancialBacklog(
        candidates: [
          for (var i = 0; i < ApiConfig.financialSyncMaxCount + 50; i++)
            '${5000 + i}',
        ],
        prioritySymbols: const {},
      );

      expect(picked.length, ApiConfig.financialSyncMaxCount);
    });
  });
}
