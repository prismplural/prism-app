import 'package:drift/drift.dart';

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/tables/sync_op_outbox_table.dart';

part 'sync_op_outbox_dao.g.dart';

/// DAO for the durable sync-op outbox. Rows are enqueued inside the same Drift
/// transaction as the data write and drained to the Rust FFI strictly after
/// commit by [SyncOutboxDrainer]; `id` autoincrement order IS the drain order.
@DriftAccessor(tables: [SyncOpOutbox])
class SyncOutboxDao extends DatabaseAccessor<AppDatabase>
    with _$SyncOutboxDaoMixin {
  SyncOutboxDao(super.db);

  /// Batch-enqueue captured ops. The caller passes companions whose `id` is
  /// absent so SQLite assigns the autoincrement drain order.
  Future<void> insertAll(List<SyncOpOutboxCompanion> rows) async {
    if (rows.isEmpty) return;
    await batch((b) => b.insertAll(syncOpOutbox, rows));
  }

  /// All non-quarantined rows in drain (`id`) order. Quarantined rows are still
  /// needed to enforce per-entity lane blocking, so the drainer reads them
  /// separately via [allInIdOrder] when it needs the full picture.
  Future<List<SyncOpOutboxRow>> pendingInIdOrder() {
    return (select(syncOpOutbox)
          ..where((t) => t.quarantined.equals(false))
          ..orderBy([(t) => OrderingTerm.asc(t.id)]))
        .get();
  }

  /// Every row (including quarantined) in drain order. The drainer needs the
  /// quarantined rows to block later ops for the same entity.
  Future<List<SyncOpOutboxRow>> allInIdOrder() {
    return (select(syncOpOutbox)
          ..orderBy([(t) => OrderingTerm.asc(t.id)]))
        .get();
  }

  /// Delete the given rows after their FFI dispatch returned Ok. Batched so a
  /// coalesced delete group clears in one statement.
  Future<void> deleteByIds(List<int> ids) async {
    if (ids.isEmpty) return;
    await (delete(syncOpOutbox)..where((t) => t.id.isIn(ids))).go();
  }

  /// Record a failed (non-deferral) dispatch: bump `attempts`, store the error,
  /// and quarantine once `attempts` reaches [quarantineAfter]. The increment
  /// and the quarantine decision happen in one statement so a re-run is
  /// deterministic.
  Future<void> recordFailure(
    int id,
    String error, {
    required int quarantineAfter,
  }) async {
    await customUpdate(
      'UPDATE sync_op_outbox '
      'SET attempts = attempts + 1, '
      '    last_error = ?, '
      '    quarantined = (attempts + 1 >= ?) '
      'WHERE id = ?',
      variables: [
        Variable<String>(error),
        Variable<int>(quarantineAfter),
        Variable<int>(id),
      ],
      updates: {syncOpOutbox},
    );
  }

  /// Whether a row was quarantined by the most recent [recordFailure]. The
  /// drainer reads this to decide whether to file an ErrorReportingService
  /// report exactly once at the quarantine transition.
  Future<bool> isQuarantined(int id) async {
    final row = await (select(syncOpOutbox)
          ..where((t) => t.id.equals(id))
          ..limit(1))
        .getSingleOrNull();
    return row?.quarantined ?? false;
  }

  Future<int> count() async {
    final result = await customSelect(
      'SELECT COUNT(*) AS c FROM sync_op_outbox',
    ).getSingle();
    return result.read<int>('c');
  }

  /// Drop every outbox row. Used at pairing/bootstrap on never-paired devices,
  /// where `bootstrapExistingData` seeds the whole Drift store directly into
  /// `field_versions` (so any pre-pairing-enqueued rows would be redundant).
  Future<void> clearAll() => delete(syncOpOutbox).go();
}
