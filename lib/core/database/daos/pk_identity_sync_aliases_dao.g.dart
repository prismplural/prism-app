// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'pk_identity_sync_aliases_dao.dart';

// ignore_for_file: type=lint
mixin _$PkIdentitySyncAliasesDaoMixin on DatabaseAccessor<AppDatabase> {
  $PkIdentitySyncAliasesTable get pkIdentitySyncAliases =>
      attachedDatabase.pkIdentitySyncAliases;
  PkIdentitySyncAliasesDaoManager get managers =>
      PkIdentitySyncAliasesDaoManager(this);
}

class PkIdentitySyncAliasesDaoManager {
  final _$PkIdentitySyncAliasesDaoMixin _db;
  PkIdentitySyncAliasesDaoManager(this._db);
  $$PkIdentitySyncAliasesTableTableManager get pkIdentitySyncAliases =>
      $$PkIdentitySyncAliasesTableTableManager(
        _db.attachedDatabase,
        _db.pkIdentitySyncAliases,
      );
}
