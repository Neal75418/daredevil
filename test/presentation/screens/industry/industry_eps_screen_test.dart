import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:daredevil/data/remote/tpex_client.dart';
import 'package:daredevil/presentation/providers/industry_eps_provider.dart';
import 'package:daredevil/presentation/providers/providers.dart';
import 'package:daredevil/presentation/screens/industry/industry_eps_screen.dart';

import '../../../helpers/widget_test_helpers.dart';

class _MockTpexClient extends Mock implements TpexClient {}

void main() {
  setUpAll(() async {
    await setupTestLocalization();
  });

  testWidgets('稅後淨利欄以千元換算成元顯示（1,353,387 千元 → 13.5 億）', (tester) async {
    tester.view.physicalSize = const Size(5000, 4000);
    addTearDown(() => tester.view.resetPhysicalSize());

    final mock = _MockTpexClient();
    // 回傳可變清單：TpexClient 回的是一般 List，而 state.filteredData 會就地排序
    when(() => mock.getIndustryEps()).thenAnswer(
      (_) async => [
        const TpexIndustryEps(
          symbol: '3105',
          companyName: '穩懋',
          industry: '半導體業',
          year: 2026,
          quarter: 2,
          eps: 3.56,
          revenue: 9847328,
          operatingProfit: 0,
          netIncome: 1353387,
        ),
      ],
    );

    // 先載好資料再掛畫面（等同回到有快取的頁面）：畫面第一幀在資料到之前會
    // 先畫空狀態，那是另一件事，這裡只驗單位換算。
    final container = ProviderContainer(
      overrides: [tpexClientProvider.overrideWithValue(mock)],
    );
    final keepAlive = container.listen(industryEpsProvider, (_, _) {});
    await container.read(industryEpsProvider.notifier).loadData();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: buildTestApp(
          const IndustryEpsScreen(),
          locale: const Locale('zh', 'TW'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 前提：這一列確實畫出來了（EPS 欄），否則下面的斷言失敗不代表單位錯
    expect(find.text('3.56'), findsOneWidget);
    expect(find.text('13.5億'), findsOneWidget);

    // 卸載畫面後才釋放 container（provider 的 keepAlive 計時器隨之取消）
    await tester.pumpWidget(const SizedBox());
    keepAlive.close();
    container.dispose();
  });
}
