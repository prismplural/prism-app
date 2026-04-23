// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'pk_group_sync_aliases_dao.dart';

// ignore_for_file: type=lint
mixin _$PkGroupSyncAliasesDaoMixin on DatabaseAccessor<AppDatabase> {
  $PkGroupSyncAliasesTable get pkGroupSyncAliases =>
      attachedDatabase.pkGroupSyncAliases;
  PkGroupSyncAliasesDaoManager get managers =>
      PkGroupSyncAliasesDaoManager(this);
}

class PkGroupSyncAliasesDaoManager {
  final _$PkGroupSyncAliasesDaoMixin _db;
  PkGroupSyncAliasesDaoManager(this._db);
  $$PkGroupSyncAliasesTableTableManager get pkGroupSyncAliases =>
      $$PkGroupSyncAliasesTableTableManager(
        _db.attachedDatabase,
        _db.pkGroupSyncAliases,
      );
}
