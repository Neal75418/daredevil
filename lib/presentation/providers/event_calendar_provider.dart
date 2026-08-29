import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:table_calendar/table_calendar.dart';

import 'package:daredevil/core/constants/data_freshness.dart';
import 'package:daredevil/core/theme/semantic_colors.dart';
import 'package:daredevil/core/utils/clock.dart';
import 'package:daredevil/core/utils/date_context.dart';
import 'package:daredevil/core/utils/error_display.dart';
import 'package:daredevil/core/utils/logger.dart';
import 'package:daredevil/core/utils/sentinel.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/data/repositories/event_repository.dart';
import 'package:daredevil/presentation/providers/providers.dart';

// ==================================================
// 狀態模型
// ==================================================

/// 事件類型枚舉
enum EventType {
  exDividend('EX_DIVIDEND'),
  exRights('EX_RIGHTS'),
  earnings('EARNINGS'),
  shareholderMeeting('SHAREHOLDER_MEETING'),
  disposalEnd('DISPOSAL_END'),
  shortSuspension('SHORT_SUSPENSION'),
  custom('CUSTOM');

  const EventType(this.value);
  final String value;

  static EventType fromValue(String v) {
    return EventType.values.firstWhere(
      (e) => e.value == v,
      orElse: () => EventType.custom,
    );
  }

  String get i18nKey {
    switch (this) {
      case EventType.exDividend:
        return 'calendar.typeExDividend';
      case EventType.exRights:
        return 'calendar.typeExRights';
      case EventType.earnings:
        return 'calendar.typeEarnings';
      case EventType.shareholderMeeting:
        return 'calendar.typeMeeting';
      case EventType.disposalEnd:
        return 'calendar.typeDisposalEnd';
      case EventType.shortSuspension:
        return 'calendar.typeShortSuspension';
      case EventType.custom:
        return 'calendar.typeCustom';
    }
  }

  /// 類型識別色——僅用於 tint 底、左邊框等裝飾層。
  ///
  /// 文字與圖示請走 [onTintFor]：同色前景疊在自身 15% tint 上，
  /// 合成後多數類型僅 1.8～3.9:1。
  Color get color {
    switch (this) {
      case EventType.exDividend:
        return Colors.red;
      case EventType.exRights:
        return Colors.orange;
      case EventType.earnings:
        return Colors.green;
      case EventType.shareholderMeeting:
        // 紫→teal（2026-07-24 使用者回饋：粉紫不喜歡）→cyan（2026-08-01
        // 複審：teal 全家族色相 172~175° 落在綠區(88-175)內緣、違反
        // 紅綠專屬股價鐵律；cyan 186° 出區且保留同一冷色溫觀感，與
        // 紅/橘/綠/藍灰/棕/藍仍可區分。守門見 semantic_colors_test
        // 的 EventType 色相掃描）
        return Colors.cyan;
      case EventType.disposalEnd:
        // 監管類事件走中性藍灰，與五個既有類別皆可區分
        return Colors.blueGrey;
      case EventType.shortSuspension:
        // 棕：與紅/橘/綠/cyan/藍灰/藍皆可區分、且非使用者排除的紫粉家族
        return Colors.brown;
      case EventType.custom:
        return Colors.blue;
    }
  }

