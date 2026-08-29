import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:daredevil/core/constants/pagination.dart';
import 'package:daredevil/core/constants/rule_params.dart';
import 'package:daredevil/core/utils/date_context.dart';
import 'package:daredevil/core/utils/error_display.dart';
import 'package:daredevil/core/utils/logger.dart';
import 'package:daredevil/domain/services/price_calculator.dart';
import 'package:daredevil/core/utils/sentinel.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/domain/models/signal_names.dart';
import 'package:daredevil/data/database/cached_accessor.dart';
import 'package:daredevil/data/repositories/insider_repository.dart';
import 'package:daredevil/data/repositories/warning_repository.dart';
import 'package:daredevil/presentation/providers/data_update_epoch_provider.dart';
import 'package:daredevil/presentation/providers/settings_provider.dart';
import 'package:daredevil/presentation/providers/providers.dart';
import 'package:daredevil/presentation/providers/watchlist_types.dart';
import 'package:daredevil/presentation/widgets/warning_badge.dart';

export 'package:daredevil/presentation/providers/watchlist_types.dart';

// ==================================================
// 自選股頁面狀態
// ==================================================

/// 自選股頁面狀態
///
/// 使用快取策略：[filteredItems]、[groupedByStatus]、[groupedByTrend]
/// 僅在建構時計算一次，避免每次 build 時重複計算。
class WatchlistState {
  WatchlistState({
    this.items = const [],
    this.groups = const [],
    this.isLoading = false,
    this.error,
    this.sort = WatchlistSort.addedDesc,
    this.group = WatchlistGroup.none,
    this.searchQuery = '',
    this.isLoadingMore = false,
    this.hasMore = true,
    this.displayedCount = kPageSize,
  }) : _filteredItems = _computeFilteredItems(items, searchQuery),
       watchedSymbols = Set.unmodifiable({for (final i in items) i.symbol}),
       _groupedByStatus = null,
       _groupedByTrend = null,
       _groupedByCategory = null;

  /// 內部建構子：copyWith 時保留快取值
  WatchlistState._internal({
    required this.items,
    required this.groups,
    required this.isLoading,
    required this.error,
    required this.sort,
    required this.group,
    required this.searchQuery,
    required this.isLoadingMore,
    required this.hasMore,
    required this.displayedCount,
    required List<WatchlistItemData> filteredItems,
    required this.watchedSymbols,
  }) : _filteredItems = filteredItems,
       _groupedByStatus = null,
       _groupedByTrend = null,
       _groupedByCategory = null;

  final List<WatchlistItemData> items;

  /// 自選代碼集(items 的派生快取,2026-08-15 select 修復)。
  ///
  /// 只要 symbol 集的消費端一律 `select((s) => s.watchedSymbols)`,不要
  /// 自己 `items.map(...).toSet()`——那會每次 emit 生新 Set(identity ==),
  /// select 的相等性比較永遠判「已變」,searchQuery 每打一字全頁 rebuild。
  /// 本欄位只在 items 變更時重建,無關變更保留同一實例;內容 unmodifiable,
  /// 要 mutate 請自持副本 `{...symbols}`(見 scan_provider)。
  /// 已知例外:兩個 filing entry 需要 (symbol, name) 對,本欄位餵不了,
  /// 仍屬不穩定 select(輕量列,rebuild 成本可忽略,未修)。
  final Set<String> watchedSymbols;

  /// 使用者自訂分組清單（依 sortOrder 排序），供管理分組 / picker 使用
  final List<WatchlistGroupEntry> groups;
  final bool isLoading;
  final String? error;
  final WatchlistSort sort;
  final WatchlistGroup group;
  final String searchQuery;

  /// 是否正在載入更多（無限滾動）
  final bool isLoadingMore;

  /// 是否還有更多資料可載入
  final bool hasMore;

  /// 目前已顯示的數量
  final int displayedCount;

  // 快取的過濾結果
  final List<WatchlistItemData> _filteredItems;
  // 延遲初始化的分組快取
  Map<WatchlistStatus, List<WatchlistItemData>>? _groupedByStatus;
  Map<WatchlistTrend, List<WatchlistItemData>>? _groupedByTrend;
  Map<String, List<WatchlistItemData>>? _groupedByCategory;

