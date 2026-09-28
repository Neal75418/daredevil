import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:daredevil/core/exceptions/app_exception.dart';
import 'package:daredevil/data/repositories/stock_repository.dart';
import 'package:daredevil/presentation/providers/providers.dart';
import 'package:daredevil/presentation/screens/industry/industry_overview_screen.dart';
import 'package:daredevil/presentation/widgets/empty_state.dart';

import '../../../helpers/phone_layout_helpers.dart';
import '../../../helpers/provider_test_helpers.dart';
import '../../../helpers/widget_test_helpers.dart';

class _MockStockRepository extends Mock implements StockRepository {}

void main() {
  setUpAll(() async {
    await setupTestLocalization();
  });

  group('錯誤頁在手機上（小螢幕、放大字級）', () {
    final errors = <String, AppException>{
      'Database error': const DatabaseException('Database error'),
      'Network error': const NetworkException('Network error'),
    };

    for (final entry in errors.entries) {
      for (final scenario in phoneScenarios) {
        testWidgets('${entry.key}：$scenario 不溢位', (tester) async {
          applyPhoneScenario(tester, scenario);
          final repo = _MockStockRepository();
          when(() => repo.getIndustryStockCounts()).thenThrow(entry.value);
          await tester.pumpWidget(
            buildProviderTestApp(
              const IndustryOverviewScreen(),
              overrides: [stockRepositoryProvider.overrideWithValue(repo)],
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(seconds: 1));

          expect(tester.takeException(), isNull);
          expect(find.byType(EmptyState), findsOneWidget);
        });
      }
    }
  });
}
