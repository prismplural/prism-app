import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/domain/preferences/preference_registry.dart';
import 'package:prism_plurality/domain/preferences/system_terms.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/settings/views/system_info_screen.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';

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

  Widget buildSubject({
    SystemSettings settings = seedSettings,
    List<Member> members = const [],
    bool hideMemberCounts = false,
    FakeAppPreferenceRepository? appPrefs,
  }) {
    final fakeRepo = FakeSystemSettingsRepository()..settings = settings;
    final effectivePrefs = appPrefs ?? FakeAppPreferenceRepository();
    if (hideMemberCounts) {
      effectivePrefs.seed(hideMemberCountsPreference, true);
    }
    if (appPrefs == null) {
      addTearDown(effectivePrefs.close);
    }

    return ProviderScope(
      overrides: [
        appPreferenceRepositoryProvider.overrideWithValue(effectivePrefs),
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

    testWidgets('uses custom system terminology for labels', (tester) async {
      final appPrefs = FakeAppPreferenceRepository()
        ..seed(
          systemTermsPreference,
          const SystemTerms.custom(
            singular: 'collective',
            plural: 'collectives',
          ),
        );
      addTearDown(appPrefs.close);

      await tester.pumpWidget(buildSubject(appPrefs: appPrefs));
      await tester.pumpAndSettle();

      expect(find.text('Collective Information'), findsOneWidget);
      expect(find.text('Collective tag'), findsOneWidget);
      expect(find.text('Collective color'), findsOneWidget);
    });

    testWidgets('uses preset system terminology for labels', (tester) async {
      final appPrefs = FakeAppPreferenceRepository()
        ..seed(
          systemTermsPreference,
          const SystemTerms.preset(SystemTermPreset.collective),
        );
      addTearDown(appPrefs.close);

      await tester.pumpWidget(buildSubject(appPrefs: appPrefs));
      await tester.pumpAndSettle();

      expect(find.text('Collective Information'), findsOneWidget);
      expect(find.text('Collective tag'), findsOneWidget);
      expect(find.text('Collective color'), findsOneWidget);
    });

    testWidgets(
      'updating name field triggers updateSystemName after debounce',
      (tester) async {
        final fakeRepo = FakeSystemSettingsRepository()
          ..settings = seedSettings;
        final appPrefs = FakeAppPreferenceRepository();
        addTearDown(appPrefs.close);

        final subject = ProviderScope(
          overrides: [
            appPreferenceRepositoryProvider.overrideWithValue(appPrefs),
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

    testWidgets(
      'editing description inline triggers updateSystemDescription after debounce',
      (tester) async {
        final fakeRepo = FakeSystemSettingsRepository()
          ..settings = seedSettings;
        final appPrefs = FakeAppPreferenceRepository();
        addTearDown(appPrefs.close);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              appPreferenceRepositoryProvider.overrideWithValue(appPrefs),
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
          ),
        );
        await tester.pumpAndSettle();

        final descField = find.widgetWithText(
          TextFormField,
          'A test description',
        );
        expect(descField, findsOneWidget);
        await tester.enterText(descField, 'Updated **bold** description');
        await tester.pump(const Duration(milliseconds: 400));

        expect(
          fakeRepo.settings.systemDescription,
          'Updated **bold** description',
        );
      },
    );

    testWidgets('shows the full-screen description editor button', (
      tester,
    ) async {
      await tester.pumpWidget(buildSubject());
      await tester.pumpAndSettle();
      expect(find.byTooltip('Open description in full screen'), findsOneWidget);
    });

    // The full editor round-trip needs media-infra provider overrides
    // unavailable in this harness; covered by manual QA.

    testWidgets('shows member counts by default', (tester) async {
      await tester.pumpWidget(buildSubject(members: seedMembers));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('2 headmates'),
        200,
        scrollable: find.byType(Scrollable).first,
      );

      expect(find.text('2 headmates'), findsOneWidget);
      expect(find.text('Hide member counts'), findsOneWidget);
    });

    testWidgets('hides member counts when synced preference is enabled', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildSubject(members: overflowMembers, hideMemberCounts: true),
      );
      await tester.pumpAndSettle();

      expect(find.text('+1'), findsNothing);

      await tester.scrollUntilVisible(
        find.text('Hide member counts'),
        200,
        scrollable: find.byType(Scrollable).first,
      );

      expect(find.text('9 headmates'), findsNothing);
      expect(find.text('Hide member counts'), findsOneWidget);
    });

    testWidgets('toggling hide count persists as a synced app preference', (
      tester,
    ) async {
      final appPrefs = FakeAppPreferenceRepository();
      addTearDown(appPrefs.close);

      await tester.pumpWidget(
        buildSubject(members: seedMembers, appPrefs: appPrefs),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Hide member counts'),
        200,
        scrollable: find.byType(Scrollable).first,
      );

      await tester.tap(find.text('Hide member counts'));
      await tester.pumpAndSettle();

      expect(await appPrefs.get(hideMemberCountsPreference), true);
      expect(find.text('2 headmates'), findsNothing);
    });
  });
}
