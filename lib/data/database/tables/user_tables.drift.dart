// dart format width=80
// ignore_for_file: type=lint
import 'package:drift/drift.dart' as i0;
import 'package:daredevil/data/database/tables/user_tables.drift.dart' as i1;
import 'package:daredevil/data/database/tables/user_tables.dart' as i2;
import 'package:drift/src/runtime/query_builder/query_builder.dart' as i3;
import 'package:drift/internal/modular.dart' as i4;
import 'package:daredevil/data/database/tables/stock_master.drift.dart' as i5;

typedef $$WatchlistGroupsTableCreateCompanionBuilder =
    i1.WatchlistGroupsCompanion Function({
      i0.Value<int> id,
      required String name,
      i0.Value<int> sortOrder,
      i0.Value<bool> isDefault,
      i0.Value<DateTime> createdAt,
    });
typedef $$WatchlistGroupsTableUpdateCompanionBuilder =
    i1.WatchlistGroupsCompanion Function({
      i0.Value<int> id,
      i0.Value<String> name,
      i0.Value<int> sortOrder,
      i0.Value<bool> isDefault,
      i0.Value<DateTime> createdAt,
    });

final class $$WatchlistGroupsTableReferences
    extends
        i0.BaseReferences<
          i0.GeneratedDatabase,
          i1.$WatchlistGroupsTable,
          i1.WatchlistGroupEntry
        > {
  $$WatchlistGroupsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static i0.MultiTypedResultKey<i1.$WatchlistTable, List<i1.WatchlistEntry>>
  _watchlistRefsTable(i0.GeneratedDatabase db) =>
      i0.MultiTypedResultKey.fromTable(
        i4.ReadDatabaseContainer(db).resultSet<i1.$WatchlistTable>('watchlist'),
        aliasName: i0.$_aliasNameGenerator(
          i4.ReadDatabaseContainer(
            db,
          ).resultSet<i1.$WatchlistGroupsTable>('watchlist_groups').id,
          i4.ReadDatabaseContainer(
            db,
          ).resultSet<i1.$WatchlistTable>('watchlist').groupId,
        ),
      );

  i1.$$WatchlistTableProcessedTableManager get watchlistRefs {
    final manager = i1
        .$$WatchlistTableTableManager(
          $_db,
          i4.ReadDatabaseContainer(
            $_db,
          ).resultSet<i1.$WatchlistTable>('watchlist'),
        )
        .filter((f) => f.groupId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_watchlistRefsTable($_db));
    return i0.ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$WatchlistGroupsTableFilterComposer
    extends i0.Composer<i0.GeneratedDatabase, i1.$WatchlistGroupsTable> {
  $$WatchlistGroupsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  i0.ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<bool> get isDefault => $composableBuilder(
    column: $table.isDefault,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.Expression<bool> watchlistRefs(
    i0.Expression<bool> Function(i1.$$WatchlistTableFilterComposer f) f,
  ) {
    final i1.$$WatchlistTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: i4.ReadDatabaseContainer(
        $db,
      ).resultSet<i1.$WatchlistTable>('watchlist'),
      getReferencedColumn: (t) => t.groupId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => i1.$$WatchlistTableFilterComposer(
            $db: $db,
            $table: i4.ReadDatabaseContainer(
              $db,
            ).resultSet<i1.$WatchlistTable>('watchlist'),
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$WatchlistGroupsTableOrderingComposer
    extends i0.Composer<i0.GeneratedDatabase, i1.$WatchlistGroupsTable> {
  $$WatchlistGroupsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  i0.ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<bool> get isDefault => $composableBuilder(
    column: $table.isDefault,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => i0.ColumnOrderings(column),
  );
}

class $$WatchlistGroupsTableAnnotationComposer
    extends i0.Composer<i0.GeneratedDatabase, i1.$WatchlistGroupsTable> {
  $$WatchlistGroupsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  i0.GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  i0.GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  i0.GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);

  i0.GeneratedColumn<bool> get isDefault =>
      $composableBuilder(column: $table.isDefault, builder: (column) => column);

  i0.GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  i0.Expression<T> watchlistRefs<T extends Object>(
    i0.Expression<T> Function(i1.$$WatchlistTableAnnotationComposer a) f,
  ) {
    final i1.$$WatchlistTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: i4.ReadDatabaseContainer(
        $db,
      ).resultSet<i1.$WatchlistTable>('watchlist'),
      getReferencedColumn: (t) => t.groupId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => i1.$$WatchlistTableAnnotationComposer(
            $db: $db,
            $table: i4.ReadDatabaseContainer(
              $db,
            ).resultSet<i1.$WatchlistTable>('watchlist'),
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$WatchlistGroupsTableTableManager
    extends
        i0.RootTableManager<
          i0.GeneratedDatabase,
          i1.$WatchlistGroupsTable,
          i1.WatchlistGroupEntry,
          i1.$$WatchlistGroupsTableFilterComposer,
          i1.$$WatchlistGroupsTableOrderingComposer,
          i1.$$WatchlistGroupsTableAnnotationComposer,
          $$WatchlistGroupsTableCreateCompanionBuilder,
          $$WatchlistGroupsTableUpdateCompanionBuilder,
          (i1.WatchlistGroupEntry, i1.$$WatchlistGroupsTableReferences),
          i1.WatchlistGroupEntry,
          i0.PrefetchHooks Function({bool watchlistRefs})
        > {
  $$WatchlistGroupsTableTableManager(
    i0.GeneratedDatabase db,
    i1.$WatchlistGroupsTable table,
  ) : super(
        i0.TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              i1.$$WatchlistGroupsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              i1.$$WatchlistGroupsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () => i1
              .$$WatchlistGroupsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                i0.Value<int> id = const i0.Value.absent(),
                i0.Value<String> name = const i0.Value.absent(),
                i0.Value<int> sortOrder = const i0.Value.absent(),
                i0.Value<bool> isDefault = const i0.Value.absent(),
                i0.Value<DateTime> createdAt = const i0.Value.absent(),
              }) => i1.WatchlistGroupsCompanion(
                id: id,
                name: name,
                sortOrder: sortOrder,
                isDefault: isDefault,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                i0.Value<int> id = const i0.Value.absent(),
                required String name,
                i0.Value<int> sortOrder = const i0.Value.absent(),
                i0.Value<bool> isDefault = const i0.Value.absent(),
                i0.Value<DateTime> createdAt = const i0.Value.absent(),
              }) => i1.WatchlistGroupsCompanion.insert(
                id: id,
                name: name,
                sortOrder: sortOrder,
                isDefault: isDefault,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  i1.$$WatchlistGroupsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({watchlistRefs = false}) {
            return i0.PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (watchlistRefs)
                  i4.ReadDatabaseContainer(
                    db,
                  ).resultSet<i1.$WatchlistTable>('watchlist'),
              ],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (watchlistRefs)
                    await i0.$_getPrefetchedData<
                      i1.WatchlistGroupEntry,
                      i1.$WatchlistGroupsTable,
                      i1.WatchlistEntry
                    >(
                      currentTable: table,
                      referencedTable: i1.$$WatchlistGroupsTableReferences
                          ._watchlistRefsTable(db),
                      managerFromTypedResult: (p0) => i1
                          .$$WatchlistGroupsTableReferences(db, table, p0)
                          .watchlistRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.groupId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$WatchlistGroupsTableProcessedTableManager =
    i0.ProcessedTableManager<
      i0.GeneratedDatabase,
      i1.$WatchlistGroupsTable,
      i1.WatchlistGroupEntry,
      i1.$$WatchlistGroupsTableFilterComposer,
      i1.$$WatchlistGroupsTableOrderingComposer,
      i1.$$WatchlistGroupsTableAnnotationComposer,
      $$WatchlistGroupsTableCreateCompanionBuilder,
      $$WatchlistGroupsTableUpdateCompanionBuilder,
      (i1.WatchlistGroupEntry, i1.$$WatchlistGroupsTableReferences),
      i1.WatchlistGroupEntry,
      i0.PrefetchHooks Function({bool watchlistRefs})
    >;
typedef $$WatchlistTableCreateCompanionBuilder =
    i1.WatchlistCompanion Function({
      required String symbol,
      i0.Value<DateTime> createdAt,
      i0.Value<int?> groupId,
      i0.Value<int> rowid,
    });
typedef $$WatchlistTableUpdateCompanionBuilder =
    i1.WatchlistCompanion Function({
      i0.Value<String> symbol,
      i0.Value<DateTime> createdAt,
      i0.Value<int?> groupId,
      i0.Value<int> rowid,
    });

final class $$WatchlistTableReferences
    extends
        i0.BaseReferences<
          i0.GeneratedDatabase,
          i1.$WatchlistTable,
          i1.WatchlistEntry
        > {
  $$WatchlistTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static i5.$StockMasterTable _symbolTable(i0.GeneratedDatabase db) =>
      i4.ReadDatabaseContainer(db)
          .resultSet<i5.$StockMasterTable>('stock_master')
          .createAlias(
            i0.$_aliasNameGenerator(
              i4.ReadDatabaseContainer(
                db,
              ).resultSet<i1.$WatchlistTable>('watchlist').symbol,
              i4.ReadDatabaseContainer(
                db,
              ).resultSet<i5.$StockMasterTable>('stock_master').symbol,
            ),
          );

  i5.$$StockMasterTableProcessedTableManager get symbol {
    final $_column = $_itemColumn<String>('symbol')!;

    final manager = i5
        .$$StockMasterTableTableManager(
          $_db,
          i4.ReadDatabaseContainer(
            $_db,
          ).resultSet<i5.$StockMasterTable>('stock_master'),
        )
        .filter((f) => f.symbol.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_symbolTable($_db));
    if (item == null) return manager;
    return i0.ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static i1.$WatchlistGroupsTable _groupIdTable(i0.GeneratedDatabase db) =>
      i4.ReadDatabaseContainer(db)
          .resultSet<i1.$WatchlistGroupsTable>('watchlist_groups')
          .createAlias(
            i0.$_aliasNameGenerator(
              i4.ReadDatabaseContainer(
                db,
              ).resultSet<i1.$WatchlistTable>('watchlist').groupId,
              i4.ReadDatabaseContainer(
                db,
              ).resultSet<i1.$WatchlistGroupsTable>('watchlist_groups').id,
            ),
          );

  i1.$$WatchlistGroupsTableProcessedTableManager? get groupId {
    final $_column = $_itemColumn<int>('group_id');
    if ($_column == null) return null;
    final manager = i1
        .$$WatchlistGroupsTableTableManager(
          $_db,
          i4.ReadDatabaseContainer(
            $_db,
          ).resultSet<i1.$WatchlistGroupsTable>('watchlist_groups'),
        )
        .filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_groupIdTable($_db));
    if (item == null) return manager;
    return i0.ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$WatchlistTableFilterComposer
    extends i0.Composer<i0.GeneratedDatabase, i1.$WatchlistTable> {
  $$WatchlistTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  i0.ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => i0.ColumnFilters(column),
  );

  i5.$$StockMasterTableFilterComposer get symbol {
    final i5.$$StockMasterTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.symbol,
      referencedTable: i4.ReadDatabaseContainer(
        $db,
      ).resultSet<i5.$StockMasterTable>('stock_master'),
      getReferencedColumn: (t) => t.symbol,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => i5.$$StockMasterTableFilterComposer(
            $db: $db,
            $table: i4.ReadDatabaseContainer(
              $db,
            ).resultSet<i5.$StockMasterTable>('stock_master'),
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  i1.$$WatchlistGroupsTableFilterComposer get groupId {
    final i1.$$WatchlistGroupsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.groupId,
      referencedTable: i4.ReadDatabaseContainer(
        $db,
      ).resultSet<i1.$WatchlistGroupsTable>('watchlist_groups'),
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => i1.$$WatchlistGroupsTableFilterComposer(
            $db: $db,
            $table: i4.ReadDatabaseContainer(
              $db,
            ).resultSet<i1.$WatchlistGroupsTable>('watchlist_groups'),
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$WatchlistTableOrderingComposer
    extends i0.Composer<i0.GeneratedDatabase, i1.$WatchlistTable> {
  $$WatchlistTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  i0.ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i5.$$StockMasterTableOrderingComposer get symbol {
    final i5.$$StockMasterTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.symbol,
      referencedTable: i4.ReadDatabaseContainer(
        $db,
      ).resultSet<i5.$StockMasterTable>('stock_master'),
      getReferencedColumn: (t) => t.symbol,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => i5.$$StockMasterTableOrderingComposer(
            $db: $db,
            $table: i4.ReadDatabaseContainer(
              $db,
            ).resultSet<i5.$StockMasterTable>('stock_master'),
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  i1.$$WatchlistGroupsTableOrderingComposer get groupId {
    final i1.$$WatchlistGroupsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.groupId,
      referencedTable: i4.ReadDatabaseContainer(
        $db,
      ).resultSet<i1.$WatchlistGroupsTable>('watchlist_groups'),
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => i1.$$WatchlistGroupsTableOrderingComposer(
            $db: $db,
            $table: i4.ReadDatabaseContainer(
              $db,
            ).resultSet<i1.$WatchlistGroupsTable>('watchlist_groups'),
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$WatchlistTableAnnotationComposer
    extends i0.Composer<i0.GeneratedDatabase, i1.$WatchlistTable> {
  $$WatchlistTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  i0.GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  i5.$$StockMasterTableAnnotationComposer get symbol {
    final i5.$$StockMasterTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.symbol,
      referencedTable: i4.ReadDatabaseContainer(
        $db,
      ).resultSet<i5.$StockMasterTable>('stock_master'),
      getReferencedColumn: (t) => t.symbol,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => i5.$$StockMasterTableAnnotationComposer(
            $db: $db,
            $table: i4.ReadDatabaseContainer(
              $db,
            ).resultSet<i5.$StockMasterTable>('stock_master'),
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  i1.$$WatchlistGroupsTableAnnotationComposer get groupId {
    final i1.$$WatchlistGroupsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.groupId,
          referencedTable: i4.ReadDatabaseContainer(
            $db,
          ).resultSet<i1.$WatchlistGroupsTable>('watchlist_groups'),
          getReferencedColumn: (t) => t.id,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => i1.$$WatchlistGroupsTableAnnotationComposer(
                $db: $db,
                $table: i4.ReadDatabaseContainer(
                  $db,
                ).resultSet<i1.$WatchlistGroupsTable>('watchlist_groups'),
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }
}

class $$WatchlistTableTableManager
    extends
        i0.RootTableManager<
          i0.GeneratedDatabase,
          i1.$WatchlistTable,
          i1.WatchlistEntry,
          i1.$$WatchlistTableFilterComposer,
          i1.$$WatchlistTableOrderingComposer,
          i1.$$WatchlistTableAnnotationComposer,
          $$WatchlistTableCreateCompanionBuilder,
          $$WatchlistTableUpdateCompanionBuilder,
          (i1.WatchlistEntry, i1.$$WatchlistTableReferences),
          i1.WatchlistEntry,
          i0.PrefetchHooks Function({bool symbol, bool groupId})
        > {
  $$WatchlistTableTableManager(
    i0.GeneratedDatabase db,
    i1.$WatchlistTable table,
  ) : super(
        i0.TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              i1.$$WatchlistTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              i1.$$WatchlistTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              i1.$$WatchlistTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                i0.Value<String> symbol = const i0.Value.absent(),
                i0.Value<DateTime> createdAt = const i0.Value.absent(),
                i0.Value<int?> groupId = const i0.Value.absent(),
                i0.Value<int> rowid = const i0.Value.absent(),
              }) => i1.WatchlistCompanion(
                symbol: symbol,
                createdAt: createdAt,
                groupId: groupId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String symbol,
                i0.Value<DateTime> createdAt = const i0.Value.absent(),
                i0.Value<int?> groupId = const i0.Value.absent(),
                i0.Value<int> rowid = const i0.Value.absent(),
              }) => i1.WatchlistCompanion.insert(
                symbol: symbol,
                createdAt: createdAt,
                groupId: groupId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  i1.$$WatchlistTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({symbol = false, groupId = false}) {
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
                                referencedTable: i1.$$WatchlistTableReferences
                                    ._symbolTable(db),
                                referencedColumn: i1.$$WatchlistTableReferences
                                    ._symbolTable(db)
                                    .symbol,
                              )
                              as T;
                    }
                    if (groupId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.groupId,
                                referencedTable: i1.$$WatchlistTableReferences
                                    ._groupIdTable(db),
                                referencedColumn: i1.$$WatchlistTableReferences
                                    ._groupIdTable(db)
                                    .id,
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

typedef $$WatchlistTableProcessedTableManager =
    i0.ProcessedTableManager<
      i0.GeneratedDatabase,
      i1.$WatchlistTable,
      i1.WatchlistEntry,
      i1.$$WatchlistTableFilterComposer,
      i1.$$WatchlistTableOrderingComposer,
      i1.$$WatchlistTableAnnotationComposer,
      $$WatchlistTableCreateCompanionBuilder,
      $$WatchlistTableUpdateCompanionBuilder,
      (i1.WatchlistEntry, i1.$$WatchlistTableReferences),
      i1.WatchlistEntry,
      i0.PrefetchHooks Function({bool symbol, bool groupId})
    >;
typedef $$UpdateRunTableCreateCompanionBuilder =
    i1.UpdateRunCompanion Function({
      i0.Value<int> id,
      required DateTime runDate,
      i0.Value<DateTime> startedAt,
      i0.Value<DateTime?> finishedAt,
      required String status,
      i0.Value<String?> message,
    });
typedef $$UpdateRunTableUpdateCompanionBuilder =
    i1.UpdateRunCompanion Function({
      i0.Value<int> id,
      i0.Value<DateTime> runDate,
      i0.Value<DateTime> startedAt,
      i0.Value<DateTime?> finishedAt,
      i0.Value<String> status,
      i0.Value<String?> message,
    });

class $$UpdateRunTableFilterComposer
    extends i0.Composer<i0.GeneratedDatabase, i1.$UpdateRunTable> {
  $$UpdateRunTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  i0.ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<DateTime> get runDate => $composableBuilder(
    column: $table.runDate,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<DateTime> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<DateTime> get finishedAt => $composableBuilder(
    column: $table.finishedAt,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<String> get message => $composableBuilder(
    column: $table.message,
    builder: (column) => i0.ColumnFilters(column),
  );
}

class $$UpdateRunTableOrderingComposer
    extends i0.Composer<i0.GeneratedDatabase, i1.$UpdateRunTable> {
  $$UpdateRunTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  i0.ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<DateTime> get runDate => $composableBuilder(
    column: $table.runDate,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<DateTime> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<DateTime> get finishedAt => $composableBuilder(
    column: $table.finishedAt,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<String> get message => $composableBuilder(
    column: $table.message,
    builder: (column) => i0.ColumnOrderings(column),
  );
}

class $$UpdateRunTableAnnotationComposer
    extends i0.Composer<i0.GeneratedDatabase, i1.$UpdateRunTable> {
  $$UpdateRunTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  i0.GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  i0.GeneratedColumn<DateTime> get runDate =>
      $composableBuilder(column: $table.runDate, builder: (column) => column);

  i0.GeneratedColumn<DateTime> get startedAt =>
      $composableBuilder(column: $table.startedAt, builder: (column) => column);

  i0.GeneratedColumn<DateTime> get finishedAt => $composableBuilder(
    column: $table.finishedAt,
    builder: (column) => column,
  );

  i0.GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  i0.GeneratedColumn<String> get message =>
      $composableBuilder(column: $table.message, builder: (column) => column);
}

class $$UpdateRunTableTableManager
    extends
        i0.RootTableManager<
          i0.GeneratedDatabase,
          i1.$UpdateRunTable,
          i1.UpdateRunEntry,
          i1.$$UpdateRunTableFilterComposer,
          i1.$$UpdateRunTableOrderingComposer,
          i1.$$UpdateRunTableAnnotationComposer,
          $$UpdateRunTableCreateCompanionBuilder,
          $$UpdateRunTableUpdateCompanionBuilder,
          (
            i1.UpdateRunEntry,
            i0.BaseReferences<
              i0.GeneratedDatabase,
              i1.$UpdateRunTable,
              i1.UpdateRunEntry
            >,
          ),
          i1.UpdateRunEntry,
          i0.PrefetchHooks Function()
        > {
  $$UpdateRunTableTableManager(
    i0.GeneratedDatabase db,
    i1.$UpdateRunTable table,
  ) : super(
        i0.TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              i1.$$UpdateRunTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              i1.$$UpdateRunTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              i1.$$UpdateRunTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                i0.Value<int> id = const i0.Value.absent(),
                i0.Value<DateTime> runDate = const i0.Value.absent(),
                i0.Value<DateTime> startedAt = const i0.Value.absent(),
                i0.Value<DateTime?> finishedAt = const i0.Value.absent(),
                i0.Value<String> status = const i0.Value.absent(),
                i0.Value<String?> message = const i0.Value.absent(),
              }) => i1.UpdateRunCompanion(
                id: id,
                runDate: runDate,
                startedAt: startedAt,
                finishedAt: finishedAt,
                status: status,
                message: message,
              ),
          createCompanionCallback:
              ({
                i0.Value<int> id = const i0.Value.absent(),
                required DateTime runDate,
                i0.Value<DateTime> startedAt = const i0.Value.absent(),
                i0.Value<DateTime?> finishedAt = const i0.Value.absent(),
                required String status,
                i0.Value<String?> message = const i0.Value.absent(),
              }) => i1.UpdateRunCompanion.insert(
                id: id,
                runDate: runDate,
                startedAt: startedAt,
                finishedAt: finishedAt,
                status: status,
                message: message,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), i0.BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$UpdateRunTableProcessedTableManager =
    i0.ProcessedTableManager<
      i0.GeneratedDatabase,
      i1.$UpdateRunTable,
      i1.UpdateRunEntry,
      i1.$$UpdateRunTableFilterComposer,
      i1.$$UpdateRunTableOrderingComposer,
      i1.$$UpdateRunTableAnnotationComposer,
      $$UpdateRunTableCreateCompanionBuilder,
      $$UpdateRunTableUpdateCompanionBuilder,
      (
        i1.UpdateRunEntry,
        i0.BaseReferences<
          i0.GeneratedDatabase,
          i1.$UpdateRunTable,
          i1.UpdateRunEntry
        >,
      ),
      i1.UpdateRunEntry,
      i0.PrefetchHooks Function()
    >;
typedef $$AppSettingsTableCreateCompanionBuilder =
    i1.AppSettingsCompanion Function({
      required String key,
      required String value,
      i0.Value<DateTime> updatedAt,
      i0.Value<int> rowid,
    });
typedef $$AppSettingsTableUpdateCompanionBuilder =
    i1.AppSettingsCompanion Function({
      i0.Value<String> key,
      i0.Value<String> value,
      i0.Value<DateTime> updatedAt,
      i0.Value<int> rowid,
    });

class $$AppSettingsTableFilterComposer
    extends i0.Composer<i0.GeneratedDatabase, i1.$AppSettingsTable> {
  $$AppSettingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  i0.ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => i0.ColumnFilters(column),
  );
}

class $$AppSettingsTableOrderingComposer
    extends i0.Composer<i0.GeneratedDatabase, i1.$AppSettingsTable> {
  $$AppSettingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  i0.ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => i0.ColumnOrderings(column),
  );
}

class $$AppSettingsTableAnnotationComposer
    extends i0.Composer<i0.GeneratedDatabase, i1.$AppSettingsTable> {
  $$AppSettingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  i0.GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  i0.GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);

  i0.GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$AppSettingsTableTableManager
    extends
        i0.RootTableManager<
          i0.GeneratedDatabase,
          i1.$AppSettingsTable,
          i1.AppSettingEntry,
          i1.$$AppSettingsTableFilterComposer,
          i1.$$AppSettingsTableOrderingComposer,
          i1.$$AppSettingsTableAnnotationComposer,
          $$AppSettingsTableCreateCompanionBuilder,
          $$AppSettingsTableUpdateCompanionBuilder,
          (
            i1.AppSettingEntry,
            i0.BaseReferences<
              i0.GeneratedDatabase,
              i1.$AppSettingsTable,
              i1.AppSettingEntry
            >,
          ),
          i1.AppSettingEntry,
          i0.PrefetchHooks Function()
        > {
  $$AppSettingsTableTableManager(
    i0.GeneratedDatabase db,
    i1.$AppSettingsTable table,
  ) : super(
        i0.TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              i1.$$AppSettingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              i1.$$AppSettingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              i1.$$AppSettingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                i0.Value<String> key = const i0.Value.absent(),
                i0.Value<String> value = const i0.Value.absent(),
                i0.Value<DateTime> updatedAt = const i0.Value.absent(),
                i0.Value<int> rowid = const i0.Value.absent(),
              }) => i1.AppSettingsCompanion(
                key: key,
                value: value,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String key,
                required String value,
                i0.Value<DateTime> updatedAt = const i0.Value.absent(),
                i0.Value<int> rowid = const i0.Value.absent(),
              }) => i1.AppSettingsCompanion.insert(
                key: key,
                value: value,
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

typedef $$AppSettingsTableProcessedTableManager =
    i0.ProcessedTableManager<
      i0.GeneratedDatabase,
      i1.$AppSettingsTable,
      i1.AppSettingEntry,
      i1.$$AppSettingsTableFilterComposer,
      i1.$$AppSettingsTableOrderingComposer,
      i1.$$AppSettingsTableAnnotationComposer,
      $$AppSettingsTableCreateCompanionBuilder,
      $$AppSettingsTableUpdateCompanionBuilder,
      (
        i1.AppSettingEntry,
        i0.BaseReferences<
          i0.GeneratedDatabase,
          i1.$AppSettingsTable,
          i1.AppSettingEntry
        >,
      ),
      i1.AppSettingEntry,
      i0.PrefetchHooks Function()
    >;
typedef $$PriceAlertTableCreateCompanionBuilder =
    i1.PriceAlertCompanion Function({
      i0.Value<int> id,
      required String symbol,
      required String alertType,
      required double targetValue,
      i0.Value<bool> isActive,
      i0.Value<DateTime?> triggeredAt,
      i0.Value<String?> note,
      i0.Value<String?> managedBy,
      i0.Value<DateTime> createdAt,
    });
typedef $$PriceAlertTableUpdateCompanionBuilder =
    i1.PriceAlertCompanion Function({
      i0.Value<int> id,
      i0.Value<String> symbol,
      i0.Value<String> alertType,
      i0.Value<double> targetValue,
      i0.Value<bool> isActive,
      i0.Value<DateTime?> triggeredAt,
      i0.Value<String?> note,
      i0.Value<String?> managedBy,
      i0.Value<DateTime> createdAt,
    });

final class $$PriceAlertTableReferences
    extends
        i0.BaseReferences<
          i0.GeneratedDatabase,
          i1.$PriceAlertTable,
          i1.PriceAlertEntry
        > {
  $$PriceAlertTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static i5.$StockMasterTable _symbolTable(i0.GeneratedDatabase db) =>
      i4.ReadDatabaseContainer(db)
          .resultSet<i5.$StockMasterTable>('stock_master')
          .createAlias(
            i0.$_aliasNameGenerator(
              i4.ReadDatabaseContainer(
                db,
              ).resultSet<i1.$PriceAlertTable>('price_alert').symbol,
              i4.ReadDatabaseContainer(
                db,
              ).resultSet<i5.$StockMasterTable>('stock_master').symbol,
            ),
          );

  i5.$$StockMasterTableProcessedTableManager get symbol {
    final $_column = $_itemColumn<String>('symbol')!;

    final manager = i5
        .$$StockMasterTableTableManager(
          $_db,
          i4.ReadDatabaseContainer(
            $_db,
          ).resultSet<i5.$StockMasterTable>('stock_master'),
        )
        .filter((f) => f.symbol.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_symbolTable($_db));
    if (item == null) return manager;
    return i0.ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$PriceAlertTableFilterComposer
    extends i0.Composer<i0.GeneratedDatabase, i1.$PriceAlertTable> {
  $$PriceAlertTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  i0.ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<String> get alertType => $composableBuilder(
    column: $table.alertType,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<double> get targetValue => $composableBuilder(
    column: $table.targetValue,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<bool> get isActive => $composableBuilder(
    column: $table.isActive,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<DateTime> get triggeredAt => $composableBuilder(
    column: $table.triggeredAt,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<String> get managedBy => $composableBuilder(
    column: $table.managedBy,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => i0.ColumnFilters(column),
  );

  i5.$$StockMasterTableFilterComposer get symbol {
    final i5.$$StockMasterTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.symbol,
      referencedTable: i4.ReadDatabaseContainer(
        $db,
      ).resultSet<i5.$StockMasterTable>('stock_master'),
      getReferencedColumn: (t) => t.symbol,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => i5.$$StockMasterTableFilterComposer(
            $db: $db,
            $table: i4.ReadDatabaseContainer(
              $db,
            ).resultSet<i5.$StockMasterTable>('stock_master'),
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$PriceAlertTableOrderingComposer
    extends i0.Composer<i0.GeneratedDatabase, i1.$PriceAlertTable> {
  $$PriceAlertTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  i0.ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<String> get alertType => $composableBuilder(
    column: $table.alertType,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<double> get targetValue => $composableBuilder(
    column: $table.targetValue,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<bool> get isActive => $composableBuilder(
    column: $table.isActive,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<DateTime> get triggeredAt => $composableBuilder(
    column: $table.triggeredAt,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<String> get managedBy => $composableBuilder(
    column: $table.managedBy,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i5.$$StockMasterTableOrderingComposer get symbol {
    final i5.$$StockMasterTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.symbol,
      referencedTable: i4.ReadDatabaseContainer(
        $db,
      ).resultSet<i5.$StockMasterTable>('stock_master'),
      getReferencedColumn: (t) => t.symbol,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => i5.$$StockMasterTableOrderingComposer(
            $db: $db,
            $table: i4.ReadDatabaseContainer(
              $db,
            ).resultSet<i5.$StockMasterTable>('stock_master'),
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$PriceAlertTableAnnotationComposer
    extends i0.Composer<i0.GeneratedDatabase, i1.$PriceAlertTable> {
  $$PriceAlertTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  i0.GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  i0.GeneratedColumn<String> get alertType =>
      $composableBuilder(column: $table.alertType, builder: (column) => column);

  i0.GeneratedColumn<double> get targetValue => $composableBuilder(
    column: $table.targetValue,
    builder: (column) => column,
  );

  i0.GeneratedColumn<bool> get isActive =>
      $composableBuilder(column: $table.isActive, builder: (column) => column);

  i0.GeneratedColumn<DateTime> get triggeredAt => $composableBuilder(
    column: $table.triggeredAt,
    builder: (column) => column,
  );

  i0.GeneratedColumn<String> get note =>
      $composableBuilder(column: $table.note, builder: (column) => column);

  i0.GeneratedColumn<String> get managedBy =>
      $composableBuilder(column: $table.managedBy, builder: (column) => column);

  i0.GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  i5.$$StockMasterTableAnnotationComposer get symbol {
    final i5.$$StockMasterTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.symbol,
      referencedTable: i4.ReadDatabaseContainer(
        $db,
      ).resultSet<i5.$StockMasterTable>('stock_master'),
      getReferencedColumn: (t) => t.symbol,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => i5.$$StockMasterTableAnnotationComposer(
            $db: $db,
            $table: i4.ReadDatabaseContainer(
              $db,
            ).resultSet<i5.$StockMasterTable>('stock_master'),
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$PriceAlertTableTableManager
    extends
        i0.RootTableManager<
          i0.GeneratedDatabase,
          i1.$PriceAlertTable,
          i1.PriceAlertEntry,
          i1.$$PriceAlertTableFilterComposer,
          i1.$$PriceAlertTableOrderingComposer,
          i1.$$PriceAlertTableAnnotationComposer,
          $$PriceAlertTableCreateCompanionBuilder,
          $$PriceAlertTableUpdateCompanionBuilder,
          (i1.PriceAlertEntry, i1.$$PriceAlertTableReferences),
          i1.PriceAlertEntry,
          i0.PrefetchHooks Function({bool symbol})
        > {
  $$PriceAlertTableTableManager(
    i0.GeneratedDatabase db,
    i1.$PriceAlertTable table,
  ) : super(
        i0.TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              i1.$$PriceAlertTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              i1.$$PriceAlertTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              i1.$$PriceAlertTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                i0.Value<int> id = const i0.Value.absent(),
                i0.Value<String> symbol = const i0.Value.absent(),
                i0.Value<String> alertType = const i0.Value.absent(),
                i0.Value<double> targetValue = const i0.Value.absent(),
                i0.Value<bool> isActive = const i0.Value.absent(),
                i0.Value<DateTime?> triggeredAt = const i0.Value.absent(),
                i0.Value<String?> note = const i0.Value.absent(),
                i0.Value<String?> managedBy = const i0.Value.absent(),
                i0.Value<DateTime> createdAt = const i0.Value.absent(),
              }) => i1.PriceAlertCompanion(
                id: id,
                symbol: symbol,
                alertType: alertType,
                targetValue: targetValue,
                isActive: isActive,
                triggeredAt: triggeredAt,
                note: note,
                managedBy: managedBy,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                i0.Value<int> id = const i0.Value.absent(),
                required String symbol,
                required String alertType,
                required double targetValue,
                i0.Value<bool> isActive = const i0.Value.absent(),
                i0.Value<DateTime?> triggeredAt = const i0.Value.absent(),
                i0.Value<String?> note = const i0.Value.absent(),
                i0.Value<String?> managedBy = const i0.Value.absent(),
                i0.Value<DateTime> createdAt = const i0.Value.absent(),
              }) => i1.PriceAlertCompanion.insert(
                id: id,
                symbol: symbol,
                alertType: alertType,
                targetValue: targetValue,
                isActive: isActive,
                triggeredAt: triggeredAt,
                note: note,
                managedBy: managedBy,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  i1.$$PriceAlertTableReferences(db, table, e),
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
                                referencedTable: i1.$$PriceAlertTableReferences
                                    ._symbolTable(db),
                                referencedColumn: i1.$$PriceAlertTableReferences
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

typedef $$PriceAlertTableProcessedTableManager =
    i0.ProcessedTableManager<
      i0.GeneratedDatabase,
      i1.$PriceAlertTable,
      i1.PriceAlertEntry,
      i1.$$PriceAlertTableFilterComposer,
      i1.$$PriceAlertTableOrderingComposer,
      i1.$$PriceAlertTableAnnotationComposer,
      $$PriceAlertTableCreateCompanionBuilder,
      $$PriceAlertTableUpdateCompanionBuilder,
      (i1.PriceAlertEntry, i1.$$PriceAlertTableReferences),
      i1.PriceAlertEntry,
      i0.PrefetchHooks Function({bool symbol})
    >;
typedef $$PinnedThesisTableCreateCompanionBuilder =
    i1.PinnedThesisCompanion Function({
      i0.Value<int> id,
      required String symbol,
      required DateTime pinnedDate,
      required double referencePrice,
      required String mode,
      required String triggeredRules,
      required double scoreShort,
      required double scoreLong,
      i0.Value<String> status,
      i0.Value<DateTime?> invalidatedDate,
      i0.Value<String?> invalidatedReason,
      i0.Value<DateTime?> lastCheckedDate,
      i0.Value<DateTime> createdAt,
      i0.Value<DateTime> updatedAt,
    });
typedef $$PinnedThesisTableUpdateCompanionBuilder =
    i1.PinnedThesisCompanion Function({
      i0.Value<int> id,
      i0.Value<String> symbol,
      i0.Value<DateTime> pinnedDate,
      i0.Value<double> referencePrice,
      i0.Value<String> mode,
      i0.Value<String> triggeredRules,
      i0.Value<double> scoreShort,
      i0.Value<double> scoreLong,
      i0.Value<String> status,
      i0.Value<DateTime?> invalidatedDate,
      i0.Value<String?> invalidatedReason,
      i0.Value<DateTime?> lastCheckedDate,
      i0.Value<DateTime> createdAt,
      i0.Value<DateTime> updatedAt,
    });

final class $$PinnedThesisTableReferences
    extends
        i0.BaseReferences<
          i0.GeneratedDatabase,
          i1.$PinnedThesisTable,
          i1.PinnedThesisEntry
        > {
  $$PinnedThesisTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static i5.$StockMasterTable _symbolTable(i0.GeneratedDatabase db) =>
      i4.ReadDatabaseContainer(db)
          .resultSet<i5.$StockMasterTable>('stock_master')
          .createAlias(
            i0.$_aliasNameGenerator(
              i4.ReadDatabaseContainer(
                db,
              ).resultSet<i1.$PinnedThesisTable>('pinned_thesis').symbol,
              i4.ReadDatabaseContainer(
                db,
              ).resultSet<i5.$StockMasterTable>('stock_master').symbol,
            ),
          );

  i5.$$StockMasterTableProcessedTableManager get symbol {
    final $_column = $_itemColumn<String>('symbol')!;

    final manager = i5
        .$$StockMasterTableTableManager(
          $_db,
          i4.ReadDatabaseContainer(
            $_db,
          ).resultSet<i5.$StockMasterTable>('stock_master'),
        )
        .filter((f) => f.symbol.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_symbolTable($_db));
    if (item == null) return manager;
    return i0.ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$PinnedThesisTableFilterComposer
    extends i0.Composer<i0.GeneratedDatabase, i1.$PinnedThesisTable> {
  $$PinnedThesisTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  i0.ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<DateTime> get pinnedDate => $composableBuilder(
    column: $table.pinnedDate,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<double> get referencePrice => $composableBuilder(
    column: $table.referencePrice,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<String> get mode => $composableBuilder(
    column: $table.mode,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<String> get triggeredRules => $composableBuilder(
    column: $table.triggeredRules,
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

  i0.ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<DateTime> get invalidatedDate => $composableBuilder(
    column: $table.invalidatedDate,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<String> get invalidatedReason => $composableBuilder(
    column: $table.invalidatedReason,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<DateTime> get lastCheckedDate => $composableBuilder(
    column: $table.lastCheckedDate,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => i0.ColumnFilters(column),
  );

  i5.$$StockMasterTableFilterComposer get symbol {
    final i5.$$StockMasterTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.symbol,
      referencedTable: i4.ReadDatabaseContainer(
        $db,
      ).resultSet<i5.$StockMasterTable>('stock_master'),
      getReferencedColumn: (t) => t.symbol,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => i5.$$StockMasterTableFilterComposer(
            $db: $db,
            $table: i4.ReadDatabaseContainer(
              $db,
            ).resultSet<i5.$StockMasterTable>('stock_master'),
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$PinnedThesisTableOrderingComposer
    extends i0.Composer<i0.GeneratedDatabase, i1.$PinnedThesisTable> {
  $$PinnedThesisTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  i0.ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<DateTime> get pinnedDate => $composableBuilder(
    column: $table.pinnedDate,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<double> get referencePrice => $composableBuilder(
    column: $table.referencePrice,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<String> get mode => $composableBuilder(
    column: $table.mode,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<String> get triggeredRules => $composableBuilder(
    column: $table.triggeredRules,
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

  i0.ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<DateTime> get invalidatedDate => $composableBuilder(
    column: $table.invalidatedDate,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<String> get invalidatedReason => $composableBuilder(
    column: $table.invalidatedReason,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<DateTime> get lastCheckedDate => $composableBuilder(
    column: $table.lastCheckedDate,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i5.$$StockMasterTableOrderingComposer get symbol {
    final i5.$$StockMasterTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.symbol,
      referencedTable: i4.ReadDatabaseContainer(
        $db,
      ).resultSet<i5.$StockMasterTable>('stock_master'),
      getReferencedColumn: (t) => t.symbol,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => i5.$$StockMasterTableOrderingComposer(
            $db: $db,
            $table: i4.ReadDatabaseContainer(
              $db,
            ).resultSet<i5.$StockMasterTable>('stock_master'),
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$PinnedThesisTableAnnotationComposer
    extends i0.Composer<i0.GeneratedDatabase, i1.$PinnedThesisTable> {
  $$PinnedThesisTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  i0.GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  i0.GeneratedColumn<DateTime> get pinnedDate => $composableBuilder(
    column: $table.pinnedDate,
    builder: (column) => column,
  );

  i0.GeneratedColumn<double> get referencePrice => $composableBuilder(
    column: $table.referencePrice,
    builder: (column) => column,
  );

  i0.GeneratedColumn<String> get mode =>
      $composableBuilder(column: $table.mode, builder: (column) => column);

  i0.GeneratedColumn<String> get triggeredRules => $composableBuilder(
    column: $table.triggeredRules,
    builder: (column) => column,
  );

  i0.GeneratedColumn<double> get scoreShort => $composableBuilder(
    column: $table.scoreShort,
    builder: (column) => column,
  );

  i0.GeneratedColumn<double> get scoreLong =>
      $composableBuilder(column: $table.scoreLong, builder: (column) => column);

  i0.GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  i0.GeneratedColumn<DateTime> get invalidatedDate => $composableBuilder(
    column: $table.invalidatedDate,
    builder: (column) => column,
  );

  i0.GeneratedColumn<String> get invalidatedReason => $composableBuilder(
    column: $table.invalidatedReason,
    builder: (column) => column,
  );

  i0.GeneratedColumn<DateTime> get lastCheckedDate => $composableBuilder(
    column: $table.lastCheckedDate,
    builder: (column) => column,
  );

  i0.GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  i0.GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  i5.$$StockMasterTableAnnotationComposer get symbol {
    final i5.$$StockMasterTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.symbol,
      referencedTable: i4.ReadDatabaseContainer(
        $db,
      ).resultSet<i5.$StockMasterTable>('stock_master'),
      getReferencedColumn: (t) => t.symbol,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => i5.$$StockMasterTableAnnotationComposer(
            $db: $db,
            $table: i4.ReadDatabaseContainer(
              $db,
            ).resultSet<i5.$StockMasterTable>('stock_master'),
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$PinnedThesisTableTableManager
    extends
        i0.RootTableManager<
          i0.GeneratedDatabase,
          i1.$PinnedThesisTable,
          i1.PinnedThesisEntry,
          i1.$$PinnedThesisTableFilterComposer,
          i1.$$PinnedThesisTableOrderingComposer,
          i1.$$PinnedThesisTableAnnotationComposer,
          $$PinnedThesisTableCreateCompanionBuilder,
          $$PinnedThesisTableUpdateCompanionBuilder,
          (i1.PinnedThesisEntry, i1.$$PinnedThesisTableReferences),
          i1.PinnedThesisEntry,
          i0.PrefetchHooks Function({bool symbol})
        > {
  $$PinnedThesisTableTableManager(
    i0.GeneratedDatabase db,
    i1.$PinnedThesisTable table,
  ) : super(
        i0.TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              i1.$$PinnedThesisTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              i1.$$PinnedThesisTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              i1.$$PinnedThesisTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                i0.Value<int> id = const i0.Value.absent(),
                i0.Value<String> symbol = const i0.Value.absent(),
                i0.Value<DateTime> pinnedDate = const i0.Value.absent(),
                i0.Value<double> referencePrice = const i0.Value.absent(),
                i0.Value<String> mode = const i0.Value.absent(),
                i0.Value<String> triggeredRules = const i0.Value.absent(),
                i0.Value<double> scoreShort = const i0.Value.absent(),
                i0.Value<double> scoreLong = const i0.Value.absent(),
                i0.Value<String> status = const i0.Value.absent(),
                i0.Value<DateTime?> invalidatedDate = const i0.Value.absent(),
                i0.Value<String?> invalidatedReason = const i0.Value.absent(),
                i0.Value<DateTime?> lastCheckedDate = const i0.Value.absent(),
                i0.Value<DateTime> createdAt = const i0.Value.absent(),
                i0.Value<DateTime> updatedAt = const i0.Value.absent(),
              }) => i1.PinnedThesisCompanion(
                id: id,
                symbol: symbol,
                pinnedDate: pinnedDate,
                referencePrice: referencePrice,
                mode: mode,
                triggeredRules: triggeredRules,
                scoreShort: scoreShort,
                scoreLong: scoreLong,
                status: status,
                invalidatedDate: invalidatedDate,
                invalidatedReason: invalidatedReason,
                lastCheckedDate: lastCheckedDate,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          createCompanionCallback:
              ({
                i0.Value<int> id = const i0.Value.absent(),
                required String symbol,
                required DateTime pinnedDate,
                required double referencePrice,
                required String mode,
                required String triggeredRules,
                required double scoreShort,
                required double scoreLong,
                i0.Value<String> status = const i0.Value.absent(),
                i0.Value<DateTime?> invalidatedDate = const i0.Value.absent(),
                i0.Value<String?> invalidatedReason = const i0.Value.absent(),
                i0.Value<DateTime?> lastCheckedDate = const i0.Value.absent(),
                i0.Value<DateTime> createdAt = const i0.Value.absent(),
                i0.Value<DateTime> updatedAt = const i0.Value.absent(),
              }) => i1.PinnedThesisCompanion.insert(
                id: id,
                symbol: symbol,
                pinnedDate: pinnedDate,
                referencePrice: referencePrice,
                mode: mode,
                triggeredRules: triggeredRules,
                scoreShort: scoreShort,
                scoreLong: scoreLong,
                status: status,
                invalidatedDate: invalidatedDate,
                invalidatedReason: invalidatedReason,
                lastCheckedDate: lastCheckedDate,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  i1.$$PinnedThesisTableReferences(db, table, e),
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
                                    .$$PinnedThesisTableReferences
                                    ._symbolTable(db),
                                referencedColumn: i1
                                    .$$PinnedThesisTableReferences
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

typedef $$PinnedThesisTableProcessedTableManager =
    i0.ProcessedTableManager<
      i0.GeneratedDatabase,
      i1.$PinnedThesisTable,
      i1.PinnedThesisEntry,
      i1.$$PinnedThesisTableFilterComposer,
      i1.$$PinnedThesisTableOrderingComposer,
      i1.$$PinnedThesisTableAnnotationComposer,
      $$PinnedThesisTableCreateCompanionBuilder,
      $$PinnedThesisTableUpdateCompanionBuilder,
      (i1.PinnedThesisEntry, i1.$$PinnedThesisTableReferences),
      i1.PinnedThesisEntry,
      i0.PrefetchHooks Function({bool symbol})
    >;

class $WatchlistGroupsTable extends i2.WatchlistGroups
    with i0.TableInfo<$WatchlistGroupsTable, i1.WatchlistGroupEntry> {
  @override
  final i0.GeneratedDatabase attachedDatabase;
  final String? _alias;
  $WatchlistGroupsTable(this.attachedDatabase, [this._alias]);
  static const i0.VerificationMeta _idMeta = const i0.VerificationMeta('id');
  @override
  late final i0.GeneratedColumn<int> id = i0.GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: i0.DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: i0.GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const i0.VerificationMeta _nameMeta = const i0.VerificationMeta(
    'name',
  );
  @override
  late final i0.GeneratedColumn<String> name = i0.GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    additionalChecks: i0.GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 50,
    ),
    type: i0.DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const i0.VerificationMeta _sortOrderMeta = const i0.VerificationMeta(
    'sortOrder',
  );
  @override
  late final i0.GeneratedColumn<int> sortOrder = i0.GeneratedColumn<int>(
    'sort_order',
    aliasedName,
    false,
    type: i0.DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const i3.Constant(0),
  );
  static const i0.VerificationMeta _isDefaultMeta = const i0.VerificationMeta(
    'isDefault',
  );
  @override
  late final i0.GeneratedColumn<bool> isDefault = i0.GeneratedColumn<bool>(
    'is_default',
    aliasedName,
    false,
    type: i0.DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: i0.GeneratedColumn.constraintIsAlways(
      'CHECK ("is_default" IN (0, 1))',
    ),
    defaultValue: const i3.Constant(false),
  );
  static const i0.VerificationMeta _createdAtMeta = const i0.VerificationMeta(
    'createdAt',
  );
  @override
  late final i0.GeneratedColumn<DateTime> createdAt =
      i0.GeneratedColumn<DateTime>(
        'created_at',
        aliasedName,
        false,
        type: i0.DriftSqlType.dateTime,
        requiredDuringInsert: false,
        defaultValue: i3.currentDateAndTime,
      );
  @override
  List<i0.GeneratedColumn> get $columns => [
    id,
    name,
    sortOrder,
    isDefault,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'watchlist_groups';
  @override
  i0.VerificationContext validateIntegrity(
    i0.Insertable<i1.WatchlistGroupEntry> instance, {
    bool isInserting = false,
  }) {
    final context = i0.VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('sort_order')) {
      context.handle(
        _sortOrderMeta,
        sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta),
      );
    }
    if (data.containsKey('is_default')) {
      context.handle(
        _isDefaultMeta,
        isDefault.isAcceptableOrUnknown(data['is_default']!, _isDefaultMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<i0.GeneratedColumn> get $primaryKey => {id};
  @override
  i1.WatchlistGroupEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return i1.WatchlistGroupEntry(
      id: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      sortOrder: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.int,
        data['${effectivePrefix}sort_order'],
      )!,
      isDefault: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.bool,
        data['${effectivePrefix}is_default'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $WatchlistGroupsTable createAlias(String alias) {
    return $WatchlistGroupsTable(attachedDatabase, alias);
  }
}

class WatchlistGroupEntry extends i0.DataClass
    implements i0.Insertable<i1.WatchlistGroupEntry> {
  /// 自動遞增 ID
  final int id;

  /// 分組名稱（使用者自訂）
  final String name;

  /// 排序順序（數字越小越前面，預設 0）
  final int sortOrder;

  /// 預設分組旗標：新加入的自選自動落入此分組（全表最多一列為 true，
  /// 由 [UserDaoMixin.setDefaultWatchlistGroup] 的交易維持）。
  ///
  /// 掛在分組列上而非 app_settings 存 id：旗標跟著列走，改名不斷、
  /// 刪組自動失效，不需要懸空 id 的存在性檢查。
  /// 既有 DB 由 `_ensureWatchlistGroupsSchema` 的 ALTER 路徑補欄
  /// （whitelist 表不吃 fingerprint reset）。
  final bool isDefault;

  /// 建立時間
  final DateTime createdAt;
  const WatchlistGroupEntry({
    required this.id,
    required this.name,
    required this.sortOrder,
    required this.isDefault,
    required this.createdAt,
  });
  @override
  Map<String, i0.Expression> toColumns(bool nullToAbsent) {
    final map = <String, i0.Expression>{};
    map['id'] = i0.Variable<int>(id);
    map['name'] = i0.Variable<String>(name);
    map['sort_order'] = i0.Variable<int>(sortOrder);
    map['is_default'] = i0.Variable<bool>(isDefault);
    map['created_at'] = i0.Variable<DateTime>(createdAt);
    return map;
  }

  i1.WatchlistGroupsCompanion toCompanion(bool nullToAbsent) {
    return i1.WatchlistGroupsCompanion(
      id: i0.Value(id),
      name: i0.Value(name),
      sortOrder: i0.Value(sortOrder),
      isDefault: i0.Value(isDefault),
      createdAt: i0.Value(createdAt),
    );
  }

  factory WatchlistGroupEntry.fromJson(
    Map<String, dynamic> json, {
    i0.ValueSerializer? serializer,
  }) {
    serializer ??= i0.driftRuntimeOptions.defaultSerializer;
    return WatchlistGroupEntry(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
      isDefault: serializer.fromJson<bool>(json['isDefault']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({i0.ValueSerializer? serializer}) {
    serializer ??= i0.driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'sortOrder': serializer.toJson<int>(sortOrder),
      'isDefault': serializer.toJson<bool>(isDefault),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  i1.WatchlistGroupEntry copyWith({
    int? id,
    String? name,
    int? sortOrder,
    bool? isDefault,
    DateTime? createdAt,
  }) => i1.WatchlistGroupEntry(
    id: id ?? this.id,
    name: name ?? this.name,
    sortOrder: sortOrder ?? this.sortOrder,
    isDefault: isDefault ?? this.isDefault,
    createdAt: createdAt ?? this.createdAt,
  );
  WatchlistGroupEntry copyWithCompanion(i1.WatchlistGroupsCompanion data) {
    return WatchlistGroupEntry(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
      isDefault: data.isDefault.present ? data.isDefault.value : this.isDefault,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('WatchlistGroupEntry(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('isDefault: $isDefault, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, sortOrder, isDefault, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is i1.WatchlistGroupEntry &&
          other.id == this.id &&
          other.name == this.name &&
          other.sortOrder == this.sortOrder &&
          other.isDefault == this.isDefault &&
          other.createdAt == this.createdAt);
}

class WatchlistGroupsCompanion
    extends i0.UpdateCompanion<i1.WatchlistGroupEntry> {
  final i0.Value<int> id;
  final i0.Value<String> name;
  final i0.Value<int> sortOrder;
  final i0.Value<bool> isDefault;
  final i0.Value<DateTime> createdAt;
  const WatchlistGroupsCompanion({
    this.id = const i0.Value.absent(),
    this.name = const i0.Value.absent(),
    this.sortOrder = const i0.Value.absent(),
    this.isDefault = const i0.Value.absent(),
    this.createdAt = const i0.Value.absent(),
  });
  WatchlistGroupsCompanion.insert({
    this.id = const i0.Value.absent(),
    required String name,
    this.sortOrder = const i0.Value.absent(),
    this.isDefault = const i0.Value.absent(),
    this.createdAt = const i0.Value.absent(),
  }) : name = i0.Value(name);
  static i0.Insertable<i1.WatchlistGroupEntry> custom({
    i0.Expression<int>? id,
    i0.Expression<String>? name,
    i0.Expression<int>? sortOrder,
    i0.Expression<bool>? isDefault,
    i0.Expression<DateTime>? createdAt,
  }) {
    return i0.RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (isDefault != null) 'is_default': isDefault,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  i1.WatchlistGroupsCompanion copyWith({
    i0.Value<int>? id,
    i0.Value<String>? name,
    i0.Value<int>? sortOrder,
    i0.Value<bool>? isDefault,
    i0.Value<DateTime>? createdAt,
  }) {
    return i1.WatchlistGroupsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      sortOrder: sortOrder ?? this.sortOrder,
      isDefault: isDefault ?? this.isDefault,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, i0.Expression> toColumns(bool nullToAbsent) {
    final map = <String, i0.Expression>{};
    if (id.present) {
      map['id'] = i0.Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = i0.Variable<String>(name.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = i0.Variable<int>(sortOrder.value);
    }
    if (isDefault.present) {
      map['is_default'] = i0.Variable<bool>(isDefault.value);
    }
    if (createdAt.present) {
      map['created_at'] = i0.Variable<DateTime>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('WatchlistGroupsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('isDefault: $isDefault, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $WatchlistTable extends i2.Watchlist
    with i0.TableInfo<$WatchlistTable, i1.WatchlistEntry> {
  @override
  final i0.GeneratedDatabase attachedDatabase;
  final String? _alias;
  $WatchlistTable(this.attachedDatabase, [this._alias]);
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
  static const i0.VerificationMeta _createdAtMeta = const i0.VerificationMeta(
    'createdAt',
  );
  @override
  late final i0.GeneratedColumn<DateTime> createdAt =
      i0.GeneratedColumn<DateTime>(
        'created_at',
        aliasedName,
        false,
        type: i0.DriftSqlType.dateTime,
        requiredDuringInsert: false,
        defaultValue: i3.currentDateAndTime,
      );
  static const i0.VerificationMeta _groupIdMeta = const i0.VerificationMeta(
    'groupId',
  );
  @override
  late final i0.GeneratedColumn<int> groupId = i0.GeneratedColumn<int>(
    'group_id',
    aliasedName,
    true,
    type: i0.DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: i0.GeneratedColumn.constraintIsAlways(
      'REFERENCES watchlist_groups (id) ON DELETE SET NULL',
    ),
  );
  @override
  List<i0.GeneratedColumn> get $columns => [symbol, createdAt, groupId];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'watchlist';
  @override
  i0.VerificationContext validateIntegrity(
    i0.Insertable<i1.WatchlistEntry> instance, {
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
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('group_id')) {
      context.handle(
        _groupIdMeta,
        groupId.isAcceptableOrUnknown(data['group_id']!, _groupIdMeta),
      );
    }
    return context;
  }

  @override
  Set<i0.GeneratedColumn> get $primaryKey => {symbol};
  @override
  i1.WatchlistEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return i1.WatchlistEntry(
      symbol: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.string,
        data['${effectivePrefix}symbol'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      groupId: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.int,
        data['${effectivePrefix}group_id'],
      ),
    );
  }

  @override
  $WatchlistTable createAlias(String alias) {
    return $WatchlistTable(attachedDatabase, alias);
  }
}

class WatchlistEntry extends i0.DataClass
    implements i0.Insertable<i1.WatchlistEntry> {
  /// 股票代碼
  final String symbol;

  /// 加入自選股的時間
  final DateTime createdAt;

  /// 所屬自訂分組 ID（null 代表未分組）
  ///
  /// 刪除分組時 `KeyAction.setNull` 會把成員的 groupId 清空，不刪股票。
  final int? groupId;
  const WatchlistEntry({
    required this.symbol,
    required this.createdAt,
    this.groupId,
  });
  @override
  Map<String, i0.Expression> toColumns(bool nullToAbsent) {
    final map = <String, i0.Expression>{};
    map['symbol'] = i0.Variable<String>(symbol);
    map['created_at'] = i0.Variable<DateTime>(createdAt);
    if (!nullToAbsent || groupId != null) {
      map['group_id'] = i0.Variable<int>(groupId);
    }
    return map;
  }

  i1.WatchlistCompanion toCompanion(bool nullToAbsent) {
    return i1.WatchlistCompanion(
      symbol: i0.Value(symbol),
      createdAt: i0.Value(createdAt),
      groupId: groupId == null && nullToAbsent
          ? const i0.Value.absent()
          : i0.Value(groupId),
    );
  }

  factory WatchlistEntry.fromJson(
    Map<String, dynamic> json, {
    i0.ValueSerializer? serializer,
  }) {
    serializer ??= i0.driftRuntimeOptions.defaultSerializer;
    return WatchlistEntry(
      symbol: serializer.fromJson<String>(json['symbol']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      groupId: serializer.fromJson<int?>(json['groupId']),
    );
  }
  @override
  Map<String, dynamic> toJson({i0.ValueSerializer? serializer}) {
    serializer ??= i0.driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'symbol': serializer.toJson<String>(symbol),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'groupId': serializer.toJson<int?>(groupId),
    };
  }

  i1.WatchlistEntry copyWith({
    String? symbol,
    DateTime? createdAt,
    i0.Value<int?> groupId = const i0.Value.absent(),
  }) => i1.WatchlistEntry(
    symbol: symbol ?? this.symbol,
    createdAt: createdAt ?? this.createdAt,
    groupId: groupId.present ? groupId.value : this.groupId,
  );
  WatchlistEntry copyWithCompanion(i1.WatchlistCompanion data) {
    return WatchlistEntry(
      symbol: data.symbol.present ? data.symbol.value : this.symbol,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      groupId: data.groupId.present ? data.groupId.value : this.groupId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('WatchlistEntry(')
          ..write('symbol: $symbol, ')
          ..write('createdAt: $createdAt, ')
          ..write('groupId: $groupId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(symbol, createdAt, groupId);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is i1.WatchlistEntry &&
          other.symbol == this.symbol &&
          other.createdAt == this.createdAt &&
          other.groupId == this.groupId);
}

class WatchlistCompanion extends i0.UpdateCompanion<i1.WatchlistEntry> {
  final i0.Value<String> symbol;
  final i0.Value<DateTime> createdAt;
  final i0.Value<int?> groupId;
  final i0.Value<int> rowid;
  const WatchlistCompanion({
    this.symbol = const i0.Value.absent(),
    this.createdAt = const i0.Value.absent(),
    this.groupId = const i0.Value.absent(),
    this.rowid = const i0.Value.absent(),
  });
  WatchlistCompanion.insert({
    required String symbol,
    this.createdAt = const i0.Value.absent(),
    this.groupId = const i0.Value.absent(),
    this.rowid = const i0.Value.absent(),
  }) : symbol = i0.Value(symbol);
  static i0.Insertable<i1.WatchlistEntry> custom({
    i0.Expression<String>? symbol,
    i0.Expression<DateTime>? createdAt,
    i0.Expression<int>? groupId,
    i0.Expression<int>? rowid,
  }) {
    return i0.RawValuesInsertable({
      if (symbol != null) 'symbol': symbol,
      if (createdAt != null) 'created_at': createdAt,
      if (groupId != null) 'group_id': groupId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  i1.WatchlistCompanion copyWith({
    i0.Value<String>? symbol,
    i0.Value<DateTime>? createdAt,
    i0.Value<int?>? groupId,
    i0.Value<int>? rowid,
  }) {
    return i1.WatchlistCompanion(
      symbol: symbol ?? this.symbol,
      createdAt: createdAt ?? this.createdAt,
      groupId: groupId ?? this.groupId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, i0.Expression> toColumns(bool nullToAbsent) {
    final map = <String, i0.Expression>{};
    if (symbol.present) {
      map['symbol'] = i0.Variable<String>(symbol.value);
    }
    if (createdAt.present) {
      map['created_at'] = i0.Variable<DateTime>(createdAt.value);
    }
    if (groupId.present) {
      map['group_id'] = i0.Variable<int>(groupId.value);
    }
    if (rowid.present) {
      map['rowid'] = i0.Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('WatchlistCompanion(')
          ..write('symbol: $symbol, ')
          ..write('createdAt: $createdAt, ')
          ..write('groupId: $groupId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $UpdateRunTable extends i2.UpdateRun
    with i0.TableInfo<$UpdateRunTable, i1.UpdateRunEntry> {
  @override
  final i0.GeneratedDatabase attachedDatabase;
  final String? _alias;
  $UpdateRunTable(this.attachedDatabase, [this._alias]);
  static const i0.VerificationMeta _idMeta = const i0.VerificationMeta('id');
  @override
  late final i0.GeneratedColumn<int> id = i0.GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: i0.DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: i0.GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const i0.VerificationMeta _runDateMeta = const i0.VerificationMeta(
    'runDate',
  );
  @override
  late final i0.GeneratedColumn<DateTime> runDate =
      i0.GeneratedColumn<DateTime>(
        'run_date',
        aliasedName,
        false,
        type: i0.DriftSqlType.dateTime,
        requiredDuringInsert: true,
      );
  static const i0.VerificationMeta _startedAtMeta = const i0.VerificationMeta(
    'startedAt',
  );
  @override
  late final i0.GeneratedColumn<DateTime> startedAt =
      i0.GeneratedColumn<DateTime>(
        'started_at',
        aliasedName,
        false,
        type: i0.DriftSqlType.dateTime,
        requiredDuringInsert: false,
        defaultValue: i3.currentDateAndTime,
      );
  static const i0.VerificationMeta _finishedAtMeta = const i0.VerificationMeta(
    'finishedAt',
  );
  @override
  late final i0.GeneratedColumn<DateTime> finishedAt =
      i0.GeneratedColumn<DateTime>(
        'finished_at',
        aliasedName,
        true,
        type: i0.DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const i0.VerificationMeta _statusMeta = const i0.VerificationMeta(
    'status',
  );
  @override
  late final i0.GeneratedColumn<String> status = i0.GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: i0.DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const i0.VerificationMeta _messageMeta = const i0.VerificationMeta(
    'message',
  );
  @override
  late final i0.GeneratedColumn<String> message = i0.GeneratedColumn<String>(
    'message',
    aliasedName,
    true,
    type: i0.DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<i0.GeneratedColumn> get $columns => [
    id,
    runDate,
    startedAt,
    finishedAt,
    status,
    message,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'update_run';
  @override
  i0.VerificationContext validateIntegrity(
    i0.Insertable<i1.UpdateRunEntry> instance, {
    bool isInserting = false,
  }) {
    final context = i0.VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('run_date')) {
      context.handle(
        _runDateMeta,
        runDate.isAcceptableOrUnknown(data['run_date']!, _runDateMeta),
      );
    } else if (isInserting) {
      context.missing(_runDateMeta);
    }
    if (data.containsKey('started_at')) {
      context.handle(
        _startedAtMeta,
        startedAt.isAcceptableOrUnknown(data['started_at']!, _startedAtMeta),
      );
    }
    if (data.containsKey('finished_at')) {
      context.handle(
        _finishedAtMeta,
        finishedAt.isAcceptableOrUnknown(data['finished_at']!, _finishedAtMeta),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('message')) {
      context.handle(
        _messageMeta,
        message.isAcceptableOrUnknown(data['message']!, _messageMeta),
      );
    }
    return context;
  }

  @override
  Set<i0.GeneratedColumn> get $primaryKey => {id};
  @override
  i1.UpdateRunEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return i1.UpdateRunEntry(
      id: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      runDate: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.dateTime,
        data['${effectivePrefix}run_date'],
      )!,
      startedAt: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.dateTime,
        data['${effectivePrefix}started_at'],
      )!,
      finishedAt: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.dateTime,
        data['${effectivePrefix}finished_at'],
      ),
      status: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      message: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.string,
        data['${effectivePrefix}message'],
      ),
    );
  }

  @override
  $UpdateRunTable createAlias(String alias) {
    return $UpdateRunTable(attachedDatabase, alias);
  }
}

class UpdateRunEntry extends i0.DataClass
    implements i0.Insertable<i1.UpdateRunEntry> {
  /// 自動遞增 ID
  final int id;

  /// 更新的目標日期
  final DateTime runDate;

  /// 開始執行時間
  final DateTime startedAt;

  /// 完成時間（執行中則為空）
  final DateTime? finishedAt;

  /// 狀態：SUCCESS、FAILED、PARTIAL
  final String status;

  /// 訊息（錯誤詳情等）
  final String? message;
  const UpdateRunEntry({
    required this.id,
    required this.runDate,
    required this.startedAt,
    this.finishedAt,
    required this.status,
    this.message,
  });
  @override
  Map<String, i0.Expression> toColumns(bool nullToAbsent) {
    final map = <String, i0.Expression>{};
    map['id'] = i0.Variable<int>(id);
    map['run_date'] = i0.Variable<DateTime>(runDate);
    map['started_at'] = i0.Variable<DateTime>(startedAt);
    if (!nullToAbsent || finishedAt != null) {
      map['finished_at'] = i0.Variable<DateTime>(finishedAt);
    }
    map['status'] = i0.Variable<String>(status);
    if (!nullToAbsent || message != null) {
      map['message'] = i0.Variable<String>(message);
    }
    return map;
  }

  i1.UpdateRunCompanion toCompanion(bool nullToAbsent) {
    return i1.UpdateRunCompanion(
      id: i0.Value(id),
      runDate: i0.Value(runDate),
      startedAt: i0.Value(startedAt),
      finishedAt: finishedAt == null && nullToAbsent
          ? const i0.Value.absent()
          : i0.Value(finishedAt),
      status: i0.Value(status),
      message: message == null && nullToAbsent
          ? const i0.Value.absent()
          : i0.Value(message),
    );
  }

  factory UpdateRunEntry.fromJson(
    Map<String, dynamic> json, {
    i0.ValueSerializer? serializer,
  }) {
    serializer ??= i0.driftRuntimeOptions.defaultSerializer;
    return UpdateRunEntry(
      id: serializer.fromJson<int>(json['id']),
      runDate: serializer.fromJson<DateTime>(json['runDate']),
      startedAt: serializer.fromJson<DateTime>(json['startedAt']),
      finishedAt: serializer.fromJson<DateTime?>(json['finishedAt']),
      status: serializer.fromJson<String>(json['status']),
      message: serializer.fromJson<String?>(json['message']),
    );
  }
  @override
  Map<String, dynamic> toJson({i0.ValueSerializer? serializer}) {
    serializer ??= i0.driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'runDate': serializer.toJson<DateTime>(runDate),
      'startedAt': serializer.toJson<DateTime>(startedAt),
      'finishedAt': serializer.toJson<DateTime?>(finishedAt),
      'status': serializer.toJson<String>(status),
      'message': serializer.toJson<String?>(message),
    };
  }

  i1.UpdateRunEntry copyWith({
    int? id,
    DateTime? runDate,
    DateTime? startedAt,
    i0.Value<DateTime?> finishedAt = const i0.Value.absent(),
    String? status,
    i0.Value<String?> message = const i0.Value.absent(),
  }) => i1.UpdateRunEntry(
    id: id ?? this.id,
    runDate: runDate ?? this.runDate,
    startedAt: startedAt ?? this.startedAt,
    finishedAt: finishedAt.present ? finishedAt.value : this.finishedAt,
    status: status ?? this.status,
    message: message.present ? message.value : this.message,
  );
  UpdateRunEntry copyWithCompanion(i1.UpdateRunCompanion data) {
    return UpdateRunEntry(
      id: data.id.present ? data.id.value : this.id,
      runDate: data.runDate.present ? data.runDate.value : this.runDate,
      startedAt: data.startedAt.present ? data.startedAt.value : this.startedAt,
      finishedAt: data.finishedAt.present
          ? data.finishedAt.value
          : this.finishedAt,
      status: data.status.present ? data.status.value : this.status,
      message: data.message.present ? data.message.value : this.message,
    );
  }

  @override
  String toString() {
    return (StringBuffer('UpdateRunEntry(')
          ..write('id: $id, ')
          ..write('runDate: $runDate, ')
          ..write('startedAt: $startedAt, ')
          ..write('finishedAt: $finishedAt, ')
          ..write('status: $status, ')
          ..write('message: $message')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, runDate, startedAt, finishedAt, status, message);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is i1.UpdateRunEntry &&
          other.id == this.id &&
          other.runDate == this.runDate &&
          other.startedAt == this.startedAt &&
          other.finishedAt == this.finishedAt &&
          other.status == this.status &&
          other.message == this.message);
}

class UpdateRunCompanion extends i0.UpdateCompanion<i1.UpdateRunEntry> {
  final i0.Value<int> id;
  final i0.Value<DateTime> runDate;
  final i0.Value<DateTime> startedAt;
  final i0.Value<DateTime?> finishedAt;
  final i0.Value<String> status;
  final i0.Value<String?> message;
  const UpdateRunCompanion({
    this.id = const i0.Value.absent(),
    this.runDate = const i0.Value.absent(),
    this.startedAt = const i0.Value.absent(),
    this.finishedAt = const i0.Value.absent(),
    this.status = const i0.Value.absent(),
    this.message = const i0.Value.absent(),
  });
  UpdateRunCompanion.insert({
    this.id = const i0.Value.absent(),
    required DateTime runDate,
    this.startedAt = const i0.Value.absent(),
    this.finishedAt = const i0.Value.absent(),
    required String status,
    this.message = const i0.Value.absent(),
  }) : runDate = i0.Value(runDate),
       status = i0.Value(status);
  static i0.Insertable<i1.UpdateRunEntry> custom({
    i0.Expression<int>? id,
    i0.Expression<DateTime>? runDate,
    i0.Expression<DateTime>? startedAt,
    i0.Expression<DateTime>? finishedAt,
    i0.Expression<String>? status,
    i0.Expression<String>? message,
  }) {
    return i0.RawValuesInsertable({
      if (id != null) 'id': id,
      if (runDate != null) 'run_date': runDate,
      if (startedAt != null) 'started_at': startedAt,
      if (finishedAt != null) 'finished_at': finishedAt,
      if (status != null) 'status': status,
      if (message != null) 'message': message,
    });
  }

  i1.UpdateRunCompanion copyWith({
    i0.Value<int>? id,
    i0.Value<DateTime>? runDate,
    i0.Value<DateTime>? startedAt,
    i0.Value<DateTime?>? finishedAt,
    i0.Value<String>? status,
    i0.Value<String?>? message,
  }) {
    return i1.UpdateRunCompanion(
      id: id ?? this.id,
      runDate: runDate ?? this.runDate,
      startedAt: startedAt ?? this.startedAt,
      finishedAt: finishedAt ?? this.finishedAt,
      status: status ?? this.status,
      message: message ?? this.message,
    );
  }

  @override
  Map<String, i0.Expression> toColumns(bool nullToAbsent) {
    final map = <String, i0.Expression>{};
    if (id.present) {
      map['id'] = i0.Variable<int>(id.value);
    }
    if (runDate.present) {
      map['run_date'] = i0.Variable<DateTime>(runDate.value);
    }
    if (startedAt.present) {
      map['started_at'] = i0.Variable<DateTime>(startedAt.value);
    }
    if (finishedAt.present) {
      map['finished_at'] = i0.Variable<DateTime>(finishedAt.value);
    }
    if (status.present) {
      map['status'] = i0.Variable<String>(status.value);
    }
    if (message.present) {
      map['message'] = i0.Variable<String>(message.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('UpdateRunCompanion(')
          ..write('id: $id, ')
          ..write('runDate: $runDate, ')
          ..write('startedAt: $startedAt, ')
          ..write('finishedAt: $finishedAt, ')
          ..write('status: $status, ')
          ..write('message: $message')
          ..write(')'))
        .toString();
  }
}

class $AppSettingsTable extends i2.AppSettings
    with i0.TableInfo<$AppSettingsTable, i1.AppSettingEntry> {
  @override
  final i0.GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AppSettingsTable(this.attachedDatabase, [this._alias]);
  static const i0.VerificationMeta _keyMeta = const i0.VerificationMeta('key');
  @override
  late final i0.GeneratedColumn<String> key = i0.GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: i0.DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const i0.VerificationMeta _valueMeta = const i0.VerificationMeta(
    'value',
  );
  @override
  late final i0.GeneratedColumn<String> value = i0.GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: i0.DriftSqlType.string,
    requiredDuringInsert: true,
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
  List<i0.GeneratedColumn> get $columns => [key, value, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'app_settings';
  @override
  i0.VerificationContext validateIntegrity(
    i0.Insertable<i1.AppSettingEntry> instance, {
    bool isInserting = false,
  }) {
    final context = i0.VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
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
  Set<i0.GeneratedColumn> get $primaryKey => {key};
  @override
  i1.AppSettingEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return i1.AppSettingEntry(
      key: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $AppSettingsTable createAlias(String alias) {
    return $AppSettingsTable(attachedDatabase, alias);
  }
}

class AppSettingEntry extends i0.DataClass
    implements i0.Insertable<i1.AppSettingEntry> {
  /// 設定鍵
  final String key;

  /// 設定值
  final String value;

  /// 最後更新時間
  final DateTime updatedAt;
  const AppSettingEntry({
    required this.key,
    required this.value,
    required this.updatedAt,
  });
  @override
  Map<String, i0.Expression> toColumns(bool nullToAbsent) {
    final map = <String, i0.Expression>{};
    map['key'] = i0.Variable<String>(key);
    map['value'] = i0.Variable<String>(value);
    map['updated_at'] = i0.Variable<DateTime>(updatedAt);
    return map;
  }

  i1.AppSettingsCompanion toCompanion(bool nullToAbsent) {
    return i1.AppSettingsCompanion(
      key: i0.Value(key),
      value: i0.Value(value),
      updatedAt: i0.Value(updatedAt),
    );
  }

  factory AppSettingEntry.fromJson(
    Map<String, dynamic> json, {
    i0.ValueSerializer? serializer,
  }) {
    serializer ??= i0.driftRuntimeOptions.defaultSerializer;
    return AppSettingEntry(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({i0.ValueSerializer? serializer}) {
    serializer ??= i0.driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  i1.AppSettingEntry copyWith({
    String? key,
    String? value,
    DateTime? updatedAt,
  }) => i1.AppSettingEntry(
    key: key ?? this.key,
    value: value ?? this.value,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  AppSettingEntry copyWithCompanion(i1.AppSettingsCompanion data) {
    return AppSettingEntry(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AppSettingEntry(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is i1.AppSettingEntry &&
          other.key == this.key &&
          other.value == this.value &&
          other.updatedAt == this.updatedAt);
}

class AppSettingsCompanion extends i0.UpdateCompanion<i1.AppSettingEntry> {
  final i0.Value<String> key;
  final i0.Value<String> value;
  final i0.Value<DateTime> updatedAt;
  final i0.Value<int> rowid;
  const AppSettingsCompanion({
    this.key = const i0.Value.absent(),
    this.value = const i0.Value.absent(),
    this.updatedAt = const i0.Value.absent(),
    this.rowid = const i0.Value.absent(),
  });
  AppSettingsCompanion.insert({
    required String key,
    required String value,
    this.updatedAt = const i0.Value.absent(),
    this.rowid = const i0.Value.absent(),
  }) : key = i0.Value(key),
       value = i0.Value(value);
  static i0.Insertable<i1.AppSettingEntry> custom({
    i0.Expression<String>? key,
    i0.Expression<String>? value,
    i0.Expression<DateTime>? updatedAt,
    i0.Expression<int>? rowid,
  }) {
    return i0.RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  i1.AppSettingsCompanion copyWith({
    i0.Value<String>? key,
    i0.Value<String>? value,
    i0.Value<DateTime>? updatedAt,
    i0.Value<int>? rowid,
  }) {
    return i1.AppSettingsCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, i0.Expression> toColumns(bool nullToAbsent) {
    final map = <String, i0.Expression>{};
    if (key.present) {
      map['key'] = i0.Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = i0.Variable<String>(value.value);
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
    return (StringBuffer('AppSettingsCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PriceAlertTable extends i2.PriceAlert
    with i0.TableInfo<$PriceAlertTable, i1.PriceAlertEntry> {
  @override
  final i0.GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PriceAlertTable(this.attachedDatabase, [this._alias]);
  static const i0.VerificationMeta _idMeta = const i0.VerificationMeta('id');
  @override
  late final i0.GeneratedColumn<int> id = i0.GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: i0.DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: i0.GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
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
  static const i0.VerificationMeta _alertTypeMeta = const i0.VerificationMeta(
    'alertType',
  );
  @override
  late final i0.GeneratedColumn<String> alertType = i0.GeneratedColumn<String>(
    'alert_type',
    aliasedName,
    false,
    type: i0.DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const i0.VerificationMeta _targetValueMeta = const i0.VerificationMeta(
    'targetValue',
  );
  @override
  late final i0.GeneratedColumn<double> targetValue =
      i0.GeneratedColumn<double>(
        'target_value',
        aliasedName,
        false,
        type: i0.DriftSqlType.double,
        requiredDuringInsert: true,
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
  static const i0.VerificationMeta _triggeredAtMeta = const i0.VerificationMeta(
    'triggeredAt',
  );
  @override
  late final i0.GeneratedColumn<DateTime> triggeredAt =
      i0.GeneratedColumn<DateTime>(
        'triggered_at',
        aliasedName,
        true,
        type: i0.DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const i0.VerificationMeta _noteMeta = const i0.VerificationMeta(
    'note',
  );
  @override
  late final i0.GeneratedColumn<String> note = i0.GeneratedColumn<String>(
    'note',
    aliasedName,
    true,
    type: i0.DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const i0.VerificationMeta _managedByMeta = const i0.VerificationMeta(
    'managedBy',
  );
  @override
  late final i0.GeneratedColumn<String> managedBy = i0.GeneratedColumn<String>(
    'managed_by',
    aliasedName,
    true,
    type: i0.DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const i0.VerificationMeta _createdAtMeta = const i0.VerificationMeta(
    'createdAt',
  );
  @override
  late final i0.GeneratedColumn<DateTime> createdAt =
      i0.GeneratedColumn<DateTime>(
        'created_at',
        aliasedName,
        false,
        type: i0.DriftSqlType.dateTime,
        requiredDuringInsert: false,
        defaultValue: i3.currentDateAndTime,
      );
  @override
  List<i0.GeneratedColumn> get $columns => [
    id,
    symbol,
    alertType,
    targetValue,
    isActive,
    triggeredAt,
    note,
    managedBy,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'price_alert';
  @override
  i0.VerificationContext validateIntegrity(
    i0.Insertable<i1.PriceAlertEntry> instance, {
    bool isInserting = false,
  }) {
    final context = i0.VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('symbol')) {
      context.handle(
        _symbolMeta,
        symbol.isAcceptableOrUnknown(data['symbol']!, _symbolMeta),
      );
    } else if (isInserting) {
      context.missing(_symbolMeta);
    }
    if (data.containsKey('alert_type')) {
      context.handle(
        _alertTypeMeta,
        alertType.isAcceptableOrUnknown(data['alert_type']!, _alertTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_alertTypeMeta);
    }
    if (data.containsKey('target_value')) {
      context.handle(
        _targetValueMeta,
        targetValue.isAcceptableOrUnknown(
          data['target_value']!,
          _targetValueMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_targetValueMeta);
    }
    if (data.containsKey('is_active')) {
      context.handle(
        _isActiveMeta,
        isActive.isAcceptableOrUnknown(data['is_active']!, _isActiveMeta),
      );
    }
    if (data.containsKey('triggered_at')) {
      context.handle(
        _triggeredAtMeta,
        triggeredAt.isAcceptableOrUnknown(
          data['triggered_at']!,
          _triggeredAtMeta,
        ),
      );
    }
    if (data.containsKey('note')) {
      context.handle(
        _noteMeta,
        note.isAcceptableOrUnknown(data['note']!, _noteMeta),
      );
    }
    if (data.containsKey('managed_by')) {
      context.handle(
        _managedByMeta,
        managedBy.isAcceptableOrUnknown(data['managed_by']!, _managedByMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<i0.GeneratedColumn> get $primaryKey => {id};
  @override
  i1.PriceAlertEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return i1.PriceAlertEntry(
      id: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      symbol: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.string,
        data['${effectivePrefix}symbol'],
      )!,
      alertType: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.string,
        data['${effectivePrefix}alert_type'],
      )!,
      targetValue: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.double,
        data['${effectivePrefix}target_value'],
      )!,
      isActive: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.bool,
        data['${effectivePrefix}is_active'],
      )!,
      triggeredAt: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.dateTime,
        data['${effectivePrefix}triggered_at'],
      ),
      note: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.string,
        data['${effectivePrefix}note'],
      ),
      managedBy: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.string,
        data['${effectivePrefix}managed_by'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $PriceAlertTable createAlias(String alias) {
    return $PriceAlertTable(attachedDatabase, alias);
  }
}

class PriceAlertEntry extends i0.DataClass
    implements i0.Insertable<i1.PriceAlertEntry> {
  /// 自動遞增 ID
  final int id;

  /// 股票代碼
  final String symbol;

  /// 提醒類型（值域見 AlertParams）
  final String alertType;

  /// 目標值（價格或百分比）
  final double targetValue;

  /// 是否啟用
  final bool isActive;

  /// 觸發時間（尚未觸發則為空）
  final DateTime? triggeredAt;

  /// 備註說明
  final String? note;

  /// 自動維護者（`NULL` = 使用者手動設定，值域見 `AlertParams.managedBy*`）
  ///
  /// **NULL 是受保護的語意**：均線階梯([TrailingMaAlertService])每日重算並
  /// 改寫提醒價位，沒有這欄就分不出自動與手動，重算會把使用者特地設的
  /// 關鍵價位一起洗掉。自動流程只准動自己標記過的列。
  final String? managedBy;

  /// 建立時間
  final DateTime createdAt;
  const PriceAlertEntry({
    required this.id,
    required this.symbol,
    required this.alertType,
    required this.targetValue,
    required this.isActive,
    this.triggeredAt,
    this.note,
    this.managedBy,
    required this.createdAt,
  });
  @override
  Map<String, i0.Expression> toColumns(bool nullToAbsent) {
    final map = <String, i0.Expression>{};
    map['id'] = i0.Variable<int>(id);
    map['symbol'] = i0.Variable<String>(symbol);
    map['alert_type'] = i0.Variable<String>(alertType);
    map['target_value'] = i0.Variable<double>(targetValue);
    map['is_active'] = i0.Variable<bool>(isActive);
    if (!nullToAbsent || triggeredAt != null) {
      map['triggered_at'] = i0.Variable<DateTime>(triggeredAt);
    }
    if (!nullToAbsent || note != null) {
      map['note'] = i0.Variable<String>(note);
    }
    if (!nullToAbsent || managedBy != null) {
      map['managed_by'] = i0.Variable<String>(managedBy);
    }
    map['created_at'] = i0.Variable<DateTime>(createdAt);
    return map;
  }

  i1.PriceAlertCompanion toCompanion(bool nullToAbsent) {
    return i1.PriceAlertCompanion(
      id: i0.Value(id),
      symbol: i0.Value(symbol),
      alertType: i0.Value(alertType),
      targetValue: i0.Value(targetValue),
      isActive: i0.Value(isActive),
      triggeredAt: triggeredAt == null && nullToAbsent
          ? const i0.Value.absent()
          : i0.Value(triggeredAt),
      note: note == null && nullToAbsent
          ? const i0.Value.absent()
          : i0.Value(note),
      managedBy: managedBy == null && nullToAbsent
          ? const i0.Value.absent()
          : i0.Value(managedBy),
      createdAt: i0.Value(createdAt),
    );
  }

  factory PriceAlertEntry.fromJson(
    Map<String, dynamic> json, {
    i0.ValueSerializer? serializer,
  }) {
    serializer ??= i0.driftRuntimeOptions.defaultSerializer;
    return PriceAlertEntry(
      id: serializer.fromJson<int>(json['id']),
      symbol: serializer.fromJson<String>(json['symbol']),
      alertType: serializer.fromJson<String>(json['alertType']),
      targetValue: serializer.fromJson<double>(json['targetValue']),
      isActive: serializer.fromJson<bool>(json['isActive']),
      triggeredAt: serializer.fromJson<DateTime?>(json['triggeredAt']),
      note: serializer.fromJson<String?>(json['note']),
      managedBy: serializer.fromJson<String?>(json['managedBy']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({i0.ValueSerializer? serializer}) {
    serializer ??= i0.driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'symbol': serializer.toJson<String>(symbol),
      'alertType': serializer.toJson<String>(alertType),
      'targetValue': serializer.toJson<double>(targetValue),
      'isActive': serializer.toJson<bool>(isActive),
      'triggeredAt': serializer.toJson<DateTime?>(triggeredAt),
      'note': serializer.toJson<String?>(note),
      'managedBy': serializer.toJson<String?>(managedBy),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  i1.PriceAlertEntry copyWith({
    int? id,
    String? symbol,
    String? alertType,
    double? targetValue,
    bool? isActive,
    i0.Value<DateTime?> triggeredAt = const i0.Value.absent(),
    i0.Value<String?> note = const i0.Value.absent(),
    i0.Value<String?> managedBy = const i0.Value.absent(),
    DateTime? createdAt,
  }) => i1.PriceAlertEntry(
    id: id ?? this.id,
    symbol: symbol ?? this.symbol,
    alertType: alertType ?? this.alertType,
    targetValue: targetValue ?? this.targetValue,
    isActive: isActive ?? this.isActive,
    triggeredAt: triggeredAt.present ? triggeredAt.value : this.triggeredAt,
    note: note.present ? note.value : this.note,
    managedBy: managedBy.present ? managedBy.value : this.managedBy,
    createdAt: createdAt ?? this.createdAt,
  );
  PriceAlertEntry copyWithCompanion(i1.PriceAlertCompanion data) {
    return PriceAlertEntry(
      id: data.id.present ? data.id.value : this.id,
      symbol: data.symbol.present ? data.symbol.value : this.symbol,
      alertType: data.alertType.present ? data.alertType.value : this.alertType,
      targetValue: data.targetValue.present
          ? data.targetValue.value
          : this.targetValue,
      isActive: data.isActive.present ? data.isActive.value : this.isActive,
      triggeredAt: data.triggeredAt.present
          ? data.triggeredAt.value
          : this.triggeredAt,
      note: data.note.present ? data.note.value : this.note,
      managedBy: data.managedBy.present ? data.managedBy.value : this.managedBy,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PriceAlertEntry(')
          ..write('id: $id, ')
          ..write('symbol: $symbol, ')
          ..write('alertType: $alertType, ')
          ..write('targetValue: $targetValue, ')
          ..write('isActive: $isActive, ')
          ..write('triggeredAt: $triggeredAt, ')
          ..write('note: $note, ')
          ..write('managedBy: $managedBy, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    symbol,
    alertType,
    targetValue,
    isActive,
    triggeredAt,
    note,
    managedBy,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is i1.PriceAlertEntry &&
          other.id == this.id &&
          other.symbol == this.symbol &&
          other.alertType == this.alertType &&
          other.targetValue == this.targetValue &&
          other.isActive == this.isActive &&
          other.triggeredAt == this.triggeredAt &&
          other.note == this.note &&
          other.managedBy == this.managedBy &&
          other.createdAt == this.createdAt);
}

class PriceAlertCompanion extends i0.UpdateCompanion<i1.PriceAlertEntry> {
  final i0.Value<int> id;
  final i0.Value<String> symbol;
  final i0.Value<String> alertType;
  final i0.Value<double> targetValue;
  final i0.Value<bool> isActive;
  final i0.Value<DateTime?> triggeredAt;
  final i0.Value<String?> note;
  final i0.Value<String?> managedBy;
  final i0.Value<DateTime> createdAt;
  const PriceAlertCompanion({
    this.id = const i0.Value.absent(),
    this.symbol = const i0.Value.absent(),
    this.alertType = const i0.Value.absent(),
    this.targetValue = const i0.Value.absent(),
    this.isActive = const i0.Value.absent(),
    this.triggeredAt = const i0.Value.absent(),
    this.note = const i0.Value.absent(),
    this.managedBy = const i0.Value.absent(),
    this.createdAt = const i0.Value.absent(),
  });
  PriceAlertCompanion.insert({
    this.id = const i0.Value.absent(),
    required String symbol,
    required String alertType,
    required double targetValue,
    this.isActive = const i0.Value.absent(),
    this.triggeredAt = const i0.Value.absent(),
    this.note = const i0.Value.absent(),
    this.managedBy = const i0.Value.absent(),
    this.createdAt = const i0.Value.absent(),
  }) : symbol = i0.Value(symbol),
       alertType = i0.Value(alertType),
       targetValue = i0.Value(targetValue);
  static i0.Insertable<i1.PriceAlertEntry> custom({
    i0.Expression<int>? id,
    i0.Expression<String>? symbol,
    i0.Expression<String>? alertType,
    i0.Expression<double>? targetValue,
    i0.Expression<bool>? isActive,
    i0.Expression<DateTime>? triggeredAt,
    i0.Expression<String>? note,
    i0.Expression<String>? managedBy,
    i0.Expression<DateTime>? createdAt,
  }) {
    return i0.RawValuesInsertable({
      if (id != null) 'id': id,
      if (symbol != null) 'symbol': symbol,
      if (alertType != null) 'alert_type': alertType,
      if (targetValue != null) 'target_value': targetValue,
      if (isActive != null) 'is_active': isActive,
      if (triggeredAt != null) 'triggered_at': triggeredAt,
      if (note != null) 'note': note,
      if (managedBy != null) 'managed_by': managedBy,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  i1.PriceAlertCompanion copyWith({
    i0.Value<int>? id,
    i0.Value<String>? symbol,
    i0.Value<String>? alertType,
    i0.Value<double>? targetValue,
    i0.Value<bool>? isActive,
    i0.Value<DateTime?>? triggeredAt,
    i0.Value<String?>? note,
    i0.Value<String?>? managedBy,
    i0.Value<DateTime>? createdAt,
  }) {
    return i1.PriceAlertCompanion(
      id: id ?? this.id,
      symbol: symbol ?? this.symbol,
      alertType: alertType ?? this.alertType,
      targetValue: targetValue ?? this.targetValue,
      isActive: isActive ?? this.isActive,
      triggeredAt: triggeredAt ?? this.triggeredAt,
      note: note ?? this.note,
      managedBy: managedBy ?? this.managedBy,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, i0.Expression> toColumns(bool nullToAbsent) {
    final map = <String, i0.Expression>{};
    if (id.present) {
      map['id'] = i0.Variable<int>(id.value);
    }
    if (symbol.present) {
      map['symbol'] = i0.Variable<String>(symbol.value);
    }
    if (alertType.present) {
      map['alert_type'] = i0.Variable<String>(alertType.value);
    }
    if (targetValue.present) {
      map['target_value'] = i0.Variable<double>(targetValue.value);
    }
    if (isActive.present) {
      map['is_active'] = i0.Variable<bool>(isActive.value);
    }
    if (triggeredAt.present) {
      map['triggered_at'] = i0.Variable<DateTime>(triggeredAt.value);
    }
    if (note.present) {
      map['note'] = i0.Variable<String>(note.value);
    }
    if (managedBy.present) {
      map['managed_by'] = i0.Variable<String>(managedBy.value);
    }
    if (createdAt.present) {
      map['created_at'] = i0.Variable<DateTime>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PriceAlertCompanion(')
          ..write('id: $id, ')
          ..write('symbol: $symbol, ')
          ..write('alertType: $alertType, ')
          ..write('targetValue: $targetValue, ')
          ..write('isActive: $isActive, ')
          ..write('triggeredAt: $triggeredAt, ')
          ..write('note: $note, ')
          ..write('managedBy: $managedBy, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $PinnedThesisTable extends i2.PinnedThesis
    with i0.TableInfo<$PinnedThesisTable, i1.PinnedThesisEntry> {
  @override
  final i0.GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PinnedThesisTable(this.attachedDatabase, [this._alias]);
  static const i0.VerificationMeta _idMeta = const i0.VerificationMeta('id');
  @override
  late final i0.GeneratedColumn<int> id = i0.GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: i0.DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: i0.GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
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
      'REFERENCES stock_master (symbol)',
    ),
  );
  static const i0.VerificationMeta _pinnedDateMeta = const i0.VerificationMeta(
    'pinnedDate',
  );
  @override
  late final i0.GeneratedColumn<DateTime> pinnedDate =
      i0.GeneratedColumn<DateTime>(
        'pinned_date',
        aliasedName,
        false,
        type: i0.DriftSqlType.dateTime,
        requiredDuringInsert: true,
      );
  static const i0.VerificationMeta _referencePriceMeta =
      const i0.VerificationMeta('referencePrice');
  @override
  late final i0.GeneratedColumn<double> referencePrice =
      i0.GeneratedColumn<double>(
        'reference_price',
        aliasedName,
        false,
        type: i0.DriftSqlType.double,
        requiredDuringInsert: true,
      );
  static const i0.VerificationMeta _modeMeta = const i0.VerificationMeta(
    'mode',
  );
  @override
  late final i0.GeneratedColumn<String> mode = i0.GeneratedColumn<String>(
    'mode',
    aliasedName,
    false,
    type: i0.DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const i0.VerificationMeta _triggeredRulesMeta =
      const i0.VerificationMeta('triggeredRules');
  @override
  late final i0.GeneratedColumn<String> triggeredRules =
      i0.GeneratedColumn<String>(
        'triggered_rules',
        aliasedName,
        false,
        type: i0.DriftSqlType.string,
        requiredDuringInsert: true,
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
    requiredDuringInsert: true,
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
    requiredDuringInsert: true,
  );
  static const i0.VerificationMeta _statusMeta = const i0.VerificationMeta(
    'status',
  );
  @override
  late final i0.GeneratedColumn<String> status = i0.GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: i0.DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const i3.Constant('ACTIVE'),
  );
  static const i0.VerificationMeta _invalidatedDateMeta =
      const i0.VerificationMeta('invalidatedDate');
  @override
  late final i0.GeneratedColumn<DateTime> invalidatedDate =
      i0.GeneratedColumn<DateTime>(
        'invalidated_date',
        aliasedName,
        true,
        type: i0.DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const i0.VerificationMeta _invalidatedReasonMeta =
      const i0.VerificationMeta('invalidatedReason');
  @override
  late final i0.GeneratedColumn<String> invalidatedReason =
      i0.GeneratedColumn<String>(
        'invalidated_reason',
        aliasedName,
        true,
        type: i0.DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const i0.VerificationMeta _lastCheckedDateMeta =
      const i0.VerificationMeta('lastCheckedDate');
  @override
  late final i0.GeneratedColumn<DateTime> lastCheckedDate =
      i0.GeneratedColumn<DateTime>(
        'last_checked_date',
        aliasedName,
        true,
        type: i0.DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const i0.VerificationMeta _createdAtMeta = const i0.VerificationMeta(
    'createdAt',
  );
  @override
  late final i0.GeneratedColumn<DateTime> createdAt =
      i0.GeneratedColumn<DateTime>(
        'created_at',
        aliasedName,
        false,
        type: i0.DriftSqlType.dateTime,
        requiredDuringInsert: false,
        defaultValue: i3.currentDateAndTime,
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
    id,
    symbol,
    pinnedDate,
    referencePrice,
    mode,
    triggeredRules,
    scoreShort,
    scoreLong,
    status,
    invalidatedDate,
    invalidatedReason,
    lastCheckedDate,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'pinned_thesis';
  @override
  i0.VerificationContext validateIntegrity(
    i0.Insertable<i1.PinnedThesisEntry> instance, {
    bool isInserting = false,
  }) {
    final context = i0.VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('symbol')) {
      context.handle(
        _symbolMeta,
        symbol.isAcceptableOrUnknown(data['symbol']!, _symbolMeta),
      );
    } else if (isInserting) {
      context.missing(_symbolMeta);
    }
    if (data.containsKey('pinned_date')) {
      context.handle(
        _pinnedDateMeta,
        pinnedDate.isAcceptableOrUnknown(data['pinned_date']!, _pinnedDateMeta),
      );
    } else if (isInserting) {
      context.missing(_pinnedDateMeta);
    }
    if (data.containsKey('reference_price')) {
      context.handle(
        _referencePriceMeta,
        referencePrice.isAcceptableOrUnknown(
          data['reference_price']!,
          _referencePriceMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_referencePriceMeta);
    }
    if (data.containsKey('mode')) {
      context.handle(
        _modeMeta,
        mode.isAcceptableOrUnknown(data['mode']!, _modeMeta),
      );
    } else if (isInserting) {
      context.missing(_modeMeta);
    }
    if (data.containsKey('triggered_rules')) {
      context.handle(
        _triggeredRulesMeta,
        triggeredRules.isAcceptableOrUnknown(
          data['triggered_rules']!,
          _triggeredRulesMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_triggeredRulesMeta);
    }
    if (data.containsKey('score_short')) {
      context.handle(
        _scoreShortMeta,
        scoreShort.isAcceptableOrUnknown(data['score_short']!, _scoreShortMeta),
      );
    } else if (isInserting) {
      context.missing(_scoreShortMeta);
    }
    if (data.containsKey('score_long')) {
      context.handle(
        _scoreLongMeta,
        scoreLong.isAcceptableOrUnknown(data['score_long']!, _scoreLongMeta),
      );
    } else if (isInserting) {
      context.missing(_scoreLongMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    if (data.containsKey('invalidated_date')) {
      context.handle(
        _invalidatedDateMeta,
        invalidatedDate.isAcceptableOrUnknown(
          data['invalidated_date']!,
          _invalidatedDateMeta,
        ),
      );
    }
    if (data.containsKey('invalidated_reason')) {
      context.handle(
        _invalidatedReasonMeta,
        invalidatedReason.isAcceptableOrUnknown(
          data['invalidated_reason']!,
          _invalidatedReasonMeta,
        ),
      );
    }
    if (data.containsKey('last_checked_date')) {
      context.handle(
        _lastCheckedDateMeta,
        lastCheckedDate.isAcceptableOrUnknown(
          data['last_checked_date']!,
          _lastCheckedDateMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
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
  Set<i0.GeneratedColumn> get $primaryKey => {id};
  @override
  i1.PinnedThesisEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return i1.PinnedThesisEntry(
      id: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      symbol: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.string,
        data['${effectivePrefix}symbol'],
      )!,
      pinnedDate: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.dateTime,
        data['${effectivePrefix}pinned_date'],
      )!,
      referencePrice: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.double,
        data['${effectivePrefix}reference_price'],
      )!,
      mode: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.string,
        data['${effectivePrefix}mode'],
      )!,
      triggeredRules: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.string,
        data['${effectivePrefix}triggered_rules'],
      )!,
      scoreShort: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.double,
        data['${effectivePrefix}score_short'],
      )!,
      scoreLong: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.double,
        data['${effectivePrefix}score_long'],
      )!,
      status: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      invalidatedDate: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.dateTime,
        data['${effectivePrefix}invalidated_date'],
      ),
      invalidatedReason: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.string,
        data['${effectivePrefix}invalidated_reason'],
      ),
      lastCheckedDate: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.dateTime,
        data['${effectivePrefix}last_checked_date'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $PinnedThesisTable createAlias(String alias) {
    return $PinnedThesisTable(attachedDatabase, alias);
  }
}

class PinnedThesisEntry extends i0.DataClass
    implements i0.Insertable<i1.PinnedThesisEntry> {
  final int id;
  final String symbol;

  /// 快照**資料日**（dataDate，非點擊時刻）
  final DateTime pinnedDate;

  /// 釘選資料日收盤——僅供顯示與 timeStop 基準，不代表可成交價
  final double referencePrice;

  /// 釘選當下路由 mode（momentum / strength / pullback）
  final String mode;

  /// 當日觸發規則碼快照（JSON array；v1 不顯示、留回溯用）
  final String triggeredRules;
  final double scoreShort;
  final double scoreLong;

  /// ACTIVE / INVALIDATED / ARCHIVED
  final String status;
  final DateTime? invalidatedDate;

  /// ExitReason.name（現值域僅 timeStop——gate 砍掉 hardStop/trendBreak）
  final String? invalidatedReason;

  /// monitor 每次跑必更新（staleness 顯示用）
  final DateTime? lastCheckedDate;
  final DateTime createdAt;

  /// 僅於 status 實際變更時更新
  final DateTime updatedAt;
  const PinnedThesisEntry({
    required this.id,
    required this.symbol,
    required this.pinnedDate,
    required this.referencePrice,
    required this.mode,
    required this.triggeredRules,
    required this.scoreShort,
    required this.scoreLong,
    required this.status,
    this.invalidatedDate,
    this.invalidatedReason,
    this.lastCheckedDate,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, i0.Expression> toColumns(bool nullToAbsent) {
    final map = <String, i0.Expression>{};
    map['id'] = i0.Variable<int>(id);
    map['symbol'] = i0.Variable<String>(symbol);
    map['pinned_date'] = i0.Variable<DateTime>(pinnedDate);
    map['reference_price'] = i0.Variable<double>(referencePrice);
    map['mode'] = i0.Variable<String>(mode);
    map['triggered_rules'] = i0.Variable<String>(triggeredRules);
    map['score_short'] = i0.Variable<double>(scoreShort);
    map['score_long'] = i0.Variable<double>(scoreLong);
    map['status'] = i0.Variable<String>(status);
    if (!nullToAbsent || invalidatedDate != null) {
      map['invalidated_date'] = i0.Variable<DateTime>(invalidatedDate);
    }
    if (!nullToAbsent || invalidatedReason != null) {
      map['invalidated_reason'] = i0.Variable<String>(invalidatedReason);
    }
    if (!nullToAbsent || lastCheckedDate != null) {
      map['last_checked_date'] = i0.Variable<DateTime>(lastCheckedDate);
    }
    map['created_at'] = i0.Variable<DateTime>(createdAt);
    map['updated_at'] = i0.Variable<DateTime>(updatedAt);
    return map;
  }

  i1.PinnedThesisCompanion toCompanion(bool nullToAbsent) {
    return i1.PinnedThesisCompanion(
      id: i0.Value(id),
      symbol: i0.Value(symbol),
      pinnedDate: i0.Value(pinnedDate),
      referencePrice: i0.Value(referencePrice),
      mode: i0.Value(mode),
      triggeredRules: i0.Value(triggeredRules),
      scoreShort: i0.Value(scoreShort),
      scoreLong: i0.Value(scoreLong),
      status: i0.Value(status),
      invalidatedDate: invalidatedDate == null && nullToAbsent
          ? const i0.Value.absent()
          : i0.Value(invalidatedDate),
      invalidatedReason: invalidatedReason == null && nullToAbsent
          ? const i0.Value.absent()
          : i0.Value(invalidatedReason),
      lastCheckedDate: lastCheckedDate == null && nullToAbsent
          ? const i0.Value.absent()
          : i0.Value(lastCheckedDate),
      createdAt: i0.Value(createdAt),
      updatedAt: i0.Value(updatedAt),
    );
  }

  factory PinnedThesisEntry.fromJson(
    Map<String, dynamic> json, {
    i0.ValueSerializer? serializer,
  }) {
    serializer ??= i0.driftRuntimeOptions.defaultSerializer;
    return PinnedThesisEntry(
      id: serializer.fromJson<int>(json['id']),
      symbol: serializer.fromJson<String>(json['symbol']),
      pinnedDate: serializer.fromJson<DateTime>(json['pinnedDate']),
      referencePrice: serializer.fromJson<double>(json['referencePrice']),
      mode: serializer.fromJson<String>(json['mode']),
      triggeredRules: serializer.fromJson<String>(json['triggeredRules']),
      scoreShort: serializer.fromJson<double>(json['scoreShort']),
      scoreLong: serializer.fromJson<double>(json['scoreLong']),
      status: serializer.fromJson<String>(json['status']),
      invalidatedDate: serializer.fromJson<DateTime?>(json['invalidatedDate']),
      invalidatedReason: serializer.fromJson<String?>(
        json['invalidatedReason'],
      ),
      lastCheckedDate: serializer.fromJson<DateTime?>(json['lastCheckedDate']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({i0.ValueSerializer? serializer}) {
    serializer ??= i0.driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'symbol': serializer.toJson<String>(symbol),
      'pinnedDate': serializer.toJson<DateTime>(pinnedDate),
      'referencePrice': serializer.toJson<double>(referencePrice),
      'mode': serializer.toJson<String>(mode),
      'triggeredRules': serializer.toJson<String>(triggeredRules),
      'scoreShort': serializer.toJson<double>(scoreShort),
      'scoreLong': serializer.toJson<double>(scoreLong),
      'status': serializer.toJson<String>(status),
      'invalidatedDate': serializer.toJson<DateTime?>(invalidatedDate),
      'invalidatedReason': serializer.toJson<String?>(invalidatedReason),
      'lastCheckedDate': serializer.toJson<DateTime?>(lastCheckedDate),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  i1.PinnedThesisEntry copyWith({
    int? id,
    String? symbol,
    DateTime? pinnedDate,
    double? referencePrice,
    String? mode,
    String? triggeredRules,
    double? scoreShort,
    double? scoreLong,
    String? status,
    i0.Value<DateTime?> invalidatedDate = const i0.Value.absent(),
    i0.Value<String?> invalidatedReason = const i0.Value.absent(),
    i0.Value<DateTime?> lastCheckedDate = const i0.Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => i1.PinnedThesisEntry(
    id: id ?? this.id,
    symbol: symbol ?? this.symbol,
    pinnedDate: pinnedDate ?? this.pinnedDate,
    referencePrice: referencePrice ?? this.referencePrice,
    mode: mode ?? this.mode,
    triggeredRules: triggeredRules ?? this.triggeredRules,
    scoreShort: scoreShort ?? this.scoreShort,
    scoreLong: scoreLong ?? this.scoreLong,
    status: status ?? this.status,
    invalidatedDate: invalidatedDate.present
        ? invalidatedDate.value
        : this.invalidatedDate,
    invalidatedReason: invalidatedReason.present
        ? invalidatedReason.value
        : this.invalidatedReason,
    lastCheckedDate: lastCheckedDate.present
        ? lastCheckedDate.value
        : this.lastCheckedDate,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  PinnedThesisEntry copyWithCompanion(i1.PinnedThesisCompanion data) {
    return PinnedThesisEntry(
      id: data.id.present ? data.id.value : this.id,
      symbol: data.symbol.present ? data.symbol.value : this.symbol,
      pinnedDate: data.pinnedDate.present
          ? data.pinnedDate.value
          : this.pinnedDate,
      referencePrice: data.referencePrice.present
          ? data.referencePrice.value
          : this.referencePrice,
      mode: data.mode.present ? data.mode.value : this.mode,
      triggeredRules: data.triggeredRules.present
          ? data.triggeredRules.value
          : this.triggeredRules,
      scoreShort: data.scoreShort.present
          ? data.scoreShort.value
          : this.scoreShort,
      scoreLong: data.scoreLong.present ? data.scoreLong.value : this.scoreLong,
      status: data.status.present ? data.status.value : this.status,
      invalidatedDate: data.invalidatedDate.present
          ? data.invalidatedDate.value
          : this.invalidatedDate,
      invalidatedReason: data.invalidatedReason.present
          ? data.invalidatedReason.value
          : this.invalidatedReason,
      lastCheckedDate: data.lastCheckedDate.present
          ? data.lastCheckedDate.value
          : this.lastCheckedDate,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PinnedThesisEntry(')
          ..write('id: $id, ')
          ..write('symbol: $symbol, ')
          ..write('pinnedDate: $pinnedDate, ')
          ..write('referencePrice: $referencePrice, ')
          ..write('mode: $mode, ')
          ..write('triggeredRules: $triggeredRules, ')
          ..write('scoreShort: $scoreShort, ')
          ..write('scoreLong: $scoreLong, ')
          ..write('status: $status, ')
          ..write('invalidatedDate: $invalidatedDate, ')
          ..write('invalidatedReason: $invalidatedReason, ')
          ..write('lastCheckedDate: $lastCheckedDate, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    symbol,
    pinnedDate,
    referencePrice,
    mode,
    triggeredRules,
    scoreShort,
    scoreLong,
    status,
    invalidatedDate,
    invalidatedReason,
    lastCheckedDate,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is i1.PinnedThesisEntry &&
          other.id == this.id &&
          other.symbol == this.symbol &&
          other.pinnedDate == this.pinnedDate &&
          other.referencePrice == this.referencePrice &&
          other.mode == this.mode &&
          other.triggeredRules == this.triggeredRules &&
          other.scoreShort == this.scoreShort &&
          other.scoreLong == this.scoreLong &&
          other.status == this.status &&
          other.invalidatedDate == this.invalidatedDate &&
          other.invalidatedReason == this.invalidatedReason &&
          other.lastCheckedDate == this.lastCheckedDate &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class PinnedThesisCompanion extends i0.UpdateCompanion<i1.PinnedThesisEntry> {
  final i0.Value<int> id;
  final i0.Value<String> symbol;
  final i0.Value<DateTime> pinnedDate;
  final i0.Value<double> referencePrice;
  final i0.Value<String> mode;
  final i0.Value<String> triggeredRules;
  final i0.Value<double> scoreShort;
  final i0.Value<double> scoreLong;
  final i0.Value<String> status;
  final i0.Value<DateTime?> invalidatedDate;
  final i0.Value<String?> invalidatedReason;
  final i0.Value<DateTime?> lastCheckedDate;
  final i0.Value<DateTime> createdAt;
  final i0.Value<DateTime> updatedAt;
  const PinnedThesisCompanion({
    this.id = const i0.Value.absent(),
    this.symbol = const i0.Value.absent(),
    this.pinnedDate = const i0.Value.absent(),
    this.referencePrice = const i0.Value.absent(),
    this.mode = const i0.Value.absent(),
    this.triggeredRules = const i0.Value.absent(),
    this.scoreShort = const i0.Value.absent(),
    this.scoreLong = const i0.Value.absent(),
    this.status = const i0.Value.absent(),
    this.invalidatedDate = const i0.Value.absent(),
    this.invalidatedReason = const i0.Value.absent(),
    this.lastCheckedDate = const i0.Value.absent(),
    this.createdAt = const i0.Value.absent(),
    this.updatedAt = const i0.Value.absent(),
  });
  PinnedThesisCompanion.insert({
    this.id = const i0.Value.absent(),
    required String symbol,
    required DateTime pinnedDate,
    required double referencePrice,
    required String mode,
    required String triggeredRules,
    required double scoreShort,
    required double scoreLong,
    this.status = const i0.Value.absent(),
    this.invalidatedDate = const i0.Value.absent(),
    this.invalidatedReason = const i0.Value.absent(),
    this.lastCheckedDate = const i0.Value.absent(),
    this.createdAt = const i0.Value.absent(),
    this.updatedAt = const i0.Value.absent(),
  }) : symbol = i0.Value(symbol),
       pinnedDate = i0.Value(pinnedDate),
       referencePrice = i0.Value(referencePrice),
       mode = i0.Value(mode),
       triggeredRules = i0.Value(triggeredRules),
       scoreShort = i0.Value(scoreShort),
       scoreLong = i0.Value(scoreLong);
  static i0.Insertable<i1.PinnedThesisEntry> custom({
    i0.Expression<int>? id,
    i0.Expression<String>? symbol,
    i0.Expression<DateTime>? pinnedDate,
    i0.Expression<double>? referencePrice,
    i0.Expression<String>? mode,
    i0.Expression<String>? triggeredRules,
    i0.Expression<double>? scoreShort,
    i0.Expression<double>? scoreLong,
    i0.Expression<String>? status,
    i0.Expression<DateTime>? invalidatedDate,
    i0.Expression<String>? invalidatedReason,
    i0.Expression<DateTime>? lastCheckedDate,
    i0.Expression<DateTime>? createdAt,
    i0.Expression<DateTime>? updatedAt,
  }) {
    return i0.RawValuesInsertable({
      if (id != null) 'id': id,
      if (symbol != null) 'symbol': symbol,
      if (pinnedDate != null) 'pinned_date': pinnedDate,
      if (referencePrice != null) 'reference_price': referencePrice,
      if (mode != null) 'mode': mode,
      if (triggeredRules != null) 'triggered_rules': triggeredRules,
      if (scoreShort != null) 'score_short': scoreShort,
      if (scoreLong != null) 'score_long': scoreLong,
      if (status != null) 'status': status,
      if (invalidatedDate != null) 'invalidated_date': invalidatedDate,
      if (invalidatedReason != null) 'invalidated_reason': invalidatedReason,
      if (lastCheckedDate != null) 'last_checked_date': lastCheckedDate,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  i1.PinnedThesisCompanion copyWith({
    i0.Value<int>? id,
    i0.Value<String>? symbol,
    i0.Value<DateTime>? pinnedDate,
    i0.Value<double>? referencePrice,
    i0.Value<String>? mode,
    i0.Value<String>? triggeredRules,
    i0.Value<double>? scoreShort,
    i0.Value<double>? scoreLong,
    i0.Value<String>? status,
    i0.Value<DateTime?>? invalidatedDate,
    i0.Value<String?>? invalidatedReason,
    i0.Value<DateTime?>? lastCheckedDate,
    i0.Value<DateTime>? createdAt,
    i0.Value<DateTime>? updatedAt,
  }) {
    return i1.PinnedThesisCompanion(
      id: id ?? this.id,
      symbol: symbol ?? this.symbol,
      pinnedDate: pinnedDate ?? this.pinnedDate,
      referencePrice: referencePrice ?? this.referencePrice,
      mode: mode ?? this.mode,
      triggeredRules: triggeredRules ?? this.triggeredRules,
      scoreShort: scoreShort ?? this.scoreShort,
      scoreLong: scoreLong ?? this.scoreLong,
      status: status ?? this.status,
      invalidatedDate: invalidatedDate ?? this.invalidatedDate,
      invalidatedReason: invalidatedReason ?? this.invalidatedReason,
      lastCheckedDate: lastCheckedDate ?? this.lastCheckedDate,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, i0.Expression> toColumns(bool nullToAbsent) {
    final map = <String, i0.Expression>{};
    if (id.present) {
      map['id'] = i0.Variable<int>(id.value);
    }
    if (symbol.present) {
      map['symbol'] = i0.Variable<String>(symbol.value);
    }
    if (pinnedDate.present) {
      map['pinned_date'] = i0.Variable<DateTime>(pinnedDate.value);
    }
    if (referencePrice.present) {
      map['reference_price'] = i0.Variable<double>(referencePrice.value);
    }
    if (mode.present) {
      map['mode'] = i0.Variable<String>(mode.value);
    }
    if (triggeredRules.present) {
      map['triggered_rules'] = i0.Variable<String>(triggeredRules.value);
    }
    if (scoreShort.present) {
      map['score_short'] = i0.Variable<double>(scoreShort.value);
    }
    if (scoreLong.present) {
      map['score_long'] = i0.Variable<double>(scoreLong.value);
    }
    if (status.present) {
      map['status'] = i0.Variable<String>(status.value);
    }
    if (invalidatedDate.present) {
      map['invalidated_date'] = i0.Variable<DateTime>(invalidatedDate.value);
    }
    if (invalidatedReason.present) {
      map['invalidated_reason'] = i0.Variable<String>(invalidatedReason.value);
    }
    if (lastCheckedDate.present) {
      map['last_checked_date'] = i0.Variable<DateTime>(lastCheckedDate.value);
    }
    if (createdAt.present) {
      map['created_at'] = i0.Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = i0.Variable<DateTime>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PinnedThesisCompanion(')
          ..write('id: $id, ')
          ..write('symbol: $symbol, ')
          ..write('pinnedDate: $pinnedDate, ')
          ..write('referencePrice: $referencePrice, ')
          ..write('mode: $mode, ')
          ..write('triggeredRules: $triggeredRules, ')
          ..write('scoreShort: $scoreShort, ')
          ..write('scoreLong: $scoreLong, ')
          ..write('status: $status, ')
          ..write('invalidatedDate: $invalidatedDate, ')
          ..write('invalidatedReason: $invalidatedReason, ')
          ..write('lastCheckedDate: $lastCheckedDate, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}
