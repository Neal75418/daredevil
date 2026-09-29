import 'package:easy_localization/easy_localization.dart';

import 'package:daredevil/core/constants/market_codes.dart';
import 'package:daredevil/core/utils/date_context.dart';
import 'package:daredevil/data/models/twse/twse_market_index.dart';
import 'package:daredevil/domain/services/market_sentiment_service.dart';
import 'package:daredevil/presentation/providers/market_overview_provider.dart';

/// 市場主指數名稱：上市取加權指數、上櫃取櫃買指數
String heroIndexName(String marketKey) => marketKey == MarketCode.twse
    ? MarketIndexNames.taiex
    : MarketIndexNames.tpexIndex;

/// 該市場的主指數；查無回 null
TwseMarketIndex? heroIndexOf(MarketOverviewState state, String marketKey) {
  final name = heroIndexName(marketKey);
  for (final idx in state.indices) {
    if (idx.name == name) return idx;
  }
  return null;
}

/// 指數漲跌幅文字（大盤頁 hero 與今日頁摘要條共用）
///
/// 正負號看 [TwseMarketIndex.change]，與漲跌配色同一欄位：`changePercent`
/// 在「方向 -、漲跌幅 0.00」時是 -0.0，看它會顯示成「+-0.00%」。
String indexChangePercentText(TwseMarketIndex index) {
  final sign = index.change > 0 ? '+' : '';
  return '$sign${index.changePercent.toStringAsFixed(2)}%';
}

/// 指定市場的今日情緒分數；資料不足回 null（儀表板與今日頁摘要條共用）
///
/// 今日情緒：法人、融資取各自完整序列的值獨立計算（不跨序列對齊）；
/// 資金流向取漲跌家數那天的單點值（見 [_latestOn]），兩者須同一交易日。
MarketSentiment? computeMarketSentiment(
  MarketOverviewState state,
  String marketKey,
) {
  final ad = state.advanceDeclineByMarket[marketKey];
  final trends = state.historyTrends;
  final instHist = trends.institutionalTotalNet[marketKey];
  final marginHist = trends.marginBalance[marketKey];
  final industries = state.industrySummaryByMarket[marketKey];
  // 漲跌家數當日缺資料時回退到前一交易日（advanceDeclineStaleDates），
  // 資金流向要取同一天
  final adDate = state.advanceDeclineStaleDates[marketKey] ?? state.dataDate;
  final upShare = _latestOn(trends.upVolumeShare[marketKey], adDate);

  // 至少需要漲跌家數 + 一項可用的歷史資料
  if (ad == null || ad.total == 0) return null;
  if ((instHist == null || instHist.length < 5) && upShare == null) {
    return null;
  }

  return MarketSentimentService.calculate(
    advanceDecline: ad,
    institutionalNetHistory: _values(instHist) ?? const [],
    upVolumeShare: upShare,
    marginBalanceHistory: _values(marginHist) ?? const [],
    industries: industries ?? [],
  );
}

/// 情緒等級的顯示文字
String sentimentLevelText(SentimentLevel level) {
  final key = switch (level) {
    SentimentLevel.extremeFear => 'marketOverview.sentiment.extremeFear',
    SentimentLevel.fear => 'marketOverview.sentiment.fear',
    SentimentLevel.neutral => 'marketOverview.sentiment.neutral',
    SentimentLevel.greed => 'marketOverview.sentiment.greed',
    SentimentLevel.extremeGreed => 'marketOverview.sentiment.extremeGreed',
  };
  return key.tr();
}

List<double>? _values(List<DatedValue>? series) =>
    series?.map((e) => e.value).toList();

/// 序列最後一筆的值——僅當它落在 [date] 那天；[date] 為 null 時取最後一筆。
///
/// 資金流向必須與漲跌家數同一交易日：該日若因報價不足被完整日過濾濾掉，
/// 取最後一筆會拿到別的交易日、與漲跌家數混算，寧可缺席。
double? _latestOn(List<DatedValue>? series, DateTime? date) {
  if (series == null || series.isEmpty) return null;
  final last = series.last;
  if (date == null) return last.value;
  return DateContext.isSameDay(last.date, date) ? last.value : null;
}
