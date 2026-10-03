import 'package:daredevil/core/constants/rule_params.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/domain/models/models.dart';
import 'package:daredevil/domain/services/rule_engine.dart';
import 'package:daredevil/domain/services/rules/stock_rules.dart';
import 'package:daredevil/domain/services/rules/candlestick_rules.dart';
import 'package:daredevil/domain/services/rules/indicator_rules.dart';
import 'package:daredevil/domain/services/rules/technical_rules.dart';
import 'package:daredevil/domain/services/rules/fundamental_scan_rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late RuleEngine ruleEngine;

  setUp(() {
    ruleEngine = RuleEngine(
      customRules: [
        const WeakToStrongRule(),
        const DojiRule(),
        const Week52HighRule(),
        const KDGoldenCrossRule(),
        const PEUndervaluedRule(),
      ],
    );
  });

  group('KDGoldenCrossRule', () {
    test('triggers on cross', () async {
      // 建構滿足以下條件的價格資料：
      // 1. 最後一天成交量 > 5 日均量（volume spike）
      // 2. 最後一天漲幅 >= 1%（close 102 vs prev 100）
      final prices = List.generate(20, (i) {
        final isLastDay = i == 19;
        const baseClose = 100.0;
        return DailyPriceEntry(
          symbol: '2330',
          date: DateTime.now().subtract(Duration(days: 20 - i)),
          open: baseClose,
          close: isLastDay ? 102.0 : baseClose,
          high: isLastDay ? 103.0 : baseClose + 1,
          low: baseClose - 1,
          volume: isLastDay ? 5000 : 1000,
        );
      }).toList();

      // 模擬 KD 指標：昨日 K < D（15 < 18），今日 K > D（22 > 20）
      const indicators = TechnicalIndicators(
        kdK: 22,
        kdD: 20,
        prevKdK: 15,
        prevKdD: 18,
        rsi: 50,
      );

      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
        indicators: indicators,
      );

      final reasons = ruleEngine.evaluateStock(
        context,
        StockData(
          symbol: '2330',
          prices: prices,
          dividends: DividendContext.noEvents,
        ),
      );

      expect(reasons.any((r) => r.type == ReasonType.kdGoldenCross), isTrue);
    });
  });

  group('PEUndervaluedRule', () {
    test('triggers on low PE', () async {
      final valuation = StockValuationEntry(
        symbol: '2330',
        date: DateTime.now(),
        per: 8.5,
        dividendYield: 4.0,
        pbr: 1.2,
      );

      // MA20 = (15×100 + 5×110) / 20 = 102.5; close=110 > 102.5
      final context = AnalysisContext(
        evaluationTime: DateTime(2025, 6, 1),
        trendState: TrendState.range,
        indicators: const TechnicalIndicators(ma20: 102.5),
      );

      // 需要至少 20 筆價格資料，且 close > MA20
      final prices = List.generate(25, (i) {
        final isRecent = i >= 20;
        return DailyPriceEntry(
          symbol: '2330',
          date: DateTime.now().subtract(Duration(days: 25 - i)),
          open: 100.0,
          close: isRecent ? 110.0 : 100.0,
          high: isRecent ? 112.0 : 102.0,
          low: 98.0,
          volume: 1000000,
        );
      });

      final reasons = ruleEngine.evaluateStock(
        context,
        StockData(
          symbol: '2330',
          prices: prices,
          latestValuation: valuation,
          dividends: DividendContext.noEvents,
        ),
      );

      expect(reasons.any((r) => r.type == ReasonType.peUndervalued), isTrue);
    });
  });
}
