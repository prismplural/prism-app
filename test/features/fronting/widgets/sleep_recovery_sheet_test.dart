import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/features/fronting/providers/sleep_providers.dart';
import 'package:prism_plurality/features/fronting/widgets/sleep_recovery_sheet.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';

/// Fake notifier whose restore resolves via a [Completer] the test controls,
/// so the async `_restore` continuation can be driven deterministically.
class _FakeSleepNotifier extends SleepNotifier {
  _FakeSleepNotifier(this.completer);

  final Completer<int> completer;
  int restoreCalls = 0;

  @override
  Future<int> restoreDeletedSleepSessions() {
    restoreCalls += 1;
    return completer.future;
  }
}

Widget _host(_FakeSleepNotifier notifier, {int count = 3}) {
  return ProviderScope(
    overrides: [
      sleepNotifierProvider.overrideWith(() => notifier),
      deletedSleepSessionCountProvider.overrideWith(
        (ref) => Future.value(count),
      ),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('en')],
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () =>
                  SleepRecoverySheet.show(context, recoverableCount: count),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> _openSheet(WidgetTester tester) async {
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  expect(find.byType(SleepRecoverySheet), findsOneWidget);
}

/// Drains PrismToast's auto-dismiss timer so it doesn't trip the
/// pending-timer invariant when the test ends (no toast host in this harness).
Future<void> _drainToasts(WidgetTester tester) =>
    tester.pump(const Duration(seconds: 5));

void main() {
  testWidgets('Restore calls the notifier and closes the sheet on success', (
    tester,
  ) async {
    final completer = Completer<int>();
    final notifier = _FakeSleepNotifier(completer);
    await tester.pumpWidget(_host(notifier));
    await _openSheet(tester);

    await tester.tap(find.text('Restore'));
    await tester.pump(); // enter the busy state, future still pending
    expect(notifier.restoreCalls, 1);
    expect(find.byType(SleepRecoverySheet), findsOneWidget);

    completer.complete(2);
    await tester.pumpAndSettle();

    expect(find.byType(SleepRecoverySheet), findsNothing);
    await _drainToasts(tester);
  });

  testWidgets('zero restored still closes the sheet', (tester) async {
    final completer = Completer<int>();
    await tester.pumpWidget(_host(_FakeSleepNotifier(completer)));
    await _openSheet(tester);

    await tester.tap(find.text('Restore'));
    await tester.pump();
    completer.complete(0);
    await tester.pumpAndSettle();

    expect(find.byType(SleepRecoverySheet), findsNothing);
    await _drainToasts(tester);
  });

  testWidgets('error keeps the sheet open and re-enables Restore', (
    tester,
  ) async {
    final completer = Completer<int>();
    await tester.pumpWidget(_host(_FakeSleepNotifier(completer)));
    await _openSheet(tester);

    await tester.tap(find.text('Restore'));
    await tester.pump();
    completer.completeError(Exception('restore failed'));
    await tester.pumpAndSettle();

    // Sheet stays open so the user can retry, and the button is no longer in
    // the busy state ("Restore", not "Restoring…").
    expect(find.byType(SleepRecoverySheet), findsOneWidget);
    expect(find.text('Restore'), findsOneWidget);
    expect(find.text('Restoring…'), findsNothing);
    expect(tester.takeException(), isNull);
    await _drainToasts(tester);
  });

  testWidgets('dismissing mid-restore does not over-pop the underlying route', (
    tester,
  ) async {
    final completer = Completer<int>();
    await tester.pumpWidget(_host(_FakeSleepNotifier(completer)));
    await _openSheet(tester);

    await tester.tap(find.text('Restore'));
    await tester.pump(); // busy; future pending

    // User dismisses the sheet via the modal barrier while the restore is
    // still running.
    await tester.tapAt(const Offset(8, 8));
    await tester.pump();

    // The restore now completes — the continuation must NOT pop again, or it
    // would punch through to the host route.
    completer.complete(2);
    await tester.pumpAndSettle();

    expect(find.byType(SleepRecoverySheet), findsNothing);
    // Host route survived — we did not over-pop past the sheet.
    expect(find.text('open'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _drainToasts(tester);
  });
}
