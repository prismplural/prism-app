import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:prism_plurality/core/database/database_providers.dart';
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
import '../../helpers/fake_repositories.dart';

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

  // M11 — the member-edit auto-push trigger must compare the
  // fields the PK PATCH payload actually carries (display_name ←
  // pluralkitDisplayName, pronouns, description ← bio, birthday, color,
  // proxy_tags), NOT the local-only `name` / in-app `displayName`.
  group('member-edit push trigger (M11)', () {
    domain.Member linked({
      String id = 'm-1',
      String name = 'Ada',
      String? pluralkitDisplayName,
      String? displayName,
      String? pronouns,
      String? bio,
      String? birthday,
      bool customColorEnabled = false,
      String? customColorHex,
      String? proxyTagsJson,
      String? pluralkitId = 'abcde',
    }) => domain.Member(
      id: id,
      name: name,
      createdAt: DateTime.utc(2026, 2, 1),
      pluralkitId: pluralkitId,
      pluralkitDisplayName: pluralkitDisplayName,
      displayName: displayName,
      pronouns: pronouns,
      bio: bio,
      birthday: birthday,
      customColorEnabled: customColorEnabled,
      customColorHex: customColorHex,
      proxyTagsJson: proxyTagsJson,
    );

    Future<List<String>> runEdit(
      WidgetTester tester, {
      required domain.Member before,
      required domain.Member after,
    }) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final members = StreamController<List<domain.Member>>();
      addTearDown(members.close);
      final memberPushCalls = <String>[];
      final memberRepository = FakeMemberRepository()..seed([before]);

      final router = GoRouter(
        initialLocation: AppRoutePaths.home,
        routes: [
          StatefulShellRoute.indexedStack(
            builder: (context, state, navigationShell) =>
                AppShell(navigationShell: navigationShell),
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
            systemSettingsProvider.overrideWith(
              (ref) => Stream.value(const SystemSettings()),
            ),
            isPinSetProvider.overrideWith((ref) async => false),
            syncStatusProvider.overrideWith(_FakeSyncStatusNotifier.new),
            pkAutoPollProvider.overrideWith(_FakePkAutoPollNotifier.new),
            pluralKitSyncProvider.overrideWith(
              () => _RecordingPluralKitSyncNotifier(
                <int>[],
                pushReturn: 0,
                memberPushCalls: memberPushCalls,
              ),
            ),
            habitsBadgeEnabledProvider.overrideWith((ref) => false),
            activeSessionsProvider.overrideWith((ref) => const Stream.empty()),
            memberRepositoryProvider.overrideWithValue(memberRepository),
            allMembersProvider.overrideWith((ref) => members.stream),
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

      members.add([before]);
      await tester.pump();
      memberRepository.seed([after]);
      members.add([after]);
      await tester.pump();

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
      return memberPushCalls;
    }

    testWidgets('PK display-name edit fires the push', (tester) async {
      final calls = await runEdit(
        tester,
        before: linked(pluralkitDisplayName: 'Old'),
        after: linked(pluralkitDisplayName: 'New'),
      );
      expect(calls, ['m-1']);
    });

    testWidgets('local display-name edit does NOT fire the push', (
      tester,
    ) async {
      final calls = await runEdit(
        tester,
        before: linked(displayName: 'Old Local'),
        after: linked(displayName: 'New Local'),
      );
      expect(calls, isEmpty);
    });

    testWidgets('local name edit does NOT fire the push', (tester) async {
      final calls = await runEdit(
        tester,
        before: linked(name: 'Ada'),
        after: linked(name: 'Ada Lovelace'),
      );
      expect(calls, isEmpty);
    });

    testWidgets('pronouns edit fires the push', (tester) async {
      final calls = await runEdit(
        tester,
        before: linked(pronouns: 'she/her'),
        after: linked(pronouns: 'they/them'),
      );
      expect(calls, ['m-1']);
    });

    testWidgets('bio / birthday / color edits fire the push', (tester) async {
      expect(
        await runEdit(
          tester,
          before: linked(bio: 'a'),
          after: linked(bio: 'b'),
        ),
        ['m-1'],
      );
      expect(
        await runEdit(
          tester,
          before: linked(birthday: '0004-01-01'),
          after: linked(birthday: '0004-02-02'),
        ),
        ['m-1'],
      );
      expect(
        await runEdit(
          tester,
          before: linked(customColorEnabled: true, customColorHex: 'aaaaaa'),
          after: linked(customColorEnabled: true, customColorHex: 'bbbbbb'),
        ),
        ['m-1'],
      );
      // Proxy-tag edits deliberately do NOT fire: the auto-push always passes
      // includeProxyTags: false (destructive tag changes route through manual
      // sync's delete-risk preview), so a proxy-tag-only edit would PATCH a
      // body that cannot carry the change — a wasted call.
      expect(
        await runEdit(
          tester,
          before: linked(proxyTagsJson: '[{"prefix":"a:"}]'),
          after: linked(proxyTagsJson: '[{"prefix":"b:"}]'),
        ),
        isEmpty,
      );
    });

    testWidgets('unlinked member never fires the push', (tester) async {
      final calls = await runEdit(
        tester,
        before: linked(pluralkitId: null, pluralkitDisplayName: 'Old'),
        after: linked(pluralkitId: null, pluralkitDisplayName: 'New'),
      );
      expect(calls, isEmpty);
    });
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
  _RecordingPluralKitSyncNotifier(
    this.pushCalls, {
    required this.pushReturn,
    List<String>? memberPushCalls,
  }) : memberPushCalls = memberPushCalls ?? <String>[];

  final List<int> pushCalls;
  final int pushReturn;

  /// Member ids passed to [pushMemberUpdate], in call order. Lets the member-
  /// edit trigger tests assert which edits fire (and which don't).
  final List<String> memberPushCalls;

  @override
  PluralKitSyncState build() => const PluralKitSyncState();

  @override
  Future<int> pushPendingSwitches() async {
    pushCalls.add(pushCalls.length + 1);
    return pushReturn;
  }

  @override
  Future<void> pushMemberUpdate(domain.Member member) async {
    memberPushCalls.add(member.id);
  }
}
