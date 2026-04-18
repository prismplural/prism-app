import 'package:drift/drift.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/tables/sp_sync_state_table.dart';
import 'package:prism_plurality/core/database/tables/sp_id_map_table.dart';

part 'sp_import_dao.g.dart';

@DriftAccessor(tables: [SpSyncStateTable, SpIdMapTable])
class SpImportDao extends DatabaseAccessor<AppDatabase>
    with _$SpImportDaoMixin {
  SpImportDao(super.db);

  // SpSyncState
  Future<SpSyncStateRow?> getSyncState() =>
      (select(spSyncStateTable)..where((t) => t.id.equals('singleton')))
          .getSingleOrNull();

  Future<void> upsertSyncState(SpSyncStateTableCompanion data) =>
      into(spSyncStateTable).insertOnConflictUpdate(data);

  // SpIdMap
  Future<List<SpIdMapRow>> getAllMappings() => select(spIdMapTable).get();

  Future<void> upsertMapping(SpIdMapTableCompanion data) =>
      into(spIdMapTable).insertOnConflictUpdate(data);

  Future<void> upsertMappings(List<SpIdMapTableCompanion> rows) =>
      batch((b) => b.insertAllOnConflictUpdate(spIdMapTable, rows));

  /// Delete id-map rows matching any of [spIds] within [entityType].
  /// Used by the SP importer to scrub stale CF-as-member mappings whose
  /// user disposition is no longer `importAsMember` (plan §Classification).
  Future<void> deleteMappings(List<String> spIds, String entityType) async {
    if (spIds.isEmpty) return;
    await (delete(spIdMapTable)
          ..where(
            (t) => t.entityType.equals(entityType) & t.spId.isIn(spIds),
          ))
        .go();
  }
}
