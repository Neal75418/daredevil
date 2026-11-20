import 'package:daredevil/core/constants/market_index_names.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/data/database/dao/user_dao.dart';

/// 第 [i] 個交易日（從 2026-01-05 週一起，跳過週末）
DateTime tradingDay(int i) {
  var d = DateTime(2026, 1, 5);
  var left = i;
  while (left > 0) {
    d = d.add(const Duration(days: 1));
    if (d.weekday != DateTime.saturday && d.weekday != DateTime.sunday) left--;
  }
  return d;
}

/// 依收盤序列造日線：漲跌＝收盤 − 前一根收盤（第一根為 null），最高、最低
/// 預設等於收盤，成交量預設 5,000,000 股；[nullVolumes] 指定的根成交量為 null。
List<DailyPriceEntry> barsFrom(
  List<double> closes, {
  Map<int, double> highs = const {},
  Map<int, double> lows = const {},
  Map<int, double> volumes = const {},
  Set<int> nullVolumes = const {},
  String symbol = '2330',
  int startDay = 0,
}) {
  return [
    for (var i = 0; i < closes.length; i++)
      DailyPriceEntry(
        symbol: symbol,
        date: tradingDay(startDay + i),
        open: closes[i],
        high: highs[i] ?? closes[i],
        low: lows[i] ?? closes[i],
        close: closes[i],
        volume: nullVolumes.contains(i) ? null : volumes[i] ?? 5000000,
        priceChange: i == 0 ? null : closes[i] - closes[i - 1],
      ),
  ];
}

/// 依收盤序列造加權指數
List<MarketIndexEntry> taiexFrom(List<double> closes, {int startDay = 0}) {
  return [
    for (var i = 0; i < closes.length; i++)
      MarketIndexEntry(
        id: i + 1,
        date: tradingDay(startDay + i),
        name: MarketIndexNames.taiex,
        close: closes[i],
        change: 0,
        changePercent: 0,
        createdAt: tradingDay(startDay + i),
      ),
  ];
}

List<double> repeat(double value, int count) => List.filled(count, value);

/// 第 i 個交易日的外資、投信買賣超（股）；`null` 代表那天沒有該股的法人列
List<DailyInstitutionalEntry> instFrom(
  List<({double foreign, double trust})?> days, {
  String symbol = '2330',
  int startDay = 0,
}) {
  return [
    for (var i = 0; i < days.length; i++)
      if (days[i] case final d?)
        DailyInstitutionalEntry(
          symbol: symbol,
          date: tradingDay(startDay + i),
          foreignNet: d.foreign,
          investmentTrustNet: d.trust,
          dealerNet: 0,
          dealerSelfNet: 0,
        ),
  ];
}

PortfolioTransactionEntry txOn(
  int day,
  String type,
  double quantity, {
  double price = 100,
  String symbol = '2330',
  int id = 0,
  DateTime? createdAt,
}) => PortfolioTransactionEntry(
  id: id,
  symbol: symbol,
  txType: type,
  date: tradingDay(day),
  quantity: quantity,
  price: price,
  fee: 0,
  tax: 0,
  createdAt: createdAt ?? tradingDay(day),
);

PortfolioPositionEntry positionOf({
  String symbol = '2330',
  required double quantity,
  required double avgCost,
}) => PortfolioPositionEntry(
  id: 1,
  symbol: symbol,
  quantity: quantity,
  avgCost: avgCost,
  realizedPnl: 0,
  totalDividendReceived: 0,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

StockMasterEntry stockOf(
  String symbol, {
  String market = 'TWSE',
  String? industry = '半導體業',
}) => StockMasterEntry(
  symbol: symbol,
  name: '名$symbol',
  market: market,
  industry: industry,
  isActive: true,
  updatedAt: DateTime(2026),
);

WatchlistGroupEntry groupOf(int id, String name, int sortOrder) =>
    WatchlistGroupEntry(
      id: id,
      name: name,
      sortOrder: sortOrder,
      isDefault: false,
      createdAt: DateTime(2026),
    );

WatchlistWithGroup watchOf(String symbol, {WatchlistGroupEntry? group}) =>
    WatchlistWithGroup(
      entry: WatchlistEntry(
        symbol: symbol,
        createdAt: DateTime(2026),
        groupId: group?.id,
      ),
      groupName: group?.name,
    );

/// 最近 3 個月營收年增都是 [yoy]（%）
List<MonthlyRevenueEntry> revenueOf(String symbol, double yoy) => [
  for (var m = 8; m <= 10; m++)
    MonthlyRevenueEntry(
      symbol: symbol,
      date: DateTime(2025, m),
      revenueYear: 2025,
      revenueMonth: m,
      revenue: 1000,
      yoyGrowth: yoy,
    ),
];
