import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/data/repositories/drift_front_session_comments_repository.dart';
import 'package:prism_plurality/domain/models/front_session_comment.dart';
import 'package:prism_plurality/domain/utils/time_range.dart';

void main() {
  late AppDatabase db;
  late DriftFrontSessionCommentsRepository repo;

  FrontSessionComment comment({
    required String id,
    required String sessionId,
    required DateTime timestamp,
  }) => FrontSessionComment(
    id: id,
    sessionId: sessionId,
    body: id,
    timestamp: timestamp,
    createdAt: timestamp,
  );

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = DriftFrontSessionCommentsRepository(
      db.frontSessionCommentsDao,
      null,
    );
  });

  tearDown(() async {
    await db.close();
  });

  test('fresh schema keeps only the session comment index', () async {
    await db.customSelect('SELECT 1').get();

    final indexes = await db
        .customSelect("PRAGMA index_list('front_session_comments')")
        .get();
    final names = indexes.map((row) => row.read<String>('name')).toSet();

    expect(names, contains('idx_comments_session'));
    expect(names, isNot(contains('idx_comments_target_time')));
  });

  test('session query uses session_id and excludes deleted comments', () async {
    final ts = DateTime.utc(2026, 4, 30, 10);

    await repo.createComment(
      comment(id: 'session-a-1', sessionId: 'session-a', timestamp: ts),
    );
    await repo.createComment(
      comment(id: 'session-b-1', sessionId: 'session-b', timestamp: ts),
    );
    await repo.deleteComment('session-a-1');
    await repo.createComment(
      comment(
        id: 'session-a-2',
        sessionId: 'session-a',
        timestamp: ts.add(const Duration(minutes: 1)),
      ),
    );

    final comments = await repo.watchCommentsForSession('session-a').first;
    final count = await repo.watchCommentCount('session-a').first;

    expect(comments.map((c) => c.id), ['session-a-2']);
    expect(count, 1);
  });

  test('period query filters by session membership and half-open time range',
      () async {
    final start = DateTime.utc(2026, 4, 30, 10);
    final end = DateTime.utc(2026, 4, 30, 11);

    await repo.createComment(
      comment(
        id: 'before',
        sessionId: 'session-a',
        timestamp: start.subtract(const Duration(minutes: 1)),
      ),
    );
    await repo.createComment(
      comment(id: 'at-start', sessionId: 'session-a', timestamp: start),
    );
    await repo.createComment(
      comment(
        id: 'inside',
        sessionId: 'session-b',
        timestamp: start.add(const Duration(minutes: 15)),
      ),
    );
    await repo.createComment(
      comment(id: 'wrong-session', sessionId: 'session-c', timestamp: start),
    );
    await repo.createComment(
      comment(id: 'at-end', sessionId: 'session-a', timestamp: end),
    );

    final range = TimeRange(start: start, end: end);
    final comments = await repo
        .watchCommentsForPeriod(
          sessionIds: ['session-b', 'session-a'],
          range: range,
        )
        .first;
    final count = await repo
        .watchCommentCountForPeriod(
          sessionIds: ['session-b', 'session-a'],
          range: range,
        )
        .first;

    expect(comments.map((c) => c.id), ['at-start', 'inside']);
    expect(count, 2);
  });

  test('period query handles empty session id list', () async {
    final start = DateTime.utc(2026, 4, 30, 10);
    final range = TimeRange(
      start: start,
      end: start.add(const Duration(hours: 1)),
    );

    final comments = await repo
        .watchCommentsForPeriod(sessionIds: const [], range: range)
        .first;
    final count = await repo
        .watchCommentCountForPeriod(sessionIds: const [], range: range)
        .first;

    expect(comments, isEmpty);
    expect(count, 0);
  });

  test('reparent moves active comments and emits updated session ids', () async {
    final ts = DateTime.utc(2026, 4, 30, 10);
    await repo.createComment(
      comment(id: 'move-me', sessionId: 'old-session', timestamp: ts),
    );

    await repo.reparentComments(
      fromSessionId: 'old-session',
      toSessionId: 'new-session',
    );

    final oldComments = await repo.watchCommentsForSession('old-session').first;
    final newComments = await repo.watchCommentsForSession('new-session').first;

    expect(oldComments, isEmpty);
    expect(newComments.map((c) => c.id), ['move-me']);
  });

  test('reparent at-or-after splits comments by timestamp', () async {
    final split = DateTime.utc(2026, 4, 30, 10);
    await repo.createComment(
      comment(
        id: 'before',
        sessionId: 'old-session',
        timestamp: split.subtract(const Duration(minutes: 1)),
      ),
    );
    await repo.createComment(
      comment(id: 'at-split', sessionId: 'old-session', timestamp: split),
    );
    await repo.createComment(
      comment(
        id: 'after',
        sessionId: 'old-session',
        timestamp: split.add(const Duration(minutes: 1)),
      ),
    );

    await repo.reparentCommentsAtOrAfter(
      fromSessionId: 'old-session',
      toSessionId: 'new-session',
      atOrAfter: split,
    );

    final oldComments = await repo.watchCommentsForSession('old-session').first;
    final newComments = await repo.watchCommentsForSession('new-session').first;

    expect(oldComments.map((c) => c.id), ['before']);
    expect(newComments.map((c) => c.id), ['at-split', 'after']);
  });
}
