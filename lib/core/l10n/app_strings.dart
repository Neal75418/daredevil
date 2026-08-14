import 'package:easy_localization/easy_localization.dart';

import 'package:daredevil/core/utils/number_formatter.dart';

/// 應用程式字串集中管理（基於 easy_localization）
///
/// 此類別為所有 UI 字串的單一來源，
/// 內部委託 `.tr()` 讀取 JSON 翻譯檔。
///
/// 使用範例：
/// ```dart
/// Text(S.appName)
/// Text(S.priceUp(2.5))
/// ```
class S {
  S._();

  // ==================================================
  // 應用程式通用
  // ==================================================
  static String get appName => 'app.name'.tr();
  static String get retry => 'common.retry'.tr();
  static String get refresh => 'common.refresh'.tr();
  static String get settings => 'common.settings'.tr();
  static String get detail => 'common.detail'.tr();

  // ==================================================
  // 今日頁面
  // ==================================================
  /// 動態 header：`今日推薦 ({count} 檔)` — 反映該 mode 通過 eligibility filter
  /// 後實際清單長度（每天不固定）。loading / 無資料 fallback 用 [todayTop10Loading]。
  ///
  /// **2026-06-20**：從固定 `今日推薦 Top 20` 改動態。舊「Top 20」是 horizon
  /// UI 時代 hardcoded 20 cap 的字面、跟新 Mode UI 動態 cap 30 + score floor
  /// 邏輯不符。動態 N 反映真實品質：Mode A 通常 15-30、Mode B 飽和 30、Mode C
  /// 強市稀缺 0-5。
  static String todayTop10(int count) =>
      'today.top10'.tr(namedArgs: {'count': '$count'});

  /// loading / error fallback header（沒 count）
  static String get todayTop10Loading => 'today.top10Loading'.tr();

  static String get todayUpdateData => 'today.updateData'.tr();
  static String get todayPriceAlert => 'today.priceAlert'.tr();
  static String todayLastUpdate(String time) =>
      'today.lastUpdate'.tr(namedArgs: {'time': time});
  static String todayDataDate(String date) =>
      'today.dataDate'.tr(namedArgs: {'date': date});
  static String get todayDataToday => 'today.dataToday'.tr();
  static String get todayDataYesterday => 'today.dataYesterday'.tr();
  static String todayUpdateFailed(String error) =>
      'today.updateFailed'.tr(namedArgs: {'error': error});
  static String get todayWarningDetail => 'today.warningDetail'.tr();
  static String get todayWarningItems => 'today.warningItems'.tr();

  // ==================================================
  // 新聞頁面
  // ==================================================
  static String get newsTitle => 'news.title'.tr();
  static String get newsToday => 'news.today'.tr();
  static String get newsYesterday => 'news.yesterday'.tr();
  static String get newsEarlier => 'news.earlier'.tr();
  static String get newsRelatedStocks => 'news.relatedStocks'.tr();
  static String get newsOpenInBrowser => 'news.openInBrowser'.tr();
  static String get newsCannotOpenLink => 'news.cannotOpenLink'.tr();
  static String newsMinutesAgo(int minutes) =>
      'news.minutesAgo'.tr(namedArgs: {'minutes': minutes.toString()});
  static String newsHoursAgo(int hours) =>
      'news.hoursAgo'.tr(namedArgs: {'hours': hours.toString()});
  static String newsDaysAgo(int days) =>
      'news.daysAgo'.tr(namedArgs: {'days': days.toString()});

  // ==================================================
  // 自選股頁面
  // ==================================================
  static String watchlistRemoved(String symbol) =>
      'watchlist.removed'.tr(namedArgs: {'symbol': symbol});
  static String watchlistAddedToWatchlist(String symbol) =>
      'watchlist.addedToWatchlist'.tr(namedArgs: {'symbol': symbol});
  static String get watchlistAddFailed => 'watchlist.addFailed'.tr();
  static String get watchlistRemoveFailed => 'watchlist.removeFailed'.tr();
  static String get watchlistUndo => 'watchlist.undo'.tr();
  static String get watchlistRemoveTooltip => 'watchlist.removeTooltip'.tr();
  static String get watchlistAddTooltip => 'watchlist.addTooltip'.tr();

