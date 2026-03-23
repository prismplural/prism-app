// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'front_session_comments_dao.dart';

// ignore_for_file: type=lint
mixin _$FrontSessionCommentsDaoMixin on DatabaseAccessor<AppDatabase> {
  $FrontSessionCommentsTable get frontSessionComments =>
      attachedDatabase.frontSessionComments;
  FrontSessionCommentsDaoManager get managers =>
      FrontSessionCommentsDaoManager(this);
}

class FrontSessionCommentsDaoManager {
  final _$FrontSessionCommentsDaoMixin _db;
  FrontSessionCommentsDaoManager(this._db);
  $$FrontSessionCommentsTableTableManager get frontSessionComments =>
      $$FrontSessionCommentsTableTableManager(
        _db.attachedDatabase,
        _db.frontSessionComments,
      );
}
