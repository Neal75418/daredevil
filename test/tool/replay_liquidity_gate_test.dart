// Replay 校準語料的流動性宇宙 parity(生產一致性 (d),findings #47)
//
// 生產只評分候選層過流動性門檻的股票(PriceDao.getMedianTurnoverBatch +
// CandidateSelector.isLiquid:20 日中位成交值 ≥ 3,000 萬,窗界=全市場第
// 20 新交易日、volume/close 皆非 null 才算有效日、有效日 < 10 → permissive
// 放行)。replay 原本評 stock_master 全部——實測 64% 校準語料是生產永不
// 評分的 stock-day。
//
// **ground truth = 生產 DAO 本身**:(d-1) 對每個 (symbol, 交易日) 全掃,
// 把 computeLiquidityEligibility 的判定與 getMedianTurnoverBatch 逐對比對
// ——任何窗界/中位數/permissive 語意的漂移都會在剖面差異處現形。
//
// 生產另有「自選清單豁免」,replay **刻意不模擬**:把今天的自選注入全部
// 歷史日等於 lookahead,且那是使用者 overlay、不是規則母體(門檻本身
// 才是)。此 delta 記載於 tool/replay_calibrator.dart 檔頭。
import 'package:drift/drift.dart' show Value;
import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:daredevil/core/constants/rule_params.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/domain/models/models.dart';
import 'package:daredevil/domain/services/analysis_service.dart';
import 'package:daredevil/domain/services/rule_engine.dart';
import 'package:daredevil/domain/services/rules/stock_rules.dart';
import '../../tool/replay_calibrator.dart';

class _MockAnalysisService extends Mock implements AnalysisService {}

class _MockRuleEngine extends Mock implements RuleEngine {}