  /// 搜尋過濾後的項目（已快取）
  List<WatchlistItemData> get filteredItems => _filteredItems;

  /// 目前顯示的項目（分頁後）
  List<WatchlistItemData> get displayedItems {
    return _filteredItems.take(displayedCount).toList();
  }

  /// 依狀態分組（延遲初始化快取）
  Map<WatchlistStatus, List<WatchlistItemData>> get groupedByStatus {
    return _groupedByStatus ??= _computeGroupedByStatus(_filteredItems);
  }

  /// 依趨勢分組（延遲初始化快取）
  Map<WatchlistTrend, List<WatchlistItemData>> get groupedByTrend {
    return _groupedByTrend ??= _computeGroupedByTrend(_filteredItems);
  }

  /// 依使用者自訂分組分組（延遲初始化快取）
  ///
  /// Key 為分組名稱（依 [groups] 的 sortOrder 排序），最後附上未分組桶
  /// （i18n `watchlist.ungrouped`）。只保留「有成員」的分組桶，空分組不顯示
  /// 標題（與 status/trend 分組的空桶過濾一致，由 UI 端負責）。
  Map<String, List<WatchlistItemData>> get groupedByCategory {
    return _groupedByCategory ??= _computeGroupedByCategory(
      _filteredItems,
      groups,
    );
  }

  /// 根據搜尋關鍵字計算過濾結果
  static List<WatchlistItemData> _computeFilteredItems(
    List<WatchlistItemData> items,
    String searchQuery,
  ) {
    if (searchQuery.isEmpty) return items;
    final query = searchQuery.toLowerCase();
    return items.where((item) {
      return item.symbol.toLowerCase().contains(query) ||
          (item.stockName?.toLowerCase().contains(query) ?? false);
    }).toList();
  }

  /// 計算狀態分組
  static Map<WatchlistStatus, List<WatchlistItemData>> _computeGroupedByStatus(
    List<WatchlistItemData> items,
  ) {
    final result = <WatchlistStatus, List<WatchlistItemData>>{};
    for (final status in WatchlistStatus.values) {
      result[status] = [];
    }
    for (final item in items) {
      result[item.status]!.add(item);
    }
    return result;
  }

  /// 計算趨勢分組
  static Map<WatchlistTrend, List<WatchlistItemData>> _computeGroupedByTrend(
    List<WatchlistItemData> items,
  ) {
    final result = <WatchlistTrend, List<WatchlistItemData>>{};
    for (final trend in WatchlistTrend.values) {
      result[trend] = [];
    }
    for (final item in items) {
      result[item.trend]!.add(item);
    }
    return result;
  }

  /// 計算自訂分組（依 [groups] 的 sortOrder 排序，未分組放最後）
  ///
  /// 依 item 的 groupId 分桶；groupId 為 null 或對應分組已不存在的，歸入
  /// 「未分組」桶。回傳的 Map 用 insertion order 保證顯示順序：先依
  /// [groups] 順序，最後才是未分組。
  static Map<String, List<WatchlistItemData>> _computeGroupedByCategory(
    List<WatchlistItemData> items,
    List<WatchlistGroupEntry> groups,
  ) {
    final ungroupedLabel = 'watchlist.ungrouped'.tr();
    // 以 LinkedHashMap（Dart Map 預設保序）建立順序：分組在前、未分組在後
    final result = <String, List<WatchlistItemData>>{};
    final groupIdToName = <int, String>{};
    for (final g in groups) {
      result[g.name] = [];
      groupIdToName[g.id] = g.name;
    }
    final ungrouped = <WatchlistItemData>[];
    for (final item in items) {
      final name = item.groupId != null ? groupIdToName[item.groupId] : null;
      if (name != null) {
        result[name]!.add(item);
      } else {
        ungrouped.add(item);
      }
    }
    result[ungroupedLabel] = ungrouped;
    return result;
  }

