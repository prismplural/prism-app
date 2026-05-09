import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/domain/models/habit.dart';
import 'package:prism_plurality/domain/models/habit_completion.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/repositories/habit_repository.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_providers.dart';
import 'package:prism_plurality/features/habits/providers/habit_providers.dart';
import 'package:prism_plurality/features/habits/views/complete_habit_sheet.dart'
    show CompleteHabitSheet, CompleteHabitSheetState;
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/features/members/providers/member_groups_providers.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';

void main() {
  final sampleHabit = Habit(
    id: 'habit-1',
    name: 'Exercise',
    createdAt: DateTime(2026, 4, 1),
    modifiedAt: DateTime(2026, 4, 1),
    frequency: HabitFrequency.daily,
  );

  setUp(PrismToast.resetForTest);

  // ── Test 1: date pill shows ~24h ago when initialPastDefault=true ────────

  testWidgets(
    'open with initialPastDefault: true shows date within 5s of now-24h',
    (tester) async {
      final before = DateTime.now().subtract(const Duration(hours: 24));

      await tester.pumpWidget(
        _buildSubject(
          habit: sampleHabit,
          initialPastDefault: true,
        ),
      );
      await tester.pumpAndSettle();

      final after = DateTime.now().subtract(const Duration(hours: 24));

      // The sheet should be visible.
      expect(find.byType(CompleteHabitSheet), findsOneWidget);

      // Read the displayed date from the pill text. We check that the date
      // matches yesterday's date (the date part of now-24h).
      final expectedDate = before;
      // The pill shows month abbreviation + day (e.g. "Apr 8").
      // We verify via the state instead of UI text parsing.
      final state = tester.state<CompleteHabitSheetState>(
        find.byType(CompleteHabitSheet),
      );
      final completedAt = state.completedAt;

      expect(
        completedAt.millisecondsSinceEpoch,
        greaterThanOrEqualTo(
          expectedDate.millisecondsSinceEpoch - 5000,
        ),
      );
      expect(
        completedAt.millisecondsSinceEpoch,
        lessThanOrEqualTo(
          after.millisecondsSinceEpoch + 5000,
        ),
      );
    },
  );

  // ── Test 2: save with initialPastDefault calls completeHabit with
  //   wasFronting: false even when currentFronterProvider has a value ────────

  testWidgets(
    'save with initialPastDefault: true calls completeHabit with wasFronting: false',
    (tester) async {
      final fronterController = StreamController<Member?>.broadcast();
      final fronterMember = Member(
        id: 'member-1',
        name: 'Alex',
        isActive: true,
        createdAt: DateTime(2026, 4, 1),
      );
      fronterController.add(fronterMember);

      final spy = _SpyHabitNotifier();

      await tester.pumpWidget(
        _buildSubject(
          habit: sampleHabit,
          initialPastDefault: true,
          currentFronterStream: fronterController.stream,
          habitNotifierOverride: spy,
        ),
      );
      await tester.pumpAndSettle();

      // Tap the save check button.
      final saveButton = find.byTooltip('Save');
      expect(saveButton, findsOneWidget);
      await tester.tap(saveButton);
      // Close the stream BEFORE pumpAndSettle so Riverpod's StreamProvider
      // subscription can settle cleanly after the sheet pops.
      await fronterController.close();
      await tester.pumpAndSettle();

      expect(spy.completeHabitCalls, hasLength(1));
      expect(spy.completeHabitCalls.first.wasFronting, isFalse);
    },
  );
}

// ── Helpers ──────────────────────────────────────────────────────────────────

