import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import 'package:daredevil/app/router.dart';
import 'package:daredevil/core/constants/app_routes.dart';
import 'package:daredevil/presentation/screens/market/market_heatmap_screen.dart';

class _MockContext extends Mock implements BuildContext {}

class _MockState extends Mock implements GoRouterState {}

void main() {
  GoRoute heatmapRoute() => router.configuration
      .findMatch(Uri.parse(AppRoutes.marketHeatmap))
      .last
      .route;

  test('/market-heatmap 對應到 marketHeatmap 路由', () {
    expect(AppRoutes.marketHeatmap, '/market-heatmap');
    expect(heatmapRoute().name, 'marketHeatmap');
  });

  test('marketHeatmap 路由建出熱力圖頁', () {
    final page = heatmapRoute().builder!(_MockContext(), _MockState());
    expect(page, isA<MarketHeatmapScreen>());
  });
}
