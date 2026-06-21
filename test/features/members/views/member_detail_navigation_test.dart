import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:prism_plurality/core/constants/fronting_namespaces.dart';
import 'package:prism_plurality/core/database/database_providers.dart';
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
import 'package:prism_plurality/features/chat/providers/pending_conversation_selection_provider.dart';
import 'package:prism_plurality/features/fronting/providers/member_fronting_history_providers.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_providers.dart';
import 'package:prism_plurality/features/fronting/services/derive_periods.dart';
import 'package:prism_plurality/features/members/navigation/member_navigation_branch.dart';
import 'package:prism_plurality/features/members/providers/custom_field_group_profile_preferences.dart';
import 'package:prism_plurality/features/members/providers/custom_fields_providers.dart';
import 'package:prism_plurality/features/members/providers/member_groups_providers.dart';
import 'package:prism_plurality/features/members/providers/member_stats_providers.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/members/providers/notes_providers.dart';
import 'package:prism_plurality/features/members/views/member_custom_field_group_page.dart';
import 'package:prism_plurality/features/members/views/member_detail_screen.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_sync_config.dart';
import 'package:prism_plurality/features/pluralkit/providers/pluralkit_providers.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_sync_service.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/theme/app_theme.dart';

import '../../../helpers/fake_repositories.dart';

final _now = DateTime(2026, 5, 1, 12);

