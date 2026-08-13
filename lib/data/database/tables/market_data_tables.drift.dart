// dart format width=80
// ignore_for_file: type=lint
import 'package:drift/drift.dart' as i0;
import 'package:daredevil/data/database/tables/market_data_tables.drift.dart'
    as i1;
import 'package:daredevil/data/database/tables/market_data_tables.dart' as i2;
import 'package:drift/src/runtime/query_builder/query_builder.dart' as i3;
import 'package:daredevil/data/database/tables/stock_master.drift.dart' as i4;
import 'package:drift/internal/modular.dart' as i5;

typedef $$ShareholdingTableCreateCompanionBuilder =
    i1.ShareholdingCompanion Function({
      required String symbol,
      required DateTime date,
      i0.Value<double?> foreignRemainingShares,
      i0.Value<double?> foreignSharesRatio,
      i0.Value<double?> foreignUpperLimitRatio,
      i0.Value<double?> sharesIssued,
      i0.Value<int> rowid,
    });
typedef $$ShareholdingTableUpdateCompanionBuilder =
    i1.ShareholdingCompanion Function({
      i0.Value<String> symbol,
      i0.Value<DateTime> date,
      i0.Value<double?> foreignRemainingShares,
      i0.Value<double?> foreignSharesRatio,
      i0.Value<double?> foreignUpperLimitRatio,
      i0.Value<double?> sharesIssued,
      i0.Value<int> rowid,
    });

