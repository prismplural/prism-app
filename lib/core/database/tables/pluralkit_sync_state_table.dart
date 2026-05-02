import 'package:drift/drift.dart';

class PluralKitSyncState extends Table {
  TextColumn get id => text()(); // always 'pk_config'
  TextColumn get systemId => text().nullable()();
  DateTimeColumn get lastSyncDate => dateTime().nullable()();
  DateTimeColumn get lastManualSyncDate => dateTime().nullable()();
  BoolColumn get isConnected =>
      boolean().withDefault(const Constant(false))();
  TextColumn get fieldSyncConfig => text().nullable()(); // JSON map of memberId → field config

  /// True once the user has completed (or explicitly dismissed) the member
  /// mapping flow for the current PK connection. While false, the connection
  /// is in `connected_pending_map` — auto-push and auto-sync are gated off.
  /// Reset to false on re-connect (new token).
  BoolColumn get mappingAcknowledged =>
      boolean().withDefault(const Constant(false))();

  /// The time at which the current PK connection was linked — used to scope
  /// switch push to sessions that started after linking. Set on `setToken`
  /// (fresh connection) and cleared on `clearToken`. Remains stable across
  /// subsequent `acknowledgeMapping()` calls so re-running the mapping flow
  /// doesn't shift the push window.
  DateTimeColumn get linkedAt => dateTime().nullable()();

  /// Monotonically-increasing counter bumped whenever the PK connection
  /// changes identity (new system on [setToken], or [clearToken]). Plan 02
  /// R1: stamped onto tombstones at delete time as `delete_intent_epoch`,
  /// then compared at push time to suppress deletions made under a prior
  /// link. Local-only — not synced across devices (each device tracks its
  /// own connection history, and cross-device coordination is handled via
  /// the synced `delete_push_started_at` timestamp instead).
  IntColumn get linkEpoch => integer().withDefault(const Constant(0))();

  // -- Phase 4B: diff-sweep resume cursor (§2.6 "Resume cursor shape") -------
  //
  // PK switches are ordered by timestamp, not by UUID. The cursor is a
  // (timestamp, switch_id) tuple so a resume re-fetches from the correct
  // boundary and the switch_id dedups the edge-case where two switches share
  // the same millisecond timestamp. Both are nullable — null means "never
  // processed any switch" (start from the beginning).

  /// Timestamp of the last PK switch successfully processed by the diff sweep.
  /// Used as the `before=` query parameter on resume: fetch
  /// `before = switchCursorTimestamp + 1µs`.
  DateTimeColumn get switchCursorTimestamp => dateTime().nullable()();

  /// UUID of the last PK switch successfully processed by the diff sweep.
  /// Deduplicates within the fetched page when the cursor timestamp falls
  /// on a page boundary shared by multiple switches.
  TextColumn get switchCursorId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
