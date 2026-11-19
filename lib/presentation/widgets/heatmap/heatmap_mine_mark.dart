import 'package:flutter/material.dart';

import 'package:daredevil/core/constants/heatmap_params.dart';
import 'package:daredevil/core/theme/heatmap_colors.dart';

/// 自選或持股的標記：與格子上的自選框同樣的雙線框（外深內淺各 1px），圖例
/// 用它，與圖上看到的是同一個符號。純裝飾，語意由旁邊的說明文字負責
class HeatmapMineMark extends StatelessWidget {
  const HeatmapMineMark({super.key, required this.fill});

  /// 框內的底色
  final Color fill;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
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
