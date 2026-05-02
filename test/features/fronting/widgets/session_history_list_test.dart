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
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/features/fronting/providers/always_present_members_provider.dart';
import 'package:prism_plurality/features/fronting/services/derive_periods.dart';
import 'package:prism_plurality/features/fronting/utils/period_day_grouping.dart';
import 'package:prism_plurality/features/fronting/widgets/session_history_list.dart';
import 'package:prism_plurality/features/fronting/widgets/timeline_view.dart';
import 'package:prism_plurality/features/members/providers/members_batch_provider.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';

Member _member(String id, String name) =>
    Member(id: id, name: name, createdAt: DateTime(2026, 1, 1));

FrontingSession _s({
  required String id,
  required String memberId,
  required DateTime start,
  DateTime? end,
}) =>
    FrontingSession(id: id, memberId: memberId, startTime: start, endTime: end);

Widget _buildSubject({
  required List<FrontingSession> sessions,
  required List<FrontingPeriod> periods,
  required Map<String, Member> members,
  GoRouter? router,
}) {
  final routerInstance =
      router ??
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
      // 1B: SessionHistoryList now reads `systemSettingsProvider` to
      // pick the inline view mode. Default to the post-1A
      // `combinedPeriods` mode so the existing tests continue to
      // exercise the derived-period rendering path.
      systemSettingsProvider.overrideWith(
        (ref) => Stream.value(const SystemSettings()),
      ),
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
    testWidgets('renders one row per period with avatar stack', (tester) async {
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

      await tester.pumpWidget(
        _buildSubject(
          sessions: [
            _s(id: 's-a', memberId: 'a', start: t0, end: t3),
            _s(id: 's-b', memberId: 'b', start: t1, end: t2),
          ],
          periods: periods,
          members: {'a': _member('a', 'Alice'), 'b': _member('b', 'Bob')},
        ),
      );
      await tester.pumpAndSettle();

      // Three rows: "Alice", "Alice & Bob", "Alice".
      expect(find.text('Alice'), findsNWidgets(2));
      expect(find.text('Alice & Bob'), findsOneWidget);
    });

    testWidgets('renders day group header for the period\'s day', (
      tester,
    ) async {
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

      await tester.pumpWidget(
        _buildSubject(
          sessions: [_s(id: 's-a', memberId: 'a', start: t0, end: t1)],
          periods: periods,
          members: {'a': _member('a', 'Alice')},
        ),
      );
      await tester.pumpAndSettle();

      // The DateChip renders the formatted day; "April" should appear in
      // the rendered en-locale date.
      expect(find.textContaining('April'), findsOneWidget);
    });

    testWidgets('brief visitors render as trailing chips', (tester) async {
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

      await tester.pumpWidget(
        _buildSubject(
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
          members: {'a': _member('a', 'Alice'), 'b': _member('b', 'Bob')},
        ),
      );
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

        await tester.pumpWidget(
          _buildSubject(
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
          ),
        );
        await tester.pumpAndSettle();

        // Title shows only the foreground member.
        expect(find.text('Visitor'), findsOneWidget);
        // Always-present line surfaces the host separately.
        expect(find.textContaining('Always-present'), findsOneWidget);
        expect(find.textContaining('Host'), findsOneWidget);
      },
    );

    testWidgets('tapping a row navigates to the first session id', (
      tester,
    ) async {
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
            builder: (_, state) =>
                Scaffold(body: Text('session-${state.pathParameters['id']}')),
          ),
        ],
      );

      await tester.pumpWidget(
        _buildSubject(
          sessions: [_s(id: 's-a', memberId: 'a', start: t0, end: t1)],
          periods: periods,
          members: {'a': _member('a', 'Alice')},
          router: router,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Alice'));
      await tester.pumpAndSettle();

      expect(find.text('session-s-a'), findsOneWidget);
    });

    testWidgets('empty periods + empty sessions renders the empty state', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildSubject(sessions: const [], periods: const [], members: const {}),
      );
      await tester.pumpAndSettle();

      // The empty-state copy comes from l10n; assert presence of the icon
      // by widget type is enough for this smoke check.
      expect(find.byType(Icon), findsWidgets);
    });

    testWidgets(
      'brief visitor before midnight does NOT duplicate on continuation day',
      (tester) async {
        // Regression: a period crossing midnight with a brief
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

        await tester.pumpWidget(
          _buildSubject(
            sessions: [
              _s(id: 's-a', memberId: 'a', start: dayOneStart, end: dayTwoEnd),
            ],
            periods: periods,
            members: {'a': _member('a', 'Alice'), 'b': _member('b', 'Bob')},
          ),
        );
        await tester.pumpAndSettle();

        // The visitor's chip should appear EXACTLY once — on the day
        // the visit happened, not duplicated on the continuation row.
        expect(find.text('+Bob briefly'), findsOneWidget);
      },
    );

    testWidgets(
      'tapping a co-front middle period navigates to a contributing session',
      (tester) async {
        // Regression: in `A → A+B → A`, the middle period's
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
              builder: (_, state) =>
                  Scaffold(body: Text('session-${state.pathParameters['id']}')),
            ),
          ],
        );

        await tester.pumpWidget(
          _buildSubject(
            sessions: [
              _s(id: 'session-a', memberId: 'a', start: t0, end: t3),
              _s(id: 'session-b', memberId: 'b', start: t1, end: t2),
            ],
            periods: periods,
            members: {'a': _member('a', 'Alice'), 'b': _member('b', 'Bob')},
            router: router,
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Alice & Bob'));
        await tester.pumpAndSettle();

        // The route opens on a session ID drawn from the middle period's
        // sessionIds. The widget routes to the first id (current 1A
        // behavior). What matters: it's one of the period's real
        // contributors, NOT a stray ID.
        final routedToA = find.text('session-session-a').evaluate().isNotEmpty;
        final routedToB = find.text('session-session-b').evaluate().isNotEmpty;
        expect(
          routedToA || routedToB,
          isTrue,
          reason:
              'tap on middle co-front period must route to a '
              'contributing session',
        );
      },
    );

    test('open current front produces a single midnight slice (not 30+) when '
        'rangeEnd is bounded at now', () {
      // Regression: when the provider conflated the SQL
      // lookahead (now + 30d) with the visible rangeEnd, an open
      // current front would extend to "now + 30 days" and the
      // midnight splitter would carve it into ~30 day-group rows,
      // each labelled with a future date. With rangeEnd bounded at
      // `now`, the open period extends exactly to `now`; the
      // midnight splitter produces at most 1–2 slices (today, plus
      // possibly yesterday if started before midnight).
      //
      // Tested at the splitter layer (pure function) rather than
      // via widget test — the live FrontingDurationText timer leaks
      // pending timers when exercised through pumpAndSettle, and the
      // midnight-slice contract is a pure function of the period's
      // start/end.
      final start = DateTime.now().subtract(const Duration(hours: 2));
      final endBoundedAtNow = DateTime.now();

      // Period as the (post-fix) derivation would emit: end ≈ now.
      final period = FrontingPeriod(
        start: start,
        end: endBoundedAtNow,
        activeMembers: const ['a'],
        briefVisitors: const [],
        sessionIds: const ['open'],
        alwaysPresentMembers: const [],
        isOpenEnded: true,
      );

      final slices = splitPeriodAtMidnight(period);
      // 2-hour open period spans at most TODAY (and possibly
      // YESTERDAY if "now" is between midnight and 02:00). Must
      // NEVER produce 30+ slices spanning the SQL lookahead window.
      expect(
        slices.length,
        lessThanOrEqualTo(2),
        reason:
            'a 2-hour open period should produce 1–2 day slices, '
            'not 30+ future midnight slices',
      );
      // No slice should start in the future.
      for (final s in slices) {
        expect(
          s.displayStart.isAfter(endBoundedAtNow),
          isFalse,
          reason:
              'no slice should start after the period\'s end '
              '(which is bounded at "now")',
        );
      }
    });

    testWidgets(
      'tap routing through actual provider chain (real Drift) lands on '
      'a contributing session for a co-front period',
      (tester) async {
        // Regression: instead of overriding `derivedPeriodsProvider`
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
              builder: (_, state) =>
                  Scaffold(body: Text('routed-${state.pathParameters['id']}')),
            ),
          ],
        );

        final widget = ProviderScope(
          overrides: [
            // Real repository → exercises the real overlap query and
            // the real derivation through the provider chain.
            frontingSessionRepositoryProvider.overrideWith(
              (ref) => repo as FrontingSessionRepository,
            ),
            // 1B: SessionHistoryList now reads `systemSettingsProvider`
            // to pick the inline view mode. Pin to combinedPeriods so
            // this test continues to exercise the derived-period path
            // through the real Drift chain.
            systemSettingsProvider.overrideWith(
              (ref) => Stream.value(const SystemSettings()),
            ),
            // Members are looked up by the widget for avatars/names —
            // we override these two streams (not the repository) so we
            // don't have to wire the full member repo.
            allMembersProvider.overrideWith(
              (ref) => Stream.value([
                Member(id: 'a', name: 'Alice', createdAt: DateTime(2026, 1, 1)),
                Member(id: 'b', name: 'Bob', createdAt: DateTime(2026, 1, 1)),
              ]),
            ),
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
        expect(
          cofront,
          findsOneWidget,
          reason:
              'real Drift chain must produce a co-front period for A → A+B → A',
        );
        await tester.tap(cofront);
        await tester.pumpAndSettle();

        final routedToA = find.text('routed-session-a').evaluate().isNotEmpty;
        final routedToB = find.text('routed-session-b').evaluate().isNotEmpty;
        expect(
          routedToA || routedToB,
          isTrue,
          reason:
              'tap on co-front period must route to a real contributing '
              'session id (not a boundary event)',
        );
      },
    );
  });

  // ─────────────────────────────────────────────────────────────────────
  // 1B view-mode branching coverage
  // ─────────────────────────────────────────────────────────────────────

  group('SessionHistoryList – view mode (1B)', () {
    SystemSettings settings(FrontingListViewMode mode) =>
        SystemSettings(frontingListViewMode: mode);

    Widget buildModeSubject({
      required FrontingListViewMode mode,
      required List<FrontingSession> sessions,
      List<FrontingPeriod> periods = const [],
      Map<String, Member> members = const {},
      List<AlwaysPresentMember> alwaysPresent = const [],
    }) {
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
            builder: (_, state) =>
                Scaffold(body: Text('session-${state.pathParameters['id']}')),
          ),
        ],
      );

      // Build a bundle for the overlap provider — perMemberRows reads
      // from this directly. `rangeStart` only matters for derivation,
      // which the perMemberRows path doesn't run.
      final bundle = DerivedPeriodsInputBundle(
        sessions: sessions,
        rangeStart: DateTime(2020),
      );

      return ProviderScope(
        overrides: [
          systemSettingsProvider.overrideWith(
            (ref) => Stream.value(settings(mode)),
          ),
          unifiedHistoryProvider.overrideWith((ref) => Stream.value(sessions)),
          unifiedHistoryOverlapProvider.overrideWith(
            (ref) => Stream.value(bundle),
          ),
          derivedPeriodsProvider.overrideWith(
            (ref) => AsyncValue.data(periods),
          ),
          alwaysPresentMembersProvider.overrideWith(
            (ref) => AsyncValue.data(alwaysPresent),
          ),
          membersByIdsProvider.overrideWith((ref, _) => Stream.value(members)),
          allMembersProvider.overrideWith(
            (ref) => Stream.value(members.values.toList()),
          ),
        ],
        child: MaterialApp.router(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: const [Locale('en')],
          routerConfig: router,
        ),
      );
    }

    testWidgets('combinedPeriods mode renders derived-period rows', (
      tester,
    ) async {
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

      await tester.pumpWidget(
        buildModeSubject(
          mode: FrontingListViewMode.combinedPeriods,
          sessions: [_s(id: 's-a', memberId: 'a', start: t0, end: t1)],
          periods: periods,
          members: {'a': _member('a', 'Alice')},
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Alice'), findsOneWidget);
    });

    testWidgets('perMemberRows mode renders one row per session', (
      tester,
    ) async {
      final t0 = DateTime(2026, 4, 1, 10);
      final t1 = DateTime(2026, 4, 1, 11);
      final t2 = DateTime(2026, 4, 1, 12);

      await tester.pumpWidget(
        buildModeSubject(
          mode: FrontingListViewMode.perMemberRows,
          sessions: [
            _s(id: 's-a', memberId: 'a', start: t0, end: t2),
            _s(id: 's-b', memberId: 'b', start: t1, end: t2),
          ],
          members: {'a': _member('a', 'Alice'), 'b': _member('b', 'Bob')},
        ),
      );
      await tester.pumpAndSettle();

      // Two rows — one per session, NOT a combined "Alice & Bob" row.
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);
      expect(find.text('Alice & Bob'), findsNothing);
    });

    testWidgets(
      'perMemberRows mode filters always-present members on days where '
      'their pinned session was already open',
      (tester) async {
        // Anchor: Host has been fronting since day 1 noon (still open).
        // Day 2 sessions for Host should be filtered out — they are part
        // of the "currently-open" window the pinned glass header covers.
        final hostStart = DateTime(2026, 4, 1, 12);
        final day2Start = DateTime(2026, 4, 2, 9);

        final hostSession = _s(
          id: 's-host',
          memberId: 'host',
          start: hostStart,
          end: null, // open
        );
        final day2VisitorSession = _s(
          id: 's-bob',
          memberId: 'bob',
          start: day2Start,
          end: DateTime(2026, 4, 2, 10),
        );

        final hostMember = Member(
          id: 'host',
          name: 'Host',
          createdAt: DateTime(2025, 1, 1),
          isAlwaysFronting: true,
        );

        await tester.pumpWidget(
          buildModeSubject(
            mode: FrontingListViewMode.perMemberRows,
            sessions: [hostSession, day2VisitorSession],
            members: {'host': hostMember, 'bob': _member('bob', 'Bob')},
            alwaysPresent: [
              AlwaysPresentMember(
                member: hostMember,
                session: hostSession,
                age: const Duration(days: 8),
              ),
            ],
          ),
        );
        await tester.pumpAndSettle();

        // Bob's session shows. Host's open session is filtered.
        expect(find.text('Bob'), findsOneWidget);
        expect(find.text('Host'), findsNothing);
      },
    );

    testWidgets(
      'perMemberRows mode keeps always-present members inline on earlier '
      'days where they were guests',
      (tester) async {
        // Host became "always-present" on April 5 (current open session).
        // On April 1 they had a separate, closed session — that one
        // should still appear inline, since it ended BEFORE the
        // currently-pinned session began.
        final earlyHostStart = DateTime(2026, 4, 1, 9);
        final earlyHostEnd = DateTime(2026, 4, 1, 10);
        final pinnedHostStart = DateTime(2026, 4, 5, 12);

        final earlyHostSession = _s(
          id: 's-host-early',
          memberId: 'host',
          start: earlyHostStart,
          end: earlyHostEnd,
        );
        final pinnedHostSession = _s(
          id: 's-host-pinned',
          memberId: 'host',
          start: pinnedHostStart,
          end: null,
        );

        final hostMember = Member(
          id: 'host',
          name: 'Host',
          createdAt: DateTime(2025, 1, 1),
          isAlwaysFronting: true,
        );

        await tester.pumpWidget(
          buildModeSubject(
            mode: FrontingListViewMode.perMemberRows,
            sessions: [pinnedHostSession, earlyHostSession],
            members: {'host': hostMember},
            alwaysPresent: [
              AlwaysPresentMember(
                member: hostMember,
                session: pinnedHostSession,
                age: const Duration(days: 1),
              ),
            ],
          ),
        );
        await tester.pumpAndSettle();

        // The April 1 session stays inline (ended before pinned start).
        // The April 5 pinned session is filtered (it IS the always-
        // present session). Net: one Host row.
        expect(find.text('Host'), findsOneWidget);
      },
    );

    testWidgets(
      'timeline pref falls back to combinedPeriods inside SessionHistoryList',
      (tester) async {
        // The screen-level toggle (`timelineViewActiveProvider`) owns
        // timeline rendering. When this widget is invoked we are by
        // definition on the list path, so the timeline pref value must
        // collapse to combinedPeriods — otherwise the toggle and the
        // pref fight each other when both resolve to different views.
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              systemSettingsProvider.overrideWith(
                (ref) => Stream.value(
                  const SystemSettings(
                    frontingListViewMode: FrontingListViewMode.timeline,
                  ),
                ),
              ),
              derivedPeriodsProvider.overrideWith(
                (ref) => const AsyncValue<List<FrontingPeriod>>.data([]),
              ),
              unifiedHistoryProvider.overrideWith(
                (ref) => Stream.value(const <FrontingSession>[]),
              ),
            ],
            // ignore: prefer_const_constructors
            child: MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: const [Locale('en')],
              home: const Scaffold(
                body: CustomScrollView(slivers: [SessionHistoryList()]),
              ),
            ),
          ),
        );
        await tester.pump();
        // No inline TimelineView — that path was removed in 1B fixups.
        expect(find.byType(TimelineView), findsNothing);
      },
    );
  });
}
