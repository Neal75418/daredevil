// 資料缺漏提示不得誤報 —— 籌碼分佈是延遲載入的
//
// 實機（2026-07-26，2357 華碩）：摘要頁頁首常駐「資料缺漏：籌碼分佈
// （分數可能因此偏低）」，但 DB 實測該股有 45 列 holding_distribution，
// 且**全市場 2,129 檔有價格的股票沒有任何一檔缺這份資料**。
//
// 根因：`loadChipData()` 的唯一呼叫點是 chip_tab.dart —— 只有使用者開啟
// 「籌碼」分頁才載入。而 `_computeMissingDomains` 在每個分頁的頁首都會跑，
// 檢查 `chip.holdingDistribution.isEmpty`。既有守門只擋 `isLoadingChip`，
// 但「從未開始載入」時該旗標也是 false，於是直接判定缺漏。
//
// 註解原本就寫著「載入中不判定缺漏（避免非同步子狀態未到位時閃現假提示）」
// —— 意圖正確，只是漏了「從未載入」這個狀態。
//
// 後果比看起來嚴重：一個對每檔股票都出現的假警告會訓練使用者忽略警告，
// 於是真的缺資料時反而看不見。判準用 `chipStrength != null`，與
// `loadChipData` 自身的「已載入」哨兵同源。
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/core/constants/chip_strength.dart';
import 'package:daredevil/presentation/providers/stock_detail_state.dart';
import 'package:daredevil/presentation/screens/stock_detail/widgets/stock_detail_header.dart';

void main() {
  StockMasterEntry stock(String symbol) => StockMasterEntry(
    symbol: symbol,
    name: '測試',
    market: 'TWSE',
    isActive: true,
    updatedAt: DateTime(2026, 7, 24),
  );

  DailyPriceEntry price(String symbol) =>
      DailyPriceEntry(symbol: symbol, date: DateTime(2026, 7, 24), close: 100);

  StockDetailState stateWith({
    required bool chipLoaded,
    List<HoldingDistributionEntry> distribution = const [],
  }) => StockDetailState(
    price: StockPriceState(stock: stock('2357'), priceHistory: [price('2357')]),
    fundamentals: const FundamentalsState(),
    chip: ChipAnalysisState(
      institutionalHistory: [
        DailyInstitutionalEntry(symbol: '2357', date: DateTime(2026, 7, 24)),
      ],
      holdingDistribution: distribution,
      chipStrength: chipLoaded
          ? const ChipStrengthResult(
              score: 50,
              rating: ChipRating.neutral,
              attitude: InstitutionalAttitude.neutral,
              measuredDomains: 6,
            )
          : null,
    ),
    loading: const LoadingState(),
  );

  test('🚨 籌碼尚未載入時不得宣稱籌碼分佈缺漏', () {
    final data = StockHeaderData.fromState(stateWith(chipLoaded: false));

    expect(
      data.missingDomains,
      isNot(contains('stockDetail.domain.distribution')),
      reason:
          '延遲載入的資料在載入前狀態是「未知」，不是「缺漏」——'
          '對每檔股票都出現的假警告會訓練使用者忽略警告',
    );
  });

  test('籌碼已載入且確實無資料時才回報缺漏', () {
    final data = StockHeaderData.fromState(stateWith(chipLoaded: true));

    expect(
      data.missingDomains,
      contains('stockDetail.domain.distribution'),
      reason: '真的缺資料仍須揭露，否則這個提示就沒用了',
    );
  });

  test('籌碼已載入且有資料時不報缺漏', () {
    final data = StockHeaderData.fromState(
      stateWith(
        chipLoaded: true,
        distribution: [
          HoldingDistributionEntry(
            symbol: '2357',
            date: DateTime(2026, 7, 24),
            level: '1-999',
          ),
        ],
      ),
    );

    expect(
      data.missingDomains,
      isNot(contains('stockDetail.domain.distribution')),
    );
  });
}