  WatchlistState copyWith({
    List<WatchlistItemData>? items,
    List<WatchlistGroupEntry>? groups,
    bool? isLoading,
    Object? error = sentinel,
    WatchlistSort? sort,
    WatchlistGroup? group,
    String? searchQuery,
    bool? isLoadingMore,
    bool? hasMore,
    int? displayedCount,
  }) {
    final newItems = items ?? this.items;
    final newGroups = groups ?? this.groups;
    final newSearchQuery = searchQuery ?? this.searchQuery;
    final newError = error == sentinel ? this.error : error as String?;

    // 兩個派生快取各自精確依賴,無關變更保留原實例(select 穩定性的關鍵):
    // - filteredItems 依賴 items + searchQuery
    // - watchedSymbols 只依賴 items
    // （groups 變更只影響 groupedByCategory，內部建構子的該快取本就重置）
    final itemsChanged = items != null;
    final searchChanged =
        searchQuery != null && searchQuery != this.searchQuery;
    return WatchlistState._internal(
      items: newItems,
      groups: newGroups,
      isLoading: isLoading ?? this.isLoading,
      error: newError,
      sort: sort ?? this.sort,
      group: group ?? this.group,
      searchQuery: newSearchQuery,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      displayedCount: displayedCount ?? this.displayedCount,
      filteredItems: (itemsChanged || searchChanged)
          ? _computeFilteredItems(newItems, newSearchQuery)
          : _filteredItems,
      watchedSymbols: itemsChanged
          ? Set.unmodifiable({for (final i in newItems) i.symbol})
          : watchedSymbols,
    );
  }
}

// ==================================================
// 自選股 Notifier
// ==================================================

class WatchlistNotifier extends Notifier<WatchlistState> {
  var _active = true;

  /// load generation guard(2026-07-30 審查):dataUpdateEpoch listener 與
  /// pull-to-refresh 可並發觸發 loadData,先發慢完成者會以舊資料覆蓋新
  /// state——today/marketOverview 已修過同型 race,此為漏網 sibling。
  var _loadGeneration = 0;

  @override
  WatchlistState build() {
    _active = true;
    ref.onDispose(() => _active = false);
    _pendingAdds = {};

    // M6 fix：runUpdate 完成後 bump dataUpdateEpoch；自選畫面開著時自動
    // reload 拿到新分析 / 警示 / 法人，否則使用者切離再回來才會看到。
    ref.listen(dataUpdateEpochProvider, (_, _) {
      if (!_active) return;
      loadData();
    });

    return WatchlistState();
  }

  AppDatabase get _db => ref.read(databaseProvider);
  CachedDatabaseAccessor get _cachedDb => ref.read(cachedDbProvider);
  WarningRepository get _warningRepo => ref.read(warningRepositoryProvider);
  InsiderRepository get _insiderRepo => ref.read(insiderRepositoryProvider);

  /// 同一 symbol 的 in-flight addStock Future（快速連點共享結果）
  Map<String, Future<bool>> _pendingAdds = {};

  /// 清除錯誤狀態
  void clearError() => state = state.copyWith(error: null);

