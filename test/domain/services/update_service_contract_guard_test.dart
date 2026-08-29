// UpdateService 的限流契約守門(2026-08-29 稽核 D1)
//
// coordinator 的每個同步步驟都要手寫同一組三件套:進入時
// `if (ctx.rateLimitedAbort) return;`、`on RateLimitException` 翻旗標、
// generic catch 記 recordError。抄了 13 次,而 `_UpdateContext` 自己的
// 註解記載:coordinator 曾因裸 catch 吞掉 rethrow,導致下游對已被限流的
// API 連打 222 檔 × 3 vendor。
//
// **為什麼是守門測試而不是抽 helper**:抽 `_guardedStep` 能消除抄寫,但
// 那是對一個有兩次事故在案、且錯誤語意(不 rethrow 以保留已抓資料、
// 旗標式中止)沒有完整測試釘住的檔案動大手術。守門測試拿到同樣的核心
// 價值——**第 14 個 syncer 忘了契約時當場轉紅**——而完全不碰產品碼。
// 真要重構時,這組測試也正好是它的安全網。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final source = File(
    'lib/domain/services/update_service.dart',
  ).readAsStringSync();

  /// 切出每個 `_sync*` 方法體(以下一個同層方法宣告為界)。
  Map<String, String> syncMethods() {
    final starts = [
      for (final m in RegExp(
        r'\n  (?:Future<[^>]*>|void) (_sync\w+)\(',
      ).allMatches(source))
        (m.start, m.group(1)!),
    ];
    return {
      for (var i = 0; i < starts.length; i++)
        starts[i].$2: source.substring(
          starts[i].$1,
          i + 1 < starts.length ? starts[i + 1].$1 : source.length,
        ),
    };
  }

  /// 不需要自己帶 rateLimitedAbort 的步驟——**純委派**,不做 IO,
  /// 中止判斷由它呼叫的子步驟各自負責。新增例外時要寫清楚理由。
  const pureDelegators = {
    // 只做「呼叫 _syncDailyPrices → 校正日期 → 呼叫 _syncHistoricalData」,
    // 兩個子步驟各自有完整契約。
    '_syncPricesAndHistory',
  };

  test('🚨 每個 _sync* 步驟都要有 rateLimitedAbort 中止判斷', () {
    final methods = syncMethods();
    expect(methods.length, greaterThanOrEqualTo(13), reason: '切割本身失效');

    final missing = [
      for (final e in methods.entries)
        if (!pureDelegators.contains(e.key) &&
            !e.value.contains('rateLimitedAbort'))
          e.key,
    ];
    expect(
      missing,
      isEmpty,
      reason:
          '沒有中止判斷的步驟會在 run 已被限流之後繼續打 API——'
          '2026-07 實測下游對已限流的 vendor 連打 222 檔 × 3。'
          '純委派步驟請加進 pureDelegators 並寫明理由',
    );
  });

  test('🚨 每個 on RateLimitException 區塊都要跳閘(翻旗標或 rethrow)', () {
    // 這是那次事故的**精確形狀**:catch 住了限流、記了 log,但沒讓上游
    // 知道要停——熔斷器接到訊號卻沒有動作。
    final offenders = <int>[];
    for (final m in RegExp(
      r'on RateLimitException(?: catch \(\w+\))? \{(.*?)\n(\s*)\}',
      dotAll: true,
    ).allMatches(source)) {
      final block = m.group(1)!;
      if (!block.contains('rateLimitedAbort = true') &&
          !block.contains('rethrow')) {
        offenders.add('\n'.allMatches(source.substring(0, m.start)).length + 1);
      }
    }
    expect(
      offenders,
      isEmpty,
      reason: 'update_service.dart 這些行號的 on RateLimitException 沒有跳閘',
    );
  });

  test('sanity:掃描器真的看得到契約字面(防假綠)', () {
    // 上面兩條都是「找不到違規就過」——掃描器若因重構/改名而失效,
    // 兩條會一起變成套套邏輯。這條確保字面確實存在於檔案裡。
    expect(source, contains('rateLimitedAbort'));
    expect(source, contains('on RateLimitException'));
    expect(source, contains('recordError'));
    expect(
      RegExp(r'on RateLimitException').allMatches(source).length,
      greaterThanOrEqualTo(10),
      reason: '契約點數量驟減 = 可能有人把它們拿掉了',
    );
  });
}
