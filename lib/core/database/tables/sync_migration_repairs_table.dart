import 'package:drift/drift.dart';

/// Durable sync-repair queue for migration rewrites of synced fields.
///
/// The Drift `onUpgrade` chain rewrites synced columns (`markdown_enabled`,
/// `member_groups.sort_state`, `conversations.includes_all_members` /
/// `participant_ids` / `creator_id`) in raw SQL at DB-open time, before any
/// repository or sync engine exists. Those rewrites emit no CRDT ops and never
/// touch the Rust `field_versions`, so paired devices diverge permanently. The
/// rule: any migration write to a `prismSyncSchema` column SELECTs the affected
/// ids and enqueues a row here inside the SAME step transaction, so the intent
/// is durable and atomic with the rewrite. After boot, when the engine is
/// healthy, `MigrationSyncRepairService` re-reads the CURRENT values and emits
/// real `recordUpdate`/`recordCreate` ops, then deletes the row only on FFI
/// success. Local-only; NOT in `prismSyncSchema` (no wire/protocol change).
///
/// The `(table_name, entity_id, reason)` primary key makes enqueue idempotent
/// (re-running a migration step coalesces onto the same row) and lets distinct
/// repairs for the same entity (different reasons) coexist.
@DataClassName('SyncMigrationRepairRow')
class SyncMigrationRepairs extends Table {
  /// Named explicitly so the SQL column stays `table_name` while the Dart
  /// getter avoids shadowing Drift's reserved `tableName` override below.
  TextColumn get entityTable => text().named('table_name')();
  TextColumn get entityId => text()();

  /// `jsonEncode` of the field names this repair must re-read and re-emit at
  /// drain time. Values are NOT stored — the drain reads CURRENT row values so
  /// a post-migration user edit is never clobbered with stale migration-time
  /// data.
  TextColumn get fieldNamesJson => text()();

  /// Why the repair was enqueued (e.g. `migration_v21_to_v25_sort_state`). Part
  /// of the PK, so the same entity can carry independent repairs.
  TextColumn get reason => text()();

  /// Wall-clock enqueue time (ms since epoch).
  IntColumn get enqueuedAt => integer()();

  @override
  Set<Column> get primaryKey => {entityTable, entityId, reason};

  @override
  String get tableName => 'sync_migration_repairs';
}