  /// 自身 tint（@0.15）之上的文字／圖示色，依主題解析。
  ///
  /// 各組合實測 4.7～8.7:1（守門見 `semantic_colors_test.dart`）。
  /// 除息（紅）／財報（綠）屬紅綠家族，色值調整延後至紅綠專案，
  /// 目前沿用識別色本色（維持既有視覺，缺陷已記錄於 Phase 2 清單）。
  Color onTintFor(Brightness brightness) {
    final isLight = brightness == Brightness.light;
    switch (this) {
      case EventType.exDividend:
        // 深色：紅家族淺紅（同 PriceColors.chipBullish 值，5.67:1）；
        // 淺色維持本色（deferred，使用者僅用深色主題）
        return isLight ? Colors.red : const Color(0xFFFF8A94);
      case EventType.exRights:
        return WarningColors.onTintFor(brightness);
      case EventType.earnings:
        // 深色：綠家族淺綠（同 PriceColors.chipBearish 值，6.86:1）；淺色同上
        return isLight ? Colors.green : const Color(0xFF7DD8A0);
      case EventType.shareholderMeeting:
        // 淺色 cyan 本色對比不足需壓深（cyan900 達 4.5）；深色 cyan200
        return isLight ? const Color(0xFF006064) : const Color(0xFF80DEEA);
      case EventType.disposalEnd:
        // 淺色 blueGrey800、深色 blueGrey200
        return isLight ? const Color(0xFF37474F) : const Color(0xFFB0BEC5);
      case EventType.shortSuspension:
        // material brown 的深淺階(brown800 11°/brown200 15°)落在紅區
        // (hue≤15)——手調同觀感棕色、色相移到 25~30°(2026-08-01 複審
        // 擴掃抓到,守門見 semantic_colors_test EventType 色相掃描)
        return isLight ? const Color(0xFF5F452A) : const Color(0xFFC9AE93);
      case EventType.custom:
        return isLight ? const Color(0xFF1565C0) : const Color(0xFF90CAF9);
    }
  }

  /// 主題調和後的**實心**識別色——dot、卡片左框、日期字、chip 色點等
  /// 「直接畫在 surface 上」的裝飾。深色沿用 [onTintFor] 的粉彩家族
  /// （對 dark surface 對比有守門背書），淺色維持本色。
  ///
  /// 注意：**tint 底（@0.15 疊色）仍走 [color]**——粉彩當 tint 基底會把
  /// 合成底拉亮、讓前景對比跌破 4.5（custom 實算 ~4.2），守門測試的
  /// 組合（fg=onTintFor、tint=color@0.15）維持不動。
  Color colorFor(Brightness brightness) =>
      brightness == Brightness.light ? color : onTintFor(brightness);

  IconData get icon {
    switch (this) {
      case EventType.exDividend:
        return Icons.payments_outlined;
      case EventType.exRights:
        return Icons.inventory_2_outlined;
      case EventType.earnings:
        return Icons.article_outlined;
      case EventType.shareholderMeeting:
        return Icons.groups_outlined;
      case EventType.disposalEnd:
        return Icons.lock_open_outlined;
      case EventType.shortSuspension:
        return Icons.block_outlined;
      case EventType.custom:
        return Icons.edit_note;
    }
  }
}

/// 日曆篩選模式
enum CalendarFilter { all, watchlistOnly, portfolioOnly }

/// 行事曆狀態
class EventCalendarState {
  EventCalendarState({
    this.focusedMonth,
    this.selectedDate,
    this.events = const {},
    this.selectedDayEvents = const [],
    this.upcomingEvents = const [],
    // 預設自選：全市場事件（尤其股東會）對交易流程是雜訊，
    // 行事曆該回答「我的股票要發生什麼事」（2026-07-24 分析師視角檢討）
    this.filter = CalendarFilter.watchlistOnly,
    Set<EventType>? selectedEventTypes,
    this.calendarFormat = CalendarFormat.month,
    this.isLoading = false,
    this.isSyncing = false,
    this.error,
  }) : selectedEventTypes = selectedEventTypes ?? EventType.values.toSet();

  final DateTime? focusedMonth;
  final DateTime? selectedDate;

  /// 月事件 map（日期 → 事件列表），用於顯示日曆上的 dot indicators
  final Map<DateTime, List<StockEventEntry>> events;

  /// 選取日期的事件列表
  final List<StockEventEntry> selectedDayEvents;

  /// 未來 14 天的即將到來事件
  final List<StockEventEntry> upcomingEvents;

  /// 篩選模式
  final CalendarFormat calendarFormat;

  final CalendarFilter filter;

  /// 選取的事件類型（用於類型篩選）
  final Set<EventType> selectedEventTypes;

  final bool isLoading;

  /// 是否正在同步（防止連續點擊）
  final bool isSyncing;

  final String? error;

  /// 根據 selectedEventTypes 過濾後的事件 map
  /// 套用類型篩選後的近期事件（未來14天卡列用）——與月曆 dots／當日
  /// 清單同一套 selectedEventTypes，關掉的類型不得只從月曆消失
  List<StockEventEntry> get visibleUpcomingEvents => upcomingEvents
      .where(
        (e) => selectedEventTypes.contains(EventType.fromValue(e.eventType)),
      )
      .toList();

