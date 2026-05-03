import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'package:prism_plurality/domain/models/front_session_comment.dart';
import 'package:prism_plurality/domain/utils/time_range.dart';
import 'package:prism_plurality/core/database/database_providers.dart';

@immutable
class PeriodCommentsQuery {
  PeriodCommentsQuery({
    required Iterable<String> sessionIds,
    required this.range,
  }) : sessionIds = List.unmodifiable([...sessionIds]..sort());

  final List<String> sessionIds;
  final DateTimeRange range;

  TimeRange get timeRange => TimeRange(start: range.start, end: range.end);

  @override
  bool operator ==(Object other) {
    return other is PeriodCommentsQuery &&
        _sameIds(sessionIds, other.sessionIds) &&
        range.start == other.range.start &&
        range.end == other.range.end;
  }

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(sessionIds), range.start, range.end);

  static bool _sameIds(List<String> a, List<String> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

final commentsForSessionProvider = StreamProvider.autoDispose
    .family<List<FrontSessionComment>, String>((ref, sessionId) {
      final repo = ref.watch(frontSessionCommentsRepositoryProvider);
      return repo.watchCommentsForSession(sessionId);
    });

final commentCountForSessionProvider = StreamProvider.autoDispose
    .family<int, String>((ref, sessionId) {
      final repo = ref.watch(frontSessionCommentsRepositoryProvider);
      return repo.watchCommentCount(sessionId);
    });

final commentsForPeriodProvider = StreamProvider.autoDispose
    .family<List<FrontSessionComment>, PeriodCommentsQuery>((ref, query) {
      final repo = ref.watch(frontSessionCommentsRepositoryProvider);
      return repo.watchCommentsForPeriod(
        sessionIds: query.sessionIds,
        range: query.timeRange,
      );
    });

final commentCountForPeriodProvider = StreamProvider.autoDispose
    .family<int, PeriodCommentsQuery>((ref, query) {
      final repo = ref.watch(frontSessionCommentsRepositoryProvider);
      return repo.watchCommentCountForPeriod(
        sessionIds: query.sessionIds,
        range: query.timeRange,
      );
    });

/// Comment CRUD notifier.
class CommentNotifier extends AsyncNotifier<void> {
  static const _uuid = Uuid();

  @override
  Future<void> build() async {}

  Future<void> createComment({
    required String sessionId,
    required String body,
    required DateTime timestamp,
  }) async {
    state = await AsyncValue.guard(() async {
      if (sessionId.trim().isEmpty) {
        throw ArgumentError.value(sessionId, 'sessionId', 'must be non-empty');
      }
      final repo = ref.read(frontSessionCommentsRepositoryProvider);
      final now = DateTime.now();
      final comment = FrontSessionComment(
        id: _uuid.v4(),
        sessionId: sessionId,
        body: body,
        timestamp: timestamp,
        createdAt: now,
      );
      await repo.createComment(comment);
    });
  }

  Future<void> updateComment(FrontSessionComment comment) async {
    state = await AsyncValue.guard(() async {
      final sessionId = comment.sessionId;
      if (sessionId.trim().isEmpty) {
        throw ArgumentError.value(
          sessionId,
          'comment.sessionId',
          'must be non-empty',
        );
      }
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
