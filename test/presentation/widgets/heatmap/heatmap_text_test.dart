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
  test('即時比例與沒有值的文字依模式選 key', () {
    expect(
      heatmapCoverageSuffix(0.5, HeatmapLiveMode.intraday),
      'marketHeatmap.liveCoverage',
    );
    expect(
      heatmapCoverageSuffix(0.5, HeatmapLiveMode.afterClose),
      'marketHeatmap.closingCoverage',
    );
    expect(
      heatmapCoverageSemantics(0.5, HeatmapLiveMode.intraday),
      'marketHeatmap.semLiveCoverage',
    );
    expect(
      heatmapCoverageSemantics(0.5, HeatmapLiveMode.afterClose),
      'marketHeatmap.semClosingCoverage',
    );
    expect(
      heatmapNoChangeText(null, allNoClosingMatch: false),
      'marketHeatmap.hollowNoChange',
    );
    expect(
      heatmapNoChangeText(HeatmapLiveMode.intraday, allNoClosingMatch: false),
      'marketHeatmap.notLive',
    );
    expect(
      heatmapNoChangeText(HeatmapLiveMode.afterClose, allNoClosingMatch: false),
      'marketHeatmap.notClosed',
    );
  });

  test('🚨 區塊每一格都是收盤沒撮合：沒有值寫「收盤沒撮合」（與格子同一個 key）', () {
    expect(
      heatmapNoChangeText(HeatmapLiveMode.afterClose, allNoClosingMatch: true),
      'marketHeatmap.hollowNoClosingMatch',
    );
    expect(
      heatmapNoChangeText(HeatmapLiveMode.afterClose, allNoClosingMatch: true),
      heatmapHollowReasonText(HollowReason.noClosingMatch),
    );
  });

  group('heatmapWeightedText', () {
    test('正式資料：只有漲跌幅；沒有值寫無漲跌資料', () {
      expect(
        heatmapWeightedText(
          percent: -0.8,
          coverage: null,
          mode: null,
          allNoClosingMatch: false,
        ),
        '-0.80%',
      );
      expect(
        heatmapWeightedText(
          percent: -0.8,
          coverage: 0.5,
          mode: null,
          allNoClosingMatch: false,
        ),
        '-0.80%',
        reason: '正式資料不標比例',
      );
      expect(
        heatmapWeightedText(
          percent: null,
          coverage: null,
          mode: null,
          allNoClosingMatch: false,
        ),
        'marketHeatmap.hollowNoChange',
      );
    });

    test('即時：漲跌幅後接比例；沒有值寫模式的文字', () {
      expect(
        heatmapWeightedText(
          percent: 1.83,
          coverage: 0.96,
          mode: HeatmapLiveMode.intraday,
          allNoClosingMatch: false,
        ),
        '+1.83%marketHeatmap.liveCoverage',
      );
      expect(
        heatmapWeightedText(
          percent: null,
          coverage: 0,
          mode: HeatmapLiveMode.afterClose,
          allNoClosingMatch: false,
        ),
        'marketHeatmap.notClosed',
      );
    });

    test('🚨 收盤後區塊每一格都是收盤沒撮合：寫「收盤沒撮合」', () {
      expect(
        heatmapWeightedText(
          percent: null,
          coverage: 0,
          mode: HeatmapLiveMode.afterClose,
          allNoClosingMatch: true,
        ),
        'marketHeatmap.hollowNoClosingMatch',
      );
    });

    test('即時但沒有比例：只寫漲跌幅', () {
      expect(
        heatmapWeightedText(
          percent: 1.83,
          coverage: null,
          mode: HeatmapLiveMode.intraday,
          allNoClosingMatch: false,
        ),
        '+1.83%',
      );
    });
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

  test('即時相關的新文字在 zh-TW 與 en 都有；無障礙的比例子句不帶「・」', () {
    const zhExpected = {
      'liveCoverage': '・即時 {pct}%',
      'closingCoverage': '・收盤 {pct}%',
      'semLiveCoverage': '即時部分占 {pct}%',
      'semClosingCoverage': '已收盤部分占 {pct}%',
      'semAppend': '{base}，{clause}',
      'notLive': '未即時',
      'notClosed': '未收盤',
      'previousClose': '{date} 收盤 {pct}',
      'closingProgress': '今日收盤 {done}／{total} 檔・待盤後更新',
      'closingProgressUnmatched':
          '今日收盤 {done}／{total} 檔・{unmatched} 檔收盤沒撮合・待盤後更新',
      'statusJoin': '・',
      'tooltipBreadthWithHollow': '漲 {up}、跌 {down}、平 {flat}、空心 {hollow}',
      'semOtherWithHollow':
          '{label}，市值加權{dir} {pct}，漲 {up}、跌 {down}、平 {flat}、'
          '沒有今日漲跌 {hollow}',
      'semIndustryNoChange': '{name}，{status}，共 {count} 檔',
      'semOtherNoChange': '{label}，{status}，共 {count} 檔',
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
      }
      for (final key in ['semLiveCoverage', 'semClosingCoverage']) {
        expect(block[key] as String, isNot(contains('・')), reason: key);
        expect(block[key] as String, isNot(contains('·')), reason: key);
      }
      // 參數名稱一致：翻譯少了參數，畫面會印出 {pct} 之類的字
      for (final (key, params) in [
        ('liveCoverage', ['{pct}']),
        ('closingCoverage', ['{pct}']),
        ('semLiveCoverage', ['{pct}']),
        ('semClosingCoverage', ['{pct}']),
        ('previousClose', ['{date}', '{pct}']),
        ('closingProgress', ['{done}', '{total}']),
        ('closingProgressUnmatched', ['{done}', '{unmatched}', '{total}']),
        ('semIndustryNoChange', ['{name}', '{status}', '{count}']),
        ('semOtherNoChange', ['{label}', '{status}', '{count}']),
        ('tooltipBreadthWithHollow', ['{hollow}']),
        ('semOtherWithHollow', ['{hollow}']),
        ('semAppend', ['{base}', '{clause}']),
      ]) {
        for (final param in params) {
          expect(block[key] as String, contains(param), reason: '$locale $key');
        }
      }
    }
  });
}
