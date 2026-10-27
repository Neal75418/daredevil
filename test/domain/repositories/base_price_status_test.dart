// 平盤價狀態（除權息漲跌修正 spec 第 3 節狀態表）：呼叫端只看兩個 getter
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/domain/repositories/price_repository.dart';

void main() {
  test('shouldRecordError 只在 withheld 且非限流', () {
    expect(
      const BasePriceStatus(
        fetch: BasePriceFetch.failed,
        missing: 3,
        withheld: true,
      ).shouldRecordError,
      isTrue,
    );
    expect(
      const BasePriceStatus(
        fetch: BasePriceFetch.rateLimited,
        missing: 3,
        withheld: true,
      ).shouldRecordError,
      isFalse,
      reason: '限流由呼叫端另設旗標',
    );
    expect(
      const BasePriceStatus(
        fetch: BasePriceFetch.fetched,
        missing: 3,
      ).shouldRecordError,
      isFalse,
      reason: '清單不全只記 warning',
    );
    expect(
      const BasePriceStatus(fetch: BasePriceFetch.failed).shouldRecordError,
      isFalse,
      reason: 'N=0 只記 log',
    );
  });

  test('rateLimited 只看 fetch', () {
    expect(
      const BasePriceStatus(fetch: BasePriceFetch.rateLimited).rateLimited,
      isTrue,
    );
    expect(BasePriceStatus.skipped.rateLimited, isFalse);
    expect(BasePriceStatus.notNeeded.rateLimited, isFalse);
  });

  test('常數：skipped／notNeeded 的 missing 為 0、不 withheld', () {
    for (final s in [BasePriceStatus.skipped, BasePriceStatus.notNeeded]) {
      expect(s.missing, 0);
      expect(s.withheld, isFalse);
      expect(s.shouldRecordError, isFalse);
    }
  });

  test('MarketSyncResult.basePrices 預設空 Map', () {
    const r = MarketSyncResult(count: 0, candidates: []);
    expect(r.basePrices, isEmpty);
  });

  test('MarketDayBackfillResult 帶列數與狀態', () {
    const r = MarketDayBackfillResult(
      rows: 3,
      basePrice: BasePriceStatus.notNeeded,
    );
    expect(r.rows, 3);
    expect(r.basePrice.fetch, BasePriceFetch.notNeeded);
  });
}
