import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/features/fronting/providers/derived_periods_provider.dart';
import 'package:prism_plurality/features/fronting/providers/front_comments_providers.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_providers.dart';
import 'package:prism_plurality/features/fronting/services/derive_periods.dart';
import 'package:prism_plurality/features/fronting/views/period_detail_args.dart';
import 'package:prism_plurality/features/fronting/views/period_detail_screen.dart';
import 'package:prism_plurality/features/fronting/widgets/comments_for_range_section.dart';
import 'package:prism_plurality/features/fronting/widgets/fronting_duration_text.dart';
import 'package:prism_plurality/features/members/providers/members_batch_provider.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/shared/widgets/group_member_avatar.dart';
import 'package:prism_plurality/shared/widgets/member_avatar.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';

// ── Navigator observer for pop detection ─────────────────────────────────────

class _TestObserver extends NavigatorObserver {
  final List<Route<dynamic>> popped = [];

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    popped.add(route);
  }
}

Member _member(String id, String name) =>
    Member(id: id, name: name, createdAt: DateTime(2026, 1, 1));

final _t0 = DateTime(2026, 4, 1, 10, 0);
final _t1 = DateTime(2026, 4, 1, 11, 0);

PeriodDetailArgs _hint({
  List<Member>? members,
  DateTime? start,
  DateTime? end,
  bool isOpenEnded = false,
}) {
  final activeMembers =
      members ??
      [_member('a', 'Sky'), _member('b', 'Fern')];
  return PeriodDetailArgs(
    activeMembers: activeMembers,
    start: start ?? _t0,
    end: end ?? _t1,
    isOpenEnded: isOpenEnded,
    alwaysPresentMembers: const [],
  );
}

FrontingSession _session(String id, String memberId, {bool active = false}) =>
    FrontingSession(
      id: id,
      memberId: memberId,
      startTime: _t0,
      endTime: active ? null : _t1,
    );

Widget _wrap({
  required List<String> sessionIds,
  PeriodDetailArgs? hint,
  List<FrontingPeriod> periods = const [],
  // When true, all sessionByIdProvider stubs return null (simulates fully
  // deleted sessions). When false (default), stubs return minimal non-null
  // sessions so the screen renders normally instead of triggering staleness.
  bool allSessionsNull = false,
}) {
  // CommentsForRangeSection watches commentsForRangeProvider(range), where range
  // comes from the matched period or the hint. Stub the expected range so Drift
  // is never touched and no pending timers fire on teardown.
  //
  // The helper's hint defaults to _t0.._t1, and _wrap passes no matching period
  // by default (periods=[]), so the range is derived from the hint.
  final hintStart = hint?.start ?? _t0;
  final hintEnd = hint?.end ?? _t1;
  final matchedPeriod = periods.isNotEmpty
      ? periods.where((p) {
          final target = sessionIds.toSet();
          final candidate = p.sessionIds.toSet();
          return candidate.length == target.length &&
              candidate.containsAll(target);
        }).firstOrNull
      : null;
  final commentRangeStart = matchedPeriod?.start ?? hintStart;
  final commentRangeEnd = matchedPeriod?.end ?? hintEnd;
  final commentRange = DateTimeRange(
    start: commentRangeStart,
    end: commentRangeEnd,
  );

  return ProviderScope(
    overrides: [
      derivedPeriodsProvider.overrideWith(
        (ref) => AsyncValue.data(periods),
      ),
      // Stub systemSettingsProvider — GroupMemberAvatar reads terminology
      // settings which chain through systemSettingsProvider to Drift. Without
      // this stub, a pending Drift cleanup timer fires on test teardown.
      systemSettingsProvider.overrideWith(
        (ref) => Stream.value(const SystemSettings()),
      ),
      // Stub sessionByIdProvider for every session id — _CoFrontersSection
      // watches these. Without stubs they hit Drift and leave pending timers.
      // Default: return a minimal non-null session (memberId = sessionId) so
      // staleness UX doesn't fire. Set allSessionsNull: true to simulate a
      // fully-stale period.
      for (final id in sessionIds)
        sessionByIdProvider(id).overrideWith(
          (ref) => Stream.value(allSessionsNull ? null : _session(id, id)),
        ),
      // When sessions are non-null, _CoFrontersSection will watch
      // membersByIdsProvider for the stub member IDs (= sessionIds). Stub to
      // avoid hitting Drift and leaving pending timers.
      if (!allSessionsNull)
        membersByIdsProvider(memberIdsKey(sessionIds)).overrideWith(
          (ref) => Stream.value(const {}),
        ),
      // Stub commentsForRangeProvider — CommentsForRangeSection watches this.
      // Without a stub it hits Drift and leaves a pending cleanup timer.
      commentsForRangeProvider(commentRange).overrideWith(
        (ref) => Stream.value(const []),
      ),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('en')],
      home: PeriodDetailScreen(sessionIds: sessionIds, hint: hint),
    ),
  );
}

