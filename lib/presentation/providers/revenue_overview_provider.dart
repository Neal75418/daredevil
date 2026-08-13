import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:daredevil/core/utils/error_display.dart';
import 'package:daredevil/core/utils/logger.dart';
import 'package:daredevil/data/database/dao/revenue_dao.dart';
import 'package:daredevil/presentation/providers/providers.dart';

/// 營收總覽的排序鍵(全部基於資料庫真實存在的欄位——「公布順序」
/// 因無公布日欄位而刻意不提供,見 2026-08-05 設計討論)
enum RevenueSortBy { yoy, mom, revenue, ytdYoy }

/// 營收總覽的過濾器(過濾是使用者主動選的,預設「全部」不裁剪——
/// 清單的完整性是本頁的存在理由)
enum RevenueFilter { all, watchlist, newHigh }

class RevenueOverviewState {
  const RevenueOverviewState({
    this.overview,
    this.isLoading = false,
    this.error,
    this.sortBy = RevenueSortBy.yoy,
    this.filter = RevenueFilter.all,
  });

  final RevenueOverview? overview;
  final bool isLoading;
  final String? error;
  final RevenueSortBy sortBy;
  final RevenueFilter filter;

  RevenueOverviewState copyWith({
    RevenueOverview? overview,
    bool? isLoading,
    String? error,
    bool clearError = false,
    RevenueSortBy? sortBy,
    RevenueFilter? filter,
  }) {
    return RevenueOverviewState(
      overview: overview ?? this.overview,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
      sortBy: sortBy ?? this.sortBy,
      filter: filter ?? this.filter,
    );
  }

  /// 套用過濾+排序後的可見列(純函式,單元測試直接驗)。
  ///
  /// 排序皆為降冪;null 增減率(無前期基準)一律沉底,不與有值者混排。
  List<RevenueOverviewRow> visibleRows(Set<String> watchlistSymbols) {
    final o = overview;
    if (o == null) return const [];

    var rows = switch (filter) {
      RevenueFilter.all => o.rows,
      RevenueFilter.watchlist =>
        o.rows.where((r) => watchlistSymbols.contains(r.symbol)).toList(),
      RevenueFilter.newHigh => o.rows.where((r) => r.isNewHigh).toList(),
    };

    double? keyOf(RevenueOverviewRow r) => switch (sortBy) {
      RevenueSortBy.yoy => r.yoyGrowth,
      RevenueSortBy.mom => r.momGrowth,
      RevenueSortBy.revenue => r.revenue,
      RevenueSortBy.ytdYoy => r.ytdYoyGrowth,
    };

    rows = List.of(rows)
      ..sort((a, b) {
        // 年增排序的低基期防護(2026-08-13):怪物列(聯上單月 +109 萬%)
        // 沉到非低基期之後——沉底是排序不是裁剪,列仍完整可見(淡化)。
        // 只有年增排序需要:其他排序鍵不受基期效應污染。
        if (sortBy == RevenueSortBy.yoy && a.isLowBase != b.isLowBase) {
          return a.isLowBase ? 1 : -1;
        }
        final ka = keyOf(a);
        final kb = keyOf(b);
        if (ka == null && kb == null) return a.symbol.compareTo(b.symbol);
        if (ka == null) return 1;
        if (kb == null) return -1;
        return kb.compareTo(ka);
      });
    return rows;
  }
}

class RevenueOverviewNotifier extends Notifier<RevenueOverviewState> {
  @override
  RevenueOverviewState build() => const RevenueOverviewState();

  Future<void> loadData() async {
    if (state.isLoading) return;
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final overview = await ref
          .read(databaseProvider)
          .getRevenueOverviewForLatestMonth();
      state = state.copyWith(overview: overview, isLoading: false);
    } catch (e) {
      AppLogger.warning('RevenueOverviewNotifier', '載入營收總覽失敗', e);
      state = state.copyWith(isLoading: false, error: ErrorDisplay.message(e));
    }
  }

  void setSortBy(RevenueSortBy sortBy) =>
      state = state.copyWith(sortBy: sortBy);

  void setFilter(RevenueFilter filter) =>
      state = state.copyWith(filter: filter);
}

final revenueOverviewProvider =
    NotifierProvider<RevenueOverviewNotifier, RevenueOverviewState>(
      RevenueOverviewNotifier.new,
    );
