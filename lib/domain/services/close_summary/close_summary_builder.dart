/// 把讀好的資料組成收盤摘要：每檔套 v3 條件、依分組角色決定標哪些事件、
/// 排區段與順序。純函式，不讀資料庫、不讀時鐘（現在時間由輸入帶進來）。
library;

import 'package:daredevil/core/constants/close_summary_params.dart';
import 'package:daredevil/core/constants/data_freshness.dart';
import 'package:daredevil/core/constants/industry_names.dart';
import 'package:daredevil/core/utils/date_context.dart';
import 'package:daredevil/core/utils/taiwan_calendar.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/data/database/dao/user_dao.dart';
import 'package:daredevil/domain/models/close_summary.dart';
import 'package:daredevil/domain/services/close_summary/chip_checks.dart';
import 'package:daredevil/domain/services/close_summary/holding_checks.dart';
import 'package:daredevil/domain/services/close_summary/price_checks.dart';
import 'package:daredevil/domain/services/close_summary/throttle.dart';
import 'package:daredevil/domain/services/price_calculator.dart';
import 'package:daredevil/domain/services/price_continuity.dart';
import 'package:daredevil/domain/services/revenue_stats.dart';

CloseSummary buildCloseSummary(CloseSummaryInput input) {
  final dataDate = DateContext.normalize(input.dataDate);
  final groupIds = {for (final g in input.groups) g.id};
  // 有分組卻沒有「強者榜」才算找不到；一個分組都沒有的人不必提示
  final strongListGroupMissing =
      input.groups.isNotEmpty &&
      !input.groups.any(
        (g) => g.name == CloseSummaryParams.strongListGroupName,
      );
  final watchBySymbol = {for (final w in input.watchlist) w.entry.symbol: w};
  final holdings = {
    for (final p in input.positions)
      if (p.quantity > 0) p.symbol: p,
  };

  final drafts = <String, _Draft>{
    for (final symbol in {...holdings.keys, ...watchBySymbol.keys})
      symbol: _evaluate(
        symbol: symbol,
        input: input,
        dataDate: dataDate,
        watch: watchBySymbol[symbol],
        groupIds: groupIds,
        position: holdings[symbol],
        strongListGroupMissing: strongListGroupMissing,
      ),
  };
  _markSectorCooling(drafts.values);

  CloseSummaryRow rowOf(String symbol) => drafts[symbol]!.toRow();

  final sections = <CloseSummarySection>[
    CloseSummarySection(
      isHoldings: true,
      groupId: null,
      groupName: null,
      rows: [for (final s in holdings.keys) rowOf(s)],
    ),
    for (final g in input.groups)
      CloseSummarySection(
        isHoldings: false,
        groupId: g.id,
        groupName: g.name,
        rows: [
          for (final d in drafts.values)
            if (!d.isHolding && d.groupId == g.id) d.toRow(),
        ],
      ),
    CloseSummarySection(
      isHoldings: false,
      groupId: null,
      groupName: null,
      rows: [
        for (final d in drafts.values)
          if (!d.isHolding && d.groupId == null) d.toRow(),
      ],
    ),
  ];
  for (final section in sections) {
    section.rows.sort(_compareRows);
  }

  final indexReady =
      input.taiex.isNotEmpty &&
      DateContext.isSameDay(input.taiex.last.date, dataDate);

  return CloseSummary(
    dataDate: dataDate,
    pricePendingMarkets: {
      for (final e in input.priceReadyByMarket.entries)
        if (!e.value) e.key,
    },
    institutionalPendingMarkets: {
      for (final e in input.institutionalReadyByMarket.entries)
        if (!e.value) e.key,
    },
    indexReady: indexReady,
    throttle: indexReady ? readThrottle(input.taiex) : null,
    strongListGroupMissing: strongListGroupMissing,
    sections: [
      for (final s in sections)
        if (s.rows.isNotEmpty) s,
    ],
  );
}

/// 頁首的資料時間狀態，兩者互斥。[now] 為台灣時間。
///
/// - awaitingToday：今天是交易日、還沒到每日資料就緒的時刻、資料日是預期的
///   上一個交易日（今天的資料還沒到是正常的）
/// - dataBehind：資料日早於預期的最新交易日（每日更新落後）
///
/// 畫面每次 build 用當下時鐘重算：摘要算好之後，時間過了就緒時刻而資料沒有
/// 更新時，頁首要從「等今天」變成「落後」。
({bool awaitingToday, bool dataBehind}) closeSummaryTimeFlags({
  required DateTime dataDate,
  required DateTime now,
}) {
  final date = DateContext.normalize(dataDate);
  final today = DateTime(now.year, now.month, now.day);
  final expected = DateContext.normalize(
    TaiwanCalendar.expectedLatestTradingDataDate(now),
  );
  return (
    awaitingToday:
        TaiwanCalendar.isTradingDay(today) &&
        now.hour < DataFreshness.dailyDataReadyHour &&
        DateContext.isSameDay(date, expected),
    dataBehind: date.isBefore(expected),
  );
}

