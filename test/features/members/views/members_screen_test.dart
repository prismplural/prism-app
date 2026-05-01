import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:prism_plurality/core/router/app_routes.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/models/member_group.dart';
import 'package:prism_plurality/domain/models/member_group_entry.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_providers.dart';
import 'package:prism_plurality/features/members/providers/member_groups_providers.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/members/views/members_screen.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/member_search_sheet.dart';

Member _member(String id, {int displayOrder = 0}) => Member(
  id: id,
  name: 'Member $id',
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
                builder: (context, state) =>
                    const MembersScreen(showBackButton: false),
              ),
              GoRoute(
                path: '/members/:id',
                builder: (context, state) =>
                    Text('Member detail ${state.pathParameters['id']}'),
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
      systemSettingsProvider.overrideWith(
        (ref) => Stream.value(const SystemSettings()),
      ),
      activeMembersProvider.overrideWith((ref) => Stream.value(members)),
      allMembersProvider.overrideWith((ref) => Stream.value(members)),
      activeSessionsProvider.overrideWith(
        (ref) => Stream.value(const <FrontingSession>[]),
      ),
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

void main() {
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
    expect(find.text('Deactivate'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);

    await tester.tap(find.text('Add to group'));
    await tester.pumpAndSettle();

    expect(find.text('Groups'), findsOneWidget);
    expect(find.text('No groups yet'), findsOneWidget);
  });
}
