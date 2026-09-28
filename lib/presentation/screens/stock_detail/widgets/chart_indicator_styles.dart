import 'package:flutter/material.dart';
import 'package:k_chart_plus/k_chart_plus.dart';

import 'package:daredevil/core/theme/app_theme.dart';
import 'package:daredevil/core/theme/indicator_colors.dart';
import 'package:daredevil/core/theme/semantic_colors.dart';

/// 副圖指標樣式的唯一出口(2026-08-05 複審 High #3 的修復)。
///
/// 1.0.4 遷移時副圖曾直接用套件預設 `IndicatorStyle`——其 MACD 柱是
/// 「綠=正、紅=負」(國際慣例),與本 app 的台股紅漲綠跌**方向相反**,
/// 且預設線色(#14AD8F/#D5405D/#35CDAC)踩進股價紅綠色相禁區;1.0.3
/// 舊版吃的是 app 的 chartColors,語意本來正確,遷移把它弄丟了。
///
/// 集中在此的理由:`chart_secondary_styles_test` 對這個出口逐色守門
/// (MACD 柱必須等於 AppTheme 漲跌色、其餘線色不得落入紅綠禁區),
/// 散在 widget 內就守不住。
abstract final class ChartIndicatorStyles {
  static MAStyle maFor(Brightness brightness) =>
      MAStyle(maColors: IndicatorColors.maColorsFor(brightness));

  /// MACD 柱走台股語意:正=漲色(紅)、負=跌色(綠)
  static MACDStyle macdFor(Brightness brightness) => MACDStyle(
    upColor: AppTheme.upColor,
    dnColor: PriceColors.downFor(brightness),
    difColor: IndicatorColors.chartPrimary,
    deaColor: IndicatorColors.chartSecondary,
    macdColor: IndicatorColors.chartTertiary,
    macdWidth: 3,
  );

  static KDJStyle kdjFor(Brightness brightness) => const KDJStyle(
    kColor: IndicatorColors.chartPrimary,
    dColor: IndicatorColors.chartSecondary,
    jColor: IndicatorColors.chartTertiary,
  );

  static RSIStyle rsiFor(Brightness brightness) =>
      const RSIStyle(rsiColor: IndicatorColors.chartSecondary);

  static WRStyle wrFor(Brightness brightness) =>
      const WRStyle(wrColor: IndicatorColors.chartPrimary);

  static CCIStyle cciFor(Brightness brightness) =>
      const CCIStyle(cciColor: IndicatorColors.chartTertiary);

  /// 守門測試用:列舉本出口管轄的指標色(MA 與五個副圖)——線色,加上 MACD
  /// 副圖標頭的數值文字色(macdColor);不含 MACD 柱(柱色有自己的語意斷言)
  @visibleForTesting
  static List<Color> lineColorsFor(Brightness b) {
    final macd = macdFor(b);
    final kdj = kdjFor(b);
    return [
      ...IndicatorColors.maColorsFor(b),
      macd.difColor,
      macd.deaColor,
      macd.macdColor,
      kdj.kColor,
      kdj.dColor,
      kdj.jColor,
      rsiFor(b).rsiColor,
      wrFor(b).wrColor,
      cciFor(b).cciColor,
    ];
  }
}
