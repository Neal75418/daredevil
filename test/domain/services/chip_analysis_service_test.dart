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

      // Base score is 0 (no signals = no score)
      expect(result.score, 0);
      expect(result.rating, ChipRating.weak);
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

      // Base 0 + 30 (Large Bonus) = 30
      expect(result.score, 30);
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

      // Base 0 - 12 (Margin Increase Penalty) = 0 (clamped)
      expect(result.score, 0);
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

      // Base 0 - 8 (Day Trading Penalty) = 0 (clamped)
      expect(result.score, 0);
    });

    // 2026-07-18 門檻由 35% 移到 60%（TWSE 注意交易資訊異常標準）。
    // 35% 是市場平均、且在規則實際評估的流動股池裡正好是**中位數**（p52），
    // 全樣本 p76 —— 每 4 個股票日就有 1 個被扣分（觸發率 23.83%），
    // 把中位數叫「過熱」在語意上站不住腳。
    // 60% 為 p98.4、觸發率 1.64%，且與 TWSE 注意股當沖標準同基準（成交量）。
    //
    // 這兩筆測試用法人連買 +30 當基底，讓 −8 可被觀測
    // （原測試 base 0 會被 clamp(0,100) 夾成 0，扣或不扣都是 0、無鑑別力）。
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
        // 30 (法人連買) + 0 = 30
        expect(scoreWithRatio(40.0), 30);
      });

      test('65% 仍扣分（超過監管 60% 注意標準）', () {
        // 30 (法人連買) − 8 (當沖扣分) = 22
        expect(scoreWithRatio(65.0), 22);
      });

      test('剛好 60% 觸發扣分（邊界）', () {
        expect(scoreWithRatio(60.0), 22);
      });

      test('59.9% 不扣分（邊界下緣）', () {
        expect(scoreWithRatio(59.9), 30);
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

      // Base 0 + 15 (Small Bonus) = 15
      expect(result.score, 15);
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

      // Base 0 - 12 (Small Penalty) = 0 (clamped); 2 sell days → neutral attitude
      expect(result.score, 0);
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

      // Base 0 - 25 (Large Penalty) = 0 (clamped); attitude should be aggressiveSell
      expect(result.score, 0);
      expect(result.attitude, InstitutionalAttitude.aggressiveSell);
    });
  });

  group('資料充足性(全面稽核 MEDIUM-HIGH #1)', () {
    // score 從 0 起算、六個輸入全空時各調整項回 0 → 0 分被 fromScore 判成
    // weak(極弱)直接渲染。上櫃股的持股/當沖/融資覆蓋系統性稀疏——「沒被
    // 量測」與「實測極弱」在 UI 上逐 pixel 相同,使用者可能因假評級放棄
    // 一檔只是沒資料的股票。
    final service = ChipAnalysisService();

    ChipStrengthResult run({
      List<DailyInstitutionalEntry> inst = const [],
      List<ShareholdingEntry> share = const [],
      List<MarginTradingEntry> margin = const [],
    }) => service.compute(
      institutionalHistory: inst,
      shareholdingHistory: share,
      marginHistory: margin,
      dayTradingHistory: [],
      holdingDistribution: [],
      insiderHistory: [],
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

    test('只有一域有資料 → 仍 insufficient(門檻 2)', () {
      final r = run(
        inst: [
          DailyInstitutionalEntry(
            symbol: '6104',
            date: DateTime(2026, 8, 20),
            foreignNet: 1000,
          ),
        ],
      );
      expect(r.measuredDomains, 1);
      expect(r.isInsufficient, isTrue);
    });

    test('兩域有資料 → 可評級', () {
      final r = run(
        inst: [
          DailyInstitutionalEntry(
            symbol: '6104',
            date: DateTime(2026, 8, 20),
            foreignNet: 1000,
          ),
        ],
        margin: [
          MarginTradingEntry(
            symbol: '6104',
            date: DateTime(2026, 8, 20),
            marginBuy: 100,
          ),
        ],
      );
      expect(r.measuredDomains, 2);
      expect(r.isInsufficient, isFalse);
    });
  });
}
