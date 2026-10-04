// 個股頁股利表：依 DividendSummary 畫今年＋前 5 年與平均列。翻譯未載入時
// 畫面顯示 key 字面，這裡以 key 比對；實際中文與參數見同目錄的 _zh_test
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/theme/app_theme.dart';
import 'package:daredevil/domain/services/dividend_summary.dart';
import 'package:daredevil/presentation/screens/stock_detail/tabs/fundamentals/dividend_summary_table.dart';

import '../../../../../helpers/widget_test_helpers.dart';

DividendSummary _summary({
  bool parValueTen = true,
  DividendYearRow current = const DividendYearRow(
    year: 2026,
    status: DividendYearStatus.notYet,
  ),
  List<DividendYearRow>? pastYears,
  DividendAverage? average,
}) => DividendSummary(
  displayEnd: DateTime(2026, 10, 2),
  parValueTen: parValueTen,
  current: current,
  pastYears:
      pastYears ??
      [
        for (var y = 2025; y >= 2021; y--)
          DividendYearRow(year: y, status: DividendYearStatus.noRecord),
      ],
  average: average,
  trailingYield: const TrailingYieldNone(),
);

void main() {
  setUpAll(() async {
    await setupTestLocalization();
  });

  Future<void> pump(
    WidgetTester tester,
    DividendSummary summary, {
    bool showROCYear = false,
  }) async {
    tester.view.physicalSize = const Size(5000, 4000);
    addTearDown(() => tester.view.resetPhysicalSize());
    await tester.pumpWidget(
      buildTestApp(
        DividendSummaryTable(summary: summary, showROCYear: showROCYear),
      ),
    );
  }

  testWidgets('有配發：現金、配股換算成元、合計', (tester) async {
    await pump(
      tester,
      _summary(
        current: const DividendYearRow(
          year: 2026,
          status: DividendYearStatus.paid,
          cash: 5,
          stockShares: 50,
          cashCount: 1,
        ),
      ),
    );
    expect(find.text('NT\$5.00'), findsOneWidget);
    expect(find.text('NT\$0.50'), findsOneWidget);
    expect(find.text('NT\$5.50'), findsOneWidget);
  });

  testWidgets('🚨 淺色主題：現金欄文字用主題的 primary（品牌藍對淺色底不到 3:1）', (tester) async {
    await pump(
      tester,
      _summary(
        current: const DividendYearRow(
          year: 2026,
          status: DividendYearStatus.paid,
          cash: 5,
          stockShares: 50,
          cashCount: 1,
        ),
      ),
    );
    final cash = tester.widget<Text>(find.text('NT\$5.00'));
    expect(cash.style?.color, AppTheme.lightTheme.colorScheme.primary);
  });

  testWidgets('多次配息才標次數', (tester) async {
    await pump(
      tester,
      _summary(
        current: const DividendYearRow(
          year: 2026,
          status: DividendYearStatus.paid,
          cash: 4,
          cashCount: 4,
        ),
        pastYears: [
          const DividendYearRow(
            year: 2025,
            status: DividendYearStatus.paid,
            cash: 3,
            cashCount: 1,
          ),
          for (var y = 2024; y >= 2021; y--)
            DividendYearRow(year: y, status: DividendYearStatus.noRecord),
        ],
      ),
    );
    expect(find.text('stockDetail.dividendCashCount'), findsOneWidget);
  });

  testWidgets('🚨 面額不是 10 元：配股顯示每千股、合計顯示「—」', (tester) async {
    await pump(
      tester,
      _summary(
        parValueTen: false,
        current: const DividendYearRow(
          year: 2026,
          status: DividendYearStatus.paid,
          stockShares: 3157.03,
        ),
      ),
    );
    expect(find.text('stockDetail.dividendSharesPerThousand'), findsOneWidget);
    expect(find.text('—'), findsOneWidget);
    expect(find.textContaining('NT\$31'), findsNothing);
  });

  testWidgets('各年度狀態的文案', (tester) async {
    await pump(
      tester,
      _summary(
        pastYears: const [
          DividendYearRow(year: 2025, status: DividendYearStatus.none),
          DividendYearRow(year: 2024, status: DividendYearStatus.building),
          DividendYearRow(year: 2023, status: DividendYearStatus.noRecord),
          DividendYearRow(year: 2022, status: DividendYearStatus.noRecord),
          DividendYearRow(year: 2021, status: DividendYearStatus.noRecord),
        ],
      ),
    );
    expect(find.text('stockDetail.dividendStatusNotYet'), findsOneWidget);
    expect(find.text('stockDetail.dividendStatusNone'), findsOneWidget);
    expect(find.text('stockDetail.dividendStatusBuilding'), findsOneWidget);
    expect(find.text('stockDetail.dividendStatusNoRecord'), findsNWidgets(3));
  });

  testWidgets('今年標截至；今年建置中時不標', (tester) async {
    await pump(tester, _summary());
    expect(find.text('stockDetail.dividendAsOf'), findsOneWidget);

    await pump(
      tester,
      _summary(
        current: const DividendYearRow(
          year: 2026,
          status: DividendYearStatus.building,
        ),
      ),
    );
    expect(find.text('stockDetail.dividendAsOf'), findsNothing);
  });

  testWidgets('平均列：滿 5 年、不足 5 年、建置中、沒有平均', (tester) async {
    await pump(
      tester,
      _summary(
        average: const DividendAverageValue(
          fromYear: 2021,
          years: 5,
          cash: 3,
          stockShares: 0,
        ),
      ),
    );
    expect(find.text('stockDetail.dividendAverageFull'), findsOneWidget);
    expect(find.text('NT\$3.00'), findsNWidgets(2)); // 現金與合計

    await pump(
      tester,
      _summary(
        average: const DividendAverageValue(
          fromYear: 2023,
          years: 3,
          cash: 3,
          stockShares: 10,
        ),
      ),
    );
    expect(find.text('stockDetail.dividendAverageSince'), findsOneWidget);

    await pump(tester, _summary(average: const DividendAverageBuilding()));
    expect(find.text('stockDetail.dividendAverage'), findsOneWidget);
    expect(find.text('stockDetail.dividendStatusBuilding'), findsOneWidget);

    await pump(tester, _summary());
    expect(find.text('stockDetail.dividendAverage'), findsNothing);
    expect(find.text('stockDetail.dividendAverageFull'), findsNothing);
  });

  testWidgets('民國年', (tester) async {
    await pump(tester, _summary(), showROCYear: true);
    expect(find.text('2026 (民115)'), findsOneWidget);
  });
}
