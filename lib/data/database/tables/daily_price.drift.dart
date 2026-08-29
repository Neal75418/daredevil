// dart format width=80
// ignore_for_file: type=lint
import 'package:drift/drift.dart' as i0;
import 'package:daredevil/data/database/tables/daily_price.drift.dart' as i1;
import 'package:daredevil/data/database/tables/daily_price.dart' as i2;
import 'package:daredevil/data/database/tables/stock_master.drift.dart' as i3;
import 'package:drift/internal/modular.dart' as i4;

typedef $$DailyPriceTableCreateCompanionBuilder =
    i1.DailyPriceCompanion Function({
      required String symbol,
      required DateTime date,
      i0.Value<double?> open,
      i0.Value<double?> high,
      i0.Value<double?> low,
      i0.Value<double?> close,
      i0.Value<double?> volume,
      i0.Value<double?> priceChange,
      i0.Value<int> rowid,
    });
typedef $$DailyPriceTableUpdateCompanionBuilder =
    i1.DailyPriceCompanion Function({
      i0.Value<String> symbol,
      i0.Value<DateTime> date,
      i0.Value<double?> open,
      i0.Value<double?> high,
      i0.Value<double?> low,
      i0.Value<double?> close,
      i0.Value<double?> volume,
      i0.Value<double?> priceChange,
      i0.Value<int> rowid,
    });

