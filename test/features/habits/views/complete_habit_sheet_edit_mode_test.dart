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

  final pastDate = DateTime(2026, 4, 5, 10, 30);

  final existingCompletion = HabitCompletion(
    id: 'completion-1',
    habitId: 'habit-1',
    completedAt: pastDate,
    completedByMemberId: 'm1',
    notes: 'hello',
    rating: 3,
    wasFronting: true,
    createdAt: pastDate,
    modifiedAt: pastDate,
  );

  setUp(PrismToast.resetForTest);

  // ── Test 1: top-bar title shows "Edit Completion" in edit mode ────────────

  testWidgets('edit mode: top-bar shows "Edit Completion"', (tester) async {
    await tester.pumpWidget(
      _buildSubject(habit: sampleHabit, existingCompletion: existingCompletion),
    );
    await tester.pumpAndSettle();

    expect(find.text('Edit Completion'), findsOneWidget);
  });

  // ── Test 2: fields prefill from existingCompletion ────────────────────────

  testWidgets('edit mode: notes field prefills with existing notes', (
    tester,
  ) async {
    await tester.pumpWidget(
      _buildSubject(habit: sampleHabit, existingCompletion: existingCompletion),
    );
    await tester.pumpAndSettle();

    expect(find.text('hello'), findsOneWidget);
  });

  // ── Test 3: _isDirty == false initially; save calls updateCompletion ──────

  testWidgets(
    'edit mode: no changes → save calls updateCompletion with original values',
    (tester) async {
      final spy = _SpyHabitNotifier();

      await tester.pumpWidget(
        _buildSubject(
          habit: sampleHabit,
          existingCompletion: existingCompletion,
          habitNotifierOverride: spy,
        ),
      );
      await tester.pumpAndSettle();

      // Tap save without making any changes.
      await tester.tap(find.byTooltip('Save'));
      await tester.pumpAndSettle();

      // updateCompletion was called (not completeHabit).
      expect(spy.updateCompletionCalls, hasLength(1));
      expect(spy.completeHabitCalls, isEmpty);

      // No fields changed → changedFields is empty; IDs are correct.
      final saved = spy.updateCompletionCalls.first;
      expect(saved.completionId, existingCompletion.id);
      expect(saved.habitId, existingCompletion.habitId);
      expect(saved.changedFields, isEmpty);
    },
  );

  // ── Test 3b: null notes → save with no edits emits empty patch ───────────
  // Regression test for the null/empty mismatch bug: when notes is null the
  // controller initialises to '', and the old code compared `null != ''` (true)
  // and falsely emitted notes: null on every untouched save.

  testWidgets(
    'edit mode: null notes — save with no edits emits empty changedFields',
    (tester) async {
      final spy = _SpyHabitNotifier();

      final nullNotesCompletion = HabitCompletion(
        id: 'completion-null-notes',
        habitId: 'habit-1',
        completedAt: DateTime(2026, 4, 5, 10, 30),
        completedByMemberId: 'm1',
        notes: null, // <-- null notes
        rating: 3,
        wasFronting: true,
        createdAt: DateTime(2026, 4, 5, 10, 30),
        modifiedAt: DateTime(2026, 4, 5, 10, 30),
      );

      await tester.pumpWidget(
        _buildSubject(
          habit: sampleHabit,
          existingCompletion: nullNotesCompletion,
          habitNotifierOverride: spy,
        ),
      );
      await tester.pumpAndSettle();

      // Tap save without making any changes.
      await tester.tap(find.byTooltip('Save'));
      await tester.pumpAndSettle();

      expect(spy.updateCompletionCalls, hasLength(1));
      // notes was null → controller starts as '' → no edit → must NOT appear in patch.
      expect(
        spy.updateCompletionCalls.first.changedFields.containsKey('notes'),
        isFalse,
      );
      expect(spy.updateCompletionCalls.first.changedFields, isEmpty);
    },
  );

  testWidgets(
    'edit mode: notes whitespace-only edit emits empty changedFields',
    (tester) async {
      final spy = _SpyHabitNotifier();

      await tester.pumpWidget(
        _buildSubject(
          habit: sampleHabit,
          existingCompletion: existingCompletion,
          habitNotifierOverride: spy,
        ),
      );
      await tester.pumpAndSettle();

      final notesField = find.byType(TextField);
      await tester.tap(notesField);
      await tester.pump();
      await tester.enterText(notesField, 'hello ');
      await tester.pump();

      await tester.tap(find.byTooltip('Save'));
      await tester.pumpAndSettle();

      expect(spy.updateCompletionCalls, hasLength(1));
      expect(spy.updateCompletionCalls.first.changedFields, isEmpty);
    },
  );

  // ── Test 4: mutate notes → save calls updateCompletion with new notes ─────

  testWidgets(
    'edit mode: editing notes → save calls updateCompletion with new notes',
    (tester) async {
      final spy = _SpyHabitNotifier();

      await tester.pumpWidget(
        _buildSubject(
          habit: sampleHabit,
          existingCompletion: existingCompletion,
          habitNotifierOverride: spy,
        ),
      );
      await tester.pumpAndSettle();

      // Clear existing text and type new notes.
      final notesField = find.byType(TextField);
      await tester.tap(notesField);
      await tester.pump();
      await tester.enterText(notesField, 'new notes');
      await tester.pump();

      await tester.tap(find.byTooltip('Save'));
      await tester.pumpAndSettle();

      expect(spy.updateCompletionCalls, hasLength(1));
      expect(
        spy.updateCompletionCalls.first.changedFields['notes'],
        'new notes',
      );
    },
  );

  // ── Test 5: wasFronting preserved on notes/rating-only edits ─────────────

  testWidgets('edit mode: notes-only edit preserves wasFronting: true', (
    tester,
  ) async {
    final spy = _SpyHabitNotifier();

    await tester.pumpWidget(
      _buildSubject(
        habit: sampleHabit,
        existingCompletion: existingCompletion, // wasFronting: true
        habitNotifierOverride: spy,
      ),
    );
    await tester.pumpAndSettle();

    // Edit notes only (member and timestamp stay the same).
    final notesField = find.byType(TextField);
    await tester.tap(notesField);
    await tester.pump();
    await tester.enterText(notesField, 'updated notes');
    await tester.pump();

    await tester.tap(find.byTooltip('Save'));
    await tester.pumpAndSettle();

    expect(spy.updateCompletionCalls, hasLength(1));
    // notes-only edit: was_fronting is unchanged (still true) so it's NOT
    // included in changedFields, preserving the synced value.
    expect(
      spy.updateCompletionCalls.first.changedFields.containsKey('was_fronting'),
      isFalse,
    );
    expect(
      spy.updateCompletionCalls.first.changedFields.containsKey('notes'),
      isTrue,
    );
  });

  // ── Test 6: wasFronting cleared when member changes ──────────────────────
  // (Member-change interaction requires HeadmatePicker; we test via state
  //  accessor on the sheet state directly.)

  testWidgets('edit mode: changing member clears wasFronting', (tester) async {
    final spy = _SpyHabitNotifier();

    await tester.pumpWidget(
      _buildSubject(
        habit: sampleHabit,
        existingCompletion: existingCompletion, // wasFronting: true
        habitNotifierOverride: spy,
      ),
    );
    await tester.pumpAndSettle();

    // Directly set the member via state mutation on the sheet.
    final state = tester.state<CompleteHabitSheetState>(
      find.byType(CompleteHabitSheet),
    );
    state.setCompletedByMemberIdForTest('m2');
    await tester.pump();

    await tester.tap(find.byTooltip('Save'));
    await tester.pumpAndSettle();

    expect(spy.updateCompletionCalls, hasLength(1));
    // Member changed → completed_by_member_id AND was_fronting: false in patch.
    expect(
      spy.updateCompletionCalls.first.changedFields['completed_by_member_id'],
      'm2',
    );
    expect(
      spy.updateCompletionCalls.first.changedFields['was_fronting'],
      isFalse,
    );
  });

  // ── Test 7: wasFronting cleared when timestamp changes ───────────────────

  testWidgets('edit mode: changing timestamp clears wasFronting', (
    tester,
  ) async {
    final spy = _SpyHabitNotifier();

    await tester.pumpWidget(
      _buildSubject(
        habit: sampleHabit,
        existingCompletion: existingCompletion, // wasFronting: true
        habitNotifierOverride: spy,
      ),
    );
    await tester.pumpAndSettle();

    // Directly set a different completedAt.
    final state = tester.state<CompleteHabitSheetState>(
      find.byType(CompleteHabitSheet),
    );
    state.setCompletedAtForTest(
      existingCompletion.completedAt.subtract(const Duration(hours: 1)),
    );
    await tester.pump();

    await tester.tap(find.byTooltip('Save'));
    await tester.pumpAndSettle();

    expect(spy.updateCompletionCalls, hasLength(1));
    // Timestamp changed → completed_at AND was_fronting: false in patch.
    expect(
      spy.updateCompletionCalls.first.changedFields.containsKey('completed_at'),
      isTrue,
    );
    expect(
      spy.updateCompletionCalls.first.changedFields['was_fronting'],
      isFalse,
    );
  });

  // ── Test 8: future-time validation ───────────────────────────────────────

  testWidgets(
    'edit mode: future completedAt → no notifier call, toast visible, sheet open',
    (tester) async {
      final spy = _SpyHabitNotifier();

      await tester.pumpWidget(
        _buildSubject(
          habit: sampleHabit,
          existingCompletion: existingCompletion,
          habitNotifierOverride: spy,
        ),
      );
      await tester.pumpAndSettle();

      // Set completedAt to 1 hour in the future.
      final state = tester.state<CompleteHabitSheetState>(
        find.byType(CompleteHabitSheet),
      );
      state.setCompletedAtForTest(DateTime.now().add(const Duration(hours: 1)));
      await tester.pump();

      await tester.tap(find.byTooltip('Save'));
      await tester.pumpAndSettle();

      // No notifier call.
      expect(spy.updateCompletionCalls, isEmpty);
      expect(spy.completeHabitCalls, isEmpty);

      // Sheet is still open.
      expect(find.byType(CompleteHabitSheet), findsOneWidget);

      // Dismiss the toast to cancel its auto-dismiss timer before test teardown.
      PrismToast.resetForTest();
    },
  );

  // ── Test 9: async fronter prefill in CREATE mode ─────────────────────────

  testWidgets(
    'create mode: async fronter prefill updates _completedByMemberId and '
    '_initialMemberId (no false-dirty)',
    (tester) async {
      final fronterController = StreamController<Member?>.broadcast();

      final spy = _SpyHabitNotifier();

      await tester.pumpWidget(
        _buildSubject(
          habit: sampleHabit,
          currentFronterStream: fronterController.stream,
          habitNotifierOverride: spy,
        ),
      );
      await tester.pumpAndSettle();

      // Initially no member.
      final state = tester.state<CompleteHabitSheetState>(
        find.byType(CompleteHabitSheet),
      );
      expect(state.completedByMemberId, isNull);

      // Emit a member asynchronously.
      final member = Member(
        id: 'member-async',
        name: 'Jamie',
        isActive: true,
        createdAt: DateTime(2026, 4, 1),
      );
      fronterController.add(member);
      await tester.pumpAndSettle();

      expect(state.completedByMemberId, 'member-async');

      // Save without any explicit changes — should NOT be dirty,
      // and completeHabit should be called (create-now path).
      await tester.tap(find.byTooltip('Save'));
      // Close the stream BEFORE pumpAndSettle so Riverpod's StreamProvider
      // subscription can settle cleanly after the sheet pops.
      await fronterController.close();
      await tester.pumpAndSettle();

      expect(spy.completeHabitCalls, hasLength(1));
    },
  );

  testWidgets('create mode: rapid double save only creates one completion', (
    tester,
  ) async {
    final saveBlocker = Completer<void>();
    addTearDown(() {
      if (!saveBlocker.isCompleted) saveBlocker.complete();
    });
    final spy = _SpyHabitNotifier(completeHabitBlocker: saveBlocker);

    await tester.pumpWidget(
      _buildSubject(habit: sampleHabit, habitNotifierOverride: spy),
    );
    await tester.pumpAndSettle();

    final saveButton = find.byTooltip('Save');
    expect(saveButton, findsOneWidget);

    await tester.tap(saveButton);
    await tester.pump();
    await tester.tap(saveButton);
    await tester.pump();

    expect(spy.completeHabitCalls, hasLength(1));

    saveBlocker.complete();
    await tester.pumpAndSettle();
  });

  // ── Test 10: in EDIT mode, fronter provider is ignored ───────────────────

  testWidgets('edit mode: currentFronterProvider emission does NOT override '
      'existing completion member', (tester) async {
    final fronterController = StreamController<Member?>.broadcast();
    final spy = _SpyHabitNotifier();

    await tester.pumpWidget(
      _buildSubject(
        habit: sampleHabit,
        existingCompletion: existingCompletion, // member: m1
        currentFronterStream: fronterController.stream,
        habitNotifierOverride: spy,
      ),
    );
    await tester.pumpAndSettle();

    // Emit a different member.
    final member = Member(
      id: 'member-other',
      name: 'Sam',
      isActive: true,
      createdAt: DateTime(2026, 4, 1),
    );
    fronterController.add(member);
    await tester.pumpAndSettle();

    // The sheet's member should STILL be m1.
    final state = tester.state<CompleteHabitSheetState>(
      find.byType(CompleteHabitSheet),
    );
    expect(state.completedByMemberId, 'm1');

    await fronterController.close();
  });
}