  Map<DateTime, List<StockEventEntry>> get filteredEvents {
    if (selectedEventTypes.length == EventType.values.length) return events;
    final filtered = <DateTime, List<StockEventEntry>>{};
    for (final entry in events.entries) {
      final list = entry.value
          .where(
            (e) =>
                selectedEventTypes.contains(EventType.fromValue(e.eventType)),
          )
          .toList();
      if (list.isNotEmpty) filtered[entry.key] = list;
    }
    return filtered;
  }

  EventCalendarState copyWith({
    DateTime? focusedMonth,
    DateTime? selectedDate,
    Map<DateTime, List<StockEventEntry>>? events,
    List<StockEventEntry>? selectedDayEvents,
    List<StockEventEntry>? upcomingEvents,
    CalendarFilter? filter,
    Set<EventType>? selectedEventTypes,
    CalendarFormat? calendarFormat,
    bool? isLoading,
    bool? isSyncing,
    Object? error = sentinel,
  }) {
    return EventCalendarState(
      focusedMonth: focusedMonth ?? this.focusedMonth,
      selectedDate: selectedDate ?? this.selectedDate,
      events: events ?? this.events,
      selectedDayEvents: selectedDayEvents ?? this.selectedDayEvents,
      upcomingEvents: upcomingEvents ?? this.upcomingEvents,
      filter: filter ?? this.filter,
      selectedEventTypes: selectedEventTypes ?? this.selectedEventTypes,
      calendarFormat: calendarFormat ?? this.calendarFormat,
      isLoading: isLoading ?? this.isLoading,
      isSyncing: isSyncing ?? this.isSyncing,
      error: error == sentinel ? this.error : error as String?,
    );
  }
}

// ==================================================
// Notifier
// ==================================================

class EventCalendarNotifier extends Notifier<EventCalendarState> {
  late final EventRepository _repo;
  late final AppDatabase _db;
  late final AppClock _clock;

  /// Generation token：防止舊月份載入結果覆蓋新月份狀態
  int _loadGeneration = 0;

  @override
  EventCalendarState build() {
    _repo = ref.watch(eventRepositoryProvider);
    _db = ref.watch(databaseProvider);
    _clock = ref.watch(appClockProvider);
    _loadGeneration = 0;
    return EventCalendarState();
  }

  /// 初始化：設定焦點月份為當月，載入事件
  Future<void> init() async {
    final now = _clock.now();
    final focused = DateTime(now.year, now.month);
    state = state.copyWith(focusedMonth: focused, selectedDate: now);
    await loadMonthEvents(focused);
    _updateSelectedDayEvents(now);
    await _loadUpcomingEvents();
  }

  /// 載入某月的事件
  ///
  /// 使用 generation token 防止舊月份結果覆蓋新月份狀態。
  /// 回傳 `true` 表示載入完成並已寫入 state，`false` 表示被更新的載入取代。
  Future<bool> loadMonthEvents(DateTime month) async {
    final generation = ++_loadGeneration;
    state = state.copyWith(isLoading: true, error: null);

    try {
      final start = DateTime(month.year, month.month, 1);
      final end = DateTime(
        month.year,
        month.month + 1,
        0,
        23,
        59,
        59,
        999,
        999,
      );

      // 根據篩選取得 symbol 清單
      final filterSymbols = await _resolveFilterSymbols();

      if (_loadGeneration != generation) return false;

      final eventList = await _repo.getEventsInRange(
        start,
        end,
        symbols: filterSymbols,
      );

      if (_loadGeneration != generation) return false;

      // 按日期分組（table_calendar 需要 normalize 到日期 key）
      final eventMap = <DateTime, List<StockEventEntry>>{};
      for (final event in eventList) {
        final dateKey = _normalizeDate(event.eventDate);
        eventMap.putIfAbsent(dateKey, () => []).add(event);
      }

      state = state.copyWith(
        focusedMonth: month,
        events: eventMap,
        isLoading: false,
        error: null,
      );

      // 更新選取日的事件
      if (state.selectedDate != null) {
        _updateSelectedDayEvents(state.selectedDate!);
      }
      return true;
    } catch (e) {
      if (_loadGeneration != generation) return false;
      AppLogger.warning('EventCalendarNotifier', '載入月事件失敗', e);
      state = state.copyWith(isLoading: false, error: ErrorDisplay.message(e));
      return true; // 完成了（雖然是錯誤），error 已寫入 state
    }
  }

