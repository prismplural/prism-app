import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/features/fronting/providers/sleep_providers.dart';
import 'package:prism_plurality/features/fronting/widgets/session_history_list.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';

Widget _wrap(FrontingSession? sleepSession) {
  return ProviderScope(
    overrides: [
      activeSleepSessionProvider.overrideWith(
        (ref) => Stream.value(sleepSession),
      ),
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
    final session = FrontingSession(
      id: 'sleep-1',
      startTime: DateTime.now().subtract(const Duration(hours: 2)),
      sessionType: SessionType.sleep,
    );

    await tester.pumpWidget(_wrap(session));
    await tester.pump();

    expect(find.text('Sleeping'), findsOneWidget);
    expect(find.text('Wake Up'), findsOneWidget);
    expect(find.byType(CurrentFrontingSessionChip), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
