// Tests for SleepStatCards widget.
//
// STUB NOTE: SleepStatsView and sleepStatsProvider are defined below as stubs
// because this worktree branches from main before Task 3 (sleep stats provider)
// landed. On cherry-pick into fronting-per-member-sessions these stubs must be
// removed and the import from sleep_providers.dart used instead. The production
// widget already imports from the real path.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/features/fronting/widgets/sleep_stat_cards.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';

// ─────────────────────────────────────────────────────────────────────────────
// STUBS — remove these when cherry-picking onto fronting-per-member-sessions
// ─────────────────────────────────────────────────────────────────────────────

class SleepStatsView {
  const SleepStatsView({
    required this.totalEverCount,
    this.lastNight,
    required this.avg7d,
    required this.avg7dPrior,
  });

  final int totalEverCount;
  final FrontingSession? lastNight;
  final ({int count, Duration? avgDuration}) avg7d;
  final ({int count, Duration? avgDuration}) avg7dPrior;
}

final sleepStatsProvider = FutureProvider.autoDispose<SleepStatsView>(
  (ref) => Future.value(
    const SleepStatsView(
      totalEverCount: 0,
      avg7d: (count: 0, avgDuration: null),
      avg7dPrior: (count: 0, avgDuration: null),
    ),
  ),
);

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

FrontingSession _sleepSession({
  Duration duration = const Duration(hours: 8, minutes: 12),
  SleepQuality quality = SleepQuality.good,
}) {
  final start = DateTime.now().subtract(duration);
  return FrontingSession(
    id: 'sleep-1',
    startTime: start,
    endTime: DateTime.now(),
    sessionType: SessionType.sleep,
    quality: quality,
  );
}

Widget _buildSubject(SleepStatsView view) {
  return ProviderScope(
    overrides: [
      sleepStatsProvider.overrideWith((ref) => Future.value(view)),
    ],
    child: const MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: [Locale('en')],
      home: Scaffold(body: SleepStatCards()),
    ),
  );
}

const _emptyStats = SleepStatsView(
  totalEverCount: 0,
  avg7d: (count: 0, avgDuration: null),
  avg7dPrior: (count: 0, avgDuration: null),
);

SleepStatsView _statsWithLastNight({
  FrontingSession? session,
  ({int count, Duration? avgDuration}) avg7d = (count: 0, avgDuration: null),
  ({int count, Duration? avgDuration}) avg7dPrior = (
    count: 0,
    avgDuration: null,
  ),
}) => SleepStatsView(
  totalEverCount: 5,
  lastNight: session,
  avg7d: avg7d,
  avg7dPrior: avg7dPrior,
);

