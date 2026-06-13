// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sync_op_outbox_dao.dart';

// ignore_for_file: type=lint
mixin _$SyncOutboxDaoMixin on DatabaseAccessor<AppDatabase> {
  $SyncOpOutboxTable get syncOpOutbox => attachedDatabase.syncOpOutbox;
  SyncOutboxDaoManager get managers => SyncOutboxDaoManager(this);
}

class SyncOutboxDaoManager {
  final _$SyncOutboxDaoMixin _db;
  SyncOutboxDaoManager(this._db);
  $$SyncOpOutboxTableTableManager get syncOpOutbox =>
      $$SyncOpOutboxTableTableManager(_db.attachedDatabase, _db.syncOpOutbox);
}
