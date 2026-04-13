import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';

import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/domain/models/habit.dart';
import 'package:prism_plurality/domain/models/habit_completion.dart';
import 'package:prism_plurality/domain/repositories/habit_repository.dart';
import 'package:prism_plurality/features/habits/providers/habit_providers.dart';
import 'package:prism_plurality/features/habits/views/habits_list_screen.dart';
import 'package:prism_plurality/features/habits/widgets/today_habits_container.dart';

/// Integration tests for the habits list screen's Today Due/Complete
/// presentation.
///
/// These tests exercise the 4-way partition (due / complete / upcoming /
/// inactive), the split Due container + Complete section rendering, and
/// the real `HabitNotifier.uncompleteHabit` path through a mutable fake
/// repo.
void main() {
  final today = DateTime(2026, 4, 11);

  Habit intervalHabit({
    required String id,
    String? name,
    int intervalDays = 5,
  }) {
    return Habit(
      id: id,
      name: name ?? 'Habit $id',
      createdAt: today.subtract(const Duration(days: 30)),
      modifiedAt: today,
      frequency: HabitFrequency.interval,
      intervalDays: intervalDays,
    );
  }

  HabitCompletion completion(
    String habitId, {
    DateTime? completedAt,
    String? id,
  }) {
    final ts = completedAt ?? today.add(const Duration(hours: 9));
    return HabitCompletion(
      id: id ?? 'completion-$habitId-${ts.millisecondsSinceEpoch}',
      habitId: habitId,
      completedAt: ts,
      createdAt: ts,
      modifiedAt: ts,
    );
  }

  Widget buildApp({
    required _FakeHabitRepository repository,
    required ValueNotifier<String?> lastRoute,
  }) {
    final router = GoRouter(
      initialLocation: '/habits',
      routes: [
        GoRoute(
          path: '/habits',
          builder: (context, state) => const HabitsListScreen(),
        ),
        GoRoute(
          path: '/habits/:id',
          builder: (context, state) {
            lastRoute.value = state.uri.path;
            return const Scaffold(
              body: Center(child: Text('detail')),
            );
          },
        ),
      ],
    );

    return ProviderScope(
      overrides: [
        habitRepositoryProvider.overrideWithValue(repository),
        currentDateProvider.overrideWith((ref) => today),
      ],
      child: MaterialApp.router(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: const [Locale('en')],
        routerConfig: router,
      ),
    );
  }

  testWidgets(
    'interval habit completed manually today appears in Complete section',
    (tester) async {
      final habit = intervalHabit(id: 'h1', name: 'Water plants');
      // Interval=5, last completion yesterday, plus a completion today.
      // The habit is NOT otherwise due today; it's in Today because it
      // was manually completed. It should land in the Complete section —
      // NOT in Due, NOT in Upcoming.
      final yesterday = today.subtract(const Duration(days: 1));
      final repo = _FakeHabitRepository(
        habits: [habit],
        allCompletions: [
          completion('h1', completedAt: yesterday.add(const Duration(hours: 9))),
          completion('h1', completedAt: today.add(const Duration(hours: 8))),
        ],
      );
      addTearDown(repo.dispose);

      final lastRoute = ValueNotifier<String?>(null);
      await tester.pumpWidget(
        buildApp(repository: repo, lastRoute: lastRoute),
      );
      await tester.pumpAndSettle();

      // The TodayHabitsContainer is rendered.
      expect(find.byType(TodayHabitsContainer), findsOneWidget);
      // No Upcoming section — the habit went into Complete.
      expect(find.text('Upcoming'), findsNothing);
      // With no due habits, the Due container is in collapsed "all done"
      // mode. The Complete section header and chip render below.
      expect(find.text('all done'), findsOneWidget);
      expect(find.text('Complete'), findsOneWidget);
      expect(find.text('Water plants'), findsOneWidget);
    },
  );

  testWidgets(
    'daily habit due but not yet complete lands in the Due container',
    (tester) async {
      final habit = Habit(
        id: 'h1',
        name: 'Meditate',
        createdAt: today.subtract(const Duration(days: 7)),
        modifiedAt: today,
        frequency: HabitFrequency.daily,
      );
      final repo = _FakeHabitRepository(
        habits: [habit],
        allCompletions: const [],
      );
      addTearDown(repo.dispose);

      final lastRoute = ValueNotifier<String?>(null);
      await tester.pumpWidget(
        buildApp(repository: repo, lastRoute: lastRoute),
      );
      await tester.pumpAndSettle();

      expect(find.byType(TodayHabitsContainer), findsOneWidget);
      // Full Due container, not collapsed.
      expect(
        find.byKey(const ValueKey('today-due-full')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('today-due-collapsed')),
        findsNothing,
      );
      // No Complete section header.
      expect(find.text('Complete'), findsNothing);
      expect(find.text('Meditate'), findsOneWidget);
      // Full-state header is just "Today" — no progress counter.
      expect(find.text('Today'), findsOneWidget);
      expect(find.textContaining('/'), findsNothing);
    },
  );

  testWidgets(
    'completing the last due habit collapses Due into all-done pill',
    (tester) async {
      // Daily habit, no prior completions — starts in Due.
      final habit = Habit(
        id: 'h1',
        name: 'Meditate',
        createdAt: today.subtract(const Duration(days: 7)),
        modifiedAt: today,
        frequency: HabitFrequency.daily,
      );
      final repo = _FakeHabitRepository(
        habits: [habit],
        allCompletions: const [],
      );
      addTearDown(repo.dispose);

      final lastRoute = ValueNotifier<String?>(null);
      await tester.pumpWidget(
        buildApp(repository: repo, lastRoute: lastRoute),
      );
      await tester.pumpAndSettle();

      // Sanity: full Due container rendered.
      expect(find.byKey(const ValueKey('today-due-full')), findsOneWidget);
      expect(find.text('Complete'), findsNothing);

      // Directly mutate the repo to simulate a completion landing (without
      // going through the sheet flow, which is out-of-scope here).
      repo.addCompletion(
        completion('h1', completedAt: today.add(const Duration(hours: 9))),
      );
      await tester.pumpAndSettle();

      // Due container should be in collapsed "all done" mode now.
      expect(find.byKey(const ValueKey('today-due-collapsed')), findsOneWidget);
      expect(find.byKey(const ValueKey('today-due-full')), findsNothing);
      expect(find.text('all done'), findsOneWidget);
      // Complete section shows the now-completed habit.
      expect(find.text('Complete'), findsOneWidget);
      expect(find.text('Meditate'), findsOneWidget);
    },
  );

  testWidgets(
    'uncompleting a manually-completed interval habit moves it to Upcoming',
    (tester) async {
      // Start state: interval=5 habit with a stale yesterday completion
      // PLUS a today completion. It lives in Today's Complete section.
      // When the user uncompletes it, the partition loop must route it
      // to Upcoming — NOT to Due, NOT back to Complete.
      final habit = intervalHabit(id: 'h1', name: 'Water plants');
      final yesterday = today.subtract(const Duration(days: 1));
      final repo = _FakeHabitRepository(
        habits: [habit],
        allCompletions: [
          completion(
            'h1',
            id: 'stale',
            completedAt: yesterday.add(const Duration(hours: 9)),
          ),
          completion(
            'h1',
            id: 'today',
            completedAt: today.add(const Duration(hours: 8)),
          ),
        ],
      );
      addTearDown(repo.dispose);

      final lastRoute = ValueNotifier<String?>(null);
      await tester.pumpWidget(
        buildApp(repository: repo, lastRoute: lastRoute),
      );
      await tester.pumpAndSettle();

      // Sanity: habit starts in the Complete section (Due is collapsed).
      expect(find.byType(TodayHabitsContainer), findsOneWidget);
      expect(find.text('Complete'), findsOneWidget);
      expect(find.text('Upcoming'), findsNothing);

      // Tap the leading circle on the completed chip. This goes through
      // `TodayHabitsContainer._handleTap` → `_showCompleteSheet` →
      // `HabitNotifier.uncompleteHabit` → `repo.deleteCompletion`, which
      // mutates the fake repo's state and emits a new completion list.
      await tester.tap(find.bySemanticsLabel('Water plants, completed'));
      await tester.pumpAndSettle();

      // The today completion is gone; the stale yesterday completion
      // remains. The partition loop should now route the habit into
      // Upcoming.
      expect(find.byType(TodayHabitsContainer), findsNothing);
      expect(find.text('Complete'), findsNothing);
      expect(find.text('Upcoming'), findsOneWidget);
      expect(find.text('Water plants'), findsOneWidget);
      expect(repo.deletedCompletionIds, contains('today'));
    },
  );

  testWidgets(
    'tapping a Today container row body navigates to the habit detail route',
    (tester) async {
      final habit = intervalHabit(id: 'h1', name: 'Water plants');
      // Due today: no prior completions.
      final repo = _FakeHabitRepository(
        habits: [habit],
        allCompletions: const [],
      );
      addTearDown(repo.dispose);

      final lastRoute = ValueNotifier<String?>(null);
      await tester.pumpWidget(
        buildApp(repository: repo, lastRoute: lastRoute),
      );
      await tester.pumpAndSettle();

      expect(find.byType(TodayHabitsContainer), findsOneWidget);
      expect(find.text('Water plants'), findsOneWidget);

      await tester.tap(find.text('Water plants'));
      await tester.pumpAndSettle();

      expect(lastRoute.value, '/habits/h1');
    },
  );
}

