import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/domain/models/fronting_analytics.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/features/members/providers/members_batch_provider.dart';
import 'package:prism_plurality/features/settings/widgets/member_ranking_chart.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';

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

Member _member(String id, String name) => Member(
      id: id,
      name: name,
      createdAt: DateTime(2026, 1, 1),
    );

Widget _wrap(
  Widget child, {
  required List<Member> members,
  TextScaler textScaler = TextScaler.noScaling,
  Size surfaceSize = const Size(390, 700),
}) {
  return ProviderScope(
    overrides: [
      membersByIdsProvider.overrideWith((ref, idsKey) {
        return Stream.value({for (final m in members) m.id: m});
      }),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('en'), Locale('es')],
      home: MediaQuery(
        data: MediaQueryData(textScaler: textScaler, size: surfaceSize),
        child: Scaffold(body: child),
      ),
    ),
  );
}

void main() {
  group('MemberRankingChart', () {
    testWidgets('renders nothing when memberStats is empty',
        (tester) async {
      await tester
          .pumpWidget(_wrap(const MemberRankingChart(memberStats: []),
              members: const []));
      expect(find.text('Fronting Time by Member'), findsNothing);
    });

    testWidgets('renders one bar per member with name + total time',
        (tester) async {
      final stats = [
        _stat('a', 600, 60.0),  // 10h
        _stat('b', 300, 30.0),  // 5h
        _stat('c', 60, 10.0),   // 1h
      ];
      await tester.pumpWidget(_wrap(
        MemberRankingChart(memberStats: stats),
        members: [
          _member('a', 'Alice'),
          _member('b', 'Bob'),
          _member('c', 'Cassie'),
        ],
      ));
      await tester.pumpAndSettle();

      expect(find.text('Fronting Time by Member'), findsOneWidget);
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);
      expect(find.text('Cassie'), findsOneWidget);
      // Defaults to total time, not percentage.
      expect(find.text('10h'), findsOneWidget);
      expect(find.text('5h'), findsOneWidget);
      expect(find.text('1h'), findsOneWidget);
      expect(find.text('60%'), findsNothing);
    });

    testWidgets('uses a horizontal ListView so large systems scroll lazily',
        (tester) async {
      final stats = List.generate(
          12, (i) => _stat('m$i', 1000 - i * 50, 100.0 / 12));
      final members =
          List.generate(12, (i) => _member('m$i', 'Member $i'));

      await tester.pumpWidget(_wrap(
        MemberRankingChart(memberStats: stats),
        members: members,
      ));
      await tester.pumpAndSettle();

      final listView = tester.widget<ListView>(find.byType(ListView));
      expect(listView.scrollDirection, Axis.horizontal);
      expect(listView.childrenDelegate, isA<SliverChildBuilderDelegate>());
    });

    testWidgets('slot width adapts to the widest visible member name',
        (tester) async {
      // Slots are chart-level uniform: every slot gets the same width,
      // computed from the widest displayed name. With one short and one
      // long name, that width must be wider than the floor — otherwise
      // the long name would be ellipsized.
      final stats = [
        _stat('a', 600, 60.0),
        _stat('b', 400, 40.0),
      ];
      await tester.pumpWidget(_wrap(
        MemberRankingChart(memberStats: stats),
        members: [
          _member('a', 'Al'),
          _member('b', 'Alexandria the Great'),
        ],
      ));
      await tester.pumpAndSettle();

      final slotA = tester
          .getSize(find.byKey(const ValueKey('member_ranking_slot_a')))
          .width;
      final slotB = tester
          .getSize(find.byKey(const ValueKey('member_ranking_slot_b')))
          .width;
      expect(slotA, slotB,
          reason: 'all slots in one chart render should be the same width');
      expect(slotA, greaterThan(48.0),
          reason:
              'long name should push slot above the 48px floor for short names');
    });

    testWidgets('slot width clamps so one extreme name does not bloat',
        (tester) async {
      final stats = [_stat('a', 600, 100.0)];
      const slotKey = ValueKey('member_ranking_slot_a');
      // Matches MemberRankingChart._maxSlotWidth.
      const maxSlotWidth = 88.0;

      // Pathological 200-character name should not produce a 1000px slot.
      await tester.pumpWidget(_wrap(
        MemberRankingChart(memberStats: stats),
        members: [_member('a', 'A' * 200)],
      ));
      await tester.pumpAndSettle();
      final width = tester.getSize(find.byKey(slotKey)).width;
      expect(width, lessThanOrEqualTo(maxSlotWidth));
    });

    testWidgets('does not overflow under large accessibility text scale',
        (tester) async {
      final stats = [
        _stat('a', 600, 60.0),
        _stat('b', 300, 30.0),
        _stat('c', 100, 10.0),
      ];
      final members = [
        _member('a', 'Alice'),
        _member('b', 'Bob'),
        _member('c', 'Cassandra'),
      ];

      await tester.pumpWidget(_wrap(
        MemberRankingChart(memberStats: stats),
        members: members,
        textScaler: const TextScaler.linear(1.6),
      ));
      await tester.pumpAndSettle();

      // Layout overflows surface as a thrown exception captured by the
      // tester. None means the chart absorbed the larger text correctly.
      expect(tester.takeException(), isNull);
    });

    testWidgets('tapping a bar toggles all bars between total time and %',
        (tester) async {
      final stats = [
        _stat('a', 600, 60.0),  // 10h, 60%
        _stat('b', 300, 30.0),  // 5h,  30%
      ];
      await tester.pumpWidget(_wrap(
        MemberRankingChart(memberStats: stats),
        members: [
          _member('a', 'Alice'),
          _member('b', 'Bob'),
        ],
      ));
      await tester.pumpAndSettle();

      // Default view shows total time.
      expect(find.text('10h'), findsOneWidget);
      expect(find.text('5h'), findsOneWidget);
      expect(find.text('60%'), findsNothing);
      expect(find.text('30%'), findsNothing);

      // Tap one bar — all bars flip together.
      await tester.tap(find.byKey(const ValueKey('member_ranking_slot_a')));
      await tester.pumpAndSettle();

      expect(find.text('10h'), findsNothing);
      expect(find.text('5h'), findsNothing);
      expect(find.text('60%'), findsOneWidget);
      expect(find.text('30%'), findsOneWidget);

      // Tap any bar again — back to time.
      await tester.tap(find.byKey(const ValueKey('member_ranking_slot_b')));
      await tester.pumpAndSettle();

      expect(find.text('10h'), findsOneWidget);
      expect(find.text('5h'), findsOneWidget);
      expect(find.text('60%'), findsNothing);
      expect(find.text('30%'), findsNothing);
    });

    testWidgets('falls back to "..." when member not yet loaded',
        (tester) async {
      final stats = [_stat('missing', 100, 100.0)];
      await tester.pumpWidget(_wrap(
        MemberRankingChart(memberStats: stats),
        members: const [],
      ));
      await tester.pumpAndSettle();

      expect(find.text('...'), findsOneWidget);
    });
  });
}
