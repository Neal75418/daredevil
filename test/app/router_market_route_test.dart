import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import 'package:daredevil/app/router.dart';
import 'package:daredevil/core/constants/app_routes.dart';
import 'package:daredevil/presentation/screens/market/market_overview_screen.dart';

class _MockContext extends Mock implements BuildContext {}

class _MockState extends Mock implements GoRouterState {}

void main() {
  GoRoute marketRoute() =>
      router.configuration.findMatch(Uri.parse(AppRoutes.market)).last.route;

  test('/market 對應到 market 路由', () {
    expect(marketRoute().name, 'market');
  });

  test('market 路由建出大盤總覽頁', () {
    final page = marketRoute().builder!(_MockContext(), _MockState());
    expect(page, isA<MarketOverviewScreen>());
  });
}
