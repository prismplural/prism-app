import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/features/fronting/providers/sleep_providers.dart';
import 'package:prism_plurality/features/fronting/widgets/sleep_recovery_sheet.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';

FrontingSession _sleep(String id) => FrontingSession(
  id: id,
  startTime: DateTime(2026, 3, 10, 22),
  endTime: DateTime(2026, 3, 11, 6),
  sessionType: SessionType.sleep,
  quality: SleepQuality.good,
);

/// Fake notifier whose restore resolves via a [Completer] the test controls,
/// so the async `_restore` continuation can be driven deterministically.
class _FakeSleepNotifier extends SleepNotifier {
  _FakeSleepNotifier(this.completer);

  final Completer<int> completer;
  int restoreCalls = 0;
  List<FrontingSession>? restoredWith;

  @override
  Future<int> restoreSleepSessions(List<FrontingSession> sessions) {
    restoreCalls += 1;
    restoredWith = sessions;
    return completer.future;
  }
}

Widget _host(
  _FakeSleepNotifier notifier, {
  List<FrontingSession>? sessions,
  bool failLoad = false,
}) {
  final list = sessions ?? [_sleep('s1'), _sleep('s2')];
  return ProviderScope(
    overrides: [
      sleepNotifierProvider.overrideWith(() => notifier),
      recoverableDeletedSleepSessionsProvider.overrideWith((ref) {
        if (failLoad) throw Exception('load failed');
        return list;
      }),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('en')],
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => SleepRecoverySheet.show(context),
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
  testWidgets('lists the recoverable sessions once loaded', (tester) async {
    await tester.pumpWidget(_host(_FakeSleepNotifier(Completer<int>())));
    await _openSheet(tester);

    // The loaded list drives the count subtitle (2 sessions provided).
    expect(
      find.text('2 deleted sleep sessions can be restored'),
      findsOneWidget,
    );
  });

  testWidgets('actions clear bottom system navigation', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 800);
    tester.view.viewPadding = const FakeViewPadding(bottom: 48);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetViewPadding);

    await tester.pumpWidget(_host(_FakeSleepNotifier(Completer<int>())));
    await _openSheet(tester);

    final cancelButton = find.widgetWithText(PrismButton, 'Cancel');
    expect(cancelButton, findsOneWidget);
    expect(tester.getBottomLeft(cancelButton).dy, lessThanOrEqualTo(800 - 48));
  });

  testWidgets('a load failure closes the sheet instead of hanging', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(_FakeSleepNotifier(Completer<int>()), failLoad: true),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Sheet closed instead of hanging on the spinner, error handled cleanly.
    expect(find.byType(SleepRecoverySheet), findsNothing);
    expect(tester.takeException(), isNull);
    await _drainToasts(tester);
  });

  testWidgets('Restore passes the loaded list and closes on success', (
    tester,
  ) async {
    final completer = Completer<int>();
    final notifier = _FakeSleepNotifier(completer);
    await tester.pumpWidget(_host(notifier));
    await _openSheet(tester);

    await tester.tap(find.text('Restore'));
    await tester.pump(); // busy; future pending
    expect(notifier.restoreCalls, 1);
    expect(notifier.restoredWith?.map((s) => s.id), ['s1', 's2']);
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

    // User dismisses the sheet via the modal barrier while restore is running.
    await tester.tapAt(const Offset(8, 8));
    await tester.pump();

    // The restore now completes — the continuation must NOT pop again, or it
    // would punch through to the host route.
    completer.complete(2);
    await tester.pumpAndSettle();

    expect(find.byType(SleepRecoverySheet), findsNothing);
    expect(find.text('open'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _drainToasts(tester);
  });
}
