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
  HollowReason.noClosingMatch => 'marketHeatmap.hollowNoClosingMatch'.tr(),
};

/// 圖上的格子占這個市場市值的比例，整數 %：四捨五入後夾在 1～99，只要有
/// 一檔就不寫 0%、還差一檔沒畫就不寫 100%；恰為 0 或 1 時照實寫。
int heatmapCoveragePercent(double coverage) {
  if (!(coverage > 0)) return 0;
  if (coverage >= 1) return 100;
  return (coverage * 100).round().clamp(1, 99);
}

/// 圖例說明這張圖代表多少：「市值前 30 檔・占上市市值 74%」。[tileCount] 是
/// 實際畫出來的檔數，[marketLabel] 是市場名稱（上市／上櫃）
String heatmapLegendCoverageText({
  required int tileCount,
  required String marketLabel,
  required double coverage,
}) => 'marketHeatmap.legendCoverage'.tr(
  namedArgs: {
    'count': '$tileCount',
    'market': marketLabel,
    'pct': '${heatmapCoveragePercent(coverage)}',
  },
);

/// 盤中未即時的格子附的正式資料漲跌：「M/D 收盤 -0.80%」（ASCII 減號，與其他
/// 漲跌幅同一個格式）
String heatmapPreviousCloseText(({double percent, DateTime date}) previous) =>
    'marketHeatmap.previousClose'.tr(
      namedArgs: {
        'date': _monthDay(previous.date),
        'pct': formatHeatmapPercent(previous.percent),
      },
    );

/// 格子提示的價格：「價格 150.00」；[closeDate] 不是 null 時這個價格是那天的
/// 收盤，接「（M/D 收盤）」
String heatmapTooltipPriceText(double price, {DateTime? closeDate}) {
  final text =
      '${'marketHeatmap.tooltipPrice'.tr()} ${formatHeatmapPrice(price)}';
  if (closeDate == null) return text;
  return '$text${'marketHeatmap.tooltipPriceClose'.tr(namedArgs: {'date': _monthDay(closeDate)})}';
}

String _monthDay(DateTime date) => '${date.month}/${date.day}';

/// 熱力圖頁指數列下方的即時狀態行；空字串表示不顯示。
///
/// 報價暫停、限流等報價中心的狀態放在最前面：這一行最多兩行，窄螢幕截斷時
/// 先捨後面的收盤進度。收盤後（沒有退回正式資料）再接「今日收盤 N／M 檔」；
/// 有收盤沒撮合的檔時另寫檔數（「K 檔收盤沒撮合」）：那幾檔已不再等。
String heatmapLiveStatusText(HeatmapLiveView view) => [
  if (view.quoteStatus case final status?) status.text(),
  if (view.closing case final closing?)
    closing.unmatched > 0
        ? 'marketHeatmap.closingProgressUnmatched'.tr(
            namedArgs: {
              'done': '${closing.done}',
              'unmatched': '${closing.unmatched}',
              'total': '${closing.total}',
            },
          )
        : 'marketHeatmap.closingProgress'.tr(
            namedArgs: {'done': '${closing.done}', 'total': '${closing.total}'},
          ),
].join('marketHeatmap.statusJoin'.tr());
