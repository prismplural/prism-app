// test/data/repositories/drift_habit_repository_update_completion_test.dart
//
// TDD coverage for DriftHabitRepository.updateCompletion,
// DriftHabitRepository.getCompletionById, and the
// debugCompletionUpdateDiff visible-for-testing helper.

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

  // ── debugCompletionUpdateDiff ─────────────────────────────────────────────

  group('debugCompletionUpdateDiff', () {
    test('returns only changed fields between two completions', () {
      final prev = makeCompletion(notes: 'old');
      final next = makeCompletion(notes: 'new');
      final diff = repo.debugCompletionUpdateDiff(prev, next);
      expect(diff, {'notes': 'new'});
    });

    test('returns empty map for identical completions', () {
      final c = makeCompletion(notes: 'same');
      final diff = repo.debugCompletionUpdateDiff(c, c);
      expect(diff, isEmpty);
    });

    test('strips is_deleted from diff output', () {
      // _completionFields always emits is_deleted: false, so two otherwise
      // identical completions (both is_deleted false) should never include it.
      final c = makeCompletion();
      final diff = repo.debugCompletionUpdateDiff(c, c);
      expect(diff.containsKey('is_deleted'), isFalse);
    });

    test('always includes modified_at when notifier bumps it', () {
      final earlier = baseTime;
      final later = baseTime.add(const Duration(seconds: 1));
      final prev = makeCompletion(modifiedAt: earlier);
      final next = makeCompletion(modifiedAt: later);
      final diff = repo.debugCompletionUpdateDiff(prev, next);
      expect(diff.containsKey('modified_at'), isTrue);
      expect(diff['modified_at'], later.toUtc().toIso8601String());
    });

    test('catches changed timestamp (completedAt)', () {
      final prev = makeCompletion(completedAt: baseTime);
      final next = makeCompletion(
        completedAt: baseTime.add(const Duration(hours: 1)),
      );
      final diff = repo.debugCompletionUpdateDiff(prev, next);
      expect(diff.containsKey('completed_at'), isTrue);
    });

    test('catches changed member (completedByMemberId)', () {
      final prev = makeCompletion(completedByMemberId: null);
      final next = makeCompletion(completedByMemberId: 'member-42');
      final diff = repo.debugCompletionUpdateDiff(prev, next);
      expect(diff['completed_by_member_id'], 'member-42');
    });

    test('catches changed rating', () {
      final prev = makeCompletion(rating: null);
      final next = makeCompletion(rating: 4);
      final diff = repo.debugCompletionUpdateDiff(prev, next);
      expect(diff['rating'], 4);
    });

    test('catches changed wasFronting', () {
      final prev = makeCompletion(wasFronting: false);
      final next = makeCompletion(wasFronting: true);
      final diff = repo.debugCompletionUpdateDiff(prev, next);
      expect(diff['was_fronting'], isTrue);
    });

    test('catches notes set from null to value', () {
      final prev = makeCompletion(notes: null);
      final next = makeCompletion(notes: 'added');
      final diff = repo.debugCompletionUpdateDiff(prev, next);
      expect(diff['notes'], 'added');
    });

    test('catches notes set from value to null', () {
      final prev = makeCompletion(notes: 'existing');
      final next = makeCompletion(notes: null);
      final diff = repo.debugCompletionUpdateDiff(prev, next);
      expect(diff.containsKey('notes'), isTrue);
      expect(diff['notes'], isNull);
    });
  });

  // ── updateCompletion ─────────────────────────────────────────────────────

  group('updateCompletion (in-memory db, null sync handle)', () {
    test('returns 1 for an active row, persists changed columns', () async {
      final original = makeCompletion(notes: null);
      await repo.createCompletion(original);

      final updated = original.copyWith(notes: 'hello world');
      final count = await repo.updateCompletion(updated);

      expect(count, 1);

      final readBack = await repo.getCompletionById(original.id);
      expect(readBack, isNotNull);
      expect(readBack!.notes, 'hello world');
    });

    test('returns 0 when row is tombstoned', () async {
      final c = makeCompletion();
      await repo.createCompletion(c);
      await repo.deleteCompletion(c.id);

      final count = await repo.updateCompletion(c.copyWith(notes: 'ghost'));
      expect(count, 0);
    });

    test('returns 0 when row does not exist', () async {
      final ghost = makeCompletion(id: 'nonexistent-id');
      final count = await repo.updateCompletion(ghost);
      expect(count, 0);
    });

    test('does not resurrect a tombstoned row', () async {
      final c = makeCompletion();
      await repo.createCompletion(c);
      await repo.deleteCompletion(c.id);

      // Attempt to update — should be a no-op
      await repo.updateCompletion(c.copyWith(notes: 'resurface?'));

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
