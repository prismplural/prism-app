// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'member_board_posts_dao.dart';

// ignore_for_file: type=lint
mixin _$MemberBoardPostsDaoMixin on DatabaseAccessor<AppDatabase> {
  $MemberBoardPostsTable get memberBoardPosts =>
      attachedDatabase.memberBoardPosts;
  MemberBoardPostsDaoManager get managers => MemberBoardPostsDaoManager(this);
}

class MemberBoardPostsDaoManager {
  final _$MemberBoardPostsDaoMixin _db;
  MemberBoardPostsDaoManager(this._db);
  $$MemberBoardPostsTableTableManager get memberBoardPosts =>
      $$MemberBoardPostsTableTableManager(
        _db.attachedDatabase,
        _db.memberBoardPosts,
      );
}
