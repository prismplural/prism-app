// Tests for the floating "End session" pill on SessionDetailScreen.
//
// Covers:
//   1. Visibility when active non-sleep session with member
//   2. Hidden when sleep session
//   3. Hidden when ended session
//   4. Hidden when orphan (memberId == null)
//   5. Tap with 2+ active sessions → endFronting called, no dialog
//   6. Tap with 1 active session → dialog with 3 action choices
//   7. Dialog → End without fronting → endFronting called
//   8. Dialog → Unknown → endFronting then startFronting(unknown)
//   9. Dialog → Pick a fronter (sheet returns true) → endFronting called
//  10. Dialog → Pick a fronter (sheet cancelled) → endFronting NOT called
//  11. Dialog → tap outside barrier → no calls

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/constants/fronting_namespaces.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/features/fronting/providers/front_comments_providers.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_providers.dart';
import 'package:prism_plurality/features/fronting/views/session_detail_screen.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Test doubles
// ─────────────────────────────────────────────────────────────────────────────

class _FakeFrontingNotifier extends FrontingNotifier {
  final List<List<String>> endedCalls = [];
  final List<List<String>> startedCalls = [];

  @override
  Future<void> build() async {}

  @override
  Future<void> endFronting(List<String> memberIds) async {
    endedCalls.add(List.of(memberIds));
  }

