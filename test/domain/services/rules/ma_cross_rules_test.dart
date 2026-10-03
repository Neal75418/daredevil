// MA 穿越事件 4 條規則(2026-07-31)。
//
// 站回月線/季線=修復期領先者偵測(V 轉後率先修復的股票,60D 報酬還是
// 負的進不了 B tab,落在 A/B 縫隙——這 2 條就是為那個縫隙生的);
// 跌破=持股風控。**刻意不加多頭 regime gate**:修復期偵測器的主場正是
// regime 未翻多時,跌破警示則在轉空時最需要——與回檔規則(接刀防護
// 要 gate)語境相反。neutral ±8 起步,校準實證判決升格或歸零。
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/constants/reason_type.dart';
import 'package:daredevil/core/constants/rule_enums.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/domain/models/analysis_context.dart';
import 'package:daredevil/domain/models/technical_indicators.dart';
import 'package:daredevil/domain/services/rules/ma_cross_rules.dart';
import 'package:daredevil/domain/services/rules/stock_rules.dart';
import 'package:daredevil/domain/models/dividend_context.dart';

void main() {
  List<DailyPriceEntry> pricesEndingWith({
    required double prevClose,
    required double close,
    int count = 65,
    String symbol = 'TEST',
  }) {
    return [
      for (var i = 0; i < count; i++)
        DailyPriceEntry(
          symbol: symbol,
          date: DateTime(2026, 1, 1).add(Duration(days: i)),
          open: 100,
          high: 101,
          low: 99,
          close: i == count - 1 ? close : (i == count - 2 ? prevClose : 100),
          volume: 1000,
        ),
    ];
  }

  AnalysisContext ctx({double? ma20, double? ma60}) => AnalysisContext(
    trendState: TrendState.range,
    evaluationTime: DateTime(2026, 3, 10),
    indicators: TechnicalIndicators(ma20: ma20, ma60: ma60),
  );

  group('ReclaimMa20Rule(站回月線)', () {
    const rule = ReclaimMa20Rule();

    test('昨收線下、今收線上 → fire,evidence 帶關卡價', () {
      final r = rule.evaluate(
        ctx(ma20: 100),
        StockData(
          symbol: 'TEST',
          prices: pricesEndingWith(prevClose: 98, close: 102),
          dividends: DividendContext.noEvents,
        ),
      );
      expect(r, isNotNull);
      expect(r!.type, ReasonType.reclaimMa20);
      expect(r.evidence!['ma20'], 100);
      expect(r.evidence!['close'], 102);
    });

    test('昨收恰等於 MA(壓線)、今收上 → fire(含平盤突破)', () {
      final r = rule.evaluate(
        ctx(ma20: 100),
        StockData(
          symbol: 'TEST',
          prices: pricesEndingWith(prevClose: 100, close: 101),
          dividends: DividendContext.noEvents,
        ),
      );
      expect(r, isNotNull);
    });

    test('兩天都在線上(非穿越)→ null', () {
      final r = rule.evaluate(
        ctx(ma20: 100),
        StockData(
          symbol: 'TEST',
          prices: pricesEndingWith(prevClose: 103, close: 105),
          dividends: DividendContext.noEvents,
        ),
      );
      expect(r, isNull);
    });

    test('兩天都在線下 → null', () {
      final r = rule.evaluate(
        ctx(ma20: 100),
        StockData(
          symbol: 'TEST',
          prices: pricesEndingWith(prevClose: 95, close: 97),
          dividends: DividendContext.noEvents,
        ),
      );
      expect(r, isNull);
    });

    test('ETF → null(走勢平滑的穿越是雜訊,與回檔規則同判斷)', () {
      final r = rule.evaluate(
        ctx(ma20: 100),
        StockData(
          symbol: '0050',
          prices: pricesEndingWith(prevClose: 98, close: 102, symbol: '0050'),
          dividends: DividendContext.noEvents,
        ),
      );
      expect(r, isNull);
    });

    test('ma20 缺(資料不足)→ null', () {
      final r = rule.evaluate(
        ctx(ma20: null),
        StockData(
          symbol: 'TEST',
          prices: pricesEndingWith(prevClose: 98, close: 102),
          dividends: DividendContext.noEvents,
        ),
      );
      expect(r, isNull);
    });
  });

  group('ReclaimMa60Rule(站回季線)', () {
    const rule = ReclaimMa60Rule();

    test('穿越季線 → fire', () {
      final r = rule.evaluate(
        ctx(ma60: 100),
        StockData(
          symbol: 'TEST',
          prices: pricesEndingWith(prevClose: 99, close: 101),
          dividends: DividendContext.noEvents,
        ),
      );
      expect(r, isNotNull);
      expect(r!.type, ReasonType.reclaimMa60);
    });

    test('未穿越 → null', () {
      final r = rule.evaluate(
        ctx(ma60: 100),
        StockData(
          symbol: 'TEST',
          prices: pricesEndingWith(prevClose: 101, close: 103),
          dividends: DividendContext.noEvents,
        ),
      );
      expect(r, isNull);
    });
  });

  group('BreakMa20Rule / BreakMa60Rule(跌破,風控對稱版)', () {
    test('昨收線上、今收線下 → fire 跌破月線', () {
      const rule = BreakMa20Rule();
      final r = rule.evaluate(
        ctx(ma20: 100),
        StockData(
          symbol: 'TEST',
          prices: pricesEndingWith(prevClose: 102, close: 98),
          dividends: DividendContext.noEvents,
        ),
      );
      expect(r, isNotNull);
      expect(r!.type, ReasonType.breakMa20);
    });

    test('跌破季線 → fire,分數為負(風控警示)', () {
      const rule = BreakMa60Rule();
      final r = rule.evaluate(
        ctx(ma60: 100),
        StockData(
          symbol: 'TEST',
          prices: pricesEndingWith(prevClose: 100.5, close: 99),
          dividends: DividendContext.noEvents,
        ),
      );
      expect(r, isNotNull);
      expect(r!.type, ReasonType.breakMa60);
      expect(r.type.score, lessThan(0));
    });

    test('兩天都在線下(早已跌破,非事件)→ null', () {
      const rule = BreakMa60Rule();
      final r = rule.evaluate(
        ctx(ma60: 100),
        StockData(
          symbol: 'TEST',
          prices: pricesEndingWith(prevClose: 97, close: 95),
          dividends: DividendContext.noEvents,
        ),
      );
      expect(r, isNull);
    });
  });

  group('CoilingBelowMa20/Ma60(蓄勢區:貼線下 0~3% + 60D>10%)', () {
    // 60D 報酬由 prices 計算:count=65 根,closes[4](倒數第 61 根)為 60 交易日前。
    // pricesEndingWith 的 baseline=100,把最舊一段改低製造 60D 正報酬。
    List<DailyPriceEntry> coilingPrices({
      required double close,
      double past60Close = 80, // 60D 前 80 → 今收 97 時 60D +21%
      String symbol = 'TEST',
    }) {
      return [
        for (var i = 0; i < 65; i++)
          DailyPriceEntry(
            symbol: symbol,
            date: DateTime(2026, 1, 1).add(Duration(days: i)),
            open: 100,
            high: 101,
            low: 99,
            close: i == 64 ? close : (i <= 4 ? past60Close : 100),
            volume: 1000,
          ),
      ];
    }

    test('貼月線下 2%+60D 強 → fire,evidence 帶距離與動能', () {
      const rule = CoilingBelowMa20Rule();
      final r = rule.evaluate(
        ctx(ma20: 100),
        StockData(
          symbol: 'TEST',
          prices: coilingPrices(close: 98),
          dividends: DividendContext.noEvents,
        ),
      );
      expect(r, isNotNull);
      expect(r!.type, ReasonType.coilingBelowMa20);
      expect(r.evidence!['distancePct'], closeTo(-2.0, 0.01));
    });

    test('線上(已突破)→ null:蓄勢只在線下', () {
      const rule = CoilingBelowMa20Rule();
      final r = rule.evaluate(
        ctx(ma20: 100),
        StockData(
          symbol: 'TEST',
          prices: coilingPrices(close: 101),
          dividends: DividendContext.noEvents,
        ),
      );
      expect(r, isNull);
    });

    test('離線太遠(>3%)→ null', () {
      const rule = CoilingBelowMa20Rule();
      final r = rule.evaluate(
        ctx(ma20: 100),
        StockData(
          symbol: 'TEST',
          prices: coilingPrices(close: 96),
          dividends: DividendContext.noEvents,
        ),
      );
      expect(r, isNull);
    });

    test('60D 動能不足(≤10%)→ null:弱勢反彈到壓力不是蓄勢', () {
      const rule = CoilingBelowMa20Rule();
      final r = rule.evaluate(
        ctx(ma20: 100),
        StockData(
          symbol: 'TEST',
          prices: coilingPrices(close: 98, past60Close: 95), // 60D 僅 +3%
          dividends: DividendContext.noEvents,
        ),
      );
      expect(r, isNull);
    });

    test('季線版:貼季線下 1% + 60D 強 → fire', () {
      const rule = CoilingBelowMa60Rule();
      final r = rule.evaluate(
        ctx(ma60: 100),
        StockData(
          symbol: 'TEST',
          prices: coilingPrices(close: 99),
          dividends: DividendContext.noEvents,
        ),
      );
      expect(r, isNotNull);
      expect(r!.type, ReasonType.coilingBelowMa60);
    });

    test('ETF → null', () {
      const rule = CoilingBelowMa20Rule();
      final r = rule.evaluate(
        ctx(ma20: 100),
        StockData(
          symbol: '0050',
          prices: coilingPrices(close: 98, symbol: '0050'),
          dividends: DividendContext.noEvents,
        ),
      );
      expect(r, isNull);
    });
  });
}
