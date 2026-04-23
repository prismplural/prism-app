import 'package:drift/drift.dart';

@DataClassName('PkGroupSyncAliasRow')
class PkGroupSyncAliases extends Table {
  /// Legacy sync entity id that may still appear in old delete/read paths.
  TextColumn get legacyEntityId => text()();

  /// Canonical PK group UUID this alias points at.
  TextColumn get pkGroupUuid => text()();

  /// Canonical sync entity id for the PK group, usually `pk-group:<uuid>`.
  TextColumn get canonicalEntityId => text()();

  DateTimeColumn get createdAt => dateTime()();

  @override
  String get tableName => 'pk_group_sync_aliases';

  @override
  Set<Column> get primaryKey => {legacyEntityId};
}