  /// 載入自選股資料
  Future<void> loadData() async {
    final generation = ++_loadGeneration;
    state = state.copyWith(isLoading: true, error: null);

    try {
      final dateCtx = DateContext.now();
      final analysisRepo = ref.read(analysisRepositoryProvider);

      // Group 1：平行取得自選清單（含分組名稱）+ 自訂分組清單 + 最新分析日期
      final (watchlist, groups, latestAnalysisDate) = await (
        _db.getWatchlistWithGroups(),
        _db.getWatchlistGroups(),
        analysisRepo.findLatestAnalysisDate(),
      ).wait;
      if (!_active || _loadGeneration != generation) return;

      if (watchlist.isEmpty) {
        state = state.copyWith(items: [], groups: groups, isLoading: false);
        return;
      }

      // 收集所有代號進行批次查詢
      final symbols = watchlist.map((w) => w.entry.symbol).toList();

      // 取得實際分析日期（使用分析表的日期，而非價格表）
      // 價格表的 MAX(date) 可能因歷史同步而超前分析表，
      // 導致 getAnalysesBatch/getReasonsBatch 查不到對應日期的資料
      final analysisDate = latestAnalysisDate ?? dateCtx.today;

      // Group 2：平行載入股票資料 + 警示資料
      // historyStart 必須以 analysisDate 為基準（而非今天），
      // 避免長假/資料過期時 historyStart > analysisDate 導致查詢範圍反轉
      final historyCtx = DateContext.forDate(analysisDate);
      final (data, warningsMap, highPledgeMap) = await (
        _cachedDb.loadStockListData(
          symbols: symbols,
          analysisDate: analysisDate,
          historyStart: historyCtx.historyStart,
        ),
        _warningRepo.getWatchlistWarnings(symbols),
        _insiderRepo.getWatchlistHighPledgeStocks(
          symbols,
          threshold: FundamentalParams.highPledgeRatioThreshold,
        ),
      ).wait;
      if (!_active || _loadGeneration != generation) return;

      // 解構 Record 欄位
      final stocksMap = data.stocks;
      final latestPricesMap = data.latestPrices;
      final analysesMap = data.analyses;
      final reasonsMap = data.reasons;
      final priceHistoriesMap = data.priceHistories;

      // 計算漲跌幅
      final priceChanges = PriceCalculator.calculatePriceChangesBatch(
        priceHistoriesMap,
        latestPricesMap,
      );

      // 讀取警示標記顯示設定
      final showBadges = ref.read(settingsProvider).showWarningBadges;

      // 從批次結果建構項目
      final items = watchlist.map((item) {
        final symbol = item.entry.symbol;
        final stock = stocksMap[symbol];
        final latestPrice = latestPricesMap[symbol];
        final analysis = analysesMap[symbol];
        final reasons = reasonsMap[symbol] ?? [];
        final priceHistory = priceHistoriesMap[symbol] ?? [];

        // 提取近期價格用於 sparkline
        final recentPrices = PriceCalculator.extractSparklinePrices(
          priceHistory,
        );

        // 判斷警示類型（優先級：處置 > 注意 > 高質押）
        // 受 showWarningBadges 設定控制
        final warningType = showBadges
            ? _determineWarningType(
                symbol: symbol,
                warningsMap: warningsMap,
                highPledgeMap: highPledgeMap,
              )
            : null;

        return WatchlistItemData(
          symbol: symbol,
          stockName: stock?.name,
          market: stock?.market,
          latestClose: latestPrice?.close,
          priceChange: priceChanges[symbol],
          trendState: analysis?.trendState,
          // 自選股預設顯示短線分數，未來可加 horizon 切換
          score: analysis?.scoreShort,
          hasSignal: reasons.isNotEmpty,
          addedAt: item.entry.createdAt,
          recentPrices: recentPrices,
          // MA 階段訊號前置(跌破>站回>回踩>蓄勢):ReasonTags 只顯示
          // 前 1-2 個,不排序會被其他訊號擠出視窗(2026-07-31)
          reasons: (reasons.map((r) => r.reasonType).toList()
            ..sort(
              (a, b) => SignalName.maStagePriority(
                a,
              ).compareTo(SignalName.maStagePriority(b)),
            )),
          warningType: warningType,
          groupId: item.entry.groupId,
          groupName: item.groupName,
        );
      }).toList();

      // 排序
      final sortedItems = _sortItems(items, state.sort);

      // 初始化分頁狀態
      final hasMore = sortedItems.length > kPageSize;
      final displayedCount = hasMore ? kPageSize : sortedItems.length;

      state = state.copyWith(
        items: sortedItems,
        groups: groups,
        isLoading: false,
        hasMore: hasMore,
        displayedCount: displayedCount,
      );
    } catch (e) {
      AppLogger.warning('WatchlistNotifier', '載入自選股資料失敗', e);
      if (!_active || _loadGeneration != generation) return;
      state = state.copyWith(isLoading: false, error: ErrorDisplay.message(e));
    }
  }

