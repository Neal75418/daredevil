/// 市場日寫入前後的平盤價合併（除權息漲跌修正 spec 第 3 節）：純函式，
/// 由 `PriceRepository` 的三個市場日寫入函式呼叫。
///
/// 「需要平盤價的列」＝收盤非空，而且來源的漲跌分不出是不是不比價：
/// - 上市每日 `STOCK_DAY_ALL`：漲跌 0（不比價與真的平盤都給 `0.0000`）；
/// - 上市歷史 MI_INDEX：漲跌 null（方向欄 X 已解析成 null）；
/// - 上櫃兩個端點：文字標記（`noComparison`）。
/// 漲跌是非 0 數字的列，來源的漲跌就是官方值，不需要平盤價。
library;

import 'package:drift/drift.dart';

import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/data/models/tpex/tpex_daily_price.dart';
import 'package:daredevil/data/models/twse/twse_daily_price.dart';

/// `STOCK_DAY_ALL`：收盤非空且漲跌為 0 的列
Set<String> twseDailyNeedsBasePrice(Iterable<TwseDailyPrice> prices) => {
  for (final p in prices)
    if (p.close != null && p.change == 0) p.code,
};

/// MI_INDEX：收盤非空且漲跌為 null（X）的列
Set<String> twseHistoricalNeedsBasePrice(Iterable<TwseDailyPrice> prices) => {
  for (final p in prices)
    if (p.close != null && p.change == null) p.code,
};

/// 上櫃：收盤非空且有文字標記的列
Set<String> tpexNeedsBasePrice(Iterable<TpexDailyPrice> prices) => {
  for (final p in prices)
    if (p.close != null && p.noComparison) p.code,
};

/// 把平盤價帶進 companion：[bases] 有這檔 → 設 `basePrice`（一般日也存）；
/// [zeroToNull] 且 [needs] 有這檔、但沒有平盤價 → `priceChange` 改成明確的
/// null（`STOCK_DAY_ALL` 的 0 分不出不比價和真的平盤，不得暫存 0）。其餘欄位
/// 與順序不動。漲跌＝收盤 − 平盤價由 `insertPrices` 的第 1 條算。
List<DailyPriceCompanion> mergeBasePrices(
  List<DailyPriceCompanion> entries, {
  required Map<String, double> bases,
  required Set<String> needs,
  required bool zeroToNull,
}) => [
  for (final e in entries)
    switch (bases[e.symbol.value]) {
      final base? => e.copyWith(basePrice: Value(base)),
      null when zeroToNull && needs.contains(e.symbol.value) => e.copyWith(
        priceChange: const Value(null),
      ),
      null => e,
    },
];
