import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/domain/models/heatmap.dart';
import 'package:daredevil/presentation/providers/heatmap_live_provider.dart';
import 'package:daredevil/presentation/widgets/heatmap/heatmap_text.dart';
import 'package:daredevil/presentation/widgets/live_quote_status.dart';

import '../../../helpers/widget_test_helpers.dart';

void main() {
  setUpAll(() async => setupTestLocalization());

  // 沒載入翻譯時 `.tr()` 回 key 字串：用它確認每種原因對到各自的 key
  const keys = {
    HollowReason.noChangeData: 'marketHeatmap.hollowNoChange',
    HollowReason.notLive: 'marketHeatmap.hollowNotLive',
    HollowReason.noTrade: 'marketHeatmap.hollowNoTrade',
    HollowReason.noQuote: 'marketHeatmap.hollowNoQuote',
    HollowReason.noClosingQuote: 'marketHeatmap.hollowNoClosingQuote',
    HollowReason.noClosingMatch: 'marketHeatmap.hollowNoClosingMatch',
  };

  test('六種原因各自對到自己的翻譯 key', () {
    expect(keys.keys.toSet(), HollowReason.values.toSet());
    for (final MapEntry(key: reason, value: key) in keys.entries) {
      expect(heatmapHollowReasonText(reason), key, reason: '$reason');
    }
  });

  test('六個 key 在 zh-TW 與 en 都有文字，且彼此不同', () {
    for (final (locale, expected) in [
      (
        'zh-TW',
        {
          HollowReason.noChangeData: '無漲跌資料',
          HollowReason.notLive: '盤中未即時',
          HollowReason.noTrade: '尚無成交',
          HollowReason.noQuote: '無報價',
          HollowReason.noClosingQuote: '尚未取得收盤報價',
          HollowReason.noClosingMatch: '收盤沒撮合',
        },
      ),
      (
        'en',
        // 英文只驗存在且不重複，措辭由翻譯檔決定；收盤沒撮合照規格的措辭
        {HollowReason.noClosingMatch: 'No closing match'},
      ),
    ]) {
      final root =
          json.decode(
                File('assets/translations/$locale.json').readAsStringSync(),
              )
              as Map<String, dynamic>;
      final block = root['marketHeatmap'] as Map<String, dynamic>;
      final texts = {
        for (final MapEntry(key: reason, value: key) in keys.entries)
          reason: block[key.split('.').last] as String?,
      };
      for (final MapEntry(key: reason, value: text) in texts.entries) {
        expect(text, isNotNull, reason: '$locale 缺 ${keys[reason]}');
        expect(text, isNotEmpty);
        if (expected.containsKey(reason)) expect(text, expected[reason]);
      }
      expect(texts.values.toSet(), hasLength(6), reason: '$locale 有重複文字');
    }
  });

  group('heatmapCoveragePercent：四捨五入後夾在 1～99，恰為 0 或 1 時照實寫', () {
    for (final (coverage, expected) in [
      (0.0, 0),
      (1.0, 100),
      (0.96, 96),
      (0.5, 50),
      // 有一檔即時、比例不到 0.5%：不寫成 0%
      (0.004, 1),
      (0.0001, 1),
      // 只差一檔、四捨五入成 100：不寫成 100%
      (0.995, 99),
      (0.9999, 99),
      (0.994, 99),
      (0.015, 2),
      (double.nan, 0),
    ]) {
      test('$coverage → $expected', () {
        expect(heatmapCoveragePercent(coverage), expected);
      });
    }
  });

  // 沒載入翻譯時 `.tr()` 回 key：用 key 確認模式對到的文字；實際措辭見下方翻譯檔
  // 測試與畫面測試
  test('圖例的覆蓋率文字用 legendCoverage 這個 key；提示的價格小數 2 位', () {
    // 沒載入翻譯時 `.tr()` 回 key 字串
    expect(
      heatmapLegendCoverageText(
        tileCount: 30,
        marketLabel: 'x',
        coverage: 0.74,
      ),
      'marketHeatmap.legendCoverage',
    );
    expect(heatmapTooltipPriceText(53.4), 'marketHeatmap.tooltipPrice 53.40');
  });

  group('heatmapLiveStatusText', () {
    const paused = LiveHeaderStatus(LiveHeaderKind.pausedRateLimit, '13:41');

    test('沒有狀態也沒有進度：空字串（不顯示）', () {
      expect(
        heatmapLiveStatusText(
          const HeatmapLiveView(mode: HeatmapLiveMode.intraday),
        ),
        '',
      );
    });

    test('盤中：只有報價狀態', () {
      expect(
        heatmapLiveStatusText(
          const HeatmapLiveView(
            mode: HeatmapLiveMode.intraday,
            quoteStatus: LiveHeaderStatus(LiveHeaderKind.quoteTime, '10:30'),
          ),
        ),
        'liveQuote.quoteTime',
      );
    });

    test('收盤後：只有進度', () {
      expect(
        heatmapLiveStatusText(
          const HeatmapLiveView(
            mode: HeatmapLiveMode.afterClose,
            closing: (done: 3, unmatched: 0, total: 120),
          ),
        ),
        'marketHeatmap.closingProgress',
      );
    });

    test('🚨 收盤後有收盤沒撮合的檔：進度另寫檔數', () {
      expect(
        heatmapLiveStatusText(
          const HeatmapLiveView(
            mode: HeatmapLiveMode.afterClose,
            closing: (done: 3, unmatched: 1, total: 120),
          ),
        ),
        'marketHeatmap.closingProgressUnmatched',
      );
    });

    // 窄螢幕最多兩行、超過以省略號結束：截掉的必須是後面的進度，不是暫停
    test('收盤後又暫停：暫停在前、以分隔字接進度', () {
      for (final (unmatched, key) in [
        (0, 'marketHeatmap.closingProgress'),
        (2, 'marketHeatmap.closingProgressUnmatched'),
      ]) {
        expect(
          heatmapLiveStatusText(
            HeatmapLiveView(
              mode: HeatmapLiveMode.afterClose,
              quoteStatus: paused,
              closing: (done: 3, unmatched: unmatched, total: 120),
            ),
          ),
          'liveQuote.pausedRateLimit'
          'marketHeatmap.statusJoin'
          '$key',
          reason: '收盤沒撮合 $unmatched 檔',
        );
      }
    });

    test('停市日退回：只有報價狀態（沒有進度）', () {
      expect(
        heatmapLiveStatusText(
          const HeatmapLiveView(
            mode: HeatmapLiveMode.afterClose,
            quoteStatus: LiveHeaderStatus(LiveHeaderKind.noQuotesToday),
          ),
        ),
        'liveQuote.noQuotesToday',
      );
    });
  });

  test('狀態行與圖例的文字在 zh-TW 與 en 都有，參數名稱一致', () {
    const zhExpected = {
      'previousClose': '{date} 收盤 {pct}',
      'closingProgress': '今日收盤 {done}／{total} 檔・待盤後更新',
      'closingProgressUnmatched':
          '今日收盤 {done}／{total} 檔・{unmatched} 檔收盤沒撮合・待盤後更新',
      'statusJoin': '・',
      'legendCoverage': '市值前 {count} 檔・占{market}市值 {pct}%',
    };
    for (final locale in ['zh-TW', 'en']) {
      final root =
          json.decode(
                File('assets/translations/$locale.json').readAsStringSync(),
              )
              as Map<String, dynamic>;
      final block = root['marketHeatmap'] as Map<String, dynamic>;
      for (final key in zhExpected.keys) {
        final text = block[key] as String?;
        expect(text, isNotNull, reason: '$locale 缺 $key');
        expect(text, isNotEmpty, reason: '$locale $key');
        if (locale == 'zh-TW') expect(text, zhExpected[key], reason: key);
      }
      if (locale == 'en') {
        // 規格的英文措辭
        expect(
          block['closingProgressUnmatched'],
          "Today's close {done}/{total} · {unmatched} no closing match · "
          'after-hours data pending',
        );
        expect(
          block['closingProgress'],
          "Today's close {done}/{total} · after-hours data pending",
        );
        expect(
          block['legendCoverage'],
          'Top {count} by market cap · {pct}% of {market} market cap',
        );
      }
      // 參數名稱一致：翻譯少了參數，畫面會印出 {pct} 之類的字
      for (final (key, params) in [
        ('previousClose', ['{date}', '{pct}']),
        ('closingProgress', ['{done}', '{total}']),
        ('closingProgressUnmatched', ['{done}', '{unmatched}', '{total}']),
        ('legendCoverage', ['{count}', '{market}', '{pct}']),
      ]) {
        for (final param in params) {
          expect(block[key] as String, contains(param), reason: '$locale $key');
        }
      }
    }
  });
}
