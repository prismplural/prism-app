import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:prism_plurality/domain/models/member_board_post.dart';
import 'package:prism_plurality/core/router/app_routes.dart';
import 'package:prism_plurality/domain/models/conversation.dart';
import 'package:prism_plurality/domain/models/custom_field.dart';
import 'package:prism_plurality/domain/models/custom_field_value.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/models/member_group.dart';
import 'package:prism_plurality/domain/models/member_group_entry.dart';
import 'package:prism_plurality/domain/models/note.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/features/boards/providers/board_posts_providers.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_providers.dart';
import 'package:prism_plurality/features/members/navigation/member_navigation_branch.dart';
import 'package:prism_plurality/features/members/providers/custom_fields_providers.dart';
import 'package:prism_plurality/features/members/providers/member_groups_providers.dart';
import 'package:prism_plurality/features/members/providers/member_stats_providers.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/members/providers/notes_providers.dart';
import 'package:prism_plurality/features/members/views/member_detail_screen.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_sync_config.dart';
import 'package:prism_plurality/features/pluralkit/providers/pluralkit_providers.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_sync_service.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/theme/app_theme.dart';

final _now = DateTime(2026, 5, 1, 12);

Member _member(String id, String name) =>
    Member(id: id, name: name, createdAt: _now, isActive: true);

FrontingSession _session({
  required String id,
  required String memberId,
  required DateTime start,
  required DateTime end,
}) =>
    FrontingSession(id: id, memberId: memberId, startTime: start, endTime: end);

Conversation _conversation({
  required String id,
  required List<String> participantIds,
  String? title,
}) => Conversation(
  id: id,
  title: title,
  participantIds: participantIds,
  createdAt: _now,
  lastActivityAt: _now,
);

Note _note(String id, {String title = 'Profile note'}) => Note(
  id: id,
  title: title,
  body: 'Note body',
  memberId: 'alice',
  date: _now,
  createdAt: _now,
  modifiedAt: _now,
);

MemberBoardPost _boardPost(String id, {String body = 'Board post body'}) =>
    MemberBoardPost(
      id: id,
      targetMemberId: 'alice',
      authorId: 'bob',
      audience: 'public',
      body: body,
      createdAt: _now,
      writtenAt: _now,
    );

