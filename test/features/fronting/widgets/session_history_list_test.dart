// Widget tests for the period-grouped SessionHistoryList. These exercise
// the §2.3 / §4.6 derived-period rendering: one row per period with avatar
// stacks, day-group headers, brief-visitor chips, and tap navigation.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/features/fronting/providers/derived_periods_provider.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_providers.dart';
import 'package:prism_plurality/features/fronting/services/derive_periods.dart';
import 'package:prism_plurality/features/fronting/widgets/session_history_list.dart';
import 'package:prism_plurality/features/members/providers/members_batch_provider.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';

Member _member(String id, String name) =>
    Member(id: id, name: name, createdAt: DateTime(2026, 1, 1));

FrontingSession _s({
  required String id,
  required String memberId,
  required DateTime start,
  DateTime? end,
}) =>
    FrontingSession(
      id: id,
      memberId: memberId,
      startTime: start,
      endTime: end,
    );

Widget _buildSubject({
  required List<FrontingSession> sessions,
  required List<FrontingPeriod> periods,
  required Map<String, Member> members,
  GoRouter? router,
}) {
  final routerInstance = router ??
      GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const Scaffold(
              body: CustomScrollView(slivers: [SessionHistoryList()]),
            ),
          ),
          GoRoute(
            path: '/session/:id',
            builder: (_, state) =>
                Scaffold(body: Text('session-${state.pathParameters['id']}')),
          ),
        ],
      );

  return ProviderScope(
    overrides: [
      unifiedHistoryProvider.overrideWith((ref) => Stream.value(sessions)),
      derivedPeriodsProvider.overrideWith((ref) => AsyncValue.data(periods)),
      membersByIdsProvider.overrideWith((ref, _) => Stream.value(members)),
    ],
    child: MaterialApp.router(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('en')],
      routerConfig: routerInstance,
    ),
  );
}