/// 有待處理的在前，再依漲幅由高到低（沒有漲幅的最後），再依代號
int _compareRows(CloseSummaryRow a, CloseSummaryRow b) {
  if (a.hasActionable != b.hasActionable) return a.hasActionable ? -1 : 1;
  final ca = a.changePct;
  final cb = b.changePct;
  if (ca != cb) {
    if (ca == null) return 1;
    if (cb == null) return -1;
    return cb.compareTo(ca);
  }
  return a.symbol.compareTo(b.symbol);
}

GroupRole _roleOf(String? groupName) => switch (groupName) {
  CloseSummaryParams.strongListGroupName => GroupRole.strongList,
  CloseSummaryParams.delistReviewGroupName => GroupRole.delistReview,
  CloseSummaryParams.thermometerGroupName => GroupRole.thermometer,
  _ => GroupRole.other,
};

_Draft _evaluate({
  required String symbol,
  required CloseSummaryInput input,
  required DateTime dataDate,
  required WatchlistWithGroup? watch,
  required Set<int> groupIds,
  required PortfolioPositionEntry? position,
  required bool strongListGroupMissing,
}) {
  final rawGroupId = watch?.entry.groupId;
  final groupId = rawGroupId != null && groupIds.contains(rawGroupId)
      ? rawGroupId
      : null;
  final groupName = groupId == null ? null : watch?.groupName;
  final role = _roleOf(groupName);
  final stock = input.stocks[symbol];
  final market = stock?.market ?? '';
  final draft = _Draft(
    symbol: symbol,
    name: stock?.name ?? symbol,
    market: market,
    industry: stock?.industry,
    groupId: groupId,
    groupName: groupName,
    role: role,
    inWatchlist: watch != null,
    isHolding: position != null,
  );

  // 先去掉資料日以後的日線再切斷點：資料日之後的跳空不該切掉資料日以前的資料
  final upToDataDate = [
    for (final b in input.prices[symbol] ?? const <DailyPriceEntry>[])
      if (!DateContext.normalize(b.date).isAfter(dataDate)) b,
  ];
  final bars = [
    for (final b in upToDataDate.contiguousSuffix())
      if (b.close != null) b,
  ];
  if (!(input.priceReadyByMarket[market] ?? true)) {
    draft.status = RowDataStatus.marketPending;
    return draft;
  }
  if (bars.isEmpty || !DateContext.isSameDay(bars.last.date, dataDate)) {
    draft.status = RowDataStatus.noTrade;
    return draft;
  }

  final changePct = PriceCalculator.calculatePriceChange(bars, bars.last);
  final strongList = checkStrongList(bars);
  final revenueYoy3m = yoy3mAvg([
    for (final r in input.revenues[symbol] ?? const <MonthlyRevenueEntry>[])
      (year: r.revenueYear, month: r.revenueMonth, yoy: r.yoyGrowth),
  ]);
  final prerequisites = checkEntryPrerequisites(
    bars,
    revenueYoy3m: revenueYoy3m,
  );
  final chip = checkChip(
    institutional: input.institutional[symbol] ?? const [],
    bars: bars,
    institutionalReady: input.institutionalReadyByMarket[market] ?? true,
  );
  final holding = position == null
      ? null
      : checkHolding(
          position: position,
          transactions: input.transactions[symbol] ?? const [],
          bars: bars,
        );

  draft
    ..close = bars.last.close
    ..changePct = changePct
    ..volumeShares = bars.last.volume
    ..biasPct = prerequisites.biasPct
    ..strongList = strongList
    ..prerequisites = prerequisites
    ..chip = chip
    ..holding = holding
    ..crossedBelowMa = crossedBelowMa(bars);

  final events = draft.events;
  if (holding != null) {
    if (holding.stopBroken) {
      events.add(const SummaryEvent(SummaryEventKind.stopBroken));
    }
    if (holding.timeStop == TimeStopState.expired) {
      events.add(const SummaryEvent(SummaryEventKind.timeStopExpired));
    }
  }

  if (role == GroupRole.thermometer) {
    final streak = maSideStreak(bars);
    draft
      ..thermometerStreak = streak
      ..thermometerStreakAtLeast =
          streak != 0 &&
          streak.abs() == bars.length - (CloseSummaryParams.maPeriod - 1);
    return draft;
  }

  if (role == GroupRole.strongList) {
    final streak = maSideStreak(bars);
    if (streak <= -CloseSummaryParams.demotionBelowMaDays) {
      events.add(SummaryEvent(SummaryEventKind.belowMaStreak, days: -streak));
    }
  }

  if (role != GroupRole.strongList &&
      !strongListGroupMissing &&
      strongList.allPassed) {
    events.add(const SummaryEvent(SummaryEventKind.strongListQualified));
  }

  // 除名重審不標進場這一側的事件（v3 的掃描排除這組）
  if (role != GroupRole.delistReview) {
    final support = structureBSupport(bars);
    final breakout = structureC(bars);
    final triggered = support != null || breakout;
    final downgraded =
        triggered &&
        changePct != null &&
        changePct <= CloseSummaryParams.triggerDayDowngradePct;
    if (downgraded) {
      events.add(const SummaryEvent(SummaryEventKind.triggerDowngrade));
    } else {
      if (breakout) {
        events.add(const SummaryEvent(SummaryEventKind.structureC));
      }
      if (support != null) {
        events.add(
          SummaryEvent(SummaryEventKind.structureB, supportPeriod: support),
        );
      }
    }
    final priceSeal = triggered && !downgraded;
    if (priceSeal &&
        chip != null &&
        chip.sealed &&
        !chip.opposed &&
        prerequisites.allPassed) {
      events.add(const SummaryEvent(SummaryEventKind.dualSeal));
    }
  }

  final limit = closeLimitStatus(bars, bars.length - 1);
  if (limit.isUp) {
    events.add(const SummaryEvent(SummaryEventKind.limitUp));
    if (chip != null && chip.foreignNetShares < 0) {
      events.add(const SummaryEvent(SummaryEventKind.limitUpForeignSelling));
    }
  }
  if (limit.isDown) {
    events.add(const SummaryEvent(SummaryEventKind.limitDown));
  }
  return draft;
}

