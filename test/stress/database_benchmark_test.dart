import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/features/settings/services/stress_data_generator.dart';

/// Tiny preset sized for CI speed — seeds enough data to exercise query paths
/// without blowing up wall-clock time.
const _benchPreset = StressPreset(
  label: 'Benchmark',
  members: 20,
  sessions: 500,
  conversations: 10,
  messages: 1000,
  habits: 10,
  completions: 100,
  notes: 50,
  polls: 5,
  groups: 3,
  customFields: 3,
  years: 1,
  estimatedSizeMb: 5,
  estimatedSeconds: 3,
);

void main() {
  late AppDatabase db;

  setUpAll(() async {
    db = AppDatabase(NativeDatabase.memory());
    final generator = StressDataGenerator(db);
    // Consume the stream to complete generation.
    await for (final _ in generator.generate(_benchPreset)) {}
  });

  tearDownAll(() async {
    await db.close();
  });

  test('fetch all members completes quickly', () async {
    final sw = Stopwatch()..start();
    final members = await db.membersDao.getAllMembers();
    sw.stop();
    expect(members.length, greaterThanOrEqualTo(_benchPreset.members));
    // Should complete well under 1 second even on CI.
    expect(sw.elapsedMilliseconds, lessThan(1000));
  });

  test('fetch fronting sessions by date range', () async {
    final sw = Stopwatch()..start();
    final now = DateTime.now();
    final thirtyDaysAgo = now.subtract(const Duration(days: 30));
    final sessions = await db.frontingSessionsDao.getSessionsInRange(
      thirtyDaysAgo,
      now,
    );
    sw.stop();
    // Just verify it completes in a reasonable time.
    expect(sw.elapsedMilliseconds, lessThan(1000));
    // May or may not have sessions in this range depending on RNG.
    expect(sessions, isA<List>());
  });

  test('fetch messages for busiest conversation', () async {
    final sw = Stopwatch()..start();
    final messages = await db.chatMessagesDao.getMessagesForConversation(
      'stress-conv-0', // Busiest conversation (power law distribution)
      limit: 50,
    );
    sw.stop();
    expect(messages, isNotEmpty);
    expect(sw.elapsedMilliseconds, lessThan(500));
  });

  test('FTS message search', () async {
    final sw = Stopwatch()..start();
    final results = await db.chatMessagesDao.searchMessages('hello');
    sw.stop();
    // FTS should be fast regardless of dataset size.
    expect(sw.elapsedMilliseconds, lessThan(1000));
  });

  test('conversation list with ordering', () async {
    final sw = Stopwatch()..start();
    final conversations = await (db.select(db.conversations)
          ..where((c) => c.isDeleted.equals(false))
          ..orderBy([(c) => OrderingTerm.desc(c.lastActivityAt)]))
        .get();
    sw.stop();
    expect(
      conversations.length,
      greaterThanOrEqualTo(_benchPreset.conversations),
    );
    expect(sw.elapsedMilliseconds, lessThan(500));
  });

  test('habit completions per member aggregation', () async {
    final sw = Stopwatch()..start();
    final results = await db.customSelect(
      'SELECT completed_by_member_id, COUNT(*) as cnt '
      'FROM habit_completions WHERE is_deleted = 0 '
      'GROUP BY completed_by_member_id '
      'ORDER BY cnt DESC LIMIT 10',
    ).get();
    sw.stop();
    expect(results, isNotEmpty);
    expect(sw.elapsedMilliseconds, lessThan(500));
  });
}
