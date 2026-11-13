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
    DateTime? now,
  }) => LiveQuoteStatusRule.header(
    state: state,
    merged: merged,
    intradayTime: intraday,
    now: now ?? morning,
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
        ], now: afterClose),
        const LiveHeaderStatus(LiveHeaderKind.closingPending),
      );
    });

    test('🚨 收盤後有一張不是收盤報價 → 最後報價,取最舊的時間,不寫今日收盤', () {
      expect(
        header(const LiveQuoteState(latestResponseHadToday: true), [
          live(afterClose, closing: true, time: '13:30:00'),
          live(afterClose, time: '13:29:40'),
          live(afterClose, time: '13:25:00'),
        ], now: afterClose),
        const LiveHeaderStatus(LiveHeaderKind.lastQuote, '13:25:00'),
      );
    });

    test('🚨 收盤後只有一張不是收盤報價 → 仍寫最後報價', () {
      expect(
        header(const LiveQuoteState(latestResponseHadToday: true), [
          live(afterClose, closing: true, time: '13:30:00'),
          live(afterClose, time: '13:29:40'),
        ], now: afterClose),
        const LiveHeaderStatus(LiveHeaderKind.lastQuote, '13:29:40'),
      );
    });

    test('🚨 收盤後只剩暫停交易的那檔還在抓(列被丟掉)→ 不寫「尚無報價」', () {
      // 收盤後逐檔抓:最近一輪只有那一檔,有回應但沒有可用的列;其他卡片
      // 都已顯示今天的收盤報價
      expect(
        header(const LiveQuoteState(latestResponseHadToday: false), [
          live(afterClose, closing: true, time: '13:30:00'),
        ], now: afterClose),
        const LiveHeaderStatus(LiveHeaderKind.closingPending),
      );
    });

    test('🚨 全部用今天的正式資料 → 不顯示(即使最近一輪「尚無報價」或中心暫停)', () {
      // 報價中心的旗標全 App 共用:例如別的畫面那檔暫停交易,最近一輪列被丟掉
      expect(
        header(const LiveQuoteState(latestResponseHadToday: false), [
          official(afterClose),
        ], now: afterClose),
        isNull,
      );
      expect(
        header(const LiveQuoteState(stalled: true), [
          official(afterClose),
        ], now: afterClose),
        isNull,
      );
    });

    test('🚨 有今天正式資料、另一檔暫停交易(列被丟掉)→ 不寫「尚無報價」(那檔卡片標無報價)', () {
      final halted = LiveQuoteMerge.merge(
        official: OfficialPrice(date: DateTime(2026, 10, 5), close: 100),
        live: null,
        now: afterClose,
      );
      expect(
        header(const LiveQuoteState(latestResponseHadToday: false), [
          official(afterClose),
          halted,
        ], now: afterClose),
        isNull,
      );
    });

    test('全部用正式資料 → 不顯示', () {
      expect(
        header(const LiveQuoteState(latestResponseHadToday: true), [
          official(afterClose),
        ], now: afterClose),
        isNull,
      );
    });
  });

  /// 自選與熱力圖頁首的「報價時間」:這一頁用即時報價的卡片裡,最新的那一列
  /// 時間。不用全 App 共用的值——證交所的快取每一組查詢各一份、各自落後,
  /// 別頁剛抓到的時間可能比這一頁的每一筆都新。
  group('這一頁最新的那一列時間(latestRowTime)', () {
    final now = DateTime(2026, 10, 6, 10, 30);
    MergedPrice card(String symbol, String? rowTime, {bool official = false}) =>
        LiveQuoteMerge.merge(
          official: OfficialPrice(
            date: official ? DateTime(2026, 10, 6) : DateTime(2026, 10, 5),
            close: 100,
          ),
          live: LiveQuoteEntry(
            symbol: symbol,
            date: DateTime(2026, 10, 6),
            price: 101,
            displaySource: LiveDisplaySource.lastTrade,
            previousClose: 100,
            // 顯示的是更早的那筆成交;要取的是列的時間
            quoteTime: '09:30:00',
            isClosingQuote: false,
            rowTime: rowTime,
          ),
          now: now,
        );

    test('🚨 取用即時報價的卡片裡最大的那一列時間(不是顯示用的成交時間)', () {
      expect(
        LiveQuoteStatusRule.latestRowTime([
          card('A', '10:28:40'),
          card('B', '10:29:05'),
          card('C', '10:27:00'),
        ]),
        '10:29:05',
      );
    });

    test('🚨 用今天正式資料的卡片、沒有列時間或無法解析的不算;都沒有 → null', () {
      expect(
        LiveQuoteStatusRule.latestRowTime([
          card('A', '10:28:40'),
          card('B', '10:29:59', official: true),
          card('C', null),
          card('D', '9:9'),
        ]),
        '10:28:40',
      );
      expect(
        LiveQuoteStatusRule.latestRowTime([card('C', null), card('D', '9:9')]),
        isNull,
      );
      expect(LiveQuoteStatusRule.latestRowTime(const []), isNull);
    });
  });

  /// 證交所的快取平常就會落後一兩分鐘;最近有收到、收到的卻是 3 分鐘以前
  /// 的快照,才說證交所的資料停住。延遲＝最近一次收到－畫面那筆的快照時刻。
  group('報價延遲', () {
    DateTime at(int h, int m, [int s = 0]) => DateTime(2026, 10, 6, h, m, s);
    final now = at(10, 30);

    /// 一張用即時報價的卡片;[snapshot] 是畫面那筆的快照時刻
    MergedPrice card(
      String symbol, {
      DateTime? snapshot,
      DateTime? mergedAt,
      String time = '10:25:00',
    }) => LiveQuoteMerge.merge(
      official: OfficialPrice(date: DateTime(2026, 10, 5), close: 100),
      live: LiveQuoteEntry(
        symbol: symbol,
        date: DateTime(2026, 10, 6),
        price: 101,
        displaySource: LiveDisplaySource.trade,
        previousClose: 100,
        quoteTime: time,
        isClosingQuote: false,
        snapshotAt: snapshot,
      ),
      now: mergedAt ?? now,
    );

    LiveQuoteState received(
      Map<String, DateTime> at, {
      bool stalled = false,
      DateTime? rateLimitedUntil,
    }) => LiveQuoteState(
      latestResponseHadToday: true,
      lastReceivedAt: at,
      stalled: stalled,
      rateLimitedUntil: rateLimitedUntil,
    );

    const onTime = LiveHeaderStatus(LiveHeaderKind.quoteTime, '10:29:40');
    LiveHeaderStatus? headerAt(
      LiveQuoteState state,
      List<MergedPrice> merged, {
      DateTime? at,
    }) => header(state, merged, intraday: '10:29:40', now: at ?? now);

    test('🚨 延遲恰好 3 分鐘不提示;多 1 秒 → 報價延遲,時刻是那張卡片的快照時刻', () {
      expect(
        headerAt(received({'A': at(10, 29)}), [
          card('A', snapshot: at(10, 26)),
        ]),
        onTime,
      );
      expect(
        headerAt(received({'A': at(10, 29)}), [
          card('A', snapshot: at(10, 25, 59)),
        ]),
        const LiveHeaderStatus(LiveHeaderKind.delayed, '10:25:59'),
      );
    });

    test('🚨 兩張卡片取延遲最大的那張(不是快照最舊的那張)', () {
      // A 的快照較舊、延遲 4 分 10 秒;B 延遲 5 分 20 秒
      expect(
        headerAt(received({'A': at(10, 28, 10), 'B': at(10, 29, 50)}), [
          card('A', snapshot: at(10, 24)),
          card('B', snapshot: at(10, 24, 30)),
        ]),
        const LiveHeaderStatus(LiveHeaderKind.delayed, '10:24:30'),
      );
      // 與卡片的順序無關
      expect(
        headerAt(received({'A': at(10, 28, 10), 'B': at(10, 29, 50)}), [
          card('B', snapshot: at(10, 24, 30)),
          card('A', snapshot: at(10, 24)),
        ]),
        const LiveHeaderStatus(LiveHeaderKind.delayed, '10:24:30'),
      );
    });

    test('🚨 最近一次收到恰好在 2 分鐘前仍算;再早 1 秒就不算(重新進入畫面)', () {
      expect(
        headerAt(received({'A': at(10, 28)}), [
          card('A', snapshot: at(10, 24)),
        ]),
        const LiveHeaderStatus(LiveHeaderKind.delayed, '10:24:00'),
      );
      expect(
        headerAt(received({'A': at(10, 27, 59)}), [
          card('A', snapshot: at(10, 23, 59)),
        ]),
        onTime,
      );
    });

    test('🚨 沒有快照時刻、沒有收到紀錄的卡片略過;全部略過 → 報價時間', () {
      expect(
        headerAt(received({'A': at(10, 29), 'B': at(10, 29)}), [
          card('A'),
          card('B', snapshot: at(10, 24)),
          card('C', snapshot: at(10, 20)),
        ]),
        const LiveHeaderStatus(LiveHeaderKind.delayed, '10:24:00'),
      );
      expect(
        headerAt(received({'A': at(10, 29)}), [
          card('A'),
          card('C', snapshot: at(10, 20)),
        ]),
        onTime,
      );
    });

    test('🚨 報價暫停優先:限流、網路都排在報價延遲前面', () {
      final cards = [card('A', snapshot: at(10, 24))];
      expect(
        headerAt(
          received({'A': at(10, 29)}, rateLimitedUntil: at(10, 34, 5)),
          cards,
        ),
        const LiveHeaderStatus(LiveHeaderKind.pausedRateLimit, '10:34'),
      );
      expect(
        headerAt(received({'A': at(10, 29)}, stalled: true), cards)?.kind,
        LiveHeaderKind.pausedNetwork,
      );
    });

    test('🚨 收盤後不判斷:照收盤後的規則', () {
      final closed = at(14, 0);
      expect(
        headerAt(received({'A': at(13, 59, 30)}), [
          card('A', snapshot: at(13, 55), mergedAt: closed, time: '13:24:58'),
        ], at: closed),
        const LiveHeaderStatus(LiveHeaderKind.lastQuote, '13:24:58'),
      );
    });

    test('只用今天正式資料的卡片不看:那一檔沒有即時報價可說延遲', () {
      expect(
        headerAt(received({'A': at(10, 29), 'B': at(10, 29)}), [
          card('A', snapshot: at(10, 28)),
          LiveQuoteMerge.merge(
            official: OfficialPrice(date: DateTime(2026, 10, 6), close: 101),
            live: LiveQuoteEntry(
              symbol: 'B',
              date: DateTime(2026, 10, 6),
              price: 101,
              displaySource: LiveDisplaySource.trade,
              previousClose: 100,
              quoteTime: '10:20:00',
              isClosingQuote: false,
              snapshotAt: at(10, 20),
            ),
            now: now,
          ),
        ]),
        onTime,
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

  test('報價延遲的文字走 i18n key', () {
    expect(
      const LiveHeaderStatus(LiveHeaderKind.delayed, '10:25:59').text(),
      'liveQuote.delayed',
    );
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
