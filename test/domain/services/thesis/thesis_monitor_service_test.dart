// ThesisMonitorService 測試 — 每日更新後的失效檢查（真 in-memory DB）
//
// 驗證 spec §5：全量重算冪等、INVALIDATED 凍結（只掃 ACTIVE）、
// lastCheckedDate 必更新、觸發日 = 首個滿足日的資料日。
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/domain/services/thesis/thesis_monitor_service.dart';

/// 對指定 symbol 拋錯的 DB，用來驗證單筆失敗不得污染其餘論點的
/// `lastCheckedDate`（否則未評估者會謊報「最後檢查：今天」）。
class _ThrowingDb extends AppDatabase {
  _ThrowingDb(this.failSymbol) : super.forTesting();

  final String failSymbol;

  @override
  Future<List<DailyPriceEntry>> getPriceHistory(
    String symbol, {
    required DateTime startDate,
    DateTime? endDate,
  }) {
    if (symbol == failSymbol) {
      throw StateError('模擬讀取失敗');
    }
    return super.getPriceHistory(
      symbol,
      startDate: startDate,
      endDate: endDate,
    );
  }
}

void main() {
  late AppDatabase db;
  late ThesisMonitorService service;

  final pinnedDate = DateTime(2026, 1, 5);

  setUp(() async {
    db = AppDatabase.forTesting();
    service = ThesisMonitorService(database: db);
    await db.upsertStocks([
      StockMasterCompanion.insert(symbol: '2330', name: '台積電', market: 'TWSE'),
    ]);
  });

  tearDown(() async {
    await db.close();
  });

  /// 從釘選日起 seed [days] 天收盤（工作日連續、值由 [closeAt] 決定）
  Future<void> seedCloses(int days, double Function(int i) closeAt) async {
    await db.insertPrices([
      for (var i = 0; i < days; i++)
        DailyPriceCompanion.insert(
          symbol: '2330',
          date: pinnedDate.add(Duration(days: i)),
          close: Value(closeAt(i)),
          volume: const Value(1000000),
        ),
    ]);
  }

  Future<int> pin() => db.pinThesis(
    symbol: '2330',
    pinnedDate: pinnedDate,
    referencePrice: 100.0,
    mode: 'pullback',
    triggeredRules: '[]',
    scoreShort: 20,
    scoreLong: 30,
  );

  test('40 列未實現 → INVALIDATED(timeStop)、觸發日 = 第 40 列資料日', () async {
    await seedCloses(45, (_) => 100.0); // 從未 > ref
    await pin();

    final invalidated = await service.checkActiveTheses(
      asOf: pinnedDate.add(const Duration(days: 44)),
    );
    expect(invalidated, 1);

    final row = (await db.getThesesByStatus('INVALIDATED')).single;
    expect(row.invalidatedReason, 'timeStop');
    expect(row.invalidatedDate, pinnedDate.add(const Duration(days: 40)));
    expect(row.lastCheckedDate, isNotNull);
  });

  test('論點實現（曾收高於 ref）→ 維持 ACTIVE、lastChecked 仍更新', () async {
    await seedCloses(45, (i) => i == 10 ? 101.0 : 100.0);
    await pin();

    final invalidated = await service.checkActiveTheses(
      asOf: pinnedDate.add(const Duration(days: 44)),
    );
    expect(invalidated, 0);

    final row = (await db.getActiveTheses()).single;
    expect(row.status, 'ACTIVE');
    expect(row.lastCheckedDate, isNotNull);
  });

  test('🚨 單筆讀取失敗：該筆不得蓋「已檢查」章，其餘照常', () async {
    final failDb = _ThrowingDb('2317');
    final failService = ThesisMonitorService(database: failDb);
    await failDb.upsertStocks([
      StockMasterCompanion.insert(symbol: '2330', name: '台積電', market: 'TWSE'),
      StockMasterCompanion.insert(symbol: '2317', name: '鴻海', market: 'TWSE'),
    ]);
    await failDb.insertPrices([
      for (var i = 0; i < 45; i++)
        DailyPriceCompanion.insert(
          symbol: '2330',
          date: pinnedDate.add(Duration(days: i)),
          close: const Value(101.0),
          volume: const Value(1000000),
        ),
    ]);
    for (final sym in ['2330', '2317']) {
      await failDb.pinThesis(
        symbol: sym,
        pinnedDate: pinnedDate,
        referencePrice: 100.0,
        mode: 'pullback',
        triggeredRules: '[]',
        scoreShort: 20,
        scoreLong: 30,
      );
    }

    // 一筆炸掉不得中斷整輪，但整輪必須以例外收尾——否則 UpdateService 的
    // fail-safe 收不到，update_run 會標成 SUCCESS（靜默失敗）。
    await expectLater(
      failService.checkActiveTheses(
        asOf: pinnedDate.add(const Duration(days: 44)),
      ),
      throwsA(isA<StateError>()),
      reason: '有失敗卻正常回傳＝呼叫端無從得知，等同靜默失敗',
    );

    final rows = await failDb.getActiveTheses();
    final ok = rows.firstWhere((r) => r.symbol == '2330');
    final bad = rows.firstWhere((r) => r.symbol == '2317');
    expect(ok.lastCheckedDate, isNotNull, reason: '成功評估的應蓋章');
    expect(
      bad.lastCheckedDate,
      isNull,
      reason: '讀取失敗＝根本沒評估，蓋章會讓 UI 謊報「最後檢查：今天」',
    );
    await failDb.close();
  });

  test('冪等：重跑不改變 INVALIDATED 的凍結欄位', () async {
    await seedCloses(45, (_) => 100.0);
    await pin();
    await service.checkActiveTheses(
      asOf: pinnedDate.add(const Duration(days: 44)),
    );
    final first = (await db.getThesesByStatus('INVALIDATED')).single;

    // 第二次跑（模擬隔日更新）：只掃 ACTIVE → 已失效者不動
    final second = await service.checkActiveTheses(
      asOf: pinnedDate.add(const Duration(days: 45)),
    );
    expect(second, 0);
    final after = (await db.getThesesByStatus('INVALIDATED')).single;
    expect(after.invalidatedDate, first.invalidatedDate);
    expect(after.updatedAt, first.updatedAt);
  });

  test('🚨 完全沒有價格列 → 仍須蓋章（否則 staleness 永遠凍結）', () async {
    await pin();

    await service.checkActiveTheses(
      asOf: pinnedDate.add(const Duration(days: 44)),
    );

    final row = (await db.getActiveTheses()).single;
    expect(
      row.lastCheckedDate,
      isNotNull,
      reason: '「查了但沒資料」也是查過；不蓋章會讓該筆的最後檢查日永久凍結',
    );
  });

  test('資料不足（< 40 列）→ 倒數中、維持 ACTIVE', () async {
    await seedCloses(20, (_) => 100.0);
    await pin();
    final invalidated = await service.checkActiveTheses(
      asOf: pinnedDate.add(const Duration(days: 19)),
    );
    expect(invalidated, 0);
    expect((await db.getActiveTheses()).single.status, 'ACTIVE');
  });
}
