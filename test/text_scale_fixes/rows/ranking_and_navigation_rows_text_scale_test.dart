// The ranking chart's slot bounds and the navigation editor's rows at large text sizes.
//
// Chart: it measures every label with the ambient scaler and then clamped the result to
// a constant 88dp ceiling, so the measurement was discarded above ~1.5x and names were
// ellipsised although the chart's own doc promises "labels never wrap or clip". A
// control keeps the intentional ceiling: an extreme name may not inflate every column.
//
// Navigation editor: a reorderable row holds up to three 44dp actions plus a drag handle
// in a non-flex trailing column (~156dp), and the disabled rows capped their
// "Enable in Features" hint at 104dp with two lines and an ellipsis. The checks are that
// the hint is not ellipsised and that each row action keeps a 44dp target inside the
// window, with the completion/detail callbacks still firing through the real widget.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/router/app_routes.dart';
import 'package:prism_plurality/domain/models/fronting_analytics.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/features/members/providers/members_batch_provider.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/features/settings/widgets/member_ranking_chart.dart';
import 'package:prism_plurality/features/settings/widgets/navigation_layout_editor.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/member_avatar.dart';

import 'rows_text_scale_harness.dart';

const _terminology = (
  term: SystemTerminology.headmates,
  customSingular: null,
  customPlural: null,
  useEnglish: false,
);

const _flags = (
  chat: true,
  polls: true,
  habits: false,
  sleep: true,
  notes: false,
  reminders: true,
  boards: false,
);

MemberAnalytics _stat(String id, int totalMinutes, double pct) =>
    MemberAnalytics(
      memberId: id,
      totalTime: Duration(minutes: totalMinutes),
      percentageOfTotal: pct,
      sessionCount: 1,
      averageDuration: Duration(minutes: totalMinutes),
      medianDuration: Duration(minutes: totalMinutes),
      shortestSession: Duration(minutes: totalMinutes),
      longestSession: Duration(minutes: totalMinutes),
      timeOfDayBreakdown: const {},
    );

Member _member(String id, String name) =>
    Member(id: id, name: name, createdAt: DateTime(2026));

Widget _chart({
  required double system,
  required double app,
  required List<Member> members,
  required List<MemberAnalytics> stats,
  String fontFamily = 'Lexend',
  TextScaler? scalerOverride,
}) {
  return ProviderScope(
    overrides: [
      membersByIdsProvider.overrideWith(
        (ref, idsKey) => Stream.value({for (final m in members) m.id: m}),
      ),
      terminologySettingProvider.overrideWith((ref) => _terminology),
    ],
    child: rowsApp(
      Scaffold(
        body: SingleChildScrollView(
          child: MemberRankingChart(memberStats: stats),
        ),
      ),
      system: system,
      app: app,
      fontFamily: fontFamily,
      scalerOverride: scalerOverride,
    ),
  );
}

List<AppShellTab> _enabledTabs() => [
  for (final tab in appShellTabs)
    if (tab.isEnabled(_flags)) tab,
];

Widget _editor({
  required double system,
  required double app,
  String fontFamily = 'Lexend',
  TextScaler? scalerOverride,
  void Function(List<AppShellTab>, List<AppShellTab>)? onLayoutChanged,
}) {
  final enabled = _enabledTabs();
  return rowsApp(
    Scaffold(
      body: SingleChildScrollView(
        child: NavigationLayoutEditor(
          primaryTabs: enabled.take(4).toList(),
          overflowTabs: enabled.skip(4).toList(),
          flags: _flags,
          terminologyPlural: 'headmates',
          onLayoutChanged: onLayoutChanged ?? (primary, overflow) {},
        ),
      ),
    ),
    system: system,
    app: app,
    fontFamily: fontFamily,
    scalerOverride: scalerOverride,
  );
}

/// Editor harness that keeps the lists it is given back, so a row action can be
/// proven to run its callback through the real widget.
class _EditorHarness extends StatefulWidget {
  const _EditorHarness();

  @override
  State<_EditorHarness> createState() => _EditorHarnessState();
}

class _EditorHarnessState extends State<_EditorHarness> {
  late List<AppShellTab> _primary;
  late List<AppShellTab> _overflow;

