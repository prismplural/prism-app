import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/core/database/database_encryption.dart';
import 'package:prism_plurality/core/router/app_routes.dart';
import 'package:prism_plurality/domain/models/custom_field.dart';
import 'package:prism_plurality/domain/models/custom_field_value.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/models/member_group.dart';
import 'package:prism_plurality/domain/models/member_group_entry.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/features/boards/providers/board_posts_providers.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_providers.dart';
import 'package:prism_plurality/features/members/navigation/member_navigation_branch.dart';
import 'package:prism_plurality/features/members/providers/members_batch_provider.dart';
import 'package:prism_plurality/features/members/providers/custom_fields_providers.dart';
import 'package:prism_plurality/features/members/providers/member_groups_providers.dart';
import 'package:prism_plurality/features/members/providers/member_stats_providers.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/members/providers/notes_providers.dart';
import 'package:prism_plurality/features/members/utils/group_tree_utils.dart';
import 'package:prism_plurality/features/members/views/member_detail_screen.dart';
import 'package:prism_plurality/features/members/views/members_screen.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_sync_config.dart';
import 'package:prism_plurality/features/pluralkit/providers/pluralkit_providers.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_sync_service.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/app_shell.dart';
import 'package:prism_plurality/shared/providers/member_avatar_image_provider.dart';
import 'package:prism_plurality/shared/widgets/member_search_sheet.dart';

import '../../../helpers/fake_repositories.dart';

Member _member(
  String id, {
  int displayOrder = 0,
  String? pronouns,
  bool isActive = true,
}) => Member(
  id: id,
  name: 'Member $id',
  pronouns: pronouns,
  displayOrder: displayOrder,
  createdAt: DateTime(2024),
  isActive: isActive,
);

MemberGroup _group(String id, String name, {int displayOrder = 0}) =>
    MemberGroup(
      id: id,
      name: name,
      displayOrder: displayOrder,
      createdAt: DateTime(2024),
    );

Widget _buildSubject({
  required List<Member> members,
  required List<MemberGroup> groups,
  required List<MemberGroupEntry> entries,
  SystemSettings settings = const SystemSettings(),
  List<FrontingSession> activeSessions = const [],
  List<CustomField> customFields = const [],
  List<CustomFieldValue> customFieldValues = const [],
  _FakeFrontingNotifier? frontingNotifier,
  _FakeMembersNotifier? membersNotifier,
  bool withRouter = false,
}) {
  final activeMembers = members.where((member) => member.isActive).toList();
  final child = withRouter
      ? MaterialApp.router(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: const [Locale('en')],
          routerConfig: GoRouter(
            initialLocation: AppRoutePaths.members,
            routes: [
              GoRoute(
                path: AppRoutePaths.members,
                builder: (context, state) => const MembersScreen(
                  showBackButton: false,
                  branch: MemberNavigationBranch.members,
                ),
                routes: [
                  GoRoute(
                    path: 'groups/:id',
                    builder: (context, state) =>
                        Text('Group detail ${state.pathParameters['id']}'),
                  ),
                  GoRoute(
                    path: ':id',
                    builder: (context, state) =>
                        Text('Member detail ${state.pathParameters['id']}'),
                  ),
                ],
              ),
            ],
          ),
        )
      : const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: [Locale('en')],
          home: MembersScreen(showBackButton: false),
        );
  final appPrefs = FakeAppPreferenceRepository();
  addTearDown(appPrefs.close);

  return ProviderScope(
    overrides: [
      verifiedStartupKeyProvider.overrideWithValue('aa' * 32),
      appPreferenceRepositoryProvider.overrideWithValue(appPrefs),
      systemSettingsProvider.overrideWith((ref) => Stream.value(settings)),
      activeMembersProvider.overrideWith((ref) => Stream.value(activeMembers)),
      allMembersProvider.overrideWith((ref) => Stream.value(members)),
      activeMemberListProvider.overrideWith(
        (ref) => Stream.value(activeMembers),
      ),
      allMemberListProvider.overrideWith((ref) => Stream.value(members)),
      memberByIdProvider.overrideWith((ref, id) {
        for (final member in members) {
          if (member.id == id) return Stream.value(member);
        }
        return Stream.value(null);
      }),
      memberAvatarImageDataProvider.overrideWith(
        (ref, memberId) => Stream.value(null),
      ),
      recentMemberNotesProvider.overrideWith((ref, memberId) {
        return Stream.value(const []);
      }),
      memberFrontingStatsProvider.overrideWith((ref, memberId) async {
        return const MemberFrontingStats(
          totalSessions: 0,
          totalDuration: Duration.zero,
        );
      }),
      memberRecentSessionsProvider.overrideWith((ref, memberId) async {
        return const <FrontingSession>[];
      }),
      memberConversationActivityProvider.overrideWith((ref, memberId) async {
        return const [];
      }),
      memberConversationPreviewActivityProvider.overrideWith((
        ref,
        memberId,
      ) async {
        return const [];
      }),
      memberBoardSectionProvider.overrideWith((ref, memberId) {
        return Stream.value(
          const MemberBoardSection(publicPosts: [], totalPublic: 0),
        );
      }),
      customFieldsProvider.overrideWithValue(AsyncValue.data(customFields)),
      memberCustomFieldValuesProvider.overrideWith(
        (ref, memberId) => Stream.value(
          customFieldValues
              .where((value) => value.memberId == memberId)
              .toList(growable: false),
        ),
      ),
      pluralKitSyncProvider.overrideWith(
        () => _FakePluralKitSyncNotifier(
          const PluralKitSyncState(isConnected: false),
        ),
      ),
      pkSyncDirectionProvider.overrideWith(
        () => _StaticPkSyncDirectionNotifier(PkSyncDirection.pullOnly),
      ),
      activeSessionsProvider.overrideWith(
        (ref) => Stream.value(activeSessions),
      ),
      if (frontingNotifier != null)
        frontingNotifierProvider.overrideWith(() => frontingNotifier),
      if (membersNotifier != null)
        membersNotifierProvider.overrideWith(() => membersNotifier),
      allGroupsProvider.overrideWith((ref) => Stream.value(groups)),
      allGroupEntriesProvider.overrideWith((ref) => Stream.value(entries)),
      groupByIdProvider.overrideWith((ref, groupId) {
        final matching = groups.where((group) => group.id == groupId);
        return Stream.value(matching.isEmpty ? null : matching.first);
      }),
      groupEntriesProvider.overrideWith(
        (ref, groupId) => Stream.value(
          entries.where((entry) => entry.groupId == groupId).toList(),
        ),
      ),
      groupTreeProvider.overrideWith(
        (ref) => GroupTreeUtils.buildGroupTree(groups),
      ),
      memberGroupsProvider.overrideWith((ref, memberId) {
        final groupIds = entries
            .where((entry) => entry.memberId == memberId)
            .map((entry) => entry.groupId)
            .toSet();
        return Stream.value(
          groups.where((group) => groupIds.contains(group.id)).toList(),
        );
      }),
      membersByIdsListProvider.overrideWith((ref, idsKey) {
        final ids = idsKey.isEmpty
            ? const <String>{}
            : idsKey.split(',').toSet();
        return Stream.value({
          for (final member in members)
            if (ids.contains(member.id)) member.id: member,
        });
      }),
    ],
    child: child,
  );
}

