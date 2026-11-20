/// 收盤摘要的資料模型（設計見 `docs/plans/2026-11-20-close-summary-design.md`）
library;

import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/data/database/dao/user_dao.dart';
import 'package:daredevil/domain/services/close_summary/chip_checks.dart';
import 'package:daredevil/domain/services/close_summary/holding_checks.dart';
import 'package:daredevil/domain/services/close_summary/price_checks.dart';
import 'package:daredevil/domain/services/close_summary/throttle.dart';

/// 事件種類。待處理在前、資訊在後，同一列的事件照這個順序排。
enum SummaryEventKind {
  // 待處理：會讓使用者明天做點什麼的
  stopBroken,
  timeStopExpired,
  belowMaStreak,
  strongListQualified,
  dualSeal,
  structureB,
  structureC,
  triggerDowngrade,
  sectorCooling,

  // 資訊：只顯示，不排序、不計數
  limitUp,
  limitDown,
  limitUpForeignSelling;

  bool get isActionable => index <= sectorCooling.index;
}

/// 一個事件
class SummaryEvent {
  const SummaryEvent(this.kind, {this.days, this.supportPeriod, this.industry});

  final SummaryEventKind kind;

  /// [SummaryEventKind.belowMaStreak] 的連續天數
  final int? days;

  /// [SummaryEventKind.structureB] 的支撐均線週期
  final int? supportPeriod;

  /// [SummaryEventKind.sectorCooling] 的產業（正規化後的名稱）
  final String? industry;
}

/// 分組在 v3 裡的角色，以分組名稱辨認
enum GroupRole { strongList, delistReview, thermometer, other }

/// 一列的資料狀態
enum RowDataStatus {
  ok,

  /// 該股所屬市場在資料日還沒有價格寫入
  marketPending,

  /// 市場已有資料日的價格，這檔沒有（停牌、處置等）
  noTrade,
}

/// 摘要的一列（一檔股票）
class CloseSummaryRow {
  const CloseSummaryRow({
    required this.symbol,
    required this.name,
    required this.market,
    required this.groupId,
    required this.groupName,
    required this.role,
    required this.status,
    this.close,
    this.changePct,
    this.volumeShares,
    this.biasPct,
    this.strongList,
    this.prerequisites,
    this.chip,
    this.holding,
    this.thermometerStreak,
    this.thermometerStreakAtLeast = false,
    this.events = const [],
  });

  final String symbol;
  final String name;
  final String market;

  /// 所在的自選分組；不在自選或未分組為 null
  final int? groupId;
  final String? groupName;
  final GroupRole role;

  /// 不是 [RowDataStatus.ok] 時，以下數值全為 null、[events] 為空
  final RowDataStatus status;

  final double? close;
  final double? changePct;
  final double? volumeShares;
  final double? biasPct;
  final StrongListCheck? strongList;
  final EntryPrerequisites? prerequisites;

  /// null：該市場法人未到（或列的狀態不是 ok）
  final ChipCheck? chip;

  /// 持股；不是持股、或持股算不出來時為 null
  final HoldingCheck? holding;

  /// 只有大盤溫度計的列有：連續收在 20 日均線之上（正）或之下（負）的天數
  final int? thermometerStreak;

  /// 讀到的日線每天都在同一側、數到頭了，實際天數可能更多（畫面寫「至少」）
  final bool thermometerStreakAtLeast;

  /// 待處理在前
  final List<SummaryEvent> events;

  bool get hasActionable => events.any((e) => e.kind.isActionable);
}

/// 一個區段：持股，或一個自選分組，或未分組
class CloseSummarySection {
  const CloseSummarySection({
    required this.isHoldings,
    required this.groupId,
    required this.groupName,
    required this.rows,
  });

  final bool isHoldings;

  /// 分組 id；持股段與未分組為 null
  final int? groupId;
  final String? groupName;
  final List<CloseSummaryRow> rows;

  bool get isUngrouped => !isHoldings && groupId == null;
}

/// 整份收盤摘要
class CloseSummary {
  const CloseSummary({
    required this.dataDate,
    required this.pricePendingMarkets,
    required this.institutionalPendingMarkets,
    required this.indexReady,
    required this.throttle,
    required this.strongListGroupMissing,
    required this.sections,
  });

  final DateTime dataDate;

  /// 資料日還沒有價格的市場（`MarketCode`）
  final Set<String> pricePendingMarkets;

  /// 資料日還沒有法人的市場（`MarketCode`）
  final Set<String> institutionalPendingMarkets;

  /// 加權指數最後一筆是資料日
  final bool indexReady;

  /// [indexReady] 為 false、或加權指數不足 21 筆時為 null
  final ThrottleReading? throttle;

  /// 有分組、但沒有名稱為「強者榜」的分組
  final bool strongListGroupMissing;

  final List<CloseSummarySection> sections;

  int get holdingCount => sections
      .where((s) => s.isHoldings)
      .fold(0, (sum, s) => sum + s.rows.length);

  /// 有待處理事件的不重複檔數
  int get actionableStockCount => {
    for (final section in sections)
      for (final row in section.rows)
        if (row.hasActionable) row.symbol,
  }.length;
}

/// 組裝摘要需要的全部資料（由 loader 從資料庫讀出）
class CloseSummaryInput {
  const CloseSummaryInput({
    required this.dataDate,
    required this.now,
    required this.priceReadyByMarket,
    required this.institutionalReadyByMarket,
    required this.taiex,
    required this.watchlist,
    required this.groups,
    required this.positions,
    required this.transactions,
    required this.stocks,
    required this.prices,
    required this.institutional,
    required this.revenues,
  });

  final DateTime dataDate;

  /// 台灣時間（`AppClock` 的 `SystemClock` 回傳 `TaiwanTime.now()`）
  final DateTime now;

  /// `MarketCode` → 資料日是否已有價格
  final Map<String, bool> priceReadyByMarket;

  /// `MarketCode` → 資料日是否已有法人
  final Map<String, bool> institutionalReadyByMarket;

  /// 加權指數，升冪
  final List<MarketIndexEntry> taiex;

  final List<WatchlistWithGroup> watchlist;

  /// 依使用者排序的分組
  final List<WatchlistGroupEntry> groups;

  final List<PortfolioPositionEntry> positions;
  final Map<String, List<PortfolioTransactionEntry>> transactions;
  final Map<String, StockMasterEntry> stocks;

  /// 原始日線，升冪、未處理斷點
  final Map<String, List<DailyPriceEntry>> prices;
  final Map<String, List<DailyInstitutionalEntry>> institutional;
  final Map<String, List<MonthlyRevenueEntry>> revenues;
}
