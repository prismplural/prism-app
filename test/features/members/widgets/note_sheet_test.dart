import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/features/members/widgets/note_sheet.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';

void main() {
  testWidgets('localizes the empty headmate picker semantics label', (
    tester,
  ) async {
    Finder semanticsWithLabel(String label) => find.byWidgetPredicate(
      (widget) => widget is Semantics && widget.properties.label == label,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          systemSettingsProvider.overrideWithValue(
            const AsyncValue.data(
              SystemSettings(terminology: SystemTerminology.members),
            ),
          ),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: [Locale('en'), Locale('es')],
          locale: Locale('es'),
          home: Scaffold(body: NoteSheet()),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(
      semanticsWithLabel('No hay integrante seleccionado. Toca para elegir'),
      findsOneWidget,
    );
  });

  testWidgets('does not show fallback terminology while settings load', (
    tester,
  ) async {
    final settings = StreamController<SystemSettings>();
    addTearDown(settings.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          systemSettingsProvider.overrideWith((ref) => settings.stream),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: [Locale('en')],
          home: Scaffold(body: NoteSheet()),
        ),
      ),
    );

    await tester.pump();
    expect(find.text('Add headmate'), findsNothing);
    expect(find.text('Add member'), findsNothing);

    settings.add(const SystemSettings(terminology: SystemTerminology.members));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Add member'), findsOneWidget);
    expect(find.text('Add headmate'), findsNothing);
  });
}
