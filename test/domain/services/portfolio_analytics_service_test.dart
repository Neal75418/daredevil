import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/domain/models/dividend_context.dart';
import 'package:daredevil/domain/services/portfolio_analytics_service.dart';
import 'package:daredevil/core/utils/device_time.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/portfolio_data_builders.dart';

void main() {
  const service = PortfolioAnalyticsService();

  // ==========================================
  // calculatePerformance — 總報酬
  // ==========================================
  group('calculatePerformance', () {
    test('returns empty for no transactions and no positions', () {
      final result = service.calculatePerformance(
        transactions: [],
        positions: [],
        currentPrices: {},
        stocksMap: {},
        periodInputs: null,
      );

      expect(result.totalReturn, equals(0));
      expect(result.totalMarketValue, equals(0));
      expect(result.totalCostBasis, equals(0));
    });

    test('calculates total return correctly', () {
      // 場景：買 1500 股 @ 500，賣 500 股 @ 510（實現損益 5000），持有 1000 股
      final positions = [
        createTestPortfolioPosition(
          symbol: '2330',
          quantity: 1000,
          avgCost: 500.0,
          totalDividendReceived: 10000,
          realizedPnl: 5000,
        ),
      ];
      final transactions = [
        createTestPortfolioTransaction(
          symbol: '2330',
          txType: 'BUY',
          quantity: 1500,
          price: 500.0,
          fee: 0,
          date: DeviceTime.now().subtract(const Duration(days: 100)),
        ),
        createTestPortfolioTransaction(
          symbol: '2330',
          txType: 'SELL',
          quantity: 500,
          price: 510.0,
          fee: 0,
          tax: 0,
          date: DeviceTime.now().subtract(const Duration(days: 50)),
        ),
      ];

      final result = service.calculatePerformance(
        transactions: transactions,
        positions: positions,
        currentPrices: {'2330': 600.0},
        stocksMap: {},
        periodInputs: null,
      );

      // totalHistoricalBuyCost = 1500 * 500 = 750000
      // totalSellProceeds = 500 * 510 = 255000
      // currentMarketValue = 1000 * 600 = 600000
      // dividends = 10000
      // totalReturn = (600000 + 10000 + 255000 - 750000) / 750000 * 100 = 15.33%
      expect(result.totalReturn, closeTo(15.33, 0.1));
      expect(result.totalMarketValue, equals(600000.0));
      expect(result.totalCostBasis, equals(500000.0)); // 持倉成本不變
    });

    test('returns 0 total return when costBasis is 0', () {
      final result = service.calculatePerformance(
        transactions: [
          createTestPortfolioTransaction(
            txType: 'SELL',
            date: DeviceTime.now().subtract(const Duration(days: 10)),
          ),
        ],
        positions: [], // no positions = no cost
        currentPrices: {},
        stocksMap: {},
        periodInputs: null,
      );

      expect(result.totalReturn, equals(0));
    });

    test('uses avgCost as fallback when currentPrice missing', () {
      final positions = [
        createTestPortfolioPosition(
          symbol: '2330',
          quantity: 1000,
          avgCost: 500.0,
        ),
      ];

      final result = service.calculatePerformance(
        transactions: [],
        positions: positions,
        currentPrices: {}, // no current price → uses avgCost
        stocksMap: {},
        periodInputs: null,
      );

      // marketValue = 500 * 1000 = costBasis → totalReturn = 0
      expect(result.totalReturn, equals(0));
      expect(result.totalMarketValue, equals(500000.0));
    });

    test('totalPnl getter works correctly', () {
      final positions = [
        createTestPortfolioPosition(
          symbol: 'A',
          quantity: 100,
          avgCost: 100.0,
          totalDividendReceived: 500,
          realizedPnl: 1000,
        ),
      ];

      final result = service.calculatePerformance(
        transactions: [],
        positions: positions,
        currentPrices: {'A': 120.0},
        stocksMap: {},
        periodInputs: null,
      );

      // totalPnl = marketValue - costBasis + dividends + realizedPnl
      // = 12000 - 10000 + 500 + 1000 = 3500
      expect(result.totalPnl, closeTo(3500.0, 0.1));
    });
  });

  // ==========================================
  // periodReturns：近 1／5／20 個交易日、年化
  // ==========================================
  group('periodReturns', () {
    DailyPriceEntry bar(String symbol, DateTime date, double close) =>
        DailyPriceEntry(
          symbol: symbol,
          date: date,
          open: close,
          high: close,
          low: close,
          close: close,
          volume: 1000,
        );

    /// 從 [last] 往回 [count] 個平日（含 [last]），升冪；[skip] 裡的日子當休市跳過
    List<DateTime> weekdays(
      DateTime last,
      int count, {
      Set<DateTime> skip = const {},
    }) {
      final days = <DateTime>[];
      var d = last;
      while (days.length < count) {
        if (d.weekday <= DateTime.friday && !skip.contains(d)) days.add(d);
        d = DateTime(d.year, d.month, d.day - 1);
      }
      return days.reversed.toList();
    }

    PortfolioTransactionEntry tx(
      String symbol,
      String type,
      DateTime date, {
      double quantity = 1000,
      double price = 100,
      double fee = 0,
      double tax = 0,
    }) => createTestPortfolioTransaction(
      symbol: symbol,
      txType: type,
      date: date,
      quantity: quantity,
      price: price,
      fee: fee,
      tax: tax,
    );

    DividendContext noDividends(String symbol, DateTime from, DateTime to) =>
        DividendContext.noEvents;

    /// 照 `DividendCompleteness.priceContext` 的界線回事件：除權息日在
    /// (from, to] 之間；[incomplete] 裡的代號回資料不完整
    DividendContextLookup dividendsOf(
      Map<String, List<DividendPriceEvent>> events, {
      Set<String> incomplete = const {},
    }) =>
        (symbol, from, to) => incomplete.contains(symbol)
        ? const DividendContext.incomplete()
        : DividendContext.complete([
            for (final e in events[symbol] ?? const <DividendPriceEvent>[])
              if (e.exDate.isAfter(from) && !e.exDate.isAfter(to)) e,
          ]);

    PeriodReturns returnsOf({
      required List<PortfolioTransactionEntry> transactions,
      required Map<String, List<DailyPriceEntry>> closeHistory,
      required DateTime? asOf,
      List<PortfolioPositionEntry> positions = const [],
      Map<String, double> currentPrices = const {},
      DividendContextLookup? dividends,
    }) => service
        .calculatePerformance(
          transactions: transactions,
          positions: positions,
          currentPrices: currentPrices,
          stocksMap: {},
          periodInputs: asOf == null
              ? null
              : PeriodReturnInputs(
                  asOf: asOf,
                  closeHistory: closeHistory,
                  dividendContext: dividends ?? noDividends,
                ),
        )
        .periodReturns;

    test('沒有交易 → 四格都是 null', () {
      final r = returnsOf(
        transactions: [],
        positions: [createTestPortfolioPosition(symbol: 'A', quantity: 100)],
        currentPrices: {'A': 110.0},
        closeHistory: {},
        asOf: DateTime(2026, 11, 23),
      );
      expect(
        [r.daily, r.weekly, r.monthly, r.yearly],
        [isNull, isNull, isNull, isNull],
      );
    });

    test('asOf 為 null（持股都沒有收盤）→ 四格都是 null', () {
      final days = weekdays(DateTime(2026, 11, 23), 21);
      final r = returnsOf(
        transactions: [tx('A', 'BUY', days.first)],
        closeHistory: {
          'A': [for (final d in days) bar('A', d, 100)],
        },
        asOf: null,
      );
      expect(
        [r.daily, r.weekly, r.monthly, r.yearly],
        [isNull, isNull, isNull, isNull],
      );
    });

    test('🚨 期間內才買進：三格都以買進成本當起點（資料日當天買進）', () {
      final days = weekdays(DateTime(2026, 11, 23), 21);
      final r = returnsOf(
        transactions: [
          tx('2330', 'BUY', DateTime(2026, 11, 23), quantity: 20, price: 2040),
        ],
        closeHistory: {
          '2330': [
            for (final d in days)
              bar('2330', d, d == days.last ? 2030.0 : 2000.0),
          ],
        },
        asOf: DateTime(2026, 11, 23),
      );
      const expected = (2030 - 2040) / 2040 * 100;
      expect(r.daily, closeTo(expected, 1e-9));
      expect(r.weekly, closeTo(expected, 1e-9));
      expect(r.monthly, closeTo(expected, 1e-9));
    });

    test('前一交易日收盤已持有：日報酬是收盤對收盤，週、月從買進成本起算', () {
      final days = weekdays(DateTime(2026, 11, 24), 21);
      final r = returnsOf(
        transactions: [
          tx('2330', 'BUY', DateTime(2026, 11, 23), quantity: 20, price: 2040),
        ],
        closeHistory: {
          '2330': [
            for (final d in days)
              bar('2330', d, switch (d.day) {
                24 => 2230.0,
                23 => 2030.0,
                _ => 2000.0,
              }),
          ],
        },
        asOf: DateTime(2026, 11, 24),
      );
      expect(r.daily, closeTo((2230 - 2030) / 2030 * 100, 1e-9));
      expect(r.weekly, closeTo((2230 - 2040) / 2040 * 100, 1e-9));
      expect(r.monthly, closeTo((2230 - 2040) / 2040 * 100, 1e-9));
    });

    test('窗口數的是交易日：中間有休市日時，週報酬的起點是往回第 5 個交易日', () {
      // 11/19（四）休市：往回第 5 個交易日是 11/16（一），不是 7 天前的 11/17
      final days = weekdays(
        DateTime(2026, 11, 24),
        21,
        skip: {DateTime(2026, 11, 19)},
      );
      final closes = {for (var i = 0; i < days.length; i++) days[i]: 100.0 + i};
      final r = returnsOf(
        transactions: [tx('A', 'BUY', days.first)],
        closeHistory: {
          'A': [for (final d in days) bar('A', d, closes[d]!)],
        },
        asOf: days.last,
      );
      expect(days[days.length - 6], DateTime(2026, 11, 16));
      expect(r.daily, closeTo((120 - 119) / 119 * 100, 1e-9));
      expect(r.weekly, closeTo((120 - 115) / 115 * 100, 1e-9));
      // 往回第 20 個交易日是首筆買進那天：當天收盤已持有，起點是那天收盤
      expect(r.monthly, closeTo((120 - 100) / 100 * 100, 1e-9));
    });

    test('同一天兩筆不同時區寫法的收盤列只算一個交易日', () {
      final days = weekdays(DateTime(2026, 11, 24), 21);
      final closes = {for (var i = 0; i < days.length; i++) days[i]: 100.0 + i};
      final d = days[days.length - 3];
      final r = returnsOf(
        transactions: [tx('A', 'BUY', days.first)],
        closeHistory: {
          'A': [
            for (final d in days) bar('A', d, closes[d]!),
            bar('A', DateTime.utc(d.year, d.month, d.day), closes[d]!),
          ],
        },
        asOf: days.last,
      );
      expect(r.weekly, closeTo((120 - 115) / 115 * 100, 1e-9));
    });

    test('期間內的賣出收入算現金流；已賣光的股票以期初持股計值', () {
      final days = weekdays(DateTime(2026, 11, 24), 21);
      // 週報酬的起點是 days[15]
      double closeA(int i) => i <= 15 ? 110.0 : (i < 20 ? 115.0 : 120.0);
      double closeB(int i) => i == 15 ? 52.0 : 50.0;
      final r = returnsOf(
        transactions: [
          tx('A', 'BUY', days[0], quantity: 1000, price: 100),
          tx('B', 'BUY', days[0], quantity: 2000, price: 50),
          tx(
            'B',
            'SELL',
            days[18],
            quantity: 2000,
            price: 55,
            fee: 20,
            tax: 30,
          ),
        ],
        positions: [createTestPortfolioPosition(symbol: 'A', quantity: 1000)],
        closeHistory: {
          'A': [for (var i = 0; i < 21; i++) bar('A', days[i], closeA(i))],
          'B': [for (var i = 0; i < 21; i++) bar('B', days[i], closeB(i))],
        },
        asOf: days.last,
      );
      const startValue = 1000 * 110 + 2000 * 52;
      const sells = 2000 * 55 - 20 - 30;
      const endValue = 1000 * 120;
      expect(
        r.weekly,
        closeTo((endValue + sells - startValue) / startValue * 100, 1e-9),
      );
    });

    test('期間內買進的成本含手續費', () {
      final days = weekdays(DateTime(2026, 11, 24), 21);
      final r = returnsOf(
        transactions: [
          tx('A', 'BUY', days.last, quantity: 1000, price: 100, fee: 143),
        ],
        closeHistory: {
          'A': [
            for (final d in days) bar('A', d, d == days.last ? 110.0 : 100.0),
          ],
        },
        asOf: days.last,
      );
      expect(r.daily, closeTo((110000 - 100143) / 100143 * 100, 1e-9));
    });

    test('股票股利入帳落在窗口內 → null；入帳之後的窗口照新股數算', () {
      // 入帳那天股數跳一截、價格沒有對應調整（除權早在之前），算出來會是假獲利
      final days = weekdays(DateTime(2026, 11, 24), 21);
      final r = returnsOf(
        transactions: [
          tx('A', 'BUY', days[0], quantity: 1000, price: 100),
          tx('A', 'DIVIDEND_STOCK', days[18], quantity: 100, price: 0),
          tx('B', 'BUY', days[0], quantity: 1000, price: 100),
        ],
        closeHistory: {
          'A': [
            for (final d in days) bar('A', d, d == days.last ? 110.0 : 100.0),
          ],
          'B': [for (final d in days) bar('B', d, 100)],
        },
        asOf: days.last,
      );
      expect(r.weekly, isNull);
      // 日：A 1100 股漲 10 元、B 不動（股數算錯時比例會變）
      expect(r.daily, closeTo(11000 / 210000 * 100, 1e-9));
    });

    test('資料日之後的交易與收盤列都不算', () {
      final days = weekdays(DateTime(2026, 11, 23), 21);
      final after = DateTime(2026, 11, 24);
      final r = returnsOf(
        transactions: [
          tx('A', 'BUY', days[0], quantity: 1000, price: 100),
          // 資料日之後賣光：算進期末持股的話期初、期末都變 0，日報酬算不出來
          tx('A', 'SELL', after, quantity: 1000, price: 100),
        ],
        closeHistory: {
          'A': [
            for (final d in days) bar('A', d, d == days.last ? 110.0 : 100.0),
            bar('A', after, 150),
          ],
        },
        asOf: days.last,
      );
      expect(r.daily, closeTo(10, 1e-9));
    });

    test('收盤列不夠窗口長度時那一格是 null，其他照算', () {
      final days = weekdays(DateTime(2026, 11, 24), 6);
      final r = returnsOf(
        transactions: [
          tx('A', 'BUY', DateTime(2026, 10, 1), quantity: 1000, price: 100),
        ],
        closeHistory: {
          'A': [
            for (final d in days) bar('A', d, d == days.last ? 110.0 : 100.0),
          ],
        },
        asOf: days.last,
      );
      expect(r.daily, closeTo(10, 1e-9));
      expect(r.weekly, closeTo(10, 1e-9));
      expect(r.monthly, isNull);
    });

    test('收盤列剛好 5 筆：往回第 5 個交易日不存在，週報酬是 null', () {
      final days = weekdays(DateTime(2026, 11, 24), 5);
      final r = returnsOf(
        transactions: [
          tx('A', 'BUY', DateTime(2026, 10, 1), quantity: 1000, price: 100),
        ],
        closeHistory: {
          'A': [
            for (final d in days) bar('A', d, d == days.last ? 110.0 : 100.0),
          ],
        },
        asOf: days.last,
      );
      expect(r.daily, closeTo(10, 1e-9));
      expect(r.weekly, isNull);
    });

    test('期初有持股、收盤列從期初之後才開始（掛牌前就記了買進）：以買進成本當起點', () {
      final days = weekdays(DateTime(2026, 11, 24), 21);
      final r = returnsOf(
        transactions: [
          tx('A', 'BUY', days[0], quantity: 1000, price: 100),
          tx('B', 'BUY', days[0], quantity: 1000, price: 100),
        ],
        closeHistory: {
          'A': [
            bar('A', days[18], 105),
            bar('A', days[19], 105),
            bar('A', days[20], 110),
          ],
          'B': [for (final d in days) bar('B', d, 100)],
        },
        asOf: days.last,
      );
      // 日：期初（days[19]）A 已有收盤 105
      expect(r.daily, closeTo(5000 / 205000 * 100, 1e-9));
      // 週：期初（days[15]）A 還沒有收盤 → A 的買進當期間內的買進成本
      expect(
        r.weekly,
        closeTo((210000 - 100000 - 100000) / 200000 * 100, 1e-9),
      );
    });

    test('在倉持股完全沒有收盤列：以最新價（沒有就用均價）計值，不讓整排變 null', () {
      final days = weekdays(DateTime(2026, 11, 24), 21);
      final r = returnsOf(
        transactions: [
          tx('A', 'BUY', days[0], quantity: 1000, price: 60),
          tx('C', 'BUY', days[0], quantity: 1000, price: 40),
          tx('B', 'BUY', days[0], quantity: 1000, price: 100),
        ],
        positions: [
          createTestPortfolioPosition(symbol: 'A', quantity: 1000, avgCost: 60),
          createTestPortfolioPosition(symbol: 'C', quantity: 1000, avgCost: 40),
          createTestPortfolioPosition(symbol: 'B', quantity: 1000),
        ],
        currentPrices: {'A': 50, 'B': 110},
        closeHistory: {
          'B': [
            for (final d in days) bar('B', d, d == days.last ? 110.0 : 100.0),
          ],
        },
        asOf: days.last,
      );
      // A 以最新價 50、C 以均價 40 計值，期初期末同價：只有 B 漲 10%
      expect(r.daily, closeTo(10000 / 190000 * 100, 1e-9));
    });

    test('期初持有、期間內賣光又沒有任何收盤列 → null（期初價值未知）', () {
      final days = weekdays(DateTime(2026, 11, 24), 21);
      final r = returnsOf(
        transactions: [
          tx('A', 'BUY', days[0], quantity: 1000, price: 100),
          tx('A', 'SELL', days.last, quantity: 1000, price: 120),
          tx('B', 'BUY', days[0], quantity: 1000, price: 100),
        ],
        positions: [createTestPortfolioPosition(symbol: 'B', quantity: 1000)],
        closeHistory: {
          'B': [for (final d in days) bar('B', d, 100)],
        },
        asOf: days.last,
      );
      expect(r.daily, isNull);
    });

    test('🚨 除息日：持股 × (除息前收盤 − 參考價) 算流入（與今日損益同口徑）', () {
      // 00878 2026-11-17 除息：前收 32.43、參考價 31.18、收盤 30.86
      final days = weekdays(DateTime(2026, 11, 17), 21);
      final r = returnsOf(
        transactions: [tx('00878', 'BUY', days[0], quantity: 1000, price: 33)],
        closeHistory: {
          '00878': [
            for (final d in days)
              bar('00878', d, d == days.last ? 30.86 : 32.43),
          ],
        },
        dividends: dividendsOf({
          '00878': [
            DividendPriceEvent(
              exDate: DateTime(2026, 11, 17),
              closeBefore: 32.43,
              referencePrice: 31.18,
            ),
          ],
        }),
        asOf: days.last,
      );
      // 30860 + 1000 × 1.25 − 32430 = −320：等於 (收盤 − 參考價) × 股數
      expect(r.daily, closeTo(-320 / 32430 * 100, 1e-9));
      expect(r.weekly, closeTo(-320 / 32430 * 100, 1e-9));
    });

    test('除息日在期初當天不算進窗口（已反映在期初收盤）', () {
      final days = weekdays(DateTime(2026, 11, 18), 21);
      final r = returnsOf(
        transactions: [tx('00878', 'BUY', days[0], quantity: 1000, price: 33)],
        closeHistory: {
          '00878': [
            for (final d in days)
              bar('00878', d, switch (d.day) {
                18 => 30.65,
                17 => 30.86,
                _ => 32.43,
              }),
          ],
        },
        dividends: dividendsOf({
          '00878': [
            DividendPriceEvent(
              exDate: DateTime(2026, 11, 17),
              closeBefore: 32.43,
              referencePrice: 31.18,
            ),
          ],
        }),
        asOf: days.last,
      );
      expect(r.daily, closeTo((30.65 - 30.86) / 30.86 * 100, 1e-9));
    });

    test('除息前一天收盤持有的股數才領得到：除息日當天買進的不算', () {
      final days = weekdays(DateTime(2026, 11, 17), 21);
      final r = returnsOf(
        transactions: [
          tx('00878', 'BUY', days[0], quantity: 1000, price: 33),
          tx('00878', 'BUY', days.last, quantity: 1000, price: 30.86),
        ],
        closeHistory: {
          '00878': [
            for (final d in days)
              bar('00878', d, d == days.last ? 30.86 : 32.43),
          ],
        },
        dividends: dividendsOf({
          '00878': [
            DividendPriceEvent(
              exDate: DateTime(2026, 11, 17),
              closeBefore: 32.43,
              referencePrice: 31.18,
            ),
          ],
        }),
        asOf: days.last,
      );
      // 期末 2000 × 30.86，流入只有 1000 × 1.25，買進 30860
      expect(
        r.daily,
        closeTo((61720 + 1250 - 30860 - 32430) / (32430 + 30860) * 100, 1e-9),
      );
    });

    test('現金股利入帳紀錄不算期間現金流（已在除息日入帳）', () {
      final days = weekdays(DateTime(2026, 11, 24), 21);
      final r = returnsOf(
        transactions: [
          tx('A', 'BUY', days[0], quantity: 1000, price: 100),
          tx('A', 'DIVIDEND_CASH', days.last, quantity: 3000, price: 0),
        ],
        closeHistory: {
          'A': [for (final d in days) bar('A', d, 100)],
        },
        asOf: days.last,
      );
      expect(r.daily, closeTo(0, 1e-9));
    });

    test('除權息資料不完整 → 那檔有持股的窗口是 null', () {
      final days = weekdays(DateTime(2026, 11, 24), 21);
      final r = returnsOf(
        transactions: [tx('A', 'BUY', days[0], quantity: 1000, price: 100)],
        closeHistory: {
          'A': [for (final d in days) bar('A', d, 100)],
        },
        dividends: dividendsOf({}, incomplete: {'A'}),
        asOf: days.last,
      );
      expect(r.daily, isNull);
    });

    test('分割（停牌後恢復、收盤跳動超過門檻、沒有除權息事件）落在窗口內 → null', () {
      // 00662：11/10 收 117.8 後停止買賣，11/17 以一股分五股後的 23.1 恢復
      final days = weekdays(DateTime(2026, 11, 24), 21);
      final r = returnsOf(
        transactions: [
          tx('A', 'BUY', days[0], quantity: 1000, price: 117.8),
          tx('B', 'BUY', days[0], quantity: 1000, price: 100),
        ],
        closeHistory: {
          'A': [
            for (var i = 0; i < days.length; i++)
              if (i != 15 && i != 16) bar('A', days[i], i < 15 ? 117.8 : 23.1),
          ],
          'B': [for (final d in days) bar('B', d, 100)],
        },
        asOf: days.last,
      );
      expect(r.weekly, isNull);
      // 日：期初、期末都在分割之後
      expect(r.daily, closeTo(0, 1e-9));
    });

    test('沒有停牌的單日大漲跌（新股掛牌頭五天、無漲跌幅限制的 ETF）不算斷點', () {
      // 6983 掛牌第 2 天 385 → 472（+22.6%），中間照常交易
      final days = weekdays(DateTime(2026, 11, 24), 21);
      final r = returnsOf(
        transactions: [tx('A', 'BUY', days[0], quantity: 1000, price: 385)],
        closeHistory: {
          'A': [
            for (var i = 0; i < days.length; i++)
              bar('A', days[i], switch (i) {
                19 => 472.0,
                20 => 430.0,
                _ => 385.0,
              }),
          ],
        },
        asOf: days.last,
      );
      expect(r.weekly, closeTo((430 - 385) / 385 * 100, 1e-9));
    });

    test('分割後才買進：斷點不在持有期間內，照算', () {
      final days = weekdays(DateTime(2026, 11, 24), 21);
      final r = returnsOf(
        transactions: [
          tx('A', 'BUY', days[16], quantity: 1000, price: 23.1),
          tx('B', 'BUY', days[0], quantity: 1000, price: 100),
        ],
        closeHistory: {
          'A': [
            for (var i = 0; i < days.length; i++)
              if (i <= 10 || i >= 15)
                bar('A', days[i], switch (i) {
                  <= 10 => 117.8,
                  20 => 24.0,
                  _ => 23.1,
                }),
          ],
          'B': [for (final d in days) bar('B', d, 100)],
        },
        asOf: days.last,
      );
      // 月（期初 days[0]）：A 期間內買進 23100、期末 24000；B 不動
      expect(r.monthly, closeTo(900 / 123100 * 100, 1e-9));
    });

    test('掛牌前就記了買進、掛牌後頭幾天大漲：以買進成本當起點照算', () {
      final days = weekdays(DateTime(2026, 11, 24), 21);
      final r = returnsOf(
        transactions: [
          tx('A', 'BUY', days[14], quantity: 1000, price: 300),
          tx('B', 'BUY', days[0], quantity: 1000, price: 100),
        ],
        closeHistory: {
          'A': [
            bar('A', days[17], 385),
            bar('A', days[18], 472),
            bar('A', days[19], 430),
            bar('A', days[20], 385),
          ],
          'B': [for (final d in days) bar('B', d, 100)],
        },
        asOf: days.last,
      );
      // 週（期初 days[15]）：A 以抽籤成本 300000 起算、期末 385000；B 不動
      expect(r.weekly, closeTo(85000 / 400000 * 100, 1e-9));
    });

    test('停牌超過日線範圍、在窗口內才恢復交易 → null（期初價值未知）', () {
      // H 2023 年買進、停牌前的收盤不在讀到的日線裡；days[18] 恢復交易
      final days = weekdays(DateTime(2026, 11, 24), 21);
      final r = returnsOf(
        transactions: [
          tx('H', 'BUY', DateTime(2023, 6, 1), quantity: 1000, price: 20),
          tx('A', 'BUY', days[0], quantity: 1000, price: 100),
        ],
        positions: [
          createTestPortfolioPosition(symbol: 'H', quantity: 1000, avgCost: 20),
          createTestPortfolioPosition(symbol: 'A', quantity: 1000),
        ],
        closeHistory: {
          'H': [for (final d in days.sublist(18)) bar('H', d, 55)],
          'A': [for (final d in days) bar('A', d, 100)],
        },
        asOf: days.last,
      );
      expect(r.weekly, isNull);
      // 日（期初 days[19]）：H 已有收盤
      expect(r.daily, closeTo(0, 1e-9));
    });

    test('窗口內才買進、之後碰到除息：除息前持有的股數照樣入帳', () {
      final days = weekdays(DateTime(2026, 11, 24), 21);
      final r = returnsOf(
        transactions: [tx('A', 'BUY', days[16], quantity: 1000, price: 32.43)],
        closeHistory: {
          'A': [
            for (var i = 0; i < days.length; i++)
              bar('A', days[i], i < 18 ? 32.43 : 31.18),
          ],
        },
        dividends: dividendsOf({
          'A': [
            DividendPriceEvent(
              exDate: days[18],
              closeBefore: 32.43,
              referencePrice: 31.18,
            ),
          ],
        }),
        asOf: days.last,
      );
      // 週（期初 days[15]）：31180 + 1250 − 32430 = 0
      expect(r.weekly, closeTo(0, 1e-9));
    });

    test('減資（停牌後恢復、收盤往上跳超過門檻）也是斷點 → null', () {
      // 3714 2026-11-16 減資：停止買賣後恢復，價格約 1.7 倍
      final days = weekdays(DateTime(2026, 11, 24), 21);
      final r = returnsOf(
        transactions: [
          tx('A', 'BUY', days[0], quantity: 1000, price: 51.5),
          tx('B', 'BUY', days[0], quantity: 1000, price: 100),
        ],
        closeHistory: {
          'A': [
            for (var i = 0; i < days.length; i++)
              if (i != 15 && i != 16) bar('A', days[i], i < 15 ? 51.5 : 87.4),
          ],
          'B': [for (final d in days) bar('B', d, 100)],
        },
        asOf: days.last,
      );
      expect(r.weekly, isNull);
    });

    test('停牌跨過期初時，斷點從期初之前最近的收盤比起', () {
      final days = weekdays(DateTime(2026, 11, 24), 21);
      // A 在 days[15]、days[16] 停牌，days[17] 以分割後的價格恢復；B 提供交易日
      final r = returnsOf(
        transactions: [
          tx('A', 'BUY', days[0], quantity: 1000, price: 117.8),
          tx('B', 'BUY', days[0], quantity: 1000, price: 100),
        ],
        closeHistory: {
          'A': [
            for (var i = 0; i < days.length; i++)
              if (i != 15 && i != 16) bar('A', days[i], i < 15 ? 117.8 : 23.1),
          ],
          'B': [for (final d in days) bar('B', d, 100)],
        },
        asOf: days.last,
      );
      expect(r.weekly, isNull);
    });

    test('停牌期間碰到大額除息（跌幅超過門檻）：以參考價換算後不算斷點', () {
      final days = weekdays(DateTime(2026, 11, 24), 21);
      final r = returnsOf(
        transactions: [
          tx('A', 'BUY', days[0], quantity: 1000, price: 100),
          tx('B', 'BUY', days[0], quantity: 1000, price: 100),
        ],
        closeHistory: {
          'A': [
            for (var i = 0; i < days.length; i++)
              if (i != 17 && i != 18) bar('A', days[i], i < 17 ? 100.0 : 80.0),
          ],
          'B': [for (final d in days) bar('B', d, 100)],
        },
        dividends: dividendsOf({
          'A': [
            DividendPriceEvent(
              exDate: days[19],
              closeBefore: 100,
              referencePrice: 80,
            ),
          ],
        }),
        asOf: days.last,
      );
      expect(r.weekly, closeTo(0, 1e-9));
    });

    test('期初沒有持股、期間內也沒有買進 → null', () {
      final days = weekdays(DateTime(2026, 11, 24), 21);
      final r = returnsOf(
        transactions: [
          tx('A', 'BUY', days[0], quantity: 1000, price: 100),
          tx('A', 'SELL', days[10], quantity: 1000, price: 105),
        ],
        closeHistory: {
          'A': [for (final d in days) bar('A', d, 100)],
        },
        asOf: days.last,
      );
      expect(r.daily, isNull);
      expect(r.weekly, isNull);
      // 往回第 20 個交易日（首筆買進那天收盤）有持股：算得出來
      expect(r.monthly, closeTo(5, 1e-9));
    });

    test('早已賣光、近期沒有收盤列的股票不影響（例如已下市）', () {
      final days = weekdays(DateTime(2026, 11, 24), 21);
      final r = returnsOf(
        transactions: [
          tx('C', 'BUY', DateTime(2025, 3, 3), quantity: 1000, price: 30),
          tx('C', 'SELL', DateTime(2025, 6, 2), quantity: 1000, price: 35),
          tx('A', 'BUY', days[0], quantity: 1000, price: 100),
        ],
        closeHistory: {
          'A': [
            for (final d in days) bar('A', d, d == days.last ? 110.0 : 100.0),
          ],
        },
        asOf: days.last,
      );
      expect(r.daily, closeTo(10, 1e-9));
    });

    group('年化（持有天數量到資料日）', () {
      final asOf = DateTime(2026, 11, 23);

      double? yearlyOf({
        required int heldDays,
        required double currentPrice,
        double sellFee = 0,
      }) {
        final days = weekdays(asOf, 21);
        return returnsOf(
          transactions: [
            tx(
              'A',
              'BUY',
              DateTime(asOf.year, asOf.month, asOf.day - heldDays),
              quantity: 1000,
              price: 100,
            ),
            if (sellFee > 0)
              tx('A', 'SELL', asOf, quantity: 1, price: 1, fee: sellFee),
          ],
          positions: [
            createTestPortfolioPosition(
              symbol: 'A',
              quantity: sellFee > 0 ? 999 : 1000,
              avgCost: 100,
            ),
          ],
          currentPrices: {'A': currentPrice},
          closeHistory: {
            'A': [for (final d in days) bar('A', d, currentPrice)],
          },
          asOf: asOf,
        ).yearly;
      }

      test('持有未滿一年不換算（364 天 → null）', () {
        expect(yearlyOf(heldDays: 364, currentPrice: 150), isNull);
      });

      test('剛好一年（365 天）就換算：年化等於總報酬', () {
        expect(yearlyOf(heldDays: 365, currentPrice: 110), closeTo(10, 1e-9));
      });

      test('持有兩年、總報酬 21% → 年化 10%（複利）', () {
        expect(yearlyOf(heldDays: 730, currentPrice: 121), closeTo(10, 1e-9));
      });

      test('持有天數從第一筆交易算起（之後加碼不重算）', () {
        final days = weekdays(asOf, 21);
        final r = returnsOf(
          transactions: [
            tx('A', 'BUY', DateTime(2024, 11, 23), quantity: 1000, price: 100),
            tx('A', 'BUY', DateTime(2026, 8, 13), quantity: 1000, price: 100),
          ],
          positions: [
            createTestPortfolioPosition(
              symbol: 'A',
              quantity: 2000,
              avgCost: 100,
            ),
          ],
          currentPrices: {'A': 121},
          closeHistory: {
            'A': [for (final d in days) bar('A', d, 121)],
          },
          asOf: asOf,
        );
        // 2024-11-23 到 2026-11-23 是 730 天，總報酬 21% → 年化 10%
        expect(r.yearly, closeTo(10, 1e-9));
      });

      test('沒有任何買進紀錄 → 年化 null（不拿 0% 充數）', () {
        final r = returnsOf(
          transactions: [
            tx('A', 'SELL', DateTime(2025, 1, 2), quantity: 1000, price: 100),
          ],
          closeHistory: {
            'A': [bar('A', asOf, 100)],
          },
          asOf: asOf,
        );
        expect(r.yearly, isNull);
      });

      test('總報酬低於 -100%（賣出費用大於收入）→ 年化 -100%', () {
        // 市值 0、賣出收入 1 − 2000：總報酬 (0 − 1999 − 100000) ÷ 100000 < -100%
        expect(
          yearlyOf(heldDays: 730, currentPrice: 0, sellFee: 2000),
          closeTo(-100, 1e-9),
        );
      });
    });
  });

  // ==========================================
  // _calculateCurrentDrawdown（欄位名稱仍為 maxDrawdown）
  // ==========================================
  group('maxDrawdown', () {
    test('returns 0 for no transactions', () {
      final result = service.calculatePerformance(
        transactions: [],
        positions: [],
        currentPrices: {},
        stocksMap: {},
        periodInputs: null,
      );

      expect(result.maxDrawdown, equals(0));
    });

    test('returns 0 when currentValue >= peak', () {
      final positions = [
        createTestPortfolioPosition(
          symbol: 'A',
          quantity: 1000,
          avgCost: 100.0,
        ),
      ];

      final result = service.calculatePerformance(
        transactions: [
          createTestPortfolioTransaction(
            symbol: 'A',
            date: DeviceTime.now().subtract(const Duration(days: 30)),
          ),
        ],
        positions: positions,
        currentPrices: {'A': 120.0}, // above cost
        stocksMap: {},
        periodInputs: null,
      );

      // peak = max(100000, 120000) = 120000
      // currentValue = 120000 → no drawdown
      expect(result.maxDrawdown, equals(0));
    });

    test('calculates drawdown when currentValue < peak', () {
      final positions = [
        createTestPortfolioPosition(
          symbol: 'A',
          quantity: 1000,
          avgCost: 100.0,
        ),
      ];

      final result = service.calculatePerformance(
        transactions: [
          createTestPortfolioTransaction(
            symbol: 'A',
            date: DeviceTime.now().subtract(const Duration(days: 30)),
          ),
        ],
        positions: positions,
        currentPrices: {'A': 80.0}, // below cost
        stocksMap: {},
        periodInputs: null,
      );

      // peak = max(100000, 80000) = 100000
      // drawdown = (100000 - 80000) / 100000 * 100 = 20%
      expect(result.maxDrawdown, closeTo(20.0, 0.1));
    });
  });

  // ==========================================
  // _calculateIndustryAllocation
  // ==========================================
  group('industryAllocation', () {
    test('returns empty for no positions', () {
      final result = service.calculatePerformance(
        transactions: [],
        positions: [],
        currentPrices: {},
        stocksMap: {},
        periodInputs: null,
      );

      expect(result.industryAllocation, isEmpty);
    });

    test('calculates single industry at 100%', () {
      final positions = [
        createTestPortfolioPosition(
          symbol: 'A',
          quantity: 1000,
          avgCost: 100.0,
        ),
      ];
      final stocksMap = {
        'A': createTestStockMaster(symbol: 'A', industry: '半導體'),
      };

      final result = service.calculatePerformance(
        transactions: [],
        positions: positions,
        currentPrices: {'A': 100.0},
        stocksMap: stocksMap,
        periodInputs: null,
      );

      expect(result.industryAllocation.length, equals(1));
      expect(result.industryAllocation['半導體']!.percentage, closeTo(100.0, 0.1));
      expect(result.industryAllocation['半導體']!.symbols, equals(['A']));
    });

    test('calculates multiple industries correctly', () {
      final positions = [
        createTestPortfolioPosition(
          id: 1,
          symbol: 'A',
          quantity: 1000,
          avgCost: 100.0,
        ),
        createTestPortfolioPosition(
          id: 2,
          symbol: 'B',
          quantity: 500,
          avgCost: 200.0,
        ),
      ];
      final stocksMap = {
        'A': createTestStockMaster(symbol: 'A', industry: '半導體'),
        'B': createTestStockMaster(symbol: 'B', industry: '金融'),
      };

      final result = service.calculatePerformance(
        transactions: [],
        positions: positions,
        currentPrices: {'A': 100.0, 'B': 200.0},
        stocksMap: stocksMap,
        periodInputs: null,
      );

      // A = 100*1000 = 100000, B = 200*500 = 100000, total = 200000
      expect(result.industryAllocation['半導體']!.percentage, closeTo(50.0, 0.1));
      expect(result.industryAllocation['金融']!.percentage, closeTo(50.0, 0.1));
    });

    test('skips positions with quantity <= 0', () {
      final positions = [
        createTestPortfolioPosition(
          id: 1,
          symbol: 'A',
          quantity: 1000,
          avgCost: 100.0,
        ),
        createTestPortfolioPosition(
          id: 2,
          symbol: 'B',
          quantity: 0,
          avgCost: 200.0,
        ),
      ];
      final stocksMap = {
        'A': createTestStockMaster(symbol: 'A', industry: '半導體'),
        'B': createTestStockMaster(symbol: 'B', industry: '金融'),
      };

      final result = service.calculatePerformance(
        transactions: [],
        positions: positions,
        currentPrices: {'A': 100.0, 'B': 200.0},
        stocksMap: stocksMap,
        periodInputs: null,
      );

      expect(result.industryAllocation.length, equals(1));
      expect(result.industryAllocation.containsKey('半導體'), isTrue);
    });

    test('uses 其他 when stock not in stocksMap', () {
      final positions = [
        createTestPortfolioPosition(
          symbol: 'UNKNOWN',
          quantity: 100,
          avgCost: 50.0,
        ),
      ];

      final result = service.calculatePerformance(
        transactions: [],
        positions: positions,
        currentPrices: {'UNKNOWN': 50.0},
        stocksMap: {}, // not in map
        periodInputs: null,
      );

      expect(result.industryAllocation.containsKey('其他'), isTrue);
      expect(result.industryAllocation['其他']!.percentage, closeTo(100.0, 0.1));
    });

    test('groups multiple stocks in same industry', () {
      final positions = [
        createTestPortfolioPosition(
          id: 1,
          symbol: 'A',
          quantity: 500,
          avgCost: 100.0,
        ),
        createTestPortfolioPosition(
          id: 2,
          symbol: 'B',
          quantity: 500,
          avgCost: 100.0,
        ),
      ];
      final stocksMap = {
        'A': createTestStockMaster(symbol: 'A', industry: '半導體'),
        'B': createTestStockMaster(symbol: 'B', industry: '半導體'),
      };

      final result = service.calculatePerformance(
        transactions: [],
        positions: positions,
        currentPrices: {'A': 100.0, 'B': 100.0},
        stocksMap: stocksMap,
        periodInputs: null,
      );

      expect(result.industryAllocation.length, equals(1));
      expect(
        result.industryAllocation['半導體']!.symbols,
        containsAll(['A', 'B']),
      );
      expect(result.industryAllocation['半導體']!.percentage, closeTo(100.0, 0.1));
    });

    test('uses 其他 when industry is null', () {
      final positions = [
        createTestPortfolioPosition(symbol: 'A', quantity: 100, avgCost: 100.0),
      ];
      final stocksMap = {
        'A': createTestStockMaster(symbol: 'A', industry: null),
      };

      final result = service.calculatePerformance(
        transactions: [],
        positions: positions,
        currentPrices: {'A': 100.0},
        stocksMap: stocksMap,
        periodInputs: null,
      );

      expect(result.industryAllocation.containsKey('其他'), isTrue);
    });
  });
}