  /// 載入更多自選股（無限滾動）
  ///
  /// 純記憶體分頁運算——原本包著一個**無 log 的全靜默 catch**(違反專案
  /// 「catch 必留痕」鐵律),而 body 沒有任何可拋的 IO,實為 dead code,
  /// 直接拆掉(2026-08-29 靜默稽核 #17)。
  void loadMore() {
    // 防止重複載入
    if (state.isLoadingMore || !state.hasMore) return;

    // 計算下一頁的範圍
    final currentCount = state.displayedCount;
    final totalCount = state.filteredItems.length;
    const nextPageSize = kPageSize;
    final newDisplayedCount = (currentCount + nextPageSize).clamp(
      0,
      totalCount,
    );

    // 更新狀態
    state = state.copyWith(
      displayedCount: newDisplayedCount,
      hasMore: newDisplayedCount < totalCount,
    );
  }

  /// 依指定選項排序
  List<WatchlistItemData> _sortItems(
    List<WatchlistItemData> items,
    WatchlistSort sort,
  ) {
    final sorted = List<WatchlistItemData>.from(items);
    switch (sort) {
      case WatchlistSort.addedDesc:
        sorted.sort((a, b) => _compareDatesNullLast(b.addedAt, a.addedAt));
      case WatchlistSort.addedAsc:
        sorted.sort((a, b) => _compareDatesNullLast(a.addedAt, b.addedAt));
      case WatchlistSort.scoreDesc:
        sorted.sort((a, b) => (b.score ?? 0).compareTo(a.score ?? 0));
      case WatchlistSort.scoreAsc:
        sorted.sort((a, b) => (a.score ?? 0).compareTo(b.score ?? 0));
      case WatchlistSort.priceChangeDesc:
        sorted.sort(
          (a, b) => (b.priceChange ?? 0).compareTo(a.priceChange ?? 0),
        );
      case WatchlistSort.priceChangeAsc:
        sorted.sort(
          (a, b) => (a.priceChange ?? 0).compareTo(b.priceChange ?? 0),
        );
      case WatchlistSort.nameAsc:
        sorted.sort((a, b) => a.symbol.compareTo(b.symbol));
    }
    return sorted;
  }

  /// 比較日期，null 值排在最後
  int _compareDatesNullLast(DateTime? a, DateTime? b) {
    if (a == null && b == null) return 0;
    if (a == null) return 1; // a 是 null，排在後面
    if (b == null) return -1; // b 是 null，排在後面
    return a.compareTo(b);
  }

  /// 判斷警示類型（優先級：處置 > 注意 > 高質押）
  WarningBadgeType? _determineWarningType({
    required String symbol,
    required Map<String, TradingWarningEntry> warningsMap,
    required Map<String, InsiderHoldingEntry> highPledgeMap,
  }) {
    final warning = warningsMap[symbol];
    if (warning != null) {
      if (warning.warningType == 'DISPOSAL') {
        return WarningBadgeType.disposal;
      }
      return WarningBadgeType.attention;
    }
    if (highPledgeMap.containsKey(symbol)) {
      return WarningBadgeType.highPledge;
    }
    return null;
  }

  /// 設定排序選項
  void setSort(WatchlistSort sort) {
    if (state.sort == sort) return;
    final sortedItems = _sortItems(state.items, sort);
    state = state.copyWith(sort: sort, items: sortedItems);
  }

  /// 設定分組選項
  void setGroup(WatchlistGroup group) {
    state = state.copyWith(group: group);
  }

  // ==================================================
  // 自訂分組管理（資料夾模式：一檔一組）
  // ==================================================

  /// 重新載入自訂分組清單（不動 items）
  Future<void> _reloadGroups() async {
    final groups = await _db.getWatchlistGroups();
    if (!_active) return;
    state = state.copyWith(groups: groups);
  }

  /// 建立新分組，回傳新分組 id（失敗回 null）
  Future<int?> createGroup(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return null;
    try {
      final id = await _db.createWatchlistGroup(trimmed);
      await _reloadGroups();
      return id;
    } catch (e) {
      AppLogger.warning('WatchlistNotifier', '建立分組失敗: $name', e);
      state = state.copyWith(error: ErrorDisplay.message(e));
      return null;
    }
  }

