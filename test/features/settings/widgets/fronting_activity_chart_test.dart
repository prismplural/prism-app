import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:prism_plurality/domain/models/fronting_analytics.dart';
import 'package:prism_plurality/features/settings/widgets/fronting_activity_chart.dart';
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
  testWidgets('uses localized chart strings and summary semantics', (
    tester,
  ) async {
    Finder semanticsWithLabel(String label) => find.byWidgetPredicate(
      (widget) => widget is Semantics && widget.properties.label == label,
    );

    await initializeDateFormatting('es');
    final l10n = await AppLocalizations.delegate.load(const Locale('es'));
    final dateFormat = DateFormat.MMMd('es');
    final dailyActivity = [
      DailyActivity(
        date: DateTime(2026, 4, 1),
        totalMinutes: 120,
        sessionCount: 1,
      ),
      DailyActivity(
        date: DateTime(2026, 4, 2),
        totalMinutes: 360,
        sessionCount: 2,
      ),
      DailyActivity(
        date: DateTime(2026, 4, 3),
        totalMinutes: 240,
        sessionCount: 1,
      ),
      DailyActivity(
        date: DateTime(2026, 4, 4),
        totalMinutes: 180,
        sessionCount: 1,
      ),
      DailyActivity(
        date: DateTime(2026, 4, 5),
        totalMinutes: 300,
        sessionCount: 2,
      ),
    ];

    tester.binding.platformDispatcher.localeTestValue = const Locale('es');
    addTearDown(tester.binding.platformDispatcher.clearLocaleTestValue);

    await tester.pumpWidget(
      _wrap(FrontingActivityChart(dailyActivity: dailyActivity)),
    );

    await tester.pumpAndSettle();

    expect(find.text(l10n.frontingActivityChartTitle), findsOneWidget);
    expect(
      find.text(l10n.frontingActivityChartAverageLabel('4.0')),
      findsOneWidget,
    );
    expect(
      find.text(dateFormat.format(dailyActivity.first.date)),
      findsAtLeastNWidgets(1),
    );
    expect(
      find.text(dateFormat.format(dailyActivity.last.date)),
      findsAtLeastNWidgets(1),
    );
    expect(
      semanticsWithLabel(
        l10n.frontingActivityChartSemantics(
          '6.0',
          dateFormat.format(dailyActivity[1].date),
          '4.0',
        ),
      ),
      findsOneWidget,
    );
  });
}
