// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sp_import_dao.dart';

// ignore_for_file: type=lint
mixin _$SpImportDaoMixin on DatabaseAccessor<AppDatabase> {
  $SpSyncStateTableTable get spSyncStateTable =>
      attachedDatabase.spSyncStateTable;
  $SpIdMapTableTable get spIdMapTable => attachedDatabase.spIdMapTable;
  SpImportDaoManager get managers => SpImportDaoManager(this);
}

class SpImportDaoManager {
  final _$SpImportDaoMixin _db;
  SpImportDaoManager(this._db);
  $$SpSyncStateTableTableTableManager get spSyncStateTable =>
      $$SpSyncStateTableTableTableManager(
        _db.attachedDatabase,
        _db.spSyncStateTable,
      );
  $$SpIdMapTableTableTableManager get spIdMapTable =>
      $$SpIdMapTableTableTableManager(_db.attachedDatabase, _db.spIdMapTable);
}
