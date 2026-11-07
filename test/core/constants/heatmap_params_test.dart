import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/constants/heatmap_params.dart';

void main() {
  group('HeatmapParams.stepOf', () {
    test('依 spec 分界', () {
      expect(HeatmapParams.stepOf(0), 0);
      expect(HeatmapParams.stepOf(0.49), 1);
      expect(HeatmapParams.stepOf(0.5), 2);
      expect(HeatmapParams.stepOf(1.5), 3);
      expect(HeatmapParams.stepOf(3), 4);
      expect(HeatmapParams.stepOf(5), 5);
      expect(HeatmapParams.stepOf(9.5), 6);
      expect(HeatmapParams.stepOf(123.93), 6);
      expect(HeatmapParams.stepOf(-0.5), 2);
      expect(HeatmapParams.stepOf(-9.5), 6);
      // 分界下方最大的可能輸入（四捨五入到 2 位後）：分界被調低就會紅
      expect(HeatmapParams.stepOf(1.49), 2);
      expect(HeatmapParams.stepOf(2.99), 3);
      expect(HeatmapParams.stepOf(4.99), 4);
      expect(HeatmapParams.stepOf(9.49), 5);
    });

    test('roundPercent 四捨五入到 2 位，負值對稱', () {
      expect(HeatmapParams.roundPercent(9.499999999999998), 9.5);
      expect(HeatmapParams.roundPercent(1.834), 1.83);
      expect(HeatmapParams.roundPercent(-1.836), -1.84);
      expect(HeatmapParams.roundPercent(-0.004), 0);
      // 負零會被格式化成 "-0.00"
      expect(HeatmapParams.roundPercent(-0.004).isNegative, isFalse);
    });

    test('先四捨五入到 2 位', () {
      // 收盤 6.57、漲 0.57（平盤 6.00）：未四捨五入是 9.499999999999998
      expect(HeatmapParams.stepOf(0.57 / (6.57 - 0.57) * 100), 6);
      // 收盤 23.73、漲 1.13：未四捨五入是 4.999999999999999
      expect(HeatmapParams.stepOf(1.13 / (23.73 - 1.13) * 100), 5);
      // 顯示為 0.00% 的值畫平盤
      expect(HeatmapParams.stepOf(0.004), 0);
      expect(HeatmapParams.stepOf(-0.004), 0);
    });
  });

  test('heatmap_params.dart 維持純 Dart（遞移只 import dart: 函式庫、不含 dart:ui）', () {
    // core_layer_purity_test 只擋上層 import，不擋 Flutter；沿著 core/constants
    // 的 import 一路查到底，只准 dart: 函式庫，才擋得住經由別的 core 檔間接
    // 帶進 Flutter
    const constantsPackage = 'package:daredevil/core/constants/';
    final directive = RegExp(
      r'''^\s*(?:import|export)\s+['"]([^'"]+)['"]''',
      multiLine: true,
    );
    final visited = <String>{};
    void check(String path) {
      if (!visited.add(path)) return;
      final src = File(path).readAsStringSync();
      for (final m in directive.allMatches(src)) {
        final uri = m.group(1)!;
        if (uri.startsWith(constantsPackage)) {
          check('lib/core/constants/${uri.substring(constantsPackage.length)}');
        } else {
          expect(
            uri.startsWith('dart:') && uri != 'dart:ui',
            isTrue,
            reason: '$path → $uri',
          );
        }
      }
    }

    check('lib/core/constants/heatmap_params.dart');
    // 真的走進了被引用的常數檔（走不進去就不算查過）
    expect(visited, contains('lib/core/constants/api_endpoints.dart'));
  });

  test('isExcludedIndustry：ETF、上櫃ETF、存託憑證排除，一般產業與 null 不排除', () {
    expect(HeatmapParams.isExcludedIndustry('ETF'), isTrue);
    expect(HeatmapParams.isExcludedIndustry('上櫃ETF'), isTrue);
    expect(HeatmapParams.isExcludedIndustry('存託憑證'), isTrue);
    expect(HeatmapParams.isExcludedIndustry('半導體業'), isFalse);
    expect(HeatmapParams.isExcludedIndustry(null), isFalse);
  });
}