// ── Fake repository ──────────────────────────────────────────────────────────

/// Minimal mutable fake. Tracks habits and completions in memory and emits
/// stream updates when `deleteCompletion` is called, so the real
/// `HabitNotifier.uncompleteHabit` path can be exercised end-to-end.
class _FakeHabitRepository implements HabitRepository {
  _FakeHabitRepository({
    required List<Habit> habits,
    required List<HabitCompletion> allCompletions,
  })  : _habits = List.of(habits),
        _allCompletions = List.of(allCompletions) {
    // Seed initial values so late subscribers receive the starting state.
    _allCompletionsController.add(List.unmodifiable(_allCompletions));
    _activeHabitsController.add(
      List.unmodifiable(_habits.where((h) => h.isActive)),
    );
  }

  final List<Habit> _habits;
  final List<HabitCompletion> _allCompletions;
  final List<String> deletedCompletionIds = [];

  final StreamController<List<HabitCompletion>> _allCompletionsController =
      StreamController<List<HabitCompletion>>.broadcast();
  final StreamController<List<Habit>> _activeHabitsController =
      StreamController<List<Habit>>.broadcast();

  void dispose() {
    _allCompletionsController.close();
    _activeHabitsController.close();
  }

  void _emitCompletions() {
    if (!_allCompletionsController.isClosed) {
      _allCompletionsController.add(List.unmodifiable(_allCompletions));
    }
  }

