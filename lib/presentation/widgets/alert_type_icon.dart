import 'package:flutter/material.dart';

import 'package:daredevil/presentation/providers/price_alert_provider.dart';

/// AlertType → 圖示的單一來源
///
/// 2026-07-23 稽核修復：原本個股「警示」分頁與全域警示頁各自維護整份
/// switch 複本，changePct 已分岔（percent vs show_chart）——統一取
/// percent（百分比語意較準確），其餘沿用全域警示頁版本。
extension AlertTypeIcon on AlertType {
  IconData get icon => switch (this) {
    // 2026-08-16：`above`/`below` 原本是 trending_up / trending_down，而自選股
    // 卡片的**趨勢狀態**用 trending_up_rounded / trending_down_rounded
    // （`trend_state_extension.dart`）——20px 下分不出來的兩個圖示，表達的卻是
    // 完全不同的事：這裡是「提醒會在跌破還是突破時響」，那裡是「這檔股票現在
    // 多頭還空頭」。均線階梯上線後每檔強勢股都掛 BELOW，矛盾天天出現（實機：
    // 仁寶漲停 +9.92%，自選股頁紅色上箭頭、警示頁綠色下箭頭）。
    //
    // 改用 vertical_align_*：箭頭 + 一條線，正是「價格穿越門檻」的語意，而且
    // 不再與趨勢共用視覺語言。顏色同步改中性（見 alerts_screen 的
    // `_getAlertColor`）——紅綠是股價語意保留區（`semantic_colors.dart`）。
    AlertType.above => Icons.vertical_align_top,
    AlertType.below => Icons.vertical_align_bottom,
    AlertType.changePct => Icons.percent,
    AlertType.volumeSpike || AlertType.volumeAbove => Icons.bar_chart,
    AlertType.rsiOverbought => Icons.arrow_upward,
    AlertType.rsiOversold => Icons.arrow_downward,
    AlertType.kdGoldenCross => Icons.add_circle_outline,
    AlertType.kdDeathCross => Icons.remove_circle_outline,
    AlertType.breakResistance => Icons.north_east,
    AlertType.breakSupport => Icons.south_east,
    AlertType.week52High => Icons.emoji_events,
    AlertType.week52Low => Icons.trending_down,
    AlertType.crossAboveMa || AlertType.crossBelowMa => Icons.timeline,
    AlertType.revenueYoySurge ||
    AlertType.highDividendYield ||
    AlertType.peUndervalued => Icons.analytics,
    AlertType.tradingWarning => Icons.warning_amber,
    AlertType.tradingDisposal => Icons.gpp_bad,
    AlertType.insiderSelling => Icons.person_remove,
    AlertType.insiderBuying => Icons.person_add,
    AlertType.highPledgeRatio => Icons.lock,
  };
}