  void clearError() {
    state = state.copyWith(error: null);
  }

  /// 選取日期
  void selectDate(DateTime date) {
    state = state.copyWith(selectedDate: date);
    _updateSelectedDayEvents(date);
  }

  /// 切換篩選模式
  Future<void> setFilter(CalendarFilter filter) async {
    state = state.copyWith(filter: filter);
    if (state.focusedMonth != null) {
      await loadMonthEvents(state.focusedMonth!);
    }
    // 未來14天清單與月曆同一套過濾，換 filter 一併刷新
    await _loadUpcomingEvents();
  }

  /// 儲存日曆格式偏好
  void setCalendarFormat(CalendarFormat format) {
    state = state.copyWith(calendarFormat: format);
  }

  /// 切換事件類型篩選
  void toggleEventType(EventType type) {
    final current = Set<EventType>.from(state.selectedEventTypes);
    if (current.contains(type)) {
      // 至少保留一種類型
      if (current.length > 1) current.remove(type);
    } else {
      current.add(type);
    }
    state = state.copyWith(selectedEventTypes: current);
    if (state.selectedDate != null) {
      _updateSelectedDayEvents(state.selectedDate!);
    }
  }

  /// 新增自訂事件
  ///
  /// 寫入成功後重載當月事件；若重載失敗會拋出例外，
  /// 讓呼叫端知道資料可能未同步（寫入本身已完成）。
  Future<void> addEvent({
    String? symbol,
    required DateTime eventDate,
    required String title,
    String? description,
  }) async {
    await _repo.addCustomEvent(
      symbol: symbol,
      eventDate: eventDate,
      title: title,
      description: description,
    );
    // 重新載入當月事件
    if (state.focusedMonth != null) {
      final completed = await loadMonthEvents(state.focusedMonth!);
      // loadMonthEvents 吞掉例外只寫 state.error，
      // 但呼叫端需要知道重載失敗才能給正確回饋。
      // 若被更新的載入取代（completed=false），寫入已成功，新載入會處理 UI。
      if (completed && state.error != null) {
        throw StateError(state.error!);
      }
    }
  }

  /// 更新自訂事件
  ///
  /// 寫入成功後重載當月事件；若重載失敗會拋出例外。
  Future<void> updateEvent({
    required int id,
    String? symbol,
    required DateTime eventDate,
    required String title,
    String? description,
  }) async {
    await _repo.updateCustomEvent(
      id: id,
      symbol: symbol,
      eventDate: eventDate,
      title: title,
      description: description,
    );
    // 重新載入當月事件
    if (state.focusedMonth != null) {
      final completed = await loadMonthEvents(state.focusedMonth!);
      if (completed && state.error != null) {
        throw StateError(state.error!);
      }
    }
  }

  /// 刪除事件
  ///
  /// 寫入成功後重載當月事件；若重載失敗會拋出例外。
  /// 若重載被更新的載入取代，寫入仍成功，不拋例外。
  Future<void> deleteEvent(int id) async {
    await _repo.deleteEvent(id);
    if (state.focusedMonth != null) {
      final completed = await loadMonthEvents(state.focusedMonth!);
      if (completed && state.error != null) {
        throw StateError(state.error!);
      }
    }
  }