final class $$ShareholdingTableReferences
    extends
        i0.BaseReferences<
          i0.GeneratedDatabase,
          i1.$ShareholdingTable,
          i1.ShareholdingEntry
        > {
  $$ShareholdingTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static i4.$StockMasterTable _symbolTable(i0.GeneratedDatabase db) =>
      i5.ReadDatabaseContainer(db)
          .resultSet<i4.$StockMasterTable>('stock_master')
          .createAlias(
            i0.$_aliasNameGenerator(
              i5.ReadDatabaseContainer(
                db,
              ).resultSet<i1.$ShareholdingTable>('shareholding').symbol,
              i5.ReadDatabaseContainer(
                db,
              ).resultSet<i4.$StockMasterTable>('stock_master').symbol,
            ),
          );

  i4.$$StockMasterTableProcessedTableManager get symbol {
    final $_column = $_itemColumn<String>('symbol')!;

    final manager = i4
        .$$StockMasterTableTableManager(
          $_db,
          i5.ReadDatabaseContainer(
            $_db,
          ).resultSet<i4.$StockMasterTable>('stock_master'),
        )
        .filter((f) => f.symbol.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_symbolTable($_db));
    if (item == null) return manager;
    return i0.ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$ShareholdingTableFilterComposer
    extends i0.Composer<i0.GeneratedDatabase, i1.$ShareholdingTable> {
  $$ShareholdingTableFilterComposer({
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

  i0.ColumnFilters<double> get foreignRemainingShares => $composableBuilder(
    column: $table.foreignRemainingShares,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<double> get foreignSharesRatio => $composableBuilder(
    column: $table.foreignSharesRatio,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<double> get foreignUpperLimitRatio => $composableBuilder(
    column: $table.foreignUpperLimitRatio,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<double> get sharesIssued => $composableBuilder(
    column: $table.sharesIssued,
    builder: (column) => i0.ColumnFilters(column),
  );

  i4.$$StockMasterTableFilterComposer get symbol {
    final i4.$$StockMasterTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.symbol,
      referencedTable: i5.ReadDatabaseContainer(
        $db,
      ).resultSet<i4.$StockMasterTable>('stock_master'),
      getReferencedColumn: (t) => t.symbol,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => i4.$$StockMasterTableFilterComposer(
            $db: $db,
            $table: i5.ReadDatabaseContainer(
              $db,
            ).resultSet<i4.$StockMasterTable>('stock_master'),
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ShareholdingTableOrderingComposer
    extends i0.Composer<i0.GeneratedDatabase, i1.$ShareholdingTable> {
  $$ShareholdingTableOrderingComposer({
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

  i0.ColumnOrderings<double> get foreignRemainingShares => $composableBuilder(
    column: $table.foreignRemainingShares,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<double> get foreignSharesRatio => $composableBuilder(
    column: $table.foreignSharesRatio,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<double> get foreignUpperLimitRatio => $composableBuilder(
    column: $table.foreignUpperLimitRatio,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<double> get sharesIssued => $composableBuilder(
    column: $table.sharesIssued,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i4.$$StockMasterTableOrderingComposer get symbol {
    final i4.$$StockMasterTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.symbol,
      referencedTable: i5.ReadDatabaseContainer(
        $db,
      ).resultSet<i4.$StockMasterTable>('stock_master'),
      getReferencedColumn: (t) => t.symbol,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => i4.$$StockMasterTableOrderingComposer(
            $db: $db,
            $table: i5.ReadDatabaseContainer(
              $db,
            ).resultSet<i4.$StockMasterTable>('stock_master'),
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ShareholdingTableAnnotationComposer
    extends i0.Composer<i0.GeneratedDatabase, i1.$ShareholdingTable> {
  $$ShareholdingTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  i0.GeneratedColumn<DateTime> get date =>
      $composableBuilder(column: $table.date, builder: (column) => column);

  i0.GeneratedColumn<double> get foreignRemainingShares => $composableBuilder(
    column: $table.foreignRemainingShares,
    builder: (column) => column,
  );

  i0.GeneratedColumn<double> get foreignSharesRatio => $composableBuilder(
    column: $table.foreignSharesRatio,
    builder: (column) => column,
  );

  i0.GeneratedColumn<double> get foreignUpperLimitRatio => $composableBuilder(
    column: $table.foreignUpperLimitRatio,
    builder: (column) => column,
  );

  i0.GeneratedColumn<double> get sharesIssued => $composableBuilder(
    column: $table.sharesIssued,
    builder: (column) => column,
  );

  i4.$$StockMasterTableAnnotationComposer get symbol {
    final i4.$$StockMasterTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.symbol,
      referencedTable: i5.ReadDatabaseContainer(
        $db,
      ).resultSet<i4.$StockMasterTable>('stock_master'),
      getReferencedColumn: (t) => t.symbol,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => i4.$$StockMasterTableAnnotationComposer(
            $db: $db,
            $table: i5.ReadDatabaseContainer(
              $db,
            ).resultSet<i4.$StockMasterTable>('stock_master'),
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ShareholdingTableTableManager
    extends
        i0.RootTableManager<
          i0.GeneratedDatabase,
          i1.$ShareholdingTable,
          i1.ShareholdingEntry,
          i1.$$ShareholdingTableFilterComposer,
          i1.$$ShareholdingTableOrderingComposer,
          i1.$$ShareholdingTableAnnotationComposer,
          $$ShareholdingTableCreateCompanionBuilder,
          $$ShareholdingTableUpdateCompanionBuilder,
          (i1.ShareholdingEntry, i1.$$ShareholdingTableReferences),
          i1.ShareholdingEntry,
          i0.PrefetchHooks Function({bool symbol})
        > {
  $$ShareholdingTableTableManager(
    i0.GeneratedDatabase db,
    i1.$ShareholdingTable table,
  ) : super(
        i0.TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              i1.$$ShareholdingTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              i1.$$ShareholdingTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              i1.$$ShareholdingTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                i0.Value<String> symbol = const i0.Value.absent(),
                i0.Value<DateTime> date = const i0.Value.absent(),
                i0.Value<double?> foreignRemainingShares =
                    const i0.Value.absent(),
                i0.Value<double?> foreignSharesRatio = const i0.Value.absent(),
                i0.Value<double?> foreignUpperLimitRatio =
                    const i0.Value.absent(),
                i0.Value<double?> sharesIssued = const i0.Value.absent(),
                i0.Value<int> rowid = const i0.Value.absent(),
              }) => i1.ShareholdingCompanion(
                symbol: symbol,
                date: date,
                foreignRemainingShares: foreignRemainingShares,
                foreignSharesRatio: foreignSharesRatio,
                foreignUpperLimitRatio: foreignUpperLimitRatio,
                sharesIssued: sharesIssued,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String symbol,
                required DateTime date,
                i0.Value<double?> foreignRemainingShares =
                    const i0.Value.absent(),
                i0.Value<double?> foreignSharesRatio = const i0.Value.absent(),
                i0.Value<double?> foreignUpperLimitRatio =
                    const i0.Value.absent(),
                i0.Value<double?> sharesIssued = const i0.Value.absent(),
                i0.Value<int> rowid = const i0.Value.absent(),
              }) => i1.ShareholdingCompanion.insert(
                symbol: symbol,
                date: date,
                foreignRemainingShares: foreignRemainingShares,
                foreignSharesRatio: foreignSharesRatio,
                foreignUpperLimitRatio: foreignUpperLimitRatio,
                sharesIssued: sharesIssued,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  i1.$$ShareholdingTableReferences(db, table, e),
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
                                    .$$ShareholdingTableReferences
                                    ._symbolTable(db),
                                referencedColumn: i1
                                    .$$ShareholdingTableReferences
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

typedef $$ShareholdingTableProcessedTableManager =
    i0.ProcessedTableManager<
      i0.GeneratedDatabase,
      i1.$ShareholdingTable,
      i1.ShareholdingEntry,
      i1.$$ShareholdingTableFilterComposer,
      i1.$$ShareholdingTableOrderingComposer,
      i1.$$ShareholdingTableAnnotationComposer,
      $$ShareholdingTableCreateCompanionBuilder,
      $$ShareholdingTableUpdateCompanionBuilder,
      (i1.ShareholdingEntry, i1.$$ShareholdingTableReferences),
      i1.ShareholdingEntry,
      i0.PrefetchHooks Function({bool symbol})
    >;
typedef $$DayTradingTableCreateCompanionBuilder =
    i1.DayTradingCompanion Function({
      required String symbol,
      required DateTime date,
      i0.Value<double?> buyVolume,
      i0.Value<double?> sellVolume,
      i0.Value<double?> dayTradingRatio,
      i0.Value<double?> tradeVolume,
      i0.Value<int> rowid,
    });
typedef $$DayTradingTableUpdateCompanionBuilder =
    i1.DayTradingCompanion Function({
      i0.Value<String> symbol,
      i0.Value<DateTime> date,
      i0.Value<double?> buyVolume,
      i0.Value<double?> sellVolume,
      i0.Value<double?> dayTradingRatio,
      i0.Value<double?> tradeVolume,
      i0.Value<int> rowid,
    });

final class $$DayTradingTableReferences
    extends
        i0.BaseReferences<
          i0.GeneratedDatabase,
          i1.$DayTradingTable,
          i1.DayTradingEntry
        > {
  $$DayTradingTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static i4.$StockMasterTable _symbolTable(i0.GeneratedDatabase db) =>
      i5.ReadDatabaseContainer(db)
          .resultSet<i4.$StockMasterTable>('stock_master')
          .createAlias(
            i0.$_aliasNameGenerator(
              i5.ReadDatabaseContainer(
                db,
              ).resultSet<i1.$DayTradingTable>('day_trading').symbol,
              i5.ReadDatabaseContainer(
                db,
              ).resultSet<i4.$StockMasterTable>('stock_master').symbol,
            ),
          );

  i4.$$StockMasterTableProcessedTableManager get symbol {
    final $_column = $_itemColumn<String>('symbol')!;

    final manager = i4
        .$$StockMasterTableTableManager(
          $_db,
          i5.ReadDatabaseContainer(
            $_db,
          ).resultSet<i4.$StockMasterTable>('stock_master'),
        )
        .filter((f) => f.symbol.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_symbolTable($_db));
    if (item == null) return manager;
    return i0.ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$DayTradingTableFilterComposer
    extends i0.Composer<i0.GeneratedDatabase, i1.$DayTradingTable> {
  $$DayTradingTableFilterComposer({
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

  i0.ColumnFilters<double> get buyVolume => $composableBuilder(
    column: $table.buyVolume,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<double> get sellVolume => $composableBuilder(
    column: $table.sellVolume,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<double> get dayTradingRatio => $composableBuilder(
    column: $table.dayTradingRatio,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<double> get tradeVolume => $composableBuilder(
    column: $table.tradeVolume,
    builder: (column) => i0.ColumnFilters(column),
  );

  i4.$$StockMasterTableFilterComposer get symbol {
    final i4.$$StockMasterTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.symbol,
      referencedTable: i5.ReadDatabaseContainer(
        $db,
      ).resultSet<i4.$StockMasterTable>('stock_master'),
      getReferencedColumn: (t) => t.symbol,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => i4.$$StockMasterTableFilterComposer(
            $db: $db,
            $table: i5.ReadDatabaseContainer(
              $db,
            ).resultSet<i4.$StockMasterTable>('stock_master'),
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$DayTradingTableOrderingComposer
    extends i0.Composer<i0.GeneratedDatabase, i1.$DayTradingTable> {
  $$DayTradingTableOrderingComposer({
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

  i0.ColumnOrderings<double> get buyVolume => $composableBuilder(
    column: $table.buyVolume,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<double> get sellVolume => $composableBuilder(
    column: $table.sellVolume,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<double> get dayTradingRatio => $composableBuilder(
    column: $table.dayTradingRatio,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<double> get tradeVolume => $composableBuilder(
    column: $table.tradeVolume,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i4.$$StockMasterTableOrderingComposer get symbol {
    final i4.$$StockMasterTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.symbol,
      referencedTable: i5.ReadDatabaseContainer(
        $db,
      ).resultSet<i4.$StockMasterTable>('stock_master'),
      getReferencedColumn: (t) => t.symbol,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => i4.$$StockMasterTableOrderingComposer(
            $db: $db,
            $table: i5.ReadDatabaseContainer(
              $db,
            ).resultSet<i4.$StockMasterTable>('stock_master'),
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$DayTradingTableAnnotationComposer
    extends i0.Composer<i0.GeneratedDatabase, i1.$DayTradingTable> {
  $$DayTradingTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  i0.GeneratedColumn<DateTime> get date =>
      $composableBuilder(column: $table.date, builder: (column) => column);

  i0.GeneratedColumn<double> get buyVolume =>
      $composableBuilder(column: $table.buyVolume, builder: (column) => column);

  i0.GeneratedColumn<double> get sellVolume => $composableBuilder(
    column: $table.sellVolume,
    builder: (column) => column,
  );

  i0.GeneratedColumn<double> get dayTradingRatio => $composableBuilder(
    column: $table.dayTradingRatio,
    builder: (column) => column,
  );

  i0.GeneratedColumn<double> get tradeVolume => $composableBuilder(
    column: $table.tradeVolume,
    builder: (column) => column,
  );

  i4.$$StockMasterTableAnnotationComposer get symbol {
    final i4.$$StockMasterTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.symbol,
      referencedTable: i5.ReadDatabaseContainer(
        $db,
      ).resultSet<i4.$StockMasterTable>('stock_master'),
      getReferencedColumn: (t) => t.symbol,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => i4.$$StockMasterTableAnnotationComposer(
            $db: $db,
            $table: i5.ReadDatabaseContainer(
              $db,
            ).resultSet<i4.$StockMasterTable>('stock_master'),
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$DayTradingTableTableManager
    extends
        i0.RootTableManager<
          i0.GeneratedDatabase,
          i1.$DayTradingTable,
          i1.DayTradingEntry,
          i1.$$DayTradingTableFilterComposer,
          i1.$$DayTradingTableOrderingComposer,
          i1.$$DayTradingTableAnnotationComposer,
          $$DayTradingTableCreateCompanionBuilder,
          $$DayTradingTableUpdateCompanionBuilder,
          (i1.DayTradingEntry, i1.$$DayTradingTableReferences),
          i1.DayTradingEntry,
          i0.PrefetchHooks Function({bool symbol})
        > {
  $$DayTradingTableTableManager(
    i0.GeneratedDatabase db,
    i1.$DayTradingTable table,
  ) : super(
        i0.TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              i1.$$DayTradingTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              i1.$$DayTradingTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              i1.$$DayTradingTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                i0.Value<String> symbol = const i0.Value.absent(),
                i0.Value<DateTime> date = const i0.Value.absent(),
                i0.Value<double?> buyVolume = const i0.Value.absent(),
                i0.Value<double?> sellVolume = const i0.Value.absent(),
                i0.Value<double?> dayTradingRatio = const i0.Value.absent(),
                i0.Value<double?> tradeVolume = const i0.Value.absent(),
                i0.Value<int> rowid = const i0.Value.absent(),
              }) => i1.DayTradingCompanion(
                symbol: symbol,
                date: date,
                buyVolume: buyVolume,
                sellVolume: sellVolume,
                dayTradingRatio: dayTradingRatio,
                tradeVolume: tradeVolume,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String symbol,
                required DateTime date,
                i0.Value<double?> buyVolume = const i0.Value.absent(),
                i0.Value<double?> sellVolume = const i0.Value.absent(),
                i0.Value<double?> dayTradingRatio = const i0.Value.absent(),
                i0.Value<double?> tradeVolume = const i0.Value.absent(),
                i0.Value<int> rowid = const i0.Value.absent(),
              }) => i1.DayTradingCompanion.insert(
                symbol: symbol,
                date: date,
                buyVolume: buyVolume,
                sellVolume: sellVolume,
                dayTradingRatio: dayTradingRatio,
                tradeVolume: tradeVolume,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  i1.$$DayTradingTableReferences(db, table, e),
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
                                referencedTable: i1.$$DayTradingTableReferences
                                    ._symbolTable(db),
                                referencedColumn: i1.$$DayTradingTableReferences
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

typedef $$DayTradingTableProcessedTableManager =
    i0.ProcessedTableManager<
      i0.GeneratedDatabase,
      i1.$DayTradingTable,
      i1.DayTradingEntry,
      i1.$$DayTradingTableFilterComposer,
      i1.$$DayTradingTableOrderingComposer,
      i1.$$DayTradingTableAnnotationComposer,
      $$DayTradingTableCreateCompanionBuilder,
      $$DayTradingTableUpdateCompanionBuilder,
      (i1.DayTradingEntry, i1.$$DayTradingTableReferences),
      i1.DayTradingEntry,
      i0.PrefetchHooks Function({bool symbol})
    >;
typedef $$QuarterlyReportTableCreateCompanionBuilder =
    i1.QuarterlyReportCompanion Function({
      required String symbol,
      required int year,
      required int quarter,
      i0.Value<double?> eps,
      i0.Value<double?> netIncome,
      i0.Value<double?> revenue,
      i0.Value<int> rowid,
    });
typedef $$QuarterlyReportTableUpdateCompanionBuilder =
    i1.QuarterlyReportCompanion Function({
      i0.Value<String> symbol,
      i0.Value<int> year,
      i0.Value<int> quarter,
      i0.Value<double?> eps,
      i0.Value<double?> netIncome,
      i0.Value<double?> revenue,
      i0.Value<int> rowid,
    });

final class $$QuarterlyReportTableReferences
    extends
        i0.BaseReferences<
          i0.GeneratedDatabase,
          i1.$QuarterlyReportTable,
          i1.QuarterlyReportData
        > {
  $$QuarterlyReportTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static i4.$StockMasterTable _symbolTable(i0.GeneratedDatabase db) =>
      i5.ReadDatabaseContainer(db)
          .resultSet<i4.$StockMasterTable>('stock_master')
          .createAlias(
            i0.$_aliasNameGenerator(
              i5.ReadDatabaseContainer(
                db,
              ).resultSet<i1.$QuarterlyReportTable>('quarterly_report').symbol,
              i5.ReadDatabaseContainer(
                db,
              ).resultSet<i4.$StockMasterTable>('stock_master').symbol,
            ),
          );

  i4.$$StockMasterTableProcessedTableManager get symbol {
    final $_column = $_itemColumn<String>('symbol')!;

    final manager = i4
        .$$StockMasterTableTableManager(
          $_db,
          i5.ReadDatabaseContainer(
            $_db,
          ).resultSet<i4.$StockMasterTable>('stock_master'),
        )
        .filter((f) => f.symbol.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_symbolTable($_db));
    if (item == null) return manager;
    return i0.ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$QuarterlyReportTableFilterComposer
    extends i0.Composer<i0.GeneratedDatabase, i1.$QuarterlyReportTable> {
  $$QuarterlyReportTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  i0.ColumnFilters<int> get year => $composableBuilder(
    column: $table.year,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<int> get quarter => $composableBuilder(
    column: $table.quarter,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<double> get eps => $composableBuilder(
    column: $table.eps,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<double> get netIncome => $composableBuilder(
    column: $table.netIncome,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<double> get revenue => $composableBuilder(
    column: $table.revenue,
    builder: (column) => i0.ColumnFilters(column),
  );

  i4.$$StockMasterTableFilterComposer get symbol {
    final i4.$$StockMasterTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.symbol,
      referencedTable: i5.ReadDatabaseContainer(
        $db,
      ).resultSet<i4.$StockMasterTable>('stock_master'),
      getReferencedColumn: (t) => t.symbol,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => i4.$$StockMasterTableFilterComposer(
            $db: $db,
            $table: i5.ReadDatabaseContainer(
              $db,
            ).resultSet<i4.$StockMasterTable>('stock_master'),
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$QuarterlyReportTableOrderingComposer
    extends i0.Composer<i0.GeneratedDatabase, i1.$QuarterlyReportTable> {
  $$QuarterlyReportTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  i0.ColumnOrderings<int> get year => $composableBuilder(
    column: $table.year,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<int> get quarter => $composableBuilder(
    column: $table.quarter,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<double> get eps => $composableBuilder(
    column: $table.eps,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<double> get netIncome => $composableBuilder(
    column: $table.netIncome,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<double> get revenue => $composableBuilder(
    column: $table.revenue,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i4.$$StockMasterTableOrderingComposer get symbol {
    final i4.$$StockMasterTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.symbol,
      referencedTable: i5.ReadDatabaseContainer(
        $db,
      ).resultSet<i4.$StockMasterTable>('stock_master'),
      getReferencedColumn: (t) => t.symbol,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => i4.$$StockMasterTableOrderingComposer(
            $db: $db,
            $table: i5.ReadDatabaseContainer(
              $db,
            ).resultSet<i4.$StockMasterTable>('stock_master'),
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$QuarterlyReportTableAnnotationComposer
    extends i0.Composer<i0.GeneratedDatabase, i1.$QuarterlyReportTable> {
  $$QuarterlyReportTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  i0.GeneratedColumn<int> get year =>
      $composableBuilder(column: $table.year, builder: (column) => column);

  i0.GeneratedColumn<int> get quarter =>
      $composableBuilder(column: $table.quarter, builder: (column) => column);

  i0.GeneratedColumn<double> get eps =>
      $composableBuilder(column: $table.eps, builder: (column) => column);

  i0.GeneratedColumn<double> get netIncome =>
      $composableBuilder(column: $table.netIncome, builder: (column) => column);

  i0.GeneratedColumn<double> get revenue =>
      $composableBuilder(column: $table.revenue, builder: (column) => column);

  i4.$$StockMasterTableAnnotationComposer get symbol {
    final i4.$$StockMasterTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.symbol,
      referencedTable: i5.ReadDatabaseContainer(
        $db,
      ).resultSet<i4.$StockMasterTable>('stock_master'),
      getReferencedColumn: (t) => t.symbol,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => i4.$$StockMasterTableAnnotationComposer(
            $db: $db,
            $table: i5.ReadDatabaseContainer(
              $db,
            ).resultSet<i4.$StockMasterTable>('stock_master'),
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$QuarterlyReportTableTableManager
    extends
        i0.RootTableManager<
          i0.GeneratedDatabase,
          i1.$QuarterlyReportTable,
          i1.QuarterlyReportData,
          i1.$$QuarterlyReportTableFilterComposer,
          i1.$$QuarterlyReportTableOrderingComposer,
          i1.$$QuarterlyReportTableAnnotationComposer,
          $$QuarterlyReportTableCreateCompanionBuilder,
          $$QuarterlyReportTableUpdateCompanionBuilder,
          (i1.QuarterlyReportData, i1.$$QuarterlyReportTableReferences),
          i1.QuarterlyReportData,
          i0.PrefetchHooks Function({bool symbol})
        > {
  $$QuarterlyReportTableTableManager(
    i0.GeneratedDatabase db,
    i1.$QuarterlyReportTable table,
  ) : super(
        i0.TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              i1.$$QuarterlyReportTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              i1.$$QuarterlyReportTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () => i1
              .$$QuarterlyReportTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                i0.Value<String> symbol = const i0.Value.absent(),
                i0.Value<int> year = const i0.Value.absent(),
                i0.Value<int> quarter = const i0.Value.absent(),
                i0.Value<double?> eps = const i0.Value.absent(),
                i0.Value<double?> netIncome = const i0.Value.absent(),
                i0.Value<double?> revenue = const i0.Value.absent(),
                i0.Value<int> rowid = const i0.Value.absent(),
              }) => i1.QuarterlyReportCompanion(
                symbol: symbol,
                year: year,
                quarter: quarter,
                eps: eps,
                netIncome: netIncome,
                revenue: revenue,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String symbol,
                required int year,
                required int quarter,
                i0.Value<double?> eps = const i0.Value.absent(),
                i0.Value<double?> netIncome = const i0.Value.absent(),
                i0.Value<double?> revenue = const i0.Value.absent(),
                i0.Value<int> rowid = const i0.Value.absent(),
              }) => i1.QuarterlyReportCompanion.insert(
                symbol: symbol,
                year: year,
                quarter: quarter,
                eps: eps,
                netIncome: netIncome,
                revenue: revenue,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  i1.$$QuarterlyReportTableReferences(db, table, e),
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
                                    .$$QuarterlyReportTableReferences
                                    ._symbolTable(db),
                                referencedColumn: i1
                                    .$$QuarterlyReportTableReferences
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

typedef $$QuarterlyReportTableProcessedTableManager =
    i0.ProcessedTableManager<
      i0.GeneratedDatabase,
      i1.$QuarterlyReportTable,
      i1.QuarterlyReportData,
      i1.$$QuarterlyReportTableFilterComposer,
      i1.$$QuarterlyReportTableOrderingComposer,
      i1.$$QuarterlyReportTableAnnotationComposer,
      $$QuarterlyReportTableCreateCompanionBuilder,
      $$QuarterlyReportTableUpdateCompanionBuilder,
      (i1.QuarterlyReportData, i1.$$QuarterlyReportTableReferences),
      i1.QuarterlyReportData,
      i0.PrefetchHooks Function({bool symbol})
    >;
typedef $$FinancialDataTableCreateCompanionBuilder =
    i1.FinancialDataCompanion Function({
      required String symbol,
      required DateTime date,
      required String statementType,
      required String dataType,
      i0.Value<double?> value,
      i0.Value<String?> originName,
      i0.Value<int> rowid,
    });
typedef $$FinancialDataTableUpdateCompanionBuilder =
    i1.FinancialDataCompanion Function({
      i0.Value<String> symbol,
      i0.Value<DateTime> date,
      i0.Value<String> statementType,
      i0.Value<String> dataType,
      i0.Value<double?> value,
      i0.Value<String?> originName,
      i0.Value<int> rowid,
    });

final class $$FinancialDataTableReferences
    extends
        i0.BaseReferences<
          i0.GeneratedDatabase,
          i1.$FinancialDataTable,
          i1.FinancialDataEntry
        > {
  $$FinancialDataTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static i4.$StockMasterTable _symbolTable(i0.GeneratedDatabase db) =>
      i5.ReadDatabaseContainer(db)
          .resultSet<i4.$StockMasterTable>('stock_master')
          .createAlias(
            i0.$_aliasNameGenerator(
              i5.ReadDatabaseContainer(
                db,
              ).resultSet<i1.$FinancialDataTable>('financial_data').symbol,
              i5.ReadDatabaseContainer(
                db,
              ).resultSet<i4.$StockMasterTable>('stock_master').symbol,
            ),
          );

  i4.$$StockMasterTableProcessedTableManager get symbol {
    final $_column = $_itemColumn<String>('symbol')!;

    final manager = i4
        .$$StockMasterTableTableManager(
          $_db,
          i5.ReadDatabaseContainer(
            $_db,
          ).resultSet<i4.$StockMasterTable>('stock_master'),
        )
        .filter((f) => f.symbol.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_symbolTable($_db));
    if (item == null) return manager;
    return i0.ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$FinancialDataTableFilterComposer
    extends i0.Composer<i0.GeneratedDatabase, i1.$FinancialDataTable> {
  $$FinancialDataTableFilterComposer({
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

  i0.ColumnFilters<String> get statementType => $composableBuilder(
    column: $table.statementType,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<String> get dataType => $composableBuilder(
    column: $table.dataType,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<double> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<String> get originName => $composableBuilder(
    column: $table.originName,
    builder: (column) => i0.ColumnFilters(column),
  );

  i4.$$StockMasterTableFilterComposer get symbol {
    final i4.$$StockMasterTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.symbol,
      referencedTable: i5.ReadDatabaseContainer(
        $db,
      ).resultSet<i4.$StockMasterTable>('stock_master'),
      getReferencedColumn: (t) => t.symbol,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => i4.$$StockMasterTableFilterComposer(
            $db: $db,
            $table: i5.ReadDatabaseContainer(
              $db,
            ).resultSet<i4.$StockMasterTable>('stock_master'),
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$FinancialDataTableOrderingComposer
    extends i0.Composer<i0.GeneratedDatabase, i1.$FinancialDataTable> {
  $$FinancialDataTableOrderingComposer({
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

  i0.ColumnOrderings<String> get statementType => $composableBuilder(
    column: $table.statementType,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<String> get dataType => $composableBuilder(
    column: $table.dataType,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<double> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<String> get originName => $composableBuilder(
    column: $table.originName,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i4.$$StockMasterTableOrderingComposer get symbol {
    final i4.$$StockMasterTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.symbol,
      referencedTable: i5.ReadDatabaseContainer(
        $db,
      ).resultSet<i4.$StockMasterTable>('stock_master'),
      getReferencedColumn: (t) => t.symbol,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => i4.$$StockMasterTableOrderingComposer(
            $db: $db,
            $table: i5.ReadDatabaseContainer(
              $db,
            ).resultSet<i4.$StockMasterTable>('stock_master'),
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$FinancialDataTableAnnotationComposer
    extends i0.Composer<i0.GeneratedDatabase, i1.$FinancialDataTable> {
  $$FinancialDataTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  i0.GeneratedColumn<DateTime> get date =>
      $composableBuilder(column: $table.date, builder: (column) => column);

  i0.GeneratedColumn<String> get statementType => $composableBuilder(
    column: $table.statementType,
    builder: (column) => column,
  );

  i0.GeneratedColumn<String> get dataType =>
      $composableBuilder(column: $table.dataType, builder: (column) => column);

  i0.GeneratedColumn<double> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);

  i0.GeneratedColumn<String> get originName => $composableBuilder(
    column: $table.originName,
    builder: (column) => column,
  );

  i4.$$StockMasterTableAnnotationComposer get symbol {
    final i4.$$StockMasterTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.symbol,
      referencedTable: i5.ReadDatabaseContainer(
        $db,
      ).resultSet<i4.$StockMasterTable>('stock_master'),
      getReferencedColumn: (t) => t.symbol,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => i4.$$StockMasterTableAnnotationComposer(
            $db: $db,
            $table: i5.ReadDatabaseContainer(
              $db,
            ).resultSet<i4.$StockMasterTable>('stock_master'),
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$FinancialDataTableTableManager
    extends
        i0.RootTableManager<
          i0.GeneratedDatabase,
          i1.$FinancialDataTable,
          i1.FinancialDataEntry,
          i1.$$FinancialDataTableFilterComposer,
          i1.$$FinancialDataTableOrderingComposer,
          i1.$$FinancialDataTableAnnotationComposer,
          $$FinancialDataTableCreateCompanionBuilder,
          $$FinancialDataTableUpdateCompanionBuilder,
          (i1.FinancialDataEntry, i1.$$FinancialDataTableReferences),
          i1.FinancialDataEntry,
          i0.PrefetchHooks Function({bool symbol})
        > {
  $$FinancialDataTableTableManager(
    i0.GeneratedDatabase db,
    i1.$FinancialDataTable table,
  ) : super(
        i0.TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              i1.$$FinancialDataTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              i1.$$FinancialDataTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              i1.$$FinancialDataTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                i0.Value<String> symbol = const i0.Value.absent(),
                i0.Value<DateTime> date = const i0.Value.absent(),
                i0.Value<String> statementType = const i0.Value.absent(),
                i0.Value<String> dataType = const i0.Value.absent(),
                i0.Value<double?> value = const i0.Value.absent(),
                i0.Value<String?> originName = const i0.Value.absent(),
                i0.Value<int> rowid = const i0.Value.absent(),
              }) => i1.FinancialDataCompanion(
                symbol: symbol,
                date: date,
                statementType: statementType,
                dataType: dataType,
                value: value,
                originName: originName,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String symbol,
                required DateTime date,
                required String statementType,
                required String dataType,
                i0.Value<double?> value = const i0.Value.absent(),
                i0.Value<String?> originName = const i0.Value.absent(),
                i0.Value<int> rowid = const i0.Value.absent(),
              }) => i1.FinancialDataCompanion.insert(
                symbol: symbol,
                date: date,
                statementType: statementType,
                dataType: dataType,
                value: value,
                originName: originName,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  i1.$$FinancialDataTableReferences(db, table, e),
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
                                    .$$FinancialDataTableReferences
                                    ._symbolTable(db),
                                referencedColumn: i1
                                    .$$FinancialDataTableReferences
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

typedef $$FinancialDataTableProcessedTableManager =
    i0.ProcessedTableManager<
      i0.GeneratedDatabase,
      i1.$FinancialDataTable,
      i1.FinancialDataEntry,
      i1.$$FinancialDataTableFilterComposer,
      i1.$$FinancialDataTableOrderingComposer,
      i1.$$FinancialDataTableAnnotationComposer,
      $$FinancialDataTableCreateCompanionBuilder,
      $$FinancialDataTableUpdateCompanionBuilder,
      (i1.FinancialDataEntry, i1.$$FinancialDataTableReferences),
      i1.FinancialDataEntry,
      i0.PrefetchHooks Function({bool symbol})
    >;
typedef $$HoldingDistributionTableCreateCompanionBuilder =
    i1.HoldingDistributionCompanion Function({
      required String symbol,
      required DateTime date,
      required String level,
      i0.Value<int?> shareholders,
      i0.Value<double?> percent,
      i0.Value<double?> shares,
      i0.Value<int> rowid,
    });
typedef $$HoldingDistributionTableUpdateCompanionBuilder =
    i1.HoldingDistributionCompanion Function({
      i0.Value<String> symbol,
      i0.Value<DateTime> date,
      i0.Value<String> level,
      i0.Value<int?> shareholders,
      i0.Value<double?> percent,
      i0.Value<double?> shares,
      i0.Value<int> rowid,
    });

final class $$HoldingDistributionTableReferences
    extends
        i0.BaseReferences<
          i0.GeneratedDatabase,
          i1.$HoldingDistributionTable,
          i1.HoldingDistributionEntry
        > {
  $$HoldingDistributionTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static i4.$StockMasterTable _symbolTable(i0.GeneratedDatabase db) =>
      i5.ReadDatabaseContainer(db)
          .resultSet<i4.$StockMasterTable>('stock_master')
          .createAlias(
            i0.$_aliasNameGenerator(
              i5.ReadDatabaseContainer(db)
                  .resultSet<i1.$HoldingDistributionTable>(
                    'holding_distribution',
                  )
                  .symbol,
              i5.ReadDatabaseContainer(
                db,
              ).resultSet<i4.$StockMasterTable>('stock_master').symbol,
            ),
          );

  i4.$$StockMasterTableProcessedTableManager get symbol {
    final $_column = $_itemColumn<String>('symbol')!;

    final manager = i4
        .$$StockMasterTableTableManager(
          $_db,
          i5.ReadDatabaseContainer(
            $_db,
          ).resultSet<i4.$StockMasterTable>('stock_master'),
        )
        .filter((f) => f.symbol.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_symbolTable($_db));
    if (item == null) return manager;
    return i0.ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$HoldingDistributionTableFilterComposer
    extends i0.Composer<i0.GeneratedDatabase, i1.$HoldingDistributionTable> {
  $$HoldingDistributionTableFilterComposer({
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

  i0.ColumnFilters<String> get level => $composableBuilder(
    column: $table.level,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<int> get shareholders => $composableBuilder(
    column: $table.shareholders,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<double> get percent => $composableBuilder(
    column: $table.percent,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<double> get shares => $composableBuilder(
    column: $table.shares,
    builder: (column) => i0.ColumnFilters(column),
  );

  i4.$$StockMasterTableFilterComposer get symbol {
    final i4.$$StockMasterTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.symbol,
      referencedTable: i5.ReadDatabaseContainer(
        $db,
      ).resultSet<i4.$StockMasterTable>('stock_master'),
      getReferencedColumn: (t) => t.symbol,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => i4.$$StockMasterTableFilterComposer(
            $db: $db,
            $table: i5.ReadDatabaseContainer(
              $db,
            ).resultSet<i4.$StockMasterTable>('stock_master'),
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$HoldingDistributionTableOrderingComposer
    extends i0.Composer<i0.GeneratedDatabase, i1.$HoldingDistributionTable> {
  $$HoldingDistributionTableOrderingComposer({
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

  i0.ColumnOrderings<String> get level => $composableBuilder(
    column: $table.level,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<int> get shareholders => $composableBuilder(
    column: $table.shareholders,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<double> get percent => $composableBuilder(
    column: $table.percent,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<double> get shares => $composableBuilder(
    column: $table.shares,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i4.$$StockMasterTableOrderingComposer get symbol {
    final i4.$$StockMasterTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.symbol,
      referencedTable: i5.ReadDatabaseContainer(
        $db,
      ).resultSet<i4.$StockMasterTable>('stock_master'),
      getReferencedColumn: (t) => t.symbol,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => i4.$$StockMasterTableOrderingComposer(
            $db: $db,
            $table: i5.ReadDatabaseContainer(
              $db,
            ).resultSet<i4.$StockMasterTable>('stock_master'),
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$HoldingDistributionTableAnnotationComposer
    extends i0.Composer<i0.GeneratedDatabase, i1.$HoldingDistributionTable> {
  $$HoldingDistributionTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  i0.GeneratedColumn<DateTime> get date =>
      $composableBuilder(column: $table.date, builder: (column) => column);

  i0.GeneratedColumn<String> get level =>
      $composableBuilder(column: $table.level, builder: (column) => column);

  i0.GeneratedColumn<int> get shareholders => $composableBuilder(
    column: $table.shareholders,
    builder: (column) => column,
  );

  i0.GeneratedColumn<double> get percent =>
      $composableBuilder(column: $table.percent, builder: (column) => column);

  i0.GeneratedColumn<double> get shares =>
      $composableBuilder(column: $table.shares, builder: (column) => column);

  i4.$$StockMasterTableAnnotationComposer get symbol {
    final i4.$$StockMasterTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.symbol,
      referencedTable: i5.ReadDatabaseContainer(
        $db,
      ).resultSet<i4.$StockMasterTable>('stock_master'),
      getReferencedColumn: (t) => t.symbol,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => i4.$$StockMasterTableAnnotationComposer(
            $db: $db,
            $table: i5.ReadDatabaseContainer(
              $db,
            ).resultSet<i4.$StockMasterTable>('stock_master'),
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$HoldingDistributionTableTableManager
    extends
        i0.RootTableManager<
          i0.GeneratedDatabase,
          i1.$HoldingDistributionTable,
          i1.HoldingDistributionEntry,
          i1.$$HoldingDistributionTableFilterComposer,
          i1.$$HoldingDistributionTableOrderingComposer,
          i1.$$HoldingDistributionTableAnnotationComposer,
          $$HoldingDistributionTableCreateCompanionBuilder,
          $$HoldingDistributionTableUpdateCompanionBuilder,
          (
            i1.HoldingDistributionEntry,
            i1.$$HoldingDistributionTableReferences,
          ),
          i1.HoldingDistributionEntry,
          i0.PrefetchHooks Function({bool symbol})
        > {
  $$HoldingDistributionTableTableManager(
    i0.GeneratedDatabase db,
    i1.$HoldingDistributionTable table,
  ) : super(
        i0.TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () => i1
              .$$HoldingDistributionTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              i1.$$HoldingDistributionTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              i1.$$HoldingDistributionTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                i0.Value<String> symbol = const i0.Value.absent(),
                i0.Value<DateTime> date = const i0.Value.absent(),
                i0.Value<String> level = const i0.Value.absent(),
                i0.Value<int?> shareholders = const i0.Value.absent(),
                i0.Value<double?> percent = const i0.Value.absent(),
                i0.Value<double?> shares = const i0.Value.absent(),
                i0.Value<int> rowid = const i0.Value.absent(),
              }) => i1.HoldingDistributionCompanion(
                symbol: symbol,
                date: date,
                level: level,
                shareholders: shareholders,
                percent: percent,
                shares: shares,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String symbol,
                required DateTime date,
                required String level,
                i0.Value<int?> shareholders = const i0.Value.absent(),
                i0.Value<double?> percent = const i0.Value.absent(),
                i0.Value<double?> shares = const i0.Value.absent(),
                i0.Value<int> rowid = const i0.Value.absent(),
              }) => i1.HoldingDistributionCompanion.insert(
                symbol: symbol,
                date: date,
                level: level,
                shareholders: shareholders,
                percent: percent,
                shares: shares,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  i1.$$HoldingDistributionTableReferences(db, table, e),
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
                                    .$$HoldingDistributionTableReferences
                                    ._symbolTable(db),
                                referencedColumn: i1
                                    .$$HoldingDistributionTableReferences
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

typedef $$HoldingDistributionTableProcessedTableManager =
    i0.ProcessedTableManager<
      i0.GeneratedDatabase,
      i1.$HoldingDistributionTable,
      i1.HoldingDistributionEntry,
      i1.$$HoldingDistributionTableFilterComposer,
      i1.$$HoldingDistributionTableOrderingComposer,
      i1.$$HoldingDistributionTableAnnotationComposer,
      $$HoldingDistributionTableCreateCompanionBuilder,
      $$HoldingDistributionTableUpdateCompanionBuilder,
      (i1.HoldingDistributionEntry, i1.$$HoldingDistributionTableReferences),
      i1.HoldingDistributionEntry,
      i0.PrefetchHooks Function({bool symbol})
    >;
typedef $$DividendHistoryTableCreateCompanionBuilder =
    i1.DividendHistoryCompanion Function({
      required String symbol,
      required int year,
      i0.Value<double> cashDividend,
      i0.Value<double> stockDividend,
      i0.Value<String?> exDividendDate,
      i0.Value<String?> exRightsDate,
      i0.Value<int> rowid,
    });
typedef $$DividendHistoryTableUpdateCompanionBuilder =
    i1.DividendHistoryCompanion Function({
      i0.Value<String> symbol,
      i0.Value<int> year,
      i0.Value<double> cashDividend,
      i0.Value<double> stockDividend,
      i0.Value<String?> exDividendDate,
      i0.Value<String?> exRightsDate,
      i0.Value<int> rowid,
    });

final class $$DividendHistoryTableReferences
    extends
        i0.BaseReferences<
          i0.GeneratedDatabase,
          i1.$DividendHistoryTable,
          i1.DividendHistoryEntry
        > {
  $$DividendHistoryTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static i4.$StockMasterTable _symbolTable(i0.GeneratedDatabase db) =>
      i5.ReadDatabaseContainer(db)
          .resultSet<i4.$StockMasterTable>('stock_master')
          .createAlias(
            i0.$_aliasNameGenerator(
              i5.ReadDatabaseContainer(
                db,
              ).resultSet<i1.$DividendHistoryTable>('dividend_history').symbol,
              i5.ReadDatabaseContainer(
                db,
              ).resultSet<i4.$StockMasterTable>('stock_master').symbol,
            ),
          );

  i4.$$StockMasterTableProcessedTableManager get symbol {
    final $_column = $_itemColumn<String>('symbol')!;

    final manager = i4
        .$$StockMasterTableTableManager(
          $_db,
          i5.ReadDatabaseContainer(
            $_db,
          ).resultSet<i4.$StockMasterTable>('stock_master'),
        )
        .filter((f) => f.symbol.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_symbolTable($_db));
    if (item == null) return manager;
    return i0.ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$DividendHistoryTableFilterComposer
    extends i0.Composer<i0.GeneratedDatabase, i1.$DividendHistoryTable> {
  $$DividendHistoryTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  i0.ColumnFilters<int> get year => $composableBuilder(
    column: $table.year,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<double> get cashDividend => $composableBuilder(
    column: $table.cashDividend,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<double> get stockDividend => $composableBuilder(
    column: $table.stockDividend,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<String> get exDividendDate => $composableBuilder(
    column: $table.exDividendDate,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<String> get exRightsDate => $composableBuilder(
    column: $table.exRightsDate,
    builder: (column) => i0.ColumnFilters(column),
  );

  i4.$$StockMasterTableFilterComposer get symbol {
    final i4.$$StockMasterTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.symbol,
      referencedTable: i5.ReadDatabaseContainer(
        $db,
      ).resultSet<i4.$StockMasterTable>('stock_master'),
      getReferencedColumn: (t) => t.symbol,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => i4.$$StockMasterTableFilterComposer(
            $db: $db,
            $table: i5.ReadDatabaseContainer(
              $db,
            ).resultSet<i4.$StockMasterTable>('stock_master'),
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$DividendHistoryTableOrderingComposer
    extends i0.Composer<i0.GeneratedDatabase, i1.$DividendHistoryTable> {
  $$DividendHistoryTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  i0.ColumnOrderings<int> get year => $composableBuilder(
    column: $table.year,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<double> get cashDividend => $composableBuilder(
    column: $table.cashDividend,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<double> get stockDividend => $composableBuilder(
    column: $table.stockDividend,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<String> get exDividendDate => $composableBuilder(
    column: $table.exDividendDate,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<String> get exRightsDate => $composableBuilder(
    column: $table.exRightsDate,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i4.$$StockMasterTableOrderingComposer get symbol {
    final i4.$$StockMasterTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.symbol,
      referencedTable: i5.ReadDatabaseContainer(
        $db,
      ).resultSet<i4.$StockMasterTable>('stock_master'),
      getReferencedColumn: (t) => t.symbol,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => i4.$$StockMasterTableOrderingComposer(
            $db: $db,
            $table: i5.ReadDatabaseContainer(
              $db,
            ).resultSet<i4.$StockMasterTable>('stock_master'),
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$DividendHistoryTableAnnotationComposer
    extends i0.Composer<i0.GeneratedDatabase, i1.$DividendHistoryTable> {
  $$DividendHistoryTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  i0.GeneratedColumn<int> get year =>
      $composableBuilder(column: $table.year, builder: (column) => column);

  i0.GeneratedColumn<double> get cashDividend => $composableBuilder(
    column: $table.cashDividend,
    builder: (column) => column,
  );

  i0.GeneratedColumn<double> get stockDividend => $composableBuilder(
    column: $table.stockDividend,
    builder: (column) => column,
  );

  i0.GeneratedColumn<String> get exDividendDate => $composableBuilder(
    column: $table.exDividendDate,
    builder: (column) => column,
  );

  i0.GeneratedColumn<String> get exRightsDate => $composableBuilder(
    column: $table.exRightsDate,
    builder: (column) => column,
  );

  i4.$$StockMasterTableAnnotationComposer get symbol {
    final i4.$$StockMasterTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.symbol,
      referencedTable: i5.ReadDatabaseContainer(
        $db,
      ).resultSet<i4.$StockMasterTable>('stock_master'),
      getReferencedColumn: (t) => t.symbol,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => i4.$$StockMasterTableAnnotationComposer(
            $db: $db,
            $table: i5.ReadDatabaseContainer(
              $db,
            ).resultSet<i4.$StockMasterTable>('stock_master'),
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$DividendHistoryTableTableManager
    extends
        i0.RootTableManager<
          i0.GeneratedDatabase,
          i1.$DividendHistoryTable,
          i1.DividendHistoryEntry,
          i1.$$DividendHistoryTableFilterComposer,
          i1.$$DividendHistoryTableOrderingComposer,
          i1.$$DividendHistoryTableAnnotationComposer,
          $$DividendHistoryTableCreateCompanionBuilder,
          $$DividendHistoryTableUpdateCompanionBuilder,
          (i1.DividendHistoryEntry, i1.$$DividendHistoryTableReferences),
          i1.DividendHistoryEntry,
          i0.PrefetchHooks Function({bool symbol})
        > {
  $$DividendHistoryTableTableManager(
    i0.GeneratedDatabase db,
    i1.$DividendHistoryTable table,
  ) : super(
        i0.TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              i1.$$DividendHistoryTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              i1.$$DividendHistoryTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () => i1
              .$$DividendHistoryTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                i0.Value<String> symbol = const i0.Value.absent(),
                i0.Value<int> year = const i0.Value.absent(),
                i0.Value<double> cashDividend = const i0.Value.absent(),
                i0.Value<double> stockDividend = const i0.Value.absent(),
                i0.Value<String?> exDividendDate = const i0.Value.absent(),
                i0.Value<String?> exRightsDate = const i0.Value.absent(),
                i0.Value<int> rowid = const i0.Value.absent(),
              }) => i1.DividendHistoryCompanion(
                symbol: symbol,
                year: year,
                cashDividend: cashDividend,
                stockDividend: stockDividend,
                exDividendDate: exDividendDate,
                exRightsDate: exRightsDate,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String symbol,
                required int year,
                i0.Value<double> cashDividend = const i0.Value.absent(),
                i0.Value<double> stockDividend = const i0.Value.absent(),
                i0.Value<String?> exDividendDate = const i0.Value.absent(),
                i0.Value<String?> exRightsDate = const i0.Value.absent(),
                i0.Value<int> rowid = const i0.Value.absent(),
              }) => i1.DividendHistoryCompanion.insert(
                symbol: symbol,
                year: year,
                cashDividend: cashDividend,
                stockDividend: stockDividend,
                exDividendDate: exDividendDate,
                exRightsDate: exRightsDate,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  i1.$$DividendHistoryTableReferences(db, table, e),
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
                                    .$$DividendHistoryTableReferences
                                    ._symbolTable(db),
                                referencedColumn: i1
                                    .$$DividendHistoryTableReferences
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

typedef $$DividendHistoryTableProcessedTableManager =
    i0.ProcessedTableManager<
      i0.GeneratedDatabase,
      i1.$DividendHistoryTable,
      i1.DividendHistoryEntry,
      i1.$$DividendHistoryTableFilterComposer,
      i1.$$DividendHistoryTableOrderingComposer,
      i1.$$DividendHistoryTableAnnotationComposer,
      $$DividendHistoryTableCreateCompanionBuilder,
      $$DividendHistoryTableUpdateCompanionBuilder,
      (i1.DividendHistoryEntry, i1.$$DividendHistoryTableReferences),
      i1.DividendHistoryEntry,
      i0.PrefetchHooks Function({bool symbol})
    >;
typedef $$MonthlyRevenueTableCreateCompanionBuilder =
    i1.MonthlyRevenueCompanion Function({
      required String symbol,
      required DateTime date,
      required int revenueYear,
      required int revenueMonth,
      required double revenue,
      i0.Value<double?> momGrowth,
      i0.Value<double?> yoyGrowth,
      i0.Value<double?> ytdYoyGrowth,
      i0.Value<int> rowid,
    });
typedef $$MonthlyRevenueTableUpdateCompanionBuilder =
    i1.MonthlyRevenueCompanion Function({
      i0.Value<String> symbol,
      i0.Value<DateTime> date,
      i0.Value<int> revenueYear,
      i0.Value<int> revenueMonth,
      i0.Value<double> revenue,
      i0.Value<double?> momGrowth,
      i0.Value<double?> yoyGrowth,
      i0.Value<double?> ytdYoyGrowth,
      i0.Value<int> rowid,
    });

final class $$MonthlyRevenueTableReferences
    extends
        i0.BaseReferences<
          i0.GeneratedDatabase,
          i1.$MonthlyRevenueTable,
          i1.MonthlyRevenueEntry
        > {
  $$MonthlyRevenueTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static i4.$StockMasterTable _symbolTable(i0.GeneratedDatabase db) =>
      i5.ReadDatabaseContainer(db)
          .resultSet<i4.$StockMasterTable>('stock_master')
          .createAlias(
            i0.$_aliasNameGenerator(
              i5.ReadDatabaseContainer(
                db,
              ).resultSet<i1.$MonthlyRevenueTable>('monthly_revenue').symbol,
              i5.ReadDatabaseContainer(
                db,
              ).resultSet<i4.$StockMasterTable>('stock_master').symbol,
            ),
          );

  i4.$$StockMasterTableProcessedTableManager get symbol {
    final $_column = $_itemColumn<String>('symbol')!;

    final manager = i4
        .$$StockMasterTableTableManager(
          $_db,
          i5.ReadDatabaseContainer(
            $_db,
          ).resultSet<i4.$StockMasterTable>('stock_master'),
        )
        .filter((f) => f.symbol.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_symbolTable($_db));
    if (item == null) return manager;
    return i0.ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$MonthlyRevenueTableFilterComposer
    extends i0.Composer<i0.GeneratedDatabase, i1.$MonthlyRevenueTable> {
  $$MonthlyRevenueTableFilterComposer({
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

  i0.ColumnFilters<int> get revenueYear => $composableBuilder(
    column: $table.revenueYear,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<int> get revenueMonth => $composableBuilder(
    column: $table.revenueMonth,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<double> get revenue => $composableBuilder(
    column: $table.revenue,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<double> get momGrowth => $composableBuilder(
    column: $table.momGrowth,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<double> get yoyGrowth => $composableBuilder(
    column: $table.yoyGrowth,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<double> get ytdYoyGrowth => $composableBuilder(
    column: $table.ytdYoyGrowth,
    builder: (column) => i0.ColumnFilters(column),
  );

  i4.$$StockMasterTableFilterComposer get symbol {
    final i4.$$StockMasterTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.symbol,
      referencedTable: i5.ReadDatabaseContainer(
        $db,
      ).resultSet<i4.$StockMasterTable>('stock_master'),
      getReferencedColumn: (t) => t.symbol,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => i4.$$StockMasterTableFilterComposer(
            $db: $db,
            $table: i5.ReadDatabaseContainer(
              $db,
            ).resultSet<i4.$StockMasterTable>('stock_master'),
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$MonthlyRevenueTableOrderingComposer
    extends i0.Composer<i0.GeneratedDatabase, i1.$MonthlyRevenueTable> {
  $$MonthlyRevenueTableOrderingComposer({
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

  i0.ColumnOrderings<int> get revenueYear => $composableBuilder(
    column: $table.revenueYear,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<int> get revenueMonth => $composableBuilder(
    column: $table.revenueMonth,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<double> get revenue => $composableBuilder(
    column: $table.revenue,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<double> get momGrowth => $composableBuilder(
    column: $table.momGrowth,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<double> get yoyGrowth => $composableBuilder(
    column: $table.yoyGrowth,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<double> get ytdYoyGrowth => $composableBuilder(
    column: $table.ytdYoyGrowth,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i4.$$StockMasterTableOrderingComposer get symbol {
    final i4.$$StockMasterTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.symbol,
      referencedTable: i5.ReadDatabaseContainer(
        $db,
      ).resultSet<i4.$StockMasterTable>('stock_master'),
      getReferencedColumn: (t) => t.symbol,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => i4.$$StockMasterTableOrderingComposer(
            $db: $db,
            $table: i5.ReadDatabaseContainer(
              $db,
            ).resultSet<i4.$StockMasterTable>('stock_master'),
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$MonthlyRevenueTableAnnotationComposer
    extends i0.Composer<i0.GeneratedDatabase, i1.$MonthlyRevenueTable> {
  $$MonthlyRevenueTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  i0.GeneratedColumn<DateTime> get date =>
      $composableBuilder(column: $table.date, builder: (column) => column);

  i0.GeneratedColumn<int> get revenueYear => $composableBuilder(
    column: $table.revenueYear,
    builder: (column) => column,
  );

  i0.GeneratedColumn<int> get revenueMonth => $composableBuilder(
    column: $table.revenueMonth,
    builder: (column) => column,
  );

  i0.GeneratedColumn<double> get revenue =>
      $composableBuilder(column: $table.revenue, builder: (column) => column);

  i0.GeneratedColumn<double> get momGrowth =>
      $composableBuilder(column: $table.momGrowth, builder: (column) => column);

  i0.GeneratedColumn<double> get yoyGrowth =>
      $composableBuilder(column: $table.yoyGrowth, builder: (column) => column);

  i0.GeneratedColumn<double> get ytdYoyGrowth => $composableBuilder(
    column: $table.ytdYoyGrowth,
    builder: (column) => column,
  );

  i4.$$StockMasterTableAnnotationComposer get symbol {
    final i4.$$StockMasterTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.symbol,
      referencedTable: i5.ReadDatabaseContainer(
        $db,
      ).resultSet<i4.$StockMasterTable>('stock_master'),
      getReferencedColumn: (t) => t.symbol,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => i4.$$StockMasterTableAnnotationComposer(
            $db: $db,
            $table: i5.ReadDatabaseContainer(
              $db,
            ).resultSet<i4.$StockMasterTable>('stock_master'),
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$MonthlyRevenueTableTableManager
    extends
        i0.RootTableManager<
          i0.GeneratedDatabase,
          i1.$MonthlyRevenueTable,
          i1.MonthlyRevenueEntry,
          i1.$$MonthlyRevenueTableFilterComposer,
          i1.$$MonthlyRevenueTableOrderingComposer,
          i1.$$MonthlyRevenueTableAnnotationComposer,
          $$MonthlyRevenueTableCreateCompanionBuilder,
          $$MonthlyRevenueTableUpdateCompanionBuilder,
          (i1.MonthlyRevenueEntry, i1.$$MonthlyRevenueTableReferences),
          i1.MonthlyRevenueEntry,
          i0.PrefetchHooks Function({bool symbol})
        > {
  $$MonthlyRevenueTableTableManager(
    i0.GeneratedDatabase db,
    i1.$MonthlyRevenueTable table,
  ) : super(
        i0.TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              i1.$$MonthlyRevenueTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              i1.$$MonthlyRevenueTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () => i1
              .$$MonthlyRevenueTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                i0.Value<String> symbol = const i0.Value.absent(),
                i0.Value<DateTime> date = const i0.Value.absent(),
                i0.Value<int> revenueYear = const i0.Value.absent(),
                i0.Value<int> revenueMonth = const i0.Value.absent(),
                i0.Value<double> revenue = const i0.Value.absent(),
                i0.Value<double?> momGrowth = const i0.Value.absent(),
                i0.Value<double?> yoyGrowth = const i0.Value.absent(),
                i0.Value<double?> ytdYoyGrowth = const i0.Value.absent(),
                i0.Value<int> rowid = const i0.Value.absent(),
              }) => i1.MonthlyRevenueCompanion(
                symbol: symbol,
                date: date,
                revenueYear: revenueYear,
                revenueMonth: revenueMonth,
                revenue: revenue,
                momGrowth: momGrowth,
                yoyGrowth: yoyGrowth,
                ytdYoyGrowth: ytdYoyGrowth,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String symbol,
                required DateTime date,
                required int revenueYear,
                required int revenueMonth,
                required double revenue,
                i0.Value<double?> momGrowth = const i0.Value.absent(),
                i0.Value<double?> yoyGrowth = const i0.Value.absent(),
                i0.Value<double?> ytdYoyGrowth = const i0.Value.absent(),
                i0.Value<int> rowid = const i0.Value.absent(),
              }) => i1.MonthlyRevenueCompanion.insert(
                symbol: symbol,
                date: date,
                revenueYear: revenueYear,
                revenueMonth: revenueMonth,
                revenue: revenue,
                momGrowth: momGrowth,
                yoyGrowth: yoyGrowth,
                ytdYoyGrowth: ytdYoyGrowth,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  i1.$$MonthlyRevenueTableReferences(db, table, e),
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
                                    .$$MonthlyRevenueTableReferences
                                    ._symbolTable(db),
                                referencedColumn: i1
                                    .$$MonthlyRevenueTableReferences
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

typedef $$MonthlyRevenueTableProcessedTableManager =
    i0.ProcessedTableManager<
      i0.GeneratedDatabase,
      i1.$MonthlyRevenueTable,
      i1.MonthlyRevenueEntry,
      i1.$$MonthlyRevenueTableFilterComposer,
      i1.$$MonthlyRevenueTableOrderingComposer,
      i1.$$MonthlyRevenueTableAnnotationComposer,
      $$MonthlyRevenueTableCreateCompanionBuilder,
      $$MonthlyRevenueTableUpdateCompanionBuilder,
      (i1.MonthlyRevenueEntry, i1.$$MonthlyRevenueTableReferences),
      i1.MonthlyRevenueEntry,
      i0.PrefetchHooks Function({bool symbol})
    >;
typedef $$StockValuationTableCreateCompanionBuilder =
    i1.StockValuationCompanion Function({
      required String symbol,
      required DateTime date,
      i0.Value<double?> per,
      i0.Value<double?> pbr,
      i0.Value<double?> dividendYield,
      i0.Value<int> rowid,
    });
typedef $$StockValuationTableUpdateCompanionBuilder =
    i1.StockValuationCompanion Function({
      i0.Value<String> symbol,
      i0.Value<DateTime> date,
      i0.Value<double?> per,
      i0.Value<double?> pbr,
      i0.Value<double?> dividendYield,
      i0.Value<int> rowid,
    });

final class $$StockValuationTableReferences
    extends
        i0.BaseReferences<
          i0.GeneratedDatabase,
          i1.$StockValuationTable,
          i1.StockValuationEntry
        > {
  $$StockValuationTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static i4.$StockMasterTable _symbolTable(i0.GeneratedDatabase db) =>
      i5.ReadDatabaseContainer(db)
          .resultSet<i4.$StockMasterTable>('stock_master')
          .createAlias(
            i0.$_aliasNameGenerator(
              i5.ReadDatabaseContainer(
                db,
              ).resultSet<i1.$StockValuationTable>('stock_valuation').symbol,
              i5.ReadDatabaseContainer(
                db,
              ).resultSet<i4.$StockMasterTable>('stock_master').symbol,
            ),
          );

  i4.$$StockMasterTableProcessedTableManager get symbol {
    final $_column = $_itemColumn<String>('symbol')!;

    final manager = i4
        .$$StockMasterTableTableManager(
          $_db,
          i5.ReadDatabaseContainer(
            $_db,
          ).resultSet<i4.$StockMasterTable>('stock_master'),
        )
        .filter((f) => f.symbol.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_symbolTable($_db));
    if (item == null) return manager;
    return i0.ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$StockValuationTableFilterComposer
    extends i0.Composer<i0.GeneratedDatabase, i1.$StockValuationTable> {
  $$StockValuationTableFilterComposer({
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

  i0.ColumnFilters<double> get per => $composableBuilder(
    column: $table.per,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<double> get pbr => $composableBuilder(
    column: $table.pbr,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<double> get dividendYield => $composableBuilder(
    column: $table.dividendYield,
    builder: (column) => i0.ColumnFilters(column),
  );

  i4.$$StockMasterTableFilterComposer get symbol {
    final i4.$$StockMasterTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.symbol,
      referencedTable: i5.ReadDatabaseContainer(
        $db,
      ).resultSet<i4.$StockMasterTable>('stock_master'),
      getReferencedColumn: (t) => t.symbol,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => i4.$$StockMasterTableFilterComposer(
            $db: $db,
            $table: i5.ReadDatabaseContainer(
              $db,
            ).resultSet<i4.$StockMasterTable>('stock_master'),
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$StockValuationTableOrderingComposer
    extends i0.Composer<i0.GeneratedDatabase, i1.$StockValuationTable> {
  $$StockValuationTableOrderingComposer({
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

  i0.ColumnOrderings<double> get per => $composableBuilder(
    column: $table.per,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<double> get pbr => $composableBuilder(
    column: $table.pbr,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<double> get dividendYield => $composableBuilder(
    column: $table.dividendYield,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i4.$$StockMasterTableOrderingComposer get symbol {
    final i4.$$StockMasterTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.symbol,
      referencedTable: i5.ReadDatabaseContainer(
        $db,
      ).resultSet<i4.$StockMasterTable>('stock_master'),
      getReferencedColumn: (t) => t.symbol,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => i4.$$StockMasterTableOrderingComposer(
            $db: $db,
            $table: i5.ReadDatabaseContainer(
              $db,
            ).resultSet<i4.$StockMasterTable>('stock_master'),
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$StockValuationTableAnnotationComposer
    extends i0.Composer<i0.GeneratedDatabase, i1.$StockValuationTable> {
  $$StockValuationTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  i0.GeneratedColumn<DateTime> get date =>
      $composableBuilder(column: $table.date, builder: (column) => column);

  i0.GeneratedColumn<double> get per =>
      $composableBuilder(column: $table.per, builder: (column) => column);

  i0.GeneratedColumn<double> get pbr =>
      $composableBuilder(column: $table.pbr, builder: (column) => column);

  i0.GeneratedColumn<double> get dividendYield => $composableBuilder(
    column: $table.dividendYield,
    builder: (column) => column,
  );

  i4.$$StockMasterTableAnnotationComposer get symbol {
    final i4.$$StockMasterTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.symbol,
      referencedTable: i5.ReadDatabaseContainer(
        $db,
      ).resultSet<i4.$StockMasterTable>('stock_master'),
      getReferencedColumn: (t) => t.symbol,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => i4.$$StockMasterTableAnnotationComposer(
            $db: $db,
            $table: i5.ReadDatabaseContainer(
              $db,
            ).resultSet<i4.$StockMasterTable>('stock_master'),
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$StockValuationTableTableManager
    extends
        i0.RootTableManager<
          i0.GeneratedDatabase,
          i1.$StockValuationTable,
          i1.StockValuationEntry,
          i1.$$StockValuationTableFilterComposer,
          i1.$$StockValuationTableOrderingComposer,
          i1.$$StockValuationTableAnnotationComposer,
          $$StockValuationTableCreateCompanionBuilder,
          $$StockValuationTableUpdateCompanionBuilder,
          (i1.StockValuationEntry, i1.$$StockValuationTableReferences),
          i1.StockValuationEntry,
          i0.PrefetchHooks Function({bool symbol})
        > {
  $$StockValuationTableTableManager(
    i0.GeneratedDatabase db,
    i1.$StockValuationTable table,
  ) : super(
        i0.TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              i1.$$StockValuationTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              i1.$$StockValuationTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () => i1
              .$$StockValuationTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                i0.Value<String> symbol = const i0.Value.absent(),
                i0.Value<DateTime> date = const i0.Value.absent(),
                i0.Value<double?> per = const i0.Value.absent(),
                i0.Value<double?> pbr = const i0.Value.absent(),
                i0.Value<double?> dividendYield = const i0.Value.absent(),
                i0.Value<int> rowid = const i0.Value.absent(),
              }) => i1.StockValuationCompanion(
                symbol: symbol,
                date: date,
                per: per,
                pbr: pbr,
                dividendYield: dividendYield,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String symbol,
                required DateTime date,
                i0.Value<double?> per = const i0.Value.absent(),
                i0.Value<double?> pbr = const i0.Value.absent(),
                i0.Value<double?> dividendYield = const i0.Value.absent(),
                i0.Value<int> rowid = const i0.Value.absent(),
              }) => i1.StockValuationCompanion.insert(
                symbol: symbol,
                date: date,
                per: per,
                pbr: pbr,
                dividendYield: dividendYield,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  i1.$$StockValuationTableReferences(db, table, e),
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
                                    .$$StockValuationTableReferences
                                    ._symbolTable(db),
                                referencedColumn: i1
                                    .$$StockValuationTableReferences
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

typedef $$StockValuationTableProcessedTableManager =
    i0.ProcessedTableManager<
      i0.GeneratedDatabase,
      i1.$StockValuationTable,
      i1.StockValuationEntry,
      i1.$$StockValuationTableFilterComposer,
      i1.$$StockValuationTableOrderingComposer,
      i1.$$StockValuationTableAnnotationComposer,
      $$StockValuationTableCreateCompanionBuilder,
      $$StockValuationTableUpdateCompanionBuilder,
      (i1.StockValuationEntry, i1.$$StockValuationTableReferences),
      i1.StockValuationEntry,
      i0.PrefetchHooks Function({bool symbol})
    >;
typedef $$MarginTradingTableCreateCompanionBuilder =
    i1.MarginTradingCompanion Function({
      required String symbol,
      required DateTime date,
      i0.Value<double?> marginBuy,
      i0.Value<double?> marginSell,
      i0.Value<double?> marginBalance,
      i0.Value<double?> shortBuy,
      i0.Value<double?> shortSell,
      i0.Value<double?> shortBalance,
      i0.Value<int> rowid,
    });
typedef $$MarginTradingTableUpdateCompanionBuilder =
    i1.MarginTradingCompanion Function({
      i0.Value<String> symbol,
      i0.Value<DateTime> date,
      i0.Value<double?> marginBuy,
      i0.Value<double?> marginSell,
      i0.Value<double?> marginBalance,
      i0.Value<double?> shortBuy,
      i0.Value<double?> shortSell,
      i0.Value<double?> shortBalance,
      i0.Value<int> rowid,
    });

final class $$MarginTradingTableReferences
    extends
        i0.BaseReferences<
          i0.GeneratedDatabase,
          i1.$MarginTradingTable,
          i1.MarginTradingEntry
        > {
  $$MarginTradingTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static i4.$StockMasterTable _symbolTable(i0.GeneratedDatabase db) =>
      i5.ReadDatabaseContainer(db)
          .resultSet<i4.$StockMasterTable>('stock_master')
          .createAlias(
            i0.$_aliasNameGenerator(
              i5.ReadDatabaseContainer(
                db,
              ).resultSet<i1.$MarginTradingTable>('margin_trading').symbol,
              i5.ReadDatabaseContainer(
                db,
              ).resultSet<i4.$StockMasterTable>('stock_master').symbol,
            ),
          );

  i4.$$StockMasterTableProcessedTableManager get symbol {
    final $_column = $_itemColumn<String>('symbol')!;

    final manager = i4
        .$$StockMasterTableTableManager(
          $_db,
          i5.ReadDatabaseContainer(
            $_db,
          ).resultSet<i4.$StockMasterTable>('stock_master'),
        )
        .filter((f) => f.symbol.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_symbolTable($_db));
    if (item == null) return manager;
    return i0.ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$MarginTradingTableFilterComposer
    extends i0.Composer<i0.GeneratedDatabase, i1.$MarginTradingTable> {
  $$MarginTradingTableFilterComposer({
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

  i0.ColumnFilters<double> get marginBuy => $composableBuilder(
    column: $table.marginBuy,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<double> get marginSell => $composableBuilder(
    column: $table.marginSell,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<double> get marginBalance => $composableBuilder(
    column: $table.marginBalance,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<double> get shortBuy => $composableBuilder(
    column: $table.shortBuy,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<double> get shortSell => $composableBuilder(
    column: $table.shortSell,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<double> get shortBalance => $composableBuilder(
    column: $table.shortBalance,
    builder: (column) => i0.ColumnFilters(column),
  );

  i4.$$StockMasterTableFilterComposer get symbol {
    final i4.$$StockMasterTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.symbol,
      referencedTable: i5.ReadDatabaseContainer(
        $db,
      ).resultSet<i4.$StockMasterTable>('stock_master'),
      getReferencedColumn: (t) => t.symbol,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => i4.$$StockMasterTableFilterComposer(
            $db: $db,
            $table: i5.ReadDatabaseContainer(
              $db,
            ).resultSet<i4.$StockMasterTable>('stock_master'),
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$MarginTradingTableOrderingComposer
    extends i0.Composer<i0.GeneratedDatabase, i1.$MarginTradingTable> {
  $$MarginTradingTableOrderingComposer({
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

  i0.ColumnOrderings<double> get marginBuy => $composableBuilder(
    column: $table.marginBuy,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<double> get marginSell => $composableBuilder(
    column: $table.marginSell,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<double> get marginBalance => $composableBuilder(
    column: $table.marginBalance,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<double> get shortBuy => $composableBuilder(
    column: $table.shortBuy,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<double> get shortSell => $composableBuilder(
    column: $table.shortSell,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<double> get shortBalance => $composableBuilder(
    column: $table.shortBalance,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i4.$$StockMasterTableOrderingComposer get symbol {
    final i4.$$StockMasterTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.symbol,
      referencedTable: i5.ReadDatabaseContainer(
        $db,
      ).resultSet<i4.$StockMasterTable>('stock_master'),
      getReferencedColumn: (t) => t.symbol,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => i4.$$StockMasterTableOrderingComposer(
            $db: $db,
            $table: i5.ReadDatabaseContainer(
              $db,
            ).resultSet<i4.$StockMasterTable>('stock_master'),
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$MarginTradingTableAnnotationComposer
    extends i0.Composer<i0.GeneratedDatabase, i1.$MarginTradingTable> {
  $$MarginTradingTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  i0.GeneratedColumn<DateTime> get date =>
      $composableBuilder(column: $table.date, builder: (column) => column);

  i0.GeneratedColumn<double> get marginBuy =>
      $composableBuilder(column: $table.marginBuy, builder: (column) => column);

  i0.GeneratedColumn<double> get marginSell => $composableBuilder(
    column: $table.marginSell,
    builder: (column) => column,
  );

  i0.GeneratedColumn<double> get marginBalance => $composableBuilder(
    column: $table.marginBalance,
    builder: (column) => column,
  );

  i0.GeneratedColumn<double> get shortBuy =>
      $composableBuilder(column: $table.shortBuy, builder: (column) => column);

  i0.GeneratedColumn<double> get shortSell =>
      $composableBuilder(column: $table.shortSell, builder: (column) => column);

  i0.GeneratedColumn<double> get shortBalance => $composableBuilder(
    column: $table.shortBalance,
    builder: (column) => column,
  );

  i4.$$StockMasterTableAnnotationComposer get symbol {
    final i4.$$StockMasterTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.symbol,
      referencedTable: i5.ReadDatabaseContainer(
        $db,
      ).resultSet<i4.$StockMasterTable>('stock_master'),
      getReferencedColumn: (t) => t.symbol,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => i4.$$StockMasterTableAnnotationComposer(
            $db: $db,
            $table: i5.ReadDatabaseContainer(
              $db,
            ).resultSet<i4.$StockMasterTable>('stock_master'),
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$MarginTradingTableTableManager
    extends
        i0.RootTableManager<
          i0.GeneratedDatabase,
          i1.$MarginTradingTable,
          i1.MarginTradingEntry,
          i1.$$MarginTradingTableFilterComposer,
          i1.$$MarginTradingTableOrderingComposer,
          i1.$$MarginTradingTableAnnotationComposer,
          $$MarginTradingTableCreateCompanionBuilder,
          $$MarginTradingTableUpdateCompanionBuilder,
          (i1.MarginTradingEntry, i1.$$MarginTradingTableReferences),
          i1.MarginTradingEntry,
          i0.PrefetchHooks Function({bool symbol})
        > {
  $$MarginTradingTableTableManager(
    i0.GeneratedDatabase db,
    i1.$MarginTradingTable table,
  ) : super(
        i0.TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              i1.$$MarginTradingTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              i1.$$MarginTradingTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              i1.$$MarginTradingTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                i0.Value<String> symbol = const i0.Value.absent(),
                i0.Value<DateTime> date = const i0.Value.absent(),
                i0.Value<double?> marginBuy = const i0.Value.absent(),
                i0.Value<double?> marginSell = const i0.Value.absent(),
                i0.Value<double?> marginBalance = const i0.Value.absent(),
                i0.Value<double?> shortBuy = const i0.Value.absent(),
                i0.Value<double?> shortSell = const i0.Value.absent(),
                i0.Value<double?> shortBalance = const i0.Value.absent(),
                i0.Value<int> rowid = const i0.Value.absent(),
              }) => i1.MarginTradingCompanion(
                symbol: symbol,
                date: date,
                marginBuy: marginBuy,
                marginSell: marginSell,
                marginBalance: marginBalance,
                shortBuy: shortBuy,
                shortSell: shortSell,
                shortBalance: shortBalance,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String symbol,
                required DateTime date,
                i0.Value<double?> marginBuy = const i0.Value.absent(),
                i0.Value<double?> marginSell = const i0.Value.absent(),
                i0.Value<double?> marginBalance = const i0.Value.absent(),
                i0.Value<double?> shortBuy = const i0.Value.absent(),
                i0.Value<double?> shortSell = const i0.Value.absent(),
                i0.Value<double?> shortBalance = const i0.Value.absent(),
                i0.Value<int> rowid = const i0.Value.absent(),
              }) => i1.MarginTradingCompanion.insert(
                symbol: symbol,
                date: date,
                marginBuy: marginBuy,
                marginSell: marginSell,
                marginBalance: marginBalance,
                shortBuy: shortBuy,
                shortSell: shortSell,
                shortBalance: shortBalance,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  i1.$$MarginTradingTableReferences(db, table, e),
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
                                    .$$MarginTradingTableReferences
                                    ._symbolTable(db),
                                referencedColumn: i1
                                    .$$MarginTradingTableReferences
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

typedef $$MarginTradingTableProcessedTableManager =
    i0.ProcessedTableManager<
      i0.GeneratedDatabase,
      i1.$MarginTradingTable,
      i1.MarginTradingEntry,
      i1.$$MarginTradingTableFilterComposer,
      i1.$$MarginTradingTableOrderingComposer,
      i1.$$MarginTradingTableAnnotationComposer,
      $$MarginTradingTableCreateCompanionBuilder,
      $$MarginTradingTableUpdateCompanionBuilder,
      (i1.MarginTradingEntry, i1.$$MarginTradingTableReferences),
      i1.MarginTradingEntry,
      i0.PrefetchHooks Function({bool symbol})
    >;
typedef $$TradingWarningTableCreateCompanionBuilder =
    i1.TradingWarningCompanion Function({
      required String symbol,
      required DateTime date,
      required String warningType,
      i0.Value<String?> reasonCode,
      i0.Value<String?> reasonDescription,
      i0.Value<String?> disposalMeasures,
      i0.Value<DateTime?> disposalStartDate,
      i0.Value<DateTime?> disposalEndDate,
      i0.Value<bool> isActive,
      i0.Value<int> rowid,
    });
typedef $$TradingWarningTableUpdateCompanionBuilder =
    i1.TradingWarningCompanion Function({
      i0.Value<String> symbol,
      i0.Value<DateTime> date,
      i0.Value<String> warningType,
      i0.Value<String?> reasonCode,
      i0.Value<String?> reasonDescription,
      i0.Value<String?> disposalMeasures,
      i0.Value<DateTime?> disposalStartDate,
      i0.Value<DateTime?> disposalEndDate,
      i0.Value<bool> isActive,
      i0.Value<int> rowid,
    });

final class $$TradingWarningTableReferences
    extends
        i0.BaseReferences<
          i0.GeneratedDatabase,
          i1.$TradingWarningTable,
          i1.TradingWarningEntry
        > {
  $$TradingWarningTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static i4.$StockMasterTable _symbolTable(i0.GeneratedDatabase db) =>
      i5.ReadDatabaseContainer(db)
          .resultSet<i4.$StockMasterTable>('stock_master')
          .createAlias(
            i0.$_aliasNameGenerator(
              i5.ReadDatabaseContainer(
                db,
              ).resultSet<i1.$TradingWarningTable>('trading_warning').symbol,
              i5.ReadDatabaseContainer(
                db,
              ).resultSet<i4.$StockMasterTable>('stock_master').symbol,
            ),
          );

  i4.$$StockMasterTableProcessedTableManager get symbol {
    final $_column = $_itemColumn<String>('symbol')!;

    final manager = i4
        .$$StockMasterTableTableManager(
          $_db,
          i5.ReadDatabaseContainer(
            $_db,
          ).resultSet<i4.$StockMasterTable>('stock_master'),
        )
        .filter((f) => f.symbol.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_symbolTable($_db));
    if (item == null) return manager;
    return i0.ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$TradingWarningTableFilterComposer
    extends i0.Composer<i0.GeneratedDatabase, i1.$TradingWarningTable> {
  $$TradingWarningTableFilterComposer({
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

  i0.ColumnFilters<String> get warningType => $composableBuilder(
    column: $table.warningType,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<String> get reasonCode => $composableBuilder(
    column: $table.reasonCode,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<String> get reasonDescription => $composableBuilder(
    column: $table.reasonDescription,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<String> get disposalMeasures => $composableBuilder(
    column: $table.disposalMeasures,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<DateTime> get disposalStartDate => $composableBuilder(
    column: $table.disposalStartDate,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<DateTime> get disposalEndDate => $composableBuilder(
    column: $table.disposalEndDate,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<bool> get isActive => $composableBuilder(
    column: $table.isActive,
    builder: (column) => i0.ColumnFilters(column),
  );

  i4.$$StockMasterTableFilterComposer get symbol {
    final i4.$$StockMasterTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.symbol,
      referencedTable: i5.ReadDatabaseContainer(
        $db,
      ).resultSet<i4.$StockMasterTable>('stock_master'),
      getReferencedColumn: (t) => t.symbol,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => i4.$$StockMasterTableFilterComposer(
            $db: $db,
            $table: i5.ReadDatabaseContainer(
              $db,
            ).resultSet<i4.$StockMasterTable>('stock_master'),
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TradingWarningTableOrderingComposer
    extends i0.Composer<i0.GeneratedDatabase, i1.$TradingWarningTable> {
  $$TradingWarningTableOrderingComposer({
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

  i0.ColumnOrderings<String> get warningType => $composableBuilder(
    column: $table.warningType,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<String> get reasonCode => $composableBuilder(
    column: $table.reasonCode,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<String> get reasonDescription => $composableBuilder(
    column: $table.reasonDescription,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<String> get disposalMeasures => $composableBuilder(
    column: $table.disposalMeasures,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<DateTime> get disposalStartDate => $composableBuilder(
    column: $table.disposalStartDate,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<DateTime> get disposalEndDate => $composableBuilder(
    column: $table.disposalEndDate,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<bool> get isActive => $composableBuilder(
    column: $table.isActive,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i4.$$StockMasterTableOrderingComposer get symbol {
    final i4.$$StockMasterTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.symbol,
      referencedTable: i5.ReadDatabaseContainer(
        $db,
      ).resultSet<i4.$StockMasterTable>('stock_master'),
      getReferencedColumn: (t) => t.symbol,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => i4.$$StockMasterTableOrderingComposer(
            $db: $db,
            $table: i5.ReadDatabaseContainer(
              $db,
            ).resultSet<i4.$StockMasterTable>('stock_master'),
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TradingWarningTableAnnotationComposer
    extends i0.Composer<i0.GeneratedDatabase, i1.$TradingWarningTable> {
  $$TradingWarningTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  i0.GeneratedColumn<DateTime> get date =>
      $composableBuilder(column: $table.date, builder: (column) => column);

  i0.GeneratedColumn<String> get warningType => $composableBuilder(
    column: $table.warningType,
    builder: (column) => column,
  );

  i0.GeneratedColumn<String> get reasonCode => $composableBuilder(
    column: $table.reasonCode,
    builder: (column) => column,
  );

  i0.GeneratedColumn<String> get reasonDescription => $composableBuilder(
    column: $table.reasonDescription,
    builder: (column) => column,
  );

  i0.GeneratedColumn<String> get disposalMeasures => $composableBuilder(
    column: $table.disposalMeasures,
    builder: (column) => column,
  );

  i0.GeneratedColumn<DateTime> get disposalStartDate => $composableBuilder(
    column: $table.disposalStartDate,
    builder: (column) => column,
  );

  i0.GeneratedColumn<DateTime> get disposalEndDate => $composableBuilder(
    column: $table.disposalEndDate,
    builder: (column) => column,
  );

  i0.GeneratedColumn<bool> get isActive =>
      $composableBuilder(column: $table.isActive, builder: (column) => column);

  i4.$$StockMasterTableAnnotationComposer get symbol {
    final i4.$$StockMasterTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.symbol,
      referencedTable: i5.ReadDatabaseContainer(
        $db,
      ).resultSet<i4.$StockMasterTable>('stock_master'),
      getReferencedColumn: (t) => t.symbol,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => i4.$$StockMasterTableAnnotationComposer(
            $db: $db,
            $table: i5.ReadDatabaseContainer(
              $db,
            ).resultSet<i4.$StockMasterTable>('stock_master'),
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TradingWarningTableTableManager
    extends
        i0.RootTableManager<
          i0.GeneratedDatabase,
          i1.$TradingWarningTable,
          i1.TradingWarningEntry,
          i1.$$TradingWarningTableFilterComposer,
          i1.$$TradingWarningTableOrderingComposer,
          i1.$$TradingWarningTableAnnotationComposer,
          $$TradingWarningTableCreateCompanionBuilder,
          $$TradingWarningTableUpdateCompanionBuilder,
          (i1.TradingWarningEntry, i1.$$TradingWarningTableReferences),
          i1.TradingWarningEntry,
          i0.PrefetchHooks Function({bool symbol})
        > {
  $$TradingWarningTableTableManager(
    i0.GeneratedDatabase db,
    i1.$TradingWarningTable table,
  ) : super(
        i0.TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              i1.$$TradingWarningTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              i1.$$TradingWarningTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () => i1
              .$$TradingWarningTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                i0.Value<String> symbol = const i0.Value.absent(),
                i0.Value<DateTime> date = const i0.Value.absent(),
                i0.Value<String> warningType = const i0.Value.absent(),
                i0.Value<String?> reasonCode = const i0.Value.absent(),
                i0.Value<String?> reasonDescription = const i0.Value.absent(),
                i0.Value<String?> disposalMeasures = const i0.Value.absent(),
                i0.Value<DateTime?> disposalStartDate = const i0.Value.absent(),
                i0.Value<DateTime?> disposalEndDate = const i0.Value.absent(),
                i0.Value<bool> isActive = const i0.Value.absent(),
                i0.Value<int> rowid = const i0.Value.absent(),
              }) => i1.TradingWarningCompanion(
                symbol: symbol,
                date: date,
                warningType: warningType,
                reasonCode: reasonCode,
                reasonDescription: reasonDescription,
                disposalMeasures: disposalMeasures,
                disposalStartDate: disposalStartDate,
                disposalEndDate: disposalEndDate,
                isActive: isActive,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String symbol,
                required DateTime date,
                required String warningType,
                i0.Value<String?> reasonCode = const i0.Value.absent(),
                i0.Value<String?> reasonDescription = const i0.Value.absent(),
                i0.Value<String?> disposalMeasures = const i0.Value.absent(),
                i0.Value<DateTime?> disposalStartDate = const i0.Value.absent(),
                i0.Value<DateTime?> disposalEndDate = const i0.Value.absent(),
                i0.Value<bool> isActive = const i0.Value.absent(),
                i0.Value<int> rowid = const i0.Value.absent(),
              }) => i1.TradingWarningCompanion.insert(
                symbol: symbol,
                date: date,
                warningType: warningType,
                reasonCode: reasonCode,
                reasonDescription: reasonDescription,
                disposalMeasures: disposalMeasures,
                disposalStartDate: disposalStartDate,
                disposalEndDate: disposalEndDate,
                isActive: isActive,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  i1.$$TradingWarningTableReferences(db, table, e),
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
                                    .$$TradingWarningTableReferences
                                    ._symbolTable(db),
                                referencedColumn: i1
                                    .$$TradingWarningTableReferences
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

typedef $$TradingWarningTableProcessedTableManager =
    i0.ProcessedTableManager<
      i0.GeneratedDatabase,
      i1.$TradingWarningTable,
      i1.TradingWarningEntry,
      i1.$$TradingWarningTableFilterComposer,
      i1.$$TradingWarningTableOrderingComposer,
      i1.$$TradingWarningTableAnnotationComposer,
      $$TradingWarningTableCreateCompanionBuilder,
      $$TradingWarningTableUpdateCompanionBuilder,
      (i1.TradingWarningEntry, i1.$$TradingWarningTableReferences),
      i1.TradingWarningEntry,
      i0.PrefetchHooks Function({bool symbol})
    >;
typedef $$InsiderHoldingTableCreateCompanionBuilder =
    i1.InsiderHoldingCompanion Function({
      required String symbol,
      required DateTime date,
      i0.Value<double?> directorShares,
      i0.Value<double?> supervisorShares,
      i0.Value<double?> managerShares,
      i0.Value<double?> insiderRatio,
      i0.Value<double?> pledgeRatio,
      i0.Value<double?> sharesChange,
      i0.Value<double?> sharesIssued,
      i0.Value<int> rowid,
    });
typedef $$InsiderHoldingTableUpdateCompanionBuilder =
    i1.InsiderHoldingCompanion Function({
      i0.Value<String> symbol,
      i0.Value<DateTime> date,
      i0.Value<double?> directorShares,
      i0.Value<double?> supervisorShares,
      i0.Value<double?> managerShares,
      i0.Value<double?> insiderRatio,
      i0.Value<double?> pledgeRatio,
      i0.Value<double?> sharesChange,
      i0.Value<double?> sharesIssued,
      i0.Value<int> rowid,
    });

final class $$InsiderHoldingTableReferences
    extends
        i0.BaseReferences<
          i0.GeneratedDatabase,
          i1.$InsiderHoldingTable,
          i1.InsiderHoldingEntry
        > {
  $$InsiderHoldingTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static i4.$StockMasterTable _symbolTable(i0.GeneratedDatabase db) =>
      i5.ReadDatabaseContainer(db)
          .resultSet<i4.$StockMasterTable>('stock_master')
          .createAlias(
            i0.$_aliasNameGenerator(
              i5.ReadDatabaseContainer(
                db,
              ).resultSet<i1.$InsiderHoldingTable>('insider_holding').symbol,
              i5.ReadDatabaseContainer(
                db,
              ).resultSet<i4.$StockMasterTable>('stock_master').symbol,
            ),
          );

  i4.$$StockMasterTableProcessedTableManager get symbol {
    final $_column = $_itemColumn<String>('symbol')!;

    final manager = i4
        .$$StockMasterTableTableManager(
          $_db,
          i5.ReadDatabaseContainer(
            $_db,
          ).resultSet<i4.$StockMasterTable>('stock_master'),
        )
        .filter((f) => f.symbol.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_symbolTable($_db));
    if (item == null) return manager;
    return i0.ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$InsiderHoldingTableFilterComposer
    extends i0.Composer<i0.GeneratedDatabase, i1.$InsiderHoldingTable> {
  $$InsiderHoldingTableFilterComposer({
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

  i0.ColumnFilters<double> get directorShares => $composableBuilder(
    column: $table.directorShares,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<double> get supervisorShares => $composableBuilder(
    column: $table.supervisorShares,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<double> get managerShares => $composableBuilder(
    column: $table.managerShares,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<double> get insiderRatio => $composableBuilder(
    column: $table.insiderRatio,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<double> get pledgeRatio => $composableBuilder(
    column: $table.pledgeRatio,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<double> get sharesChange => $composableBuilder(
    column: $table.sharesChange,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<double> get sharesIssued => $composableBuilder(
    column: $table.sharesIssued,
    builder: (column) => i0.ColumnFilters(column),
  );

  i4.$$StockMasterTableFilterComposer get symbol {
    final i4.$$StockMasterTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.symbol,
      referencedTable: i5.ReadDatabaseContainer(
        $db,
      ).resultSet<i4.$StockMasterTable>('stock_master'),
      getReferencedColumn: (t) => t.symbol,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => i4.$$StockMasterTableFilterComposer(
            $db: $db,
            $table: i5.ReadDatabaseContainer(
              $db,
            ).resultSet<i4.$StockMasterTable>('stock_master'),
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$InsiderHoldingTableOrderingComposer
    extends i0.Composer<i0.GeneratedDatabase, i1.$InsiderHoldingTable> {
  $$InsiderHoldingTableOrderingComposer({
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

  i0.ColumnOrderings<double> get directorShares => $composableBuilder(
    column: $table.directorShares,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<double> get supervisorShares => $composableBuilder(
    column: $table.supervisorShares,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<double> get managerShares => $composableBuilder(
    column: $table.managerShares,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<double> get insiderRatio => $composableBuilder(
    column: $table.insiderRatio,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<double> get pledgeRatio => $composableBuilder(
    column: $table.pledgeRatio,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<double> get sharesChange => $composableBuilder(
    column: $table.sharesChange,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<double> get sharesIssued => $composableBuilder(
    column: $table.sharesIssued,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i4.$$StockMasterTableOrderingComposer get symbol {
    final i4.$$StockMasterTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.symbol,
      referencedTable: i5.ReadDatabaseContainer(
        $db,
      ).resultSet<i4.$StockMasterTable>('stock_master'),
      getReferencedColumn: (t) => t.symbol,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => i4.$$StockMasterTableOrderingComposer(
            $db: $db,
            $table: i5.ReadDatabaseContainer(
              $db,
            ).resultSet<i4.$StockMasterTable>('stock_master'),
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$InsiderHoldingTableAnnotationComposer
    extends i0.Composer<i0.GeneratedDatabase, i1.$InsiderHoldingTable> {
  $$InsiderHoldingTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  i0.GeneratedColumn<DateTime> get date =>
      $composableBuilder(column: $table.date, builder: (column) => column);

  i0.GeneratedColumn<double> get directorShares => $composableBuilder(
    column: $table.directorShares,
    builder: (column) => column,
  );

  i0.GeneratedColumn<double> get supervisorShares => $composableBuilder(
    column: $table.supervisorShares,
    builder: (column) => column,
  );

  i0.GeneratedColumn<double> get managerShares => $composableBuilder(
    column: $table.managerShares,
    builder: (column) => column,
  );

  i0.GeneratedColumn<double> get insiderRatio => $composableBuilder(
    column: $table.insiderRatio,
    builder: (column) => column,
  );

  i0.GeneratedColumn<double> get pledgeRatio => $composableBuilder(
    column: $table.pledgeRatio,
    builder: (column) => column,
  );

  i0.GeneratedColumn<double> get sharesChange => $composableBuilder(
    column: $table.sharesChange,
    builder: (column) => column,
  );

  i0.GeneratedColumn<double> get sharesIssued => $composableBuilder(
    column: $table.sharesIssued,
    builder: (column) => column,
  );

  i4.$$StockMasterTableAnnotationComposer get symbol {
    final i4.$$StockMasterTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.symbol,
      referencedTable: i5.ReadDatabaseContainer(
        $db,
      ).resultSet<i4.$StockMasterTable>('stock_master'),
      getReferencedColumn: (t) => t.symbol,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => i4.$$StockMasterTableAnnotationComposer(
            $db: $db,
            $table: i5.ReadDatabaseContainer(
              $db,
            ).resultSet<i4.$StockMasterTable>('stock_master'),
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$InsiderHoldingTableTableManager
    extends
        i0.RootTableManager<
          i0.GeneratedDatabase,
          i1.$InsiderHoldingTable,
          i1.InsiderHoldingEntry,
          i1.$$InsiderHoldingTableFilterComposer,
          i1.$$InsiderHoldingTableOrderingComposer,
          i1.$$InsiderHoldingTableAnnotationComposer,
          $$InsiderHoldingTableCreateCompanionBuilder,
          $$InsiderHoldingTableUpdateCompanionBuilder,
          (i1.InsiderHoldingEntry, i1.$$InsiderHoldingTableReferences),
          i1.InsiderHoldingEntry,
          i0.PrefetchHooks Function({bool symbol})
        > {
  $$InsiderHoldingTableTableManager(
    i0.GeneratedDatabase db,
    i1.$InsiderHoldingTable table,
  ) : super(
        i0.TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              i1.$$InsiderHoldingTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              i1.$$InsiderHoldingTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () => i1
              .$$InsiderHoldingTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                i0.Value<String> symbol = const i0.Value.absent(),
                i0.Value<DateTime> date = const i0.Value.absent(),
                i0.Value<double?> directorShares = const i0.Value.absent(),
                i0.Value<double?> supervisorShares = const i0.Value.absent(),
                i0.Value<double?> managerShares = const i0.Value.absent(),
                i0.Value<double?> insiderRatio = const i0.Value.absent(),
                i0.Value<double?> pledgeRatio = const i0.Value.absent(),
                i0.Value<double?> sharesChange = const i0.Value.absent(),
                i0.Value<double?> sharesIssued = const i0.Value.absent(),
                i0.Value<int> rowid = const i0.Value.absent(),
              }) => i1.InsiderHoldingCompanion(
                symbol: symbol,
                date: date,
                directorShares: directorShares,
                supervisorShares: supervisorShares,
                managerShares: managerShares,
                insiderRatio: insiderRatio,
                pledgeRatio: pledgeRatio,
                sharesChange: sharesChange,
                sharesIssued: sharesIssued,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String symbol,
                required DateTime date,
                i0.Value<double?> directorShares = const i0.Value.absent(),
                i0.Value<double?> supervisorShares = const i0.Value.absent(),
                i0.Value<double?> managerShares = const i0.Value.absent(),
                i0.Value<double?> insiderRatio = const i0.Value.absent(),
                i0.Value<double?> pledgeRatio = const i0.Value.absent(),
                i0.Value<double?> sharesChange = const i0.Value.absent(),
                i0.Value<double?> sharesIssued = const i0.Value.absent(),
                i0.Value<int> rowid = const i0.Value.absent(),
              }) => i1.InsiderHoldingCompanion.insert(
                symbol: symbol,
                date: date,
                directorShares: directorShares,
                supervisorShares: supervisorShares,
                managerShares: managerShares,
                insiderRatio: insiderRatio,
                pledgeRatio: pledgeRatio,
                sharesChange: sharesChange,
                sharesIssued: sharesIssued,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  i1.$$InsiderHoldingTableReferences(db, table, e),
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
                                    .$$InsiderHoldingTableReferences
                                    ._symbolTable(db),
                                referencedColumn: i1
                                    .$$InsiderHoldingTableReferences
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

typedef $$InsiderHoldingTableProcessedTableManager =
    i0.ProcessedTableManager<
      i0.GeneratedDatabase,
      i1.$InsiderHoldingTable,
      i1.InsiderHoldingEntry,
      i1.$$InsiderHoldingTableFilterComposer,
      i1.$$InsiderHoldingTableOrderingComposer,
      i1.$$InsiderHoldingTableAnnotationComposer,
      $$InsiderHoldingTableCreateCompanionBuilder,
      $$InsiderHoldingTableUpdateCompanionBuilder,
      (i1.InsiderHoldingEntry, i1.$$InsiderHoldingTableReferences),
      i1.InsiderHoldingEntry,
      i0.PrefetchHooks Function({bool symbol})
    >;
typedef $$InsiderTransferTableCreateCompanionBuilder =
    i1.InsiderTransferCompanion Function({
      required String symbol,
      required DateTime reportDate,
      required String identity,
      required String name,
      required String transferMethod,
      required int transferShares,
      required int currentHolding,
      i0.Value<DateTime?> validPeriodStart,
      i0.Value<DateTime?> validPeriodEnd,
      i0.Value<int> rowid,
    });
typedef $$InsiderTransferTableUpdateCompanionBuilder =
    i1.InsiderTransferCompanion Function({
      i0.Value<String> symbol,
      i0.Value<DateTime> reportDate,
      i0.Value<String> identity,
      i0.Value<String> name,
      i0.Value<String> transferMethod,
      i0.Value<int> transferShares,
      i0.Value<int> currentHolding,
      i0.Value<DateTime?> validPeriodStart,
      i0.Value<DateTime?> validPeriodEnd,
      i0.Value<int> rowid,
    });

final class $$InsiderTransferTableReferences
    extends
        i0.BaseReferences<
          i0.GeneratedDatabase,
          i1.$InsiderTransferTable,
          i1.InsiderTransferEntry
        > {
  $$InsiderTransferTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static i4.$StockMasterTable _symbolTable(i0.GeneratedDatabase db) =>
      i5.ReadDatabaseContainer(db)
          .resultSet<i4.$StockMasterTable>('stock_master')
          .createAlias(
            i0.$_aliasNameGenerator(
              i5.ReadDatabaseContainer(
                db,
              ).resultSet<i1.$InsiderTransferTable>('insider_transfer').symbol,
              i5.ReadDatabaseContainer(
                db,
              ).resultSet<i4.$StockMasterTable>('stock_master').symbol,
            ),
          );

  i4.$$StockMasterTableProcessedTableManager get symbol {
    final $_column = $_itemColumn<String>('symbol')!;

    final manager = i4
        .$$StockMasterTableTableManager(
          $_db,
          i5.ReadDatabaseContainer(
            $_db,
          ).resultSet<i4.$StockMasterTable>('stock_master'),
        )
        .filter((f) => f.symbol.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_symbolTable($_db));
    if (item == null) return manager;
    return i0.ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$InsiderTransferTableFilterComposer
    extends i0.Composer<i0.GeneratedDatabase, i1.$InsiderTransferTable> {
  $$InsiderTransferTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  i0.ColumnFilters<DateTime> get reportDate => $composableBuilder(
    column: $table.reportDate,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<String> get identity => $composableBuilder(
    column: $table.identity,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<String> get transferMethod => $composableBuilder(
    column: $table.transferMethod,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<int> get transferShares => $composableBuilder(
    column: $table.transferShares,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<int> get currentHolding => $composableBuilder(
    column: $table.currentHolding,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<DateTime> get validPeriodStart => $composableBuilder(
    column: $table.validPeriodStart,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<DateTime> get validPeriodEnd => $composableBuilder(
    column: $table.validPeriodEnd,
    builder: (column) => i0.ColumnFilters(column),
  );

  i4.$$StockMasterTableFilterComposer get symbol {
    final i4.$$StockMasterTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.symbol,
      referencedTable: i5.ReadDatabaseContainer(
        $db,
      ).resultSet<i4.$StockMasterTable>('stock_master'),
      getReferencedColumn: (t) => t.symbol,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => i4.$$StockMasterTableFilterComposer(
            $db: $db,
            $table: i5.ReadDatabaseContainer(
              $db,
            ).resultSet<i4.$StockMasterTable>('stock_master'),
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$InsiderTransferTableOrderingComposer
    extends i0.Composer<i0.GeneratedDatabase, i1.$InsiderTransferTable> {
  $$InsiderTransferTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  i0.ColumnOrderings<DateTime> get reportDate => $composableBuilder(
    column: $table.reportDate,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<String> get identity => $composableBuilder(
    column: $table.identity,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<String> get transferMethod => $composableBuilder(
    column: $table.transferMethod,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<int> get transferShares => $composableBuilder(
    column: $table.transferShares,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<int> get currentHolding => $composableBuilder(
    column: $table.currentHolding,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<DateTime> get validPeriodStart => $composableBuilder(
    column: $table.validPeriodStart,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<DateTime> get validPeriodEnd => $composableBuilder(
    column: $table.validPeriodEnd,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i4.$$StockMasterTableOrderingComposer get symbol {
    final i4.$$StockMasterTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.symbol,
      referencedTable: i5.ReadDatabaseContainer(
        $db,
      ).resultSet<i4.$StockMasterTable>('stock_master'),
      getReferencedColumn: (t) => t.symbol,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => i4.$$StockMasterTableOrderingComposer(
            $db: $db,
            $table: i5.ReadDatabaseContainer(
              $db,
            ).resultSet<i4.$StockMasterTable>('stock_master'),
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$InsiderTransferTableAnnotationComposer
    extends i0.Composer<i0.GeneratedDatabase, i1.$InsiderTransferTable> {
  $$InsiderTransferTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  i0.GeneratedColumn<DateTime> get reportDate => $composableBuilder(
    column: $table.reportDate,
    builder: (column) => column,
  );

  i0.GeneratedColumn<String> get identity =>
      $composableBuilder(column: $table.identity, builder: (column) => column);

  i0.GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  i0.GeneratedColumn<String> get transferMethod => $composableBuilder(
    column: $table.transferMethod,
    builder: (column) => column,
  );

  i0.GeneratedColumn<int> get transferShares => $composableBuilder(
    column: $table.transferShares,
    builder: (column) => column,
  );

  i0.GeneratedColumn<int> get currentHolding => $composableBuilder(
    column: $table.currentHolding,
    builder: (column) => column,
  );

  i0.GeneratedColumn<DateTime> get validPeriodStart => $composableBuilder(
    column: $table.validPeriodStart,
    builder: (column) => column,
  );

  i0.GeneratedColumn<DateTime> get validPeriodEnd => $composableBuilder(
    column: $table.validPeriodEnd,
    builder: (column) => column,
  );

  i4.$$StockMasterTableAnnotationComposer get symbol {
    final i4.$$StockMasterTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.symbol,
      referencedTable: i5.ReadDatabaseContainer(
        $db,
      ).resultSet<i4.$StockMasterTable>('stock_master'),
      getReferencedColumn: (t) => t.symbol,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => i4.$$StockMasterTableAnnotationComposer(
            $db: $db,
            $table: i5.ReadDatabaseContainer(
              $db,
            ).resultSet<i4.$StockMasterTable>('stock_master'),
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$InsiderTransferTableTableManager
    extends
        i0.RootTableManager<
          i0.GeneratedDatabase,
          i1.$InsiderTransferTable,
          i1.InsiderTransferEntry,
          i1.$$InsiderTransferTableFilterComposer,
          i1.$$InsiderTransferTableOrderingComposer,
          i1.$$InsiderTransferTableAnnotationComposer,
          $$InsiderTransferTableCreateCompanionBuilder,
          $$InsiderTransferTableUpdateCompanionBuilder,
          (i1.InsiderTransferEntry, i1.$$InsiderTransferTableReferences),
          i1.InsiderTransferEntry,
          i0.PrefetchHooks Function({bool symbol})
        > {
  $$InsiderTransferTableTableManager(
    i0.GeneratedDatabase db,
    i1.$InsiderTransferTable table,
  ) : super(
        i0.TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              i1.$$InsiderTransferTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              i1.$$InsiderTransferTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () => i1
              .$$InsiderTransferTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                i0.Value<String> symbol = const i0.Value.absent(),
                i0.Value<DateTime> reportDate = const i0.Value.absent(),
                i0.Value<String> identity = const i0.Value.absent(),
                i0.Value<String> name = const i0.Value.absent(),
                i0.Value<String> transferMethod = const i0.Value.absent(),
                i0.Value<int> transferShares = const i0.Value.absent(),
                i0.Value<int> currentHolding = const i0.Value.absent(),
                i0.Value<DateTime?> validPeriodStart = const i0.Value.absent(),
                i0.Value<DateTime?> validPeriodEnd = const i0.Value.absent(),
                i0.Value<int> rowid = const i0.Value.absent(),
              }) => i1.InsiderTransferCompanion(
                symbol: symbol,
                reportDate: reportDate,
                identity: identity,
                name: name,
                transferMethod: transferMethod,
                transferShares: transferShares,
                currentHolding: currentHolding,
                validPeriodStart: validPeriodStart,
                validPeriodEnd: validPeriodEnd,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String symbol,
                required DateTime reportDate,
                required String identity,
                required String name,
                required String transferMethod,
                required int transferShares,
                required int currentHolding,
                i0.Value<DateTime?> validPeriodStart = const i0.Value.absent(),
                i0.Value<DateTime?> validPeriodEnd = const i0.Value.absent(),
                i0.Value<int> rowid = const i0.Value.absent(),
              }) => i1.InsiderTransferCompanion.insert(
                symbol: symbol,
                reportDate: reportDate,
                identity: identity,
                name: name,
                transferMethod: transferMethod,
                transferShares: transferShares,
                currentHolding: currentHolding,
                validPeriodStart: validPeriodStart,
                validPeriodEnd: validPeriodEnd,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  i1.$$InsiderTransferTableReferences(db, table, e),
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
                                    .$$InsiderTransferTableReferences
                                    ._symbolTable(db),
                                referencedColumn: i1
                                    .$$InsiderTransferTableReferences
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

typedef $$InsiderTransferTableProcessedTableManager =
    i0.ProcessedTableManager<
      i0.GeneratedDatabase,
      i1.$InsiderTransferTable,
      i1.InsiderTransferEntry,
      i1.$$InsiderTransferTableFilterComposer,
      i1.$$InsiderTransferTableOrderingComposer,
      i1.$$InsiderTransferTableAnnotationComposer,
      $$InsiderTransferTableCreateCompanionBuilder,
      $$InsiderTransferTableUpdateCompanionBuilder,
      (i1.InsiderTransferEntry, i1.$$InsiderTransferTableReferences),
      i1.InsiderTransferEntry,
      i0.PrefetchHooks Function({bool symbol})
    >;
i0.Index get idxShareholdingDate => i0.Index(
  'idx_shareholding_date',
  'CREATE INDEX idx_shareholding_date ON shareholding (date)',
);

class $ShareholdingTable extends i2.Shareholding
    with i0.TableInfo<$ShareholdingTable, i1.ShareholdingEntry> {
  @override
  final i0.GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ShareholdingTable(this.attachedDatabase, [this._alias]);
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
  static const i0.VerificationMeta _foreignRemainingSharesMeta =
      const i0.VerificationMeta('foreignRemainingShares');
  @override
  late final i0.GeneratedColumn<double> foreignRemainingShares =
      i0.GeneratedColumn<double>(
        'foreign_remaining_shares',
        aliasedName,
        true,
        type: i0.DriftSqlType.double,
        requiredDuringInsert: false,
      );
  static const i0.VerificationMeta _foreignSharesRatioMeta =
      const i0.VerificationMeta('foreignSharesRatio');
  @override
  late final i0.GeneratedColumn<double> foreignSharesRatio =
      i0.GeneratedColumn<double>(
        'foreign_shares_ratio',
        aliasedName,
        true,
        type: i0.DriftSqlType.double,
        requiredDuringInsert: false,
      );
  static const i0.VerificationMeta _foreignUpperLimitRatioMeta =
      const i0.VerificationMeta('foreignUpperLimitRatio');
  @override
  late final i0.GeneratedColumn<double> foreignUpperLimitRatio =
      i0.GeneratedColumn<double>(
        'foreign_upper_limit_ratio',
        aliasedName,
        true,
        type: i0.DriftSqlType.double,
        requiredDuringInsert: false,
      );
  static const i0.VerificationMeta _sharesIssuedMeta =
      const i0.VerificationMeta('sharesIssued');
  @override
  late final i0.GeneratedColumn<double> sharesIssued =
      i0.GeneratedColumn<double>(
        'shares_issued',
        aliasedName,
        true,
        type: i0.DriftSqlType.double,
        requiredDuringInsert: false,
      );
  @override
  List<i0.GeneratedColumn> get $columns => [
    symbol,
    date,
    foreignRemainingShares,
    foreignSharesRatio,
    foreignUpperLimitRatio,
    sharesIssued,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'shareholding';
  @override
  i0.VerificationContext validateIntegrity(
    i0.Insertable<i1.ShareholdingEntry> instance, {
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
    if (data.containsKey('foreign_remaining_shares')) {
      context.handle(
        _foreignRemainingSharesMeta,
        foreignRemainingShares.isAcceptableOrUnknown(
          data['foreign_remaining_shares']!,
          _foreignRemainingSharesMeta,
        ),
      );
    }
    if (data.containsKey('foreign_shares_ratio')) {
      context.handle(
        _foreignSharesRatioMeta,
        foreignSharesRatio.isAcceptableOrUnknown(
          data['foreign_shares_ratio']!,
          _foreignSharesRatioMeta,
        ),
      );
    }
    if (data.containsKey('foreign_upper_limit_ratio')) {
      context.handle(
        _foreignUpperLimitRatioMeta,
        foreignUpperLimitRatio.isAcceptableOrUnknown(
          data['foreign_upper_limit_ratio']!,
          _foreignUpperLimitRatioMeta,
        ),
      );
    }
    if (data.containsKey('shares_issued')) {
      context.handle(
        _sharesIssuedMeta,
        sharesIssued.isAcceptableOrUnknown(
          data['shares_issued']!,
          _sharesIssuedMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<i0.GeneratedColumn> get $primaryKey => {symbol, date};
  @override
  i1.ShareholdingEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return i1.ShareholdingEntry(
      symbol: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.string,
        data['${effectivePrefix}symbol'],
      )!,
      date: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.dateTime,
        data['${effectivePrefix}date'],
      )!,
      foreignRemainingShares: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.double,
        data['${effectivePrefix}foreign_remaining_shares'],
      ),
      foreignSharesRatio: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.double,
        data['${effectivePrefix}foreign_shares_ratio'],
      ),
      foreignUpperLimitRatio: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.double,
        data['${effectivePrefix}foreign_upper_limit_ratio'],
      ),
      sharesIssued: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.double,
        data['${effectivePrefix}shares_issued'],
      ),
    );
  }

  @override
  $ShareholdingTable createAlias(String alias) {
    return $ShareholdingTable(attachedDatabase, alias);
  }
}

class ShareholdingEntry extends i0.DataClass
    implements i0.Insertable<i1.ShareholdingEntry> {
  /// 股票代碼
  final String symbol;

  /// 交易日期
  final DateTime date;

  /// 外資持股餘額（股）
  final double? foreignRemainingShares;

  /// 外資持股比例（%）
  final double? foreignSharesRatio;

  /// 外資持股上限比例（%）
  final double? foreignUpperLimitRatio;

  /// 已發行股數
  final double? sharesIssued;
  const ShareholdingEntry({
    required this.symbol,
    required this.date,
    this.foreignRemainingShares,
    this.foreignSharesRatio,
    this.foreignUpperLimitRatio,
    this.sharesIssued,
  });
  @override
  Map<String, i0.Expression> toColumns(bool nullToAbsent) {
    final map = <String, i0.Expression>{};
    map['symbol'] = i0.Variable<String>(symbol);
    map['date'] = i0.Variable<DateTime>(date);
    if (!nullToAbsent || foreignRemainingShares != null) {
      map['foreign_remaining_shares'] = i0.Variable<double>(
        foreignRemainingShares,
      );
    }
    if (!nullToAbsent || foreignSharesRatio != null) {
      map['foreign_shares_ratio'] = i0.Variable<double>(foreignSharesRatio);
    }
    if (!nullToAbsent || foreignUpperLimitRatio != null) {
      map['foreign_upper_limit_ratio'] = i0.Variable<double>(
        foreignUpperLimitRatio,
      );
    }
    if (!nullToAbsent || sharesIssued != null) {
      map['shares_issued'] = i0.Variable<double>(sharesIssued);
    }
    return map;
  }

  i1.ShareholdingCompanion toCompanion(bool nullToAbsent) {
    return i1.ShareholdingCompanion(
      symbol: i0.Value(symbol),
      date: i0.Value(date),
      foreignRemainingShares: foreignRemainingShares == null && nullToAbsent
          ? const i0.Value.absent()
          : i0.Value(foreignRemainingShares),
      foreignSharesRatio: foreignSharesRatio == null && nullToAbsent
          ? const i0.Value.absent()
          : i0.Value(foreignSharesRatio),
      foreignUpperLimitRatio: foreignUpperLimitRatio == null && nullToAbsent
          ? const i0.Value.absent()
          : i0.Value(foreignUpperLimitRatio),
      sharesIssued: sharesIssued == null && nullToAbsent
          ? const i0.Value.absent()
          : i0.Value(sharesIssued),
    );
  }

  factory ShareholdingEntry.fromJson(
    Map<String, dynamic> json, {
    i0.ValueSerializer? serializer,
  }) {
    serializer ??= i0.driftRuntimeOptions.defaultSerializer;
    return ShareholdingEntry(
      symbol: serializer.fromJson<String>(json['symbol']),
      date: serializer.fromJson<DateTime>(json['date']),
      foreignRemainingShares: serializer.fromJson<double?>(
        json['foreignRemainingShares'],
      ),
      foreignSharesRatio: serializer.fromJson<double?>(
        json['foreignSharesRatio'],
      ),
      foreignUpperLimitRatio: serializer.fromJson<double?>(
        json['foreignUpperLimitRatio'],
      ),
      sharesIssued: serializer.fromJson<double?>(json['sharesIssued']),
    );
  }
  @override
  Map<String, dynamic> toJson({i0.ValueSerializer? serializer}) {
    serializer ??= i0.driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'symbol': serializer.toJson<String>(symbol),
      'date': serializer.toJson<DateTime>(date),
      'foreignRemainingShares': serializer.toJson<double?>(
        foreignRemainingShares,
      ),
      'foreignSharesRatio': serializer.toJson<double?>(foreignSharesRatio),
      'foreignUpperLimitRatio': serializer.toJson<double?>(
        foreignUpperLimitRatio,
      ),
      'sharesIssued': serializer.toJson<double?>(sharesIssued),
    };
  }

  i1.ShareholdingEntry copyWith({
    String? symbol,
    DateTime? date,
    i0.Value<double?> foreignRemainingShares = const i0.Value.absent(),
    i0.Value<double?> foreignSharesRatio = const i0.Value.absent(),
    i0.Value<double?> foreignUpperLimitRatio = const i0.Value.absent(),
    i0.Value<double?> sharesIssued = const i0.Value.absent(),
  }) => i1.ShareholdingEntry(
    symbol: symbol ?? this.symbol,
    date: date ?? this.date,
    foreignRemainingShares: foreignRemainingShares.present
        ? foreignRemainingShares.value
        : this.foreignRemainingShares,
    foreignSharesRatio: foreignSharesRatio.present
        ? foreignSharesRatio.value
        : this.foreignSharesRatio,
    foreignUpperLimitRatio: foreignUpperLimitRatio.present
        ? foreignUpperLimitRatio.value
        : this.foreignUpperLimitRatio,
    sharesIssued: sharesIssued.present ? sharesIssued.value : this.sharesIssued,
  );
  ShareholdingEntry copyWithCompanion(i1.ShareholdingCompanion data) {
    return ShareholdingEntry(
      symbol: data.symbol.present ? data.symbol.value : this.symbol,
      date: data.date.present ? data.date.value : this.date,
      foreignRemainingShares: data.foreignRemainingShares.present
          ? data.foreignRemainingShares.value
          : this.foreignRemainingShares,
      foreignSharesRatio: data.foreignSharesRatio.present
          ? data.foreignSharesRatio.value
          : this.foreignSharesRatio,
      foreignUpperLimitRatio: data.foreignUpperLimitRatio.present
          ? data.foreignUpperLimitRatio.value
          : this.foreignUpperLimitRatio,
      sharesIssued: data.sharesIssued.present
          ? data.sharesIssued.value
          : this.sharesIssued,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ShareholdingEntry(')
          ..write('symbol: $symbol, ')
          ..write('date: $date, ')
          ..write('foreignRemainingShares: $foreignRemainingShares, ')
          ..write('foreignSharesRatio: $foreignSharesRatio, ')
          ..write('foreignUpperLimitRatio: $foreignUpperLimitRatio, ')
          ..write('sharesIssued: $sharesIssued')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    symbol,
    date,
    foreignRemainingShares,
    foreignSharesRatio,
    foreignUpperLimitRatio,
    sharesIssued,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is i1.ShareholdingEntry &&
          other.symbol == this.symbol &&
          other.date == this.date &&
          other.foreignRemainingShares == this.foreignRemainingShares &&
          other.foreignSharesRatio == this.foreignSharesRatio &&
          other.foreignUpperLimitRatio == this.foreignUpperLimitRatio &&
          other.sharesIssued == this.sharesIssued);
}

class ShareholdingCompanion extends i0.UpdateCompanion<i1.ShareholdingEntry> {
  final i0.Value<String> symbol;
  final i0.Value<DateTime> date;
  final i0.Value<double?> foreignRemainingShares;
  final i0.Value<double?> foreignSharesRatio;
  final i0.Value<double?> foreignUpperLimitRatio;
  final i0.Value<double?> sharesIssued;
  final i0.Value<int> rowid;
  const ShareholdingCompanion({
    this.symbol = const i0.Value.absent(),
    this.date = const i0.Value.absent(),
    this.foreignRemainingShares = const i0.Value.absent(),
    this.foreignSharesRatio = const i0.Value.absent(),
    this.foreignUpperLimitRatio = const i0.Value.absent(),
    this.sharesIssued = const i0.Value.absent(),
    this.rowid = const i0.Value.absent(),
  });
  ShareholdingCompanion.insert({
    required String symbol,
    required DateTime date,
    this.foreignRemainingShares = const i0.Value.absent(),
    this.foreignSharesRatio = const i0.Value.absent(),
    this.foreignUpperLimitRatio = const i0.Value.absent(),
    this.sharesIssued = const i0.Value.absent(),
    this.rowid = const i0.Value.absent(),
  }) : symbol = i0.Value(symbol),
       date = i0.Value(date);
  static i0.Insertable<i1.ShareholdingEntry> custom({
    i0.Expression<String>? symbol,
    i0.Expression<DateTime>? date,
    i0.Expression<double>? foreignRemainingShares,
    i0.Expression<double>? foreignSharesRatio,
    i0.Expression<double>? foreignUpperLimitRatio,
    i0.Expression<double>? sharesIssued,
    i0.Expression<int>? rowid,
  }) {
    return i0.RawValuesInsertable({
      if (symbol != null) 'symbol': symbol,
      if (date != null) 'date': date,
      if (foreignRemainingShares != null)
        'foreign_remaining_shares': foreignRemainingShares,
      if (foreignSharesRatio != null)
        'foreign_shares_ratio': foreignSharesRatio,
      if (foreignUpperLimitRatio != null)
        'foreign_upper_limit_ratio': foreignUpperLimitRatio,
      if (sharesIssued != null) 'shares_issued': sharesIssued,
      if (rowid != null) 'rowid': rowid,
    });
  }

  i1.ShareholdingCompanion copyWith({
    i0.Value<String>? symbol,
    i0.Value<DateTime>? date,
    i0.Value<double?>? foreignRemainingShares,
    i0.Value<double?>? foreignSharesRatio,
    i0.Value<double?>? foreignUpperLimitRatio,
    i0.Value<double?>? sharesIssued,
    i0.Value<int>? rowid,
  }) {
    return i1.ShareholdingCompanion(
      symbol: symbol ?? this.symbol,
      date: date ?? this.date,
      foreignRemainingShares:
          foreignRemainingShares ?? this.foreignRemainingShares,
      foreignSharesRatio: foreignSharesRatio ?? this.foreignSharesRatio,
      foreignUpperLimitRatio:
          foreignUpperLimitRatio ?? this.foreignUpperLimitRatio,
      sharesIssued: sharesIssued ?? this.sharesIssued,
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
    if (foreignRemainingShares.present) {
      map['foreign_remaining_shares'] = i0.Variable<double>(
        foreignRemainingShares.value,
      );
    }
    if (foreignSharesRatio.present) {
      map['foreign_shares_ratio'] = i0.Variable<double>(
        foreignSharesRatio.value,
      );
    }
    if (foreignUpperLimitRatio.present) {
      map['foreign_upper_limit_ratio'] = i0.Variable<double>(
        foreignUpperLimitRatio.value,
      );
    }
    if (sharesIssued.present) {
      map['shares_issued'] = i0.Variable<double>(sharesIssued.value);
    }
    if (rowid.present) {
      map['rowid'] = i0.Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ShareholdingCompanion(')
          ..write('symbol: $symbol, ')
          ..write('date: $date, ')
          ..write('foreignRemainingShares: $foreignRemainingShares, ')
          ..write('foreignSharesRatio: $foreignSharesRatio, ')
          ..write('foreignUpperLimitRatio: $foreignUpperLimitRatio, ')
          ..write('sharesIssued: $sharesIssued, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

i0.Index get idxDayTradingDate => i0.Index(
  'idx_day_trading_date',
  'CREATE INDEX idx_day_trading_date ON day_trading (date)',
);

class $DayTradingTable extends i2.DayTrading
    with i0.TableInfo<$DayTradingTable, i1.DayTradingEntry> {
  @override
  final i0.GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DayTradingTable(this.attachedDatabase, [this._alias]);
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
  static const i0.VerificationMeta _buyVolumeMeta = const i0.VerificationMeta(
    'buyVolume',
  );
  @override
  late final i0.GeneratedColumn<double> buyVolume = i0.GeneratedColumn<double>(
    'buy_volume',
    aliasedName,
    true,
    type: i0.DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const i0.VerificationMeta _sellVolumeMeta = const i0.VerificationMeta(
    'sellVolume',
  );
  @override
  late final i0.GeneratedColumn<double> sellVolume = i0.GeneratedColumn<double>(
    'sell_volume',
    aliasedName,
    true,
    type: i0.DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const i0.VerificationMeta _dayTradingRatioMeta =
      const i0.VerificationMeta('dayTradingRatio');
  @override
  late final i0.GeneratedColumn<double> dayTradingRatio =
      i0.GeneratedColumn<double>(
        'day_trading_ratio',
        aliasedName,
        true,
        type: i0.DriftSqlType.double,
        requiredDuringInsert: false,
      );
  static const i0.VerificationMeta _tradeVolumeMeta = const i0.VerificationMeta(
    'tradeVolume',
  );
  @override
  late final i0.GeneratedColumn<double> tradeVolume =
      i0.GeneratedColumn<double>(
        'trade_volume',
        aliasedName,
        true,
        type: i0.DriftSqlType.double,
        requiredDuringInsert: false,
      );
  @override
  List<i0.GeneratedColumn> get $columns => [
    symbol,
    date,
    buyVolume,
    sellVolume,
    dayTradingRatio,
    tradeVolume,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'day_trading';
  @override
  i0.VerificationContext validateIntegrity(
    i0.Insertable<i1.DayTradingEntry> instance, {
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
    if (data.containsKey('buy_volume')) {
      context.handle(
        _buyVolumeMeta,
        buyVolume.isAcceptableOrUnknown(data['buy_volume']!, _buyVolumeMeta),
      );
    }
    if (data.containsKey('sell_volume')) {
      context.handle(
        _sellVolumeMeta,
        sellVolume.isAcceptableOrUnknown(data['sell_volume']!, _sellVolumeMeta),
      );
    }
    if (data.containsKey('day_trading_ratio')) {
      context.handle(
        _dayTradingRatioMeta,
        dayTradingRatio.isAcceptableOrUnknown(
          data['day_trading_ratio']!,
          _dayTradingRatioMeta,
        ),
      );
    }
    if (data.containsKey('trade_volume')) {
      context.handle(
        _tradeVolumeMeta,
        tradeVolume.isAcceptableOrUnknown(
          data['trade_volume']!,
          _tradeVolumeMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<i0.GeneratedColumn> get $primaryKey => {symbol, date};
  @override
  i1.DayTradingEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return i1.DayTradingEntry(
      symbol: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.string,
        data['${effectivePrefix}symbol'],
      )!,
      date: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.dateTime,
        data['${effectivePrefix}date'],
      )!,
      buyVolume: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.double,
        data['${effectivePrefix}buy_volume'],
      ),
      sellVolume: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.double,
        data['${effectivePrefix}sell_volume'],
      ),
      dayTradingRatio: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.double,
        data['${effectivePrefix}day_trading_ratio'],
      ),
      tradeVolume: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.double,
        data['${effectivePrefix}trade_volume'],
      ),
    );
  }

  @override
  $DayTradingTable createAlias(String alias) {
    return $DayTradingTable(attachedDatabase, alias);
  }
}

class DayTradingEntry extends i0.DataClass
    implements i0.Insertable<i1.DayTradingEntry> {
  /// 股票代碼
  final String symbol;

  /// 交易日期
  final DateTime date;

  /// 當沖買進金額（元，TWSE TWTB4U）
  final double? buyVolume;

  /// 當沖賣出金額（元，TWSE TWTB4U）
  final double? sellVolume;

  /// 當沖比例（%）
  ///
  /// 此為主要指標，由總成交量計算。
  final double? dayTradingRatio;

  /// 當沖成交股數
  final double? tradeVolume;
  const DayTradingEntry({
    required this.symbol,
    required this.date,
    this.buyVolume,
    this.sellVolume,
    this.dayTradingRatio,
    this.tradeVolume,
  });
  @override
  Map<String, i0.Expression> toColumns(bool nullToAbsent) {
    final map = <String, i0.Expression>{};
    map['symbol'] = i0.Variable<String>(symbol);
    map['date'] = i0.Variable<DateTime>(date);
    if (!nullToAbsent || buyVolume != null) {
      map['buy_volume'] = i0.Variable<double>(buyVolume);
    }
    if (!nullToAbsent || sellVolume != null) {
      map['sell_volume'] = i0.Variable<double>(sellVolume);
    }
    if (!nullToAbsent || dayTradingRatio != null) {
      map['day_trading_ratio'] = i0.Variable<double>(dayTradingRatio);
    }
    if (!nullToAbsent || tradeVolume != null) {
      map['trade_volume'] = i0.Variable<double>(tradeVolume);
    }
    return map;
  }

  i1.DayTradingCompanion toCompanion(bool nullToAbsent) {
    return i1.DayTradingCompanion(
      symbol: i0.Value(symbol),
      date: i0.Value(date),
      buyVolume: buyVolume == null && nullToAbsent
          ? const i0.Value.absent()
          : i0.Value(buyVolume),
      sellVolume: sellVolume == null && nullToAbsent
          ? const i0.Value.absent()
          : i0.Value(sellVolume),
      dayTradingRatio: dayTradingRatio == null && nullToAbsent
          ? const i0.Value.absent()
          : i0.Value(dayTradingRatio),
      tradeVolume: tradeVolume == null && nullToAbsent
          ? const i0.Value.absent()
          : i0.Value(tradeVolume),
    );
  }

  factory DayTradingEntry.fromJson(
    Map<String, dynamic> json, {
    i0.ValueSerializer? serializer,
  }) {
    serializer ??= i0.driftRuntimeOptions.defaultSerializer;
    return DayTradingEntry(
      symbol: serializer.fromJson<String>(json['symbol']),
      date: serializer.fromJson<DateTime>(json['date']),
      buyVolume: serializer.fromJson<double?>(json['buyVolume']),
      sellVolume: serializer.fromJson<double?>(json['sellVolume']),
      dayTradingRatio: serializer.fromJson<double?>(json['dayTradingRatio']),
      tradeVolume: serializer.fromJson<double?>(json['tradeVolume']),
    );
  }
  @override
  Map<String, dynamic> toJson({i0.ValueSerializer? serializer}) {
    serializer ??= i0.driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'symbol': serializer.toJson<String>(symbol),
      'date': serializer.toJson<DateTime>(date),
      'buyVolume': serializer.toJson<double?>(buyVolume),
      'sellVolume': serializer.toJson<double?>(sellVolume),
      'dayTradingRatio': serializer.toJson<double?>(dayTradingRatio),
      'tradeVolume': serializer.toJson<double?>(tradeVolume),
    };
  }

  i1.DayTradingEntry copyWith({
    String? symbol,
    DateTime? date,
    i0.Value<double?> buyVolume = const i0.Value.absent(),
    i0.Value<double?> sellVolume = const i0.Value.absent(),
    i0.Value<double?> dayTradingRatio = const i0.Value.absent(),
    i0.Value<double?> tradeVolume = const i0.Value.absent(),
  }) => i1.DayTradingEntry(
    symbol: symbol ?? this.symbol,
    date: date ?? this.date,
    buyVolume: buyVolume.present ? buyVolume.value : this.buyVolume,
    sellVolume: sellVolume.present ? sellVolume.value : this.sellVolume,
    dayTradingRatio: dayTradingRatio.present
        ? dayTradingRatio.value
        : this.dayTradingRatio,
    tradeVolume: tradeVolume.present ? tradeVolume.value : this.tradeVolume,
  );
  DayTradingEntry copyWithCompanion(i1.DayTradingCompanion data) {
    return DayTradingEntry(
      symbol: data.symbol.present ? data.symbol.value : this.symbol,
      date: data.date.present ? data.date.value : this.date,
      buyVolume: data.buyVolume.present ? data.buyVolume.value : this.buyVolume,
      sellVolume: data.sellVolume.present
          ? data.sellVolume.value
          : this.sellVolume,
      dayTradingRatio: data.dayTradingRatio.present
          ? data.dayTradingRatio.value
          : this.dayTradingRatio,
      tradeVolume: data.tradeVolume.present
          ? data.tradeVolume.value
          : this.tradeVolume,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DayTradingEntry(')
          ..write('symbol: $symbol, ')
          ..write('date: $date, ')
          ..write('buyVolume: $buyVolume, ')
          ..write('sellVolume: $sellVolume, ')
          ..write('dayTradingRatio: $dayTradingRatio, ')
          ..write('tradeVolume: $tradeVolume')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    symbol,
    date,
    buyVolume,
    sellVolume,
    dayTradingRatio,
    tradeVolume,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is i1.DayTradingEntry &&
          other.symbol == this.symbol &&
          other.date == this.date &&
          other.buyVolume == this.buyVolume &&
          other.sellVolume == this.sellVolume &&
          other.dayTradingRatio == this.dayTradingRatio &&
          other.tradeVolume == this.tradeVolume);
}

class DayTradingCompanion extends i0.UpdateCompanion<i1.DayTradingEntry> {
  final i0.Value<String> symbol;
  final i0.Value<DateTime> date;
  final i0.Value<double?> buyVolume;
  final i0.Value<double?> sellVolume;
  final i0.Value<double?> dayTradingRatio;
  final i0.Value<double?> tradeVolume;
  final i0.Value<int> rowid;
  const DayTradingCompanion({
    this.symbol = const i0.Value.absent(),
    this.date = const i0.Value.absent(),
    this.buyVolume = const i0.Value.absent(),
    this.sellVolume = const i0.Value.absent(),
    this.dayTradingRatio = const i0.Value.absent(),
    this.tradeVolume = const i0.Value.absent(),
    this.rowid = const i0.Value.absent(),
  });
  DayTradingCompanion.insert({
    required String symbol,
    required DateTime date,
    this.buyVolume = const i0.Value.absent(),
    this.sellVolume = const i0.Value.absent(),
    this.dayTradingRatio = const i0.Value.absent(),
    this.tradeVolume = const i0.Value.absent(),
    this.rowid = const i0.Value.absent(),
  }) : symbol = i0.Value(symbol),
       date = i0.Value(date);
  static i0.Insertable<i1.DayTradingEntry> custom({
    i0.Expression<String>? symbol,
    i0.Expression<DateTime>? date,
    i0.Expression<double>? buyVolume,
    i0.Expression<double>? sellVolume,
    i0.Expression<double>? dayTradingRatio,
    i0.Expression<double>? tradeVolume,
    i0.Expression<int>? rowid,
  }) {
    return i0.RawValuesInsertable({
      if (symbol != null) 'symbol': symbol,
      if (date != null) 'date': date,
      if (buyVolume != null) 'buy_volume': buyVolume,
      if (sellVolume != null) 'sell_volume': sellVolume,
      if (dayTradingRatio != null) 'day_trading_ratio': dayTradingRatio,
      if (tradeVolume != null) 'trade_volume': tradeVolume,
      if (rowid != null) 'rowid': rowid,
    });
  }

  i1.DayTradingCompanion copyWith({
    i0.Value<String>? symbol,
    i0.Value<DateTime>? date,
    i0.Value<double?>? buyVolume,
    i0.Value<double?>? sellVolume,
    i0.Value<double?>? dayTradingRatio,
    i0.Value<double?>? tradeVolume,
    i0.Value<int>? rowid,
  }) {
    return i1.DayTradingCompanion(
      symbol: symbol ?? this.symbol,
      date: date ?? this.date,
      buyVolume: buyVolume ?? this.buyVolume,
      sellVolume: sellVolume ?? this.sellVolume,
      dayTradingRatio: dayTradingRatio ?? this.dayTradingRatio,
      tradeVolume: tradeVolume ?? this.tradeVolume,
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
    if (buyVolume.present) {
      map['buy_volume'] = i0.Variable<double>(buyVolume.value);
    }
    if (sellVolume.present) {
      map['sell_volume'] = i0.Variable<double>(sellVolume.value);
    }
    if (dayTradingRatio.present) {
      map['day_trading_ratio'] = i0.Variable<double>(dayTradingRatio.value);
    }
    if (tradeVolume.present) {
      map['trade_volume'] = i0.Variable<double>(tradeVolume.value);
    }
    if (rowid.present) {
      map['rowid'] = i0.Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DayTradingCompanion(')
          ..write('symbol: $symbol, ')
          ..write('date: $date, ')
          ..write('buyVolume: $buyVolume, ')
          ..write('sellVolume: $sellVolume, ')
          ..write('dayTradingRatio: $dayTradingRatio, ')
          ..write('tradeVolume: $tradeVolume, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $QuarterlyReportTable extends i2.QuarterlyReport
    with i0.TableInfo<$QuarterlyReportTable, i1.QuarterlyReportData> {
  @override
  final i0.GeneratedDatabase attachedDatabase;
  final String? _alias;
  $QuarterlyReportTable(this.attachedDatabase, [this._alias]);
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
  static const i0.VerificationMeta _yearMeta = const i0.VerificationMeta(
    'year',
  );
  @override
  late final i0.GeneratedColumn<int> year = i0.GeneratedColumn<int>(
    'year',
    aliasedName,
    false,
    type: i0.DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const i0.VerificationMeta _quarterMeta = const i0.VerificationMeta(
    'quarter',
  );
  @override
  late final i0.GeneratedColumn<int> quarter = i0.GeneratedColumn<int>(
    'quarter',
    aliasedName,
    false,
    type: i0.DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const i0.VerificationMeta _epsMeta = const i0.VerificationMeta('eps');
  @override
  late final i0.GeneratedColumn<double> eps = i0.GeneratedColumn<double>(
    'eps',
    aliasedName,
    true,
    type: i0.DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const i0.VerificationMeta _netIncomeMeta = const i0.VerificationMeta(
    'netIncome',
  );
  @override
  late final i0.GeneratedColumn<double> netIncome = i0.GeneratedColumn<double>(
    'net_income',
    aliasedName,
    true,
    type: i0.DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const i0.VerificationMeta _revenueMeta = const i0.VerificationMeta(
    'revenue',
  );
  @override
  late final i0.GeneratedColumn<double> revenue = i0.GeneratedColumn<double>(
    'revenue',
    aliasedName,
    true,
    type: i0.DriftSqlType.double,
    requiredDuringInsert: false,
  );
  @override
  List<i0.GeneratedColumn> get $columns => [
    symbol,
    year,
    quarter,
    eps,
    netIncome,
    revenue,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'quarterly_report';
  @override
  i0.VerificationContext validateIntegrity(
    i0.Insertable<i1.QuarterlyReportData> instance, {
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
    if (data.containsKey('year')) {
      context.handle(
        _yearMeta,
        year.isAcceptableOrUnknown(data['year']!, _yearMeta),
      );
    } else if (isInserting) {
      context.missing(_yearMeta);
    }
    if (data.containsKey('quarter')) {
      context.handle(
        _quarterMeta,
        quarter.isAcceptableOrUnknown(data['quarter']!, _quarterMeta),
      );
    } else if (isInserting) {
      context.missing(_quarterMeta);
    }
    if (data.containsKey('eps')) {
      context.handle(
        _epsMeta,
        eps.isAcceptableOrUnknown(data['eps']!, _epsMeta),
      );
    }
    if (data.containsKey('net_income')) {
      context.handle(
        _netIncomeMeta,
        netIncome.isAcceptableOrUnknown(data['net_income']!, _netIncomeMeta),
      );
    }
    if (data.containsKey('revenue')) {
      context.handle(
        _revenueMeta,
        revenue.isAcceptableOrUnknown(data['revenue']!, _revenueMeta),
      );
    }
    return context;
  }

  @override
  Set<i0.GeneratedColumn> get $primaryKey => {symbol, year, quarter};
  @override
  i1.QuarterlyReportData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return i1.QuarterlyReportData(
      symbol: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.string,
        data['${effectivePrefix}symbol'],
      )!,
      year: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.int,
        data['${effectivePrefix}year'],
      )!,
      quarter: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.int,
        data['${effectivePrefix}quarter'],
      )!,
      eps: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.double,
        data['${effectivePrefix}eps'],
      ),
      netIncome: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.double,
        data['${effectivePrefix}net_income'],
      ),
      revenue: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.double,
        data['${effectivePrefix}revenue'],
      ),
    );
  }

  @override
  $QuarterlyReportTable createAlias(String alias) {
    return $QuarterlyReportTable(attachedDatabase, alias);
  }
}

class QuarterlyReportData extends i0.DataClass
    implements i0.Insertable<i1.QuarterlyReportData> {
  /// 股票代碼
  final String symbol;

  /// 西元年度
  final int year;

  /// 季別 1~4
  final int quarter;

  /// 基本每股盈餘(元,累計)
  final double? eps;

  /// 本期淨利(千元,累計)
  final double? netIncome;

  /// 營業收入(千元,累計;金融業別無此欄為 NULL)
  final double? revenue;
  const QuarterlyReportData({
    required this.symbol,
    required this.year,
    required this.quarter,
    this.eps,
    this.netIncome,
    this.revenue,
  });
  @override
  Map<String, i0.Expression> toColumns(bool nullToAbsent) {
    final map = <String, i0.Expression>{};
    map['symbol'] = i0.Variable<String>(symbol);
    map['year'] = i0.Variable<int>(year);
    map['quarter'] = i0.Variable<int>(quarter);
    if (!nullToAbsent || eps != null) {
      map['eps'] = i0.Variable<double>(eps);
    }
    if (!nullToAbsent || netIncome != null) {
      map['net_income'] = i0.Variable<double>(netIncome);
    }
    if (!nullToAbsent || revenue != null) {
      map['revenue'] = i0.Variable<double>(revenue);
    }
    return map;
  }

  i1.QuarterlyReportCompanion toCompanion(bool nullToAbsent) {
    return i1.QuarterlyReportCompanion(
      symbol: i0.Value(symbol),
      year: i0.Value(year),
      quarter: i0.Value(quarter),
      eps: eps == null && nullToAbsent
          ? const i0.Value.absent()
          : i0.Value(eps),
      netIncome: netIncome == null && nullToAbsent
          ? const i0.Value.absent()
          : i0.Value(netIncome),
      revenue: revenue == null && nullToAbsent
          ? const i0.Value.absent()
          : i0.Value(revenue),
    );
  }

  factory QuarterlyReportData.fromJson(
    Map<String, dynamic> json, {
    i0.ValueSerializer? serializer,
  }) {
    serializer ??= i0.driftRuntimeOptions.defaultSerializer;
    return QuarterlyReportData(
      symbol: serializer.fromJson<String>(json['symbol']),
      year: serializer.fromJson<int>(json['year']),
      quarter: serializer.fromJson<int>(json['quarter']),
      eps: serializer.fromJson<double?>(json['eps']),
      netIncome: serializer.fromJson<double?>(json['netIncome']),
      revenue: serializer.fromJson<double?>(json['revenue']),
    );
  }
  @override
  Map<String, dynamic> toJson({i0.ValueSerializer? serializer}) {
    serializer ??= i0.driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'symbol': serializer.toJson<String>(symbol),
      'year': serializer.toJson<int>(year),
      'quarter': serializer.toJson<int>(quarter),
      'eps': serializer.toJson<double?>(eps),
      'netIncome': serializer.toJson<double?>(netIncome),
      'revenue': serializer.toJson<double?>(revenue),
    };
  }

  i1.QuarterlyReportData copyWith({
    String? symbol,
    int? year,
    int? quarter,
    i0.Value<double?> eps = const i0.Value.absent(),
    i0.Value<double?> netIncome = const i0.Value.absent(),
    i0.Value<double?> revenue = const i0.Value.absent(),
  }) => i1.QuarterlyReportData(
    symbol: symbol ?? this.symbol,
    year: year ?? this.year,
    quarter: quarter ?? this.quarter,
    eps: eps.present ? eps.value : this.eps,
    netIncome: netIncome.present ? netIncome.value : this.netIncome,
    revenue: revenue.present ? revenue.value : this.revenue,
  );
  QuarterlyReportData copyWithCompanion(i1.QuarterlyReportCompanion data) {
    return QuarterlyReportData(
      symbol: data.symbol.present ? data.symbol.value : this.symbol,
      year: data.year.present ? data.year.value : this.year,
      quarter: data.quarter.present ? data.quarter.value : this.quarter,
      eps: data.eps.present ? data.eps.value : this.eps,
      netIncome: data.netIncome.present ? data.netIncome.value : this.netIncome,
      revenue: data.revenue.present ? data.revenue.value : this.revenue,
    );
  }

  @override
  String toString() {
    return (StringBuffer('QuarterlyReportData(')
          ..write('symbol: $symbol, ')
          ..write('year: $year, ')
          ..write('quarter: $quarter, ')
          ..write('eps: $eps, ')
          ..write('netIncome: $netIncome, ')
          ..write('revenue: $revenue')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(symbol, year, quarter, eps, netIncome, revenue);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is i1.QuarterlyReportData &&
          other.symbol == this.symbol &&
          other.year == this.year &&
          other.quarter == this.quarter &&
          other.eps == this.eps &&
          other.netIncome == this.netIncome &&
          other.revenue == this.revenue);
}

class QuarterlyReportCompanion
    extends i0.UpdateCompanion<i1.QuarterlyReportData> {
  final i0.Value<String> symbol;
  final i0.Value<int> year;
  final i0.Value<int> quarter;
  final i0.Value<double?> eps;
  final i0.Value<double?> netIncome;
  final i0.Value<double?> revenue;
  final i0.Value<int> rowid;
  const QuarterlyReportCompanion({
    this.symbol = const i0.Value.absent(),
    this.year = const i0.Value.absent(),
    this.quarter = const i0.Value.absent(),
    this.eps = const i0.Value.absent(),
    this.netIncome = const i0.Value.absent(),
    this.revenue = const i0.Value.absent(),
    this.rowid = const i0.Value.absent(),
  });
  QuarterlyReportCompanion.insert({
    required String symbol,
    required int year,
    required int quarter,
    this.eps = const i0.Value.absent(),
    this.netIncome = const i0.Value.absent(),
    this.revenue = const i0.Value.absent(),
    this.rowid = const i0.Value.absent(),
  }) : symbol = i0.Value(symbol),
       year = i0.Value(year),
       quarter = i0.Value(quarter);
  static i0.Insertable<i1.QuarterlyReportData> custom({
    i0.Expression<String>? symbol,
    i0.Expression<int>? year,
    i0.Expression<int>? quarter,
    i0.Expression<double>? eps,
    i0.Expression<double>? netIncome,
    i0.Expression<double>? revenue,
    i0.Expression<int>? rowid,
  }) {
    return i0.RawValuesInsertable({
      if (symbol != null) 'symbol': symbol,
      if (year != null) 'year': year,
      if (quarter != null) 'quarter': quarter,
      if (eps != null) 'eps': eps,
      if (netIncome != null) 'net_income': netIncome,
      if (revenue != null) 'revenue': revenue,
      if (rowid != null) 'rowid': rowid,
    });
  }

  i1.QuarterlyReportCompanion copyWith({
    i0.Value<String>? symbol,
    i0.Value<int>? year,
    i0.Value<int>? quarter,
    i0.Value<double?>? eps,
    i0.Value<double?>? netIncome,
    i0.Value<double?>? revenue,
    i0.Value<int>? rowid,
  }) {
    return i1.QuarterlyReportCompanion(
      symbol: symbol ?? this.symbol,
      year: year ?? this.year,
      quarter: quarter ?? this.quarter,
      eps: eps ?? this.eps,
      netIncome: netIncome ?? this.netIncome,
      revenue: revenue ?? this.revenue,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, i0.Expression> toColumns(bool nullToAbsent) {
    final map = <String, i0.Expression>{};
    if (symbol.present) {
      map['symbol'] = i0.Variable<String>(symbol.value);
    }
    if (year.present) {
      map['year'] = i0.Variable<int>(year.value);
    }
    if (quarter.present) {
      map['quarter'] = i0.Variable<int>(quarter.value);
    }
    if (eps.present) {
      map['eps'] = i0.Variable<double>(eps.value);
    }
    if (netIncome.present) {
      map['net_income'] = i0.Variable<double>(netIncome.value);
    }
    if (revenue.present) {
      map['revenue'] = i0.Variable<double>(revenue.value);
    }
    if (rowid.present) {
      map['rowid'] = i0.Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('QuarterlyReportCompanion(')
          ..write('symbol: $symbol, ')
          ..write('year: $year, ')
          ..write('quarter: $quarter, ')
          ..write('eps: $eps, ')
          ..write('netIncome: $netIncome, ')
          ..write('revenue: $revenue, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

i0.Index get idxFinancialDataDate => i0.Index(
  'idx_financial_data_date',
  'CREATE INDEX idx_financial_data_date ON financial_data (date)',
);

class $FinancialDataTable extends i2.FinancialData
    with i0.TableInfo<$FinancialDataTable, i1.FinancialDataEntry> {
  @override
  final i0.GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FinancialDataTable(this.attachedDatabase, [this._alias]);
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
  static const i0.VerificationMeta _statementTypeMeta =
      const i0.VerificationMeta('statementType');
  @override
  late final i0.GeneratedColumn<String> statementType =
      i0.GeneratedColumn<String>(
        'statement_type',
        aliasedName,
        false,
        type: i0.DriftSqlType.string,
        requiredDuringInsert: true,
      );
  static const i0.VerificationMeta _dataTypeMeta = const i0.VerificationMeta(
    'dataType',
  );
  @override
  late final i0.GeneratedColumn<String> dataType = i0.GeneratedColumn<String>(
    'data_type',
    aliasedName,
    false,
    type: i0.DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const i0.VerificationMeta _valueMeta = const i0.VerificationMeta(
    'value',
  );
  @override
  late final i0.GeneratedColumn<double> value = i0.GeneratedColumn<double>(
    'value',
    aliasedName,
    true,
    type: i0.DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const i0.VerificationMeta _originNameMeta = const i0.VerificationMeta(
    'originName',
  );
  @override
  late final i0.GeneratedColumn<String> originName = i0.GeneratedColumn<String>(
    'origin_name',
    aliasedName,
    true,
    type: i0.DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<i0.GeneratedColumn> get $columns => [
    symbol,
    date,
    statementType,
    dataType,
    value,
    originName,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'financial_data';
  @override
  i0.VerificationContext validateIntegrity(
    i0.Insertable<i1.FinancialDataEntry> instance, {
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
    if (data.containsKey('statement_type')) {
      context.handle(
        _statementTypeMeta,
        statementType.isAcceptableOrUnknown(
          data['statement_type']!,
          _statementTypeMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_statementTypeMeta);
    }
    if (data.containsKey('data_type')) {
      context.handle(
        _dataTypeMeta,
        dataType.isAcceptableOrUnknown(data['data_type']!, _dataTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_dataTypeMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    }
    if (data.containsKey('origin_name')) {
      context.handle(
        _originNameMeta,
        originName.isAcceptableOrUnknown(data['origin_name']!, _originNameMeta),
      );
    }
    return context;
  }

  @override
  Set<i0.GeneratedColumn> get $primaryKey => {
    symbol,
    date,
    statementType,
    dataType,
  };
  @override
  i1.FinancialDataEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return i1.FinancialDataEntry(
      symbol: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.string,
        data['${effectivePrefix}symbol'],
      )!,
      date: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.dateTime,
        data['${effectivePrefix}date'],
      )!,
      statementType: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.string,
        data['${effectivePrefix}statement_type'],
      )!,
      dataType: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.string,
        data['${effectivePrefix}data_type'],
      )!,
      value: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.double,
        data['${effectivePrefix}value'],
      ),
      originName: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.string,
        data['${effectivePrefix}origin_name'],
      ),
    );
  }

  @override
  $FinancialDataTable createAlias(String alias) {
    return $FinancialDataTable(attachedDatabase, alias);
  }
}

class FinancialDataEntry extends i0.DataClass
    implements i0.Insertable<i1.FinancialDataEntry> {
  /// 股票代碼
  final String symbol;

  /// 報告日期（季度以日期格式儲存）
  final DateTime date;

  /// 報表類型：INCOME、BALANCE、CASHFLOW
  final String statementType;

  /// 資料項目（如 Revenue、IncomeAfterTaxes、TotalAssets——⚠️ NetIncome 是 0 筆的幻影 key，見 financial_data_dao）
  final String dataType;

  /// 數值（千元）
  final double? value;

  /// 原始中文名稱
  final String? originName;
  const FinancialDataEntry({
    required this.symbol,
    required this.date,
    required this.statementType,
    required this.dataType,
    this.value,
    this.originName,
  });
  @override
  Map<String, i0.Expression> toColumns(bool nullToAbsent) {
    final map = <String, i0.Expression>{};
    map['symbol'] = i0.Variable<String>(symbol);
    map['date'] = i0.Variable<DateTime>(date);
    map['statement_type'] = i0.Variable<String>(statementType);
    map['data_type'] = i0.Variable<String>(dataType);
    if (!nullToAbsent || value != null) {
      map['value'] = i0.Variable<double>(value);
    }
    if (!nullToAbsent || originName != null) {
      map['origin_name'] = i0.Variable<String>(originName);
    }
    return map;
  }

  i1.FinancialDataCompanion toCompanion(bool nullToAbsent) {
    return i1.FinancialDataCompanion(
      symbol: i0.Value(symbol),
      date: i0.Value(date),
      statementType: i0.Value(statementType),
      dataType: i0.Value(dataType),
      value: value == null && nullToAbsent
          ? const i0.Value.absent()
          : i0.Value(value),
      originName: originName == null && nullToAbsent
          ? const i0.Value.absent()
          : i0.Value(originName),
    );
  }

  factory FinancialDataEntry.fromJson(
    Map<String, dynamic> json, {
    i0.ValueSerializer? serializer,
  }) {
    serializer ??= i0.driftRuntimeOptions.defaultSerializer;
    return FinancialDataEntry(
      symbol: serializer.fromJson<String>(json['symbol']),
      date: serializer.fromJson<DateTime>(json['date']),
      statementType: serializer.fromJson<String>(json['statementType']),
      dataType: serializer.fromJson<String>(json['dataType']),
      value: serializer.fromJson<double?>(json['value']),
      originName: serializer.fromJson<String?>(json['originName']),
    );
  }
  @override
  Map<String, dynamic> toJson({i0.ValueSerializer? serializer}) {
    serializer ??= i0.driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'symbol': serializer.toJson<String>(symbol),
      'date': serializer.toJson<DateTime>(date),
      'statementType': serializer.toJson<String>(statementType),
      'dataType': serializer.toJson<String>(dataType),
      'value': serializer.toJson<double?>(value),
      'originName': serializer.toJson<String?>(originName),
    };
  }

  i1.FinancialDataEntry copyWith({
    String? symbol,
    DateTime? date,
    String? statementType,
    String? dataType,
    i0.Value<double?> value = const i0.Value.absent(),
    i0.Value<String?> originName = const i0.Value.absent(),
  }) => i1.FinancialDataEntry(
    symbol: symbol ?? this.symbol,
    date: date ?? this.date,
    statementType: statementType ?? this.statementType,
    dataType: dataType ?? this.dataType,
    value: value.present ? value.value : this.value,
    originName: originName.present ? originName.value : this.originName,
  );
  FinancialDataEntry copyWithCompanion(i1.FinancialDataCompanion data) {
    return FinancialDataEntry(
      symbol: data.symbol.present ? data.symbol.value : this.symbol,
      date: data.date.present ? data.date.value : this.date,
      statementType: data.statementType.present
          ? data.statementType.value
          : this.statementType,
      dataType: data.dataType.present ? data.dataType.value : this.dataType,
      value: data.value.present ? data.value.value : this.value,
      originName: data.originName.present
          ? data.originName.value
          : this.originName,
    );
  }

  @override
  String toString() {
    return (StringBuffer('FinancialDataEntry(')
          ..write('symbol: $symbol, ')
          ..write('date: $date, ')
          ..write('statementType: $statementType, ')
          ..write('dataType: $dataType, ')
          ..write('value: $value, ')
          ..write('originName: $originName')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(symbol, date, statementType, dataType, value, originName);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is i1.FinancialDataEntry &&
          other.symbol == this.symbol &&
          other.date == this.date &&
          other.statementType == this.statementType &&
          other.dataType == this.dataType &&
          other.value == this.value &&
          other.originName == this.originName);
}

class FinancialDataCompanion extends i0.UpdateCompanion<i1.FinancialDataEntry> {
  final i0.Value<String> symbol;
  final i0.Value<DateTime> date;
  final i0.Value<String> statementType;
  final i0.Value<String> dataType;
  final i0.Value<double?> value;
  final i0.Value<String?> originName;
  final i0.Value<int> rowid;
  const FinancialDataCompanion({
    this.symbol = const i0.Value.absent(),
    this.date = const i0.Value.absent(),
    this.statementType = const i0.Value.absent(),
    this.dataType = const i0.Value.absent(),
    this.value = const i0.Value.absent(),
    this.originName = const i0.Value.absent(),
    this.rowid = const i0.Value.absent(),
  });
  FinancialDataCompanion.insert({
    required String symbol,
    required DateTime date,
    required String statementType,
    required String dataType,
    this.value = const i0.Value.absent(),
    this.originName = const i0.Value.absent(),
    this.rowid = const i0.Value.absent(),
  }) : symbol = i0.Value(symbol),
       date = i0.Value(date),
       statementType = i0.Value(statementType),
       dataType = i0.Value(dataType);
  static i0.Insertable<i1.FinancialDataEntry> custom({
    i0.Expression<String>? symbol,
    i0.Expression<DateTime>? date,
    i0.Expression<String>? statementType,
    i0.Expression<String>? dataType,
    i0.Expression<double>? value,
    i0.Expression<String>? originName,
    i0.Expression<int>? rowid,
  }) {
    return i0.RawValuesInsertable({
      if (symbol != null) 'symbol': symbol,
      if (date != null) 'date': date,
      if (statementType != null) 'statement_type': statementType,
      if (dataType != null) 'data_type': dataType,
      if (value != null) 'value': value,
      if (originName != null) 'origin_name': originName,
      if (rowid != null) 'rowid': rowid,
    });
  }

  i1.FinancialDataCompanion copyWith({
    i0.Value<String>? symbol,
    i0.Value<DateTime>? date,
    i0.Value<String>? statementType,
    i0.Value<String>? dataType,
    i0.Value<double?>? value,
    i0.Value<String?>? originName,
    i0.Value<int>? rowid,
  }) {
    return i1.FinancialDataCompanion(
      symbol: symbol ?? this.symbol,
      date: date ?? this.date,
      statementType: statementType ?? this.statementType,
      dataType: dataType ?? this.dataType,
      value: value ?? this.value,
      originName: originName ?? this.originName,
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
    if (statementType.present) {
      map['statement_type'] = i0.Variable<String>(statementType.value);
    }
    if (dataType.present) {
      map['data_type'] = i0.Variable<String>(dataType.value);
    }
    if (value.present) {
      map['value'] = i0.Variable<double>(value.value);
    }
    if (originName.present) {
      map['origin_name'] = i0.Variable<String>(originName.value);
    }
    if (rowid.present) {
      map['rowid'] = i0.Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FinancialDataCompanion(')
          ..write('symbol: $symbol, ')
          ..write('date: $date, ')
          ..write('statementType: $statementType, ')
          ..write('dataType: $dataType, ')
          ..write('value: $value, ')
          ..write('originName: $originName, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

i0.Index get idxFinancialDataType => i0.Index(
  'idx_financial_data_type',
  'CREATE INDEX idx_financial_data_type ON financial_data (data_type)',
);
i0.Index get idxHoldingDistDate => i0.Index(
  'idx_holding_dist_date',
  'CREATE INDEX idx_holding_dist_date ON holding_distribution (date)',
);

class $HoldingDistributionTable extends i2.HoldingDistribution
    with i0.TableInfo<$HoldingDistributionTable, i1.HoldingDistributionEntry> {
  @override
  final i0.GeneratedDatabase attachedDatabase;
  final String? _alias;
  $HoldingDistributionTable(this.attachedDatabase, [this._alias]);
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
  static const i0.VerificationMeta _levelMeta = const i0.VerificationMeta(
    'level',
  );
  @override
  late final i0.GeneratedColumn<String> level = i0.GeneratedColumn<String>(
    'level',
    aliasedName,
    false,
    type: i0.DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const i0.VerificationMeta _shareholdersMeta =
      const i0.VerificationMeta('shareholders');
  @override
  late final i0.GeneratedColumn<int> shareholders = i0.GeneratedColumn<int>(
    'shareholders',
    aliasedName,
    true,
    type: i0.DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const i0.VerificationMeta _percentMeta = const i0.VerificationMeta(
    'percent',
  );
  @override
  late final i0.GeneratedColumn<double> percent = i0.GeneratedColumn<double>(
    'percent',
    aliasedName,
    true,
    type: i0.DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const i0.VerificationMeta _sharesMeta = const i0.VerificationMeta(
    'shares',
  );
  @override
  late final i0.GeneratedColumn<double> shares = i0.GeneratedColumn<double>(
    'shares',
    aliasedName,
    true,
    type: i0.DriftSqlType.double,
    requiredDuringInsert: false,
  );
  @override
  List<i0.GeneratedColumn> get $columns => [
    symbol,
    date,
    level,
    shareholders,
    percent,
    shares,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'holding_distribution';
  @override
  i0.VerificationContext validateIntegrity(
    i0.Insertable<i1.HoldingDistributionEntry> instance, {
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
    if (data.containsKey('level')) {
      context.handle(
        _levelMeta,
        level.isAcceptableOrUnknown(data['level']!, _levelMeta),
      );
    } else if (isInserting) {
      context.missing(_levelMeta);
    }
    if (data.containsKey('shareholders')) {
      context.handle(
        _shareholdersMeta,
        shareholders.isAcceptableOrUnknown(
          data['shareholders']!,
          _shareholdersMeta,
        ),
      );
    }
    if (data.containsKey('percent')) {
      context.handle(
        _percentMeta,
        percent.isAcceptableOrUnknown(data['percent']!, _percentMeta),
      );
    }
    if (data.containsKey('shares')) {
      context.handle(
        _sharesMeta,
        shares.isAcceptableOrUnknown(data['shares']!, _sharesMeta),
      );
    }
    return context;
  }

  @override
  Set<i0.GeneratedColumn> get $primaryKey => {symbol, date, level};
  @override
  i1.HoldingDistributionEntry map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return i1.HoldingDistributionEntry(
      symbol: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.string,
        data['${effectivePrefix}symbol'],
      )!,
      date: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.dateTime,
        data['${effectivePrefix}date'],
      )!,
      level: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.string,
        data['${effectivePrefix}level'],
      )!,
      shareholders: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.int,
        data['${effectivePrefix}shareholders'],
      ),
      percent: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.double,
        data['${effectivePrefix}percent'],
      ),
      shares: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.double,
        data['${effectivePrefix}shares'],
      ),
    );
  }

  @override
  $HoldingDistributionTable createAlias(String alias) {
    return $HoldingDistributionTable(attachedDatabase, alias);
  }
}

class HoldingDistributionEntry extends i0.DataClass
    implements i0.Insertable<i1.HoldingDistributionEntry> {
  /// 股票代碼
  final String symbol;

  /// 報告日期
  final DateTime date;

  /// 持股級距（如 "1-999"、"1000-5000"）
  final String level;

  /// 該級距股東人數
  final int? shareholders;

  /// 佔總股數比例（%）
  final double? percent;

  /// 持股數（股）
  final double? shares;
  const HoldingDistributionEntry({
    required this.symbol,
    required this.date,
    required this.level,
    this.shareholders,
    this.percent,
    this.shares,
  });
  @override
  Map<String, i0.Expression> toColumns(bool nullToAbsent) {
    final map = <String, i0.Expression>{};
    map['symbol'] = i0.Variable<String>(symbol);
    map['date'] = i0.Variable<DateTime>(date);
    map['level'] = i0.Variable<String>(level);
    if (!nullToAbsent || shareholders != null) {
      map['shareholders'] = i0.Variable<int>(shareholders);
    }
    if (!nullToAbsent || percent != null) {
      map['percent'] = i0.Variable<double>(percent);
    }
    if (!nullToAbsent || shares != null) {
      map['shares'] = i0.Variable<double>(shares);
    }
    return map;
  }

  i1.HoldingDistributionCompanion toCompanion(bool nullToAbsent) {
    return i1.HoldingDistributionCompanion(
      symbol: i0.Value(symbol),
      date: i0.Value(date),
      level: i0.Value(level),
      shareholders: shareholders == null && nullToAbsent
          ? const i0.Value.absent()
          : i0.Value(shareholders),
      percent: percent == null && nullToAbsent
          ? const i0.Value.absent()
          : i0.Value(percent),
      shares: shares == null && nullToAbsent
          ? const i0.Value.absent()
          : i0.Value(shares),
    );
  }

  factory HoldingDistributionEntry.fromJson(
    Map<String, dynamic> json, {
    i0.ValueSerializer? serializer,
  }) {
    serializer ??= i0.driftRuntimeOptions.defaultSerializer;
    return HoldingDistributionEntry(
      symbol: serializer.fromJson<String>(json['symbol']),
      date: serializer.fromJson<DateTime>(json['date']),
      level: serializer.fromJson<String>(json['level']),
      shareholders: serializer.fromJson<int?>(json['shareholders']),
      percent: serializer.fromJson<double?>(json['percent']),
      shares: serializer.fromJson<double?>(json['shares']),
    );
  }
  @override
  Map<String, dynamic> toJson({i0.ValueSerializer? serializer}) {
    serializer ??= i0.driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'symbol': serializer.toJson<String>(symbol),
      'date': serializer.toJson<DateTime>(date),
      'level': serializer.toJson<String>(level),
      'shareholders': serializer.toJson<int?>(shareholders),
      'percent': serializer.toJson<double?>(percent),
      'shares': serializer.toJson<double?>(shares),
    };
  }

  i1.HoldingDistributionEntry copyWith({
    String? symbol,
    DateTime? date,
    String? level,
    i0.Value<int?> shareholders = const i0.Value.absent(),
    i0.Value<double?> percent = const i0.Value.absent(),
    i0.Value<double?> shares = const i0.Value.absent(),
  }) => i1.HoldingDistributionEntry(
    symbol: symbol ?? this.symbol,
    date: date ?? this.date,
    level: level ?? this.level,
    shareholders: shareholders.present ? shareholders.value : this.shareholders,
    percent: percent.present ? percent.value : this.percent,
    shares: shares.present ? shares.value : this.shares,
  );
  HoldingDistributionEntry copyWithCompanion(
    i1.HoldingDistributionCompanion data,
  ) {
    return HoldingDistributionEntry(
      symbol: data.symbol.present ? data.symbol.value : this.symbol,
      date: data.date.present ? data.date.value : this.date,
      level: data.level.present ? data.level.value : this.level,
      shareholders: data.shareholders.present
          ? data.shareholders.value
          : this.shareholders,
      percent: data.percent.present ? data.percent.value : this.percent,
      shares: data.shares.present ? data.shares.value : this.shares,
    );
  }

  @override
  String toString() {
    return (StringBuffer('HoldingDistributionEntry(')
          ..write('symbol: $symbol, ')
          ..write('date: $date, ')
          ..write('level: $level, ')
          ..write('shareholders: $shareholders, ')
          ..write('percent: $percent, ')
          ..write('shares: $shares')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(symbol, date, level, shareholders, percent, shares);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is i1.HoldingDistributionEntry &&
          other.symbol == this.symbol &&
          other.date == this.date &&
          other.level == this.level &&
          other.shareholders == this.shareholders &&
          other.percent == this.percent &&
          other.shares == this.shares);
}

class HoldingDistributionCompanion
    extends i0.UpdateCompanion<i1.HoldingDistributionEntry> {
  final i0.Value<String> symbol;
  final i0.Value<DateTime> date;
  final i0.Value<String> level;
  final i0.Value<int?> shareholders;
  final i0.Value<double?> percent;
  final i0.Value<double?> shares;
  final i0.Value<int> rowid;
  const HoldingDistributionCompanion({
    this.symbol = const i0.Value.absent(),
    this.date = const i0.Value.absent(),
    this.level = const i0.Value.absent(),
    this.shareholders = const i0.Value.absent(),
    this.percent = const i0.Value.absent(),
    this.shares = const i0.Value.absent(),
    this.rowid = const i0.Value.absent(),
  });
  HoldingDistributionCompanion.insert({
    required String symbol,
    required DateTime date,
    required String level,
    this.shareholders = const i0.Value.absent(),
    this.percent = const i0.Value.absent(),
    this.shares = const i0.Value.absent(),
    this.rowid = const i0.Value.absent(),
  }) : symbol = i0.Value(symbol),
       date = i0.Value(date),
       level = i0.Value(level);
  static i0.Insertable<i1.HoldingDistributionEntry> custom({
    i0.Expression<String>? symbol,
    i0.Expression<DateTime>? date,
    i0.Expression<String>? level,
    i0.Expression<int>? shareholders,
    i0.Expression<double>? percent,
    i0.Expression<double>? shares,
    i0.Expression<int>? rowid,
  }) {
    return i0.RawValuesInsertable({
      if (symbol != null) 'symbol': symbol,
      if (date != null) 'date': date,
      if (level != null) 'level': level,
      if (shareholders != null) 'shareholders': shareholders,
      if (percent != null) 'percent': percent,
      if (shares != null) 'shares': shares,
      if (rowid != null) 'rowid': rowid,
    });
  }

  i1.HoldingDistributionCompanion copyWith({
    i0.Value<String>? symbol,
    i0.Value<DateTime>? date,
    i0.Value<String>? level,
    i0.Value<int?>? shareholders,
    i0.Value<double?>? percent,
    i0.Value<double?>? shares,
    i0.Value<int>? rowid,
  }) {
    return i1.HoldingDistributionCompanion(
      symbol: symbol ?? this.symbol,
      date: date ?? this.date,
      level: level ?? this.level,
      shareholders: shareholders ?? this.shareholders,
      percent: percent ?? this.percent,
      shares: shares ?? this.shares,
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
    if (level.present) {
      map['level'] = i0.Variable<String>(level.value);
    }
    if (shareholders.present) {
      map['shareholders'] = i0.Variable<int>(shareholders.value);
    }
    if (percent.present) {
      map['percent'] = i0.Variable<double>(percent.value);
    }
    if (shares.present) {
      map['shares'] = i0.Variable<double>(shares.value);
    }
    if (rowid.present) {
      map['rowid'] = i0.Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('HoldingDistributionCompanion(')
          ..write('symbol: $symbol, ')
          ..write('date: $date, ')
          ..write('level: $level, ')
          ..write('shareholders: $shareholders, ')
          ..write('percent: $percent, ')
          ..write('shares: $shares, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DividendHistoryTable extends i2.DividendHistory
    with i0.TableInfo<$DividendHistoryTable, i1.DividendHistoryEntry> {
  @override
  final i0.GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DividendHistoryTable(this.attachedDatabase, [this._alias]);
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
  static const i0.VerificationMeta _yearMeta = const i0.VerificationMeta(
    'year',
  );
  @override
  late final i0.GeneratedColumn<int> year = i0.GeneratedColumn<int>(
    'year',
    aliasedName,
    false,
    type: i0.DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const i0.VerificationMeta _cashDividendMeta =
      const i0.VerificationMeta('cashDividend');
  @override
  late final i0.GeneratedColumn<double> cashDividend =
      i0.GeneratedColumn<double>(
        'cash_dividend',
        aliasedName,
        false,
        type: i0.DriftSqlType.double,
        requiredDuringInsert: false,
        defaultValue: const i3.Constant(0),
      );
  static const i0.VerificationMeta _stockDividendMeta =
      const i0.VerificationMeta('stockDividend');
  @override
  late final i0.GeneratedColumn<double> stockDividend =
      i0.GeneratedColumn<double>(
        'stock_dividend',
        aliasedName,
        false,
        type: i0.DriftSqlType.double,
        requiredDuringInsert: false,
        defaultValue: const i3.Constant(0),
      );
  static const i0.VerificationMeta _exDividendDateMeta =
      const i0.VerificationMeta('exDividendDate');
  @override
  late final i0.GeneratedColumn<String> exDividendDate =
      i0.GeneratedColumn<String>(
        'ex_dividend_date',
        aliasedName,
        true,
        type: i0.DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const i0.VerificationMeta _exRightsDateMeta =
      const i0.VerificationMeta('exRightsDate');
  @override
  late final i0.GeneratedColumn<String> exRightsDate =
      i0.GeneratedColumn<String>(
        'ex_rights_date',
        aliasedName,
        true,
        type: i0.DriftSqlType.string,
        requiredDuringInsert: false,
      );
  @override
  List<i0.GeneratedColumn> get $columns => [
    symbol,
    year,
    cashDividend,
    stockDividend,
    exDividendDate,
    exRightsDate,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'dividend_history';
  @override
  i0.VerificationContext validateIntegrity(
    i0.Insertable<i1.DividendHistoryEntry> instance, {
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
    if (data.containsKey('year')) {
      context.handle(
        _yearMeta,
        year.isAcceptableOrUnknown(data['year']!, _yearMeta),
      );
    } else if (isInserting) {
      context.missing(_yearMeta);
    }
    if (data.containsKey('cash_dividend')) {
      context.handle(
        _cashDividendMeta,
        cashDividend.isAcceptableOrUnknown(
          data['cash_dividend']!,
          _cashDividendMeta,
        ),
      );
    }
    if (data.containsKey('stock_dividend')) {
      context.handle(
        _stockDividendMeta,
        stockDividend.isAcceptableOrUnknown(
          data['stock_dividend']!,
          _stockDividendMeta,
        ),
      );
    }
    if (data.containsKey('ex_dividend_date')) {
      context.handle(
        _exDividendDateMeta,
        exDividendDate.isAcceptableOrUnknown(
          data['ex_dividend_date']!,
          _exDividendDateMeta,
        ),
      );
    }
    if (data.containsKey('ex_rights_date')) {
      context.handle(
        _exRightsDateMeta,
        exRightsDate.isAcceptableOrUnknown(
          data['ex_rights_date']!,
          _exRightsDateMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<i0.GeneratedColumn> get $primaryKey => {symbol, year};
  @override
  i1.DividendHistoryEntry map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return i1.DividendHistoryEntry(
      symbol: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.string,
        data['${effectivePrefix}symbol'],
      )!,
      year: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.int,
        data['${effectivePrefix}year'],
      )!,
      cashDividend: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.double,
        data['${effectivePrefix}cash_dividend'],
      )!,
      stockDividend: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.double,
        data['${effectivePrefix}stock_dividend'],
      )!,
      exDividendDate: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.string,
        data['${effectivePrefix}ex_dividend_date'],
      ),
      exRightsDate: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.string,
        data['${effectivePrefix}ex_rights_date'],
      ),
    );
  }

  @override
  $DividendHistoryTable createAlias(String alias) {
    return $DividendHistoryTable(attachedDatabase, alias);
  }
}

class DividendHistoryEntry extends i0.DataClass
    implements i0.Insertable<i1.DividendHistoryEntry> {
  /// 股票代碼
  final String symbol;

  /// 股利所屬年度
  final int year;

  /// 現金股利（元）
  final double cashDividend;

  /// 股票股利（元）
  final double stockDividend;

  /// 除息日（格式: yyyy-MM-dd）
  final String? exDividendDate;

  /// 除權日（格式: yyyy-MM-dd）
  final String? exRightsDate;
  const DividendHistoryEntry({
    required this.symbol,
    required this.year,
    required this.cashDividend,
    required this.stockDividend,
    this.exDividendDate,
    this.exRightsDate,
  });
  @override
  Map<String, i0.Expression> toColumns(bool nullToAbsent) {
    final map = <String, i0.Expression>{};
    map['symbol'] = i0.Variable<String>(symbol);
    map['year'] = i0.Variable<int>(year);
    map['cash_dividend'] = i0.Variable<double>(cashDividend);
    map['stock_dividend'] = i0.Variable<double>(stockDividend);
    if (!nullToAbsent || exDividendDate != null) {
      map['ex_dividend_date'] = i0.Variable<String>(exDividendDate);
    }
    if (!nullToAbsent || exRightsDate != null) {
      map['ex_rights_date'] = i0.Variable<String>(exRightsDate);
    }
    return map;
  }

  i1.DividendHistoryCompanion toCompanion(bool nullToAbsent) {
    return i1.DividendHistoryCompanion(
      symbol: i0.Value(symbol),
      year: i0.Value(year),
      cashDividend: i0.Value(cashDividend),
      stockDividend: i0.Value(stockDividend),
      exDividendDate: exDividendDate == null && nullToAbsent
          ? const i0.Value.absent()
          : i0.Value(exDividendDate),
      exRightsDate: exRightsDate == null && nullToAbsent
          ? const i0.Value.absent()
          : i0.Value(exRightsDate),
    );
  }

  factory DividendHistoryEntry.fromJson(
    Map<String, dynamic> json, {
    i0.ValueSerializer? serializer,
  }) {
    serializer ??= i0.driftRuntimeOptions.defaultSerializer;
    return DividendHistoryEntry(
      symbol: serializer.fromJson<String>(json['symbol']),
      year: serializer.fromJson<int>(json['year']),
      cashDividend: serializer.fromJson<double>(json['cashDividend']),
      stockDividend: serializer.fromJson<double>(json['stockDividend']),
      exDividendDate: serializer.fromJson<String?>(json['exDividendDate']),
      exRightsDate: serializer.fromJson<String?>(json['exRightsDate']),
    );
  }
  @override
  Map<String, dynamic> toJson({i0.ValueSerializer? serializer}) {
    serializer ??= i0.driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'symbol': serializer.toJson<String>(symbol),
      'year': serializer.toJson<int>(year),
      'cashDividend': serializer.toJson<double>(cashDividend),
      'stockDividend': serializer.toJson<double>(stockDividend),
      'exDividendDate': serializer.toJson<String?>(exDividendDate),
      'exRightsDate': serializer.toJson<String?>(exRightsDate),
    };
  }

  i1.DividendHistoryEntry copyWith({
    String? symbol,
    int? year,
    double? cashDividend,
    double? stockDividend,
    i0.Value<String?> exDividendDate = const i0.Value.absent(),
    i0.Value<String?> exRightsDate = const i0.Value.absent(),
  }) => i1.DividendHistoryEntry(
    symbol: symbol ?? this.symbol,
    year: year ?? this.year,
    cashDividend: cashDividend ?? this.cashDividend,
    stockDividend: stockDividend ?? this.stockDividend,
    exDividendDate: exDividendDate.present
        ? exDividendDate.value
        : this.exDividendDate,
    exRightsDate: exRightsDate.present ? exRightsDate.value : this.exRightsDate,
  );
  DividendHistoryEntry copyWithCompanion(i1.DividendHistoryCompanion data) {
    return DividendHistoryEntry(
      symbol: data.symbol.present ? data.symbol.value : this.symbol,
      year: data.year.present ? data.year.value : this.year,
      cashDividend: data.cashDividend.present
          ? data.cashDividend.value
          : this.cashDividend,
      stockDividend: data.stockDividend.present
          ? data.stockDividend.value
          : this.stockDividend,
      exDividendDate: data.exDividendDate.present
          ? data.exDividendDate.value
          : this.exDividendDate,
      exRightsDate: data.exRightsDate.present
          ? data.exRightsDate.value
          : this.exRightsDate,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DividendHistoryEntry(')
          ..write('symbol: $symbol, ')
          ..write('year: $year, ')
          ..write('cashDividend: $cashDividend, ')
          ..write('stockDividend: $stockDividend, ')
          ..write('exDividendDate: $exDividendDate, ')
          ..write('exRightsDate: $exRightsDate')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    symbol,
    year,
    cashDividend,
    stockDividend,
    exDividendDate,
    exRightsDate,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is i1.DividendHistoryEntry &&
          other.symbol == this.symbol &&
          other.year == this.year &&
          other.cashDividend == this.cashDividend &&
          other.stockDividend == this.stockDividend &&
          other.exDividendDate == this.exDividendDate &&
          other.exRightsDate == this.exRightsDate);
}

class DividendHistoryCompanion
    extends i0.UpdateCompanion<i1.DividendHistoryEntry> {
  final i0.Value<String> symbol;
  final i0.Value<int> year;
  final i0.Value<double> cashDividend;
  final i0.Value<double> stockDividend;
  final i0.Value<String?> exDividendDate;
  final i0.Value<String?> exRightsDate;
  final i0.Value<int> rowid;
  const DividendHistoryCompanion({
    this.symbol = const i0.Value.absent(),
    this.year = const i0.Value.absent(),
    this.cashDividend = const i0.Value.absent(),
    this.stockDividend = const i0.Value.absent(),
    this.exDividendDate = const i0.Value.absent(),
    this.exRightsDate = const i0.Value.absent(),
    this.rowid = const i0.Value.absent(),
  });
  DividendHistoryCompanion.insert({
    required String symbol,
    required int year,
    this.cashDividend = const i0.Value.absent(),
    this.stockDividend = const i0.Value.absent(),
    this.exDividendDate = const i0.Value.absent(),
    this.exRightsDate = const i0.Value.absent(),
    this.rowid = const i0.Value.absent(),
  }) : symbol = i0.Value(symbol),
       year = i0.Value(year);
  static i0.Insertable<i1.DividendHistoryEntry> custom({
    i0.Expression<String>? symbol,
    i0.Expression<int>? year,
    i0.Expression<double>? cashDividend,
    i0.Expression<double>? stockDividend,
    i0.Expression<String>? exDividendDate,
    i0.Expression<String>? exRightsDate,
    i0.Expression<int>? rowid,
  }) {
    return i0.RawValuesInsertable({
      if (symbol != null) 'symbol': symbol,
      if (year != null) 'year': year,
      if (cashDividend != null) 'cash_dividend': cashDividend,
      if (stockDividend != null) 'stock_dividend': stockDividend,
      if (exDividendDate != null) 'ex_dividend_date': exDividendDate,
      if (exRightsDate != null) 'ex_rights_date': exRightsDate,
      if (rowid != null) 'rowid': rowid,
    });
  }

  i1.DividendHistoryCompanion copyWith({
    i0.Value<String>? symbol,
    i0.Value<int>? year,
    i0.Value<double>? cashDividend,
    i0.Value<double>? stockDividend,
    i0.Value<String?>? exDividendDate,
    i0.Value<String?>? exRightsDate,
    i0.Value<int>? rowid,
  }) {
    return i1.DividendHistoryCompanion(
      symbol: symbol ?? this.symbol,
      year: year ?? this.year,
      cashDividend: cashDividend ?? this.cashDividend,
      stockDividend: stockDividend ?? this.stockDividend,
      exDividendDate: exDividendDate ?? this.exDividendDate,
      exRightsDate: exRightsDate ?? this.exRightsDate,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, i0.Expression> toColumns(bool nullToAbsent) {
    final map = <String, i0.Expression>{};
    if (symbol.present) {
      map['symbol'] = i0.Variable<String>(symbol.value);
    }
    if (year.present) {
      map['year'] = i0.Variable<int>(year.value);
    }
    if (cashDividend.present) {
      map['cash_dividend'] = i0.Variable<double>(cashDividend.value);
    }
    if (stockDividend.present) {
      map['stock_dividend'] = i0.Variable<double>(stockDividend.value);
    }
    if (exDividendDate.present) {
      map['ex_dividend_date'] = i0.Variable<String>(exDividendDate.value);
    }
    if (exRightsDate.present) {
      map['ex_rights_date'] = i0.Variable<String>(exRightsDate.value);
    }
    if (rowid.present) {
      map['rowid'] = i0.Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DividendHistoryCompanion(')
          ..write('symbol: $symbol, ')
          ..write('year: $year, ')
          ..write('cashDividend: $cashDividend, ')
          ..write('stockDividend: $stockDividend, ')
          ..write('exDividendDate: $exDividendDate, ')
          ..write('exRightsDate: $exRightsDate, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

i0.Index get idxMonthlyRevenueDate => i0.Index(
  'idx_monthly_revenue_date',
  'CREATE INDEX idx_monthly_revenue_date ON monthly_revenue (date)',
);

class $MonthlyRevenueTable extends i2.MonthlyRevenue
    with i0.TableInfo<$MonthlyRevenueTable, i1.MonthlyRevenueEntry> {
  @override
  final i0.GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MonthlyRevenueTable(this.attachedDatabase, [this._alias]);
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
  static const i0.VerificationMeta _revenueYearMeta = const i0.VerificationMeta(
    'revenueYear',
  );
  @override
  late final i0.GeneratedColumn<int> revenueYear = i0.GeneratedColumn<int>(
    'revenue_year',
    aliasedName,
    false,
    type: i0.DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const i0.VerificationMeta _revenueMonthMeta =
      const i0.VerificationMeta('revenueMonth');
  @override
  late final i0.GeneratedColumn<int> revenueMonth = i0.GeneratedColumn<int>(
    'revenue_month',
    aliasedName,
    false,
    type: i0.DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const i0.VerificationMeta _revenueMeta = const i0.VerificationMeta(
    'revenue',
  );
  @override
  late final i0.GeneratedColumn<double> revenue = i0.GeneratedColumn<double>(
    'revenue',
    aliasedName,
    false,
    type: i0.DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const i0.VerificationMeta _momGrowthMeta = const i0.VerificationMeta(
    'momGrowth',
  );
  @override
  late final i0.GeneratedColumn<double> momGrowth = i0.GeneratedColumn<double>(
    'mom_growth',
    aliasedName,
    true,
    type: i0.DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const i0.VerificationMeta _yoyGrowthMeta = const i0.VerificationMeta(
    'yoyGrowth',
  );
  @override
  late final i0.GeneratedColumn<double> yoyGrowth = i0.GeneratedColumn<double>(
    'yoy_growth',
    aliasedName,
    true,
    type: i0.DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const i0.VerificationMeta _ytdYoyGrowthMeta =
      const i0.VerificationMeta('ytdYoyGrowth');
  @override
  late final i0.GeneratedColumn<double> ytdYoyGrowth =
      i0.GeneratedColumn<double>(
        'ytd_yoy_growth',
        aliasedName,
        true,
        type: i0.DriftSqlType.double,
        requiredDuringInsert: false,
      );
  @override
  List<i0.GeneratedColumn> get $columns => [
    symbol,
    date,
    revenueYear,
    revenueMonth,
    revenue,
    momGrowth,
    yoyGrowth,
    ytdYoyGrowth,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'monthly_revenue';
  @override
  i0.VerificationContext validateIntegrity(
    i0.Insertable<i1.MonthlyRevenueEntry> instance, {
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
    if (data.containsKey('revenue_year')) {
      context.handle(
        _revenueYearMeta,
        revenueYear.isAcceptableOrUnknown(
          data['revenue_year']!,
          _revenueYearMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_revenueYearMeta);
    }
    if (data.containsKey('revenue_month')) {
      context.handle(
        _revenueMonthMeta,
        revenueMonth.isAcceptableOrUnknown(
          data['revenue_month']!,
          _revenueMonthMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_revenueMonthMeta);
    }
    if (data.containsKey('revenue')) {
      context.handle(
        _revenueMeta,
        revenue.isAcceptableOrUnknown(data['revenue']!, _revenueMeta),
      );
    } else if (isInserting) {
      context.missing(_revenueMeta);
    }
    if (data.containsKey('mom_growth')) {
      context.handle(
        _momGrowthMeta,
        momGrowth.isAcceptableOrUnknown(data['mom_growth']!, _momGrowthMeta),
      );
    }
    if (data.containsKey('yoy_growth')) {
      context.handle(
        _yoyGrowthMeta,
        yoyGrowth.isAcceptableOrUnknown(data['yoy_growth']!, _yoyGrowthMeta),
      );
    }
    if (data.containsKey('ytd_yoy_growth')) {
      context.handle(
        _ytdYoyGrowthMeta,
        ytdYoyGrowth.isAcceptableOrUnknown(
          data['ytd_yoy_growth']!,
          _ytdYoyGrowthMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<i0.GeneratedColumn> get $primaryKey => {symbol, date};
  @override
  i1.MonthlyRevenueEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return i1.MonthlyRevenueEntry(
      symbol: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.string,
        data['${effectivePrefix}symbol'],
      )!,
      date: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.dateTime,
        data['${effectivePrefix}date'],
      )!,
      revenueYear: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.int,
        data['${effectivePrefix}revenue_year'],
      )!,
      revenueMonth: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.int,
        data['${effectivePrefix}revenue_month'],
      )!,
      revenue: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.double,
        data['${effectivePrefix}revenue'],
      )!,
      momGrowth: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.double,
        data['${effectivePrefix}mom_growth'],
      ),
      yoyGrowth: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.double,
        data['${effectivePrefix}yoy_growth'],
      ),
      ytdYoyGrowth: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.double,
        data['${effectivePrefix}ytd_yoy_growth'],
      ),
    );
  }

  @override
  $MonthlyRevenueTable createAlias(String alias) {
    return $MonthlyRevenueTable(attachedDatabase, alias);
  }
}

class MonthlyRevenueEntry extends i0.DataClass
    implements i0.Insertable<i1.MonthlyRevenueEntry> {
  /// 股票代碼
  final String symbol;

  /// 報告日期（統一使用當月第一天）
  final DateTime date;

  /// 營收年度
  final int revenueYear;

  /// 營收月份
  final int revenueMonth;

  /// 月營收（千元）
  final double revenue;

  /// 月增率（%）
  final double? momGrowth;

  /// 年增率（%）
  final double? yoyGrowth;

  /// 累計年增率 %(年初至當月 vs 去年同期;2026-08-13 加欄)。
  ///
  /// 來源與單月欄同一支 API(openapi/MOPS 皆自帶),FinMind 歷史回補
  /// 路徑無此資料留 null。既有 DB 由 `_ensureMonthlyRevenueYtdColumn`
  /// 補欄——本表不在 fingerprint 白名單,但 bump 指紋會 wipe 全部非
  /// 白名單表(含 58.7 萬列價格),走 ALTER 前例(dealer_self_net)。
  final double? ytdYoyGrowth;
  const MonthlyRevenueEntry({
    required this.symbol,
    required this.date,
    required this.revenueYear,
    required this.revenueMonth,
    required this.revenue,
    this.momGrowth,
    this.yoyGrowth,
    this.ytdYoyGrowth,
  });
  @override
  Map<String, i0.Expression> toColumns(bool nullToAbsent) {
    final map = <String, i0.Expression>{};
    map['symbol'] = i0.Variable<String>(symbol);
    map['date'] = i0.Variable<DateTime>(date);
    map['revenue_year'] = i0.Variable<int>(revenueYear);
    map['revenue_month'] = i0.Variable<int>(revenueMonth);
    map['revenue'] = i0.Variable<double>(revenue);
    if (!nullToAbsent || momGrowth != null) {
      map['mom_growth'] = i0.Variable<double>(momGrowth);
    }
    if (!nullToAbsent || yoyGrowth != null) {
      map['yoy_growth'] = i0.Variable<double>(yoyGrowth);
    }
    if (!nullToAbsent || ytdYoyGrowth != null) {
      map['ytd_yoy_growth'] = i0.Variable<double>(ytdYoyGrowth);
    }
    return map;
  }

  i1.MonthlyRevenueCompanion toCompanion(bool nullToAbsent) {
    return i1.MonthlyRevenueCompanion(
      symbol: i0.Value(symbol),
      date: i0.Value(date),
      revenueYear: i0.Value(revenueYear),
      revenueMonth: i0.Value(revenueMonth),
      revenue: i0.Value(revenue),
      momGrowth: momGrowth == null && nullToAbsent
          ? const i0.Value.absent()
          : i0.Value(momGrowth),
      yoyGrowth: yoyGrowth == null && nullToAbsent
          ? const i0.Value.absent()
          : i0.Value(yoyGrowth),
      ytdYoyGrowth: ytdYoyGrowth == null && nullToAbsent
          ? const i0.Value.absent()
          : i0.Value(ytdYoyGrowth),
    );
  }

  factory MonthlyRevenueEntry.fromJson(
    Map<String, dynamic> json, {
    i0.ValueSerializer? serializer,
  }) {
    serializer ??= i0.driftRuntimeOptions.defaultSerializer;
    return MonthlyRevenueEntry(
      symbol: serializer.fromJson<String>(json['symbol']),
      date: serializer.fromJson<DateTime>(json['date']),
      revenueYear: serializer.fromJson<int>(json['revenueYear']),
      revenueMonth: serializer.fromJson<int>(json['revenueMonth']),
      revenue: serializer.fromJson<double>(json['revenue']),
      momGrowth: serializer.fromJson<double?>(json['momGrowth']),
      yoyGrowth: serializer.fromJson<double?>(json['yoyGrowth']),
      ytdYoyGrowth: serializer.fromJson<double?>(json['ytdYoyGrowth']),
    );
  }
  @override
  Map<String, dynamic> toJson({i0.ValueSerializer? serializer}) {
    serializer ??= i0.driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'symbol': serializer.toJson<String>(symbol),
      'date': serializer.toJson<DateTime>(date),
      'revenueYear': serializer.toJson<int>(revenueYear),
      'revenueMonth': serializer.toJson<int>(revenueMonth),
      'revenue': serializer.toJson<double>(revenue),
      'momGrowth': serializer.toJson<double?>(momGrowth),
      'yoyGrowth': serializer.toJson<double?>(yoyGrowth),
      'ytdYoyGrowth': serializer.toJson<double?>(ytdYoyGrowth),
    };
  }

  i1.MonthlyRevenueEntry copyWith({
    String? symbol,
    DateTime? date,
    int? revenueYear,
    int? revenueMonth,
    double? revenue,
    i0.Value<double?> momGrowth = const i0.Value.absent(),
    i0.Value<double?> yoyGrowth = const i0.Value.absent(),
    i0.Value<double?> ytdYoyGrowth = const i0.Value.absent(),
  }) => i1.MonthlyRevenueEntry(
    symbol: symbol ?? this.symbol,
    date: date ?? this.date,
    revenueYear: revenueYear ?? this.revenueYear,
    revenueMonth: revenueMonth ?? this.revenueMonth,
    revenue: revenue ?? this.revenue,
    momGrowth: momGrowth.present ? momGrowth.value : this.momGrowth,
    yoyGrowth: yoyGrowth.present ? yoyGrowth.value : this.yoyGrowth,
    ytdYoyGrowth: ytdYoyGrowth.present ? ytdYoyGrowth.value : this.ytdYoyGrowth,
  );
  MonthlyRevenueEntry copyWithCompanion(i1.MonthlyRevenueCompanion data) {
    return MonthlyRevenueEntry(
      symbol: data.symbol.present ? data.symbol.value : this.symbol,
      date: data.date.present ? data.date.value : this.date,
      revenueYear: data.revenueYear.present
          ? data.revenueYear.value
          : this.revenueYear,
      revenueMonth: data.revenueMonth.present
          ? data.revenueMonth.value
          : this.revenueMonth,
      revenue: data.revenue.present ? data.revenue.value : this.revenue,
      momGrowth: data.momGrowth.present ? data.momGrowth.value : this.momGrowth,
      yoyGrowth: data.yoyGrowth.present ? data.yoyGrowth.value : this.yoyGrowth,
      ytdYoyGrowth: data.ytdYoyGrowth.present
          ? data.ytdYoyGrowth.value
          : this.ytdYoyGrowth,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MonthlyRevenueEntry(')
          ..write('symbol: $symbol, ')
          ..write('date: $date, ')
          ..write('revenueYear: $revenueYear, ')
          ..write('revenueMonth: $revenueMonth, ')
          ..write('revenue: $revenue, ')
          ..write('momGrowth: $momGrowth, ')
          ..write('yoyGrowth: $yoyGrowth, ')
          ..write('ytdYoyGrowth: $ytdYoyGrowth')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    symbol,
    date,
    revenueYear,
    revenueMonth,
    revenue,
    momGrowth,
    yoyGrowth,
    ytdYoyGrowth,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is i1.MonthlyRevenueEntry &&
          other.symbol == this.symbol &&
          other.date == this.date &&
          other.revenueYear == this.revenueYear &&
          other.revenueMonth == this.revenueMonth &&
          other.revenue == this.revenue &&
          other.momGrowth == this.momGrowth &&
          other.yoyGrowth == this.yoyGrowth &&
          other.ytdYoyGrowth == this.ytdYoyGrowth);
}

class MonthlyRevenueCompanion
    extends i0.UpdateCompanion<i1.MonthlyRevenueEntry> {
  final i0.Value<String> symbol;
  final i0.Value<DateTime> date;
  final i0.Value<int> revenueYear;
  final i0.Value<int> revenueMonth;
  final i0.Value<double> revenue;
  final i0.Value<double?> momGrowth;
  final i0.Value<double?> yoyGrowth;
  final i0.Value<double?> ytdYoyGrowth;
  final i0.Value<int> rowid;
  const MonthlyRevenueCompanion({
    this.symbol = const i0.Value.absent(),
    this.date = const i0.Value.absent(),
    this.revenueYear = const i0.Value.absent(),
    this.revenueMonth = const i0.Value.absent(),
    this.revenue = const i0.Value.absent(),
    this.momGrowth = const i0.Value.absent(),
    this.yoyGrowth = const i0.Value.absent(),
    this.ytdYoyGrowth = const i0.Value.absent(),
    this.rowid = const i0.Value.absent(),
  });
  MonthlyRevenueCompanion.insert({
    required String symbol,
    required DateTime date,
    required int revenueYear,
    required int revenueMonth,
    required double revenue,
    this.momGrowth = const i0.Value.absent(),
    this.yoyGrowth = const i0.Value.absent(),
    this.ytdYoyGrowth = const i0.Value.absent(),
    this.rowid = const i0.Value.absent(),
  }) : symbol = i0.Value(symbol),
       date = i0.Value(date),
       revenueYear = i0.Value(revenueYear),
       revenueMonth = i0.Value(revenueMonth),
       revenue = i0.Value(revenue);
  static i0.Insertable<i1.MonthlyRevenueEntry> custom({
    i0.Expression<String>? symbol,
    i0.Expression<DateTime>? date,
    i0.Expression<int>? revenueYear,
    i0.Expression<int>? revenueMonth,
    i0.Expression<double>? revenue,
    i0.Expression<double>? momGrowth,
    i0.Expression<double>? yoyGrowth,
    i0.Expression<double>? ytdYoyGrowth,
    i0.Expression<int>? rowid,
  }) {
    return i0.RawValuesInsertable({
      if (symbol != null) 'symbol': symbol,
      if (date != null) 'date': date,
      if (revenueYear != null) 'revenue_year': revenueYear,
      if (revenueMonth != null) 'revenue_month': revenueMonth,
      if (revenue != null) 'revenue': revenue,
      if (momGrowth != null) 'mom_growth': momGrowth,
      if (yoyGrowth != null) 'yoy_growth': yoyGrowth,
      if (ytdYoyGrowth != null) 'ytd_yoy_growth': ytdYoyGrowth,
      if (rowid != null) 'rowid': rowid,
    });
  }

  i1.MonthlyRevenueCompanion copyWith({
    i0.Value<String>? symbol,
    i0.Value<DateTime>? date,
    i0.Value<int>? revenueYear,
    i0.Value<int>? revenueMonth,
    i0.Value<double>? revenue,
    i0.Value<double?>? momGrowth,
    i0.Value<double?>? yoyGrowth,
    i0.Value<double?>? ytdYoyGrowth,
    i0.Value<int>? rowid,
  }) {
    return i1.MonthlyRevenueCompanion(
      symbol: symbol ?? this.symbol,
      date: date ?? this.date,
      revenueYear: revenueYear ?? this.revenueYear,
      revenueMonth: revenueMonth ?? this.revenueMonth,
      revenue: revenue ?? this.revenue,
      momGrowth: momGrowth ?? this.momGrowth,
      yoyGrowth: yoyGrowth ?? this.yoyGrowth,
      ytdYoyGrowth: ytdYoyGrowth ?? this.ytdYoyGrowth,
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
    if (revenueYear.present) {
      map['revenue_year'] = i0.Variable<int>(revenueYear.value);
    }
    if (revenueMonth.present) {
      map['revenue_month'] = i0.Variable<int>(revenueMonth.value);
    }
    if (revenue.present) {
      map['revenue'] = i0.Variable<double>(revenue.value);
    }
    if (momGrowth.present) {
      map['mom_growth'] = i0.Variable<double>(momGrowth.value);
    }
    if (yoyGrowth.present) {
      map['yoy_growth'] = i0.Variable<double>(yoyGrowth.value);
    }
    if (ytdYoyGrowth.present) {
      map['ytd_yoy_growth'] = i0.Variable<double>(ytdYoyGrowth.value);
    }
    if (rowid.present) {
      map['rowid'] = i0.Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MonthlyRevenueCompanion(')
          ..write('symbol: $symbol, ')
          ..write('date: $date, ')
          ..write('revenueYear: $revenueYear, ')
          ..write('revenueMonth: $revenueMonth, ')
          ..write('revenue: $revenue, ')
          ..write('momGrowth: $momGrowth, ')
          ..write('yoyGrowth: $yoyGrowth, ')
          ..write('ytdYoyGrowth: $ytdYoyGrowth, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

i0.Index get idxStockValuationDate => i0.Index(
  'idx_stock_valuation_date',
  'CREATE INDEX idx_stock_valuation_date ON stock_valuation (date)',
);

class $StockValuationTable extends i2.StockValuation
    with i0.TableInfo<$StockValuationTable, i1.StockValuationEntry> {
  @override
  final i0.GeneratedDatabase attachedDatabase;
  final String? _alias;
  $StockValuationTable(this.attachedDatabase, [this._alias]);
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
  static const i0.VerificationMeta _perMeta = const i0.VerificationMeta('per');
  @override
  late final i0.GeneratedColumn<double> per = i0.GeneratedColumn<double>(
    'per',
    aliasedName,
    true,
    type: i0.DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const i0.VerificationMeta _pbrMeta = const i0.VerificationMeta('pbr');
  @override
  late final i0.GeneratedColumn<double> pbr = i0.GeneratedColumn<double>(
    'pbr',
    aliasedName,
    true,
    type: i0.DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const i0.VerificationMeta _dividendYieldMeta =
      const i0.VerificationMeta('dividendYield');
  @override
  late final i0.GeneratedColumn<double> dividendYield =
      i0.GeneratedColumn<double>(
        'dividend_yield',
        aliasedName,
        true,
        type: i0.DriftSqlType.double,
        requiredDuringInsert: false,
      );
  @override
  List<i0.GeneratedColumn> get $columns => [
    symbol,
    date,
    per,
    pbr,
    dividendYield,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'stock_valuation';
  @override
  i0.VerificationContext validateIntegrity(
    i0.Insertable<i1.StockValuationEntry> instance, {
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
    if (data.containsKey('per')) {
      context.handle(
        _perMeta,
        per.isAcceptableOrUnknown(data['per']!, _perMeta),
      );
    }
    if (data.containsKey('pbr')) {
      context.handle(
        _pbrMeta,
        pbr.isAcceptableOrUnknown(data['pbr']!, _pbrMeta),
      );
    }
    if (data.containsKey('dividend_yield')) {
      context.handle(
        _dividendYieldMeta,
        dividendYield.isAcceptableOrUnknown(
          data['dividend_yield']!,
          _dividendYieldMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<i0.GeneratedColumn> get $primaryKey => {symbol, date};
  @override
  i1.StockValuationEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return i1.StockValuationEntry(
      symbol: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.string,
        data['${effectivePrefix}symbol'],
      )!,
      date: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.dateTime,
        data['${effectivePrefix}date'],
      )!,
      per: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.double,
        data['${effectivePrefix}per'],
      ),
      pbr: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.double,
        data['${effectivePrefix}pbr'],
      ),
      dividendYield: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.double,
        data['${effectivePrefix}dividend_yield'],
      ),
    );
  }

  @override
  $StockValuationTable createAlias(String alias) {
    return $StockValuationTable(attachedDatabase, alias);
  }
}

class StockValuationEntry extends i0.DataClass
    implements i0.Insertable<i1.StockValuationEntry> {
  /// 股票代碼
  final String symbol;

  /// 交易日期
  final DateTime date;

  /// 本益比（PE ratio）
  final double? per;

  /// 股價淨值比（PB ratio）
  final double? pbr;

  /// 殖利率（%）
  final double? dividendYield;
  const StockValuationEntry({
    required this.symbol,
    required this.date,
    this.per,
    this.pbr,
    this.dividendYield,
  });
  @override
  Map<String, i0.Expression> toColumns(bool nullToAbsent) {
    final map = <String, i0.Expression>{};
    map['symbol'] = i0.Variable<String>(symbol);
    map['date'] = i0.Variable<DateTime>(date);
    if (!nullToAbsent || per != null) {
      map['per'] = i0.Variable<double>(per);
    }
    if (!nullToAbsent || pbr != null) {
      map['pbr'] = i0.Variable<double>(pbr);
    }
    if (!nullToAbsent || dividendYield != null) {
      map['dividend_yield'] = i0.Variable<double>(dividendYield);
    }
    return map;
  }

  i1.StockValuationCompanion toCompanion(bool nullToAbsent) {
    return i1.StockValuationCompanion(
      symbol: i0.Value(symbol),
      date: i0.Value(date),
      per: per == null && nullToAbsent
          ? const i0.Value.absent()
          : i0.Value(per),
      pbr: pbr == null && nullToAbsent
          ? const i0.Value.absent()
          : i0.Value(pbr),
      dividendYield: dividendYield == null && nullToAbsent
          ? const i0.Value.absent()
          : i0.Value(dividendYield),
    );
  }

  factory StockValuationEntry.fromJson(
    Map<String, dynamic> json, {
    i0.ValueSerializer? serializer,
  }) {
    serializer ??= i0.driftRuntimeOptions.defaultSerializer;
    return StockValuationEntry(
      symbol: serializer.fromJson<String>(json['symbol']),
      date: serializer.fromJson<DateTime>(json['date']),
      per: serializer.fromJson<double?>(json['per']),
      pbr: serializer.fromJson<double?>(json['pbr']),
      dividendYield: serializer.fromJson<double?>(json['dividendYield']),
    );
  }
  @override
  Map<String, dynamic> toJson({i0.ValueSerializer? serializer}) {
    serializer ??= i0.driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'symbol': serializer.toJson<String>(symbol),
      'date': serializer.toJson<DateTime>(date),
      'per': serializer.toJson<double?>(per),
      'pbr': serializer.toJson<double?>(pbr),
      'dividendYield': serializer.toJson<double?>(dividendYield),
    };
  }

  i1.StockValuationEntry copyWith({
    String? symbol,
    DateTime? date,
    i0.Value<double?> per = const i0.Value.absent(),
    i0.Value<double?> pbr = const i0.Value.absent(),
    i0.Value<double?> dividendYield = const i0.Value.absent(),
  }) => i1.StockValuationEntry(
    symbol: symbol ?? this.symbol,
    date: date ?? this.date,
    per: per.present ? per.value : this.per,
    pbr: pbr.present ? pbr.value : this.pbr,
    dividendYield: dividendYield.present
        ? dividendYield.value
        : this.dividendYield,
  );
  StockValuationEntry copyWithCompanion(i1.StockValuationCompanion data) {
    return StockValuationEntry(
      symbol: data.symbol.present ? data.symbol.value : this.symbol,
      date: data.date.present ? data.date.value : this.date,
      per: data.per.present ? data.per.value : this.per,
      pbr: data.pbr.present ? data.pbr.value : this.pbr,
      dividendYield: data.dividendYield.present
          ? data.dividendYield.value
          : this.dividendYield,
    );
  }

  @override
  String toString() {
    return (StringBuffer('StockValuationEntry(')
          ..write('symbol: $symbol, ')
          ..write('date: $date, ')
          ..write('per: $per, ')
          ..write('pbr: $pbr, ')
          ..write('dividendYield: $dividendYield')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(symbol, date, per, pbr, dividendYield);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is i1.StockValuationEntry &&
          other.symbol == this.symbol &&
          other.date == this.date &&
          other.per == this.per &&
          other.pbr == this.pbr &&
          other.dividendYield == this.dividendYield);
}

class StockValuationCompanion
    extends i0.UpdateCompanion<i1.StockValuationEntry> {
  final i0.Value<String> symbol;
  final i0.Value<DateTime> date;
  final i0.Value<double?> per;
  final i0.Value<double?> pbr;
  final i0.Value<double?> dividendYield;
  final i0.Value<int> rowid;
  const StockValuationCompanion({
    this.symbol = const i0.Value.absent(),
    this.date = const i0.Value.absent(),
    this.per = const i0.Value.absent(),
    this.pbr = const i0.Value.absent(),
    this.dividendYield = const i0.Value.absent(),
    this.rowid = const i0.Value.absent(),
  });
  StockValuationCompanion.insert({
    required String symbol,
    required DateTime date,
    this.per = const i0.Value.absent(),
    this.pbr = const i0.Value.absent(),
    this.dividendYield = const i0.Value.absent(),
    this.rowid = const i0.Value.absent(),
  }) : symbol = i0.Value(symbol),
       date = i0.Value(date);
  static i0.Insertable<i1.StockValuationEntry> custom({
    i0.Expression<String>? symbol,
    i0.Expression<DateTime>? date,
    i0.Expression<double>? per,
    i0.Expression<double>? pbr,
    i0.Expression<double>? dividendYield,
    i0.Expression<int>? rowid,
  }) {
    return i0.RawValuesInsertable({
      if (symbol != null) 'symbol': symbol,
      if (date != null) 'date': date,
      if (per != null) 'per': per,
      if (pbr != null) 'pbr': pbr,
      if (dividendYield != null) 'dividend_yield': dividendYield,
      if (rowid != null) 'rowid': rowid,
    });
  }

  i1.StockValuationCompanion copyWith({
    i0.Value<String>? symbol,
    i0.Value<DateTime>? date,
    i0.Value<double?>? per,
    i0.Value<double?>? pbr,
    i0.Value<double?>? dividendYield,
    i0.Value<int>? rowid,
  }) {
    return i1.StockValuationCompanion(
      symbol: symbol ?? this.symbol,
      date: date ?? this.date,
      per: per ?? this.per,
      pbr: pbr ?? this.pbr,
      dividendYield: dividendYield ?? this.dividendYield,
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
    if (per.present) {
      map['per'] = i0.Variable<double>(per.value);
    }
    if (pbr.present) {
      map['pbr'] = i0.Variable<double>(pbr.value);
    }
    if (dividendYield.present) {
      map['dividend_yield'] = i0.Variable<double>(dividendYield.value);
    }
    if (rowid.present) {
      map['rowid'] = i0.Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('StockValuationCompanion(')
          ..write('symbol: $symbol, ')
          ..write('date: $date, ')
          ..write('per: $per, ')
          ..write('pbr: $pbr, ')
          ..write('dividendYield: $dividendYield, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

i0.Index get idxMarginTradingDate => i0.Index(
  'idx_margin_trading_date',
  'CREATE INDEX idx_margin_trading_date ON margin_trading (date)',
);

class $MarginTradingTable extends i2.MarginTrading
    with i0.TableInfo<$MarginTradingTable, i1.MarginTradingEntry> {
  @override
  final i0.GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MarginTradingTable(this.attachedDatabase, [this._alias]);
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
  static const i0.VerificationMeta _marginBuyMeta = const i0.VerificationMeta(
    'marginBuy',
  );
  @override
  late final i0.GeneratedColumn<double> marginBuy = i0.GeneratedColumn<double>(
    'margin_buy',
    aliasedName,
    true,
    type: i0.DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const i0.VerificationMeta _marginSellMeta = const i0.VerificationMeta(
    'marginSell',
  );
  @override
  late final i0.GeneratedColumn<double> marginSell = i0.GeneratedColumn<double>(
    'margin_sell',
    aliasedName,
    true,
    type: i0.DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const i0.VerificationMeta _marginBalanceMeta =
      const i0.VerificationMeta('marginBalance');
  @override
  late final i0.GeneratedColumn<double> marginBalance =
      i0.GeneratedColumn<double>(
        'margin_balance',
        aliasedName,
        true,
        type: i0.DriftSqlType.double,
        requiredDuringInsert: false,
      );
  static const i0.VerificationMeta _shortBuyMeta = const i0.VerificationMeta(
    'shortBuy',
  );
  @override
  late final i0.GeneratedColumn<double> shortBuy = i0.GeneratedColumn<double>(
    'short_buy',
    aliasedName,
    true,
    type: i0.DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const i0.VerificationMeta _shortSellMeta = const i0.VerificationMeta(
    'shortSell',
  );
  @override
  late final i0.GeneratedColumn<double> shortSell = i0.GeneratedColumn<double>(
    'short_sell',
    aliasedName,
    true,
    type: i0.DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const i0.VerificationMeta _shortBalanceMeta =
      const i0.VerificationMeta('shortBalance');
  @override
  late final i0.GeneratedColumn<double> shortBalance =
      i0.GeneratedColumn<double>(
        'short_balance',
        aliasedName,
        true,
        type: i0.DriftSqlType.double,
        requiredDuringInsert: false,
      );
  @override
  List<i0.GeneratedColumn> get $columns => [
    symbol,
    date,
    marginBuy,
    marginSell,
    marginBalance,
    shortBuy,
    shortSell,
    shortBalance,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'margin_trading';
  @override
  i0.VerificationContext validateIntegrity(
    i0.Insertable<i1.MarginTradingEntry> instance, {
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
    if (data.containsKey('margin_buy')) {
      context.handle(
        _marginBuyMeta,
        marginBuy.isAcceptableOrUnknown(data['margin_buy']!, _marginBuyMeta),
      );
    }
    if (data.containsKey('margin_sell')) {
      context.handle(
        _marginSellMeta,
        marginSell.isAcceptableOrUnknown(data['margin_sell']!, _marginSellMeta),
      );
    }
    if (data.containsKey('margin_balance')) {
      context.handle(
        _marginBalanceMeta,
        marginBalance.isAcceptableOrUnknown(
          data['margin_balance']!,
          _marginBalanceMeta,
        ),
      );
    }
    if (data.containsKey('short_buy')) {
      context.handle(
        _shortBuyMeta,
        shortBuy.isAcceptableOrUnknown(data['short_buy']!, _shortBuyMeta),
      );
    }
    if (data.containsKey('short_sell')) {
      context.handle(
        _shortSellMeta,
        shortSell.isAcceptableOrUnknown(data['short_sell']!, _shortSellMeta),
      );
    }
    if (data.containsKey('short_balance')) {
      context.handle(
        _shortBalanceMeta,
        shortBalance.isAcceptableOrUnknown(
          data['short_balance']!,
          _shortBalanceMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<i0.GeneratedColumn> get $primaryKey => {symbol, date};
  @override
  i1.MarginTradingEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return i1.MarginTradingEntry(
      symbol: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.string,
        data['${effectivePrefix}symbol'],
      )!,
      date: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.dateTime,
        data['${effectivePrefix}date'],
      )!,
      marginBuy: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.double,
        data['${effectivePrefix}margin_buy'],
      ),
      marginSell: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.double,
        data['${effectivePrefix}margin_sell'],
      ),
      marginBalance: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.double,
        data['${effectivePrefix}margin_balance'],
      ),
      shortBuy: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.double,
        data['${effectivePrefix}short_buy'],
      ),
      shortSell: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.double,
        data['${effectivePrefix}short_sell'],
      ),
      shortBalance: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.double,
        data['${effectivePrefix}short_balance'],
      ),
    );
  }

  @override
  $MarginTradingTable createAlias(String alias) {
    return $MarginTradingTable(attachedDatabase, alias);
  }
}

class MarginTradingEntry extends i0.DataClass
    implements i0.Insertable<i1.MarginTradingEntry> {
  /// 股票代碼
  final String symbol;

  /// 交易日期
  final DateTime date;

  /// 融資買進（張）
  final double? marginBuy;

  /// 融資賣出（張）
  final double? marginSell;

  /// 融資餘額（張）
  final double? marginBalance;

  /// 融券買進/回補（張）
  final double? shortBuy;

  /// 融券賣出（張）
  final double? shortSell;

  /// 融券餘額（張）
  final double? shortBalance;
  const MarginTradingEntry({
    required this.symbol,
    required this.date,
    this.marginBuy,
    this.marginSell,
    this.marginBalance,
    this.shortBuy,
    this.shortSell,
    this.shortBalance,
  });
  @override
  Map<String, i0.Expression> toColumns(bool nullToAbsent) {
    final map = <String, i0.Expression>{};
    map['symbol'] = i0.Variable<String>(symbol);
    map['date'] = i0.Variable<DateTime>(date);
    if (!nullToAbsent || marginBuy != null) {
      map['margin_buy'] = i0.Variable<double>(marginBuy);
    }
    if (!nullToAbsent || marginSell != null) {
      map['margin_sell'] = i0.Variable<double>(marginSell);
    }
    if (!nullToAbsent || marginBalance != null) {
      map['margin_balance'] = i0.Variable<double>(marginBalance);
    }
    if (!nullToAbsent || shortBuy != null) {
      map['short_buy'] = i0.Variable<double>(shortBuy);
    }
    if (!nullToAbsent || shortSell != null) {
      map['short_sell'] = i0.Variable<double>(shortSell);
    }
    if (!nullToAbsent || shortBalance != null) {
      map['short_balance'] = i0.Variable<double>(shortBalance);
    }
    return map;
  }

  i1.MarginTradingCompanion toCompanion(bool nullToAbsent) {
    return i1.MarginTradingCompanion(
      symbol: i0.Value(symbol),
      date: i0.Value(date),
      marginBuy: marginBuy == null && nullToAbsent
          ? const i0.Value.absent()
          : i0.Value(marginBuy),
      marginSell: marginSell == null && nullToAbsent
          ? const i0.Value.absent()
          : i0.Value(marginSell),
      marginBalance: marginBalance == null && nullToAbsent
          ? const i0.Value.absent()
          : i0.Value(marginBalance),
      shortBuy: shortBuy == null && nullToAbsent
          ? const i0.Value.absent()
          : i0.Value(shortBuy),
      shortSell: shortSell == null && nullToAbsent
          ? const i0.Value.absent()
          : i0.Value(shortSell),
      shortBalance: shortBalance == null && nullToAbsent
          ? const i0.Value.absent()
          : i0.Value(shortBalance),
    );
  }

  factory MarginTradingEntry.fromJson(
    Map<String, dynamic> json, {
    i0.ValueSerializer? serializer,
  }) {
    serializer ??= i0.driftRuntimeOptions.defaultSerializer;
    return MarginTradingEntry(
      symbol: serializer.fromJson<String>(json['symbol']),
      date: serializer.fromJson<DateTime>(json['date']),
      marginBuy: serializer.fromJson<double?>(json['marginBuy']),
      marginSell: serializer.fromJson<double?>(json['marginSell']),
      marginBalance: serializer.fromJson<double?>(json['marginBalance']),
      shortBuy: serializer.fromJson<double?>(json['shortBuy']),
      shortSell: serializer.fromJson<double?>(json['shortSell']),
      shortBalance: serializer.fromJson<double?>(json['shortBalance']),
    );
  }
  @override
  Map<String, dynamic> toJson({i0.ValueSerializer? serializer}) {
    serializer ??= i0.driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'symbol': serializer.toJson<String>(symbol),
      'date': serializer.toJson<DateTime>(date),
      'marginBuy': serializer.toJson<double?>(marginBuy),
      'marginSell': serializer.toJson<double?>(marginSell),
      'marginBalance': serializer.toJson<double?>(marginBalance),
      'shortBuy': serializer.toJson<double?>(shortBuy),
      'shortSell': serializer.toJson<double?>(shortSell),
      'shortBalance': serializer.toJson<double?>(shortBalance),
    };
  }

  i1.MarginTradingEntry copyWith({
    String? symbol,
    DateTime? date,
    i0.Value<double?> marginBuy = const i0.Value.absent(),
    i0.Value<double?> marginSell = const i0.Value.absent(),
    i0.Value<double?> marginBalance = const i0.Value.absent(),
    i0.Value<double?> shortBuy = const i0.Value.absent(),
    i0.Value<double?> shortSell = const i0.Value.absent(),
    i0.Value<double?> shortBalance = const i0.Value.absent(),
  }) => i1.MarginTradingEntry(
    symbol: symbol ?? this.symbol,
    date: date ?? this.date,
    marginBuy: marginBuy.present ? marginBuy.value : this.marginBuy,
    marginSell: marginSell.present ? marginSell.value : this.marginSell,
    marginBalance: marginBalance.present
        ? marginBalance.value
        : this.marginBalance,
    shortBuy: shortBuy.present ? shortBuy.value : this.shortBuy,
    shortSell: shortSell.present ? shortSell.value : this.shortSell,
    shortBalance: shortBalance.present ? shortBalance.value : this.shortBalance,
  );
  MarginTradingEntry copyWithCompanion(i1.MarginTradingCompanion data) {
    return MarginTradingEntry(
      symbol: data.symbol.present ? data.symbol.value : this.symbol,
      date: data.date.present ? data.date.value : this.date,
      marginBuy: data.marginBuy.present ? data.marginBuy.value : this.marginBuy,
      marginSell: data.marginSell.present
          ? data.marginSell.value
          : this.marginSell,
      marginBalance: data.marginBalance.present
          ? data.marginBalance.value
          : this.marginBalance,
      shortBuy: data.shortBuy.present ? data.shortBuy.value : this.shortBuy,
      shortSell: data.shortSell.present ? data.shortSell.value : this.shortSell,
      shortBalance: data.shortBalance.present
          ? data.shortBalance.value
          : this.shortBalance,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MarginTradingEntry(')
          ..write('symbol: $symbol, ')
          ..write('date: $date, ')
          ..write('marginBuy: $marginBuy, ')
          ..write('marginSell: $marginSell, ')
          ..write('marginBalance: $marginBalance, ')
          ..write('shortBuy: $shortBuy, ')
          ..write('shortSell: $shortSell, ')
          ..write('shortBalance: $shortBalance')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    symbol,
    date,
    marginBuy,
    marginSell,
    marginBalance,
    shortBuy,
    shortSell,
    shortBalance,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is i1.MarginTradingEntry &&
          other.symbol == this.symbol &&
          other.date == this.date &&
          other.marginBuy == this.marginBuy &&
          other.marginSell == this.marginSell &&
          other.marginBalance == this.marginBalance &&
          other.shortBuy == this.shortBuy &&
          other.shortSell == this.shortSell &&
          other.shortBalance == this.shortBalance);
}

class MarginTradingCompanion extends i0.UpdateCompanion<i1.MarginTradingEntry> {
  final i0.Value<String> symbol;
  final i0.Value<DateTime> date;
  final i0.Value<double?> marginBuy;
  final i0.Value<double?> marginSell;
  final i0.Value<double?> marginBalance;
  final i0.Value<double?> shortBuy;
  final i0.Value<double?> shortSell;
  final i0.Value<double?> shortBalance;
  final i0.Value<int> rowid;
  const MarginTradingCompanion({
    this.symbol = const i0.Value.absent(),
    this.date = const i0.Value.absent(),
    this.marginBuy = const i0.Value.absent(),
    this.marginSell = const i0.Value.absent(),
    this.marginBalance = const i0.Value.absent(),
    this.shortBuy = const i0.Value.absent(),
    this.shortSell = const i0.Value.absent(),
    this.shortBalance = const i0.Value.absent(),
    this.rowid = const i0.Value.absent(),
  });
  MarginTradingCompanion.insert({
    required String symbol,
    required DateTime date,
    this.marginBuy = const i0.Value.absent(),
    this.marginSell = const i0.Value.absent(),
    this.marginBalance = const i0.Value.absent(),
    this.shortBuy = const i0.Value.absent(),
    this.shortSell = const i0.Value.absent(),
    this.shortBalance = const i0.Value.absent(),
    this.rowid = const i0.Value.absent(),
  }) : symbol = i0.Value(symbol),
       date = i0.Value(date);
  static i0.Insertable<i1.MarginTradingEntry> custom({
    i0.Expression<String>? symbol,
    i0.Expression<DateTime>? date,
    i0.Expression<double>? marginBuy,
    i0.Expression<double>? marginSell,
    i0.Expression<double>? marginBalance,
    i0.Expression<double>? shortBuy,
    i0.Expression<double>? shortSell,
    i0.Expression<double>? shortBalance,
    i0.Expression<int>? rowid,
  }) {
    return i0.RawValuesInsertable({
      if (symbol != null) 'symbol': symbol,
      if (date != null) 'date': date,
      if (marginBuy != null) 'margin_buy': marginBuy,
      if (marginSell != null) 'margin_sell': marginSell,
      if (marginBalance != null) 'margin_balance': marginBalance,
      if (shortBuy != null) 'short_buy': shortBuy,
      if (shortSell != null) 'short_sell': shortSell,
      if (shortBalance != null) 'short_balance': shortBalance,
      if (rowid != null) 'rowid': rowid,
    });
  }

  i1.MarginTradingCompanion copyWith({
    i0.Value<String>? symbol,
    i0.Value<DateTime>? date,
    i0.Value<double?>? marginBuy,
    i0.Value<double?>? marginSell,
    i0.Value<double?>? marginBalance,
    i0.Value<double?>? shortBuy,
    i0.Value<double?>? shortSell,
    i0.Value<double?>? shortBalance,
    i0.Value<int>? rowid,
  }) {
    return i1.MarginTradingCompanion(
      symbol: symbol ?? this.symbol,
      date: date ?? this.date,
      marginBuy: marginBuy ?? this.marginBuy,
      marginSell: marginSell ?? this.marginSell,
      marginBalance: marginBalance ?? this.marginBalance,
      shortBuy: shortBuy ?? this.shortBuy,
      shortSell: shortSell ?? this.shortSell,
      shortBalance: shortBalance ?? this.shortBalance,
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
    if (marginBuy.present) {
      map['margin_buy'] = i0.Variable<double>(marginBuy.value);
    }
    if (marginSell.present) {
      map['margin_sell'] = i0.Variable<double>(marginSell.value);
    }
    if (marginBalance.present) {
      map['margin_balance'] = i0.Variable<double>(marginBalance.value);
    }
    if (shortBuy.present) {
      map['short_buy'] = i0.Variable<double>(shortBuy.value);
    }
    if (shortSell.present) {
      map['short_sell'] = i0.Variable<double>(shortSell.value);
    }
    if (shortBalance.present) {
      map['short_balance'] = i0.Variable<double>(shortBalance.value);
    }
    if (rowid.present) {
      map['rowid'] = i0.Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MarginTradingCompanion(')
          ..write('symbol: $symbol, ')
          ..write('date: $date, ')
          ..write('marginBuy: $marginBuy, ')
          ..write('marginSell: $marginSell, ')
          ..write('marginBalance: $marginBalance, ')
          ..write('shortBuy: $shortBuy, ')
          ..write('shortSell: $shortSell, ')
          ..write('shortBalance: $shortBalance, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

i0.Index get idxTradingWarningDate => i0.Index(
  'idx_trading_warning_date',
  'CREATE INDEX idx_trading_warning_date ON trading_warning (date)',
);

class $TradingWarningTable extends i2.TradingWarning
    with i0.TableInfo<$TradingWarningTable, i1.TradingWarningEntry> {
  @override
  final i0.GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TradingWarningTable(this.attachedDatabase, [this._alias]);
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
  static const i0.VerificationMeta _warningTypeMeta = const i0.VerificationMeta(
    'warningType',
  );
  @override
  late final i0.GeneratedColumn<String> warningType =
      i0.GeneratedColumn<String>(
        'warning_type',
        aliasedName,
        false,
        type: i0.DriftSqlType.string,
        requiredDuringInsert: true,
      );
  static const i0.VerificationMeta _reasonCodeMeta = const i0.VerificationMeta(
    'reasonCode',
  );
  @override
  late final i0.GeneratedColumn<String> reasonCode = i0.GeneratedColumn<String>(
    'reason_code',
    aliasedName,
    true,
    type: i0.DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const i0.VerificationMeta _reasonDescriptionMeta =
      const i0.VerificationMeta('reasonDescription');
  @override
  late final i0.GeneratedColumn<String> reasonDescription =
      i0.GeneratedColumn<String>(
        'reason_description',
        aliasedName,
        true,
        type: i0.DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const i0.VerificationMeta _disposalMeasuresMeta =
      const i0.VerificationMeta('disposalMeasures');
  @override
  late final i0.GeneratedColumn<String> disposalMeasures =
      i0.GeneratedColumn<String>(
        'disposal_measures',
        aliasedName,
        true,
        type: i0.DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const i0.VerificationMeta _disposalStartDateMeta =
      const i0.VerificationMeta('disposalStartDate');
  @override
  late final i0.GeneratedColumn<DateTime> disposalStartDate =
      i0.GeneratedColumn<DateTime>(
        'disposal_start_date',
        aliasedName,
        true,
        type: i0.DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const i0.VerificationMeta _disposalEndDateMeta =
      const i0.VerificationMeta('disposalEndDate');
  @override
  late final i0.GeneratedColumn<DateTime> disposalEndDate =
      i0.GeneratedColumn<DateTime>(
        'disposal_end_date',
        aliasedName,
        true,
        type: i0.DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const i0.VerificationMeta _isActiveMeta = const i0.VerificationMeta(
    'isActive',
  );
  @override
  late final i0.GeneratedColumn<bool> isActive = i0.GeneratedColumn<bool>(
    'is_active',
    aliasedName,
    false,
    type: i0.DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: i0.GeneratedColumn.constraintIsAlways(
      'CHECK ("is_active" IN (0, 1))',
    ),
    defaultValue: const i3.Constant(true),
  );
  @override
  List<i0.GeneratedColumn> get $columns => [
    symbol,
    date,
    warningType,
    reasonCode,
    reasonDescription,
    disposalMeasures,
    disposalStartDate,
    disposalEndDate,
    isActive,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'trading_warning';
  @override
  i0.VerificationContext validateIntegrity(
    i0.Insertable<i1.TradingWarningEntry> instance, {
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
    if (data.containsKey('warning_type')) {
      context.handle(
        _warningTypeMeta,
        warningType.isAcceptableOrUnknown(
          data['warning_type']!,
          _warningTypeMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_warningTypeMeta);
    }
    if (data.containsKey('reason_code')) {
      context.handle(
        _reasonCodeMeta,
        reasonCode.isAcceptableOrUnknown(data['reason_code']!, _reasonCodeMeta),
      );
    }
    if (data.containsKey('reason_description')) {
      context.handle(
        _reasonDescriptionMeta,
        reasonDescription.isAcceptableOrUnknown(
          data['reason_description']!,
          _reasonDescriptionMeta,
        ),
      );
    }
    if (data.containsKey('disposal_measures')) {
      context.handle(
        _disposalMeasuresMeta,
        disposalMeasures.isAcceptableOrUnknown(
          data['disposal_measures']!,
          _disposalMeasuresMeta,
        ),
      );
    }
    if (data.containsKey('disposal_start_date')) {
      context.handle(
        _disposalStartDateMeta,
        disposalStartDate.isAcceptableOrUnknown(
          data['disposal_start_date']!,
          _disposalStartDateMeta,
        ),
      );
    }
    if (data.containsKey('disposal_end_date')) {
      context.handle(
        _disposalEndDateMeta,
        disposalEndDate.isAcceptableOrUnknown(
          data['disposal_end_date']!,
          _disposalEndDateMeta,
        ),
      );
    }
    if (data.containsKey('is_active')) {
      context.handle(
        _isActiveMeta,
        isActive.isAcceptableOrUnknown(data['is_active']!, _isActiveMeta),
      );
    }
    return context;
  }

  @override
  Set<i0.GeneratedColumn> get $primaryKey => {symbol, date, warningType};
  @override
  i1.TradingWarningEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return i1.TradingWarningEntry(
      symbol: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.string,
        data['${effectivePrefix}symbol'],
      )!,
      date: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.dateTime,
        data['${effectivePrefix}date'],
      )!,
      warningType: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.string,
        data['${effectivePrefix}warning_type'],
      )!,
      reasonCode: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.string,
        data['${effectivePrefix}reason_code'],
      ),
      reasonDescription: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.string,
        data['${effectivePrefix}reason_description'],
      ),
      disposalMeasures: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.string,
        data['${effectivePrefix}disposal_measures'],
      ),
      disposalStartDate: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.dateTime,
        data['${effectivePrefix}disposal_start_date'],
      ),
      disposalEndDate: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.dateTime,
        data['${effectivePrefix}disposal_end_date'],
      ),
      isActive: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.bool,
        data['${effectivePrefix}is_active'],
      )!,
    );
  }

  @override
  $TradingWarningTable createAlias(String alias) {
    return $TradingWarningTable(attachedDatabase, alias);
  }
}

class TradingWarningEntry extends i0.DataClass
    implements i0.Insertable<i1.TradingWarningEntry> {
  /// 股票代碼
  final String symbol;

  /// 公告日期
  final DateTime date;

  /// 警示類型：ATTENTION（注意）| DISPOSAL（處置）
  final String warningType;

  /// 列入原因代碼
  final String? reasonCode;

  /// 原因說明
  final String? reasonDescription;

  /// 處置措施（僅處置股）
  final String? disposalMeasures;

  /// 處置起始日
  final DateTime? disposalStartDate;

  /// 處置結束日
  final DateTime? disposalEndDate;

  /// 是否目前生效
  final bool isActive;
  const TradingWarningEntry({
    required this.symbol,
    required this.date,
    required this.warningType,
    this.reasonCode,
    this.reasonDescription,
    this.disposalMeasures,
    this.disposalStartDate,
    this.disposalEndDate,
    required this.isActive,
  });
  @override
  Map<String, i0.Expression> toColumns(bool nullToAbsent) {
    final map = <String, i0.Expression>{};
    map['symbol'] = i0.Variable<String>(symbol);
    map['date'] = i0.Variable<DateTime>(date);
    map['warning_type'] = i0.Variable<String>(warningType);
    if (!nullToAbsent || reasonCode != null) {
      map['reason_code'] = i0.Variable<String>(reasonCode);
    }
    if (!nullToAbsent || reasonDescription != null) {
      map['reason_description'] = i0.Variable<String>(reasonDescription);
    }
    if (!nullToAbsent || disposalMeasures != null) {
      map['disposal_measures'] = i0.Variable<String>(disposalMeasures);
    }
    if (!nullToAbsent || disposalStartDate != null) {
      map['disposal_start_date'] = i0.Variable<DateTime>(disposalStartDate);
    }
    if (!nullToAbsent || disposalEndDate != null) {
      map['disposal_end_date'] = i0.Variable<DateTime>(disposalEndDate);
    }
    map['is_active'] = i0.Variable<bool>(isActive);
    return map;
  }

  i1.TradingWarningCompanion toCompanion(bool nullToAbsent) {
    return i1.TradingWarningCompanion(
      symbol: i0.Value(symbol),
      date: i0.Value(date),
      warningType: i0.Value(warningType),
      reasonCode: reasonCode == null && nullToAbsent
          ? const i0.Value.absent()
          : i0.Value(reasonCode),
      reasonDescription: reasonDescription == null && nullToAbsent
          ? const i0.Value.absent()
          : i0.Value(reasonDescription),
      disposalMeasures: disposalMeasures == null && nullToAbsent
          ? const i0.Value.absent()
          : i0.Value(disposalMeasures),
      disposalStartDate: disposalStartDate == null && nullToAbsent
          ? const i0.Value.absent()
          : i0.Value(disposalStartDate),
      disposalEndDate: disposalEndDate == null && nullToAbsent
          ? const i0.Value.absent()
          : i0.Value(disposalEndDate),
      isActive: i0.Value(isActive),
    );
  }

  factory TradingWarningEntry.fromJson(
    Map<String, dynamic> json, {
    i0.ValueSerializer? serializer,
  }) {
    serializer ??= i0.driftRuntimeOptions.defaultSerializer;
    return TradingWarningEntry(
      symbol: serializer.fromJson<String>(json['symbol']),
      date: serializer.fromJson<DateTime>(json['date']),
      warningType: serializer.fromJson<String>(json['warningType']),
      reasonCode: serializer.fromJson<String?>(json['reasonCode']),
      reasonDescription: serializer.fromJson<String?>(
        json['reasonDescription'],
      ),
      disposalMeasures: serializer.fromJson<String?>(json['disposalMeasures']),
      disposalStartDate: serializer.fromJson<DateTime?>(
        json['disposalStartDate'],
      ),
      disposalEndDate: serializer.fromJson<DateTime?>(json['disposalEndDate']),
      isActive: serializer.fromJson<bool>(json['isActive']),
    );
  }
  @override
  Map<String, dynamic> toJson({i0.ValueSerializer? serializer}) {
    serializer ??= i0.driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'symbol': serializer.toJson<String>(symbol),
      'date': serializer.toJson<DateTime>(date),
      'warningType': serializer.toJson<String>(warningType),
      'reasonCode': serializer.toJson<String?>(reasonCode),
      'reasonDescription': serializer.toJson<String?>(reasonDescription),
      'disposalMeasures': serializer.toJson<String?>(disposalMeasures),
      'disposalStartDate': serializer.toJson<DateTime?>(disposalStartDate),
      'disposalEndDate': serializer.toJson<DateTime?>(disposalEndDate),
      'isActive': serializer.toJson<bool>(isActive),
    };
  }

  i1.TradingWarningEntry copyWith({
    String? symbol,
    DateTime? date,
    String? warningType,
    i0.Value<String?> reasonCode = const i0.Value.absent(),
    i0.Value<String?> reasonDescription = const i0.Value.absent(),
    i0.Value<String?> disposalMeasures = const i0.Value.absent(),
    i0.Value<DateTime?> disposalStartDate = const i0.Value.absent(),
    i0.Value<DateTime?> disposalEndDate = const i0.Value.absent(),
    bool? isActive,
  }) => i1.TradingWarningEntry(
    symbol: symbol ?? this.symbol,
    date: date ?? this.date,
    warningType: warningType ?? this.warningType,
    reasonCode: reasonCode.present ? reasonCode.value : this.reasonCode,
    reasonDescription: reasonDescription.present
        ? reasonDescription.value
        : this.reasonDescription,
    disposalMeasures: disposalMeasures.present
        ? disposalMeasures.value
        : this.disposalMeasures,
    disposalStartDate: disposalStartDate.present
        ? disposalStartDate.value
        : this.disposalStartDate,
    disposalEndDate: disposalEndDate.present
        ? disposalEndDate.value
        : this.disposalEndDate,
    isActive: isActive ?? this.isActive,
  );
  TradingWarningEntry copyWithCompanion(i1.TradingWarningCompanion data) {
    return TradingWarningEntry(
      symbol: data.symbol.present ? data.symbol.value : this.symbol,
      date: data.date.present ? data.date.value : this.date,
      warningType: data.warningType.present
          ? data.warningType.value
          : this.warningType,
      reasonCode: data.reasonCode.present
          ? data.reasonCode.value
          : this.reasonCode,
      reasonDescription: data.reasonDescription.present
          ? data.reasonDescription.value
          : this.reasonDescription,
      disposalMeasures: data.disposalMeasures.present
          ? data.disposalMeasures.value
          : this.disposalMeasures,
      disposalStartDate: data.disposalStartDate.present
          ? data.disposalStartDate.value
          : this.disposalStartDate,
      disposalEndDate: data.disposalEndDate.present
          ? data.disposalEndDate.value
          : this.disposalEndDate,
      isActive: data.isActive.present ? data.isActive.value : this.isActive,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TradingWarningEntry(')
          ..write('symbol: $symbol, ')
          ..write('date: $date, ')
          ..write('warningType: $warningType, ')
          ..write('reasonCode: $reasonCode, ')
          ..write('reasonDescription: $reasonDescription, ')
          ..write('disposalMeasures: $disposalMeasures, ')
          ..write('disposalStartDate: $disposalStartDate, ')
          ..write('disposalEndDate: $disposalEndDate, ')
          ..write('isActive: $isActive')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    symbol,
    date,
    warningType,
    reasonCode,
    reasonDescription,
    disposalMeasures,
    disposalStartDate,
    disposalEndDate,
    isActive,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is i1.TradingWarningEntry &&
          other.symbol == this.symbol &&
          other.date == this.date &&
          other.warningType == this.warningType &&
          other.reasonCode == this.reasonCode &&
          other.reasonDescription == this.reasonDescription &&
          other.disposalMeasures == this.disposalMeasures &&
          other.disposalStartDate == this.disposalStartDate &&
          other.disposalEndDate == this.disposalEndDate &&
          other.isActive == this.isActive);
}

class TradingWarningCompanion
    extends i0.UpdateCompanion<i1.TradingWarningEntry> {
  final i0.Value<String> symbol;
  final i0.Value<DateTime> date;
  final i0.Value<String> warningType;
  final i0.Value<String?> reasonCode;
  final i0.Value<String?> reasonDescription;
  final i0.Value<String?> disposalMeasures;
  final i0.Value<DateTime?> disposalStartDate;
  final i0.Value<DateTime?> disposalEndDate;
  final i0.Value<bool> isActive;
  final i0.Value<int> rowid;
  const TradingWarningCompanion({
    this.symbol = const i0.Value.absent(),
    this.date = const i0.Value.absent(),
    this.warningType = const i0.Value.absent(),
    this.reasonCode = const i0.Value.absent(),
    this.reasonDescription = const i0.Value.absent(),
    this.disposalMeasures = const i0.Value.absent(),
    this.disposalStartDate = const i0.Value.absent(),
    this.disposalEndDate = const i0.Value.absent(),
    this.isActive = const i0.Value.absent(),
    this.rowid = const i0.Value.absent(),
  });
  TradingWarningCompanion.insert({
    required String symbol,
    required DateTime date,
    required String warningType,
    this.reasonCode = const i0.Value.absent(),
    this.reasonDescription = const i0.Value.absent(),
    this.disposalMeasures = const i0.Value.absent(),
    this.disposalStartDate = const i0.Value.absent(),
    this.disposalEndDate = const i0.Value.absent(),
    this.isActive = const i0.Value.absent(),
    this.rowid = const i0.Value.absent(),
  }) : symbol = i0.Value(symbol),
       date = i0.Value(date),
       warningType = i0.Value(warningType);
  static i0.Insertable<i1.TradingWarningEntry> custom({
    i0.Expression<String>? symbol,
    i0.Expression<DateTime>? date,
    i0.Expression<String>? warningType,
    i0.Expression<String>? reasonCode,
    i0.Expression<String>? reasonDescription,
    i0.Expression<String>? disposalMeasures,
    i0.Expression<DateTime>? disposalStartDate,
    i0.Expression<DateTime>? disposalEndDate,
    i0.Expression<bool>? isActive,
    i0.Expression<int>? rowid,
  }) {
    return i0.RawValuesInsertable({
      if (symbol != null) 'symbol': symbol,
      if (date != null) 'date': date,
      if (warningType != null) 'warning_type': warningType,
      if (reasonCode != null) 'reason_code': reasonCode,
      if (reasonDescription != null) 'reason_description': reasonDescription,
      if (disposalMeasures != null) 'disposal_measures': disposalMeasures,
      if (disposalStartDate != null) 'disposal_start_date': disposalStartDate,
      if (disposalEndDate != null) 'disposal_end_date': disposalEndDate,
      if (isActive != null) 'is_active': isActive,
      if (rowid != null) 'rowid': rowid,
    });
  }

  i1.TradingWarningCompanion copyWith({
    i0.Value<String>? symbol,
    i0.Value<DateTime>? date,
    i0.Value<String>? warningType,
    i0.Value<String?>? reasonCode,
    i0.Value<String?>? reasonDescription,
    i0.Value<String?>? disposalMeasures,
    i0.Value<DateTime?>? disposalStartDate,
    i0.Value<DateTime?>? disposalEndDate,
    i0.Value<bool>? isActive,
    i0.Value<int>? rowid,
  }) {
    return i1.TradingWarningCompanion(
      symbol: symbol ?? this.symbol,
      date: date ?? this.date,
      warningType: warningType ?? this.warningType,
      reasonCode: reasonCode ?? this.reasonCode,
      reasonDescription: reasonDescription ?? this.reasonDescription,
      disposalMeasures: disposalMeasures ?? this.disposalMeasures,
      disposalStartDate: disposalStartDate ?? this.disposalStartDate,
      disposalEndDate: disposalEndDate ?? this.disposalEndDate,
      isActive: isActive ?? this.isActive,
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
    if (warningType.present) {
      map['warning_type'] = i0.Variable<String>(warningType.value);
    }
    if (reasonCode.present) {
      map['reason_code'] = i0.Variable<String>(reasonCode.value);
    }
    if (reasonDescription.present) {
      map['reason_description'] = i0.Variable<String>(reasonDescription.value);
    }
    if (disposalMeasures.present) {
      map['disposal_measures'] = i0.Variable<String>(disposalMeasures.value);
    }
    if (disposalStartDate.present) {
      map['disposal_start_date'] = i0.Variable<DateTime>(
        disposalStartDate.value,
      );
    }
    if (disposalEndDate.present) {
      map['disposal_end_date'] = i0.Variable<DateTime>(disposalEndDate.value);
    }
    if (isActive.present) {
      map['is_active'] = i0.Variable<bool>(isActive.value);
    }
    if (rowid.present) {
      map['rowid'] = i0.Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TradingWarningCompanion(')
          ..write('symbol: $symbol, ')
          ..write('date: $date, ')
          ..write('warningType: $warningType, ')
          ..write('reasonCode: $reasonCode, ')
          ..write('reasonDescription: $reasonDescription, ')
          ..write('disposalMeasures: $disposalMeasures, ')
          ..write('disposalStartDate: $disposalStartDate, ')
          ..write('disposalEndDate: $disposalEndDate, ')
          ..write('isActive: $isActive, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

i0.Index get idxTradingWarningType => i0.Index(
  'idx_trading_warning_type',
  'CREATE INDEX idx_trading_warning_type ON trading_warning (warning_type)',
);
i0.Index get idxInsiderHoldingDate => i0.Index(
  'idx_insider_holding_date',
  'CREATE INDEX idx_insider_holding_date ON insider_holding (date)',
);

class $InsiderHoldingTable extends i2.InsiderHolding
    with i0.TableInfo<$InsiderHoldingTable, i1.InsiderHoldingEntry> {
  @override
  final i0.GeneratedDatabase attachedDatabase;
  final String? _alias;
  $InsiderHoldingTable(this.attachedDatabase, [this._alias]);
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
  static const i0.VerificationMeta _directorSharesMeta =
      const i0.VerificationMeta('directorShares');
  @override
  late final i0.GeneratedColumn<double> directorShares =
      i0.GeneratedColumn<double>(
        'director_shares',
        aliasedName,
        true,
        type: i0.DriftSqlType.double,
        requiredDuringInsert: false,
      );
  static const i0.VerificationMeta _supervisorSharesMeta =
      const i0.VerificationMeta('supervisorShares');
  @override
  late final i0.GeneratedColumn<double> supervisorShares =
      i0.GeneratedColumn<double>(
        'supervisor_shares',
        aliasedName,
        true,
        type: i0.DriftSqlType.double,
        requiredDuringInsert: false,
      );
  static const i0.VerificationMeta _managerSharesMeta =
      const i0.VerificationMeta('managerShares');
  @override
  late final i0.GeneratedColumn<double> managerShares =
      i0.GeneratedColumn<double>(
        'manager_shares',
        aliasedName,
        true,
        type: i0.DriftSqlType.double,
        requiredDuringInsert: false,
      );
  static const i0.VerificationMeta _insiderRatioMeta =
      const i0.VerificationMeta('insiderRatio');
  @override
  late final i0.GeneratedColumn<double> insiderRatio =
      i0.GeneratedColumn<double>(
        'insider_ratio',
        aliasedName,
        true,
        type: i0.DriftSqlType.double,
        requiredDuringInsert: false,
      );
  static const i0.VerificationMeta _pledgeRatioMeta = const i0.VerificationMeta(
    'pledgeRatio',
  );
  @override
  late final i0.GeneratedColumn<double> pledgeRatio =
      i0.GeneratedColumn<double>(
        'pledge_ratio',
        aliasedName,
        true,
        type: i0.DriftSqlType.double,
        requiredDuringInsert: false,
      );
  static const i0.VerificationMeta _sharesChangeMeta =
      const i0.VerificationMeta('sharesChange');
  @override
  late final i0.GeneratedColumn<double> sharesChange =
      i0.GeneratedColumn<double>(
        'shares_change',
        aliasedName,
        true,
        type: i0.DriftSqlType.double,
        requiredDuringInsert: false,
      );
  static const i0.VerificationMeta _sharesIssuedMeta =
      const i0.VerificationMeta('sharesIssued');
  @override
  late final i0.GeneratedColumn<double> sharesIssued =
      i0.GeneratedColumn<double>(
        'shares_issued',
        aliasedName,
        true,
        type: i0.DriftSqlType.double,
        requiredDuringInsert: false,
      );
  @override
  List<i0.GeneratedColumn> get $columns => [
    symbol,
    date,
    directorShares,
    supervisorShares,
    managerShares,
    insiderRatio,
    pledgeRatio,
    sharesChange,
    sharesIssued,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'insider_holding';
  @override
  i0.VerificationContext validateIntegrity(
    i0.Insertable<i1.InsiderHoldingEntry> instance, {
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
    if (data.containsKey('director_shares')) {
      context.handle(
        _directorSharesMeta,
        directorShares.isAcceptableOrUnknown(
          data['director_shares']!,
          _directorSharesMeta,
        ),
      );
    }
    if (data.containsKey('supervisor_shares')) {
      context.handle(
        _supervisorSharesMeta,
        supervisorShares.isAcceptableOrUnknown(
          data['supervisor_shares']!,
          _supervisorSharesMeta,
        ),
      );
    }
    if (data.containsKey('manager_shares')) {
      context.handle(
        _managerSharesMeta,
        managerShares.isAcceptableOrUnknown(
          data['manager_shares']!,
          _managerSharesMeta,
        ),
      );
    }
    if (data.containsKey('insider_ratio')) {
      context.handle(
        _insiderRatioMeta,
        insiderRatio.isAcceptableOrUnknown(
          data['insider_ratio']!,
          _insiderRatioMeta,
        ),
      );
    }
    if (data.containsKey('pledge_ratio')) {
      context.handle(
        _pledgeRatioMeta,
        pledgeRatio.isAcceptableOrUnknown(
          data['pledge_ratio']!,
          _pledgeRatioMeta,
        ),
      );
    }
    if (data.containsKey('shares_change')) {
      context.handle(
        _sharesChangeMeta,
        sharesChange.isAcceptableOrUnknown(
          data['shares_change']!,
          _sharesChangeMeta,
        ),
      );
    }
    if (data.containsKey('shares_issued')) {
      context.handle(
        _sharesIssuedMeta,
        sharesIssued.isAcceptableOrUnknown(
          data['shares_issued']!,
          _sharesIssuedMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<i0.GeneratedColumn> get $primaryKey => {symbol, date};
  @override
  i1.InsiderHoldingEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return i1.InsiderHoldingEntry(
      symbol: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.string,
        data['${effectivePrefix}symbol'],
      )!,
      date: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.dateTime,
        data['${effectivePrefix}date'],
      )!,
      directorShares: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.double,
        data['${effectivePrefix}director_shares'],
      ),
      supervisorShares: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.double,
        data['${effectivePrefix}supervisor_shares'],
      ),
      managerShares: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.double,
        data['${effectivePrefix}manager_shares'],
      ),
      insiderRatio: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.double,
        data['${effectivePrefix}insider_ratio'],
      ),
      pledgeRatio: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.double,
        data['${effectivePrefix}pledge_ratio'],
      ),
      sharesChange: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.double,
        data['${effectivePrefix}shares_change'],
      ),
      sharesIssued: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.double,
        data['${effectivePrefix}shares_issued'],
      ),
    );
  }

  @override
  $InsiderHoldingTable createAlias(String alias) {
    return $InsiderHoldingTable(attachedDatabase, alias);
  }
}

class InsiderHoldingEntry extends i0.DataClass
    implements i0.Insertable<i1.InsiderHoldingEntry> {
  /// 股票代碼
  final String symbol;

  /// 報告日期（月報）
  final DateTime date;

  /// 董事持股總數（股）
  final double? directorShares;

  /// 監察人持股總數（股）
  final double? supervisorShares;

  /// 經理人持股總數（股）
  final double? managerShares;

  /// 董監持股比例（%）
  final double? insiderRatio;

  /// 質押比例（%）
  final double? pledgeRatio;

  /// 持股變動（股）- 與前期比較
  final double? sharesChange;

  /// 已發行股數
  final double? sharesIssued;
  const InsiderHoldingEntry({
    required this.symbol,
    required this.date,
    this.directorShares,
    this.supervisorShares,
    this.managerShares,
    this.insiderRatio,
    this.pledgeRatio,
    this.sharesChange,
    this.sharesIssued,
  });
  @override
  Map<String, i0.Expression> toColumns(bool nullToAbsent) {
    final map = <String, i0.Expression>{};
    map['symbol'] = i0.Variable<String>(symbol);
    map['date'] = i0.Variable<DateTime>(date);
    if (!nullToAbsent || directorShares != null) {
      map['director_shares'] = i0.Variable<double>(directorShares);
    }
    if (!nullToAbsent || supervisorShares != null) {
      map['supervisor_shares'] = i0.Variable<double>(supervisorShares);
    }
    if (!nullToAbsent || managerShares != null) {
      map['manager_shares'] = i0.Variable<double>(managerShares);
    }
    if (!nullToAbsent || insiderRatio != null) {
      map['insider_ratio'] = i0.Variable<double>(insiderRatio);
    }
    if (!nullToAbsent || pledgeRatio != null) {
      map['pledge_ratio'] = i0.Variable<double>(pledgeRatio);
    }
    if (!nullToAbsent || sharesChange != null) {
      map['shares_change'] = i0.Variable<double>(sharesChange);
    }
    if (!nullToAbsent || sharesIssued != null) {
      map['shares_issued'] = i0.Variable<double>(sharesIssued);
    }
    return map;
  }

  i1.InsiderHoldingCompanion toCompanion(bool nullToAbsent) {
    return i1.InsiderHoldingCompanion(
      symbol: i0.Value(symbol),
      date: i0.Value(date),
      directorShares: directorShares == null && nullToAbsent
          ? const i0.Value.absent()
          : i0.Value(directorShares),
      supervisorShares: supervisorShares == null && nullToAbsent
          ? const i0.Value.absent()
          : i0.Value(supervisorShares),
      managerShares: managerShares == null && nullToAbsent
          ? const i0.Value.absent()
          : i0.Value(managerShares),
      insiderRatio: insiderRatio == null && nullToAbsent
          ? const i0.Value.absent()
          : i0.Value(insiderRatio),
      pledgeRatio: pledgeRatio == null && nullToAbsent
          ? const i0.Value.absent()
          : i0.Value(pledgeRatio),
      sharesChange: sharesChange == null && nullToAbsent
          ? const i0.Value.absent()
          : i0.Value(sharesChange),
      sharesIssued: sharesIssued == null && nullToAbsent
          ? const i0.Value.absent()
          : i0.Value(sharesIssued),
    );
  }

  factory InsiderHoldingEntry.fromJson(
    Map<String, dynamic> json, {
    i0.ValueSerializer? serializer,
  }) {
    serializer ??= i0.driftRuntimeOptions.defaultSerializer;
    return InsiderHoldingEntry(
      symbol: serializer.fromJson<String>(json['symbol']),
      date: serializer.fromJson<DateTime>(json['date']),
      directorShares: serializer.fromJson<double?>(json['directorShares']),
      supervisorShares: serializer.fromJson<double?>(json['supervisorShares']),
      managerShares: serializer.fromJson<double?>(json['managerShares']),
      insiderRatio: serializer.fromJson<double?>(json['insiderRatio']),
      pledgeRatio: serializer.fromJson<double?>(json['pledgeRatio']),
      sharesChange: serializer.fromJson<double?>(json['sharesChange']),
      sharesIssued: serializer.fromJson<double?>(json['sharesIssued']),
    );
  }
  @override
  Map<String, dynamic> toJson({i0.ValueSerializer? serializer}) {
    serializer ??= i0.driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'symbol': serializer.toJson<String>(symbol),
      'date': serializer.toJson<DateTime>(date),
      'directorShares': serializer.toJson<double?>(directorShares),
      'supervisorShares': serializer.toJson<double?>(supervisorShares),
      'managerShares': serializer.toJson<double?>(managerShares),
      'insiderRatio': serializer.toJson<double?>(insiderRatio),
      'pledgeRatio': serializer.toJson<double?>(pledgeRatio),
      'sharesChange': serializer.toJson<double?>(sharesChange),
      'sharesIssued': serializer.toJson<double?>(sharesIssued),
    };
  }

  i1.InsiderHoldingEntry copyWith({
    String? symbol,
    DateTime? date,
    i0.Value<double?> directorShares = const i0.Value.absent(),
    i0.Value<double?> supervisorShares = const i0.Value.absent(),
    i0.Value<double?> managerShares = const i0.Value.absent(),
    i0.Value<double?> insiderRatio = const i0.Value.absent(),
    i0.Value<double?> pledgeRatio = const i0.Value.absent(),
    i0.Value<double?> sharesChange = const i0.Value.absent(),
    i0.Value<double?> sharesIssued = const i0.Value.absent(),
  }) => i1.InsiderHoldingEntry(
    symbol: symbol ?? this.symbol,
    date: date ?? this.date,
    directorShares: directorShares.present
        ? directorShares.value
        : this.directorShares,
    supervisorShares: supervisorShares.present
        ? supervisorShares.value
        : this.supervisorShares,
    managerShares: managerShares.present
        ? managerShares.value
        : this.managerShares,
    insiderRatio: insiderRatio.present ? insiderRatio.value : this.insiderRatio,
    pledgeRatio: pledgeRatio.present ? pledgeRatio.value : this.pledgeRatio,
    sharesChange: sharesChange.present ? sharesChange.value : this.sharesChange,
    sharesIssued: sharesIssued.present ? sharesIssued.value : this.sharesIssued,
  );
  InsiderHoldingEntry copyWithCompanion(i1.InsiderHoldingCompanion data) {
    return InsiderHoldingEntry(
      symbol: data.symbol.present ? data.symbol.value : this.symbol,
      date: data.date.present ? data.date.value : this.date,
      directorShares: data.directorShares.present
          ? data.directorShares.value
          : this.directorShares,
      supervisorShares: data.supervisorShares.present
          ? data.supervisorShares.value
          : this.supervisorShares,
      managerShares: data.managerShares.present
          ? data.managerShares.value
          : this.managerShares,
      insiderRatio: data.insiderRatio.present
          ? data.insiderRatio.value
          : this.insiderRatio,
      pledgeRatio: data.pledgeRatio.present
          ? data.pledgeRatio.value
          : this.pledgeRatio,
      sharesChange: data.sharesChange.present
          ? data.sharesChange.value
          : this.sharesChange,
      sharesIssued: data.sharesIssued.present
          ? data.sharesIssued.value
          : this.sharesIssued,
    );
  }

  @override
  String toString() {
    return (StringBuffer('InsiderHoldingEntry(')
          ..write('symbol: $symbol, ')
          ..write('date: $date, ')
          ..write('directorShares: $directorShares, ')
          ..write('supervisorShares: $supervisorShares, ')
          ..write('managerShares: $managerShares, ')
          ..write('insiderRatio: $insiderRatio, ')
          ..write('pledgeRatio: $pledgeRatio, ')
          ..write('sharesChange: $sharesChange, ')
          ..write('sharesIssued: $sharesIssued')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    symbol,
    date,
    directorShares,
    supervisorShares,
    managerShares,
    insiderRatio,
    pledgeRatio,
    sharesChange,
    sharesIssued,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is i1.InsiderHoldingEntry &&
          other.symbol == this.symbol &&
          other.date == this.date &&
          other.directorShares == this.directorShares &&
          other.supervisorShares == this.supervisorShares &&
          other.managerShares == this.managerShares &&
          other.insiderRatio == this.insiderRatio &&
          other.pledgeRatio == this.pledgeRatio &&
          other.sharesChange == this.sharesChange &&
          other.sharesIssued == this.sharesIssued);
}

class InsiderHoldingCompanion
    extends i0.UpdateCompanion<i1.InsiderHoldingEntry> {
  final i0.Value<String> symbol;
  final i0.Value<DateTime> date;
  final i0.Value<double?> directorShares;
  final i0.Value<double?> supervisorShares;
  final i0.Value<double?> managerShares;
  final i0.Value<double?> insiderRatio;
  final i0.Value<double?> pledgeRatio;
  final i0.Value<double?> sharesChange;
  final i0.Value<double?> sharesIssued;
  final i0.Value<int> rowid;
  const InsiderHoldingCompanion({
    this.symbol = const i0.Value.absent(),
    this.date = const i0.Value.absent(),
    this.directorShares = const i0.Value.absent(),
    this.supervisorShares = const i0.Value.absent(),
    this.managerShares = const i0.Value.absent(),
    this.insiderRatio = const i0.Value.absent(),
    this.pledgeRatio = const i0.Value.absent(),
    this.sharesChange = const i0.Value.absent(),
    this.sharesIssued = const i0.Value.absent(),
    this.rowid = const i0.Value.absent(),
  });
  InsiderHoldingCompanion.insert({
    required String symbol,
    required DateTime date,
    this.directorShares = const i0.Value.absent(),
    this.supervisorShares = const i0.Value.absent(),
    this.managerShares = const i0.Value.absent(),
    this.insiderRatio = const i0.Value.absent(),
    this.pledgeRatio = const i0.Value.absent(),
    this.sharesChange = const i0.Value.absent(),
    this.sharesIssued = const i0.Value.absent(),
    this.rowid = const i0.Value.absent(),
  }) : symbol = i0.Value(symbol),
       date = i0.Value(date);
  static i0.Insertable<i1.InsiderHoldingEntry> custom({
    i0.Expression<String>? symbol,
    i0.Expression<DateTime>? date,
    i0.Expression<double>? directorShares,
    i0.Expression<double>? supervisorShares,
    i0.Expression<double>? managerShares,
    i0.Expression<double>? insiderRatio,
    i0.Expression<double>? pledgeRatio,
    i0.Expression<double>? sharesChange,
    i0.Expression<double>? sharesIssued,
    i0.Expression<int>? rowid,
  }) {
    return i0.RawValuesInsertable({
      if (symbol != null) 'symbol': symbol,
      if (date != null) 'date': date,
      if (directorShares != null) 'director_shares': directorShares,
      if (supervisorShares != null) 'supervisor_shares': supervisorShares,
      if (managerShares != null) 'manager_shares': managerShares,
      if (insiderRatio != null) 'insider_ratio': insiderRatio,
      if (pledgeRatio != null) 'pledge_ratio': pledgeRatio,
      if (sharesChange != null) 'shares_change': sharesChange,
      if (sharesIssued != null) 'shares_issued': sharesIssued,
      if (rowid != null) 'rowid': rowid,
    });
  }

  i1.InsiderHoldingCompanion copyWith({
    i0.Value<String>? symbol,
    i0.Value<DateTime>? date,
    i0.Value<double?>? directorShares,
    i0.Value<double?>? supervisorShares,
    i0.Value<double?>? managerShares,
    i0.Value<double?>? insiderRatio,
    i0.Value<double?>? pledgeRatio,
    i0.Value<double?>? sharesChange,
    i0.Value<double?>? sharesIssued,
    i0.Value<int>? rowid,
  }) {
    return i1.InsiderHoldingCompanion(
      symbol: symbol ?? this.symbol,
      date: date ?? this.date,
      directorShares: directorShares ?? this.directorShares,
      supervisorShares: supervisorShares ?? this.supervisorShares,
      managerShares: managerShares ?? this.managerShares,
      insiderRatio: insiderRatio ?? this.insiderRatio,
      pledgeRatio: pledgeRatio ?? this.pledgeRatio,
      sharesChange: sharesChange ?? this.sharesChange,
      sharesIssued: sharesIssued ?? this.sharesIssued,
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
    if (directorShares.present) {
      map['director_shares'] = i0.Variable<double>(directorShares.value);
    }
    if (supervisorShares.present) {
      map['supervisor_shares'] = i0.Variable<double>(supervisorShares.value);
    }
    if (managerShares.present) {
      map['manager_shares'] = i0.Variable<double>(managerShares.value);
    }
    if (insiderRatio.present) {
      map['insider_ratio'] = i0.Variable<double>(insiderRatio.value);
    }
    if (pledgeRatio.present) {
      map['pledge_ratio'] = i0.Variable<double>(pledgeRatio.value);
    }
    if (sharesChange.present) {
      map['shares_change'] = i0.Variable<double>(sharesChange.value);
    }
    if (sharesIssued.present) {
      map['shares_issued'] = i0.Variable<double>(sharesIssued.value);
    }
    if (rowid.present) {
      map['rowid'] = i0.Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('InsiderHoldingCompanion(')
          ..write('symbol: $symbol, ')
          ..write('date: $date, ')
          ..write('directorShares: $directorShares, ')
          ..write('supervisorShares: $supervisorShares, ')
          ..write('managerShares: $managerShares, ')
          ..write('insiderRatio: $insiderRatio, ')
          ..write('pledgeRatio: $pledgeRatio, ')
          ..write('sharesChange: $sharesChange, ')
          ..write('sharesIssued: $sharesIssued, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

i0.Index get idxInsiderTransferDate => i0.Index(
  'idx_insider_transfer_date',
  'CREATE INDEX idx_insider_transfer_date ON insider_transfer (report_date)',
);

class $InsiderTransferTable extends i2.InsiderTransfer
    with i0.TableInfo<$InsiderTransferTable, i1.InsiderTransferEntry> {
  @override
  final i0.GeneratedDatabase attachedDatabase;
  final String? _alias;
  $InsiderTransferTable(this.attachedDatabase, [this._alias]);
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
  static const i0.VerificationMeta _reportDateMeta = const i0.VerificationMeta(
    'reportDate',
  );
  @override
  late final i0.GeneratedColumn<DateTime> reportDate =
      i0.GeneratedColumn<DateTime>(
        'report_date',
        aliasedName,
        false,
        type: i0.DriftSqlType.dateTime,
        requiredDuringInsert: true,
      );
  static const i0.VerificationMeta _identityMeta = const i0.VerificationMeta(
    'identity',
  );
  @override
  late final i0.GeneratedColumn<String> identity = i0.GeneratedColumn<String>(
    'identity',
    aliasedName,
    false,
    type: i0.DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const i0.VerificationMeta _nameMeta = const i0.VerificationMeta(
    'name',
  );
  @override
  late final i0.GeneratedColumn<String> name = i0.GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: i0.DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const i0.VerificationMeta _transferMethodMeta =
      const i0.VerificationMeta('transferMethod');
  @override
  late final i0.GeneratedColumn<String> transferMethod =
      i0.GeneratedColumn<String>(
        'transfer_method',
        aliasedName,
        false,
        type: i0.DriftSqlType.string,
        requiredDuringInsert: true,
      );
  static const i0.VerificationMeta _transferSharesMeta =
      const i0.VerificationMeta('transferShares');
  @override
  late final i0.GeneratedColumn<int> transferShares = i0.GeneratedColumn<int>(
    'transfer_shares',
    aliasedName,
    false,
    type: i0.DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const i0.VerificationMeta _currentHoldingMeta =
      const i0.VerificationMeta('currentHolding');
  @override
  late final i0.GeneratedColumn<int> currentHolding = i0.GeneratedColumn<int>(
    'current_holding',
    aliasedName,
    false,
    type: i0.DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const i0.VerificationMeta _validPeriodStartMeta =
      const i0.VerificationMeta('validPeriodStart');
  @override
  late final i0.GeneratedColumn<DateTime> validPeriodStart =
      i0.GeneratedColumn<DateTime>(
        'valid_period_start',
        aliasedName,
        true,
        type: i0.DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const i0.VerificationMeta _validPeriodEndMeta =
      const i0.VerificationMeta('validPeriodEnd');
  @override
  late final i0.GeneratedColumn<DateTime> validPeriodEnd =
      i0.GeneratedColumn<DateTime>(
        'valid_period_end',
        aliasedName,
        true,
        type: i0.DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  @override
  List<i0.GeneratedColumn> get $columns => [
    symbol,
    reportDate,
    identity,
    name,
    transferMethod,
    transferShares,
    currentHolding,
    validPeriodStart,
    validPeriodEnd,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'insider_transfer';
  @override
  i0.VerificationContext validateIntegrity(
    i0.Insertable<i1.InsiderTransferEntry> instance, {
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
    if (data.containsKey('report_date')) {
      context.handle(
        _reportDateMeta,
        reportDate.isAcceptableOrUnknown(data['report_date']!, _reportDateMeta),
      );
    } else if (isInserting) {
      context.missing(_reportDateMeta);
    }
    if (data.containsKey('identity')) {
      context.handle(
        _identityMeta,
        identity.isAcceptableOrUnknown(data['identity']!, _identityMeta),
      );
    } else if (isInserting) {
      context.missing(_identityMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('transfer_method')) {
      context.handle(
        _transferMethodMeta,
        transferMethod.isAcceptableOrUnknown(
          data['transfer_method']!,
          _transferMethodMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_transferMethodMeta);
    }
    if (data.containsKey('transfer_shares')) {
      context.handle(
        _transferSharesMeta,
        transferShares.isAcceptableOrUnknown(
          data['transfer_shares']!,
          _transferSharesMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_transferSharesMeta);
    }
    if (data.containsKey('current_holding')) {
      context.handle(
        _currentHoldingMeta,
        currentHolding.isAcceptableOrUnknown(
          data['current_holding']!,
          _currentHoldingMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_currentHoldingMeta);
    }
    if (data.containsKey('valid_period_start')) {
      context.handle(
        _validPeriodStartMeta,
        validPeriodStart.isAcceptableOrUnknown(
          data['valid_period_start']!,
          _validPeriodStartMeta,
        ),
      );
    }
    if (data.containsKey('valid_period_end')) {
      context.handle(
        _validPeriodEndMeta,
        validPeriodEnd.isAcceptableOrUnknown(
          data['valid_period_end']!,
          _validPeriodEndMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<i0.GeneratedColumn> get $primaryKey => {
    symbol,
    reportDate,
    identity,
    name,
  };
  @override
  i1.InsiderTransferEntry map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return i1.InsiderTransferEntry(
      symbol: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.string,
        data['${effectivePrefix}symbol'],
      )!,
      reportDate: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.dateTime,
        data['${effectivePrefix}report_date'],
      )!,
      identity: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.string,
        data['${effectivePrefix}identity'],
      )!,
      name: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      transferMethod: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.string,
        data['${effectivePrefix}transfer_method'],
      )!,
      transferShares: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.int,
        data['${effectivePrefix}transfer_shares'],
      )!,
      currentHolding: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.int,
        data['${effectivePrefix}current_holding'],
      )!,
      validPeriodStart: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.dateTime,
        data['${effectivePrefix}valid_period_start'],
      ),
      validPeriodEnd: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.dateTime,
        data['${effectivePrefix}valid_period_end'],
      ),
    );
  }

  @override
  $InsiderTransferTable createAlias(String alias) {
    return $InsiderTransferTable(attachedDatabase, alias);
  }
}

class InsiderTransferEntry extends i0.DataClass
    implements i0.Insertable<i1.InsiderTransferEntry> {
  /// 股票代碼
  final String symbol;

  /// 申報日期
  final DateTime reportDate;

  /// 申請人身分（董事、經理人、大股東等）
  final String identity;

  /// 姓名
  final String name;

  /// 轉讓方式（一般交易、盤後定價等）
  final String transferMethod;

  /// 轉讓股數
  final int transferShares;

  /// 目前持有股數
  final int currentHolding;

  /// 有效轉讓期間起始日
  final DateTime? validPeriodStart;

  /// 有效轉讓期間結束日
  final DateTime? validPeriodEnd;
  const InsiderTransferEntry({
    required this.symbol,
    required this.reportDate,
    required this.identity,
    required this.name,
    required this.transferMethod,
    required this.transferShares,
    required this.currentHolding,
    this.validPeriodStart,
    this.validPeriodEnd,
  });
  @override
  Map<String, i0.Expression> toColumns(bool nullToAbsent) {
    final map = <String, i0.Expression>{};
    map['symbol'] = i0.Variable<String>(symbol);
    map['report_date'] = i0.Variable<DateTime>(reportDate);
    map['identity'] = i0.Variable<String>(identity);
    map['name'] = i0.Variable<String>(name);
    map['transfer_method'] = i0.Variable<String>(transferMethod);
    map['transfer_shares'] = i0.Variable<int>(transferShares);
    map['current_holding'] = i0.Variable<int>(currentHolding);
    if (!nullToAbsent || validPeriodStart != null) {
      map['valid_period_start'] = i0.Variable<DateTime>(validPeriodStart);
    }
    if (!nullToAbsent || validPeriodEnd != null) {
      map['valid_period_end'] = i0.Variable<DateTime>(validPeriodEnd);
    }
    return map;
  }

  i1.InsiderTransferCompanion toCompanion(bool nullToAbsent) {
    return i1.InsiderTransferCompanion(
      symbol: i0.Value(symbol),
      reportDate: i0.Value(reportDate),
      identity: i0.Value(identity),
      name: i0.Value(name),
      transferMethod: i0.Value(transferMethod),
      transferShares: i0.Value(transferShares),
      currentHolding: i0.Value(currentHolding),
      validPeriodStart: validPeriodStart == null && nullToAbsent
          ? const i0.Value.absent()
          : i0.Value(validPeriodStart),
      validPeriodEnd: validPeriodEnd == null && nullToAbsent
          ? const i0.Value.absent()
          : i0.Value(validPeriodEnd),
    );
  }

  factory InsiderTransferEntry.fromJson(
    Map<String, dynamic> json, {
    i0.ValueSerializer? serializer,
  }) {
    serializer ??= i0.driftRuntimeOptions.defaultSerializer;
    return InsiderTransferEntry(
      symbol: serializer.fromJson<String>(json['symbol']),
      reportDate: serializer.fromJson<DateTime>(json['reportDate']),
      identity: serializer.fromJson<String>(json['identity']),
      name: serializer.fromJson<String>(json['name']),
      transferMethod: serializer.fromJson<String>(json['transferMethod']),
      transferShares: serializer.fromJson<int>(json['transferShares']),
      currentHolding: serializer.fromJson<int>(json['currentHolding']),
      validPeriodStart: serializer.fromJson<DateTime?>(
        json['validPeriodStart'],
      ),
      validPeriodEnd: serializer.fromJson<DateTime?>(json['validPeriodEnd']),
    );
  }
  @override
  Map<String, dynamic> toJson({i0.ValueSerializer? serializer}) {
    serializer ??= i0.driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'symbol': serializer.toJson<String>(symbol),
      'reportDate': serializer.toJson<DateTime>(reportDate),
      'identity': serializer.toJson<String>(identity),
      'name': serializer.toJson<String>(name),
      'transferMethod': serializer.toJson<String>(transferMethod),
      'transferShares': serializer.toJson<int>(transferShares),
      'currentHolding': serializer.toJson<int>(currentHolding),
      'validPeriodStart': serializer.toJson<DateTime?>(validPeriodStart),
      'validPeriodEnd': serializer.toJson<DateTime?>(validPeriodEnd),
    };
  }

  i1.InsiderTransferEntry copyWith({
    String? symbol,
    DateTime? reportDate,
    String? identity,
    String? name,
    String? transferMethod,
    int? transferShares,
    int? currentHolding,
    i0.Value<DateTime?> validPeriodStart = const i0.Value.absent(),
    i0.Value<DateTime?> validPeriodEnd = const i0.Value.absent(),
  }) => i1.InsiderTransferEntry(
    symbol: symbol ?? this.symbol,
    reportDate: reportDate ?? this.reportDate,
    identity: identity ?? this.identity,
    name: name ?? this.name,
    transferMethod: transferMethod ?? this.transferMethod,
    transferShares: transferShares ?? this.transferShares,
    currentHolding: currentHolding ?? this.currentHolding,
    validPeriodStart: validPeriodStart.present
        ? validPeriodStart.value
        : this.validPeriodStart,
    validPeriodEnd: validPeriodEnd.present
        ? validPeriodEnd.value
        : this.validPeriodEnd,
  );
  InsiderTransferEntry copyWithCompanion(i1.InsiderTransferCompanion data) {
    return InsiderTransferEntry(
      symbol: data.symbol.present ? data.symbol.value : this.symbol,
      reportDate: data.reportDate.present
          ? data.reportDate.value
          : this.reportDate,
      identity: data.identity.present ? data.identity.value : this.identity,
      name: data.name.present ? data.name.value : this.name,
      transferMethod: data.transferMethod.present
          ? data.transferMethod.value
          : this.transferMethod,
      transferShares: data.transferShares.present
          ? data.transferShares.value
          : this.transferShares,
      currentHolding: data.currentHolding.present
          ? data.currentHolding.value
          : this.currentHolding,
      validPeriodStart: data.validPeriodStart.present
          ? data.validPeriodStart.value
          : this.validPeriodStart,
      validPeriodEnd: data.validPeriodEnd.present
          ? data.validPeriodEnd.value
          : this.validPeriodEnd,
    );
  }

  @override
  String toString() {
    return (StringBuffer('InsiderTransferEntry(')
          ..write('symbol: $symbol, ')
          ..write('reportDate: $reportDate, ')
          ..write('identity: $identity, ')
          ..write('name: $name, ')
          ..write('transferMethod: $transferMethod, ')
          ..write('transferShares: $transferShares, ')
          ..write('currentHolding: $currentHolding, ')
          ..write('validPeriodStart: $validPeriodStart, ')
          ..write('validPeriodEnd: $validPeriodEnd')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    symbol,
    reportDate,
    identity,
    name,
    transferMethod,
    transferShares,
    currentHolding,
    validPeriodStart,
    validPeriodEnd,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is i1.InsiderTransferEntry &&
          other.symbol == this.symbol &&
          other.reportDate == this.reportDate &&
          other.identity == this.identity &&
          other.name == this.name &&
          other.transferMethod == this.transferMethod &&
          other.transferShares == this.transferShares &&
          other.currentHolding == this.currentHolding &&
          other.validPeriodStart == this.validPeriodStart &&
          other.validPeriodEnd == this.validPeriodEnd);
}

class InsiderTransferCompanion
    extends i0.UpdateCompanion<i1.InsiderTransferEntry> {
  final i0.Value<String> symbol;
  final i0.Value<DateTime> reportDate;
  final i0.Value<String> identity;
  final i0.Value<String> name;
  final i0.Value<String> transferMethod;
  final i0.Value<int> transferShares;
  final i0.Value<int> currentHolding;
  final i0.Value<DateTime?> validPeriodStart;
  final i0.Value<DateTime?> validPeriodEnd;
  final i0.Value<int> rowid;
  const InsiderTransferCompanion({
    this.symbol = const i0.Value.absent(),
    this.reportDate = const i0.Value.absent(),
    this.identity = const i0.Value.absent(),
    this.name = const i0.Value.absent(),
    this.transferMethod = const i0.Value.absent(),
    this.transferShares = const i0.Value.absent(),
    this.currentHolding = const i0.Value.absent(),
    this.validPeriodStart = const i0.Value.absent(),
    this.validPeriodEnd = const i0.Value.absent(),
    this.rowid = const i0.Value.absent(),
  });
  InsiderTransferCompanion.insert({
    required String symbol,
    required DateTime reportDate,
    required String identity,
    required String name,
    required String transferMethod,
    required int transferShares,
    required int currentHolding,
    this.validPeriodStart = const i0.Value.absent(),
    this.validPeriodEnd = const i0.Value.absent(),
    this.rowid = const i0.Value.absent(),
  }) : symbol = i0.Value(symbol),
       reportDate = i0.Value(reportDate),
       identity = i0.Value(identity),
       name = i0.Value(name),
       transferMethod = i0.Value(transferMethod),
       transferShares = i0.Value(transferShares),
       currentHolding = i0.Value(currentHolding);
  static i0.Insertable<i1.InsiderTransferEntry> custom({
    i0.Expression<String>? symbol,
    i0.Expression<DateTime>? reportDate,
    i0.Expression<String>? identity,
    i0.Expression<String>? name,
    i0.Expression<String>? transferMethod,
    i0.Expression<int>? transferShares,
    i0.Expression<int>? currentHolding,
    i0.Expression<DateTime>? validPeriodStart,
    i0.Expression<DateTime>? validPeriodEnd,
    i0.Expression<int>? rowid,
  }) {
    return i0.RawValuesInsertable({
      if (symbol != null) 'symbol': symbol,
      if (reportDate != null) 'report_date': reportDate,
      if (identity != null) 'identity': identity,
      if (name != null) 'name': name,
      if (transferMethod != null) 'transfer_method': transferMethod,
      if (transferShares != null) 'transfer_shares': transferShares,
      if (currentHolding != null) 'current_holding': currentHolding,
      if (validPeriodStart != null) 'valid_period_start': validPeriodStart,
      if (validPeriodEnd != null) 'valid_period_end': validPeriodEnd,
      if (rowid != null) 'rowid': rowid,
    });
  }

  i1.InsiderTransferCompanion copyWith({
    i0.Value<String>? symbol,
    i0.Value<DateTime>? reportDate,
    i0.Value<String>? identity,
    i0.Value<String>? name,
    i0.Value<String>? transferMethod,
    i0.Value<int>? transferShares,
    i0.Value<int>? currentHolding,
    i0.Value<DateTime?>? validPeriodStart,
    i0.Value<DateTime?>? validPeriodEnd,
    i0.Value<int>? rowid,
  }) {
    return i1.InsiderTransferCompanion(
      symbol: symbol ?? this.symbol,
      reportDate: reportDate ?? this.reportDate,
      identity: identity ?? this.identity,
      name: name ?? this.name,
      transferMethod: transferMethod ?? this.transferMethod,
      transferShares: transferShares ?? this.transferShares,
      currentHolding: currentHolding ?? this.currentHolding,
      validPeriodStart: validPeriodStart ?? this.validPeriodStart,
      validPeriodEnd: validPeriodEnd ?? this.validPeriodEnd,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, i0.Expression> toColumns(bool nullToAbsent) {
    final map = <String, i0.Expression>{};
    if (symbol.present) {
      map['symbol'] = i0.Variable<String>(symbol.value);
    }
    if (reportDate.present) {
      map['report_date'] = i0.Variable<DateTime>(reportDate.value);
    }
    if (identity.present) {
      map['identity'] = i0.Variable<String>(identity.value);
    }
    if (name.present) {
      map['name'] = i0.Variable<String>(name.value);
    }
    if (transferMethod.present) {
      map['transfer_method'] = i0.Variable<String>(transferMethod.value);
    }
    if (transferShares.present) {
      map['transfer_shares'] = i0.Variable<int>(transferShares.value);
    }
    if (currentHolding.present) {
      map['current_holding'] = i0.Variable<int>(currentHolding.value);
    }
    if (validPeriodStart.present) {
      map['valid_period_start'] = i0.Variable<DateTime>(validPeriodStart.value);
    }
    if (validPeriodEnd.present) {
      map['valid_period_end'] = i0.Variable<DateTime>(validPeriodEnd.value);
    }
    if (rowid.present) {
      map['rowid'] = i0.Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('InsiderTransferCompanion(')
          ..write('symbol: $symbol, ')
          ..write('reportDate: $reportDate, ')
          ..write('identity: $identity, ')
          ..write('name: $name, ')
          ..write('transferMethod: $transferMethod, ')
          ..write('transferShares: $transferShares, ')
          ..write('currentHolding: $currentHolding, ')
          ..write('validPeriodStart: $validPeriodStart, ')
          ..write('validPeriodEnd: $validPeriodEnd, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}
