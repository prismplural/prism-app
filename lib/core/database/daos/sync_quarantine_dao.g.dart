// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sync_quarantine_dao.dart';

// ignore_for_file: type=lint
mixin _$SyncQuarantineDaoMixin on DatabaseAccessor<AppDatabase> {
  $SyncQuarantineTableTable get syncQuarantineTable =>
      attachedDatabase.syncQuarantineTable;
  SyncQuarantineDaoManager get managers => SyncQuarantineDaoManager(this);
}

class SyncQuarantineDaoManager {
  final _$SyncQuarantineDaoMixin _db;
  SyncQuarantineDaoManager(this._db);
  $$SyncQuarantineTableTableTableManager get syncQuarantineTable =>
      $$SyncQuarantineTableTableTableManager(
        _db.attachedDatabase,
        _db.syncQuarantineTable,
      );
}
