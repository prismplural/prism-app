import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/router/app_routes.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/features/onboarding/providers/onboarding_providers.dart';
import 'package:prism_plurality/features/onboarding/widgets/navigation_step.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';

void main() {
  Widget buildSubject(ProviderContainer container) {
    return UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: [Locale('en')],
        home: Scaffold(body: NavigationStep()),
      ),
    );
  }

  testWidgets('shows More hint and filters unselected features', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container
        .read(onboardingProvider.notifier)
        .setFeatureToggle(chatEnabled: false, pollsEnabled: false);

    await tester.pumpWidget(buildSubject(container));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Move less-used items into More,\n'
        'the three-dot button opens that menu.',
      ),
      findsOneWidget,
    );
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Chat'), findsNothing);
    expect(find.text('Polls'), findsNothing);

    final state = container.read(onboardingProvider);
    expect(state.navBarItems, ['home', 'habits', 'settings']);
    expect(state.navBarOverflowItems, [
      'members',
      'notes',
      'reminders',
      'statistics',
      'timeline',
      'sleep',
    ]);
  });

  testWidgets('seeds existing navigation config when onboarding is rerun', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        systemSettingsProvider.overrideWithValue(
          const AsyncValue.data(
            SystemSettings(
              navBarItems: ['home', 'members', 'settings'],
              navBarOverflowItems: ['timeline'],
            ),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(buildSubject(container));
    await tester.pumpAndSettle();

    final state = container.read(onboardingProvider);
    expect(state.navBarItems, ['home', 'members', 'settings']);
    expect(state.navBarOverflowItems, ['timeline']);
    expect(onboardingNavLayout(state).primary.map((tab) => tab.id), [
      AppShellTabId.home,
      AppShellTabId.members,
      AppShellTabId.settings,
    ]);
  });

  testWidgets('Simply Plural import ignores sparse imported nav config', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        systemSettingsProvider.overrideWithValue(
          const AsyncValue.data(
            SystemSettings(
              boardsEnabled: true,
              navBarOverflowItems: ['boards'],
            ),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    container
        .read(onboardingProvider.notifier)
        .setWasImportedFromSimplyPlural(true, boardPostsImported: true);

    await tester.pumpWidget(buildSubject(container));
    await tester.pumpAndSettle();

    final state = container.read(onboardingProvider);
    expect(state.navBarItems, ['home', 'chat', 'habits', 'polls', 'settings']);
    expect(state.navBarOverflowItems, [
      'members',
      'notes',
      'reminders',
      'statistics',
      'timeline',
      'sleep',
      'boards',
    ]);
  });

  testWidgets('PluralKit import ignores persisted third-party nav config', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        systemSettingsProvider.overrideWithValue(
          const AsyncValue.data(
            SystemSettings(
              navBarItems: ['home', 'members', 'settings'],
              navBarOverflowItems: ['timeline'],
            ),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    container
        .read(onboardingProvider.notifier)
        .setWasImportedFromPluralKit(true);

    await tester.pumpWidget(buildSubject(container));
    await tester.pumpAndSettle();

    final state = container.read(onboardingProvider);
    expect(state.navBarItems, ['home', 'chat', 'habits', 'polls', 'settings']);
    expect(state.navBarOverflowItems, [
      'members',
      'notes',
      'reminders',
      'statistics',
      'timeline',
      'sleep',
    ]);
  });
}
