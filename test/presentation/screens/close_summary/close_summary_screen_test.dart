import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:daredevil/core/constants/app_routes.dart';
import 'package:daredevil/core/theme/semantic_colors.dart';
import 'package:daredevil/core/utils/clock.dart';
import 'package:daredevil/domain/models/close_summary.dart';
import 'package:daredevil/domain/services/close_summary/chip_checks.dart';
import 'package:daredevil/domain/services/close_summary/holding_checks.dart';
import 'package:daredevil/domain/services/close_summary/price_checks.dart';
import 'package:daredevil/domain/services/close_summary/throttle.dart';
import 'package:daredevil/presentation/providers/close_summary_provider.dart';
import 'package:daredevil/presentation/providers/providers.dart';
import 'package:daredevil/presentation/screens/close_summary/close_summary_screen.dart';
import 'package:daredevil/presentation/screens/today/widgets/close_summary_entry_card.dart';

import '../../../helpers/provider_test_helpers.dart';

class _FixedClock implements AppClock {
  const _FixedClock(this._now);
  final DateTime _now;
  @override
  DateTime now() => _now;
}

/// 資料日 2026-11-19（四）；時鐘 11-19 17:00（資料是今天的，不等、不落後）
final _d = DateTime(2026, 11, 19);
final _clock = _FixedClock(DateTime(2026, 11, 19, 17));

const _ready = ThrottleReading(
  state: ThrottleState.reduced,
  close: 35877,
  ma20: 36410,
  threshold: 35600,
  lastBreakDate: null,
  tradingDaysSinceBreak: null,
  lookbackTradingDays: 80,
);

CloseSummaryRow _row(
  String symbol, {
  String? groupName,
  int? groupId,
  GroupRole role = GroupRole.other,
  RowDataStatus status = RowDataStatus.ok,
  List<SummaryEvent> events = const [],
  HoldingCheck? holding,
  StrongListCheck? strongList,
  ChipCheck? chip,
  int? thermometerStreak,
  bool thermometerStreakAtLeast = false,
  double changePct = 0.76,
}) => CloseSummaryRow(
  symbol: symbol,
  name: '名$symbol',
  market: 'TWSE',
  groupId: groupId,
  groupName: groupName,
  role: role,
  status: status,
  close: status == RowDataStatus.ok ? 530 : null,
  changePct: status == RowDataStatus.ok ? changePct : null,
  volumeShares: status == RowDataStatus.ok ? 12000000 : null,
  biasPct: status == RowDataStatus.ok ? 4.2 : null,
  strongList: status == RowDataStatus.ok
      ? (strongList ??
            const StrongListCheck(
              ret20: CheckOutcome.pass,
              limitUpIn20: CheckOutcome.insufficient,
              avgVolume20: CheckOutcome.pass,
              aboveMa20: CheckOutcome.fail,
            ))
      : null,
  prerequisites: status == RowDataStatus.ok
      ? const EntryPrerequisites(
          moving: CheckOutcome.pass,
          bias: CheckOutcome.pass,
          revenue: CheckOutcome.fail,
          dayVolume: CheckOutcome.pass,
          biasPct: 4.2,
        )
      : null,
  chip: chip,
  holding: holding,
  thermometerStreak: thermometerStreak,
  thermometerStreakAtLeast: thermometerStreakAtLeast,
  events: events,
);

CloseSummary _summary({
  DateTime? dataDate,
  List<CloseSummarySection>? sections,
  Set<String> pricePending = const {},
  Set<String> institutionalPending = const {},
  bool indexReady = true,
  ThrottleReading? throttle = _ready,
  bool strongListGroupMissing = false,
}) => CloseSummary(
  dataDate: dataDate ?? _d,
  pricePendingMarkets: pricePending,
  institutionalPendingMarkets: institutionalPending,
  indexReady: indexReady,
  throttle: indexReady ? throttle : null,
  strongListGroupMissing: strongListGroupMissing,
  sections:
      sections ??
      [
        CloseSummarySection(
          isHoldings: false,
          groupId: null,
          groupName: null,
          rows: [_row('2330')],
        ),
      ],
);

