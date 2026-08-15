// dart format width=80
// ignore_for_file: type=lint
import 'package:drift/drift.dart' as i0;
import 'package:daredevil/data/database/tables/analysis_tables.drift.dart'
    as i1;
import 'package:daredevil/data/database/tables/analysis_tables.dart' as i2;
import 'package:drift/src/runtime/query_builder/query_builder.dart' as i3;
import 'package:daredevil/data/database/tables/stock_master.drift.dart' as i4;
import 'package:drift/internal/modular.dart' as i5;

typedef $$DailyAnalysisTableCreateCompanionBuilder =
    i1.DailyAnalysisCompanion Function({
      required String symbol,
      required DateTime date,
      required String trendState,
      i0.Value<String> reversalState,
      i0.Value<double?> supportLevel,
      i0.Value<double?> resistanceLevel,
      i0.Value<double> scoreShort,
      i0.Value<double> scoreLong,
      i0.Value<DateTime> computedAt,
      i0.Value<int> rowid,
    });
typedef $$DailyAnalysisTableUpdateCompanionBuilder =
    i1.DailyAnalysisCompanion Function({
      i0.Value<String> symbol,
      i0.Value<DateTime> date,
      i0.Value<String> trendState,
      i0.Value<String> reversalState,
      i0.Value<double?> supportLevel,
      i0.Value<double?> resistanceLevel,
      i0.Value<double> scoreShort,
      i0.Value<double> scoreLong,
      i0.Value<DateTime> computedAt,
      i0.Value<int> rowid,
    });

