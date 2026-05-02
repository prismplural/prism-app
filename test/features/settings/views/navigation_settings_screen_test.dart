import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/app_shell.dart';
import 'package:prism_plurality/shared/widgets/prism_list_row.dart';

import 'package:prism_plurality/core/router/app_routes.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/features/settings/views/navigation_settings_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final fontLoader = FontLoader('OpenDyslexic')
      ..addFont(rootBundle.load('assets/fonts/OpenDyslexic-Regular.otf'))
      ..addFont(rootBundle.load('assets/fonts/OpenDyslexic-Bold.otf'));
    await fontLoader.load();
  });

  // Default 5-tab nav bar: Home, Chat, Habits, Polls, Settings
  final defaultTabs = [
    appShellTabs[0], // Home
    appShellTabs[1], // Chat
    appShellTabs[2], // Habits
    appShellTabs[3], // Polls
    appShellTabs[4], // Settings
  ];

  Widget buildSubjectWithMedia({
    List<AppShellTab>? tabs,
    List<AppShellTab> overflowTabs = const [],
    SystemSettings settings = const SystemSettings(),
    Size mediaSize = const Size(800, 600),
    TextScaler textScaler = TextScaler.noScaling,
    ThemeData? theme,
  }) {
    return ProviderScope(
      overrides: [
        activeNavBarTabsProvider.overrideWithValue(tabs ?? defaultTabs),
        navBarOverflowTabsProvider.overrideWithValue(overflowTabs),
        systemSettingsProvider.overrideWith((ref) => Stream.value(settings)),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: const [Locale('en')],
        theme: theme,
        home: MediaQuery(
          data: MediaQueryData(size: mediaSize, textScaler: textScaler),
          child: const NavigationSettingsScreen(),
        ),
      ),
    );
  }

  Finder findRow(String title) =>
      find.ancestor(of: find.text(title), matching: find.byType(PrismListRow));

  Finder findRowSemantics(String rowTitle, String label) => find.descendant(
    of: findRow(rowTitle),
    matching: find.byWidgetPredicate(
      (widget) => widget is Semantics && widget.properties.label == label,
    ),
  );

  group('NavigationSettingsScreen', () {
    testWidgets('renders current nav bar items with labels', (tester) async {
      await tester.pumpWidget(buildSubjectWithMedia());
      await tester.pumpAndSettle();

      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Chat'), findsOneWidget);
      expect(find.text('Habits'), findsOneWidget);
      expect(find.text('Polls'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);
    });

    testWidgets('only Home shows a lock icon', (tester) async {
      await tester.pumpWidget(buildSubjectWithMedia());
      await tester.pumpAndSettle();

      // Only Home is locked.
      expect(find.byIcon(AppIcons.lockOutline), findsOneWidget);
    });

    testWidgets('non-locked tabs show remove button', (tester) async {
      await tester.pumpWidget(buildSubjectWithMedia());
      await tester.pumpAndSettle();

      // Chat, Habits, Polls, Settings are not locked — each gets a remove button.
      expect(find.byIcon(AppIcons.removeCircleOutline), findsNWidgets(4));
    });

    testWidgets('available tabs section shows tabs not in current nav', (
      tester,
    ) async {
      // Only Home + Settings in nav => Members, Notes, Reminders should be
      // available (Chat, Habits, Polls too).
      final minimalTabs = [
        appShellTabs[0], // Home
        appShellTabs[4], // Settings
      ];

      await tester.pumpWidget(buildSubjectWithMedia(tabs: minimalTabs));
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
      expect(find.text('Timeline'), findsOneWidget);

      // Each available tab gets an add button.
      expect(find.byIcon(AppIcons.addCircleOutline), findsNWidgets(9));
    });

    testWidgets('disabled features appear in Disabled Features section', (
      tester,
    ) async {
      // Disable chat and polls via settings. Boards is also off-by-default;
      // enable it so the disabled section under test is just Chat + Polls.
      const settings = SystemSettings(
        chatEnabled: false,
        pollsEnabled: false,
        boardsEnabled: true,
      );

      // Nav bar has only Home + Habits + Settings (Chat/Polls disabled).
      final tabs = [
        appShellTabs[0], // Home
        appShellTabs[2], // Habits
        appShellTabs[4], // Settings
      ];

      await tester.pumpWidget(
        buildSubjectWithMedia(tabs: tabs, settings: settings),
      );
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

    testWidgets(
      'keeps move-to-primary enabled when moving the last overflow tab would fit',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(700, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final tabs = [
          appShellTabs[0], // Home
          appShellTabs[1], // Chat
          appShellTabs[2], // Habits
          appShellTabs[3], // Polls
        ];

        await tester.pumpWidget(
          buildSubjectWithMedia(
            tabs: tabs,
            overflowTabs: [appShellTabs[4]], // Settings
            mediaSize: const Size(700, 900),
          ),
        );
        await tester.pumpAndSettle();

        final moveFinder = findRowSemantics('Settings', 'Move to nav bar');
        expect(moveFinder, findsOneWidget);
        expect(tester.widget<Semantics>(moveFinder).properties.enabled, isTrue);
      },
    );

    testWidgets(
      'keeps the generic add affordance enabled on a constrained device when the candidate would spill',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(320, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final tabs = [
          appShellTabs[0], // Home
          appShellTabs[1], // Chat
          appShellTabs[2], // Habits
        ];

        await tester.pumpWidget(
          buildSubjectWithMedia(
            tabs: tabs,
            overflowTabs: [appShellTabs[3]], // Polls
            mediaSize: const Size(320, 800),
            textScaler: const TextScaler.linear(1.6),
          ),
        );
        await tester.pumpAndSettle();

        expect(findRowSemantics('Polls', 'Move to nav bar'), findsNothing);

        await tester.scrollUntilVisible(
          find.text('Settings'),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();

        final addFinder = findRowSemantics('Settings', 'Add');
        expect(addFinder, findsOneWidget);
        expect(tester.widget<Semantics>(addFinder).properties.enabled, isTrue);
      },
    );

    testWidgets('preview expands to three overflow rows when needed', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(320, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final tabs = [
        appShellTabs[0], // Home
        appShellTabs[1], // Chat
        appShellTabs[4], // Settings
      ];

      await tester.pumpWidget(
        buildSubjectWithMedia(
          tabs: tabs,
          overflowTabs: [
            appShellTabs[2], // Habits
            appShellTabs[3], // Polls
            appShellTabs[5], // Members
            appShellTabs[6], // Reminders
            appShellTabs[7], // Notes
            appShellTabs[8], // Statistics
            appShellTabs[9], // Timeline
          ],
          mediaSize: const Size(320, 800),
          textScaler: const TextScaler.linear(1.6),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('navigation_preview')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('navigation_preview_overflow_row_0')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('navigation_preview_overflow_row_1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('navigation_preview_overflow_row_2')),
        findsOneWidget,
      );
    });

    testWidgets(
      'preview no longer loses an extra inner gutter width inside the card',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(390, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          buildSubjectWithMedia(mediaSize: const Size(390, 800)),
        );
        await tester.pumpAndSettle();

        expect(
          tester.getSize(find.byKey(const Key('navigation_preview'))).width,
          closeTo(390 - (kFloatingNavBarSideMargin * 2) - 2, 0.01),
        );
      },
    );

    testWidgets(
      'uses the real label style when deciding whether a tab fits in primary',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(320, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final tabs = [
          appShellTabs[0], // Home
          appShellTabs[1], // Chat
          appShellTabs[2], // Habits
        ];

        await tester.pumpWidget(
          buildSubjectWithMedia(
            tabs: tabs,
            overflowTabs: [appShellTabs[3]], // Polls
            mediaSize: const Size(320, 800),
            textScaler: const TextScaler.linear(1.3),
            theme: ThemeData(fontFamily: 'OpenDyslexic'),
          ),
        );
        await tester.pumpAndSettle();

        expect(findRowSemantics('Polls', 'Move to nav bar'), findsNothing);
      },
    );

    testWidgets(
      'adaptive persistence helper keeps a fitting overflow tab in primary',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: [Locale('en')],
            home: MediaQuery(
              data: MediaQueryData(size: Size(700, 900)),
              child: Builder(builder: _buildAdaptiveLayoutForWideDevice),
            ),
          ),
        );
        await tester.pump();

        final layout = tester
            .widget<_AdaptiveLayoutProbe>(find.byType(_AdaptiveLayoutProbe))
            .layout;

        expect(layout.primaryTabs.map((tab) => tab.id), [
          AppShellTabId.home,
          AppShellTabId.chat,
          AppShellTabId.habits,
          AppShellTabId.polls,
          AppShellTabId.settings,
        ]);
        expect(layout.overflowTabs, isEmpty);
      },
    );

    testWidgets(
      'adaptive persistence helper spills an impossible primary move back into overflow',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: [Locale('en')],
            home: MediaQuery(
              data: MediaQueryData(
                size: Size(320, 800),
                textScaler: TextScaler.linear(1.6),
              ),
              child: Builder(builder: _buildAdaptiveLayoutForNarrowDevice),
            ),
          ),
        );
        await tester.pump();

        final layout = tester
            .widget<_AdaptiveLayoutProbe>(find.byType(_AdaptiveLayoutProbe))
            .layout;

        expect(layout.primaryTabs.map((tab) => tab.id), [
          AppShellTabId.home,
          AppShellTabId.chat,
        ]);
        expect(layout.overflowTabs.map((tab) => tab.id), [
          AppShellTabId.habits,
          AppShellTabId.polls,
          AppShellTabId.settings,
        ]);
      },
    );
  });
}

Widget _buildAdaptiveLayoutForWideDevice(BuildContext context) {
  return _AdaptiveLayoutProbe(
    layout: computeAdaptiveNavLayoutForCurrentDevice(
      context,
      primary: [
        appShellTabs[0], // Home
        appShellTabs[1], // Chat
        appShellTabs[2], // Habits
        appShellTabs[3], // Polls
        appShellTabs[4], // Settings
      ],
      overflow: const [],
      terminologyPlural: 'Headmates',
    ),
  );
}

Widget _buildAdaptiveLayoutForNarrowDevice(BuildContext context) {
  return _AdaptiveLayoutProbe(
    layout: computeAdaptiveNavLayoutForCurrentDevice(
      context,
      primary: [
        appShellTabs[0], // Home
        appShellTabs[1], // Chat
        appShellTabs[2], // Habits
        appShellTabs[3], // Polls
      ],
      overflow: [appShellTabs[4]], // Settings
      terminologyPlural: 'Headmates',
    ),
  );
}

class _AdaptiveLayoutProbe extends StatelessWidget {
  const _AdaptiveLayoutProbe({required this.layout});

  final AppShellMobileNavLayout layout;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