  @override
  void initState() {
    super.initState();
    final enabled = _enabledTabs();
    _primary = enabled.take(4).toList();
    _overflow = enabled.skip(4).toList();
  }

  @override
  Widget build(BuildContext context) {
    return NavigationLayoutEditor(
      primaryTabs: _primary,
      overflowTabs: _overflow,
      flags: _flags,
      terminologyPlural: 'headmates',
      onLayoutChanged: (primary, overflow) => setState(() {
        _primary = primary;
        _overflow = overflow;
      }),
    );
  }
}

Finder _slot(String id) => find.byKey(ValueKey('member_ranking_slot_$id'));

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadRowsFonts();
  });

  group('ST3 ranking-chart slot bounds', () {
    testWidgets('default text keeps the 40-88dp slot bounds', (tester) async {
      useWindow(tester, phoneWindow);
      await tester.pumpWidget(
        _chart(
          system: 1,
          app: 1,
          stats: [_stat('a', 600, 60.0), _stat('b', 300, 40.0)],
          members: [_member('a', 'Alice'), _member('b', 'Bob')],
        ),
      );
      await tester.pumpAndSettle();

      expectNoLayoutError(tester, label: 'ranking chart at 1x');
      final slotWidth = tester.getSize(_slot('a')).width;
      expect(slotWidth, greaterThanOrEqualTo(40));
      expect(slotWidth, lessThanOrEqualTo(88));
      expectHonoursSingleLineWidth(
        tester,
        find.text('Alice'),
        label: 'Alice at 1x',
      );
    });

    testWidgets('at 0.5x the slot keeps its floor so the avatar still fits ('
        'control)', (tester) async {
      useWindow(tester, compactPhone);
      await tester.pumpWidget(
        _chart(
          system: 1,
          app: 0.5,
          stats: [_stat('a', 600, 100.0)],
          members: [_member('a', 'Al')],
        ),
      );
      await tester.pumpAndSettle();

      expectNoLayoutError(tester, label: 'ranking chart at 0.5x');

      // The slot bounds do not shrink with the text preference: the avatar inside a
      // slot is a fixed 24dp and needs its breathing room, so a short name still gets
      // the original 40dp floor rather than a 20dp box.
      final slotWidth = tester.getSize(_slot('a')).width;
      expect(slotWidth, greaterThanOrEqualTo(40));
      expect(slotWidth, lessThanOrEqualTo(88));

      // The text itself still honours the 0.5x preference: the chart's slot is at
      // least as wide as the name needs on one line at that requested size.
      expectHonoursSingleLineWidth(
        tester,
        find.text('Al'),
        label: 'name at 0.5x',
      );
      // ...and the avatar is painted inside the slot.
      final avatar = find.descendant(
        of: _slot('a'),
        matching: find.byType(MemberAvatar),
      );
      expect(avatar, findsOneWidget);
      expect(
        tester.getSize(avatar).width,
        lessThanOrEqualTo(slotWidth),
        reason: 'the avatar must fit the slot it is given',
      );
    });

    for (final (system, app, scaleLabel) in [
      (1.5, 1.0, 'large text'),
      (2.25, 1.5, 'system 225% x Prism 150% = 3.375x'),
    ]) {
      // The chart's own contract: the slot is measured from the widest visible name
      // "so labels never wrap or clip", while the intentional ceiling still stops one
      // extreme name from inflating every column. What is checked here is that the
      // measured width is honoured - not a general "no ellipsis" rule for user names.
      testWidgets('the chart honours its measured name width - $scaleLabel', (
        tester,
      ) async {
        useWindow(tester, compactPhone);
        await tester.pumpWidget(
          _chart(
            system: system,
            app: app,
            stats: [_stat('a', 600, 60.0), _stat('b', 300, 40.0)],
            // ~117dp at 1.5x and ~234dp at 3.375x: the chart measures exactly
            // this width for its slot, so a 13-character name is the ordinary
            // case the slot width exists for.
            members: [_member('a', 'Cassandra Joy'), _member('b', 'Bob')],
          ),
        );
        await tester.pumpAndSettle();

        expectNoLayoutError(tester, label: 'ranking chart $scaleLabel');
        final name = find.text('Cassandra Joy');
        expect(name, findsOneWidget);
        expectHonoursSingleLineWidth(
          tester,
          name,
          label: 'Cassandra Joy ($scaleLabel)',
        );
        // The chart lives in the page's scrollable: bring the slot into view before
        // asserting window containment (at max scale the second row is below the fold).
        await tester.ensureVisible(name);
        await tester.pumpAndSettle();
        expectPaintedInside(tester, name, label: 'Cassandra Joy ($scaleLabel)');
      });
    }

    testWidgets('the extreme-name ceiling is kept (control)', (tester) async {
      useWindow(tester, compactPhone);
      final longName = 'A' * 200;
      await tester.pumpWidget(
        _chart(
          system: 2.25,
          app: 1.5,
          stats: [_stat('a', 600, 100.0)],
          members: [_member('a', longName)],
        ),
      );
      await tester.pumpAndSettle();

      expectNoLayoutError(tester, label: 'ranking chart long name');
      // Whatever the bounds become, one 200-character name may not inflate the
      // column without limit; it is still ellipsised rather than allowed to grow.
      expect(tester.getSize(_slot('a')).width, lessThanOrEqualTo(88 * 3.375));
      expect(
        paragraphOf(tester, find.text(longName)).didExceedMaxLines,
        isTrue,
        reason: 'the ceiling must still ellipsise an extreme name',
      );
    });

    testWidgets('tapping a bar still toggles every label (control)', (
      tester,
    ) async {
      useWindow(tester, compactPhone);
      await tester.pumpWidget(
        _chart(
          system: 2.25,
          app: 1.5,
          stats: [_stat('a', 600, 60.0), _stat('b', 300, 40.0)],
          members: [_member('a', 'Alice'), _member('b', 'Bob')],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('10h'), findsOneWidget);
      await tester.tap(_slot('a'));
      await tester.pumpAndSettle();
      expect(find.text('60%'), findsOneWidget);
      expect(find.text('10h'), findsNothing);
      expect(
        tester.widget<ListView>(find.byType(ListView)).scrollDirection,
        Axis.horizontal,
      );
    });

    testWidgets('a non-linear scaler does not break the chart', (tester) async {
      useWindow(tester, compactPhone);
      await tester.pumpWidget(
        _chart(
          system: 1,
          app: 1,
          scalerOverride: const NonlinearTextScaler(),
          stats: [_stat('a', 600, 100.0)],
          members: [_member('a', 'Alexandra')],
        ),
      );
      await tester.pumpAndSettle();

      expectNoLayoutError(tester, label: 'ranking chart nonlinear');
      // labelSmall is 11pt: the nonlinear scaler triples it, so the slot is sized
      // from the measured name and must hold a 9-character one.
      expectHonoursSingleLineWidth(
        tester,
        find.text('Alexandra'),
        label: 'Alexandra (nonlinear)',
      );
    });
  });

  group('ST4 navigation-editor rows', () {
    testWidgets(
      'at the default size the actions stay beside the label (control)',
      (tester) async {
        useWindow(tester, phoneWindow);
        await tester.pumpWidget(_editor(system: 1, app: 1));
        await tester.pumpAndSettle();

        expectNoLayoutError(tester, label: 'navigation editor at 1x');

        final row = find.byKey(const ValueKey(AppShellTabId.chat));
        expect(row, findsOneWidget);
        final label = find.descendant(of: row, matching: find.text('Chat'));
        final action = find.descendant(
          of: row,
          matching: find.byIcon(AppIcons.arrowDownward),
        );
        expect(label, findsOneWidget);
        expect(action, findsOneWidget);
        expectOnTheSameLine(tester, label, action, label: 'label/action at 1x');
        expectStaticLabelFullyPainted(tester, label, label: 'Chat at 1x');
      },
    );

    testWidgets('a row action still runs its callback (control)', (
      tester,
    ) async {
      useWindow(tester, phoneWindow);
      await tester.pumpWidget(
        rowsApp(
          const Scaffold(body: SingleChildScrollView(child: _EditorHarness())),
          system: 1,
          app: 1,
        ),
      );
      await tester.pumpAndSettle();

      expectNoLayoutError(tester, label: 'navigation editor behaviour');
      final row = find.byKey(const ValueKey(AppShellTabId.chat));
      expect(row, findsOneWidget);
      final remove = find.descendant(
        of: row,
        matching: find.byIcon(AppIcons.removeCircleOutline),
      );
      expect(remove, findsOneWidget);
      await tester.tap(remove);
      await tester.pumpAndSettle();

      // The editor hands the new layout back and re-renders without the removed
      // destination.
      expect(find.byKey(const ValueKey(AppShellTabId.chat)), findsNothing);
    });

    for (final (system, app, scaleLabel) in [
      (1.5, 1.0, 'large text'),
      (2.25, 1.5, 'system 225% x Prism 150% = 3.375x'),
    ]) {
      for (final fontFamily in rowsFontFamilies) {
        testWidgets('destination label and actions stay readable and reachable - '
            '$scaleLabel / $fontFamily', (tester) async {
          useWindow(tester, tallCompactPage);
          await tester.pumpWidget(
            _editor(system: system, app: app, fontFamily: fontFamily),
          );
          await tester.pumpAndSettle();

          expectNoLayoutError(tester, label: 'navigation editor $scaleLabel');

          // A guard, not a defect report: at the largest size the label box is still
          // wide enough, so this only catches a future change that shatters a finite,
          // app-authored destination label into one or two characters per line.
          for (final id in [AppShellTabId.chat, AppShellTabId.settings]) {
            final row = find.byKey(ValueKey(id));
            if (row.evaluate().isEmpty) continue;
            final label = find.descendant(
              of: row,
              matching: find.byType(RichText),
            );
            expect(label, findsWidgets, reason: '$id label');
            expectAtMostLines(
              tester,
              label.first,
              maxLines: 2,
              label: '$id destination label ($scaleLabel)',
            );
          }

          // The disabled rows' hint is finite, app-authored text, and a 104dp /
          // two-line box ellipsises it at the largest size in both bundled faces -
          // real clipping of a static label, not a style preference.
          final hint = find.text('Enable in Features');
          expect(hint, findsWidgets);
          for (var i = 0; i < hint.evaluate().length; i++) {
            // The editor sits in the page's scrollable; bring each hint into view before
            // asserting window containment (it is below the fold at max scale).
            await tester.ensureVisible(hint.at(i));
            await tester.pumpAndSettle();
            expectStaticLabelFullyPainted(
              tester,
              hint.at(i),
              label: 'enable hint $i',
            );
            expectPaintedInside(tester, hint.at(i), label: 'enable hint $i');
          }

          // Action semantics: every row action keeps a 44dp target, stays on
          // screen and keeps its accessible label.
          final row = find.byKey(const ValueKey(AppShellTabId.chat));
          final remove = find.descendant(
            of: row,
            matching: find.byIcon(AppIcons.removeCircleOutline),
          );
          expect(remove, findsOneWidget);
          final removeRect = tester.getRect(remove);
          expect(removeRect.width, greaterThanOrEqualTo(44));
          expect(removeRect.height, greaterThanOrEqualTo(44));
          expectPaintedInside(tester, remove, label: 'remove action');
          expect(
            find.byTooltip('Remove from navigation'),
            findsWidgets,
            reason: '$scaleLabel: the action lost its accessible label',
          );
        });
      }
    }

    testWidgets('wide window where it fits: nothing is reflowed (control)', (
      tester,
    ) async {
      useWindow(tester, wideWindow);
      await tester.pumpWidget(_editor(system: 2.25, app: 1.5));
      await tester.pumpAndSettle();

      expectNoLayoutError(tester, label: 'navigation editor wide 3.375x');

      final row = find.byKey(const ValueKey(AppShellTabId.chat));
      final label = find.descendant(of: row, matching: find.text('Chat'));
      final action = find.descendant(
        of: row,
        matching: find.byIcon(AppIcons.arrowDownward),
      );
      expectStaticLabelFullyPainted(tester, label, label: 'Chat (wide 3.375x)');
      // There is room for both, so the label and its actions stay on one line.
      expectOnTheSameLine(
        tester,
        label,
        action,
        label: 'label/action (wide 3.375x)',
      );
    });
  });
}
