import 'package:freezed_annotation/freezed_annotation.dart';

part 'front_session_comment.freezed.dart';
part 'front_session_comment.g.dart';

@freezed
abstract class FrontSessionComment with _$FrontSessionComment {
  const factory FrontSessionComment({
    required String id,
    required String body,
    required DateTime timestamp,
    required DateTime createdAt,
    // target_time: the moment this comment is about. Nullable until the
    // app-layer migration backfills existing rows. Range queries exclude
    // null-targetTime rows by design; after backfill every row carries a
    // non-null value.
    DateTime? targetTime,
    // Optional author — which member wrote this comment.
    String? authorMemberId,
    // Legacy v6 FK to fronting_sessions.id. Kept on the model so migration
    // and import code can read the legacy column for backfill until the
    // schema cleanup drops the column. New code uses targetTime instead.
    String? sessionId,
  }) = _FrontSessionComment;

  factory FrontSessionComment.fromJson(Map<String, dynamic> json) =>
      _$FrontSessionCommentFromJson(json);
}