  // ── Mutations ────────────────────────────────────────────────────────────

  /// Test-only helper: directly append a completion row and emit an update,
  /// without routing through the real notifier/sheet flow.
  void addCompletion(HabitCompletion completion) {
    _allCompletions.add(completion);
    _emitCompletions();
  }

  @override
  Future<void> deleteCompletion(String id) async {
    final index = _allCompletions.indexWhere((c) => c.id == id);
    if (index == -1) return;
    _allCompletions.removeAt(index);
    deletedCompletionIds.add(id);
    _emitCompletions();
  }

  @override
  Future<void> updateHabit(Habit habit) async {
    final index = _habits.indexWhere((h) => h.id == habit.id);
    if (index == -1) {
      _habits.add(habit);
    } else {
      _habits[index] = habit;
    }
    if (!_activeHabitsController.isClosed) {
      _activeHabitsController.add(
        List.unmodifiable(_habits.where((h) => h.isActive)),
      );
    }
  }

  // ── Unused write paths ───────────────────────────────────────────────────

  @override
  Future<void> createCompletion(HabitCompletion completion) async =>
      throw UnimplementedError();

  @override
  Future<void> createHabit(Habit habit) async => throw UnimplementedError();

  @override
  Future<void> deleteHabit(String id) async => throw UnimplementedError();

