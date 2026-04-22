import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/features/settings/widgets/time_of_day_chart.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';

Widget _wrap(Widget child, {Locale locale = const Locale('es')}) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: const [Locale('en'), Locale('es')],
    locale: locale,
    home: Scaffold(body: Center(child: child)),
  );
}

void main() {
  testWidgets('uses localized bucket labels and summary semantics', (
    tester,
  ) async {
    Finder semanticsWithLabel(String label) => find.byWidgetPredicate(
      (widget) => widget is Semantics && widget.properties.label == label,
    );

    final l10n = await AppLocalizations.delegate.load(const Locale('es'));
    const breakdown = {'morning': 1, 'afternoon': 1, 'evening': 1, 'night': 1};

    await tester.pumpWidget(_wrap(const TimeOfDayChart(breakdown: breakdown)));

    await tester.pumpAndSettle();

    expect(
      semanticsWithLabel(
        l10n.timeOfDayChartSemantics(
          '${l10n.timeOfDayMorning}: 25%, '
          '${l10n.timeOfDayAfternoon}: 25%, '
          '${l10n.timeOfDayEvening}: 25%, '
          '${l10n.timeOfDayNight}: 25%',
        ),
      ),
      findsOneWidget,
    );

    expect(find.text('${l10n.timeOfDayMorning} 25%'), findsOneWidget);
    expect(find.text('${l10n.timeOfDayAfternoon} 25%'), findsOneWidget);
    expect(find.text('${l10n.timeOfDayEvening} 25%'), findsOneWidget);
    expect(find.text('${l10n.timeOfDayNight} 25%'), findsOneWidget);
    expect(find.text('Morning 25%'), findsNothing);
  });
}
