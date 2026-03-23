// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'pluralkit_sync_dao.dart';

// ignore_for_file: type=lint
mixin _$PluralKitSyncDaoMixin on DatabaseAccessor<AppDatabase> {
  $PluralKitSyncStateTable get pluralKitSyncState =>
      attachedDatabase.pluralKitSyncState;
  PluralKitSyncDaoManager get managers => PluralKitSyncDaoManager(this);
}

class PluralKitSyncDaoManager {
  final _$PluralKitSyncDaoMixin _db;
  PluralKitSyncDaoManager(this._db);
  $$PluralKitSyncStateTableTableManager get pluralKitSyncState =>
      $$PluralKitSyncStateTableTableManager(
        _db.attachedDatabase,
        _db.pluralKitSyncState,
      );
}
