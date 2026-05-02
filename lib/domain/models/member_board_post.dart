import 'package:freezed_annotation/freezed_annotation.dart';

part 'member_board_post.freezed.dart';
part 'member_board_post.g.dart';

@freezed
abstract class MemberBoardPost with _$MemberBoardPost {
  const factory MemberBoardPost({
    required String id,
    String? targetMemberId,
    String? authorId,

    /// Audience — exactly `'public'` or `'private'`.
    required String audience,

    String? title,
    required String body,
    required DateTime createdAt,

    /// User-facing post timestamp. Equals [createdAt] for native posts;
    /// equals SP `writtenAt` for SP-imported posts.
    required DateTime writtenAt,

    /// Non-null when the post has been edited at least once.
    DateTime? editedAt,

    @Default(false) bool isDeleted,
  }) = _MemberBoardPost;

  factory MemberBoardPost.fromJson(Map<String, dynamic> json) =>
      _$MemberBoardPostFromJson(json);
}
