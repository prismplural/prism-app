import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/features/fronting/services/derive_periods.dart';

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

Member _m(String id, {bool isAlwaysFronting = false}) => Member(
      id: id,
      name: id,
      createdAt: DateTime(2026, 1, 1),
      isAlwaysFronting: isAlwaysFronting,
    );

DerivePeriodsInput _input({
  required List<FrontingSession> sessions,
  Map<String, Member>? members,
  DateTime? rangeStart,
  DateTime? rangeEnd,
  DateTime? now,
  Duration ephemeralThreshold = kEphemeralThreshold,
}) {
  return DerivePeriodsInput(
    sessions: sessions,
    members: members ?? const {},
    rangeStart: rangeStart ?? DateTime(2026, 4, 1),
    rangeEnd: rangeEnd ?? DateTime(2026, 4, 2),
    now: now ?? DateTime(2026, 4, 2),
    ephemeralThreshold: ephemeralThreshold,
  );
}

void main() {
  group('deriveMaximalPeriods', () {
    test('empty input → empty output', () {
      final result = deriveMaximalPeriods(_input(sessions: const []));
      expect(result, isEmpty);
    });

    test('single session 6:42–9:07 → 1 period', () {
      final start = DateTime(2026, 4, 1, 6, 42);
      final end = DateTime(2026, 4, 1, 9, 7);
      final result = deriveMaximalPeriods(_input(sessions: [
        _s(id: 's1', memberId: 'a', start: start, end: end),
      ]));
      expect(result, hasLength(1));
      expect(result[0].start, start);
      expect(result[0].end, end);
      expect(result[0].activeMembers, ['a']);
      expect(result[0].sessionIds, ['s1']);
      expect(result[0].briefVisitors, isEmpty);
      expect(result[0].isOpenEnded, isFalse);
    });

    test('two members co-front entire range → 1 period with both', () {
      final start = DateTime(2026, 4, 1, 10);
      final end = DateTime(2026, 4, 1, 14);
      final result = deriveMaximalPeriods(_input(sessions: [
        _s(id: 's1', memberId: 'a', start: start, end: end),
        _s(id: 's2', memberId: 'b', start: start, end: end),
      ]));
      expect(result, hasLength(1));
      expect(result[0].activeMembers.toSet(), {'a', 'b'});
      expect(result[0].sessionIds.toSet(), {'s1', 's2'});
    });

    test('A → A+B → A pattern produces 3 periods', () {
      final t0 = DateTime(2026, 4, 1, 10);
      final t1 = DateTime(2026, 4, 1, 11);
      final t2 = DateTime(2026, 4, 1, 12);
      final t3 = DateTime(2026, 4, 1, 13);

      final result = deriveMaximalPeriods(_input(sessions: [
        _s(id: 'a', memberId: 'a', start: t0, end: t3),
        _s(id: 'b', memberId: 'b', start: t1, end: t2),
      ]));

      expect(result, hasLength(3));
      expect(result[0].activeMembers, ['a']);
      expect(result[0].start, t0);
      expect(result[0].end, t1);
      expect(result[1].activeMembers.toSet(), {'a', 'b'});
      expect(result[1].start, t1);
      expect(result[1].end, t2);
      expect(result[2].activeMembers, ['a']);
      expect(result[2].start, t2);
      expect(result[2].end, t3);
    });

    test('same-instant transition → 2 periods, no zero-length gap', () {
      final t0 = DateTime(2026, 4, 1, 10);
      final t1 = DateTime(2026, 4, 1, 12);
      final t2 = DateTime(2026, 4, 1, 14);

      final result = deriveMaximalPeriods(_input(sessions: [
        _s(id: 'a', memberId: 'a', start: t0, end: t1),
        _s(id: 'b', memberId: 'b', start: t1, end: t2),
      ]));

      expect(result, hasLength(2));
      expect(result[0].activeMembers, ['a']);
      expect(result[1].activeMembers, ['b']);
      // No zero-length "neither fronting" period in between.
      for (final p in result) {
        expect(p.duration > Duration.zero, isTrue,
            reason: 'period $p has zero duration');
      }
    });

    test('ephemeral visitor in 2-hour period collapses to brief', () {
      final t0 = DateTime(2026, 4, 1, 10);
      final t3 = DateTime(2026, 4, 1, 12); // 2 hours
      final tBriefStart = DateTime(2026, 4, 1, 11);
      final tBriefEnd = DateTime(2026, 4, 1, 11, 0, 30); // 30s

      final result = deriveMaximalPeriods(_input(sessions: [
        _s(id: 'a', memberId: 'a', start: t0, end: t3),
        _s(id: 'b', memberId: 'b', start: tBriefStart, end: tBriefEnd),
      ]));

      // The 30s middle slice (active set {a,b}) is collapsed; only one
      // long period for {a} survives, with b as a brief visitor.
      expect(result, hasLength(1));
      expect(result[0].activeMembers, ['a']);
      expect(result[0].briefVisitors, hasLength(1));
      expect(result[0].briefVisitors.first.memberId, 'b');
      expect(result[0].briefVisitors.first.duration,
          tBriefEnd.difference(tBriefStart));
    });

    test('open-ended session extends to range_end / now', () {
      final t0 = DateTime(2026, 4, 1, 10);
      final now = DateTime(2026, 4, 1, 15);

      final result = deriveMaximalPeriods(_input(
        sessions: [
          _s(id: 'a', memberId: 'a', start: t0, end: null),
        ],
        rangeStart: DateTime(2026, 4, 1),
        rangeEnd: DateTime(2026, 4, 1, 12),
        now: now,
      ));

      expect(result, hasLength(1));
      expect(result[0].start, t0);
      // openEndSub = max(now, rangeEnd) = now
      expect(result[0].end, now);
      expect(result[0].isOpenEnded, isTrue);
    });

    test('400-day continuous host with shorter visitor in visible range', () {
      final hostStart = DateTime(2025, 1, 1);
      final visibleStart = DateTime(2026, 4, 1);
      final visibleEnd = DateTime(2026, 4, 2);
      final visitorStart = DateTime(2026, 4, 1, 14);
      final visitorEnd = DateTime(2026, 4, 1, 16);

      final result = deriveMaximalPeriods(_input(
        sessions: [
          _s(id: 'host', memberId: 'host', start: hostStart, end: null),
          _s(id: 'v', memberId: 'v', start: visitorStart, end: visitorEnd),
        ],
        rangeStart: visibleStart,
        rangeEnd: visibleEnd,
        now: visibleEnd,
      ));

      // Three periods: host alone, host+v, host alone.
      expect(result, hasLength(3));
      expect(result[0].activeMembers, ['host']);
      expect(result[0].start, visibleStart); // clamped
      expect(result[1].activeMembers.toSet(), {'host', 'v'});
      expect(result[2].activeMembers, ['host']);
      // Host appears throughout.
      for (final p in result) {
        expect(p.activeMembers, contains('host'));
      }
    });

    test('is_always_fronting member is excluded from activeMembers', () {
      final hostStart = DateTime(2025, 1, 1);
      final visibleStart = DateTime(2026, 4, 1);
      final visibleEnd = DateTime(2026, 4, 2);
      final visitorStart = DateTime(2026, 4, 1, 14);
      final visitorEnd = DateTime(2026, 4, 1, 16);

      final result = deriveMaximalPeriods(_input(
        sessions: [
          _s(id: 'host', memberId: 'host', start: hostStart, end: null),
          _s(id: 'v', memberId: 'v', start: visitorStart, end: visitorEnd),
        ],
        members: {'host': _m('host', isAlwaysFronting: true), 'v': _m('v')},
        rangeStart: visibleStart,
        rangeEnd: visibleEnd,
        now: visibleEnd,
      ));

      // Only the visitor's period (foreground) is rendered. Always-present
      // host is surfaced via alwaysPresentMembers, not activeMembers.
      expect(result, hasLength(1));
      expect(result[0].activeMembers, ['v']);
      expect(result[0].alwaysPresentMembers, ['host']);
    });

    test('avatar stack ordering: longest-active-at-period-start first', () {
      // C starts earliest, then A joins, then B joins. At the period
      // {A,B,C}, expected order is C, A, B (by firstStart ascending).
      final t0 = DateTime(2026, 4, 1, 10); // C starts
      final t1 = DateTime(2026, 4, 1, 11); // A joins
      final t2 = DateTime(2026, 4, 1, 12); // B joins
      final t3 = DateTime(2026, 4, 1, 13); // all end

      final result = deriveMaximalPeriods(_input(sessions: [
        _s(id: 'c', memberId: 'c', start: t0, end: t3),
        _s(id: 'a', memberId: 'a', start: t1, end: t3),
        _s(id: 'b', memberId: 'b', start: t2, end: t3),
      ]));

      // Find the period where all three are active.
      final triple =
          result.firstWhere((p) => p.activeMembers.toSet().length == 3);
      expect(triple.activeMembers, ['c', 'a', 'b']);
    });

    test('avatar stack ordering: tiebreak by selection (input) order', () {
      // A and B start at the same instant. Spec §2.3 says tiebreak is
      // the user's selection order from the add-front sheet — at the
      // storage layer this is the input stream order. The sort must
      // NOT alphabetize by memberId.
      final t0 = DateTime(2026, 4, 1, 10);
      final t1 = DateTime(2026, 4, 1, 11);
      final result = deriveMaximalPeriods(_input(sessions: [
        // Input order: b first, then a — that's the "selection order".
        _s(id: 's1', memberId: 'b', start: t0, end: t1),
        _s(id: 's2', memberId: 'a', start: t0, end: t1),
      ]));
      expect(result, hasLength(1));
      // Both share firstStart = t0; tiebreak is input order, so 'b'
      // (selected first) leads.
      expect(result[0].activeMembers, ['b', 'a']);
    });

    test('avatar stack ordering: input-order tiebreak survives reverse',
        () {
      final t0 = DateTime(2026, 4, 1, 10);
      final t1 = DateTime(2026, 4, 1, 11);
      // Same data, reversed input → 'a' is the selected-first one now.
      final result = deriveMaximalPeriods(_input(sessions: [
        _s(id: 's2', memberId: 'a', start: t0, end: t1),
        _s(id: 's1', memberId: 'b', start: t0, end: t1),
      ]));
      expect(result, hasLength(1));
      expect(result[0].activeMembers, ['a', 'b']);
    });

    test('sleep sessions are skipped', () {
      final t0 = DateTime(2026, 4, 1, 10);
      final t1 = DateTime(2026, 4, 1, 12);
      final result = deriveMaximalPeriods(_input(sessions: [
        FrontingSession(
          id: 'sleep',
          memberId: 'a',
          startTime: t0,
          endTime: t1,
          sessionType: SessionType.sleep,
        ),
      ]));
      expect(result, isEmpty);
    });

    test('deleted sessions are skipped', () {
      final t0 = DateTime(2026, 4, 1, 10);
      final t1 = DateTime(2026, 4, 1, 12);
      final result = deriveMaximalPeriods(_input(sessions: [
        FrontingSession(
          id: 'd',
          memberId: 'a',
          startTime: t0,
          endTime: t1,
          isDeleted: true,
        ),
      ]));
      expect(result, isEmpty);
    });

    test('Unknown-fronter row (memberId == null) is treated as no-op', () {
      final t0 = DateTime(2026, 4, 1, 10);
      final t1 = DateTime(2026, 4, 1, 12);
      final result = deriveMaximalPeriods(_input(sessions: [
        FrontingSession(id: 'u', memberId: null, startTime: t0, endTime: t1),
      ]));
      expect(result, isEmpty);
    });

    test('A → A+B → A: each period\'s sessionIds covers contributors',
        () {
      // Codex P1 #3 fix: sessionIds must reflect the active sessions
      // throughout the period, not just the boundary events. The
      // middle co-front period was previously missing 'a' (only the
      // boundary +b/-b events recorded), and the trailing {a} period
      // could spuriously inherit b's session id from the boundary
      // event.
      final t0 = DateTime(2026, 4, 1, 10);
      final t1 = DateTime(2026, 4, 1, 11);
      final t2 = DateTime(2026, 4, 1, 12);
      final t3 = DateTime(2026, 4, 1, 13);

      final result = deriveMaximalPeriods(_input(sessions: [
        _s(id: 'session-a', memberId: 'a', start: t0, end: t3),
        _s(id: 'session-b', memberId: 'b', start: t1, end: t2),
      ]));

      expect(result, hasLength(3));

      // Leading {a} period: only a's session.
      expect(result[0].activeMembers, ['a']);
      expect(result[0].sessionIds.toSet(), {'session-a'});

      // Middle {a, b} period: BOTH sessions are active throughout.
      expect(result[1].activeMembers.toSet(), {'a', 'b'});
      expect(result[1].sessionIds.toSet(), {'session-a', 'session-b'});

      // Trailing {a} period: only a's session, NOT b's.
      expect(result[2].activeMembers, ['a']);
      expect(result[2].sessionIds.toSet(), {'session-a'});
      expect(result[2].sessionIds, isNot(contains('session-b')),
          reason: 'b\'s session must not bleed into the trailing {a} period');
    });

    test('isOpenEnded is scoped to the trailing-edge period only', () {
      // Codex P1 #2 fix: an active session must NOT mark earlier
      // closed periods as open-ended.
      final t0 = DateTime(2026, 4, 1, 8);
      final t1 = DateTime(2026, 4, 1, 9);
      final t2 = DateTime(2026, 4, 1, 12); // a's open session starts here
      final now = DateTime(2026, 4, 1, 15);

      final result = deriveMaximalPeriods(_input(
        sessions: [
          // Earlier closed period: just B.
          _s(id: 'closed-b', memberId: 'b', start: t0, end: t1),
          // Current/open: A.
          _s(id: 'open-a', memberId: 'a', start: t2, end: null),
        ],
        rangeStart: DateTime(2026, 4, 1),
        rangeEnd: now,
        now: now,
      ));

      // Two periods: closed {b} and open {a}.
      expect(result, hasLength(2));
      // Earlier closed period must not be marked open-ended even
      // though a later session is currently open.
      final closed = result.firstWhere((p) => p.activeMembers.contains('b'));
      expect(closed.isOpenEnded, isFalse,
          reason: 'closed earlier periods must not render the live timer');
      final open = result.firstWhere((p) => p.activeMembers.contains('a'));
      expect(open.isOpenEnded, isTrue);
    });

    test('past visible range: closed sessions clamp to rangeEnd', () {
      // Codex P2 fix: a closed session whose endTime is past the
      // visible range must clamp at rangeEnd. The previous behavior
      // used effectiveRangeEnd = max(now, rangeEnd) for ALL sessions,
      // letting a closed session bleed past the visible window.
      final pastStart = DateTime(2026, 1, 1, 10);
      final pastEnd = DateTime(2026, 1, 1, 14);
      final visibleStart = DateTime(2026, 1, 1, 9);
      final visibleEnd = DateTime(2026, 1, 1, 12);
      final now = DateTime(2026, 4, 1); // way past the visible range

      final result = deriveMaximalPeriods(_input(
        sessions: [
          _s(id: 's', memberId: 'a', start: pastStart, end: pastEnd),
        ],
        rangeStart: visibleStart,
        rangeEnd: visibleEnd,
        now: now,
      ));

      expect(result, hasLength(1));
      // End must be clamped to visibleEnd, not bleed to pastEnd.
      expect(result[0].end, visibleEnd);
      // And the period must NOT be flagged open-ended even though
      // openEndSub = max(now, visibleEnd) > visibleEnd — closed
      // sessions are never live.
      expect(result[0].isOpenEnded, isFalse);
    });

    test('cascading shorts: all-short input still emits one row',
        () {
      // Codex P2 fix: the previous collapse skipped every short
      // period when there were multiple in a row, producing empty
      // output for an all-short history. We must emit at least one
      // row covering the span with everyone as briefs.
      final t0 = DateTime(2026, 4, 1, 10);
      final result = deriveMaximalPeriods(_input(
        sessions: [
          _s(
            id: 's1',
            memberId: 'a',
            start: t0,
            end: t0.add(const Duration(seconds: 10)),
          ),
          _s(
            id: 's2',
            memberId: 'b',
            start: t0.add(const Duration(seconds: 15)),
            end: t0.add(const Duration(seconds: 25)),
          ),
          _s(
            id: 's3',
            memberId: 'c',
            start: t0.add(const Duration(seconds: 30)),
            end: t0.add(const Duration(seconds: 40)),
          ),
        ],
      ));

      // All three are below the 2-minute threshold; expect a single
      // emitted row with all three as briefs.
      expect(result, hasLength(1));
      expect(result[0].briefVisitors.map((v) => v.memberId).toSet(),
          {'a', 'b', 'c'});
    });

    test(
        'same-member tied handoff: A1 ends at T, A2 starts at T '
        '(different session ids) → merged period covers both, '
        'isOpenEnded reflects A2', () {
      // Codex P1 #2 fix-up: the snapshot-refresh predicate previously
      // checked only the active MEMBER set. A same-member tied
      // transition (A1 ends, A2 starts at the same instant for the
      // same member) kept stale activeSessionIds and hasOpenSession
      // because the active member set didn't change.
      //
      // Post-fix: the snapshot refreshes at the tied batch, so the
      // sweep emits two raw periods. The same-member merge step in
      // _collapseAndAnnotate folds them into a single visible period
      // whose sessionIds union both contributors and whose
      // isOpenEnded reflects the LATER session (A2, open).
      final t0 = DateTime(2026, 4, 1, 10);
      final t1 = DateTime(2026, 4, 1, 11);
      final t2 = DateTime(2026, 4, 1, 13);

      final result = deriveMaximalPeriods(_input(
        sessions: [
          // First session for member 'a': closes at t1.
          _s(id: 'a1', memberId: 'a', start: t0, end: t1),
          // Second session for member 'a': starts at the same instant
          // t1 (tied batch) and is OPEN (still ongoing).
          _s(id: 'a2', memberId: 'a', start: t1, end: null),
        ],
        rangeStart: DateTime(2026, 4, 1),
        rangeEnd: t2,
        now: t2,
      ));

      // One merged period covering both halves. Without the snapshot
      // refresh fix, the merged period would still appear but its
      // sessionIds would only contain a1 (because the second raw
      // period's sessionIds snapshot was never updated).
      expect(result, hasLength(1));
      final merged = result.single;
      expect(merged.activeMembers, ['a']);
      expect(merged.sessionIds.toSet(), {'a1', 'a2'},
          reason:
              'merged same-member period must include BOTH contributing '
              'session ids — a2 was missing pre-fix because the snapshot '
              'never refreshed at the tied batch');
      expect(merged.isOpenEnded, isTrue,
          reason:
              'merged period inherits a2\'s open-ended state — pre-fix, '
              'hasOpenSession was stale and the live timer was missing');
    });

    test(
        'same-member tied handoff: both closed → merged period unions '
        'sessionIds and stays closed', () {
      // Variant: both sides closed, ensuring the snapshot still
      // refreshes when only sessionIds change (the symmetric case)
      // and the merged period correctly stays closed.
      final t0 = DateTime(2026, 4, 1, 10);
      final t1 = DateTime(2026, 4, 1, 11);
      final t2 = DateTime(2026, 4, 1, 12);

      final result = deriveMaximalPeriods(_input(sessions: [
        _s(id: 'a1', memberId: 'a', start: t0, end: t1),
        _s(id: 'a2', memberId: 'a', start: t1, end: t2),
      ]));

      // Same-member merge folds the two raw periods into one.
      expect(result, hasLength(1));
      final merged = result.single;
      expect(merged.activeMembers, ['a']);
      expect(merged.sessionIds.toSet(), {'a1', 'a2'},
          reason:
              'merged period must include both contributing session ids');
      expect(merged.start, t0);
      expect(merged.end, t2);
      expect(merged.isOpenEnded, isFalse,
          reason: 'both sessions closed → merged period stays closed');
    });

    test(
        'all-short input with an OPEN current period does not collapse '
        'into a Unknown row', () {
      // Codex P2 fix: a just-started current front (under 2 minutes,
      // the ephemeral threshold) used to land in the all-short
      // shortcut, which zeroed out activeMembers and rendered as
      // "Unknown". The fix skips the all-short collapse when any raw
      // period has an open session.
      final now = DateTime(2026, 4, 1, 12);
      // Five short historical periods (each well under 2 min).
      final sessions = <FrontingSession>[];
      for (var i = 0; i < 5; i++) {
        final start = now.subtract(Duration(minutes: 30 - i * 5));
        sessions.add(_s(
          id: 'h$i',
          memberId: 'h$i',
          start: start,
          end: start.add(const Duration(seconds: 30)),
        ));
      }
      // One open current period under 2 min: started 30s ago, no end.
      sessions.add(_s(
        id: 'current',
        memberId: 'now',
        start: now.subtract(const Duration(seconds: 30)),
        end: null,
      ));

      final result = deriveMaximalPeriods(_input(
        sessions: sessions,
        rangeStart: now.subtract(const Duration(hours: 1)),
        rangeEnd: now,
        now: now,
      ));

      // The open current period should be present as its own row
      // with activeMembers = ['now'], NOT collapsed into a brief-only
      // combined row.
      expect(result, isNotEmpty);
      final current =
          result.where((p) => p.activeMembers.contains('now')).toList();
      expect(current, isNotEmpty,
          reason: 'open current period must not collapse to all-briefs');
      expect(current.first.isOpenEnded, isTrue,
          reason: 'the open current period must render the live timer');
    });

    test(
        'all-short input with all closed sessions still emits one '
        'combined row (existing behavior preserved)', () {
      // Regression-pin: the all-short shortcut still fires when no
      // session is open. (Same as the existing "cascading shorts"
      // test, but expressed as a property of the open-guard fix.)
      final t0 = DateTime(2026, 4, 1, 10);
      final result = deriveMaximalPeriods(_input(
        sessions: [
          _s(
            id: 's1',
            memberId: 'a',
            start: t0,
            end: t0.add(const Duration(seconds: 10)),
          ),
          _s(
            id: 's2',
            memberId: 'b',
            start: t0.add(const Duration(seconds: 15)),
            end: t0.add(const Duration(seconds: 25)),
          ),
        ],
      ));
      expect(result, hasLength(1));
      expect(result[0].activeMembers, isEmpty,
          reason:
              'all-closed-short still collapses to brief-visitors-only row');
      expect(result[0].briefVisitors.map((v) => v.memberId).toSet(),
          {'a', 'b'});
      expect(result[0].isOpenEnded, isFalse);
    });

    test('input permutation invariance', () {
      // Property: shuffling the input shouldn't change the output stream.
      final t0 = DateTime(2026, 4, 1, 10);
      final t1 = DateTime(2026, 4, 1, 11);
      final t2 = DateTime(2026, 4, 1, 12);
      final t3 = DateTime(2026, 4, 1, 13);
      final sessions = [
        _s(id: 'a', memberId: 'a', start: t0, end: t3),
        _s(id: 'b', memberId: 'b', start: t1, end: t2),
        _s(id: 'c', memberId: 'c', start: t1, end: t3),
      ];
      final r1 = deriveMaximalPeriods(_input(sessions: sessions));
      final r2 =
          deriveMaximalPeriods(_input(sessions: sessions.reversed.toList()));
      expect(r1.length, r2.length);
      for (var i = 0; i < r1.length; i++) {
        expect(r1[i].start, r2[i].start);
        expect(r1[i].end, r2[i].end);
        expect(r1[i].activeMembers.toSet(), r2[i].activeMembers.toSet());
      }
    });
  });
}
