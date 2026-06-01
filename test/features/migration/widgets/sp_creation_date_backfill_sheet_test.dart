import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/features/migration/widgets/sp_creation_date_backfill_sheet.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';

Widget _buildSubject() {
  return const ProviderScope(
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: [Locale('en')],
      home: Scaffold(body: SpCreationDateBackfillSheet()),
    ),
  );
}

void main() {
  testWidgets('creation date backfill asks for the SP JSON export', (
    tester,
  ) async {
    await tester.pumpWidget(_buildSubject());

    expect(find.text('Select SP JSON'), findsOneWidget);
    expect(find.text('Select Avatar ZIP'), findsNothing);
  });
}
