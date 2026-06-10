// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'missing_media_dao.dart';

// ignore_for_file: type=lint
mixin _$MissingMediaDaoMixin on DatabaseAccessor<AppDatabase> {
  $MissingMediaEntriesTable get missingMediaEntries =>
      attachedDatabase.missingMediaEntries;
  MissingMediaDaoManager get managers => MissingMediaDaoManager(this);
}

class MissingMediaDaoManager {
  final _$MissingMediaDaoMixin _db;
  MissingMediaDaoManager(this._db);
  $$MissingMediaEntriesTableTableManager get missingMediaEntries =>
      $$MissingMediaEntriesTableTableManager(
        _db.attachedDatabase,
        _db.missingMediaEntries,
      );
}
