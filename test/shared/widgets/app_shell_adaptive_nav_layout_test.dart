import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:prism_plurality/core/router/app_routes.dart';
import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/domain/models/member.dart' as domain;
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/features/chat/providers/chat_providers.dart';
import 'package:prism_plurality/features/fronting/migration/providers/fronting_migration_providers.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_providers.dart';
import 'package:prism_plurality/features/pluralkit/providers/pk_auto_poll_provider.dart';
import 'package:prism_plurality/features/pluralkit/providers/pluralkit_providers.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_sync_service.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/features/settings/providers/pin_lock_providers.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/theme/app_theme.dart';
import 'package:prism_plurality/shared/utils/nav_bar_layout.dart';
import 'package:prism_plurality/shared/widgets/app_shell.dart';
import 'package:prism_plurality/shared/widgets/floating_nav_bar_backdrop.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final fontLoader = FontLoader('OpenDyslexic')
      ..addFont(rootBundle.load('assets/fonts/OpenDyslexic3-Regular.ttf'))
      ..addFont(rootBundle.load('assets/fonts/OpenDyslexic3-Bold.ttf'));
    await fontLoader.load();
  });

  const labelStyle = TextStyle(fontSize: 12, fontWeight: FontWeight.w600);

  List<AppShellTabId> tabIds(List<AppShellTab> tabs) =>
      tabs.map((tab) => tab.id).toList();

  test('keeps five primary tabs when labels fit without overflow', () {
    final primaryTabs = appShellTabs.take(5).toList();

    final layout = computeAdaptiveMobileNavLayout(
      barWidth: 600,
      primaryTabs: primaryTabs,
      overflowTabs: const [],
      primaryLabels: const ['Home', 'Chat', 'Habits', 'Polls', 'Settings'],
      overflowLabels: const [],
      labelStyle: labelStyle,
      textScaler: const TextScaler.linear(1),
      textDirection: TextDirection.ltr,
    );

    expect(layout.spec.usesOverflowMenu, isFalse);
    expect(layout.spec.overflowRows, 0);
    expect(tabIds(layout.primaryTabs), [
      AppShellTabId.home,
      AppShellTabId.chat,
      AppShellTabId.habits,
      AppShellTabId.polls,
      AppShellTabId.settings,
    ]);
    expect(layout.overflowTabs, isEmpty);
    expect(layout.expandedHeight, layout.rowHeight);
  });

  test('moves spilled primary tabs ahead of persisted overflow tabs', () {
    final primaryTabs = appShellTabs.take(5).toList();
    final overflowTabs = [appShellTabs[5], appShellTabs[7]];

    final layout = computeAdaptiveMobileNavLayout(
      barWidth: 320,
      primaryTabs: primaryTabs,
      overflowTabs: overflowTabs,
      primaryLabels: const [
        'Dashboard Home',
        'Conversations',
        'Daily Habits',
        'Community Polls',
        'Application Settings',
      ],
      overflowLabels: const ['System Headmates', 'Longform Notes'],
      labelStyle: labelStyle,
      textScaler: const TextScaler.linear(2),
      textDirection: TextDirection.ltr,
    );

    expect(layout.spec.usesOverflowMenu, isTrue);
    expect(layout.spec.collapsedPrimaryCount, 2);
    expect(layout.spec.overflowColumns, 2);
    expect(layout.spec.overflowRows, 3);
    expect(tabIds(layout.primaryTabs), [
      AppShellTabId.home,
      AppShellTabId.chat,
    ]);
    expect(tabIds(layout.overflowTabs), [
      AppShellTabId.habits,
      AppShellTabId.polls,
      AppShellTabId.settings,
      AppShellTabId.members,
      AppShellTabId.notes,
    ]);
    expect(
      layout.expandedHeight,
      floatingNavBarExpandedHeight(
        3,
        rowHeight: layout.rowHeight,
        overflowRowHeight: layout.overflowRowHeight,
      ),
    );
  });

  test(
    'truncated labels keep configured primary tabs in the collapsed row',
    () {
      final primaryTabs = appShellTabs.take(5).toList();

      final layout = computeAdaptiveMobileNavLayout(
        barWidth: 320,
        primaryTabs: primaryTabs,
        overflowTabs: const [],
        primaryLabels: const [
          'Dashboard Home',
          'Conversations',
          'Daily Habits',
          'Community Polls',
          'Application Settings',
        ],
        overflowLabels: const [],
        labelStyle: labelStyle,
        textScaler: const TextScaler.linear(2),
        textDirection: TextDirection.ltr,
        labelDisplayMode: NavBarLabelDisplayMode.truncatedLabels,
      );

      expect(layout.spec.usesOverflowMenu, isFalse);
      expect(tabIds(layout.primaryTabs), [
        AppShellTabId.home,
        AppShellTabId.chat,
        AppShellTabId.habits,
        AppShellTabId.polls,
        AppShellTabId.settings,
      ]);
      expect(layout.overflowTabs, isEmpty);
    },
  );

  test('icons only mode ignores label width when fitting primary tabs', () {
    final primaryTabs = appShellTabs.take(5).toList();

    final layout = computeAdaptiveMobileNavLayout(
      barWidth: 260,
      primaryTabs: primaryTabs,
      overflowTabs: const [],
      primaryLabels: const [
        'Dashboard Home',
        'Conversations',
        'Daily Habits',
        'Community Polls',
        'Application Settings',
      ],
      overflowLabels: const [],
      labelStyle: labelStyle,
      textScaler: const TextScaler.linear(2),
      textDirection: TextDirection.ltr,
      labelDisplayMode: NavBarLabelDisplayMode.iconsOnly,
    );

    expect(layout.spec.usesOverflowMenu, isFalse);
    expect(tabIds(layout.primaryTabs), [
      AppShellTabId.home,
      AppShellTabId.chat,
      AppShellTabId.habits,
      AppShellTabId.polls,
      AppShellTabId.settings,
    ]);
    expect(layout.rowHeight, kFloatingNavBarHeight);
  });

  test('reports a four-row expanded overflow layout when needed', () {
    final primaryTabs = appShellTabs.take(5).toList();
    final overflowTabs = [
      appShellTabs[5],
      appShellTabs[6],
      appShellTabs[7],
      appShellTabs[8],
      appShellTabs[9],
    ];

    final layout = computeAdaptiveMobileNavLayout(
      barWidth: 320,
      primaryTabs: primaryTabs,
      overflowTabs: overflowTabs,
      primaryLabels: const [
        'Dashboard Home',
        'Conversations',
        'Daily Habits',
        'Community Polls',
        'Application Settings',
      ],
      overflowLabels: const [
        'System Headmates',
        'Scheduled Reminders',
        'Longform Notes',
        'Usage Statistics',
        'Activity Timeline',
      ],
      labelStyle: labelStyle,
      textScaler: const TextScaler.linear(2),
      textDirection: TextDirection.ltr,
    );

    expect(layout.spec.usesOverflowMenu, isTrue);
    expect(layout.spec.collapsedPrimaryCount, 2);
    expect(layout.spec.overflowColumns, 2);
    expect(layout.spec.overflowRows, 4);
    expect(tabIds(layout.overflowTabs), [
      AppShellTabId.habits,
      AppShellTabId.polls,
      AppShellTabId.settings,
      AppShellTabId.members,
      AppShellTabId.reminders,
      AppShellTabId.notes,
      AppShellTabId.statistics,
      AppShellTabId.timeline,
    ]);
    expect(
      layout.expandedHeight,
      floatingNavBarExpandedHeight(
        4,
        rowHeight: layout.rowHeight,
        overflowRowHeight: layout.overflowRowHeight,
      ),
    );
  });

  testWidgets(
    'memoizes mobile nav layout across rebuilds with identical inputs',
    (tester) async {
      const textScaler = TextScaler.linear(1);

      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final semantics = tester.ensureSemantics();
      try {
        const settings = SystemSettings();
        final configuredPrimaryTabs = appShellTabs.take(5).toList();
        const configuredOverflowTabs = <AppShellTab>[];

        final router = GoRouter(
          initialLocation: AppRoutePaths.home,
          routes: [
            StatefulShellRoute.indexedStack(
              builder: (context, state, navigationShell) {
                return AppShell(navigationShell: navigationShell);
              },
              branches: [
                StatefulShellBranch(
                  routes: [
                    GoRoute(
                      path: AppRoutePaths.home,
                      builder: (context, state) =>
                          const Scaffold(body: SizedBox.expand()),
                    ),
                  ],
                ),
              ],
            ),
          ],
        );
        addTearDown(router.dispose);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              activeNavBarTabsProvider.overrideWithValue(configuredPrimaryTabs),
              navBarOverflowTabsProvider.overrideWithValue(
                configuredOverflowTabs,
              ),
              systemSettingsProvider.overrideWith(
                (ref) => Stream.value(settings),
              ),
              isPinSetProvider.overrideWith((ref) async => false),
              syncStatusProvider.overrideWith(_FakeSyncStatusNotifier.new),
              pkAutoPollProvider.overrideWith(_FakePkAutoPollNotifier.new),
              pluralKitSyncProvider.overrideWith(
                _FakePluralKitSyncNotifier.new,
              ),
              habitsBadgeEnabledProvider.overrideWith((ref) => false),
              activeSessionsProvider.overrideWith(
                (ref) => Stream.value(const []),
              ),
              allMembersProvider.overrideWith((ref) => Stream.value(const [])),
              unreadConversationCountProvider.overrideWith((ref) {
                return ref.watch(_unreadCountStateProvider);
              }),
            ],
            child: MaterialApp.router(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: const [Locale('en')],
              theme: ThemeData(fontFamily: 'OpenDyslexic'),
              builder: (context, child) {
                return MediaQuery(
                  data: MediaQuery.of(context).copyWith(textScaler: textScaler),
                  child: child!,
                );
              },
              routerConfig: router,
            ),
          ),
        );
        await tester.pumpAndSettle();

        final container = ProviderScope.containerOf(
          tester.element(find.byType(AppShell)),
        );

        // Initial pump should have computed the layout once. Reset the
        // counter so we can measure rebuild-triggered recomputes only.
        debugAdaptiveMobileNavLayoutComputeCount = 0;

        // Trigger rebuilds of AppShell via an unrelated provider. A single
        // build computes layout once the first time; subsequent equal rebuilds
        // should hit the memoization cache.
        for (var i = 0; i < 5; i++) {
          container.read(_unreadCountStateProvider.notifier).value = i + 1;
          await tester.pump();
        }

        expect(
          debugAdaptiveMobileNavLayoutComputeCount,
          0,
          reason:
              'Layout should stay cached when labels/scale/width do not change.',
        );

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets(
    'renders the real mobile shell without layout overflow and expands to the computed height',
    (tester) async {
      const textScaler = TextScaler.linear(1);

      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final semantics = tester.ensureSemantics();
      try {
        const settings = SystemSettings();
        final configuredPrimaryTabs = appShellTabs.take(5).toList();
        final configuredOverflowTabs = [
          appShellTabs[5],
          appShellTabs[6],
          appShellTabs[7],
          appShellTabs[8],
          appShellTabs[9],
        ];

        final router = GoRouter(
          initialLocation: AppRoutePaths.home,
          routes: [
            StatefulShellRoute.indexedStack(
              builder: (context, state, navigationShell) {
                return AppShell(navigationShell: navigationShell);
              },
              branches: [
                StatefulShellBranch(
                  routes: [
                    GoRoute(
                      path: AppRoutePaths.home,
                      builder: (context, state) =>
                          const Scaffold(body: SizedBox.expand()),
                    ),
                  ],
                ),
              ],
            ),
          ],
        );
        addTearDown(router.dispose);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              activeNavBarTabsProvider.overrideWithValue(configuredPrimaryTabs),
              navBarOverflowTabsProvider.overrideWithValue(
                configuredOverflowTabs,
              ),
              systemSettingsProvider.overrideWith(
                (ref) => Stream.value(settings),
              ),
              isPinSetProvider.overrideWith((ref) async => false),
              syncStatusProvider.overrideWith(_FakeSyncStatusNotifier.new),
              pkAutoPollProvider.overrideWith(_FakePkAutoPollNotifier.new),
              pluralKitSyncProvider.overrideWith(
                _FakePluralKitSyncNotifier.new,
              ),
              habitsBadgeEnabledProvider.overrideWith((ref) => false),
              activeSessionsProvider.overrideWith(
                (ref) => Stream.value(const []),
              ),
              allMembersProvider.overrideWith((ref) => Stream.value(const [])),
              unreadConversationCountProvider.overrideWith((ref) => 0),
              // Pre-existing test setup didn't override this. After commit
              // a1cbd1a1 the AppShell auto-presents the per-member fronting
              // upgrade modal whenever the gate isn't `complete`, which
              // intercepts the More-tabs tap and prevents the navbar from
              // expanding. Force the gate to complete here so the modal
              // doesn't surface during the test.
              frontingMigrationGateProvider.overrideWith(
                (ref) => FrontingMigrationGateStatus.complete,
              ),
            ],
            child: MaterialApp.router(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: const [Locale('en')],
              theme: ThemeData(fontFamily: 'OpenDyslexic'),
              builder: (context, child) {
                return MediaQuery(
                  data: MediaQuery.of(context).copyWith(textScaler: textScaler),
                  child: child!,
                );
              },
              routerConfig: router,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);

        final appShellContext = tester.element(find.byType(AppShell));
        final terminology = resolveTerminology(
          AppLocalizations.of(appShellContext),
          settings.terminology,
          customSingular: settings.customTerminology,
          customPlural: settings.customPluralTerminology,
          useEnglish: settings.terminologyUseEnglish,
        );
        final expectedLayout = computeAdaptiveMobileNavLayout(
          barWidth:
              MediaQuery.sizeOf(appShellContext).width -
              (kFloatingNavBarSideMargin * 2),
          primaryTabs: configuredPrimaryTabs,
          overflowTabs: configuredOverflowTabs,
          primaryLabels: [
            for (final tab in configuredPrimaryTabs)
              tab.localizedLabel(
                appShellContext,
                terminologyPlural: terminology.plural,
              ),
          ],
          overflowLabels: [
            for (final tab in configuredOverflowTabs)
              tab.localizedLabel(
                appShellContext,
                terminologyPlural: terminology.plural,
              ),
          ],
          labelStyle: navBarLabelTextStyle(appShellContext, isSelected: true),
          textScaler: MediaQuery.textScalerOf(appShellContext),
          textDirection: Directionality.of(appShellContext),
        );

        expect(expectedLayout.spec.usesOverflowMenu, isTrue);
        expect(expectedLayout.spec.overflowRows, greaterThan(1));
        expect(
          expectedLayout.expandedHeight,
          greaterThan(expectedLayout.rowHeight),
        );

        final navBarClip = find.descendant(
          of: find.bySemanticsLabel('Navigation bar'),
          matching: find.byType(ClipRRect),
        );
        expect(
          tester.getSize(navBarClip).height,
          closeTo(expectedLayout.rowHeight, 0.01),
        );

        await tester.tap(find.bySemanticsLabel('More tabs'));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('Timeline'), findsOneWidget);
        expect(
          tester.getSize(navBarClip).height,
          closeTo(expectedLayout.expandedHeight, 0.01),
        );

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets('mobile nav bar base color follows Material You palette', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final semantics = tester.ensureSemantics();
    try {
      const settings = SystemSettings();
      final configuredPrimaryTabs = appShellTabs.take(5).toList();
      const configuredOverflowTabs = <AppShellTab>[];
      final theme = AppTheme.materialYouLight(
        null,
        paletteSource: PaletteSource.custom,
        paletteSeedColorHex: '#16A34A',
        paletteMood: PaletteMood.vibrant,
      );

      final router = GoRouter(
        initialLocation: AppRoutePaths.home,
        routes: [
          StatefulShellRoute.indexedStack(
            builder: (context, state, navigationShell) {
              return AppShell(navigationShell: navigationShell);
            },
            branches: [
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: AppRoutePaths.home,
                    builder: (context, state) =>
                        const Scaffold(body: SizedBox.expand()),
                  ),
                ],
              ),
            ],
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            activeNavBarTabsProvider.overrideWithValue(configuredPrimaryTabs),
            navBarOverflowTabsProvider.overrideWithValue(
              configuredOverflowTabs,
            ),
            systemSettingsProvider.overrideWith(
              (ref) => Stream.value(settings),
            ),
            isPinSetProvider.overrideWith((ref) async => false),
            syncStatusProvider.overrideWith(_FakeSyncStatusNotifier.new),
            pkAutoPollProvider.overrideWith(_FakePkAutoPollNotifier.new),
            pluralKitSyncProvider.overrideWith(_FakePluralKitSyncNotifier.new),
            habitsBadgeEnabledProvider.overrideWith((ref) => false),
            activeSessionsProvider.overrideWith(
              (ref) => Stream.value(const []),
            ),
            allMembersProvider.overrideWith((ref) => Stream.value(const [])),
            unreadConversationCountProvider.overrideWith((ref) => 0),
            frontingMigrationGateProvider.overrideWith(
              (ref) => FrontingMigrationGateStatus.complete,
            ),
          ],
          child: MaterialApp.router(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: const [Locale('en')],
            theme: theme,
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final navBarColor = _floatingNavBarDecorationColor(tester);
      final legacyParchmentColor = Color.alphaBlend(
        theme.colorScheme.primary.withValues(alpha: 0.06),
        AppColors.parchmentElevated.withValues(alpha: 0.82),
      );

      expect(navBarColor, isNot(legacyParchmentColor));
      expect(navBarColor.a, lessThan(0.60));
      expect(navBarColor.a, greaterThan(0.54));
      expect(
        find.descendant(
          of: find.bySemanticsLabel('Navigation bar'),
          matching: find.byType(BackdropFilter),
        ),
        findsOneWidget,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('mobile nav bar dark glass remains translucent', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final semantics = tester.ensureSemantics();
    try {
      const settings = SystemSettings();
      final configuredPrimaryTabs = appShellTabs.take(5).toList();
      const configuredOverflowTabs = <AppShellTab>[];
      final theme = AppTheme.materialYouDark(
        null,
        paletteSource: PaletteSource.custom,
        paletteSeedColorHex: '#9070A0',
        paletteMood: PaletteMood.tonal,
      );

      final router = GoRouter(
        initialLocation: AppRoutePaths.home,
        routes: [
          StatefulShellRoute.indexedStack(
            builder: (context, state, navigationShell) {
              return AppShell(navigationShell: navigationShell);
            },
            branches: [
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: AppRoutePaths.home,
                    builder: (context, state) =>
                        const Scaffold(body: SizedBox.expand()),
                  ),
                ],
              ),
            ],
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            activeNavBarTabsProvider.overrideWithValue(configuredPrimaryTabs),
            navBarOverflowTabsProvider.overrideWithValue(
              configuredOverflowTabs,
            ),
            systemSettingsProvider.overrideWith(
              (ref) => Stream.value(settings),
            ),
            isPinSetProvider.overrideWith((ref) async => false),
            syncStatusProvider.overrideWith(_FakeSyncStatusNotifier.new),
            pkAutoPollProvider.overrideWith(_FakePkAutoPollNotifier.new),
            pluralKitSyncProvider.overrideWith(_FakePluralKitSyncNotifier.new),
            habitsBadgeEnabledProvider.overrideWith((ref) => false),
            activeSessionsProvider.overrideWith(
              (ref) => Stream.value(const []),
            ),
            allMembersProvider.overrideWith((ref) => Stream.value(const [])),
            unreadConversationCountProvider.overrideWith((ref) => 0),
            frontingMigrationGateProvider.overrideWith(
              (ref) => FrontingMigrationGateStatus.complete,
            ),
          ],
          child: MaterialApp.router(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: const [Locale('en')],
            theme: theme,
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final navBarColor = _floatingNavBarDecorationColor(tester);
      final expectedNavBarColor = Color.alphaBlend(
        theme.colorScheme.primary.withValues(alpha: 0.06),
        theme.colorScheme.surfaceContainerHigh.withValues(alpha: 0.50),
      );

      expect(navBarColor, expectedNavBarColor);
      expect(
        navBarColor,
        isNot(
          Color.alphaBlend(
            theme.colorScheme.primary.withValues(alpha: 0.06),
            theme.colorScheme.surfaceContainer.withValues(alpha: 0.50),
          ),
        ),
      );
      expect(navBarColor.a, lessThan(0.56));
      expect(navBarColor.a, greaterThan(0.50));
      expect(
        find.descendant(
          of: find.bySemanticsLabel('Navigation bar'),
          matching: find.byType(BackdropFilter),
        ),
        findsOneWidget,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('mobile nav footer fade leaves content visible under glass', (
    tester,
  ) async {
    const backdropColor = Color(0xFFBFD7C4);

    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: FloatingNavBarBackdrop(height: 100, color: backdropColor),
      ),
    );

    final decoratedBox = tester.widget<DecoratedBox>(find.byType(DecoratedBox));
    final decoration = decoratedBox.decoration as BoxDecoration;
    final gradient = decoration.gradient! as LinearGradient;

    expect(gradient.colors[0], backdropColor.withValues(alpha: 0));
    expect(gradient.colors[1], backdropColor.withValues(alpha: 0.60));
    expect(gradient.colors[2], backdropColor.withValues(alpha: 0.86));
  });

  testWidgets('desktop sidebar hover fill snaps without a dark mid-tween', (
    tester,
  ) async {
    // Wide enough to cross the desktop breakpoint and render the sidebar.
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final semantics = tester.ensureSemantics();
    try {
      const settings = SystemSettings();
      final configuredPrimaryTabs = appShellTabs.take(5).toList();

      final router = GoRouter(
        initialLocation: AppRoutePaths.home,
        routes: [
          StatefulShellRoute.indexedStack(
            builder: (context, state, navigationShell) {
              return AppShell(navigationShell: navigationShell);
            },
            branches: [
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: AppRoutePaths.home,
                    builder: (context, state) =>
                        const Scaffold(body: SizedBox.expand()),
                  ),
                ],
              ),
            ],
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            activeNavBarTabsProvider.overrideWithValue(configuredPrimaryTabs),
            navBarOverflowTabsProvider.overrideWithValue(const <AppShellTab>[]),
            systemSettingsProvider.overrideWith(
              (ref) => Stream.value(settings),
            ),
            isPinSetProvider.overrideWith((ref) async => false),
            syncStatusProvider.overrideWith(_FakeSyncStatusNotifier.new),
            pkAutoPollProvider.overrideWith(_FakePkAutoPollNotifier.new),
            pluralKitSyncProvider.overrideWith(_FakePluralKitSyncNotifier.new),
            habitsBadgeEnabledProvider.overrideWith((ref) => false),
            activeSessionsProvider.overrideWith(
              (ref) => Stream.value(const []),
            ),
            allMembersProvider.overrideWith((ref) => Stream.value(const [])),
            unreadConversationCountProvider.overrideWith((ref) => 0),
            frontingMigrationGateProvider.overrideWith(
              (ref) => FrontingMigrationGateStatus.complete,
            ),
          ],
          child: MaterialApp.router(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: const [Locale('en')],
            theme: ThemeData(fontFamily: 'OpenDyslexic'),
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Home (index 0) is selected at the initial route, so Settings is a
      // guaranteed non-selected sidebar item to hover.
      final appShellContext = tester.element(find.byType(AppShell));
      final terminology = resolveTerminology(
        AppLocalizations.of(appShellContext),
        settings.terminology,
        customSingular: settings.customTerminology,
        customPlural: settings.customPluralTerminology,
        useEnglish: settings.terminologyUseEnglish,
      );
      final settingsLabel = appShellTabs
          .firstWhere((tab) => tab.id == AppShellTabId.settings)
          .localizedLabel(
            appShellContext,
            terminologyPlural: terminology.plural,
          );

      final labelFinder = find.text(settingsLabel);
      expect(labelFinder, findsOneWidget);

      final itemRegion = find
          .ancestor(of: labelFinder, matching: find.byType(MouseRegion))
          .first;

      // An implicit fill animation tweens from Colors.transparent (transparent
      // black), so mid-fade frames render the dark flash this fix removed.
      expect(
        find.descendant(
          of: itemRegion,
          matching: find.byType(AnimatedContainer),
        ),
        findsNothing,
        reason: 'Sidebar fill must snap, not implicitly animate.',
      );

      // Behavioral check: one frame after the pointer enters, the painted fill
      // is already the full hover color — not a faint dark mid-tween value.
      final theme = Theme.of(appShellContext);
      final expectedHoverColor = theme.colorScheme.surfaceContainerHigh
          .withValues(alpha: theme.brightness == Brightness.dark ? 0.62 : 0.72);

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await gesture.moveTo(tester.getCenter(labelFinder));
      await tester.pump(const Duration(milliseconds: 1));

      final paintedFill = tester
          .widgetList<DecoratedBox>(
            find.descendant(
              of: itemRegion,
              matching: find.byType(DecoratedBox),
            ),
          )
          .map((box) => box.decoration)
          .whereType<BoxDecoration>()
          .firstWhere(
            (decoration) =>
                decoration.borderRadius != null && decoration.color != null,
          );

      expect(
        paintedFill.color,
        expectedHoverColor,
        reason:
            'Hover fill should be applied in a single frame, with no dark '
            'transparent-black intermediate.',
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    } finally {
      semantics.dispose();
    }
  });
}

Color _floatingNavBarDecorationColor(WidgetTester tester) {
  final navBarContainers = find.descendant(
    of: find.bySemanticsLabel('Navigation bar'),
    matching: find.byType(Container),
  );
  for (final element in navBarContainers.evaluate()) {
    final container = element.widget as Container;
    final decoration = container.decoration;
    final renderObject = element.renderObject;
    if (renderObject is RenderBox &&
        renderObject.size.height >= kFloatingNavBarHeight &&
        decoration is BoxDecoration &&
        decoration.color != null) {
      return decoration.color!;
    }
  }
  throw TestFailure('Could not find floating nav bar decoration color.');
}

class _FakeSyncStatusNotifier extends SyncStatusNotifier {
  @override
  SyncStatus build() => const SyncStatus();
}

class _UnreadCountNotifier extends Notifier<int> {
  @override
  int build() => 0;
  set value(int newValue) => state = newValue;
}

final _unreadCountStateProvider = NotifierProvider<_UnreadCountNotifier, int>(
  _UnreadCountNotifier.new,
);

class _FakePkAutoPollNotifier extends PkAutoPollNotifier {
  @override
  void build() {}

  @override
  void markForegrounded(bool value) {}

  @override
  void noteLocalPush() {}
}

class _FakePluralKitSyncNotifier extends PluralKitSyncNotifier {
  @override
  PluralKitSyncState build() => const PluralKitSyncState();

  @override
  Future<int> pushPendingSwitches() async => 0;

  @override
  Future<void> pushMemberUpdate(domain.Member member) async {}
}
