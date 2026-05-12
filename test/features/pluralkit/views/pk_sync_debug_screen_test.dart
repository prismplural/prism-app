// Widget tests for [PkSyncDebugScreen].
//
// These tests drive a `ProviderContainer` with a real `PkSyncEventBus` so the
// notifier's stream subscription runs exactly as it would in production. We
// flip the bus's main-isolate guard on in `setUp` and reset it in
// `tearDown` — without the reset, the flag leaks into sibling test files and
// produces order-dependent runs.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/features/pluralkit/services/pk_sync_event.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_sync_event_bus.dart';
import 'package:prism_plurality/features/pluralkit/views/pk_sync_debug_screen.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';

/// Pump the [PkSyncDebugScreen] inside a `MaterialApp` with the minimal l10n
/// setup. The pre-populated [events] are pushed through a real
/// [PkSyncEventBus], routed via the overridden Riverpod provider, so the
/// notifier observes them through its production subscription.
Future<PkSyncEventBus> _pumpScreen(
  WidgetTester tester, {
  List<PkSyncEvent> events = const [],
}) async {
  final bus = PkSyncEventBus();
  addTearDown(bus.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [pkSyncEventBusProvider.overrideWithValue(bus)],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: [Locale('en')],
        home: PrismToastHost(child: PkSyncDebugScreen()),
      ),
    ),
  );
  // First frame establishes the subscription via the notifier's `build()`.
  await tester.pump();

  for (final event in events) {
    bus.emit(event);
  }
  // Drain the broadcast stream microtasks (the listener fires on a microtask
  // so the notifier appends each entry before the next frame), then pump a
  // fresh frame so the screen rebuilds against the populated state.
  await tester.pump(Duration.zero);
  await tester.pump();
  return bus;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(markPkBusMainIsolate);

  tearDown(resetPkBusMainIsolateForTest);

  group('PkSyncDebugScreen empty state', () {
    testWidgets('renders empty title + body and disables top-bar actions', (
      tester,
    ) async {
      await _pumpScreen(tester);

      // Localized title is rendered in the top bar.
      expect(find.text('PluralKit sync log'), findsOneWidget);
      // Plural form for zero events.
      expect(find.text('No events'), findsOneWidget);
      // Empty-state title and body.
      expect(find.text('No PluralKit events'), findsOneWidget);
      expect(
        find.text('Sync with PluralKit to start recording events.'),
        findsOneWidget,
      );

      // Tapping the copy/clear actions is a no-op (icons exist but the
      // buttons are disabled). Tap is safe — disabled IconButtons swallow
      // the tap without throwing.
      final copyFinder = find.byIcon(AppIcons.copyAll);
      final clearFinder = find.byIcon(AppIcons.deleteOutline);
      expect(copyFinder, findsOneWidget);
      expect(clearFinder, findsOneWidget);
      await tester.tap(copyFinder, warnIfMissed: false);
      await tester.tap(clearFinder, warnIfMissed: false);
      await tester.pump();
      // Still on the empty state — nothing changed.
      expect(find.text('No PluralKit events'), findsOneWidget);
    });
  });

  group('PkSyncDebugScreen populated state', () {
    final events = <PkSyncEvent>[
      const PkSyncStarted(
        trigger: 'manual',
        direction: 'pullOnly',
        mode: 'fullSync',
      ),
      const PkTokenAuthFailed(),
      const PkSyncCompleted(
        durationMs: 123,
        pulled: 2,
        pushed: 0,
      ),
    ];

    testWidgets('renders 3 tiles with localized "3 events" subtitle', (
      tester,
    ) async {
      await _pumpScreen(tester, events: events);

      expect(find.text('PluralKit sync log'), findsOneWidget);
      expect(find.text('3 events'), findsOneWidget);

      // One tile per event.
      expect(
        find.textContaining('Sync started'),
        findsOneWidget,
      );
      expect(
        find.text('PluralKit token rejected (auth)'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Sync completed'),
        findsOneWidget,
      );
    });

    testWidgets(
      'error tile shows error-color icon; non-error tiles do not',
      (tester) async {
        await _pumpScreen(tester, events: events);

        // Newest-first ordering — the third emitted event (Sync completed) is
        // at the top, the auth-failed error is in the middle, the sync-started
        // is at the bottom.
        final errorIcons = find.byIcon(AppIcons.errorOutline);
        // Only the auth-failed tile renders the error icon.
        expect(errorIcons, findsOneWidget);

        final BuildContext ctx = tester.element(errorIcons.first);
        final Icon icon = tester.widget(errorIcons.first);
        expect(icon.color, Theme.of(ctx).colorScheme.error);
      },
    );

    testWidgets('tapping a tile expands the JSON drawer', (tester) async {
      await _pumpScreen(tester, events: events);

      // Drawer is collapsed before tap — the JSON body for token-auth-failed
      // is not on screen.
      expect(find.textContaining('"pkTokenAuthFailed"'), findsNothing);

      // Tap the error tile's summary to expand.
      await tester.tap(find.text('PluralKit token rejected (auth)'));
      await tester.pumpAndSettle();

      // JSON drawer is now visible and contains the event's structured
      // payload.
      expect(find.textContaining('"pkTokenAuthFailed"'), findsOneWidget);
      expect(find.textContaining('"error_kind"'), findsOneWidget);
    });

    testWidgets('copy action writes a formatted dump to the clipboard', (
      tester,
    ) async {
      await _pumpScreen(tester, events: events);

      // Capture the clipboard data set by the copy action.
      String? clipboardText;
      TestDefaultBinaryMessengerBinding
          .instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          final args = call.arguments as Map<dynamic, dynamic>;
          clipboardText = args['text'] as String?;
        }
        return null;
      });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding
            .instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null);
      });

      await tester.tap(find.byIcon(AppIcons.copyAll));
      await tester.pump();

      expect(clipboardText, isNotNull);
      final dump = clipboardText!;
      // Header line names the log + entry count.
      expect(dump, contains('PluralKit sync log (3 events)'));
      // Newest-first ordering: PkSyncCompleted is the most-recently-emitted
      // event so its summary must appear before the older PkSyncStarted.
      final completedIdx = dump.indexOf('Sync completed');
      final startedIdx = dump.indexOf('Sync started');
      expect(completedIdx, greaterThanOrEqualTo(0));
      expect(startedIdx, greaterThan(completedIdx));
      // Per-event JSON drawers are present.
      const encoder = JsonEncoder.withIndent('  ');
      expect(
        dump,
        contains(encoder.convert(const PkTokenAuthFailed().toJson())),
      );
      // Toast is shown.
      expect(find.text('PluralKit sync log copied'), findsOneWidget);
      // Drain the toast's auto-dismiss timer so the test framework's
      // "no pending timers" invariant holds at teardown.
      await tester.pumpAndSettle(const Duration(seconds: 5));
    });

    testWidgets('tap copy with empty log is a no-op', (tester) async {
      String? clipboardText;
      TestDefaultBinaryMessengerBinding
          .instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          final args = call.arguments as Map<dynamic, dynamic>;
          clipboardText = args['text'] as String?;
        }
        return null;
      });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding
            .instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null);
      });

      await _pumpScreen(tester);
      await tester.tap(find.byIcon(AppIcons.copyAll), warnIfMissed: false);
      await tester.pump();

      expect(clipboardText, isNull);
    });

    testWidgets('clear action empties the log and returns to empty state', (
      tester,
    ) async {
      await _pumpScreen(tester, events: events);
      expect(find.text('3 events'), findsOneWidget);

      await tester.tap(find.byIcon(AppIcons.deleteOutline));
      await tester.pump();

      // Subtitle flips back to the zero-events plural form.
      expect(find.text('No events'), findsOneWidget);
      // Empty state body is shown.
      expect(
        find.text('Sync with PluralKit to start recording events.'),
        findsOneWidget,
      );
    });
  });
}