  // ── Reads ────────────────────────────────────────────────────────────────

  @override
  Future<List<HabitCompletion>> getAllCompletions() async =>
      List.unmodifiable(_allCompletions);

  @override
  Future<List<Habit>> getAllHabits() async => List.unmodifiable(_habits);

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
  Stream<List<HabitCompletion>> watchAllCompletions() async* {
    yield List.unmodifiable(_allCompletions);
    yield* _allCompletionsController.stream;
  }

  @override
  Stream<List<Habit>> watchAllHabits() async* {
    yield List.unmodifiable(_habits);
    yield* _activeHabitsController.stream;
  }

  @override
  Stream<List<Habit>> watchActiveHabits() async* {
    yield List.unmodifiable(_habits.where((h) => h.isActive));
    yield* _activeHabitsController.stream;
  }

  @override
  Stream<Habit?> watchHabitById(String id) async* {
    Habit? find() {
      for (final habit in _habits) {
        if (habit.id == id) return habit;
      }
      return null;
    }
    yield find();
    yield* _activeHabitsController.stream.map((_) => find());
  }

  @override
  Stream<List<HabitCompletion>> watchCompletionsForDate(DateTime date) {
    final start = DateTime(date.year, date.month, date.day);
    final end = start.add(const Duration(days: 1));
    List<HabitCompletion> filter(List<HabitCompletion> source) {
      return source.where((c) {
        return !c.completedAt.isBefore(start) && c.completedAt.isBefore(end);
      }).toList();
    }

    // ignore: close_sinks
    final controller = StreamController<List<HabitCompletion>>();
    controller.add(filter(_allCompletions));
    final sub = _allCompletionsController.stream.listen((value) {
      controller.add(filter(value));
    });
    controller.onCancel = sub.cancel;
    return controller.stream;
  }

  @override
  Stream<List<HabitCompletion>> watchCompletionsForDateRange(
    DateTime start,
    DateTime end,
  ) {
    final rangeStart = DateTime(start.year, start.month, start.day);
    final rangeEnd = DateTime(end.year, end.month, end.day)
        .add(const Duration(days: 1));
    List<HabitCompletion> filter(List<HabitCompletion> source) {
      return source.where((c) {
        return !c.completedAt.isBefore(rangeStart) &&
            c.completedAt.isBefore(rangeEnd);
      }).toList();
    }

    // ignore: close_sinks
    final controller = StreamController<List<HabitCompletion>>();
    controller.add(filter(_allCompletions));
    final sub = _allCompletionsController.stream.listen((value) {
      controller.add(filter(value));
    });
    controller.onCancel = sub.cancel;
    return controller.stream;
  }

  @override
  Stream<List<HabitCompletion>> watchCompletionsForHabit(String habitId) {
    List<HabitCompletion> filter(List<HabitCompletion> source) =>
        source.where((c) => c.habitId == habitId).toList();
    // ignore: close_sinks
    final controller = StreamController<List<HabitCompletion>>();
    controller.add(filter(_allCompletions));
    final sub = _allCompletionsController.stream.listen((value) {
      controller.add(filter(value));
    });
    controller.onCancel = sub.cancel;
    return controller.stream;
  }
}
