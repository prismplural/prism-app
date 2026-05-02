import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/features/fronting/providers/derived_periods_provider.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_providers.dart';
import 'package:prism_plurality/features/fronting/services/derive_periods.dart';
import 'package:prism_plurality/features/fronting/views/period_detail_args.dart';
import 'package:prism_plurality/features/fronting/views/period_detail_screen.dart';
import 'package:prism_plurality/features/fronting/widgets/fronting_duration_text.dart';
import 'package:prism_plurality/features/members/providers/members_batch_provider.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/shared/widgets/group_member_avatar.dart';
import 'package:prism_plurality/shared/widgets/member_avatar.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';

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
}) {
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
      for (final id in sessionIds)
        sessionByIdProvider(id).overrideWith(
          (ref) => Stream.value(null),
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
      // Time range should contain the start time (locale-formatted "10:00 AM")
      expect(find.textContaining('10:00 AM'), findsOneWidget);
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
              // Without stubs they hit Drift and leave pending timers.
              sessionByIdProvider('s1').overrideWith(
                (ref) => Stream.value(null),
              ),
              sessionByIdProvider('s2').overrideWith(
                (ref) => Stream.value(null),
              ),
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
  });
}