  // ==================================================
  // 股票詳情
  // ==================================================
  static String get stockAddToWatchlist => 'stock.addToWatchlist'.tr();
  static String get stockRemoveFromWatchlist =>
      'stock.removeFromWatchlist'.tr();
  static String get stockViewDetails => 'stock.viewDetails'.tr();
  static String get stockPreview => 'stock.preview'.tr();

  // ==================================================
  // 評分
  // ==================================================
  static String get scoreLabel => 'score.label'.tr();
  static String get scoreLevelStrong => 'score.strong'.tr();
  // 下三者無外部呼叫者,但由 [getScoreLevel] 裸名消費(2026-08-15 審計:
  // 外部 grep `S.x` 會誤判死碼,類內傳遞性存活)
  static String get scoreLevelWatch => 'score.watch'.tr();
  static String get scoreLevelNormal => 'score.normal'.tr();
  static String get scoreLevelWait => 'score.wait'.tr();

  static String getScoreLevel(double score) {
    if (score >= 80) return scoreLevelStrong;
    if (score >= 60) return scoreLevelWatch;
    if (score >= 40) return scoreLevelNormal;
    return scoreLevelWait;
  }

  // ==================================================
  // 趨勢
  // ==================================================
  // 由 [getTrendLabel] 裸名消費(傳遞性存活,同評分區說明)
  static String get trendUp => 'trend.up'.tr();
  static String get trendDown => 'trend.down'.tr();
  static String get trendSideways => 'trend.sideways'.tr();

  static String getTrendLabel(String? trendState) {
    return switch (trendState) {
      'UP' => trendUp,
      'DOWN' => trendDown,
      _ => trendSideways,
    };
  }

  // ==================================================
  // 價格
  // ==================================================
  static String get priceUp => 'price.up'.tr();
  static String get priceDown => 'price.down'.tr();
  static String get priceNeutral => 'price.neutral'.tr();
  static String get priceLimitUp => 'price.limitUp'.tr();
  static String get priceLimitDown => 'price.limitDown'.tr();

  static String priceChangeLabel(double? change) {
    if (change == null || change == 0) return priceNeutral;
    return change > 0 ? priceUp : priceDown;
  }

  // ==================================================
  // 推薦理由（訊號類型）
  // ==================================================
  static String get reasonsLabel => 'reasons.label'.tr();

  // ==================================================
  // 空狀態
  // ==================================================
  static String get emptyNoRecommendations => 'empty.noRecommendations'.tr();
  static String get emptyNoRecommendationsHint =>
      'empty.noRecommendationsHint'.tr();
  static String get emptyNoFilterResults => 'empty.noFilterResults'.tr();
  static String get emptyNoFilterResultsHint =>
      'empty.noFilterResultsHint'.tr();
  static String get emptyClearFilter => 'empty.clearFilter'.tr();
  static String get emptyNoWatchlist => 'empty.noWatchlist'.tr();
  static String get emptyNoWatchlistHint => 'empty.noWatchlistHint'.tr();
  static String get emptyAddWatchlist => 'empty.addWatchlist'.tr();
  static String get emptyNoNews => 'empty.noNews'.tr();
  static String get emptyNoNewsHint => 'empty.noNewsHint'.tr();
  static String get emptyError => 'empty.error'.tr();
  static String get emptyNetworkError => 'empty.networkError'.tr();
  static String get emptyNetworkErrorHint => 'empty.networkErrorHint'.tr();

  // ==================================================
  // 無障礙
  // ==================================================
  static String accessibilityStock(String symbol) =>
      'accessibility.stock'.tr(namedArgs: {'symbol': symbol});
  static String accessibilityPrice(double price) =>
      'accessibility.price'.tr(namedArgs: {'price': price.toStringAsFixed(2)});

