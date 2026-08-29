// Replay 校準器與生產評分的組裝一致性（parity）
//
// 2026-08-29 全面稽核發現三處分岔——calibrated scores 在生產不會出現的觸發
// 分布上訓練：
//   (a) 缺 fillNoActivityDays：streak 規則以 list 相鄰當連續，缺列日把不相鄰
//       兩天焊成連續（生產修掉的 bug 在校準語料復活）
//   (b) 缺 regime gate：回檔規則的校準樣本含生產會壓掉的空頭觸發
//   (c) 法人窗不同：生產裁到 institutionalStreakLookbackDays，replay 餵全歷史
//
// 斷言點＝replay 傳給 rule engine / buildContext 的實物（mock 捕捉），
// 對照生產端同一批函式（BatchDataBuilder.fillNoActivityDays、
// PriceCalculator.marketUptrendOrNull）的輸出。
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:daredevil/core/constants/rule_params_institutional.dart';
import 'package:daredevil/core/constants/rule_params_sector.dart';
import 'package:daredevil/core/constants/rule_enums.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/domain/models/models.dart';
import 'package:daredevil/domain/services/analysis_service.dart';
import 'package:daredevil/domain/services/price_calculator.dart';
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
    final ctx = AnalysisContext(
      evaluationTime: DateTime(2024, 2, 1),
      trendState: TrendState.up,
    );
    // 兩個 stub 並存：修復前呼叫不帶 isMarketUptrend、修復後帶——都要能跑
    when(
      () => mockAnalysis.buildContext(
        any(),
        priceHistory: any(named: 'priceHistory'),
        marketData: any(named: 'marketData'),
        evaluationTime: any(named: 'evaluationTime'),
      ),
    ).thenReturn(ctx);
    when(
      () => mockAnalysis.buildContext(
        any(),
        priceHistory: any(named: 'priceHistory'),
        marketData: any(named: 'marketData'),
        evaluationTime: any(named: 'evaluationTime'),
        isMarketUptrend: any(named: 'isMarketUptrend'),
      ),
    ).thenReturn(ctx);
    when(() => mockRuleEngine.evaluateStock(any(), any())).thenReturn(const []);
  });

  tearDown(() async => db.close());

  Future<void> seedPrices(String symbol, int days) async {
    await db.upsertStocks([
      StockMasterCompanion.insert(symbol: symbol, name: symbol, market: 'TWSE'),
    ]);
    await db.insertPrices([
      for (var i = 0; i < days; i++)
        DailyPriceCompanion.insert(
          symbol: symbol,
          date: first.add(Duration(days: i)),
          open: Value(100.0 + i),
          high: Value(101.0 + i),
          low: Value(99.0 + i),
          close: Value(100.0 + i),
          volume: const Value(1000000),
        ),
    ]);
  }

  Future<void> seedInst(String symbol, List<int> dayOffsets) =>
      db.insertInstitutionalData([
        for (final o in dayOffsets)
          DailyInstitutionalCompanion.insert(
            symbol: symbol,
            date: first.add(Duration(days: o)),
            foreignNet: const Value(500000),
            investmentTrustNet: const Value(100000),
          ),
      ]);

  ReplayCalibrator makeCalibrator() => ReplayCalibrator(
    db: db,
    config: const ReplayConfig(
      dbPath: ':memory:',
      minHistoryDays: 5,
      excessReturn: false,
      persist: false,
    ),
    analysisService: mockAnalysis,
    ruleEngine: mockRuleEngine,
  );

  List<StockData> capturedFor(String symbol) => verify(
    () => mockRuleEngine.evaluateStock(any(), captureAny()),
  ).captured.cast<StockData>().where((s) => s.symbol == symbol).toList();

  test('🚨 (a) 市場有同步、個股無活動的日子必須補零列——不得焊接 streak', () async {
    // A：day 0,1,3 有法人資料,day 2 缺;B 在 day 2 有資料 → day 2 是市場已同步日
    // 70 天:replay 的 forward window 是寫死的 longDays=60,
    // i + 60 >= len 就 break——太短連一次評估都不會發生
    await seedPrices('1111', 70);
    await seedPrices('2222', 70);
    await seedInst('1111', [0, 1, 3]);
    await seedInst('2222', [2]);

    await makeCalibrator().run();

    final snapshots = capturedFor('1111');
    expect(snapshots, isNotEmpty, reason: '前提:1111 有被評估');
    final last = snapshots.last;
    final instDates = last.institutional!.map((e) => e.date).toSet();
    expect(
      instDates,
      contains(first.add(const Duration(days: 2))),
      reason:
          '生產端 fillNoActivityDays 會在市場已同步、個股無活動的 day 2 '
          '補零列以斷開 streak;replay 不補會把 day 1 與 day 3 焊成連續',
    );
    final filled = last.institutional!.firstWhere(
      (e) => e.date == first.add(const Duration(days: 2)),
    );
    expect(filled.foreignNet, 0, reason: '補的是零列,不是捏造的活動');
  });

  test('🚨 (c) 法人清單必須裁到 streak 窗,與生產一致', () async {
    // 180 天:forward window(60)使最後評估日 = day 119,窗(90)起點 = day 29
    // → day 0 真正出窗。第一版種 150 天時最後評估日 89、cutoff = day -1,
    // day 0 反而在窗內——mutation 存活抓到這個算術錯誤。
    final days = InstitutionalParams.institutionalStreakLookbackDays + 90;
    await seedPrices('1111', days);
    // day 0 在窗外;day 100 在窗內(防「整串被濾光」的空集合假綠)
    await seedInst('1111', [0, 100]);

    await makeCalibrator().run();

    final snapshots = capturedFor('1111');
    expect(snapshots, isNotEmpty);
    final last = snapshots.last;
    final evalDate = last.prices.last.date;
    final cutoff = evalDate.subtract(
      const Duration(days: InstitutionalParams.institutionalStreakLookbackDays),
    );
    expect(
      last.institutional!.where((e) => e.date.isBefore(cutoff)),
      isEmpty,
      reason:
          '生產端查詢窗起點是 evalDate - institutionalStreakLookbackDays;'
          'replay 餵全歷史會讓 streakTruncated 語意與長度門檻不一致',
    );
    expect(
      last.institutional!.map((e) => e.date),
      contains(first.add(const Duration(days: 100))),
      reason: '窗內的資料必須還在——整串空集合會讓上一條斷言假綠',
    );
  });

  test('🚨 (b-1) 空頭段的評估必須收到 isMarketUptrend=false', () async {
    // mocktail 對「呼叫缺少具名參數」照樣以 null 匹配 captureAny——
    // 只斷言 isNotEmpty 是空測試(mutation 存活抓到)。改斷言捕到明確的
    // false:regime 需要 ≥50 檔有 121 根 bar,種 55 檔 × 200 天、
    // 尾段 80 天崩跌 → 評估後段的 120 日報酬必為負。
    for (var k = 0; k < 55; k++) {
      final sym = '9${k.toString().padLeft(3, '0')}';
      await db.upsertStocks([
        StockMasterCompanion.insert(symbol: sym, name: sym, market: 'TWSE'),
      ]);
      await db.insertPrices([
        for (var i = 0; i < 200; i++)
          DailyPriceCompanion.insert(
            symbol: sym,
            date: first.add(Duration(days: i)),
            close: Value(i < 120 ? 100.0 + i * 0.05 : 106.0 - (i - 120) * 1.0),
            volume: const Value(1000000),
          ),
      ]);
    }

    await makeCalibrator().run();

    final captured = verify(
      () => mockAnalysis.buildContext(
        any(),
        priceHistory: any(named: 'priceHistory'),
        marketData: any(named: 'marketData'),
        evaluationTime: any(named: 'evaluationTime'),
        isMarketUptrend: captureAny(named: 'isMarketUptrend'),
      ),
    ).captured;
    expect(
      captured,
      contains(false),
      reason:
          '崩跌段的 120 日全市場報酬為負,生產會以 isMarketUptrend=false '
          'gate 掉回檔規則;replay 不傳(捕到全 null)=校準樣本含空頭觸發',
    );
  });

  test('(b-2) per-date regime map 與生產函式逐日一致(parity)', () {
    // 40 檔、160 天:前 120 天緩漲、後 40 天急跌 → 後段 uptrend 應為 false
    // (40 檔 < regimeMinEligibleStocks=50 → 兩邊都該回 null;
    //  再用 60 檔驗非 null 段)
    Map<String, List<DailyPriceEntry>> build(int symbols, double lateSlope) => {
      for (var s = 0; s < symbols; s++)
        'S$s': [
          for (var i = 0; i < 160; i++)
            DailyPriceEntry(
              symbol: 'S$s',
              date: first.add(Duration(days: i)),
              close: i < 120 ? 100.0 + i * 0.1 : 112.0 + (i - 120) * lateSlope,
              volume: 1000,
            ),
        ],
    };

    for (final (symbols, slope) in [(40, -2.0), (60, -2.0), (60, 2.0)]) {
      final map = build(symbols, slope);
      final byDate = ReplayCalibrator.computeMarketUptrendByDate(
        map,
        SectorParams.regimeLookbackDays,
      );
      // 抽三個代表日與生產函式對照:歷史截到該日、asOf=該日
      for (final dayIdx in [125, 140, 159]) {
        final d = first.add(Duration(days: dayIdx));
        final truncated = {
          for (final e in map.entries) e.key: e.value.sublist(0, dayIdx + 1),
        };
        final expected = PriceCalculator.marketUptrendOrNull(
          truncated,
          SectorParams.regimeLookbackDays,
          asOf: d,
        );
        expect(
          byDate[DateTime(d.year, d.month, d.day)],
          expected,
          reason:
              'symbols=$symbols slope=$slope day=$dayIdx:'
              'map 與生產函式必須逐日一致',
        );
      }
    }
  });
}
