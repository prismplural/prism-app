// test/data/repositories/drift_habit_repository_update_completion_test.dart
//
// TDD coverage for DriftHabitRepository.updateCompletionFields and
// DriftHabitRepository.getCompletionById.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/daos/habits_dao.dart';
import 'package:prism_plurality/data/repositories/drift_habit_repository.dart';
import 'package:prism_plurality/domain/models/habit.dart' as domain;
import 'package:prism_plurality/domain/models/habit_completion.dart' as domain;

void main() {
  late AppDatabase db;
  late HabitsDao dao;
  late DriftHabitRepository repo;

  // A habit row is required to satisfy the FK constraint on habit_completions.
  late domain.Habit testHabit;

  final baseTime = DateTime.utc(2026, 5, 9, 12, 0);

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    dao = HabitsDao(db);
    // Null sync handle — no FFI calls are made.
    repo = DriftHabitRepository(dao, null);

    testHabit = domain.Habit(
      id: 'habit-1',
      name: 'Test Habit',
      createdAt: baseTime,
      modifiedAt: baseTime,
    );
    await repo.createHabit(testHabit);
  });

  tearDown(() => db.close());

  // ── helpers ──────────────────────────────────────────────────────────────

  domain.HabitCompletion makeCompletion({
    String id = 'c1',
    String? notes,
    String? completedByMemberId,
    bool wasFronting = false,
    int? rating,
    DateTime? completedAt,
    DateTime? createdAt,
    DateTime? modifiedAt,
  }) {
    return domain.HabitCompletion(
      id: id,
      habitId: testHabit.id,
      completedAt: completedAt ?? baseTime,
      completedByMemberId: completedByMemberId,
      notes: notes,
      wasFronting: wasFronting,
      rating: rating,
      createdAt: createdAt ?? baseTime,
      modifiedAt: modifiedAt ?? baseTime,
    );
  }

  // ── updateCompletionFields ────────────────────────────────────────────────

  group('updateCompletionFields (in-memory db, null sync handle)', () {
    test('writes only the specified fields, leaves others intact', () async {
      final original = makeCompletion(notes: 'hello', rating: 3);
      await repo.createCompletion(original);

      final count = await repo.updateCompletionFields(original.id, {'notes': 'world'});

      expect(count, 1);

      final readBack = await repo.getCompletionById(original.id);
      expect(readBack, isNotNull);
      expect(readBack!.notes, 'world');
      // rating is unspecified in the patch — must be unchanged
      expect(readBack.rating, 3);
    });

    test('returns 0 when row is tombstoned', () async {
      final c = makeCompletion();
      await repo.createCompletion(c);
      await repo.deleteCompletion(c.id);

      final count = await repo.updateCompletionFields(c.id, {'notes': 'ghost'});
      expect(count, 0);
    });

    test('returns 0 when row does not exist', () async {
      final count = await repo.updateCompletionFields('nonexistent-id', {'notes': 'ghost'});
      expect(count, 0);
    });

    test('returns 1 with empty patch (no-op success)', () async {
      final c = makeCompletion();
      await repo.createCompletion(c);

      final count = await repo.updateCompletionFields(c.id, {});
      expect(count, 1);
    });

    test('handles null values for nullable fields (notes -> null)', () async {
      final c = makeCompletion(notes: 'hello');
      await repo.createCompletion(c);

      final count = await repo.updateCompletionFields(c.id, {'notes': null});
      expect(count, 1);

      final readBack = await repo.getCompletionById(c.id);
      expect(readBack, isNotNull);
      expect(readBack!.notes, isNull);
    });

    test('CRITICAL: concurrent disjoint update does not clobber', () async {
      // Insert with notes='original', rating=3.
      final c = makeCompletion(notes: 'original', rating: 3);
      await repo.createCompletion(c);

      // Simulate a sync-in update: directly DAO-update notes='synced-in',
      // bypassing the repo (as the drift_sync_adapter would do).
      await dao.updateCompletionById(
        c.id,
        const HabitCompletionsCompanion(
          notes: Value('synced-in'),
        ),
      );

      // User's edit: only the rating changed.
      final count = await repo.updateCompletionFields(c.id, {'rating': 5});
      expect(count, 1);

      // notes='synced-in' (preserved!), rating=5 (updated).
      final readBack = await repo.getCompletionById(c.id);
      expect(readBack, isNotNull);
      expect(readBack!.notes, 'synced-in');
      expect(readBack.rating, 5);
    });

    test('does not resurrect a tombstoned row', () async {
      final c = makeCompletion();
      await repo.createCompletion(c);
      await repo.deleteCompletion(c.id);

      // Attempt to update — should be a no-op
      await repo.updateCompletionFields(c.id, {'notes': 'resurface?'});

      // Raw DAO row should still be tombstoned
      final raw = await dao.getCompletionByIdRow(c.id);
      expect(raw, isNotNull);
      expect(raw!.isDeleted, isTrue);
    });
  });

  // ── getCompletionById ────────────────────────────────────────────────────

  group('getCompletionById', () {
    test('returns the completion when present', () async {
      final c = makeCompletion(notes: 'readable');
      await repo.createCompletion(c);
      final result = await repo.getCompletionById(c.id);
      expect(result, isNotNull);
      expect(result!.id, c.id);
      expect(result.notes, 'readable');
    });

    test('returns null when tombstoned', () async {
      final c = makeCompletion();
      await repo.createCompletion(c);
      await repo.deleteCompletion(c.id);
      final result = await repo.getCompletionById(c.id);
      expect(result, isNull);
    });

    test('returns null when not present', () async {
      final result = await repo.getCompletionById('does-not-exist');
      expect(result, isNull);
    });
  });
}
