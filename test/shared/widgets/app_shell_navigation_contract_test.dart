import 'dart:async';

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
import 'package:prism_plurality/features/fronting/migration/fronting_migration_service.dart';
import 'package:prism_plurality/features/fronting/migration/providers/fronting_migration_providers.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_providers.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/pluralkit/providers/pk_auto_poll_provider.dart';
import 'package:prism_plurality/features/pluralkit/providers/pluralkit_providers.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_sync_service.dart';
import 'package:prism_plurality/features/settings/providers/pin_lock_providers.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/widgets/app_shell.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final fontLoader = FontLoader('OpenDyslexic')
      ..addFont(rootBundle.load('assets/fonts/OpenDyslexic-Regular.otf'))
      ..addFont(rootBundle.load('assets/fonts/OpenDyslexic-Bold.otf'));
    await fontLoader.load();
  });

  testWidgets('all shell root routes show the mobile nav bar', (tester) async {
    final router = await _pumpContractApp(tester);

    for (final tab in appShellTabs) {
      router.go(tab.rootLocation);
      await tester.pumpAndSettle();

      expect(
        find.text(_rootTitle(tab.rootLocation)),
        findsOneWidget,
        reason: '${tab.rootLocation} should render its root page.',
      );
      _expectNavBar(tester, isVisible: true, reason: tab.rootLocation);
    }

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets(
    'first-level detail routes hide nav and Android back returns root',
    (tester) async {
      final router = await _pumpContractApp(tester);

      const cases = [
        _SingleStepContract(
          name: 'chat conversation',
          rootLocation: AppRoutePaths.chat,
          actionLabel: _openChatConversation,
          detailTitle: _chatConversationTitle,
        ),
        _SingleStepContract(
          name: 'habit detail',
          rootLocation: AppRoutePaths.habits,
          actionLabel: _openHabitDetail,
          detailTitle: _habitDetailTitle,
        ),
        _SingleStepContract(
          name: 'poll detail',
          rootLocation: AppRoutePaths.polls,
          actionLabel: _openPollDetail,
          detailTitle: _pollDetailTitle,
        ),
        _SingleStepContract(
          name: 'settings features',
          rootLocation: AppRoutePaths.settings,
          actionLabel: _openSettingsFeatures,
          detailTitle: _settingsFeaturesTitle,
        ),
        _SingleStepContract(
          name: 'member detail',
          rootLocation: AppRoutePaths.members,
          actionLabel: _openMemberDetail,
          detailTitle: _memberDetailTitle,
        ),
        _SingleStepContract(
          name: 'note detail',
          rootLocation: AppRoutePaths.notes,
          actionLabel: _openNoteDetail,
          detailTitle: _noteDetailTitle,
        ),
        _SingleStepContract(
          name: 'sleep session',
          rootLocation: AppRoutePaths.sleep,
          actionLabel: _openSleepSession,
          detailTitle: _sleepSessionTitle,
        ),
        _SingleStepContract(
          name: 'board post',
          rootLocation: AppRoutePaths.boards,
          actionLabel: _openBoardPost,
          detailTitle: _boardPostTitle,
        ),
        _SingleStepContract(
          name: 'group detail',
          rootLocation: AppRoutePaths.groups,
          actionLabel: _openGroupDetail,
          detailTitle: _groupDetailTitle,
        ),
      ];

      for (final contract in cases) {
        router.go(contract.rootLocation);
        await tester.pumpAndSettle();

        expect(find.text(_rootTitle(contract.rootLocation)), findsOneWidget);
        _expectNavBar(tester, isVisible: true, reason: contract.name);

        await tester.tap(find.text(contract.actionLabel));
        await tester.pumpAndSettle();

        expect(
          find.text(contract.detailTitle),
          findsOneWidget,
          reason: contract.name,
        );
        _expectNavBar(tester, isVisible: false, reason: contract.name);

        await _systemBack(tester, reason: contract.name);

        expect(
          find.text(_rootTitle(contract.rootLocation)),
          findsOneWidget,
          reason: contract.name,
        );
        _expectNavBar(tester, isVisible: true, reason: contract.name);
      }

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'multi-step detail stacks keep nav hidden until Android back reaches root',
    (tester) async {
      final router = await _pumpContractApp(tester);

      const cases = [
        _StackContract(
          name: 'home period to session',
          rootLocation: AppRoutePaths.home,
          steps: [
            _StackStep(
              actionLabel: _openHomePeriod,
              expectedTitle: _homePeriodTitle,
            ),
            _StackStep(
              actionLabel: _openHomeSession,
              expectedTitle: _homeSessionTitle,
            ),
          ],
        ),
        _StackContract(
          name: 'settings features to fronting',
          rootLocation: AppRoutePaths.settings,
          steps: [
            _StackStep(
              actionLabel: _openSettingsFeatures,
              expectedTitle: _settingsFeaturesTitle,
            ),
            _StackStep(
              actionLabel: _openFrontingFeature,
              expectedTitle: _frontingFeatureTitle,
            ),
          ],
        ),
        _StackContract(
          name: 'members detail to fronting history',
          rootLocation: AppRoutePaths.members,
          steps: [
            _StackStep(
              actionLabel: _openMemberDetail,
              expectedTitle: _memberDetailTitle,
            ),
            _StackStep(
              actionLabel: _openMemberFronting,
              expectedTitle: _memberFrontingTitle,
            ),
          ],
        ),
        _StackContract(
          name: 'member board to post',
          rootLocation: AppRoutePaths.boards,
          steps: [
            _StackStep(
              actionLabel: _openMemberBoard,
              expectedTitle: _memberBoardTitle,
            ),
            _StackStep(
              actionLabel: _openBoardPostFromMemberBoard,
              expectedTitle: _boardPostTitle,
            ),
          ],
        ),
        _StackContract(
          name: 'group detail to member fronting history',
          rootLocation: AppRoutePaths.groups,
          steps: [
            _StackStep(
              actionLabel: _openGroupDetail,
              expectedTitle: _groupDetailTitle,
            ),
            _StackStep(
              actionLabel: _openGroupMember,
              expectedTitle: _groupMemberTitle,
            ),
            _StackStep(
              actionLabel: _openGroupMemberFronting,
              expectedTitle: _groupMemberFrontingTitle,
            ),
          ],
        ),
      ];

      for (final contract in cases) {
        router.go(contract.rootLocation);
        await tester.pumpAndSettle();

        expect(find.text(_rootTitle(contract.rootLocation)), findsOneWidget);
        _expectNavBar(tester, isVisible: true, reason: contract.name);

        for (final step in contract.steps) {
          await tester.tap(find.text(step.actionLabel));
          await tester.pumpAndSettle();

          expect(
            find.text(step.expectedTitle),
            findsOneWidget,
            reason: contract.name,
          );
          _expectNavBar(tester, isVisible: false, reason: contract.name);
        }

        for (var i = contract.steps.length - 2; i >= 0; i--) {
          await _systemBack(tester, reason: contract.name);

          expect(
            find.text(contract.steps[i].expectedTitle),
            findsOneWidget,
            reason: contract.name,
          );
          _expectNavBar(tester, isVisible: false, reason: contract.name);
        }

        await _systemBack(tester, reason: contract.name);

        expect(
          find.text(_rootTitle(contract.rootLocation)),
          findsOneWidget,
          reason: contract.name,
        );
        _expectNavBar(tester, isVisible: true, reason: contract.name);
      }

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets('auth-dialog lifecycle does not relock the shell', (
    tester,
  ) async {
    final settings = StreamController<SystemSettings>();
    addTearDown(settings.close);
    settings.add(const SystemSettings());

    await _pumpContractApp(
      tester,
      settingsStream: settings.stream,
      isPinSet: true,
    );

    settings.add(
      const SystemSettings(pinLockEnabled: true, autoLockDelaySeconds: 0),
    );
    await tester.pump();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(find.text('Enter PIN'), findsNothing);
  });

  testWidgets('hidden lifecycle relocks the shell after PIN lock is enabled', (
    tester,
  ) async {
    final settings = StreamController<SystemSettings>();
    addTearDown(settings.close);
    settings.add(const SystemSettings());

    await _pumpContractApp(
      tester,
      settingsStream: settings.stream,
      isPinSet: true,
    );

    settings.add(
      const SystemSettings(pinLockEnabled: true, autoLockDelaySeconds: 0),
    );
    await tester.pump();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(find.text('Enter PIN'), findsOneWidget);
  });

  testWidgets('sync password gate redacts shell before unlock', (tester) async {
    var syncStatusBuilds = 0;

    await _pumpContractApp(
      tester,
      initialLocation: AppRoutePaths.members,
      syncHealthState: SyncHealthState.needsPassword,
      onSyncStatusBuild: () => syncStatusBuilds++,
    );

    expect(find.text('Enter your PIN'), findsOneWidget);
    expect(find.text(_membersRootTitle), findsNothing);
    _expectNavBar(tester, isVisible: false, reason: 'sync password gate');
    expect(
      syncStatusBuilds,
      greaterThan(0),
      reason: 'revoke/auth-failure cleanup must stay live behind the gate',
    );
  });
}

Future<GoRouter> _pumpContractApp(
  WidgetTester tester, {
  String initialLocation = AppRoutePaths.home,
  Stream<SystemSettings>? settingsStream,
  bool isPinSet = false,
  SyncHealthState syncHealthState = SyncHealthState.healthy,
  VoidCallback? onSyncStatusBuild,
}) async {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return AppShell(navigationShell: navigationShell);
        },
        branches: _contractBranches(),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        activeNavBarTabsProvider.overrideWithValue(
          appShellTabs.take(5).toList(),
        ),
        navBarOverflowTabsProvider.overrideWithValue(
          appShellTabs.skip(5).toList(),
        ),
        systemSettingsProvider.overrideWith(
          (ref) => settingsStream ?? Stream.value(const SystemSettings()),
        ),
        isPinSetProvider.overrideWith((ref) async => isPinSet),
        syncStatusProvider.overrideWith(
          () => _FakeSyncStatusNotifier(onBuild: onSyncStatusBuild),
        ),
        syncHealthProvider.overrideWith(
          () => _FakeSyncHealthNotifier(syncHealthState),
        ),
        pkAutoPollProvider.overrideWith(_FakePkAutoPollNotifier.new),
        pluralKitSyncProvider.overrideWith(_FakePluralKitSyncNotifier.new),
        habitsBadgeEnabledProvider.overrideWith((ref) => false),
        activeSessionsProvider.overrideWith((ref) => Stream.value(const [])),
        allMembersProvider.overrideWith((ref) => Stream.value(const [])),
        unreadConversationCountProvider.overrideWith((ref) => 0),
        frontingMigrationModeProvider.overrideWith(
          (ref) => Stream.value(FrontingMigrationService.modeComplete),
        ),
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

  return router;
}

List<StatefulShellBranch> _contractBranches() {
  return [
    StatefulShellBranch(
      routes: [
        GoRoute(
          path: AppRoutePaths.home,
          builder: (context, state) => _ProbePage(
            title: _homeRootTitle,
            actions: [
              _ProbeAction.push(
                _openHomePeriod,
                AppRoutePaths.period(const ['s1', 's2']),
              ),
            ],
          ),
          routes: [
            GoRoute(
              path: 'period',
              builder: (context, state) => _ProbePage(
                title: _homePeriodTitle,
                actions: [
                  _ProbeAction.push(
                    _openHomeSession,
                    AppRoutePaths.session('s1'),
                  ),
                ],
              ),
            ),
            GoRoute(
              path: 'session/:id',
              builder: (context, state) =>
                  const _ProbePage(title: _homeSessionTitle),
            ),
          ],
        ),
      ],
    ),
    StatefulShellBranch(
      routes: [
        GoRoute(
          path: AppRoutePaths.chat,
          builder: (context, state) => _ProbePage(
            title: _chatRootTitle,
            actions: [
              _ProbeAction.go(
                _openChatConversation,
                AppRoutePaths.chatConversation('c1'),
              ),
              const _ProbeAction.push(
                _openChatSearch,
                '${AppRoutePaths.chat}/search',
              ),
            ],
          ),
          routes: [
            GoRoute(
              path: 'search',
              builder: (context, state) =>
                  const _ProbePage(title: _chatSearchTitle),
            ),
            GoRoute(
              path: ':id',
              builder: (context, state) =>
                  const _ProbePage(title: _chatConversationTitle),
            ),
          ],
        ),
      ],
    ),
    StatefulShellBranch(
      routes: [
        GoRoute(
          path: AppRoutePaths.habits,
          builder: (context, state) => _ProbePage(
            title: _habitsRootTitle,
            actions: [
              _ProbeAction.push(_openHabitDetail, AppRoutePaths.habit('h1')),
            ],
          ),
          routes: [
            GoRoute(
              path: ':id',
              builder: (context, state) =>
                  const _ProbePage(title: _habitDetailTitle),
            ),
          ],
        ),
      ],
    ),
    StatefulShellBranch(
      routes: [
        GoRoute(
          path: AppRoutePaths.polls,
          builder: (context, state) => _ProbePage(
            title: _pollsRootTitle,
            actions: [
              _ProbeAction.go(_openPollDetail, AppRoutePaths.poll('p1')),
            ],
          ),
          routes: [
            GoRoute(
              path: ':id',
              builder: (context, state) =>
                  const _ProbePage(title: _pollDetailTitle),
            ),
          ],
        ),
      ],
    ),
    StatefulShellBranch(
      routes: [
        GoRoute(
          path: AppRoutePaths.settings,
          builder: (context, state) => const _ProbePage(
            title: _settingsRootTitle,
            actions: [
              _ProbeAction.push(
                _openSettingsFeatures,
                AppRoutePaths.settingsFeatures,
              ),
            ],
          ),
          routes: [
            GoRoute(
              path: 'features',
              builder: (context, state) => const _ProbePage(
                title: _settingsFeaturesTitle,
                actions: [
                  _ProbeAction.go(
                    _openFrontingFeature,
                    AppRoutePaths.settingsFeaturesFronting,
                  ),
                ],
              ),
              routes: [
                GoRoute(
                  path: 'fronting',
                  builder: (context, state) =>
                      const _ProbePage(title: _frontingFeatureTitle),
                ),
              ],
            ),
          ],
        ),
      ],
    ),
    StatefulShellBranch(
      routes: [
        GoRoute(
          path: AppRoutePaths.members,
          builder: (context, state) => _ProbePage(
            title: _membersRootTitle,
            actions: [
              _ProbeAction.push(_openMemberDetail, AppRoutePaths.member('m1')),
            ],
          ),
          routes: [
            GoRoute(
              path: ':id',
              builder: (context, state) => _ProbePage(
                title: _memberDetailTitle,
                actions: [
                  _ProbeAction.push(
                    _openMemberFronting,
                    AppRoutePaths.memberFrontingHistory('m1'),
                  ),
                ],
              ),
              routes: [
                GoRoute(
                  path: 'fronting',
                  builder: (context, state) =>
                      const _ProbePage(title: _memberFrontingTitle),
                ),
              ],
            ),
          ],
        ),
      ],
    ),
    StatefulShellBranch(
      routes: [
        GoRoute(
          path: AppRoutePaths.reminders,
          builder: (context, state) =>
              const _ProbePage(title: _remindersRootTitle),
        ),
      ],
    ),
    StatefulShellBranch(
      routes: [
        GoRoute(
          path: AppRoutePaths.notes,
          builder: (context, state) => _ProbePage(
            title: _notesRootTitle,
            actions: [
              _ProbeAction.push(_openNoteDetail, AppRoutePaths.note('n1')),
            ],
          ),
          routes: [
            GoRoute(
              path: ':id',
              builder: (context, state) =>
                  const _ProbePage(title: _noteDetailTitle),
            ),
          ],
        ),
      ],
    ),
    StatefulShellBranch(
      routes: [
        GoRoute(
          path: AppRoutePaths.statistics,
          builder: (context, state) =>
              const _ProbePage(title: _statisticsRootTitle),
        ),
      ],
    ),
    StatefulShellBranch(
      routes: [
        GoRoute(
          path: AppRoutePaths.timeline,
          builder: (context, state) =>
              const _ProbePage(title: _timelineRootTitle),
        ),
      ],
    ),
    StatefulShellBranch(
      routes: [
        GoRoute(
          path: AppRoutePaths.sleep,
          builder: (context, state) => _ProbePage(
            title: _sleepRootTitle,
            actions: [
              _ProbeAction.push(
                _openSleepSession,
                AppRoutePaths.sleepSession('sl1'),
              ),
            ],
          ),
          routes: [
            GoRoute(
              path: 'session/:id',
              builder: (context, state) =>
                  const _ProbePage(title: _sleepSessionTitle),
            ),
          ],
        ),
      ],
    ),
    StatefulShellBranch(
      routes: [
        GoRoute(
          path: AppRoutePaths.boards,
          builder: (context, state) => _ProbePage(
            title: _boardsRootTitle,
            actions: [
              _ProbeAction.push(
                _openMemberBoard,
                AppRoutePaths.memberBoard('m1'),
              ),
              _ProbeAction.push(_openBoardPost, AppRoutePaths.boardPost('bp1')),
            ],
          ),
          routes: [
            GoRoute(
              path: 'member/:memberId',
              builder: (context, state) => _ProbePage(
                title: _memberBoardTitle,
                actions: [
                  _ProbeAction.push(
                    _openBoardPostFromMemberBoard,
                    AppRoutePaths.boardPost('bp1'),
                  ),
                ],
              ),
            ),
            GoRoute(
              path: 'post/:postId',
              builder: (context, state) =>
                  const _ProbePage(title: _boardPostTitle),
            ),
          ],
        ),
      ],
    ),
    StatefulShellBranch(
      routes: [
        GoRoute(
          path: AppRoutePaths.groups,
          builder: (context, state) => _ProbePage(
            title: _groupsRootTitle,
            actions: [
              _ProbeAction.push(_openGroupDetail, AppRoutePaths.group('g1')),
            ],
          ),
          routes: [
            GoRoute(
              path: ':id',
              builder: (context, state) => _ProbePage(
                title: _groupDetailTitle,
                actions: [
                  _ProbeAction.push(
                    _openGroupMember,
                    AppRoutePaths.groupMember('g1', 'm1'),
                  ),
                ],
              ),
              routes: [
                GoRoute(
                  path: 'member/:memberId',
                  builder: (context, state) => _ProbePage(
                    title: _groupMemberTitle,
                    actions: [
                      _ProbeAction.push(
                        _openGroupMemberFronting,
                        AppRoutePaths.groupMemberFrontingHistory('g1', 'm1'),
                      ),
                    ],
                  ),
                  routes: [
                    GoRoute(
                      path: 'fronting',
                      builder: (context, state) =>
                          const _ProbePage(title: _groupMemberFrontingTitle),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ],
    ),
    StatefulShellBranch(
      routes: [
        GoRoute(
          path: AppRoutePaths.media,
          builder: (context, state) =>
              const _ProbePage(title: _mediaRootTitle),
        ),
      ],
    ),
  ];
}

Future<void> _systemBack(WidgetTester tester, {required String reason}) async {
  final handled = await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
  expect(handled, isTrue, reason: reason);
}

void _expectNavBar(
  WidgetTester tester, {
  required bool isVisible,
  required String reason,
}) {
  expect(
    find.bySemanticsLabel('Navigation bar'),
    isVisible ? findsOneWidget : findsNothing,
    reason: reason,
  );
}

String _rootTitle(String location) {
  return switch (location) {
    AppRoutePaths.home => _homeRootTitle,
    AppRoutePaths.chat => _chatRootTitle,
    AppRoutePaths.habits => _habitsRootTitle,
    AppRoutePaths.polls => _pollsRootTitle,
    AppRoutePaths.settings => _settingsRootTitle,
    AppRoutePaths.members => _membersRootTitle,
    AppRoutePaths.reminders => _remindersRootTitle,
    AppRoutePaths.notes => _notesRootTitle,
    AppRoutePaths.statistics => _statisticsRootTitle,
    AppRoutePaths.timeline => _timelineRootTitle,
    AppRoutePaths.sleep => _sleepRootTitle,
    AppRoutePaths.boards => _boardsRootTitle,
    AppRoutePaths.groups => _groupsRootTitle,
    AppRoutePaths.media => _mediaRootTitle,
    _ => throw ArgumentError.value(location, 'location'),
  };
}

enum _ProbeNavigation { push, go }

class _ProbeAction {
  const _ProbeAction._(this.label, this.location, this.navigation);

  const _ProbeAction.push(String label, String location)
    : this._(label, location, _ProbeNavigation.push);

  const _ProbeAction.go(String label, String location)
    : this._(label, location, _ProbeNavigation.go);

  final String label;
  final String location;
  final _ProbeNavigation navigation;
}

class _ProbePage extends StatelessWidget {
  const _ProbePage({required this.title, this.actions = const []});

  final String title;
  final List<_ProbeAction> actions;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title),
            for (final action in actions)
              TextButton(
                onPressed: () {
                  switch (action.navigation) {
                    case _ProbeNavigation.push:
                      context.push(action.location);
                    case _ProbeNavigation.go:
                      context.go(action.location);
                  }
                },
                child: Text(action.label),
              ),
          ],
        ),
      ),
    );
  }
}

class _SingleStepContract {
  const _SingleStepContract({
    required this.name,
    required this.rootLocation,
    required this.actionLabel,
    required this.detailTitle,
  });

  final String name;
  final String rootLocation;
  final String actionLabel;
  final String detailTitle;
}

class _StackContract {
  const _StackContract({
    required this.name,
    required this.rootLocation,
    required this.steps,
  });

  final String name;
  final String rootLocation;
  final List<_StackStep> steps;
}

class _StackStep {
  const _StackStep({required this.actionLabel, required this.expectedTitle});

  final String actionLabel;
  final String expectedTitle;
}

class _FakeSyncStatusNotifier extends SyncStatusNotifier {
  _FakeSyncStatusNotifier({this.onBuild});

  final VoidCallback? onBuild;

  @override
  SyncStatus build() {
    onBuild?.call();
    return const SyncStatus();
  }
}

class _FakeSyncHealthNotifier extends SyncHealthNotifier {
  _FakeSyncHealthNotifier(this.initialState);

  final SyncHealthState initialState;

  @override
  SyncHealthState build() => initialState;
}

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

const _homeRootTitle = 'Route contract: home root';
const _chatRootTitle = 'Route contract: chat root';
const _habitsRootTitle = 'Route contract: habits root';
const _pollsRootTitle = 'Route contract: polls root';
const _settingsRootTitle = 'Route contract: settings root';
const _membersRootTitle = 'Route contract: members root';
const _remindersRootTitle = 'Route contract: reminders root';
const _notesRootTitle = 'Route contract: notes root';
const _statisticsRootTitle = 'Route contract: statistics root';
const _timelineRootTitle = 'Route contract: timeline root';
const _sleepRootTitle = 'Route contract: sleep root';
const _boardsRootTitle = 'Route contract: boards root';
const _groupsRootTitle = 'Route contract: groups root';
const _mediaRootTitle = 'Route contract: media root';

const _homePeriodTitle = 'Route contract: home period detail';
const _homeSessionTitle = 'Route contract: home session detail';
const _chatSearchTitle = 'Route contract: chat search';
const _chatConversationTitle = 'Route contract: chat conversation';
const _habitDetailTitle = 'Route contract: habit detail';
const _pollDetailTitle = 'Route contract: poll detail';
const _settingsFeaturesTitle = 'Route contract: settings features';
const _frontingFeatureTitle = 'Route contract: fronting feature settings';
const _memberDetailTitle = 'Route contract: member detail';
const _memberFrontingTitle = 'Route contract: member fronting history';
const _noteDetailTitle = 'Route contract: note detail';
const _sleepSessionTitle = 'Route contract: sleep session detail';
const _memberBoardTitle = 'Route contract: member board';
const _boardPostTitle = 'Route contract: board post detail';
const _groupDetailTitle = 'Route contract: group detail';
const _groupMemberTitle = 'Route contract: group member detail';
const _groupMemberFrontingTitle =
    'Route contract: group member fronting history';

const _openHomePeriod = 'Open route contract home period';
const _openHomeSession = 'Open route contract home session';
const _openChatConversation = 'Open route contract chat conversation';
const _openChatSearch = 'Open route contract chat search';
const _openHabitDetail = 'Open route contract habit detail';
const _openPollDetail = 'Open route contract poll detail';
const _openSettingsFeatures = 'Open route contract settings features';
const _openFrontingFeature = 'Open route contract fronting feature';
const _openMemberDetail = 'Open route contract member detail';
const _openMemberFronting = 'Open route contract member fronting';
const _openNoteDetail = 'Open route contract note detail';
const _openSleepSession = 'Open route contract sleep session';
const _openMemberBoard = 'Open route contract member board';
const _openBoardPost = 'Open route contract board post';
const _openBoardPostFromMemberBoard =
    'Open route contract board post from member board';
const _openGroupDetail = 'Open route contract group detail';
const _openGroupMember = 'Open route contract group member';
const _openGroupMemberFronting = 'Open route contract group member fronting';
