import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/features/fronting/providers/sleep_providers.dart';
import 'package:prism_plurality/features/fronting/views/start_sleep_sheet.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_datetime_pills.dart';

/// A `logHistoricalSleep` call the sheet made, captured for assertions.
class _HistoricalSleepCall {
  const _HistoricalSleepCall({required this.startTime, required this.endTime});

  final DateTime startTime;
  final DateTime endTime;
}

class _FakeSleepNotifier extends SleepNotifier {
  int startSleepCalls = 0;
  Completer<void>? startSleepCompleter;
  final logHistoricalSleepCalls = <_HistoricalSleepCall>[];

  @override
  void build() {}

  @override
  Future<void> startSleep({
    String? notes,
    DateTime? startTime,
    SleepQuality? quality,
  }) async {
    startSleepCalls += 1;
    final completer = startSleepCompleter;
    if (completer != null) {
      await completer.future;
    }
  }

  @override
  Future<FrontingSession> logHistoricalSleep({
    required DateTime startTime,
    required DateTime endTime,
    SleepQuality? quality,
    String? notes,
  }) async {
    logHistoricalSleepCalls.add(
      _HistoricalSleepCall(startTime: startTime, endTime: endTime),
    );
    return FrontingSession(
      id: 'sleep-${logHistoricalSleepCalls.length}',
      startTime: startTime,
      endTime: endTime,
      sessionType: SessionType.sleep,
    );
  }
}

/// Hosts the sheet on a pushed route, the way the app presents it, so the
/// sheet's own `Navigator.pop` on save has somewhere to go.
Widget _buildSubject(_FakeSleepNotifier notifier) {
  return ProviderScope(
    overrides: [
      sleepNotifierProvider.overrideWith(() => notifier),
      recentSleepSessionsPaginatedProvider.overrideWith(
        (ref, limit) => Stream.value(const <FrontingSession>[]),
      ),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('en')],
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () async {
                await Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => const Scaffold(body: StartSleepSheet()),
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> _openSheet(
  WidgetTester tester,
  _FakeSleepNotifier notifier,
) async {
  await tester.pumpWidget(_buildSubject(notifier));
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

Finder _startButton() => find.byWidgetPredicate(
  (widget) => widget is PrismButton && widget.label == 'Start',
);

/// The "Log past sleep" / "Cancel historical sleep" disclosure link, which is
/// the sheet's only compact-density button.
Finder _historicalToggle() => find.byWidgetPredicate(
  (widget) =>
      widget is PrismButton && widget.density == PrismControlDensity.compact,
);

Finder _pillsFinder(String label) => find.byWidgetPredicate(
  (widget) => widget is PrismDateTimePills && widget.label == label,
);

PrismDateTimePills _pills(WidgetTester tester, String label) =>
    tester.widget<PrismDateTimePills>(_pillsFinder(label));

/// Edits the Start field the way a picked time does: the pills widget reports
/// the new value through [PrismDateTimePills.onChanged].
Future<void> _editStart(WidgetTester tester, DateTime value) async {
  _pills(tester, 'Start').onChanged(value);
  await tester.pump();
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('start ignores repeated taps while start is pending', (
    tester,
  ) async {
    final notifier = _FakeSleepNotifier()
      ..startSleepCompleter = Completer<void>();

    await _openSheet(tester, notifier);

    await tester.tap(_startButton());
    await tester.tap(_startButton());

    expect(notifier.startSleepCalls, 1);

    notifier.startSleepCompleter!.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('editing Start then tapping Log past sleep keeps that start', (
    tester,
  ) async {
    final notifier = _FakeSleepNotifier();
    await _openSheet(tester, notifier);

    final editedStart = DateTime.now().subtract(const Duration(hours: 3));
    await _editStart(tester, editedStart);
    expect(_pills(tester, 'Start').dateTime, editedStart);

    await _tap(tester, _historicalToggle());

    expect(_pills(tester, 'Start').dateTime, editedStart);
    // Past-sleep mode still fills in a sensible end time.
    final end = _pills(tester, 'End').dateTime!;
    expect(end.isAfter(editedStart), isTrue);
  });

  testWidgets(
    'Log past sleep without an edited Start applies the default past range',
    (tester) async {
      final notifier = _FakeSleepNotifier();
      await _openSheet(tester, notifier);
      final before = DateTime.now();

      await _tap(tester, _historicalToggle());

      final start = _pills(tester, 'Start').dateTime!;
      final end = _pills(tester, 'End').dateTime!;
      expect(before.difference(start).inMinutes, closeTo(8 * 60, 2));
      expect(end.isAfter(start), isTrue);
      expect(before.difference(end).inSeconds.abs(), lessThan(60));
    },
  );

  testWidgets('saving a past sleep entry submits the preserved start time', (
    tester,
  ) async {
    final notifier = _FakeSleepNotifier();
    await _openSheet(tester, notifier);

    final editedStart = DateTime.now().subtract(const Duration(hours: 5));
    await _editStart(tester, editedStart);
    await _tap(tester, _historicalToggle());

    await _tap(tester, _startButton());

    final call = notifier.logHistoricalSleepCalls.single;
    expect(call.startTime, editedStart);
    expect(call.endTime.isAfter(editedStart), isTrue);
    expect(notifier.startSleepCalls, 0);
  });

  testWidgets('canceling past-sleep mode keeps a Start edited beforehand', (
    tester,
  ) async {
    final notifier = _FakeSleepNotifier();
    await _openSheet(tester, notifier);

    final editedStart = DateTime.now().subtract(const Duration(hours: 2));
    await _editStart(tester, editedStart);

    await _tap(tester, _historicalToggle());
    await _tap(tester, _historicalToggle());

    expect(_pills(tester, 'Start').dateTime, editedStart);
    expect(_pillsFinder('End'), findsNothing);
  });

  testWidgets('canceling past-sleep mode keeps a Start edited inside it', (
    tester,
  ) async {
    final notifier = _FakeSleepNotifier();
    await _openSheet(tester, notifier);

    await _tap(tester, _historicalToggle());
    final editedStart = DateTime.now().subtract(const Duration(hours: 6));
    await _editStart(tester, editedStart);

    await _tap(tester, _historicalToggle());

    expect(_pills(tester, 'Start').dateTime, editedStart);
  });

  testWidgets(
    'canceling past-sleep mode restores the Start default when untouched',
    (tester) async {
      final notifier = _FakeSleepNotifier();
      await _openSheet(tester, notifier);
      final before = DateTime.now();

      await _tap(tester, _historicalToggle());
      await _tap(tester, _historicalToggle());

      final start = _pills(tester, 'Start').dateTime!;
      expect(before.difference(start).inSeconds.abs(), lessThan(60));
    },
  );

  testWidgets(
    're-entering past-sleep mode re-applies the 8-hour default when untouched',
    (tester) async {
      final notifier = _FakeSleepNotifier();
      await _openSheet(tester, notifier);

      await _tap(tester, _historicalToggle());
      await _tap(tester, _historicalToggle());
      expect(_pillsFinder('End'), findsNothing);

      final before = DateTime.now();
      await _tap(tester, _historicalToggle());

      final start = _pills(tester, 'Start').dateTime!;
      final end = _pills(tester, 'End').dateTime!;
      expect(before.difference(start).inMinutes, closeTo(8 * 60, 2));
      expect(end.isAfter(start), isTrue);
      expect(before.difference(end).inSeconds.abs(), lessThan(60));
    },
  );
}
