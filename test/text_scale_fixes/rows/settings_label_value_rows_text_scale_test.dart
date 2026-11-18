// Label/value rows on the statistics and database-diagnostics screens, and the
// statistics top-fronters row, at large text sizes. The shared rows are
// `Row(spaceBetween, [Text(label), Text(value)])` with neither side flexible, so both
// keep an intrinsic width and the pair runs past the card; the top-fronters row also put
// the rank numeral in a constant 24dp box and let an un-flexed session count squeeze the
// name away. Each case asserts painted geometry: nothing may leave its card, a rank
// numeral stays on one line, a count stays inside the window, and content that fits stays
// on one line.
//
// These are written as desired-behaviour expectations, not as a description of
// any particular fix. Each assertion names a defect that is visible through the
// real screens:
//
//  * a `RenderFlex` overflow (layout error), or
//  * a paragraph painting outside the card that must contain it (a non-flex
//    `Row` child keeps its intrinsic width and leaves the box), or
//  * a paragraph whose box is too narrow to hold its own widest word, or whose
//    text had to be ellipsised although it is an ordinary short label.
//
// Expected on the restored prior delivery (source before any fix):
//   * 3.375x compact - RED: the statistics, diagnostics and top-fronter rows
//     overflow by tens of dp, the count paints past the card, "#1" is clipped by
//     its fixed 24dp box and the name column collapses.
//   * 1.5x - RED for the rank numeral only ("#1" needs ~34dp in a 24dp box).
//   * 0.5x / 1x - GREEN: everything fits; these are controls.
//   * 3.375x on a 1024dp window - GREEN: content fits, so nothing may be
//     reflowed; also a control against a fix that stacks on font size alone.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/database_provider.dart'
    show databaseProvider;
import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/core/services/database_health_providers.dart';
import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/features/settings/providers/database_diagnostics_providers.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/features/settings/providers/statistics_providers.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/features/settings/views/database_diagnostics_screen.dart';
import 'package:prism_plurality/features/settings/views/statistics_screen.dart';
import 'package:prism_plurality/shared/widgets/prism_section_card.dart';
import 'package:prism_plurality/shared/widgets/prism_spinner.dart';

import '../../helpers/fake_repositories.dart';
import 'rows_text_scale_harness.dart';

final _alice = Member(id: 'm1', name: 'Alice', createdAt: DateTime.utc(2024));
final _bob = Member(id: 'm2', name: 'Bob', createdAt: DateTime.utc(2024, 1, 2));

const _terminology = (
  term: SystemTerminology.headmates,
  customSingular: null,
  customPlural: null,
  useEnglish: false,
);

Widget _statisticsScreen({
  required double system,
  required double app,
  String fontFamily = 'Lexend',
  TextScaler? scalerOverride,
  Locale locale = const Locale('en'),
  TextDirection? textDirection,
  List<MapEntry<Member, int>> topFronters = const [],
}) {
  final appPrefs = FakeAppPreferenceRepository();
  addTearDown(appPrefs.close);
  return ProviderScope(
    overrides: [
      // No database is opened by this fixture: every statistic is overridden below,
      // and an accidental read through the real provider fails loudly.
      databaseProvider.overrideWith((ref) {
        throw StateError('statistics row tests must not open a database');
      }),
      appPreferenceRepositoryProvider.overrideWithValue(appPrefs),
      systemSettingsProvider.overrideWith(
        (ref) => Stream.value(const SystemSettings()),
      ),
      terminologySettingProvider.overrideWith((ref) => _terminology),
      memberCountStatProvider.overrideWith((ref) async => 2),
      allMembersStatProvider.overrideWith((ref) async => [_alice, _bob]),
      sessionCountStatProvider.overrideWith((ref) async => 3),
      allSessionsStatProvider.overrideWith((ref) async => const []),
      allConversationsCountProvider.overrideWith((ref) async => 1),
      allPollsCountProvider.overrideWith((ref) async => 0),
      topFrontersProvider.overrideWith((ref) async => topFronters),
    ],
    child: rowsApp(
      const StatisticsScreen(),
      system: system,
      app: app,
      fontFamily: fontFamily,
      scalerOverride: scalerOverride,
      locale: locale,
      textDirection: textDirection,
    ),
  );
}

