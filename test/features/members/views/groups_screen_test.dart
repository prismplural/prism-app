import 'dart:async';

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
  _RecordingGroupNotifier({this.reorderCompleter});

  final Completer<void>? reorderCompleter;
  final reorderedSequences = <List<MemberGroup>>[];

  @override
  Future<void> build() async {}

  @override
  Future<void> reorderGroups(List<MemberGroup> groups) async {
    reorderedSequences.add(List.of(groups));
    await (reorderCompleter?.future ?? Future<void>.value());
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

    expect(find.text('Sort groups'), findsOneWidget);
    await tester.tap(find.text('Groups and sub-groups'));
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

  testWidgets('can sort only top-level groups when sub-groups exist', (
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

    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Name A'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Top-level groups only'));
    await tester.pumpAndSettle();

    expect(notifier.reorderedSequences.length, 1);
    expect(
      notifier.reorderedSequences.single.map((group) => group.id).toList(),
      ['root-alpha', 'root-beta'],
    );
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('keeps overflow visible for a single group', (tester) async {
    final group = _group(id: 'solo', name: 'Solo');
    final notifier = _RecordingGroupNotifier();

    await tester.pumpWidget(_buildSubject(groups: [group], notifier: notifier));
    await tester.pumpAndSettle();

    expect(find.byTooltip('More options'), findsOneWidget);

    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Name A'));
    await tester.pumpAndSettle();

    expect(notifier.reorderedSequences, isEmpty);
  });

  testWidgets(
    'dragging a root group below an expanded root reorders root siblings '
    'optimistically',
    (tester) async {
      final alpha = _group(id: 'alpha', name: 'Alpha', displayOrder: 0);
      final beta = _group(id: 'beta', name: 'Beta', displayOrder: 1);
      final betaChildOne = _group(
        id: 'beta-child-one',
        name: 'Beta child one',
        displayOrder: 0,
        parentGroupId: 'beta',
      );
      final betaChildTwo = _group(
        id: 'beta-child-two',
        name: 'Beta child two',
        displayOrder: 1,
        parentGroupId: 'beta',
      );
      final gamma = _group(id: 'gamma', name: 'Gamma', displayOrder: 2);
      final persistence = Completer<void>();
      final notifier = _RecordingGroupNotifier(reorderCompleter: persistence);

      await tester.pumpWidget(
        _buildSubject(
          groups: [alpha, beta, betaChildOne, betaChildTwo, gamma],
          notifier: notifier,
        ),
      );
      await tester.pumpAndSettle();

      final alphaHandle = find.byType(ReorderableDragStartListener).first;
      await tester.timedDrag(
        alphaHandle,
        const Offset(0, 220),
        const Duration(milliseconds: 500),
      );
      await tester.pumpAndSettle();

      expect(notifier.reorderedSequences.length, 1);
      expect(notifier.reorderedSequences.single.map((g) => g.id), [
        'beta',
        'alpha',
        'gamma',
      ]);
      expect(
        tester.getTopLeft(find.text('Beta')).dy <
            tester.getTopLeft(find.text('Alpha')).dy,
        isTrue,
      );

      persistence.complete();
      await tester.pumpAndSettle();
    },
  );
}
