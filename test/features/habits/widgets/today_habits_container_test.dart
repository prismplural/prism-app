import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';

import 'package:prism_plurality/domain/models/habit.dart';
import 'package:prism_plurality/domain/models/habit_completion.dart';
import 'package:prism_plurality/features/habits/widgets/habit_chip.dart';
import 'package:prism_plurality/features/habits/widgets/today_habits_container.dart';
import 'package:prism_plurality/shared/providers/visual_effects_provider.dart';

void main() {
  final baseDate = DateTime(2026, 4, 11);

  Habit habit({
    required String id,
    String? name,
    String? icon,
    String? colorHex,
    HabitFrequency frequency = HabitFrequency.daily,
    int streak = 0,
  }) {
    return Habit(
      id: id,
      name: name ?? 'Habit $id',
      icon: icon,
      colorHex: colorHex,
      createdAt: baseDate,
      modifiedAt: baseDate,
      frequency: frequency,
      currentStreak: streak,
    );
  }

  HabitCompletion completion(
    String habitId, {
    DateTime? completedAt,
  }) {
    final ts = completedAt ?? baseDate.add(const Duration(hours: 9));
    return HabitCompletion(
      id: 'completion-$habitId-${ts.millisecondsSinceEpoch}',
      habitId: habitId,
      completedAt: ts,
      createdAt: ts,
      modifiedAt: ts,
    );
  }

  Widget buildScope({
    required List<Habit> due,
    required List<Habit> complete,
    List<HabitCompletion>? todayCompletions,
    Map<String, List<HabitCompletion>>? weeklyByHabit,
    void Function(Habit)? onTap,
    Future<void> Function(Habit)? onQuickComplete,
    VisualEffectsMode? visualEffectsMode,
  }) {
    // Default today completions: one row per habit in `complete`.
    final effectiveCompletions = todayCompletions ??
        [for (final h in complete) completion(h.id)];
    return ProviderScope(
      overrides: [
        if (visualEffectsMode != null)
          visualEffectsPreferenceProvider.overrideWith(
            () => _StaticVisualEffectsNotifier(visualEffectsMode),
          ),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: const [Locale('en')],
        home: Scaffold(
          body: CustomScrollView(
            slivers: [
              TodayHabitsContainer(
                due: due,
                complete: complete,
                todayCompletions: effectiveCompletions,
                weeklyByHabit: weeklyByHabit ?? const {},
                onTap: onTap ?? (_) {},
                onQuickComplete:
                    onQuickComplete ?? (_) async => Future<void>.value(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Finder findSemanticsWidget(String label) => find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.label == label,
      );

  testWidgets(
    'Due container renders due habits as chips with centered Today header',
    (tester) async {
      await tester.pumpWidget(
        buildScope(
          due: [
            habit(id: '1', name: 'Meditate'),
            habit(id: '2', name: 'Stretch'),
          ],
          complete: const [],
        ),
      );
      await tester.pumpAndSettle();

      // Header is just the word 'Today' — no middot, no N / M, no dots.
      expect(find.text('Today'), findsOneWidget);
      expect(find.text('·'), findsNothing);
      expect(find.textContaining('/'), findsNothing);

      // Both due chips are rendered.
      expect(find.byType(HabitChip), findsNWidgets(2));
      expect(find.text('Meditate'), findsOneWidget);
      expect(find.text('Stretch'), findsOneWidget);

      // The "Complete" section header is NOT rendered — no completed habits.
      expect(find.text('Complete'), findsNothing);
    },
  );

  testWidgets(
    'Complete section renders completed habits below Due container',
    (tester) async {
      await tester.pumpWidget(
        buildScope(
          due: [habit(id: '1', name: 'Meditate')],
          complete: [habit(id: '2', name: 'Walk dog')],
        ),
      );
      await tester.pumpAndSettle();

      // Full Due container present.
      expect(find.byKey(const Key('today-due-container')), findsOneWidget);
      expect(find.text('Meditate'), findsOneWidget);

      // Complete section header + chip present.
      expect(find.text('Complete'), findsOneWidget);
      expect(find.text('Walk dog'), findsOneWidget);
      expect(find.byType(HabitChip), findsNWidgets(2));

      // Visual top-to-bottom ordering: Due container above Complete section.
      final meditateY = tester.getCenter(find.text('Meditate')).dy;
      final walkY = tester.getCenter(find.text('Walk dog')).dy;
      expect(meditateY, lessThan(walkY));

      // No N / M progress text in the full-state header.
      expect(find.textContaining('/'), findsNothing);
    },
  );

  testWidgets(
    'collapsed all-done mode renders when due is empty and complete is non-empty',
    (tester) async {
      await tester.pumpWidget(
        buildScope(
          due: const [],
          complete: [
            habit(id: '1', name: 'Meditate'),
            habit(id: '2', name: 'Walk dog'),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // The collapsed pill is the active child of the AnimatedSwitcher.
      expect(
        find.byKey(const ValueKey('today-due-collapsed')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('today-due-full')),
        findsNothing,
      );

      // Copy check.
      expect(find.text('all done'), findsOneWidget);
      expect(find.text('Today'), findsOneWidget);
      // No '0 / N' progress text in collapsed mode.
      expect(find.text('0 / 2'), findsNothing);

      // Complete section is still rendered below.
      expect(find.text('Complete'), findsOneWidget);
      expect(find.text('Meditate'), findsOneWidget);
      expect(find.text('Walk dog'), findsOneWidget);
    },
  );

  testWidgets(
    'full -> collapsed transition when the last due habit becomes complete',
    (tester) async {
      // Start with one due habit and no completed.
      await tester.pumpWidget(
        buildScope(
          due: [habit(id: '1', name: 'Meditate')],
          complete: const [],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('today-due-full')), findsOneWidget);
      expect(find.byKey(const ValueKey('today-due-collapsed')), findsNothing);

      // Now pump the same tree with the habit moved into `complete`.
      await tester.pumpWidget(
        buildScope(
          due: const [],
          complete: [habit(id: '1', name: 'Meditate')],
        ),
      );
      // Let AnimatedSize + AnimatedSwitcher settle.
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('today-due-collapsed')), findsOneWidget);
      expect(find.byKey(const ValueKey('today-due-full')), findsNothing);
      expect(find.text('all done'), findsOneWidget);
    },
  );

  testWidgets(
      'full-state container semantics label is just "Today"',
      (tester) async {
    await tester.pumpWidget(
      buildScope(
        due: [habit(id: '1'), habit(id: '2')],
        complete: [habit(id: '3')],
      ),
    );
    await tester.pumpAndSettle();
    expect(findSemanticsWidget('Today'), findsOneWidget);
    expect(
      findSemanticsWidget('Today, 1 of 3 habits complete'),
      findsNothing,
    );
  });

  testWidgets('container semantics label says all complete in collapsed mode',
      (tester) async {
    await tester.pumpWidget(
      buildScope(
        due: const [],
        complete: [habit(id: '1')],
      ),
    );
    await tester.pumpAndSettle();
    expect(
      findSemanticsWidget('Today, all habits complete'),
      findsOneWidget,
    );
  });

  testWidgets('tapping leading circle on due chip calls onQuickComplete',
      (tester) async {
    final tapped = <String>[];
    await tester.pumpWidget(
      buildScope(
        due: [habit(id: '1', name: 'Meditate')],
        complete: const [],
        onQuickComplete: (h) async {
          tapped.add(h.id);
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('Complete Meditate'));
    await tester.pumpAndSettle();
    expect(tapped, ['1']);
  });

  testWidgets(
      'tapping leading circle on completed chip calls onQuickComplete',
      (tester) async {
    final tapped = <String>[];
    await tester.pumpWidget(
      buildScope(
        due: const [],
        complete: [habit(id: '1', name: 'Meditate')],
        onQuickComplete: (h) async {
          tapped.add(h.id);
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('Meditate, completed'));
    await tester.pumpAndSettle();
    expect(tapped, ['1']);
  });

  testWidgets('tapping chip body (not circle) invokes onTap', (tester) async {
    final navigated = <String>[];
    await tester.pumpWidget(
      buildScope(
        due: [habit(id: '1', name: 'Meditate')],
        complete: const [],
        onTap: (h) => navigated.add(h.id),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Meditate'));
    await tester.pumpAndSettle();
    expect(navigated, ['1']);
  });

  testWidgets('rapid double-tap debounces to a single onQuickComplete call',
      (tester) async {
    int calls = 0;
    final completer = Completer<void>();
    await tester.pumpWidget(
      buildScope(
        due: [habit(id: '1', name: 'Meditate')],
        complete: const [],
        onQuickComplete: (h) async {
          calls++;
          await completer.future;
        },
      ),
    );
    await tester.pumpAndSettle();

    // Locate the leading circle by Semantics label; `enabled` flips while
    // the tap is in flight so we use a widget predicate.
    Finder leadingSemantics() => find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.label == 'Complete Meditate',
        );

    expect(
      (tester.widget(leadingSemantics()) as Semantics).properties.enabled,
      isTrue,
    );

    // First tap kicks off the async handler and acquires the _tapping gate.
    await tester.tap(leadingSemantics());
    await tester.pump();

    expect(
      (tester.widget(leadingSemantics()) as Semantics).properties.enabled,
      isFalse,
    );

    // Second tap lands while the future is still pending — no-op.
    await tester.tap(leadingSemantics(), warnIfMissed: false);
    await tester.pump();

    expect(calls, 1);

    completer.complete();
    await tester.pumpAndSettle();
    expect(
      (tester.widget(leadingSemantics()) as Semantics).properties.enabled,
      isTrue,
    );
  });

  testWidgets(
      'accessible visual effects mode raises completed opacity floor',
      (tester) async {
    await tester.pumpWidget(
      buildScope(
        due: const [],
        complete: [habit(id: '1', name: 'Meditate')],
        visualEffectsMode: VisualEffectsMode.accessible,
      ),
    );
    await tester.pumpAndSettle();

    // Locate the AnimatedOpacity that wraps the single completed chip.
    final opacity = tester.widgetList<AnimatedOpacity>(
      find.ancestor(
        of: find.byType(HabitChip),
        matching: find.byType(AnimatedOpacity),
      ),
    );
    expect(opacity, isNotEmpty);
    expect(opacity.first.opacity, closeTo(0.65, 0.0001));
  });

  testWidgets(
      'non-accessible mode uses 0.45 opacity floor for completed chips',
      (tester) async {
    await tester.pumpWidget(
      buildScope(
        due: const [],
        complete: [habit(id: '1', name: 'Meditate')],
        visualEffectsMode: VisualEffectsMode.full,
      ),
    );
    await tester.pumpAndSettle();

    final opacity = tester.widgetList<AnimatedOpacity>(
      find.ancestor(
        of: find.byType(HabitChip),
        matching: find.byType(AnimatedOpacity),
      ),
    );
    expect(opacity, isNotEmpty);
    expect(opacity.first.opacity, closeTo(0.45, 0.0001));
  });
}

class _StaticVisualEffectsNotifier extends VisualEffectsPreferenceNotifier {
  _StaticVisualEffectsNotifier(this._value);
  final VisualEffectsMode _value;
  @override
  VisualEffectsMode? build() => _value;
}
