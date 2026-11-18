import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
import 'package:prism_plurality/core/database/database_providers.dart'
    show appPreferenceRepositoryProvider;
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/theme/app_theme.dart';
import 'package:prism_plurality/shared/theme/prism_text_scaler.dart';
import 'package:prism_plurality/shared/utils/nav_bar_layout.dart';
import '../../helpers/fake_repositories.dart' show FakeAppPreferenceRepository;
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
        labelVisibility: NavBarLabelVisibility.always,
        labelStyleMode: NavBarLabelStyle.truncated,
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
      labelVisibility: NavBarLabelVisibility.never,
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

  test('icon-only mode uses larger centered collapsed icons', () {
    expect(kNavBarIconOnlyItemIconSize, greaterThan(kNavBarItemIconSize));

    final collapsedTop = navBarPrimaryPillTop(
      rowHeight: kFloatingNavBarHeight,
      prominentIcons: true,
      labelVisibility: 0,
    );
    final expandedTop = navBarPrimaryPillTop(
      rowHeight: kFloatingNavBarHeight,
      prominentIcons: true,
      labelVisibility: 1,
    );
    final expandedPaintOffset = navBarPrimaryPillPaintOffsetY(
      rowHeight: kFloatingNavBarHeight,
      prominentIcons: true,
      labelVisibility: 1,
    );
    final expandedScaleInset =
        (navBarPrimaryPillLayoutHeight(prominentIcons: true) -
            navBarPrimaryPillHeight(prominentIcons: true, labelVisibility: 1)) /
        2;

    expect(
      collapsedTop,
      (kFloatingNavBarHeight - kNavBarIconOnlyItemIconHeight) / 2,
    );
    expect(
      navBarLabelRevealLiftY(labelVisibility: 1),
      (kNavBarLabelFontSize + 4) / 2,
    );
    expect(
      navBarPrimaryPillHeight(prominentIcons: true, labelVisibility: 0),
      kNavBarIconOnlyItemIconHeight,
    );
    expect(
      navBarPrimaryPillLayoutHeight(prominentIcons: true),
      kNavBarIconOnlyItemIconHeight,
    );
    expect(
      navBarPrimaryPillHeight(prominentIcons: true, labelVisibility: 1),
      kNavBarItemIconHeight,
    );
    expect(
      navBarPrimaryPillScaleY(prominentIcons: true, labelVisibility: 0),
      1,
    );
    expect(
      navBarPrimaryPillScaleY(prominentIcons: true, labelVisibility: 1),
      kNavBarItemIconHeight / kNavBarIconOnlyItemIconHeight,
    );
    expect(
      navBarPrimaryPillTop(
        rowHeight: kFloatingNavBarHeight,
        prominentIcons: false,
        labelVisibility: 0,
      ),
      8,
    );
    expect(
      navBarPrimaryPillTop(
        rowHeight: kFloatingNavBarHeight,
        prominentIcons: true,
        labelVisibility: navBarEffectiveLabelVisibility(
          labelVisibility: NavBarLabelVisibility.never,
          expandProgress: 1,
        ),
      ),
      collapsedTop,
    );
    expect(
      navBarPrimaryPillPaintOffsetY(
        rowHeight: kFloatingNavBarHeight,
        prominentIcons: true,
        labelVisibility: navBarEffectiveLabelVisibility(
          labelVisibility: NavBarLabelVisibility.never,
          expandProgress: 1,
        ),
      ),
      0,
    );
    expect(
      navBarPrimaryPillTop(
        rowHeight: kFloatingNavBarHeight,
        prominentIcons: true,
        labelVisibility: 1,
      ),
      expandedTop,
    );
    expect(expandedTop, lessThan(collapsedTop));
    expect(
      navBarPrimaryPillLayoutTop(
            rowHeight: kFloatingNavBarHeight,
            prominentIcons: true,
          ) +
          expandedPaintOffset +
          expandedScaleInset,
      closeTo(expandedTop, 0.001),
      reason: 'The paint transform should target the scaled pill bounds.',
    );

    expect(
      navBarPrimaryContentOffsetX(
        segmentWidth: 64,
        prominentIcons: true,
        pillWidth: 56,
      ),
      4,
    );
    expect(
      navBarPrimaryContentOffsetX(
        segmentWidth: 64,
        prominentIcons: false,
        pillWidth: 48,
      ),
      0,
    );
    expect(
      navBarEffectiveLabelVisibility(
        labelVisibility: NavBarLabelVisibility.whenExpanded,
        expandProgress: 0.5,
      ),
      0.5,
    );
    expect(
      navBarEffectiveLabelVisibility(
        labelVisibility: NavBarLabelVisibility.never,
        expandProgress: 1,
      ),
      0,
    );
    expect(
      navBarEffectiveLabelVisibility(
        labelVisibility: NavBarLabelVisibility.always,
        expandProgress: 0,
      ),
      1,
    );
    expect(navBarIconOpticalOffsetY(prominentIcons: true), 1);
    expect(navBarIconOpticalOffsetY(prominentIcons: false), 0);
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
                return AppShell(
                  navigationShell: navigationShell,
                  routePath: state.uri.path,
                );
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
              appPreferenceRepositoryProvider.overrideWithValue(
                FakeAppPreferenceRepository(),
              ),
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
                return AppShell(
                  navigationShell: navigationShell,
                  routePath: state.uri.path,
                );
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
              appPreferenceRepositoryProvider.overrideWithValue(
                FakeAppPreferenceRepository(),
              ),
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
        expect(
          tester.getBottomLeft(navBarClip).dy,
          closeTo(800 - kFloatingNavBarBottomMargin, 0.01),
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

  testWidgets('icon-only mode reveals primary and overflow labels when expanded', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final semantics = tester.ensureSemantics();
    try {
      const settings = SystemSettings(
        navBarLabelDisplayMode: NavBarLabelDisplayMode.iconsOnly,
        navBarRevealLabelsWhenExpanded: true,
      );
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
              return AppShell(
                navigationShell: navigationShell,
                routePath: state.uri.path,
              );
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
            appPreferenceRepositoryProvider.overrideWithValue(
              FakeAppPreferenceRepository(),
            ),
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
            theme: ThemeData(fontFamily: 'OpenDyslexic'),
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        _navLabelFinder(AppShellTabId.home),
        findsNothing,
        reason:
            'Hidden icon-only labels should not build text during collapsed frames.',
      );
      expect(
        _navIconSlotCenterY(tester, AppShellTabId.home),
        closeTo(_floatingNavBarCenterY(tester), 0.5),
        reason: 'Collapsed icon-only items should be centered in the nav bar.',
      );
      expect(
        _navIconSlotCenterX(tester, AppShellTabId.home),
        closeTo(_selectedPillCenterX(tester), 0.5),
        reason: 'Selected icon-only items should be centered in the pill.',
      );
      expect(
        _navIconVisualOffsetY(tester, AppShellTabId.home),
        navBarIconOpticalOffsetY(prominentIcons: true),
        reason:
            'Icon-only glyphs should be optically nudged down inside the pill.',
      );

      final collapsedPillScaleY = _selectedPillScaleY(tester);
      final collapsedPillCenterY = _selectedPillCenterY(tester);

      await tester.tap(find.bySemanticsLabel('More tabs'));
      await tester.pumpAndSettle();

      expect(
        _selectedPillScaleY(tester),
        lessThan(collapsedPillScaleY),
        reason:
            'Icon-only selected pills should shorten when expanded labels appear.',
      );
      expect(
        _selectedPillCenterY(tester),
        lessThan(collapsedPillCenterY - 4),
        reason: 'The selected pill should lift as icon-only labels animate in.',
      );
      expect(
        _selectedPillCenterY(tester),
        closeTo(_navIconSlotCenterY(tester, AppShellTabId.home), 1.1),
        reason: 'The lifted selected pill should remain centered on the icon.',
      );
      expect(
        _navLabelOpacities(tester, AppShellTabId.home),
        contains(1),
        reason:
            'The expanded icon-only menu should reveal labels in the primary row.',
      );
      expect(
        _navLabelOpacities(tester, AppShellTabId.timeline),
        contains(1),
        reason:
            'The expanded icon-only menu should reveal labels in overflow rows.',
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    } finally {
      semantics.dispose();
    }
  });

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
              return AppShell(
                navigationShell: navigationShell,
                routePath: state.uri.path,
              );
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
            appPreferenceRepositoryProvider.overrideWithValue(
              FakeAppPreferenceRepository(),
            ),
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
              return AppShell(
                navigationShell: navigationShell,
                routePath: state.uri.path,
              );
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
            appPreferenceRepositoryProvider.overrideWithValue(
              FakeAppPreferenceRepository(),
            ),
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
              return AppShell(
                navigationShell: navigationShell,
                routePath: state.uri.path,
              );
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
            appPreferenceRepositoryProvider.overrideWithValue(
              FakeAppPreferenceRepository(),
            ),
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

  // ---------------------------------------------------------------------
  // Desktop sidebar at Windows accessibility text sizes:
  // labels were laid out on one unconstrained line and clipped by a fixed
  // 38pt row height, so the panel showed cut-off text. These are real
  // AppShell tests: they measure the actual RenderParagraph boxes of the
  // sidebar labels at the combined system + app text scale.
  // ---------------------------------------------------------------------

  testWidgets(
    'desktop sidebar keeps its default panel and row metrics at scale 1',
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        final shell = await _pumpDesktopSidebarShell(
          tester,
          windowSize: const Size(1280, 900),
          textScaler: const TextScaler.linear(1),
        );

        // Default-size design is unchanged: 200pt panel, 38pt rows.
        expect(_sidebarPanelRect(tester).width, 200.0);

        final viewportRect = _sidebarViewportRect(tester);
        for (final label in shell.labels) {
          _expectSidebarLabelFits(
            tester,
            label,
            viewportRect: viewportRect,
            scaleDescription: '1x',
            expectedTextScaler: const TextScaler.linear(1),
          );
          expect(
            _sidebarTextMetrics(_sidebarLabelParagraph(tester, label)).lines,
            1,
            reason: '"$label" fits on one line at the default text size.',
          );
          expect(
            _sidebarItemRect(tester, label).height,
            38.0,
            reason: 'Sidebar rows keep their 38pt default height at 1x.',
          );
        }

        // Tab order and localized labels are unchanged.
        final renderedLabels = [
          for (final element
              in find
                  .descendant(
                    of: _sidebarScrollView(),
                    matching: find.byType(Text),
                  )
                  .evaluate())
            (element.widget as Text).data,
        ];
        expect(renderedLabels, shell.labels);
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets(
    'desktop sidebar wraps labels and grows rows at 3.375x text scale',
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        final shell = await _pumpDesktopSidebarShell(
          tester,
          windowSize: const Size(1280, 900),
          // Windows 225% accessibility scaling times the app's 1.5 font
          // preference, composed the way lib/app.dart composes it.
          textScaler: const PrismTextScaler(TextScaler.linear(2.25), 1.5),
          chatUnreadCount: 2,
        );

        final viewportRect = _sidebarViewportRect(tester);
        for (final label in shell.labels) {
          _expectSidebarLabelFits(
            tester,
            label,
            viewportRect: viewportRect,
            scaleDescription: '3.375x',
            expectedTextScaler: const PrismTextScaler(
              TextScaler.linear(2.25),
              1.5,
            ),
          );
          final paragraph = _sidebarLabelParagraph(tester, label);
          expect(
            paragraph.size.height,
            greaterThan(30.0),
            reason:
                '"$label" still renders at the scaled text size; there is no '
                'shrink-to-fit cap on sidebar labels.',
          );
          expect(
            _sidebarItemRect(tester, label).height,
            greaterThanOrEqualTo(38.0),
            reason: 'Rows never shrink below their default 38pt height.',
          );
        }

        final panelRect = _sidebarPanelRect(tester);
        expect(
          panelRect.width,
          greaterThan(200.0),
          reason:
              'The panel grows with the label text scale so scaled labels '
              'need fewer mid-word wraps.',
        );
        expect(
          panelRect.width,
          lessThanOrEqualTo(320.5),
          reason: 'The panel width stays bounded at large text sizes.',
        );

        final contentRect = tester.getRect(
          find.byKey(const ValueKey('route_body_home')),
        );
        expect(
          contentRect.left,
          greaterThanOrEqualTo(panelRect.right - 0.5),
          reason: 'Sidebar and content must not overlap.',
        );
        expect(
          contentRect.width,
          greaterThanOrEqualTo(1280 * 0.5),
          reason: 'A wider panel must not starve the main content column.',
        );

        // Badge presence and the declared accessibility contract survive the
        // layout change; asserted separately from the geometry above.
        final chatLabel = _shellLabel(shell, AppShellTabId.chat);
        final chatItem = _sidebarItemFinder(chatLabel);
        expect(
          find.descendant(of: chatItem, matching: find.text('2')),
          findsOneWidget,
          reason: 'The unread chat badge still renders inside the row.',
        );

        final groupSemantics = _sidebarGroupSemantics(tester);
        expect(
          groupSemantics.container,
          isTrue,
          reason: 'The sidebar is still a semantics container.',
        );
        expect(
          groupSemantics.properties.label,
          AppLocalizations.of(
            tester.element(find.byType(AppShell)),
          ).mainNavigation,
          reason: 'The sidebar still announces itself as the main navigation.',
        );
        for (var index = 0; index < shell.labels.length; index++) {
          final label = shell.labels[index];
          final itemSemantics = _sidebarItemSemantics(tester, label);
          expect(
            itemSemantics.properties.label,
            label,
            reason: 'The "$label" row still exposes its localized label.',
          );
          expect(
            itemSemantics.properties.button,
            isTrue,
            reason: 'The "$label" row is still a button.',
          );
          expect(
            itemSemantics.properties.selected,
            index == 0,
            reason: 'Only the current destination is announced as selected.',
          );
        }
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets(
    'desktop sidebar wraps a long custom terminology label at 4.5x scale',
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        final shell = await _pumpDesktopSidebarShell(
          tester,
          windowSize: const Size(1280, 900),
          // Beyond the app's 1.5 cap on purpose: a stress case for future
          // scalers and narrow panels.
          textScaler: const PrismTextScaler(TextScaler.linear(2.25), 2.0),
          settings: const SystemSettings(
            terminology: SystemTerminology.custom,
            customTerminology: 'Systemmitglied',
            customPluralTerminology: 'Systemmitglieder',
          ),
        );

        final membersLabel = _shellLabel(shell, AppShellTabId.members);
        expect(membersLabel, 'Systemmitglieder');

        final viewportRect = _sidebarViewportRect(tester);
        for (final label in shell.labels) {
          _expectSidebarLabelFits(
            tester,
            label,
            viewportRect: viewportRect,
            scaleDescription: '4.5x',
            expectedTextScaler: const PrismTextScaler(
              TextScaler.linear(2.25),
              2.0,
            ),
          );
        }

        // A long word has to break across lines instead of painting past the
        // panel edge.
        expect(
          _sidebarTextMetrics(
            _sidebarLabelParagraph(tester, membersLabel),
          ).lines,
          greaterThanOrEqualTo(2),
          reason:
              'A 16-character custom terminology label cannot fit on one line '
              'at 4.5x in a bounded panel, so it must wrap.',
        );

        final panelRect = _sidebarPanelRect(tester);
        expect(panelRect.width, lessThanOrEqualTo(320.5));
        expect(
          tester.getRect(find.byKey(const ValueKey('route_body_home'))).width,
          greaterThanOrEqualTo(1280 * 0.5),
          reason: 'The main content column stays usable at the stress scale.',
        );
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets(
    'desktop sidebar keeps Settings reachable on a short narrow window at 3.375x',
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        final shell = await _pumpDesktopSidebarShell(
          tester,
          windowSize: const Size(768, 480),
          textScaler: const PrismTextScaler(TextScaler.linear(2.25), 1.5),
          // The order from the report, with Settings at the bottom of the
          // list, so the last row is the one that has to stay reachable.
          displayOrder: const [
            AppShellTabId.members,
            AppShellTabId.home,
            AppShellTabId.notes,
            AppShellTabId.chat,
            AppShellTabId.boards,
            AppShellTabId.sleep,
            AppShellTabId.media,
            AppShellTabId.polls,
            AppShellTabId.statistics,
            AppShellTabId.timeline,
            AppShellTabId.groups,
            AppShellTabId.settings,
          ],
        );

        final panelRect = _sidebarPanelRect(tester);
        expect(panelRect.width, greaterThanOrEqualTo(200.0));
        expect(
          panelRect.width,
          lessThanOrEqualTo(768 * 0.45),
          reason: 'The panel stays bounded on a narrow desktop window.',
        );
        expect(
          tester.getRect(find.byKey(const ValueKey('route_body_home'))).width,
          greaterThanOrEqualTo(768 * 0.55),
          reason: 'Main content keeps the majority of a narrow desktop window.',
        );

        final viewportRect = _sidebarViewportRect(tester);
        for (final label in shell.labels) {
          _expectSidebarLabelFits(
            tester,
            label,
            viewportRect: viewportRect,
            scaleDescription: '3.375x on a 768pt window',
            expectedTextScaler: const PrismTextScaler(
              TextScaler.linear(2.25),
              1.5,
            ),
          );
        }

        // The list is taller than the panel here, so Settings starts clipped
        // below the fold and must be reachable by scrolling.
        final settingsLabel = _shellLabel(shell, AppShellTabId.settings);
        expect(
          _sidebarItemRect(tester, settingsLabel).bottom,
          greaterThan(viewportRect.bottom),
          reason: 'At this scale the sidebar content overflows its panel.',
        );

        expect(find.byType(SingleChildScrollView), findsOneWidget);
        await tester.drag(
          find.byType(SingleChildScrollView),
          const Offset(0, -4000),
        );
        await tester.pumpAndSettle();

        final scrolledViewport = _sidebarViewportRect(tester);
        final settingsRect = _sidebarItemRect(tester, settingsLabel);
        expect(
          settingsRect.top,
          greaterThanOrEqualTo(scrolledViewport.top - 0.5),
          reason: 'Scrolling reaches the bottom of the sidebar.',
        );
        expect(
          settingsRect.bottom,
          lessThanOrEqualTo(scrolledViewport.bottom + 0.5),
          reason: 'The Settings row is fully visible after scrolling.',
        );

        await tester.tap(find.text(settingsLabel));
        await tester.pumpAndSettle();

        expect(
          shell.router.routeInformationProvider.value.uri.path,
          AppRoutePaths.settings,
          reason: 'Tapping Settings navigates to the settings branch.',
        );
        expect(
          find.byKey(const ValueKey('route_body_settings')),
          findsOneWidget,
          reason: 'The settings branch renders its own content.',
        );

        // Selection moved to Settings and away from Home.
        final theme = Theme.of(tester.element(find.byType(AppShell)));
        expect(
          _sidebarItemIconColor(tester, settingsLabel),
          theme.colorScheme.primary,
          reason: 'The selected destination is tinted with the accent color.',
        );
        expect(
          _sidebarItemIconColor(tester, _shellLabel(shell, AppShellTabId.home)),
          isNot(theme.colorScheme.primary),
          reason: 'The previously selected destination is no longer selected.',
        );
        expect(
          _sidebarItemSemantics(tester, settingsLabel).properties.selected,
          isTrue,
          reason: 'The Settings destination is announced as selected.',
        );
        expect(
          _sidebarItemSemantics(
            tester,
            _shellLabel(shell, AppShellTabId.home),
          ).properties.selected,
          isFalse,
          reason: 'Home is announced as not selected after navigating away.',
        );
      } finally {
        semantics.dispose();
      }
    },
  );
}

typedef _DesktopSidebarShell = ({
  List<AppShellTab> tabs,
  List<String> labels,
  GoRouter router,
});

/// Pumps the real [AppShell] on a desktop-sized Windows window with the app's
/// composed text scaler, and returns the tab list, the rendered labels and the
/// router so tests can assert navigation.
Future<_DesktopSidebarShell> _pumpDesktopSidebarShell(
  WidgetTester tester, {
  required Size windowSize,
  required TextScaler textScaler,
  SystemSettings settings = const SystemSettings(),
  int chatUnreadCount = 0,
  List<AppShellTabId>? displayOrder,
}) async {
  tester.view.physicalSize = windowSize;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  // Branches follow branchIndex, like the real router; the sidebar renders
  // the configured tab order, which is user-reorderable.
  final displayIds = displayOrder ?? [for (final tab in appShellTabs) tab.id];
  final tabs = [
    for (final id in displayIds) appShellTabs.firstWhere((tab) => tab.id == id),
  ];
  final router = GoRouter(
    initialLocation: AppRoutePaths.home,
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) => AppShell(
          navigationShell: navigationShell,
          routePath: state.uri.path,
        ),
        branches: [
          for (final tab in appShellTabs)
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: tab.rootLocation,
                  builder: (context, state) => Scaffold(
                    body: Container(key: ValueKey('route_body_${tab.id.name}')),
                  ),
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
        activeNavBarTabsProvider.overrideWithValue(tabs),
        appPreferenceRepositoryProvider.overrideWithValue(
          FakeAppPreferenceRepository(),
        ),
        navBarOverflowTabsProvider.overrideWithValue(const <AppShellTab>[]),
        systemSettingsProvider.overrideWith((ref) => Stream.value(settings)),
        isPinSetProvider.overrideWith((ref) async => false),
        syncStatusProvider.overrideWith(_FakeSyncStatusNotifier.new),
        pkAutoPollProvider.overrideWith(_FakePkAutoPollNotifier.new),
        pluralKitSyncProvider.overrideWith(_FakePluralKitSyncNotifier.new),
        habitsBadgeEnabledProvider.overrideWith((ref) => false),
        activeSessionsProvider.overrideWith((ref) => Stream.value(const [])),
        allMembersProvider.overrideWith((ref) => Stream.value(const [])),
        unreadConversationCountProvider.overrideWith((ref) => chatUnreadCount),
        frontingMigrationGateProvider.overrideWith(
          (ref) => FrontingMigrationGateStatus.complete,
        ),
      ],
      child: MaterialApp.router(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: const [Locale('en')],
        theme: ThemeData(fontFamily: 'OpenDyslexic'),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: textScaler),
          child: child!,
        ),
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();

  final appShellContext = tester.element(find.byType(AppShell));
  final terminology = resolveTerminology(
    AppLocalizations.of(appShellContext),
    settings.terminology,
    customSingular: settings.customTerminology,
    customPlural: settings.customPluralTerminology,
    useEnglish: settings.terminologyUseEnglish,
  );
  final labels = [
    for (final tab in tabs)
      tab.localizedLabel(
        appShellContext,
        terminologyPlural: terminology.plural,
      ),
  ];
  return (tabs: tabs, labels: labels, router: router);
}

/// The desktop sidebar's scroll view.
///
/// It is the only [SingleChildScrollView] inside [AppShell], so structural
/// lookups scoped to the app shell cannot reach the content beside the panel.
/// Deliberately not keyed off the "Main navigation" semantics label: this
/// harness does not surface that group node through `find.bySemanticsLabel`
/// even though the nav bar's equivalent node is found, so scoping must not
/// depend on the semantics tree.
Finder _sidebarScrollView() {
  final scrollView = find.descendant(
    of: find.byType(AppShell),
    matching: find.byType(SingleChildScrollView),
  );
  expect(
    scrollView,
    findsOneWidget,
    reason: 'The desktop shell renders exactly one sidebar scroll view.',
  );
  return scrollView;
}

/// The floating panel: the [Container] that wraps the sidebar scroll view.
Rect _sidebarPanelRect(WidgetTester tester) {
  final panel = find
      .ancestor(of: _sidebarScrollView(), matching: find.byType(Container))
      .first;
  expect(
    panel,
    findsOneWidget,
    reason: 'The sidebar panel wraps its scroll view.',
  );
  return tester.getRect(panel);
}

/// The sidebar scroll viewport; this is the rectangle that clips the panel.
Rect _sidebarViewportRect(WidgetTester tester) =>
    tester.getRect(_sidebarScrollView());

/// The sidebar's declared accessibility group.
///
/// The contract is read from the widget that publishes it, not from the
/// semantics tree, for the reason in [_sidebarScrollView].
Semantics _sidebarGroupSemantics(WidgetTester tester) {
  final finder = find
      .ancestor(of: _sidebarScrollView(), matching: find.byType(Semantics))
      .first;
  expect(
    finder,
    findsOneWidget,
    reason: 'The sidebar publishes a semantics group.',
  );
  return tester.widget<Semantics>(finder);
}

/// The declared accessibility contract of one sidebar destination.
Semantics _sidebarItemSemantics(WidgetTester tester, String label) {
  final finder = find
      .ancestor(of: find.text(label), matching: find.byType(Semantics))
      .first;
  expect(
    finder,
    findsOneWidget,
    reason: 'The "$label" row publishes semantics.',
  );
  return tester.widget<Semantics>(finder);
}

Finder _sidebarItemFinder(String label) {
  final item = find
      .ancestor(of: find.text(label), matching: find.byType(GestureDetector))
      .first;
  expect(item, findsOneWidget, reason: 'Expected a sidebar row for "$label".');
  return item;
}

Rect _sidebarItemRect(WidgetTester tester, String label) =>
    tester.getRect(_sidebarItemFinder(label));

RenderParagraph _sidebarLabelParagraph(WidgetTester tester, String label) {
  final finder = find.text(label);
  expect(
    finder,
    findsOneWidget,
    reason: 'Expected one sidebar label "$label".',
  );
  return tester.renderObject<RenderParagraph>(finder);
}

Color? _sidebarItemIconColor(WidgetTester tester, String label) {
  final icon = find
      .descendant(of: _sidebarItemFinder(label), matching: find.byType(Icon))
      .first;
  expect(icon, findsOneWidget);
  return tester.widget<Icon>(icon).color;
}

String _shellLabel(_DesktopSidebarShell shell, AppShellTabId id) {
  final index = shell.tabs.indexWhere((tab) => tab.id == id);
  expect(index, isNonNegative, reason: 'Tab $id belongs to the shell.');
  return shell.labels[index];
}

/// Re-lays out a sidebar label's paragraph at the width it was given, so the
/// height and line count it *needs* can be compared with the box it got.
({double height, int lines}) _sidebarTextMetrics(RenderParagraph paragraph) {
  final maxWidth = paragraph.constraints.maxWidth;
  final layoutWidth = maxWidth.isFinite ? maxWidth : paragraph.size.width;
  final painter = TextPainter(
    text: paragraph.text,
    textAlign: paragraph.textAlign,
    textDirection: paragraph.textDirection,
    textScaler: paragraph.textScaler,
    maxLines: paragraph.maxLines,
    locale: paragraph.locale,
    strutStyle: paragraph.strutStyle,
    textHeightBehavior: paragraph.textHeightBehavior,
    textWidthBasis: paragraph.textWidthBasis,
  )..layout(maxWidth: layoutWidth);
  final metrics = (
    height: painter.height,
    lines: painter.computeLineMetrics().length,
  );
  painter.dispose();
  return metrics;
}

/// Asserts one sidebar label is fully painted inside its row and the panel.
void _expectSidebarLabelFits(
  WidgetTester tester,
  String label, {
  required Rect viewportRect,
  required String scaleDescription,
  required TextScaler expectedTextScaler,
}) {
  final paragraph = _sidebarLabelParagraph(tester, label);
  final labelRect = tester.getRect(find.text(label));
  final itemRect = _sidebarItemRect(tester, label);
  final metrics = _sidebarTextMetrics(paragraph);
  expect(paragraph.text.style?.fontSize, 13);
  expect(
    paragraph.textScaler.scale(13),
    expectedTextScaler.scale(13),
    reason: 'The sidebar must keep the requested system and Prism text scale.',
  );

  // Nav labels may use as many lines as they need: no ellipsis, no line cap
  // and no clipping overflow hiding the problem.
  expect(
    paragraph.maxLines,
    isNull,
    reason: '"$label" at $scaleDescription must not cap its line count.',
  );
  expect(
    paragraph.overflow,
    isNot(TextOverflow.ellipsis),
    reason: '"$label" at $scaleDescription must not be truncated.',
  );
  expect(
    paragraph.softWrap,
    isTrue,
    reason: '"$label" at $scaleDescription must wrap instead of clipping.',
  );

  // The row has to be as tall as the text needs; a fixed height clips glyphs.
  expect(
    paragraph.size.height,
    greaterThanOrEqualTo(metrics.height - 0.5),
    reason:
        '"$label" at $scaleDescription is laid out in '
        '${paragraph.size.height}px but its text needs ${metrics.height}px, '
        'so the row clips its glyphs.',
  );

  // The label box stays inside its row...
  expect(
    labelRect.left,
    greaterThanOrEqualTo(itemRect.left - 0.5),
    reason: '"$label" at $scaleDescription paints past the left of its row.',
  );
  expect(
    labelRect.right,
    lessThanOrEqualTo(itemRect.right + 0.5),
    reason: '"$label" at $scaleDescription paints past the right of its row.',
  );
  expect(
    labelRect.top,
    greaterThanOrEqualTo(itemRect.top - 0.5),
    reason: '"$label" at $scaleDescription paints above its row.',
  );
  expect(
    labelRect.bottom,
    lessThanOrEqualTo(itemRect.bottom + 0.5),
    reason: '"$label" at $scaleDescription paints below its row.',
  );

  // ...and inside the scroll viewport, whose edge clips it against the panel.
  expect(
    labelRect.left,
    greaterThanOrEqualTo(viewportRect.left - 0.5),
    reason: '"$label" at $scaleDescription is clipped at the panel edge.',
  );
  expect(
    labelRect.right,
    lessThanOrEqualTo(viewportRect.right + 0.5),
    reason: '"$label" at $scaleDescription is clipped at the panel edge.',
  );

  // Every glyph box stays inside the paragraph, so no word runs past the panel.
  final boxes = paragraph.getBoxesForSelection(
    TextSelection(baseOffset: 0, extentOffset: label.length),
  );
  expect(
    boxes,
    isNotEmpty,
    reason: 'No glyph boxes were reported for "$label".',
  );
  final widestGlyphRight = boxes
      .map((box) => box.right)
      .fold<double>(0, (widest, right) => right > widest ? right : widest);
  expect(
    widestGlyphRight,
    lessThanOrEqualTo(paragraph.size.width + 0.5),
    reason:
        '"$label" at $scaleDescription paints glyphs outside its own box, so '
        'they are clipped.',
  );
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

double _floatingNavBarCenterY(WidgetTester tester) {
  final navBarClip = find
      .descendant(
        of: find.bySemanticsLabel('Navigation bar'),
        matching: find.byType(ClipRRect),
      )
      .first;
  return tester.getCenter(navBarClip).dy;
}

double _navIconSlotCenterY(WidgetTester tester, AppShellTabId tabId) {
  final slot = find.byKey(ValueKey('nav_icon_slot_${tabId.name}'));
  expect(slot, findsOneWidget);
  return tester.getCenter(slot).dy;
}

double _navIconVisualOffsetY(WidgetTester tester, AppShellTabId tabId) {
  final icon = find.byKey(ValueKey('nav_icon_visual_${tabId.name}'));
  expect(icon, findsOneWidget);
  final transform = tester.widget<Transform>(icon);
  return transform.transform.getTranslation().y;
}

double _navIconSlotCenterX(WidgetTester tester, AppShellTabId tabId) {
  final slot = find.byKey(ValueKey('nav_icon_slot_${tabId.name}'));
  expect(slot, findsOneWidget);
  return tester.getCenter(slot).dx;
}

double _selectedPillCenterX(WidgetTester tester) {
  final pill = find.byKey(const ValueKey('nav_selected_pill'));
  expect(pill, findsOneWidget);
  return tester.getCenter(pill).dx;
}

double _selectedPillCenterY(WidgetTester tester) {
  final pill = find.byKey(const ValueKey('nav_selected_pill'));
  expect(pill, findsOneWidget);
  return tester.getCenter(pill).dy;
}

double _selectedPillScaleY(WidgetTester tester) {
  final transform = find.byKey(const ValueKey('nav_selected_pill_transform'));
  expect(transform, findsOneWidget);
  return tester.widget<Transform>(transform).transform.storage[5];
}

List<double> _navLabelOpacities(WidgetTester tester, AppShellTabId tabId) {
  final label = _navLabelFinder(tabId);
  expect(label, findsOneWidget);

  final opacities = tester
      .widgetList<Opacity>(
        find.ancestor(of: label, matching: find.byType(Opacity)),
      )
      .map((opacity) => opacity.opacity)
      .toList();
  return opacities.isEmpty ? [1.0] : opacities;
}

Finder _navLabelFinder(AppShellTabId tabId) {
  return find.byKey(ValueKey('nav_label_${tabId.name}'));
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
