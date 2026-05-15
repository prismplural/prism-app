import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/domain/models/member_group.dart';
import 'package:prism_plurality/domain/models/member_group_entry.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/features/members/providers/member_groups_providers.dart';
import 'package:prism_plurality/features/members/views/groups_screen.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';

class _RecordingGroupNotifier extends GroupNotifier {
  final reorderedSequences = <List<MemberGroup>>[];

  @override
  Future<void> build() async {}

  @override
  Future<void> reorderGroups(List<MemberGroup> groups) async {
    reorderedSequences.add(List.of(groups));
  }
}

MemberGroup _group({
  required String id,
  required String name,
  int displayOrder = 0,
  String? parentGroupId,
  DateTime? createdAt,
}) => MemberGroup(
  id: id,
  name: name,
  displayOrder: displayOrder,
  parentGroupId: parentGroupId,
  createdAt: createdAt ?? DateTime(2024),
);

Widget _buildSubject({
  required List<MemberGroup> groups,
  required _RecordingGroupNotifier notifier,
}) {
  return ProviderScope(
    overrides: [
      systemSettingsProvider.overrideWith(
        (ref) => Stream.value(const SystemSettings()),
      ),
      allGroupsProvider.overrideWith((ref) => Stream.value(groups)),
      allGroupEntriesProvider.overrideWith(
        (ref) => Stream.value(const <MemberGroupEntry>[]),
      ),
      groupNotifierProvider.overrideWith(() => notifier),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('en')],
      builder: (context, child) =>
          PrismToastHost(child: child ?? const SizedBox.shrink()),
      home: const GroupsScreen(showBackButton: false),
    ),
  );
}

void main() {
  testWidgets('offers one-shot sorting for root groups and sub-groups', (
    tester,
  ) async {
    final rootBeta = _group(id: 'root-beta', name: 'Beta', displayOrder: 0);
    final childZed = _group(
      id: 'child-zed',
      name: 'Zed',
      displayOrder: 0,
      parentGroupId: 'root-beta',
    );
    final childAble = _group(
      id: 'child-able',
      name: 'Able',
      displayOrder: 1,
      parentGroupId: 'root-beta',
    );
    final rootAlpha = _group(id: 'root-alpha', name: 'Alpha', displayOrder: 1);
    final notifier = _RecordingGroupNotifier();

    await tester.pumpWidget(
      _buildSubject(
        groups: [rootBeta, childZed, childAble, rootAlpha],
        notifier: notifier,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('More options'), findsOneWidget);

    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Name A'));
    await tester.pumpAndSettle();

    expect(notifier.reorderedSequences.length, 2);
    expect(notifier.reorderedSequences[0].map((group) => group.id).toList(), [
      'root-alpha',
      'root-beta',
    ]);
    expect(notifier.reorderedSequences[1].map((group) => group.id).toList(), [
      'child-able',
      'child-zed',
    ]);
    expect(find.text('Order updated'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
  });
}
