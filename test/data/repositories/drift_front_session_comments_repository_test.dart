import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/data/repositories/drift_front_session_comments_repository.dart';
import 'package:prism_plurality/data/repositories/sync_record_mixin.dart';
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

  // Item #7 of the drift-repo migration plan: patch-style updates. The
  // comments table has no `modified_at` column, so the diff for a
  // domain-edit (or a reparent) is just the column(s) whose value changed.
  group('updateComment (patch-style emission)', () {
    final baseTime = DateTime.utc(2026, 5, 1, 12);

    FrontSessionComment makeComment({
      String id = 'c1',
      String sessionId = 'session-a',
      String body = 'Original body',
      DateTime? timestamp,
      DateTime? createdAt,
    }) {
      return FrontSessionComment(
        id: id,
        sessionId: sessionId,
        body: body,
        timestamp: timestamp ?? baseTime,
        createdAt: createdAt ?? baseTime,
      );
    }

    test('emits only the changed fields', () async {
      await repo.createComment(makeComment());
      final captured = <CapturedSyncOp>[];
      SyncRecordMixin.installCaptureSinkForTesting(captured.add);
      addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

      await repo.updateComment(makeComment(body: 'Updated body'));

      expect(captured, hasLength(1));
      expect(captured.single.opType, SyncRecordOpType.update);
      expect(captured.single.table, 'front_session_comments');
      expect(captured.single.entityId, 'c1');
      expect(captured.single.fields.keys.toSet(), {'body'});
      expect(captured.single.fields['body'], 'Updated body');
      expect(captured.single.fields.containsKey('is_deleted'), isFalse);
    });

    test(
      'emits nothing when the domain object matches the stored row',
      () async {
        await repo.createComment(makeComment());
        final captured = <CapturedSyncOp>[];
        SyncRecordMixin.installCaptureSinkForTesting(captured.add);
        addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

        await repo.updateComment(makeComment());

        expect(captured, isEmpty);
      },
    );

    test('preserves untouched columns in the database', () async {
      final originalTs = baseTime;
      await repo.createComment(
        makeComment(
          sessionId: 'session-a',
          body: 'Original body',
          timestamp: originalTs,
        ),
      );

      await repo.updateComment(
        makeComment(
          sessionId: 'session-a',
          body: 'Updated body',
          timestamp: originalTs,
        ),
      );

      final row = await db.frontSessionCommentsDao.getCommentByIdRow('c1');
      expect(row, isNotNull);
      expect(row!.body, 'Updated body');
      expect(row.sessionId, 'session-a');
      expect(row.timestamp.toUtc(), originalTs);
      expect(row.createdAt.toUtc(), baseTime);
      expect(row.isDeleted, isFalse);
    });

    // The comments schema has no nullable user-editable columns, so the
    // classic "null-clearing" case from notes/friends doesn't apply.
    // Substitute a DateTime change to exercise `_partialCommentCompanion`'s
    // `parseSyncDateTime` branch (same code path that handles nullable
    // DateTimes in other repos).
    test(
      'DateTime change round-trips through parseSyncDateTime',
      () async {
        await repo.createComment(makeComment());
        final captured = <CapturedSyncOp>[];
        SyncRecordMixin.installCaptureSinkForTesting(captured.add);
        addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

        final newTs = baseTime.add(const Duration(hours: 2));
        await repo.updateComment(makeComment(timestamp: newTs));

        expect(captured, hasLength(1));
        final patch = captured.single.fields;
        expect(patch.keys.toSet(), {'timestamp'});
        expect(patch['timestamp'], isA<String>());
        expect((patch['timestamp'] as String).endsWith('Z'), isTrue);

        final row = await db.frontSessionCommentsDao.getCommentByIdRow('c1');
        expect(row!.timestamp.toUtc(), newTs);
      },
    );

    test(
      'silently no-ops on a tombstoned row (does not emit, '
      'does not resurrect)',
      () async {
        await repo.createComment(makeComment());
        await repo.deleteComment('c1');
        final captured = <CapturedSyncOp>[];
        SyncRecordMixin.installCaptureSinkForTesting(captured.add);
        addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

        await repo.updateComment(makeComment(body: 'Attempted edit'));

        expect(captured, isEmpty);
        final row = await db.frontSessionCommentsDao.getCommentByIdRow('c1');
        expect(row, isNotNull);
        expect(row!.isDeleted, isTrue);
        expect(row.body, 'Original body');
      },
    );

    test('silently no-ops when the row does not exist', () async {
      final captured = <CapturedSyncOp>[];
      SyncRecordMixin.installCaptureSinkForTesting(captured.add);
      addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

      await repo.updateComment(makeComment(id: 'missing'));

      expect(captured, isEmpty);
      final row =
          await db.frontSessionCommentsDao.getCommentByIdRow('missing');
      expect(row, isNull);
    });

    test('does not emit is_deleted in the patch', () async {
      await repo.createComment(makeComment());
      final captured = <CapturedSyncOp>[];
      SyncRecordMixin.installCaptureSinkForTesting(captured.add);
      addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

      await repo.updateComment(makeComment(body: 'Changed'));

      expect(captured, hasLength(1));
      expect(captured.single.fields.containsKey('is_deleted'), isFalse);
    });
  });

  group('reparent ops produce only session_id diff', () {
    // The comments table has no `modified_at` column. After migration each
    // reparented comment emits exactly `{session_id}` instead of the full
    // field map.
    final ts = DateTime.utc(2026, 5, 1, 12);

    test(
      'reparentComments emits only {session_id} per moved comment',
      () async {
        await repo.createComment(
          FrontSessionComment(
            id: 'move-me',
            sessionId: 'session-a',
            body: 'hello',
            timestamp: ts,
            createdAt: ts,
          ),
        );

        final captured = <CapturedSyncOp>[];
        SyncRecordMixin.installCaptureSinkForTesting(captured.add);
        addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

        await repo.reparentComments(
          fromSessionId: 'session-a',
          toSessionId: 'session-b',
        );

        final updates = captured
            .where((op) => op.opType == SyncRecordOpType.update)
            .toList();
        expect(updates, hasLength(1));
        expect(updates.single.table, 'front_session_comments');
        expect(updates.single.entityId, 'move-me');
        expect(updates.single.fields.keys.toSet(), {'session_id'});
        expect(updates.single.fields['session_id'], 'session-b');
        expect(updates.single.fields.containsKey('is_deleted'), isFalse);
      },
    );

    test(
      'reparentCommentsAtOrAfter emits {session_id} only for moved comments',
      () async {
        final split = ts;
        await repo.createComment(
          FrontSessionComment(
            id: 'before',
            sessionId: 'old',
            body: 'b',
            timestamp: split.subtract(const Duration(minutes: 1)),
            createdAt: split,
          ),
        );
        await repo.createComment(
          FrontSessionComment(
            id: 'at-split',
            sessionId: 'old',
            body: 'a',
            timestamp: split,
            createdAt: split,
          ),
        );

        final captured = <CapturedSyncOp>[];
        SyncRecordMixin.installCaptureSinkForTesting(captured.add);
        addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

        await repo.reparentCommentsAtOrAfter(
          fromSessionId: 'old',
          toSessionId: 'new',
          atOrAfter: split,
        );

        final updates = captured
            .where((op) => op.opType == SyncRecordOpType.update)
            .toList();
        expect(updates, hasLength(1));
        expect(updates.single.entityId, 'at-split');
        expect(updates.single.fields.keys.toSet(), {'session_id'});
        expect(updates.single.fields['session_id'], 'new');
      },
    );
  });
}
