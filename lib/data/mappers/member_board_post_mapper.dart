import 'package:drift/drift.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/domain/models/member_board_post.dart';

class MemberBoardPostMapper {
  MemberBoardPostMapper._();

  static MemberBoardPost toDomain(MemberBoardPostRow row) {
    return MemberBoardPost(
      id: row.id,
      targetMemberId: row.targetMemberId,
      authorId: row.authorId,
      audience: row.audience,
      title: row.title,
      body: row.body,
      createdAt: row.createdAt,
      writtenAt: row.writtenAt,
      editedAt: row.editedAt,
      isDeleted: row.isDeleted,
    );
  }

  static MemberBoardPostsCompanion toCompanion(MemberBoardPost model) {
    return MemberBoardPostsCompanion(
      id: Value(model.id),
      targetMemberId: Value(model.targetMemberId),
      authorId: Value(model.authorId),
      audience: Value(model.audience),
      title: Value(model.title),
      body: Value(model.body),
      createdAt: Value(model.createdAt),
      writtenAt: Value(model.writtenAt),
      editedAt: Value(model.editedAt),
      isDeleted: Value(model.isDeleted),
    );
  }
}