void main() {
  group('PeriodDetailScreen', () {
    // PrismToast.resetForTest() must run before the test framework checks for
    // pending timers — register inside the group so it applies to all tests
    // in this suite and fires before _verifyInvariants.
    tearDown(PrismToast.resetForTest);

    testWidgets('renders header from hint with names and time range', (
      tester,
    ) async {
      final hint = _hint(
        members: [_member('a', 'Sky'), _member('b', 'Fern')],
        start: DateTime(2026, 4, 1, 10, 0),
        end: DateTime(2026, 4, 1, 11, 0),
      );
      await tester.pumpWidget(
        _wrap(sessionIds: const ['s1', 's2'], hint: hint),
      );
      // Use pump(Duration.zero) instead of pumpAndSettle to avoid blocking on
      // any animation or pending timer from FrontingDurationText.
      await tester.pump();

      // Names string: "Sky & Fern"
      expect(find.text('Sky & Fern'), findsOneWidget);
      // Time range should contain the start time (locale-formatted "10:00 AM").
      // At least one widget shows "10:00 AM" (header + co-fronter rows may both
      // show it when stub sessions share the same time range).
      expect(find.textContaining('10:00 AM'), findsAtLeastNWidgets(1));
    });

    testWidgets('loading state when hint is null', (tester) async {
      await tester.pumpWidget(
        _wrap(sessionIds: const ['s1'], hint: null),
      );
      // Use pump() — CircularProgressIndicator is animated and pumpAndSettle
      // would spin forever.
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('live timer renders for open-ended period', (tester) async {
      final hint = _hint(isOpenEnded: true, end: DateTime.now());
      await tester.pumpWidget(
        _wrap(sessionIds: const ['s1', 's2'], hint: hint),
      );
      await tester.pump();

      expect(find.byType(FrontingDurationText), findsOneWidget);
    });

    testWidgets('live timer disappears when period closes mid-mount', (
      tester,
    ) async {
      // Start with open-ended hint and no matching period in provider (hint
      // drives isOpenEnded = true).
      final start = DateTime.now().subtract(const Duration(hours: 1));
      final hint = _hint(
        isOpenEnded: true,
        start: start,
        end: DateTime.now(),
      );
      await tester.pumpWidget(
        _wrap(
          sessionIds: const ['s1', 's2'],
          hint: hint,
          periods: const [],
        ),
      );
      await tester.pump();

      // Timer visible because hint says isOpenEnded=true and no matching
      // period to override it.
      expect(find.byType(FrontingDurationText), findsOneWidget);

      // Now override derivedPeriodsProvider to return a matching closed period.
      final closedEnd = DateTime.now();
      final closedPeriod = FrontingPeriod(
        start: start,
        end: closedEnd,
        activeMembers: const ['a', 'b'],
        briefVisitors: const [],
        sessionIds: const ['s1', 's2'],
        alwaysPresentMembers: const [],
        isOpenEnded: false,
      );

      // Use a new key to force Flutter to fully unmount the old tree and mount
      // a fresh one — avoids ProviderScope.didUpdateWidget diffing subtleties.
      await tester.pumpWidget(
        KeyedSubtree(
          key: const ValueKey('closed'),
          child: ProviderScope(
            overrides: [
              derivedPeriodsProvider.overrideWith(
                (ref) => AsyncValue.data([closedPeriod]),
              ),
              systemSettingsProvider.overrideWith(
                (ref) => Stream.value(const SystemSettings()),
              ),
              // Stub sessionByIdProvider — _CoFrontersSection watches these.
              // Must be non-null to avoid triggering the all-null staleness UX.
              // Without stubs they hit Drift and leave pending timers.
              sessionByIdProvider('s1').overrideWith(
                (ref) => Stream.value(_session('s1', 's1')),
              ),
              sessionByIdProvider('s2').overrideWith(
                (ref) => Stream.value(_session('s2', 's2')),
              ),
              // Stub membersByIdsProvider for the sessions' member IDs — avoids
              // hitting Drift and leaving pending timers.
              membersByIdsProvider(memberIdsKey(['s1', 's2'])).overrideWith(
                (ref) => Stream.value(const {}),
              ),
              // Stub commentsForRangeProvider — matched period is closedPeriod
              // with start/end derived from closedPeriod.start/end.
              commentsForRangeProvider(
                DateTimeRange(start: closedPeriod.start, end: closedPeriod.end),
              ).overrideWith((ref) => Stream.value(const [])),
            ],
            child: MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: const [Locale('en')],
              home: PeriodDetailScreen(
                sessionIds: const ['s1', 's2'],
                hint: hint,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // Timer gone — provider says closed.
      expect(find.byType(FrontingDurationText), findsNothing);
    });

    testWidgets('4 names render fully without truncation', (tester) async {
      final members = [
        _member('a', 'Sky'),
        _member('b', 'Fern'),
        _member('c', 'Aimee'),
        _member('d', 'Hex'),
      ];
      final hint = _hint(members: members);
      await tester.pumpWidget(
        _wrap(sessionIds: const ['s1', 's2', 's3', 's4'], hint: hint),
      );
      await tester.pump();

      // All four names must appear in the title text (no "+N" truncation).
      final titleFinder = find.textContaining('Sky');
      expect(titleFinder, findsOneWidget);
      expect(find.textContaining('Fern'), findsOneWidget);
      expect(find.textContaining('Aimee'), findsOneWidget);
      expect(find.textContaining('Hex'), findsOneWidget);

      // "+1" or "+2" or any "+N" should NOT appear in the names title.
      final titleWidget = tester.widget<Text>(
        find.byWidgetPredicate(
          (w) =>
              w is Text &&
              w.data != null &&
              w.data!.contains('Sky') &&
              w.data!.contains('Fern'),
        ),
      );
      expect(titleWidget.data, isNot(contains('+')));
    });

    testWidgets('group avatar renders with 4 members', (tester) async {
      final members = [
        _member('a', 'Sky'),
        _member('b', 'Fern'),
        _member('c', 'Aimee'),
        _member('d', 'Hex'),
      ];
      final hint = _hint(members: members);
      await tester.pumpWidget(
        _wrap(sessionIds: const ['s1', 's2', 's3', 's4'], hint: hint),
      );
      await tester.pump();

      expect(find.byType(GroupMemberAvatar), findsOneWidget);
    });

    // ── T6: Co-fronters section ─────────────────────────────────────────────

    testWidgets('co-fronters section renders one row per resolved session', (
      tester,
    ) async {
      final memberA = _member('ma', 'Fern');
      final memberB = _member('mb', 'Hex');
      final sessionS1 = _session('s1', 'ma');
      final sessionS2 = _session('s2', 'mb');

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            derivedPeriodsProvider.overrideWith(
              (ref) => const AsyncValue.data([]),
            ),
            systemSettingsProvider.overrideWith(
              (ref) => Stream.value(const SystemSettings()),
            ),
            sessionByIdProvider('s1').overrideWith(
              (ref) => Stream.value(sessionS1),
            ),
            sessionByIdProvider('s2').overrideWith(
              (ref) => Stream.value(sessionS2),
            ),
            membersByIdsProvider(memberIdsKey(['ma', 'mb'])).overrideWith(
              (ref) => Stream.value({'ma': memberA, 'mb': memberB}),
            ),
            commentsForRangeProvider(
              DateTimeRange(start: _t0, end: _t1),
            ).overrideWith((ref) => Stream.value(const [])),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: const [Locale('en')],
            home: PeriodDetailScreen(
              sessionIds: const ['s1', 's2'],
              hint: _hint(),
            ),
          ),
        ),
      );
      // Two pumps: first propagates stream subscriptions, second delivers data.
      await tester.pump();
      await tester.pump();

      // Both names must appear in the co-fronters section.
      expect(find.text('Fern'), findsOneWidget);
      expect(find.text('Hex'), findsOneWidget);
      // Two MemberAvatars rendered (one per row).
      expect(find.byType(MemberAvatar), findsNWidgets(2));
    });

    testWidgets('co-fronters section silently omits null sessions', (
      tester,
    ) async {
      final memberA = _member('ma', 'Fern');
      final sessionS1 = _session('s1', 'ma');

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            derivedPeriodsProvider.overrideWith(
              (ref) => const AsyncValue.data([]),
            ),
            systemSettingsProvider.overrideWith(
              (ref) => Stream.value(const SystemSettings()),
            ),
            sessionByIdProvider('s1').overrideWith(
              (ref) => Stream.value(sessionS1),
            ),
            // s2 resolves to null (tombstoned/missing).
            sessionByIdProvider('s2').overrideWith(
              (ref) => Stream.value(null),
            ),
            membersByIdsProvider(memberIdsKey(['ma'])).overrideWith(
              (ref) => Stream.value({'ma': memberA}),
            ),
            commentsForRangeProvider(
              DateTimeRange(start: _t0, end: _t1),
            ).overrideWith((ref) => Stream.value(const [])),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: const [Locale('en')],
            home: PeriodDetailScreen(
              sessionIds: const ['s1', 's2'],
              hint: _hint(),
            ),
          ),
        ),
      );
      // Two pumps: first propagates stream subscriptions, second delivers data.
      await tester.pump();
      await tester.pump();

      // Only s1's member row renders — no error.
      expect(find.text('Fern'), findsOneWidget);
      // One MemberAvatar for the resolved row.
      expect(find.byType(MemberAvatar), findsOneWidget);
      // No error widget rendered.
      expect(find.byType(ErrorWidget), findsNothing);
    });

    testWidgets('co-fronters section tap navigates to session detail', (
      tester,
    ) async {
      // Verifies that tapping a co-fronter row routes to /session/s1.
      final memberA = _member('ma', 'Fern');
      final sessionS1 = _session('s1', 'ma');

      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => PeriodDetailScreen(
              sessionIds: const ['s1'],
              hint: _hint(),
            ),
          ),
          GoRoute(
            path: '/session/:id',
            builder: (_, state) => Scaffold(
              body: Text('session-${state.pathParameters['id']}'),
            ),
          ),
          GoRoute(
            path: '/session/:id/edit',
            builder: (_, state) => Scaffold(
              body: Text('edit-${state.pathParameters['id']}'),
            ),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            derivedPeriodsProvider.overrideWith(
              (ref) => const AsyncValue.data([]),
            ),
            systemSettingsProvider.overrideWith(
              (ref) => Stream.value(const SystemSettings()),
            ),
            sessionByIdProvider('s1').overrideWith(
              (ref) => Stream.value(sessionS1),
            ),
            membersByIdsProvider(memberIdsKey(['ma'])).overrideWith(
              (ref) => Stream.value({'ma': memberA}),
            ),
            commentsForRangeProvider(
              DateTimeRange(start: _t0, end: _t1),
            ).overrideWith((ref) => Stream.value(const [])),
          ],
          child: MaterialApp.router(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: const [Locale('en')],
            routerConfig: router,
          ),
        ),
      );
      // Two pumps: first propagates stream subscriptions, second delivers data.
      await tester.pump();
      await tester.pump();

      // Row is present.
      expect(find.text('Fern'), findsOneWidget);

      // Tap navigates to /session/s1.
      await tester.tap(find.text('Fern'));
      await tester.pumpAndSettle();

      expect(find.text('session-s1'), findsOneWidget);
    });

    testWidgets(
      'co-fronters section shows Unknown treatment for missing member',
      (tester) async {
        // Session present but its memberId is NOT in the membersMap.
        final sessionS1 = _session('s1', 'missing-member-id');

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              derivedPeriodsProvider.overrideWith(
                (ref) => const AsyncValue.data([]),
              ),
              systemSettingsProvider.overrideWith(
                (ref) => Stream.value(const SystemSettings()),
              ),
              sessionByIdProvider('s1').overrideWith(
                (ref) => Stream.value(sessionS1),
              ),
              // Empty map — member not resolved.
              membersByIdsProvider(
                memberIdsKey(['missing-member-id']),
              ).overrideWith((ref) => Stream.value({})),
              commentsForRangeProvider(
                DateTimeRange(start: _t0, end: _t1),
              ).overrideWith((ref) => Stream.value(const [])),
            ],
            child: MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: const [Locale('en')],
              home: PeriodDetailScreen(
                sessionIds: const ['s1'],
                hint: _hint(),
              ),
            ),
          ),
        );
        await tester.pump();

        // "Unknown" text should appear in italic/dim style.
        final unknownFinder = find.text('Unknown');
        expect(unknownFinder, findsOneWidget);

        // The Unknown row should show a dim italic name style (fontStyle.italic).
        final unknownText = tester.widget<Text>(unknownFinder);
        expect(unknownText.style?.fontStyle, FontStyle.italic);
      },
    );

    // ── T8: Briefly joined section ──────────────────────────────────────────

    testWidgets('briefly joined section renders when briefVisitors non-empty', (
      tester,
    ) async {
      final visitStart = DateTime(2026, 4, 1, 10, 5);
      final visitEnd = DateTime(2026, 4, 1, 10, 15);
      final visit = EphemeralVisit(
        memberId: 'm1',
        start: visitStart,
        end: visitEnd,
        sessionId: 'v1',
      );
      final period = FrontingPeriod(
        start: _t0,
        end: _t1,
        activeMembers: const ['a', 'b'],
        briefVisitors: [visit],
        sessionIds: const ['s1', 's2'],
        alwaysPresentMembers: const [],
        isOpenEnded: false,
      );
      final memberM1 = _member('m1', 'Jules');

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            derivedPeriodsProvider.overrideWith(
              (ref) => AsyncValue.data([period]),
            ),
            systemSettingsProvider.overrideWith(
              (ref) => Stream.value(const SystemSettings()),
            ),
            // s1 is non-null to prevent the all-null staleness UX from firing.
            // s2 is null — partial staleness is silently tolerated.
            sessionByIdProvider('s1').overrideWith(
              (ref) => Stream.value(_session('s1', 's1')),
            ),
            sessionByIdProvider('s2').overrideWith(
              (ref) => Stream.value(null),
            ),
            // Stub members for s1 (memberId='s1') and Jules (m1).
            membersByIdsProvider(memberIdsKey(['s1'])).overrideWith(
              (ref) => Stream.value(const {}),
            ),
            membersByIdsProvider(memberIdsKey(['m1'])).overrideWith(
              (ref) => Stream.value({'m1': memberM1}),
            ),
            commentsForRangeProvider(
              DateTimeRange(start: _t0, end: _t1),
            ).overrideWith((ref) => Stream.value(const [])),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: const [Locale('en')],
            home: PeriodDetailScreen(
              sessionIds: const ['s1', 's2'],
              hint: _hint(),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('Briefly joined'), findsOneWidget);
      expect(find.text('Jules'), findsOneWidget);
    });

    testWidgets('briefly joined section is hidden when briefVisitors is empty', (
      tester,
    ) async {
      final period = FrontingPeriod(
        start: _t0,
        end: _t1,
        activeMembers: const ['a', 'b'],
        briefVisitors: const [],
        sessionIds: const ['s1', 's2'],
        alwaysPresentMembers: const [],
        isOpenEnded: false,
      );

      await tester.pumpWidget(
        _wrap(
          sessionIds: const ['s1', 's2'],
          hint: _hint(),
          periods: [period],
        ),
      );
      await tester.pump();

      expect(find.text('Briefly joined'), findsNothing);
    });

    testWidgets(
      'tapping a brief visitor row navigates to that visit session detail',
      (tester) async {
        final visitStart = DateTime(2026, 4, 1, 10, 5);
        final visitEnd = DateTime(2026, 4, 1, 10, 15);
        final visit = EphemeralVisit(
          memberId: 'm1',
          start: visitStart,
          end: visitEnd,
          sessionId: 'v1',
        );
        final period = FrontingPeriod(
          start: _t0,
          end: _t1,
          activeMembers: const ['a', 'b'],
          briefVisitors: [visit],
          sessionIds: const ['s1', 's2'],
          alwaysPresentMembers: const [],
          isOpenEnded: false,
        );
        final memberM1 = _member('m1', 'Jules');

        final router = GoRouter(
          routes: [
            GoRoute(
              path: '/',
              builder: (_, _) => PeriodDetailScreen(
                sessionIds: const ['s1', 's2'],
                hint: _hint(),
              ),
            ),
            GoRoute(
              path: '/session/:id',
              builder: (_, state) => Scaffold(
                body: Text('session-${state.pathParameters['id']}'),
              ),
            ),
            GoRoute(
              path: '/session/:id/edit',
              builder: (_, state) => Scaffold(
                body: Text('edit-${state.pathParameters['id']}'),
              ),
            ),
          ],
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              derivedPeriodsProvider.overrideWith(
                (ref) => AsyncValue.data([period]),
              ),
              systemSettingsProvider.overrideWith(
                (ref) => Stream.value(const SystemSettings()),
              ),
              // s1 non-null to prevent the all-null staleness UX.
              sessionByIdProvider('s1').overrideWith(
                (ref) => Stream.value(_session('s1', 's1')),
              ),
              sessionByIdProvider('s2').overrideWith(
                (ref) => Stream.value(null),
              ),
              membersByIdsProvider(memberIdsKey(['s1'])).overrideWith(
                (ref) => Stream.value(const {}),
              ),
              membersByIdsProvider(memberIdsKey(['m1'])).overrideWith(
                (ref) => Stream.value({'m1': memberM1}),
              ),
              commentsForRangeProvider(
                DateTimeRange(start: _t0, end: _t1),
              ).overrideWith((ref) => Stream.value(const [])),
            ],
            child: MaterialApp.router(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: const [Locale('en')],
              routerConfig: router,
            ),
          ),
        );
        await tester.pump();
        await tester.pump();

        expect(find.text('Jules'), findsOneWidget);

        await tester.tap(find.text('Jules'));
        await tester.pumpAndSettle();

        // Visit's sessionId is 'v1', so navigation should go to /session/v1.
        expect(find.text('session-v1'), findsOneWidget);
      },
    );

    // ── T8: Always present section ──────────────────────────────────────────

    testWidgets(
      'always present section renders when alwaysPresentMembers non-empty',
      (tester) async {
        final period = FrontingPeriod(
          start: _t0,
          end: _t1,
          activeMembers: const ['a', 'b'],
          briefVisitors: const [],
          sessionIds: const ['s1', 's2'],
          alwaysPresentMembers: const ['ap1'],
          isOpenEnded: false,
        );
        final memberAp1 = _member('ap1', 'Aria');

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              derivedPeriodsProvider.overrideWith(
                (ref) => AsyncValue.data([period]),
              ),
              systemSettingsProvider.overrideWith(
                (ref) => Stream.value(const SystemSettings()),
              ),
              // s1 non-null to prevent the all-null staleness UX from firing.
              sessionByIdProvider('s1').overrideWith(
                (ref) => Stream.value(_session('s1', 's1')),
              ),
              sessionByIdProvider('s2').overrideWith(
                (ref) => Stream.value(null),
              ),
              membersByIdsProvider(memberIdsKey(['s1'])).overrideWith(
                (ref) => Stream.value(const {}),
              ),
              membersByIdsProvider(memberIdsKey(['ap1'])).overrideWith(
                (ref) => Stream.value({'ap1': memberAp1}),
              ),
              commentsForRangeProvider(
                DateTimeRange(start: _t0, end: _t1),
              ).overrideWith((ref) => Stream.value(const [])),
            ],
            child: MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: const [Locale('en')],
              home: PeriodDetailScreen(
                sessionIds: const ['s1', 's2'],
                hint: _hint(),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump();

        expect(find.text('Always present'), findsOneWidget);
        expect(find.text('Aria'), findsOneWidget);
      },
    );

    testWidgets(
      'always present section is hidden when alwaysPresentMembers is empty',
      (tester) async {
        final period = FrontingPeriod(
          start: _t0,
          end: _t1,
          activeMembers: const ['a', 'b'],
          briefVisitors: const [],
          sessionIds: const ['s1', 's2'],
          alwaysPresentMembers: const [],
          isOpenEnded: false,
        );

        await tester.pumpWidget(
          _wrap(
            sessionIds: const ['s1', 's2'],
            hint: _hint(),
            periods: [period],
          ),
        );
        await tester.pump();

        expect(find.text('Always present'), findsNothing);
      },
    );

    testWidgets(
      'briefly joined and always present hidden when no matching period',
      (tester) async {
        // derivedPeriodsProvider returns a period that does NOT match the
        // screen's sessionIds — simulates period boundaries shifted mid-flight.
        final nonMatchingPeriod = FrontingPeriod(
          start: _t0,
          end: _t1,
          activeMembers: const ['x'],
          briefVisitors: [
            EphemeralVisit(
              memberId: 'v',
              start: _t0,
              end: _t1,
              sessionId: 'different-session',
            ),
          ],
          sessionIds: const ['different-session'],
          alwaysPresentMembers: const ['ap1'],
          isOpenEnded: false,
        );

        await tester.pumpWidget(
          _wrap(
            sessionIds: const ['s1', 's2'],
            hint: _hint(),
            periods: [nonMatchingPeriod],
          ),
        );
        await tester.pump();

        expect(find.text('Briefly joined'), findsNothing);
        expect(find.text('Always present'), findsNothing);
      },
    );

    // ── T9: Comments section ────────────────────────────────────────────────

    testWidgets('comments section renders with matched period range', (
      tester,
    ) async {
      final period = FrontingPeriod(
        start: _t0,
        end: _t1,
        activeMembers: const ['a', 'b'],
        briefVisitors: const [],
        sessionIds: const ['s1', 's2'],
        alwaysPresentMembers: const [],
        isOpenEnded: false,
      );

      await tester.pumpWidget(
        _wrap(
          sessionIds: const ['s1', 's2'],
          hint: _hint(),
          periods: [period],
        ),
      );
      await tester.pump();

      expect(find.byType(CommentsForRangeSection), findsOneWidget);
    });

    testWidgets('comments section renders with hint range when no matching period', (
      tester,
    ) async {
      // Provide a hint but no matching period — CommentsForRangeSection should
      // still render, deriving range from hint.start/hint.end.
      await tester.pumpWidget(
        _wrap(
          sessionIds: const ['s1', 's2'],
          hint: _hint(start: _t0, end: _t1),
          periods: const [],
        ),
      );
      await tester.pump();

      expect(find.byType(CommentsForRangeSection), findsOneWidget);
    });

    // ── T13: Stale-session UX ───────────────────────────────────────────────

    testWidgets(
      'all sessionIds resolve null → toast shown and route popped',
      (tester) async {
        // Use GoRouter with 2 routes: home "/" + detail "/detail".
        // Navigate to detail, let sessions resolve null, and verify:
        //   1. We end up back at "/"  (the detail was popped)
        //   2. The error toast text is visible via PrismToastHost.
        final router = GoRouter(
          routes: [
            GoRoute(
              path: '/',
              builder: (_, _) => const Scaffold(
                body: Center(child: Text('home')),
              ),
            ),
            GoRoute(
              path: '/detail',
              builder: (_, _) => PeriodDetailScreen(
                sessionIds: const ['s1', 's2'],
                hint: _hint(),
              ),
            ),
          ],
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              derivedPeriodsProvider.overrideWith(
                (ref) => const AsyncValue.data([]),
              ),
              systemSettingsProvider.overrideWith(
                (ref) => Stream.value(const SystemSettings()),
              ),
              // Both sessions resolve to null — fully stale.
              sessionByIdProvider('s1').overrideWith(
                (ref) => Stream.value(null),
              ),
              sessionByIdProvider('s2').overrideWith(
                (ref) => Stream.value(null),
              ),
              commentsForRangeProvider(DateTimeRange(start: _t0, end: _t1))
                  .overrideWith((ref) => Stream.value(const [])),
            ],
            child: MaterialApp.router(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: const [Locale('en')],
              routerConfig: router,
              builder: (context, child) => PrismToastHost(child: child!),
            ),
          ),
        );

        // Navigate to the detail route with push (preserves "/" in history so
        // Navigator.canPop() returns true and the pop lands on "/").
        await tester.pump(); // initial build: "/" renders
        router.push('/detail');
        await tester.pump(); // route pushed
        await tester.pump(); // streams deliver null data
        // Post-frame callback fires — toast shown, pop requested.
        await tester.pump(Duration.zero);
        // Let the pop animation settle.
        await tester.pump();

        // Toast message visible (PrismToastHost renders it in the builder).
        expect(find.text('Session not found'), findsOneWidget);
        // We are back at "/" — the detail screen was popped.
        expect(find.text('home'), findsOneWidget);

        // Dismiss the toast timer — must be called inside the test body because
        // _verifyInvariants (pending timer check) fires BEFORE tearDown.
        PrismToast.resetForTest();
      },
    );

    testWidgets(
      'toast fires exactly once — not re-fired on subsequent rebuilds',
      (tester) async {
        // Use GoRouter: push to detail, let sessions resolve null.
        // Multiple extra pumps must NOT produce a second toast widget.
        final router = GoRouter(
          routes: [
            GoRoute(
              path: '/',
              builder: (_, _) => const Scaffold(
                body: Center(child: Text('home')),
              ),
            ),
            GoRoute(
              path: '/detail',
              builder: (_, _) => PeriodDetailScreen(
                sessionIds: const ['s1'],
                hint: _hint(),
              ),
            ),
          ],
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              derivedPeriodsProvider.overrideWith(
                (ref) => const AsyncValue.data([]),
              ),
              systemSettingsProvider.overrideWith(
                (ref) => Stream.value(const SystemSettings()),
              ),
              sessionByIdProvider('s1').overrideWith(
                (ref) => Stream.value(null),
              ),
              commentsForRangeProvider(DateTimeRange(start: _t0, end: _t1))
                  .overrideWith((ref) => Stream.value(const [])),
            ],
            child: MaterialApp.router(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: const [Locale('en')],
              routerConfig: router,
              builder: (context, child) => PrismToastHost(child: child!),
            ),
          ),
        );

        await tester.pump(); // initial build
        router.push('/detail');
        await tester.pump();
        await tester.pump();
        await tester.pump(Duration.zero);
        await tester.pump(); // pop settles

        // Toast appears exactly once.
        expect(
          tester.widgetList(find.text('Session not found')).length,
          1,
          reason: 'Toast must fire exactly once',
        );

        // Additional pumps — should NOT re-fire; still exactly one toast.
        await tester.pump();
        await tester.pump();
        expect(
          tester.widgetList(find.text('Session not found')).length,
          1,
          reason: 'Toast must not re-fire on subsequent rebuilds',
        );

        // Dismiss toast timer before _verifyInvariants runs.
        PrismToast.resetForTest();
      },
    );

    testWidgets(
      'one of N sessions null, others survive → no toast, no pop, row renders',
      (tester) async {
        final memberA = _member('ma', 'Fern');
        final sessionS1 = _session('s1', 'ma');
        final observer = _TestObserver();

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              derivedPeriodsProvider.overrideWith(
                (ref) => const AsyncValue.data([]),
              ),
              systemSettingsProvider.overrideWith(
                (ref) => Stream.value(const SystemSettings()),
              ),
              // s1 resolves to a real session; s2 is null.
              sessionByIdProvider('s1').overrideWith(
                (ref) => Stream.value(sessionS1),
              ),
              sessionByIdProvider('s2').overrideWith(
                (ref) => Stream.value(null),
              ),
              membersByIdsProvider(memberIdsKey(['ma'])).overrideWith(
                (ref) => Stream.value({'ma': memberA}),
              ),
              commentsForRangeProvider(DateTimeRange(start: _t0, end: _t1))
                  .overrideWith((ref) => Stream.value(const [])),
            ],
            child: MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: const [Locale('en')],
              navigatorObservers: [observer],
              home: PrismToastHost(
                child: PeriodDetailScreen(
                  sessionIds: const ['s1', 's2'],
                  hint: _hint(),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump();
        await tester.pump(Duration.zero);

        // No error toast shown.
        expect(find.text('Session not found'), findsNothing);
        // No pop fired — observer sees nothing.
        expect(observer.popped, isEmpty);
        // Surviving row renders.
        expect(find.text('Fern'), findsOneWidget);
      },
    );

    testWidgets(
      'dropped ID from original set: header renders from hint, '
      'period-level subsections hide (set-equality miss)',
      (tester) async {
        // Screen receives 2 IDs; original period had 3 (s1, s2, s3).
        // derivedPeriodsProvider returns the 3-id period — set-equality
        // mismatch → no matchedPeriod → Briefly joined + Always present hidden.
        final originalPeriod = FrontingPeriod(
          start: _t0,
          end: _t1,
          activeMembers: const ['a', 'b', 'c'],
          briefVisitors: [
            EphemeralVisit(
              memberId: 'bv1',
              start: _t0,
              end: _t1,
              sessionId: 'sv1',
            ),
          ],
          sessionIds: const ['s1', 's2', 's3'],
          alwaysPresentMembers: const ['ap1'],
          isOpenEnded: false,
        );

        final hint = _hint(
          members: [_member('a', 'Sky'), _member('b', 'Fern')],
          start: _t0,
          end: _t1,
        );

        await tester.pumpWidget(
          _wrap(
            sessionIds: const ['s1', 's2'],
            hint: hint,
            periods: [originalPeriod],
          ),
        );
        await tester.pump();

        // Header renders from hint (Sky & Fern present).
        expect(find.textContaining('Sky'), findsOneWidget);
        expect(find.textContaining('Fern'), findsOneWidget);

        // Period-level subsections hidden — set-equality miss, no matchedPeriod.
        expect(find.text('Briefly joined'), findsNothing);
        expect(find.text('Always present'), findsNothing);
      },
    );
  });
}
