/// 族群排行資料模型（今日頁族群 section 顯示用）
library;

/// 排行的動能視窗：20日＝輪動主視角、5日＝轉折視角
///
/// 2026-07-22 使用者實機回饋：電子族群 20日修正墊底、反彈第一天完全
/// 進不了前八——5日視窗讓「20日弱但正在翻強」的轉折族群被看到。
/// 排行視窗。d1(今日)於 2026-08-13 加入——原今日頁「產業表現」區塊
/// (當日·等權·分市場)與本排行(多窗·中位數·合併市場)口徑互撞:上櫃
/// 金融同屏出現 +4.37% 與 −1.3%,不看小字像壞掉。合併後全部走同一條
/// 中位數管線,只差視窗長度。
enum RankingWindow {
  d20,
  d5,
  d1;

  /// 該視窗需要的最少收盤筆數(最新一筆+視窗長度)。
  ///
  /// 供大盤同窗報酬取「第 [minHistoryRows] 筆前」的收盤——差一格會讓
  /// 超額值系統性偏移,故獨立成可測的映射(2026-08-13 審查)。
  int get minHistoryRows => switch (this) {
    RankingWindow.d20 => 21,
    RankingWindow.d5 => 6,
    RankingWindow.d1 => 2,
  };
}

/// 「轉向」的分類——**排名躍升本身不足以判斷該不該進場**。
///
/// 2026-08-10 實測:半導體 20日排第 34(−13.6%)、5日排第 1(+7.2%),
/// 躍升 +33 名居冠。但那是**跌深反彈**,不是新的主流——它的成員多半過不了
/// v3.4 強者榜的「月漲 >+15%」(那是 20 日尺度)。
///
/// 兩者對應 v3.4 的兩個結構,進場邏輯完全不同:
/// - [reboundFromDeep] → 結構 A(崩後超跌股,要三件套確認)
/// - [sustained]       → 結構 B(強勢回測,可直接套強者榜)
///
/// 混為一談會讓使用者拿結構 B 的規則去買結構 A 的標的。
enum RotationCategory {
  /// 兩個窗口都排前段——真正的主流
  sustained,

  /// 5日前段但 20日後段——跌深反彈
  reboundFromDeep,

  /// 20日前段但 5日後段——退燒
  cooling,

  /// 其餘
  neutral,
}

/// 單一產業的轉向資料
class IndustryRotation {
  const IndustryRotation({
    required this.industry,
    required this.memberCount,
    required this.rankJump,
    required this.rank5d,
    required this.rank20d,
    required this.ret5dPct,
    required this.ret20dPct,
    required this.category,
    required this.strongListCount,
    required this.topMembers,
    required this.strongListSymbols,
  });

  final String industry;
  final int memberCount;

  /// 20日名次 − 5日名次。正 = 正在往上竄,負 = 正在退場。
  final int rankJump;

  final int rank5d;
  final int rank20d;

  /// 各窗口的成員報酬中位數(%),與 [IndustryRanking.momentumPct] 同口徑
  final double ret5dPct;
  final double ret20dPct;

  final RotationCategory category;

  /// 成員中通過 v3.4 強者榜「月漲 >+15% ＋ 日均量 >3,000 張」的檔數。
  ///
  /// UI 用它決定卡片要不要淡化:**0 檔代表點進去也沒東西可買**,
  /// 躍升再多都是死路。刻意不在服務層過濾掉——躍升本身仍是市場資訊。
  final int strongListCount;

  /// 領先成員,依 **20 日報酬** DESC(不是 5 日)。
  ///
  /// 刻意用 20 日:使用者點進來是要**找可買的標的**,而 v3.4 強者榜的
  /// 「月漲 >+15%」是 20 日尺度。用 5 日排序會把「昨天剛彈起來但月線仍弱」
  /// 的排在前面,那正是規則不會放行的。
  final List<IndustryMember> topMembers;

  /// [topMembers] 中通過強者榜四條件的代號,供 UI 標記。
  final Set<String> strongListSymbols;
}

/// 產業內的領漲成員
class IndustryMember {
  const IndustryMember({
    required this.symbol,
    required this.name,
    required this.retPct,
  });

  final String symbol;

  /// 股票名稱；stock_master 查無時為空字串（UI 以 symbol 呈現）
  final String name;

  /// 選定視窗（[RankingWindow]）的報酬（%）
  final double retPct;
}

/// 單一產業的排行項目
class IndustryRanking {
  const IndustryRanking({
    required this.industry,
    required this.momentumPct,
    required this.memberCount,
    required this.institutionalNetShares,
    required this.topMembers,
    this.excessPct,
    this.institutionalVolumeRatio,
    required this.advancingRatio,
  });

  final String industry;

  /// 產業動能：成員**選定視窗**報酬的**中位數**（%）。20日視窗與
  /// computeIndustryMomentum 同口徑
  final double momentumPct;

  /// 有選定視窗報酬資料的成員數
  final int memberCount;

  /// 外資+投信近 [SectorParams.rankingInstitutionalDays] 交易日合計淨買賣（股）
  final double institutionalNetShares;

  /// 領漲成員（選定視窗報酬 DESC，上限 [SectorParams.rankingTopMembersCount]）
  final List<IndustryMember> topMembers;

  /// 超額報酬（%）：[momentumPct] − 同視窗大盤報酬。缺大盤資料時為 null。
  ///
  /// 輪動要問的是「誰比大盤強」，不是「誰漲了」。2026-07-27 實測大盤 20 日
  /// 為 **-2.10%**，此時居家生活類的 +0.23% 讀起來像「幾乎沒動」，實際是
  /// **跑贏 2.34pp**；榜上 12 個族群其實全部跑贏大盤。
  ///
  /// **缺資料時為 null 不是 0**——0 等於宣稱「大盤沒漲跌」，把缺資料講成事實。
  final double? excessPct;

  /// 法人淨買賣佔該族群同期成交量的比例（0~1，可為負）。缺成交量資料時 null。
  ///
  /// [institutionalNetShares] 的絕對值主要反映**族群規模**而非法人態度。
  /// 2026-07-27 實測：依張數是「金融保險 +18.9萬 > 電腦週邊 +16.1萬 >
  /// 鋼鐵 +9.8萬」，依佔比則是「**鋼鐵 32.6% > 水泥 25.7% > 紡織 16.2% >
  /// 金融保險 12.4%**」——排序完全不同。法人吃掉鋼鐵三日成交量的三分之一，
  /// 那才是真正被主導的族群。
  final double? institutionalVolumeRatio;

  /// 族群內報酬為正的成員佔比（0~1）。
  ///
  /// 中位數不揭露廣度：2026-07-27 實測橡膠工業中位 +3.5%／上漲佔比 **73%**
  /// （整族在動），「其他」中位 +0.7%／上漲佔比 **52%**（一半漲一半跌，
  /// 中位數由少數成員撐）。同一個排序下訊號品質天差地遠。
  final double advancingRatio;
}