  /// 重新命名分組（並同步更新受影響 items 的 groupName）
  Future<void> renameGroup(int id, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    try {
      await _db.renameWatchlistGroup(id, trimmed);
      // 就地更新已載入 items 的 groupName，避免整批 reload
      final newItems = state.items.map((item) {
        if (item.groupId == id) {
          return item.copyWith(groupName: trimmed);
        }
        return item;
      }).toList();
      state = state.copyWith(items: newItems);
      await _reloadGroups();
    } catch (e) {
      AppLogger.warning('WatchlistNotifier', '重新命名分組失敗: $id', e);
      state = state.copyWith(error: ErrorDisplay.message(e));
    }
  }

  /// 刪除分組（成員 groupId 由 FK setNull 清空，回到未分組、不刪股票）
  Future<void> deleteGroup(int id) async {
    try {
      await _db.deleteWatchlistGroup(id);
      // 就地把該分組成員改為未分組
      final newItems = state.items.map((item) {
        if (item.groupId == id) {
          return item.copyWith(clearGroup: true);
        }
        return item;
      }).toList();
      state = state.copyWith(items: newItems);
      await _reloadGroups();
    } catch (e) {
      AppLogger.warning('WatchlistNotifier', '刪除分組失敗: $id', e);
      state = state.copyWith(error: ErrorDisplay.message(e));
    }
  }

  /// 設定/清除預設分組（[id] 為 null 代表清除）
  ///
  /// 新加入的自選會自動落入預設分組（見 DAO `addToWatchlist`）。
  Future<void> setDefaultGroup(int? id) async {
    try {
      await _db.setDefaultWatchlistGroup(id);
      await _reloadGroups();
    } catch (e) {
      AppLogger.warning('WatchlistNotifier', '設定預設分組失敗: $id', e);
      state = state.copyWith(error: ErrorDisplay.message(e));
    }
  }

  /// 指定股票到分組（[groupId] 為 null 代表移出分組）
  Future<void> assignGroup(String symbol, int? groupId) async {
    try {
      await _db.assignWatchlistGroup(symbol, groupId);
      final groupName = groupId == null
          ? null
          : state.groups
                .where((g) => g.id == groupId)
                .map((g) => g.name)
                .firstOrNull;
      // 就地更新該 item 的 groupId / groupName
      final newItems = state.items.map((item) {
        if (item.symbol == symbol) {
          return groupId == null
              ? item.copyWith(clearGroup: true)
              : item.copyWith(groupId: groupId, groupName: groupName);
        }
        return item;
      }).toList();
      state = state.copyWith(items: newItems);
    } catch (e) {
      AppLogger.warning('WatchlistNotifier', '指定分組失敗: $symbol → $groupId', e);
      state = state.copyWith(error: ErrorDisplay.message(e));
    }
  }

  /// 設定搜尋關鍵字
  void setSearchQuery(String query) {
    state = state.copyWith(searchQuery: query);
  }

  /// 新增股票至自選股
  Future<bool> addStock(String symbol) async {
    // 若同一 symbol 已有 in-flight 請求，共享其結果（不另起新請求）
    final pending = _pendingAdds[symbol];
    if (pending != null) return pending;

    final future = _doAddStock(symbol);
    _pendingAdds[symbol] = future;
    try {
      return await future;
    } finally {
      _pendingAdds.remove(symbol);
    }
  }

  Future<bool> _doAddStock(String symbol) async {
    try {
      // 檢查股票是否存在
      final stock = await _db.getStock(symbol);
      if (stock == null) {
        return false;
      }

      // 檢查是否已在自選股中
      final existingSymbols = state.items.map((i) => i.symbol).toSet();
      if (existingSymbols.contains(symbol)) {
        return true;
      }
      // 寫入資料庫
      await _db.addToWatchlist(symbol);

      // 從資料庫讀取實際的 createdAt，確保與 loadData 一致
      final watchlistEntry = await _db.getWatchlistEntry(symbol);
      final actualAddedAt = watchlistEntry?.createdAt ?? DateTime.now();

      // 增量更新：僅載入此股票資料
      final itemData = await _loadSingleStockData(
        symbol,
        stock.name,
        stock.market,
        addedAt: actualAddedAt,
      );
      final newItems = [...state.items, itemData];
      state = state.copyWith(
        items: _sortItems(newItems, state.sort),
        error: null,
      );

      // 背景回填歷史月營收（不阻塞 UI）
      unawaited(_backfillRevenueHistory(symbol));

      return true;
    } catch (e) {
      AppLogger.warning('WatchlistNotifier', '新增自選股失敗: $symbol', e);
      state = state.copyWith(error: ErrorDisplay.message(e));
      return false;
    }
  }

