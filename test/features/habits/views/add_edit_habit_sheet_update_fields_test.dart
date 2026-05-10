import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:prism_plurality/domain/models/habit.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/models/member_group.dart';
import 'package:prism_plurality/domain/models/member_group_entry.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/features/habits/providers/habit_providers.dart';
import 'package:prism_plurality/features/habits/views/add_edit_habit_sheet.dart';
import 'package:prism_plurality/features/members/providers/member_groups_providers.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';

void main() {
  testWidgets('edit mode sends only changed habit fields', (tester) async {
    final habit = Habit(
      id: 'habit-1',
      name: 'Read',
      description: 'Existing description',
      icon: '📚',
      colorHex: '#123456',
      createdAt: DateTime(2026, 5, 1, 12),
      modifiedAt: DateTime(2026, 5, 1, 12),
      frequency: HabitFrequency.daily,
      notificationsEnabled: true,
      reminderTime: '09:00',
      notificationMessage: 'Read now',
      currentStreak: 4,
      bestStreak: 9,
      totalCompletions: 12,
    );
    final spy = _SpyHabitNotifier();

    await tester.pumpWidget(_buildSubject(habit: habit, notifier: spy));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open habit sheet'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'Read more');
    await tester.pump();

    await tester.tap(find.byTooltip('Save'));
    await tester.pumpAndSettle();

    expect(spy.updateHabitFieldsCalls, hasLength(1));
    final call = spy.updateHabitFieldsCalls.single;
    expect(call.habitId, habit.id);
    expect(call.changedFields, {'name': 'Read more'});
    expect(spy.updateHabitCalls, isEmpty);
    expect(spy.createHabitCalls, isEmpty);
  });

  testWidgets('color picker keeps vertical swatch spacing in angular mode', (
    tester,
  ) async {
    final habit = Habit(
      id: 'habit-1',
      name: 'Read',
      createdAt: DateTime(2026, 5, 1, 12),
      modifiedAt: DateTime(2026, 5, 1, 12),
      frequency: HabitFrequency.daily,
    );

    await tester.pumpWidget(
      _buildSubject(
        habit: habit,
        notifier: _SpyHabitNotifier(),
        shapes: PrismShapes.angular,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open habit sheet'));
    await tester.pumpAndSettle();

    final colorWraps = tester
        .widgetList<Wrap>(find.byType(Wrap))
        .where((wrap) => wrap.spacing == 8 && wrap.children.length == 8);

    expect(colorWraps, isNotEmpty);
    expect(colorWraps.first.runSpacing, 8);
  });
}

Widget _buildSubject({
  required Habit habit,
  required _SpyHabitNotifier notifier,
  PrismShapes shapes = PrismShapes.rounded,
}) {
  return ProviderScope(
    overrides: [
      allMembersProvider.overrideWith((ref) => Stream<List<Member>>.value([])),
      allGroupsProvider.overrideWithValue(
        const AsyncValue.data(<MemberGroup>[]),
      ),
      allGroupEntriesProvider.overrideWithValue(
        const AsyncValue.data(<MemberGroupEntry>[]),
      ),
      systemSettingsProvider.overrideWithValue(
        const AsyncValue.data(SystemSettings()),
      ),
      habitNotifierProvider.overrideWith(() => notifier),
    ],
    child: MaterialApp.router(
      theme: ThemeData(extensions: [shapes]),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('en')],
      routerConfig: GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => Scaffold(
              body: TextButton(
                onPressed: () => context.push('/sheet'),
                child: const Text('Open habit sheet'),
              ),
            ),
          ),
          GoRoute(
            path: '/sheet',
            builder: (context, state) => Scaffold(
              body: AddEditHabitSheet(
                existingHabit: habit,
                scrollController: ScrollController(),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _SpyHabitNotifier extends HabitNotifier {
  final List<Habit> createHabitCalls = [];
  final List<Habit> updateHabitCalls = [];
  final List<({String habitId, Map<String, dynamic> changedFields})>
  updateHabitFieldsCalls = [];

  @override
  Future<void> createHabit(Habit habit) async {
    createHabitCalls.add(habit);
  }

  @override
  Future<void> updateHabit(Habit habit) async {
    updateHabitCalls.add(habit);
  }

  @override
  Future<void> updateHabitFields({
    required String habitId,
    required Map<String, dynamic> changedFields,
  }) async {
    updateHabitFieldsCalls.add((
      habitId: habitId,
      changedFields: Map<String, dynamic>.from(changedFields),
    ));
  }
}
