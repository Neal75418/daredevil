import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:table_calendar/table_calendar.dart';

import 'package:daredevil/core/theme/breakpoints.dart';
import 'package:daredevil/core/utils/date_context.dart';
import 'package:daredevil/core/utils/error_display.dart';
import 'package:daredevil/presentation/widgets/empty_state.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/presentation/providers/event_calendar_provider.dart';
import 'package:daredevil/presentation/screens/calendar/widgets/add_event_sheet.dart';
import 'package:daredevil/presentation/screens/calendar/widgets/event_detail_sheet.dart';
import 'package:daredevil/presentation/screens/calendar/widgets/event_list_tile.dart';
import 'package:daredevil/presentation/screens/calendar/widgets/upcoming_events_section.dart';

/// 事件行事曆頁面
class EventCalendarScreen extends ConsumerStatefulWidget {
  const EventCalendarScreen({super.key, this.initialFocusedDay});

  /// 測試注入點:釘死初始聚焦月份。production 一律 null(=今天)。
  ///
  /// 沒有這個注入,widget 測試會隨真實日期漂移——月曆列數 4~6 列依
  /// 當月而變(2026-08 六列比 07 五列多 52dp),cramped 高度斷言在
  /// 跨月當天無預警翻紅(2026-08-01 實發)。
  final DateTime? initialFocusedDay;

  @override
  ConsumerState<EventCalendarScreen> createState() =>
      _EventCalendarScreenState();
}

/// 桌面左欄固定件（月曆 header＋星期列＋chips＋統計 pills 卡＋間距）
/// 估算高，供動態 rowHeight 反推：(可用高 − 此值) / 當月週數。
const double _wideLeftFixedHeight = 270;

/// 窄佈局非月曆列固定件估算(未來14天卡＋月曆 header/星期列＋chips),
/// 供矮視窗反推動態 rowHeight。實測 625dp 視窗 ~319dp。
/// 正常手機高度((h−320−80)/6 ≥ 52)不受影響。
const double _narrowChromeHeight = 320;

/// 日事件區(清單/空狀態)最低保留高;空狀態 FittedBox 可再縮。
const double _narrowDayBodyMinHeight = 80;

/// 條件式錯誤 banner(MaterialBanner 一行文字+兩鈕)估高——banner 顯示
/// 時必須計入預算,否則「舊資料+重整失敗+矮視窗+6 列月份」四條件齊發
/// 會重現溢位(2026-08-01 複審)。
const double _narrowErrorBannerAllowance = 64;

/// 極矮 fallback(固定件+最小格高都塞不下)整頁轉捲動時,日事件區的
/// 固定高度。
const double _narrowScrollFallbackDayBodyHeight = 240;

/// FAB 迴避間距(FAB 直徑 56+邊距 16+餘裕):清單底部與 chips 列尾端
/// 共用,改 FAB 尺寸/位置時三處同步。
const double _fabClearance = 88;

/// 當月在「週一起算」月曆上實際佔的週列數（4~6）。
///
/// 動態 rowHeight 用 6 週硬除會在 5 週月份少算 ~20%、填不滿留白。
@visibleForTesting
int calendarWeekRows(DateTime month) {
  final first = DateTime(month.year, month.month, 1);
  final offset = first.weekday - DateTime.monday; // 週一=0 … 週日=6
  final days = DateUtils.getDaysInMonth(month.year, month.month);
  return (offset + days + 6) ~/ 7;
}

class _EventCalendarScreenState extends ConsumerState<EventCalendarScreen> {
  late DateTime _focusedDay;
  DateTime? _selectedDay;

  /// 程式化跳月（回今日／date picker）的目標月；非 null 時，不合目標月的
  /// onPageChanged 視為前一個翻頁動畫的**延遲殘響**、忽略——否則殘響會在
  /// setState 之後抵達、把剛設好的 focusedDay 踩回舊月（實測 race）。
  DateTime? _pendingFocusTarget;

