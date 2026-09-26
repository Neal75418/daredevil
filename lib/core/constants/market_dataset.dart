import 'package:daredevil/core/constants/api_config.dart';
import 'package:daredevil/core/constants/market_codes.dart';

/// 追蹤「是否已定案」的盤後資料集
///
/// [minCoverageRatio]：一次抓取寫入的列數達到「該市場在市股票數 × 比例」
/// 才記錄抓取狀態，未達視為尚未發布或抓取不完整。
enum MarketDataset {
  prices('prices', ApiConfig.historicalMarketDayMinCoverageRatio),
  institutional('institutional', ApiConfig.finalityNewDatasetMinCoverageRatio),
  dayTrading('dayTrading', ApiConfig.finalityNewDatasetMinCoverageRatio),
  margin('margin', ApiConfig.tradingBackfillMinCoverageRatio),
  foreignShareholding(
    'foreignShareholding',
    ApiConfig.foreignShareholdingMinCoverageRatio,
  );

  const MarketDataset(this.code, this.minCoverageRatio);

  /// 寫入 `market_day_fetch.dataset` 的值（不可改名：既有資料以此為鍵）
  final String code;
  final double minCoverageRatio;
}

/// 一組追蹤對象（資料集 × 市場）
typedef FinalityGroup = ({MarketDataset dataset, String market});

/// 全部 9 組。外資持股只有上市（上櫃走 FinMind 逐檔，不在追蹤範圍）
const List<FinalityGroup> finalityGroups = [
  (dataset: MarketDataset.prices, market: MarketCode.twse),
  (dataset: MarketDataset.prices, market: MarketCode.tpex),
  (dataset: MarketDataset.institutional, market: MarketCode.twse),
  (dataset: MarketDataset.institutional, market: MarketCode.tpex),
  (dataset: MarketDataset.dayTrading, market: MarketCode.twse),
  (dataset: MarketDataset.dayTrading, market: MarketCode.tpex),
  (dataset: MarketDataset.margin, market: MarketCode.twse),
  (dataset: MarketDataset.margin, market: MarketCode.tpex),
  (dataset: MarketDataset.foreignShareholding, market: MarketCode.twse),
];