void main() {
  late AppDatabase db;
  late _MockAnalysisService mockAnalysis;
  late _MockRuleEngine mockRuleEngine;

  final first = DateTime(2024, 1, 1);
  DateTime day(int i) => first.add(Duration(days: i));

  setUpAll(() {
    registerFallbackValue(
      AnalysisContext(
        evaluationTime: DateTime(2024),
        trendState: TrendState.up,
      ),
    );
    registerFallbackValue(const StockData(symbol: '', prices: []));
    registerFallbackValue(
      const AnalysisResult(
        trendState: TrendState.up,
        reversalState: ReversalState.none,
        supportLevel: 0,
        resistanceLevel: 0,
      ),
    );
  });

  setUp(() async {
    db = AppDatabase.forTesting();
    mockAnalysis = _MockAnalysisService();
    mockRuleEngine = _MockRuleEngine();
    when(() => mockAnalysis.analyzeStock(any())).thenReturn(
      const AnalysisResult(
        trendState: TrendState.up,
        reversalState: ReversalState.none,
        supportLevel: 100,
        resistanceLevel: 120,
      ),
    );
    when(
      () => mockAnalysis.buildContext(
        any(),
        priceHistory: any(named: 'priceHistory'),
        marketData: any(named: 'marketData'),
        evaluationTime: any(named: 'evaluationTime'),
        isMarketUptrend: any(named: 'isMarketUptrend'),
      ),
    ).thenReturn(
      AnalysisContext(
        evaluationTime: DateTime(2024, 2, 1),
        trendState: TrendState.up,
      ),
    );
    when(() => mockRuleEngine.evaluateStock(any(), any())).thenReturn(const []);
  });

  tearDown(() async => db.close());

  /// 六種流動性剖面,80 個全市場交易日。每種剖面對應一類要釘住的語意:
  ///
  /// - LIQD:100M 恆過門檻
  /// - ILLQ:10M 恆不過(判定成立後)
  /// - EDGE:恰 30,000,000——邊界含等於(>= 而非 >)
  /// - EDGB:29,999,900——邊界下緣
  /// - SPRS:80 bar 但僅 9 bar 的 volume 非 null → 有效日 9 < 10 → permissive
  /// - SKEW:週期 20 的 11 低(10M)/9 高(100M)——任何 20 窗中位=10M、
  ///   平均≈50.5M,中位數↔平均的突變在此現形
  /// - GAPY:只在偶數日有 bar(隔日停牌)——窗界必須取**全市場**第 20 新
  ///   交易日(自身 bar 較少),「取自身最近 20 bar」的突變在轉折段現形
  Future<Map<String, List<DailyPriceEntry>>> seedMarket() async {
    const days = 80;
    final specs = <String, (double? Function(int), bool Function(int))>{
      // (volume(i), hasBar(i))
      'LIQD': ((i) => 1000000, (i) => true),
      'ILLQ': ((i) => 100000, (i) => true),
      'EDGE': ((i) => 300000, (i) => true),
      'EDGB': ((i) => 299999, (i) => true),
      'SPRS': ((i) => i < 9 ? 100000.0 : null, (i) => true),
      'SKEW': ((i) => (i % 20) < 11 ? 100000.0 : 1000000.0, (i) => true),
      'GAPY': ((i) => i < 40 ? 1000000.0 : 100000.0, (i) => i.isEven),
    };
    final result = <String, List<DailyPriceEntry>>{};
    for (final e in specs.entries) {
      final (volumeAt, hasBar) = e.value;
      await db.upsertStocks([
        StockMasterCompanion.insert(symbol: e.key, name: e.key, market: 'TWSE'),
      ]);
      final list = [
        for (var i = 0; i < days; i++)
          if (hasBar(i))
            DailyPriceEntry(
              symbol: e.key,
              date: day(i),
              close: 100.0,
              volume: volumeAt(i),
            ),
      ];
      result[e.key] = list;
      await db.insertPrices([
        for (final p in list)
          DailyPriceCompanion.insert(
            symbol: p.symbol,
            date: p.date,
            close: Value(p.close),
            volume: Value(p.volume),
          ),
      ]);
    }
    return result;
  }

  test('🚨 (d-1) 全掃 parity:每個 (symbol, 交易日) 與生產 DAO 判定逐對相等', () async {
    final prices = await seedMarket();
    final eligibility = ReplayCalibrator.computeLiquidityEligibility(prices);

    var pairsChecked = 0;
    for (var d = 0; d < 80; d++) {
      final median = await db.getMedianTurnoverBatch(
        endDate: day(d),
        windowDays: RuleParams.liquidityMedianWindowDays,
        minDataDays: RuleParams.liquidityMinDataDays,
      );
      for (final e in prices.entries) {
        final barIdx = e.value.indexWhere((p) => p.date == day(d));
        if (barIdx < 0) continue; // 該檔當日停牌,replay 本來就無此評估日
        final m = median[e.key];
        final productionLiquid =
            m == null || m >= RuleParams.liquidityMinMedianTurnoverNtd;
        expect(
          eligibility[e.key]![barIdx],
          productionLiquid,
          reason:
              '${e.key} @ day $d:replay=${eligibility[e.key]![barIdx]} '
              'production=$productionLiquid (median=$m)',
        );
        pairsChecked++;
      }
    }
    // sanity floor:全掃真的掃了東西(6 全日剖面 × 80 日 + GAPY 40 日)
    expect(pairsChecked, greaterThanOrEqualTo(500));
  });

  test('(d-2) 邊界語意:恰 30M 過、29,999,900 不過(判定成立段)', () async {
    final prices = await seedMarket();
    final eligibility = ReplayCalibrator.computeLiquidityEligibility(prices);
    // day 79 = 全市場第 80 個交易日,窗完整、兩檔都有 20 個有效日
    final idxEdge = prices['EDGE']!.indexWhere((p) => p.date == day(79));
    final idxEdgb = prices['EDGB']!.indexWhere((p) => p.date == day(79));
    expect(eligibility['EDGE']![idxEdge], isTrue, reason: '>= 門檻,等於要過');
    expect(eligibility['EDGB']![idxEdgb], isFalse);
  });

  test('(d-3) permissive 語意:有效日 < 10 → 無法判定 → 放行', () async {
    final prices = await seedMarket();
    final eligibility = ReplayCalibrator.computeLiquidityEligibility(prices);
    // SPRS 只有前 9 bar volume 非 null,其後任何窗有效日 ≤ 9 —— 即使那
    // 9 天的 turnover 只有 10M(遠低於門檻)也必須放行:無資料 ≠ 低流動
    final idx = prices['SPRS']!.indexWhere((p) => p.date == day(79));
    expect(eligibility['SPRS']![idx], isTrue);
    // 對照:全窗皆有效但低流動的 ILLQ 在同一天被擋——permissive 不是全放
    final idxIllq = prices['ILLQ']!.indexWhere((p) => p.date == day(79));
    expect(eligibility['ILLQ']![idxIllq], isFalse);
  });

  test('(d-4) 全市場資料不足一個窗(前 19 日)→ 與生產同樣全放行', () async {
    final prices = await seedMarket();
    final eligibility = ReplayCalibrator.computeLiquidityEligibility(prices);
    // 生產 DAO 在 distinct 日 < 20 時 cutoffRow=null → 回空 map → caller
    // 全 permissive。ILLQ 恆 10M,但 day 0..18 仍必須放行
    for (var d = 0; d < 19; d++) {
      final idx = prices['ILLQ']!.indexWhere((p) => p.date == day(d));
      expect(eligibility['ILLQ']![idx], isTrue, reason: 'day $d 窗未滿');
    }
    expect(eligibility['ILLQ']![19], isFalse, reason: 'day 19 起窗滿、開始判定');
  });

  test('🚨 (d-5) run() 接線:不合格 stock-day 不進評估——生產根本不會評分它', () async {
    // minHistoryDays=20 讓所有評估日都落在窗滿之後(day 19 起),排除
    // 前段 permissive 的干擾;forward window 60 → 評估日 = day 20..19+?
    // (i+60<80 → i<20 → 恰 i=20 會 break…改 90 天)
    const days = 90;
    for (final (sym, vol) in [('LIQD', 1000000.0), ('ILLQ', 100000.0)]) {
      await db.upsertStocks([
        StockMasterCompanion.insert(symbol: sym, name: sym, market: 'TWSE'),
      ]);
      await db.insertPrices([
        for (var i = 0; i < days; i++)
          DailyPriceCompanion.insert(
            symbol: sym,
            date: day(i),
            open: const Value(100.0),
            close: const Value(100.0),
            volume: Value(vol),
          ),
      ]);
    }
    final calibrator = ReplayCalibrator(
      db: db,
      config: const ReplayConfig(
        dbPath: ':memory:',
        minHistoryDays: 20,
        excessReturn: false,
        persist: false,
      ),
      analysisService: mockAnalysis,
      ruleEngine: mockRuleEngine,
    );
    await calibrator.run();

    final evaluatedSymbols = verify(
      () => mockRuleEngine.evaluateStock(any(), captureAny()),
    ).captured.cast<StockData>().map((s) => s.symbol).toSet();
    expect(evaluatedSymbols, contains('LIQD'), reason: '前提:流動股有被評估');
    expect(
      evaluatedSymbols,
      isNot(contains('ILLQ')),
      reason: '10M 中位成交值的股票在生產不會進候選,校準語料也不得含它',
    );
  });

  test('🚨 (d-7) excess 模式的 universe 均值與 baseline H0 同樣只含合格股', () async {
    // 30 檔 A(+2%/日)+ 30 檔 B(+1%/日)雙閘全過:均值恰在兩者之間 →
    // A 全 hit、B 全 miss → baseline hit 恰 0.5(threshold=0,贏過大盤
    // 即命中)。兩組污染源:
    // - C:25 檔 −5%/日、vol 10 萬股 → 中位數與單日閘**都**不過
    // - R:15 檔 −3%/日、vol 999,999 股 → 成交額 ~100M 過中位數閘,
    //   但股數差 1 股不過單日閘——單日閘漏接時唯一會現形的剖面
    //
    // 各 mutation 把 0.5 推去哪(independent 重算;60D 對「均值漏單日閘」
    // 是**盲的**——R 只把 mean60 從 154.9 拉到 107,B(81.7)仍 miss;
    // 5D 是它唯一的鑑別 horizon):
    //   均值漏單日閘(medianEligible)→ hit5=1.0、hit60=0.5
    //   均值全漏 → hit5=1.0、hit60=1.0
    //   baseline 漏單日閘 → 兩 horizon 皆 30/75=0.4
    //   baseline 全漏 → 兩 horizon 皆 30/100=0.3
    const days = 90;
    Future<void> seed(String sym, double dailyRate, double volume) async {
      await db.upsertStocks([
        StockMasterCompanion.insert(symbol: sym, name: sym, market: 'TWSE'),
      ]);
      await db.insertPrices([
        for (var i = 0; i < days; i++)
          DailyPriceCompanion.insert(
            symbol: sym,
            date: day(i),
            close: Value(100.0 * math.pow(dailyRate, i).toDouble()),
            volume: Value(volume),
          ),
      ]);
    }

    for (var k = 0; k < 30; k++) {
      await seed('A$k', 1.02, 1000000); // 雙閘全過,較強
      await seed('B$k', 1.01, 1000000); // 雙閘全過,較弱
    }
    for (var k = 0; k < 25; k++) {
      await seed('C$k', 0.95, 100000); // 兩閘都不過,崩跌
    }
    for (var k = 0; k < 15; k++) {
      await seed('R$k', 0.97, 999999); // 過中位數閘、差 1 股不過單日閘
    }

    final calibrator = ReplayCalibrator(
      db: db,
      config: ReplayConfig(
        dbPath: ':memory:',
        minHistoryDays: 20,
        excessReturn: true,
        minUniverseSymbols: 10,
        persist: false,
        // 25..45:起點避開前 19 日的中位數閘 permissive 段;終點保住
        // 「R 仍過中位數閘」的前提(R 成交額遞減,約 day 49 後中位數
        // 跌破 3,000 萬,之後兩閘都擋、單日閘的漏接就照不出來了)
        dateFilter: (start: day(25), end: day(45)),
      ),
      analysisService: mockAnalysis,
      ruleEngine: mockRuleEngine,
    );
    final result = await calibrator.run();

    expect(result.universeBaselineHit5, 0.5);
    expect(result.universeBaselineHit60, 0.5);
  });

  group('(e) 生產一致性:scoring 層單日流動性閘門(review Critical 二補)', () {
    // 生產除了候選層 20 日中位數,對訊號日當根 bar 還有
    // LiquidityChecker.checkCandidateLiquidity(股數 ≥ 100 萬、成交額
    // ≥ 3,000 萬、close/volume 缺值=noData 同樣 skip)。review 實測只套
    // 中位數層時剩餘語料仍有 28–39% 是生產當日 skip 的 stock-day,且
    // 系統性偏向高價薄量股。replay 直接呼叫生產函式判定,不重寫語意。
    DailyPriceEntry bar(int d, {double? close, double? volume}) =>
        DailyPriceEntry(
          symbol: 'X',
          date: day(d),
          close: close,
          volume: volume,
        );

    test('(e-1) 單日閘語意 + 與中位數閘的合成', () {
      final prices = {
        'X': [
          bar(0, close: 30.0, volume: 1000000), // 恰 3,000 萬、恰 100 萬股 → 過
          bar(1, close: 100.0, volume: 999999), // 成交額夠,股數差 1 股 → 擋
          bar(2, close: 29.9, volume: 1000000), // 股數夠,成交額 29.9M → 擋
          bar(3, close: 100.0), // volume null → noData,擋(非 permissive!)
          bar(4, volume: 2000000), // close null → 同上
          bar(5, close: 100.0, volume: 2000000), // 全過
        ],
      };
      final medianAllPass = {'X': List<bool>.filled(6, true)};
      expect(ReplayCalibrator.applySignalDayGate(prices, medianAllPass)['X'], [
        true,
        false,
        false,
        false,
        false,
        true,
      ]);
      // 合成:中位數閘不過的 bar,單日閘再好也不得放行
      final medianLastFail = {
        'X': [true, true, true, true, true, false],
      };
      expect(ReplayCalibrator.applySignalDayGate(prices, medianLastFail)['X'], [
        true,
        false,
        false,
        false,
        false,
        false,
      ]);
    });

    test('🚨 (e-2) run() 接線:過中位數閘但當日縮量的 stock-day 不進評估', () async {
      // 單日 999,999 股(成交額仍 ~1 億,中位數閘無感)——被擋的必須
      // 恰是那一天,前後日照常評估
      const days = 100;
      await db.upsertStocks([
        StockMasterCompanion.insert(
          symbol: 'GATE',
          name: 'GATE',
          market: 'TWSE',
        ),
      ]);
      await db.insertPrices([
        for (var i = 0; i < days; i++)
          DailyPriceCompanion.insert(
            symbol: 'GATE',
            date: day(i),
            open: const Value(100.0),
            close: const Value(100.0),
            volume: Value(i == 30 ? 999999.0 : 1500000.0),
          ),
      ]);
      final calibrator = ReplayCalibrator(
        db: db,
        config: const ReplayConfig(
          dbPath: ':memory:',
          minHistoryDays: 20,
          excessReturn: false,
          persist: false,
        ),
        analysisService: mockAnalysis,
        ruleEngine: mockRuleEngine,
      );
      await calibrator.run();

      final evaluatedDates = verify(
        () => mockAnalysis.buildContext(
          any(),
          priceHistory: any(named: 'priceHistory'),
          marketData: any(named: 'marketData'),
          evaluationTime: captureAny(named: 'evaluationTime'),
          isMarketUptrend: any(named: 'isMarketUptrend'),
        ),
      ).captured.cast<DateTime>().toSet();
      expect(evaluatedDates, contains(day(29)), reason: '前提:前一日照常評估');
      expect(evaluatedDates, contains(day(31)), reason: '前提:後一日照常評估');
      expect(
        evaluatedDates,
        isNot(contains(day(30))),
        reason: '生產當日 skip(lowLiquidity)的 stock-day 不得進校準語料',
      );
    });

    test('🚨 (e-3) regime universe 只套中位數閘,不套單日閘', () async {
      // 生產的 marketUptrendOrNull 對候選批次**全體**計算,單日 skip 發生
      // 在其後的逐股評分(scoring_isolate 先算 regime 再逐股 classify)。
      // 5 檔雙閘全過 + 55 檔「過中位數、股數差 1 股」緩漲:regime 母體
      // 應為 60(≥50 → 判定成立、多頭);若誤把單日閘也套進 regime,
      // 母體剩 5 → 永遠 null。
      const days = 200;
      Future<void> seed(String sym, double volume) async {
        await db.upsertStocks([
          StockMasterCompanion.insert(symbol: sym, name: sym, market: 'TWSE'),
        ]);
        await db.insertPrices([
          for (var i = 0; i < days; i++)
            DailyPriceCompanion.insert(
              symbol: sym,
              date: day(i),
              close: Value(50.0 + i * 0.1),
              volume: Value(volume),
            ),
        ]);
      }

      for (var k = 0; k < 5; k++) {
        await seed('L$k', 1500000); // 雙閘全過
      }
      for (var k = 0; k < 55; k++) {
        await seed('M$k', 999999); // 過中位數(成交額 ~5,000 萬),不過單日
      }
      final calibrator = ReplayCalibrator(
        db: db,
        config: const ReplayConfig(
          dbPath: ':memory:',
          minHistoryDays: 20,
          excessReturn: false,
          persist: false,
        ),
        analysisService: mockAnalysis,
        ruleEngine: mockRuleEngine,
      );
      await calibrator.run();

      final uptrends = verify(
        () => mockAnalysis.buildContext(
          any(),
          priceHistory: any(named: 'priceHistory'),
          marketData: any(named: 'marketData'),
          evaluationTime: any(named: 'evaluationTime'),
          isMarketUptrend: captureAny(named: 'isMarketUptrend'),
        ),
      ).captured;
      final defined = uptrends.whereType<bool>().toList();
      expect(
        defined,
        isNotEmpty,
        reason: 'regime 母體=60 檔過中位數閘者,lookback 滿後必有判定',
      );
      expect(defined, everyElement(isTrue), reason: '全體緩漲 → 多頭');
    });
  });

  test('🚨 (d-6) regime universe 同樣只含合格股——低流動股不得拉動大盤 gate', () {
    // 55 檔合格緩漲 + 30 檔不合格崩跌:未 gate 的均值被崩跌股拉成負,
    // gate 後應為正。eligibility 手工給定(判定邏輯由 d-1 釘,這裡釘接線)
    final prices = <String, List<DailyPriceEntry>>{};
    final eligible = <String, List<bool>>{};
    List<DailyPriceEntry> series(String sym, double Function(int) close) => [
      for (var i = 0; i < 200; i++)
        DailyPriceEntry(symbol: sym, date: day(i), close: close(i)),
    ];
    for (var k = 0; k < 55; k++) {
      final sym = 'L$k';
      prices[sym] = series(sym, (i) => 100.0 + i * 0.05);
      eligible[sym] = List.filled(200, true);
    }
    for (var k = 0; k < 30; k++) {
      final sym = 'X$k';
      prices[sym] = series(sym, (i) => 100.0 - i * 0.45); // −90% 到底
      eligible[sym] = List.filled(200, false);
    }

    final ungated = ReplayCalibrator.computeMarketUptrendByDate(prices, 120);
    final gated = ReplayCalibrator.computeMarketUptrendByDate(
      prices,
      120,
      eligibleBySymbol: eligible,
    );
    // day() 產生的即是 midnight,與 calibrator 內部的日期鍵正規化同值
    final probe = day(150);
    expect(ungated[probe], isFalse, reason: '前提:未 gate 時崩跌股拉成空頭');
    expect(gated[probe], isTrue, reason: 'gate 後只剩 55 檔緩漲 → 多頭');

    // 合格數 < regimeMinEligibleStocks(50) → null(permissive),與生產
    // 「候選不足不判 regime」一致
    final few = <String, List<bool>>{
      for (final e in eligible.entries)
        e.key: e.key.startsWith('L') && int.parse(e.key.substring(1)) < 45
            ? e.value
            : List.filled(200, false),
    };
    final under = ReplayCalibrator.computeMarketUptrendByDate(
      prices,
      120,
      eligibleBySymbol: few,
    );
    expect(under[probe], isNull, reason: '45 檔 < 50 → 無法判定');
  });
}
