// Unit tests for the pure helpers exposed by mode_recommendation_provider —
// `isEligibleForMode` predicate + `computeBiasMa20ForHistory`.
//
// 2026-06-19 audit Action 5b: filter-aware mode assignment. Predicate is the
// single source of truth for which mode a stock is allowed to land in.

import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/constants/scoring_mode.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/data/database/dao/analysis_dao.dart';
import 'package:daredevil/presentation/providers/mode_recommendation_provider.dart';

void main() {
  group('isEligibleForMode — Mode A (momentumEntry) — 乖離率 gate', () {
    test('eligible when today and bias both within thresholds', () {
      expect(
        isEligibleForMode(
          mode: ScoringMode.momentumEntry,
          score: _score(short: 30),
          todayPct: 5.0,
          biasMa20: 5.0,
        ),
        isTrue,
      );
    });

    test('ineligible when today > +8%', () {
      expect(
        isEligibleForMode(
          mode: ScoringMode.momentumEntry,
          score: _score(short: 30),
          todayPct: 8.01,
          biasMa20: 0.0,
        ),
        isFalse,
      );
    });

    test('keeps stock at exact +8% today boundary (strict >)', () {
      expect(
        isEligibleForMode(
          mode: ScoringMode.momentumEntry,
          score: _score(short: 30),
          todayPct: 8.0,
          biasMa20: 0.0,
        ),
        isTrue,
      );
    });

    test('ineligible when MA20 bias > +15% (6742-style 已漲一波)', () {
      // 6742 澤米：乖離 +15.7% → 過度延伸、踢出
      expect(
        isEligibleForMode(
          mode: ScoringMode.momentumEntry,
          score: _score(short: 57),
          todayPct: 2.0,
          biasMa20: 15.7,
        ),
        isFalse,
      );
    });

    test('high score does NOT exempt extended stock (豁免已移除)', () {
      // 強訊號不再豁免延伸：score 90 但乖離 +20% → 仍踢出
      expect(
        isEligibleForMode(
          mode: ScoringMode.momentumEntry,
          score: _score(short: 90),
          todayPct: 2.0,
          biasMa20: 20.0,
        ),
        isFalse,
      );
    });

    test('keeps stock at exact +15% bias boundary (strict >)', () {
      expect(
        isEligibleForMode(
          mode: ScoringMode.momentumEntry,
          score: _score(short: 30),
          todayPct: 2.0,
          biasMa20: 15.0,
        ),
        isTrue,
      );
    });

    test('eligible when bias modest (貼均線早期移動)', () {
      expect(
        isEligibleForMode(
          mode: ScoringMode.momentumEntry,
          score: _score(short: 30),
          todayPct: 3.0,
          biasMa20: 8.0,
        ),
        isTrue,
      );
    });

    test('null bias (history < 20) treated as permissive', () {
      expect(
        isEligibleForMode(
          mode: ScoringMode.momentumEntry,
          score: _score(short: 30),
          todayPct: 3.0,
          biasMa20: null,
        ),
        isTrue,
      );
    });

    test('null today treated as pass (data lag / new IPO)', () {
      expect(
        isEligibleForMode(
          mode: ScoringMode.momentumEntry,
          score: _score(short: 30),
          todayPct: null,
          biasMa20: null,
        ),
        isTrue,
      );
    });

    test('today gap-up excludes even when bias modest (導去 Mode B)', () {
      // 從低於 MA20 跳上來：乖離還小但今天 +10% → today gate 擋
      expect(
        isEligibleForMode(
          mode: ScoringMode.momentumEntry,
          score: _score(short: 40),
          todayPct: 10.0,
          biasMa20: 3.0,
        ),
        isFalse,
      );
    });

    // **2026-07-16 當日跌幅下限**：「準備起漲」與當日重挫語意不相容，沿用
    // Mode C（回檔觀察）的崩跌分界 -4%。案例：1444 力麗 today -7.55%，score
    // 只靠 ROE_IMPROVING（非當日價格訊號）撐住、誤入 Mode A 起漲候選榜。
    group('當日跌幅下限（沿用 Mode C -4% 崩跌分界）', () {
      test('ineligible when today -7.55% (1444 力麗案例、重挫日不入起漲榜)', () {
        expect(
          isEligibleForMode(
            mode: ScoringMode.momentumEntry,
            score: _score(short: 30),
            todayPct: -7.55,
            biasMa20: 0.0,
          ),
          isFalse,
        );
      });

      test('eligible when today -3.9%（未達崩跌分界）', () {
        expect(
          isEligibleForMode(
            mode: ScoringMode.momentumEntry,
            score: _score(short: 30),
            todayPct: -3.9,
            biasMa20: 0.0,
          ),
          isTrue,
        );
      });

      test('keeps stock at exact -4.0% boundary（strict <，與 Mode C 共用分界）', () {
        expect(
          isEligibleForMode(
            mode: ScoringMode.momentumEntry,
            score: _score(short: 30),
            todayPct: -4.0,
            biasMa20: 0.0,
          ),
          isTrue,
        );
      });

      test('null today 仍 eligible（不知道就不擋，加了 floor 也一樣）', () {
        expect(
          isEligibleForMode(
            mode: ScoringMode.momentumEntry,
            score: _score(short: 30),
            todayPct: null,
            biasMa20: 0.0,
          ),
          isTrue,
        );
      });
    });
  });

  group('isEligibleForMode — Mode B (strengthObserve)', () {
    test('eligible when score > 0', () {
      expect(
        isEligibleForMode(
          mode: ScoringMode.strengthObserve,
          score: _score(short: 1),
          todayPct: null,
        ),
        isTrue,
      );
    });

    test('mode_b_rejects_zero_score_row', () {
      expect(
        isEligibleForMode(
          mode: ScoringMode.strengthObserve,
          score: _score(short: 0),
          todayPct: null,
        ),
        isFalse,
      );
    });

    test('mode_b_rejects_negative_score', () {
      // Rare: a Mode B rule scored negatively
      expect(
        isEligibleForMode(
          mode: ScoringMode.strengthObserve,
          score: _score(short: -15),
          todayPct: null,
        ),
        isFalse,
      );
    });

    test('mode_b_indifferent_to_price_filters', () {
      // 強勢觀察沒 price gate；只看 score 正性
      expect(
        isEligibleForMode(
          mode: ScoringMode.strengthObserve,
          score: _score(short: 50),
          todayPct: 10.0,
        ),
        isTrue,
      );
    });
  });

  // **2026-06-19 v2 audit — Mode C 重定義為「回檔觀察 / 強股回檔進場」**
  // - 從「負分警示」改「正分機會」tab
  // - 必過 gate：至少 1 條主訊號 rule fire（見 ModeFilters.modeCRequiredAnyOf）
  // - todayPct in [-4%, 0%]（回檔但非崩跌）
  // - score ≥ +12（最弱主訊號 kdHighPullback 的分數）
  group('isEligibleForMode — Mode C v2 (回檔觀察 pullbackEntry)', () {
    const mainSignalGate = {'PULLBACK_TO_MA20'};

    test('eligible when all conditions met (主訊號 + 今日 ≤0 + score ≥12)', () {
      expect(
        isEligibleForMode(
          mode: ScoringMode.weaknessObserve,
          score: _score(short: 15),
          todayPct: -1.5,
          triggeredReasonCodes: mainSignalGate,
        ),
        isTrue,
      );
    });

    test('mode_c_keeps_stock_at_exact_0pct_today_boundary', () {
      // strict `>` so 0.00% stays
      expect(
        isEligibleForMode(
          mode: ScoringMode.weaknessObserve,
          score: _score(short: 15),
          todayPct: 0.0,
          triggeredReasonCodes: mainSignalGate,
        ),
        isTrue,
      );
    });

    test('mode_c_drops_stock_at_tiny_positive_today', () {
      // 0.01% > 0% → 擋
      expect(
        isEligibleForMode(
          mode: ScoringMode.weaknessObserve,
          score: _score(short: 15),
          todayPct: 0.01,
          triggeredReasonCodes: mainSignalGate,
        ),
        isFalse,
      );
    });

    test('mode_c_drops_stock_at_min_today_boundary (-4.01%)', () {
      // 深 V 不算健康回檔
      expect(
        isEligibleForMode(
          mode: ScoringMode.weaknessObserve,
          score: _score(short: 15),
          todayPct: -4.01,
          triggeredReasonCodes: mainSignalGate,
        ),
        isFalse,
      );
    });

    test('mode_c_keeps_stock_at_exact_min_today (-4.00%)', () {
      // strict `<` so -4.00% stays
      expect(
        isEligibleForMode(
          mode: ScoringMode.weaknessObserve,
          score: _score(short: 15),
          todayPct: -4.0,
          triggeredReasonCodes: mainSignalGate,
        ),
        isTrue,
      );
    });

    test('mode_c_rejects_when_no_main_signal_fires (gate)', () {
      // 只有 warning rule fire、無主訊號 → drop
      expect(
        isEligibleForMode(
          mode: ScoringMode.weaknessObserve,
          score: _score(short: 15),
          todayPct: -1.0,
          triggeredReasonCodes: const {'RSI_EXTREME_OVERBOUGHT'},
        ),
        isFalse,
      );
    });

    test('mode_c_rejects_when_score_below_min_12', () {
      expect(
        isEligibleForMode(
          mode: ScoringMode.weaknessObserve,
          score: _score(short: 11),
          todayPct: -1.0,
          triggeredReasonCodes: mainSignalGate,
        ),
        isFalse,
      );
    });

    test('mode_c_keeps_at_exact_min_score_12', () {
      expect(
        isEligibleForMode(
          mode: ScoringMode.weaknessObserve,
          score: _score(short: 12),
          todayPct: -1.0,
          triggeredReasonCodes: mainSignalGate,
        ),
        isTrue,
      );
    });

    test(
      'mode_c_accepts_other_main_signals (HAMMER_AT_SUPPORT / KD_HIGH_PULLBACK)',
      () {
        for (final code in ['HAMMER_AT_SUPPORT', 'KD_HIGH_PULLBACK']) {
          expect(
            isEligibleForMode(
              mode: ScoringMode.weaknessObserve,
              score: _score(short: 15),
              todayPct: -1.0,
              triggeredReasonCodes: {code},
            ),
            isTrue,
            reason: 'main signal $code should pass gate',
          );
        }
      },
    );

    test('null_today_pct_with_gate_treated_as_pass — mode C', () {
      expect(
        isEligibleForMode(
          mode: ScoringMode.weaknessObserve,
          score: _score(short: 15),
          todayPct: null,
          triggeredReasonCodes: mainSignalGate,
        ),
        isTrue,
      );
    });

    test('empty_triggered_codes_default_fails_gate', () {
      // 預設 triggeredReasonCodes 空 set → gate 失敗
      expect(
        isEligibleForMode(
          mode: ScoringMode.weaknessObserve,
          score: _score(short: 15),
          todayPct: -1.0,
        ),
        isFalse,
      );
    });
  });

  // Mode B 從 v2 加 `todayPct > 0` 排他條件（讓 Mode C 接走回檔股）
  group('isEligibleForMode — Mode B v2 排他 today ≤ 0', () {
    test('mode_b_rejects_today_negative_to_let_mode_c_handle', () {
      expect(
        isEligibleForMode(
          mode: ScoringMode.strengthObserve,
          score: _score(short: 30),
          todayPct: -1.0,
        ),
        isFalse,
      );
    });

    test('mode_b_rejects_today_zero_to_let_mode_c_handle', () {
      // strict `<=` Mode C maxTodayPct(0) → today=0 也讓給 C
      expect(
        isEligibleForMode(
          mode: ScoringMode.strengthObserve,
          score: _score(short: 30),
          todayPct: 0.0,
        ),
        isFalse,
      );
    });

    test('mode_b_keeps_today_positive', () {
      expect(
        isEligibleForMode(
          mode: ScoringMode.strengthObserve,
          score: _score(short: 30),
          todayPct: 0.1,
        ),
        isTrue,
      );
    });
  });

  group('isEligibleForMode — neutral', () {
    test('neutral mode never eligible (not user-facing)', () {
      expect(
        isEligibleForMode(
          mode: ScoringMode.neutral,
          score: _score(short: 50),
          todayPct: 0.0,
        ),
        isFalse,
      );
    });
  });

  group('computeBiasMa20ForHistory', () {
    test('returns null when history is null', () {
      expect(computeBiasMa20ForHistory(null), isNull);
    });

    test('returns null when history.length < 20', () {
      final h = List.generate(19, (_) => _price(100));
      expect(computeBiasMa20ForHistory(h), isNull);
    });

    test('returns null when any close in MA20 window is null', () {
      final h = List.generate(20, (i) => _price(i == 5 ? null : 100));
      expect(computeBiasMa20ForHistory(h), isNull);
    });

    test('returns null when latest close is null', () {
      final h = List.generate(20, (i) => _price(i == 19 ? null : 100));
      expect(computeBiasMa20ForHistory(h), isNull);
    });

    test('returns null when MA20 is 0 (all zero closes)', () {
      final h = List.generate(20, (_) => _price(0));
      expect(computeBiasMa20ForHistory(h), isNull);
    });

    test('computes +10% bias (MA20=100, latest=110)', () {
      // 10×90 + 10×110 → MA20 = 100, latest = 110 → +10%
      final h = [
        ...List.generate(10, (_) => _price(90)),
        ...List.generate(10, (_) => _price(110)),
      ];
      expect(computeBiasMa20ForHistory(h), closeTo(10.0, 0.001));
    });

    test('negative bias when latest below MA20', () {
      // 10×110 + 10×90 → MA20 = 100, latest = 90 → -10%
      final h = [
        ...List.generate(10, (_) => _price(110)),
        ...List.generate(10, (_) => _price(90)),
      ];
      expect(computeBiasMa20ForHistory(h), closeTo(-10.0, 0.001));
    });

    test('uses last 20 closes only — ignores older history', () {
      // 前置極端值落在 MA20 窗口外、不影響
      final h = [
        _price(99999),
        ...List.generate(10, (_) => _price(90)),
        ...List.generate(10, (_) => _price(110)),
      ];
      expect(computeBiasMa20ForHistory(h), closeTo(10.0, 0.001));
    });
  });

  group('computeRet60dForHistory', () {
    test('returns null when history is null', () {
      expect(computeRet60dForHistory(null), isNull);
    });

    test('returns null when history.length < 61', () {
      final h = List.generate(60, (_) => _price(100));
      expect(computeRet60dForHistory(h), isNull);
    });

    test('returns null when oldest (index length-61) close is 0', () {
      final h = [
        _price(0),
        ...List.generate(59, (_) => _price(120)),
        _price(150),
      ];
      expect(computeRet60dForHistory(h), isNull);
    });

    test('returns null when oldest close is null', () {
      final h = [
        _price(null),
        ...List.generate(59, (_) => _price(120)),
        _price(150),
      ];
      expect(computeRet60dForHistory(h), isNull);
    });

    test('returns null when latest close is null', () {
      final h = [
        _price(100),
        ...List.generate(59, (_) => _price(120)),
        _price(null),
      ];
      expect(computeRet60dForHistory(h), isNull);
    });

    test('computes +50% (index length-61 = 100, last = 150)', () {
      final h = [
        _price(100), // [length-61]
        ...List.generate(59, (_) => _price(120)), // ignored
        _price(150), // last
      ];
      expect(computeRet60dForHistory(h), closeTo(50.0, 0.001));
    });

    test('uses index length-61, not 60 — accommodates longer history', () {
      // length 62：比較 index 1 (length-61) vs index 61 (last)
      final h = [
        _price(999), // ignored
        _price(200), // [length-61]
        ...List.generate(59, (_) => _price(210)),
        _price(220), // last
      ];
      expect(computeRet60dForHistory(h), closeTo(10.0, 0.001));
    });
  });

  group('computeRet20dForHistory', () {
    test('null when history < 21', () {
      expect(
        computeRet20dForHistory(List.generate(20, (_) => _price(100))),
        isNull,
      );
    });

    test('null when endpoint close null', () {
      final h = [
        _price(null),
        ...List.generate(19, (_) => _price(120)),
        _price(150),
      ];
      expect(computeRet20dForHistory(h), isNull);
    });

    test('computes +20% (index length-21 = 100, last = 120)', () {
      final h = [
        _price(100),
        ...List.generate(19, (_) => _price(110)),
        _price(120),
      ];
      expect(computeRet20dForHistory(h), closeTo(20.0, 0.001));
    });
  });

  group('computeIndustryMomentum', () {
    // 各股 21 根，最後一根 close 決定 20D 報酬（起點固定 100）
    List<DailyPriceEntry> hist(double last) => [
      _price(100),
      ...List.generate(19, (_) => _price(105)),
      _price(last),
    ];

    test('groups by industry and takes member median', () {
      final result = computeIndustryMomentum(
        priceHistories: {
          'A1': hist(110), // +10%
          'A2': hist(130), // +30%  → 半導體 median(10,30)=20
          'B1': hist(95), // -5%    → 金融 median(-5)=-5
        },
        industries: {'A1': '半導體業', 'A2': '半導體業', 'B1': '金融業'},
      );
      expect(result['半導體業'], closeTo(20.0, 0.001));
      expect(result['金融業'], closeTo(-5.0, 0.001));
    });

    test('skips null-industry / insufficient-history stocks', () {
      final result = computeIndustryMomentum(
        priceHistories: {
          'A1': hist(110),
          'NOIND': hist(200), // 無產業 → 略過
          'SHORT': List.generate(10, (_) => _price(100)), // 歷史不足 → 略過
        },
        industries: {'A1': '半導體業', 'NOIND': null, 'SHORT': '航運業'},
      );
      expect(result.keys, ['半導體業']);
      expect(result['半導體業'], closeTo(10.0, 0.001));
    });

    test('odd member count uses middle median', () {
      final result = computeIndustryMomentum(
        priceHistories: {'A': hist(110), 'B': hist(120), 'C': hist(140)},
        industries: {'A': '電子', 'B': '電子', 'C': '電子'},
      );
      // 報酬 10/20/40 → median 20
      expect(result['電子'], closeTo(20.0, 0.001));
    });
  });

  group('isMarketUptrend（regime gate）', () {
    // count 檔，每檔 len 根；最後一根對 [len-1-120] 漲 retPct%
    Map<String, List<DailyPriceEntry>> universe(
      int count,
      double retPct,
      int len,
    ) {
      return {
        for (var i = 0; i < count; i++)
          's$i': [
            ...List.generate(len - 1, (_) => _price(100)),
            _price(100 * (1 + retPct / 100)),
          ],
      };
    }

    test('有效股 < 50 → false（資料不足保守不套）', () {
      expect(isMarketUptrend(universe(40, 10, 121), 120), isFalse);
    });

    test('全市場 120D 平均報酬 > 0 → true（上升 regime）', () {
      expect(isMarketUptrend(universe(60, 10, 121), 120), isTrue);
    });

    test('全市場 120D 平均報酬 < 0 → false（下降 regime、gate 關）', () {
      expect(isMarketUptrend(universe(60, -10, 121), 120), isFalse);
    });

    test('歷史不足 lookback+1 的股票被略過 → 不足 50 檔 → false', () {
      expect(isMarketUptrend(universe(60, 10, 100), 120), isFalse);
    });
  });

  // **2026-07-17 fix**：isSignalTier 改吃 modeScores（跟 eligibility / 排名
  // 同一組分數），不再吃 daily_analysis 的 blended 總分——後者含 neutral
  // 警訊分數，會誤判（見 mode_recommendation_provider.dart isSignalTier
  // docstring 的完整 mechanism 說明，以及整合測試
  // mode_recommendation_neutral_drag_test.dart 的 7/17 audit 案例）。
  group('isSignalTier — 觀察層擋在 mode tab 之外', () {
    test('空 map（無 mode 訊號）→ false', () {
      expect(isSignalTier(const {}), isFalse);
    });

    test('唯一 mode 雙 horizon < 12（觀察層 8–11）→ false', () {
      expect(
        isSignalTier({ScoringMode.momentumEntry: _score(short: 11, long: 8)}),
        isFalse,
      );
    });

    test('唯一 mode 任一 horizon ≥ 12（成立訊號）→ true', () {
      expect(
        isSignalTier({ScoringMode.momentumEntry: _score(short: 12, long: 3)}),
        isTrue,
      );
      expect(
        isSignalTier({ScoringMode.strengthObserve: _score(short: 5, long: 20)}),
        isTrue,
      );
    });

    test('多 mode 皆 <12 → false（不是「取最高」而是每個 mode 各自判斷）', () {
      expect(
        isSignalTier({
          ScoringMode.momentumEntry: _score(short: 11, long: 11),
          ScoringMode.strengthObserve: _score(short: 9, long: 9),
        }),
        isFalse,
      );
    });

    test('多 mode 其中一個 ≥12 → true（任一 mode 成立即可）', () {
      expect(
        isSignalTier({
          ScoringMode.momentumEntry: _score(short: 5, long: 5),
          ScoringMode.weaknessObserve: _score(short: 12, long: 12),
        }),
        isTrue,
      );
    });
  });

  group('isEligibleForMode — Mode A — 會動底線（ret60 gate）', () {
    // 回測依據（2017-05~2026-07 calibration.db，A 價格包絡代理宇宙、
    // 次日開盤進場、cross-sectional demean）：60D<=0 桶 20D 前瞻超額
    // -0.39% vs >0 桶 +0.43%，差 -0.81pp、三分期符號全穩定且近段最強
    // （-1.26pp）。「起漲」候選需具備已證明的動能，長期弱勢反彈交給
    // 反轉類訊號與其他 tab。
    test('ineligible when 60D return <= 0（長期弱勢股反彈不入起漲）', () {
      expect(
        isEligibleForMode(
          mode: ScoringMode.momentumEntry,
          score: _score(short: 30),
          todayPct: 3.0,
          biasMa20: 5.0,
          ret60Pct: -10.0,
        ),
        isFalse,
      );
    });

    test('eligible when 60D return > 0', () {
      expect(
        isEligibleForMode(
          mode: ScoringMode.momentumEntry,
          score: _score(short: 30),
          todayPct: 3.0,
          biasMa20: 5.0,
          ret60Pct: 8.0,
        ),
        isTrue,
      );
    });

    test('ret60 null（history < 61）permissive 不擋，同其他 price gate 原則', () {
      expect(
        isEligibleForMode(
          mode: ScoringMode.momentumEntry,
          score: _score(short: 30),
          todayPct: 3.0,
          biasMa20: 5.0,
          ret60Pct: null,
        ),
        isTrue,
      );
    });

    test('ret60 gate 僅適用 Mode A：Mode B 不受影響', () {
      expect(
        isEligibleForMode(
          mode: ScoringMode.strengthObserve,
          score: _score(short: 30),
          todayPct: 2.0,
          ret60Pct: -10.0,
        ),
        isTrue,
      );
    });
  });

  group('isEtfIndustry — ETF 宇宙過濾（含上櫃ETF 補漏）', () {
    test("industry 'ETF' 與 '上櫃ETF' 皆判定為 ETF", () {
      // 2026-07-21 補漏：stock_master 兩種標記並存（ETF 158 檔＋上櫃ETF
      // 14 檔），舊 == 'ETF' 精確比對漏掉後者。
      expect(isEtfIndustry('ETF'), isTrue);
      expect(isEtfIndustry('上櫃ETF'), isTrue);
    });

    test('一般產業與 null 不受影響', () {
      expect(isEtfIndustry('半導體業'), isFalse);
      expect(isEtfIndustry('紡織業'), isFalse);
      expect(isEtfIndustry(null), isFalse);
    });
  });
}

/// 建立 ModeStockScore 的 helper（test 內最常用 short 分數）
ModeStockScore _score({
  required int short,
  int long = 0,
  String symbol = 'TEST',
}) => ModeStockScore(
  symbol: symbol,
  modeScoreShort: short.toDouble(),
  modeScoreLong: long.toDouble(),
);

/// 建立 DailyPriceEntry 的 helper — 只關心 close
DailyPriceEntry _price(double? close) =>
    DailyPriceEntry(symbol: 'TEST', date: DateTime(2026, 6, 18), close: close);