final class $$DailyAnalysisTableReferences
    extends
        i0.BaseReferences<
          i0.GeneratedDatabase,
          i1.$DailyAnalysisTable,
          i1.DailyAnalysisEntry
        > {
  $$DailyAnalysisTableReferences(
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
              ).resultSet<i1.$DailyAnalysisTable>('daily_analysis').symbol,
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

class $$DailyAnalysisTableFilterComposer
    extends i0.Composer<i0.GeneratedDatabase, i1.$DailyAnalysisTable> {
  $$DailyAnalysisTableFilterComposer({
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

  i0.ColumnFilters<String> get trendState => $composableBuilder(
    column: $table.trendState,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<String> get reversalState => $composableBuilder(
    column: $table.reversalState,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<double> get supportLevel => $composableBuilder(
    column: $table.supportLevel,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<double> get resistanceLevel => $composableBuilder(
    column: $table.resistanceLevel,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<double> get scoreShort => $composableBuilder(
    column: $table.scoreShort,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<double> get scoreLong => $composableBuilder(
    column: $table.scoreLong,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<DateTime> get computedAt => $composableBuilder(
    column: $table.computedAt,
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

class $$DailyAnalysisTableOrderingComposer
    extends i0.Composer<i0.GeneratedDatabase, i1.$DailyAnalysisTable> {
  $$DailyAnalysisTableOrderingComposer({
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

  i0.ColumnOrderings<String> get trendState => $composableBuilder(
    column: $table.trendState,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<String> get reversalState => $composableBuilder(
    column: $table.reversalState,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<double> get supportLevel => $composableBuilder(
    column: $table.supportLevel,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<double> get resistanceLevel => $composableBuilder(
    column: $table.resistanceLevel,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<double> get scoreShort => $composableBuilder(
    column: $table.scoreShort,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<double> get scoreLong => $composableBuilder(
    column: $table.scoreLong,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<DateTime> get computedAt => $composableBuilder(
    column: $table.computedAt,
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

class $$DailyAnalysisTableAnnotationComposer
    extends i0.Composer<i0.GeneratedDatabase, i1.$DailyAnalysisTable> {
  $$DailyAnalysisTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  i0.GeneratedColumn<DateTime> get date =>
      $composableBuilder(column: $table.date, builder: (column) => column);

  i0.GeneratedColumn<String> get trendState => $composableBuilder(
    column: $table.trendState,
    builder: (column) => column,
  );

  i0.GeneratedColumn<String> get reversalState => $composableBuilder(
    column: $table.reversalState,
    builder: (column) => column,
  );

  i0.GeneratedColumn<double> get supportLevel => $composableBuilder(
    column: $table.supportLevel,
    builder: (column) => column,
  );

  i0.GeneratedColumn<double> get resistanceLevel => $composableBuilder(
    column: $table.resistanceLevel,
    builder: (column) => column,
  );

  i0.GeneratedColumn<double> get scoreShort => $composableBuilder(
    column: $table.scoreShort,
    builder: (column) => column,
  );

  i0.GeneratedColumn<double> get scoreLong =>
      $composableBuilder(column: $table.scoreLong, builder: (column) => column);

  i0.GeneratedColumn<DateTime> get computedAt => $composableBuilder(
    column: $table.computedAt,
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

class $$DailyAnalysisTableTableManager
    extends
        i0.RootTableManager<
          i0.GeneratedDatabase,
          i1.$DailyAnalysisTable,
          i1.DailyAnalysisEntry,
          i1.$$DailyAnalysisTableFilterComposer,
          i1.$$DailyAnalysisTableOrderingComposer,
          i1.$$DailyAnalysisTableAnnotationComposer,
          $$DailyAnalysisTableCreateCompanionBuilder,
          $$DailyAnalysisTableUpdateCompanionBuilder,
          (i1.DailyAnalysisEntry, i1.$$DailyAnalysisTableReferences),
          i1.DailyAnalysisEntry,
          i0.PrefetchHooks Function({bool symbol})
        > {
  $$DailyAnalysisTableTableManager(
    i0.GeneratedDatabase db,
    i1.$DailyAnalysisTable table,
  ) : super(
        i0.TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              i1.$$DailyAnalysisTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              i1.$$DailyAnalysisTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              i1.$$DailyAnalysisTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                i0.Value<String> symbol = const i0.Value.absent(),
                i0.Value<DateTime> date = const i0.Value.absent(),
                i0.Value<String> trendState = const i0.Value.absent(),
                i0.Value<String> reversalState = const i0.Value.absent(),
                i0.Value<double?> supportLevel = const i0.Value.absent(),
                i0.Value<double?> resistanceLevel = const i0.Value.absent(),
                i0.Value<double> scoreShort = const i0.Value.absent(),
                i0.Value<double> scoreLong = const i0.Value.absent(),
                i0.Value<DateTime> computedAt = const i0.Value.absent(),
                i0.Value<int> rowid = const i0.Value.absent(),
              }) => i1.DailyAnalysisCompanion(
                symbol: symbol,
                date: date,
                trendState: trendState,
                reversalState: reversalState,
                supportLevel: supportLevel,
                resistanceLevel: resistanceLevel,
                scoreShort: scoreShort,
                scoreLong: scoreLong,
                computedAt: computedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String symbol,
                required DateTime date,
                required String trendState,
                i0.Value<String> reversalState = const i0.Value.absent(),
                i0.Value<double?> supportLevel = const i0.Value.absent(),
                i0.Value<double?> resistanceLevel = const i0.Value.absent(),
                i0.Value<double> scoreShort = const i0.Value.absent(),
                i0.Value<double> scoreLong = const i0.Value.absent(),
                i0.Value<DateTime> computedAt = const i0.Value.absent(),
                i0.Value<int> rowid = const i0.Value.absent(),
              }) => i1.DailyAnalysisCompanion.insert(
                symbol: symbol,
                date: date,
                trendState: trendState,
                reversalState: reversalState,
                supportLevel: supportLevel,
                resistanceLevel: resistanceLevel,
                scoreShort: scoreShort,
                scoreLong: scoreLong,
                computedAt: computedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  i1.$$DailyAnalysisTableReferences(db, table, e),
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
                                    .$$DailyAnalysisTableReferences
                                    ._symbolTable(db),
                                referencedColumn: i1
                                    .$$DailyAnalysisTableReferences
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

typedef $$DailyAnalysisTableProcessedTableManager =
    i0.ProcessedTableManager<
      i0.GeneratedDatabase,
      i1.$DailyAnalysisTable,
      i1.DailyAnalysisEntry,
      i1.$$DailyAnalysisTableFilterComposer,
      i1.$$DailyAnalysisTableOrderingComposer,
      i1.$$DailyAnalysisTableAnnotationComposer,
      $$DailyAnalysisTableCreateCompanionBuilder,
      $$DailyAnalysisTableUpdateCompanionBuilder,
      (i1.DailyAnalysisEntry, i1.$$DailyAnalysisTableReferences),
      i1.DailyAnalysisEntry,
      i0.PrefetchHooks Function({bool symbol})
    >;
typedef $$DailyReasonTableCreateCompanionBuilder =
    i1.DailyReasonCompanion Function({
      required String symbol,
      required DateTime date,
      required int rank,
      required String reasonType,
      required String evidenceJson,
      i0.Value<double> ruleScoreShort,
      i0.Value<double> ruleScoreLong,
      i0.Value<int> rowid,
    });
typedef $$DailyReasonTableUpdateCompanionBuilder =
    i1.DailyReasonCompanion Function({
      i0.Value<String> symbol,
      i0.Value<DateTime> date,
      i0.Value<int> rank,
      i0.Value<String> reasonType,
      i0.Value<String> evidenceJson,
      i0.Value<double> ruleScoreShort,
      i0.Value<double> ruleScoreLong,
      i0.Value<int> rowid,
    });

final class $$DailyReasonTableReferences
    extends
        i0.BaseReferences<
          i0.GeneratedDatabase,
          i1.$DailyReasonTable,
          i1.DailyReasonEntry
        > {
  $$DailyReasonTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static i4.$StockMasterTable _symbolTable(i0.GeneratedDatabase db) =>
      i5.ReadDatabaseContainer(db)
          .resultSet<i4.$StockMasterTable>('stock_master')
          .createAlias(
            i0.$_aliasNameGenerator(
              i5.ReadDatabaseContainer(
                db,
              ).resultSet<i1.$DailyReasonTable>('daily_reason').symbol,
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

class $$DailyReasonTableFilterComposer
    extends i0.Composer<i0.GeneratedDatabase, i1.$DailyReasonTable> {
  $$DailyReasonTableFilterComposer({
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

  i0.ColumnFilters<int> get rank => $composableBuilder(
    column: $table.rank,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<String> get reasonType => $composableBuilder(
    column: $table.reasonType,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<String> get evidenceJson => $composableBuilder(
    column: $table.evidenceJson,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<double> get ruleScoreShort => $composableBuilder(
    column: $table.ruleScoreShort,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<double> get ruleScoreLong => $composableBuilder(
    column: $table.ruleScoreLong,
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

class $$DailyReasonTableOrderingComposer
    extends i0.Composer<i0.GeneratedDatabase, i1.$DailyReasonTable> {
  $$DailyReasonTableOrderingComposer({
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

  i0.ColumnOrderings<int> get rank => $composableBuilder(
    column: $table.rank,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<String> get reasonType => $composableBuilder(
    column: $table.reasonType,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<String> get evidenceJson => $composableBuilder(
    column: $table.evidenceJson,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<double> get ruleScoreShort => $composableBuilder(
    column: $table.ruleScoreShort,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<double> get ruleScoreLong => $composableBuilder(
    column: $table.ruleScoreLong,
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

class $$DailyReasonTableAnnotationComposer
    extends i0.Composer<i0.GeneratedDatabase, i1.$DailyReasonTable> {
  $$DailyReasonTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  i0.GeneratedColumn<DateTime> get date =>
      $composableBuilder(column: $table.date, builder: (column) => column);

  i0.GeneratedColumn<int> get rank =>
      $composableBuilder(column: $table.rank, builder: (column) => column);

  i0.GeneratedColumn<String> get reasonType => $composableBuilder(
    column: $table.reasonType,
    builder: (column) => column,
  );

  i0.GeneratedColumn<String> get evidenceJson => $composableBuilder(
    column: $table.evidenceJson,
    builder: (column) => column,
  );

  i0.GeneratedColumn<double> get ruleScoreShort => $composableBuilder(
    column: $table.ruleScoreShort,
    builder: (column) => column,
  );

  i0.GeneratedColumn<double> get ruleScoreLong => $composableBuilder(
    column: $table.ruleScoreLong,
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

class $$DailyReasonTableTableManager
    extends
        i0.RootTableManager<
          i0.GeneratedDatabase,
          i1.$DailyReasonTable,
          i1.DailyReasonEntry,
          i1.$$DailyReasonTableFilterComposer,
          i1.$$DailyReasonTableOrderingComposer,
          i1.$$DailyReasonTableAnnotationComposer,
          $$DailyReasonTableCreateCompanionBuilder,
          $$DailyReasonTableUpdateCompanionBuilder,
          (i1.DailyReasonEntry, i1.$$DailyReasonTableReferences),
          i1.DailyReasonEntry,
          i0.PrefetchHooks Function({bool symbol})
        > {
  $$DailyReasonTableTableManager(
    i0.GeneratedDatabase db,
    i1.$DailyReasonTable table,
  ) : super(
        i0.TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              i1.$$DailyReasonTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              i1.$$DailyReasonTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              i1.$$DailyReasonTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                i0.Value<String> symbol = const i0.Value.absent(),
                i0.Value<DateTime> date = const i0.Value.absent(),
                i0.Value<int> rank = const i0.Value.absent(),
                i0.Value<String> reasonType = const i0.Value.absent(),
                i0.Value<String> evidenceJson = const i0.Value.absent(),
                i0.Value<double> ruleScoreShort = const i0.Value.absent(),
                i0.Value<double> ruleScoreLong = const i0.Value.absent(),
                i0.Value<int> rowid = const i0.Value.absent(),
              }) => i1.DailyReasonCompanion(
                symbol: symbol,
                date: date,
                rank: rank,
                reasonType: reasonType,
                evidenceJson: evidenceJson,
                ruleScoreShort: ruleScoreShort,
                ruleScoreLong: ruleScoreLong,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String symbol,
                required DateTime date,
                required int rank,
                required String reasonType,
                required String evidenceJson,
                i0.Value<double> ruleScoreShort = const i0.Value.absent(),
                i0.Value<double> ruleScoreLong = const i0.Value.absent(),
                i0.Value<int> rowid = const i0.Value.absent(),
              }) => i1.DailyReasonCompanion.insert(
                symbol: symbol,
                date: date,
                rank: rank,
                reasonType: reasonType,
                evidenceJson: evidenceJson,
                ruleScoreShort: ruleScoreShort,
                ruleScoreLong: ruleScoreLong,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  i1.$$DailyReasonTableReferences(db, table, e),
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
                                referencedTable: i1.$$DailyReasonTableReferences
                                    ._symbolTable(db),
                                referencedColumn: i1
                                    .$$DailyReasonTableReferences
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

typedef $$DailyReasonTableProcessedTableManager =
    i0.ProcessedTableManager<
      i0.GeneratedDatabase,
      i1.$DailyReasonTable,
      i1.DailyReasonEntry,
      i1.$$DailyReasonTableFilterComposer,
      i1.$$DailyReasonTableOrderingComposer,
      i1.$$DailyReasonTableAnnotationComposer,
      $$DailyReasonTableCreateCompanionBuilder,
      $$DailyReasonTableUpdateCompanionBuilder,
      (i1.DailyReasonEntry, i1.$$DailyReasonTableReferences),
      i1.DailyReasonEntry,
      i0.PrefetchHooks Function({bool symbol})
    >;
typedef $$RuleAccuracyTableCreateCompanionBuilder =
    i1.RuleAccuracyCompanion Function({
      required String ruleId,
      required String period,
      i0.Value<int> triggerCount,
      i0.Value<int> successCount,
      i0.Value<double> avgReturn,
      i0.Value<int> distinctDates,
      i0.Value<DateTime> updatedAt,
      i0.Value<int> rowid,
    });
typedef $$RuleAccuracyTableUpdateCompanionBuilder =
    i1.RuleAccuracyCompanion Function({
      i0.Value<String> ruleId,
      i0.Value<String> period,
      i0.Value<int> triggerCount,
      i0.Value<int> successCount,
      i0.Value<double> avgReturn,
      i0.Value<int> distinctDates,
      i0.Value<DateTime> updatedAt,
      i0.Value<int> rowid,
    });

class $$RuleAccuracyTableFilterComposer
    extends i0.Composer<i0.GeneratedDatabase, i1.$RuleAccuracyTable> {
  $$RuleAccuracyTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  i0.ColumnFilters<String> get ruleId => $composableBuilder(
    column: $table.ruleId,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<String> get period => $composableBuilder(
    column: $table.period,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<int> get triggerCount => $composableBuilder(
    column: $table.triggerCount,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<int> get successCount => $composableBuilder(
    column: $table.successCount,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<double> get avgReturn => $composableBuilder(
    column: $table.avgReturn,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<int> get distinctDates => $composableBuilder(
    column: $table.distinctDates,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => i0.ColumnFilters(column),
  );
}

class $$RuleAccuracyTableOrderingComposer
    extends i0.Composer<i0.GeneratedDatabase, i1.$RuleAccuracyTable> {
  $$RuleAccuracyTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  i0.ColumnOrderings<String> get ruleId => $composableBuilder(
    column: $table.ruleId,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<String> get period => $composableBuilder(
    column: $table.period,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<int> get triggerCount => $composableBuilder(
    column: $table.triggerCount,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<int> get successCount => $composableBuilder(
    column: $table.successCount,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<double> get avgReturn => $composableBuilder(
    column: $table.avgReturn,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<int> get distinctDates => $composableBuilder(
    column: $table.distinctDates,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => i0.ColumnOrderings(column),
  );
}

class $$RuleAccuracyTableAnnotationComposer
    extends i0.Composer<i0.GeneratedDatabase, i1.$RuleAccuracyTable> {
  $$RuleAccuracyTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  i0.GeneratedColumn<String> get ruleId =>
      $composableBuilder(column: $table.ruleId, builder: (column) => column);

  i0.GeneratedColumn<String> get period =>
      $composableBuilder(column: $table.period, builder: (column) => column);

  i0.GeneratedColumn<int> get triggerCount => $composableBuilder(
    column: $table.triggerCount,
    builder: (column) => column,
  );

  i0.GeneratedColumn<int> get successCount => $composableBuilder(
    column: $table.successCount,
    builder: (column) => column,
  );

  i0.GeneratedColumn<double> get avgReturn =>
      $composableBuilder(column: $table.avgReturn, builder: (column) => column);

  i0.GeneratedColumn<int> get distinctDates => $composableBuilder(
    column: $table.distinctDates,
    builder: (column) => column,
  );

  i0.GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$RuleAccuracyTableTableManager
    extends
        i0.RootTableManager<
          i0.GeneratedDatabase,
          i1.$RuleAccuracyTable,
          i1.RuleAccuracyEntry,
          i1.$$RuleAccuracyTableFilterComposer,
          i1.$$RuleAccuracyTableOrderingComposer,
          i1.$$RuleAccuracyTableAnnotationComposer,
          $$RuleAccuracyTableCreateCompanionBuilder,
          $$RuleAccuracyTableUpdateCompanionBuilder,
          (
            i1.RuleAccuracyEntry,
            i0.BaseReferences<
              i0.GeneratedDatabase,
              i1.$RuleAccuracyTable,
              i1.RuleAccuracyEntry
            >,
          ),
          i1.RuleAccuracyEntry,
          i0.PrefetchHooks Function()
        > {
  $$RuleAccuracyTableTableManager(
    i0.GeneratedDatabase db,
    i1.$RuleAccuracyTable table,
  ) : super(
        i0.TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              i1.$$RuleAccuracyTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              i1.$$RuleAccuracyTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              i1.$$RuleAccuracyTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                i0.Value<String> ruleId = const i0.Value.absent(),
                i0.Value<String> period = const i0.Value.absent(),
                i0.Value<int> triggerCount = const i0.Value.absent(),
                i0.Value<int> successCount = const i0.Value.absent(),
                i0.Value<double> avgReturn = const i0.Value.absent(),
                i0.Value<int> distinctDates = const i0.Value.absent(),
                i0.Value<DateTime> updatedAt = const i0.Value.absent(),
                i0.Value<int> rowid = const i0.Value.absent(),
              }) => i1.RuleAccuracyCompanion(
                ruleId: ruleId,
                period: period,
                triggerCount: triggerCount,
                successCount: successCount,
                avgReturn: avgReturn,
                distinctDates: distinctDates,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String ruleId,
                required String period,
                i0.Value<int> triggerCount = const i0.Value.absent(),
                i0.Value<int> successCount = const i0.Value.absent(),
                i0.Value<double> avgReturn = const i0.Value.absent(),
                i0.Value<int> distinctDates = const i0.Value.absent(),
                i0.Value<DateTime> updatedAt = const i0.Value.absent(),
                i0.Value<int> rowid = const i0.Value.absent(),
              }) => i1.RuleAccuracyCompanion.insert(
                ruleId: ruleId,
                period: period,
                triggerCount: triggerCount,
                successCount: successCount,
                avgReturn: avgReturn,
                distinctDates: distinctDates,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), i0.BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$RuleAccuracyTableProcessedTableManager =
    i0.ProcessedTableManager<
      i0.GeneratedDatabase,
      i1.$RuleAccuracyTable,
      i1.RuleAccuracyEntry,
      i1.$$RuleAccuracyTableFilterComposer,
      i1.$$RuleAccuracyTableOrderingComposer,
      i1.$$RuleAccuracyTableAnnotationComposer,
      $$RuleAccuracyTableCreateCompanionBuilder,
      $$RuleAccuracyTableUpdateCompanionBuilder,
      (
        i1.RuleAccuracyEntry,
        i0.BaseReferences<
          i0.GeneratedDatabase,
          i1.$RuleAccuracyTable,
          i1.RuleAccuracyEntry
        >,
      ),
      i1.RuleAccuracyEntry,
      i0.PrefetchHooks Function()
    >;
i0.Index get idxDailyAnalysisDate => i0.Index(
  'idx_daily_analysis_date',
  'CREATE INDEX idx_daily_analysis_date ON daily_analysis (date)',
);

class $DailyAnalysisTable extends i2.DailyAnalysis
    with i0.TableInfo<$DailyAnalysisTable, i1.DailyAnalysisEntry> {
  @override
  final i0.GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DailyAnalysisTable(this.attachedDatabase, [this._alias]);
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
  static const i0.VerificationMeta _trendStateMeta = const i0.VerificationMeta(
    'trendState',
  );
  @override
  late final i0.GeneratedColumn<String> trendState = i0.GeneratedColumn<String>(
    'trend_state',
    aliasedName,
    false,
    type: i0.DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const i0.VerificationMeta _reversalStateMeta =
      const i0.VerificationMeta('reversalState');
  @override
  late final i0.GeneratedColumn<String> reversalState =
      i0.GeneratedColumn<String>(
        'reversal_state',
        aliasedName,
        false,
        type: i0.DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const i3.Constant('NONE'),
      );
  static const i0.VerificationMeta _supportLevelMeta =
      const i0.VerificationMeta('supportLevel');
  @override
  late final i0.GeneratedColumn<double> supportLevel =
      i0.GeneratedColumn<double>(
        'support_level',
        aliasedName,
        true,
        type: i0.DriftSqlType.double,
        requiredDuringInsert: false,
      );
  static const i0.VerificationMeta _resistanceLevelMeta =
      const i0.VerificationMeta('resistanceLevel');
  @override
  late final i0.GeneratedColumn<double> resistanceLevel =
      i0.GeneratedColumn<double>(
        'resistance_level',
        aliasedName,
        true,
        type: i0.DriftSqlType.double,
        requiredDuringInsert: false,
      );
  static const i0.VerificationMeta _scoreShortMeta = const i0.VerificationMeta(
    'scoreShort',
  );
  @override
  late final i0.GeneratedColumn<double> scoreShort = i0.GeneratedColumn<double>(
    'score_short',
    aliasedName,
    false,
    type: i0.DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const i3.Constant(0),
  );
  static const i0.VerificationMeta _scoreLongMeta = const i0.VerificationMeta(
    'scoreLong',
  );
  @override
  late final i0.GeneratedColumn<double> scoreLong = i0.GeneratedColumn<double>(
    'score_long',
    aliasedName,
    false,
    type: i0.DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const i3.Constant(0),
  );
  static const i0.VerificationMeta _computedAtMeta = const i0.VerificationMeta(
    'computedAt',
  );
  @override
  late final i0.GeneratedColumn<DateTime> computedAt =
      i0.GeneratedColumn<DateTime>(
        'computed_at',
        aliasedName,
        false,
        type: i0.DriftSqlType.dateTime,
        requiredDuringInsert: false,
        defaultValue: i3.currentDateAndTime,
      );
  @override
  List<i0.GeneratedColumn> get $columns => [
    symbol,
    date,
    trendState,
    reversalState,
    supportLevel,
    resistanceLevel,
    scoreShort,
    scoreLong,
    computedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'daily_analysis';
  @override
  i0.VerificationContext validateIntegrity(
    i0.Insertable<i1.DailyAnalysisEntry> instance, {
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
    if (data.containsKey('trend_state')) {
      context.handle(
        _trendStateMeta,
        trendState.isAcceptableOrUnknown(data['trend_state']!, _trendStateMeta),
      );
    } else if (isInserting) {
      context.missing(_trendStateMeta);
    }
    if (data.containsKey('reversal_state')) {
      context.handle(
        _reversalStateMeta,
        reversalState.isAcceptableOrUnknown(
          data['reversal_state']!,
          _reversalStateMeta,
        ),
      );
    }
    if (data.containsKey('support_level')) {
      context.handle(
        _supportLevelMeta,
        supportLevel.isAcceptableOrUnknown(
          data['support_level']!,
          _supportLevelMeta,
        ),
      );
    }
    if (data.containsKey('resistance_level')) {
      context.handle(
        _resistanceLevelMeta,
        resistanceLevel.isAcceptableOrUnknown(
          data['resistance_level']!,
          _resistanceLevelMeta,
        ),
      );
    }
    if (data.containsKey('score_short')) {
      context.handle(
        _scoreShortMeta,
        scoreShort.isAcceptableOrUnknown(data['score_short']!, _scoreShortMeta),
      );
    }
    if (data.containsKey('score_long')) {
      context.handle(
        _scoreLongMeta,
        scoreLong.isAcceptableOrUnknown(data['score_long']!, _scoreLongMeta),
      );
    }
    if (data.containsKey('computed_at')) {
      context.handle(
        _computedAtMeta,
        computedAt.isAcceptableOrUnknown(data['computed_at']!, _computedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<i0.GeneratedColumn> get $primaryKey => {symbol, date};
  @override
  i1.DailyAnalysisEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return i1.DailyAnalysisEntry(
      symbol: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.string,
        data['${effectivePrefix}symbol'],
      )!,
      date: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.dateTime,
        data['${effectivePrefix}date'],
      )!,
      trendState: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.string,
        data['${effectivePrefix}trend_state'],
      )!,
      reversalState: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.string,
        data['${effectivePrefix}reversal_state'],
      )!,
      supportLevel: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.double,
        data['${effectivePrefix}support_level'],
      ),
      resistanceLevel: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.double,
        data['${effectivePrefix}resistance_level'],
      ),
      scoreShort: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.double,
        data['${effectivePrefix}score_short'],
      )!,
      scoreLong: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.double,
        data['${effectivePrefix}score_long'],
      )!,
      computedAt: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.dateTime,
        data['${effectivePrefix}computed_at'],
      )!,
    );
  }

  @override
  $DailyAnalysisTable createAlias(String alias) {
    return $DailyAnalysisTable(attachedDatabase, alias);
  }
}

class DailyAnalysisEntry extends i0.DataClass
    implements i0.Insertable<i1.DailyAnalysisEntry> {
  /// 股票代碼
  final String symbol;

  /// 分析日期
  final DateTime date;

  /// 趨勢狀態：UP（上漲）、DOWN（下跌）、RANGE（盤整）
  final String trendState;

  /// 反轉狀態：NONE（無）、W2S（弱轉強）、S2W（強轉弱）
  final String reversalState;

  /// 支撐價位
  final double? supportLevel;

  /// 壓力價位
  final double? resistanceLevel;

  /// 短線（5 日）所有觸發規則的總分數
  final double scoreShort;

  /// 長線（60 日）所有觸發規則的總分數
  final double scoreLong;

  /// 分析運算時間
  final DateTime computedAt;
  const DailyAnalysisEntry({
    required this.symbol,
    required this.date,
    required this.trendState,
    required this.reversalState,
    this.supportLevel,
    this.resistanceLevel,
    required this.scoreShort,
    required this.scoreLong,
    required this.computedAt,
  });
  @override
  Map<String, i0.Expression> toColumns(bool nullToAbsent) {
    final map = <String, i0.Expression>{};
    map['symbol'] = i0.Variable<String>(symbol);
    map['date'] = i0.Variable<DateTime>(date);
    map['trend_state'] = i0.Variable<String>(trendState);
    map['reversal_state'] = i0.Variable<String>(reversalState);
    if (!nullToAbsent || supportLevel != null) {
      map['support_level'] = i0.Variable<double>(supportLevel);
    }
    if (!nullToAbsent || resistanceLevel != null) {
      map['resistance_level'] = i0.Variable<double>(resistanceLevel);
    }
    map['score_short'] = i0.Variable<double>(scoreShort);
    map['score_long'] = i0.Variable<double>(scoreLong);
    map['computed_at'] = i0.Variable<DateTime>(computedAt);
    return map;
  }

  i1.DailyAnalysisCompanion toCompanion(bool nullToAbsent) {
    return i1.DailyAnalysisCompanion(
      symbol: i0.Value(symbol),
      date: i0.Value(date),
      trendState: i0.Value(trendState),
      reversalState: i0.Value(reversalState),
      supportLevel: supportLevel == null && nullToAbsent
          ? const i0.Value.absent()
          : i0.Value(supportLevel),
      resistanceLevel: resistanceLevel == null && nullToAbsent
          ? const i0.Value.absent()
          : i0.Value(resistanceLevel),
      scoreShort: i0.Value(scoreShort),
      scoreLong: i0.Value(scoreLong),
      computedAt: i0.Value(computedAt),
    );
  }

  factory DailyAnalysisEntry.fromJson(
    Map<String, dynamic> json, {
    i0.ValueSerializer? serializer,
  }) {
    serializer ??= i0.driftRuntimeOptions.defaultSerializer;
    return DailyAnalysisEntry(
      symbol: serializer.fromJson<String>(json['symbol']),
      date: serializer.fromJson<DateTime>(json['date']),
      trendState: serializer.fromJson<String>(json['trendState']),
      reversalState: serializer.fromJson<String>(json['reversalState']),
      supportLevel: serializer.fromJson<double?>(json['supportLevel']),
      resistanceLevel: serializer.fromJson<double?>(json['resistanceLevel']),
      scoreShort: serializer.fromJson<double>(json['scoreShort']),
      scoreLong: serializer.fromJson<double>(json['scoreLong']),
      computedAt: serializer.fromJson<DateTime>(json['computedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({i0.ValueSerializer? serializer}) {
    serializer ??= i0.driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'symbol': serializer.toJson<String>(symbol),
      'date': serializer.toJson<DateTime>(date),
      'trendState': serializer.toJson<String>(trendState),
      'reversalState': serializer.toJson<String>(reversalState),
      'supportLevel': serializer.toJson<double?>(supportLevel),
      'resistanceLevel': serializer.toJson<double?>(resistanceLevel),
      'scoreShort': serializer.toJson<double>(scoreShort),
      'scoreLong': serializer.toJson<double>(scoreLong),
      'computedAt': serializer.toJson<DateTime>(computedAt),
    };
  }

  i1.DailyAnalysisEntry copyWith({
    String? symbol,
    DateTime? date,
    String? trendState,
    String? reversalState,
    i0.Value<double?> supportLevel = const i0.Value.absent(),
    i0.Value<double?> resistanceLevel = const i0.Value.absent(),
    double? scoreShort,
    double? scoreLong,
    DateTime? computedAt,
  }) => i1.DailyAnalysisEntry(
    symbol: symbol ?? this.symbol,
    date: date ?? this.date,
    trendState: trendState ?? this.trendState,
    reversalState: reversalState ?? this.reversalState,
    supportLevel: supportLevel.present ? supportLevel.value : this.supportLevel,
    resistanceLevel: resistanceLevel.present
        ? resistanceLevel.value
        : this.resistanceLevel,
    scoreShort: scoreShort ?? this.scoreShort,
    scoreLong: scoreLong ?? this.scoreLong,
    computedAt: computedAt ?? this.computedAt,
  );
  DailyAnalysisEntry copyWithCompanion(i1.DailyAnalysisCompanion data) {
    return DailyAnalysisEntry(
      symbol: data.symbol.present ? data.symbol.value : this.symbol,
      date: data.date.present ? data.date.value : this.date,
      trendState: data.trendState.present
          ? data.trendState.value
          : this.trendState,
      reversalState: data.reversalState.present
          ? data.reversalState.value
          : this.reversalState,
      supportLevel: data.supportLevel.present
          ? data.supportLevel.value
          : this.supportLevel,
      resistanceLevel: data.resistanceLevel.present
          ? data.resistanceLevel.value
          : this.resistanceLevel,
      scoreShort: data.scoreShort.present
          ? data.scoreShort.value
          : this.scoreShort,
      scoreLong: data.scoreLong.present ? data.scoreLong.value : this.scoreLong,
      computedAt: data.computedAt.present
          ? data.computedAt.value
          : this.computedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DailyAnalysisEntry(')
          ..write('symbol: $symbol, ')
          ..write('date: $date, ')
          ..write('trendState: $trendState, ')
          ..write('reversalState: $reversalState, ')
          ..write('supportLevel: $supportLevel, ')
          ..write('resistanceLevel: $resistanceLevel, ')
          ..write('scoreShort: $scoreShort, ')
          ..write('scoreLong: $scoreLong, ')
          ..write('computedAt: $computedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    symbol,
    date,
    trendState,
    reversalState,
    supportLevel,
    resistanceLevel,
    scoreShort,
    scoreLong,
    computedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is i1.DailyAnalysisEntry &&
          other.symbol == this.symbol &&
          other.date == this.date &&
          other.trendState == this.trendState &&
          other.reversalState == this.reversalState &&
          other.supportLevel == this.supportLevel &&
          other.resistanceLevel == this.resistanceLevel &&
          other.scoreShort == this.scoreShort &&
          other.scoreLong == this.scoreLong &&
          other.computedAt == this.computedAt);
}

class DailyAnalysisCompanion extends i0.UpdateCompanion<i1.DailyAnalysisEntry> {
  final i0.Value<String> symbol;
  final i0.Value<DateTime> date;
  final i0.Value<String> trendState;
  final i0.Value<String> reversalState;
  final i0.Value<double?> supportLevel;
  final i0.Value<double?> resistanceLevel;
  final i0.Value<double> scoreShort;
  final i0.Value<double> scoreLong;
  final i0.Value<DateTime> computedAt;
  final i0.Value<int> rowid;
  const DailyAnalysisCompanion({
    this.symbol = const i0.Value.absent(),
    this.date = const i0.Value.absent(),
    this.trendState = const i0.Value.absent(),
    this.reversalState = const i0.Value.absent(),
    this.supportLevel = const i0.Value.absent(),
    this.resistanceLevel = const i0.Value.absent(),
    this.scoreShort = const i0.Value.absent(),
    this.scoreLong = const i0.Value.absent(),
    this.computedAt = const i0.Value.absent(),
    this.rowid = const i0.Value.absent(),
  });
  DailyAnalysisCompanion.insert({
    required String symbol,
    required DateTime date,
    required String trendState,
    this.reversalState = const i0.Value.absent(),
    this.supportLevel = const i0.Value.absent(),
    this.resistanceLevel = const i0.Value.absent(),
    this.scoreShort = const i0.Value.absent(),
    this.scoreLong = const i0.Value.absent(),
    this.computedAt = const i0.Value.absent(),
    this.rowid = const i0.Value.absent(),
  }) : symbol = i0.Value(symbol),
       date = i0.Value(date),
       trendState = i0.Value(trendState);
  static i0.Insertable<i1.DailyAnalysisEntry> custom({
    i0.Expression<String>? symbol,
    i0.Expression<DateTime>? date,
    i0.Expression<String>? trendState,
    i0.Expression<String>? reversalState,
    i0.Expression<double>? supportLevel,
    i0.Expression<double>? resistanceLevel,
    i0.Expression<double>? scoreShort,
    i0.Expression<double>? scoreLong,
    i0.Expression<DateTime>? computedAt,
    i0.Expression<int>? rowid,
  }) {
    return i0.RawValuesInsertable({
      if (symbol != null) 'symbol': symbol,
      if (date != null) 'date': date,
      if (trendState != null) 'trend_state': trendState,
      if (reversalState != null) 'reversal_state': reversalState,
      if (supportLevel != null) 'support_level': supportLevel,
      if (resistanceLevel != null) 'resistance_level': resistanceLevel,
      if (scoreShort != null) 'score_short': scoreShort,
      if (scoreLong != null) 'score_long': scoreLong,
      if (computedAt != null) 'computed_at': computedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  i1.DailyAnalysisCompanion copyWith({
    i0.Value<String>? symbol,
    i0.Value<DateTime>? date,
    i0.Value<String>? trendState,
    i0.Value<String>? reversalState,
    i0.Value<double?>? supportLevel,
    i0.Value<double?>? resistanceLevel,
    i0.Value<double>? scoreShort,
    i0.Value<double>? scoreLong,
    i0.Value<DateTime>? computedAt,
    i0.Value<int>? rowid,
  }) {
    return i1.DailyAnalysisCompanion(
      symbol: symbol ?? this.symbol,
      date: date ?? this.date,
      trendState: trendState ?? this.trendState,
      reversalState: reversalState ?? this.reversalState,
      supportLevel: supportLevel ?? this.supportLevel,
      resistanceLevel: resistanceLevel ?? this.resistanceLevel,
      scoreShort: scoreShort ?? this.scoreShort,
      scoreLong: scoreLong ?? this.scoreLong,
      computedAt: computedAt ?? this.computedAt,
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
    if (trendState.present) {
      map['trend_state'] = i0.Variable<String>(trendState.value);
    }
    if (reversalState.present) {
      map['reversal_state'] = i0.Variable<String>(reversalState.value);
    }
    if (supportLevel.present) {
      map['support_level'] = i0.Variable<double>(supportLevel.value);
    }
    if (resistanceLevel.present) {
      map['resistance_level'] = i0.Variable<double>(resistanceLevel.value);
    }
    if (scoreShort.present) {
      map['score_short'] = i0.Variable<double>(scoreShort.value);
    }
    if (scoreLong.present) {
      map['score_long'] = i0.Variable<double>(scoreLong.value);
    }
    if (computedAt.present) {
      map['computed_at'] = i0.Variable<DateTime>(computedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = i0.Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DailyAnalysisCompanion(')
          ..write('symbol: $symbol, ')
          ..write('date: $date, ')
          ..write('trendState: $trendState, ')
          ..write('reversalState: $reversalState, ')
          ..write('supportLevel: $supportLevel, ')
          ..write('resistanceLevel: $resistanceLevel, ')
          ..write('scoreShort: $scoreShort, ')
          ..write('scoreLong: $scoreLong, ')
          ..write('computedAt: $computedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

i0.Index get idxDailyAnalysisScoreShort => i0.Index(
  'idx_daily_analysis_score_short',
  'CREATE INDEX idx_daily_analysis_score_short ON daily_analysis (score_short)',
);
i0.Index get idxDailyAnalysisScoreLong => i0.Index(
  'idx_daily_analysis_score_long',
  'CREATE INDEX idx_daily_analysis_score_long ON daily_analysis (score_long)',
);
i0.Index get idxDailyAnalysisDateScoreShort => i0.Index(
  'idx_daily_analysis_date_score_short',
  'CREATE INDEX idx_daily_analysis_date_score_short ON daily_analysis (date, score_short)',
);
i0.Index get idxDailyAnalysisDateScoreLong => i0.Index(
  'idx_daily_analysis_date_score_long',
  'CREATE INDEX idx_daily_analysis_date_score_long ON daily_analysis (date, score_long)',
);
i0.Index get idxDailyReasonDate => i0.Index(
  'idx_daily_reason_date',
  'CREATE INDEX idx_daily_reason_date ON daily_reason (date)',
);

class $DailyReasonTable extends i2.DailyReason
    with i0.TableInfo<$DailyReasonTable, i1.DailyReasonEntry> {
  @override
  final i0.GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DailyReasonTable(this.attachedDatabase, [this._alias]);
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
  static const i0.VerificationMeta _rankMeta = const i0.VerificationMeta(
    'rank',
  );
  @override
  late final i0.GeneratedColumn<int> rank = i0.GeneratedColumn<int>(
    'rank',
    aliasedName,
    false,
    type: i0.DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const i0.VerificationMeta _reasonTypeMeta = const i0.VerificationMeta(
    'reasonType',
  );
  @override
  late final i0.GeneratedColumn<String> reasonType = i0.GeneratedColumn<String>(
    'reason_type',
    aliasedName,
    false,
    type: i0.DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const i0.VerificationMeta _evidenceJsonMeta =
      const i0.VerificationMeta('evidenceJson');
  @override
  late final i0.GeneratedColumn<String> evidenceJson =
      i0.GeneratedColumn<String>(
        'evidence_json',
        aliasedName,
        false,
        type: i0.DriftSqlType.string,
        requiredDuringInsert: true,
      );
  static const i0.VerificationMeta _ruleScoreShortMeta =
      const i0.VerificationMeta('ruleScoreShort');
  @override
  late final i0.GeneratedColumn<double> ruleScoreShort =
      i0.GeneratedColumn<double>(
        'rule_score_short',
        aliasedName,
        false,
        type: i0.DriftSqlType.double,
        requiredDuringInsert: false,
        defaultValue: const i3.Constant(0),
      );
  static const i0.VerificationMeta _ruleScoreLongMeta =
      const i0.VerificationMeta('ruleScoreLong');
  @override
  late final i0.GeneratedColumn<double> ruleScoreLong =
      i0.GeneratedColumn<double>(
        'rule_score_long',
        aliasedName,
        false,
        type: i0.DriftSqlType.double,
        requiredDuringInsert: false,
        defaultValue: const i3.Constant(0),
      );
  @override
  List<i0.GeneratedColumn> get $columns => [
    symbol,
    date,
    rank,
    reasonType,
    evidenceJson,
    ruleScoreShort,
    ruleScoreLong,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'daily_reason';
  @override
  i0.VerificationContext validateIntegrity(
    i0.Insertable<i1.DailyReasonEntry> instance, {
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
    if (data.containsKey('rank')) {
      context.handle(
        _rankMeta,
        rank.isAcceptableOrUnknown(data['rank']!, _rankMeta),
      );
    } else if (isInserting) {
      context.missing(_rankMeta);
    }
    if (data.containsKey('reason_type')) {
      context.handle(
        _reasonTypeMeta,
        reasonType.isAcceptableOrUnknown(data['reason_type']!, _reasonTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_reasonTypeMeta);
    }
    if (data.containsKey('evidence_json')) {
      context.handle(
        _evidenceJsonMeta,
        evidenceJson.isAcceptableOrUnknown(
          data['evidence_json']!,
          _evidenceJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_evidenceJsonMeta);
    }
    if (data.containsKey('rule_score_short')) {
      context.handle(
        _ruleScoreShortMeta,
        ruleScoreShort.isAcceptableOrUnknown(
          data['rule_score_short']!,
          _ruleScoreShortMeta,
        ),
      );
    }
    if (data.containsKey('rule_score_long')) {
      context.handle(
        _ruleScoreLongMeta,
        ruleScoreLong.isAcceptableOrUnknown(
          data['rule_score_long']!,
          _ruleScoreLongMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<i0.GeneratedColumn> get $primaryKey => {symbol, date, rank};
  @override
  i1.DailyReasonEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return i1.DailyReasonEntry(
      symbol: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.string,
        data['${effectivePrefix}symbol'],
      )!,
      date: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.dateTime,
        data['${effectivePrefix}date'],
      )!,
      rank: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.int,
        data['${effectivePrefix}rank'],
      )!,
      reasonType: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.string,
        data['${effectivePrefix}reason_type'],
      )!,
      evidenceJson: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.string,
        data['${effectivePrefix}evidence_json'],
      )!,
      ruleScoreShort: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.double,
        data['${effectivePrefix}rule_score_short'],
      )!,
      ruleScoreLong: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.double,
        data['${effectivePrefix}rule_score_long'],
      )!,
    );
  }

  @override
  $DailyReasonTable createAlias(String alias) {
    return $DailyReasonTable(attachedDatabase, alias);
  }
}

class DailyReasonEntry extends i0.DataClass
    implements i0.Insertable<i1.DailyReasonEntry> {
  /// 股票代碼
  final String symbol;

  /// 分析日期
  final DateTime date;

  /// 原因排序（1 = 主要、2 = 次要）
  final int rank;

  /// 原因類型代碼
  final String reasonType;

  /// 證據資料（JSON 格式）
  final String evidenceJson;

  /// 此規則在短線 horizon 的分數貢獻
  final double ruleScoreShort;

  /// 此規則在長線 horizon 的分數貢獻
  final double ruleScoreLong;
  const DailyReasonEntry({
    required this.symbol,
    required this.date,
    required this.rank,
    required this.reasonType,
    required this.evidenceJson,
    required this.ruleScoreShort,
    required this.ruleScoreLong,
  });
  @override
  Map<String, i0.Expression> toColumns(bool nullToAbsent) {
    final map = <String, i0.Expression>{};
    map['symbol'] = i0.Variable<String>(symbol);
    map['date'] = i0.Variable<DateTime>(date);
    map['rank'] = i0.Variable<int>(rank);
    map['reason_type'] = i0.Variable<String>(reasonType);
    map['evidence_json'] = i0.Variable<String>(evidenceJson);
    map['rule_score_short'] = i0.Variable<double>(ruleScoreShort);
    map['rule_score_long'] = i0.Variable<double>(ruleScoreLong);
    return map;
  }

  i1.DailyReasonCompanion toCompanion(bool nullToAbsent) {
    return i1.DailyReasonCompanion(
      symbol: i0.Value(symbol),
      date: i0.Value(date),
      rank: i0.Value(rank),
      reasonType: i0.Value(reasonType),
      evidenceJson: i0.Value(evidenceJson),
      ruleScoreShort: i0.Value(ruleScoreShort),
      ruleScoreLong: i0.Value(ruleScoreLong),
    );
  }

  factory DailyReasonEntry.fromJson(
    Map<String, dynamic> json, {
    i0.ValueSerializer? serializer,
  }) {
    serializer ??= i0.driftRuntimeOptions.defaultSerializer;
    return DailyReasonEntry(
      symbol: serializer.fromJson<String>(json['symbol']),
      date: serializer.fromJson<DateTime>(json['date']),
      rank: serializer.fromJson<int>(json['rank']),
      reasonType: serializer.fromJson<String>(json['reasonType']),
      evidenceJson: serializer.fromJson<String>(json['evidenceJson']),
      ruleScoreShort: serializer.fromJson<double>(json['ruleScoreShort']),
      ruleScoreLong: serializer.fromJson<double>(json['ruleScoreLong']),
    );
  }
  @override
  Map<String, dynamic> toJson({i0.ValueSerializer? serializer}) {
    serializer ??= i0.driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'symbol': serializer.toJson<String>(symbol),
      'date': serializer.toJson<DateTime>(date),
      'rank': serializer.toJson<int>(rank),
      'reasonType': serializer.toJson<String>(reasonType),
      'evidenceJson': serializer.toJson<String>(evidenceJson),
      'ruleScoreShort': serializer.toJson<double>(ruleScoreShort),
      'ruleScoreLong': serializer.toJson<double>(ruleScoreLong),
    };
  }

  i1.DailyReasonEntry copyWith({
    String? symbol,
    DateTime? date,
    int? rank,
    String? reasonType,
    String? evidenceJson,
    double? ruleScoreShort,
    double? ruleScoreLong,
  }) => i1.DailyReasonEntry(
    symbol: symbol ?? this.symbol,
    date: date ?? this.date,
    rank: rank ?? this.rank,
    reasonType: reasonType ?? this.reasonType,
    evidenceJson: evidenceJson ?? this.evidenceJson,
    ruleScoreShort: ruleScoreShort ?? this.ruleScoreShort,
    ruleScoreLong: ruleScoreLong ?? this.ruleScoreLong,
  );
  DailyReasonEntry copyWithCompanion(i1.DailyReasonCompanion data) {
    return DailyReasonEntry(
      symbol: data.symbol.present ? data.symbol.value : this.symbol,
      date: data.date.present ? data.date.value : this.date,
      rank: data.rank.present ? data.rank.value : this.rank,
      reasonType: data.reasonType.present
          ? data.reasonType.value
          : this.reasonType,
      evidenceJson: data.evidenceJson.present
          ? data.evidenceJson.value
          : this.evidenceJson,
      ruleScoreShort: data.ruleScoreShort.present
          ? data.ruleScoreShort.value
          : this.ruleScoreShort,
      ruleScoreLong: data.ruleScoreLong.present
          ? data.ruleScoreLong.value
          : this.ruleScoreLong,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DailyReasonEntry(')
          ..write('symbol: $symbol, ')
          ..write('date: $date, ')
          ..write('rank: $rank, ')
          ..write('reasonType: $reasonType, ')
          ..write('evidenceJson: $evidenceJson, ')
          ..write('ruleScoreShort: $ruleScoreShort, ')
          ..write('ruleScoreLong: $ruleScoreLong')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    symbol,
    date,
    rank,
    reasonType,
    evidenceJson,
    ruleScoreShort,
    ruleScoreLong,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is i1.DailyReasonEntry &&
          other.symbol == this.symbol &&
          other.date == this.date &&
          other.rank == this.rank &&
          other.reasonType == this.reasonType &&
          other.evidenceJson == this.evidenceJson &&
          other.ruleScoreShort == this.ruleScoreShort &&
          other.ruleScoreLong == this.ruleScoreLong);
}

class DailyReasonCompanion extends i0.UpdateCompanion<i1.DailyReasonEntry> {
  final i0.Value<String> symbol;
  final i0.Value<DateTime> date;
  final i0.Value<int> rank;
  final i0.Value<String> reasonType;
  final i0.Value<String> evidenceJson;
  final i0.Value<double> ruleScoreShort;
  final i0.Value<double> ruleScoreLong;
  final i0.Value<int> rowid;
  const DailyReasonCompanion({
    this.symbol = const i0.Value.absent(),
    this.date = const i0.Value.absent(),
    this.rank = const i0.Value.absent(),
    this.reasonType = const i0.Value.absent(),
    this.evidenceJson = const i0.Value.absent(),
    this.ruleScoreShort = const i0.Value.absent(),
    this.ruleScoreLong = const i0.Value.absent(),
    this.rowid = const i0.Value.absent(),
  });
  DailyReasonCompanion.insert({
    required String symbol,
    required DateTime date,
    required int rank,
    required String reasonType,
    required String evidenceJson,
    this.ruleScoreShort = const i0.Value.absent(),
    this.ruleScoreLong = const i0.Value.absent(),
    this.rowid = const i0.Value.absent(),
  }) : symbol = i0.Value(symbol),
       date = i0.Value(date),
       rank = i0.Value(rank),
       reasonType = i0.Value(reasonType),
       evidenceJson = i0.Value(evidenceJson);
  static i0.Insertable<i1.DailyReasonEntry> custom({
    i0.Expression<String>? symbol,
    i0.Expression<DateTime>? date,
    i0.Expression<int>? rank,
    i0.Expression<String>? reasonType,
    i0.Expression<String>? evidenceJson,
    i0.Expression<double>? ruleScoreShort,
    i0.Expression<double>? ruleScoreLong,
    i0.Expression<int>? rowid,
  }) {
    return i0.RawValuesInsertable({
      if (symbol != null) 'symbol': symbol,
      if (date != null) 'date': date,
      if (rank != null) 'rank': rank,
      if (reasonType != null) 'reason_type': reasonType,
      if (evidenceJson != null) 'evidence_json': evidenceJson,
      if (ruleScoreShort != null) 'rule_score_short': ruleScoreShort,
      if (ruleScoreLong != null) 'rule_score_long': ruleScoreLong,
      if (rowid != null) 'rowid': rowid,
    });
  }

  i1.DailyReasonCompanion copyWith({
    i0.Value<String>? symbol,
    i0.Value<DateTime>? date,
    i0.Value<int>? rank,
    i0.Value<String>? reasonType,
    i0.Value<String>? evidenceJson,
    i0.Value<double>? ruleScoreShort,
    i0.Value<double>? ruleScoreLong,
    i0.Value<int>? rowid,
  }) {
    return i1.DailyReasonCompanion(
      symbol: symbol ?? this.symbol,
      date: date ?? this.date,
      rank: rank ?? this.rank,
      reasonType: reasonType ?? this.reasonType,
      evidenceJson: evidenceJson ?? this.evidenceJson,
      ruleScoreShort: ruleScoreShort ?? this.ruleScoreShort,
      ruleScoreLong: ruleScoreLong ?? this.ruleScoreLong,
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
    if (rank.present) {
      map['rank'] = i0.Variable<int>(rank.value);
    }
    if (reasonType.present) {
      map['reason_type'] = i0.Variable<String>(reasonType.value);
    }
    if (evidenceJson.present) {
      map['evidence_json'] = i0.Variable<String>(evidenceJson.value);
    }
    if (ruleScoreShort.present) {
      map['rule_score_short'] = i0.Variable<double>(ruleScoreShort.value);
    }
    if (ruleScoreLong.present) {
      map['rule_score_long'] = i0.Variable<double>(ruleScoreLong.value);
    }
    if (rowid.present) {
      map['rowid'] = i0.Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DailyReasonCompanion(')
          ..write('symbol: $symbol, ')
          ..write('date: $date, ')
          ..write('rank: $rank, ')
          ..write('reasonType: $reasonType, ')
          ..write('evidenceJson: $evidenceJson, ')
          ..write('ruleScoreShort: $ruleScoreShort, ')
          ..write('ruleScoreLong: $ruleScoreLong, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $RuleAccuracyTable extends i2.RuleAccuracy
    with i0.TableInfo<$RuleAccuracyTable, i1.RuleAccuracyEntry> {
  @override
  final i0.GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RuleAccuracyTable(this.attachedDatabase, [this._alias]);
  static const i0.VerificationMeta _ruleIdMeta = const i0.VerificationMeta(
    'ruleId',
  );
  @override
  late final i0.GeneratedColumn<String> ruleId = i0.GeneratedColumn<String>(
    'rule_id',
    aliasedName,
    false,
    type: i0.DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const i0.VerificationMeta _periodMeta = const i0.VerificationMeta(
    'period',
  );
  @override
  late final i0.GeneratedColumn<String> period = i0.GeneratedColumn<String>(
    'period',
    aliasedName,
    false,
    type: i0.DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const i0.VerificationMeta _triggerCountMeta =
      const i0.VerificationMeta('triggerCount');
  @override
  late final i0.GeneratedColumn<int> triggerCount = i0.GeneratedColumn<int>(
    'trigger_count',
    aliasedName,
    false,
    type: i0.DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const i3.Constant(0),
  );
  static const i0.VerificationMeta _successCountMeta =
      const i0.VerificationMeta('successCount');
  @override
  late final i0.GeneratedColumn<int> successCount = i0.GeneratedColumn<int>(
    'success_count',
    aliasedName,
    false,
    type: i0.DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const i3.Constant(0),
  );
  static const i0.VerificationMeta _avgReturnMeta = const i0.VerificationMeta(
    'avgReturn',
  );
  @override
  late final i0.GeneratedColumn<double> avgReturn = i0.GeneratedColumn<double>(
    'avg_return',
    aliasedName,
    false,
    type: i0.DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const i3.Constant(0),
  );
  static const i0.VerificationMeta _distinctDatesMeta =
      const i0.VerificationMeta('distinctDates');
  @override
  late final i0.GeneratedColumn<int> distinctDates = i0.GeneratedColumn<int>(
    'distinct_dates',
    aliasedName,
    false,
    type: i0.DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const i3.Constant(0),
  );
  static const i0.VerificationMeta _updatedAtMeta = const i0.VerificationMeta(
    'updatedAt',
  );
  @override
  late final i0.GeneratedColumn<DateTime> updatedAt =
      i0.GeneratedColumn<DateTime>(
        'updated_at',
        aliasedName,
        false,
        type: i0.DriftSqlType.dateTime,
        requiredDuringInsert: false,
        defaultValue: i3.currentDateAndTime,
      );
  @override
  List<i0.GeneratedColumn> get $columns => [
    ruleId,
    period,
    triggerCount,
    successCount,
    avgReturn,
    distinctDates,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'rule_accuracy';
  @override
  i0.VerificationContext validateIntegrity(
    i0.Insertable<i1.RuleAccuracyEntry> instance, {
    bool isInserting = false,
  }) {
    final context = i0.VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('rule_id')) {
      context.handle(
        _ruleIdMeta,
        ruleId.isAcceptableOrUnknown(data['rule_id']!, _ruleIdMeta),
      );
    } else if (isInserting) {
      context.missing(_ruleIdMeta);
    }
    if (data.containsKey('period')) {
      context.handle(
        _periodMeta,
        period.isAcceptableOrUnknown(data['period']!, _periodMeta),
      );
    } else if (isInserting) {
      context.missing(_periodMeta);
    }
    if (data.containsKey('trigger_count')) {
      context.handle(
        _triggerCountMeta,
        triggerCount.isAcceptableOrUnknown(
          data['trigger_count']!,
          _triggerCountMeta,
        ),
      );
    }
    if (data.containsKey('success_count')) {
      context.handle(
        _successCountMeta,
        successCount.isAcceptableOrUnknown(
          data['success_count']!,
          _successCountMeta,
        ),
      );
    }
    if (data.containsKey('avg_return')) {
      context.handle(
        _avgReturnMeta,
        avgReturn.isAcceptableOrUnknown(data['avg_return']!, _avgReturnMeta),
      );
    }
    if (data.containsKey('distinct_dates')) {
      context.handle(
        _distinctDatesMeta,
        distinctDates.isAcceptableOrUnknown(
          data['distinct_dates']!,
          _distinctDatesMeta,
        ),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<i0.GeneratedColumn> get $primaryKey => {ruleId, period};
  @override
  i1.RuleAccuracyEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return i1.RuleAccuracyEntry(
      ruleId: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.string,
        data['${effectivePrefix}rule_id'],
      )!,
      period: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.string,
        data['${effectivePrefix}period'],
      )!,
      triggerCount: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.int,
        data['${effectivePrefix}trigger_count'],
      )!,
      successCount: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.int,
        data['${effectivePrefix}success_count'],
      )!,
      avgReturn: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.double,
        data['${effectivePrefix}avg_return'],
      )!,
      distinctDates: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.int,
        data['${effectivePrefix}distinct_dates'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $RuleAccuracyTable createAlias(String alias) {
    return $RuleAccuracyTable(attachedDatabase, alias);
  }
}

class RuleAccuracyEntry extends i0.DataClass
    implements i0.Insertable<i1.RuleAccuracyEntry> {
  /// 規則 ID（如 reversal_w2s）
  final String ruleId;

  /// 統計週期：「N 天 + D」持有天數字串（如 5D、20D、60D）
  final String period;

  /// 觸發次數
  final int triggerCount;

  /// 成功次數（N 日後上漲）
  final int successCount;

  /// 平均報酬率（%）
  final double avgReturn;

  /// 觸發「日」數（distinct 觸發日期）
  ///
  /// 有效樣本量級是這個值，不是 [triggerCount]。同一天觸發的數十檔股票
  /// 幾乎共用同一個市場因子（實測 2026-07-17 全市場單日 −3.95%），
  /// 加上持有窗重疊，pooled 筆數是偽重複。
  /// 判準與 calibration 決策層的 [CalibrationThresholds.minDistinctDates]
  /// 同源 —— 該處註解早已寫明此事，只是未擴散到 app 內的顯示層。
  final int distinctDates;

  /// 最後更新時間
  final DateTime updatedAt;
  const RuleAccuracyEntry({
    required this.ruleId,
    required this.period,
    required this.triggerCount,
    required this.successCount,
    required this.avgReturn,
    required this.distinctDates,
    required this.updatedAt,
  });
  @override
  Map<String, i0.Expression> toColumns(bool nullToAbsent) {
    final map = <String, i0.Expression>{};
    map['rule_id'] = i0.Variable<String>(ruleId);
    map['period'] = i0.Variable<String>(period);
    map['trigger_count'] = i0.Variable<int>(triggerCount);
    map['success_count'] = i0.Variable<int>(successCount);
    map['avg_return'] = i0.Variable<double>(avgReturn);
    map['distinct_dates'] = i0.Variable<int>(distinctDates);
    map['updated_at'] = i0.Variable<DateTime>(updatedAt);
    return map;
  }

  i1.RuleAccuracyCompanion toCompanion(bool nullToAbsent) {
    return i1.RuleAccuracyCompanion(
      ruleId: i0.Value(ruleId),
      period: i0.Value(period),
      triggerCount: i0.Value(triggerCount),
      successCount: i0.Value(successCount),
      avgReturn: i0.Value(avgReturn),
      distinctDates: i0.Value(distinctDates),
      updatedAt: i0.Value(updatedAt),
    );
  }

  factory RuleAccuracyEntry.fromJson(
    Map<String, dynamic> json, {
    i0.ValueSerializer? serializer,
  }) {
    serializer ??= i0.driftRuntimeOptions.defaultSerializer;
    return RuleAccuracyEntry(
      ruleId: serializer.fromJson<String>(json['ruleId']),
      period: serializer.fromJson<String>(json['period']),
      triggerCount: serializer.fromJson<int>(json['triggerCount']),
      successCount: serializer.fromJson<int>(json['successCount']),
      avgReturn: serializer.fromJson<double>(json['avgReturn']),
      distinctDates: serializer.fromJson<int>(json['distinctDates']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({i0.ValueSerializer? serializer}) {
    serializer ??= i0.driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'ruleId': serializer.toJson<String>(ruleId),
      'period': serializer.toJson<String>(period),
      'triggerCount': serializer.toJson<int>(triggerCount),
      'successCount': serializer.toJson<int>(successCount),
      'avgReturn': serializer.toJson<double>(avgReturn),
      'distinctDates': serializer.toJson<int>(distinctDates),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  i1.RuleAccuracyEntry copyWith({
    String? ruleId,
    String? period,
    int? triggerCount,
    int? successCount,
    double? avgReturn,
    int? distinctDates,
    DateTime? updatedAt,
  }) => i1.RuleAccuracyEntry(
    ruleId: ruleId ?? this.ruleId,
    period: period ?? this.period,
    triggerCount: triggerCount ?? this.triggerCount,
    successCount: successCount ?? this.successCount,
    avgReturn: avgReturn ?? this.avgReturn,
    distinctDates: distinctDates ?? this.distinctDates,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  RuleAccuracyEntry copyWithCompanion(i1.RuleAccuracyCompanion data) {
    return RuleAccuracyEntry(
      ruleId: data.ruleId.present ? data.ruleId.value : this.ruleId,
      period: data.period.present ? data.period.value : this.period,
      triggerCount: data.triggerCount.present
          ? data.triggerCount.value
          : this.triggerCount,
      successCount: data.successCount.present
          ? data.successCount.value
          : this.successCount,
      avgReturn: data.avgReturn.present ? data.avgReturn.value : this.avgReturn,
      distinctDates: data.distinctDates.present
          ? data.distinctDates.value
          : this.distinctDates,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RuleAccuracyEntry(')
          ..write('ruleId: $ruleId, ')
          ..write('period: $period, ')
          ..write('triggerCount: $triggerCount, ')
          ..write('successCount: $successCount, ')
          ..write('avgReturn: $avgReturn, ')
          ..write('distinctDates: $distinctDates, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    ruleId,
    period,
    triggerCount,
    successCount,
    avgReturn,
    distinctDates,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is i1.RuleAccuracyEntry &&
          other.ruleId == this.ruleId &&
          other.period == this.period &&
          other.triggerCount == this.triggerCount &&
          other.successCount == this.successCount &&
          other.avgReturn == this.avgReturn &&
          other.distinctDates == this.distinctDates &&
          other.updatedAt == this.updatedAt);
}

class RuleAccuracyCompanion extends i0.UpdateCompanion<i1.RuleAccuracyEntry> {
  final i0.Value<String> ruleId;
  final i0.Value<String> period;
  final i0.Value<int> triggerCount;
  final i0.Value<int> successCount;
  final i0.Value<double> avgReturn;
  final i0.Value<int> distinctDates;
  final i0.Value<DateTime> updatedAt;
  final i0.Value<int> rowid;
  const RuleAccuracyCompanion({
    this.ruleId = const i0.Value.absent(),
    this.period = const i0.Value.absent(),
    this.triggerCount = const i0.Value.absent(),
    this.successCount = const i0.Value.absent(),
    this.avgReturn = const i0.Value.absent(),
    this.distinctDates = const i0.Value.absent(),
    this.updatedAt = const i0.Value.absent(),
    this.rowid = const i0.Value.absent(),
  });
  RuleAccuracyCompanion.insert({
    required String ruleId,
    required String period,
    this.triggerCount = const i0.Value.absent(),
    this.successCount = const i0.Value.absent(),
    this.avgReturn = const i0.Value.absent(),
    this.distinctDates = const i0.Value.absent(),
    this.updatedAt = const i0.Value.absent(),
    this.rowid = const i0.Value.absent(),
  }) : ruleId = i0.Value(ruleId),
       period = i0.Value(period);
  static i0.Insertable<i1.RuleAccuracyEntry> custom({
    i0.Expression<String>? ruleId,
    i0.Expression<String>? period,
    i0.Expression<int>? triggerCount,
    i0.Expression<int>? successCount,
    i0.Expression<double>? avgReturn,
    i0.Expression<int>? distinctDates,
    i0.Expression<DateTime>? updatedAt,
    i0.Expression<int>? rowid,
  }) {
    return i0.RawValuesInsertable({
      if (ruleId != null) 'rule_id': ruleId,
      if (period != null) 'period': period,
      if (triggerCount != null) 'trigger_count': triggerCount,
      if (successCount != null) 'success_count': successCount,
      if (avgReturn != null) 'avg_return': avgReturn,
      if (distinctDates != null) 'distinct_dates': distinctDates,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  i1.RuleAccuracyCompanion copyWith({
    i0.Value<String>? ruleId,
    i0.Value<String>? period,
    i0.Value<int>? triggerCount,
    i0.Value<int>? successCount,
    i0.Value<double>? avgReturn,
    i0.Value<int>? distinctDates,
    i0.Value<DateTime>? updatedAt,
    i0.Value<int>? rowid,
  }) {
    return i1.RuleAccuracyCompanion(
      ruleId: ruleId ?? this.ruleId,
      period: period ?? this.period,
      triggerCount: triggerCount ?? this.triggerCount,
      successCount: successCount ?? this.successCount,
      avgReturn: avgReturn ?? this.avgReturn,
      distinctDates: distinctDates ?? this.distinctDates,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, i0.Expression> toColumns(bool nullToAbsent) {
    final map = <String, i0.Expression>{};
    if (ruleId.present) {
      map['rule_id'] = i0.Variable<String>(ruleId.value);
    }
    if (period.present) {
      map['period'] = i0.Variable<String>(period.value);
    }
    if (triggerCount.present) {
      map['trigger_count'] = i0.Variable<int>(triggerCount.value);
    }
    if (successCount.present) {
      map['success_count'] = i0.Variable<int>(successCount.value);
    }
    if (avgReturn.present) {
      map['avg_return'] = i0.Variable<double>(avgReturn.value);
    }
    if (distinctDates.present) {
      map['distinct_dates'] = i0.Variable<int>(distinctDates.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = i0.Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = i0.Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RuleAccuracyCompanion(')
          ..write('ruleId: $ruleId, ')
          ..write('period: $period, ')
          ..write('triggerCount: $triggerCount, ')
          ..write('successCount: $successCount, ')
          ..write('avgReturn: $avgReturn, ')
          ..write('distinctDates: $distinctDates, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}