Finder _memberDetailEditButton() => find
    .descendant(
      of: find.byType(MemberDetailScreen),
      matching: find.byIcon(AppIcons.editOutlined),
    )
    .hitTestable();

class _FakeFrontingNotifier extends FrontingNotifier {
  final startFrontingCalls = <List<String>>[];
  final replaceFrontingCalls = <List<String>>[];

  @override
  Future<void> build() async {}

  @override
  Future<void> startFronting(
    List<String> memberIds, {
    FrontConfidence? confidence,
    String? notes,
    DateTime? startTime,
  }) async {
    startFrontingCalls.add(memberIds);
  }

  @override
  Future<void> replaceFronting(
    List<String> memberIds, {
    FrontConfidence? confidence,
    String? notes,
    DateTime? startTime,
  }) async {
    replaceFrontingCalls.add(memberIds);
  }
}

class _FakeMembersNotifier extends MembersNotifier {
  _FakeMembersNotifier({this.reorderCompleter});

  final Completer<void>? reorderCompleter;
  final reorderedSequences = <List<Member>>[];
  final deletedIds = <String>[];

  @override
  Future<void> build() async {}

  @override
  Future<void> reorderMembers(List<Member> members) async {
    reorderedSequences.add(List.of(members));
    await (reorderCompleter?.future ?? Future<void>.value());
  }

