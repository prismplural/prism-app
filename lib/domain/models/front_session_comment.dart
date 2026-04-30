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
    // target_time: the moment this comment is about. Nullable until Phase 5
    // migration backfills existing rows; downstream code falls back to
    // timestamp when targetTime is null.
    DateTime? targetTime,
    // Optional author — which member wrote this comment.
    String? authorMemberId,
    // Legacy v6 FK to fronting_sessions.id. Kept on the model so migration
    // and import code can read the legacy column for backfill until the v8
    // cleanup migration drops the column. New code uses targetTime instead.
    // Removal target: 0.8.0 (drop with the v8 TableMigration rebuild).
    String? sessionId,
  }) = _FrontSessionComment;

  factory FrontSessionComment.fromJson(Map<String, dynamic> json) =>
      _$FrontSessionCommentFromJson(json);
}
