// dart format width=80
// ignore_for_file: type=lint
import 'package:drift/drift.dart' as i0;
import 'package:daredevil/data/database/tables/daily_institutional.drift.dart'
    as i1;
import 'package:daredevil/data/database/tables/daily_institutional.dart' as i2;
import 'package:daredevil/data/database/tables/stock_master.drift.dart' as i3;
import 'package:drift/internal/modular.dart' as i4;

typedef $$DailyInstitutionalTableCreateCompanionBuilder =
    i1.DailyInstitutionalCompanion Function({
      required String symbol,
      required DateTime date,
      i0.Value<double?> foreignNet,
      i0.Value<double?> investmentTrustNet,
      i0.Value<double?> dealerNet,
      i0.Value<double?> dealerSelfNet,
      i0.Value<int> rowid,
    });
typedef $$DailyInstitutionalTableUpdateCompanionBuilder =
    i1.DailyInstitutionalCompanion Function({
      i0.Value<String> symbol,
      i0.Value<DateTime> date,
      i0.Value<double?> foreignNet,
      i0.Value<double?> investmentTrustNet,
      i0.Value<double?> dealerNet,
      i0.Value<double?> dealerSelfNet,
      i0.Value<int> rowid,
    });

final class $$DailyInstitutionalTableReferences
    extends
        i0.BaseReferences<
          i0.GeneratedDatabase,
          i1.$DailyInstitutionalTable,
          i1.DailyInstitutionalEntry
        > {
  $$DailyInstitutionalTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static i3.$StockMasterTable _symbolTable(i0.GeneratedDatabase db) =>
      i4.ReadDatabaseContainer(db)
          .resultSet<i3.$StockMasterTable>('stock_master')
          .createAlias(
            i0.$_aliasNameGenerator(
              i4.ReadDatabaseContainer(db)
                  .resultSet<i1.$DailyInstitutionalTable>('daily_institutional')
                  .symbol,
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

class $$DailyInstitutionalTableFilterComposer
    extends i0.Composer<i0.GeneratedDatabase, i1.$DailyInstitutionalTable> {
  $$DailyInstitutionalTableFilterComposer({
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

  i0.ColumnFilters<double> get foreignNet => $composableBuilder(
    column: $table.foreignNet,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<double> get investmentTrustNet => $composableBuilder(
    column: $table.investmentTrustNet,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<double> get dealerNet => $composableBuilder(
    column: $table.dealerNet,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<double> get dealerSelfNet => $composableBuilder(
    column: $table.dealerSelfNet,
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

class $$DailyInstitutionalTableOrderingComposer
    extends i0.Composer<i0.GeneratedDatabase, i1.$DailyInstitutionalTable> {
  $$DailyInstitutionalTableOrderingComposer({
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

  i0.ColumnOrderings<double> get foreignNet => $composableBuilder(
    column: $table.foreignNet,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<double> get investmentTrustNet => $composableBuilder(
    column: $table.investmentTrustNet,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<double> get dealerNet => $composableBuilder(
    column: $table.dealerNet,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<double> get dealerSelfNet => $composableBuilder(
    column: $table.dealerSelfNet,
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

class $$DailyInstitutionalTableAnnotationComposer
    extends i0.Composer<i0.GeneratedDatabase, i1.$DailyInstitutionalTable> {
  $$DailyInstitutionalTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  i0.GeneratedColumn<DateTime> get date =>
      $composableBuilder(column: $table.date, builder: (column) => column);

  i0.GeneratedColumn<double> get foreignNet => $composableBuilder(
    column: $table.foreignNet,
    builder: (column) => column,
  );

  i0.GeneratedColumn<double> get investmentTrustNet => $composableBuilder(
    column: $table.investmentTrustNet,
    builder: (column) => column,
  );

  i0.GeneratedColumn<double> get dealerNet =>
      $composableBuilder(column: $table.dealerNet, builder: (column) => column);

  i0.GeneratedColumn<double> get dealerSelfNet => $composableBuilder(
    column: $table.dealerSelfNet,
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

class $$DailyInstitutionalTableTableManager
    extends
        i0.RootTableManager<
          i0.GeneratedDatabase,
          i1.$DailyInstitutionalTable,
          i1.DailyInstitutionalEntry,
          i1.$$DailyInstitutionalTableFilterComposer,
          i1.$$DailyInstitutionalTableOrderingComposer,
          i1.$$DailyInstitutionalTableAnnotationComposer,
          $$DailyInstitutionalTableCreateCompanionBuilder,
          $$DailyInstitutionalTableUpdateCompanionBuilder,
          (i1.DailyInstitutionalEntry, i1.$$DailyInstitutionalTableReferences),
          i1.DailyInstitutionalEntry,
          i0.PrefetchHooks Function({bool symbol})
        > {
  $$DailyInstitutionalTableTableManager(
    i0.GeneratedDatabase db,
    i1.$DailyInstitutionalTable table,
  ) : super(
        i0.TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () => i1
              .$$DailyInstitutionalTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              i1.$$DailyInstitutionalTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              i1.$$DailyInstitutionalTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                i0.Value<String> symbol = const i0.Value.absent(),
                i0.Value<DateTime> date = const i0.Value.absent(),
                i0.Value<double?> foreignNet = const i0.Value.absent(),
                i0.Value<double?> investmentTrustNet = const i0.Value.absent(),
                i0.Value<double?> dealerNet = const i0.Value.absent(),
                i0.Value<double?> dealerSelfNet = const i0.Value.absent(),
                i0.Value<int> rowid = const i0.Value.absent(),
              }) => i1.DailyInstitutionalCompanion(
                symbol: symbol,
                date: date,
                foreignNet: foreignNet,
                investmentTrustNet: investmentTrustNet,
                dealerNet: dealerNet,
                dealerSelfNet: dealerSelfNet,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String symbol,
                required DateTime date,
                i0.Value<double?> foreignNet = const i0.Value.absent(),
                i0.Value<double?> investmentTrustNet = const i0.Value.absent(),
                i0.Value<double?> dealerNet = const i0.Value.absent(),
                i0.Value<double?> dealerSelfNet = const i0.Value.absent(),
                i0.Value<int> rowid = const i0.Value.absent(),
              }) => i1.DailyInstitutionalCompanion.insert(
                symbol: symbol,
                date: date,
                foreignNet: foreignNet,
                investmentTrustNet: investmentTrustNet,
                dealerNet: dealerNet,
                dealerSelfNet: dealerSelfNet,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  i1.$$DailyInstitutionalTableReferences(db, table, e),
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
                                referencedTable: i1
                                    .$$DailyInstitutionalTableReferences
                                    ._symbolTable(db),
                                referencedColumn: i1
                                    .$$DailyInstitutionalTableReferences
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

typedef $$DailyInstitutionalTableProcessedTableManager =
    i0.ProcessedTableManager<
      i0.GeneratedDatabase,
      i1.$DailyInstitutionalTable,
      i1.DailyInstitutionalEntry,
      i1.$$DailyInstitutionalTableFilterComposer,
      i1.$$DailyInstitutionalTableOrderingComposer,
      i1.$$DailyInstitutionalTableAnnotationComposer,
      $$DailyInstitutionalTableCreateCompanionBuilder,
      $$DailyInstitutionalTableUpdateCompanionBuilder,
      (i1.DailyInstitutionalEntry, i1.$$DailyInstitutionalTableReferences),
      i1.DailyInstitutionalEntry,
      i0.PrefetchHooks Function({bool symbol})
    >;
i0.Index get idxDailyInstitutionalDate => i0.Index(
  'idx_daily_institutional_date',
  'CREATE INDEX idx_daily_institutional_date ON daily_institutional (date)',
);

class $DailyInstitutionalTable extends i2.DailyInstitutional
    with i0.TableInfo<$DailyInstitutionalTable, i1.DailyInstitutionalEntry> {
  @override
  final i0.GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DailyInstitutionalTable(this.attachedDatabase, [this._alias]);
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
  static const i0.VerificationMeta _foreignNetMeta = const i0.VerificationMeta(
    'foreignNet',
  );
  @override
  late final i0.GeneratedColumn<double> foreignNet = i0.GeneratedColumn<double>(
    'foreign_net',
    aliasedName,
    true,
    type: i0.DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const i0.VerificationMeta _investmentTrustNetMeta =
      const i0.VerificationMeta('investmentTrustNet');
  @override
  late final i0.GeneratedColumn<double> investmentTrustNet =
      i0.GeneratedColumn<double>(
        'investment_trust_net',
        aliasedName,
        true,
        type: i0.DriftSqlType.double,
        requiredDuringInsert: false,
      );
  static const i0.VerificationMeta _dealerNetMeta = const i0.VerificationMeta(
    'dealerNet',
  );
  @override
  late final i0.GeneratedColumn<double> dealerNet = i0.GeneratedColumn<double>(
    'dealer_net',
    aliasedName,
    true,
    type: i0.DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const i0.VerificationMeta _dealerSelfNetMeta =
      const i0.VerificationMeta('dealerSelfNet');
  @override
  late final i0.GeneratedColumn<double> dealerSelfNet =
      i0.GeneratedColumn<double>(
        'dealer_self_net',
        aliasedName,
        true,
        type: i0.DriftSqlType.double,
        requiredDuringInsert: false,
      );
  @override
  List<i0.GeneratedColumn> get $columns => [
    symbol,
    date,
    foreignNet,
    investmentTrustNet,
    dealerNet,
    dealerSelfNet,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'daily_institutional';
  @override
  i0.VerificationContext validateIntegrity(
    i0.Insertable<i1.DailyInstitutionalEntry> instance, {
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
    if (data.containsKey('foreign_net')) {
      context.handle(
        _foreignNetMeta,
        foreignNet.isAcceptableOrUnknown(data['foreign_net']!, _foreignNetMeta),
      );
    }
    if (data.containsKey('investment_trust_net')) {
      context.handle(
        _investmentTrustNetMeta,
        investmentTrustNet.isAcceptableOrUnknown(
          data['investment_trust_net']!,
          _investmentTrustNetMeta,
        ),
      );
    }
    if (data.containsKey('dealer_net')) {
      context.handle(
        _dealerNetMeta,
        dealerNet.isAcceptableOrUnknown(data['dealer_net']!, _dealerNetMeta),
      );
    }
    if (data.containsKey('dealer_self_net')) {
      context.handle(
        _dealerSelfNetMeta,
        dealerSelfNet.isAcceptableOrUnknown(
          data['dealer_self_net']!,
          _dealerSelfNetMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<i0.GeneratedColumn> get $primaryKey => {symbol, date};
  @override
  i1.DailyInstitutionalEntry map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return i1.DailyInstitutionalEntry(
      symbol: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.string,
        data['${effectivePrefix}symbol'],
      )!,
      date: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.dateTime,
        data['${effectivePrefix}date'],
      )!,
      foreignNet: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.double,
        data['${effectivePrefix}foreign_net'],
      ),
      investmentTrustNet: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.double,
        data['${effectivePrefix}investment_trust_net'],
      ),
      dealerNet: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.double,
        data['${effectivePrefix}dealer_net'],
      ),
      dealerSelfNet: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.double,
        data['${effectivePrefix}dealer_self_net'],
      ),
    );
  }

  @override
  $DailyInstitutionalTable createAlias(String alias) {
    return $DailyInstitutionalTable(attachedDatabase, alias);
  }
}

class DailyInstitutionalEntry extends i0.DataClass
    implements i0.Insertable<i1.DailyInstitutionalEntry> {
  /// 股票代碼
  final String symbol;

  /// 交易日期
  final DateTime date;

  /// 外資買賣超（股——TWSE/TPEx API 回傳股數直接儲存）
  final double? foreignNet;

  /// 投信買賣超（股）
  final double? investmentTrustNet;

  /// 自營商買賣超（股）— 自行買賣 + 避險合計（對外口徑，媒體/TWSE 報的就是此值）
  final double? dealerNet;

  /// 自營商「自行買賣」買賣超（股，不含避險）
  ///
  /// FinMind 的 Dealer_self。自營避險部位結構性偏買，會使合計 [dealerNet]
  /// 連續買超天數失真（恆正）；此欄供「自行買賣」streak 等需要真實自營主動
  /// 方向的場景使用。
  ///
  /// ⚠️ 此欄以 idempotent ALTER 路徑（見 AppDatabase beforeOpen 的
  /// `_ensureDealerSelfNetColumn`）加入既有 DB，刻意「不」bump schema
  /// fingerprint，避免 wipe 掉使用者累積的 derived 資料。
  final double? dealerSelfNet;
  const DailyInstitutionalEntry({
    required this.symbol,
    required this.date,
    this.foreignNet,
    this.investmentTrustNet,
    this.dealerNet,
    this.dealerSelfNet,
  });
  @override
  Map<String, i0.Expression> toColumns(bool nullToAbsent) {
    final map = <String, i0.Expression>{};
    map['symbol'] = i0.Variable<String>(symbol);
    map['date'] = i0.Variable<DateTime>(date);
    if (!nullToAbsent || foreignNet != null) {
      map['foreign_net'] = i0.Variable<double>(foreignNet);
    }
    if (!nullToAbsent || investmentTrustNet != null) {
      map['investment_trust_net'] = i0.Variable<double>(investmentTrustNet);
    }
    if (!nullToAbsent || dealerNet != null) {
      map['dealer_net'] = i0.Variable<double>(dealerNet);
    }
    if (!nullToAbsent || dealerSelfNet != null) {
      map['dealer_self_net'] = i0.Variable<double>(dealerSelfNet);
    }
    return map;
  }

  i1.DailyInstitutionalCompanion toCompanion(bool nullToAbsent) {
    return i1.DailyInstitutionalCompanion(
      symbol: i0.Value(symbol),
      date: i0.Value(date),
      foreignNet: foreignNet == null && nullToAbsent
          ? const i0.Value.absent()
          : i0.Value(foreignNet),
      investmentTrustNet: investmentTrustNet == null && nullToAbsent
          ? const i0.Value.absent()
          : i0.Value(investmentTrustNet),
      dealerNet: dealerNet == null && nullToAbsent
          ? const i0.Value.absent()
          : i0.Value(dealerNet),
      dealerSelfNet: dealerSelfNet == null && nullToAbsent
          ? const i0.Value.absent()
          : i0.Value(dealerSelfNet),
    );
  }

  factory DailyInstitutionalEntry.fromJson(
    Map<String, dynamic> json, {
    i0.ValueSerializer? serializer,
  }) {
    serializer ??= i0.driftRuntimeOptions.defaultSerializer;
    return DailyInstitutionalEntry(
      symbol: serializer.fromJson<String>(json['symbol']),
      date: serializer.fromJson<DateTime>(json['date']),
      foreignNet: serializer.fromJson<double?>(json['foreignNet']),
      investmentTrustNet: serializer.fromJson<double?>(
        json['investmentTrustNet'],
      ),
      dealerNet: serializer.fromJson<double?>(json['dealerNet']),
      dealerSelfNet: serializer.fromJson<double?>(json['dealerSelfNet']),
    );
  }
  @override
  Map<String, dynamic> toJson({i0.ValueSerializer? serializer}) {
    serializer ??= i0.driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'symbol': serializer.toJson<String>(symbol),
      'date': serializer.toJson<DateTime>(date),
      'foreignNet': serializer.toJson<double?>(foreignNet),
      'investmentTrustNet': serializer.toJson<double?>(investmentTrustNet),
      'dealerNet': serializer.toJson<double?>(dealerNet),
      'dealerSelfNet': serializer.toJson<double?>(dealerSelfNet),
    };
  }

  i1.DailyInstitutionalEntry copyWith({
    String? symbol,
    DateTime? date,
    i0.Value<double?> foreignNet = const i0.Value.absent(),
    i0.Value<double?> investmentTrustNet = const i0.Value.absent(),
    i0.Value<double?> dealerNet = const i0.Value.absent(),
    i0.Value<double?> dealerSelfNet = const i0.Value.absent(),
  }) => i1.DailyInstitutionalEntry(
    symbol: symbol ?? this.symbol,
    date: date ?? this.date,
    foreignNet: foreignNet.present ? foreignNet.value : this.foreignNet,
    investmentTrustNet: investmentTrustNet.present
        ? investmentTrustNet.value
        : this.investmentTrustNet,
    dealerNet: dealerNet.present ? dealerNet.value : this.dealerNet,
    dealerSelfNet: dealerSelfNet.present
        ? dealerSelfNet.value
        : this.dealerSelfNet,
  );
  DailyInstitutionalEntry copyWithCompanion(
    i1.DailyInstitutionalCompanion data,
  ) {
    return DailyInstitutionalEntry(
      symbol: data.symbol.present ? data.symbol.value : this.symbol,
      date: data.date.present ? data.date.value : this.date,
      foreignNet: data.foreignNet.present
          ? data.foreignNet.value
          : this.foreignNet,
      investmentTrustNet: data.investmentTrustNet.present
          ? data.investmentTrustNet.value
          : this.investmentTrustNet,
      dealerNet: data.dealerNet.present ? data.dealerNet.value : this.dealerNet,
      dealerSelfNet: data.dealerSelfNet.present
          ? data.dealerSelfNet.value
          : this.dealerSelfNet,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DailyInstitutionalEntry(')
          ..write('symbol: $symbol, ')
          ..write('date: $date, ')
          ..write('foreignNet: $foreignNet, ')
          ..write('investmentTrustNet: $investmentTrustNet, ')
          ..write('dealerNet: $dealerNet, ')
          ..write('dealerSelfNet: $dealerSelfNet')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    symbol,
    date,
    foreignNet,
    investmentTrustNet,
    dealerNet,
    dealerSelfNet,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is i1.DailyInstitutionalEntry &&
          other.symbol == this.symbol &&
          other.date == this.date &&
          other.foreignNet == this.foreignNet &&
          other.investmentTrustNet == this.investmentTrustNet &&
          other.dealerNet == this.dealerNet &&
          other.dealerSelfNet == this.dealerSelfNet);
}

class DailyInstitutionalCompanion
    extends i0.UpdateCompanion<i1.DailyInstitutionalEntry> {
  final i0.Value<String> symbol;
  final i0.Value<DateTime> date;
  final i0.Value<double?> foreignNet;
  final i0.Value<double?> investmentTrustNet;
  final i0.Value<double?> dealerNet;
  final i0.Value<double?> dealerSelfNet;
  final i0.Value<int> rowid;
  const DailyInstitutionalCompanion({
    this.symbol = const i0.Value.absent(),
    this.date = const i0.Value.absent(),
    this.foreignNet = const i0.Value.absent(),
    this.investmentTrustNet = const i0.Value.absent(),
    this.dealerNet = const i0.Value.absent(),
    this.dealerSelfNet = const i0.Value.absent(),
    this.rowid = const i0.Value.absent(),
  });
  DailyInstitutionalCompanion.insert({
    required String symbol,
    required DateTime date,
    this.foreignNet = const i0.Value.absent(),
    this.investmentTrustNet = const i0.Value.absent(),
    this.dealerNet = const i0.Value.absent(),
    this.dealerSelfNet = const i0.Value.absent(),
    this.rowid = const i0.Value.absent(),
  }) : symbol = i0.Value(symbol),
       date = i0.Value(date);
  static i0.Insertable<i1.DailyInstitutionalEntry> custom({
    i0.Expression<String>? symbol,
    i0.Expression<DateTime>? date,
    i0.Expression<double>? foreignNet,
    i0.Expression<double>? investmentTrustNet,
    i0.Expression<double>? dealerNet,
    i0.Expression<double>? dealerSelfNet,
    i0.Expression<int>? rowid,
  }) {
    return i0.RawValuesInsertable({
      if (symbol != null) 'symbol': symbol,
      if (date != null) 'date': date,
      if (foreignNet != null) 'foreign_net': foreignNet,
      if (investmentTrustNet != null)
        'investment_trust_net': investmentTrustNet,
      if (dealerNet != null) 'dealer_net': dealerNet,
      if (dealerSelfNet != null) 'dealer_self_net': dealerSelfNet,
      if (rowid != null) 'rowid': rowid,
    });
  }

  i1.DailyInstitutionalCompanion copyWith({
    i0.Value<String>? symbol,
    i0.Value<DateTime>? date,
    i0.Value<double?>? foreignNet,
    i0.Value<double?>? investmentTrustNet,
    i0.Value<double?>? dealerNet,
    i0.Value<double?>? dealerSelfNet,
    i0.Value<int>? rowid,
  }) {
    return i1.DailyInstitutionalCompanion(
      symbol: symbol ?? this.symbol,
      date: date ?? this.date,
      foreignNet: foreignNet ?? this.foreignNet,
      investmentTrustNet: investmentTrustNet ?? this.investmentTrustNet,
      dealerNet: dealerNet ?? this.dealerNet,
      dealerSelfNet: dealerSelfNet ?? this.dealerSelfNet,
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
    if (foreignNet.present) {
      map['foreign_net'] = i0.Variable<double>(foreignNet.value);
    }
    if (investmentTrustNet.present) {
      map['investment_trust_net'] = i0.Variable<double>(
        investmentTrustNet.value,
      );
    }
    if (dealerNet.present) {
      map['dealer_net'] = i0.Variable<double>(dealerNet.value);
    }
    if (dealerSelfNet.present) {
      map['dealer_self_net'] = i0.Variable<double>(dealerSelfNet.value);
    }
    if (rowid.present) {
      map['rowid'] = i0.Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DailyInstitutionalCompanion(')
          ..write('symbol: $symbol, ')
          ..write('date: $date, ')
          ..write('foreignNet: $foreignNet, ')
          ..write('investmentTrustNet: $investmentTrustNet, ')
          ..write('dealerNet: $dealerNet, ')
          ..write('dealerSelfNet: $dealerSelfNet, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}
