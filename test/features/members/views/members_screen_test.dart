import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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
}) {
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
    ],
    child: const MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: [Locale('en')],
      home: MembersScreen(showBackButton: false),
    ),
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
}