  /// 背景回填歷史月營收（用於「營收創歷史新高」規則）
  ///
  /// 僅在 DB 資料不足時才呼叫 FinMind API 回填 5 年歷史。
  Future<void> _backfillRevenueHistory(String symbol) async {
    try {
      final existing = await _db.getRecentMonthlyRevenue(symbol, months: 13);
      if (existing.length >= 12) return;

      final fundamentalRepo = ref.read(fundamentalRepositoryProvider);
      // 使用 wall-clock time 計算回填範圍（非關鍵路徑，不影響測試正確性）
      final now = DateTime.now();
      await fundamentalRepo.syncMonthlyRevenue(
        symbol: symbol,
        startDate: DateTime(now.year - 5, now.month),
        endDate: now,
      );
      AppLogger.info('WatchlistNotifier', '$symbol: 已回填歷史月營收');
    } catch (e, stack) {
      AppLogger.warning('WatchlistNotifier', '$symbol: 回填營收失敗 (非關鍵)', e, stack);
    }
  }

  /// 從自選股移除
  ///
  /// 使用樂觀更新策略：先更新 UI，若資料庫操作失敗則回滾至先前狀態。
  /// 保存完整的狀態快照以確保回滾時排序與分組設定一致。
  Future<bool> removeStock(String symbol) async {
    // 保存完整狀態快照以便回滾（包含排序、分組等設定）
    final previousState = state;

    // 樂觀更新：立即從狀態中移除，並清除先前錯誤
    state = state.copyWith(
      items: state.items.where((item) => item.symbol != symbol).toList(),
      error: null,
    );

    try {
      // 刪列前先從 DB 暫存分組（分組資訊隨列消失），供 restoreStock 還原。
      // 讀 DB 而非 state：state 可能被篩選/過期，DB 才是權威。
      // 自己的 try：暫存是 best-effort，讀失敗不該擋下主要的移除動作
      try {
        final entry = await _db.getWatchlistEntry(symbol);
        if (entry != null) {
          _removedGroupIds[symbol] = entry.groupId;
          // 沒有 undo 的移除（如 scan 頁）會讓暫存累積——設上限防洩漏
          if (_removedGroupIds.length > 32) {
            _removedGroupIds.remove(_removedGroupIds.keys.first);
          }
        }
      } catch (e) {
        AppLogger.warning('WatchlistNotifier', '暫存分組失敗（復原將落預設組）: $symbol', e);
      }
      await _db.removeFromWatchlist(symbol);
      return true;
    } catch (e) {
      // 回滾至完整的先前狀態，確保排序順序一致
      AppLogger.warning('WatchlistNotifier', '移除自選股失敗: $symbol', e);
      state = previousState.copyWith(error: ErrorDisplay.message(e));
      return false;
    }
  }

  /// [removeStock] 暫存的原分組，key 為 symbol（2026-08-12）
  ///
  /// 修前：復原走 `addToWatchlist(symbol)`，股票「移除→復原」一輪就從
  /// 原分組被靜默搬進預設分組/未分組。
  final Map<String, int?> _removedGroupIds = {};

