// 公布期沉默點名(2026-08-14):「壓線的沉默也是資訊」的最後一步
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/utils/taiwan_time.dart';
import 'package:daredevil/data/database/dao/revenue_dao.dart';
import 'package:daredevil/presentation/providers/revenue_overview_provider.dart';
import 'package:daredevil/presentation/providers/watchlist_provider.dart';
import 'package:daredevil/presentation/screens/today/widgets/filing_unfiled_label.dart';
import 'package:daredevil/presentation/screens/today/widgets/revenue_filing_entry.dart';

import '../../../../helpers/provider_test_helpers.dart';
import '../../../../helpers/widget_test_helpers.dart';

class FakeRevenueNotifier extends RevenueOverviewNotifier {
  FakeRevenueNotifier(this._initial);
  final RevenueOverviewState _initial;
  @override
  RevenueOverviewState build() => _initial;
  @override
  Future<void> loadData() async {}
}

class FakeWatchlistNotifier extends WatchlistNotifier {
  FakeWatchlistNotifier(this._items);
  final List<WatchlistItemData> _items;
  @override
  WatchlistState build() => WatchlistState(items: _items);
  @override
  Future<void> loadData() async {}
}

RevenueOverviewRow filedRow(String symbol) => RevenueOverviewRow(
  symbol: symbol,
  name: '測$symbol',
  market: 'TWSE',
  revenue: 100,
  momGrowth: 1,
  yoyGrowth: 2,
  isNewHigh: false,
);

WatchlistItemData wlItem(String symbol, String name) =>
    WatchlistItemData(symbol: symbol, stockName: name);

void main() {
  setUpAll(() async => setupTestLocalization());

  tearDown(() => TaiwanTime.debugNowOverride = null);

  group('unfiledNamesLabel', () {
    final items = [
      (symbol: '2317', name: '鴻海' as String?),
      (symbol: '2330', name: '台積電' as String?),
      (symbol: '2376', name: '技嘉' as String?),
      (symbol: '6770', name: '力積電' as String?),
      (symbol: '8299', name: null as String?),
    ];

    test('🚨 前 3 名點名+餘數收尾;無名稱退回代碼', () {
      expect(
        unfiledNamesLabel(watchlistItems: items, filedSymbols: const {}),
        '鴻海、台積電、技嘉 +2',
      );
      expect(
        unfiledNamesLabel(
          watchlistItems: items,
          filedSymbols: {'2317', '2330', '2376', '6770'},
        ),
        '8299',
        reason: '名稱缺時用代碼,不得顯示 null',
      );
    });

    test('全數已交 → null(該行隱藏)', () {
      expect(
        unfiledNamesLabel(
          watchlistItems: items,
          filedSymbols: {'2317', '2330', '2376', '6770', '8299'},
        ),
        isNull,
      );
    });

    test('🚨 ETF 不點名——0050 永遠沒有月營收,不是沉默是無此義務', () {
      final withEtf = [
        (symbol: '0050', name: '元大台灣50' as String?),
        (symbol: '0056', name: '元大高股息' as String?),
        ...items,
      ];
      expect(
        unfiledNamesLabel(
          watchlistItems: withEtf,
          filedSymbols: {'2330', '2376', '6770', '8299'},
        ),
        '鴻海',
        reason: 'ETF 不得佔用點名名額,也不得計入 +N 餘數',
      );
      expect(
        unfiledNamesLabel(
          watchlistItems: [(symbol: '0050', name: '元大台灣50' as String?)],
          filedSymbols: const {},
        ),
        isNull,
        reason: '未交名單只剩 ETF → 視同全數已交',
      );
    });

    test('點名順序依代碼穩定排序,不隨自選頁排序模式漂移', () {
      final reversed = items.reversed.toList();
      expect(
        unfiledNamesLabel(watchlistItems: reversed, filedSymbols: const {}),
        '鴻海、台積電、技嘉 +2',
        reason: '同一批沉默者,不論輸入順序點名結果必須一致',
      );
    });
  });

  group('RevenueFilingEntrySection 沉默點名', () {
    Widget app({
      required List<RevenueOverviewRow> filed,
      required List<WatchlistItemData> watchlist,
    }) => buildProviderTestApp(
      const Scaffold(body: RevenueFilingEntrySection()),
      overrides: [
        revenueOverviewProvider.overrideWith(
          () => FakeRevenueNotifier(
            RevenueOverviewState(
              overview: RevenueOverview(
                year: 2026,
                month: 7,
                rows: filed,
                filedByMarket: const {'TWSE': 1},
              ),
            ),
          ),
        ),
        watchlistProvider.overrideWith(() => FakeWatchlistNotifier(watchlist)),
      ],
    );

    testWidgets('🚨 窗口內有未交卷 → 點名行出現', (tester) async {
      TaiwanTime.debugNowOverride = () => DateTime(2026, 8, 5); // 7 月窗口內
      await tester.pumpWidget(
        app(
          filed: [filedRow('2330')],
          watchlist: [wlItem('2330', '台積電'), wlItem('2317', '鴻海')],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('revenueOverview.entryUnfiled'), findsOneWidget);
    });

    testWidgets('全數交卷 → 無點名行', (tester) async {
      TaiwanTime.debugNowOverride = () => DateTime(2026, 8, 5);
      await tester.pumpWidget(
        app(filed: [filedRow('2330')], watchlist: [wlItem('2330', '台積電')]),
      );
      await tester.pumpAndSettle();

      expect(find.text('revenueOverview.entryUnfiled'), findsNothing);
    });
  });
}
