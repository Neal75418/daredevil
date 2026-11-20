import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/utils/clock.dart';
import 'package:daredevil/core/utils/date_context.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/domain/models/close_summary.dart';
import 'package:daredevil/presentation/providers/close_summary_provider.dart';
import 'package:daredevil/presentation/providers/data_update_epoch_provider.dart';
import 'package:daredevil/presentation/providers/providers.dart';

class _FixedClock implements AppClock {
  const _FixedClock(this._now);
  final DateTime _now;
  @override
  DateTime now() => _now;
}

final _d = DateTime(2026, 11, 19);
final _next = DateTime(2026, 11, 20);

void main() {
  late AppDatabase db;
  late ProviderContainer container;

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.upsertStocks([
      StockMasterCompanion.insert(symbol: '2330', name: '台積電', market: 'TWSE'),
    ]);
    await db.insertPrices([
      DailyPriceCompanion.insert(
        symbol: '2330',
        date: _d,
        close: const Value(100),
        volume: const Value(5000000),
      ),
    ]);
    await db.addToWatchlist('2330');
    container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        appClockProvider.overrideWithValue(
          _FixedClock(DateTime(2026, 11, 20, 17)),
        ),
      ],
    );
    container.listen(closeSummaryProvider, (_, _) {});
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  /// 等到 provider 發布一份符合 [matches] 的摘要（最多 3 秒）
  Future<CloseSummary> waitFor(bool Function(CloseSummary) matches) async {
    final deadline = DateTime.now().add(const Duration(seconds: 3));
    while (DateTime.now().isBefore(deadline)) {
      final value = container.read(closeSummaryProvider).value;
      if (value != null && matches(value)) return value;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    fail('3 秒內沒有等到預期的摘要');
  }

  test('每日更新寫入新一輪（epoch bump）後重算', () async {
    final first = (await container.read(closeSummaryProvider.future))!;
    expect(first.dataDate, _d);

    await db.insertPrices([
      DailyPriceCompanion.insert(
        symbol: '2330',
        date: _next,
        close: const Value(101),
        volume: const Value(5000000),
      ),
    ]);
    container.read(dataUpdateEpochProvider.notifier).bump();

    await waitFor((s) => DateContext.isSameDay(s.dataDate, _next));
  });

  test('改自選的分組後重算（今日頁一直掛著，入口卡要立刻反映）', () async {
    final first = (await container.read(closeSummaryProvider.future))!;
    expect(first.sections.single.isUngrouped, isTrue);

    final groupId = await db.createWatchlistGroup('強者榜');
    await db.assignWatchlistGroup('2330', groupId);

    await waitFor((s) => s.sections.single.groupName == '強者榜');
  });

  test('分組改名後重算：找不到「強者榜」', () async {
    final groupId = await db.createWatchlistGroup('強者榜');
    await db.assignWatchlistGroup('2330', groupId);
    await waitFor((s) => !s.strongListGroupMissing);

    await db.renameWatchlistGroup(groupId, '強者榜v2');
    await waitFor((s) => s.strongListGroupMissing);
  });

  test('記一筆持股後重算：持股數由 0 變 1', () async {
    final first = (await container.read(closeSummaryProvider.future))!;
    expect(first.holdingCount, 0);

    await db.upsertPortfolioPosition(
      PortfolioPositionCompanion.insert(
        symbol: '2330',
        quantity: const Value(1000),
        avgCost: const Value(100),
      ),
    );
    await waitFor((s) => s.holdingCount == 1);
  });
}
