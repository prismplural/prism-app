// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'fronting_sessions_dao.dart';

// ignore_for_file: type=lint
mixin _$FrontingSessionsDaoMixin on DatabaseAccessor<AppDatabase> {
  $FrontingSessionsTable get frontingSessions =>
      attachedDatabase.frontingSessions;
  FrontingSessionsDaoManager get managers => FrontingSessionsDaoManager(this);
}

class FrontingSessionsDaoManager {
  final _$FrontingSessionsDaoMixin _db;
  FrontingSessionsDaoManager(this._db);
  $$FrontingSessionsTableTableManager get frontingSessions =>
      $$FrontingSessionsTableTableManager(
        _db.attachedDatabase,
        _db.frontingSessions,
      );
}
