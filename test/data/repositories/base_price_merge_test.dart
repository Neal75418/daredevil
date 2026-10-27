// 平盤價合併的純函式（除權息漲跌修正 spec 第 3 節「需要平盤價的列」）
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/data/remote/tpex_client.dart';
import 'package:daredevil/data/remote/twse_client.dart';
import 'package:daredevil/data/repositories/base_price_merge.dart';

void main() {
  final d = DateTime(2026, 9, 16);

  TwseDailyPrice twse(String code, {double? close, double? change}) =>
      TwseDailyPrice(
        date: d,
        code: code,
        name: code,
        open: close,
        high: close,
        low: close,
        close: close,
        volume: 1000,
        change: change,
      );

  TpexDailyPrice tpex(
    String code, {
    double? close,
    double? change,
    bool noComparison = false,
  }) => TpexDailyPrice(
    date: d,
    code: code,
    name: code,
    open: close,
    high: close,
    low: close,
    close: close,
    volume: 1000,
    change: change,
    noComparison: noComparison,
  );

  DailyPriceCompanion entry(String symbol, {double? close, double? change}) =>
      DailyPriceCompanion.insert(
        symbol: symbol,
        date: d,
        close: Value(close),
        priceChange: Value(change),
      );

  group('twseDailyNeedsBasePrice（STOCK_DAY_ALL：0 分不出不比價與平盤）', () {
    test('change 0 且收盤非 null 才需要', () {
      expect(
        twseDailyNeedsBasePrice([
          twse('9901', close: 10, change: 0),
          twse('9902', close: 10, change: 0.5),
          twse('9903', close: 10, change: null),
          twse('9904', close: null, change: 0),
        ]),
        {'9901'},
      );
    });
  });

  group('twseHistoricalNeedsBasePrice（MI_INDEX：X 已解析成 null）', () {
    test('change null 且收盤非 null 才需要；0 是真的平盤', () {
      expect(
        twseHistoricalNeedsBasePrice([
          twse('9901', close: 10, change: null),
          twse('9902', close: 10, change: 0),
          twse('9903', close: null, change: null),
        ]),
        {'9901'},
      );
    });
  });

  group('tpexNeedsBasePrice（文字標記）', () {
    test('noComparison 且收盤非 null 才需要', () {
      expect(
        tpexNeedsBasePrice([
          tpex('9911', close: 10, noComparison: true),
          tpex('9912', close: 10, change: null),
          tpex('9913', close: null, noComparison: true),
          tpex('9914', close: 10, change: 0.5),
        ]),
        {'9911'},
      );
    });
  });

  group('mergeBasePrices', () {
    test(
      '有基準設 basePrice；zeroToNull 時需要而沒基準的列 priceChange 改 null；不需要的列不動；清單缺該檔不設值（Review Focus 2）',
      () {
        final out = mergeBasePrices(
          [
            entry('9901', close: 10, change: 0),
            entry('9902', close: 10, change: 0),
            entry('9903', close: 10, change: 0.5),
          ],
          bases: {'9901': 9.5},
          needs: {'9901', '9902'},
          zeroToNull: true,
        );
        expect(out.map((e) => e.symbol.value), ['9901', '9902', '9903']);
        expect(out[0].basePrice.value, 9.5);
        expect(out[0].priceChange.value, 0, reason: '第 1 條在 DAO 才算');
        expect(out[1].basePrice.present, isFalse);
        expect(out[1].priceChange, const Value<double?>(null));
        expect(out[2].basePrice.present, isFalse);
        expect(out[2].priceChange.value, 0.5);
      },
    );

    test(
      'zeroToNull=false 時需要而沒基準的列 priceChange 不動（輸入 0 才分得出「不動」和「改 null」）',
      () {
        final out = mergeBasePrices(
          [entry('9901', close: 10, change: 0)],
          bases: const {},
          needs: {'9901'},
          zeroToNull: false,
        );
        expect(out.single.priceChange.value, 0);
        expect(out.single.basePrice.present, isFalse);
      },
    );

    test('bases 有、但不在 needs 的列也設 basePrice（一般日也存平盤價）', () {
      final out = mergeBasePrices(
        [entry('9901', close: 10, change: 0.5)],
        bases: {'9901': 9.5},
        needs: const {},
        zeroToNull: true,
      );
      expect(out.single.basePrice.value, 9.5);
      expect(out.single.priceChange.value, 0.5);
    });

    test('其餘欄位不動', () {
      final src = DailyPriceCompanion.insert(
        symbol: '9901',
        date: d,
        open: const Value(1),
        high: const Value(2),
        low: const Value(0.5),
        close: const Value(1.5),
        volume: const Value(100),
        priceChange: const Value(0),
      );
      final out = mergeBasePrices(
        [src],
        bases: {'9901': 1.0},
        needs: {'9901'},
        zeroToNull: true,
      ).single;
      expect(
        (
          out.open.value,
          out.high.value,
          out.low.value,
          out.close.value,
          out.volume.value,
        ),
        (1, 2, 0.5, 1.5, 100),
      );
    });
  });
}
