import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:prism_plurality/core/router/app_routes.dart';
import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart';
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

  testWidgets('pushes to PluralKit on every active sessions emit', (
    tester,
  ) async {
    // Match the phone-portrait viewport used by other AppShell tests so
    // the floating bottom nav lays out without overflow.
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final sessions = StreamController<List<FrontingSession>>();
    final pushCalls = <int>[];
    _FakePkAutoPollNotifier.noteLocalPushCalls = 0;

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
    addTearDown(sessions.close);

    FrontingSession session(String id, String memberId) => FrontingSession(
      id: id,
      startTime: DateTime.utc(2026, 2, 1, 12),
      memberId: memberId,
    );

    final a = session('s-a', 'a');
    final b = session('s-b', 'b');

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          systemSettingsProvider.overrideWith(
            (ref) => Stream.value(const SystemSettings()),
          ),
          isPinSetProvider.overrideWith((ref) async => false),
          syncStatusProvider.overrideWith(_FakeSyncStatusNotifier.new),
          pkAutoPollProvider.overrideWith(_FakePkAutoPollNotifier.new),
          pluralKitSyncProvider.overrideWith(
            () => _RecordingPluralKitSyncNotifier(pushCalls, pushReturn: 1),
          ),
          habitsBadgeEnabledProvider.overrideWith((ref) => false),
          activeSessionsProvider.overrideWith((ref) => sessions.stream),
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
          routerConfig: router,
        ),
      ),
    );
    await tester.pump();
    expect(pushCalls, isEmpty);

    sessions.add([a]);
    await tester.pump();
    expect(pushCalls.length, 1);
    expect(_FakePkAutoPollNotifier.noteLocalPushCalls, 1);

    sessions.add([a, b]);
    await tester.pump();
    expect(pushCalls.length, 2);
    expect(_FakePkAutoPollNotifier.noteLocalPushCalls, 2);

    sessions.add([b]);
    await tester.pump();
    expect(pushCalls.length, 3);
    expect(_FakePkAutoPollNotifier.noteLocalPushCalls, 3);

    sessions.add(const []);
    await tester.pump();
    expect(pushCalls.length, 4);
    expect(_FakePkAutoPollNotifier.noteLocalPushCalls, 4);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('does not suppress auto-poll when PK push no-ops', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final sessions = StreamController<List<FrontingSession>>();
    final pushCalls = <int>[];
    _FakePkAutoPollNotifier.noteLocalPushCalls = 0;

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
    addTearDown(sessions.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          systemSettingsProvider.overrideWith(
            (ref) => Stream.value(const SystemSettings()),
          ),
          isPinSetProvider.overrideWith((ref) async => false),
          syncStatusProvider.overrideWith(_FakeSyncStatusNotifier.new),
          pkAutoPollProvider.overrideWith(_FakePkAutoPollNotifier.new),
          pluralKitSyncProvider.overrideWith(
            () => _RecordingPluralKitSyncNotifier(pushCalls, pushReturn: 0),
          ),
          habitsBadgeEnabledProvider.overrideWith((ref) => false),
          activeSessionsProvider.overrideWith((ref) => sessions.stream),
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
          routerConfig: router,
        ),
      ),
    );
    await tester.pump();

    sessions.add([
      FrontingSession(
        id: 's-a',
        startTime: DateTime.utc(2026, 2, 1, 12),
        memberId: 'a',
      ),
    ]);
    await tester.pump();

    expect(pushCalls.length, 1);
    expect(_FakePkAutoPollNotifier.noteLocalPushCalls, 0);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });
}

class _FakeSyncStatusNotifier extends SyncStatusNotifier {
  @override
  SyncStatus build() => const SyncStatus();
}

class _FakePkAutoPollNotifier extends PkAutoPollNotifier {
  static int noteLocalPushCalls = 0;

  @override
  void build() {}

  @override
  void markForegrounded(bool value) {}

  @override
  void noteLocalPush() {
    noteLocalPushCalls++;
  }
}

class _RecordingPluralKitSyncNotifier extends PluralKitSyncNotifier {
  _RecordingPluralKitSyncNotifier(this.pushCalls, {required this.pushReturn});

  final List<int> pushCalls;
  final int pushReturn;

  @override
  PluralKitSyncState build() => const PluralKitSyncState();

  @override
  Future<int> pushPendingSwitches() async {
    pushCalls.add(pushCalls.length + 1);
    return pushReturn;
  }

  @override
  Future<void> pushMemberUpdate(domain.Member member) async {}
}
