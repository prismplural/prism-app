import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/domain/models/habit.dart';
import 'package:prism_plurality/domain/models/habit_completion.dart';
import 'package:prism_plurality/domain/repositories/habit_repository.dart';
import 'package:prism_plurality/features/habits/providers/habit_providers.dart';
import 'package:prism_plurality/features/habits/views/habit_detail_screen.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';

void main() {
  final today = DateTime(2026, 4, 10);

  final sampleHabit = Habit(
    id: 'habit-1',
    name: 'Drink Water',
    icon: '💧',
    createdAt: DateTime(2026, 4, 1),
    modifiedAt: DateTime(2026, 4, 10),
    frequency: HabitFrequency.daily,
    currentStreak: 5,
    bestStreak: 12,
    totalCompletions: 47,
  );

  final todayCompletion = HabitCompletion(
    id: 'completion-1',
    habitId: 'habit-1',
    completedAt: DateTime(2026, 4, 10, 14, 30),
    createdAt: DateTime(2026, 4, 10),
    modifiedAt: DateTime(2026, 4, 10),
  );

  Widget buildSubject({
    Habit? habit,
    List<HabitCompletion> completions = const [],
    HabitStats? stats,
  }) {
    final resolvedHabit = habit ?? sampleHabit;
    final resolvedStats = stats ??
        HabitStats(
          totalCompletions: resolvedHabit.totalCompletions,
          expectedCompletions: 60,
          completionRate: 78.3,
          currentStreak: resolvedHabit.currentStreak,
          bestStreak: resolvedHabit.bestStreak,
        );

    return ProviderScope(
      overrides: [
        habitRepositoryProvider.overrideWithValue(
          _FakeHabitRepository(
            habits: [resolvedHabit],
            allCompletions: completions,
          ),
        ),
        currentDateProvider.overrideWith((ref) => today),
        allMembersProvider.overrideWith((ref) => Stream.value(const [])),
        habitStatsProvider.overrideWith(
          (ref, params) async => resolvedStats,
        ),
      ],
      child: MaterialApp(
        home: HabitDetailScreen(habitId: resolvedHabit.id),
      ),
    );
  }

  testWidgets('shows habit name in header', (tester) async {
    await tester.pumpWidget(buildSubject());
    await tester.pumpAndSettle();

    expect(find.text('Drink Water'), findsOneWidget);
  });

  // The floating complete pill's Semantics widget holds the accessibility
  // label; `enabled` flips depending on whether the habit is already
  // completed for the period.
  Finder findCompleteButtonSemantics(String label) => find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.label == label,
      );

  testWidgets('shows Complete button when not completed today',
      (tester) async {
    await tester.pumpWidget(buildSubject(completions: []));
    await tester.pumpAndSettle();

    // Floating pill copy reads 'Complete' when active.
    expect(find.text('Complete'), findsOneWidget);

    // Semantics reports enabled: true.
    final semantics = tester.widget<Semantics>(
      findCompleteButtonSemantics('Complete habit'),
    );
    expect(semantics.properties.enabled, isTrue);

    // The button lives inside a Stack overlay in the body — NOT in the
    // Scaffold's bottomNavigationBar.
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
    expect(scaffold.bottomNavigationBar, isNull);
    expect(
      find.ancestor(
        of: find.text('Complete'),
        matching: find.byType(Stack),
      ),
      findsWidgets,
    );
  });

  testWidgets('shows Completed button disabled when completed today',
      (tester) async {
    await tester.pumpWidget(
      buildSubject(completions: [todayCompletion]),
    );
    await tester.pumpAndSettle();

    // Floating pill copy reads 'Completed' when already done for the period.
    expect(find.text('Completed'), findsOneWidget);

    // Semantics reports enabled: false with the inert label.
    final semantics = tester.widget<Semantics>(
      findCompleteButtonSemantics(
        'Habit already completed for this period',
      ),
    );
    expect(semantics.properties.enabled, isFalse);

    // Still no Scaffold.bottomNavigationBar — button is the floating pill.
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
    expect(scaffold.bottomNavigationBar, isNull);
  });

  testWidgets('shows stats count and rate', (tester) async {
    await tester.pumpWidget(
      buildSubject(
        stats: const HabitStats(
          totalCompletions: 47,
          expectedCompletions: 60,
          completionRate: 78.3,
          currentStreak: 5,
          bestStreak: 12,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('47'), findsOneWidget);
    expect(find.text('78%'), findsOneWidget);
  });
}

// ── Fake repository ──────────────────────────────────────────────────────────

class _FakeHabitRepository implements HabitRepository {
  _FakeHabitRepository({
    required List<Habit> habits,
    required List<HabitCompletion> allCompletions,
  })  : _habits = List.unmodifiable(habits),
        _allCompletions = List.unmodifiable(allCompletions);

  final List<Habit> _habits;
  final List<HabitCompletion> _allCompletions;

  @override
  Future<void> createCompletion(HabitCompletion completion) async =>
      throw UnimplementedError();

  @override
  Future<void> createHabit(Habit habit) async => throw UnimplementedError();

  @override
  Future<void> deleteCompletion(String id) async => throw UnimplementedError();

  @override
  Future<void> deleteHabit(String id) async => throw UnimplementedError();

  @override
  Future<List<HabitCompletion>> getAllCompletions() async => _allCompletions;

  @override
  Future<List<Habit>> getAllHabits() async => _habits;

  @override
  Future<List<HabitCompletion>> getCompletionsForHabit(
    String habitId, {
    DateTime? since,
  }) async {
    return _allCompletions.where((c) {
      if (c.habitId != habitId) return false;
      return since == null || !c.completedAt.isBefore(since);
    }).toList();
  }

  @override
  Future<Habit?> getHabitById(String id) async {
    for (final habit in _habits) {
      if (habit.id == id) return habit;
    }
    return null;
  }

  @override
  Future<void> updateHabit(Habit habit) async => throw UnimplementedError();

  @override
  Stream<List<HabitCompletion>> watchAllCompletions() =>
      Stream.value(_allCompletions);

  @override
  Stream<List<Habit>> watchAllHabits() => Stream.value(_habits);

  @override
  Stream<List<Habit>> watchActiveHabits() =>
      Stream.value(_habits.where((h) => h.isActive).toList());

  @override
  Stream<Habit?> watchHabitById(String id) {
    for (final habit in _habits) {
      if (habit.id == id) return Stream.value(habit);
    }
    return Stream<Habit?>.value(null);
  }

  @override
  Stream<List<HabitCompletion>> watchCompletionsForDate(DateTime date) {
    final start = DateTime(date.year, date.month, date.day);
    final end = start.add(const Duration(days: 1));
    return Stream.value(
      _allCompletions.where((c) {
        return !c.completedAt.isBefore(start) && c.completedAt.isBefore(end);
      }).toList(),
    );
  }

  @override
  Stream<List<HabitCompletion>> watchCompletionsForDateRange(
    DateTime start,
    DateTime end,
  ) {
    final rangeStart = DateTime(start.year, start.month, start.day);
    final rangeEnd = DateTime(end.year, end.month, end.day)
        .add(const Duration(days: 1));
    return Stream.value(
      _allCompletions.where((c) {
        return !c.completedAt.isBefore(rangeStart) &&
            c.completedAt.isBefore(rangeEnd);
      }).toList(),
    );
  }

  @override
  Stream<List<HabitCompletion>> watchCompletionsForHabit(String habitId) =>
      Stream.value(
        _allCompletions.where((c) => c.habitId == habitId).toList(),
      );
}
