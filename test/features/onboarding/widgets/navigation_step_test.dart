import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/database_provider.dart';
import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/core/router/app_routes.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/features/onboarding/providers/onboarding_providers.dart';
import 'package:prism_plurality/features/onboarding/services/onboarding_commit_service.dart';
import 'package:prism_plurality/features/onboarding/widgets/navigation_step.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/features/settings/views/navigation_settings_screen.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/widgets/prism_inline_icon_button.dart';

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

  Widget buildSettingsSubject(ProviderContainer container) {
    return UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: [Locale('en')],
        home: NavigationSettingsScreen(),
      ),
    );
  }

  List<AppShellTabId> tabIds(List<AppShellTab> tabs) {
    return tabs.map((tab) => tab.id).toList();
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

  testWidgets('onboarding defaults Settings to the configured main row', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(393, 852);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });

    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(buildSubject(container));
    await tester.pumpAndSettle();

    final state = container.read(onboardingProvider);
    expect(state.navBarItems.first, 'home');
    expect(state.navBarItems.last, 'settings');
    expect(state.navBarItems.length, inInclusiveRange(2, 5));
    expect(state.navBarOverflowItems, isNot(contains('settings')));

    await tester.scrollUntilVisible(
      find.byKey(const Key('navigation_preview')),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('navigation_preview_primary_settings')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('navigation_preview_overflow_settings')),
      findsNothing,
    );
    final moreMenuTop = tester
        .getTopLeft(find.byKey(const ValueKey('header_More Menu')))
        .dy;
    final settingsTop = tester
        .getTopLeft(find.byKey(const ValueKey(AppShellTabId.settings)))
        .dy;

    expect(settingsTop, lessThan(moreMenuTop));
  });

  testWidgets('onboarding default nav count expands when five tabs fit', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(700, 852);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });

    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(buildSubject(container));
    await tester.pumpAndSettle();

    final state = container.read(onboardingProvider);
    expect(state.navBarItems, ['home', 'chat', 'habits', 'polls', 'settings']);
    expect(state.navBarOverflowItems.first, 'members');
    expect(
      find.byKey(const ValueKey('navigation_preview_primary_settings')),
      findsOneWidget,
    );
  });

  testWidgets('stores onboarding nav edits for the rendered nav and settings', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(700, 1200);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });

    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(buildSubject(container));
    await tester.pumpAndSettle();

    expect(container.read(onboardingProvider).navBarItems, [
      'home',
      'chat',
      'habits',
      'polls',
      'settings',
    ]);

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey(AppShellTabId.chat)),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    final moveChatToMore = find.descendant(
      of: find.byKey(const ValueKey(AppShellTabId.chat)),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is PrismInlineIconButton &&
            widget.tooltip == 'Move to More menu',
      ),
    );
    expect(moveChatToMore, findsOneWidget);

    await tester.tap(moveChatToMore);
    await tester.pumpAndSettle();

    final onboarding = container.read(onboardingProvider);
    expect(onboarding.navBarItems, ['home', 'habits', 'polls', 'settings']);
    expect(onboarding.navBarOverflowItems.first, 'chat');

    await container.read(onboardingCommitServiceProvider).complete(onboarding);

    final storedSettings = await container
        .read(systemSettingsRepositoryProvider)
        .getSettings();
    expect(storedSettings.navBarItems, ['home', 'habits', 'polls', 'settings']);
    expect(storedSettings.navBarOverflowItems.first, 'chat');

    tester.view.physicalSize = const Size(700, 1200);
    await tester.pumpWidget(buildSettingsSubject(container));
    await tester.pumpAndSettle();

    expect(tabIds(container.read(activeNavBarTabsProvider)), [
      AppShellTabId.home,
      AppShellTabId.habits,
      AppShellTabId.polls,
      AppShellTabId.settings,
    ]);
    expect(
      tabIds(container.read(navBarOverflowTabsProvider)).first,
      AppShellTabId.chat,
    );

    expect(
      find.byKey(const ValueKey('navigation_preview_primary_settings')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('navigation_preview_primary_chat')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('navigation_preview_overflow_chat')),
      findsOneWidget,
    );

    final moreMenuFinder = find.byKey(const ValueKey('header_More Menu'));
    await tester.scrollUntilVisible(
      moreMenuFinder,
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    final moreMenuTop = tester.getTopLeft(moreMenuFinder).dy;
    final settingsTop = tester
        .getTopLeft(find.byKey(const ValueKey(AppShellTabId.settings)))
        .dy;
    final chatTop = tester
        .getTopLeft(find.byKey(const ValueKey(AppShellTabId.chat)))
        .dy;

    expect(settingsTop, lessThan(moreMenuTop));
    expect(chatTop, greaterThan(moreMenuTop));
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
