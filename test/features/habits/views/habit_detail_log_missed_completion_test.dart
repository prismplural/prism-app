import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';

import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/domain/models/habit.dart';
import 'package:prism_plurality/domain/models/habit_completion.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/models/member_group.dart';
import 'package:prism_plurality/domain/models/member_group_entry.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/domain/repositories/habit_repository.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_providers.dart';
import 'package:prism_plurality/features/habits/providers/habit_providers.dart';
import 'package:prism_plurality/features/habits/views/complete_habit_sheet.dart';
import 'package:prism_plurality/features/habits/views/habit_detail_screen.dart';
import 'package:prism_plurality/features/members/providers/member_groups_providers.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';

void main() {
  // PrismToast uses a Timer internally; reset it so the test framework does not
  // flag pending timers when the widget tree is torn down after each test.
  tearDown(PrismToast.resetForTest);

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

  Widget buildSubject({Habit? habit}) {
    final resolvedHabit = habit ?? sampleHabit;

    return ProviderScope(
      overrides: [
        habitRepositoryProvider.overrideWithValue(
          _SimpleFakeHabitRepository(habits: [resolvedHabit]),
        ),
        currentDateProvider.overrideWith((ref) => today),
        allMembersProvider.overrideWith((ref) => Stream.value(const [])),
        currentFronterProvider.overrideWith(
          (ref) => Stream<Member?>.value(null),
        ),
        habitStatsProvider.overrideWith(
          (ref, params) async => const HabitStats(
            totalCompletions: 47,
            expectedCompletions: 60,
            completionRate: 78.3,
            currentStreak: 5,
            bestStreak: 12,
          ),
        ),
        // Stub out Drift-backed providers so the test framework does not see
        // pending timers when the widget tree is torn down. These are consumed
        // by HeadmatePicker (inside CompleteHabitSheet).
        activeMembersProvider.overrideWithValue(const AsyncValue.data([])),
        allGroupsProvider.overrideWithValue(
          const AsyncValue.data(<MemberGroup>[]),
        ),
        allGroupEntriesProvider.overrideWithValue(
          const AsyncValue.data(<MemberGroupEntry>[]),
        ),
        systemSettingsProvider.overrideWithValue(
          const AsyncValue.data(SystemSettings()),
        ),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: const [Locale('en')],
        home: HabitDetailScreen(habitId: resolvedHabit.id),
      ),
    );
  }

  // ── 1. Top-bar overflow menu item order ─────────────────────────────────────

  testWidgets('top-bar overflow menu contains items in expected order',
      (tester) async {
    await tester.pumpWidget(buildSubject());
    await tester.pumpAndSettle();

    // Tap the overflow icon button (tooltip: "More options").
    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();

    // All four items visible.
    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Deactivate'), findsOneWidget);
    expect(find.text('Log missed completion'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);

    // Order: Edit comes before Deactivate, Deactivate before Log, Log before Delete.
    final editPos = tester.getTopLeft(find.text('Edit')).dy;
    final togglePos = tester.getTopLeft(find.text('Deactivate')).dy;
    final logPos = tester.getTopLeft(find.text('Log missed completion')).dy;
    final deletePos = tester.getTopLeft(find.text('Delete')).dy;

    expect(editPos, lessThan(togglePos));
    expect(togglePos, lessThan(logPos));
    expect(logPos, lessThan(deletePos));
  });

  // ── 2. "Log missed completion" opens CompleteHabitSheet with past date ──────

  testWidgets(
      'Log missed completion opens CompleteHabitSheet with date ~24h before now',
      (tester) async {
    await tester.pumpWidget(buildSubject());
    await tester.pumpAndSettle();

    // Open overflow menu.
    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();

    // Tap "Log missed completion".
    await tester.tap(find.text('Log missed completion'));
    await tester.pumpAndSettle();

    // CompleteHabitSheet should be mounted.
    expect(find.byType(CompleteHabitSheet), findsOneWidget);

    // The sheet must have initialPastDefault == true.
    final sheet =
        tester.widget<CompleteHabitSheet>(find.byType(CompleteHabitSheet));
    expect(sheet.initialPastDefault, isTrue);
    expect(sheet.existingCompletion, isNull);

    // Via the @visibleForTesting accessor, the completedAt should be ~24h ago.
    final state = tester.state<CompleteHabitSheetState>(
      find.byType(CompleteHabitSheet),
    );
    final now = DateTime.now();
    final expected = now.subtract(const Duration(hours: 24));
    expect(
      state.completedAt.difference(expected).abs(),
      lessThan(const Duration(seconds: 10)),
    );
  });
}

// ── Simple fake repository ────────────────────────────────────────────────────

class _SimpleFakeHabitRepository implements HabitRepository {
  _SimpleFakeHabitRepository({required List<Habit> habits})
      : _habits = List.unmodifiable(habits);

  final List<Habit> _habits;

  @override
  Future<void> createCompletion(HabitCompletion completion) async {}

  @override
  Future<void> createHabit(Habit habit) async => throw UnimplementedError();

  @override
  Future<void> deleteCompletion(String id) async {}

  @override
  Future<void> deleteHabit(String id) async => throw UnimplementedError();

  @override
  Future<List<HabitCompletion>> getAllCompletions() async => [];

  @override
  Future<List<Habit>> getAllHabits() async => _habits;

  @override
  Future<List<HabitCompletion>> getCompletionsForHabit(
    String habitId, {
    DateTime? since,
  }) async =>
      [];

  @override
  Future<Habit?> getHabitById(String id) async =>
      _habits.where((h) => h.id == id).firstOrNull;

  @override
  Future<void> updateHabit(Habit habit) async => throw UnimplementedError();

  @override
  Stream<List<HabitCompletion>> watchAllCompletions() => Stream.value([]);

  @override
  Stream<List<Habit>> watchAllHabits() => Stream.value(_habits);

  @override
  Stream<List<Habit>> watchActiveHabits() =>
      Stream.value(_habits.where((h) => h.isActive).toList());

  @override
  Stream<Habit?> watchHabitById(String id) =>
      Stream.value(_habits.where((h) => h.id == id).firstOrNull);

  @override
  Stream<List<HabitCompletion>> watchCompletionsForDate(DateTime date) =>
      Stream.value([]);

  @override
  Stream<List<HabitCompletion>> watchCompletionsForDateRange(
    DateTime start,
    DateTime end,
  ) =>
      Stream.value([]);

  @override
  Stream<List<HabitCompletion>> watchCompletionsForHabit(String habitId) =>
      Stream.value([]);

  @override
  Future<HabitCompletion?> getCompletionById(String id) async => null;

  @override
  Future<int> updateCompletion(HabitCompletion completion) async => 0;
}
