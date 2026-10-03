// 除權除息逐檔完整度（dividend_completeness.dart）：讀取端唯一定義
//
// 兩個市場都查；有效列表日＝max(列表日, 完成紀錄的月底)；未解決的列、
// 當時略過的代號、（需要時）缺價格的列都讓該檔該期間不完整。
import 'package:flutter_test/flutter_test.dart';

import 'package:daredevil/core/constants/market_codes.dart';
import 'package:daredevil/core/utils/calendar_month.dart';
import 'package:daredevil/data/database/app_database.dart';
import 'package:daredevil/domain/models/dividend_context.dart';
import 'package:daredevil/domain/services/dividend_completeness.dart';

final _now = DateTime(2026, 10, 2, 21, 30);
const _sep = CalendarMonth(2026, 9);
const _oct = CalendarMonth(2026, 10);

DividendListingEntry _listing(
  String market,
  CalendarMonth m,
  DateTime through,
) => DividendListingEntry(
  market: market,
  year: m.year,
  month: m.month,
  listedThrough: through,
);

DividendMonthLedgerEntry _ledger(
  String market,
  CalendarMonth m, {
  String skipped = '',
  DateTime? completedAt,
}) => DividendMonthLedgerEntry(
  market: market,
  year: m.year,
  month: m.month,
  completedAt: completedAt ?? DateTime(2026, 10, 1),
  listedRows: 1,
  knownRows: 1,
  skippedSymbols: skipped,
  pricesRecorded: true,
);

DividendUnresolvedEntry _unresolved(String market, String symbol, DateTime d) =>
    DividendUnresolvedEntry(
      market: market,
      symbol: symbol,
      exDate: d,
      reason: DividendUnresolvedReason.pendingDetail.code,
      recordedAt: _now,
    );

DividendDistributionEntry _row(
  DateTime exDate, {
  double? close = 100,
  double? reference = 95,
}) => DividendDistributionEntry(
  symbol: '2330',
  exDate: exDate,
  cashDividend: 5,
  stockSharesPerThousand: 0,
  closeBefore: close,
  referencePrice: reference,
);

/// 回補範圍（2021-01）至 [through] 兩市場都完整：過去月份用完成紀錄，
/// 本月用列表日
List<DividendMonthLedgerEntry> _ledgerThroughSep() => [
  for (final market in [MarketCode.twse, MarketCode.tpex])
    for (final m in CalendarMonth.descending(
      from: const CalendarMonth(2021, 1),
      to: _sep,
    ))
      _ledger(market, m),
];

DividendCompleteness _compute({
  List<DividendListingEntry> listings = const [],
  List<DividendMonthLedgerEntry>? ledger,
  List<DividendUnresolvedEntry> unresolved = const [],
  List<(String, DateTime)> missingPrices = const [],
}) => DividendCompleteness.compute(
  now: _now,
  listings: listings,
  ledger: ledger ?? _ledgerThroughSep(),
  unresolved: unresolved,
  missingPriceKeys: missingPrices,
);