// ─────────────────────────────────────────────────────────────────────────────
// Tests
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  // ── Loading state ──────────────────────────────────────────────────────────

  group('loading state', () {
    testWidgets('renders nothing while loading', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sleepStatsProvider.overrideWith(
              (ref) => Future<SleepStatsView>.delayed(const Duration(hours: 1)),
            ),
          ],
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: [Locale('en')],
            home: Scaffold(body: SleepStatCards()),
          ),
        ),
      );
      // Don't pumpAndSettle — future never resolves; just pump once.
      await tester.pump();

      expect(find.byType(SizedBox), findsWidgets);
      // No stat content rendered.
      expect(find.byType(Card), findsNothing);
      expect(find.text('Last night'), findsNothing);
    });
  });

  // ── Zero sessions ──────────────────────────────────────────────────────────

  group('zero sessions', () {
    testWidgets('renders nothing when totalEverCount == 0', (tester) async {
      await tester.pumpWidget(_buildSubject(_emptyStats));
      await tester.pumpAndSettle();

      expect(find.text('Last night'), findsNothing);
      expect(find.text('7-day average'), findsNothing);
    });
  });

  // ── Has sessions, no last-night entry ─────────────────────────────────────

  group('sessions exist but no last night', () {
    testWidgets('shows last-night card with em-dash, hides 7d card', (
      tester,
    ) async {
      await tester.pumpWidget(_buildSubject(_statsWithLastNight()));
      await tester.pumpAndSettle();

      // Last-night card visible (label from l10n.sleepLastNight)
      expect(find.text('Last night'), findsOneWidget);

      // Duration shown as em-dash when session is null
      expect(find.text('—'), findsOneWidget);

      // 7d card hidden when lastNight == null
      expect(find.text('7-day average'), findsNothing);
    });
  });

  // ── Normal data — both cards ───────────────────────────────────────────────

  group('normal data', () {
    testWidgets('shows both cards when lastNight is set', (tester) async {
      final session = _sleepSession();
      await tester.pumpWidget(
        _buildSubject(
          _statsWithLastNight(
            session: session,
            avg7d: (count: 7, avgDuration: const Duration(hours: 7, minutes: 30)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Last night'), findsOneWidget);
      expect(find.text('7-day average'), findsOneWidget);
    });

    testWidgets('last-night card shows formatted duration', (tester) async {
      final session = _sleepSession(
        duration: const Duration(hours: 8, minutes: 12),
      );
      await tester.pumpWidget(_buildSubject(_statsWithLastNight(session: session)));
      await tester.pumpAndSettle();

      // toRoundedString() for 8h 12m → "8h 12m"
      expect(find.text('8h 12m'), findsOneWidget);
    });

    testWidgets('7d avg card shows formatted average duration', (tester) async {
      final session = _sleepSession();
      await tester.pumpWidget(
        _buildSubject(
          _statsWithLastNight(
            session: session,
            avg7d: (count: 7, avgDuration: const Duration(hours: 7, minutes: 45)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('7h 45m'), findsOneWidget);
    });

    testWidgets('trend line shown when prior count > 0', (tester) async {
      final session = _sleepSession();
      await tester.pumpWidget(
        _buildSubject(
          _statsWithLastNight(
            session: session,
            avg7d: (count: 7, avgDuration: const Duration(hours: 7, minutes: 30)),
            avg7dPrior: (
              count: 7,
              avgDuration: const Duration(hours: 7, minutes: 12),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Prior week avg 7h12m → this week 7h30m → delta = +18m
      expect(find.textContaining('+18m'), findsOneWidget);
    });

    testWidgets('trend line hidden when prior count == 0', (tester) async {
      final session = _sleepSession();
      await tester.pumpWidget(
        _buildSubject(
          _statsWithLastNight(
            session: session,
            avg7d: (count: 7, avgDuration: const Duration(hours: 7, minutes: 30)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('vs prior'), findsNothing);
    });

    testWidgets('negative delta uses minus sign', (tester) async {
      final session = _sleepSession();
      await tester.pumpWidget(
        _buildSubject(
          _statsWithLastNight(
            session: session,
            avg7d: (count: 7, avgDuration: const Duration(hours: 7)),
            avg7dPrior: (
              count: 7,
              avgDuration: const Duration(hours: 7, minutes: 23),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // delta = −23m
      expect(find.textContaining('−23m'), findsOneWidget);
    });
  });

  // ── Layout: narrow vs wide ────────────────────────────────────────────────

  group('layout', () {
    testWidgets('uses Column layout on narrow screen (359px)', (tester) async {
      tester.view.physicalSize = const Size(359, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final session = _sleepSession();
      await tester.pumpWidget(
        _buildSubject(
          _statsWithLastNight(
            session: session,
            avg7d: (count: 7, avgDuration: const Duration(hours: 7)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(Column), findsWidgets);
      expect(find.byType(Row), findsNothing);
    });

    testWidgets('uses Row layout on wide screen (400px)', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final session = _sleepSession();
      await tester.pumpWidget(
        _buildSubject(
          _statsWithLastNight(
            session: session,
            avg7d: (count: 7, avgDuration: const Duration(hours: 7)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(Row), findsWidgets);
    });
  });

  // ── Semantics ──────────────────────────────────────────────────────────────

  group('semantics', () {
    testWidgets('last-night card has a semantic label mentioning "Last night"', (
      tester,
    ) async {
      final session = _sleepSession(quality: SleepQuality.good);
      await tester.pumpWidget(_buildSubject(_statsWithLastNight(session: session)));
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsLabel(RegExp('Last night', caseSensitive: false)),
        findsOneWidget,
      );
    });

    testWidgets('7d card has a semantic label mentioning "7-day"', (
      tester,
    ) async {
      final session = _sleepSession();
      await tester.pumpWidget(
        _buildSubject(
          _statsWithLastNight(
            session: session,
            avg7d: (count: 7, avgDuration: const Duration(hours: 7)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsLabel(RegExp('7-day', caseSensitive: false)),
        findsOneWidget,
      );
    });

    testWidgets('excludeSemantics produces exactly one semantic node per card', (
      tester,
    ) async {
      final session = _sleepSession();
      await tester.pumpWidget(_buildSubject(_statsWithLastNight(session: session)));
      await tester.pumpAndSettle();

      final handle = tester.ensureSemantics();
      // With excludeSemantics: true, the Semantics wrapper merges its subtree
      // into a single node — so exactly one match for "Last night".
      expect(
        find.bySemanticsLabel(RegExp('Last night', caseSensitive: false)),
        findsOneWidget,
      );
      handle.dispose();
    });
  });
}