Widget _diagnosticsScreen({
  required double system,
  required double app,
  String fontFamily = 'Lexend',
  TextScaler? scalerOverride,
}) {
  final appPrefs = FakeAppPreferenceRepository();
  addTearDown(appPrefs.close);
  return ProviderScope(
    overrides: [
      // Every diagnostics provider is overridden below; the database stays closed.
      databaseProvider.overrideWith((ref) {
        throw StateError('diagnostics row tests must not open a database');
      }),
      appPreferenceRepositoryProvider.overrideWithValue(appPrefs),
      systemSettingsProvider.overrideWith(
        (ref) => Stream.value(const SystemSettings()),
      ),
      terminologySettingProvider.overrideWith((ref) => _terminology),
      nodeIdProvider.overrideWith((ref) async => 'node-1'),
      crdtLatestHlcProvider.overrideWith((ref) async => null),
      dbPathProvider.overrideWith((ref) async => '/tmp/prism.db'),
      memberCountProvider.overrideWith((ref) async => 2),
      sessionCountProvider.overrideWith((ref) async => 3),
      conversationCountProvider.overrideWith((ref) async => 4),
      pollCountProvider.overrideWith((ref) async => 5),
      healthReportProvider.overrideWith(
        (ref) => throw UnimplementedError('health check not opened'),
      ),
    ],
    child: rowsApp(
      const DatabaseDiagnosticsScreen(),
      system: system,
      app: app,
      fontFamily: fontFamily,
      scalerOverride: scalerOverride,
    ),
  );
}

