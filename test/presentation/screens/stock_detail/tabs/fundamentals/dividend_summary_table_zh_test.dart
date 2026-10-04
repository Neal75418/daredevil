// 股利表以真實 zh-TW 翻譯驗文案參數（{date}、{count}、{shares}、{year}、
// {years}）與手機寬度不溢位。真實翻譯寫入全域 Localization.instance、會污染
// 同檔其他測試，故獨立成檔
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/domain/services/dividend_summary.dart';
import 'package:daredevil/presentation/screens/stock_detail/tabs/fundamentals/dividend_summary_table.dart';

import '../../../../../helpers/provider_test_helpers.dart';
import '../../../../../helpers/widget_test_helpers.dart';

void main() {
  setUpAll(() async {
    await setupTestLocalization();
  });

  testWidgets('手機寬度、民國年：截至、次數、每千股、起算年平均', (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      buildProviderTestApp(
        SingleChildScrollView(
          child: DividendSummaryTable(
            summary: DividendSummary(
              displayEnd: DateTime(2026, 10, 2),
              parValueTen: false,
              current: const DividendYearRow(
                year: 2026,
                status: DividendYearStatus.paid,
                cash: 2.4,
                stockShares: 3157.03,
                cashCount: 4,
              ),
              pastYears: const [
                DividendYearRow(
                  year: 2025,
                  status: DividendYearStatus.paid,
                  cash: 6,
                  cashCount: 1,
                ),
                DividendYearRow(year: 2024, status: DividendYearStatus.none),
                DividendYearRow(
                  year: 2023,
                  status: DividendYearStatus.paid,
                  cash: 3,
                  stockShares: 30,
                  cashCount: 1,
                ),
                DividendYearRow(
                  year: 2022,
                  status: DividendYearStatus.noRecord,
                ),
                DividendYearRow(
                  year: 2021,
                  status: DividendYearStatus.noRecord,
                ),
              ],
              average: const DividendAverageValue(
                fromYear: 2023,
                years: 3,
                cash: 3,
                stockShares: 10,
              ),
              trailingYield: const TrailingYieldNone(),
            ),
            showROCYear: true,
          ),
        ),
        zhTranslations: true,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(tester.takeException(), isNull);
    expect(find.text('除息年度'), findsOneWidget);
    expect(find.text('截至 10/2'), findsOneWidget);
    expect(find.text('4 次'), findsOneWidget);
    expect(find.text('每千股 3,157.03 股'), findsOneWidget);
    expect(find.text('每千股 10 股'), findsOneWidget); // 平均列
    expect(find.text('2023 起 3 年平均'), findsOneWidget);
    expect(find.text('無除權息紀錄'), findsNWidgets(2));
  });
}
