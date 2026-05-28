import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/database/app_database.dart'
    hide FrontingSession, Member;
import 'package:prism_plurality/core/database/database_provider.dart';
import 'package:prism_plurality/data/mappers/fronting_session_mapper.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/features/settings/widgets/analytics_date_range_picker.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';

void main() {
  group('AnalyticsDateRangePicker custom picker', () {
    testWidgets(
      'opens without asserting when a pre-2020 record is the All-time start',
      (tester) async {
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);

        // A record predating the picker's default firstDate (2020). Selecting
        // "All" makes this the range start; opening "Custom" must extend
        // firstDate back to cover it or showDateRangePicker asserts that the
        // initial range starts before firstDate.
        final preimport = DateTime(2018, 6, 1);
        await db.frontingSessionsDao.insertSession(
          FrontingSessionMapper.toCompanion(
            FrontingSession(
              id: 'old',
              memberId: 'a',
              startTime: preimport,
              endTime: preimport.add(const Duration(hours: 1)),
            ),
          ),
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [databaseProvider.overrideWithValue(db)],
            child: const MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: [Locale('en')],
              home: Scaffold(body: AnalyticsDateRangePicker()),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('All'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Custom'));
        await tester.pumpAndSettle();

        // No assertion thrown, and the date range picker dialog is on screen.
        expect(tester.takeException(), isNull);
        expect(find.byType(DateRangePickerDialog), findsOneWidget);
      },
    );

    testWidgets('opens from a normal preset range without crashing', (
      tester,
    ) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(db)],
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: [Locale('en')],
            home: Scaffold(body: AnalyticsDateRangePicker()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Default selection is the 30-day preset; open Custom straight away.
      await tester.tap(find.text('Custom'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(DateRangePickerDialog), findsOneWidget);
    });
  });
}
