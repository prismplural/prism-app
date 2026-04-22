import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/features/members/widgets/note_sheet.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
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
          terminologySettingProvider.overrideWithValue((
            term: SystemTerminology.members,
            customSingular: null,
            customPlural: null,
            useEnglish: false,
          )),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: const [Locale('en'), Locale('es')],
          locale: const Locale('es'),
          home: const Scaffold(body: NoteSheet()),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(
      semanticsWithLabel('No hay integrante seleccionado. Toca para elegir'),
      findsOneWidget,
    );
  });
}
