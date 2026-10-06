import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/domain/models/live_quote.dart';
import 'package:daredevil/domain/services/live_quote/live_quote_merge.dart';
import 'package:daredevil/presentation/providers/live_quote_provider.dart';
import 'package:daredevil/presentation/widgets/live_quote_status.dart';

/// 頁首狀態與卡片例外標示(2026-10-06,spec §7「共通」)。
void main() {
  final morning = DateTime(2026, 10, 6, 10, 15);
  final afterClose = DateTime(2026, 10, 6, 14, 10);

  MergedPrice live(
    DateTime now, {
    bool closing = false,
    String time = '10:14:50',
  }) => LiveQuoteMerge.merge(
    official: OfficialPrice(date: DateTime(2026, 10, 5), close: 100),
    live: LiveQuoteEntry(
      symbol: 'A',
      date: DateTime(2026, 10, 6),
      price: 101,
      displaySource: LiveDisplaySource.trade,
      previousClose: 100,
      quoteTime: time,
      isClosingQuote: closing,
    ),
    now: now,
  );

  MergedPrice official(DateTime now) => LiveQuoteMerge.merge(
    official: OfficialPrice(date: DateTime(2026, 10, 6), close: 101),
    live: null,
    now: now,
  );

  LiveHeaderStatus? header(
    LiveQuoteState state,
    List<MergedPrice> merged, {
    String? intraday,
  }) => LiveQuoteStatusRule.header(
    state: state,
    merged: merged,
    intradayTime: intraday,
  );

  group('頁首(依序取第一個成立的)', () {
    test('🚨 限流優先於網路暫停,時間只到分', () {
      final s = header(
        LiveQuoteState(
          stalled: true,
          rateLimitedUntil: DateTime(2026, 10, 6, 10, 20, 31),
        ),
        [live(morning)],
      );
      expect(
        s,
        const LiveHeaderStatus(LiveHeaderKind.pausedRateLimit, '10:20'),
      );
    });

    test('網路暫停附最後更新時間;從沒回應過則不附時間', () {
      expect(
        header(
          LiveQuoteState(
            stalled: true,
            lastRespondedAt: DateTime(2026, 10, 6, 10, 13, 5),
          ),
          [live(morning)],
        ),
        const LiveHeaderStatus(LiveHeaderKind.pausedNetwork, '10:13:05'),
      );
      expect(
        header(const LiveQuoteState(stalled: true), const []),
        const LiveHeaderStatus(LiveHeaderKind.pausedNetwork),
      );
    });

    test('🚨 第一輪回應前不顯示「尚無報價」;最近一輪全不是今天才顯示', () {
      expect(header(const LiveQuoteState(), const []), isNull);
      expect(
        header(const LiveQuoteState(latestResponseHadToday: false), const []),
        const LiveHeaderStatus(LiveHeaderKind.noQuotesToday),
      );
    });

    test('盤中有卡片用即時 → 本輪報價時間', () {
      expect(
        header(const LiveQuoteState(latestResponseHadToday: true), [
          live(morning),
          official(morning),
        ], intraday: '10:14:58'),
        const LiveHeaderStatus(LiveHeaderKind.quoteTime, '10:14:58'),
      );
    });

    test('🚨 收盤後用即時的卡片全是收盤報價 → 今日收盤', () {
      expect(
        header(const LiveQuoteState(latestResponseHadToday: true), [
          live(afterClose, closing: true, time: '13:30:00'),
          official(afterClose),
        ]),
        const LiveHeaderStatus(LiveHeaderKind.closingPending),
      );
    });

    test('🚨 收盤後有一張不是收盤報價 → 最後報價,取最舊的時間,不寫今日收盤', () {
      expect(
        header(const LiveQuoteState(latestResponseHadToday: true), [
          live(afterClose, closing: true, time: '13:30:00'),
          live(afterClose, time: '13:29:40'),
          live(afterClose, time: '13:25:00'),
        ]),
        const LiveHeaderStatus(LiveHeaderKind.lastQuote, '13:25:00'),
      );
    });

    test('🚨 收盤後只有一張不是收盤報價 → 仍寫最後報價', () {
      expect(
        header(const LiveQuoteState(latestResponseHadToday: true), [
          live(afterClose, closing: true, time: '13:30:00'),
          live(afterClose, time: '13:29:40'),
        ]),
        const LiveHeaderStatus(LiveHeaderKind.lastQuote, '13:29:40'),
      );
    });

    test('🚨 收盤後只剩暫停交易的那檔還在抓(列被丟掉)→ 不寫「尚無報價」', () {
      // 收盤後逐檔抓:最近一輪只有那一檔,有回應但沒有可用的列;其他卡片
      // 都已顯示今天的收盤報價
      expect(
        header(const LiveQuoteState(latestResponseHadToday: false), [
          live(afterClose, closing: true, time: '13:30:00'),
        ]),
        const LiveHeaderStatus(LiveHeaderKind.closingPending),
      );
    });

    test('全部用正式資料 → 不顯示', () {
      expect(
        header(const LiveQuoteState(latestResponseHadToday: true), [
          official(afterClose),
        ]),
        isNull,
      );
    });
  });

  group('卡片例外標示', () {
    test('🚨 已有今天正式資料 → 不標(即使最近一輪批次失敗)', () {
      expect(
        LiveQuoteStatusRule.card(
          status: LiveSymbolStatus.batchFailed,
          merged: official(afterClose),
        ),
        isNull,
      );
    });

    test('批次失敗 → 報價暫停;有回應沒報價 → 無報價', () {
      expect(
        LiveQuoteStatusRule.card(
          status: LiveSymbolStatus.batchFailed,
          merged: live(morning),
        ),
        const LiveCardCaption(LiveCardCaptionKind.paused),
      );
      expect(
        LiveQuoteStatusRule.card(
          status: LiveSymbolStatus.noQuote,
          merged: live(morning),
        ),
        const LiveCardCaption(LiveCardCaptionKind.noQuote),
      );
    });

    test('收盤後不是收盤報價 → 最後報價 HH:MM:SS;盤中與收盤報價不標', () {
      expect(
        LiveQuoteStatusRule.card(
          status: LiveSymbolStatus.ok,
          merged: live(afterClose, time: '13:29:40'),
        ),
        const LiveCardCaption(LiveCardCaptionKind.lastQuote, '13:29:40'),
      );
      expect(
        LiveQuoteStatusRule.card(
          status: LiveSymbolStatus.ok,
          merged: live(morning),
        ),
        isNull,
      );
      expect(
        LiveQuoteStatusRule.card(
          status: LiveSymbolStatus.ok,
          merged: live(afterClose, closing: true, time: '13:30:00'),
        ),
        isNull,
      );
    });
  });

  test('文字走 i18n key(未載入翻譯時回 key)', () {
    expect(
      const LiveHeaderStatus(LiveHeaderKind.noQuotesToday).text(),
      'liveQuote.noQuotesToday',
    );
    expect(
      const LiveCardCaption(LiveCardCaptionKind.paused).text(),
      'liveQuote.cardPaused',
    );
  });
}
