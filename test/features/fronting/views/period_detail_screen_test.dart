import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/features/fronting/providers/derived_periods_provider.dart';
import 'package:prism_plurality/features/fronting/services/derive_periods.dart';
import 'package:prism_plurality/features/fronting/views/period_detail_args.dart';
import 'package:prism_plurality/features/fronting/views/period_detail_screen.dart';
import 'package:prism_plurality/features/fronting/widgets/fronting_duration_text.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/shared/widgets/group_member_avatar.dart';
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
  });
}
