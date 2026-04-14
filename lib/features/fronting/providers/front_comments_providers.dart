import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'package:prism_plurality/domain/models/front_session_comment.dart';
import 'package:prism_plurality/core/database/database_providers.dart';

/// Watches comments for a specific session.
final sessionCommentsProvider =
    StreamProvider.autoDispose.family<List<FrontSessionComment>, String>((ref, sessionId) {
  final repo = ref.watch(frontSessionCommentsRepositoryProvider);
  return repo.watchCommentsForSession(sessionId);
});

/// Watches comment count for a specific session.
final commentCountProvider =
    StreamProvider.autoDispose.family<int, String>((ref, sessionId) {
  final repo = ref.watch(frontSessionCommentsRepositoryProvider);
  return repo.watchCommentCount(sessionId);
});

/// Comment CRUD notifier.
class CommentNotifier extends AsyncNotifier<void> {
  static const _uuid = Uuid();

  @override
  Future<void> build() async {}

  Future<void> createComment({
    required String sessionId,
    required String body,
    DateTime? timestamp,
  }) async {
    state = await AsyncValue.guard(() async {
      final repo = ref.read(frontSessionCommentsRepositoryProvider);
      final now = DateTime.now();
      final comment = FrontSessionComment(
        id: _uuid.v4(),
        sessionId: sessionId,
        body: body,
        timestamp: timestamp ?? now,
        createdAt: now,
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

final commentNotifierProvider =
    AsyncNotifierProvider<CommentNotifier, void>(CommentNotifier.new);