  /// 還原已移除的股票（回到移除前的分組）
  Future<void> restoreStock(String symbol) async {
    try {
      // Value(null) 與 absent 語意不同：前者是「本來就未分組」，
      // absent 才交給 DAO 的預設分組解析
      final groupId = _removedGroupIds.containsKey(symbol)
          ? Value<int?>(_removedGroupIds[symbol])
          : const Value<int?>.absent();
      await _db.addToWatchlist(symbol, groupId: groupId);
      _removedGroupIds.remove(symbol); // 成功才清，失敗保留供重試

      // 從資料庫讀取實際的 createdAt，確保與 loadData 一致
      final watchlistEntry = await _db.getWatchlistEntry(symbol);
      final actualAddedAt = watchlistEntry?.createdAt ?? DateTime.now();

      // 增量更新：僅載入此股票資料
      final stock = await _db.getStock(symbol);
      final itemData = await _loadSingleStockData(
        symbol,
        stock?.name,
        stock?.market,
        addedAt: actualAddedAt,
      );
      final newItems = [...state.items, itemData];
      state = state.copyWith(
        items: _sortItems(newItems, state.sort),
        error: null,
      );
    } catch (e) {
      AppLogger.warning('WatchlistNotifier', '還原自選股失敗: $symbol', e);
      state = state.copyWith(error: ErrorDisplay.message(e));
    }
  }

  /// 載入單一股票資料（用於增量更新）
  ///
  /// [addedAt] 應從資料庫的 watchlist entry 取得，以確保與 loadData 一致。
  /// 若未提供則使用當前時間作為 fallback。
  Future<WatchlistItemData> _loadSingleStockData(
    String symbol,
    String? stockName,
    String? market, {
    DateTime? addedAt,
  }) async {
    // 取得實際資料日期，確保非交易日也能正確顯示趨勢
    final latestDataDate = await _db.getLatestDataDate();
    final analysisDate = latestDataDate != null
        ? DateContext.normalize(latestDataDate)
        : DateContext.now().today;

    // 用 analysisDate 對齊 loadData 的歷史視窗計算（與 loadData 內
    // DateContext.forDate 同 pattern）—
    // 避免增量加股的 sparkline 用 wall-clock 範圍，跟清單其他項日期偏差。
    final historyCtx = DateContext.forDate(analysisDate);

    // 平行載入此股票的所有資料（含警示）
    final (
      latestPrice,
      analysis,
      reasons,
      priceHistory,
      warningsMap,
      highPledgeMap,
    ) = await (
      _db.getLatestPrice(symbol),
      _db.getAnalysis(symbol, analysisDate),
      _db.getReasons(symbol, analysisDate),
      _db.getPriceHistory(
        symbol,
        startDate: historyCtx.historyStart,
        endDate: analysisDate,
      ),
      _warningRepo.getWatchlistWarnings([symbol]),
      _insiderRepo.getWatchlistHighPledgeStocks([
        symbol,
      ], threshold: FundamentalParams.highPledgeRatioThreshold),
    ).wait;

    // Calculate price change（統一使用 PriceCalculator，優先取 API 漲跌價差）
    final priceChange = PriceCalculator.calculatePriceChange(
      priceHistory,
      latestPrice,
    );

    // 提取近期價格用於 sparkline
    final recentPrices = PriceCalculator.extractSparklinePrices(priceHistory);
    // 與批次 loadData 同一 gate：關閉「顯示警示徽章」時不得計算
    // （2026-07-23 稽核修復——原本無條件計算，addStock/restore 的項目
    // 會無視設定顯示徽章直到下次全量 reload）
    final showBadges = ref.read(settingsProvider).showWarningBadges;
    final warningType = showBadges
        ? _determineWarningType(
            symbol: symbol,
            warningsMap: warningsMap,
            highPledgeMap: highPledgeMap,
          )
        : null;

    return WatchlistItemData(
      symbol: symbol,
      stockName: stockName,
      market: market,
      latestClose: latestPrice?.close,
      priceChange: priceChange,
      trendState: analysis?.trendState,
      // 自選股預設顯示短線分數，未來可加 horizon 切換
      score: analysis?.scoreShort,
      hasSignal: reasons.isNotEmpty,
      addedAt: addedAt ?? DateTime.now(),
      recentPrices: recentPrices,
      reasons: reasons.map((r) => r.reasonType).toList(),
      warningType: warningType,
    );
  }
}

/// 自選股頁面狀態 Provider
final watchlistProvider = NotifierProvider<WatchlistNotifier, WatchlistState>(
  WatchlistNotifier.new,
);
