import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/exceptions/app_exception.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/presentation/providers/update_history_provider.dart';
import 'package:daredevil/presentation/widgets/update_history_sheet.dart';

import '../../helpers/phone_layout_helpers.dart';
import '../../helpers/provider_test_helpers.dart';
import '../../helpers/widget_test_helpers.dart';

void main() {
  setUpAll(() async {
    await setupTestLocalization();
  });

  Widget sheetWithError() => buildProviderTestApp(
    const UpdateHistorySheet(),
    overrides: [
      updateHistoryProvider.overrideWith(
        (ref) => Future<List<UpdateRunEntry>>.error(
          const DatabaseException('Database error'),
        ),
      ),
    ],
  );

  group('載入失敗畫面', () {
    for (final scenario in phoneScenarios) {
      testWidgets('$scenario 不溢位', (tester) async {
        applyPhoneScenario(tester, scenario);
        await tester.pumpWidget(sheetWithError());
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));

        expect(tester.takeException(), isNull);
        expect(find.text('updateHistory.retry'), findsOneWidget);
      });
    }

    testWidgets('在錯誤內容上拖曳可以拉高 sheet（接上 sheet 的 controller）', (tester) async {
      applyPhoneScenario(tester, phoneScenarios.first);
      await tester.pumpWidget(sheetWithError());
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      final sheet = find.descendant(
        of: find.byType(DraggableScrollableSheet),
        matching: find.byType(Column),
      );
      final before = tester.getSize(sheet.first).height;

      await tester.drag(
        find.text('updateHistory.retry'),
        const Offset(0, -200),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(tester.getSize(sheet.first).height, greaterThan(before));
    });
  });

  testWidgets('無紀錄：在文字上拖曳可以拉高 sheet', (tester) async {
    applyPhoneScenario(tester, phoneScenarios.first);
    await tester.pumpWidget(
      buildProviderTestApp(
        const UpdateHistorySheet(),
        overrides: [
          updateHistoryProvider.overrideWith(
            (ref) async => const <UpdateRunEntry>[],
          ),
        ],
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    final sheet = find.descendant(
      of: find.byType(DraggableScrollableSheet),
      matching: find.byType(Column),
    );
    final before = tester.getSize(sheet.first).height;

    await tester.drag(find.text('updateHistory.empty'), const Offset(0, -200));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(tester.getSize(sheet.first).height, greaterThan(before));
  });
}
