import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';

import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/domain/models/habit.dart';
import 'package:prism_plurality/domain/models/habit_completion.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/repositories/habit_repository.dart';
import 'package:prism_plurality/domain/models/member_group.dart';
import 'package:prism_plurality/domain/models/member_group_entry.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_providers.dart';
import 'package:prism_plurality/features/habits/providers/habit_providers.dart';
import 'package:prism_plurality/features/habits/views/complete_habit_sheet.dart';
import 'package:prism_plurality/features/habits/views/habit_detail_screen.dart';
import 'package:prism_plurality/features/members/providers/member_groups_providers.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/shared/widgets/blur_popup.dart';
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

  final sampleCompletion = HabitCompletion(
    id: 'completion-1',
    habitId: 'habit-1',
    completedAt: DateTime(2026, 4, 9, 10, 0),
    createdAt: DateTime(2026, 4, 9),
    modifiedAt: DateTime(2026, 4, 9),
  );

  Widget buildSubject({
    Habit? habit,
    List<HabitCompletion> completions = const [],
    _TrackingFakeHabitRepository? repo,
  }) {
    final resolvedHabit = habit ?? sampleHabit;
    final resolvedRepo =
        repo ??
        _TrackingFakeHabitRepository(
          habits: [resolvedHabit],
          completions: completions,
        );

    return ProviderScope(
      overrides: [
        habitRepositoryProvider.overrideWithValue(resolvedRepo),
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
        // Stub out providers that create Drift QueryStream timers so the test
        // framework does not see pending timers when the widget tree is torn down.
        // These are consumed by HeadmatePicker (inside CompleteHabitSheet).
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

  // ── 1. Long-press shows BlurPopupAnchor overlay with Edit + Delete ──────────

  Future<void> openCompletionMenuByLongPress(WidgetTester tester) async {
    await tester.longPress(find.textContaining('Yesterday'));
    await tester.pumpAndSettle();
  }

  Future<void> openCompletionMenuByButton(WidgetTester tester) async {
    await tester.tap(find.byTooltip('More options').last);
    await tester.pumpAndSettle();
  }

  testWidgets('long-press completion tile opens popup with Edit and Delete', (
    tester,
  ) async {
    await tester.pumpWidget(buildSubject(completions: [sampleCompletion]));
    await tester.pumpAndSettle();

    // Verify we have a BlurPopupAnchor wrapping the tile.
    expect(find.byType(BlurPopupAnchor), findsWidgets);

    await openCompletionMenuByLongPress(tester);

    // Popup should show Edit and Delete items.
    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
  });

  testWidgets('completion tile exposes a tappable More options fallback', (
    tester,
  ) async {
    await tester.pumpWidget(buildSubject(completions: [sampleCompletion]));
    await tester.pumpAndSettle();

    // The first More options tooltip belongs to the top bar; the second belongs
    // to the completion row action button.
    expect(find.byTooltip('More options'), findsNWidgets(2));

    await openCompletionMenuByButton(tester);

    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
  });

  // ── 2. No Dismissible on completion tiles ───────────────────────────────────

  testWidgets('completion tile has no Dismissible', (tester) async {
    await tester.pumpWidget(buildSubject(completions: [sampleCompletion]));
    await tester.pumpAndSettle();

    expect(find.byType(Dismissible), findsNothing);
  });

  // ── 3. Delete → cancel → dialog dismissed, deleteCompletion not called ──────

  testWidgets('tapping cancel on delete dialog does not delete completion', (
    tester,
  ) async {
    final repo = _TrackingFakeHabitRepository(
      habits: [sampleHabit],
      completions: [sampleCompletion],
    );

    await tester.pumpWidget(
      buildSubject(completions: [sampleCompletion], repo: repo),
    );
    await tester.pumpAndSettle();

    await openCompletionMenuByButton(tester);

    // Tap Delete item in the popup.
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    // Confirm dialog appeared with the expected title.
    expect(find.text('Delete completion?'), findsOneWidget);

    // Tap cancel button.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    // Dialog dismissed.
    expect(find.text('Delete completion?'), findsNothing);

    // deleteCompletion was not called.
    expect(repo.deletedCompletionIds, isEmpty);
  });

  // ── 4. Delete → confirm → deleteCompletion called ───────────────────────────

  testWidgets('confirming delete calls deleteCompletion', (tester) async {
    final repo = _TrackingFakeHabitRepository(
      habits: [sampleHabit],
      completions: [sampleCompletion],
    );

    await tester.pumpWidget(
      buildSubject(completions: [sampleCompletion], repo: repo),
    );
    await tester.pumpAndSettle();

    await openCompletionMenuByButton(tester);

    // Tap Delete item in the popup.
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    // Confirm the deletion.
    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();

    expect(repo.deletedCompletionIds, contains('completion-1'));
  });

  // ── 5. Edit → CompleteHabitSheet opens with existingCompletion ──────────────

  testWidgets('tapping Edit opens CompleteHabitSheet in edit mode', (
    tester,
  ) async {
    await tester.pumpWidget(buildSubject(completions: [sampleCompletion]));
    await tester.pumpAndSettle();

    await openCompletionMenuByButton(tester);

    // Tap Edit item.
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();

    // CompleteHabitSheet should be mounted in the modal route.
    expect(find.byType(CompleteHabitSheet), findsOneWidget);
    final sheet = tester.widget<CompleteHabitSheet>(
      find.byType(CompleteHabitSheet),
    );
    expect(sheet.existingCompletion, isNotNull);
    expect(sheet.existingCompletion!.id, equals('completion-1'));
  });
}

// ── Tracking fake repository ─────────────────────────────────────────────────

class _TrackingFakeHabitRepository implements HabitRepository {
  _TrackingFakeHabitRepository({
    required List<Habit> habits,
    required List<HabitCompletion> completions,
  }) : _habits = List.of(habits),
       _completions = List.of(completions);

  final List<Habit> _habits;
  final List<HabitCompletion> _completions;
  final List<String> deletedCompletionIds = [];

  @override
  Future<int> createCompletion(HabitCompletion completion) async => 1;

  @override
  Future<void> createHabit(Habit habit) async => throw UnimplementedError();

  @override
  Future<int> deleteCompletion(String id) async {
    deletedCompletionIds.add(id);
    _completions.removeWhere((c) => c.id == id);
    return 1;
  }

  @override
  Future<void> deleteHabit(String id) async => throw UnimplementedError();

  @override
  Future<List<HabitCompletion>> getAllCompletions() async => _completions;

  @override
  Future<List<Habit>> getAllHabits() async => _habits;

  @override
  Future<List<HabitCompletion>> getCompletionsForHabit(
    String habitId, {
    DateTime? since,
  }) async {
    return _completions.where((c) {
      if (c.habitId != habitId) return false;
      return since == null || !c.completedAt.isBefore(since);
    }).toList();
  }

  @override
  Future<Habit?> getHabitById(String id) async => _habits.firstWhere(
    (h) => h.id == id,
    orElse: () => throw StateError('not found'),
  );

  @override
  Future<void> updateHabit(Habit habit) async => throw UnimplementedError();

  @override
  Future<int> updateHabitFields(
    String id,
    Map<String, dynamic> changedFields,
  ) async {
    final index = _habits.indexWhere((habit) => habit.id == id);
    if (index == -1) return 0;
    final habit = _habits[index];
    _habits[index] = habit.copyWith(
      isActive: changedFields.containsKey('is_active')
          ? changedFields['is_active'] as bool
          : habit.isActive,
      modifiedAt: changedFields.containsKey('modified_at')
          ? DateTime.parse(changedFields['modified_at'] as String)
          : habit.modifiedAt,
      currentStreak: changedFields.containsKey('current_streak')
          ? changedFields['current_streak'] as int
          : habit.currentStreak,
      bestStreak: changedFields.containsKey('best_streak')
          ? changedFields['best_streak'] as int
          : habit.bestStreak,
      totalCompletions: changedFields.containsKey('total_completions')
          ? changedFields['total_completions'] as int
          : habit.totalCompletions,
    );
    return 1;
  }

  @override
  Stream<List<HabitCompletion>> watchAllCompletions() =>
      Stream.value(_completions);

  @override
  Stream<List<Habit>> watchAllHabits() => Stream.value(_habits);

  @override
  Stream<List<Habit>> watchActiveHabits() =>
      Stream.value(_habits.where((h) => h.isActive).toList());

  @override
  Stream<Habit?> watchHabitById(String id) {
    final match = _habits.where((h) => h.id == id).toList();
    return Stream.value(match.isEmpty ? null : match.first);
  }

  @override
  Stream<List<HabitCompletion>> watchCompletionsForDate(DateTime date) {
    final start = DateTime(date.year, date.month, date.day);
    final end = start.add(const Duration(days: 1));
    return Stream.value(
      _completions.where((c) {
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
    final rangeEnd = DateTime(
      end.year,
      end.month,
      end.day,
    ).add(const Duration(days: 1));
    return Stream.value(
      _completions.where((c) {
        return !c.completedAt.isBefore(rangeStart) &&
            c.completedAt.isBefore(rangeEnd);
      }).toList(),
    );
  }

  @override
  Stream<List<HabitCompletion>> watchCompletionsForHabit(String habitId) =>
      Stream.value(_completions.where((c) => c.habitId == habitId).toList());

  @override
  Future<HabitCompletion?> getCompletionById(String id) async =>
      _completions.where((c) => c.id == id).firstOrNull;

  @override
  Future<int> updateCompletionFields(
    String id,
    Map<String, dynamic> changedFields,
  ) async => 0;
}
