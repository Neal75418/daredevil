import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/constants/live_quote_params.dart';
import 'package:daredevil/data/models/twse/intraday_quote.dart';
import 'package:daredevil/domain/services/live_quote/live_quote_schedule.dart';

/// 盤中即時報價的排程規則(2026-10-06,spec §2、參數表)。
void main() {
  Duration s(num seconds) => Duration(milliseconds: (seconds * 1000).round());

  group('phaseAt', () {
    for (final (label, t, phase) in [
      ('08:59:59 盤前', DateTime(2026, 10, 6, 8, 59, 59), MarketPhase.preOpen),
      ('09:00:00 開盤', DateTime(2026, 10, 6, 9), MarketPhase.open),
      ('13:29:59 仍是盤中', DateTime(2026, 10, 6, 13, 29, 59), MarketPhase.open),
      ('13:30:00 起收盤後', DateTime(2026, 10, 6, 13, 30), MarketPhase.afterClose),
      (
        '14:10 收盤後(沒有時間上限)',
        DateTime(2026, 10, 6, 14, 10),
        MarketPhase.afterClose,
      ),
      ('週六休市', DateTime(2026, 10, 3, 10), MarketPhase.closed),
      ('2026-10-09 國慶補假休市', DateTime(2026, 10, 9, 10), MarketPhase.closed),
    ]) {
      test(label, () => expect(LiveQuoteSchedule.phaseAt(t), phase));
    }
  });

  test('🚨 輪詢間隔:2 批以內 15 秒;批數 > 2 為批數 × 7.5 秒', () {
    for (final (batches, expected) in [
      (0, s(15)),
      (1, s(15)),
      (2, s(15)),
      (3, s(22.5)),
      (4, s(30)),
      (10, s(75)),
    ]) {
      expect(
        LiveQuoteSchedule.pollInterval(batches),
        expected,
        reason: '$batches 批',
      );
    }
  });

  test('🚨 暫停門檻:max(60 秒, 2 × 輪詢間隔);收盤後以 1 分鐘為間隔', () {
    expect(LiveQuoteSchedule.stallThreshold(1), s(60));
    expect(LiveQuoteSchedule.stallThreshold(4), s(60));
    expect(LiveQuoteSchedule.stallThreshold(5), s(75));
    expect(LiveQuoteSchedule.stallThreshold(10), s(150));
    expect(LiveQuoteSchedule.stallThreshold(1, afterClose: true), s(120));
    expect(LiveQuoteSchedule.stallThreshold(10, afterClose: true), s(150));
  });

  test('🚨 退避:暫停後每次失敗加倍,最長 2 分鐘', () {
    expect(LiveQuoteSchedule.backoffInterval(1, 0), s(15));
    expect(LiveQuoteSchedule.backoffInterval(1, 1), s(30));
    expect(LiveQuoteSchedule.backoffInterval(1, 2), s(60));
    expect(LiveQuoteSchedule.backoffInterval(1, 3), s(120));
    expect(LiveQuoteSchedule.backoffInterval(1, 9), s(120));
    expect(
      LiveQuoteSchedule.backoffInterval(10, 1),
      s(120),
      reason: '75×2 也封頂',
    );
  });

  test('🚨 CLI 避讓:每 5 分鐘整點後 10 秒內', () {
    for (final (t, expected) in [
      (DateTime(2026, 10, 6, 10, 5), true),
      (DateTime(2026, 10, 6, 10, 5, 9, 999), true),
      (DateTime(2026, 10, 6, 10, 5, 10), false),
      (DateTime(2026, 10, 6, 10, 4, 59), false),
      (DateTime(2026, 10, 6, 10, 0, 3), true),
      (DateTime(2026, 10, 6, 10, 1, 5), false),
      (DateTime(2026, 10, 6, 13, 25, 5), true),
    ]) {
      expect(LiveQuoteSchedule.inCliAvoidWindow(t), expected, reason: '$t');
    }
  });

  group('canSendRequest', () {
    final now = DateTime(2026, 10, 6, 10, 2);
    List<DateTime> ago(List<num> seconds) => [
      for (final x in seconds) now.subtract(s(x)),
    ];

    test('沒有紀錄 → 可以', () {
      expect(LiveQuoteSchedule.canSendRequest(const [], now), isTrue);
    });

    test('🚨 時鐘只到整秒:紀錄差 2 秒時實際可能只差 1 秒多 → 不行;差 3 秒才行', () {
      expect(LiveQuoteSchedule.canSendRequest(ago([2]), now), isFalse);
      expect(LiveQuoteSchedule.canSendRequest(ago([3]), now), isTrue);
    });

    test('🚨 紀錄上 61 秒內(60 秒加時鐘解析度)已有 8 個 → 不行', () {
      expect(
        LiveQuoteSchedule.canSendRequest(
          ago([60, 50, 40, 30, 20, 12, 8, 4]),
          now,
        ),
        isFalse,
        reason: '紀錄 60 秒前的,實際可能只差 59 秒多',
      );
      expect(
        LiveQuoteSchedule.canSendRequest(
          ago([61, 50, 40, 30, 20, 12, 8, 4]),
          now,
        ),
        isTrue,
      );
      expect(
        LiveQuoteSchedule.canSendRequest(ago([50, 40, 30, 20, 12, 8, 4]), now),
        isTrue,
      );
    });

    test(
      '🚨 送出時刻只記到整秒(TaiwanTime.now() 丟掉毫秒)時,實際時間仍保證相鄰 ≥ 2 秒、任何 60 秒 ≤ 8 個',
      () {
        // 每拍 1 秒、相位 .999;每三拍有一拍晚 2 毫秒,跨過整秒
        final start = DateTime(2026, 10, 6, 10, 2);
        final real = <DateTime>[];
        final recorded = <DateTime>[];
        for (var i = 0; i < 600; i++) {
          final t = start.add(
            Duration(milliseconds: i * 1000 + 999 + (i % 3 == 1 ? 2 : 0)),
          );
          final truncated = DateTime(
            t.year,
            t.month,
            t.day,
            t.hour,
            t.minute,
            t.second,
          );
          if (LiveQuoteSchedule.canSendRequest(recorded, truncated)) {
            real.add(t);
            recorded.add(truncated);
          }
        }
        expect(real.length, greaterThan(40));
        for (var i = 0; i < real.length; i++) {
          if (i > 0) {
            expect(
              real[i].difference(real[i - 1]),
              greaterThanOrEqualTo(LiveQuoteParams.minRequestGap),
              reason: '第 $i 個',
            );
          }
          final window = real
              .where(
                (t) =>
                    !t.isBefore(real[i]) &&
                    t.isBefore(real[i].add(const Duration(minutes: 1))),
              )
              .length;
          expect(
            window,
            lessThanOrEqualTo(LiveQuoteParams.maxRequestsPerMinute),
            reason: '從第 $i 個起的 60 秒',
          );
        }
      },
    );
  });

  group('isClosingQuote', () {
    final today = DateTime(2026, 10, 6);
    IntradayQuote q(Map<String, Object?> extra) => IntradayQuote.parseResponse({
      'rtcode': '0000',
      'msgArray': [
        {'c': 'A', 'y': '100.0000', 'd': '20261006', 't': '13:30:00', ...extra},
      ],
    })['A']!;

    test('🚨 今天、t ≥ 13:30:00、成交 → 收盤報價', () {
      expect(
        LiveQuoteSchedule.isClosingQuote(q({'z': '101.0000'}), today),
        isTrue,
      );
    });

    test('鎖住(z、pz 都是 -)也算', () {
      final locked = q({
        'z': '-',
        'pz': '-',
        'b': '0.0000_110.0000_',
        'a': '-',
        'u': '110.0000',
      });
      expect(locked.priceSource, QuotePriceSource.locked);
      expect(LiveQuoteSchedule.isClosingQuote(locked, today), isTrue);
    });

    test('🚨 延緩收盤(z=-、v>0、t<13:30:00)不算', () {
      final delayed = q({
        'z': '-',
        'pz': '-',
        'v': '1234',
        't': '13:29:40',
        'b': '99.5000_',
        'a': '100.5000_',
      });
      expect(LiveQuoteSchedule.isClosingQuote(delayed, today), isFalse);
    });

    test('t 早一秒、日期不是今天、試撮、五檔、t 格式不符、沒有日期 → 都不算', () {
      for (final extra in <Map<String, Object?>>[
        {'z': '101.0000', 't': '13:29:59'},
        {'z': '101.0000', 'd': '20261005'},
        {'z': '-', 'pz': '101.0000'},
        {'z': '-', 'b': '99.5000_', 'a': '100.5000_'},
        {'z': '101.0000', 't': '1330'},
        {'z': '101.0000', 'd': ''},
      ]) {
        expect(
          LiveQuoteSchedule.isClosingQuote(q(extra), today),
          isFalse,
          reason: '$extra',
        );
      }
    });
  });

  group('收盤後逐檔', () {
    final now = DateTime(2026, 10, 6, 14);

    test('🚨 拿到收盤報價 → 不再抓', () {
      expect(
        LiveQuoteSchedule.afterClosePending(hasClosingQuote: true, attempts: 0),
        isFalse,
      );
    });

    test('🚨 第 10 次「有回應但不是收盤報價」之後不再抓', () {
      expect(
        LiveQuoteSchedule.afterClosePending(
          hasClosingQuote: false,
          attempts: 9,
        ),
        isTrue,
      );
      expect(
        LiveQuoteSchedule.afterClosePending(
          hasClosingQuote: false,
          attempts: LiveQuoteParams.afterCloseMaxAttempts,
        ),
        isFalse,
      );
    });

    test('每檔 1 分鐘一次', () {
      bool due(DateTime? last) => LiveQuoteSchedule.afterCloseDue(
        hasClosingQuote: false,
        attempts: 3,
        lastAttemptAt: last,
        now: now,
      );
      expect(due(null), isTrue);
      expect(due(now.subtract(s(59))), isFalse);
      expect(due(now.subtract(s(60))), isTrue);
    });

    test('已停的不會因為過了 1 分鐘又變成該抓', () {
      expect(
        LiveQuoteSchedule.afterCloseDue(
          hasClosingQuote: true,
          attempts: 0,
          lastAttemptAt: null,
          now: now,
        ),
        isFalse,
      );
    });
  });

  test('secondsOfDay:HH:mm:ss 才解析', () {
    expect(LiveQuoteSchedule.secondsOfDay('13:30:00'), 48600);
    expect(LiveQuoteSchedule.secondsOfDay('9:05:00'), 32700);
    expect(LiveQuoteSchedule.secondsOfDay('1330'), isNull);
    expect(LiveQuoteSchedule.secondsOfDay(null), isNull);
  });
}
