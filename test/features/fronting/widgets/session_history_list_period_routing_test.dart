// Widget tests for _PeriodTile routing: 1-contributor → /session/:id,
// 2+-contributor → /period?id=…&id=… with PeriodDetailArgs extra.
//
// Test strategy: Path A — drive through the public SessionHistoryList widget
// with mocked providers and a test GoRouter that captures the built page URL
// and state.extra so we can assert routing without a full Drift setup.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:prism_plurality/core/router/app_routes.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/features/fronting/providers/derived_periods_provider.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_providers.dart';
import 'package:prism_plurality/features/fronting/services/derive_periods.dart';
import 'package:prism_plurality/features/fronting/views/period_detail_args.dart';
import 'package:prism_plurality/features/fronting/widgets/session_history_list.dart';
import 'package:prism_plurality/features/members/providers/members_batch_provider.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

Member _member(String id, String name) =>
    Member(id: id, name: name, createdAt: DateTime(2026, 1, 1));

FrontingSession _session({
  required String id,
  required String memberId,
  required DateTime start,
  DateTime? end,
}) => FrontingSession(id: id, memberId: memberId, startTime: start, endTime: end);

/// Builds a test widget that:
///   - Mounts SessionHistoryList with the given derived periods + members
///   - Wires up a GoRouter with routes for '/', '/session/:id', and '/period'
///   - The '/period' route records the routed URI and state.extra in [capturedUri]
///     and [capturedExtra] for assertion
Widget _buildSubject({
  required List<FrontingSession> sessions,
  required List<FrontingPeriod> periods,
  required Map<String, Member> members,
  required GoRouter router,
}) {
  return ProviderScope(
    overrides: [
      unifiedHistoryProvider.overrideWith((ref) => Stream.value(sessions)),
      derivedPeriodsProvider.overrideWith((ref) => AsyncValue.data(periods)),
      membersByIdsProvider.overrideWith((ref, _) => Stream.value(members)),
      systemSettingsProvider.overrideWith(
        (ref) => Stream.value(const SystemSettings()),
      ),
    ],
    child: MaterialApp.router(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('en')],
      routerConfig: router,
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Tests
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  group('_PeriodTile routing', () {
    testWidgets(
      '1-contributor period routes to /session/<id>',
      (tester) async {
        final t0 = DateTime(2026, 4, 1, 10);
        final t1 = DateTime(2026, 4, 1, 12);

        final periods = [
          FrontingPeriod(
            start: t0,
            end: t1,
            activeMembers: const ['alice'],
            briefVisitors: const [],
            sessionIds: const ['s1'],
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
            // /period registered so the router doesn't throw if somehow
            // the wrong branch is taken.
            GoRoute(
              path: '/period',
              builder: (_, _) => const Scaffold(body: Text('period-screen')),
            ),
          ],
        );

        await tester.pumpWidget(
          _buildSubject(
            sessions: [_session(id: 's1', memberId: 'alice', start: t0, end: t1)],
            periods: periods,
            members: {'alice': _member('alice', 'Alice')},
            router: router,
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Alice'));
        await tester.pumpAndSettle();

        // Must land on the single-session detail route.
        expect(find.text('session-s1'), findsOneWidget);
        // Must NOT have navigated to /period.
        expect(find.text('period-screen'), findsNothing);
      },
    );

    testWidgets(
      '2-contributor period routes to /period with sorted ids in URI',
      (tester) async {
        final t0 = DateTime(2026, 4, 1, 10);
        final t1 = DateTime(2026, 4, 1, 12);

        // sessionIds deliberately given in reverse order to confirm sorting.
        final periods = [
          FrontingPeriod(
            start: t0,
            end: t1,
            activeMembers: const ['alice', 'bob'],
            briefVisitors: const [],
            sessionIds: const ['s2', 's1'],
            alwaysPresentMembers: const [],
            isOpenEnded: false,
          ),
        ];

        // Capture the URI the /period builder receives.
        Uri? capturedUri;

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
            GoRoute(
              path: '/period',
              builder: (context, state) {
                capturedUri = state.uri;
                return const Scaffold(body: Text('period-screen'));
              },
            ),
          ],
        );

        await tester.pumpWidget(
          _buildSubject(
            sessions: [
              _session(id: 's1', memberId: 'alice', start: t0, end: t1),
              _session(id: 's2', memberId: 'bob', start: t0, end: t1),
            ],
            periods: periods,
            members: {
              'alice': _member('alice', 'Alice'),
              'bob': _member('bob', 'Bob'),
            },
            router: router,
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Alice & Bob'));
        await tester.pumpAndSettle();

        // Must land on /period, not /session/:id.
        expect(find.text('period-screen'), findsOneWidget);
        expect(find.textContaining('session-'), findsNothing);

        // URI must be /period?id=s1&id=s2 (AppRoutePaths.period sorts them).
        expect(capturedUri, isNotNull);
        final ids = capturedUri!.queryParametersAll['id'] ?? [];
        expect(ids, containsAll(['s1', 's2']));
        expect(ids, hasLength(2));
        // IDs must be sorted ascending.
        expect(ids, equals([...ids]..sort()));
      },
    );

    testWidgets(
      '2-contributor period passes PeriodDetailArgs via extra with full period bounds',
      (tester) async {
        // NOTE: the period intentionally crosses midnight so we can assert
        // that PeriodDetailArgs carries the FULL period.start / period.end
        // values and not the day-clamped slice bounds. Because the midnight
        // splitter produces two display slices (one per day), we tap the
        // first() match rather than asserting a single widget.
        final periodStart = DateTime(2026, 4, 1, 22); // 10 PM day 1
        final periodEnd = DateTime(2026, 4, 2, 2); // 2 AM day 2 — crosses midnight

        final periods = [
          FrontingPeriod(
            start: periodStart,
            end: periodEnd,
            activeMembers: const ['alice', 'bob'],
            briefVisitors: const [],
            sessionIds: const ['s1', 's2'],
            alwaysPresentMembers: const [],
            isOpenEnded: false,
          ),
        ];

        // Capture the extra passed to /period.
        Object? capturedExtra;

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
            GoRoute(
              path: '/period',
              builder: (context, state) {
                capturedExtra = state.extra;
                return const Scaffold(body: Text('period-screen'));
              },
            ),
          ],
        );

        final aliceObj = _member('alice', 'Alice');
        final bobObj = _member('bob', 'Bob');

        await tester.pumpWidget(
          _buildSubject(
            sessions: [
              _session(id: 's1', memberId: 'alice', start: periodStart, end: periodEnd),
              _session(id: 's2', memberId: 'bob', start: periodStart, end: periodEnd),
            ],
            periods: periods,
            members: {'alice': aliceObj, 'bob': bobObj},
            router: router,
          ),
        );
        await tester.pumpAndSettle();

        // The midnight splitter may produce two rows for this crossing period
        // (one on day 1, one on day 2). Tapping either must route to /period
        // with the same full-extent args. Tap the first rendered instance.
        expect(find.text('Alice & Bob'), findsWidgets);
        await tester.tap(find.text('Alice & Bob').first);
        await tester.pumpAndSettle();

        // Must land on the period screen.
        expect(find.text('period-screen'), findsOneWidget);

        // extra must be a PeriodDetailArgs.
        expect(capturedExtra, isA<PeriodDetailArgs>());
        final args = capturedExtra as PeriodDetailArgs;

        // Active members must include Alice and Bob.
        final activeNames = args.activeMembers.map((m) => m.name).toList();
        expect(activeNames, containsAll(['Alice', 'Bob']));

        // Bounds must be the FULL period extent, not day-clamped slice bounds.
        // For a midnight-crossing period this is critical — we assert the exact
        // period.start / period.end values rather than the display slice values.
        expect(args.start, equals(periodStart));
        expect(args.end, equals(periodEnd));
        expect(args.isOpenEnded, isFalse);
        expect(args.alwaysPresentMembers, isEmpty);
      },
    );
  });
}