  @override
  void initState() {
    super.initState();
    _focusedDay = widget.initialFocusedDay ?? DateTime.now();
    _selectedDay = widget.initialFocusedDay ?? DateTime.now();

    Future.microtask(() => ref.read(eventCalendarProvider.notifier).init());
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(eventCalendarProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text('calendar.title'.tr()),
        actions: [
          // 回今日
          IconButton(
            icon: const Icon(Icons.today),
            tooltip: 'calendar.backToToday'.tr(),
            onPressed: _jumpToToday,
          ),
          // 篩選
          PopupMenuButton<CalendarFilter>(
            icon: const Icon(Icons.filter_list),
            tooltip: 'calendar.filter'.tr(),
            initialValue: state.filter,
            onSelected: (filter) {
              ref.read(eventCalendarProvider.notifier).setFilter(filter);
            },
            itemBuilder: (context) {
              return [
                PopupMenuItem(
                  value: CalendarFilter.all,
                  child: _FilterMenuItem(
                    label: 'calendar.filterAll'.tr(),
                    isSelected: state.filter == CalendarFilter.all,
                  ),
                ),
                PopupMenuItem(
                  value: CalendarFilter.watchlistOnly,
                  child: _FilterMenuItem(
                    label: 'calendar.filterWatchlist'.tr(),
                    isSelected: state.filter == CalendarFilter.watchlistOnly,
                  ),
                ),
                PopupMenuItem(
                  value: CalendarFilter.portfolioOnly,
                  child: _FilterMenuItem(
                    label: 'calendar.filterPortfolio'.tr(),
                    isSelected: state.filter == CalendarFilter.portfolioOnly,
                  ),
                ),
              ];
            },
          ),
          // 同步除權息
          if (state.isSyncing)
            const Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.sync),
              onPressed: _syncDividendEvents,
              tooltip: 'calendar.syncDividendEvents'.tr(),
            ),
        ],
      ),
      // 響應式：≥ tablet 斷點雙欄（月曆左、未來14天＋當日事件右），
      // 空間用起來、不再是置中浮島；窄視窗維持單欄。兩者皆置中限寬。
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= Breakpoints.tablet;
          return isWide
              ? _buildWideBody(theme, state)
              : _buildNarrowBody(theme, state);
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddEvent(),
        child: const Icon(Icons.add),
      ),
    );
  }

  /// 單欄（手機／窄視窗）：未來14天橫向卡 → 月曆＋篩選 → 當日清單
  Widget _buildNarrowBody(ThemeData theme, EventCalendarState state) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: Breakpoints.contentMaxWidth,
        ),
        child: LayoutBuilder(
          builder: (context, cons) {
            // 矮視窗下格高隨當月週數反推收縮(鏡射 wide 佈局的動態
            // rowHeight):固定 52 在 6 列月份比 5 列多 52dp 固定高度,
            // 矮視窗的 Column 無捲動、直接溢位(2026-08-01 跨月實發,
            // 溢 6px)。下限 44 對齊今日圈固定尺寸(44dp 不隨格高縮)。
            final rows = calendarWeekRows(_focusedDay);
            final showBanner = state.error != null && state.events.isNotEmpty;
            final bannerAllowance = showBanner
                ? _narrowErrorBannerAllowance
                : 0.0;
            final fixed =
                _narrowChromeHeight + bannerAllowance + _narrowDayBodyMinHeight;
            final rowHeight = cons.maxHeight.isFinite
                ? ((cons.maxHeight - fixed) / rows).clamp(44.0, 52.0)
                : 52.0;

            final children = <Widget>[
              _buildUpcoming(state, direction: Axis.horizontal),
              _buildCalendarSection(
                theme,
                state,
                isWide: false,
                rowHeight: rowHeight,
              ),
              if (showBanner) _buildErrorBanner(state),
            ];

            // 固定件+最小格高都塞不下(6 列月份+banner+極矮視窗)時,
            // 格高收縮救不回來——整頁轉捲動,日事件區給固定高。
            final minRequired = fixed + rows * 44.0;
            if (cons.maxHeight.isFinite && cons.maxHeight < minRequired) {
              return SingleChildScrollView(
                child: Column(
                  children: [
                    ...children,
                    SizedBox(
                      height: _narrowScrollFallbackDayBodyHeight,
                      child: _buildDayEventsBody(theme, state),
                    ),
                  ],
                ),
              );
            }

            return Column(
              children: [
                ...children,
                Expanded(child: _buildDayEventsBody(theme, state)),
              ],
            );
          },
        ),
      ),
    );
  }

  /// 雙欄（桌面）：左欄月曆＋篩選（flex 3、surface 卡定錨）、右欄
  /// 未來14天＋當日清單（flex 2、單一捲動——避免內層固定高把卡片腰斬）。
  ///
  /// **自適應吃滿視窗**（僅留 16dp 外框）——置中限寬會在超寬視窗留大幅
  /// 死空白（2026-07-24 使用者回饋）。
  Widget _buildWideBody(ThemeData theme, EventCalendarState state) {
    return Column(
      children: [
        if (state.error != null && state.events.isNotEmpty)
          _buildErrorBanner(state),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 3,
                  child: LayoutBuilder(
                    builder: (context, cons) {
                      // 高視窗把月曆格高撐開填滿（Google Calendar 式），
                      // 消掉下方大片留白；矮視窗回落 68 並由外層捲動。
                      // 以當月實際週數（4~6）反推，5 週月份才填得滿。
                      final rows = calendarWeekRows(_focusedDay);
                      // 上限 176：128 在 2560 級大視窗會剩 ~400dp 黑底
                      final rowHeight = cons.maxHeight.isFinite
                          ? ((cons.maxHeight - _wideLeftFixedHeight) / rows)
                                .clamp(68.0, 176.0)
                          : 68.0;
                      return SingleChildScrollView(
                        // surface 卡片包月曆：裸月曆浮在黑底上沒有定錨
                        child: Column(
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surfaceContainerLow,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: _buildCalendarSection(
                                theme,
                                state,
                                isWide: true,
                                rowHeight: rowHeight,
                              ),
                            ),
                            const SizedBox(height: 12),
                            _buildMonthStats(theme, state),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(flex: 2, child: _buildRightPane(theme, state)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// 右欄：未來14天直列＋當日事件。
  ///
  /// 有清單資料時合併為單一 ListView 捲動（避免內層固定高腰斬卡片）；
  /// placeholder 態（載入／空／錯誤）改 Column＋Expanded 給彈性高度，
  /// EmptyStates 的按鈕在固定小盒裡會垂直 overflow。
  Widget _buildRightPane(ThemeData theme, EventCalendarState state) {
    // 空清單不得讓右欄整片虛空（區塊含標題會整個消失，看起來像壞掉）：
    // 保留標題＋空狀態說明＋「查看全市場」捷徑
    final upcomingBlock = state.visibleUpcomingEvents.isEmpty
        ? _buildUpcomingEmptyHint(theme, state)
        : _buildUpcoming(state, direction: Axis.vertical);
    final placeholder = _buildDayEventsPlaceholder(theme, state);
    if (placeholder != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          upcomingBlock,
          const Divider(height: 17),
          Expanded(child: placeholder),
        ],
      );
    }
    return ListView(
      // 底部留 FAB 迴避空間
      padding: const EdgeInsets.only(bottom: _fabClearance),
      children: [
        upcomingBlock,
        const Divider(height: 17),
        for (final event in state.selectedDayEvents)
          EventListTile(
            event: event,
            onTap: () => showEventDetailSheet(
              context,
              event,
              onDelete: event.isAutoGenerated
                  ? null
                  : () => _confirmDelete(event),
            ),
            onDelete: () => _confirmDelete(event),
          ),
      ],
    );
  }

  /// 右欄「未來14天」的空狀態：標題照留、說明原因、給切全市場捷徑
  Widget _buildUpcomingEmptyHint(ThemeData theme, EventCalendarState state) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'calendar.upcomingTitle'.tr(),
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'calendar.noUpcomingWatchlistEvents'.tr(),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
          if (state.filter != CalendarFilter.all) ...[
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => ref
                  .read(eventCalendarProvider.notifier)
                  .setFilter(CalendarFilter.all),
              child: Text('calendar.showAllEvents'.tr()),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildUpcoming(EventCalendarState state, {required Axis direction}) {
    return UpcomingEventsSection(
      events: state.visibleUpcomingEvents,
      direction: direction,
      onEventTap: (event) => _jumpTo(event.eventDate),
    );
  }

  /// 月曆＋分隔線＋類型篩選 chips（單欄／雙欄共用）
  ///
  /// [isWide] 桌面雙欄時格高加高（52→68）、dot 放大——165dp 寬的格子配
  /// 手機格高會扁成表格列。
  Widget _buildCalendarSection(
    ThemeData theme,
    EventCalendarState state, {
    required bool isWide,
    double rowHeight = 52,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TableCalendar<StockEventEntry>(
          firstDay: DateTime(2000),
          lastDay: DateTime(2100),
          focusedDay: _focusedDay,
          selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
          calendarFormat: state.calendarFormat,
          rowHeight: rowHeight,
          daysOfWeekHeight: isWide ? 24 : 16,
          onHeaderTapped: (_) => _pickMonth(),
          // 取代套件英文預設（'Month'/'2 weeks'/'Week'）；按鈕顯示的是
          // 「下一個」格式的 label（formatButtonShowsNext 預設 true）。
          availableCalendarFormats: {
            CalendarFormat.month: 'calendar.formatMonth'.tr(),
            CalendarFormat.twoWeeks: 'calendar.formatTwoWeeks'.tr(),
            CalendarFormat.week: 'calendar.formatWeek'.tr(),
          },
          startingDayOfWeek: StartingDayOfWeek.monday,
          eventLoader: (day) {
            final dateKey = DateContext.normalize(day);
            return state.filteredEvents[dateKey] ?? [];
          },
          onDaySelected: (selectedDay, focusedDay) {
            setState(() {
              _selectedDay = selectedDay;
              _focusedDay = focusedDay;
            });
            ref.read(eventCalendarProvider.notifier).selectDate(selectedDay);
          },
          onFormatChanged: (format) {
            ref.read(eventCalendarProvider.notifier).setCalendarFormat(format);
          },
          onPageChanged: (focusedDay) {
            final target = _pendingFocusTarget;
            if (target != null) {
              final arrived =
                  focusedDay.year == target.year &&
                  focusedDay.month == target.month;
              if (!arrived) return; // 前一個翻頁動畫的延遲殘響，忽略
              _pendingFocusTarget = null;
            }
            // 必須 setState：裸賦值會讓 widget 的 focusedDay 參數停在舊值，
            // 程式化跳月與套件內部 page 狀態會不一致（2026-07-24 實測）
            setState(() => _focusedDay = focusedDay);
            ref
                .read(eventCalendarProvider.notifier)
                .loadMonthEvents(DateTime(focusedDay.year, focusedDay.month));
          },
          calendarBuilders: CalendarBuilders(
            markerBuilder: (context, date, events) {
              if (events.isEmpty) return null;
              return _buildEventMarkers(context, events, isWide: isWide);
            },
            // 固定 44dp 圈：預設 decoration 會隨 rowHeight 等比放大成
            // 氣球（格高 128 時圈徑近 100）
            selectedBuilder: (context, day, _) => _buildDayCircle(
              day,
              key: const ValueKey('selectedDayCircle'),
              background: theme.colorScheme.primary,
              foreground: theme.colorScheme.onPrimary,
            ),
            todayBuilder: (context, day, _) => _buildDayCircle(
              day,
              key: const ValueKey('todayCircle'),
              background: theme.colorScheme.primaryContainer,
              foreground: theme.colorScheme.onPrimaryContainer,
            ),
          ),
          headerStyle: HeaderStyle(
            formatButtonVisible: true,
            titleCentered: true,
            titleTextFormatter: (date, locale) =>
                DateFormat.yMMMM(locale).format(date),
          ),
          // today/selected 外觀由上方 builders 接管（固定 44dp 圈）
          calendarStyle: const CalendarStyle(outsideDaysVisible: false),
        ),
        const Divider(height: 1),
        _buildEventTypeFilterChips(state, fabClearance: !isWide),
      ],
    );
  }

  /// Refresh 失敗但有舊資料時的 MaterialBanner
  Widget _buildErrorBanner(EventCalendarState state) {
    return MaterialBanner(
      content: Text(state.error!),
      actions: [
        TextButton(
          onPressed: () {
            if (state.focusedMonth != null) {
              ref
                  .read(eventCalendarProvider.notifier)
                  .loadMonthEvents(state.focusedMonth!);
            }
          },
          child: Text('common.retry'.tr()),
        ),
        TextButton(
          onPressed: () =>
              ref.read(eventCalendarProvider.notifier).clearError(),
          child: Text('common.dismiss'.tr()),
        ),
      ],
    );
  }

  /// 錯誤／載入／空三態 placeholder；有清單資料時回 null
  Widget? _buildDayEventsPlaceholder(
    ThemeData theme,
    EventCalendarState state,
  ) {
    if (state.error != null && state.events.isEmpty) {
      return ErrorDisplay.isNetworkError(state.error!)
          ? EmptyStates.networkError(
              onRetry: () {
                if (state.focusedMonth != null) {
                  ref
                      .read(eventCalendarProvider.notifier)
                      .loadMonthEvents(state.focusedMonth!);
                }
              },
            )
          : EmptyStates.error(
              message: state.error!,
              onRetry: () {
                if (state.focusedMonth != null) {
                  ref
                      .read(eventCalendarProvider.notifier)
                      .loadMonthEvents(state.focusedMonth!);
                }
              },
            );
    }
    if (state.isLoading) {
      return const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (state.selectedDayEvents.isEmpty) {
      return Center(
        // scaleDown：矮視窗下 Expanded 可能只剩 ~80dp，icon48+文字會
        // 垂直溢位（2026-07-24 實機紅條）；FittedBox 只在不夠時縮小
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.event_busy,
                size: 48,
                color: theme.colorScheme.outline.withValues(alpha: 0.5),
              ),
              const SizedBox(height: 8),
              Text(
                'calendar.noEvents'.tr(),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return null;
  }

  /// 選取日期的事件列表（單欄用；placeholder 態或自捲清單）
  Widget _buildDayEventsBody(ThemeData theme, EventCalendarState state) {
    return _buildDayEventsPlaceholder(theme, state) ??
        ListView.builder(
          // 底部留 FAB 迴避空間，最後一張卡不被 + 鈕壓住
          padding: const EdgeInsets.only(top: 8, bottom: _fabClearance),
          itemCount: state.selectedDayEvents.length,
          itemBuilder: (context, index) {
            final event = state.selectedDayEvents[index];
            return EventListTile(
              event: event,
              onTap: () => showEventDetailSheet(
                context,
                event,
                onDelete: event.isAutoGenerated
                    ? null
                    : () => _confirmDelete(event),
              ),
              onDelete: () => _confirmDelete(event),
            );
          },
        );
  }

  /// [fabClearance] 窄版短視窗下 FAB 會壓住列尾最後一顆 chip，留 [_fabClearance]
  /// 尾距讓它能捲出來；寬版 chips 在左欄、離 FAB 遠，不加（避免置中偏移）
  Widget _buildEventTypeFilterChips(
    EventCalendarState state, {
    bool fabClearance = false,
  }) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: EdgeInsets.only(
        left: 12,
        top: 6,
        bottom: 6,
        right: fabClearance ? _fabClearance : 12,
      ),
      child: Row(
        children: EventType.values.map((type) {
          final selected = state.selectedEventTypes.contains(type);
          return Padding(
            padding: const EdgeInsets.only(right: 6),
            child: FilterChip(
              label: Text(type.i18nKey.tr()),
              selected: selected,
              onSelected: (_) {
                ref.read(eventCalendarProvider.notifier).toggleEventType(type);
              },
              // 兩態皆中性、類型色只留 8px 色點：預設五類全選時，著色
              // label/avatar 會讓整排恆常呈彩虹（2026-07-24 使用者回饋）。
              // 選中與否由底色＋勾勾表達。
              selectedColor: theme.colorScheme.surfaceContainerHighest,
              checkmarkColor: theme.colorScheme.onSurface,
              avatar: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: type.colorFor(brightness),
                  shape: BoxShape.circle,
                ),
              ),
              labelStyle: const TextStyle(fontSize: 12),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildEventMarkers(
    BuildContext context,
    List<StockEventEntry> events, {
    bool isWide = false,
  }) {
    final brightness = Theme.of(context).brightness;
    final dotSize = isWide ? 8.0 : 6.0;
    // 取不重複的事件類型，按 enum 順序排列（最多顯示 3 個 dot）
    final types =
        events.map((e) => EventType.fromValue(e.eventType)).toSet().toList()
          ..sort((a, b) => a.index.compareTo(b.index));
    final displayTypes = types.take(3).toList();

    return Positioned(
      bottom: 1,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: displayTypes.map((type) {
          return Container(
            width: dotSize,
            height: dotSize,
            margin: const EdgeInsets.symmetric(horizontal: 1),
            decoration: BoxDecoration(
              color: type.colorFor(brightness),
              shape: BoxShape.circle,
            ),
          );
        }).toList(),
      ),
    );
  }

  /// 今日／選中日的固定尺寸圓圈（44dp，不隨 rowHeight 膨脹）
  Widget _buildDayCircle(
    DateTime day, {
    required Key key,
    required Color background,
    required Color foreground,
  }) {
    return Center(
      child: Container(
        key: key,
        width: 44,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: background, shape: BoxShape.circle),
        child: Text(
          '${day.day}',
          style: TextStyle(color: foreground, fontSize: 16),
        ),
      ),
    );
  }

  /// 程式化跳月的唯一入口(回今日/date picker/未來14天卡片)。
  ///
  /// 三件事缺一不可:_pendingFocusTarget 濾掉翻頁動畫殘響(見欄位註解,
  /// 2026-08-01 複審:第三入口漏設,殘響把目標月踩回舊月)、setState 讓
  /// widget 參數跟上、provider 端選日+載月。新增第四個跳月入口一律走
  /// 這裡,不要散裝複製。
  void _jumpTo(DateTime target) {
    _pendingFocusTarget = target;
    setState(() {
      _selectedDay = target;
      _focusedDay = target;
    });
    ref.read(eventCalendarProvider.notifier).selectDate(target);
    ref
        .read(eventCalendarProvider.notifier)
        .loadMonthEvents(DateTime(target.year, target.month));
  }

  /// 跳回今天（focus＋選取＋載入當月）
  void _jumpToToday() => _jumpTo(DateTime.now());

  /// 點月曆標題開 date picker 跳月
  Future<void> _pickMonth() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _focusedDay,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) return;
    _jumpTo(picked);
  }

  /// 本月事件統計卡（桌面左欄）——各類型 count、點列切換該類型篩選。
  /// 統計基於當月**全部**事件（state.events 未過濾），與 chips 篩選狀態
  /// 無關；被篩掉的類型以降透明度提示。
  Widget _buildMonthStats(ThemeData theme, EventCalendarState state) {
    final counts = <EventType, int>{};
    for (final entry in state.events.entries) {
      if (entry.key.year != _focusedDay.year ||
          entry.key.month != _focusedDay.month) {
        continue;
      }
      for (final e in entry.value) {
        final t = EventType.fromValue(e.eventType);
        counts[t] = (counts[t] ?? 0) + 1;
      }
    }
    final brightness = theme.brightness;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'calendar.monthStats'.tr(),
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          // 橫向 pills：整寬直列會讓 label 與數字相距上千 dp、掃視困難；
          // 0 場次或被篩掉的類型降透明度
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final type in EventType.values)
                InkWell(
                  key: ValueKey('monthStat_${type.name}'),
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => ref
                      .read(eventCalendarProvider.notifier)
                      .toggleEventType(type),
                  child: Opacity(
                    opacity:
                        (state.selectedEventTypes.contains(type) &&
                            (counts[type] ?? 0) > 0)
                        ? 1
                        : 0.4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: type.colorFor(brightness),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            type.i18nKey.tr(),
                            style: theme.textTheme.bodySmall,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '${counts[type] ?? 0}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  void _showAddEvent() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: Breakpoints.sheetMaxWidth),
      builder: (context) => AddEventSheet(initialDate: _selectedDay),
    );
  }

  Future<void> _confirmDelete(StockEventEntry event) async {
    if (event.isAutoGenerated) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('calendar.deleteEvent'.tr()),
        content: Text('calendar.deleteConfirm'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(MaterialLocalizations.of(ctx).okButtonLabel),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        await ref.read(eventCalendarProvider.notifier).deleteEvent(event.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('calendar.eventDeleted'.tr()),
              behavior: SnackBarBehavior.floating,
              action: SnackBarAction(
                label: 'common.undo'.tr(),
                onPressed: () async {
                  try {
                    await ref
                        .read(eventCalendarProvider.notifier)
                        .addEvent(
                          symbol: event.symbol,
                          eventDate: event.eventDate,
                          title: event.title,
                          description: event.description,
                        );
                  } catch (_) {
                    // 還原失敗靜默處理（事件已刪除，重新建立可能失敗）
                  }
                },
              ),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(ErrorDisplay.message(e)),
              behavior: SnackBarBehavior.floating,
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
      }
    }
  }

  Future<void> _syncDividendEvents() async {
    try {
      final notifier = ref.read(eventCalendarProvider.notifier);
      final result = await notifier.syncDividendEvents();
      if (mounted) {
        // syncDividendEvents 不 throw reload 失敗，但會設定 state.error
        final reloadError = ref.read(eventCalendarProvider).error;
        var message = 'calendar.syncDetailComplete'.tr(
          namedArgs: {
            'exDividend': '${result.exDividend}',
            'exRights': '${result.exRights}',
          },
        );
        // 靜默稽核 #8:附帶來源失敗要說出來——這顆按鈕是停券預告/法說會/
        // 處置出關唯一的同步入口,半殘不得報成功
        if (result.failedSources.isNotEmpty) {
          final names = result.failedSources
              .map((k) => 'calendar.source.$k'.tr())
              .join('calendar.sourceSeparator'.tr());
          message =
              '$message;${'calendar.syncPartialFail'.tr(namedArgs: {'sources': names})}';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              reloadError != null ? '$message（$reloadError）' : message,
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ErrorDisplay.message(e)),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }
}

class _FilterMenuItem extends StatelessWidget {
  const _FilterMenuItem({required this.label, required this.isSelected});

  final String label;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (isSelected)
          const Icon(Icons.check, size: 18)
        else
          const SizedBox(width: 18),
        const SizedBox(width: 8),
        Text(label),
      ],
    );
  }
}
