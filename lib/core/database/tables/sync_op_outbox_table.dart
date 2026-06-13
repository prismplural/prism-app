import 'package:drift/drift.dart';

/// Durable transactional outbox for CRDT sync emissions.
///
/// The Drift app DB and the Rust engine's `pending_ops` are two independent
/// durability domains bridged only by best-effort in-memory FFI calls, so an
/// op can be silently dropped after a committed write (engine unconfigured /
/// crash between commits) or durably leaked for a write that never commits
/// (emission inside a rollback-able transaction). This table makes the
/// emission durable: an op is persisted in the SAME Drift transaction as the
/// data write, then a serialized drainer dispatches rows to the Rust FFI
/// strictly after commit, retrying across engine-unconfigured windows and
/// process restarts. Local-only; not in `prismSyncSchema` (no wire change).
@DataClassName('SyncOpOutboxRow')
class SyncOpOutbox extends Table {
  /// Autoincrement so `id` order is the durable drain order.
  IntColumn get id => integer().autoIncrement()();

  /// Named explicitly so the SQL column stays `table_name` while the Dart
  /// getter avoids shadowing Drift's reserved `tableName` (physical-table-name)
  /// override below.
  TextColumn get entityTable => text().named('table_name')();
  TextColumn get entityId => text()();

  /// One of `create` / `update` / `delete`. This vocabulary CANNOT represent
  /// the divergence-aware reconcile/backfill modes; a reconcile/backfill is
  /// captured as `update` but is refused entry by the
  /// `persistCapturedOpsToOutbox` guard, because a drained plain `update`
  /// carries a fresh HLC and would reintroduce the reconcile/backfill clobber.
  /// Reconcile/backfill ops dispatch directly, never through this table.
  TextColumn get opType => text()();

  /// `jsonEncode` of the captured op fields; empty (`{}`) for deletes.
  TextColumn get fieldsJson => text()();

  /// Capture-time origin (ms since epoch), copied from
  /// `CapturedSyncOp.capturedAtMs`. The drainer re-derives the op's origin HLC
  /// from this so a deferred/replayed op is stamped via the `*_at` FFI at its
  /// capture time and can never win LWW against an edit made after capture.
  /// Falls back to enqueue time only for legacy ops with no capture
  /// stamp.
  IntColumn get createdAt => integer()();

  IntColumn get attempts => integer().withDefault(const Constant(0))();
  TextColumn get lastError => text().nullable()();
  BoolColumn get quarantined => boolean().withDefault(const Constant(false))();

  @override
  String get tableName => 'sync_op_outbox';
}
