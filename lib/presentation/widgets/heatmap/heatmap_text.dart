import 'package:easy_localization/easy_localization.dart';

import 'package:daredevil/domain/models/heatmap.dart';
import 'package:daredevil/presentation/providers/heatmap_live_provider.dart';
import 'package:daredevil/presentation/widgets/heatmap/heatmap_painter.dart';

/// 空心格子原因的文字（畫面、提示、無障礙描述共用）
String heatmapHollowReasonText(HollowReason reason) => switch (reason) {
  HollowReason.noChangeData => 'marketHeatmap.hollowNoChange'.tr(),
  HollowReason.notLive => 'marketHeatmap.hollowNotLive'.tr(),
  HollowReason.noTrade => 'marketHeatmap.hollowNoTrade'.tr(),
  HollowReason.noQuote => 'marketHeatmap.hollowNoQuote'.tr(),
  HollowReason.noClosingQuote => 'marketHeatmap.hollowNoClosingQuote'.tr(),
};

/// 即時（收盤後是已收盤）部分占的市值比例，整數 %：四捨五入後夾在 1～99，
/// 只要有一檔就不寫 0%、還差一檔就不寫 100%；恰為 0 或 1 時照實寫。
/// 圖上與無障礙描述共用。
int heatmapCoveragePercent(double coverage) {
  if (!(coverage > 0)) return 0;
  if (coverage >= 1) return 100;
  return (coverage * 100).round().clamp(1, 99);
}

/// 接在加權漲跌後的即時比例：盤中「・即時 N%」、收盤後「・收盤 N%」
String heatmapCoverageSuffix(double coverage, HeatmapLiveMode mode) =>
    switch (mode) {
      HeatmapLiveMode.intraday => 'marketHeatmap.liveCoverage',
      HeatmapLiveMode.afterClose => 'marketHeatmap.closingCoverage',
    }.tr(namedArgs: {'pct': '${heatmapCoveragePercent(coverage)}'});

/// 無障礙描述的即時比例子句（不帶「・」，報讀軟體才不會念出符號）
String heatmapCoverageSemantics(double coverage, HeatmapLiveMode mode) =>
    switch (mode) {
      HeatmapLiveMode.intraday => 'marketHeatmap.semLiveCoverage',
      HeatmapLiveMode.afterClose => 'marketHeatmap.semClosingCoverage',
    }.tr(namedArgs: {'pct': '${heatmapCoveragePercent(coverage)}'});

/// 產業或合併塊沒有加權漲跌時的文字：盤中「未即時」、收盤後「未收盤」、
/// 正式資料（[mode] null）「無漲跌資料」
String heatmapNoChangeText(HeatmapLiveMode? mode) => switch (mode) {
  null => 'marketHeatmap.hollowNoChange'.tr(),
  HeatmapLiveMode.intraday => 'marketHeatmap.notLive'.tr(),
  HeatmapLiveMode.afterClose => 'marketHeatmap.notClosed'.tr(),
};

/// 產業或合併塊的加權漲跌：有值寫漲跌幅，即時套色時（[mode] 不是 null）
/// 後面接即時比例；沒有值寫 [heatmapNoChangeText]
String heatmapWeightedText({
  required double? percent,
  required double? coverage,
  required HeatmapLiveMode? mode,
}) {
  if (percent == null) return heatmapNoChangeText(mode);
  final text = formatHeatmapPercent(percent);
  if (mode == null || coverage == null) return text;
  return '$text${heatmapCoverageSuffix(coverage, mode)}';
}

/// 盤中未即時的格子附的正式資料漲跌：「M/D 收盤 -0.80%」（ASCII 減號，與其他
/// 漲跌幅同一個格式）
String heatmapPreviousCloseText(({double percent, DateTime date}) previous) =>
    'marketHeatmap.previousClose'.tr(
      namedArgs: {
        'date': '${previous.date.month}/${previous.date.day}',
        'pct': formatHeatmapPercent(previous.percent),
      },
    );

/// 熱力圖頁指數列下方的即時狀態行；空字串表示不顯示。
///
/// 報價暫停、限流等報價中心的狀態放在最前面：這一行最多兩行，窄螢幕截斷時
/// 先捨後面的收盤進度。收盤後（沒有退回正式資料）再接「今日收盤 N／M 檔」。
String heatmapLiveStatusText(HeatmapLiveView view) => [
  if (view.quoteStatus case final status?) status.text(),
  if (view.closing case final closing?)
    'marketHeatmap.closingProgress'.tr(
      namedArgs: {'done': '${closing.done}', 'total': '${closing.total}'},
    ),
].join('marketHeatmap.statusJoin'.tr());
