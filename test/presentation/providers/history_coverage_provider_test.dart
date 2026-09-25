import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:daredevil/core/constants/market_codes.dart';
import 'package:daredevil/core/constants/rule_params.dart';
import 'package:daredevil/core/utils/clock.dart';
import 'package:daredevil/core/utils/date_context.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/presentation/providers/history_coverage_provider.dart';
import 'package:daredevil/presentation/providers/providers.dart';
import 'package:daredevil/presentation/providers/today_provider.dart';

class _MockDb extends Mock implements AppDatabase {}

class _FixedClock implements AppClock {
  const _FixedClock(this._now);
  final DateTime _now;
  @override
  DateTime now() => _now;
}

class _TodayAt extends TodayNotifier {
  _TodayAt(this._dataDate);
  final DateTime _dataDate;
  @override
  TodayState build() => TodayState(dataDate: _dataDate);
}

void main() {
  // 窗口右端要取自今日頁的資料日；沒接上的話，資料落後的那幾天會被當成
  // 「歷史沒補齊」，和落後提示同時出現。
  test('🚨 以今日頁的資料日定窗口：資料落後的近幾天不算建置中', () async {
    final db = _MockDb();
    when(() => db.getStocksByMarket(MarketCode.twse)).thenAnswer(
      (_) async => [
        StockMasterEntry(
          symbol: '2330',
          name: '2330',
          market: MarketCode.twse,
          isActive: true,
          updatedAt: DateTime(2026),
        ),
      ],
    );
    when(
      () => db.getStocksByMarket(MarketCode.tpex),
    ).thenAnswer((_) async => []);
    final dataDate = DateTime(2026, 9, 17);
    final start = dataDate.subtract(
      const Duration(days: RuleParams.historyRequiredDays),
    );
    final counts = <String, int>{
      for (
        var d = dataDate;
        !d.isBefore(start);
        d = d.subtract(const Duration(days: 1))
      )
        DateContext.formatYmd(d): 1,
    };
    when(
      () => db.getPriceCountsByDayAndMarket(
        startDate: any(named: 'startDate'),
        endDate: any(named: 'endDate'),
      ),
    ).thenAnswer((_) async => {MarketCode.twse: counts});

    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        appClockProvider.overrideWithValue(
          _FixedClock(DateTime(2026, 9, 25, 17)),
        ),
        todayProvider.overrideWith(() => _TodayAt(dataDate)),
      ],
    );
    addTearDown(container.dispose);

    final coverage = await container.read(historyCoverageProvider.future);

    expect(coverage.isComplete, isTrue);
  });

  test('還沒有資料日 → 不查 DB，回 0/0（今日頁此時不顯示進度）', () async {
    final db = _MockDb();
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        todayProvider.overrideWith(_NoData.new),
      ],
    );
    addTearDown(container.dispose);

    final coverage = await container.read(historyCoverageProvider.future);

    expect(coverage.total, 0);
    verifyNever(() => db.getStocksByMarket(any()));
  });
}

class _NoData extends TodayNotifier {
  @override
  TodayState build() => const TodayState();
}
