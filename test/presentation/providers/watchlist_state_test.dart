import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/presentation/providers/watchlist_provider.dart';

void main() {
  group('WatchlistState', () {
    // Helper to create test items
    WatchlistItemData createItem({
      required String symbol,
      String? stockName,
      double? priceChange,
      String? trendState,
      bool hasSignal = false,
      int? groupId,
      String? groupName,
    }) {
      return WatchlistItemData(
        symbol: symbol,
        stockName: stockName,
        priceChange: priceChange,
        trendState: trendState,
        hasSignal: hasSignal,
        groupId: groupId,
        groupName: groupName,
      );
    }

    // Helper to build a WatchlistGroupEntry（自訂分組）
    WatchlistGroupEntry createGroup({
      required int id,
      required String name,
      int sortOrder = 0,
    }) {
      return WatchlistGroupEntry(
        id: id,
        name: name,
        sortOrder: sortOrder,
        createdAt: DateTime(2026),
        isDefault: false,
      );
    }

    group('constructor and defaults', () {
      test('creates state with default values', () {
        final state = WatchlistState();

        expect(state.items, isEmpty);
        expect(state.isLoading, isFalse);
        expect(state.error, isNull);
        expect(state.sort, equals(WatchlistSort.addedDesc));
        expect(state.group, equals(WatchlistGroup.none));
        expect(state.searchQuery, isEmpty);
      });

      test('creates state with custom values', () {
        final items = [createItem(symbol: '2330')];
        final state = WatchlistState(
          items: items,
          isLoading: true,
          error: 'Test error',
          sort: WatchlistSort.scoreDesc,
          group: WatchlistGroup.status,
          searchQuery: 'test',
        );

        expect(state.items, equals(items));
        expect(state.isLoading, isTrue);
        expect(state.error, equals('Test error'));
        expect(state.sort, equals(WatchlistSort.scoreDesc));
        expect(state.group, equals(WatchlistGroup.status));
        expect(state.searchQuery, equals('test'));
      });
    });

    group('filteredItems caching', () {
      test('returns all items when searchQuery is empty', () {
        final items = [
          createItem(symbol: '2330', stockName: '台積電'),
          createItem(symbol: '2317', stockName: '鴻海'),
        ];
        final state = WatchlistState(items: items);

        expect(state.filteredItems, equals(items));
      });

      test('filters by symbol', () {
        final items = [
          createItem(symbol: '2330', stockName: '台積電'),
          createItem(symbol: '2317', stockName: '鴻海'),
        ];
        final state = WatchlistState(items: items, searchQuery: '2330');

        expect(state.filteredItems.length, equals(1));
        expect(state.filteredItems.first.symbol, equals('2330'));
      });

      test('filters by stock name', () {
        final items = [
          createItem(symbol: '2330', stockName: '台積電'),
          createItem(symbol: '2317', stockName: '鴻海'),
        ];
        final state = WatchlistState(items: items, searchQuery: '台積');

        expect(state.filteredItems.length, equals(1));
        expect(state.filteredItems.first.symbol, equals('2330'));
      });

      test('filter is case insensitive', () {
        final items = [createItem(symbol: 'AAPL', stockName: 'Apple')];
        final state = WatchlistState(items: items, searchQuery: 'aapl');

        expect(state.filteredItems.length, equals(1));
      });

      test('returns empty list when no matches', () {
        final items = [createItem(symbol: '2330', stockName: '台積電')];
        final state = WatchlistState(items: items, searchQuery: 'xyz');

        expect(state.filteredItems, isEmpty);
      });
    });

    group('groupedByStatus lazy caching', () {
      test('groups items by status correctly', () {
        final items = [
          createItem(symbol: '2330', hasSignal: true), // signal
          createItem(symbol: '2317', priceChange: 5.0), // volatile (>= 3%)
          createItem(symbol: '2454', priceChange: 1.0), // quiet (< 3%)
          createItem(symbol: '3008', hasSignal: true), // signal
        ];
        final state = WatchlistState(items: items);

        final grouped = state.groupedByStatus;

        expect(grouped[WatchlistStatus.signal]!.length, equals(2));
        expect(grouped[WatchlistStatus.volatile]!.length, equals(1));
        expect(grouped[WatchlistStatus.quiet]!.length, equals(1));
      });

      test('returns same cached instance on multiple accesses', () {
        final state = WatchlistState(items: [createItem(symbol: '2330')]);

        final first = state.groupedByStatus;
        final second = state.groupedByStatus;

        expect(identical(first, second), isTrue);
      });

      test('handles empty items', () {
        final state = WatchlistState();
        final grouped = state.groupedByStatus;

        expect(grouped[WatchlistStatus.signal], isEmpty);
        expect(grouped[WatchlistStatus.volatile], isEmpty);
        expect(grouped[WatchlistStatus.quiet], isEmpty);
      });
    });

    group('groupedByTrend lazy caching', () {
      test('groups items by trend correctly', () {
        final items = [
          createItem(symbol: '2330', trendState: 'UP'),
          createItem(symbol: '2317', trendState: 'DOWN'),
          createItem(symbol: '2454', trendState: 'SIDEWAYS'),
          createItem(symbol: '3008', trendState: null), // sideways
          createItem(symbol: '2412', trendState: 'UP'),
        ];
        final state = WatchlistState(items: items);

        final grouped = state.groupedByTrend;

        expect(grouped[WatchlistTrend.up]!.length, equals(2));
        expect(grouped[WatchlistTrend.down]!.length, equals(1));
        expect(grouped[WatchlistTrend.sideways]!.length, equals(2));
      });

      test('returns same cached instance on multiple accesses', () {
        final state = WatchlistState(items: [createItem(symbol: '2330')]);

        final first = state.groupedByTrend;
        final second = state.groupedByTrend;

        expect(identical(first, second), isTrue);
      });
    });

    group('groupedByCategory lazy caching', () {
      test('groups items by custom group, ungrouped bucket last', () {
        final groups = [
          createGroup(id: 1, name: '核心', sortOrder: 0),
          createGroup(id: 2, name: '觀察', sortOrder: 1),
        ];
        final items = [
          createItem(symbol: '2330', groupId: 1, groupName: '核心'),
          createItem(symbol: '2454', groupId: 1, groupName: '核心'),
          createItem(symbol: '2317', groupId: 2, groupName: '觀察'),
          createItem(symbol: '3008'), // 未分組
        ];
        final state = WatchlistState(items: items, groups: groups);

        final grouped = state.groupedByCategory;

        // 桶順序：分組依 sortOrder，未分組在最後
        final keys = grouped.keys.toList();
        expect(keys.length, 3);
        expect(keys[0], '核心');
        expect(keys[1], '觀察');
        expect(keys.last, 'watchlist.ungrouped'); // .tr() 未載入翻譯回傳 key

        expect(grouped['核心']!.map((i) => i.symbol), ['2330', '2454']);
        expect(grouped['觀察']!.single.symbol, '2317');
        expect(grouped[keys.last]!.single.symbol, '3008');
      });

      test('empty group still gets a (empty) bucket', () {
        final groups = [createGroup(id: 1, name: '空組')];
        final items = [createItem(symbol: '2330')]; // 全未分組
        final state = WatchlistState(items: items, groups: groups);

        final grouped = state.groupedByCategory;

        expect(grouped['空組'], isEmpty);
        expect(grouped['watchlist.ungrouped']!.single.symbol, '2330');
      });

      test('item pointing to deleted group falls into ungrouped', () {
        // groupId 指向不存在於 groups 的分組（如刪除後殘留）→ 歸未分組
        final items = [
          createItem(symbol: '2330', groupId: 99, groupName: '幽靈'),
        ];
        final state = WatchlistState(items: items, groups: const []);

        final grouped = state.groupedByCategory;

        expect(grouped['watchlist.ungrouped']!.single.symbol, '2330');
      });

      test('returns same cached instance on multiple accesses', () {
        final state = WatchlistState(
          items: [createItem(symbol: '2330')],
          groups: const [],
        );

        final first = state.groupedByCategory;
        final second = state.groupedByCategory;

        expect(identical(first, second), isTrue);
      });
    });

    group('copyWith', () {
      test('preserves cache when only sort changes', () {
        final items = [createItem(symbol: '2330')];
        final original = WatchlistState(items: items);

        // Access to trigger lazy init
        final _ = original.filteredItems;

        final updated = original.copyWith(sort: WatchlistSort.nameAsc);

        expect(updated.sort, equals(WatchlistSort.nameAsc));
        expect(updated.items, equals(items));
        // filteredItems should be the same reference (cache preserved)
        expect(
          identical(updated.filteredItems, original.filteredItems),
          isTrue,
        );
      });

      test('preserves cache when only group changes', () {
        final items = [createItem(symbol: '2330')];
        final original = WatchlistState(items: items);

        final updated = original.copyWith(group: WatchlistGroup.trend);

        expect(updated.group, equals(WatchlistGroup.trend));
        expect(
          identical(updated.filteredItems, original.filteredItems),
          isTrue,
        );
      });

      test('preserves cache when only isLoading changes', () {
        final items = [createItem(symbol: '2330')];
        final original = WatchlistState(items: items);

        final updated = original.copyWith(isLoading: true);

        expect(updated.isLoading, isTrue);
        expect(
          identical(updated.filteredItems, original.filteredItems),
          isTrue,
        );
      });

      test('recomputes cache when items change', () {
        final original = WatchlistState(items: [createItem(symbol: '2330')]);
        final newItems = [
          createItem(symbol: '2330'),
          createItem(symbol: '2317'),
        ];

        final updated = original.copyWith(items: newItems);

        expect(updated.items.length, equals(2));
        expect(
          identical(updated.filteredItems, original.filteredItems),
          isFalse,
        );
      });

      test('recomputes cache when searchQuery changes', () {
        final items = [createItem(symbol: '2330'), createItem(symbol: '2317')];
        final original = WatchlistState(items: items);

        final updated = original.copyWith(searchQuery: '2330');

        expect(updated.filteredItems.length, equals(1));
        expect(
          identical(updated.filteredItems, original.filteredItems),
          isFalse,
        );
      });

      test('preserves error when not specified and items change', () {
        final original = WatchlistState(
          items: [createItem(symbol: '2330')],
          error: 'Previous error',
        );

        final updated = original.copyWith(items: [createItem(symbol: '2317')]);

        expect(updated.error, equals('Previous error'));
      });

      test('sets error when explicitly provided', () {
        final original = WatchlistState();

        final updated = original.copyWith(error: 'New error');

        expect(updated.error, equals('New error'));
      });

      test('clears error when explicitly set to null', () {
        final original = WatchlistState(error: 'Old error');

        final updated = original.copyWith(error: null);

        expect(updated.error, isNull);
      });
    });
  });

  group('WatchlistItemData', () {
    group('status getter', () {
      test('returns signal when hasSignal is true', () {
        const item = WatchlistItemData(
          symbol: '2330',
          hasSignal: true,
          priceChange: 1.0,
        );

        expect(item.status, equals(WatchlistStatus.signal));
      });

      test('returns volatile when priceChange >= 3%', () {
        const item = WatchlistItemData(symbol: '2330', priceChange: 3.0);

        expect(item.status, equals(WatchlistStatus.volatile));
      });

      test('returns volatile when priceChange <= -3%', () {
        const item = WatchlistItemData(symbol: '2330', priceChange: -3.5);

        expect(item.status, equals(WatchlistStatus.volatile));
      });

      test('returns quiet when priceChange < 3%', () {
        const item = WatchlistItemData(symbol: '2330', priceChange: 2.9);

        expect(item.status, equals(WatchlistStatus.quiet));
      });

      test('returns quiet when priceChange is null', () {
        const item = WatchlistItemData(symbol: '2330');

        expect(item.status, equals(WatchlistStatus.quiet));
      });

      test('signal takes priority over volatile', () {
        const item = WatchlistItemData(
          symbol: '2330',
          hasSignal: true,
          priceChange: 5.0, // Would be volatile if not for signal
        );

        expect(item.status, equals(WatchlistStatus.signal));
      });
    });

    group('trend getter', () {
      test('returns up for UP trendState', () {
        const item = WatchlistItemData(symbol: '2330', trendState: 'UP');

        expect(item.trend, equals(WatchlistTrend.up));
      });

      test('returns down for DOWN trendState', () {
        const item = WatchlistItemData(symbol: '2330', trendState: 'DOWN');

        expect(item.trend, equals(WatchlistTrend.down));
      });

      test('returns sideways for SIDEWAYS trendState', () {
        const item = WatchlistItemData(symbol: '2330', trendState: 'SIDEWAYS');

        expect(item.trend, equals(WatchlistTrend.sideways));
      });

      test('returns sideways for null trendState', () {
        const item = WatchlistItemData(symbol: '2330');

        expect(item.trend, equals(WatchlistTrend.sideways));
      });

      test('returns sideways for unknown trendState', () {
        const item = WatchlistItemData(symbol: '2330', trendState: 'UNKNOWN');

        expect(item.trend, equals(WatchlistTrend.sideways));
      });
    });
  });

  group('WatchlistSort', () {
    test('all values have labels', () {
      for (final sort in WatchlistSort.values) {
        expect(sort.label, isNotEmpty);
      }
    });
  });

  group('WatchlistGroup', () {
    test('all values have labels', () {
      for (final group in WatchlistGroup.values) {
        expect(group.label, isNotEmpty);
      }
    });
  });

  group('WatchlistStatus', () {
    test('all values have icons and labels', () {
      for (final status in WatchlistStatus.values) {
        expect(status.icon, isNotEmpty);
        expect(status.label, isNotEmpty);
      }
    });
  });

  group('WatchlistTrend', () {
    test('all values have icons and labels', () {
      for (final trend in WatchlistTrend.values) {
        expect(trend.icon, isNotEmpty);
        expect(trend.label, isNotEmpty);
      }
    });
  });
}
