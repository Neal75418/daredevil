import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/domain/services/chip_anomaly_service.dart'
    show ChipAnomaly, ChipAnomalyType, ChipSeverity, kZeroInsiderTransfer;
import 'package:daredevil/presentation/providers/market_overview_provider.dart'
    show WarningCounts;
import 'package:daredevil/presentation/widgets/market_dashboard/chip_anomaly_row.dart';

import '../../../helpers/widget_test_helpers.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Test helper
// ─────────────────────────────────────────────────────────────────────────────

ChipAnomaly _anomaly(
  String symbol,
  String name, {
  ChipAnomalyType type = ChipAnomalyType.highPledge,
  ChipSeverity severity = ChipSeverity.high,
  String market = 'TWSE',
  String? keyValue = '65.5%',
}) {
  return ChipAnomaly(
    type: type,
    severity: severity,
    symbol: symbol,
    stockName: name,
    market: market,
    keyValue: keyValue,
  );
}

void main() {
  setUpAll(() async {
    await setupTestLocalization();
  });

  void widenViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(5000, 4000);
    addTearDown(() => tester.view.resetPhysicalSize());
  }

  group('ChipAnomalyRow', () {
    // ─────────────────────────────────────────────────────────────────────────
    // 空資料
    // ─────────────────────────────────────────────────────────────────────────

    testWidgets('空列表時不渲染任何內容', (tester) async {
      await tester.pumpWidget(
        buildTestApp(const ChipAnomalyRow(anomalies: [])),
      );

      expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
      expect(find.byType(Text), findsNothing);
    });

    // ─────────────────────────────────────────────────────────────────────────
    // 摘要橫幅
    // ─────────────────────────────────────────────────────────────────────────

    testWidgets('有異動時顯示摘要橫幅 icon', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(
        buildTestApp(ChipAnomalyRow(anomalies: [_anomaly('2330', '台積電')])),
      );

      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    });

    // ─────────────────────────────────────────────────────────────────────────
    // 個股資料顯示
    // ─────────────────────────────────────────────────────────────────────────

    testWidgets('股票代號與名稱顯示在畫面上', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(
        buildTestApp(ChipAnomalyRow(anomalies: [_anomaly('2330', '台積電')])),
      );

      expect(find.text('2330'), findsOneWidget);
      expect(find.text('台積電'), findsOneWidget);
    });

    testWidgets('keyValue 顯示在畫面上', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(
        buildTestApp(
          ChipAnomalyRow(
            anomalies: [_anomaly('2330', '台積電', keyValue: '65.5%')],
          ),
        ),
      );

      expect(find.text('65.5%'), findsOneWidget);
    });

    testWidgets('個股列壓縮為單行，不再顯示白話說明句', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(
        buildTestApp(
          ChipAnomalyRow(
            anomalies: [_anomaly('2330', '台積電', keyValue: '65.5%')],
          ),
        ),
      );

      // 代號/名稱/數值單行仍在，但原本逐檔重複的白話說明句已移除
      // （分類標頭 subtitle 已解釋類型意義，不需每檔重複一次）。
      expect(find.text('2330'), findsOneWidget);
      expect(
        find.textContaining('marketOverview.chipAnomaly.desc'),
        findsNothing,
      );
    });

    // ─────────────────────────────────────────────────────────────────────────
    // kZeroInsiderTransfer
    // ─────────────────────────────────────────────────────────────────────────

    testWidgets('insiderTransfer with kZeroInsiderTransfer 不崩潰', (
      tester,
    ) async {
      widenViewport(tester);
      await tester.pumpWidget(
        buildTestApp(
          ChipAnomalyRow(
            anomalies: [
              _anomaly(
                '2330',
                '台積電',
                type: ChipAnomalyType.insiderTransfer,
                severity: ChipSeverity.medium,
                keyValue: kZeroInsiderTransfer,
              ),
            ],
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('2330'), findsOneWidget);
    });

    // ─────────────────────────────────────────────────────────────────────────
    // 點擊回呼
    // ─────────────────────────────────────────────────────────────────────────

    testWidgets('點擊個股觸發 onStockTap 並傳入正確代號', (tester) async {
      widenViewport(tester);
      String? tappedSymbol;

      await tester.pumpWidget(
        buildTestApp(
          ChipAnomalyRow(
            anomalies: [_anomaly('2330', '台積電')],
            onStockTap: (symbol) => tappedSymbol = symbol,
          ),
        ),
      );

      await tester.tap(find.text('2330'));
      await tester.pump();

      expect(tappedSymbol, '2330');
    });

    testWidgets('onStockTap 為 null 時點擊不崩潰', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(
        buildTestApp(ChipAnomalyRow(anomalies: [_anomaly('2330', '台積電')])),
      );

      await tester.tap(find.text('2330'));
      expect(tester.takeException(), isNull);
    });

    // ─────────────────────────────────────────────────────────────────────────
    // 類型區塊：徽章與顯示上限
    // ─────────────────────────────────────────────────────────────────────────

    testWidgets('totalCount 徽章顯示實際總數，不受顯示上限（3 筆）影響', (tester) async {
      widenViewport(tester);

      // 5 筆相同類型，widget 最多顯示 3 筆，但徽章應顯示 5
      final anomalies = List.generate(
        5,
        (i) => _anomaly('${2330 + i}', '股票$i'),
      );

      await tester.pumpWidget(
        buildTestApp(ChipAnomalyRow(anomalies: anomalies)),
      );

      // 徽章顯示總數 '5'
      expect(find.text('5'), findsOneWidget);
    });

    testWidgets('超過 3 筆時只顯示 3 筆個股', (tester) async {
      widenViewport(tester);

      final anomalies = List.generate(
        5,
        (i) => _anomaly('${2330 + i}', '股票$i'),
      );

      await tester.pumpWidget(
        buildTestApp(ChipAnomalyRow(anomalies: anomalies)),
      );

      // 5 筆只顯示前 3 筆（2330, 2331, 2332）
      expect(find.text('2330'), findsOneWidget);
      expect(find.text('2332'), findsOneWidget);
      expect(find.text('2334'), findsNothing);
    });

    // ─────────────────────────────────────────────────────────────────────────
    // 多類型分群
    // ─────────────────────────────────────────────────────────────────────────

    testWidgets('不同類型分別渲染各自區塊', (tester) async {
      widenViewport(tester);

      await tester.pumpWidget(
        buildTestApp(
          ChipAnomalyRow(
            anomalies: [
              _anomaly('2330', '台積電', type: ChipAnomalyType.highPledge),
              _anomaly(
                '2317',
                '鴻海',
                type: ChipAnomalyType.shortSurge,
                severity: ChipSeverity.medium,
                keyValue: '4.0倍',
              ),
            ],
          ),
        ),
      );

      expect(find.byIcon(Icons.lock_outline_rounded), findsOneWidget);
      expect(find.byIcon(Icons.trending_down_rounded), findsOneWidget);
    });

    // ─────────────────────────────────────────────────────────────────────────
    // 深色模式
    // ─────────────────────────────────────────────────────────────────────────

    testWidgets('深色模式正常渲染', (tester) async {
      widenViewport(tester);

      await tester.pumpWidget(
        buildTestApp(
          ChipAnomalyRow(anomalies: [_anomaly('2330', '台積電')]),
          brightness: Brightness.dark,
        ),
      );

      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
      expect(find.text('2330'), findsOneWidget);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // 注意/處置徽章併入標題列
  // ─────────────────────────────────────────────────────────────────────────

  group('ChipAnomalyRow 注意/處置徽章併入標題列', () {
    testWidgets('warningCounts 有值時，標題列顯示注意/處置徽章', (tester) async {
      widenViewport(tester);
      await tester.pumpWidget(
        buildTestApp(
          ChipAnomalyRow(
            anomalies: [_anomaly('2330', '台積電')],
            warningCounts: const WarningCounts(attention: 3, disposal: 1),
          ),
        ),
      );

      expect(
        find.textContaining('marketOverview.attentionCount'),
        findsOneWidget,
      );
      expect(
        find.textContaining('marketOverview.disposalCount'),
        findsOneWidget,
      );
    });

    testWidgets('anomalies 為空但 warningCounts 有值時，標題列徽章仍渲染（不隨獨立列一起消失）', (
      tester,
    ) async {
      widenViewport(tester);
      await tester.pumpWidget(
        buildTestApp(
          const ChipAnomalyRow(
            anomalies: [],
            warningCounts: WarningCounts(attention: 2),
          ),
        ),
      );

      expect(find.text('marketOverview.chipAnomaly.title'), findsOneWidget);
      expect(
        find.textContaining('marketOverview.attentionCount'),
        findsOneWidget,
      );
      // 無籌碼異動資料 → 摘要橫幅（含 warning_amber icon）不出現
      expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
    });

    testWidgets('anomalies 與 warningCounts 皆空（或 0）時仍不渲染任何內容', (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          const ChipAnomalyRow(anomalies: [], warningCounts: WarningCounts()),
        ),
      );

      expect(find.byType(Text), findsNothing);
    });
  });

  group('per-detector 失敗註記(2026-08-29 靜默稽核 #4)', () {
    testWidgets('🚨 有偵測失敗 → 區塊現身並顯示「N 類未偵測」', (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          const ChipAnomalyRow(anomalies: [], failedDetectorCount: 2),
        ),
      );
      expect(
        find.text('marketOverview.chipAnomaly.partialFail'),
        findsOneWidget,
        reason: '零異動+有失敗:安靜的市場與壞掉的偵測不可同貌',
      );
    });

    testWidgets('🚨 只有 ETF 過濾失效 → 掛「可能混入 ETF」,不得說「未偵測」', (tester) async {
      // review 更正:ETF 過濾失效時榜單是完整的,問題方向相反——會多出
      // 不該在榜上的 ETF。借「N 類未偵測」文案為假陳述(最壞會寫出
      // 「6 類未偵測」但類別總共 5 類)。
      await tester.pumpWidget(
        buildTestApp(
          const ChipAnomalyRow(anomalies: [], etfFilterUnavailable: true),
        ),
      );
      expect(
        find.text('marketOverview.chipAnomaly.etfFilterFail'),
        findsOneWidget,
      );
      expect(
        find.text('marketOverview.chipAnomaly.partialFail'),
        findsNothing,
        reason: '沒有任何類別「未偵測」,不得誤用該文案',
      );
    });

    testWidgets('無異動無失敗 → 區塊隱藏(既有行為不變)', (tester) async {
      await tester.pumpWidget(
        buildTestApp(const ChipAnomalyRow(anomalies: [])),
      );
      expect(find.text('marketOverview.chipAnomaly.partialFail'), findsNothing);
      expect(find.text('marketOverview.chipAnomaly.title'), findsNothing);
    });
  });
}
