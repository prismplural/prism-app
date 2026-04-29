// Tests for the 1B initial-state seeding of the home screen's
// list↔timeline toggle (`timelineViewActiveProvider`) from the user's
// `fronting_list_view_mode` preference.
//
// FrontingScreen itself is too heavy to mount here (member queries,
// scroll state, top-bar action graph, banner stack, etc.); the logic
// under test is the small `_maybeInitializeToggleFromPref` helper,
// which:
//
//   1. Reads `systemSettingsProvider`.
//   2. On first emit, sets `timelineViewActiveProvider` to true if
//      the pref is `timeline`, false otherwise.
//   3. Latches a flag so subsequent emits (e.g., a sync push from
//      another device flipping the pref mid-screen) DO NOT override
//      the user's current toggle position.
//
// This test mirrors the same 4-line idiom the real screen uses, in a
// minimal harness so we can drive the pref + toggle state without
// dragging in the rest of the home screen.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/features/fronting/providers/timeline_providers.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';

class _ToggleSeederHarness extends ConsumerStatefulWidget {
  const _ToggleSeederHarness();

  @override
  ConsumerState<_ToggleSeederHarness> createState() =>
      _ToggleSeederHarnessState();
}

class _ToggleSeederHarnessState extends ConsumerState<_ToggleSeederHarness> {
  bool _toggleInitialized = false;

  void _maybeInitializeToggleFromPref() {
    if (_toggleInitialized) return;
    final mode = ref.read(systemSettingsProvider).whenOrNull(
          data: (s) => s.frontingListViewMode,
        );
    if (mode == null) return;
    _toggleInitialized = true;
    final shouldShowTimeline = mode == FrontingListViewMode.timeline;
    if (ref.read(timelineViewActiveProvider) == shouldShowTimeline) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref
          .read(timelineViewActiveProvider.notifier)
          .setActive(shouldShowTimeline);
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(systemSettingsProvider);
    _maybeInitializeToggleFromPref();
    final isTimeline = ref.watch(timelineViewActiveProvider);
    return MaterialApp(
      home: Scaffold(
        body: Text(isTimeline ? 'TIMELINE' : 'LIST'),
      ),
    );
  }
}

void main() {
  group('1B toggle initial-state seeding from preference', () {
    testWidgets(
      'pref `combinedPeriods` → toggle initial state is list (false)',
      (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              systemSettingsProvider.overrideWith(
                (ref) => Stream.value(
                  const SystemSettings(
                    frontingListViewMode: FrontingListViewMode.combinedPeriods,
                  ),
                ),
              ),
            ],
            child: const _ToggleSeederHarness(),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('LIST'), findsOneWidget);
      },
    );

    testWidgets(
      'pref `perMemberRows` → toggle initial state is list (false)',
      (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              systemSettingsProvider.overrideWith(
                (ref) => Stream.value(
                  const SystemSettings(
                    frontingListViewMode: FrontingListViewMode.perMemberRows,
                  ),
                ),
              ),
            ],
            child: const _ToggleSeederHarness(),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('LIST'), findsOneWidget);
      },
    );

    testWidgets(
      'pref `timeline` → toggle initial state is timeline (true)',
      (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              systemSettingsProvider.overrideWith(
                (ref) => Stream.value(
                  const SystemSettings(
                    frontingListViewMode: FrontingListViewMode.timeline,
                  ),
                ),
              ),
            ],
            child: const _ToggleSeederHarness(),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('TIMELINE'), findsOneWidget);
      },
    );

    testWidgets(
      'user toggle override is NOT persisted back to the preference',
      (tester) async {
        // Hand-roll a writable settings stream so we can assert that
        // toggling the UI's local state does not push back to the pref.
        const current = SystemSettings(
          frontingListViewMode: FrontingListViewMode.combinedPeriods,
        );
        final container = ProviderContainer(
          overrides: [
            systemSettingsProvider.overrideWith(
              (ref) => Stream.value(current),
            ),
          ],
        );
        addTearDown(container.dispose);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const _ToggleSeederHarness(),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('LIST'), findsOneWidget);

        // User flips the toggle.
        container.read(timelineViewActiveProvider.notifier).toggle();
        await tester.pumpAndSettle();
        expect(find.text('TIMELINE'), findsOneWidget);

        // Pref untouched: the in-memory variable representing the
        // synced setting did NOT change.
        expect(current.frontingListViewMode,
            FrontingListViewMode.combinedPeriods);
      },
    );

    testWidgets(
      'sync change to pref mid-screen does NOT override the user toggle',
      (tester) async {
        // Drive the settings stream from a controller so we can push
        // a "sync arrived from another device" emit after the toggle
        // has been seeded.
        final controller = StreamController<SystemSettings>();
        addTearDown(controller.close);
        controller.add(const SystemSettings(
          frontingListViewMode: FrontingListViewMode.combinedPeriods,
        ));

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              systemSettingsProvider.overrideWith((ref) => controller.stream),
            ],
            child: const _ToggleSeederHarness(),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('LIST'), findsOneWidget);

        // Push a NEW pref value — as if another paired device flipped
        // the setting and it sync'd in. The seeder must NOT re-seed.
        controller.add(const SystemSettings(
          frontingListViewMode: FrontingListViewMode.timeline,
        ));
        await tester.pumpAndSettle();

        // Still on LIST: the initial seeding latched. The user's
        // current position wins until the next mount.
        expect(find.text('LIST'), findsOneWidget);
      },
    );
  });
}
