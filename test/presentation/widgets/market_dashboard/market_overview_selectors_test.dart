import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/constants/market_codes.dart';
import 'package:daredevil/data/models/twse/twse_market_index.dart';
import 'package:daredevil/domain/services/market_sentiment_service.dart';
import 'package:daredevil/presentation/providers/market_overview_provider.dart';
import 'package:daredevil/presentation/widgets/market_dashboard/market_overview_selectors.dart';

import '../../../helpers/widget_test_helpers.dart';

TwseMarketIndex _index(String name, double close, double pct) =>
    TwseMarketIndex(
      date: DateTime(2026, 9, 24),
      name: name,
      close: close,
      change: close * pct / 100,
      changePercent: pct,
    );

List<DatedValue> _series(List<double> values) => [
  for (var i = 0; i < values.length; i++)
    (date: DateTime(2026, 9, 1 + i), value: values[i]),
];

void main() {
  setUpAll(() async => setupTestLocalization());

  group('heroIndexOf', () {
    const state = MarketOverviewState();
    test('上市取加權、上櫃取櫃買', () {
      final s = state.copyWith(
        indices: [
          _index(MarketIndexNames.taiex, 48024.6, -0.28),
          _index(MarketIndexNames.tpexIndex, 285.3, 0.1),
        ],
      );
      expect(heroIndexOf(s, MarketCode.twse)!.close, 48024.6);
      expect(heroIndexOf(s, MarketCode.tpex)!.close, 285.3);
    });
    test('查無主指數回 null', () {
      expect(heroIndexOf(state, MarketCode.twse), isNull);
    });
  });

  group('computeMarketSentiment', () {
    const ad = AdvanceDecline(advance: 408, decline: 667, unchanged: 149);
    test('沒有漲跌家數 → null', () {
      expect(
        computeMarketSentiment(const MarketOverviewState(), MarketCode.twse),
        isNull,
      );
    });
    test('漲跌家數為 0 → null', () {
      final s = const MarketOverviewState().copyWith(
        advanceDeclineByMarket: {MarketCode.twse: const AdvanceDecline()},
        historyTrends: HistoryTrends(
          turnover: {
            MarketCode.twse: _series([1, 2]),
          },
        ),
      );
      expect(computeMarketSentiment(s, MarketCode.twse), isNull);
    });
    test('法人 <5 筆且成交額 <2 筆 → null', () {
      final s = const MarketOverviewState().copyWith(
        advanceDeclineByMarket: {MarketCode.twse: ad},
        historyTrends: HistoryTrends(
          institutionalTotalNet: {
            MarketCode.twse: _series([1, 2, 3, 4]),
          },
          turnover: {
            MarketCode.twse: _series([1]),
          },
        ),
      );
      expect(computeMarketSentiment(s, MarketCode.twse), isNull);
    });
    test('法人剛好 5 筆、無成交額 → 算得出（法人路徑）', () {
      final s = const MarketOverviewState().copyWith(
        advanceDeclineByMarket: {MarketCode.twse: ad},
        historyTrends: HistoryTrends(
          institutionalTotalNet: {
            MarketCode.twse: _series([1, 2, 3, 4, 5]),
          },
        ),
      );
      expect(computeMarketSentiment(s, MarketCode.twse), isNotNull);
    });

    test('無法人、成交額剛好 2 筆 → 算得出（成交額路徑）', () {
      final s = const MarketOverviewState().copyWith(
        advanceDeclineByMarket: {MarketCode.twse: ad},
        historyTrends: HistoryTrends(
          turnover: {
            MarketCode.twse: _series([100, 90]),
          },
        ),
      );
      expect(computeMarketSentiment(s, MarketCode.twse), isNotNull);
    });

    // 每條輸入都填不同數值，參數接錯（例如法人傳成融資）或漏傳都會讓
    // 子分數對不上
    test('五條輸入各自送進 calculate 的對應參數', () {
      final inst = [-50.0, 30.0, -20.0, 80.0, -120.0, 60.0];
      final turnover = [100.0, 120.0, 90.0, 140.0];
      final margin = [700.0, 705.0, 698.0, 710.0];
      const industries = [
        IndustrySummary(
          industry: '半導體',
          stockCount: 10,
          avgChangePct: 1.2,
          advance: 7,
          decline: 3,
        ),
        IndustrySummary(
          industry: '航運',
          stockCount: 8,
          avgChangePct: -0.8,
          advance: 2,
          decline: 6,
        ),
        IndustrySummary(
          industry: '金融',
          stockCount: 12,
          avgChangePct: 0.3,
          advance: 6,
          decline: 5,
        ),
      ];
      final s = const MarketOverviewState().copyWith(
        advanceDeclineByMarket: {MarketCode.twse: ad},
        industrySummaryByMarket: {MarketCode.twse: industries},
        historyTrends: HistoryTrends(
          institutionalTotalNet: {MarketCode.twse: _series(inst)},
          turnover: {MarketCode.twse: _series(turnover)},
          marginBalance: {MarketCode.twse: _series(margin)},
        ),
      );
      final expected = MarketSentimentService.calculate(
        advanceDecline: ad,
        institutionalNetHistory: inst,
        turnoverHistory: turnover,
        marginBalanceHistory: margin,
        industries: industries,
      );

      final actual = computeMarketSentiment(s, MarketCode.twse)!;

      expect(actual.subScores, equals(expected.subScores));
      expect(actual.score, expected.score);
      expect(actual.level, expected.level);
      // 前提：五條子分數都有進來，否則上面的比對可能兩邊一起缺
      expect(expected.subScores.length, 5);
    });
  });

  // 正負號看 change（與顏色同一欄位）；twse_client 在「方向 -、漲跌幅
  // 0.00」時會給 changePercent = -0.0，不能顯示成「+-0.00%」
  group('indexChangePercentText', () {
    TwseMarketIndex idx(double change, double pct) => TwseMarketIndex(
      date: DateTime(2026, 9, 24),
      name: MarketIndexNames.taiex,
      close: 48000,
      change: change,
      changePercent: pct,
    );
    test('上漲帶 +', () => expect(indexChangePercentText(idx(28, 0.1)), '+0.10%'));
    test(
      '下跌帶 -',
      () => expect(indexChangePercentText(idx(-132.69, -0.28)), '-0.28%'),
    );
    test('平盤不帶號', () => expect(indexChangePercentText(idx(0, 0)), '0.00%'));
    test('跌 2 點、漲跌幅 -0.0 → -0.00%', () {
      expect(indexChangePercentText(idx(-2, -0.0)), '-0.00%');
    });
  });

  test('sentimentLevelText：五個等級各對應自己的 i18n key', () {
    for (final level in SentimentLevel.values) {
      expect(
        sentimentLevelText(level),
        'marketOverview.sentiment.${level.name}',
      );
    }
  });
}
