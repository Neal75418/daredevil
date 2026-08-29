import 'package:daredevil/core/constants/chip_scoring_params.dart';
import 'package:daredevil/core/constants/chip_strength.dart';
import 'package:daredevil/domain/services/chip_analysis_service.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late ChipAnalysisService service;

  setUp(() {
    service = const ChipAnalysisService();
  });

  group('ChipAnalysisService Golden Master', () {
    test('compute returns expected score for neutral input', () {
      final result = service.compute(
        institutionalHistory: [],
        shareholdingHistory: [],
        marginHistory: [],
        dayTradingHistory: [],
        holdingDistribution: [],
        insiderHistory: [],
      );

      // 無訊號 = 停在 baseline 中點(50);全空輸入下 isInsufficient 為
      // true,UI 不會渲染這個評級,但分數語意仍須誠實:無訊號≠極弱
      expect(result.score, ChipScoringParams.baselineScore);
      expect(result.rating, ChipRating.neutral);
      expect(result.attitude, InstitutionalAttitude.neutral);
    });

    test('Institutional buy streak > 4 days adds large bonus', () {
      final history = List<DailyInstitutionalEntry>.generate(
        5,
        (i) => DailyInstitutionalEntry(
          symbol: '2330', // Dummy symbol
          date: DateTime(2023, 1, i + 1),
          foreignNet: 1000,
          investmentTrustNet: 0,
          dealerNet: 0,
        ),
      );

      final result = service.compute(
        institutionalHistory: history,
        shareholdingHistory: [],
        marginHistory: [],
        dayTradingHistory: [],
        holdingDistribution: [],
        insiderHistory: [],
      );

      // Base 50 + 30 (Large Bonus) = 80
      expect(result.score, 80);
      expect(result.attitude, InstitutionalAttitude.aggressiveBuy);
    });

    test('Margin increasing streak > 4 days penalizes score', () {
      final history = List<MarginTradingEntry>.generate(
        5,
        (i) => MarginTradingEntry(
          symbol: '2330', // Dummy symbol
          date: DateTime(2023, 1, i + 1),
          marginBalance: 1000.0 + (i * 100), // Increasing
          shortBalance: 0,
        ),
      );

      final result = service.compute(
        institutionalHistory: [],
        shareholdingHistory: [],
        marginHistory: history,
        dayTradingHistory: [],
        holdingDistribution: [],
        insiderHistory: [],
      );

      // Base 50 - 12 (Margin Increase Penalty) = 38——舊制被 clamp 夾成 0,
      // 與無訊號無法區分
      expect(result.score, 38);
    });

    test('High day trading ratio penalizes score', () {
      final history = <DayTradingEntry>[
        DayTradingEntry(
          symbol: '2330', // Dummy symbol
          date: DateTime(2023, 1, 1),
          dayTradingRatio: 65.0, // >= 60%（監管注意標準）
        ),
      ];

      final result = service.compute(
        institutionalHistory: [],
        shareholdingHistory: [],
        marginHistory: [],
        dayTradingHistory: history,
        holdingDistribution: [],
        insiderHistory: [],
      );

      // Base 50 - 8 (Day Trading Penalty) = 42
      expect(result.score, 42);
    });

    // 2026-07-18 門檻由 35% 移到 60%（TWSE 注意交易資訊異常標準）。
    // 35% 是市場平均、且在規則實際評估的流動股池裡正好是**中位數**（p52），
    // 全樣本 p76 —— 每 4 個股票日就有 1 個被扣分（觸發率 23.83%），
    // 把中位數叫「過熱」在語意上站不住腳。
    // 60% 為 p98.4、觸發率 1.64%，且與 TWSE 注意股當沖標準同基準（成交量）。
    //
    // 這兩筆測試用法人連買 +30 疊在 baseline 上,讓 −8 可被觀測。
    // (baseline 50 之前這裡是為了逃 clamp 的 workaround;現在 baseline
    // 本身已可觀測,保留連買基底是為了同時釘住「加分與扣分不互相干擾」)
    group('當沖扣分門檻 — 監管錨定 60%', () {
      List<DailyInstitutionalEntry> buyStreak() =>
          List<DailyInstitutionalEntry>.generate(
            5,
            (i) => DailyInstitutionalEntry(
              symbol: '2330',
              date: DateTime(2023, 1, i + 1),
              foreignNet: 1000,
              investmentTrustNet: 0,
              dealerNet: 0,
            ),
          );

      int scoreWithRatio(double ratio) => service
          .compute(
            institutionalHistory: buyStreak(),
            shareholdingHistory: [],
            marginHistory: [],
            dayTradingHistory: [
              DayTradingEntry(
                symbol: '2330',
                date: DateTime(2023, 1, 5),
                dayTradingRatio: ratio,
              ),
            ],
            holdingDistribution: [],
            insiderHistory: [],
          )
          .score;

      test('40% 不再扣分（舊 35% 門檻會誤扣；40% 僅 p83.8）', () {
        // 50 + 30 (法人連買) + 0 = 80
        expect(scoreWithRatio(40.0), 80);
      });

      test('65% 仍扣分（超過監管 60% 注意標準）', () {
        // 50 + 30 (法人連買) − 8 (當沖扣分) = 72
        expect(scoreWithRatio(65.0), 72);
      });

      test('剛好 60% 觸發扣分（邊界）', () {
        expect(scoreWithRatio(60.0), 72);
      });

      test('59.9% 不扣分（邊界下緣）', () {
        expect(scoreWithRatio(59.9), 80);
      });
    });

    test('Institutional buy streak == 2 days adds small bonus', () {
      final history = List<DailyInstitutionalEntry>.generate(
        2,
        (i) => DailyInstitutionalEntry(
          symbol: '2330',
          date: DateTime(2023, 1, i + 1),
          foreignNet: 1000,
          investmentTrustNet: 0,
          dealerNet: 0,
        ),
      );

      final result = service.compute(
        institutionalHistory: history,
        shareholdingHistory: [],
        marginHistory: [],
        dayTradingHistory: [],
        holdingDistribution: [],
        insiderHistory: [],
      );

      // Base 50 + 15 (Small Bonus) = 65
      expect(result.score, 65);
    });

    test('Institutional sell streak == 2 days penalizes score', () {
      final history = List<DailyInstitutionalEntry>.generate(
        2,
        (i) => DailyInstitutionalEntry(
          symbol: '2330',
          date: DateTime(2023, 1, i + 1),
          foreignNet: -1000,
          investmentTrustNet: 0,
          dealerNet: 0,
        ),
      );

      final result = service.compute(
        institutionalHistory: history,
        shareholdingHistory: [],
        marginHistory: [],
        dayTradingHistory: [],
        holdingDistribution: [],
        insiderHistory: [],
      );

      // Base 50 - 12 (Small Penalty) = 38; 2 sell days → neutral attitude
      expect(result.score, 38);
      expect(result.attitude, InstitutionalAttitude.neutral);
    });

    test('Institutional sell streak >= 4 days adds large penalty', () {
      final history = List<DailyInstitutionalEntry>.generate(
        4,
        (i) => DailyInstitutionalEntry(
          symbol: '2330',
          date: DateTime(2023, 1, i + 1),
          foreignNet: -1000,
          investmentTrustNet: 0,
          dealerNet: 0,
        ),
      );

      final result = service.compute(
        institutionalHistory: history,
        shareholdingHistory: [],
        marginHistory: [],
        dayTradingHistory: [],
        holdingDistribution: [],
        insiderHistory: [],
      );

      // Base 50 - 25 (Large Penalty) = 25; attitude should be aggressiveSell
      expect(result.score, 25);
      expect(result.attitude, InstitutionalAttitude.aggressiveSell);
    });
  });

  group('資料充足性(全面稽核 MEDIUM-HIGH #1)', () {
    // 六個輸入全空時各調整項回 0 → 分數停在 baseline、被判成「中性」。
    // 上櫃股的持股/當沖/融資覆蓋系統性稀疏——「沒被量測」與「實測中性」
    // 在 UI 上逐 pixel 相同,仍是謊報,使用者可能據此誤讀一檔只是沒資料
    // 的股票。
    final service = ChipAnalysisService();

    ChipStrengthResult run({
      List<DailyInstitutionalEntry> inst = const [],
      List<ShareholdingEntry> share = const [],
      List<MarginTradingEntry> margin = const [],
      List<DayTradingEntry> day = const [],
      List<HoldingDistributionEntry> holding = const [],
      List<InsiderHoldingEntry> insider = const [],
    }) => service.compute(
      institutionalHistory: inst,
      shareholdingHistory: share,
      marginHistory: margin,
      dayTradingHistory: day,
      holdingDistribution: holding,
      insiderHistory: insider,
    );

    DailyInstitutionalEntry instRow(int d) => DailyInstitutionalEntry(
      symbol: '6104',
      date: DateTime(2026, 8, d),
      foreignNet: 1000,
    );
    ShareholdingEntry shareRow(int d) => ShareholdingEntry(
      symbol: '6104',
      date: DateTime(2026, 8, d),
      foreignSharesRatio: 20.0,
    );
    MarginTradingEntry marginRow(int d) => MarginTradingEntry(
      symbol: '6104',
      date: DateTime(2026, 8, d),
      marginBuy: 100,
    );

    test('🚨 六域全空 → isInsufficient,不得評「極弱」當事實', () {
      final r = run();
      expect(r.measuredDomains, 0);
      expect(
        r.isInsufficient,
        isTrue,
        reason: '沒被量測 ≠ 實測極弱——UI 據此顯示「資料不足」而非 weak 徽章',
      );
    });

    test('只有一域可計算 → 仍 insufficient(門檻 2)', () {
      // dayTrading 走 history.last,單列即可計算——用它當「真的量測了
      // 一域」的代表
      final r = run(
        day: [
          DayTradingEntry(
            symbol: '6104',
            date: DateTime(2026, 8, 20),
            dayTradingRatio: 10.0,
          ),
        ],
      );
      expect(r.measuredDomains, 1);
      expect(r.isInsufficient, isTrue);
    });

    test('🚨 孤列資料不算已量測——上櫃稀疏股(1 列融資+1 列持股)結構上保證 0 分', () {
      // 2026-08-29 review 實測反例:isNotEmpty 當充足性 proxy 時,這個
      // fixture 得到 measuredDomains=2 → 照樣渲染「偏弱 0/100」。但
      // _marginAdjustment 湊不出 pair、_shareholdingAdjustment 有
      // length<2 守衛——兩域的貢獻是**保證為 0**,不是「量測結果中性」。
      final r = run(margin: [marginRow(20)], share: [shareRow(20)]);
      expect(r.measuredDomains, 0);
      expect(r.isInsufficient, isTrue);
    });

    test('兩域確實可計算 → 可評級,且分數證明評級非捏造', () {
      // insider(單列可計算:內部人買進)+ 集中度(大戶 ≥ 高門檻)——
      // 斷言精確分數,證明「可評級」的 fixture 真的能產生非零訊號,
      // 不再替 score=0 → weak 的洞背書
      final r = run(
        insider: [
          InsiderHoldingEntry(
            symbol: '6104',
            date: DateTime(2026, 8, 20),
            sharesChange: 500,
            pledgeRatio: 0,
          ),
        ],
        holding: [
          HoldingDistributionEntry(
            symbol: '6104',
            date: DateTime(2026, 8, 20),
            level: '1,000以上',
            percent: 90.0, // ≥85(p90)拿最高檔加分——門檻百分位錨定後 65 落中帶
          ),
        ],
      );
      expect(r.measuredDomains, 2);
      expect(r.isInsufficient, isFalse);
      expect(
        r.score,
        ChipScoringParams.baselineScore +
            ChipScoringParams.insiderBuyBonus +
            ChipScoringParams.concentrationVeryHighBonus,
      );
    });

    test('各域可計算下限:inst/share 要 2 列,margin 要 streak+1 列', () {
      // 下限的定義:資料量足以讓對應 adjustment **可能**吐出非零值。
      // share 的 2 是結構性(頭尾才有 diff),刻意用字面值釘住,不引常數
      expect(run(inst: [instRow(20)]).measuredDomains, 0);
      expect(
        run(
          inst: List.generate(
            ChipScoringParams.instStreakSmallDays,
            (i) => instRow(20 + i),
          ),
        ).measuredDomains,
        1,
      );

      expect(run(share: [shareRow(20)]).measuredDomains, 0);
      expect(run(share: [shareRow(20), shareRow(21)]).measuredDomains, 1);

      // marginStreakDays 個連續 pair 需要 streak+1 列;少一列即保證 0
      expect(
        run(
          margin: List.generate(
            ChipScoringParams.marginStreakDays,
            (i) => marginRow(20 + i),
          ),
        ).measuredDomains,
        0,
      );
      expect(
        run(
          margin: List.generate(
            ChipScoringParams.marginStreakDays + 1,
            (i) => marginRow(20 + i),
          ),
        ).measuredDomains,
        1,
      );
    });
  });

  group('集中度百分位錨定(2026-08-29 review Critical:3.4× 偏多來源)', () {
    // 舊制 ≥60 加分,但 60 恰為母體中位數 p50.9(production DB 2,573 檔
    // 實測)——過半股票帶「高度集中」加分、域只加不減,是籌碼分數 3.4×
    // 偏多偏斜的唯一來源。重定為百分位對稱錨定:
    //   ≥85(p90)+20 | ≥75(p75)+8 | 45–75 中性 | ≤45(p25)−8 | ≤30(p10)−20
    final service = const ChipAnalysisService();

    int scoreWith(List<HoldingDistributionEntry> holding) => service
        .compute(
          institutionalHistory: [],
          shareholdingHistory: [],
          marginHistory: [],
          dayTradingHistory: [],
          holdingDistribution: holding,
          insiderHistory: [],
        )
        .score;

    HoldingDistributionEntry big(double? pct, {String level = '1,000以上'}) =>
        HoldingDistributionEntry(
          symbol: '2330',
          date: DateTime(2026, 8, 28),
          level: level,
          percent: pct,
        );

    test('五帶邊界(含等於的方向與生產語意一致)', () {
      const base = ChipScoringParams.baselineScore;
      expect(scoreWith([big(85.0)]), base + 20, reason: '≥85 → +20');
      expect(scoreWith([big(84.9)]), base + 8, reason: '75–85 → +8');
      expect(scoreWith([big(75.0)]), base + 8);
      expect(scoreWith([big(74.9)]), base, reason: '中帶(45–75)不動分');
      expect(scoreWith([big(45.1)]), base);
      expect(scoreWith([big(45.0)]), base - 8, reason: '≤45 → −8');
      expect(scoreWith([big(30.1)]), base - 8);
      expect(scoreWith([big(30.0)]), base - 20, reason: '≤30 → −20');
    });

    test('跨級距加總維持既有行為:40+46=86 → +20', () {
      expect(
        scoreWith([big(40.0, level: '800-999'), big(46.0)]),
        ChipScoringParams.baselineScore + 20,
      );
    });

    test('🚨 大戶列 percent 為 null → 不可計算,禁止捏造「分散」懲罰', () {
      // 雙向計分後 null 的代價變重:舊制 null 頂多少加分,現在部分加總
      // 會把「缺值」算成低集中 → 扣分——null 不是 0(專案反覆踩過的坑)
      final r = service.compute(
        institutionalHistory: [],
        shareholdingHistory: [],
        marginHistory: [],
        dayTradingHistory: [],
        holdingDistribution: [
          big(null),
          big(90.0, level: '800-999'),
        ],
        insiderHistory: [],
      );
      expect(r.score, ChipScoringParams.baselineScore, reason: '缺值 → 不動分');
      expect(r.measuredDomains, 0, reason: '不可計算 = 未量測');
    });

    test('🚨 無任何大戶級距列 → 不可計算,不是「大戶 0% = 極度分散」', () {
      final r = service.compute(
        institutionalHistory: [],
        shareholdingHistory: [],
        marginHistory: [],
        dayTradingHistory: [],
        holdingDistribution: [big(30.0, level: '100-200')],
        insiderHistory: [],
      );
      expect(r.score, ChipScoringParams.baselineScore);
      expect(r.measuredDomains, 0);
    });
  });

  group('外資持股端點 null(2026-08-29 靜默稽核 #6:null 不是 0)', () {
    // 窗端點是 null-ratio 列時,舊碼 `?? 0` 讓 diff 變成「從 0 增到現值」
    // ——持股 25% 的股票憑空拿最大加分(反向則誤發 penalty)。null=沒量
    // 到,不是 0%;與集中度域同一修法:端點缺值 → 不可計算 → 不動分、
    // 不算已量測。
    final service = const ChipAnalysisService();

    ChipStrengthResult runShare(List<double?> ratios) => service.compute(
      institutionalHistory: [],
      shareholdingHistory: [
        for (var i = 0; i < ratios.length; i++)
          ShareholdingEntry(
            symbol: '2330',
            date: DateTime(2026, 8, 20 + i),
            foreignSharesRatio: ratios[i],
          ),
      ],
      marginHistory: [],
      dayTradingHistory: [],
      holdingDistribution: [],
      insiderHistory: [],
    );

    test('🚨 舊端點 null → 不得把 25% 當成「從 0 增持」發最大加分', () {
      final r = runShare([null, 25.0]);
      expect(r.score, ChipScoringParams.baselineScore, reason: '不可計算=不動分');
      expect(r.measuredDomains, 0, reason: '端點缺值=未量測');
    });

    test('🚨 新端點 null → 不得誤發最大減持 penalty', () {
      final r = runShare([25.0, null]);
      expect(r.score, ChipScoringParams.baselineScore);
      expect(r.measuredDomains, 0);
    });

    test('兩端點都有值 → 照常計算(對照組)', () {
      final r = runShare([20.0, 20.7]); // diff +0.7 ≥ large 0.5
      expect(
        r.score,
        ChipScoringParams.baselineScore +
            ChipScoringParams.foreignIncreaseLargeBonus,
      );
      expect(r.measuredDomains, 1);
    });

    test('中間列 null 不影響(只看頭尾)', () {
      final r = runShare([20.0, null, 20.7]);
      expect(
        r.score,
        ChipScoringParams.baselineScore +
            ChipScoringParams.foreignIncreaseLargeBonus,
      );
    });
  });

  group('baseline 50 重定標(2026-08-29 review 射程外發現)', () {
    // 六個調整項是**有正負號的雙向訊號**,但從 0 起算再 clamp(0,100) 等於
    // 砍掉負半軸:「法人連賣的極弱股」與「什麼訊號都沒有的中性股」都是
    // 0 分、同一顆「極弱」徽章——與「沒資料畫成極弱」同一類謊言,主角
    // 換成 neutral。baseline 移到 50 後:中性=50=中性帶、偏空的扣分終於
    // 看得見、排序單調性保持。
    final service = const ChipAnalysisService();

    test('🚨 六域齊全且全部中性 → baseline 分、評「中性」,不得評「極弱」', () {
      DailyInstitutionalEntry inst(int d) => DailyInstitutionalEntry(
        symbol: '2330',
        date: DateTime(2026, 8, d),
        foreignNet: 0,
      );
      ShareholdingEntry share(int d) => ShareholdingEntry(
        symbol: '2330',
        date: DateTime(2026, 8, d),
        foreignSharesRatio: 20.0,
      );
      MarginTradingEntry margin(int d) => MarginTradingEntry(
        symbol: '2330',
        date: DateTime(2026, 8, d),
        marginBalance: 1000,
        shortBalance: 100,
      );
      final r = service.compute(
        institutionalHistory: [inst(20), inst(21)],
        shareholdingHistory: [share(20), share(21)],
        marginHistory: List.generate(
          ChipScoringParams.marginStreakDays + 1,
          (i) => margin(20 + i),
        ),
        dayTradingHistory: [
          DayTradingEntry(
            symbol: '2330',
            date: DateTime(2026, 8, 24),
            dayTradingRatio: 10.0,
          ),
        ],
        holdingDistribution: [
          HoldingDistributionEntry(
            symbol: '2330',
            date: DateTime(2026, 8, 24),
            level: '1,000以上',
            percent: 60.0, // 中帶(45–75)——恰為母體中位數,「常態」不動分
          ),
        ],
        insiderHistory: [
          InsiderHoldingEntry(
            symbol: '2330',
            date: DateTime(2026, 8, 24),
            sharesChange: 0,
            pledgeRatio: 0,
          ),
        ],
      );
      expect(r.isInsufficient, isFalse);
      expect(r.score, ChipScoringParams.baselineScore);
      expect(r.rating, ChipRating.neutral);
    });

    test('🚨 偏空訊號不再被 clamp 吃掉——極弱與中性可區分', () {
      // 法人連賣 4 天(−25):舊制 0−25 clamp 成 0,與中性股逐 pixel 相同
      final sells = List.generate(
        ChipScoringParams.instStreakLargeDays,
        (i) => DailyInstitutionalEntry(
          symbol: '2330',
          date: DateTime(2026, 8, 20 + i),
          foreignNet: -1000,
        ),
      );
      final r = service.compute(
        institutionalHistory: sells,
        shareholdingHistory: [],
        marginHistory: [],
        dayTradingHistory: [
          DayTradingEntry(
            symbol: '2330',
            date: DateTime(2026, 8, 24),
            dayTradingRatio: 10.0,
          ),
        ],
        holdingDistribution: [],
        insiderHistory: [],
      );
      expect(
        r.score,
        ChipScoringParams.baselineScore +
            ChipScoringParams.instSellStreakLargePenalty,
      );
      expect(r.rating, ChipRating.bearish);
      expect(r.score, lessThan(ChipScoringParams.baselineScore));
    });

    test('分帶邊界:±9 中性、±10~29 偏多/偏空、±30 起極強/極弱(對稱)', () {
      expect(ChipRating.fromScore(80), ChipRating.strong);
      expect(ChipRating.fromScore(79), ChipRating.bullish);
      expect(ChipRating.fromScore(60), ChipRating.bullish);
      expect(ChipRating.fromScore(59), ChipRating.neutral);
      expect(ChipRating.fromScore(41), ChipRating.neutral);
      expect(ChipRating.fromScore(40), ChipRating.bearish);
      expect(ChipRating.fromScore(21), ChipRating.bearish);
      expect(ChipRating.fromScore(20), ChipRating.weak);
    });
  });
}
