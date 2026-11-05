import 'package:flutter/material.dart';

import 'package:daredevil/core/constants/heatmap_params.dart';
import 'package:daredevil/core/theme/heatmap_colors.dart';

/// 自選或持股的標記：與格子上的自選框同樣的雙線框（外深內淺各 1px），
/// 圖例與清單共用，看到的是同一個符號
class HeatmapMineMark extends StatelessWidget {
  const HeatmapMineMark({super.key, this.fill, this.semanticLabel});

  /// 框內的底色；null 時透明
  final Color? fill;

  /// 單獨出現（例如清單列）時給螢幕閱讀器的說明；旁邊已有說明文字時不給
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) => Semantics(
    label: semanticLabel,
    excludeSemantics: true,
    child: Container(
      width: HeatmapParams.legendSwatchSize,
      height: HeatmapParams.legendSwatchSize,
      decoration: BoxDecoration(
        color: fill,
        border: Border.all(color: HeatmapColors.mineOuter),
      ),
      child: const DecoratedBox(
        decoration: BoxDecoration(
          border: Border.fromBorderSide(
            BorderSide(color: HeatmapColors.mineInner),
          ),
        ),
      ),
    ),
  );
}
