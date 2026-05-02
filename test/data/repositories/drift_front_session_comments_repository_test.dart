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
    required DateTime timestamp,
    DateTime? targetTime,
  }) => FrontSessionComment(
    id: id,
    body: id,
    timestamp: timestamp,
    createdAt: timestamp,
    targetTime: targetTime,
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

  test('fresh schema indexes comment target_time range queries', () async {
    await db.customSelect('SELECT 1').get();

    final indexes = await db
        .customSelect("PRAGMA index_list('front_session_comments')")
        .get();
    final names = indexes.map((row) => row.read<String>('name')).toSet();

    expect(names, contains('idx_comments_target_time'));
  });

  test('range query uses target_time and excludes null targets', () async {
    final start = DateTime.utc(2026, 4, 30, 10);
    final end = DateTime.utc(2026, 4, 30, 11);

    await repo.createComment(
      comment(
        id: 'before',
        timestamp: start.subtract(const Duration(minutes: 1)),
        targetTime: start.subtract(const Duration(minutes: 1)),
      ),
    );
    await repo.createComment(
      comment(id: 'at-start', timestamp: start, targetTime: start),
    );
    await repo.createComment(
      comment(
        id: 'inside',
        timestamp: start.add(const Duration(minutes: 15)),
        targetTime: start.add(const Duration(minutes: 15)),
      ),
    );
    await repo.createComment(
      comment(id: 'at-end', timestamp: end, targetTime: end),
    );
    await repo.createComment(
      comment(
        id: 'null-target',
        timestamp: start.add(const Duration(minutes: 5)),
      ),
    );

    final range = TimeRange(start: start, end: end);
    final comments = await repo.watchCommentsForRange(range).first;
    final count = await repo.watchCommentCountForRange(range).first;

    expect(comments.map((c) => c.id), ['at-start', 'inside']);
    expect(count, 2);
  });

  test('range query returns rows sorted by target_time ascending', () async {
    final start = DateTime.utc(2026, 4, 30, 14);
    final end = DateTime.utc(2026, 4, 30, 15);

    // Insert deliberately out of order so insertion order ≠ targetTime order.
    // The SQL ORDER BY targetTime ASC is what guarantees the result set comes
    // back sorted; without it the period detail screen would render comments
    // in whatever order the storage layer happened to return.
    await repo.createComment(comment(
      id: 'middle',
      timestamp: start.add(const Duration(minutes: 30)),
      targetTime: start.add(const Duration(minutes: 30)),
    ));
    await repo.createComment(comment(
      id: 'last',
      timestamp: start.add(const Duration(minutes: 50)),
      targetTime: start.add(const Duration(minutes: 50)),
    ));
    await repo.createComment(comment(
      id: 'first',
      timestamp: start.add(const Duration(minutes: 5)),
      targetTime: start.add(const Duration(minutes: 5)),
    ));

    final range = TimeRange(start: start, end: end);
    final comments = await repo.watchCommentsForRange(range).first;
    expect(comments.map((c) => c.id), ['first', 'middle', 'last']);
  });
}
