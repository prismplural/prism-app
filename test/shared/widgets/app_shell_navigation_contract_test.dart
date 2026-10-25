import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:prism_plurality/core/database/database_provider.dart';
import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/core/router/notification_navigation_providers.dart';
import 'package:prism_plurality/domain/models/reminder.dart';
import 'package:prism_plurality/domain/repositories/reminders_repository.dart';
import 'package:prism_plurality/core/router/app_router.dart';
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
import 'package:prism_plurality/features/settings/views/pin_input_screen.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/widgets/app_shell.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final fontLoader = FontLoader('OpenDyslexic')
      ..addFont(rootBundle.load('assets/fonts/OpenDyslexic3-Regular.ttf'))
      ..addFont(rootBundle.load('assets/fonts/OpenDyslexic3-Bold.ttf'));
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

  testWidgets('shell first launch paints the initial root route', (
    tester,
  ) async {
    await _pumpContractApp(tester, initialLocation: AppRoutePaths.home);

    expect(
      tester.takeException(),
      isNull,
      reason:
          'Cold launch must not depend on GoRouterState in AppShell context.',
    );
    expect(find.text(_homeRootTitle), findsOneWidget);
    _expectNavBar(tester, isVisible: true, reason: 'initial home route');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets(
    'shell uses its production-builder route path outside GoRouter registry',
    (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      StatefulNavigationShell? capturedShell;
      String? capturedRoutePath;
      final router = GoRouter(
        initialLocation: AppRoutePaths.home,
        routes: [
          StatefulShellRoute.indexedStack(
            builder: (context, state, navigationShell) {
              final shell =
                  buildAppShellRoute(context, state, navigationShell)
                      as AppShell;
              capturedShell = shell.navigationShell;
              capturedRoutePath = shell.routePath;
              return const SizedBox.shrink();
            },
            branches: _contractBranches(),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        MaterialApp.router(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: const [Locale('en')],
          routerConfig: router,
        ),
      );
      await tester.pumpAndSettle();

      final navigationShell = capturedShell;
      expect(navigationShell, isNotNull);
      expect(capturedRoutePath, AppRoutePaths.home);

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
              (ref) => Stream.value(const SystemSettings()),
            ),
            isPinSetProvider.overrideWith((ref) async => false),
            syncStatusProvider.overrideWith(_FakeSyncStatusNotifier.new),
            syncHealthProvider.overrideWith(
              () => _FakeSyncHealthNotifier(SyncHealthState.healthy),
            ),
            pkAutoPollProvider.overrideWith(_FakePkAutoPollNotifier.new),
            pluralKitSyncProvider.overrideWith(_FakePluralKitSyncNotifier.new),
            habitsBadgeEnabledProvider.overrideWith((ref) => false),
            activeSessionsProvider.overrideWith(
              (ref) => Stream.value(const []),
            ),
            allMembersProvider.overrideWith((ref) => Stream.value(const [])),
            unreadConversationCountProvider.overrideWith((ref) => 0),
            frontingMigrationModeProvider.overrideWith(
              (ref) => Stream.value(FrontingMigrationService.modeComplete),
            ),
            frontingMigrationGateProvider.overrideWith(
              (ref) => FrontingMigrationGateStatus.complete,
            ),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: const [Locale('en')],
            theme: ThemeData(fontFamily: 'OpenDyslexic'),
            home: AppShell(
              navigationShell: navigationShell!,
              routePath: capturedRoutePath!,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      _expectNavBar(tester, isVisible: true, reason: 'route-state boundary');
    },
  );

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

  for (final (testName, payload) in [
    (
      'authorized notification tap opens live reminder list once',
      'prism:reminder:scheduled:synthetic-id',
    ),
    (
      'authorized legacy delayed tap uses envelope reminder not member',
      'prism:reminder:front-change-delayed:synthetic-id:'
          '["Private synthetic name","Private synthetic body",2,"different-member-id"]',
    ),
  ]) {
    testWidgets(testName, (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final repo = _ReadOnlyNotificationReminders();
      final router = await _pumpContractApp(
        tester,
        initialLocation: AppRoutePaths.members,
        settingsStream: Stream.value(
          const SystemSettings(
            hasCompletedOnboarding: true,
            remindersEnabled: true,
          ),
        ),
        notificationReminders: repo,
      );
      expect(find.text(_membersRootTitle), findsOneWidget);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(AppShell)),
      );
      final intents = container.read(notificationNavigationProvider.notifier);
      final bootstrap = NotificationTapBootstrap(
        intents: intents,
        attachSink: (_) {},
        initialize: () async {},
        getLaunchPayload: () async => payload,
      );
      await bootstrap.start();
      await tester.pumpAndSettle();

      expect(
        router.routeInformationProvider.value.uri.path,
        AppRoutePaths.reminders,
      );
      expect(find.text(_remindersRootTitle), findsOneWidget);
      expect(repo.lookups, ['synthetic-id']);
      expect(intents.pending, isNull);
      await tester.pumpAndSettle();
      expect(repo.lookups, ['synthetic-id']);
      expect(find.text('Private synthetic name'), findsNothing);
      expect(find.text('Private synthetic body'), findsNothing);
    });
  }

  for (final gate in ['database', 'bootstrap', 'initial PIN']) {
    testWidgets(
      'cold notification waits for $gate before identity and record lookup',
      (tester) async {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        final database = Completer<DatabaseReadyReport>();
        final bootstrap = Completer<void>();
        final pin = Completer<bool>();
        var identityReads = 0;
        final repo = _ReadOnlyNotificationReminders();
        final router = await _pumpContractApp(
          tester,
          initialLocation: AppRoutePaths.members,
          settingsStream: Stream.value(
            const SystemSettings(hasCompletedOnboarding: true),
          ),
          notificationReminders: repo,
          notificationDatabaseReady: gate == 'database'
              ? () => database.future
              : null,
          notificationBootstrap: gate == 'bootstrap'
              ? () => bootstrap.future
              : null,
          notificationPinReady: gate == 'initial PIN' ? () => pin.future : null,
          notificationIdentity: () async {
            identityReads++;
            return null;
          },
        );
        final container = ProviderScope.containerOf(
          tester.element(find.byType(AppShell)),
        );
        final intents = container.read(notificationNavigationProvider.notifier);
        intents.receiveCallback('prism:reminder:scheduled:synthetic-id');
        await tester.pumpAndSettle();
        expect(repo.lookups, isEmpty);
        expect(identityReads, 0);
        expect(
          router.routeInformationProvider.value.uri.path,
          AppRoutePaths.members,
        );
        switch (gate) {
          case 'database':
            database.complete(
              const DatabaseReadyReport(
                schemaVersionBeforeOpen: 1,
                schemaVersionAfterOpen: 1,
              ),
            );
          case 'bootstrap':
            bootstrap.complete();
          case 'initial PIN':
            pin.complete(false);
        }
        await tester.pumpAndSettle();
        expect(repo.lookups, ['synthetic-id']);
        expect(
          router.routeInformationProvider.value.uri.path,
          AppRoutePaths.reminders,
        );
      },
    );
  }

  testWidgets('notification waits for onboarding and settings completion', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final settings = StreamController<SystemSettings>();
    addTearDown(settings.close);
    settings.add(const SystemSettings(hasCompletedOnboarding: false));
    final repo = _ReadOnlyNotificationReminders();
    final router = await _pumpContractApp(
      tester,
      initialLocation: AppRoutePaths.members,
      settingsStream: settings.stream,
      notificationReminders: repo,
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(AppShell)),
    );
    container
        .read(notificationNavigationProvider.notifier)
        .receiveCallback('prism:reminder:scheduled:synthetic-id');
    await tester.pumpAndSettle();
    expect(repo.lookups, isEmpty);
    expect(
      router.routeInformationProvider.value.uri.path,
      AppRoutePaths.members,
    );
    settings.add(const SystemSettings(hasCompletedOnboarding: true));
    await tester.pumpAndSettle();
    expect(repo.lookups, ['synthetic-id']);
    expect(
      router.routeInformationProvider.value.uri.path,
      AppRoutePaths.reminders,
    );
  });

  for (final health in [
    SyncHealthState.needsPassword,
    SyncHealthState.needsRewrap,
    SyncHealthState.awaitingDeviceUnlock,
    SyncHealthState.runtimeDekRestoreDeferred,
  ]) {
    testWidgets(
      'notification cannot resolve record through $health privacy gate',
      (tester) async {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        final repo = _ReadOnlyNotificationReminders();
        final router = await _pumpContractApp(
          tester,
          initialLocation: AppRoutePaths.members,
          settingsStream: Stream.value(
            const SystemSettings(hasCompletedOnboarding: true),
          ),
          notificationReminders: repo,
        );
        final container = ProviderScope.containerOf(
          tester.element(find.byType(AppShell)),
        );
        // Mark the existing sheet duplicate guards as showing to isolate the
        // notification consumer from the unrelated credential-entry UI.
        container
            .read(syncPasswordSheetVisibleProvider.notifier)
            .setValue(true);
        container.read(syncRewrapSheetVisibleProvider.notifier).setValue(true);
        container.read(syncHealthProvider.notifier).setState(health);
        final intents = container.read(notificationNavigationProvider.notifier);
        intents.receiveCallback('prism:reminder:scheduled:synthetic-id');
        await tester.pumpAndSettle();
        expect(repo.lookups, isEmpty);
        expect(
          router.routeInformationProvider.value.uri.path,
          AppRoutePaths.members,
        );
        expect(intents.pending?.reminderId, 'synthetic-id');
        container
            .read(syncHealthProvider.notifier)
            .setState(SyncHealthState.unpaired);
        await tester.pumpAndSettle();
        expect(
          repo.lookups,
          isEmpty,
          reason: 'protected sheets still take priority',
        );
        container
            .read(syncPasswordSheetVisibleProvider.notifier)
            .setValue(false);
        container.read(syncRewrapSheetVisibleProvider.notifier).setValue(false);
        await tester.pumpAndSettle();
        expect(repo.lookups, ['synthetic-id']);
        expect(
          router.routeInformationProvider.value.uri.path,
          AppRoutePaths.reminders,
        );
      },
    );
  }

  testWidgets('notification waits for resolved migration gate', (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final repo = _ReadOnlyNotificationReminders();
    final router = await _pumpContractApp(
      tester,
      initialLocation: AppRoutePaths.members,
      settingsStream: Stream.value(
        const SystemSettings(hasCompletedOnboarding: true),
      ),
      notificationReminders: repo,
      notificationMigrationGate: FrontingMigrationGateStatus.needsModal,
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(AppShell)),
    );
    container
        .read(notificationNavigationProvider.notifier)
        .receiveCallback('prism:reminder:scheduled:synthetic-id');
    await tester.pumpAndSettle();
    expect(repo.lookups, isEmpty);
    expect(
      router.routeInformationProvider.value.uri.path,
      AppRoutePaths.members,
    );
    expect(
      container
          .read(notificationNavigationProvider.notifier)
          .pending
          ?.reminderId,
      'synthetic-id',
    );
  });

  for (final (name, missing, active, feature) in [
    ('missing or deleted', true, true, true),
    ('inactive', false, false, true),
    ('feature disabled', false, true, false),
  ]) {
    testWidgets(
      'notification $name consumes safely without writes or routing',
      (tester) async {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        final repo = _ReadOnlyNotificationReminders(
          missing: missing,
          active: active,
        );
        final router = await _pumpContractApp(
          tester,
          initialLocation: AppRoutePaths.members,
          settingsStream: Stream.value(
            SystemSettings(
              hasCompletedOnboarding: true,
              remindersEnabled: feature,
            ),
          ),
          notificationReminders: repo,
        );
        final container = ProviderScope.containerOf(
          tester.element(find.byType(AppShell)),
        );
        final intents = container.read(notificationNavigationProvider.notifier);
        intents.receiveCallback('prism:reminder:scheduled:synthetic-id');
        await tester.pumpAndSettle();
        expect(
          router.routeInformationProvider.value.uri.path,
          AppRoutePaths.members,
        );
        expect(repo.lookups, feature ? ['synthetic-id'] : isEmpty);
        expect(intents.pending, isNull);
      },
    );
  }

  testWidgets('locked latest distinct tap waits for successful shell unlock', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final repo = _ReadOnlyNotificationReminders();
    final router = await _pumpContractApp(
      tester,
      initialLocation: AppRoutePaths.members,
      settingsStream: Stream.value(
        const SystemSettings(
          hasCompletedOnboarding: true,
          pinLockEnabled: true,
        ),
      ),
      isPinSet: true,
      notificationReminders: repo,
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(AppShell)),
    );
    final intents = container.read(notificationNavigationProvider.notifier);
    intents.receiveCallback('prism:reminder:scheduled:first');
    intents.receiveCallback('prism:reminder:scheduled:latest');
    await tester.pumpAndSettle();
    expect(repo.lookups, isEmpty);
    expect(
      router.routeInformationProvider.value.uri.path,
      AppRoutePaths.members,
    );
    expect(intents.pending?.reminderId, 'latest');
    // No success callback represents failed/cancelled authentication: even
    // subsequent frames must not resolve a record or navigate.
    await tester.pump();
    expect(repo.lookups, isEmpty);
    tester.widget<PinInputScreen>(find.byType(PinInputScreen)).onSuccess();
    await tester.pumpAndSettle();
    expect(repo.lookups, ['latest']);
    expect(
      router.routeInformationProvider.value.uri.path,
      AppRoutePaths.reminders,
    );
  });

  for (final transition in [
    'relock',
    'reset',
    'account',
    'dispose',
    'suspend',
  ]) {
    testWidgets('deferred reminder lookup cannot route across $transition', (
      tester,
    ) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final delayed = Completer<Reminder?>();
      final repo = _ReadOnlyNotificationReminders(delayed: delayed);
      var account = 'first-account';
      final router = await _pumpContractApp(
        tester,
        initialLocation: AppRoutePaths.members,
        settingsStream: Stream.value(
          SystemSettings(
            hasCompletedOnboarding: true,
            pinLockEnabled: transition == 'relock',
            autoLockDelaySeconds: 0,
          ),
        ),
        isPinSet: transition == 'relock',
        notificationReminders: repo,
        notificationIdentity: () async => account,
      );
      if (transition == 'relock') {
        tester.widget<PinInputScreen>(find.byType(PinInputScreen)).onSuccess();
        await tester.pumpAndSettle();
      }
      final container = ProviderScope.containerOf(
        tester.element(find.byType(AppShell)),
      );
      final intents = container.read(notificationNavigationProvider.notifier);
      intents.receiveCallback('prism:reminder:scheduled:synthetic-id');
      await tester.pumpAndSettle();
      expect(repo.lookups, ['synthetic-id']);
      switch (transition) {
        case 'relock':
        case 'suspend':
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.hidden,
          );
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.paused,
          );
          if (transition == 'relock') {
            tester.binding.handleAppLifecycleStateChanged(
              AppLifecycleState.resumed,
            );
          }
        case 'reset':
          intents.beginContextChange();
          intents.receiveCallback('prism:reminder:scheduled:during-reset');
          expect(intents.pending, isNull);
        case 'account':
          account = 'different-account';
          container.invalidate(syncIdProvider);
        case 'dispose':
          await tester.pumpWidget(const SizedBox.shrink());
      }
      await tester.pump();
      delayed.complete(repo.reminder('synthetic-id'));
      await tester.pumpAndSettle();
      expect(
        router.routeInformationProvider.value.uri.path,
        AppRoutePaths.members,
      );
      if (transition == 'reset' || transition == 'account') {
        expect(intents.pending, isNull);
      }
      if (transition == 'relock') {
        expect(find.text('Enter PIN'), findsOneWidget);
        expect(intents.pending?.reminderId, 'synthetic-id');
      }
      if (transition == 'reset') {
        intents.endContextChange();
        expect(intents.pending, isNull);
        intents.receiveCallback('prism:reminder:scheduled:synthetic-id');
        await tester.pumpAndSettle();
        expect(
          router.routeInformationProvider.value.uri.path,
          AppRoutePaths.reminders,
        );
      } else if (transition == 'suspend' || transition == 'relock') {
        intents.clearContext();
      }
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    });
  }

  testWidgets(
    'background tap defers until resumed without requiring healthy pairing',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final repo = _ReadOnlyNotificationReminders();
      final router = await _pumpContractApp(
        tester,
        initialLocation: AppRoutePaths.members,
        settingsStream: Stream.value(
          const SystemSettings(hasCompletedOnboarding: true),
        ),
        notificationReminders: repo,
        syncHealthState: SyncHealthState.unpaired,
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(AppShell)),
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      container
          .read(notificationNavigationProvider.notifier)
          .receiveCallback('prism:reminder:scheduled:synthetic-id');
      await tester.pumpAndSettle();
      expect(repo.lookups, isEmpty);
      expect(
        router.routeInformationProvider.value.uri.path,
        AppRoutePaths.members,
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(repo.lookups, ['synthetic-id']);
      expect(
        router.routeInformationProvider.value.uri.path,
        AppRoutePaths.reminders,
      );
    },
  );

  testWidgets(
    'fronting notification uses only fixed home route without lookup',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final repo = _ReadOnlyNotificationReminders();
      final router = await _pumpContractApp(
        tester,
        initialLocation: AppRoutePaths.members,
        settingsStream: Stream.value(
          const SystemSettings(
            hasCompletedOnboarding: true,
            frontingRemindersEnabled: true,
          ),
        ),
        notificationReminders: repo,
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(AppShell)),
      );
      container
          .read(notificationNavigationProvider.notifier)
          .receiveCallback('prism:fronting:v1');
      await tester.pumpAndSettle();
      expect(
        router.routeInformationProvider.value.uri.path,
        AppRoutePaths.home,
      );
      expect(repo.lookups, isEmpty);
    },
  );

  testWidgets('legacy delayed tap remains opaque and unread while PIN locked', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final repo = _ReadOnlyNotificationReminders();
    final router = await _pumpContractApp(
      tester,
      initialLocation: AppRoutePaths.members,
      isPinSet: true,
      settingsStream: Stream.value(
        const SystemSettings(
          hasCompletedOnboarding: true,
          pinLockEnabled: true,
        ),
      ),
      notificationReminders: repo,
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(AppShell)),
    );
    container
        .read(notificationNavigationProvider.notifier)
        .receiveCallback(
          'prism:reminder:front-change-delayed:synthetic-id:'
          '["Private synthetic name","Private synthetic body",2,"different-member-id"]',
        );
    await tester.pumpAndSettle();
    expect(find.text('Enter PIN'), findsOneWidget);
    expect(find.text(_membersRootTitle), findsNothing);
    expect(find.text('Private synthetic name'), findsNothing);
    expect(find.text('Private synthetic body'), findsNothing);
    expect(
      router.routeInformationProvider.value.uri.path,
      AppRoutePaths.members,
    );
    expect(repo.lookups, isEmpty);
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

