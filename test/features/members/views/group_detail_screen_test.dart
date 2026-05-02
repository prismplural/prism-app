import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/models/member_group.dart';
import 'package:prism_plurality/domain/models/member_group_entry.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/features/members/providers/member_groups_providers.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/members/views/group_detail_screen.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/member_search_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_glass_icon_button.dart';

class _FakeGroupNotifier extends GroupNotifier {
  final addedMemberIds = <String>[];

  @override
  Future<void> build() async {}

  @override
  Future<void> addMemberToGroup(String groupId, String memberId) async {
    addedMemberIds.add(memberId);
  }
}

Member _member({required String id, required String name}) =>
    Member(id: id, name: name, createdAt: DateTime(2024));

MemberGroup _group({
  required String id,
  required String name,
  String? colorHex,
  String? emoji,
}) => MemberGroup(
  id: id,
  name: name,
  colorHex: colorHex,
  emoji: emoji,
  createdAt: DateTime(2024),
);

Widget _buildSubject({
  required MemberGroup group,
  required List<MemberGroup> allGroups,
  required List<MemberGroupEntry> allEntries,
  required List<Member> activeMembers,
  required _FakeGroupNotifier notifier,
}) {
  return ProviderScope(
    overrides: [
      systemSettingsProvider.overrideWith(
        (ref) => Stream.value(const SystemSettings()),
      ),
      activeMembersProvider.overrideWith((ref) => Stream.value(activeMembers)),
      allGroupsProvider.overrideWith((ref) => Stream.value(allGroups)),
      allGroupEntriesProvider.overrideWith((ref) => Stream.value(allEntries)),
      groupByIdProvider.overrideWith(
        (ref, groupId) => Stream.value(groupId == group.id ? group : null),
      ),
      groupEntriesProvider.overrideWith(
        (ref, groupId) => Stream.value(
          groupId == group.id
              ? const <MemberGroupEntry>[]
              : allEntries.where((entry) => entry.groupId == groupId).toList(),
        ),
      ),
      groupTreeProvider.overrideWith((ref) => {null: allGroups}),
      groupNotifierProvider.overrideWith(() => notifier),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('en')],
      home: GroupDetailScreen(groupId: group.id),
    ),
  );
}

void main() {
  testWidgets(
    'add member uses shared multi-select sheet and keeps group chips',
    (tester) async {
      final targetGroup = _group(id: 'group-target', name: 'Target Group');
      final filterGroup = _group(
        id: 'group-filter',
        name: 'Cluster',
        colorHex: '#7A6E96',
        emoji: '🫂',
      );
      final alice = _member(id: 'alice', name: 'Alice');
      final bob = _member(id: 'bob', name: 'Bob');
      final notifier = _FakeGroupNotifier();

      await tester.pumpWidget(
        _buildSubject(
          group: targetGroup,
          allGroups: [targetGroup, filterGroup],
          allEntries: const [
            MemberGroupEntry(
              id: 'entry-filter-alice',
              groupId: 'group-filter',
              memberId: 'alice',
            ),
          ],
          activeMembers: [alice, bob],
          notifier: notifier,
        ),
      );
      await tester.pumpAndSettle();

      // Default terminology is `headmates`; the button reads
      // "Add {termSingularLower}" → "Add headmate".
      await tester.tap(find.text('Add headmate'));
      await tester.pumpAndSettle();

      expect(find.byType(MemberSearchSheet), findsOneWidget);
      expect(find.text('Cluster'), findsOneWidget);

      await tester.tap(find.text('Alice'));
      await tester.pump();
      await tester.tap(find.text('Bob'));
      await tester.pump();

      final doneButton = find.byWidgetPredicate(
        (widget) =>
            widget is PrismGlassIconButton && widget.icon == AppIcons.check,
      );
      expect(doneButton, findsOneWidget);

      await tester.tap(doneButton);
      await tester.pumpAndSettle();

      expect(notifier.addedMemberIds, containsAll(['alice', 'bob']));
      await tester.pump(const Duration(seconds: 3));
    },
  );
}