/// The section card that holds [text]; sections are `PrismSectionCard`s.
Finder _cardContaining(String text) => find
    .ancestor(of: find.text(text), matching: find.byType(PrismSectionCard))
    .first;

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadRowsFonts();
  });

  group('S7 statistics label/value rows', () {
    for (final (system, app, scaleLabel) in rowsScales) {
      for (final fontFamily in rowsFontFamilies) {
        testWidgets(
          'label and count stay inside their card - $scaleLabel / $fontFamily',
          (tester) async {
            useWindow(tester, tallCompactPage);
            await tester.pumpWidget(
              _statisticsScreen(
                system: system,
                app: app,
                fontFamily: fontFamily,
              ),
            );
            await pumpUntilFound(
              tester,
              find.text('Total sessions'),
              label: 'the overview labels',
            );
            await pumpUntilGone(
              tester,
              find.byType(PrismSpinner),
              label: 'statistics loading',
            );

            expectNoLayoutError(
              tester,
              label: 'statistics $scaleLabel',
              ignoreCauseMatching: fixedHeightBarLayoutErrors,
            );

            // Every label of the overview card, and the card itself, must keep
            // the label/value pair inside the card.
            for (final label in ['Total sessions', 'Conversations', 'Polls']) {
              final finder = find.text(label);
              expect(finder, findsOneWidget, reason: label);
              expectStaticLabelFullyPainted(
                tester,
                finder,
                label: '$label $scaleLabel',
              );
              expectDescendantTextInside(
                tester,
                _cardContaining(label),
                label: 'overview card ($scaleLabel)',
              );
            }

            // Where the pair demonstrably fits, it must stay on one line rather
            // than being reflowed for its own sake.
            if (system * app <= 1.5) {
              expectOnTheSameLine(
                tester,
                find.text('Total sessions'),
                find.text('3'),
                label: 'label/value pair ($scaleLabel)',
              );
            }
          },
        );
      }
    }

    testWidgets('a non-linear scaler does not break the rows', (tester) async {
      useWindow(tester, tallCompactPage);
      await tester.pumpWidget(
        _statisticsScreen(
          system: 1,
          app: 1,
          scalerOverride: const NonlinearTextScaler(),
        ),
      );
      await pumpUntilFound(
        tester,
        find.text('Total sessions'),
        label: 'the Total sessions',
      );
      await pumpUntilGone(
        tester,
        find.byType(PrismSpinner),
        label: 'statistics loading',
      );

      expectNoLayoutError(
        tester,
        label: 'statistics nonlinear',
        ignoreCauseMatching: fixedHeightBarLayoutErrors,
      );
      expectDescendantTextInside(
        tester,
        _cardContaining('Total sessions'),
        label: 'overview card (nonlinear)',
      );
    });
  });

  group('ST2 statistics top fronters', () {
    final topFronters = [MapEntry(_alice, 12), MapEntry(_bob, 7)];

    for (final (system, app, scaleLabel) in rowsScales) {
      testWidgets('rank numeral, name and count keep their size - $scaleLabel', (
        tester,
      ) async {
        useWindow(tester, tallCompactPage);
        await tester.pumpWidget(
          _statisticsScreen(system: system, app: app, topFronters: topFronters),
        );
        await pumpUntilFound(tester, find.text('#1'), label: 'the #1');
        await pumpUntilGone(
          tester,
          find.byType(PrismSpinner),
          label: 'statistics loading',
        );

        expectNoLayoutError(
          tester,
          label: 'top fronters $scaleLabel',
          ignoreCauseMatching: fixedHeightBarLayoutErrors,
        );

        // The rank gutter is a single-line field: "#1" is finite, app-authored
        // text and is not allowed to be broken across lines by its 24dp box.
        final rank = find.text('#1');
        expect(rank, findsOneWidget);
        expectAtMostLines(
          tester,
          rank,
          maxLines: 1,
          label: 'rank numeral ($scaleLabel)',
        );
        expectPaintedInside(tester, rank, label: 'rank numeral ($scaleLabel)');

        // The session count keeps its own size and stays on the card.
        final count = find.text('12 sessions');
        expect(count, findsOneWidget);
        expectStaticLabelFullyPainted(
          tester,
          count,
          label: 'count ($scaleLabel)',
        );
        expectPaintedInside(tester, count, label: 'count ($scaleLabel)');

        // The member name is content: it may ellipsise or wrap (accepted), so it
        // is only required to stay painted inside the window.
        final name = find.text('Alice');
        expect(name, findsOneWidget);
        expectPaintedInside(tester, name, label: 'name ($scaleLabel)');

        if (system * app <= 1.5) {
          expectOnTheSameLine(
            tester,
            name,
            count,
            label: 'name/count ($scaleLabel)',
          );
        }
      });
    }
  });

  group('S7 database diagnostics label/value rows', () {
    for (final (system, app, scaleLabel) in rowsScales) {
      testWidgets('label and count stay inside their card - $scaleLabel', (
        tester,
      ) async {
        useWindow(tester, tallCompactPage);
        await tester.pumpWidget(_diagnosticsScreen(system: system, app: app));
        await pumpUntilFound(
          tester,
          find.text('Fronting Sessions'),
          label: 'the Fronting Sessions',
        );
        await pumpUntilGone(
          tester,
          find.byType(PrismSpinner),
          label: 'diagnostics loading',
        );

        expectNoLayoutError(
          tester,
          label: 'diagnostics $scaleLabel',
          ignoreCauseMatching: fixedHeightBarLayoutErrors,
        );

        // Literal row labels only: the first row's label is the terminology plural,
        // which depends on the settings fixture, so it is not asserted by string.
        for (final label in ['Fronting Sessions', 'Conversations', 'Polls']) {
          final finder = find.text(label);
          expect(finder, findsOneWidget, reason: label);
          expectStaticLabelFullyPainted(
            tester,
            finder,
            label: '$label $scaleLabel',
          );
          expectDescendantTextInside(
            tester,
            _cardContaining(label),
            label: 'record counts card ($scaleLabel)',
          );
        }
      });
    }
  });

  group('S7 longer localized labels and RTL', () {
    testWidgets('Spanish labels keep the pair inside the card at 3.375x', (
      tester,
    ) async {
      useWindow(tester, tallCompactPage);
      await tester.pumpWidget(
        _statisticsScreen(system: 2.25, app: 1.5, locale: const Locale('es')),
      );
      // Locale-independent readiness: the Spanish labels are not the English ones,
      // so wait for the cards to build and the loading indicator to clear.
      await pumpUntilFound(
        tester,
        find.byType(PrismSectionCard),
        label: 'the overview cards',
      );
      await pumpUntilGone(
        tester,
        find.byType(PrismSpinner),
        label: 'statistics loading',
      );

      expectNoLayoutError(
        tester,
        label: 'statistics es 3.375x',
        ignoreCauseMatching: fixedHeightBarLayoutErrors,
      );
      // Spanish labels are longer than the English ones these rows were sized
      // for; whichever row is on the overview card, its text stays inside it.
      final cards = find.byType(PrismSectionCard);
      expect(cards, findsWidgets);
      for (var i = 0; i < cards.evaluate().length; i++) {
        expectDescendantTextInside(
          tester,
          cards.at(i),
          label: 'es card $i (3.375x)',
        );
      }
    });

    testWidgets('RTL keeps the pair inside the card at 3.375x', (tester) async {
      useWindow(tester, tallCompactPage);
      await tester.pumpWidget(
        _statisticsScreen(
          system: 2.25,
          app: 1.5,
          textDirection: TextDirection.rtl,
        ),
      );
      // Locale-independent readiness: the Spanish labels are not the English ones,
      // so wait for the cards to build and the loading indicator to clear.
      await pumpUntilFound(
        tester,
        find.byType(PrismSectionCard),
        label: 'the overview cards',
      );
      await pumpUntilGone(
        tester,
        find.byType(PrismSpinner),
        label: 'statistics loading',
      );

      expectNoLayoutError(
        tester,
        label: 'statistics rtl 3.375x',
        ignoreCauseMatching: fixedHeightBarLayoutErrors,
      );
      expectDescendantTextInside(
        tester,
        _cardContaining('Total sessions'),
        label: 'overview card (rtl 3.375x)',
      );
    });
  });

  group('S7 wide window where the content fits', () {
    testWidgets('nothing is clipped and nothing is reflowed at 3.375x', (
      tester,
    ) async {
      useWindow(tester, const Size(1024, 2400));
      await tester.pumpWidget(
        _statisticsScreen(
          system: 2.25,
          app: 1.5,
          topFronters: [MapEntry(_alice, 12)],
        ),
      );
      await pumpUntilFound(
        tester,
        find.text('12 sessions'),
        label: 'the top-fronter count',
      );
      await pumpUntilGone(
        tester,
        find.byType(PrismSpinner),
        label: 'statistics loading',
      );

      expectNoLayoutError(
        tester,
        label: 'statistics wide 3.375x',
        ignoreCauseMatching: fixedHeightBarLayoutErrors,
      );
      // Section label text is finite and app-authored; the count keeps its size.
      for (final text in ['Total sessions', '12 sessions']) {
        expectStaticLabelFullyPainted(
          tester,
          find.text(text),
          label: '$text (wide)',
        );
      }
      // Names and numbers only have to stay painted inside the window.
      for (final text in ['#1', 'Alice']) {
        expectPaintedInside(tester, find.text(text), label: '$text (wide)');
      }
      // There is room for the pair on one line here, so a fix must not push it
      // apart just because the font is large.
      expectOnTheSameLine(
        tester,
        find.text('Total sessions'),
        find.text('3'),
        label: 'label/value pair (wide 3.375x)',
      );
      expectOnTheSameLine(
        tester,
        find.text('Alice'),
        find.text('12 sessions'),
        label: 'name/count (wide 3.375x)',
      );
    });
  });
}