  /// 漲跌幅的無障礙播報：**先依顯示精度（2 位）捨入再判方向**。
  ///
  /// 平盤與捨入歸零一律播報「持平」，避免畫面顯示中性的 `0.00%`、
  /// 螢幕閱讀器卻念「上漲 0.00 百分比」的矛盾。
  static String accessibilityPriceChange(double change) {
    final rounded = AppNumberFormat.roundForDisplay(change, 2);
    if (rounded == 0) return 'accessibility.priceChangeNeutral'.tr();
    final key = rounded > 0
        ? 'accessibility.priceChangeUp'
        : 'accessibility.priceChangeDown';
    return key.tr(namedArgs: {'change': rounded.abs().toStringAsFixed(2)});
  }

  static String accessibilityScore(int score) =>
      'accessibility.score'.tr(namedArgs: {'score': score.toString()});
  static String accessibilitySignals(String signals) =>
      'accessibility.signals'.tr(namedArgs: {'signals': signals});

  // 股票詳情頁無障礙標籤
  static String accessibilityClosePrice(String price) =>
      'accessibility.closePrice'.tr(namedArgs: {'price': price});
  static String accessibilityAbsoluteChange(String change) =>
      'accessibility.absoluteChange'.tr(namedArgs: {'change': change});
  static String accessibilityPriceChangeDetail(
    String absText,
    String pctText,
  ) => 'accessibility.priceChangeDetail'.tr(
    namedArgs: {'absText': absText, 'pctText': pctText},
  );
  static String accessibilityTrend(String trend) =>
      'accessibility.trend'.tr(namedArgs: {'trend': trend});

  // 比較頁面無障礙標籤
  static String accessibilityPriceComparisonChart(String symbols) =>
      'accessibility.priceComparisonChart'.tr(namedArgs: {'symbols': symbols});
  static String accessibilityRadarChart(String symbols) =>
      'accessibility.radarChart'.tr(namedArgs: {'symbols': symbols});
  static String accessibilityComparisonTable(String symbols) =>
      'accessibility.comparisonTable'.tr(namedArgs: {'symbols': symbols});

  // 投資組合無障礙標籤
  static String accessibilityAllocationPieChart(int count) =>
      'accessibility.allocationPieChart'.tr(
        namedArgs: {'count': count.toString()},
      );

  // 走勢圖無障礙標籤
  static String get sparklineDefault => 'accessibility.sparklineDefault'.tr();
  static String sparklineFlat(int days) =>
      'accessibility.sparklineFlat'.tr(namedArgs: {'days': days.toString()});
  static String sparklineTrend(int days, double change) {
    final key = change >= 0
        ? 'accessibility.sparklineTrendUp'
        : 'accessibility.sparklineTrendDown';
    return key.tr(
      namedArgs: {
        'days': days.toString(),
        'change': change.abs().toStringAsFixed(1),
      },
    );
  }

  // Shimmer 載入無障礙標籤
  static String get shimmerLoadingStockList =>
      'accessibility.shimmerStockList'.tr();
  static String get shimmerLoadingStockDetail =>
      'accessibility.shimmerStockDetail'.tr();
  static String get shimmerLoadingNewsList =>
      'accessibility.shimmerNewsList'.tr();
  static String get shimmerLoadingGenericList =>
      'accessibility.shimmerGenericList'.tr();

  // ==================================================
  // 市場類型
  // ==================================================
  static String get marketTWSE => 'market.twse'.tr();
  static String get marketTPEx => 'market.tpex'.tr();

  // ==================================================
  // 基本面
  // ==================================================
  static String dividendYearAverage(int years) =>
      'fundamental.dividendYearAverage'.tr(
        namedArgs: {'years': years.toString()},
      );

  // ==================================================
  // 時間與日期
  // ==================================================
  static String dateFormat(DateTime dt) {
    final local = dt.toLocal();
    return '${local.month}/${local.day} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
}