CloseSummarySection _ungrouped(List<CloseSummaryRow> rows) =>
    CloseSummarySection(
      isHoldings: false,
      groupId: null,
      groupName: null,
      rows: rows,
    );

HoldingCheck _holdingOf({
  int? days = 3,
  TimeStopState? timeStop = TimeStopState.running,
  double? stopPrice = 488,
}) => HoldingCheck(
  entryDate: DateTime(2026, 11, 14),
  quantity: 120,
  avgCost: 525,
  stopPrice: stopPrice,
  oneR: stopPrice == null ? null : 525 - stopPrice,
  tradingDaysHeld: days,
  timeStop: timeStop,
  closePrice: 530,
  unrealizedPnl: 600,
  unrealizedPct: 0.95,
);

const _sealedChip = ChipCheck(
  foreignNetShares: 3061000,
  trustNetShares: -1817000,
  foreignStreak: 3,
  trustStreak: -1,
  sealedBy: ChipParty.foreign,
  opposed: true,
);

/// 畫面上不該出現沒翻譯的鍵或佔位符
void _expectNoRawKeys() {
  expect(find.textContaining('closeSummary.'), findsNothing);
  expect(find.textContaining('{'), findsNothing);
}

void main() {
  void viewport(WidgetTester tester, {double width = 1200}) {
    tester.view.physicalSize = Size(width, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  late GoRouter router;

  Future<void> pump(
    WidgetTester tester,
    CloseSummary? summary, {
    bool english = false,
    AppClock? clock,
    Future<CloseSummary?> Function()? load,
  }) async {
    router = GoRouter(
      initialLocation: AppRoutes.closeSummary,
      routes: [
        GoRoute(
          path: AppRoutes.closeSummary,
          builder: (_, _) => const CloseSummaryScreen(),
        ),
        GoRoute(
          path: AppRoutes.stockDetailTemplate,
          builder: (_, state) =>
              Text('detail ${state.pathParameters['symbol']}'),
        ),
        GoRoute(
          path: AppRoutes.market,
          builder: (_, _) => const Text('market'),
        ),
      ],
    );
    await tester.pumpWidget(
      buildProviderTestApp(
        const SizedBox(),
        router: router,
        zhTranslations: !english,
        enTranslations: english,
        overrides: [
          closeSummaryProvider.overrideWith(
            (ref) => load != null ? load() : Future.value(summary),
          ),
          appClockProvider.overrideWithValue(clock ?? _clock),
        ],
      ),
    );
    // 空狀態元件有持續播放的動畫，不能用 pumpAndSettle
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('頁首：資料日、法人分市場、油門與最近一次收破', (tester) async {
    viewport(tester);
    await pump(
      tester,
      _summary(
        institutionalPending: const {'TPEx'},
        throttle: const ThrottleReading(
          state: ThrottleState.reduced,
          close: 35877,
          ma20: 36410,
          threshold: 35600,
          lastBreakDate: null,
          tradingDaysSinceBreak: null,
          lookbackTradingDays: 80,
        ),
      ),
    );
    expect(find.textContaining('11/19 收盤'), findsOneWidget);
    expect(find.textContaining('法人：上櫃未到'), findsOneWidget);
    expect(find.textContaining('油門：小量'), findsOneWidget);
    expect(find.textContaining('近 80 個交易日內沒有收破 5 日門檻'), findsOneWidget);
  });

  testWidgets('頁首：最近一次收破的日期與交易日數', (tester) async {
    viewport(tester);
    await pump(
      tester,
      _summary(
        throttle: ThrottleReading(
          state: ThrottleState.flat,
          close: 35000,
          ma20: 36410,
          threshold: 35600,
          lastBreakDate: DateTime(2026, 11, 12),
          tradingDaysSinceBreak: 5,
          lookbackTradingDays: 80,
        ),
      ),
    );
    expect(find.textContaining('油門：空手'), findsOneWidget);
    expect(find.textContaining('11/12（5 個交易日前）'), findsOneWidget);
  });

  testWidgets('頁首：加權指數未到時不寫油門', (tester) async {
    viewport(tester);
    await pump(tester, _summary(indexReady: false));
    expect(find.textContaining('加權指數未到'), findsOneWidget);
    expect(find.textContaining('油門：'), findsNothing);
  });

  testWidgets('區段依序：持股、強者榜、未分組', (tester) async {
    viewport(tester);
    await pump(
      tester,
      _summary(
        sections: [
          CloseSummarySection(
            isHoldings: true,
            groupId: null,
            groupName: null,
            rows: [_row('A')],
          ),
          CloseSummarySection(
            isHoldings: false,
            groupId: 11,
            groupName: '強者榜',
            rows: [_row('B', groupId: 11, groupName: '強者榜')],
          ),
          CloseSummarySection(
            isHoldings: false,
            groupId: null,
            groupName: null,
            rows: [_row('C')],
          ),
        ],
      ),
    );
    final holdings = tester.getTopLeft(find.text('持股')).dy;
    final strong = tester.getTopLeft(find.text('強者榜')).dy;
    final ungrouped = tester.getTopLeft(find.text('未分組')).dy;
    expect(holdings, lessThan(strong));
    expect(strong, lessThan(ungrouped));
  });

  testWidgets('事件文字與資料不足；待處理與資訊用不同樣式', (tester) async {
    viewport(tester);
    await pump(
      tester,
      _summary(
        sections: [
          CloseSummarySection(
            isHoldings: false,
            groupId: null,
            groupName: null,
            rows: [
              _row(
                '2330',
                events: const [
                  SummaryEvent(SummaryEventKind.belowMaStreak, days: 3),
                  SummaryEvent(SummaryEventKind.structureB, supportPeriod: 10),
                  SummaryEvent(SummaryEventKind.sectorCooling, industry: '航運業'),
                  SummaryEvent(SummaryEventKind.limitUp),
                ],
              ),
            ],
          ),
        ],
      ),
    );
    expect(find.text('連 3 日收破月線'), findsOneWidget);
    expect(find.text('結構 B 回測 10 日線'), findsOneWidget);
    expect(find.text('族群退燒：航運業'), findsOneWidget);
    expect(find.text('漲停'), findsOneWidget);
    expect(find.textContaining('資料不足'), findsWidgets);
    expect(
      find.byKey(const ValueKey('closeSummary.chip.actionable')),
      findsNWidgets(3),
    );
    expect(
      find.byKey(const ValueKey('closeSummary.chip.info')),
      findsOneWidget,
    );
  });

  testWidgets('持股行與籌碼章、對做', (tester) async {
    viewport(tester);
    await pump(
      tester,
      _summary(
        sections: [
          CloseSummarySection(
            isHoldings: true,
            groupId: null,
            groupName: null,
            rows: [
              _row(
                '2408',
                chip: const ChipCheck(
                  foreignNetShares: 3061000,
                  trustNetShares: -1817000,
                  foreignStreak: 3,
                  trustStreak: -1,
                  sealedBy: ChipParty.foreign,
                  opposed: true,
                ),
                holding: HoldingCheck(
                  entryDate: DateTime(2026, 11, 14),
                  quantity: 120,
                  avgCost: 525,
                  stopPrice: 488,
                  oneR: 37,
                  tradingDaysHeld: 3,
                  timeStop: TimeStopState.running,
                  closePrice: 530,
                  unrealizedPnl: 600,
                  unrealizedPct: 0.95,
                ),
              ),
            ],
          ),
        ],
      ),
    );
    expect(find.textContaining('成本守門價 488.00'), findsOneWidget);
    expect(find.textContaining('持有第 3 天／共 8 天'), findsOneWidget);
    expect(find.textContaining('籌碼章 ✓（外資連 3）'), findsOneWidget);
    expect(find.textContaining('對做 → 暫緩'), findsOneWidget);
    expect(find.textContaining('外資 +3,061 張'), findsOneWidget);
  });

  testWidgets('找不到強者榜分組 → 頁首說明', (tester) async {
    viewport(tester);
    await pump(tester, _summary(strongListGroupMissing: true));
    expect(find.textContaining('找不到「強者榜」分組'), findsOneWidget);
  });

  testWidgets('行情未到與沒有成交只寫狀態', (tester) async {
    viewport(tester);
    await pump(
      tester,
      _summary(
        pricePending: const {'TPEx'},
        sections: [
          CloseSummarySection(
            isHoldings: false,
            groupId: null,
            groupName: null,
            rows: [
              _row('P1', status: RowDataStatus.marketPending),
              _row('N1', status: RowDataStatus.noTrade),
            ],
          ),
        ],
      ),
    );
    expect(find.textContaining('上櫃行情未到'), findsOneWidget);
    expect(find.text('行情未到'), findsOneWidget);
    expect(find.text('資料日沒有成交'), findsOneWidget);
  });

  testWidgets('點一列 → 該股詳情', (tester) async {
    viewport(tester);
    await pump(tester, _summary());
    await tester.tap(find.textContaining('名2330'));
    await tester.pumpAndSettle();
    expect(router.state.matchedLocation, AppRoutes.stockDetail('2330'));
  });

  testWidgets('沒有價格資料 → 空狀態', (tester) async {
    viewport(tester);
    await pump(tester, null);
    expect(find.text('還沒有價格資料'), findsOneWidget);
  });

  testWidgets('沒有自選也沒有持股 → 空狀態', (tester) async {
    viewport(tester);
    await pump(tester, _summary(sections: const []));
    expect(find.text('還沒有自選或持股'), findsOneWidget);
  });

  testWidgets('摘要算好之後時間過了 16:00 還沒更新 → 頁首改寫資料落後', (tester) async {
    viewport(tester);
    // 摘要在週四 10:00 算的（等今天），現在週四 18:00、資料仍是週三
    await pump(
      tester,
      CloseSummary(
        dataDate: DateTime(2026, 11, 18),
        pricePendingMarkets: const {},
        institutionalPendingMarkets: const {},
        indexReady: true,
        throttle: _ready,
        strongListGroupMissing: false,
        sections: [
          CloseSummarySection(
            isHoldings: false,
            groupId: null,
            groupName: null,
            rows: [_row('2330')],
          ),
        ],
      ),
      clock: _FixedClock(DateTime(2026, 11, 19, 18)),
    );
    expect(find.textContaining('資料落後'), findsOneWidget);
    expect(find.textContaining('15:30 更新後才有'), findsNothing);
  });

  testWidgets('英文 390 寬不溢位', (tester) async {
    viewport(tester, width: 390);
    await pump(
      tester,
      _summary(
        institutionalPending: const {'TPEx'},
        pricePending: const {'TPEx'},
        strongListGroupMissing: true,
        sections: [
          CloseSummarySection(
            isHoldings: true,
            groupId: null,
            groupName: null,
            rows: [
              _row(
                '2408',
                chip: const ChipCheck(
                  foreignNetShares: 3061000,
                  trustNetShares: -1817000,
                  foreignStreak: 3,
                  trustStreak: -1,
                  sealedBy: ChipParty.foreign,
                  opposed: true,
                ),
                holding: HoldingCheck(
                  entryDate: DateTime(2026, 11, 14),
                  quantity: 120,
                  avgCost: 525,
                  stopPrice: 488,
                  oneR: 37,
                  tradingDaysHeld: 3,
                  timeStop: TimeStopState.running,
                  closePrice: 530,
                  unrealizedPnl: 600,
                  unrealizedPct: 0.95,
                ),
                events: [
                  for (final kind in SummaryEventKind.values)
                    SummaryEvent(
                      kind,
                      days: 3,
                      supportPeriod: 10,
                      industry: '其他電子類',
                    ),
                ],
              ),
              _row('T1', role: GroupRole.thermometer, thermometerStreak: -12),
            ],
          ),
        ],
      ),
      english: true,
    );
    expect(tester.takeException(), isNull);
    _expectNoRawKeys();
  });

  testWidgets('持股列的每一行文字（量、法人、成本、守門價、條件、乖離、籌碼章）', (tester) async {
    viewport(tester);
    await pump(
      tester,
      _summary(
        sections: [
          CloseSummarySection(
            isHoldings: true,
            groupId: null,
            groupName: null,
            rows: [_row('2408', chip: _sealedChip, holding: _holdingOf())],
          ),
        ],
      ),
    );
    expect(find.text('12,000 張・外資 +3,061 張（連買 3）・投信 -1,817 張'), findsOneWidget);
    expect(find.text('成本 525.00・120 股・+600 元（+0.95%）'), findsOneWidget);
    expect(find.text('成本守門價 488.00（距 -7.92%）・持有第 3 天／共 8 天'), findsOneWidget);
    expect(find.text('強者榜條件 2/4・未過：近月漲停（資料不足）、站上月線'), findsOneWidget);
    expect(find.text('乖離 +4.2%・籌碼章 ✓（外資連 3）・對做 → 暫緩'), findsOneWidget);
    expect(find.text('前提條件未過：營收年增'), findsOneWidget);
    _expectNoRawKeys();
  });

  testWidgets('頁首：法人已到、全開與指數明細', (tester) async {
    viewport(tester);
    await pump(
      tester,
      _summary(
        throttle: const ThrottleReading(
          state: ThrottleState.full,
          close: 36500,
          ma20: 36410,
          threshold: 36700,
          lastBreakDate: null,
          tradingDaysSinceBreak: null,
          lookbackTradingDays: 80,
        ),
      ),
    );
    expect(find.text('法人：已到'), findsOneWidget);
    expect(find.text('油門：全開'), findsOneWidget);
    expect(find.text('加權 36,500，月線 36,410 之上；5 日門檻 36,700 之下'), findsOneWidget);
    _expectNoRawKeys();
  });

  testWidgets('頁首：資料日當天收破 → 寫「資料日當天」', (tester) async {
    viewport(tester);
    await pump(
      tester,
      _summary(
        throttle: ThrottleReading(
          state: ThrottleState.flat,
          close: 35000,
          ma20: 36410,
          threshold: 35600,
          lastBreakDate: _d,
          tradingDaysSinceBreak: 0,
          lookbackTradingDays: 80,
        ),
      ),
    );
    expect(find.text('資料日當天收破 5 日門檻'), findsOneWidget);
  });

  testWidgets('交易日 10:00、資料是前一個交易日 → 寫等今天的更新', (tester) async {
    viewport(tester);
    await pump(
      tester,
      _summary(dataDate: DateTime(2026, 11, 18)),
      clock: _FixedClock(DateTime(2026, 11, 19, 10)),
    );
    expect(find.text('今天的資料 15:30 更新後才有'), findsOneWidget);
    expect(find.textContaining('資料落後'), findsNothing);
  });

  testWidgets('資料落後的日期寫資料日', (tester) async {
    viewport(tester);
    await pump(
      tester,
      _summary(dataDate: DateTime(2026, 11, 17)),
      clock: _FixedClock(DateTime(2026, 11, 19, 18)),
    );
    expect(find.text('資料落後：最新是 11/17'), findsOneWidget);
  });

  testWidgets('漲跌幅的顏色照股價紅綠', (tester) async {
    viewport(tester);
    await pump(
      tester,
      _summary(
        sections: [
          _ungrouped([
            _row('UP', changePct: 1.23),
            _row('DN', changePct: -2.34),
          ]),
        ],
      ),
    );
    Color? colorOf(String text) =>
        tester.widget<Text>(find.text(text)).style?.color;
    expect(colorOf('+1.23%'), PriceColors.forChange(1.23, Brightness.light));
    expect(colorOf('-2.34%'), PriceColors.forChange(-2.34, Brightness.light));
  });

  testWidgets('溫度計：月線之上第幾天、之下至少幾天，不寫強者榜條件', (tester) async {
    viewport(tester);
    await pump(
      tester,
      _summary(
        sections: [
          _ungrouped([
            _row('T1', role: GroupRole.thermometer, thermometerStreak: 12),
            _row(
              'T2',
              role: GroupRole.thermometer,
              thermometerStreak: -5,
              thermometerStreakAtLeast: true,
            ),
            _row(
              'T3',
              role: GroupRole.thermometer,
              thermometerStreak: 30,
              thermometerStreakAtLeast: true,
            ),
          ]),
        ],
      ),
    );
    expect(find.text('月線之上第 12 天'), findsOneWidget);
    expect(find.text('月線之下至少 5 天'), findsOneWidget);
    expect(find.text('月線之上至少 30 天'), findsOneWidget);
    expect(find.textContaining('強者榜條件'), findsNothing);
  });

  testWidgets('除名重審不寫前提條件；法人未到寫在列上', (tester) async {
    viewport(tester);
    await pump(
      tester,
      _summary(
        sections: [
          _ungrouped([_row('R1', role: GroupRole.delistReview)]),
        ],
      ),
    );
    expect(find.textContaining('前提條件未過'), findsNothing);
    expect(find.textContaining('強者榜條件'), findsOneWidget);
    expect(find.text('12,000 張・法人未到'), findsOneWidget);
  });

  testWidgets('持股：已達 +1R、建立當天、超過 8 天只寫第幾天', (tester) async {
    viewport(tester);
    await pump(
      tester,
      _summary(
        sections: [
          CloseSummarySection(
            isHoldings: true,
            groupId: null,
            groupName: null,
            rows: [
              _row('H1', holding: _holdingOf(timeStop: TimeStopState.lifted)),
              _row('H2', holding: _holdingOf(days: 0)),
              _row(
                'H3',
                holding: _holdingOf(days: 12, timeStop: TimeStopState.expired),
              ),
              _row('H4', holding: _holdingOf(stopPrice: null, timeStop: null)),
            ],
          ),
        ],
      ),
    );
    expect(find.textContaining('已達 +1R'), findsOneWidget);
    expect(find.textContaining('建立當天'), findsOneWidget);
    expect(find.textContaining('持有第 12 天'), findsOneWidget);
    expect(find.textContaining('共 8 天'), findsNothing);
    expect(find.text('成本守門價資料不足・持有第 3 天'), findsOneWidget);
  });

  testWidgets('不到半張的買賣超留一位小數，不寫成 ±0 張', (tester) async {
    viewport(tester);
    await pump(
      tester,
      _summary(
        sections: [
          _ungrouped([
            _row(
              'S1',
              chip: const ChipCheck(
                foreignNetShares: -400,
                trustNetShares: 0,
                foreignStreak: -1,
                trustStreak: 0,
                sealedBy: null,
                opposed: false,
              ),
            ),
          ]),
        ],
      ),
    );
    expect(find.text('12,000 張・外資 -0.4 張・投信 0 張'), findsOneWidget);
  });

  testWidgets('點「大盤總覽」→ 大盤總覽頁', (tester) async {
    viewport(tester);
    await pump(tester, _summary());
    await tester.tap(find.textContaining('大盤總覽'));
    await tester.pumpAndSettle();
    expect(router.state.matchedLocation, AppRoutes.market);
  });

  // RefreshIndicator 要拉過畫面高度的 25%（3000 × 0.25）才觸發
  testWidgets('錯誤時按重試、資料頁下拉 → 都會重讀', (tester) async {
    viewport(tester);
    var calls = 0;
    await pump(
      tester,
      null,
      load: () async {
        calls++;
        if (calls == 1) throw StateError('boom');
        return _summary();
      },
    );
    expect(calls, 1);
    await tester.tap(find.text('重試'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(calls, 2);
    expect(find.textContaining('名2330'), findsOneWidget);

    await tester.fling(find.byType(ListView), const Offset(0, 1500), 1000);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(calls, 3);
  });

  testWidgets('下拉時重讀失敗 → 顯示錯誤頁，不丟出未處理的例外', (tester) async {
    viewport(tester);
    var calls = 0;
    await pump(
      tester,
      null,
      load: () async {
        calls++;
        if (calls == 2) throw StateError('boom');
        return _summary();
      },
    );
    await tester.fling(find.byType(ListView), const Offset(0, 1500), 1000);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(calls, 2);
    expect(tester.takeException(), isNull);
    expect(find.text('重試'), findsOneWidget);
  });

  testWidgets('損益捨入成 0 → 寫「0 元」不寫「-0 元」', (tester) async {
    viewport(tester);
    await pump(
      tester,
      _summary(
        sections: [
          CloseSummarySection(
            isHoldings: true,
            groupId: null,
            groupName: null,
            rows: [
              _row(
                'Z0',
                holding: HoldingCheck(
                  entryDate: DateTime(2026, 11, 14),
                  quantity: 120,
                  avgCost: 525.3333,
                  stopPrice: 488,
                  oneR: 37.3333,
                  tradingDaysHeld: 3,
                  timeStop: TimeStopState.running,
                  closePrice: 525.33,
                  unrealizedPnl: -0.4,
                  unrealizedPct: -0.0006,
                ),
              ),
            ],
          ),
        ],
      ),
    );
    expect(find.text('成本 525.33・120 股・0 元（0.00%）'), findsOneWidget);
  });

  testWidgets('中文：全部事件都有翻譯、沒有漏掉的鍵或佔位符', (tester) async {
    viewport(tester);
    await pump(
      tester,
      _summary(
        sections: [
          _ungrouped([
            _row(
              'E1',
              events: [
                for (final kind in SummaryEventKind.values)
                  SummaryEvent(
                    kind,
                    days: 3,
                    supportPeriod: 10,
                    industry: '其他電子類',
                  ),
              ],
            ),
          ]),
        ],
      ),
    );
    expect(
      find.byKey(const ValueKey('closeSummary.chip.actionable')),
      findsNWidgets(
        SummaryEventKind.values.where((k) => k.isActionable).length,
      ),
    );
    _expectNoRawKeys();
  });

  testWidgets('入口卡讓摘要一直活著時，點進摘要頁會重算一次', (tester) async {
    viewport(tester);
    var calls = 0;
    final appRouter = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(body: CloseSummaryEntryCard()),
        ),
        GoRoute(
          path: AppRoutes.closeSummary,
          builder: (_, _) => const CloseSummaryScreen(),
        ),
      ],
    );
    await tester.pumpWidget(
      buildProviderTestApp(
        const SizedBox(),
        router: appRouter,
        zhTranslations: true,
        overrides: [
          closeSummaryProvider.overrideWith((ref) {
            calls++;
            return SynchronousFuture(_summary());
          }),
          appClockProvider.overrideWithValue(_clock),
        ],
      ),
    );
    await tester.pump();
    expect(calls, 1);

    appRouter.push(AppRoutes.closeSummary);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(calls, 2, reason: 'App 外的每日更新不會通知 App，進頁時要重讀');
    expect(find.textContaining('名2330'), findsOneWidget);
  });
}