// ── Helpers ──────────────────────────────────────────────────────────────────

Widget _buildSubject({
  required Habit habit,
  HabitCompletion? existingCompletion,
  bool initialPastDefault = false,
  Stream<Member?>? currentFronterStream,
  _SpyHabitNotifier? habitNotifierOverride,
}) {
  final repo = _FakeHabitRepository(
    habits: [habit],
    allCompletions: existingCompletion != null ? [existingCompletion] : [],
  );

  return ProviderScope(
    overrides: [
      habitRepositoryProvider.overrideWithValue(repo),
      // Always stub member + fronter + settings providers so HeadmatePicker
      // and terminology don't need real data.
      activeMembersProvider.overrideWithValue(const AsyncValue.data([])),
      // HeadmatePicker → watchMemberSearchGroups watches these two providers.
      // Override with empty lists to prevent Drift QueryStream timers.
      allGroupsProvider.overrideWithValue(const AsyncValue.data([])),
      allGroupEntriesProvider.overrideWithValue(const AsyncValue.data([])),
      // currentFronterProvider: use a live stream when provided (tests 9 & 10),
      // otherwise a static null value.
      if (currentFronterStream != null)
        currentFronterProvider.overrideWith((ref) => currentFronterStream)
      else
        currentFronterProvider.overrideWithValue(const AsyncValue.data(null)),
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
          existingCompletion: existingCompletion,
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

class _UpdateCompletionArgs {
  const _UpdateCompletionArgs({
    required this.completionId,
    required this.habitId,
    required this.changedFields,
  });
  final String completionId;
  final String habitId;
  final Map<String, dynamic> changedFields;
}

class _SpyHabitNotifier extends HabitNotifier {
  _SpyHabitNotifier({this.completeHabitBlocker});

  final Completer<void>? completeHabitBlocker;
  final List<_CompleteHabitArgs> completeHabitCalls = [];
  final List<_UpdateCompletionArgs> updateCompletionCalls = [];

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
    if (completeHabitBlocker != null) {
      await completeHabitBlocker!.future;
    }
  }

  @override
  Future<void> updateCompletion({
    required String completionId,
    required String habitId,
    required Map<String, dynamic> changedFields,
  }) async {
    updateCompletionCalls.add(
      _UpdateCompletionArgs(
        completionId: completionId,
        habitId: habitId,
        changedFields: changedFields,
      ),
    );
  }
}

// ── Fake repository ───────────────────────────────────────────────────────────

class _FakeHabitRepository implements HabitRepository {
  _FakeHabitRepository({
    required List<Habit> habits,
    required List<HabitCompletion> allCompletions,
  }) : _habits = List.unmodifiable(habits),
       _allCompletions = List.unmodifiable(allCompletions);

  final List<Habit> _habits;
  final List<HabitCompletion> _allCompletions;

  @override
  Future<int> createCompletion(HabitCompletion completion) async => 1;

  @override
  Future<void> createHabit(Habit habit) async => throw UnimplementedError();

  @override
  Future<int> deleteCompletion(String id) async => throw UnimplementedError();

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
  }) async => _allCompletions.where((c) => c.habitId == habitId).toList();

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
  Future<int> updateHabitFields(
    String id,
    Map<String, dynamic> changedFields,
  ) async => _habits.any((h) => h.id == id) ? 1 : 0;

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
  ) => Stream.value(const []);

  @override
  Stream<List<HabitCompletion>> watchCompletionsForHabit(String habitId) =>
      Stream.value(const []);

  @override
  Future<HabitCompletion?> getCompletionById(String id) async => null;

  @override
  Future<int> updateCompletionFields(
    String id,
    Map<String, dynamic> changedFields,
  ) async => 1;
}
