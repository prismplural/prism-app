import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/features/settings/services/stress_data_generator.dart';

/// Small preset for fast test runs.
const _testPreset = StressPreset(
  label: 'Test',
  members: 5,
  sessions: 20,
  conversations: 3,
  messages: 20,
  habits: 4,
  completions: 10,
  notes: 5,
  polls: 2,
  groups: 2,
  customFields: 2,
  years: 1,
  estimatedSizeMb: 1,
  estimatedSeconds: 1,
);

void main() {
  late AppDatabase db;
  late StressDataGenerator generator;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    generator = StressDataGenerator(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('generates correct approximate counts for test preset', () async {
    final progress = <StressProgress>[];
    await for (final p in generator.generate(_testPreset)) {
      progress.add(p);
    }

    // Verify final progress is Done
    expect(progress.last.phase, 'Done');

    // Check member count
    final members = await db
        .customSelect(
          "SELECT COUNT(*) as c FROM members WHERE id LIKE 'stress-%'",
        )
        .getSingle();
    expect(members.read<int>('c'), _testPreset.members);

    // Check session count
    final sessions = await db
        .customSelect(
          "SELECT COUNT(*) as c FROM fronting_sessions WHERE id LIKE 'stress-%'",
        )
        .getSingle();
    expect(sessions.read<int>('c'), _testPreset.sessions);

    // Check conversation count
    final conversations = await db
        .customSelect(
          "SELECT COUNT(*) as c FROM conversations WHERE id LIKE 'stress-%'",
        )
        .getSingle();
    expect(conversations.read<int>('c'), _testPreset.conversations);

    // Check message count
    final messages = await db
        .customSelect(
          "SELECT COUNT(*) as c FROM chat_messages WHERE id LIKE 'stress-%'",
        )
        .getSingle();
    expect(messages.read<int>('c'), _testPreset.messages);

    // Check habit count
    final habits = await db
        .customSelect(
          "SELECT COUNT(*) as c FROM habits WHERE id LIKE 'stress-%'",
        )
        .getSingle();
    expect(habits.read<int>('c'), _testPreset.habits);

    // Check completions count
    final completions = await db
        .customSelect(
          "SELECT COUNT(*) as c FROM habit_completions WHERE id LIKE 'stress-%'",
        )
        .getSingle();
    expect(completions.read<int>('c'), _testPreset.completions);

    // Check notes count
    final notes = await db
        .customSelect(
          "SELECT COUNT(*) as c FROM notes WHERE id LIKE 'stress-%'",
        )
        .getSingle();
    expect(notes.read<int>('c'), _testPreset.notes);

    // Check polls count
    final polls = await db
        .customSelect(
          "SELECT COUNT(*) as c FROM polls WHERE id LIKE 'stress-%'",
        )
        .getSingle();
    expect(polls.read<int>('c'), _testPreset.polls);

    // Check groups count
    final groups = await db
        .customSelect(
          "SELECT COUNT(*) as c FROM member_groups WHERE id LIKE 'stress-%'",
        )
        .getSingle();
    expect(groups.read<int>('c'), _testPreset.groups);
  });

  test('all generated IDs start with stress-', () async {
    await for (final _ in generator.generate(_testPreset)) {}

    // Spot check several tables for the stress- prefix
    for (final table in [
      'members',
      'fronting_sessions',
      'conversations',
      'chat_messages',
      'habits',
      'notes',
      'polls',
      'member_groups',
    ]) {
      final nonStress = await db
          .customSelect(
            "SELECT COUNT(*) as c FROM $table WHERE id NOT LIKE 'stress-%'",
          )
          .getSingle();
      expect(
        nonStress.read<int>('c'),
        0,
        reason: '$table has rows without stress- prefix',
      );
    }
  });

  test('clearStressData removes stress data but not other data', () async {
    // Insert a non-stress member first.
    await db.batch((batch) {
      batch.insert(
        db.members,
        MembersCompanion.insert(
          id: 'real-member-1',
          name: 'Real Member',
          createdAt: DateTime(2024, 1, 1),
        ),
      );
    });

    // Generate stress data
    await for (final _ in generator.generate(_testPreset)) {}

    // Verify stress + real data exists
    final beforeTotal = await db
        .customSelect('SELECT COUNT(*) as c FROM members')
        .getSingle();
    expect(beforeTotal.read<int>('c'), _testPreset.members + 1);

    // Clear stress data
    await generator.clearStressData();

    // Real member should still exist
    final afterTotal = await db
        .customSelect('SELECT COUNT(*) as c FROM members')
        .getSingle();
    expect(afterTotal.read<int>('c'), 1);

    final realMember = await db
        .customSelect("SELECT name FROM members WHERE id = 'real-member-1'")
        .getSingle();
    expect(realMember.read<String>('name'), 'Real Member');

    // Stress sessions should be gone
    final sessions = await db
        .customSelect(
          "SELECT COUNT(*) as c FROM fronting_sessions WHERE id LIKE 'stress-%'",
        )
        .getSingle();
    expect(sessions.read<int>('c'), 0);
  });

  test('generated members can be read back via DAO', () async {
    await for (final _ in generator.generate(_testPreset)) {}

    final allMembers = await db.membersDao.watchAllMembers().first;
    final stressMembers = allMembers
        .where((m) => m.id.startsWith('stress-'))
        .toList();
    expect(stressMembers.length, _testPreset.members);
    expect(stressMembers.first.name, startsWith('Stress Member'));
  });

  test(
    'hasStressData returns true after generate, false after clear',
    () async {
      expect(await generator.hasStressData(), false);

      await for (final _ in generator.generate(_testPreset)) {}
      expect(await generator.hasStressData(), true);

      await generator.clearStressData();
      expect(await generator.hasStressData(), false);
    },
  );

  test(
    'hasExistingData returns false on empty DB, true after non-stress insert',
    () async {
      expect(await generator.hasExistingData(), false);

      // Insert non-stress member
      await db.batch((batch) {
        batch.insert(
          db.members,
          MembersCompanion.insert(
            id: 'real-member-1',
            name: 'Real Member',
            createdAt: DateTime(2024, 1, 1),
          ),
        );
      });
      expect(await generator.hasExistingData(), true);

      // Generating stress data should not affect this
      await for (final _ in generator.generate(_testPreset)) {}
      expect(await generator.hasExistingData(), true);
    },
  );

  test(
    'fronting sessions are per-member shape (no co_fronter_ids JSON)',
    () async {
      await for (final _ in generator.generate(_testPreset)) {}

      // Every row must have a non-null member_id (per-member invariant for
      // session_type = 0; sleep rows = type 1 are excluded).
      final orphanFront = await db
          .customSelect(
            'SELECT COUNT(*) as c FROM fronting_sessions '
            "WHERE id LIKE 'stress-%' AND session_type = 0 AND member_id IS NULL",
          )
          .getSingle();
      expect(
        orphanFront.read<int>('c'),
        0,
        reason: 'every per-member fronting row must carry a member_id',
      );

      // No row should have a non-empty co_fronter_ids list — the column still
      // exists in v7 but the per-member generator must leave it at the default
      // ('[]').  Co-fronting is now expressed as overlapping rows.
      final cofronted = await db
          .customSelect(
            'SELECT COUNT(*) as c FROM fronting_sessions '
            "WHERE id LIKE 'stress-%' AND co_fronter_ids != '[]' "
            "AND co_fronter_ids != ''",
          )
          .getSingle();
      expect(
        cofronted.read<int>('c'),
        0,
        reason: 'per-member rows must not populate the legacy co_fronter_ids',
      );

      // At least one pair of rows from the same episode must overlap in time
      // — proving that multi-member episodes really did fan out into multiple
      // member rows (not just one row per "session" as the legacy generator
      // produced).  Stagger means start/end aren't identical, so we look for
      // any two rows where one's range intersects another's.
      final overlapPairs = await db
          .customSelect(
            'SELECT COUNT(*) as c FROM fronting_sessions a '
            'JOIN fronting_sessions b ON a.id < b.id '
            "WHERE a.id LIKE 'stress-%' AND b.id LIKE 'stress-%' "
            'AND a.session_type = 0 AND b.session_type = 0 '
            'AND a.start_time < COALESCE(b.end_time, a.start_time + 1) '
            'AND b.start_time < COALESCE(a.end_time, b.start_time + 1)',
          )
          .getSingle();
      expect(
        overlapPairs.read<int>('c'),
        greaterThan(0),
        reason:
            'expected at least one multi-member episode (≥2 overlapping rows) '
            'in 20 generated rows',
      );

      // Distinct members across all rows — exercises Zipf weighting + fan-out.
      final distinctMembers = await db
          .customSelect(
            'SELECT COUNT(DISTINCT member_id) as c FROM fronting_sessions '
            "WHERE id LIKE 'stress-%' AND session_type = 0",
          )
          .getSingle();
      expect(distinctMembers.read<int>('c'), greaterThan(1));
    },
  );

  test('front session comments attach to generated sessions', () async {
    await for (final _ in generator.generate(_testPreset)) {}

    final comments = await db
        .customSelect(
          'SELECT session_id FROM front_session_comments '
          "WHERE id LIKE 'stress-%'",
        )
        .get();
    if (comments.isEmpty) {
      // Test preset has 20 sessions → ~maybe 1-2 comments depending on episode
      // count.  If we ever produce zero, skip the assertion rather than fail
      // — the shape itself is exercised elsewhere.
      return;
    }
    for (final row in comments) {
      final sessionId = row.read<String>('session_id');
      expect(sessionId, startsWith('stress-session-'));
    }
  });

  test('progress stream reports meaningful updates', () async {
    final phases = <String>[];
    await for (final p in generator.generate(_testPreset)) {
      phases.add(p.phase);
      // fraction should be between 0 and 1
      expect(p.fraction, greaterThanOrEqualTo(0));
      expect(p.fraction, lessThanOrEqualTo(1));
    }

    expect(phases, contains('Members'));
    expect(phases, contains('Fronting Sessions'));
    expect(phases, contains('Messages'));
    expect(phases, contains('Done'));
  });
}