/// 族群退燒：在自選裡、不是溫度計、資料正常的列，同產業在資料日由月線上
/// 跌到月線下的達到門檻檔數，這幾檔都標
void _markSectorCooling(Iterable<_Draft> drafts) {
  final byIndustry = <String, List<_Draft>>{};
  for (final d in drafts) {
    final industry = d.industry;
    if (!d.inWatchlist ||
        d.role == GroupRole.thermometer ||
        d.status != RowDataStatus.ok ||
        industry == null ||
        !d.crossedBelowMa) {
      continue;
    }
    byIndustry.putIfAbsent(IndustryNames.normalize(industry), () => []).add(d);
  }
  for (final entry in byIndustry.entries) {
    if (entry.value.length < CloseSummaryParams.sectorCoolingMinStocks) {
      continue;
    }
    for (final d in entry.value) {
      d.events.add(
        SummaryEvent(SummaryEventKind.sectorCooling, industry: entry.key),
      );
    }
  }
}

/// 組裝途中的一列：事件要等全部算完（族群退燒跨列）才定案
class _Draft {
  _Draft({
    required this.symbol,
    required this.name,
    required this.market,
    required this.industry,
    required this.groupId,
    required this.groupName,
    required this.role,
    required this.inWatchlist,
    required this.isHolding,
  });

  final String symbol;
  final String name;
  final String market;
  final String? industry;
  final int? groupId;
  final String? groupName;
  final GroupRole role;
  final bool inWatchlist;
  final bool isHolding;

  RowDataStatus status = RowDataStatus.ok;
  double? close;
  double? changePct;
  double? volumeShares;
  double? biasPct;
  StrongListCheck? strongList;
  EntryPrerequisites? prerequisites;
  ChipCheck? chip;
  HoldingCheck? holding;
  int? thermometerStreak;
  bool thermometerStreakAtLeast = false;
  bool crossedBelowMa = false;
  final List<SummaryEvent> events = [];

  CloseSummaryRow toRow() => CloseSummaryRow(
    symbol: symbol,
    name: name,
    market: market,
    groupId: groupId,
    groupName: groupName,
    role: role,
    status: status,
    close: close,
    changePct: changePct,
    volumeShares: volumeShares,
    biasPct: biasPct,
    strongList: strongList,
    prerequisites: prerequisites,
    chip: chip,
    holding: holding,
    thermometerStreak: thermometerStreak,
    thermometerStreakAtLeast: thermometerStreakAtLeast,
    events: [...events]..sort((a, b) => a.kind.index.compareTo(b.kind.index)),
  );
}
