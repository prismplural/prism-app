// test/data/repositories/drift_habit_repository_update_completion_test.dart
//
// TDD coverage for DriftHabitRepository.updateHabitFields,
// DriftHabitRepository.updateCompletionFields, and
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
  late _SpyDriftHabitRepository repo;

  // A habit row is required to satisfy the FK constraint on habit_completions.
  late domain.Habit testHabit;

  final baseTime = DateTime.utc(2026, 5, 9, 12, 0);

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    dao = HabitsDao(db);
    // Null sync handle — no FFI calls are made.
    repo = _SpyDriftHabitRepository(dao);

    testHabit = domain.Habit(
      id: 'habit-1',
      name: 'Test Habit',
      createdAt: baseTime,
      modifiedAt: baseTime,
    );
    await repo.createHabit(testHabit);
    repo.clearSyncCalls();
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

  // ── updateHabitFields ────────────────────────────────────────────────────

  group('updateHabitFields (in-memory db, null sync handle)', () {
    test('writes only the specified fields, leaves others intact', () async {
      await dao.updateHabitById(
        testHabit.id,
        const HabitsCompanion(name: Value('synced-in')),
      );

      final count = await repo.updateHabitFields(testHabit.id, {
        'current_streak': 7,
      });

      expect(count, 1);

      final raw = await dao.getHabitByIdRow(testHabit.id);
      expect(raw, isNotNull);
      expect(raw!.name, 'synced-in');
      expect(raw.currentStreak, 7);
      expect(raw.totalCompletions, 0);
    });

    test('name patch preserves stats and tombstone field', () async {
      await dao.updateHabitById(
        testHabit.id,
        const HabitsCompanion(
          currentStreak: Value(4),
          bestStreak: Value(9),
          totalCompletions: Value(12),
        ),
      );

      final count = await repo.updateHabitFields(testHabit.id, {
        'name': 'Renamed',
      });

      expect(count, 1);

      final raw = await dao.getHabitByIdRow(testHabit.id);
      expect(raw, isNotNull);
      expect(raw!.name, 'Renamed');
      expect(raw.currentStreak, 4);
      expect(raw.bestStreak, 9);
      expect(raw.totalCompletions, 12);
      expect(raw.isDeleted, isFalse);
    });

    test('returns 0 when row is tombstoned', () async {
      await repo.deleteHabit(testHabit.id);

      final count = await repo.updateHabitFields(testHabit.id, {
        'current_streak': 1,
      });

      expect(count, 0);
    });

    test('returns 0 when row does not exist', () async {
      final count = await repo.updateHabitFields('missing-habit', {
        'current_streak': 1,
      });

      expect(count, 0);
    });

    test('handles null values for nullable fields', () async {
      await dao.updateHabitById(
        testHabit.id,
        const HabitsCompanion(description: Value('existing')),
      );

      final count = await repo.updateHabitFields(testHabit.id, {
        'description': null,
      });

      expect(count, 1);
      final raw = await dao.getHabitByIdRow(testHabit.id);
      expect(raw, isNotNull);
      expect(raw!.description, isNull);
    });

    test('does not resurrect a tombstoned row', () async {
      await repo.deleteHabit(testHabit.id);

      final count = await repo.updateHabitFields(testHabit.id, {
        'name': 'resurface?',
        'is_deleted': false,
      });

      expect(count, 0);
      final raw = await dao.getHabitByIdRow(testHabit.id);
      expect(raw, isNotNull);
      expect(raw!.isDeleted, isTrue);
      expect(raw.name, 'Test Habit');
    });

    test('empty or is_deleted-only patch is an active-row no-op', () async {
      expect(await repo.updateHabitFields(testHabit.id, {}), 1);
      expect(
        await repo.updateHabitFields(testHabit.id, {'is_deleted': false}),
        1,
      );

      final raw = await dao.getHabitByIdRow(testHabit.id);
      expect(raw, isNotNull);
      expect(raw!.isDeleted, isFalse);
    });
  });

  group('updateHabit', () {
    test('does not resurrect a tombstoned row', () async {
      await repo.deleteHabit(testHabit.id);

      await repo.updateHabit(testHabit.copyWith(name: 'resurface?'));

      final raw = await dao.getHabitByIdRow(testHabit.id);
      expect(raw, isNotNull);
      expect(raw!.isDeleted, isTrue);
      expect(raw.name, 'Test Habit');
    });

    test('debugHabitChangedFields strips is_deleted and unchanged fields', () {
      final updated = testHabit.copyWith(
        name: 'Renamed',
        modifiedAt: baseTime.add(const Duration(minutes: 1)),
      );

      final fields = repo.debugHabitChangedFields(testHabit, updated);

      expect(fields, containsPair('name', 'Renamed'));
      expect(fields, contains('modified_at'));
      expect(fields, isNot(contains('description')));
      expect(fields, isNot(contains('is_deleted')));
    });
  });

  // ── updateCompletionFields ────────────────────────────────────────────────

  group('updateCompletionFields (in-memory db, null sync handle)', () {
    test('writes only the specified fields, leaves others intact', () async {
      final original = makeCompletion(notes: 'hello', rating: 3);
      await repo.createCompletion(original);

      final count = await repo.updateCompletionFields(original.id, {
        'notes': 'world',
      });

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
      final count = await repo.updateCompletionFields('nonexistent-id', {
        'notes': 'ghost',
      });
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

    test('emits only sanitized changed fields', () async {
      final c = makeCompletion(notes: 'hello', rating: 3);
      await repo.createCompletion(c);
      repo.clearSyncCalls();

      final count = await repo.updateCompletionFields(c.id, {
        'notes': 'world',
        'habit_id': 'other-habit',
        'unknown_field': 'ignored',
        'is_deleted': false,
      });

      expect(count, 1);
      expect(repo.updateCalls, hasLength(1));
      expect(repo.updateCalls.single.table, 'habit_completions');
      expect(repo.updateCalls.single.entityId, c.id);
      expect(repo.updateCalls.single.fields, {'notes': 'world'});

      final raw = await dao.getCompletionByIdRow(c.id);
      expect(raw, isNotNull);
      expect(raw!.habitId, testHabit.id);
      expect(raw.isDeleted, isFalse);
      expect(raw.rating, 3);
    });

    test('is_deleted-only completion patch is an active-row no-op', () async {
      final c = makeCompletion(notes: 'hello');
      await repo.createCompletion(c);
      repo.clearSyncCalls();

      final count = await repo.updateCompletionFields(c.id, {
        'is_deleted': false,
        'habit_id': 'other-habit',
      });

      expect(count, 1);
      expect(repo.updateCalls, isEmpty);
      final raw = await dao.getCompletionByIdRow(c.id);
      expect(raw, isNotNull);
      expect(raw!.habitId, testHabit.id);
      expect(raw.isDeleted, isFalse);
      expect(raw.notes, 'hello');
    });

    test('CRITICAL: concurrent disjoint update does not clobber', () async {
      // Insert with notes='original', rating=3.
      final c = makeCompletion(notes: 'original', rating: 3);
      await repo.createCompletion(c);

      // Simulate a sync-in update: directly DAO-update notes='synced-in',
      // bypassing the repo (as the drift_sync_adapter would do).
      await dao.updateCompletionById(
        c.id,
        const HabitCompletionsCompanion(notes: Value('synced-in')),
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

  group('deleteCompletion', () {
    test('returns 1 for an active row and tombstones it', () async {
      final c = makeCompletion();
      await repo.createCompletion(c);

      final count = await repo.deleteCompletion(c.id);

      expect(count, 1);
      expect(await repo.getCompletionById(c.id), isNull);
    });

    test('returns 0 when row is already tombstoned', () async {
      final c = makeCompletion();
      await repo.createCompletion(c);
      expect(await repo.deleteCompletion(c.id), 1);

      final count = await repo.deleteCompletion(c.id);

      expect(count, 0);
    });

    test('returns 0 when row does not exist', () async {
      final count = await repo.deleteCompletion('nonexistent-id');
      expect(count, 0);
    });
  });

  group('createCompletion', () {
    test('returns 0 and skips sync when parent habit is tombstoned', () async {
      await dao.updateHabitById(
        testHabit.id,
        const HabitsCompanion(isDeleted: Value(true)),
      );

      final c = makeCompletion();
      final count = await repo.createCompletion(c);

      expect(count, 0);
      expect(await dao.getCompletionByIdRow(c.id), isNull);
      expect(repo.createCalls, isEmpty);
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

class _SpyDriftHabitRepository extends DriftHabitRepository {
  _SpyDriftHabitRepository(HabitsDao dao) : super(dao, null);

  final List<({String table, String entityId, Map<String, dynamic> fields})>
  createCalls = [];
  final List<({String table, String entityId, Map<String, dynamic> fields})>
  updateCalls = [];
  final List<({String table, String entityId})> deleteCalls = [];

  void clearSyncCalls() {
    createCalls.clear();
    updateCalls.clear();
    deleteCalls.clear();
  }

  @override
  Future<void> syncRecordCreate(
    String table,
    String entityId,
    Map<String, dynamic> fields,
  ) async {
    createCalls.add((
      table: table,
      entityId: entityId,
      fields: Map<String, dynamic>.from(fields),
    ));
  }

  @override
  Future<void> syncRecordUpdate(
    String table,
    String entityId,
    Map<String, dynamic> fields,
  ) async {
    updateCalls.add((
      table: table,
      entityId: entityId,
      fields: Map<String, dynamic>.from(fields),
    ));
  }

  @override
  Future<void> syncRecordDelete(String table, String entityId) async {
    deleteCalls.add((table: table, entityId: entityId));
  }
}
