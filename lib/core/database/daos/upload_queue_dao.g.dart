// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'upload_queue_dao.dart';

// ignore_for_file: type=lint
mixin _$UploadQueueDaoMixin on DatabaseAccessor<AppDatabase> {
  $UploadQueueEntriesTable get uploadQueueEntries =>
      attachedDatabase.uploadQueueEntries;
  UploadQueueDaoManager get managers => UploadQueueDaoManager(this);
}

class UploadQueueDaoManager {
  final _$UploadQueueDaoMixin _db;
  UploadQueueDaoManager(this._db);
  $$UploadQueueEntriesTableTableManager get uploadQueueEntries =>
      $$UploadQueueEntriesTableTableManager(
        _db.attachedDatabase,
        _db.uploadQueueEntries,
      );
}
