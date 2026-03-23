// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sleep_sessions_dao.dart';

// ignore_for_file: type=lint
mixin _$SleepSessionsDaoMixin on DatabaseAccessor<AppDatabase> {
  $SleepSessionsTable get sleepSessions => attachedDatabase.sleepSessions;
  SleepSessionsDaoManager get managers => SleepSessionsDaoManager(this);
}

class SleepSessionsDaoManager {
  final _$SleepSessionsDaoMixin _db;
  SleepSessionsDaoManager(this._db);
  $$SleepSessionsTableTableManager get sleepSessions =>
      $$SleepSessionsTableTableManager(_db.attachedDatabase, _db.sleepSessions);
}