Member _member(String id, String name, {bool isActive = true}) =>
    Member(id: id, name: name, createdAt: _now, isActive: isActive);

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
  bool isDirectMessage = false,
  bool includesAllMembers = false,
}) => Conversation(
  id: id,
  title: title,
  participantIds: participantIds,
  isDirectMessage: isDirectMessage,
  includesAllMembers: includesAllMembers,
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

GoRouter _router({required String memberId, String? initialLocation}) {
  return GoRouter(
    initialLocation: initialLocation ?? AppRoutePaths.member(memberId),
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
                builder: (_, _) => Consumer(
                  builder: (context, ref, _) {
                    final pending = ref.watch(
                      pendingConversationSelectionProvider,
                    );
                    return Scaffold(
                      body: Text(
                        pending == null
                            ? 'chat'
                            : 'chat-pending-${pending.conversationId}',
                      ),
                    );
                  },
                ),
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
                    routes: [
                      GoRoute(
                        path: 'conversations',
                        builder: (_, state) => MemberConversationsScreen(
                          memberId: state.pathParameters['id']!,
                        ),
                      ),
                      GoRoute(
                        path: 'custom-fields/:fieldId',
                        builder: (_, state) => MemberCustomFieldGroupPage(
                          memberId: state.pathParameters['id']!,
                          fieldId: state.pathParameters['fieldId']!,
                        ),
                      ),
                    ],
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
  List<Member> extraMembers = const [],
  List<Note> notes = const [],
  List<CustomField> customFields = const [],
  List<CustomFieldValue> customFieldValues = const [],
  FakeAppPreferenceRepository? appPreferences,
  MemberBoardSection? boardSection,
  List<MemberGroup> memberGroups = const [],
  SystemSettings settings = const SystemSettings(
    notesEnabled: false,
    boardsEnabled: false,
  ),
  VoidCallback? onStatsProviderBuilt,
  VoidCallback? onRecentSessionsProviderBuilt,
  VoidCallback? onConversationsProviderBuilt,
  VoidCallback? onBoardSectionProviderBuilt,
}) {
  final bob = _member('bob', 'Bob');
  final allMembers = [member, bob, ...extraMembers];
  final appPrefs = appPreferences ?? FakeAppPreferenceRepository();
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
  final visibleConversations = conversations
      .where((conversation) => !conversation.isDirectMessage)
      .toList();

  return ProviderScope(
    overrides: [
      systemSettingsProvider.overrideWith((ref) => Stream.value(settings)),
      appPreferenceRepositoryProvider.overrideWithValue(appPrefs),
      memberByIdProvider(member.id).overrideWith((ref) => Stream.value(member)),
      allMembersProvider.overrideWith((ref) => Stream.value(allMembers)),
      activeMembersProvider.overrideWith((ref) => Stream.value(allMembers)),
      activeMemberListProvider.overrideWith((ref) => Stream.value(allMembers)),
      activeSessionsProvider.overrideWith((ref) => Stream.value(const [])),
      memberFrontingStatsProvider(member.id).overrideWith((ref) async {
        onStatsProviderBuilt?.call();
        return stats;
      }),
      memberRecentSessionsProvider(member.id).overrideWith((ref) async {
        onRecentSessionsProviderBuilt?.call();
        return recentSessions;
      }),
      memberFrontingHistoryProvider.overrideWith((ref, requestedMemberId) {
        return AsyncValue.data(
          MemberFrontingHistoryData(
            periods: const <FrontingPeriod>[],
            targetSessions: requestedMemberId == member.id
                ? recentSessions
                : const <FrontingSession>[],
            hasMore: false,
          ),
        );
      }),
      memberConversationActivityProvider(member.id).overrideWith((ref) async {
        onConversationsProviderBuilt?.call();
        return [
          for (var i = 0; i < visibleConversations.length; i++)
            (conversation: visibleConversations[i], messageCount: i + 1),
        ];
      }),
      memberConversationPreviewActivityProvider(member.id).overrideWith((
        ref,
      ) async {
        onConversationsProviderBuilt?.call();
        return [
          for (
            var i = 0;
            i < visibleConversations.length &&
                i < memberConversationPreviewCount + 1;
            i++
          )
            (conversation: visibleConversations[i], messageCount: i + 1),
        ];
      }),
      recentMemberNotesProvider(
        member.id,
      ).overrideWith((ref) => Stream.value(notes)),
      memberBoardSectionProvider(member.id).overrideWith((ref) {
        onBoardSectionProviderBuilt?.call();
        return Stream.value(
          boardSection ??
              const MemberBoardSection(publicPosts: [], totalPublic: 0),
        );
      }),
      memberGroupsProvider(
        member.id,
      ).overrideWith((ref) => Stream.value(memberGroups)),
      allGroupsProvider.overrideWith((ref) => Stream.value(memberGroups)),
      allGroupEntriesProvider.overrideWith(
        (ref) => Stream.value(const <MemberGroupEntry>[]),
      ),
      customFieldsProvider.overrideWith((ref) => Stream.value(customFields)),
      for (final field in customFields)
        customFieldByIdProvider(
          field.id,
        ).overrideWith((ref) => Stream.value(field)),
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
      ).overrideWith((ref) => Stream.value(customFieldValues)),
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

  testWidgets('page-mode custom field group opens a member profile page', (
    tester,
  ) async {
    final member = _member('alice', 'Alice');
    final router = _router(memberId: member.id);
    addTearDown(router.dispose);
    final appPrefs = FakeAppPreferenceRepository();
    addTearDown(appPrefs.close);
    final group = CustomField(
      id: 'vitals',
      name: 'Vitals',
      fieldType: CustomFieldType.text,
      fieldTypeId: 'group',
      createdAt: _now,
    );
    final child = CustomField(
      id: 'favorite-color',
      name: 'Favorite color',
      fieldType: CustomFieldType.text,
      fieldTypeId: 'text',
      parentFieldId: group.id,
      createdAt: _now,
    );
    final value = CustomFieldValue(
      id: 'value-favorite-color',
      customFieldId: child.id,
      memberId: member.id,
      value: 'Blue',
    );
    appPrefs.seed(
      customFieldGroupProfileDisplayModePreference(group.id),
      CustomFieldGroupProfileDisplayMode.page.storageValue,
    );

    await tester.pumpWidget(
      _buildApp(
        router: router,
        member: member,
        customFields: [group, child],
        customFieldValues: [value],
        appPreferences: appPrefs,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Vitals'), findsOneWidget);
    expect(find.text('1 field'), findsNothing);
    expect(find.text('Blue'), findsNothing);

    await tester.tap(find.text('Vitals'));
    await tester.pumpAndSettle();

    expect(find.text('Blue'), findsOneWidget);
    expect(find.text('Favorite color'), findsOneWidget);
  });

  testWidgets('page-mode custom field group opens for inactive members', (
    tester,
  ) async {
    final member = _member('alice', 'Alice', isActive: false);
    final group = CustomField(
      id: 'vitals',
      name: 'Vitals',
      fieldType: CustomFieldType.text,
      fieldTypeId: 'group',
      createdAt: _now,
    );
    final child = CustomField(
      id: 'favorite-color',
      name: 'Favorite color',
      fieldType: CustomFieldType.text,
      fieldTypeId: 'text',
      parentFieldId: group.id,
      createdAt: _now,
    );
    final value = CustomFieldValue(
      id: 'value-favorite-color',
      customFieldId: child.id,
      memberId: member.id,
      value: 'Blue',
    );
    final router = _router(
      memberId: member.id,
      initialLocation: AppRoutePaths.memberCustomFieldGroup(
        member.id,
        group.id,
      ),
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      _buildApp(
        router: router,
        member: member,
        customFields: [group, child],
        customFieldValues: [value],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Vitals'), findsOneWidget);
    expect(find.text('Favorite color'), findsOneWidget);
    expect(find.text('Blue'), findsOneWidget);

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

      final profileContext = tester.element(find.byType(CustomScrollView));
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

    final profileContext = tester.element(find.byType(CustomScrollView));
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

  testWidgets('member detail defers lower section providers until scrolled', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(600, 320);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final member = _member('alice', 'Alice').copyWith(
      bio: List.filled(
        16,
        'A long profile paragraph that keeps lower sections below the fold.',
      ).join('\n\n'),
    );
    final session = _session(
      id: 's1',
      memberId: member.id,
      start: DateTime(2020, 1, 1, 10),
      end: DateTime(2020, 1, 1, 11),
    );
    final router = _router(memberId: member.id);
    addTearDown(router.dispose);

    var statsBuilds = 0;
    var recentBuilds = 0;

    await tester.pumpWidget(
      _buildApp(
        router: router,
        member: member,
        recentSessions: [session],
        onStatsProviderBuilt: () => statsBuilds++,
        onRecentSessionsProviderBuilt: () => recentBuilds++,
      ),
    );
    await tester.pumpAndSettle();

    expect(statsBuilds, isZero);
    expect(recentBuilds, isZero);

    for (var i = 0; i < 20 && (statsBuilds == 0 || recentBuilds == 0); i++) {
      await tester.drag(find.byType(Scrollable).last, const Offset(0, -600));
      await tester.pumpAndSettle();
    }

    expect(statsBuilds, greaterThan(0));
    expect(recentBuilds, greaterThan(0));

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
    await tester.scrollUntilVisible(
      sessionDate,
      400,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.drag(find.byType(Scrollable).last, const Offset(0, -120));
    await tester.pumpAndSettle();
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

  testWidgets('wide member detail opens fronting view all in a side sheet', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

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

    await tester.ensureVisible(find.text('View All'));
    await tester.tap(find.text('View All'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('detailSideSheetPanel')), findsOneWidget);
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

  testWidgets(
    'wide member detail opens conversation view all in a side sheet',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final member = _member('alice', 'Alice');
      final conversations = [
        _conversation(
          id: 'c1',
          title: 'Most active',
          participantIds: [member.id, 'bob'],
        ),
        _conversation(
          id: 'c2',
          title: 'Second active',
          participantIds: [member.id, 'bob'],
        ),
        _conversation(
          id: 'c3',
          title: 'Third active',
          participantIds: [member.id, 'bob'],
        ),
        _conversation(
          id: 'c4',
          title: 'Fourth active',
          participantIds: [member.id, 'bob'],
        ),
      ];
      final router = _router(memberId: member.id);
      addTearDown(router.dispose);

      await tester.pumpWidget(
        _buildApp(router: router, member: member, conversations: conversations),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('View All'));
      await tester.tap(find.text('View All'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('detailSideSheetPanel')), findsOneWidget);
      expect(find.text('Fourth active'), findsOneWidget);
      expect(
        router.routerDelegate.currentConfiguration.uri.toString(),
        AppRoutePaths.member(member.id),
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    },
  );

  testWidgets('desktop member detail opens conversation in chat pane', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

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

    expect(find.text('chat-pending-c1'), findsOneWidget);
    expect(find.text('conversation-c1'), findsNothing);
    expect(
      router.routerDelegate.currentConfiguration.uri.toString(),
      AppRoutePaths.chat,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('member detail truncates conversations with view all route', (
    tester,
  ) async {
    final member = _member('alice', 'Alice');
    final conversations = [
      _conversation(
        id: 'c1',
        title: 'Most active',
        participantIds: [member.id, 'bob'],
      ),
      _conversation(
        id: 'c2',
        title: 'Second active',
        participantIds: [member.id, 'bob'],
      ),
      _conversation(
        id: 'c3',
        title: 'Third active',
        participantIds: [member.id, 'bob'],
      ),
      _conversation(
        id: 'c4',
        title: 'Fourth active',
        participantIds: [member.id, 'bob'],
      ),
    ];
    final router = _router(memberId: member.id);
    addTearDown(router.dispose);

    await tester.pumpWidget(
      _buildApp(router: router, member: member, conversations: conversations),
    );
    await tester.pumpAndSettle();

    expect(find.text('Most active'), findsOneWidget);
    expect(find.text('Second active'), findsOneWidget);
    expect(find.text('Third active'), findsOneWidget);
    expect(find.text('Fourth active'), findsNothing);

    await tester.ensureVisible(find.text('View All'));
    await tester.tap(find.text('View All'));
    await tester.pumpAndSettle();

    expect(find.text('Fourth active'), findsOneWidget);
    expect(
      router.routerDelegate.currentConfiguration.uri.toString(),
      AppRoutePaths.memberConversations(member.id),
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('member detail excludes direct messages from conversations', (
    tester,
  ) async {
    final member = _member('alice', 'Alice');
    final conversations = [
      _conversation(
        id: 'dm',
        title: 'Private DM',
        participantIds: [member.id, 'bob'],
        isDirectMessage: true,
      ),
      _conversation(
        id: 'group',
        title: 'Shared group',
        participantIds: [member.id, 'bob'],
      ),
    ];
    final router = _router(memberId: member.id);
    addTearDown(router.dispose);

    await tester.pumpWidget(
      _buildApp(router: router, member: member, conversations: conversations),
    );
    await tester.pumpAndSettle();

    expect(find.text('Shared group'), findsOneWidget);
    expect(find.text('Private DM'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('member conversation subtitles exclude Unknown sentinel', (
    tester,
  ) async {
    final member = _member('alice', 'Alice');
    final unknown = _member(unknownSentinelMemberId, 'Unknown');
    final conversation = _conversation(
      id: 'everyone',
      title: 'Everybody',
      participantIds: const [],
      includesAllMembers: true,
    );
    final router = _router(memberId: member.id);
    addTearDown(router.dispose);

    await tester.pumpWidget(
      _buildApp(
        router: router,
        member: member,
        extraMembers: [unknown],
        conversations: [conversation],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Everybody'), findsOneWidget);
    expect(find.textContaining('Bob'), findsOneWidget);
    expect(find.textContaining('Unknown'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('member conversations route hides chat data when chat disabled', (
    tester,
  ) async {
    final member = _member('alice', 'Alice');
    final conversation = _conversation(
      id: 'c1',
      title: 'Hidden chat',
      participantIds: [member.id, 'bob'],
    );
    final router = _router(memberId: member.id);
    addTearDown(router.dispose);
    var conversationsProviderBuilds = 0;

    await tester.pumpWidget(
      _buildApp(
        router: router,
        member: member,
        conversations: [conversation],
        settings: const SystemSettings(
          chatEnabled: false,
          notesEnabled: false,
          boardsEnabled: false,
        ),
        onConversationsProviderBuilt: () => conversationsProviderBuilds += 1,
      ),
    );
    await tester.pumpAndSettle();

    conversationsProviderBuilds = 0;
    router.go(AppRoutePaths.memberConversations(member.id));
    await tester.pumpAndSettle();

    expect(find.text('Hidden chat'), findsNothing);
    expect(conversationsProviderBuilds, 0);

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

    await tester.scrollUntilVisible(
      find.textContaining('Board post body'),
      400,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.textContaining('Board post body'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('member detail note preview resolves member mentions', (
    tester,
  ) async {
    const mentionedMemberId = '11111111-2222-3333-4444-555555555555';
    final member = _member('alice', 'Alice');
    final mentioned = _member(mentionedMemberId, 'June');
    final note = _note('n1').copyWith(body: 'Eugh. @[$mentionedMemberId]');
    final router = _router(memberId: member.id);
    addTearDown(router.dispose);

    await tester.pumpWidget(
      _buildApp(
        router: router,
        member: member,
        extraMembers: [mentioned],
        notes: [note],
        settings: const SystemSettings(notesEnabled: true),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Eugh. @June'), findsOneWidget);
    expect(find.textContaining('@[$mentionedMemberId]'), findsNothing);

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
