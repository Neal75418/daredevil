import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/domain/services/price_calculator.dart';
import 'package:daredevil/data/database/app_database.dart';

import '../../helpers/price_data_generators.dart';

void main() {
  group('PriceCalculator', () {
    group('calculatePriceChange', () {
      test(
        'calculate positive price change when history includes latest date',
        () {
          final now = DateTime.now();
          final history = generatePriceHistoryFromList(
            prices: [100.0, 100.0, 100.0, 100.0, 105.0],
            startDate: now.subtract(const Duration(days: 4)),
          );
          final latestPrice = createTestPrice(close: 105.0, date: now);

          final result = PriceCalculator.calculatePriceChange(
            history,
            latestPrice,
          );

          expect(result, isNotNull);
          expect(result, closeTo(5.0, 0.01)); // 5% increase from 100 to 105
        },
      );

      test(
        'calculate negative price change when history includes latest date',
        () {
          final now = DateTime.now();
          final history = generatePriceHistoryFromList(
            prices: [100.0, 100.0, 100.0, 100.0, 95.0],
            startDate: now.subtract(const Duration(days: 4)),
          );
          final latestPrice = createTestPrice(close: 95.0, date: now);

          final result = PriceCalculator.calculatePriceChange(
            history,
            latestPrice,
          );

          expect(result, isNotNull);
          expect(result, closeTo(-5.0, 0.01)); // 5% decrease from 100 to 95
        },
      );

      test(
        'calculate price change when history does NOT include latest date',
        () {
          final now = DateTime.now();
          final yesterday = now.subtract(const Duration(days: 1));
          // History only goes up to yesterday
          final history = generatePriceHistoryFromList(
            prices: [100.0, 100.0, 100.0, 100.0],
            startDate: yesterday.subtract(const Duration(days: 3)),
          );
          // Latest price is today
          final latestPrice = createTestPrice(close: 105.0, date: now);

          final result = PriceCalculator.calculatePriceChange(
            history,
            latestPrice,
          );

          expect(result, isNotNull);
          // Should use history.last (100.0) as previous close, not history[length-2]
          expect(result, closeTo(5.0, 0.01)); // 5% increase from 100 to 105
        },
      );

      test('return null when latestPrice is null', () {
        final history = generatePriceHistoryFromList(
          prices: [100.0, 100.0, 100.0, 100.0, 100.0],
        );

        final result = PriceCalculator.calculatePriceChange(history, null);

        expect(result, isNull);
      });

      test(
        'return null when history has less than 2 entries and includes latest',
        () {
          final now = DateTime.now();
          final history = generatePriceHistoryFromList(
            prices: [100.0],
            startDate: now,
          );
          final latestPrice = createTestPrice(close: 100.0, date: now);

          final result = PriceCalculator.calculatePriceChange(
            history,
            latestPrice,
          );

          expect(result, isNull);
        },
      );

      test('work with single entry history when latest date is different', () {
        final now = DateTime.now();
        final yesterday = now.subtract(const Duration(days: 1));
        final history = generatePriceHistoryFromList(
          prices: [100.0],
          startDate: yesterday,
        );
        final latestPrice = createTestPrice(close: 110.0, date: now);

        final result = PriceCalculator.calculatePriceChange(
          history,
          latestPrice,
        );

        expect(result, isNotNull);
        expect(result, closeTo(10.0, 0.01)); // 10% increase
      });

      test('return null when previous close is zero', () {
        final now = DateTime.now();
        final history = generatePriceHistoryFromList(
          prices: [100.0, 0.0, 100.0],
          startDate: now.subtract(const Duration(days: 2)),
        );
        final latestPrice = createTestPrice(close: 100.0, date: now);

        final result = PriceCalculator.calculatePriceChange(
          history,
          latestPrice,
        );

        expect(result, isNull);
      });

      test('use priceChange field when available', () {
        final now = DateTime.now();
        // priceChange = 5.0 表示漲 5 元，前一日收盤 = 105 - 5 = 100
        final latestPrice = createTestPrice(
          close: 105.0,
          date: now,
          priceChange: 5.0,
        );

        final result = PriceCalculator.calculatePriceChange([], latestPrice);

        expect(result, isNotNull);
        expect(result, closeTo(5.0, 0.01)); // (5 / 100) * 100 = 5%
      });

      test('use priceChange even when history has gaps', () {
        final now = DateTime.now();
        // 歷史資料有缺口：只有 3 天前和今天，缺少昨天
        final history = [
          createTestPrice(
            close: 98.0,
            date: now.subtract(const Duration(days: 3)),
          ),
          createTestPrice(
            close: 105.0,
            date: now,
            priceChange: 5.0, // API 告訴我們漲 5 元（相對昨天的 100）
          ),
        ];

        final latestPrice = history.last;

        final result = PriceCalculator.calculatePriceChange(
          history,
          latestPrice,
        );

        // 應使用 priceChange 計算：(5 / 100) * 100 = 5%
        // 而非使用錯誤的歷史比較：(105 - 98) / 98 * 100 = 7.14%
        expect(result, closeTo(5.0, 0.01));
      });

      test('fall back to history when priceChange is null', () {
        final now = DateTime.now();
        final history = generatePriceHistoryFromList(
          prices: [100.0, 100.0, 100.0, 100.0, 105.0],
          startDate: now.subtract(const Duration(days: 4)),
        );
        // 無 priceChange（如 FinMind 歷史資料）
        final latestPrice = createTestPrice(close: 105.0, date: now);

        final result = PriceCalculator.calculatePriceChange(
          history,
          latestPrice,
        );

        expect(result, isNotNull);
        expect(result, closeTo(5.0, 0.01));
      });

      test('return null when priceChange causes negative prevClose', () {
        final now = DateTime.now();
        // close = 5, priceChange = 10 → prevClose = 5 - 10 = -5（不合理）
        final latestPrice = createTestPrice(
          close: 5.0,
          date: now,
          priceChange: 10.0,
        );

        final result = PriceCalculator.calculatePriceChange([], latestPrice);

        expect(result, isNull);
      });
    });

    group('calculatePriceChangesBatch', () {
      test('calculate price changes for multiple symbols', () {
        final priceHistories = <String, List<DailyPriceEntry>>{
          'AAAA': generatePriceHistoryFromList(
            prices: [100.0, 100.0, 100.0, 100.0, 105.0],
            symbol: 'AAAA',
          ),
          'BBBB': generatePriceHistoryFromList(
            prices: [200.0, 200.0, 200.0, 200.0, 190.0],
            symbol: 'BBBB',
          ),
        };

        final latestPrices = <String, DailyPriceEntry>{
          'AAAA': createTestPrice(
            symbol: 'AAAA',
            close: 105.0,
            date: DateTime.now(),
          ),
          'BBBB': createTestPrice(
            symbol: 'BBBB',
            close: 190.0,
            date: DateTime.now(),
          ),
        };

        final result = PriceCalculator.calculatePriceChangesBatch(
          priceHistories,
          latestPrices,
        );

        expect(result['AAAA'], closeTo(5.0, 0.01));
        expect(result['BBBB'], closeTo(-5.0, 0.01));
      });

      test('return null for symbols with no history', () {
        final priceHistories = <String, List<DailyPriceEntry>>{};

        final latestPrices = <String, DailyPriceEntry>{
          'AAAA': createTestPrice(
            symbol: 'AAAA',
            close: 105.0,
            date: DateTime.now(),
          ),
        };

        final result = PriceCalculator.calculatePriceChangesBatch(
          priceHistories,
          latestPrices,
        );

        expect(result['AAAA'], isNull);
      });

      test('return null for symbols with empty history', () {
        final priceHistories = <String, List<DailyPriceEntry>>{'AAAA': []};

        final latestPrices = <String, DailyPriceEntry>{
          'AAAA': createTestPrice(
            symbol: 'AAAA',
            close: 105.0,
            date: DateTime.now(),
          ),
        };

        final result = PriceCalculator.calculatePriceChangesBatch(
          priceHistories,
          latestPrices,
        );

        expect(result['AAAA'], isNull);
      });

      test('use latestPrice.priceChange even when history is null', () {
        final latestPrices = <String, DailyPriceEntry>{
          'AAAA': createTestPrice(
            symbol: 'AAAA',
            close: 105.0,
            date: DateTime.now(),
            priceChange: 5.0,
          ),
        };

        // history map 完全沒有 AAAA（history == null 的情境）
        final priceHistories = <String, List<DailyPriceEntry>>{};

        final result = PriceCalculator.calculatePriceChangesBatch(
          priceHistories,
          latestPrices,
        );

        // 應使用 API 提供的 priceChange 計算：(5 / 100) * 100 = 5%
        expect(result['AAAA'], closeTo(5.0, 0.01));
      });

      test('use latestPrice.priceChange even when history is empty', () {
        final latestPrices = <String, DailyPriceEntry>{
          'AAAA': createTestPrice(
            symbol: 'AAAA',
            close: 105.0,
            date: DateTime.now(),
            priceChange: 5.0,
          ),
        };

        final priceHistories = <String, List<DailyPriceEntry>>{'AAAA': []};

        final result = PriceCalculator.calculatePriceChangesBatch(
          priceHistories,
          latestPrices,
        );

        expect(result['AAAA'], closeTo(5.0, 0.01));
      });

      test('handle mixed valid and invalid data', () {
        final priceHistories = <String, List<DailyPriceEntry>>{
          'AAAA': generatePriceHistoryFromList(
            prices: [100.0, 100.0, 100.0, 100.0, 110.0],
            symbol: 'AAAA',
          ),
          'BBBB': [], // Empty history
        };

        final latestPrices = <String, DailyPriceEntry>{
          'AAAA': createTestPrice(
            symbol: 'AAAA',
            close: 110.0,
            date: DateTime.now(),
          ),
          'BBBB': createTestPrice(
            symbol: 'BBBB',
            close: 100.0,
            date: DateTime.now(),
          ),
        };

        final result = PriceCalculator.calculatePriceChangesBatch(
          priceHistories,
          latestPrices,
        );

        expect(result['AAAA'], closeTo(10.0, 0.01));
        expect(result['BBBB'], isNull);
      });
    });

    group('marketUptrendOrNull（規則 gate 用、資料不足回 null）', () {
      // count 檔，每檔 len 根；最後一根對 [len-1-120] 漲 retPct%
      Map<String, List<DailyPriceEntry>> universe(
        int count,
        double retPct,
        int len,
      ) {
        return {
          for (var i = 0; i < count; i++)
            's$i': [
              ...List.generate(
                len - 1,
                (d) => createTestPrice(
                  symbol: 's$i',
                  close: 100,
                  date: DateTime(2025).add(Duration(days: d)),
                ),
              ),
              createTestPrice(
                symbol: 's$i',
                close: 100 * (1 + retPct / 100),
                date: DateTime(2025).add(Duration(days: len)),
              ),
            ],
        };
      }

      // ================================================================
      // 半市場日的橫斷面污染（P1-8 (A)）
      //
      // 本函式以 `history.last` 當「今日」平均全市場 N 日報酬。單一市場
      // 資料缺漏時（實測 TWSE 1225 / TPEx 904），有資料那半邊的 last 是
      // 今日、缺漏那半邊的 last 是昨日 —— regime 會變成「今日的一半」
      // 混「昨日的另一半」的平均，是評分裡唯一真正被半市場污染的計算。
      //
      // 修法與 classifyCandidate 的 staleBar 同一套新鮮度概念：只計入
      // 最後一根 bar 就是評分日的股票。半市場仍有 1225 檔遠高於門檻 50，
      // regime 照常算得出來，而且變成正確的。
      // ================================================================

      /// count 檔，最後一根 bar 停在 [endDate]，對 120 根前漲 retPct%
      Map<String, List<DailyPriceEntry>> universeEndingAt(
        int count,
        double retPct,
        DateTime endDate, {
        String prefix = 's',
      }) {
        const len = 121;
        return {
          for (var i = 0; i < count; i++)
            '$prefix$i': [
              ...List.generate(
                len - 1,
                (d) => createTestPrice(
                  symbol: '$prefix$i',
                  close: 100,
                  date: endDate.subtract(Duration(days: len - 1 - d)),
                ),
              ),
              createTestPrice(
                symbol: '$prefix$i',
                close: 100 * (1 + retPct / 100),
                date: endDate,
              ),
            ],
        };
      }

      test('🚨 asOf 給定時只計入當日 bar，陳舊的一半不得混入平均', () {
        final today = DateTime(2026, 7, 24);
        // 今日這半邊大跌 -10%，昨日那半邊「看起來」大漲 +30%
        final fresh = universeEndingAt(60, -10, today, prefix: 'fresh');
        final stale = universeEndingAt(
          60,
          30,
          today.subtract(const Duration(days: 1)),
          prefix: 'stale',
        );

        expect(
          PriceCalculator.marketUptrendOrNull(
            {...fresh, ...stale},
            120,
            asOf: today,
          ),
          isFalse,
          reason: '只有今日 bar 該進 regime 母體；混入昨日會把下跌 regime 讀成上漲',
        );
      });

      // ================================================================
      // 離群值主導（2026-08-29 領域稽核 C2）
      //
      // 舊實作是**等權算術平均** > 0。報酬的分布右偏得極端——下界被 -100%
      // 綁住、上界無限——所以少數多倍股就能主導兩千檔的平均。
      //
      // 實測(本機 DB、120 交易日回看):**180 個可判定日裡有 179 天判多頭**
      // (99.4%)，其中 40.6% 的日子過半股票其實在跌。2026-08-28 平均
      // +12.93%、中位數 +0.66%，貢獻最大的五檔是 3026(+578%)、7610(+418%)、
      // 6213(+356%)、2059(+346%)、2426(+321%)——而且都是**真行情**(價格
      // 序列連續、無斷點),不是資料錯誤。
      //
      // 換中位數不需要選新門檻,因為 `中位數 > 0 ⟺ 過半股票上漲`：這道
      // gate 自此在定義上等同市場寬度,而不是碰巧一致。
      // ================================================================

      /// 依 [returns] 逐檔給不同的 120 日報酬（%）
      Map<String, List<DailyPriceEntry>> mixedUniverse(List<double> returns) {
        const len = 121;
        final base = DateTime(2025);
        return {
          for (var i = 0; i < returns.length; i++)
            'm$i': [
              ...List.generate(
                len - 1,
                (d) => createTestPrice(
                  symbol: 'm$i',
                  close: 100,
                  date: base.add(Duration(days: d)),
                ),
              ),
              createTestPrice(
                symbol: 'm$i',
                close: 100 * (1 + returns[i] / 100),
                date: base.add(Duration(days: len)),
              ),
            ],
        };
      }

      test('🚨 少數暴漲股不得把「過半下跌」讀成多頭(稽核 C2)', () {
        // 55 檔 −2%、5 檔 +500%
        //   平均 = (55×(−2) + 5×500) / 60 = +39.8%  → 舊碼判多頭
        //   中位數 = −2%                            → 過半在跌,判空頭
        final u = mixedUniverse([
          ...List.filled(55, -2.0),
          ...List.filled(5, 500.0),
        ]);
        expect(
          PriceCalculator.marketUptrendOrNull(u, 120),
          isFalse,
          reason: '60 檔裡 55 檔在跌,不該因為 5 檔多倍股而判多頭',
        );
      });

      test('🚨 判定必須與上漲家數一致——中位數 > 0 ⟺ 過半上漲', () {
        // 這條釘住換估計量的**理由**,不只是換了一個函式。
        //
        // 幅度刻意**不對稱**（贏家 +50%、輸家 −5%）:若兩邊對稱,平均與
        // 中位數會給同一答案,這條就對 mutation 免疫、變成覆蓋的假象。
        // 不對稱下平均在 up ≥ 6 就翻多,中位數要 up ≥ 31——中間那段
        // (10/29/30) 正是舊實作說謊的區間。
        //
        // 檔數取**奇數**(61):偶數檔的中位數是中間兩值的平均,恰好半數
        // 上漲時答案取決於兩者幅度,等價關係只在奇數檔嚴格成立。
        for (final up in [0, 6, 10, 29, 30, 31, 50, 61]) {
          final u = mixedUniverse([
            ...List.filled(up, 50.0),
            ...List.filled(61 - up, -5.0),
          ]);
          expect(
            PriceCalculator.marketUptrendOrNull(u, 120),
            up > 30, // 61 檔中過半 = 31 檔以上
            reason: '61 檔中 $up 檔上漲',
          );
        }
      });

      test('🚨 單一極端值不得改變結論(穩健性)', () {
        final losers = List.filled(59, -3.0);
        expect(
          PriceCalculator.marketUptrendOrNull(mixedUniverse(losers), 120),
          isFalse,
        );
        expect(
          PriceCalculator.marketUptrendOrNull(
            mixedUniverse([...losers, 100000.0]),
            120,
          ),
          isFalse,
          reason: '加一檔 +100,000% 仍不得翻多——那正是舊碼會做的事',
        );
      });

      test('對照組:真正的全面上漲仍判多頭(確認不是把功能關掉)', () {
        expect(
          PriceCalculator.marketUptrendOrNull(
            mixedUniverse(List.filled(60, 8.0)),
            120,
          ),
          isTrue,
        );
      });

      test('過濾後有效股不足 50 → null（維持 permissive，不誤殺訊號）', () {
        final today = DateTime(2026, 7, 24);
        final fresh = universeEndingAt(40, 10, today, prefix: 'fresh');
        final stale = universeEndingAt(
          60,
          10,
          today.subtract(const Duration(days: 1)),
          prefix: 'stale',
        );

        expect(
          PriceCalculator.marketUptrendOrNull(
            {...fresh, ...stale},
            120,
            asOf: today,
          ),
          isNull,
        );
      });

      test('asOf 帶時分秒仍視為同一天（逐欄比 y/m/d）', () {
        final today = DateTime(2026, 7, 24);
        expect(
          PriceCalculator.marketUptrendOrNull(
            universeEndingAt(60, 10, today),
            120,
            asOf: DateTime(2026, 7, 24, 15, 30),
          ),
          isTrue,
        );
      });

      test('省略 asOf 時不過濾（向後相容）', () {
        final today = DateTime(2026, 7, 24);
        final stale = universeEndingAt(
          60,
          10,
          today.subtract(const Duration(days: 1)),
        );

        expect(PriceCalculator.marketUptrendOrNull(stale, 120), isTrue);
      });

      test('有效股 < 50 → null（未知、caller 不擋）', () {
        expect(
          PriceCalculator.marketUptrendOrNull(universe(40, 10, 121), 120),
          isNull,
        );
      });

      test('≥ 50 檔且中位數報酬 > 0 → true', () {
        expect(
          PriceCalculator.marketUptrendOrNull(universe(60, 10, 121), 120),
          isTrue,
        );
      });

      test('≥ 50 檔且中位數報酬 < 0 → false', () {
        expect(
          PriceCalculator.marketUptrendOrNull(universe(60, -10, 121), 120),
          isFalse,
        );
      });

      test('歷史不足 lookback+1 被略過 → 有效股歸零 → null', () {
        expect(
          PriceCalculator.marketUptrendOrNull(universe(60, 10, 100), 120),
          isNull,
        );
      });
    });
  });
}
