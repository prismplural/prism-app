import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/settings/views/system_info_screen.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';

import 'package:prism_plurality/core/database/database_providers.dart';

import '../../../helpers/fake_repositories.dart';

void main() {
  const seedSettings = SystemSettings(
    systemName: 'Test System',
    systemTag: '| TestTag',
    systemDescription: 'A test description',
    systemColor: 'af8ee9',
  );

  Widget buildSubject({SystemSettings settings = seedSettings}) {
    final fakeRepo = FakeSystemSettingsRepository()
      ..settings = settings;

    return ProviderScope(
      overrides: [
        systemSettingsRepositoryProvider.overrideWithValue(fakeRepo),
        activeMembersProvider.overrideWith(
          (ref) => Stream<List<Member>>.value(const []),
        ),
      ],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: [Locale('en')],
        home: SystemInfoScreen(),
      ),
    );
  }

  group('SystemInfoScreen', () {
    testWidgets('renders all four fields with seeded values', (tester) async {
      await tester.pumpWidget(buildSubject());
      await tester.pumpAndSettle();

      expect(find.text('Test System'), findsOneWidget);
      expect(find.text('| TestTag'), findsOneWidget);
      expect(find.text('A test description'), findsOneWidget);
      expect(find.text('#af8ee9'), findsOneWidget);
    });

    testWidgets('updating name field triggers updateSystemName after debounce',
        (tester) async {
      final fakeRepo = FakeSystemSettingsRepository()
        ..settings = seedSettings;

      final subject = ProviderScope(
        overrides: [
          systemSettingsRepositoryProvider.overrideWithValue(fakeRepo),
          activeMembersProvider.overrideWith(
            (ref) => Stream<List<Member>>.value(const []),
          ),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: [Locale('en')],
          home: SystemInfoScreen(),
        ),
      );

      await tester.pumpWidget(subject);
      await tester.pumpAndSettle();

      final nameField = find.widgetWithText(TextFormField, 'Test System');
      await tester.enterText(nameField, 'New Name');
      // Advance past the 300ms debounce timer.
      await tester.pump(const Duration(milliseconds: 400));

      expect(fakeRepo.settings.systemName, 'New Name');
    });
  });
}
