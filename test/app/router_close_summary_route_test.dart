import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import 'package:daredevil/app/router.dart';
import 'package:daredevil/core/constants/app_routes.dart';
import 'package:daredevil/presentation/screens/close_summary/close_summary_screen.dart';

class _MockContext extends Mock implements BuildContext {}

class _MockState extends Mock implements GoRouterState {}

void main() {
  GoRoute summaryRoute() => router.configuration
      .findMatch(Uri.parse(AppRoutes.closeSummary))
      .last
      .route;

  test('/close-summary 對應到 closeSummary 路由', () {
    expect(AppRoutes.closeSummary, '/close-summary');
    expect(summaryRoute().name, 'closeSummary');
  });

  test('closeSummary 路由建出收盤摘要頁', () {
    final page = summaryRoute().builder!(_MockContext(), _MockState());
    expect(page, isA<CloseSummaryScreen>());
  });
}
