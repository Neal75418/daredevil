// 自選股的流動性豁免要一路貫穿(2026-08-16 實機)
//
// **現象**:2059 川湖在自選股頁是一張空白卡,而且從 8/11 起連續四天。
//
// **真因**(第一次診斷成「零訊號」是錯的):`LiquidityChecker` 的
// `minCandidateVolumeShares` 是**股數**門檻(100 萬股)。川湖股價 12,500 元,
// 每天成交 23–46 萬股 = 成交額 29–56 **億**,流動性好得不得了,卻過不了一個
// 用股數計的門檻——12,500 元的股票要成交 100 萬股等於 125 億。8/10 那天量
// 剛好 1,016,839 股越過門檻,所以那天有分析;之後就再也沒有。
//
// **矛盾點**:`CandidateSelector` 步驟 1 已經寫明「自選清單優先（豁免流動性
// 過濾 — 使用者主動追蹤）」,但那個豁免只作用在中位數成交額那道;評分迴圈
// 的單日檢查沒對齊,於是上游給的豁免被下游吃掉。
//
// **MISSING_DATA 不可豁免**:下游 `prices.last.close!` / `volume!` 依賴這道
// 保證,豁免它會變成 null 崩潰。
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/domain/services/scoring_pipeline.dart';

import '../../helpers/price_data_generators.dart';

void main() {
  /// 高價低量:成交額 29 億(遠超 3000 萬門檻),但只有 23 萬股(低於 100 萬)
  List<DailyPriceEntry> highPriceLowShares() => generateConstantPrices(
    days: 60,
    basePrice: 12500,
    volume: 234633,
    symbol: '2059',
  );

  test('🚨 非自選股維持原行為:股數不足即擋下(對照組)', () {
    expect(
      classifyCandidate(highPriceLowShares()),
      CandidateSkipReason.lowLiquidity,
      reason: '全市場行為不得因這次修改而改變(實測另有 232 檔同型)',
    );
  });

  test('🚨 自選股豁免單日流動性——上游步驟 1 的豁免必須貫穿到這裡', () {
    expect(
      classifyCandidate(highPriceLowShares(), exemptFromLiquidity: true),
      isNull,
      reason: '川湖成交額 29 億卻因股數門檻被擋，自選股不該受此限',
    );
  });

  test('🚨 豁免不得跨過 MISSING_DATA——下游 close!/volume! 依賴它', () {
    final prices = [
      ...generateConstantPrices(days: 59, basePrice: 100, volume: 2000000),
      createTestPrice(
        symbol: 'TEST',
        date: DateTime.now(),
        close: null,
        volume: null,
      ),
    ];
    expect(
      classifyCandidate(prices, exemptFromLiquidity: true),
      CandidateSkipReason.noData,
      reason: '豁免的是「量太小」不是「沒有資料」，放行會在下游 null 崩潰',
    );
  });

  test('豁免不影響其他資格檢查(資料長度、當日 bar 新鮮度)', () {
    expect(
      classifyCandidate(
        generateConstantPrices(days: 3, basePrice: 100, volume: 2000000),
        exemptFromLiquidity: true,
      ),
      CandidateSkipReason.insufficientData,
    );
    expect(
      classifyCandidate(
        generateConstantPrices(days: 60, basePrice: 100, volume: 2000000),
        asOf: DateTime.now().add(const Duration(days: 3)),
        exemptFromLiquidity: true,
      ),
      CandidateSkipReason.staleBar,
    );
  });
}
