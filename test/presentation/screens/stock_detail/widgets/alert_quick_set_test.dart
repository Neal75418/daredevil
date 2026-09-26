import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/constants/rule_params_alert.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/domain/services/alert/alert_target_calculator.dart';
import 'package:daredevil/presentation/screens/stock_detail/widgets/alert_quick_set.dart';

import '../../../../helpers/widget_test_helpers.dart';

/// 快捷提醒鈕(2026-08-07)。
///
/// 存在理由:使用者要「觸價後開始觀察」而非每次手打價位。app **只算不
/// 決定**——把 5MA/10MA/月線/20 日高/守門價算好放著,點哪個由使用者。
void main() {
  setUpAll(() async => setupTestLocalization());

  List<Ohlc> bars(int n) => [
    for (var i = 0; i < n; i++)
      Ohlc(high: 100 + i + 2, low: 100 + i - 2, close: 100 + i.toDouble()),
  ];

  void widen(WidgetTester tester) {
    tester.view.physicalSize = const Size(5000, 4000);
    addTearDown(tester.view.resetPhysicalSize);
  }

  testWidgets('資料足夠時列出全部五種快捷鈕,各自帶算好的價位', (tester) async {
    widen(tester);
    await tester.pumpWidget(
      buildTestApp(AlertQuickSet(bars: bars(30), onSelected: (_, _) {})),
    );
    // 五種:跌破5MA/跌破10MA/跌破月線/突破月線/突破20日高 + 守門價 = 6
    expect(find.byType(ActionChip), findsNWidgets(6));
    // 價位有顯示(5MA=127.0)
    // 精度須與提醒清單一致(2 位小數):同一個數字在按鈕與清單長得不一樣
    // 會侵蝕信任(2026-08-07 實機:chip 顯示 179.9、清單顯示 179.95)
    expect(find.textContaining('127.00'), findsOneWidget);
  });

  testWidgets('🚨 點擊回傳種類與價位——app 不自己建立,由呼叫端決定', (tester) async {
    widen(tester);
    AlertKind? kind;
    double? price;
    await tester.pumpWidget(
      buildTestApp(
        AlertQuickSet(
          bars: bars(30),
          onSelected: (k, t) {
            kind = k;
            price = t.price;
          },
        ),
      ),
    );
    await tester.tap(find.byType(ActionChip).first);
    await tester.pump();
    expect(kind, isNotNull);
    expect(price, isNotNull);
  });

  testWidgets('資料不足 → 只顯示算得出來的,不硬湊', (tester) async {
    widen(tester);
    await tester.pumpWidget(
      buildTestApp(AlertQuickSet(bars: bars(8), onSelected: (_, _) {})),
    );
    expect(find.byType(ActionChip), findsOneWidget); // 只有 5MA
  });

  testWidgets('完全無資料 → 整個區塊收起,不留空殼', (tester) async {
    widen(tester);
    await tester.pumpWidget(
      buildTestApp(AlertQuickSet(bars: const [], onSelected: (_, _) {})),
    );
    expect(find.byType(ActionChip), findsNothing);
    expect(tester.takeException(), isNull);
  });

  group('toOhlc 排序契約(2026-08-07 實機 bug 迴歸鎖)', () {
    DailyPriceEntry entry(DateTime d, double c) => DailyPriceEntry(
      symbol: '3231',
      date: d,
      open: c,
      high: c + 2,
      low: c - 2,
      close: c,
      volume: 1000,
    );

    test('🚨 不論輸入順序,輸出恆為升冪(最後一筆最新)', () {
      final old = entry(DateTime(2026, 1, 2), 120);
      final mid = entry(DateTime(2026, 5, 2), 150);
      final recent = entry(DateTime(2026, 8, 7), 183.5);

      for (final input in [
        [old, mid, recent], // 升冪(DAO 實際行為)
        [recent, mid, old], // 降冪
        [mid, recent, old], // 亂序
      ]) {
        final out = AlertQuickSet.toOhlc(input);
        expect(
          out.map((o) => o.close).toList(),
          [120, 150, 183.5],
          reason: '輸入 \${input.map((e) => e.close).toList()} 應一律排成升冪',
        );
      }
    });

    test('OHLC 缺值或收盤 ≤0 的列略過(停牌)', () {
      final ok = entry(DateTime(2026, 8, 7), 183.5);
      final zero = entry(DateTime(2026, 8, 6), 0);
      final nullHigh = DailyPriceEntry(
        symbol: '3231',
        date: DateTime(2026, 8, 5),
        open: 180,
        high: null,
        low: 178,
        close: 179,
        volume: 1000,
      );
      final out = AlertQuickSet.toOhlc([ok, zero, nullHigh]);
      expect(out.length, 1);
      expect(out.single.close, 183.5);
    });
  });

  group('🚨 條件已成立的種類不可設(設了會立刻觸發)', () {
    // 2026-08-07 實機(緯創 3231):現價 183.5 已在 5MA 189.4 之下、
    // 月線 166.3 之上——這兩顆若可點,設完立刻響一次就結束,是純噪音。
    // 改為停用並在標籤標明現況,讓這排按鈕同時是狀態讀數。
    testWidgets('已跌破的向下型、已突破的向上型 → 停用', (tester) async {
      widen(tester);
      await tester.pumpWidget(
        buildTestApp(
          AlertQuickSet(
            bars: bars(30), // 最新收盤 129
            currentPrice: 129,
            onSelected: (_, _) {},
          ),
        ),
      );
      // 5MA=127 → 現價 129 在其上,跌破尚未成立 → 可點
      final chips = tester.widgetList<ActionChip>(find.byType(ActionChip));
      final enabled = chips.where((c) => c.onPressed != null).length;
      final disabled = chips.length - enabled;
      expect(disabled, greaterThan(0), reason: '突破月線(119.5)已成立應被停用');
      expect(enabled, greaterThan(0), reason: '尚未成立的仍可點');
    });

    testWidgets('未提供現價時全部可點(不臆測狀態)', (tester) async {
      widen(tester);
      await tester.pumpWidget(
        buildTestApp(
          AlertQuickSet(
            bars: bars(30),
            currentPrice: null,
            onSelected: (_, _) {},
          ),
        ),
      );
      final chips = tester.widgetList<ActionChip>(find.byType(ActionChip));
      expect(chips.every((c) => c.onPressed != null), isTrue);
    });
  });

  group('🚨 已存在同種提醒 → 停用(2026-08-08 實機:同一顆點兩次建出兩筆)', () {
    testWidgets('existingTargets 命中的種類不可再點', (tester) async {
      widen(tester);
      await tester.pumpWidget(
        buildTestApp(
          AlertQuickSet(
            bars: bars(30),
            currentPrice: null, // 不給現價,單測 existingTargets 的效果
            existingTargets: {(AlertParams.typeBelow, 127.0)}, // 5MA
            onSelected: (_, _) {},
          ),
        ),
      );
      final chips = tester.widgetList<ActionChip>(find.byType(ActionChip));
      final disabled = chips.where((c) => c.onPressed == null).length;
      expect(disabled, 1, reason: '只有 5MA 那顆該停用——區間斷言會讓「六顆全停用」也過');
    });

    testWidgets('🚨 同價不同向:設了「跌破月線」不可連「突破月線」一起封死', (tester) async {
      // 2026-08-08 三次審查:breakBelowMa20 與 breakAboveMa20 的目標價
      // **完全相同**(都是 ma20),只有方向不同。原本去重只比價格,於是
      // 建了停損型的「跌破月線」之後,語意完全相反的「突破月線」
      // (回榜資格)會被一起停用,而且 UI 謊稱「已設定」——使用者不會
      // 發現自己被擋住。closes = 100..129 → ma20 = 119.5。
      widen(tester);
      await tester.pumpWidget(
        buildTestApp(
          AlertQuickSet(
            bars: bars(30),
            currentPrice: null,
            existingTargets: {(AlertParams.typeBelow, 119.5)},
            onSelected: (_, _) {},
          ),
        ),
      );
      final chips = tester.widgetList<ActionChip>(find.byType(ActionChip));
      final disabled = chips.where((c) => c.onPressed == null).length;
      expect(disabled, 1, reason: '只有「跌破月線」該停用;「突破月線」同價但反向,必須仍可點');
    });

    testWidgets('existingTargets 為空 → 不受影響', (tester) async {
      widen(tester);
      await tester.pumpWidget(
        buildTestApp(
          AlertQuickSet(
            bars: bars(30),
            // 不給現價:避免與「已成立」邏輯糾纏,單測 existingTargets
            currentPrice: null,
            existingTargets: const <(String, double)>{},
            onSelected: (_, _) {},
          ),
        ),
      );
      final chips = tester.widgetList<ActionChip>(find.byType(ActionChip));
      expect(chips.every((c) => c.onPressed != null), isTrue);
    });
  });

  group('🚨 盤中的資料陳舊提示(2026-08-08)', () {
    // 均線與「已成立」判斷都來自最後一根日線(每日更新 15:30 才跑),
    // 對今天盤中一無所知。盤中設提醒時,一個已經跌破的價位看起來仍可
    // 點,點下去會在 5 分鐘內立刻觸發、把一次性提醒燒掉。
    //
    // 刻意不讓 UI 抓即時報價修正:MIS 限流按 IP 算,launchd 的盤中檢查
    // (55 次/交易日)靠同一個額度活著。標示限制即可。
    testWidgets('盤中 → 顯示「以昨收判斷」警語', (tester) async {
      widen(tester);
      await tester.pumpWidget(
        buildTestApp(
          AlertQuickSet(
            bars: bars(30),
            // 2026-08-10 是週一,10:30 在 09:00~13:30 之內
            now: DateTime(2026, 8, 10, 10, 30),
            onSelected: (_, _) {},
          ),
        ),
      );
      expect(find.byKey(AlertQuickSet.staleWarningKey), findsOneWidget);
    });

    testWidgets('盤前/盤後 → 不顯示(資料本來就是最新的,不打擾)', (tester) async {
      widen(tester);
      await tester.pumpWidget(
        buildTestApp(
          AlertQuickSet(
            bars: bars(30),
            now: DateTime(2026, 8, 10, 20, 0), // 同一天晚上 8 點
            onSelected: (_, _) {},
          ),
        ),
      );
      expect(find.byKey(AlertQuickSet.staleWarningKey), findsNothing);
    });

    testWidgets('週末 → 不顯示', (tester) async {
      widen(tester);
      await tester.pumpWidget(
        buildTestApp(
          AlertQuickSet(
            bars: bars(30),
            now: DateTime(2026, 8, 8, 10, 30), // 週六同一時刻
            onSelected: (_, _) {},
          ),
        ),
      );
      expect(find.byKey(AlertQuickSet.staleWarningKey), findsNothing);
    });
  });
}
