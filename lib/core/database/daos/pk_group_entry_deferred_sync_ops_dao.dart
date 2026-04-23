import 'package:drift/drift.dart';

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/tables/pk_group_entry_deferred_sync_ops_table.dart';

part 'pk_group_entry_deferred_sync_ops_dao.g.dart';

@DriftAccessor(tables: [PkGroupEntryDeferredSyncOps])
class PkGroupEntryDeferredSyncOpsDao extends DatabaseAccessor<AppDatabase>
    with _$PkGroupEntryDeferredSyncOpsDaoMixin {
  PkGroupEntryDeferredSyncOpsDao(super.db);

  Future<void> upsert(PkGroupEntryDeferredSyncOpsCompanion companion) async {
    await into(pkGroupEntryDeferredSyncOps).insertOnConflictUpdate(companion);
  }

  Future<List<PkGroupEntryDeferredSyncOpRow>> getAll() =>
      select(pkGroupEntryDeferredSyncOps).get();

  Future<List<PkGroupEntryDeferredSyncOpRow>> getForEntity(
    String entityType,
    String entityId,
  ) =>
      (select(pkGroupEntryDeferredSyncOps)..where(
            (t) =>
                t.entityType.equals(entityType) & t.entityId.equals(entityId),
          ))
          .get();

  Future<void> markRetried(String id) async {
    await customStatement(
      'UPDATE pk_group_entry_deferred_sync_ops '
      'SET retry_count = retry_count + 1, last_retry_at = ? '
      'WHERE id = ?',
      [DateTime.now().millisecondsSinceEpoch, id],
    );
  }

  Future<void> deleteById(String id) =>
      (delete(pkGroupEntryDeferredSyncOps)..where((t) => t.id.equals(id))).go();

  Future<void> clearAll() => delete(pkGroupEntryDeferredSyncOps).go();
}