void main() {
  group('SessionHistoryList – derived-period rendering', () {
    testWidgets('renders one row per period with avatar stack',
        (tester) async {
      final t0 = DateTime(2026, 4, 1, 10);
      final t1 = DateTime(2026, 4, 1, 11);
      final t2 = DateTime(2026, 4, 1, 12);
      final t3 = DateTime(2026, 4, 1, 13);

      final periods = [
        FrontingPeriod(
          start: t0,
          end: t1,
          activeMembers: const ['a'],
          briefVisitors: const [],
          sessionIds: const ['s-a'],
          alwaysPresentMembers: const [],
          isOpenEnded: false,
        ),
        FrontingPeriod(
          start: t1,
          end: t2,
          activeMembers: const ['a', 'b'],
          briefVisitors: const [],
          sessionIds: const ['s-a', 's-b'],
          alwaysPresentMembers: const [],
          isOpenEnded: false,
        ),
        FrontingPeriod(
          start: t2,
          end: t3,
          activeMembers: const ['a'],
          briefVisitors: const [],
          sessionIds: const ['s-a'],
          alwaysPresentMembers: const [],
          isOpenEnded: false,
        ),
      ];

      await tester.pumpWidget(_buildSubject(
        sessions: [
          _s(id: 's-a', memberId: 'a', start: t0, end: t3),
          _s(id: 's-b', memberId: 'b', start: t1, end: t2),
        ],
        periods: periods,
        members: {
          'a': _member('a', 'Alice'),
          'b': _member('b', 'Bob'),
        },
      ));
      await tester.pumpAndSettle();

      // Three rows: "Alice", "Alice & Bob", "Alice".
      expect(find.text('Alice'), findsNWidgets(2));
      expect(find.text('Alice & Bob'), findsOneWidget);
    });

    testWidgets('renders day group header for the period\'s day',
        (tester) async {
      final t0 = DateTime(2026, 4, 1, 10);
      final t1 = DateTime(2026, 4, 1, 11);

      final periods = [
        FrontingPeriod(
          start: t0,
          end: t1,
          activeMembers: const ['a'],
          briefVisitors: const [],
          sessionIds: const ['s-a'],
          alwaysPresentMembers: const [],
          isOpenEnded: false,
        ),
      ];

      await tester.pumpWidget(_buildSubject(
        sessions: [_s(id: 's-a', memberId: 'a', start: t0, end: t1)],
        periods: periods,
        members: {'a': _member('a', 'Alice')},
      ));
      await tester.pumpAndSettle();

      // The DateChip renders the formatted day; "April" should appear in
      // the rendered en-locale date.
      expect(find.textContaining('April'), findsOneWidget);
    });

    testWidgets('brief visitors render as trailing chips',
        (tester) async {
      final t0 = DateTime(2026, 4, 1, 10);
      final t1 = DateTime(2026, 4, 1, 12);

      final periods = [
        FrontingPeriod(
          start: t0,
          end: t1,
          activeMembers: const ['a'],
          briefVisitors: [
            EphemeralVisit(
              memberId: 'b',
              start: DateTime(2026, 4, 1, 11),
              end: DateTime(2026, 4, 1, 11, 0, 30),
              sessionId: 's-b',
            ),
          ],
          sessionIds: const ['s-a', 's-b'],
          alwaysPresentMembers: const [],
          isOpenEnded: false,
        ),
      ];

      await tester.pumpWidget(_buildSubject(
        sessions: [
          _s(id: 's-a', memberId: 'a', start: t0, end: t1),
          _s(
            id: 's-b',
            memberId: 'b',
            start: DateTime(2026, 4, 1, 11),
            end: DateTime(2026, 4, 1, 11, 0, 30),
          ),
        ],
        periods: periods,
        members: {
          'a': _member('a', 'Alice'),
          'b': _member('b', 'Bob'),
        },
      ));
      await tester.pumpAndSettle();

      expect(find.text('+Bob briefly'), findsOneWidget);
    });

    testWidgets(
      'always-present members surface as a separate line, not in stack',
      (tester) async {
        final t0 = DateTime(2026, 4, 1, 14);
        final t1 = DateTime(2026, 4, 1, 16);

        final periods = [
          FrontingPeriod(
            start: t0,
            end: t1,
            activeMembers: const ['v'],
            briefVisitors: const [],
            sessionIds: const ['s-v'],
            alwaysPresentMembers: const ['host'],
            isOpenEnded: false,
          ),
        ];

        await tester.pumpWidget(_buildSubject(
          sessions: [_s(id: 's-v', memberId: 'v', start: t0, end: t1)],
          periods: periods,
          members: {
            'v': _member('v', 'Visitor'),
            'host': Member(
              id: 'host',
              name: 'Host',
              createdAt: DateTime(2025, 1, 1),
              isAlwaysFronting: true,
            ),
          },
        ));
        await tester.pumpAndSettle();

        // Title shows only the foreground member.
        expect(find.text('Visitor'), findsOneWidget);
        // Always-present line surfaces the host separately.
        expect(find.textContaining('Always-present'), findsOneWidget);
        expect(find.textContaining('Host'), findsOneWidget);
      },
    );

    testWidgets('tapping a row navigates to the first session id',
        (tester) async {
      final t0 = DateTime(2026, 4, 1, 10);
      final t1 = DateTime(2026, 4, 1, 12);

      final periods = [
        FrontingPeriod(
          start: t0,
          end: t1,
          activeMembers: const ['a'],
          briefVisitors: const [],
          sessionIds: const ['s-a'],
          alwaysPresentMembers: const [],
          isOpenEnded: false,
        ),
      ];

      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const Scaffold(
              body: CustomScrollView(slivers: [SessionHistoryList()]),
            ),
          ),
          GoRoute(
            path: '/session/:id',
            builder: (_, state) => Scaffold(
              body: Text('session-${state.pathParameters['id']}'),
            ),
          ),
        ],
      );

      await tester.pumpWidget(_buildSubject(
        sessions: [_s(id: 's-a', memberId: 'a', start: t0, end: t1)],
        periods: periods,
        members: {'a': _member('a', 'Alice')},
        router: router,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Alice'));
      await tester.pumpAndSettle();

      expect(find.text('session-s-a'), findsOneWidget);
    });

    testWidgets('empty periods + empty sessions renders the empty state',
        (tester) async {
      await tester.pumpWidget(_buildSubject(
        sessions: const [],
        periods: const [],
        members: const {},
      ));
      await tester.pumpAndSettle();

      // The empty-state copy comes from l10n; assert presence of the icon
      // by widget type is enough for this smoke check.
      expect(find.byType(Icon), findsWidgets);
    });
  });
}