  /// 同步除權息事件
  ///
  /// 與 [addEvent]/[deleteEvent] 不同，此方法回傳結果 record 供 UI 顯示，
  /// 重載失敗時 state.error 已被設定，呼叫端可據此顯示警告而不影響 record 結果。
  Future<
    ({int exDividend, int exRights, int total, List<String> failedSources})
  >
  syncDividendEvents() async {
    if (state.isSyncing) {
      return (
        exDividend: 0,
        exRights: 0,
        total: 0,
        failedSources: const <String>[],
      );
    }
    state = state.copyWith(isSyncing: true);
    try {
      final result = await _repo.syncDividendEvents();
      // 三個附帶同步皆 fail-soft:任何一個失敗都不得吞掉已完成的除權息
      // 結果、也不得跳過後面的 reload。但**失敗要列名**(靜默稽核 #8):
      // 這顆按鈕是這些事件唯一的同步入口(daily pipeline 不呼叫),只
      // log 的話 snackbar 照報成功,「行事曆上沒有停券事件」與「同步
      // 掛了」不可分。source key 由畫面映射 i18n。
      final failedSources = <String>[];
      try {
        // 處置出關(資料源:trading_warning,成本極低)
        await _repo.syncDisposalEndEvents();
      } catch (e) {
        AppLogger.warning('EventCalendar', '處置出關同步失敗', e);
        failedSources.add('disposalEnd');
      }
      try {
        // 停券預告走網路(BFI84U)
        await _repo.syncShortSuspensionEvents();
      } catch (e) {
        AppLogger.warning('EventCalendar', '停券預告同步失敗', e);
        failedSources.add('shortSuspension');
      }
      try {
        // 法說會(自重大訊息 t187ap04_L 抽取,累積式)
        await _repo.syncInvestorConferenceEvents();
      } catch (e) {
        AppLogger.warning('EventCalendar', '法說會同步失敗', e);
        failedSources.add('investorConference');
      }
      if (state.focusedMonth != null) {
        await loadMonthEvents(state.focusedMonth!);
      }
      await _loadUpcomingEvents();
      return (
        exDividend: result.exDividend,
        exRights: result.exRights,
        total: result.total,
        failedSources: failedSources,
      );
    } finally {
      state = state.copyWith(isSyncing: false);
    }
  }

  /// 依目前 filter 解析 symbol 清單（null＝不過濾）
  ///
  /// loadMonthEvents 與 _loadUpcomingEvents 共用——兩個視圖必須同一
  /// 套過濾，否則會出現「上方未來14天列著非自選股、下方當日卻說
  /// 無事件」的自相矛盾（2026-07-24 實機截圖）。
  Future<List<String>?> _resolveFilterSymbols() async {
    switch (state.filter) {
      case CalendarFilter.watchlistOnly:
        final watchlist = await _db.getWatchlist();
        return watchlist.map((e) => e.symbol).toList();
      case CalendarFilter.portfolioOnly:
        final positions = await _db.getPortfolioPositions();
        return positions.map((e) => e.symbol).toList();
      case CalendarFilter.all:
        return null;
    }
  }

  /// 載入近期事件
  ///
  /// 失敗時寫入 [state.error]，讓呼叫端（如 syncDividendEvents）
  /// 可據此向 UI 顯示警告。
  Future<void> _loadUpcomingEvents() async {
    try {
      final now = _clock.now();
      final today = DateTime(now.year, now.month, now.day);
      final end = today.add(
        const Duration(days: DataFreshness.upcomingEventsDays),
      );
      final events = await _repo.getEventsInRange(
        today,
        end,
        symbols: await _resolveFilterSymbols(),
      );
      state = state.copyWith(upcomingEvents: events);
    } catch (e) {
      AppLogger.warning('EventCalendarNotifier', '載入近期事件失敗', e);
      // 僅在尚無錯誤時寫入，避免覆蓋 loadMonthEvents 等更重要的錯誤
      if (state.error == null) {
        state = state.copyWith(error: ErrorDisplay.message(e));
      }
    }
  }

  void _updateSelectedDayEvents(DateTime date) {
    final dateKey = _normalizeDate(date);
    final dayEvents = state.filteredEvents[dateKey] ?? [];
    state = state.copyWith(selectedDayEvents: dayEvents);
  }

  /// 將 DateTime 正規化為只有日期的 key（table_calendar 比較用）
  static DateTime _normalizeDate(DateTime date) {
    return DateContext.normalize(date);
  }
}

// ==================================================
// Providers
// ==================================================

final eventCalendarProvider =
    NotifierProvider<EventCalendarNotifier, EventCalendarState>(
      EventCalendarNotifier.new,
    );
