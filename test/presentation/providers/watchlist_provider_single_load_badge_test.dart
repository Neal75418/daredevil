// A1（2026-07-23 稽核）：單筆載入（addStock/restoreStock）必須跟批次
// loadData 一樣尊重 showWarningBadges 設定——原本無條件算 warningType，
// 關閉設定後新增的股票仍顯示警示徽章，直到下次全量 reload 才消失。
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/data/database/cached_accessor.dart';
import 'package:daredevil/data/repositories/insider_repository.dart';
import 'package:daredevil/data/repositories/warning_repository.dart';
import 'package:daredevil/presentation/providers/providers.dart';
import 'package:daredevil/presentation/providers/settings_provider.dart';
import 'package:daredevil/presentation/providers/watchlist_provider.dart';
import 'package:daredevil/presentation/widgets/warning_badge.dart';

class MockAppDatabase extends Mock implements AppDatabase {}

class MockCachedDatabaseAccessor extends Mock
    implements CachedDatabaseAccessor {}

class MockWarningRepository extends Mock implements WarningRepository {}

class MockInsiderRepository extends Mock implements InsiderRepository {}

class _FakeSettings extends SettingsNotifier {
  _FakeSettings(this._state);
  final SettingsState _state;
  @override
  SettingsState build() => _state;
}

void main() {
  late MockAppDatabase mockDb;
  late MockWarningRepository mockWarningRepo;
  late MockInsiderRepository mockInsiderRepo;

  ProviderContainer buildContainer({required bool showBadges}) {
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(mockDb),
        cachedDbProvider.overrideWithValue(MockCachedDatabaseAccessor()),
        warningRepositoryProvider.overrideWithValue(mockWarningRepo),
        insiderRepositoryProvider.overrideWithValue(mockInsiderRepo),
        settingsProvider.overrideWith(
          () => _FakeSettings(SettingsState(showWarningBadges: showBadges)),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  setUp(() {
    mockDb = MockAppDatabase();
    mockWarningRepo = MockWarningRepository();
    mockInsiderRepo = MockInsiderRepository();

    when(() => mockDb.getStock('2330')).thenAnswer(
      (_) async => StockMasterEntry(
        symbol: '2330',
        name: '台積電',
        market: 'TWSE',
        isActive: true,
        updatedAt: DateTime(2026, 7, 1),
      ),
    );
    when(() => mockDb.addToWatchlist('2330')).thenAnswer((_) async {});
    when(() => mockDb.getWatchlistEntry('2330')).thenAnswer(
      (_) async =>
          WatchlistEntry(symbol: '2330', createdAt: DateTime(2026, 7, 22)),
    );
    when(
      () => mockDb.getLatestDataDate(),
    ).thenAnswer((_) async => DateTime(2026, 7, 22));
    when(() => mockDb.getLatestPrice('2330')).thenAnswer((_) async => null);
    when(() => mockDb.getAnalysis('2330', any())).thenAnswer((_) async => null);
    when(() => mockDb.getReasons('2330', any())).thenAnswer((_) async => []);
    when(
      () => mockDb.getPriceHistory(
        '2330',
        startDate: any(named: 'startDate'),
        endDate: any(named: 'endDate'),
      ),
    ).thenAnswer((_) async => []);
    // 有活動中的處置警示——未 gate 時 warningType 會是 disposal
    when(() => mockWarningRepo.getWatchlistWarnings(['2330'])).thenAnswer(
      (_) async => {
        '2330': TradingWarningEntry(
          symbol: '2330',
          date: DateTime(2026, 7, 1),
          warningType: 'DISPOSAL',
          isActive: true,
        ),
      },
    );
    when(
      () => mockInsiderRepo.getWatchlistHighPledgeStocks([
        '2330',
      ], threshold: any(named: 'threshold')),
    ).thenAnswer((_) async => {});
    // 背景營收回填：已有 12 個月 → 早退，不打 API
    when(
      () =>
          mockDb.getRecentMonthlyRevenue('2330', months: any(named: 'months')),
    ).thenAnswer(
      (_) async => List.generate(
        13,
        (i) => MonthlyRevenueEntry(
          symbol: '2330',
          date: DateTime(2025, i + 1),
          revenueYear: 2025,
          revenueMonth: i + 1,
          revenue: 1,
        ),
      ),
    );
  });

  group('單筆載入的警示徽章 gate（與批次 loadData 對齊）', () {
    test('showWarningBadges=false → addStock 的項目不得帶 warningType', () async {
      final container = buildContainer(showBadges: false);
      final notifier = container.read(watchlistProvider.notifier);

      final ok = await notifier.addStock('2330');

      expect(ok, isTrue);
      final item = container.read(watchlistProvider).items.single;
      expect(item.warningType, isNull); // 修復前：disposal（無條件計算）
    });

    test('showWarningBadges=true → 照常帶出 warningType', () async {
      final container = buildContainer(showBadges: true);
      final notifier = container.read(watchlistProvider.notifier);

      await notifier.addStock('2330');

      final item = container.read(watchlistProvider).items.single;
      expect(item.warningType, WarningBadgeType.disposal);
    });

    test('🚨 單筆載入(新增/復原)同樣帶出價格日期與漲跌價差', () async {
      when(() => mockDb.getLatestPrice('2330')).thenAnswer(
        (_) async => DailyPriceEntry(
          symbol: '2330',
          date: DateTime(2026, 7, 22),
          close: 1000,
          priceChange: -5,
        ),
      );
      final container = buildContainer(showBadges: true);
      await container.read(watchlistProvider.notifier).addStock('2330');

      final row = container.read(watchlistProvider).itemOf('2330')!;
      expect(row.priceDate, DateTime(2026, 7, 22));
      expect(row.priceChangeAmount, -5);
    });
  });
}
