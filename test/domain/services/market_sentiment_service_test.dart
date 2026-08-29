import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/domain/models/market_overview_models.dart';
import 'package:daredevil/domain/services/market_sentiment_service.dart';

void main() {
  group('MarketSentimentService.calculate', () {
    // 固定輸入：5 項子指標皆可計算，且各自分數不同以便辨識權重變動。
    //
    // - advanceRatio: ratio 0.5（分母不含平盤）→
    //   _linearMap(0.5, 0.15, 0.80) = 53.846…
    // - institutional: 常數序列 std=0、last>0 → 75.0
    // - volumeMomentum: today/avg = 1.0 → _linearMap(1.0, 0.5, 2.0) = 33.333…
    // - marginChange: 無變動 changePct=0 → _linearMap(0, -0.05, 0.05) = 50.0
    // - industryBreadth: 2 產業 1 上漲 → 50.0
    MarketSentiment computeFixedInput() {
      return MarketSentimentService.calculate(
        advanceDecline: const AdvanceDecline(advance: 500, decline: 500),
        institutionalNetHistory: const [100, 100, 100, 100, 100],
        turnoverHistory: const [100, 100, 100, 100, 100, 100],
        marginBalanceHistory: const [100, 100, 100, 100, 100],
        industries: const [
          IndustrySummary(
            industry: 'A',
            stockCount: 1,
            avgChangePct: 1.0,
            advance: 1,
            decline: 0,
          ),
          IndustrySummary(
            industry: 'B',
            stockCount: 1,
            avgChangePct: -1.0,
            advance: 0,
            decline: 1,
          ),
        ],
      );
    }

    test('composite 恰好包含 5 項子指標（漲停比已移除）', () {
      final result = computeFixedInput();

      expect(result.subScores.length, 5);
      expect(
        result.subScores.keys,
        containsAll(<String>[
          'advanceRatio',
          'institutional',
          'volumeMomentum',
          'marginChange',
          'industryBreadth',
        ]),
      );
      // 漲停比已自情緒綜合移除
      expect(result.subScores.containsKey('limitRatio'), isFalse);
    });

    test('權重總和為 1.0（5 項全到齊時 totalWeight 正規化不縮放）', () {
      final result = computeFixedInput();

      // 5 項全到齊 ⇒ totalWeight=1.0 ⇒ 綜合分數 == 加權平均（無正規化放大）。
      // 以已知子分數手算加權平均驗證權重總和為 1.0：
      // 0.35*(35/65*100) + 0.25*75 + 0.15*(100/3) + 0.15*50 + 0.10*50
      const expected =
          0.35 * (35.0 / 65.0 * 100.0) +
          0.25 * 75.0 +
          0.15 * (100.0 / 3.0) +
          0.15 * 50.0 +
          0.10 * 50.0;

      expect(result.score, closeTo(expected, 1e-9));
    });

    test('固定輸入回歸：綜合分數 = 55.096…', () {
      final result = computeFixedInput();

      // 定錨值。歷次變動：權重重分配（advanceRatio 0.25→0.35、移除
      // limitRatio 0.10）→ 53.75；漲跌比分母排除平盤 + 下界 0.20→0.15
      // （2026-08-29 稽核 H2）→ 55.096…
      expect(result.score, closeTo(55.09615384615385, 1e-9));
      expect(result.level, SentimentLevel.neutral);
    });

    // ================================================================
    // 漲跌比的分母（2026-08-29 領域稽核 H2）
    //
    // `AdvanceDecline.total = advance + decline + unchanged`，而 unchanged
    // 是真實計數（`market_overview_dao` 的 `price_change = 0`，實測佔上市櫃
    // 股 7.8–11.1%）。`_linearMap(v, lo, hi)` 的中點對應 50 分，所以設計上的
    // 「中性」是 ratio 落在上下界中點——但把平盤算進分母，那個中點就需要
    // 遠超過半數的股票上漲才達得到。
    //
    // 實測 597 個市場日：含平盤的中位 ratio 是 0.435、排除平盤是 0.481。
    // 舊界 (0.2, 0.8) 下中位日讀 39.2 分（偏恐慌側），而它是**最大權重的
    // 子指標**（0.35），缺指標時有效權重正規化還會把偏差放大到 8 分。
    // 2026-08-27 TWSE 589 漲 / 521 跌（真的偏多）卻讀 46.7。
    //
    // 修法兩件一起做——只改分母是半套，因為上下界是配著舊分母定的：
    //   分母排除平盤 + 下界 0.20 → **0.15**（新口徑實測 p5 = 0.149）
    //   上界 0.80 不動（新口徑實測 p95 = 0.801，本來就對）
    // 飽和率由 9.5%/2.8%（不對稱）變成 5%/5%，中位日從讀 39.2 變成讀 50.9。
    // 錨定方法與籌碼集中度那次相同：量母體分布、取百分位，不憑感覺選數字。
    // ================================================================
    // ⚠️ 本條只在**分母與上下界同時 revert** 時才紅（只 revert 分母 → 50.77、
    // 只 revert 界 → 55.1，兩者都 > 50）。真正隔離分母的是下一條「平盤家數不得
    // 改變分數」，隔離下界的是本檔的定錨值 55.096… 與權重測試裡的 35.0/65.0。
    test('🚨 8/27 TWSE 的實測值必須落在中性線的偏多側(稽核 H2)', () {
      // 2026-08-27 TWSE 實測值
      const withFlats = AdvanceDecline(
        advance: 589,
        decline: 521,
        unchanged: 117,
      );
      final score = MarketSentimentService.calculate(
        advanceDecline: withFlats,
        institutionalNetHistory: const [],
        turnoverHistory: const [],
        marginBalanceHistory: const [],
      ).subScores['advanceRatio']!;

      expect(score, greaterThan(50), reason: '589 漲 vs 521 跌是真的偏多,不該落在中性線的恐慌側');
    });

    test('🚨 平盤家數不得改變漲跌比的分數', () {
      double scoreOf(int unchanged) => MarketSentimentService.calculate(
        advanceDecline: AdvanceDecline(
          advance: 600,
          decline: 400,
          unchanged: unchanged,
        ),
        institutionalNetHistory: const [],
        turnoverHistory: const [],
        marginBalanceHistory: const [],
      ).subScores['advanceRatio']!;

      // 漲跌家數完全相同,只有平盤數不同 → 分數必須一致
      final base = scoreOf(0);
      for (final u in [50, 100, 200, 500]) {
        expect(scoreOf(u), closeTo(base, 1e-9), reason: 'unchanged=$u');
      }
    });

    test('🚨 中位日應讀在中性線附近(實測 ratio 0.481)', () {
      // 597 個市場日的中位 advance/(advance+decline) = 0.481
      final score = MarketSentimentService.calculate(
        advanceDecline: const AdvanceDecline(advance: 481, decline: 519),
        institutionalNetHistory: const [],
        turnoverHistory: const [],
        marginBalanceHistory: const [],
      ).subScores['advanceRatio']!;

      // 39.2 是**含平盤**的中位日；本 fixture 的 unchanged 為 0，舊碼在此讀
      // 46.83，離容差下緣 47.0 只有 0.17 分——會紅，但邊界很窄。
      expect(score, closeTo(50, 3), reason: '典型的一天應該讀在 50 附近,舊碼讀 46.83');
    });

    // ⚠️ 這條對**界的 revert 免疫**：ratio 0.9 與 0.1 在 (0.2,0.8) 與
    // (0.15,0.80) 下都飽和。它釘的是「量表沒有被拉平」，不是新的界。
    test('🚨 全場平盤時 advanceRatio 整條缺席,不得算成 0 分', () {
      // 邊界語意改變(稽核 A4):舊碼 `total > 0` 在 advance=decline=0、
      // unchanged>0 時算出 ratio 0 → 0 分＝「極度恐慌」。沒有漲跌家數
      // 就不該宣稱方向,缺席比 0 分誠實。
      final r = MarketSentimentService.calculate(
        advanceDecline: const AdvanceDecline(unchanged: 900),
        institutionalNetHistory: const [100, 100, 100, 100, 100],
        turnoverHistory: const [],
        marginBalanceHistory: const [],
      );
      expect(r.subScores.containsKey('advanceRatio'), isFalse);
      expect(r.subScores.keys, ['institutional']);
    });

    test('邊界:極端日仍要飽和(確認不是把量表拉平)', () {
      double scoreOf(int a, int d) => MarketSentimentService.calculate(
        advanceDecline: AdvanceDecline(advance: a, decline: d),
        institutionalNetHistory: const [],
        turnoverHistory: const [],
        marginBalanceHistory: const [],
      ).subScores['advanceRatio']!;

      expect(scoreOf(900, 100), 100.0); // ratio 0.9 > 上界 0.8
      expect(scoreOf(100, 900), 0.0); // ratio 0.1 遠低於下界
    });

    test('子指標缺漏時有效權重自動正規化', () {
      // 僅提供漲跌比與法人，缺量能/融資/產業
      final result = MarketSentimentService.calculate(
        advanceDecline: const AdvanceDecline(advance: 800, decline: 200),
        institutionalNetHistory: const [100, 100, 100, 100, 100],
        turnoverHistory: const [],
        marginBalanceHistory: const [],
      );

      // advanceRatio ratio=0.8 → 100.0；institutional → 75.0
      // 有效權重 = 0.35 + 0.25 = 0.60
      // (0.35*100 + 0.25*75) / 0.60 = (35 + 18.75) / 0.60 = 89.5833…
      expect(result.subScores.length, 2);
      expect(result.score, closeTo((0.35 * 100 + 0.25 * 75) / 0.60, 1e-9));
    });
  });

  group('MarketSentimentService.calculateHistoricalScores', () {
    // 以基準日 + 偏移天數建構帶日期序列（oldest→newest）。
    final base = DateTime(2026, 1, 1);
    DateTime day(int offset) => base.add(Duration(days: offset));

    /// 將 (dayOffset, value) 配對轉為帶日期序列。
    List<DatedValue> series(List<({int day, double value})> points) => [
      for (final p in points) (date: day(p.day), value: p.value),
    ];

    // 八個共同交易日（day 0..7）的對齊基準輸入。
    // advanceRatio 用遞增比值讓每日分數不同，便於辨識錯位。
    final advanceRatioCommon = series(const [
      (day: 0, value: 0.30),
      (day: 1, value: 0.40),
      (day: 2, value: 0.50),
      (day: 3, value: 0.55),
      (day: 4, value: 0.60),
      (day: 5, value: 0.65),
      (day: 6, value: 0.70),
      (day: 7, value: 0.75),
    ]);
    final turnoverCommon = series(const [
      (day: 0, value: 1000),
      (day: 1, value: 1100),
      (day: 2, value: 1200),
      (day: 3, value: 1300),
      (day: 4, value: 1250),
      (day: 5, value: 1400),
      (day: 6, value: 1500),
      (day: 7, value: 1600),
    ]);
    final institutionalCommon = series(const [
      (day: 0, value: 50),
      (day: 1, value: 80),
      (day: 2, value: -20),
      (day: 3, value: 60),
      (day: 4, value: 90),
      (day: 5, value: 30),
      (day: 6, value: 70),
      (day: 7, value: 100),
    ]);
    final marginCommon = series(const [
      (day: 0, value: 10000),
      (day: 1, value: 10100),
      (day: 2, value: 10050),
      (day: 3, value: 10200),
      (day: 4, value: 10300),
      (day: 5, value: 10250),
      (day: 6, value: 10400),
      (day: 7, value: 10500),
    ]);

    test('輸入皆對齊時（同一組日期）正常產生分數序列', () {
      final scores = MarketSentimentService.calculateHistoricalScores(
        advanceRatioHistory: advanceRatioCommon,
        institutionalNetHistory: institutionalCommon,
        turnoverHistory: turnoverCommon,
        marginBalanceHistory: marginCommon,
      );

      // 8 共同日，從第 5 日（index 4）起逐日計分 ⇒ 4 筆。
      expect(scores.length, advanceRatioCommon.length - 4);
      expect(scores, everyElement(inInclusiveRange(0.0, 100.0)));
    });

    test('日期錯位：法人/融資多出 2 個較舊日，結果只用共同日（排除錯位日）', () {
      // institutional 與 margin 在前面多 2 個 advanceRatio/turnover 沒有的舊日。
      // 若仍按 array index 拼接，這 2 個舊日會把不同交易日的資料混進同一筆分數。
      final institutionalExtra = series(const [
        (day: -2, value: 999), // advanceRatio/turnover 無此日
        (day: -1, value: 888), // advanceRatio/turnover 無此日
        (day: 0, value: 50),
        (day: 1, value: 80),
        (day: 2, value: -20),
        (day: 3, value: 60),
        (day: 4, value: 90),
        (day: 5, value: 30),
        (day: 6, value: 70),
        (day: 7, value: 100),
      ]);
      final marginExtra = series(const [
        (day: -2, value: 1), // advanceRatio/turnover 無此日
        (day: -1, value: 2), // advanceRatio/turnover 無此日
        (day: 0, value: 10000),
        (day: 1, value: 10100),
        (day: 2, value: 10050),
        (day: 3, value: 10200),
        (day: 4, value: 10300),
        (day: 5, value: 10250),
        (day: 6, value: 10400),
        (day: 7, value: 10500),
      ]);

      final misaligned = MarketSentimentService.calculateHistoricalScores(
        advanceRatioHistory: advanceRatioCommon,
        institutionalNetHistory: institutionalExtra,
        turnoverHistory: turnoverCommon,
        marginBalanceHistory: marginExtra,
      );

      // 對照組：把多出的舊日剔除，只留共同日的「正確對齊」輸入。
      final alignedReference = MarketSentimentService.calculateHistoricalScores(
        advanceRatioHistory: advanceRatioCommon,
        institutionalNetHistory: institutionalCommon,
        turnoverHistory: turnoverCommon,
        marginBalanceHistory: marginCommon,
      );

      // inner-join 後兩者必須完全相同：錯位的 day -2 / day -1 被排除，
      // 共同日的分數逐筆相等（證明未把不同日資料拼在一起）。
      expect(misaligned, hasLength(alignedReference.length));
      for (var i = 0; i < misaligned.length; i++) {
        expect(misaligned[i], closeTo(alignedReference[i], 1e-9));
      }
    });

    test('傳入順序被打亂時仍依日期重排（不依賴輸入順序）', () {
      // 將其中一個序列順序反轉（newest→oldest），結果應與正常順序一致。
      final shuffledTurnover = turnoverCommon.reversed.toList();

      final fromShuffled = MarketSentimentService.calculateHistoricalScores(
        advanceRatioHistory: advanceRatioCommon,
        institutionalNetHistory: institutionalCommon,
        turnoverHistory: shuffledTurnover,
        marginBalanceHistory: marginCommon,
      );
      final fromOrdered = MarketSentimentService.calculateHistoricalScores(
        advanceRatioHistory: advanceRatioCommon,
        institutionalNetHistory: institutionalCommon,
        turnoverHistory: turnoverCommon,
        marginBalanceHistory: marginCommon,
      );

      expect(fromShuffled, hasLength(fromOrdered.length));
      for (var i = 0; i < fromShuffled.length; i++) {
        expect(fromShuffled[i], closeTo(fromOrdered[i], 1e-9));
      }
    });

    test('共同日少於 5 天時回傳空列表（Z-score 樣本不足）', () {
      // 僅 4 個共同日（day 0..3），其餘日期各序列不重疊。
      final adShort = series(const [
        (day: 0, value: 0.4),
        (day: 1, value: 0.5),
        (day: 2, value: 0.6),
        (day: 3, value: 0.55),
      ]);
      final instShort = series(const [
        (day: 0, value: 10),
        (day: 1, value: 20),
        (day: 2, value: 30),
        (day: 3, value: 25),
      ]);
      final turnShort = series(const [
        (day: 0, value: 100),
        (day: 1, value: 110),
        (day: 2, value: 120),
        (day: 3, value: 115),
      ]);
      final marginShort = series(const [
        (day: 0, value: 1000),
        (day: 1, value: 1010),
        (day: 2, value: 1005),
        (day: 3, value: 1020),
      ]);

      final scores = MarketSentimentService.calculateHistoricalScores(
        advanceRatioHistory: adShort,
        institutionalNetHistory: instShort,
        turnoverHistory: turnShort,
        marginBalanceHistory: marginShort,
      );

      expect(scores, isEmpty);
    });

    test('完全無共同日時回傳空列表', () {
      final scores = MarketSentimentService.calculateHistoricalScores(
        advanceRatioHistory: advanceRatioCommon, // day 0..7
        institutionalNetHistory: series(const [
          (day: 100, value: 1),
          (day: 101, value: 2),
          (day: 102, value: 3),
          (day: 103, value: 4),
          (day: 104, value: 5),
        ]),
        turnoverHistory: turnoverCommon,
        marginBalanceHistory: marginCommon,
      );

      expect(scores, isEmpty);
    });
  });
}
