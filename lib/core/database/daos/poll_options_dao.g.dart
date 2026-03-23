// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'poll_options_dao.dart';

// ignore_for_file: type=lint
mixin _$PollOptionsDaoMixin on DatabaseAccessor<AppDatabase> {
  $PollOptionsTable get pollOptions => attachedDatabase.pollOptions;
  PollOptionsDaoManager get managers => PollOptionsDaoManager(this);
}

class PollOptionsDaoManager {
  final _$PollOptionsDaoMixin _db;
  PollOptionsDaoManager(this._db);
  $$PollOptionsTableTableManager get pollOptions =>
      $$PollOptionsTableTableManager(_db.attachedDatabase, _db.pollOptions);
}
