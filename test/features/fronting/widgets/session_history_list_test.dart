// Widget tests for the period-grouped SessionHistoryList. These exercise
// the §2.3 / §4.6 derived-period rendering: one row per period with avatar
// stacks, day-group headers, brief-visitor chips, and tap navigation.

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:prism_plurality/core/database/app_database.dart'
    hide FrontingSession, Member;
import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/data/mappers/fronting_session_mapper.dart';
import 'package:prism_plurality/data/repositories/drift_fronting_session_repository.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/repositories/fronting_session_repository.dart';
import 'package:prism_plurality/features/fronting/providers/derived_periods_provider.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_providers.dart';
import 'package:prism_plurality/features/fronting/services/derive_periods.dart';
import 'package:prism_plurality/features/fronting/widgets/session_history_list.dart';
import 'package:prism_plurality/features/members/providers/members_batch_provider.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
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

    testWidgets(
      'brief visitor before midnight does NOT duplicate on continuation day',
      (tester) async {
        // Codex test gap #7: a period crossing midnight with a brief
        // visitor whose visit is entirely on day 1 must not render the
        // chip on day 2's continuation row. The slice-aware filtering
        // in DisplayPeriod.briefVisitors is what enforces this.
        final dayOneStart = DateTime(2026, 4, 1, 22); // 10 PM
        final dayTwoEnd = DateTime(2026, 4, 2, 2); // 2 AM next day

        final periods = [
          FrontingPeriod(
            start: dayOneStart,
            end: dayTwoEnd,
            activeMembers: const ['a'],
            briefVisitors: [
              EphemeralVisit(
                memberId: 'b',
                // Visit happens entirely BEFORE midnight (day 1).
                start: DateTime(2026, 4, 1, 22, 30),
                end: DateTime(2026, 4, 1, 22, 31),
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
            _s(id: 's-a', memberId: 'a', start: dayOneStart, end: dayTwoEnd),
          ],
          periods: periods,
          members: {
            'a': _member('a', 'Alice'),
            'b': _member('b', 'Bob'),
          },
        ));
        await tester.pumpAndSettle();

        // The visitor's chip should appear EXACTLY once — on the day
        // the visit happened, not duplicated on the continuation row.
        expect(find.text('+Bob briefly'), findsOneWidget);
      },
    );

    testWidgets(
      'tapping a co-front middle period navigates to a contributing session',
      (tester) async {
        // Codex test gap #8: in `A → A+B → A`, the middle period's
        // sessionIds must include both contributors so a tap routes
        // to a real co-front session, not to a "boundary event"
        // session that doesn't span the middle.
        final t0 = DateTime(2026, 4, 1, 10);
        final t1 = DateTime(2026, 4, 1, 11);
        final t2 = DateTime(2026, 4, 1, 12);
        final t3 = DateTime(2026, 4, 1, 13);

        final middle = FrontingPeriod(
          start: t1,
          end: t2,
          activeMembers: const ['a', 'b'],
          briefVisitors: const [],
          // Both contributors. The DAO/algorithm guarantees this; the
          // widget test pins the navigation contract that depends on it.
          sessionIds: const ['session-a', 'session-b'],
          alwaysPresentMembers: const [],
          isOpenEnded: false,
        );

        final periods = [
          FrontingPeriod(
            start: t0,
            end: t1,
            activeMembers: const ['a'],
            briefVisitors: const [],
            sessionIds: const ['session-a'],
            alwaysPresentMembers: const [],
            isOpenEnded: false,
          ),
          middle,
          FrontingPeriod(
            start: t2,
            end: t3,
            activeMembers: const ['a'],
            briefVisitors: const [],
            sessionIds: const ['session-a'],
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
          sessions: [
            _s(id: 'session-a', memberId: 'a', start: t0, end: t3),
            _s(id: 'session-b', memberId: 'b', start: t1, end: t2),
          ],
          periods: periods,
          members: {
            'a': _member('a', 'Alice'),
            'b': _member('b', 'Bob'),
          },
          router: router,
        ));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Alice & Bob'));
        await tester.pumpAndSettle();

        // The route opens on a session ID drawn from the middle period's
        // sessionIds. The widget routes to the first id (current 1A
        // behavior). What matters: it's one of the period's real
        // contributors, NOT a stray ID.
        final routedToA =
            find.text('session-session-a').evaluate().isNotEmpty;
        final routedToB =
            find.text('session-session-b').evaluate().isNotEmpty;
        expect(routedToA || routedToB, isTrue,
            reason: 'tap on middle co-front period must route to a '
                'contributing session');
      },
    );

    testWidgets(
      'tap routing through actual provider chain (real Drift) lands on '
      'a contributing session for a co-front period',
      (tester) async {
        // Codex test gap #7: instead of overriding `derivedPeriodsProvider`
        // with hand-built periods, drive the render through the real
        // `unifiedHistoryOverlapProvider` → `derivedPeriodsProvider`
        // chain backed by an in-memory Drift DB. Tap a co-front middle
        // period and assert the route opens a real contributing
        // session id.
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);

        final repo = DriftFrontingSessionRepository(
          db.frontingSessionsDao,
          null,
        );

        // A → A+B → A pattern, recent enough to fall inside the 90-day
        // lookback window.
        final t0 = DateTime.now().subtract(const Duration(hours: 4));
        final t1 = DateTime.now().subtract(const Duration(hours: 3));
        final t2 = DateTime.now().subtract(const Duration(hours: 2));
        final t3 = DateTime.now().subtract(const Duration(hours: 1));

        await db.frontingSessionsDao.insertSession(
          FrontingSessionMapper.toCompanion(
            FrontingSession(
              id: 'session-a',
              memberId: 'a',
              startTime: t0,
              endTime: t3,
            ),
          ),
        );
        await db.frontingSessionsDao.insertSession(
          FrontingSessionMapper.toCompanion(
            FrontingSession(
              id: 'session-b',
              memberId: 'b',
              startTime: t1,
              endTime: t2,
            ),
          ),
        );

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
                body: Text('routed-${state.pathParameters['id']}'),
              ),
            ),
          ],
        );

        final widget = ProviderScope(
          overrides: [
            // Real repository → exercises the real overlap query and
            // the real derivation through the provider chain.
            frontingSessionRepositoryProvider
                .overrideWith((ref) => repo as FrontingSessionRepository),
            // Members are looked up by the widget for avatars/names —
            // we override these two streams (not the repository) so we
            // don't have to wire the full member repo.
            allMembersProvider.overrideWith((ref) => Stream.value([
                  Member(
                    id: 'a',
                    name: 'Alice',
                    createdAt: DateTime(2026, 1, 1),
                  ),
                  Member(
                    id: 'b',
                    name: 'Bob',
                    createdAt: DateTime(2026, 1, 1),
                  ),
                ])),
            membersByIdsProvider.overrideWith(
              (ref, _) => Stream.value({
                'a': Member(
                  id: 'a',
                  name: 'Alice',
                  createdAt: DateTime(2026, 1, 1),
                ),
                'b': Member(
                  id: 'b',
                  name: 'Bob',
                  createdAt: DateTime(2026, 1, 1),
                ),
              }),
            ),
          ],
          child: MaterialApp.router(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: const [Locale('en')],
            routerConfig: router,
          ),
        );

        await tester.pumpWidget(widget);
        // Pump enough times for the overlap stream + derivation to settle.
        await tester.pumpAndSettle(const Duration(seconds: 1));

        // Tap the co-front row. The middle period's sessionIds must
        // include both contributors (the algorithm guarantees this);
        // the route opens on whichever id the widget surfaces first.
        final cofront = find.text('Alice & Bob');
        expect(cofront, findsOneWidget,
            reason:
                'real Drift chain must produce a co-front period for A → A+B → A');
        await tester.tap(cofront);
        await tester.pumpAndSettle();

        final routedToA = find.text('routed-session-a').evaluate().isNotEmpty;
        final routedToB = find.text('routed-session-b').evaluate().isNotEmpty;
        expect(routedToA || routedToB, isTrue,
            reason:
                'tap on co-front period must route to a real contributing '
                'session id (not a boundary event)');
      },
    );
  });
}
