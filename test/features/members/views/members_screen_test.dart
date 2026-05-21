import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:prism_plurality/core/router/app_routes.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/models/member_group.dart';
import 'package:prism_plurality/domain/models/member_group_entry.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_providers.dart';
import 'package:prism_plurality/features/members/navigation/member_navigation_branch.dart';
import 'package:prism_plurality/features/members/providers/member_groups_providers.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/members/views/members_screen.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/member_search_sheet.dart';

Member _member(String id, {int displayOrder = 0, String? pronouns}) => Member(
  id: id,
  name: 'Member $id',
  pronouns: pronouns,
  displayOrder: displayOrder,
  createdAt: DateTime(2024),
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
  _FakeFrontingNotifier? frontingNotifier,
  bool withRouter = false,
}) {
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

  return ProviderScope(
    overrides: [
      systemSettingsProvider.overrideWith((ref) => Stream.value(settings)),
      activeMembersProvider.overrideWith((ref) => Stream.value(members)),
      allMembersProvider.overrideWith((ref) => Stream.value(members)),
      activeSessionsProvider.overrideWith(
        (ref) => Stream.value(activeSessions),
      ),
      if (frontingNotifier != null)
        frontingNotifierProvider.overrideWith(() => frontingNotifier),
      allGroupsProvider.overrideWith((ref) => Stream.value(groups)),
      allGroupEntriesProvider.overrideWith((ref) => Stream.value(entries)),
      memberGroupsProvider.overrideWith((ref, memberId) {
        final groupIds = entries
            .where((entry) => entry.memberId == memberId)
            .map((entry) => entry.groupId)
            .toSet();
        return Stream.value(
          groups.where((group) => groupIds.contains(group.id)).toList(),
        );
      }),
    ],
    child: child,
  );
}

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
  }) async {
    replaceFrontingCalls.add(memberIds);
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'prism.members.view_settings_banner_seen': true,
    });
  });

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

    await tester.tap(find.byTooltip('Dismiss'));
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
