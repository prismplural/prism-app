import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/widgets/blur_popup.dart';
import 'package:prism_plurality/shared/widgets/member_search_sheet.dart';
import 'package:prism_plurality/shared/widgets/member_selector_popup.dart';

Member _member(String id, String name) =>
    Member(id: id, name: name, createdAt: DateTime(2026, 5, 8));

Widget _buildSubject({
  required BlurPopupDirection direction,
  required ValueChanged<String> onSelected,
  String? selectedMemberId,
  List<MemberSearchGroup> groups = const [],
}) {
  final members = [_member('alice', 'Alice'), _member('bob', 'Bob')];

  return ProviderScope(
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('en')],
      home: Scaffold(
        body: Align(
          alignment: direction == BlurPopupDirection.up
              ? Alignment.bottomCenter
              : Alignment.topCenter,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: MemberSelectorPopup(
              preferredDirection: direction,
              members: members,
              termPlural: 'members',
              selectedMemberId: selectedMemberId,
              groups: groups,
              onMemberSelected: onSelected,
              child: const Text('Open selector'),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('Search is the first visible option when opening downward', (
    tester,
  ) async {
    await tester.pumpWidget(
      _buildSubject(direction: BlurPopupDirection.down, onSelected: (_) {}),
    );

    await tester.tap(find.text('Open selector'));
    await tester.pumpAndSettle();

    final searchTop = tester.getTopLeft(find.text('Search')).dy;
    final aliceTop = tester.getTopLeft(find.text('Alice')).dy;
    expect(searchTop, lessThan(aliceTop));
  });

  testWidgets('Search is the first visible option when opening upward', (
    tester,
  ) async {
    await tester.pumpWidget(
      _buildSubject(direction: BlurPopupDirection.up, onSelected: (_) {}),
    );

    await tester.tap(find.text('Open selector'));
    await tester.pumpAndSettle();

    final searchTop = tester.getTopLeft(find.text('Search')).dy;
    final aliceTop = tester.getTopLeft(find.text('Alice')).dy;
    expect(searchTop, lessThan(aliceTop));
  });

  testWidgets('member rows select immediately and close the popup', (
    tester,
  ) async {
    String? selectedId;
    await tester.pumpWidget(
      _buildSubject(
        direction: BlurPopupDirection.down,
        selectedMemberId: 'alice',
        onSelected: (id) => selectedId = id,
      ),
    );

    await tester.tap(find.text('Open selector'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bob'));
    await tester.pumpAndSettle();

    expect(selectedId, 'bob');
    expect(find.text('Search'), findsNothing);
  });

  testWidgets('Search row closes the popup and opens member search sheet', (
    tester,
  ) async {
    await tester.pumpWidget(
      _buildSubject(
        direction: BlurPopupDirection.down,
        groups: const [
          MemberSearchGroup(
            id: 'group-1',
            name: 'Front Team',
            memberIds: {'alice'},
          ),
        ],
        onSelected: (_) {},
      ),
    );

    await tester.tap(find.text('Open selector'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();

    expect(find.byType(MemberSearchSheet), findsOneWidget);
    expect(find.text('Front Team'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(MemberSearchSheet),
        matching: find.text('Search'),
      ),
      findsNothing,
      reason: 'the popup should be closed before the sheet is presented',
    );
  });
}
