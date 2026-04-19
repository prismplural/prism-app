import 'package:drift/drift.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/tables/pluralkit_sync_state_table.dart';

part 'pluralkit_sync_dao.g.dart';

@DriftAccessor(tables: [PluralKitSyncState])
class PluralKitSyncDao extends DatabaseAccessor<AppDatabase>
    with _$PluralKitSyncDaoMixin {
  PluralKitSyncDao(super.db);

  static const _configId = 'pk_config';

  Future<PluralKitSyncStateData> getSyncState() async {
    // INSERT OR IGNORE is atomic — safe when called concurrently on first launch.
    await into(pluralKitSyncState).insert(
      const PluralKitSyncStateCompanion(id: Value(_configId)),
      mode: InsertMode.insertOrIgnore,
    );
    return (select(pluralKitSyncState)
          ..where((s) => s.id.equals(_configId)))
        .getSingle();
  }

  Stream<PluralKitSyncStateData> watchSyncState() async* {
    // Ensure the row exists before the watch query runs.
    await getSyncState();
    yield* (select(pluralKitSyncState)
          ..where((s) => s.id.equals(_configId)))
        .watchSingle();
  }

  Future<void> upsertSyncState(PluralKitSyncStateCompanion state) =>
      into(pluralKitSyncState).insertOnConflictUpdate(state);

  /// Plan 02 R1: read the current link epoch (0 when no row exists yet).
  Future<int> getLinkEpoch() async {
    final row = await getSyncState();
    return row.linkEpoch;
  }

  /// Plan 02 R1: bump the link epoch inside a transaction so the write is
  /// atomic with whatever upsert triggered it (setToken systemId change,
  /// clearToken). Returns the new epoch.
  Future<int> bumpLinkEpoch() async {
    return attachedDatabase.transaction(() async {
      final current = await getSyncState();
      final next = current.linkEpoch + 1;
      await upsertSyncState(
        PluralKitSyncStateCompanion(
          id: const Value(_configId),
          linkEpoch: Value(next),
        ),
      );
      return next;
    });
  }
}
