import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';

import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/features/settings/views/sync_troubleshooting_screen.dart';

void main() {
  testWidgets('re-pair dialog offers export-first recovery', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          relayUrlProvider.overrideWithValue(
            const AsyncValue<String?>.data('https://relay.example.com'),
          ),
          syncIdProvider.overrideWithValue(
            const AsyncValue<String?>.data('sync-123'),
          ),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: [Locale('en')],
          home: SyncTroubleshootingScreen(),
        ),
      ),
    );

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
}
