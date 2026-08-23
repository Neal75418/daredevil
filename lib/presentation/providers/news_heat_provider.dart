// lib/presentation/providers/news_heat_provider.dart
//
// 新聞熱度＝**發現層**，不是買點。
//
// 熱度標記的很可能是頂部而非起點——本功能的定位是「觀察清單產生器」：
// 從近期新聞找出主流族群與焦點股，等它們回檔修正時再由既有三模式與
// 使用者判斷進場時機，用途正是避免追高。
//
// 因此熱度**刻意不進評分**（匹配結果不寫 `news_stock_map`，由架構保證而非
// 靠約定，見 `StockNameMatcher` 的 class doc）。未來若要讓熱度影響評分，
// 必須先用 `news_mention_daily` 的快照資料回測驗證，不得直接接線。
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:daredevil/core/constants/news_heat_params.dart';
import 'package:daredevil/core/constants/scoring_mode.dart';
import 'package:daredevil/domain/services/price_calculator.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/domain/services/news/heat_calculator.dart';
import 'package:daredevil/domain/services/news/stock_name_matcher.dart';
import 'package:daredevil/domain/services/news/theme_matcher.dart';
import 'package:daredevil/presentation/providers/data_update_epoch_provider.dart';
import 'package:daredevil/presentation/providers/mode_recommendation_provider.dart';
import 'package:daredevil/presentation/providers/providers.dart';

/// 熱度分析結果（新聞頁「熱度分析」Tab 的完整狀態）
class NewsHeatAnalysis {
  const NewsHeatAnalysis({
    required this.themes,
    required this.stocks,
    required this.stockNames,
    required this.modeBySymbol,
    this.priceChangeBySymbol = const {},
    this.warningBySymbol = const {},
    this.surgeReliable = false,
  });

  /// 主流族群 Top N（articles7d 降冪）
  final List<ThemeHeat> themes;

  /// 焦點股 Top N（mentions7d 降冪）
  final List<StockHeat> stocks;

  /// symbol → 公司名（顯示用）
  final Map<String, String> stockNames;

  /// 三模式交叉：symbol → 當前指派 mode（未入選任何 mode 則缺 key）
  final Map<String, ScoringMode> modeBySymbol;

  /// 焦點股（僅 [stocks] 內的 Top N）今日漲跌幅 %。
  /// 無法計算者（無最新價或缺漲跌價差）不在 map——UI 應缺省不顯示而非當 0。
  final Map<String, double> priceChangeBySymbol;

  /// 焦點股的生效警示（注意/處置股，DISPOSAL 優先）——同樣僅查 Top N
  final Map<String, TradingWarningEntry> warningBySymbol;

  /// 爆量類顯示（🔥/新進榜/爆量排序）是否有統計意義
  /// （見 [HeatResult.surgeReliable]）。預設 false = 保守隱藏徽章。
  final bool surgeReliable;
}

/// 即時計算近 28 天新聞的熱度分析。
///
/// 資料源與新聞頁共用（重新整理抓完 RSS 後 invalidate 本 provider 即同步）。
/// 匹配結果只存在記憶體，不寫 news_stock_map（不進評分）。
final newsHeatProvider = FutureProvider<NewsHeatAnalysis>((ref) async {
  ref.watch(dataUpdateEpochProvider);

  final newsRepo = ref.read(newsRepositoryProvider);
  final db = ref.read(databaseProvider);

  const windowDays =
      NewsHeatParams.recentWindowDays + NewsHeatParams.baselineWindowDays;
  final news = await newsRepo.getRecentNews(days: windowDays);
  final stocks = await db.getAllActiveStocks();

  final nameMatcher = StockNameMatcher.fromStocks(stocks);
  final themeMatcher = ThemeMatcher();
  final articles = [
    for (final n in news)
      ArticleTags(
        newsId: n.id,
        publishedAt: n.publishedAt,
        symbols: nameMatcher.match(n.title),
        themes: themeMatcher.match(n.title),
        source: n.source,
        hasRiskKeyword: NewsHeatParams.riskNewsKeywords.any(n.title.contains),
      ),
  ];
  final heat = HeatCalculator().compute(articles, now: DateTime.now());

  // 三模式交叉（與今日頁同源）
  final modeBySymbol = <String, ScoringMode>{};
  for (final mode in ScoringMode.userFacingModes) {
    final recs = await ref.watch(modeRecommendationsProvider(mode).future);
    for (final r in recs) {
      modeBySymbol[r.symbol] = mode;
    }
  }

  // 警示與今日漲跌幅：只查焦點股 Top N（≤ topStocksCount 檔），
  // 兩者皆為單發批次查詢，不載入價格歷史。
  final topStocks = heat.stocks.take(NewsHeatParams.topStocksCount).toList();
  final topSymbols = [for (final s in topStocks) s.symbol];
  final warningBySymbol = await db.getActiveWarningsMapBatch(topSymbols);

  // 漲跌幅走最輕路徑：getLatestPricesBatch 一發 SQL 拿每檔最新價，
  // calculatePriceChange 優先用 API 帶的漲跌價差（priceChange 欄位），
  // 故不需載入歷史（傳空 map）。極少數最新價缺 priceChange 的（FinMind
  // 回補列）算不出來 → 不進 map，UI 缺省不顯示。
  final latestPrices = await db.getLatestPricesBatch(topSymbols);
  final priceChanges = PriceCalculator.calculatePriceChangesBatch(
    const {},
    latestPrices,
  );
  final priceChangeBySymbol = <String, double>{
    for (final e in priceChanges.entries)
      if (e.value != null) e.key: e.value!,
  };

  return NewsHeatAnalysis(
    themes: heat.themes.take(NewsHeatParams.topThemesCount).toList(),
    stocks: topStocks,
    stockNames: {for (final s in stocks) s.symbol: s.name},
    modeBySymbol: modeBySymbol,
    priceChangeBySymbol: priceChangeBySymbol,
    warningBySymbol: warningBySymbol,
    surgeReliable: heat.surgeReliable,
  );
});
