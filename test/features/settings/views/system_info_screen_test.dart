import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  final seedMembers = [
    Member(id: 'm1', name: 'Alice', createdAt: DateTime.utc(2024)),
    Member(id: 'm2', name: 'Bob', createdAt: DateTime.utc(2024, 1, 2)),
  ];
  final overflowMembers = List.generate(
    9,
    (index) => Member(
      id: 'm$index',
      name: 'Member $index',
      createdAt: DateTime.utc(2024, 1, index + 1),
    ),
  );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Widget buildSubject({
    SystemSettings settings = seedSettings,
    List<Member> members = const [],
  }) {
    final fakeRepo = FakeSystemSettingsRepository()..settings = settings;

    return ProviderScope(
      overrides: [
        systemSettingsRepositoryProvider.overrideWithValue(fakeRepo),
        activeMembersProvider.overrideWith(
          (ref) => Stream<List<Member>>.value(members),
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

    testWidgets(
      'updating name field triggers updateSystemName after debounce',
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
      },
    );

    testWidgets('shows total member count by default', (tester) async {
      await tester.pumpWidget(buildSubject(members: seedMembers));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('2 headmates'),
        200,
        scrollable: find.byType(Scrollable).first,
      );

      expect(find.text('2 headmates'), findsOneWidget);
      expect(find.text('Hide total member count'), findsOneWidget);
    });

    testWidgets('hides total member count when local preference is enabled', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        'prism.pref.hide_total_member_count': true,
      });

      await tester.pumpWidget(buildSubject(members: overflowMembers));
      await tester.pumpAndSettle();

      expect(find.text('+1'), findsNothing);

      await tester.scrollUntilVisible(
        find.text('Hide total member count'),
        200,
        scrollable: find.byType(Scrollable).first,
      );

      expect(find.text('9 headmates'), findsNothing);
      expect(find.text('Hide total member count'), findsOneWidget);
    });

    testWidgets('toggling hide count persists locally', (tester) async {
      await tester.pumpWidget(buildSubject(members: seedMembers));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Hide total member count'),
        200,
        scrollable: find.byType(Scrollable).first,
      );

      await tester.tap(find.text('Hide total member count'));
      await tester.pumpAndSettle();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('prism.pref.hide_total_member_count'), true);
      expect(find.text('2 headmates'), findsNothing);
    });
  });
}
