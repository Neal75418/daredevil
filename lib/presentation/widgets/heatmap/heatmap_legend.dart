import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'package:daredevil/core/constants/heatmap_params.dart';
import 'package:daredevil/core/theme/design_tokens.dart';
import 'package:daredevil/core/theme/heatmap_colors.dart';
import 'package:daredevil/presentation/widgets/heatmap/heatmap_mine_mark.dart';

/// 熱力圖圖例：13 格色階（跌 6 階、平盤、漲 6 階，兩端寫「跌／漲 ≥ 最深一階」）、
/// 自選雙線框、空心格子、產業漲跌的算法
class HeatmapLegend extends StatelessWidget {
  const HeatmapLegend({super.key});

  /// 第 [index] 格色塊（0＝跌最深、6＝平盤、12＝漲最深）
  static Key swatchKey(int index) => ValueKey('heatmapLegendSwatch$index');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final style = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final scale = [
      for (var step = 6; step >= 1; step--)
        HeatmapColors.fill(step: step, up: false, brightness: brightness),
      HeatmapColors.flat(brightness),
      for (var step = 1; step <= 6; step++)
        HeatmapColors.fill(step: step, up: true, brightness: brightness),
    ];
    final maxArgs = {
      'value': NumberFormat('0.##').format(HeatmapParams.stepBounds.last),
    };
    return Wrap(
      spacing: DesignTokens.spacing16,
      runSpacing: DesignTokens.spacing4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'marketHeatmap.legendDown'.tr(namedArgs: maxArgs),
              style: style,
            ),
            const SizedBox(width: DesignTokens.spacing4),
            // 空間不夠時色塊一起縮窄，兩端文字保持完整
            for (var i = 0; i < scale.length; i++)
              Flexible(
                child: ColoredBox(
                  key: swatchKey(i),
                  color: scale[i],
                  child: const SizedBox(
                    width: HeatmapParams.legendSwatchSize,
                    height: HeatmapParams.legendSwatchSize,
                  ),
                ),
              ),
            const SizedBox(width: DesignTokens.spacing4),
            Text('marketHeatmap.legendUp'.tr(namedArgs: maxArgs), style: style),
          ],
        ),
        _item(
          HeatmapMineMark(fill: HeatmapColors.flat(brightness)),
          'marketHeatmap.legendMine'.tr(),
          style,
        ),
        _item(
          Container(
            width: HeatmapParams.legendSwatchSize,
            height: HeatmapParams.legendSwatchSize,
            decoration: BoxDecoration(
              border: Border.all(color: HeatmapColors.hollowBorder(brightness)),
            ),
          ),
          'marketHeatmap.legendHollow'.tr(),
          style,
        ),
        Text('marketHeatmap.legendWeighted'.tr(), style: style),
      ],
    );
  }

  /// 說明文字放不下時換行（長翻譯、放大字級），不溢位
  Widget _item(Widget swatch, String text, TextStyle? style) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      swatch,
      const SizedBox(width: DesignTokens.spacing4),
      Flexible(child: Text(text, style: style)),
    ],
  );
}