  @override
  Future<void> deleteMember(String id) async {
    deletedIds.add(id);
  }
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
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'prism.members.view_settings_banner_seen': true,
    });
  });

  testWidgets('wide layout starts with no member selected', (tester) async {
    _setWideWindow(tester);

    await tester.pumpWidget(
      _buildSubject(
        settings: const SystemSettings(
          notesEnabled: false,
          boardsEnabled: false,
        ),
        members: [_member('alice')],
        groups: const [],
        entries: const [],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Select a headmate'), findsOneWidget);
    expect(find.text('Member alice'), findsOneWidget);
  });

  testWidgets('wide layout edits selected member inside the detail pane', (
    tester,
  ) async {
    _setWideWindow(tester);

    await tester.pumpWidget(
      _buildSubject(
        settings: const SystemSettings(
          notesEnabled: false,
          boardsEnabled: false,
        ),
        members: [_member('alice')],
        groups: const [],
        entries: const [],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Member alice'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(_memberDetailEditButton().first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byKey(const Key('detailSideSheetPanel')), findsNothing);
    expect(find.text('Style'), findsOneWidget);
    expect(find.text('Name *'), findsOneWidget);
    expect(find.text('Bio'), findsOneWidget);

    await tester.tap(find.text('Custom Fields'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byKey(const Key('detailSideSheetPanel')), findsNothing);
    expect(find.text('Custom Fields'), findsNWidgets(2));
  });

  testWidgets('wide layout system back clears selected member detail', (
    tester,
  ) async {
    _setWideWindow(tester);

    await tester.pumpWidget(
      _buildSubject(
        members: [_member('alice')],
        groups: const [],
        entries: const [],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Select a headmate'), findsOneWidget);

    await tester.tap(find.text('Member alice'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Select a headmate'), findsNothing);

    final handled = await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(handled, isTrue);
    expect(find.text('Select a headmate'), findsOneWidget);
    expect(find.text('Member alice'), findsOneWidget);
  });

  testWidgets(
    'wide layout system back confirms before closing dirty edit pane',
    (tester) async {
      _setWideWindow(tester);

      await tester.pumpWidget(
        _buildSubject(
          settings: const SystemSettings(
            notesEnabled: false,
            boardsEnabled: false,
          ),
          members: [_member('alice')],
          groups: const [],
          entries: const [],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Member alice'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(_memberDetailEditButton().first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      await tester.enterText(find.byType(EditableText).first, 'Edited alice');
      await tester.pump();

      final firstBackHandled = await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(firstBackHandled, isTrue);
      expect(find.text('Discard changes?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Name *'), findsOneWidget);
      expect(find.text('Edited alice'), findsOneWidget);

      final secondBackHandled = await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();

      expect(secondBackHandled, isTrue);
      expect(find.text('Name *'), findsNothing);
      expect(find.text('Edited alice'), findsNothing);
      expect(find.text('Member alice'), findsWidgets);
    },
  );

  testWidgets('wide layout delete clears detail without popping app route', (
    tester,
  ) async {
    _setWideWindow(tester);

    final membersNotifier = _FakeMembersNotifier();

    await tester.pumpWidget(
      _buildSubject(
        members: [_member('alice')],
        groups: const [],
        entries: const [],
        membersNotifier: membersNotifier,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Member alice'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.byIcon(AppIcons.moreVert).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();

    expect(membersNotifier.deletedIds, ['alice']);
    expect(find.byType(MembersScreen), findsOneWidget);
    expect(find.text('Select a headmate'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'wide layout edits long-text custom fields inside the detail pane',
    (tester) async {
      _setWideWindow(tester);

      final topLevelLongText = CustomField(
        id: 'second-bio',
        name: 'Second Bio',
        fieldType: CustomFieldType.longText,
        fieldTypeId: 'long_text',
        displayOrder: 0,
        createdAt: DateTime(2024),
      );
      final group = CustomField(
        id: 'profile-details',
        name: 'Profile Details',
        fieldType: CustomFieldType.text,
        fieldTypeId: 'group',
        displayOrder: 1,
        createdAt: DateTime(2024),
      );
      final groupedLongText = CustomField(
        id: 'grouped-note',
        name: 'Grouped Note',
        fieldType: CustomFieldType.longText,
        fieldTypeId: 'long_text',
        parentFieldId: group.id,
        createdAt: DateTime(2024),
      );

      await tester.pumpWidget(
        _buildSubject(
          settings: const SystemSettings(
            notesEnabled: false,
            boardsEnabled: false,
          ),
          members: [_member('alice')],
          groups: const [],
          entries: const [],
          customFields: [topLevelLongText, group, groupedLongText],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Member alice'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(_memberDetailEditButton().first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('Custom Fields'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      await tester.tap(find.byIcon(AppIcons.edit).hitTestable().first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byKey(const Key('detailSideSheetPanel')), findsNothing);
      expect(find.text('Second Bio'), findsNWidgets(2));

      await tester.tap(find.byIcon(AppIcons.check).hitTestable().last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      await tester.tap(find.byIcon(AppIcons.edit).hitTestable().last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byKey(const Key('detailSideSheetPanel')), findsNothing);
      expect(find.text('Grouped Note'), findsNWidgets(2));
    },
  );

  testWidgets('group chips stay reachable after jumping to a section', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 480));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final topGroup = _group('top', 'Top');
    final laterGroup = _group('later', 'Later', displayOrder: 1);
    final topMembers = List.generate(
      6,
      (index) => _member('top-$index', displayOrder: index),
    );
    final laterMember = _member('later-0', displayOrder: topMembers.length);
    final members = [...topMembers, laterMember];
    final entries = [
      for (final member in topMembers)
        MemberGroupEntry(
          id: 'entry-${member.id}',
          groupId: topGroup.id,
          memberId: member.id,
        ),
      MemberGroupEntry(
        id: 'entry-${laterMember.id}',
        groupId: laterGroup.id,
        memberId: laterMember.id,
      ),
    ];

    await tester.pumpWidget(
      _buildSubject(
        settings: const SystemSettings(
          membersListViewMode: MembersListViewMode.groupedSections,
        ),
        members: members,
        groups: [topGroup, laterGroup],
        entries: entries,
      ),
    );
    await tester.pumpAndSettle();

    final allChip = find.text('All');
    final initialChipTop = tester.getTopLeft(allChip).dy;

    await tester.tap(find.text('Later • 1'));
    await tester.pumpAndSettle();

    expect(find.text('Member later-0'), findsOneWidget);
    expect(tester.getTopLeft(allChip).dy, initialChipTop);
    expect(tester.getTopLeft(allChip).dy, greaterThanOrEqualTo(0));
  });

  testWidgets('grouped sections keep visible rows anchored across rebuilds', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 480));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final groups = List.generate(
      18,
      (index) => _group('group-$index', 'Group $index', displayOrder: index),
    );
    final insertedGroup = _group('group-new', 'Group New', displayOrder: -1);
    final members = List.generate(
      18,
      (index) => _member('member-$index', displayOrder: index),
    );
    final insertedMember = _member('member-new', displayOrder: -1);
    final sharedMember = _member('member-shared', displayOrder: 99);
    final entries = [
      for (var i = 0; i < groups.length; i++)
        MemberGroupEntry(
          id: 'entry-$i',
          groupId: groups[i].id,
          memberId: members[i].id,
        ),
      const MemberGroupEntry(
        id: 'entry-shared-8',
        groupId: 'group-8',
        memberId: 'member-shared',
      ),
      const MemberGroupEntry(
        id: 'entry-shared-9',
        groupId: 'group-9',
        memberId: 'member-shared',
      ),
    ];
    const anchoredRowKey = ValueKey((
      'members-grouped-member',
      'group-9',
      'member-shared',
    ));

    await tester.pumpWidget(
      _buildSubject(
        settings: const SystemSettings(
          membersListViewMode: MembersListViewMode.groupedSections,
        ),
        members: [...members, sharedMember],
        groups: groups,
        entries: entries,
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(anchoredRowKey),
      240,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    final before = tester.getTopLeft(find.byKey(anchoredRowKey)).dy;

    await tester.pumpWidget(
      _buildSubject(
        settings: const SystemSettings(
          membersListViewMode: MembersListViewMode.groupedSections,
        ),
        members: [insertedMember, ...members, sharedMember],
        groups: [insertedGroup, ...groups],
        entries: [
          const MemberGroupEntry(
            id: 'entry-new',
            groupId: 'group-new',
            memberId: 'member-new',
          ),
          ...entries,
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(anchoredRowKey), findsOneWidget);
    expect(
      tester.getTopLeft(find.byKey(anchoredRowKey)).dy,
      closeTo(before, 1),
    );
  });

  testWidgets('flat reorder keeps optimistic order while notifier is pending', (
    tester,
  ) async {
    final persistence = Completer<void>();
    final membersNotifier = _FakeMembersNotifier(reorderCompleter: persistence);
    final alice = _member('alice');
    final bob = _member('bob', displayOrder: 1);
    final carol = _member('carol', displayOrder: 2);

    await tester.pumpWidget(
      _buildSubject(
        members: [alice, bob, carol],
        groups: const [],
        entries: const [],
        membersNotifier: membersNotifier,
      ),
    );
    await tester.pumpAndSettle();

    final listView = tester.widget<ReorderableListView>(
      find.byType(ReorderableListView),
    );
    listView.onReorder!(1, 0);
    await tester.pump();

    expect(membersNotifier.reorderedSequences, hasLength(1));
    expect(
      membersNotifier.reorderedSequences.single.map((member) => member.id),
      ['bob', 'alice', 'carol'],
    );
    expect(
      tester.getTopLeft(find.text('Member bob')).dy,
      lessThan(tester.getTopLeft(find.text('Member alice')).dy),
    );

    persistence.complete();
    await tester.pumpAndSettle();
  });

  testWidgets(
    'members screen follows shared show-inactive state before grouped reorder',
    (tester) async {
      final membersNotifier = _FakeMembersNotifier();
      final alice = _member('alice');
      final bob = _member('bob', displayOrder: 2);
      final inactive = _member('zara', displayOrder: 1, isActive: false);
      final group = _group('crew', 'Crew');

      await tester.pumpWidget(
        _buildSubject(
          settings: const SystemSettings(
            membersListViewMode: MembersListViewMode.groupedSections,
          ),
          members: [alice, inactive, bob],
          groups: [group],
          entries: const [
            MemberGroupEntry(
              id: 'entry-alice',
              groupId: 'crew',
              memberId: 'alice',
            ),
            MemberGroupEntry(
              id: 'entry-zara',
              groupId: 'crew',
              memberId: 'zara',
            ),
            MemberGroupEntry(id: 'entry-bob', groupId: 'crew', memberId: 'bob'),
          ],
          membersNotifier: membersNotifier,
        ),
      );
      await tester.pumpAndSettle();

      final scope = ProviderScope.containerOf(
        tester.element(find.byType(MembersScreen)),
        listen: false,
      );
      scope.read(showInactiveMembersProvider.notifier).set(true);
      await tester.pumpAndSettle();

      expect(find.text('Member zara'), findsOneWidget);

      await tester.tap(find.byIcon(AppIcons.moreVert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Name A–Z'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 3));

      expect(membersNotifier.reorderedSequences, hasLength(1));
      expect(
        membersNotifier.reorderedSequences.single.map((member) => member.id),
        ['alice', 'bob', 'zara'],
      );
    },
  );

  testWidgets('options search opens shared sheet and navigates on selection', (
    tester,
  ) async {
    final group = _group('crew', 'Crew');
    final members = [_member('alice'), _member('bob', displayOrder: 1)];

    await tester.pumpWidget(
      _buildSubject(
        members: members,
        groups: [group],
        entries: const [
          MemberGroupEntry(
            id: 'entry-alice',
            groupId: 'crew',
            memberId: 'alice',
          ),
        ],
        withRouter: true,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(AppIcons.moreVert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Search headmates...'));
    await tester.pumpAndSettle();

    expect(find.byType(MemberSearchSheet), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(MemberSearchSheet),
        matching: find.text('Crew'),
      ),
      findsOneWidget,
    );

    await tester.enterText(find.byType(TextField), 'bob');
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(MemberSearchSheet),
        matching: find.text('Member bob'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(MemberSearchSheet), findsNothing);
    expect(find.text('Member detail bob'), findsOneWidget);
  });

  testWidgets('options menu opens view settings sheet without moving search', (
    tester,
  ) async {
    // The view-settings sheet is a full-screen lazy ListView; a tall viewport
    // lets the lower sections ('Display'/'Show pronouns') build for assertion.
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final members = [_member('alice')];

    await tester.pumpWidget(
      _buildSubject(members: members, groups: const [], entries: const []),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(AppIcons.moreVert));
    await tester.pumpAndSettle();

    expect(find.text('Search headmates...'), findsOneWidget);
    await tester.tap(find.text('View Settings'));
    await tester.pumpAndSettle();

    expect(find.text('View'), findsOneWidget);
    expect(find.text('Sections'), findsOneWidget);
    expect(find.text('Folders'), findsOneWidget);
    expect(find.text('Display'), findsOneWidget);
    expect(find.text('Show pronouns'), findsOneWidget);
    expect(find.text('Front buttons'), findsOneWidget);
    expect(find.text('Show front buttons'), findsOneWidget);
    expect(
      find.text('Show a direct front action next to each member in the list.'),
      findsNothing,
    );
    expect(find.text('Add'), findsNothing);
    expect(find.text('Replace'), findsNothing);
  });

  testWidgets('default settings show folders and all members below groups', (
    tester,
  ) async {
    final group = _group('crew', 'Crew');
    final members = [_member('alice'), _member('bob', displayOrder: 1)];

    await tester.pumpWidget(
      _buildSubject(
        members: members,
        groups: [group],
        entries: const [
          MemberGroupEntry(
            id: 'entry-alice',
            groupId: 'crew',
            memberId: 'alice',
          ),
        ],
        withRouter: true,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Crew'), findsOneWidget);
    expect(find.text('Crew • 1'), findsNothing);
    expect(find.text('Member alice'), findsOneWidget);
    expect(find.text('Member bob'), findsOneWidget);
  });

  testWidgets('explicit sections preference is preserved', (tester) async {
    final group = _group('crew', 'Crew');
    final members = [_member('alice'), _member('bob', displayOrder: 1)];

    await tester.pumpWidget(
      _buildSubject(
        settings: const SystemSettings(
          membersListViewMode: MembersListViewMode.groupedSections,
        ),
        members: members,
        groups: [group],
        entries: const [
          MemberGroupEntry(
            id: 'entry-alice',
            groupId: 'crew',
            memberId: 'alice',
          ),
        ],
        withRouter: true,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Crew • 1'), findsOneWidget);
  });

  testWidgets('old default settings banner opens view settings and marks seen', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final members = [_member('alice')];

    await tester.pumpWidget(
      _buildSubject(
        settings: const SystemSettings(
          membersListViewMode: MembersListViewMode.groupedSections,
        ),
        members: members,
        groups: const [],
        entries: const [],
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Group and headmate view preferences can be adjusted in View Settings.',
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('View Settings'));
    await tester.pumpAndSettle();

    expect(find.text('View'), findsOneWidget);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('prism.members.view_settings_banner_seen'), isTrue);
  });

  testWidgets('new default settings still show the view settings banner once', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final members = [_member('alice')];

    await tester.pumpWidget(
      _buildSubject(members: members, groups: const [], entries: const []),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Group and headmate view preferences can be adjusted in View Settings.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('customized view settings skip the default-layout banner', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final members = [_member('alice')];

    await tester.pumpWidget(
      _buildSubject(
        settings: const SystemSettings(
          membersListViewMode: MembersListViewMode.folders,
          membersFolderMemberVisibility:
              MembersFolderMemberVisibility.ungroupedOnly,
        ),
        members: members,
        groups: const [],
        entries: const [],
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Group and headmate view preferences can be adjusted in View Settings.',
      ),
      findsNothing,
    );
  });

  testWidgets('old default settings banner can be dismissed permanently', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final members = [_member('alice')];

    await tester.pumpWidget(
      _buildSubject(
        settings: const SystemSettings(
          membersListViewMode: MembersListViewMode.groupedSections,
        ),
        members: members,
        groups: const [],
        entries: const [],
      ),
    );
    await tester.pumpAndSettle();

    // The banner uses InfoBanner(actionsBelow: true), so dismiss renders as a
    // labeled button ("Dismiss"), not a tooltipped icon.
    await tester.tap(find.text('Dismiss'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Group and headmate view preferences can be adjusted in View Settings.',
      ),
      findsNothing,
    );

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('prism.members.view_settings_banner_seen'), isTrue);
  });

  testWidgets('view settings shows front button behavior when enabled', (
    tester,
  ) async {
    final members = [_member('alice')];

    await tester.pumpWidget(
      _buildSubject(
        settings: const SystemSettings(membersShowFrontButtons: true),
        members: members,
        groups: const [],
        entries: const [],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(AppIcons.moreVert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('View Settings'));
    await tester.pumpAndSettle();

    expect(find.text('Front buttons'), findsOneWidget);
    expect(
      find.text('Show a direct front action next to each member in the list.'),
      findsOneWidget,
    );
    expect(find.text('Add'), findsOneWidget);
    expect(find.text('Replace'), findsOneWidget);
  });

  testWidgets('member rows hide pronouns when disabled in view settings', (
    tester,
  ) async {
    final members = [_member('alice', pronouns: 'she/her')];

    await tester.pumpWidget(
      _buildSubject(
        settings: const SystemSettings(membersShowPronouns: false),
        members: members,
        groups: const [],
        entries: const [],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Member alice'), findsOneWidget);
    expect(find.text('she/her'), findsNothing);
  });

  testWidgets('folder view shows groups first and opens group detail', (
    tester,
  ) async {
    final group = _group('crew', 'Crew');
    final members = [_member('alice'), _member('bob', displayOrder: 1)];

    await tester.pumpWidget(
      _buildSubject(
        settings: const SystemSettings(
          membersListViewMode: MembersListViewMode.folders,
          notesEnabled: false,
          boardsEnabled: false,
        ),
        members: members,
        groups: [group],
        entries: const [
          MemberGroupEntry(
            id: 'entry-alice',
            groupId: 'crew',
            memberId: 'alice',
          ),
        ],
        withRouter: true,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Crew'), findsOneWidget);
    expect(find.text('Member alice'), findsOneWidget);
    expect(find.text('Member bob'), findsOneWidget);

    await tester.tap(find.text('Crew'));
    await tester.pumpAndSettle();

    expect(find.text('Group detail crew'), findsOneWidget);
  });

  testWidgets('wide folder view back returns from group detail to folders', (
    tester,
  ) async {
    _setWideWindow(tester);

    final group = _group('crew', 'Crew');
    final members = [_member('alice'), _member('bob', displayOrder: 1)];

    await tester.pumpWidget(
      _buildSubject(
        settings: const SystemSettings(
          membersListViewMode: MembersListViewMode.folders,
          notesEnabled: false,
          boardsEnabled: false,
        ),
        members: members,
        groups: [group],
        entries: const [
          MemberGroupEntry(
            id: 'entry-alice',
            groupId: 'crew',
            memberId: 'alice',
          ),
        ],
        withRouter: true,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Crew'), findsOneWidget);
    expect(find.byTooltip('Back'), findsNothing);

    await tester.tap(find.text('Crew'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Back'), findsOneWidget);
    expect(find.text('Member alice'), findsOneWidget);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Back'), findsNothing);
    expect(find.text('Crew'), findsOneWidget);
    expect(find.text('Member bob'), findsOneWidget);
  });

  testWidgets('wide folder view handles system back from group detail', (
    tester,
  ) async {
    _setWideWindow(tester);

    final group = _group('crew', 'Crew');
    final members = [_member('alice'), _member('bob', displayOrder: 1)];

    await tester.pumpWidget(
      _buildSubject(
        settings: const SystemSettings(
          membersListViewMode: MembersListViewMode.folders,
        ),
        members: members,
        groups: [group],
        entries: const [
          MemberGroupEntry(
            id: 'entry-alice',
            groupId: 'crew',
            memberId: 'alice',
          ),
        ],
        withRouter: true,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Crew'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Back'), findsOneWidget);

    final handled = await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(handled, isTrue);
    expect(find.byTooltip('Back'), findsNothing);
    expect(find.text('Crew'), findsOneWidget);
    expect(find.text('Member bob'), findsOneWidget);
  });

  testWidgets('wide folder view resets when the members tab is selected', (
    tester,
  ) async {
    _setWideWindow(tester);

    final group = _group('crew', 'Crew');
    final members = [_member('alice'), _member('bob', displayOrder: 1)];

    await tester.pumpWidget(
      _buildSubject(
        settings: const SystemSettings(
          membersListViewMode: MembersListViewMode.folders,
        ),
        members: members,
        groups: [group],
        entries: const [
          MemberGroupEntry(
            id: 'entry-alice',
            groupId: 'crew',
            memberId: 'alice',
          ),
        ],
        withRouter: true,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Crew'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Back'), findsOneWidget);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(MembersScreen)),
    );
    container
        .read(tabSelectionProvider.notifier)
        .fire(
          branchIndex: appShellBranchIndex(AppShellTabId.members),
          isRetap: false,
        );
    await tester.pumpAndSettle();

    expect(find.byTooltip('Back'), findsNothing);
    expect(find.text('Crew'), findsOneWidget);
    expect(find.text('Member bob'), findsOneWidget);

    await tester.tap(find.text('Crew'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Back'), findsOneWidget);

    container
        .read(tabSelectionProvider.notifier)
        .fire(
          branchIndex: appShellBranchIndex(AppShellTabId.members),
          isRetap: true,
        );
    await tester.pumpAndSettle();

    expect(find.byTooltip('Back'), findsNothing);
    expect(find.text('Crew'), findsOneWidget);
    expect(find.text('Member bob'), findsOneWidget);
  });

  testWidgets('wide folder view system back closes edit before group pane', (
    tester,
  ) async {
    _setWideWindow(tester);

    final group = _group('crew', 'Crew');
    final members = [_member('alice'), _member('bob', displayOrder: 1)];

    await tester.pumpWidget(
      _buildSubject(
        settings: const SystemSettings(
          membersListViewMode: MembersListViewMode.folders,
        ),
        members: members,
        groups: [group],
        entries: const [
          MemberGroupEntry(
            id: 'entry-alice',
            groupId: 'crew',
            memberId: 'alice',
          ),
        ],
        withRouter: true,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Crew'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Member alice').hitTestable().first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(_memberDetailEditButton().first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Name *'), findsOneWidget);
    expect(find.byTooltip('Back'), findsOneWidget);
    expect(find.text('Member bob'), findsNothing);

    final handled = await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(handled, isTrue);
    expect(find.text('Name *'), findsNothing);
    expect(find.byTooltip('Back'), findsOneWidget);
    expect(find.text('Member bob'), findsNothing);
  });

  testWidgets('wide folder view tab selection preserves active edit context', (
    tester,
  ) async {
    _setWideWindow(tester);

    final group = _group('crew', 'Crew');
    final members = [_member('alice'), _member('bob', displayOrder: 1)];

    await tester.pumpWidget(
      _buildSubject(
        settings: const SystemSettings(
          membersListViewMode: MembersListViewMode.folders,
        ),
        members: members,
        groups: [group],
        entries: const [
          MemberGroupEntry(
            id: 'entry-alice',
            groupId: 'crew',
            memberId: 'alice',
          ),
        ],
        withRouter: true,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Crew'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Member alice').hitTestable().first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(_memberDetailEditButton().first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Name *'), findsOneWidget);
    expect(find.byTooltip('Back'), findsOneWidget);
    expect(find.text('Member bob'), findsNothing);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(MembersScreen)),
    );
    container
        .read(tabSelectionProvider.notifier)
        .fire(
          branchIndex: appShellBranchIndex(AppShellTabId.members),
          isRetap: true,
        );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Name *'), findsOneWidget);
    expect(find.byTooltip('Back'), findsOneWidget);
    expect(find.text('Member bob'), findsNothing);
  });

  testWidgets('folder view can show only ungrouped members below groups', (
    tester,
  ) async {
    final group = _group('crew', 'Crew');
    final members = [_member('alice'), _member('bob', displayOrder: 1)];

    await tester.pumpWidget(
      _buildSubject(
        settings: const SystemSettings(
          membersListViewMode: MembersListViewMode.folders,
          membersFolderMemberVisibility:
              MembersFolderMemberVisibility.ungroupedOnly,
        ),
        members: members,
        groups: [group],
        entries: const [
          MemberGroupEntry(
            id: 'entry-alice',
            groupId: 'crew',
            memberId: 'alice',
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Crew'), findsOneWidget);
    expect(find.text('Member alice'), findsNothing);
    expect(find.text('Member bob'), findsOneWidget);
  });

  testWidgets('front button starts member in additive mode', (tester) async {
    final notifier = _FakeFrontingNotifier();
    final members = [_member('alice')];

    await tester.pumpWidget(
      _buildSubject(
        settings: const SystemSettings(membersShowFrontButtons: true),
        members: members,
        groups: const [],
        entries: const [],
        frontingNotifier: notifier,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Add Member alice to front'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3));

    expect(notifier.startFrontingCalls, [
      ['alice'],
    ]);
    expect(notifier.replaceFrontingCalls, isEmpty);
  });

  testWidgets('front button replaces front in replace mode', (tester) async {
    final notifier = _FakeFrontingNotifier();
    final members = [_member('alice')];

    await tester.pumpWidget(
      _buildSubject(
        settings: const SystemSettings(
          membersShowFrontButtons: true,
          membersFrontButtonBehavior: FrontStartBehavior.replace,
        ),
        members: members,
        groups: const [],
        entries: const [],
        frontingNotifier: notifier,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Replace front with Member alice'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3));

    expect(notifier.startFrontingCalls, isEmpty);
    expect(notifier.replaceFrontingCalls, [
      ['alice'],
    ]);
  });

  testWidgets('fronting member shows pill instead of front button', (
    tester,
  ) async {
    final members = [_member('alice')];

    await tester.pumpWidget(
      _buildSubject(
        settings: const SystemSettings(membersShowFrontButtons: true),
        members: members,
        groups: const [],
        entries: const [],
        activeSessions: [
          FrontingSession(
            id: 'session-alice',
            memberId: 'alice',
            startTime: DateTime(2024),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Fronting'), findsOneWidget);
    expect(find.byTooltip('Add Member alice to front'), findsNothing);
  });

  testWidgets('long-press set as fronter follows replace preference', (
    tester,
  ) async {
    final notifier = _FakeFrontingNotifier();
    final members = [_member('alice')];

    await tester.pumpWidget(
      _buildSubject(
        settings: const SystemSettings(
          membersFrontButtonBehavior: FrontStartBehavior.replace,
        ),
        members: members,
        groups: const [],
        entries: const [],
        frontingNotifier: notifier,
      ),
    );
    await tester.pumpAndSettle();

    await tester.longPress(find.text('Member alice'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Set as fronter'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3));

    expect(notifier.startFrontingCalls, isEmpty);
    expect(notifier.replaceFrontingCalls, [
      ['alice'],
    ]);
  });

  testWidgets('member rows expose actions from long-press menu', (
    tester,
  ) async {
    final members = [_member('alice')];

    await tester.pumpWidget(
      _buildSubject(members: members, groups: const [], entries: const []),
    );
    await tester.pumpAndSettle();

    expect(find.byType(Dismissible), findsNothing);

    await tester.longPress(find.text('Member alice'));
    await tester.pumpAndSettle();

    expect(find.text('Set as fronter'), findsOneWidget);
    expect(find.text('Add to group'), findsOneWidget);
    expect(find.text('Archive'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);

    await tester.tap(find.text('Add to group'));
    await tester.pumpAndSettle();

    expect(find.text('Groups'), findsOneWidget);
    expect(find.text('No groups yet'), findsOneWidget);
  });

  testWidgets('member long-press menu emits selection haptic', (tester) async {
    final hapticCalls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'HapticFeedback.vibrate') {
            hapticCalls.add(call);
          }
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    await tester.pumpWidget(
      _buildSubject(
        members: [_member('alice')],
        groups: const [],
        entries: const [],
      ),
    );
    await tester.pumpAndSettle();

    await tester.longPress(find.text('Member alice'));
    await tester.pumpAndSettle();

    expect(find.text('Set as fronter'), findsOneWidget);
    expect(
      hapticCalls.any(
        (call) => call.arguments == 'HapticFeedbackType.selectionClick',
      ),
      isTrue,
    );
  });

  testWidgets('archive action confirms before changing member state', (
    tester,
  ) async {
    final members = [_member('alice')];

    await tester.pumpWidget(
      _buildSubject(members: members, groups: const [], entries: const []),
    );
    await tester.pumpAndSettle();

    await tester.longPress(find.text('Member alice'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Archive'));
    await tester.pumpAndSettle();

    expect(find.text('Archive headmate?'), findsOneWidget);
    expect(
      find.textContaining('Member alice will be moved to inactive headmates.'),
      findsOneWidget,
    );
  });
}

void _setWideWindow(WidgetTester tester) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(1200, 800);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}
