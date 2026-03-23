import 'package:freezed_annotation/freezed_annotation.dart';

part 'front_session_comment.freezed.dart';
part 'front_session_comment.g.dart';

@freezed
abstract class FrontSessionComment with _$FrontSessionComment {
  const factory FrontSessionComment({
    required String id,
    required String sessionId,
    required String body,
    required DateTime timestamp,
    required DateTime createdAt,
  }) = _FrontSessionComment;

  factory FrontSessionComment.fromJson(Map<String, dynamic> json) =>
      _$FrontSessionCommentFromJson(json);
}
