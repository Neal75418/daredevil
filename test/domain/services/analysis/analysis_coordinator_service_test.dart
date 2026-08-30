import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/domain/services/analysis/analysis_coordinator_service.dart';
import 'package:daredevil/domain/services/ohlcv_data.dart';
import 'package:daredevil/domain/services/technical_indicator_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/price_data_generators.dart';

/// [AnalysisCoordinatorService.calculateTechnicalIndicators] 是 gap-bridging
/// root cause 修復的主要呼叫端（把 priceHistory 轉為 AnalysisContext 用的
/// RSI/KD 指標，直接餵給規則引擎）。這裡驗證停牌缺口不再被靜默橋接。
void main() {
  late AnalysisCoordinatorService coordinator;

  setUp(() {
    coordinator = AnalysisCoordinatorService();
  });

  // ==========================================
  // 價格水位斷點（2026-08-30 稽核 C3）
  // ==========================================
  //
  // daily_price 存交易所原始收盤價、未還原除權息／減資／分割。跨越位移的
  // 長窗指標會給出物理上不可能的值:5904 寶雅 2026-08-27 的 daily_reason
  // 存著 `ma60: 506.18`,而當天股價 74.10。
  //
  // **截斷放在指標計算裡,不在價格入口**:入口截斷會讓 prices.length 本身
  // 變短,踩到下游一連串長度閘——實測 165 檔被截斷者中 52 檔掉到 60 根以下
  // (整個 indicator 區塊 null)、142 檔掉到 250 根以下(52 週規則永不觸發)。
  // 而 52 週規則**本來就正確處理除息**(_sumDividendsInPeriod 把窗內現金
  // 股利從極值扣掉),入口截斷等於破壞一條已經解好的規則。
  group('指標只用價格水位斷點之後的資料', () {
    /// [preCount] 根在 [preClose] 水位 + [postCount] 根在 [postClose] 水位
    List<DailyPriceEntry> withShift({
      required int preCount,
      required double preClose,
      required int postCount,
      required double postClose,
    }) {
      final now = DateTime(2026, 1, 1);
      var d = 0;
      return [
        for (var i = 0; i < preCount; i++)
          createTestPrice(
            date: now.add(Duration(days: d++)),
            close: preClose + (i.isEven ? 1 : -1),
            volume: 1000,
          ),
        for (var i = 0; i < postCount; i++)
          createTestPrice(
            date: now.add(Duration(days: d++)),
            close: postClose + (i.isEven ? 1 : -1),
            volume: 1000,
          ),
      ];
    }

    test('🚨 跨越水位位移的 MA60 必須是 null,不是一個不可能的數字', () {
      // 2603 長榮的形狀:斷點後 51 根(< 60 → 算不出 MA60,但 MA20 綽綽有餘)
      final ind = coordinator.calculateTechnicalIndicators(
        withShift(preCount: 200, preClose: 700, postCount: 51, postClose: 80),
      );

      expect(ind, isNotNull, reason: '外層閘門看完整歷史,整組指標不該消失');
      expect(
        ind!.ma60,
        isNull,
        reason: '未截斷時會算出跨越 8.75 倍水位位移的均線——那正是 ma60=506 的形狀',
      );
      expect(ind.ma20, isNotNull, reason: '斷點後 51 根足夠算 MA20,不該一起消失');
      expect(ind.ma20!, closeTo(80, 2), reason: 'MA20 必須落在新水位,不是舊水位');
      expect(ind.rsi, isNotNull, reason: '斷點後 51 根足夠算 RSI');
    });

    test('對照組:沒有水位位移時 MA60 照算', () {
      final ind = coordinator.calculateTechnicalIndicators(
        withShift(preCount: 200, preClose: 80, postCount: 51, postClose: 80),
      );
      expect(ind!.ma60, isNotNull);
      expect(ind.ma60!, closeTo(80, 2));
    });

    test('🚨 合乎漲跌幅上限的移動不得被當成水位位移', () {
      // 停牌後 +10% 是合法的;把它當斷點會讓正常股票平白失去長窗指標。
      // 注意 fixture 帶 ±1 的震盪:實際比較的是 99 → 107 = +8.1%
      final ind = coordinator.calculateTechnicalIndicators(
        withShift(preCount: 200, preClose: 100, postCount: 51, postClose: 108),
      );
      expect(ind!.ma60, isNotNull, reason: '+8.1% 在 ±10% 上限的容許帶內');
    });

    test('🚨 斷點後不足 RSI 窗時整組回 null——這是已知限制,不是漏測', () {
      // `closes.length < rsiPeriod + 2`(16)是既有的早退,截斷後的短序列會
      // 撞到它 → 整個 indicator 區塊 null,連 MA5 都拿不到。
      //
      // 這對 5904 那種形狀(斷點後 15 根)反而是想要的結果:它現在會產出
      // `ma60: 506.18` 與假的 RSI 17.4,回 null 是誠實的。實測全庫約 14 檔
      // 落在這個區間。若日後想保住短窗指標,要把那道早退改成只 gate RSI/KD
      // ——那會連帶改變「重度停牌股」的既有行為,是獨立的決定。
      final ind = coordinator.calculateTechnicalIndicators(
        withShift(preCount: 239, preClose: 700, postCount: 12, postClose: 80),
      );
      expect(ind, isNull);
    });
  });

  group('calculateTechnicalIndicators — RSI gap-awareness', () {
    test('RSI reflects gap-aware calculation, not the bridged phantom spike, '
        'when priceHistory has a halt right before today', () {
      final now = DateTime(2026, 1, 1);
      final entries = <DailyPriceEntry>[
        for (int i = 0; i < 70; i++)
          createTestPrice(
            date: now.add(Duration(days: i)),
            close: 100.0 + (i.isEven ? 0.3 : -0.3),
            volume: 1000,
          ),
        // 兩日停牌（無成交）
        createTestPrice(
          date: now.add(const Duration(days: 70)),
          close: null,
          volume: 0,
        ),
        createTestPrice(
          date: now.add(const Duration(days: 71)),
          close: null,
          volume: 0,
        ),
        // 復牌當日（今天）：若跨缺口的價差被誤採計為單一交易日變動，
        // 會產生虛假極端 RSI。
        //
        // 數值刻意落在**漲跌幅上限之內**（停牌前最後一根是 99.7，
        // 110.0 是 +10.3%；兩日停牌最多累積約 ±21%）：
        // 舊 fixture 用 250.0（+149%），那在台股結構上不可能、而是公司行動的
        // 形狀，2026-08-30 起會被 `PriceContinuity` 判為水位斷點而截掉整段
        // 歷史——那條分界另有測試（見下方「水位斷點」）。
        createTestPrice(
          date: now.add(const Duration(days: 72)),
          close: 110.0,
          volume: 1000,
        ),
      ];

      final indicators = coordinator.calculateTechnicalIndicators(entries);

      expect(indicators, isNotNull);
      expect(indicators!.rsi, isNotNull);
      // 缺口前最後穩定值附近（震盪走平 → RSI 中性），遠低於橋接後的極端值
      expect(indicators.rsi!, lessThan(60.0));

      // 對照組：舊行為（extractOhlcv 後直接 calculateRSI，不帶 gapBefore）
      // 會把跨缺口的價差當成單一交易日變動，產生虛假極端 RSI——用來證明
      // 這不是「兩種算法剛好差不多」而是有意義的修正。
      final bridgedOhlcv = entries.extractOhlcv();
      final bridgedRsi = TechnicalIndicatorService()
          .calculateRSI(bridgedOhlcv.closes, period: 14)
          .last;
      expect(bridgedRsi, isNotNull);
      // 斷言**兩者的差距**而非一個絕對值：舊的 `> 90.0` 是為 +149% 那個
      // 不合法的 fixture 定的，換成合乎漲跌幅上限的 +10.3% 之後就不再成立，
      // 但真正的宣稱一直是「這不是兩種算法剛好差不多」。
      expect(
        bridgedRsi! - indicators.rsi!,
        greaterThan(15.0),
        reason: '橋接後的 RSI 必須顯著高於 gap-aware 的值',
      );
    });

    test('RSI unaffected when there is no gap anywhere in priceHistory', () {
      final now = DateTime(2026, 1, 1);
      final entries = List.generate(
        70,
        (i) => createTestPrice(
          date: now.add(Duration(days: i)),
          close: 100.0 + i * 0.2,
          volume: 1000,
        ),
      );

      final indicators = coordinator.calculateTechnicalIndicators(entries);

      expect(indicators, isNotNull);
      expect(indicators!.rsi, isNotNull);
      // 持續上升無缺口 → RSI 偏高屬正常（非缺口造成的虛假訊號）
      expect(indicators.rsi!, greaterThan(50.0));
    });
  });

  group('calculateTechnicalIndicators — KD prevK/prevD freshness', () {
    test(
      'prevKdK/prevKdD are null when a halt gap sits immediately before today '
      '(stale-guard: len-2 would not actually be "yesterday")',
      () {
        final now = DateTime(2026, 1, 1);
        final entries = <DailyPriceEntry>[
          for (int i = 0; i < 65; i++)
            createTestPrice(
              date: now.add(Duration(days: i)),
              close: 100.0 + (i % 10).toDouble(),
              volume: 1000,
            ),
          // 昨天停牌
          createTestPrice(
            date: now.add(const Duration(days: 65)),
            close: null,
            volume: 0,
          ),
          // 今天
          createTestPrice(
            date: now.add(const Duration(days: 66)),
            close: 105.0,
            volume: 1000,
          ),
        ];

        final indicators = coordinator.calculateTechnicalIndicators(entries);

        expect(indicators, isNotNull);
        // 今日自身的 K/D 仍可正常計算（RSV 視窗本身沒有問題）
        expect(indicators!.kdK, isNotNull);
        expect(indicators.kdD, isNotNull);
        // 但「前一日」不是真的前一交易日，寧可 null 讓交叉/回檔規則自然略過
        expect(indicators.prevKdK, isNull);
        expect(indicators.prevKdD, isNull);
      },
    );

    test('prevKdK/prevKdD keep their normal (non-null) value when there is no '
        'gap before today', () {
      final now = DateTime(2026, 1, 1);
      final entries = List.generate(
        67,
        (i) => createTestPrice(
          date: now.add(Duration(days: i)),
          close: 100.0 + (i % 10).toDouble(),
          volume: 1000,
        ),
      );

      final indicators = coordinator.calculateTechnicalIndicators(entries);

      expect(indicators, isNotNull);
      expect(indicators!.kdK, isNotNull);
      expect(indicators.kdD, isNotNull);
      expect(indicators.prevKdK, isNotNull);
      expect(indicators.prevKdD, isNotNull);
    });
  });
}
