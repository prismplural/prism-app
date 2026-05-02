import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'package:prism_plurality/domain/models/front_session_comment.dart';
import 'package:prism_plurality/domain/utils/time_range.dart';
import 'package:prism_plurality/core/database/database_providers.dart';

/// Watches comments whose [FrontSessionComment.targetTime] falls in [range].
///
/// Comments with `targetTime == null` (pre-Phase-5 rows that haven't been
/// backfilled yet) are excluded by the SQL filter — they don't belong to any
/// time range until the migration writes a real value. After backfill every
/// row has a non-null `targetTime` and range queries are complete.
///
/// See spec §3.5 for the comment-to-timestamp anchoring rationale.
///
/// The provider takes a Flutter [DateTimeRange] for UI ergonomics and
/// converts to the domain [TimeRange] at the boundary.
final commentsForRangeProvider = StreamProvider.autoDispose
    .family<List<FrontSessionComment>, DateTimeRange>((ref, range) {
      final repo = ref.watch(frontSessionCommentsRepositoryProvider);
      return repo.watchCommentsForRange(
        TimeRange(start: range.start, end: range.end),
      );
    });

/// Watches the count of comments whose [FrontSessionComment.targetTime] falls
/// in [range].  Pre-backfill comments (null targetTime) are excluded.
final commentCountForRangeProvider = StreamProvider.autoDispose
    .family<int, DateTimeRange>((ref, range) {
      final repo = ref.watch(frontSessionCommentsRepositoryProvider);
      return repo.watchCommentCountForRange(
        TimeRange(start: range.start, end: range.end),
      );
    });

/// Comment CRUD notifier.
///
/// `createComment` now takes [targetTime] (the moment the comment is about)
/// and optional [authorMemberId].  The old `sessionId` parameter is gone —
/// comments attach to a timestamp, not a session (spec §3.5).
class CommentNotifier extends AsyncNotifier<void> {
  static const _uuid = Uuid();

  @override
  Future<void> build() async {}

  Future<void> createComment({
    required String body,
    required DateTime targetTime,
    String? authorMemberId,
  }) async {
    state = await AsyncValue.guard(() async {
      final repo = ref.read(frontSessionCommentsRepositoryProvider);
      final now = DateTime.now();
      final comment = FrontSessionComment(
        id: _uuid.v4(),
        body: body,
        // timestamp is the legacy "what time is this about" field; keep in
        // sync with targetTime for new rows so Phase 5 backfill is a no-op.
        timestamp: targetTime,
        createdAt: now,
        targetTime: targetTime,
        authorMemberId: authorMemberId,
      );
      await repo.createComment(comment);
    });
  }

  Future<void> updateComment(FrontSessionComment comment) async {
    state = await AsyncValue.guard(() async {
      final repo = ref.read(frontSessionCommentsRepositoryProvider);
      await repo.updateComment(comment);
    });
  }

  Future<void> deleteComment(String id) async {
    state = await AsyncValue.guard(() async {
      final repo = ref.read(frontSessionCommentsRepositoryProvider);
      await repo.deleteComment(id);
    });
  }
}

final commentNotifierProvider = AsyncNotifierProvider<CommentNotifier, void>(
  CommentNotifier.new,
);
