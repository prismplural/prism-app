// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'friends_dao.dart';

// ignore_for_file: type=lint
mixin _$FriendsDaoMixin on DatabaseAccessor<AppDatabase> {
  $FriendsTable get friends => attachedDatabase.friends;
  FriendsDaoManager get managers => FriendsDaoManager(this);
}

class FriendsDaoManager {
  final _$FriendsDaoMixin _db;
  FriendsDaoManager(this._db);
  $$FriendsTableTableManager get friends =>
      $$FriendsTableTableManager(_db.attachedDatabase, _db.friends);
}
