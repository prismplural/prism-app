import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';

import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/features/settings/views/sync_troubleshooting_screen.dart';

void main() {
  Widget buildScreen({Locale locale = const Locale('en')}) {
    return ProviderScope(
      overrides: [
        relayUrlProvider.overrideWithValue(
          const AsyncValue<String?>.data('https://relay.example.com'),
        ),
        syncIdProvider.overrideWithValue(
          const AsyncValue<String?>.data('sync-123'),
        ),
      ],
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const SyncTroubleshootingScreen(),
      ),
    );
  }

  testWidgets('re-pair dialog offers export-first recovery', (tester) async {
    await tester.pumpWidget(buildScreen());

    await tester.scrollUntilVisible(
      find.text('Re-pair Device'),
      300,
      scrollable: find.byType(Scrollable).first,
    );

    await tester.tap(find.text('Re-pair Device'));
    await tester.pumpAndSettle();

    expect(find.text('Re-pair Device?'), findsOneWidget);
    expect(find.text('Export Data First'), findsOneWidget);
    expect(find.text('Re-pair Now'), findsOneWidget);
  });

  testWidgets('shows a PluralKit repair entry point', (tester) async {
    await tester.pumpWidget(buildScreen());

    await tester.scrollUntilVisible(
      find.text('Open PluralKit group repair'),
      300,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.text('Open PluralKit group repair'), findsOneWidget);
    expect(
      find.textContaining('run group repair and check any suppressed PK group'),
      findsOneWidget,
    );
  });

  testWidgets('shows the PluralKit repair entry point in Spanish', (
    tester,
  ) async {
    await tester.pumpWidget(buildScreen(locale: const Locale('es')));

    await tester.scrollUntilVisible(
      find.text('Abrir reparación de grupos de PluralKit'),
      300,
      scrollable: find.byType(Scrollable).first,
    );

    expect(
      find.text('Abrir reparación de grupos de PluralKit'),
      findsOneWidget,
    );
    expect(
      find.textContaining('revisar coincidencias de grupos PK'),
      findsOneWidget,
    );
  });
}
