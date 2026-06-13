import 'package:drift/drift.dart';

/// Generic PK-identity redirect aliases for the entity tables that perform
/// apply-time identity dedup — `members` and `fronting_sessions`.
///
/// When applyFields redirects an incoming op for legacy entity id X onto a
/// different local winner row Y (because both carry the same PluralKit
/// identity), the legacy id X is never materialized locally, so a later delete
/// op for X would no-op. Recording (entity_table, X) -> target_row_id=Y here
/// lets the delete paths resolve the redirect, and lets the repository delete
/// emitters fan tombstones out to every legacy id the fleet knows the entity
/// by. Modeled on `pk_group_sync_aliases`, generalized across tables.
@DataClassName('PkIdentitySyncAliasRow')
class PkIdentitySyncAliases extends Table {
  /// Entity table this alias belongs to: 'members' or 'fronting_sessions'.
  TextColumn get entityTable => text()();

  /// Legacy sync entity id that was redirected onto another local row.
  TextColumn get legacyEntityId => text()();

  /// PluralKit uuid of the redirected identity (used to re-resolve the current
  /// active holder on delete). Null when the redirect carried no uuid.
  TextColumn get pkUuid => text().nullable()();

  /// PluralKit id (members only) of the redirected identity. Null otherwise.
  TextColumn get pkId => text().nullable()();

  /// Owning member id (fronting_sessions only) of the redirected identity.
  /// Null otherwise.
  TextColumn get memberId => text().nullable()();

  /// The local winner row id the legacy id was redirected onto at record time
  /// (fallback resolution target if the identity re-resolves to nothing).
  TextColumn get targetRowId => text()();

  DateTimeColumn get createdAt => dateTime()();

  @override
  String get tableName => 'pk_identity_sync_aliases';

  @override
  Set<Column> get primaryKey => {entityTable, legacyEntityId};
}