final class $$DailyPriceTableReferences
    extends
        i0.BaseReferences<
          i0.GeneratedDatabase,
          i1.$DailyPriceTable,
          i1.DailyPriceEntry
        > {
  $$DailyPriceTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static i3.$StockMasterTable _symbolTable(i0.GeneratedDatabase db) =>
      i4.ReadDatabaseContainer(db)
          .resultSet<i3.$StockMasterTable>('stock_master')
          .createAlias(
            i0.$_aliasNameGenerator(
              i4.ReadDatabaseContainer(
                db,
              ).resultSet<i1.$DailyPriceTable>('daily_price').symbol,
              i4.ReadDatabaseContainer(
                db,
              ).resultSet<i3.$StockMasterTable>('stock_master').symbol,
            ),
          );

  i3.$$StockMasterTableProcessedTableManager get symbol {
    final $_column = $_itemColumn<String>('symbol')!;

    final manager = i3
        .$$StockMasterTableTableManager(
          $_db,
          i4.ReadDatabaseContainer(
            $_db,
          ).resultSet<i3.$StockMasterTable>('stock_master'),
        )
        .filter((f) => f.symbol.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_symbolTable($_db));
    if (item == null) return manager;
    return i0.ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$DailyPriceTableFilterComposer
    extends i0.Composer<i0.GeneratedDatabase, i1.$DailyPriceTable> {
  $$DailyPriceTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  i0.ColumnFilters<DateTime> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<double> get open => $composableBuilder(
    column: $table.open,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<double> get high => $composableBuilder(
    column: $table.high,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<double> get low => $composableBuilder(
    column: $table.low,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<double> get close => $composableBuilder(
    column: $table.close,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<double> get volume => $composableBuilder(
    column: $table.volume,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<double> get priceChange => $composableBuilder(
    column: $table.priceChange,
    builder: (column) => i0.ColumnFilters(column),
  );

  i3.$$StockMasterTableFilterComposer get symbol {
    final i3.$$StockMasterTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.symbol,
      referencedTable: i4.ReadDatabaseContainer(
        $db,
      ).resultSet<i3.$StockMasterTable>('stock_master'),
      getReferencedColumn: (t) => t.symbol,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => i3.$$StockMasterTableFilterComposer(
            $db: $db,
            $table: i4.ReadDatabaseContainer(
              $db,
            ).resultSet<i3.$StockMasterTable>('stock_master'),
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$DailyPriceTableOrderingComposer
    extends i0.Composer<i0.GeneratedDatabase, i1.$DailyPriceTable> {
  $$DailyPriceTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  i0.ColumnOrderings<DateTime> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<double> get open => $composableBuilder(
    column: $table.open,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<double> get high => $composableBuilder(
    column: $table.high,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<double> get low => $composableBuilder(
    column: $table.low,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<double> get close => $composableBuilder(
    column: $table.close,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<double> get volume => $composableBuilder(
    column: $table.volume,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<double> get priceChange => $composableBuilder(
    column: $table.priceChange,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i3.$$StockMasterTableOrderingComposer get symbol {
    final i3.$$StockMasterTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.symbol,
      referencedTable: i4.ReadDatabaseContainer(
        $db,
      ).resultSet<i3.$StockMasterTable>('stock_master'),
      getReferencedColumn: (t) => t.symbol,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => i3.$$StockMasterTableOrderingComposer(
            $db: $db,
            $table: i4.ReadDatabaseContainer(
              $db,
            ).resultSet<i3.$StockMasterTable>('stock_master'),
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$DailyPriceTableAnnotationComposer
    extends i0.Composer<i0.GeneratedDatabase, i1.$DailyPriceTable> {
  $$DailyPriceTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  i0.GeneratedColumn<DateTime> get date =>
      $composableBuilder(column: $table.date, builder: (column) => column);

  i0.GeneratedColumn<double> get open =>
      $composableBuilder(column: $table.open, builder: (column) => column);

  i0.GeneratedColumn<double> get high =>
      $composableBuilder(column: $table.high, builder: (column) => column);

  i0.GeneratedColumn<double> get low =>
      $composableBuilder(column: $table.low, builder: (column) => column);

  i0.GeneratedColumn<double> get close =>
      $composableBuilder(column: $table.close, builder: (column) => column);

  i0.GeneratedColumn<double> get volume =>
      $composableBuilder(column: $table.volume, builder: (column) => column);

  i0.GeneratedColumn<double> get priceChange => $composableBuilder(
    column: $table.priceChange,
    builder: (column) => column,
  );

  i3.$$StockMasterTableAnnotationComposer get symbol {
    final i3.$$StockMasterTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.symbol,
      referencedTable: i4.ReadDatabaseContainer(
        $db,
      ).resultSet<i3.$StockMasterTable>('stock_master'),
      getReferencedColumn: (t) => t.symbol,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => i3.$$StockMasterTableAnnotationComposer(
            $db: $db,
            $table: i4.ReadDatabaseContainer(
              $db,
            ).resultSet<i3.$StockMasterTable>('stock_master'),
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$DailyPriceTableTableManager
    extends
        i0.RootTableManager<
          i0.GeneratedDatabase,
          i1.$DailyPriceTable,
          i1.DailyPriceEntry,
          i1.$$DailyPriceTableFilterComposer,
          i1.$$DailyPriceTableOrderingComposer,
          i1.$$DailyPriceTableAnnotationComposer,
          $$DailyPriceTableCreateCompanionBuilder,
          $$DailyPriceTableUpdateCompanionBuilder,
          (i1.DailyPriceEntry, i1.$$DailyPriceTableReferences),
          i1.DailyPriceEntry,
          i0.PrefetchHooks Function({bool symbol})
        > {
  $$DailyPriceTableTableManager(
    i0.GeneratedDatabase db,
    i1.$DailyPriceTable table,
  ) : super(
        i0.TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              i1.$$DailyPriceTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              i1.$$DailyPriceTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              i1.$$DailyPriceTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                i0.Value<String> symbol = const i0.Value.absent(),
                i0.Value<DateTime> date = const i0.Value.absent(),
                i0.Value<double?> open = const i0.Value.absent(),
                i0.Value<double?> high = const i0.Value.absent(),
                i0.Value<double?> low = const i0.Value.absent(),
                i0.Value<double?> close = const i0.Value.absent(),
                i0.Value<double?> volume = const i0.Value.absent(),
                i0.Value<double?> priceChange = const i0.Value.absent(),
                i0.Value<int> rowid = const i0.Value.absent(),
              }) => i1.DailyPriceCompanion(
                symbol: symbol,
                date: date,
                open: open,
                high: high,
                low: low,
                close: close,
                volume: volume,
                priceChange: priceChange,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String symbol,
                required DateTime date,
                i0.Value<double?> open = const i0.Value.absent(),
                i0.Value<double?> high = const i0.Value.absent(),
                i0.Value<double?> low = const i0.Value.absent(),
                i0.Value<double?> close = const i0.Value.absent(),
                i0.Value<double?> volume = const i0.Value.absent(),
                i0.Value<double?> priceChange = const i0.Value.absent(),
                i0.Value<int> rowid = const i0.Value.absent(),
              }) => i1.DailyPriceCompanion.insert(
                symbol: symbol,
                date: date,
                open: open,
                high: high,
                low: low,
                close: close,
                volume: volume,
                priceChange: priceChange,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  i1.$$DailyPriceTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({symbol = false}) {
            return i0.PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends i0.TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (symbol) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.symbol,
                                referencedTable: i1.$$DailyPriceTableReferences
                                    ._symbolTable(db),
                                referencedColumn: i1.$$DailyPriceTableReferences
                                    ._symbolTable(db)
                                    .symbol,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$DailyPriceTableProcessedTableManager =
    i0.ProcessedTableManager<
      i0.GeneratedDatabase,
      i1.$DailyPriceTable,
      i1.DailyPriceEntry,
      i1.$$DailyPriceTableFilterComposer,
      i1.$$DailyPriceTableOrderingComposer,
      i1.$$DailyPriceTableAnnotationComposer,
      $$DailyPriceTableCreateCompanionBuilder,
      $$DailyPriceTableUpdateCompanionBuilder,
      (i1.DailyPriceEntry, i1.$$DailyPriceTableReferences),
      i1.DailyPriceEntry,
      i0.PrefetchHooks Function({bool symbol})
    >;
i0.Index get idxDailyPriceDateSymbol => i0.Index(
  'idx_daily_price_date_symbol',
  'CREATE INDEX idx_daily_price_date_symbol ON daily_price (date, symbol)',
);

class $DailyPriceTable extends i2.DailyPrice
    with i0.TableInfo<$DailyPriceTable, i1.DailyPriceEntry> {
  @override
  final i0.GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DailyPriceTable(this.attachedDatabase, [this._alias]);
  static const i0.VerificationMeta _symbolMeta = const i0.VerificationMeta(
    'symbol',
  );
  @override
  late final i0.GeneratedColumn<String> symbol = i0.GeneratedColumn<String>(
    'symbol',
    aliasedName,
    false,
    type: i0.DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: i0.GeneratedColumn.constraintIsAlways(
      'REFERENCES stock_master (symbol) ON DELETE CASCADE',
    ),
  );
  static const i0.VerificationMeta _dateMeta = const i0.VerificationMeta(
    'date',
  );
  @override
  late final i0.GeneratedColumn<DateTime> date = i0.GeneratedColumn<DateTime>(
    'date',
    aliasedName,
    false,
    type: i0.DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const i0.VerificationMeta _openMeta = const i0.VerificationMeta(
    'open',
  );
  @override
  late final i0.GeneratedColumn<double> open = i0.GeneratedColumn<double>(
    'open',
    aliasedName,
    true,
    type: i0.DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const i0.VerificationMeta _highMeta = const i0.VerificationMeta(
    'high',
  );
  @override
  late final i0.GeneratedColumn<double> high = i0.GeneratedColumn<double>(
    'high',
    aliasedName,
    true,
    type: i0.DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const i0.VerificationMeta _lowMeta = const i0.VerificationMeta('low');
  @override
  late final i0.GeneratedColumn<double> low = i0.GeneratedColumn<double>(
    'low',
    aliasedName,
    true,
    type: i0.DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const i0.VerificationMeta _closeMeta = const i0.VerificationMeta(
    'close',
  );
  @override
  late final i0.GeneratedColumn<double> close = i0.GeneratedColumn<double>(
    'close',
    aliasedName,
    true,
    type: i0.DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const i0.VerificationMeta _volumeMeta = const i0.VerificationMeta(
    'volume',
  );
  @override
  late final i0.GeneratedColumn<double> volume = i0.GeneratedColumn<double>(
    'volume',
    aliasedName,
    true,
    type: i0.DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const i0.VerificationMeta _priceChangeMeta = const i0.VerificationMeta(
    'priceChange',
  );
  @override
  late final i0.GeneratedColumn<double> priceChange =
      i0.GeneratedColumn<double>(
        'price_change',
        aliasedName,
        true,
        type: i0.DriftSqlType.double,
        requiredDuringInsert: false,
      );
  @override
  List<i0.GeneratedColumn> get $columns => [
    symbol,
    date,
    open,
    high,
    low,
    close,
    volume,
    priceChange,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'daily_price';
  @override
  i0.VerificationContext validateIntegrity(
    i0.Insertable<i1.DailyPriceEntry> instance, {
    bool isInserting = false,
  }) {
    final context = i0.VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('symbol')) {
      context.handle(
        _symbolMeta,
        symbol.isAcceptableOrUnknown(data['symbol']!, _symbolMeta),
      );
    } else if (isInserting) {
      context.missing(_symbolMeta);
    }
    if (data.containsKey('date')) {
      context.handle(
        _dateMeta,
        date.isAcceptableOrUnknown(data['date']!, _dateMeta),
      );
    } else if (isInserting) {
      context.missing(_dateMeta);
    }
    if (data.containsKey('open')) {
      context.handle(
        _openMeta,
        open.isAcceptableOrUnknown(data['open']!, _openMeta),
      );
    }
    if (data.containsKey('high')) {
      context.handle(
        _highMeta,
        high.isAcceptableOrUnknown(data['high']!, _highMeta),
      );
    }
    if (data.containsKey('low')) {
      context.handle(
        _lowMeta,
        low.isAcceptableOrUnknown(data['low']!, _lowMeta),
      );
    }
    if (data.containsKey('close')) {
      context.handle(
        _closeMeta,
        close.isAcceptableOrUnknown(data['close']!, _closeMeta),
      );
    }
    if (data.containsKey('volume')) {
      context.handle(
        _volumeMeta,
        volume.isAcceptableOrUnknown(data['volume']!, _volumeMeta),
      );
    }
    if (data.containsKey('price_change')) {
      context.handle(
        _priceChangeMeta,
        priceChange.isAcceptableOrUnknown(
          data['price_change']!,
          _priceChangeMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<i0.GeneratedColumn> get $primaryKey => {symbol, date};
  @override
  i1.DailyPriceEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return i1.DailyPriceEntry(
      symbol: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.string,
        data['${effectivePrefix}symbol'],
      )!,
      date: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.dateTime,
        data['${effectivePrefix}date'],
      )!,
      open: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.double,
        data['${effectivePrefix}open'],
      ),
      high: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.double,
        data['${effectivePrefix}high'],
      ),
      low: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.double,
        data['${effectivePrefix}low'],
      ),
      close: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.double,
        data['${effectivePrefix}close'],
      ),
      volume: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.double,
        data['${effectivePrefix}volume'],
      ),
      priceChange: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.double,
        data['${effectivePrefix}price_change'],
      ),
    );
  }

  @override
  $DailyPriceTable createAlias(String alias) {
    return $DailyPriceTable(attachedDatabase, alias);
  }
}

class DailyPriceEntry extends i0.DataClass
    implements i0.Insertable<i1.DailyPriceEntry> {
  /// 股票代碼
  final String symbol;

  /// 交易日期（本地午夜、ISO-8601 text 儲存）
  final DateTime date;

  /// 開盤價
  final double? open;

  /// 最高價
  final double? high;

  /// 最低價
  final double? low;

  /// 收盤價
  final double? close;

  /// 成交量（股）
  final double? volume;

  /// 漲跌價差（來自 TWSE/TPEX API，用於計算漲跌幅）
  final double? priceChange;
  const DailyPriceEntry({
    required this.symbol,
    required this.date,
    this.open,
    this.high,
    this.low,
    this.close,
    this.volume,
    this.priceChange,
  });
  @override
  Map<String, i0.Expression> toColumns(bool nullToAbsent) {
    final map = <String, i0.Expression>{};
    map['symbol'] = i0.Variable<String>(symbol);
    map['date'] = i0.Variable<DateTime>(date);
    if (!nullToAbsent || open != null) {
      map['open'] = i0.Variable<double>(open);
    }
    if (!nullToAbsent || high != null) {
      map['high'] = i0.Variable<double>(high);
    }
    if (!nullToAbsent || low != null) {
      map['low'] = i0.Variable<double>(low);
    }
    if (!nullToAbsent || close != null) {
      map['close'] = i0.Variable<double>(close);
    }
    if (!nullToAbsent || volume != null) {
      map['volume'] = i0.Variable<double>(volume);
    }
    if (!nullToAbsent || priceChange != null) {
      map['price_change'] = i0.Variable<double>(priceChange);
    }
    return map;
  }

  i1.DailyPriceCompanion toCompanion(bool nullToAbsent) {
    return i1.DailyPriceCompanion(
      symbol: i0.Value(symbol),
      date: i0.Value(date),
      open: open == null && nullToAbsent
          ? const i0.Value.absent()
          : i0.Value(open),
      high: high == null && nullToAbsent
          ? const i0.Value.absent()
          : i0.Value(high),
      low: low == null && nullToAbsent
          ? const i0.Value.absent()
          : i0.Value(low),
      close: close == null && nullToAbsent
          ? const i0.Value.absent()
          : i0.Value(close),
      volume: volume == null && nullToAbsent
          ? const i0.Value.absent()
          : i0.Value(volume),
      priceChange: priceChange == null && nullToAbsent
          ? const i0.Value.absent()
          : i0.Value(priceChange),
    );
  }

  factory DailyPriceEntry.fromJson(
    Map<String, dynamic> json, {
    i0.ValueSerializer? serializer,
  }) {
    serializer ??= i0.driftRuntimeOptions.defaultSerializer;
    return DailyPriceEntry(
      symbol: serializer.fromJson<String>(json['symbol']),
      date: serializer.fromJson<DateTime>(json['date']),
      open: serializer.fromJson<double?>(json['open']),
      high: serializer.fromJson<double?>(json['high']),
      low: serializer.fromJson<double?>(json['low']),
      close: serializer.fromJson<double?>(json['close']),
      volume: serializer.fromJson<double?>(json['volume']),
      priceChange: serializer.fromJson<double?>(json['priceChange']),
    );
  }
  @override
  Map<String, dynamic> toJson({i0.ValueSerializer? serializer}) {
    serializer ??= i0.driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'symbol': serializer.toJson<String>(symbol),
      'date': serializer.toJson<DateTime>(date),
      'open': serializer.toJson<double?>(open),
      'high': serializer.toJson<double?>(high),
      'low': serializer.toJson<double?>(low),
      'close': serializer.toJson<double?>(close),
      'volume': serializer.toJson<double?>(volume),
      'priceChange': serializer.toJson<double?>(priceChange),
    };
  }

  i1.DailyPriceEntry copyWith({
    String? symbol,
    DateTime? date,
    i0.Value<double?> open = const i0.Value.absent(),
    i0.Value<double?> high = const i0.Value.absent(),
    i0.Value<double?> low = const i0.Value.absent(),
    i0.Value<double?> close = const i0.Value.absent(),
    i0.Value<double?> volume = const i0.Value.absent(),
    i0.Value<double?> priceChange = const i0.Value.absent(),
  }) => i1.DailyPriceEntry(
    symbol: symbol ?? this.symbol,
    date: date ?? this.date,
    open: open.present ? open.value : this.open,
    high: high.present ? high.value : this.high,
    low: low.present ? low.value : this.low,
    close: close.present ? close.value : this.close,
    volume: volume.present ? volume.value : this.volume,
    priceChange: priceChange.present ? priceChange.value : this.priceChange,
  );
  DailyPriceEntry copyWithCompanion(i1.DailyPriceCompanion data) {
    return DailyPriceEntry(
      symbol: data.symbol.present ? data.symbol.value : this.symbol,
      date: data.date.present ? data.date.value : this.date,
      open: data.open.present ? data.open.value : this.open,
      high: data.high.present ? data.high.value : this.high,
      low: data.low.present ? data.low.value : this.low,
      close: data.close.present ? data.close.value : this.close,
      volume: data.volume.present ? data.volume.value : this.volume,
      priceChange: data.priceChange.present
          ? data.priceChange.value
          : this.priceChange,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DailyPriceEntry(')
          ..write('symbol: $symbol, ')
          ..write('date: $date, ')
          ..write('open: $open, ')
          ..write('high: $high, ')
          ..write('low: $low, ')
          ..write('close: $close, ')
          ..write('volume: $volume, ')
          ..write('priceChange: $priceChange')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(symbol, date, open, high, low, close, volume, priceChange);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is i1.DailyPriceEntry &&
          other.symbol == this.symbol &&
          other.date == this.date &&
          other.open == this.open &&
          other.high == this.high &&
          other.low == this.low &&
          other.close == this.close &&
          other.volume == this.volume &&
          other.priceChange == this.priceChange);
}

class DailyPriceCompanion extends i0.UpdateCompanion<i1.DailyPriceEntry> {
  final i0.Value<String> symbol;
  final i0.Value<DateTime> date;
  final i0.Value<double?> open;
  final i0.Value<double?> high;
  final i0.Value<double?> low;
  final i0.Value<double?> close;
  final i0.Value<double?> volume;
  final i0.Value<double?> priceChange;
  final i0.Value<int> rowid;
  const DailyPriceCompanion({
    this.symbol = const i0.Value.absent(),
    this.date = const i0.Value.absent(),
    this.open = const i0.Value.absent(),
    this.high = const i0.Value.absent(),
    this.low = const i0.Value.absent(),
    this.close = const i0.Value.absent(),
    this.volume = const i0.Value.absent(),
    this.priceChange = const i0.Value.absent(),
    this.rowid = const i0.Value.absent(),
  });
  DailyPriceCompanion.insert({
    required String symbol,
    required DateTime date,
    this.open = const i0.Value.absent(),
    this.high = const i0.Value.absent(),
    this.low = const i0.Value.absent(),
    this.close = const i0.Value.absent(),
    this.volume = const i0.Value.absent(),
    this.priceChange = const i0.Value.absent(),
    this.rowid = const i0.Value.absent(),
  }) : symbol = i0.Value(symbol),
       date = i0.Value(date);
  static i0.Insertable<i1.DailyPriceEntry> custom({
    i0.Expression<String>? symbol,
    i0.Expression<DateTime>? date,
    i0.Expression<double>? open,
    i0.Expression<double>? high,
    i0.Expression<double>? low,
    i0.Expression<double>? close,
    i0.Expression<double>? volume,
    i0.Expression<double>? priceChange,
    i0.Expression<int>? rowid,
  }) {
    return i0.RawValuesInsertable({
      if (symbol != null) 'symbol': symbol,
      if (date != null) 'date': date,
      if (open != null) 'open': open,
      if (high != null) 'high': high,
      if (low != null) 'low': low,
      if (close != null) 'close': close,
      if (volume != null) 'volume': volume,
      if (priceChange != null) 'price_change': priceChange,
      if (rowid != null) 'rowid': rowid,
    });
  }

  i1.DailyPriceCompanion copyWith({
    i0.Value<String>? symbol,
    i0.Value<DateTime>? date,
    i0.Value<double?>? open,
    i0.Value<double?>? high,
    i0.Value<double?>? low,
    i0.Value<double?>? close,
    i0.Value<double?>? volume,
    i0.Value<double?>? priceChange,
    i0.Value<int>? rowid,
  }) {
    return i1.DailyPriceCompanion(
      symbol: symbol ?? this.symbol,
      date: date ?? this.date,
      open: open ?? this.open,
      high: high ?? this.high,
      low: low ?? this.low,
      close: close ?? this.close,
      volume: volume ?? this.volume,
      priceChange: priceChange ?? this.priceChange,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, i0.Expression> toColumns(bool nullToAbsent) {
    final map = <String, i0.Expression>{};
    if (symbol.present) {
      map['symbol'] = i0.Variable<String>(symbol.value);
    }
    if (date.present) {
      map['date'] = i0.Variable<DateTime>(date.value);
    }
    if (open.present) {
      map['open'] = i0.Variable<double>(open.value);
    }
    if (high.present) {
      map['high'] = i0.Variable<double>(high.value);
    }
    if (low.present) {
      map['low'] = i0.Variable<double>(low.value);
    }
    if (close.present) {
      map['close'] = i0.Variable<double>(close.value);
    }
    if (volume.present) {
      map['volume'] = i0.Variable<double>(volume.value);
    }
    if (priceChange.present) {
      map['price_change'] = i0.Variable<double>(priceChange.value);
    }
    if (rowid.present) {
      map['rowid'] = i0.Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DailyPriceCompanion(')
          ..write('symbol: $symbol, ')
          ..write('date: $date, ')
          ..write('open: $open, ')
          ..write('high: $high, ')
          ..write('low: $low, ')
          ..write('close: $close, ')
          ..write('volume: $volume, ')
          ..write('priceChange: $priceChange, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}
