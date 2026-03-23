// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'polls_dao.dart';

// ignore_for_file: type=lint
mixin _$PollsDaoMixin on DatabaseAccessor<AppDatabase> {
  $PollsTable get polls => attachedDatabase.polls;
  PollsDaoManager get managers => PollsDaoManager(this);
}

class PollsDaoManager {
  final _$PollsDaoMixin _db;
  PollsDaoManager(this._db);
  $$PollsTableTableManager get polls =>
      $$PollsTableTableManager(_db.attachedDatabase, _db.polls);
}
