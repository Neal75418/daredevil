import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:daredevil/core/constants/app_routes.dart';
import 'package:daredevil/domain/models/close_summary.dart';
import 'package:daredevil/presentation/providers/close_summary_provider.dart';
import 'package:daredevil/presentation/screens/today/widgets/close_summary_entry_card.dart';

import '../../../../helpers/provider_test_helpers.dart';

CloseSummaryRow _row(String symbol, {List<SummaryEvent> events = const []}) =>
    CloseSummaryRow(
      symbol: symbol,
      name: symbol,
      market: 'TWSE',
      groupId: null,
      groupName: null,
      role: GroupRole.other,
      status: RowDataStatus.ok,
      events: events,
    );

/// 持股 2 檔、有待處理事件的 1 檔（另一檔只有資訊事件）
final _summary = CloseSummary(
  dataDate: DateTime(2026, 11, 19),
  pricePendingMarkets: const {},
  institutionalPendingMarkets: const {},
  indexReady: false,
  throttle: null,
  strongListGroupMissing: false,
  sections: [
    CloseSummarySection(
      isHoldings: true,
      groupId: null,
      groupName: null,
      rows: [
        _row('A', events: const [SummaryEvent(SummaryEventKind.stopBroken)]),
        _row('B', events: const [SummaryEvent(SummaryEventKind.limitUp)]),
      ],
    ),
    CloseSummarySection(
      isHoldings: false,
      groupId: null,
      groupName: null,
      rows: [_row('C')],
    ),
  ],
);

void main() {
  late GoRouter router;

  Future<void> pump(
    WidgetTester tester,
    FutureOr<CloseSummary?> Function(Ref ref) create,
  ) async {
    router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(body: CloseSummaryEntryCard()),
        ),
        GoRoute(
          path: AppRoutes.closeSummary,
          builder: (_, _) => const Text('summary page'),
        ),
      ],
    );
    await tester.pumpWidget(
      buildProviderTestApp(
        const SizedBox(),
        router: router,
        zhTranslations: true,
        overrides: [closeSummaryProvider.overrideWith(create)],
      ),
    );
    await tester.pump();
  }

  testWidgets('有資料：寫日期、持股檔數與待處理事件檔數；點了進摘要頁', (tester) async {
    await pump(tester, (ref) => SynchronousFuture(_summary));
    expect(find.text('收盤摘要・11/19・持股 2 檔・事件 1 檔'), findsOneWidget);

    await tester.tap(find.byType(CloseSummaryEntryCard));
    await tester.pumpAndSettle();
    expect(router.state.matchedLocation, AppRoutes.closeSummary);
  });

  testWidgets('第一次載入中與錯誤時整張不顯示', (tester) async {
    final pending = Completer<CloseSummary?>();
    await pump(tester, (ref) => pending.future);
    expect(find.byType(Card), findsNothing);

    await pump(tester, (ref) => Future.error(StateError('boom')));
    await tester.pump();
    expect(find.byType(Card), findsNothing);
    pending.complete(null);
  });

  testWidgets('沒有價格資料、或沒有任何列 → 不顯示', (tester) async {
    await pump(tester, (ref) => SynchronousFuture(null));
    expect(find.byType(Card), findsNothing);
  });

  testWidgets('沒有自選也沒有持股 → 不顯示', (tester) async {
    await pump(
      tester,
      (ref) => SynchronousFuture(
        CloseSummary(
          dataDate: DateTime(2026, 11, 19),
          pricePendingMarkets: const {},
          institutionalPendingMarkets: const {},
          indexReady: false,
          throttle: null,
          strongListGroupMissing: false,
          sections: const [],
        ),
      ),
    );
    expect(find.byType(Card), findsNothing);
  });

  testWidgets('重算途中沿用上一次的內容，不閃掉', (tester) async {
    var calls = 0;
    final second = Completer<CloseSummary?>();
    await pump(tester, (ref) {
      calls++;
      return calls == 1 ? SynchronousFuture(_summary) : second.future;
    });
    expect(find.textContaining('收盤摘要'), findsOneWidget);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(CloseSummaryEntryCard)),
    );
    container.invalidate(closeSummaryProvider, asReload: true);
    await tester.pump();
    expect(calls, 2);
    expect(find.textContaining('收盤摘要'), findsOneWidget);
    second.complete(_summary);
    await tester.pump();
  });
}