class _ReadOnlyNotificationReminders implements RemindersRepository {
  _ReadOnlyNotificationReminders({
    this.missing = false,
    this.active = true,
    this.delayed,
  });
  final bool missing;
  final bool active;
  final Completer<Reminder?>? delayed;
  final lookups = <String>[];

  @override
  Future<Reminder?> getById(String id) async {
    lookups.add(id);
    if (delayed != null) return delayed!.future;
    return missing ? null : reminder(id);
  }

  Reminder reminder(String id) => Reminder(
    id: id,
    isActive: active,
    name: 'Synthetic reminder',
    message: 'Synthetic message',
    createdAt: DateTime.utc(2026),
    modifiedAt: DateTime.utc(2026),
  );

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Notification navigation must only read getById');
}

Future<GoRouter> _pumpContractApp(
  WidgetTester tester, {
  String initialLocation = AppRoutePaths.home,
  Stream<SystemSettings>? settingsStream,
  bool isPinSet = false,
  Future<bool> Function()? notificationPinReady,
  SyncHealthState syncHealthState = SyncHealthState.healthy,
  VoidCallback? onSyncStatusBuild,
  RemindersRepository? notificationReminders,
  Future<String?> Function()? notificationIdentity,
  Future<DatabaseReadyReport> Function()? notificationDatabaseReady,
  Future<void> Function()? notificationBootstrap,
  FrontingMigrationGateStatus notificationMigrationGate =
      FrontingMigrationGateStatus.complete,
}) async {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      StatefulShellRoute.indexedStack(
        builder: buildAppShellRoute,
        branches: _contractBranches(),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        notificationTapBootstrapProvider.overrideWith((ref) async {
          await notificationBootstrap?.call();
        }),
        if (notificationReminders != null) ...[
          remindersRepositoryProvider.overrideWithValue(notificationReminders),
          databaseReadyProvider.overrideWith(
            (ref) async => notificationDatabaseReady != null
                ? await notificationDatabaseReady()
                : const DatabaseReadyReport(
                    schemaVersionBeforeOpen: 1,
                    schemaVersionAfterOpen: 1,
                  ),
          ),
          syncIdProvider.overrideWith(
            (ref) async => notificationIdentity == null
                ? null
                : await notificationIdentity(),
          ),
        ],
        activeNavBarTabsProvider.overrideWithValue(
          appShellTabs.take(5).toList(),
        ),
        navBarOverflowTabsProvider.overrideWithValue(
          appShellTabs.skip(5).toList(),
        ),
        systemSettingsProvider.overrideWith(
          (ref) => settingsStream ?? Stream.value(const SystemSettings()),
        ),
        isPinSetProvider.overrideWith(
          (ref) async => notificationPinReady == null
              ? isPinSet
              : await notificationPinReady(),
        ),
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
          (ref) => notificationMigrationGate,
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
          builder: (context, state) => const _ProbePage(title: _mediaRootTitle),
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
