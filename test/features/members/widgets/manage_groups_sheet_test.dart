import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/domain/models/member_group.dart';
import 'package:prism_plurality/features/members/providers/member_groups_providers.dart';
import 'package:prism_plurality/features/members/widgets/manage_groups_sheet.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/widgets/prism_checkbox_row.dart';
import 'package:prism_plurality/shared/widgets/prism_spinner.dart';

MemberGroup _group(String id) =>
    MemberGroup(id: id, name: id, createdAt: DateTime(2024, 1, 1));

const _kMemberId = 'member-1';

void main() {
  testWidgets(
    'shows loading indicator instead of false-empty checkboxes while '
    'memberGroupsProvider is still loading',
    (tester) async {
      // allGroupsProvider has resolved, but memberGroupsProvider is still
      // loading. Before the fix, the sheet rendered every checkbox as
      // unchecked, falsely implying the member belonged to no groups.
      final memberGroupsCompleter = Completer<List<MemberGroup>>();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            allGroupsProvider.overrideWith(
              (ref) => Stream.value([_group('gender'), _group('age')]),
            ),
            memberGroupsProvider(_kMemberId).overrideWith(
              (ref) => Stream.fromFuture(memberGroupsCompleter.future),
            ),
          ],
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: [Locale('en')],
            home: Scaffold(
              body: SizedBox(
                height: 400,
                child: ManageGroupsSheet(
                  memberId: _kMemberId,
                  memberName: 'Member 1',
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // While membership is still loading, no checkboxes render — instead a
      // loading indicator is shown.
      expect(find.byType(PrismCheckboxRow), findsNothing);
      expect(find.byType(PrismSpinner), findsOneWidget);

      // Once the membership stream emits, the real checked state appears.
      memberGroupsCompleter.complete([_group('gender')]);
      await tester.pumpAndSettle();

      expect(find.byType(PrismSpinner), findsNothing);
      expect(find.byType(PrismCheckboxRow), findsNWidgets(2));

      final genderRow = find.ancestor(
        of: find.text('gender'),
        matching: find.byType(PrismCheckboxRow),
      );
      final ageRow = find.ancestor(
        of: find.text('age'),
        matching: find.byType(PrismCheckboxRow),
      );
      expect(tester.widget<PrismCheckboxRow>(genderRow).value, isTrue);
      expect(tester.widget<PrismCheckboxRow>(ageRow).value, isFalse);
    },
  );
}
