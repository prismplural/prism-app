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

    test('avatar stack ordering: tiebreak by selection order', () {
      // A and B start at the same instant. Tiebreak is arrivalIndex:
      // we add events in the input order, but the sort key is
      // memberId-alphabetical inside a tied batch; verify stable.
      final t0 = DateTime(2026, 4, 1, 10);
      final t1 = DateTime(2026, 4, 1, 11);
      final result = deriveMaximalPeriods(_input(sessions: [
        _s(id: 's1', memberId: 'b', start: t0, end: t1),
        _s(id: 's2', memberId: 'a', start: t0, end: t1),
      ]));
      expect(result, hasLength(1));
      // Both have firstStart = t0; tiebreak is arrival order (alphabetical
      // by memberId for in-batch events). 'a' < 'b'.
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