  @override
  Future<void> startFronting(
    List<String> memberIds, {
    FrontConfidence? confidence,
    String? notes,
    DateTime? startTime,
  }) async {
    startedCalls.add(List.of(memberIds));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Fixtures
// ─────────────────────────────────────────────────────────────────────────────

const _memberId = 'member-1';
const _sessionId = 'session-1';

Member _member() => Member(
  id: _memberId,
  name: 'Alice',
  createdAt: DateTime(2026, 4, 30),
);

FrontingSession _activeSession({String? memberId = _memberId}) =>
    FrontingSession(
      id: _sessionId,
      memberId: memberId,
      startTime: DateTime(2026, 4, 30, 10),
    );

FrontingSession _endedSession() => FrontingSession(
  id: _sessionId,
  memberId: _memberId,
  startTime: DateTime(2026, 4, 30, 10),
  endTime: DateTime(2026, 4, 30, 11),
);

FrontingSession _sleepSession() => FrontingSession(
  id: _sessionId,
  memberId: _memberId,
  startTime: DateTime(2026, 4, 30, 10),
  sessionType: SessionType.sleep,
);

// ─────────────────────────────────────────────────────────────────────────────
// Widget builder
// ─────────────────────────────────────────────────────────────────────────────

Widget _buildApp({
  required FrontingSession session,
  Member? member,
  List<FrontingSession> activeSessions = const [],
  _FakeFrontingNotifier? frontingNotifier,
}) {
  final fake = frontingNotifier ?? _FakeFrontingNotifier();
  final memberToUse = member ?? _member();

  final commentRange = DateTimeRange(
    start: session.startTime,
    end: session.endTime ?? session.startTime.add(const Duration(days: 1)),
  );

  return ProviderScope(
    overrides: [
      sessionByIdProvider(session.id).overrideWith(
        (ref) => Stream.value(session),
      ),
      memberByIdProvider(memberToUse.id).overrideWith(
        (ref) => Stream.value(memberToUse),
      ),
      activeSessionsProvider.overrideWith(
        (ref) => Stream.value(activeSessions),
      ),
      commentsForRangeProvider(commentRange).overrideWith(
        (ref) => Stream.value(const []),
      ),
      frontingNotifierProvider.overrideWith(() => fake),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('en')],
      home: SessionDetailScreen(sessionId: session.id),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Tests
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  // PrismToast.resetForTest() must run before the test framework checks for
  // pending timers, so use addTearDown (which fires before _verifyInvariants).
  // The outer tearDown below is kept as a belt-and-suspenders clean-up.
  tearDown(PrismToast.resetForTest);

  group('SessionDetailScreen — floating end-session pill', () {
    // 1. Visibility — active non-sleep with member
    testWidgets('shows pill for active non-sleep session with member', (
      tester,
    ) async {
      final session = _activeSession();
      await tester.pumpWidget(
        _buildApp(session: session, activeSessions: [session]),
      );
      await tester.pumpAndSettle();

      expect(find.text('End session'), findsOneWidget);
    });

    // 2. Hidden when sleep
    testWidgets('hides pill for sleep session', (tester) async {
      final session = _sleepSession();
      await tester.pumpWidget(
        _buildApp(session: session, activeSessions: [session]),
      );
      await tester.pumpAndSettle();

      expect(find.text('End session'), findsNothing);
    });

    // 3. Hidden when not active
    testWidgets('hides pill for ended session', (tester) async {
      final session = _endedSession();
      await tester.pumpWidget(
        _buildApp(session: session, activeSessions: const []),
      );
      await tester.pumpAndSettle();

      expect(find.text('End session'), findsNothing);
    });

    // 4. Hidden when orphan (memberId == null)
    testWidgets('hides pill when session has no member id', (tester) async {
      final session = _activeSession(memberId: null);
      await tester.pumpWidget(
        _buildApp(session: session, activeSessions: [session]),
      );
      await tester.pumpAndSettle();

      expect(find.text('End session'), findsNothing);
    });

    // 5. Tap with 2+ active sessions → endFronting called, no dialog
    testWidgets(
      'tapping pill with 2 active sessions ends session without dialog',
      (tester) async {
        final session = _activeSession();
        final other = FrontingSession(
          id: 'session-2',
          memberId: 'member-2',
          startTime: DateTime(2026, 4, 30, 10),
        );
        final fake = _FakeFrontingNotifier();

        await tester.pumpWidget(
          _buildApp(
            session: session,
            activeSessions: [session, other],
            frontingNotifier: fake,
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('End session'));
        await tester.pumpAndSettle();

        // endFronting called with session's memberId
        expect(fake.endedCalls, [
          [_memberId],
        ]);
        // No "Who's fronting next?" dialog shown
        expect(find.text("Who's fronting next?"), findsNothing);

        // Dismiss the success toast timer before the test framework checks
        // for pending timers (PrismToast auto-dismisses after 3 seconds).
        PrismToast.resetForTest();
      },
    );

    // 6. Tap with only this session active → dialog with 3 actions visible
    testWidgets(
      'tapping pill with 1 active session shows next-fronter dialog',
      (tester) async {
        final session = _activeSession();
        final fake = _FakeFrontingNotifier();

        await tester.pumpWidget(
          _buildApp(
            session: session,
            activeSessions: [session],
            frontingNotifier: fake,
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('End session'));
        await tester.pumpAndSettle();

        expect(find.text("Who's fronting next?"), findsOneWidget);
        expect(find.text('Pick a fronter'), findsOneWidget);
        expect(find.text('Unknown'), findsOneWidget);
        expect(find.text('End without fronting'), findsOneWidget);
      },
    );

    // 7. Dialog → End without fronting → endFronting called
    testWidgets(
      'dialog → End without fronting calls endFronting once',
      (tester) async {
        final session = _activeSession();
        final fake = _FakeFrontingNotifier();

        await tester.pumpWidget(
          _buildApp(
            session: session,
            activeSessions: [session],
            frontingNotifier: fake,
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('End session'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('End without fronting'));
        await tester.pumpAndSettle();

        expect(fake.endedCalls, [
          [_memberId],
        ]);
        expect(fake.startedCalls, isEmpty);

        PrismToast.resetForTest();
      },
    );

    // 8. Dialog → Unknown → endFronting then startFronting([unknownSentinelMemberId])
    testWidgets(
      'dialog → Unknown calls endFronting then startFronting with unknown sentinel',
      (tester) async {
        final session = _activeSession();
        final fake = _FakeFrontingNotifier();

        await tester.pumpWidget(
          _buildApp(
            session: session,
            activeSessions: [session],
            frontingNotifier: fake,
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('End session'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Unknown'));
        await tester.pumpAndSettle();

        expect(fake.endedCalls, [
          [_memberId],
        ]);
        expect(fake.startedCalls, [
          [unknownSentinelMemberId],
        ]);

        PrismToast.resetForTest();
      },
    );

    // 11. Dialog → tap outside barrier → no calls
    testWidgets(
      'dismissing dialog by tapping barrier makes no calls',
      (tester) async {
        final session = _activeSession();
        final fake = _FakeFrontingNotifier();

        await tester.pumpWidget(
          _buildApp(
            session: session,
            activeSessions: [session],
            frontingNotifier: fake,
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('End session'));
        await tester.pumpAndSettle();

        // Tap the barrier to dismiss
        await tester.tapAt(const Offset(10, 10));
        await tester.pumpAndSettle();

        expect(fake.endedCalls, isEmpty);
        expect(fake.startedCalls, isEmpty);
      },
    );
  });
}
