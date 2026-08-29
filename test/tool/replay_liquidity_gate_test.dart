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
    // 30 檔 A(+2%/日)+ 30 檔 B(+1%/日)全流動:均值恰在兩者之間 →
    // A 全 hit、B 全 miss → baseline hit 恰 0.5(threshold=0,贏過大盤
    // 即命中)。另 25 檔崩跌(−5%/日)+ 15 檔火箭(+2.83%/日)全不合格:
    // - 均值漏 gate → 均值被拉低 → A、B 都變 hit → 1.0
    // - baseline 計數漏 gate → 崩跌(miss)與火箭(hit)進分母 → 0.45
    // 兩個方向都把 0.5 推離——0.5 是唯一「兩處都 gate」才會出現的值。
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
      await seed('A$k', 1.02, 1000000); // 流動,較強
      await seed('B$k', 1.01, 1000000); // 流動,較弱
    }
    for (var k = 0; k < 25; k++) {
      await seed('C$k', 0.95, 100000); // 不合格,崩跌
    }
    for (var k = 0; k < 15; k++) {
      await seed('R$k', 1.0283, 1000); // 不合格,火箭
    }

    final calibrator = ReplayCalibrator(
      db: db,
      config: ReplayConfig(
        dbPath: ':memory:',
        minHistoryDays: 20,
        excessReturn: true,
        minUniverseSymbols: 10,
        persist: false,
        // 只統計窗滿(day 19 起)之後的日子:前 19 日全市場 distinct 日不足
        // 一個窗、gate permissive,不合格股會合法地混進均值
        dateFilter: (start: day(25), end: null),
      ),
      analysisService: mockAnalysis,
      ruleEngine: mockRuleEngine,
    );
    final result = await calibrator.run();

    expect(result.universeBaselineHit5, 0.5);
    expect(result.universeBaselineHit60, 0.5);
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
