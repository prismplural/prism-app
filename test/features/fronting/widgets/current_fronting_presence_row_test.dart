import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/features/fronting/providers/sleep_providers.dart';
import 'package:prism_plurality/features/fronting/widgets/session_history_list.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';

class _FakeSleepNotifier extends SleepNotifier {
  final endedIds = <String>[];

  @override
  void build() {}

  @override
  Future<void> endSleep(String id) async => endedIds.add(id);
}

Widget _wrap(FrontingSession? sleepSession, {_FakeSleepNotifier? notifier}) {
  return ProviderScope(
    overrides: [
      activeSleepSessionProvider.overrideWith(
        (ref) => Stream.value(sleepSession),
      ),
      if (notifier != null) sleepNotifierProvider.overrideWith(() => notifier),
    ],
    child: const MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: [Locale('en')],
      home: Scaffold(body: Center(child: CurrentFrontingPresenceRow())),
    ),
  );
}

void main() {
  testWidgets('shows compact sleep presence row while sleeping', (
    tester,
  ) async {
    final notifier = _FakeSleepNotifier();
    final session = FrontingSession(
      id: 'sleep-1',
      startTime: DateTime.now().subtract(const Duration(hours: 2)),
      sessionType: SessionType.sleep,
    );

    await tester.pumpWidget(_wrap(session, notifier: notifier));
    await tester.pump();

    expect(find.text('Sleeping'), findsOneWidget);
    expect(find.text('End session'), findsOneWidget);
    expect(find.text('Wake Up'), findsOneWidget);
    expect(find.byType(CurrentFrontingSessionChip), findsNothing);

    await tester.tap(find.text('End session'));
    await tester.pumpAndSettle();

    expect(notifier.endedIds, ['sleep-1']);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
