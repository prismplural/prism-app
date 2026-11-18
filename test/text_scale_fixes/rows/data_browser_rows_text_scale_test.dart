// The data-browser record rows' subtitle at large text sizes.
//
// `_ExpandableRecord` passes a subtitle of
// `Row([Text(truncatedId, monospace), if secondary: Text(secondary)])` to
// `PrismListRow`. The subtitle sits in a **bounded** column, but that bounds the
// Row, not its children: both `Text`s are non-flex, so each takes its intrinsic
// width and the second one paints past the row (and past the card edge at
// 320dp). The monospace id alone is ~11 characters at fontSize 11, which is
// already wider than the subtitle at 3.375x even when the secondary field is
// empty.
//
// Hermetic pump: `memberRepositoryProvider` is overridden with the repo's
// existing `FakeMemberRepository` seeded with synthetic members, the terminology
// provider is fixed, and `databaseProvider` throws if anything reaches for the
// real database. No network, no real storage.
//
// The subtitle must stay inside its row at 3.375x, where the non-flex id and secondary
// field used to overflow it, and keep its inline geometry wherever both fit.
//
// The screen also renders the five-tab table selector; an overflow inside that control
// fails this test too, so read the failure location before attributing it to the rows.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/database_provider.dart'
    show databaseProvider;
import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/features/settings/views/data_browser_screen.dart';
import 'package:prism_plurality/shared/widgets/prism_list_row.dart';

import '../../helpers/fake_repositories.dart';
import 'rows_text_scale_harness.dart';

const _terminology = (
  term: SystemTerminology.headmates,
  customSingular: null,
  customPlural: null,
  useEnglish: false,
);

/// `_ExpandableRecord` truncates the id to its first eight characters.
const _shortMemberId = 'member-alpha-001';
const _shortMemberTruncatedId = 'member-a...';

/// A long secondary field (pronouns) is legal user data.
const _longPronouns =
    'they them their theirs themself she her hers herself he him his';

/// Counts `getAllMembers` calls so the test can prove the rows came from this fake
/// and not from the (throwing) real repository.
class _CountingMemberRepository extends FakeMemberRepository {
  int getAllMembersCalls = 0;

  @override
  Future<List<Member>> getAllMembers() {
    getAllMembersCalls++;
    return super.getAllMembers();
  }
}

late _CountingMemberRepository _repo;

Widget _dataBrowser({
  required double system,
  required double app,
  String fontFamily = 'Lexend',
  TextScaler? scalerOverride,
}) {
  final repo = _CountingMemberRepository()
    ..seed([
      Member(id: _shortMemberId, name: 'Alice', createdAt: DateTime.utc(2024)),
      Member(
        id: 'member-beta-002',
        name: 'Bob',
        pronouns: _longPronouns,
        createdAt: DateTime.utc(2024, 1, 2),
      ),
    ]);
  _repo = repo;
  return ProviderScope(
    overrides: [
      // No database is opened: the rows come from the counted fake below, and an
      // accidental read through the real repository fails loudly.
      databaseProvider.overrideWith((ref) {
        throw StateError('data browser row tests must not open a database');
      }),
      memberRepositoryProvider.overrideWithValue(repo),
      terminologySettingProvider.overrideWith((ref) => _terminology),
    ],
    child: rowsApp(
      const DataBrowserScreen(),
      system: system,
      app: app,
      fontFamily: fontFamily,
      scalerOverride: scalerOverride,
    ),
  );
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadRowsFonts();
  });

  for (final (system, app, scaleLabel) in rowsScales) {
    for (final fontFamily in rowsFontFamilies) {
      testWidgets('record rows keep their subtitle inside the row - '
          '$scaleLabel / $fontFamily', (tester) async {
        useWindow(tester, tallCompactPage);
        await tester.pumpWidget(
          _dataBrowser(system: system, app: app, fontFamily: fontFamily),
        );
        await pumpUntilFound(
          tester,
          find.text(_shortMemberTruncatedId),
          label: 'record rows',
        );

        expectNoLayoutError(
          tester,
          label: 'data browser $scaleLabel',
          ignoreCauseMatching: fixedHeightBarLayoutErrors,
          ignoreAlso: segmentedControlLayoutErrors,
        );

        // The truncated monospace id is the first subtitle child; it alone can
        // outgrow the subtitle at a large text size.
        // The guarded fake repository really produced these rows.
        expect(
          _repo.getAllMembersCalls,
          greaterThan(0),
          reason: 'the record rows must come from the fake repository',
        );

        final id = find.text(_shortMemberTruncatedId);
        expect(id, findsOneWidget);
        expectPaintedInside(tester, id, label: 'record id ($scaleLabel)');

        final rows = find.byType(PrismListRow);
        expect(rows, findsWidgets);
        for (var i = 0; i < rows.evaluate().length; i++) {
          expectDescendantTextInside(
            tester,
            rows.at(i),
            label: 'record row $i ($scaleLabel)',
          );
        }

        // The long secondary field must not escape the row either.
        final pronouns = find.text(_longPronouns);
        if (pronouns.evaluate().isNotEmpty) {
          expectPaintedInside(
            tester,
            pronouns,
            label: 'record secondary field ($scaleLabel)',
          );
        }
      });
    }
  }

  testWidgets('wide window where the row fits: one line, nothing reflowed ('
      'control)', (tester) async {
    useWindow(tester, wideWindow);
    await tester.pumpWidget(_dataBrowser(system: 2.25, app: 1.5));
    await pumpUntilFound(
      tester,
      find.text(_shortMemberTruncatedId),
      label: 'record rows',
    );

    expectNoLayoutError(
      tester,
      label: 'data browser wide 3.375x',
      ignoreCauseMatching: fixedHeightBarLayoutErrors,
      ignoreAlso: segmentedControlLayoutErrors,
    );
    final id = find.text(_shortMemberTruncatedId);
    expectPaintedInside(tester, id, label: 'record id (wide 3.375x)');
    expectDescendantTextInside(
      tester,
      find.byType(PrismListRow).first,
      label: 'record row (wide 3.375x)',
    );
  });
}