Widget _buildSubject({
  required Habit habit,
  bool initialPastDefault = false,
  Stream<Member?>? currentFronterStream,
  _SpyHabitNotifier? habitNotifierOverride,
}) {
  final repo = _FakeHabitRepository(
    habits: [habit],
    allCompletions: const [],
  );
  return ProviderScope(
    overrides: [
      habitRepositoryProvider.overrideWithValue(repo),
      // Always stub member + fronter + settings providers so HeadmatePicker
      // and terminology don't need real data.
      activeMembersProvider.overrideWithValue(
        const AsyncValue.data([]),
      ),
      // HeadmatePicker → watchMemberSearchGroups watches these two providers.
      // Override with empty lists to prevent Drift QueryStream timers.
      allGroupsProvider.overrideWithValue(
        const AsyncValue.data([]),
      ),
      allGroupEntriesProvider.overrideWithValue(
        const AsyncValue.data([]),
      ),
      if (currentFronterStream != null)
        currentFronterProvider.overrideWith(
          (ref) => currentFronterStream,
        )
      else
        currentFronterProvider.overrideWithValue(
          const AsyncValue.data(null),
        ),
      systemSettingsProvider.overrideWithValue(
        const AsyncValue.data(SystemSettings()),
      ),
      if (habitNotifierOverride != null)
        habitNotifierProvider.overrideWith(() => habitNotifierOverride),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('en')],
      home: Scaffold(
        body: CompleteHabitSheet(
          habit: habit,
          initialPastDefault: initialPastDefault,
        ),
      ),
    ),
  );
}

// ── Spy notifier ─────────────────────────────────────────────────────────────

class _CompleteHabitArgs {
  const _CompleteHabitArgs({
    required this.habitId,
    required this.wasFronting,
    this.completedByMemberId,
    this.notes,
    this.rating,
    this.completedAt,
  });
  final String habitId;
  final bool wasFronting;
  final String? completedByMemberId;
  final String? notes;
  final int? rating;
  final DateTime? completedAt;
}

class _SpyHabitNotifier extends HabitNotifier {
  final List<_CompleteHabitArgs> completeHabitCalls = [];
  final List<HabitCompletion> updateCompletionCalls = [];

  @override
  Future<void> completeHabit({
    required String habitId,
    String? completedByMemberId,
    String? notes,
    int? rating,
    bool wasFronting = false,
    DateTime? completedAt,
  }) async {
    completeHabitCalls.add(
      _CompleteHabitArgs(
        habitId: habitId,
        wasFronting: wasFronting,
        completedByMemberId: completedByMemberId,
        notes: notes,
        rating: rating,
        completedAt: completedAt,
      ),
    );
  }

  @override
  Future<void> updateCompletion(HabitCompletion next) async {
    updateCompletionCalls.add(next);
  }
}

// ── Fake repository ───────────────────────────────────────────────────────────

class _FakeHabitRepository implements HabitRepository {
  _FakeHabitRepository({
    required List<Habit> habits,
    required List<HabitCompletion> allCompletions,
  })  : _habits = List.unmodifiable(habits),
        _allCompletions = List.unmodifiable(allCompletions);

  final List<Habit> _habits;
  final List<HabitCompletion> _allCompletions;

  @override
  Future<void> createCompletion(HabitCompletion completion) async {}

  @override
  Future<void> createHabit(Habit habit) async =>
      throw UnimplementedError();

  @override
  Future<void> deleteCompletion(String id) async =>
      throw UnimplementedError();

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
  }) async =>
      _allCompletions.where((c) => c.habitId == habitId).toList();

  @override
  Future<Habit?> getHabitById(String id) async {
    for (final h in _habits) {
      if (h.id == id) return h;
    }
    return null;
  }

  @override
  Future<void> updateHabit(Habit habit) async {}

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
    for (final h in _habits) {
      if (h.id == id) return Stream.value(h);
    }
    return Stream<Habit?>.value(null);
  }

  @override
  Stream<List<HabitCompletion>> watchCompletionsForDate(DateTime date) =>
      Stream.value(const []);

  @override
  Stream<List<HabitCompletion>> watchCompletionsForDateRange(
    DateTime start,
    DateTime end,
  ) =>
      Stream.value(const []);

  @override
  Stream<List<HabitCompletion>> watchCompletionsForHabit(String habitId) =>
      Stream.value(const []);

  @override
  Future<HabitCompletion?> getCompletionById(String id) async => null;

  @override
  Future<int> updateCompletion(HabitCompletion completion) async => 1;
}
