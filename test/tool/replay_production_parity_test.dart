// Replay 校準器與生產評分的組裝一致性（parity）
//
// 2026-08-29 全面稽核發現三處分岔——calibrated scores 在生產不會出現的觸發
// 分布上訓練：
//   (a) 缺 fillNoActivityDays：streak 規則以 list 相鄰當連續，缺列日把不相鄰
//       兩天焊成連續（生產修掉的 bug 在校準語料復活）
//   (b) 缺 regime gate：回檔規則的校準樣本含生產會壓掉的空頭觸發
//   (c) 法人窗不同：生產裁到 institutionalStreakLookbackDays，replay 餵全歷史
//
// ⚠️ **這組測試證明的是「等價」,不是「正確」**(2026-08-29 domain 稽核)。
// 生產端的 `PriceCalculator.marketUptrendOrNull` 用等權平均判多空,而
// 該稽核實測:1,373 個可判定日裡有 **381 日(27.7%)** 說「多頭」但同期
// 上漲家數不到一半,偏差**單向**(改用中位數會讓這 381 日全部翻成空頭、
// 反向零日)。最極端的 2024-11-14:n=2,070、平均 +0.05%、只有 35% 上漲,
// 拿掉貢獻最大的 10 檔(0.48% 的宇宙)平均變 −1.06% 直接翻面。
// 若估計量要改,**兩邊一起改**——這組測試會照樣綠,因為它比的是兩份
// 實作而不是市場事實。
//
// 另一個已知盲區:下方 fixture 讓所有股票走**同一條價格路徑**,此時
// 平均恆等於中位數,所以這組測試對上述偏斜結構性看不見。
//
// 已知存活的 mutation（結構性免疫，記錄原因而非硬造 fixture）：
//   computeMarketUptrendByDate 的錨點索引 ±1（119 vs 120 根 lookback）。
//   平滑序列下 ±1 根只把均值零交叉平移 ~0.2 天，整數日邊界不動、boolean
//   逐日不變；要殺它需要「交叉恰落在日界 ±0.2 天內」的鋸齒 fixture，脆且
//   讀不懂。實質風險有界：窗長差 0.8%，且 (b-2) 已對 4 組序列 × 逐日釘住
//   與生產函式的 boolean 相等。
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
    // day 0 在窗外;day 100 在窗內(防「整串被濾光」的空集合假綠);
    // day 29/28 = 最後評估日(119)的窗界兩側——生產查詢是 >= evalDate-90,
    // 恰在界上的要留、界外一天的要丟。review 實測:窗常數 -30 的 mutation
    // 在只有 0/100 兩列時存活,這兩列釘住常數本身。
    await seedInst('1111', [0, 28, 29, 100]);

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
    final dates = last.institutional!.map((e) => e.date).toSet();
    expect(
      dates,
      contains(first.add(const Duration(days: 29))),
      reason: '恰在窗界上(evalDate-90)的列必須保留——生產查詢是 >=',
    );
    expect(
      dates,
      isNot(contains(first.add(const Duration(days: 28)))),
      reason: '窗界外一天的列必須裁掉——此斷言釘住窗常數的值',
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

  test('(b-3) 釘一個評估日:捕到的 regime == 生產函式在該日截斷歷史的輸出', () async {
    // review 的 mutation 實測:lookup key 平移 ±3 天、錨點索引 ±1 都能在
    // (b-1)/(b-2) 存活——粗粒度斷言只綁「有 false」。此測試把單一評估日的
    // 捕獲值跟生產函式(歷史截到該日、asOf=該日)逐值對齊,任何 key 平移
    // 都是把「別天(甚至未來)的 regime」餵給該日,是 look-ahead——本檔案
    // 的老毛病(audit finding #6)。
    final prices = <String, List<DailyPriceEntry>>{};
    for (var k = 0; k < 55; k++) {
      final sym = '8${k.toString().padLeft(3, '0')}';
      await db.upsertStocks([
        StockMasterCompanion.insert(symbol: sym, name: sym, market: 'TWSE'),
      ]);
      final list = [
        for (var i = 0; i < 200; i++)
          DailyPriceEntry(
            symbol: sym,
            date: first.add(Duration(days: i)),
            close: i < 120 ? 100.0 + i * 0.05 : 106.0 - (i - 120) * 1.0,
            volume: 1000000,
          ),
      ];
      prices[sym] = list;
      await db.insertPrices([
        for (final e in list)
          DailyPriceCompanion.insert(
            symbol: e.symbol,
            date: e.date,
            close: Value(e.close),
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
        evaluationTime: captureAny(named: 'evaluationTime'),
        isMarketUptrend: captureAny(named: 'isMarketUptrend'),
      ),
    ).captured;
    // captured 交錯排列:[evalTime, uptrend, ...]。驗**每一個**評估日——
    // 只釘單日的話,lookup key ±N 在區域性恆值段全數存活;逐日驗證讓
    // 轉折日附近的平移必然露餡。
    expect(captured, isNotEmpty, reason: '前提:有評估發生');
    final checked = <DateTime>{};
    for (var i = 0; i + 1 < captured.length; i += 2) {
      final t = captured[i] as DateTime;
      if (!checked.add(t)) continue;
      final idx = t.difference(first).inDays;
      final truncated = {
        for (final e in prices.entries) e.key: e.value.sublist(0, idx + 1),
      };
      expect(
        captured[i + 1] as bool?,
        PriceCalculator.marketUptrendOrNull(
          truncated,
          SectorParams.regimeLookbackDays,
          asOf: t,
        ),
        reason:
            'day $idx 的 regime 必須等於生產函式對「截至該日」歷史的輸出'
            '——不等=把別天(甚至未來)的 regime 餵給該日',
      );
    }
    expect(checked.length, greaterThan(30), reason: '前提:涵蓋足夠多評估日');
  });

  /// 偏斜宇宙:多數緩跌、少數暴漲——**平均與中位數給相反答案**。
  ///
  /// (b-2) 原本的宇宙是同質的（每檔價格路徑相同）,那種形狀下平均恆等於
  /// 中位數,parity 對「用哪個估計量」完全是盲的。regime 於 2026-08-29 從
  /// 等權平均改為中位數（稽核 C2）,而**兩份實作必須一起改**——這個 fixture
  /// 是讓 parity 看得見分岔的唯一形狀。
  Map<String, List<DailyPriceEntry>> skewedUniverse(int losers, int winners) =>
      {
        for (var s = 0; s < losers + winners; s++)
          'K$s': [
            for (var i = 0; i < 160; i++)
              DailyPriceEntry(
                symbol: 'K$s',
                date: first.add(Duration(days: i)),
                // 緩跌者 120 日報酬 ≈ −2.4%;暴漲者 ≈ +150%
                close: s < losers ? 100.0 - i * 0.02 : 100.0 + i * 2.0,
                volume: 1000,
              ),
          ],
      };

  test('🚨 (b-4) replay 的 regime 用中位數,不是平均(稽核 C2)', () {
    // parity 測不到這件事——兩邊同時用平均也會 parity 相等。這條直接
    // 斷言 replay 端的估計量:50 檔緩跌 + 10 檔暴漲,
    //   平均 = (50×(−2.4%) + 10×150%) / 60 ≈ +23%  → 平均會判多頭
    //   中位數 = −2.4%（60 檔裡 50 檔在跌）        → 中位數判空頭
    final byDate = ReplayCalibrator.computeMarketUptrendByDate(
      skewedUniverse(50, 10),
      SectorParams.regimeLookbackDays,
    );
    final probe = first.add(const Duration(days: 150));
    expect(
      byDate[DateTime(probe.year, probe.month, probe.day)],
      isFalse,
      reason: '60 檔裡 50 檔在跌,不該因 10 檔暴漲股而判多頭',
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

    // 最後一組是「刀鋒坡度」:-0.12/天 讓 120 日均值以 ~0.05%/天 的速度
    // 穿越零點,轉折橫跨多日——錨點索引 ±1(位移同量級)在陡坡序列翻不了
    // 任何一天的正負,只有刀鋒組殺得死那個 mutation。
    // 最後一組是**偏斜宇宙**:同質宇宙下平均恆等於中位數,parity 看不見
    // 估計量;偏斜宇宙下若只有一邊改了估計量,這裡會立刻分岔。
    for (final (symbols, slope) in [
      (40, -2.0),
      (60, -2.0),
      (60, 2.0),
      (60, -0.12),
      (0, 0.0), // 哨兵:改用 skewedUniverse
    ]) {
      final map = symbols == 0 ? skewedUniverse(50, 10) : build(symbols, slope);
      final byDate = ReplayCalibrator.computeMarketUptrendByDate(
        map,
        SectorParams.regimeLookbackDays,
      );
      // 掃全部評估日與生產函式對照(歷史截到該日、asOf=該日)。
      // 不抽樣:合成序列的 regime 是區域性恆值,抽樣點離轉折遠時
      // key/索引 ±N 的 mutation 全部存活(review 實測 3 個都活);
      // 全掃保證轉折日(約 day 125-126)被涵蓋,任何平移在那裡必然翻值。
      for (var dayIdx = 120; dayIdx < 160; dayIdx++) {
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

  test('🚨 (b-4) 400 天錨點守衛:停牌久的股票不得用窗外舊錨點', () async {
    // 2026-08-29 稽核抓到:守衛是那天加的,而 fixture 最長 200 天——
    // 觸發條件(錨點與當根 bar 相距 > 400 日曆天)**永遠不成立**,
    // 實測把守衛整段刪掉這個檔案照樣全綠。守衛正是兩份實作之間唯一的
    // 結構性差異(生產只載 400 日曆天窗、窗內不足 lookback+1 根就整檔
    // 跳過),沒被釘住等於白加。
    //
    // 這裡造一檔「前 120 根密集、然後停牌兩年、再恢復」的股票:
    // 恢復後的 bar 其 i−120 錨點落在停牌之前,日曆距離 > 400 天。
    const lookback = 120;
    final gapSym = 'GAP1';
    await db.upsertStocks([
      StockMasterCompanion.insert(symbol: gapSym, name: gapSym, market: 'TWSE'),
    ]);
    final rows = <DailyPriceEntry>[
      // 停牌前:緩跌
      for (var i = 0; i < lookback + 1; i++)
        DailyPriceEntry(
          symbol: gapSym,
          date: first.add(Duration(days: i)),
          close: 200.0 - i * 0.5,
          volume: 1000000,
        ),
      // 停牌 800 天後恢復,價格暴漲——若用窗外舊錨點會算出巨大正報酬
      for (var i = 0; i < 5; i++)
        DailyPriceEntry(
          symbol: gapSym,
          date: first.add(Duration(days: lookback + 1 + 800 + i)),
          close: 900.0 + i,
          volume: 1000000,
        ),
    ];

    final uptrend = ReplayCalibrator.computeMarketUptrendByDate({
      gapSym: rows,
    }, lookback);
    // 恢復後的日子:錨點跨越 800 天停牌 → 守衛應讓它整個不貢獻,
    // 因此該日沒有任何有效樣本 → 不在 map 內
    final resumedDay = rows[lookback + 1].date;
    expect(
      uptrend.containsKey(resumedDay),
      isFalse,
      reason: '錨點距今 800+ 天(> historyRequiredDays)——生產端此檔整檔跳過',
    );
    // 對照:停牌前的正常日子照常有判定(守衛不得誤殺)
    expect(uptrend.containsKey(rows[lookback].date), isTrue);
  });
}