void main() {
  final octListed = [
    _listing(MarketCode.twse, _oct, DateTime(2026, 10, 2)),
    _listing(MarketCode.tpex, _oct, DateTime(2026, 10, 2)),
  ];

  group('條件 1：兩個市場的有效列表日', () {
    test('完成紀錄＝列到月底；本月以列表日為準', () {
      final c = _compute(listings: octListed);
      expect(
        c.isComplete(
          '2330',
          DateTime(2025, 10, 2),
          DateTime(2026, 10, 2),
          requirePrices: false,
        ),
        isTrue,
      );
      expect(
        c.isComplete(
          '2330',
          DateTime(2025, 10, 2),
          DateTime(2026, 10, 3),
          requirePrices: false,
        ),
        isFalse,
      );
    });

    test('只有一個市場列到：不完整（轉板代號可能在另一個市場）', () {
      final c = _compute(listings: [octListed.first]);
      expect(
        c.isComplete(
          '2330',
          DateTime(2026, 10, 1),
          DateTime(2026, 10, 2),
          requirePrices: false,
        ),
        isFalse,
      );
    });

    test('完成紀錄是在該月結束前寫的：不算列到月底', () {
      final ledger = _ledgerThroughSep()
        ..removeWhere(
          (e) => e.market == MarketCode.twse && e.year == 2026 && e.month == 9,
        )
        ..add(
          _ledger(MarketCode.twse, _sep, completedAt: DateTime(2026, 9, 20)),
        );
      final c = _compute(ledger: ledger);
      expect(
        c.isComplete(
          '2330',
          DateTime(2026, 9, 1),
          DateTime(2026, 9, 30),
          requirePrices: false,
        ),
        isFalse,
      );
    });

    test('沒有完成紀錄但有列到月底的列表日：算列過（同步寫的上個月）', () {
      final ledger = _ledgerThroughSep()
        ..removeWhere(
          (e) => e.market == MarketCode.twse && e.year == 2026 && e.month == 9,
        );
      final c = _compute(
        ledger: ledger,
        listings: [_listing(MarketCode.twse, _sep, DateTime(2026, 9, 30))],
      );
      expect(
        c.isComplete(
          '2330',
          DateTime(2026, 9, 1),
          DateTime(2026, 9, 30),
          requirePrices: false,
        ),
        isTrue,
      );
    });

    test('回補範圍以前一律不完整（即使有完成紀錄）', () {
      const dec2020 = CalendarMonth(2020, 12);
      final c = _compute(
        listings: octListed,
        ledger: _ledgerThroughSep()
          ..add(_ledger(MarketCode.twse, dec2020))
          ..add(_ledger(MarketCode.tpex, dec2020)),
      );
      expect(
        c.isComplete(
          '2330',
          DateTime(2020, 12, 1),
          DateTime(2021, 1, 31),
          requirePrices: false,
        ),
        isFalse,
      );
    });
  });

  test('條件 2：該檔有未解決的列（任一市場）→ 期間內不完整，期間外不受影響', () {
    final c = _compute(
      listings: octListed,
      unresolved: [_unresolved(MarketCode.tpex, '2330', DateTime(2026, 9, 17))],
    );
    expect(
      c.isComplete(
        '2330',
        DateTime(2026, 9, 1),
        DateTime(2026, 9, 30),
        requirePrices: false,
      ),
      isFalse,
    );
    expect(
      c.isComplete(
        '2330',
        DateTime(2026, 10, 1),
        DateTime(2026, 10, 2),
        requirePrices: false,
      ),
      isTrue,
    );
    expect(
      c.isComplete(
        '2836',
        DateTime(2026, 9, 1),
        DateTime(2026, 9, 30),
        requirePrices: false,
      ),
      isTrue,
    );
  });

  test('條件 3：當時略過的代號 → 該月不完整', () {
    final ledger = _ledgerThroughSep()
      ..removeWhere(
        (e) => e.market == MarketCode.tpex && e.year == 2026 && e.month == 9,
      )
      ..add(_ledger(MarketCode.tpex, _sep, skipped: '00950B'));
    final c = _compute(ledger: ledger, listings: octListed);
    expect(
      c.isComplete(
        '00950B',
        DateTime(2026, 9, 1),
        DateTime(2026, 9, 30),
        requirePrices: false,
      ),
      isFalse,
    );
    expect(
      c.isComplete(
        '2330',
        DateTime(2026, 9, 1),
        DateTime(2026, 9, 30),
        requirePrices: false,
      ),
      isTrue,
    );
  });

  test('條件 4：需要價格時，缺前收盤或參考價的列 → 不完整；不需要時不影響', () {
    final c = _compute(
      listings: octListed,
      missingPrices: [('2330', DateTime(2026, 9, 16))],
    );
    expect(
      c.isComplete(
        '2330',
        DateTime(2026, 9, 1),
        DateTime(2026, 9, 30),
        requirePrices: true,
      ),
      isFalse,
    );
    expect(
      c.isComplete(
        '2330',
        DateTime(2026, 9, 1),
        DateTime(2026, 9, 30),
        requirePrices: false,
      ),
      isTrue,
    );
  });

  group('displayEnd：兩個市場自回補起點連續列過的最後一天，夾在今天以內', () {
    test('兩市場都列到 10/2 → 10/2', () {
      expect(_compute(listings: octListed).displayEnd, DateTime(2026, 10, 2));
    });

    test('本月尚未列表 → 上個月底', () {
      expect(_compute().displayEnd, DateTime(2026, 9, 30));
    });

    test('取兩市場較早者', () {
      final c = _compute(
        listings: [
          _listing(MarketCode.twse, _oct, DateTime(2026, 10, 2)),
          _listing(MarketCode.tpex, _oct, DateTime(2026, 10, 1)),
        ],
      );
      expect(c.displayEnd, DateTime(2026, 10, 1));
    });

    test('中間有一個月沒列完 → 停在那個月之前', () {
      final ledger = _ledgerThroughSep()
        ..removeWhere(
          (e) => e.market == MarketCode.twse && e.year == 2025 && e.month == 3,
        );
      expect(_compute(ledger: ledger).displayEnd, DateTime(2025, 2, 28));
    });

    test('某月只列到月中 → 停在那天（之後的月份有列表也不算連續）', () {
      final ledger = _ledgerThroughSep()
        ..removeWhere(
          (e) => e.market == MarketCode.twse && e.year == 2026 && e.month == 9,
        );
      final c = _compute(
        ledger: ledger,
        listings: [
          ...octListed,
          _listing(MarketCode.twse, _sep, DateTime(2026, 9, 20)),
        ],
      );
      expect(c.displayEnd, DateTime(2026, 9, 20));
    });

    test('列表日晚於今天（寫入當時時鐘比現在快）→ 今天', () {
      final c = _compute(
        listings: [
          _listing(MarketCode.twse, _oct, DateTime(2026, 10, 5)),
          _listing(MarketCode.tpex, _oct, DateTime(2026, 10, 5)),
        ],
      );
      expect(c.displayEnd, DateTime(2026, 10, 2));
    });

    test('任一市場連回補起點的月份都沒列 → null', () {
      final ledger = _ledgerThroughSep()
        ..removeWhere(
          (e) => e.market == MarketCode.tpex && e.year == 2021 && e.month == 1,
        );
      expect(_compute(ledger: ledger).displayEnd, isNull);
    });
  });

  group('priceContext：用到還原價的讀取端（52 週）', () {
    final from = DateTime(2025, 9, 1);
    final asOf = DateTime(2026, 10, 2);

    test('完整：帶窗口內、評分日以前（含）的事件；除權息日等於窗口首日或晚於評分日的不帶', () {
      final c = _compute(listings: octListed);

      final context = c.priceContext(
        '2330',
        from: from,
        asOf: asOf,
        rows: [
          _row(from),
          _row(DateTime(2026, 6, 11), close: 1100, reference: 1094),
          _row(asOf, close: 1500, reference: 1490),
          _row(DateTime(2026, 10, 5)),
        ],
      );

      expect(context, isA<DividendComplete>());
      expect(
        [
          for (final e in (context as DividendComplete).events)
            (e.exDate, e.closeBefore, e.referencePrice),
        ],
        [(DateTime(2026, 6, 11), 1100.0, 1094.0), (asOf, 1500.0, 1490.0)],
      );
    });

    test('🚨 本月列表日還沒到評分日（本月同步沒跑成的那一輪）→ incomplete', () {
      final c = _compute(
        listings: [
          _listing(MarketCode.twse, _oct, DateTime(2026, 10, 1)),
          _listing(MarketCode.tpex, _oct, DateTime(2026, 10, 2)),
        ],
      );

      expect(
        c.priceContext('2330', from: from, asOf: asOf, rows: const []),
        isA<DividendIncomplete>(),
      );
    });

    test('窗內有缺價格的列（完整度條件 4，requirePrices）→ incomplete', () {
      final c = _compute(
        listings: octListed,
        missingPrices: [('2330', DateTime(2026, 9, 16))],
      );

      expect(
        c.priceContext('2330', from: from, asOf: asOf, rows: const []),
        isA<DividendIncomplete>(),
      );
    });

    test('列在完整度讀取之後才變成缺價格或 ≤ 0（兩次讀取之間被改寫）→ incomplete，不拋例外', () {
      final c = _compute(listings: octListed);

      for (final row in [
        _row(DateTime(2026, 9, 16), close: null),
        _row(DateTime(2026, 9, 16), reference: null),
        _row(DateTime(2026, 9, 16), close: 0),
        _row(DateTime(2026, 9, 16), reference: -1),
      ]) {
        expect(
          c.priceContext('2330', from: from, asOf: asOf, rows: [row]),
          isA<DividendIncomplete>(),
        );
      }
    });
  });

  test('loadDividendCompleteness：列表日、未解決的列、缺價格的列都從 DB 讀進來', () async {
    final db = AppDatabase.forTesting();
    addTearDown(db.close);
    await db.upsertStocks([
      StockMasterCompanion.insert(symbol: '2330', name: '台積電', market: 'TWSE'),
      StockMasterCompanion.insert(symbol: '2836', name: '高雄銀', market: 'TWSE'),
    ]);
    await db.upsertDividendDistributions([
      DividendDistributionCompanion.insert(
        symbol: '2836',
        exDate: DateTime(2026, 10, 1),
        cashDividend: 0.15,
        stockSharesPerThousand: 45,
      ),
    ]);
    for (final market in [MarketCode.twse, MarketCode.tpex]) {
      await db.recordDividendListing(
        market: market,
        from: DateTime(2026, 10, 1),
        to: DateTime(2026, 10, 2),
        listedThrough: DateTime(2026, 10, 2),
        listedKnownKeys: market == MarketCode.twse
            ? {('2330', DateTime(2026, 10, 2)), ('2836', DateTime(2026, 10, 1))}
            : const {},
        notInMasterKeys: const {},
        recordedAt: _now,
      );
    }

    final c = await loadDividendCompleteness(db, now: _now);
    final oct1 = DateTime(2026, 10, 1);
    final oct2 = DateTime(2026, 10, 2);

    expect(
      c.isComplete('2836', oct1, oct2, requirePrices: false),
      isTrue,
      reason: '兩市場都列過、已在庫',
    );
    expect(
      c.isComplete('2330', oct1, oct2, requirePrices: false),
      isFalse,
      reason: '未解決的列',
    );
    expect(
      c.isComplete('2836', oct1, oct2, requirePrices: true),
      isFalse,
      reason: '在庫但缺前收盤與參考價',
    );
    expect(c.displayEnd, isNull, reason: '回補起點的月份沒列過');
  });
}
