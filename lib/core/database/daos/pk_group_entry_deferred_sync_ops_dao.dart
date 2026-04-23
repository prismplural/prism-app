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
    // H3: write `last_retry_at` through a Drift companion so the
    // DateTimeColumn mapping encodes it as seconds-since-epoch. A raw
    // `UPDATE ... SET last_retry_at = <ms>` bypasses the type mapper and
    // Drift decodes the 13-digit value as year ~58,000. The retry_count
    // increment stays in a small customUpdate since Drift has no
    // SET col = col + 1 helper on companions.
    await (update(pkGroupEntryDeferredSyncOps)..where((t) => t.id.equals(id)))
        .write(
          PkGroupEntryDeferredSyncOpsCompanion(
            lastRetryAt: Value(DateTime.now()),
          ),
        );
    await customUpdate(
      'UPDATE pk_group_entry_deferred_sync_ops '
      'SET retry_count = retry_count + 1 WHERE id = ?',
      variables: [Variable<String>(id)],
      updates: {pkGroupEntryDeferredSyncOps},
    );
  }

  Future<void> deleteById(String id) =>
      (delete(pkGroupEntryDeferredSyncOps)..where((t) => t.id.equals(id))).go();

  Future<void> clearAll() => delete(pkGroupEntryDeferredSyncOps).go();
}
