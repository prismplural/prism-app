import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';

import 'package:prism_plurality/core/router/app_routes.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/features/settings/views/navigation_settings_screen.dart';

void main() {
  // Default 5-tab nav bar: Home, Chat, Habits, Polls, Settings
  final defaultTabs = [
    appShellTabs[0], // Home
    appShellTabs[1], // Chat
    appShellTabs[2], // Habits
    appShellTabs[3], // Polls
    appShellTabs[4], // Settings
  ];

  Widget buildSubject({
    List<AppShellTab>? tabs,
    List<AppShellTab> overflowTabs = const [],
    SystemSettings settings = const SystemSettings(),
  }) {
    return ProviderScope(
      overrides: [
        activeNavBarTabsProvider.overrideWithValue(tabs ?? defaultTabs),
        navBarOverflowTabsProvider.overrideWithValue(overflowTabs),
        systemSettingsProvider.overrideWith(
          (ref) => Stream.value(settings),
        ),
      ],
      child: const MaterialApp(
        home: NavigationSettingsScreen(),
      ),
    );
  }

  group('NavigationSettingsScreen', () {
    testWidgets('renders current nav bar items with labels', (tester) async {
      await tester.pumpWidget(buildSubject());
      await tester.pumpAndSettle();

      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Chat'), findsOneWidget);
      expect(find.text('Habits'), findsOneWidget);
      expect(find.text('Polls'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);
    });

    testWidgets('locked tabs (Home, Settings) show lock icon', (tester) async {
      await tester.pumpWidget(buildSubject());
      await tester.pumpAndSettle();

      // Home and Settings are locked — they should show lock icons.
      // There are exactly 2 locked tabs in the default set.
      expect(find.byIcon(AppIcons.lockOutline), findsNWidgets(2));
    });

    testWidgets('non-locked tabs show remove button', (tester) async {
      await tester.pumpWidget(buildSubject());
      await tester.pumpAndSettle();

      // Chat, Habits, Polls are not locked — each gets a remove button.
      expect(find.byIcon(AppIcons.removeCircleOutline), findsNWidgets(3));
    });

    testWidgets('available tabs section shows tabs not in current nav',
        (tester) async {
      // Only Home + Settings in nav => Members, Notes, Reminders should be
      // available (Chat, Habits, Polls too).
      final minimalTabs = [
        appShellTabs[0], // Home
        appShellTabs[4], // Settings
      ];

      await tester.pumpWidget(buildSubject(tabs: minimalTabs));
      await tester.pumpAndSettle();

      // The "Available" section header should be present.
      expect(find.text('Available'), findsOneWidget);

      // Chat, Habits, Polls, Members, Reminders, Notes, Statistics are all
      // enabled by default and not in the nav, so they should appear as available.
      expect(find.text('Chat'), findsOneWidget);
      expect(find.text('Habits'), findsOneWidget);
      expect(find.text('Polls'), findsOneWidget);
      expect(find.text('Headmates'), findsOneWidget);
      expect(find.text('Reminders'), findsOneWidget);
      expect(find.text('Notes'), findsOneWidget);
      expect(find.text('Statistics'), findsOneWidget);

      // Each available tab gets an add button.
      expect(find.byIcon(AppIcons.addCircleOutline), findsNWidgets(7));
    });

    testWidgets('disabled features appear in Disabled Features section',
        (tester) async {
      // Disable chat and polls via settings.
      const settings = SystemSettings(
        chatEnabled: false,
        pollsEnabled: false,
      );

      // Nav bar has only Home + Habits + Settings (Chat/Polls disabled).
      final tabs = [
        appShellTabs[0], // Home
        appShellTabs[2], // Habits
        appShellTabs[4], // Settings
      ];

      await tester.pumpWidget(buildSubject(tabs: tabs, settings: settings));
      await tester.pumpAndSettle();

      // Scroll down to make sure the Disabled Features section is visible.
      await tester.scrollUntilVisible(
        find.text('Disabled Features'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      // Disabled Features section should exist.
      expect(find.text('Disabled Features'), findsOneWidget);

      // Chat and Polls are disabled, so they appear in the disabled section.
      expect(find.text('Chat'), findsOneWidget);
      expect(find.text('Polls'), findsOneWidget);

      // Disabled items show "Enable in Features" text.
      expect(find.text('Enable in Features'), findsNWidgets(2));
    });
  });
}
