import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_sync_config.dart';
import 'package:prism_plurality/features/pluralkit/widgets/pk_sync_summary_card.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';

Widget _wrap(PkSyncSummary summary) {
  return ProviderScope(
    overrides: [
      terminologySettingProvider.overrideWithValue((
        term: SystemTerminology.headmates,
        customSingular: null,
        customPlural: null,
        useEnglish: false,
      )),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('en')],
      home: Scaffold(body: PkSyncSummaryCard(summary: summary)),
    ),
  );
}

void main() {
  testWidgets('stale-link-only summary does not render as up to date', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const PkSyncSummary(
          staleLinkMessages: ['A PluralKit switch target was removed.'],
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Everything is up to date.'), findsNothing);
    expect(find.text('1 stale PluralKit link was cleared'), findsOneWidget);
  });
}