GoRouter _router({required String memberId}) {
  return GoRouter(
    initialLocation: AppRoutePaths.member(memberId),
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            Scaffold(body: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/',
                builder: (_, _) => const Scaffold(body: Text('home')),
                routes: [
                  GoRoute(
                    path: 'session/:id',
                    builder: (context, state) => Scaffold(
                      body: Column(
                        children: [
                          Text('session-${state.pathParameters['id']}'),
                          TextButton(
                            onPressed: () => Navigator.of(context).maybePop(),
                            child: const Text('Back from session'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutePaths.chat,
                builder: (_, _) => const Scaffold(body: Text('chat')),
                routes: [
                  GoRoute(
                    path: ':id',
                    builder: (context, state) => Scaffold(
                      body: Column(
                        children: [
                          Text('conversation-${state.pathParameters['id']}'),
                          TextButton(
                            onPressed: () => Navigator.of(context).maybePop(),
                            child: const Text('Back from conversation'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutePaths.members,
                builder: (_, _) => const Scaffold(body: Text('members')),
                routes: [
                  GoRoute(
                    path: ':id',
                    builder: (_, state) => MemberDetailScreen(
                      memberId: state.pathParameters['id']!,
                      branch: MemberNavigationBranch.members,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
  );
}

GoRouter _groupsRouter({required String groupId, required String memberId}) {
  return GoRouter(
    initialLocation: AppRoutePaths.groupMember(groupId, memberId),
    routes: [
      GoRoute(
        path: '/groups/:groupId/member/:memberId',
        builder: (_, state) => MemberDetailScreen(
          memberId: state.pathParameters['memberId']!,
          branch: MemberNavigationBranch.groups,
          groupId: state.pathParameters['groupId']!,
        ),
        routes: [
          GoRoute(
            path: 'fronting',
            builder: (context, state) => Scaffold(
              body: Text(
                'fronting-${state.pathParameters['groupId']}-'
                '${state.pathParameters['memberId']}',
              ),
            ),
          ),
        ],
      ),
      GoRoute(
        path: '/groups/:groupId',
        builder: (context, state) =>
            Text('group-${state.pathParameters['groupId']}'),
      ),
    ],
  );
}

Widget _buildApp({
  required GoRouter router,
  required Member member,
  List<FrontingSession> recentSessions = const [],
  List<Conversation> conversations = const [],
  List<Note> notes = const [],
  MemberBoardSection? boardSection,
  List<MemberGroup> memberGroups = const [],
  SystemSettings settings = const SystemSettings(
    notesEnabled: false,
    boardsEnabled: false,
  ),
}) {
  final bob = _member('bob', 'Bob');
  final stats = recentSessions.isEmpty
      ? const MemberFrontingStats(
          totalSessions: 0,
          totalDuration: Duration.zero,
        )
      : MemberFrontingStats(
          totalSessions: recentSessions.length,
          totalDuration: recentSessions.fold<Duration>(
            Duration.zero,
            (sum, session) => sum + session.duration,
          ),
          lastFronted: recentSessions.first.startTime,
        );

  return ProviderScope(
    overrides: [
      systemSettingsProvider.overrideWith((ref) => Stream.value(settings)),
      memberByIdProvider(member.id).overrideWith((ref) => Stream.value(member)),
      allMembersProvider.overrideWith((ref) => Stream.value([member, bob])),
      activeMembersProvider.overrideWith((ref) => Stream.value([member, bob])),
      activeSessionsProvider.overrideWith((ref) => Stream.value(const [])),
      memberFrontingStatsProvider(member.id).overrideWith((ref) async => stats),
      memberRecentSessionsProvider(
        member.id,
      ).overrideWith((ref) async => recentSessions),
      memberConversationsProvider(
        member.id,
      ).overrideWith((ref) async => conversations),
      recentMemberNotesProvider(
        member.id,
      ).overrideWith((ref) => Stream.value(notes)),
      memberBoardSectionProvider(member.id).overrideWith(
        (ref) => Stream.value(
          boardSection ??
              const MemberBoardSection(publicPosts: [], totalPublic: 0),
        ),
      ),
      memberGroupsProvider(
        member.id,
      ).overrideWith((ref) => Stream.value(memberGroups)),
      allGroupsProvider.overrideWith((ref) => Stream.value(memberGroups)),
      allGroupEntriesProvider.overrideWith(
        (ref) => Stream.value(const <MemberGroupEntry>[]),
      ),
      customFieldsProvider.overrideWith(
        (ref) => Stream.value(const <CustomField>[]),
      ),
      pluralKitSyncProvider.overrideWith(
        () => _FakePluralKitSyncNotifier(
          const PluralKitSyncState(isConnected: false),
        ),
      ),
      pkSyncDirectionProvider.overrideWith(
        () => _StaticPkSyncDirectionNotifier(PkSyncDirection.pullOnly),
      ),
      memberCustomFieldValuesProvider(
        member.id,
      ).overrideWith((ref) => Stream.value(const <CustomFieldValue>[])),
    ],
    child: MaterialApp.router(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('en')],
      routerConfig: router,
    ),
  );
}

class _FakePluralKitSyncNotifier extends PluralKitSyncNotifier {
  _FakePluralKitSyncNotifier(this._state);

  final PluralKitSyncState _state;

  @override
  PluralKitSyncState build() => _state;
}

class _StaticPkSyncDirectionNotifier extends PkSyncDirectionNotifier {
  _StaticPkSyncDirectionNotifier(this._direction);

  final PkSyncDirection _direction;

  @override
  PkSyncDirection build() => _direction;
}

void main() {
  testWidgets('mobile member detail still edits in a sheet route', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final member = _member('alice', 'Alice');
    final router = _router(memberId: member.id);
    addTearDown(router.dispose);

    await tester.pumpWidget(_buildApp(router: router, member: member));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(AppIcons.editOutlined));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byKey(const Key('detailSideSheetPanel')), findsNothing);
    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Style'), findsOneWidget);
    expect(find.text('Name *'), findsOneWidget);
    expect(find.text('Bio'), findsOneWidget);

    await tester.tap(find.text('Custom Fields'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byKey(const Key('detailSideSheetPanel')), findsNothing);
    expect(find.text('Custom Fields'), findsNWidgets(2));

    await tester.tap(find.byIcon(AppIcons.arrowBack).last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Style'), findsOneWidget);
    expect(find.text('Name *'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets(
    'member detail uses a seeded local profile theme in Palette mode',
    (tester) async {
      final member = _member('alice', 'Alice').copyWith(
        customColorEnabled: true,
        customColorHex: '#16A34A',
        bio: 'Profile body',
      );
      final router = _router(memberId: member.id);
      addTearDown(router.dispose);

      await tester.pumpWidget(
        _buildApp(
          router: router,
          member: member,
          settings: const SystemSettings(
            notesEnabled: false,
            boardsEnabled: false,
            themeStyle: ThemeStyle.materialYou,
            perMemberAccentColors: true,
            paletteMood: PaletteMood.vibrant,
            paletteContrast: PaletteContrast.high,
          ),
        ),
      );

      await tester.pumpAndSettle();

      final profileContext = tester.element(find.byType(SingleChildScrollView));
      final profileTheme = Theme.of(profileContext);
      final expectedTheme = AppTheme.localPaletteTheme(
        ThemeData.light(),
        seedColor: const Color(0xFF16A34A),
        paletteMood: PaletteMood.vibrant,
        paletteContrast: PaletteContrast.high,
      );

      expect(
        profileTheme.colorScheme.primary,
        expectedTheme.colorScheme.primary,
      );
      expect(
        profileTheme.scaffoldBackgroundColor,
        expectedTheme.scaffoldBackgroundColor,
      );
      expect(profileTheme.cardColor, expectedTheme.cardColor);
      expect(
        profileTheme.filledButtonTheme.style!.backgroundColor!.resolve(
          const <WidgetState>{},
        ),
        expectedTheme.colorScheme.primary,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    },
  );

  testWidgets('member detail keeps accent-only theming outside Palette mode', (
    tester,
  ) async {
    final member = _member('alice', 'Alice').copyWith(
      customColorEnabled: true,
      customColorHex: '#16A34A',
      bio: 'Profile body',
    );
    final router = _router(memberId: member.id);
    addTearDown(router.dispose);

    await tester.pumpWidget(
      _buildApp(
        router: router,
        member: member,
        settings: const SystemSettings(
          notesEnabled: false,
          boardsEnabled: false,
          themeStyle: ThemeStyle.standard,
          perMemberAccentColors: true,
          paletteMood: PaletteMood.vibrant,
          paletteContrast: PaletteContrast.high,
        ),
      ),
    );

    await tester.pumpAndSettle();

    final profileContext = tester.element(find.byType(SingleChildScrollView));
    final profileTheme = Theme.of(profileContext);
    final baseTheme = ThemeData.light();
    final seededTheme = AppTheme.localPaletteTheme(
      baseTheme,
      seedColor: const Color(0xFF16A34A),
      paletteMood: PaletteMood.vibrant,
      paletteContrast: PaletteContrast.high,
    );

    expect(profileTheme.colorScheme.primary, const Color(0xFF16A34A));
    expect(
      profileTheme.scaffoldBackgroundColor,
      baseTheme.scaffoldBackgroundColor,
    );
    expect(profileTheme.cardColor, baseTheme.cardColor);
    expect(
      profileTheme.scaffoldBackgroundColor,
      isNot(seededTheme.scaffoldBackgroundColor),
    );
    expect(profileTheme.cardColor, isNot(seededTheme.cardColor));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('member detail shows creation date as a subtle footer', (
    tester,
  ) async {
    final member = _member('alice', 'Alice');
    final router = _router(memberId: member.id);
    addTearDown(router.dispose);

    await tester.pumpWidget(_buildApp(router: router, member: member));
    await tester.pumpAndSettle();

    expect(find.text('Added May 1, 2026'), findsOneWidget);
    expect(find.text('Created May 1, 2026'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('member detail pushes recent session so back returns', (
    tester,
  ) async {
    final member = _member('alice', 'Alice');
    final session = _session(
      id: 's1',
      memberId: member.id,
      start: DateTime(2020, 1, 1, 10),
      end: DateTime(2020, 1, 1, 11),
    );
    final router = _router(memberId: member.id);
    addTearDown(router.dispose);

    await tester.pumpWidget(
      _buildApp(router: router, member: member, recentSessions: [session]),
    );
    await tester.pumpAndSettle();

    final sessionDate = find.text('1/1/2020').last;
    await tester.ensureVisible(sessionDate);
    await tester.tap(sessionDate);
    await tester.pumpAndSettle();

    expect(find.text('session-s1'), findsOneWidget);

    await tester.tap(find.text('Back from session'));
    await tester.pumpAndSettle();

    expect(find.text('Alice'), findsOneWidget);
    expect(
      router.routerDelegate.currentConfiguration.uri.toString(),
      AppRoutePaths.member(member.id),
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('member detail pushes conversation so back returns', (
    tester,
  ) async {
    final member = _member('alice', 'Alice');
    final conversation = _conversation(
      id: 'c1',
      title: 'Project chat',
      participantIds: [member.id, 'bob'],
    );
    final router = _router(memberId: member.id);
    addTearDown(router.dispose);

    await tester.pumpWidget(
      _buildApp(router: router, member: member, conversations: [conversation]),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Project chat'));
    await tester.tap(find.text('Project chat'));
    await tester.pumpAndSettle();

    expect(find.text('conversation-c1'), findsOneWidget);

    await tester.tap(find.text('Back from conversation'));
    await tester.pumpAndSettle();

    expect(find.text('Alice'), findsOneWidget);
    expect(
      router.routerDelegate.currentConfiguration.uri.toString(),
      AppRoutePaths.member(member.id),
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('member detail hides feature-owned sections when disabled', (
    tester,
  ) async {
    final member = _member('alice', 'Alice');
    final conversation = _conversation(
      id: 'c1',
      title: 'Project chat',
      participantIds: [member.id, 'bob'],
    );
    final note = _note('n1');
    final boardPost = _boardPost('p1');
    final router = _router(memberId: member.id);
    addTearDown(router.dispose);

    await tester.pumpWidget(
      _buildApp(
        router: router,
        member: member,
        conversations: [conversation],
        notes: [note],
        boardSection: MemberBoardSection(
          publicPosts: [boardPost],
          totalPublic: 1,
        ),
        settings: const SystemSettings(
          chatEnabled: false,
          notesEnabled: false,
          boardsEnabled: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Project chat'), findsNothing);
    expect(find.text('Profile note'), findsNothing);
    expect(find.textContaining('Board post body'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('member detail shows feature-owned sections when enabled', (
    tester,
  ) async {
    final member = _member('alice', 'Alice');
    final conversation = _conversation(
      id: 'c1',
      title: 'Project chat',
      participantIds: [member.id, 'bob'],
    );
    final note = _note('n1');
    final boardPost = _boardPost('p1');
    final router = _router(memberId: member.id);
    addTearDown(router.dispose);

    await tester.pumpWidget(
      _buildApp(
        router: router,
        member: member,
        conversations: [conversation],
        notes: [note],
        boardSection: MemberBoardSection(
          publicPosts: [boardPost],
          totalPublic: 1,
        ),
        settings: const SystemSettings(
          chatEnabled: true,
          notesEnabled: true,
          boardsEnabled: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Project chat'), findsOneWidget);
    expect(find.text('Profile note'), findsOneWidget);
    expect(find.textContaining('Board post body'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets(
    'groups member detail uses the route-provided group branch for fronting',
    (tester) async {
      final member = _member('alice', 'Alice');
      final session = _session(
        id: 's1',
        memberId: member.id,
        start: DateTime(2020, 1, 1, 10),
        end: DateTime(2020, 1, 1, 11),
      );
      final router = _groupsRouter(groupId: 'crew', memberId: member.id);
      addTearDown(router.dispose);

      await tester.pumpWidget(
        _buildApp(router: router, member: member, recentSessions: [session]),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('View All'));
      await tester.tap(find.text('View All'));
      await tester.pumpAndSettle();

      expect(find.text('fronting-crew-alice'), findsOneWidget);
      expect(
        router.routerDelegate.currentConfiguration.uri.toString(),
        AppRoutePaths.groupMemberFrontingHistory('crew', member.id),
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    },
  );
}
