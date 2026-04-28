// test/core/services/session_lifecycle_service_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/constants/fronting_namespaces.dart';
import 'package:prism_plurality/core/services/session_lifecycle_service.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart';
import '../../helpers/fake_repositories.dart';

FrontingSession _session({
  required String id,
  required DateTime start,
  DateTime? end,
  String? memberId,
  String? notes,
  SessionType sessionType = SessionType.normal,
}) {
  return FrontingSession(
    id: id,
    startTime: start,
    endTime: end,
    memberId: memberId,
    notes: notes,
    sessionType: sessionType,
  );
}

void main() {
  const service = SessionLifecycleService();

  // ── getDeleteOptions ─────────────────────────

  group('getDeleteOptions', () {
    test('active session with previous offers makePreviousActive + delete', () {
      final previous = _session(
        id: 'prev',
        start: DateTime(2026, 1, 1, 10),
        end: DateTime(2026, 1, 1, 12),
        memberId: 'alice',
      );
      final active = _session(
        id: 'active',
        start: DateTime(2026, 1, 1, 12),
        memberId: 'bob',
      );

      final ctx = service.getDeleteOptions(active, [previous, active]);
      expect(ctx.availableOptions, [
        DeleteOption.makePreviousActive,
        DeleteOption.delete,
      ]);
      expect(ctx.previous?.id, 'prev');
      expect(ctx.next, isNull);
    });

    test('active session with no previous offers only delete', () {
      final active = _session(
        id: 'active',
        start: DateTime(2026, 1, 1, 12),
        memberId: 'bob',
      );

      final ctx = service.getDeleteOptions(active, [active]);
      expect(ctx.availableOptions, [DeleteOption.delete]);
    });

    test('ended session with both neighbors offers extend both + delete', () {
      final prev = _session(
        id: 'prev',
        start: DateTime(2026, 1, 1, 10),
        end: DateTime(2026, 1, 1, 12),
        memberId: 'alice',
      );
      final target = _session(
        id: 'target',
        start: DateTime(2026, 1, 1, 12),
        end: DateTime(2026, 1, 1, 14),
        memberId: 'bob',
      );
      final next = _session(
        id: 'next',
        start: DateTime(2026, 1, 1, 14),
        end: DateTime(2026, 1, 1, 16),
        memberId: 'carol',
      );

      final ctx = service.getDeleteOptions(target, [prev, target, next]);
      expect(ctx.availableOptions, [
        DeleteOption.extendPrevious,
        DeleteOption.extendNext,
        DeleteOption.delete,
      ]);
    });

    test('ended session with previous only offers extendPrevious + delete', () {
      final prev = _session(
        id: 'prev',
        start: DateTime(2026, 1, 1, 10),
        end: DateTime(2026, 1, 1, 12),
        memberId: 'alice',
      );
      final target = _session(
        id: 'target',
        start: DateTime(2026, 1, 1, 12),
        end: DateTime(2026, 1, 1, 14),
        memberId: 'bob',
      );

      final ctx = service.getDeleteOptions(target, [prev, target]);
      expect(ctx.availableOptions, [
        DeleteOption.extendPrevious,
        DeleteOption.delete,
      ]);
    });

    test('ended session with next only offers extendNext + delete', () {
      final target = _session(
        id: 'target',
        start: DateTime(2026, 1, 1, 12),
        end: DateTime(2026, 1, 1, 14),
        memberId: 'bob',
      );
      final next = _session(
        id: 'next',
        start: DateTime(2026, 1, 1, 14),
        end: DateTime(2026, 1, 1, 16),
        memberId: 'carol',
      );

      final ctx = service.getDeleteOptions(target, [target, next]);
      expect(ctx.availableOptions, [
        DeleteOption.extendNext,
        DeleteOption.delete,
      ]);
    });

    test('only session offers just delete', () {
      final target = _session(
        id: 'target',
        start: DateTime(2026, 1, 1, 12),
        end: DateTime(2026, 1, 1, 14),
        memberId: 'bob',
      );

      final ctx = service.getDeleteOptions(target, [target]);
      expect(ctx.availableOptions, [DeleteOption.delete]);
    });

    test('sleep session only offers delete, even with neighbors', () {
      final previous = _session(
        id: 'prev',
        start: DateTime(2026, 1, 1, 8),
        end: DateTime(2026, 1, 1, 10),
        memberId: 'alice',
      );
      final sleep = _session(
        id: 'sleep',
        start: DateTime(2026, 1, 1, 10),
        end: DateTime(2026, 1, 1, 14),
        memberId: null,
        sessionType: SessionType.sleep,
      );
      final next = _session(
        id: 'next',
        start: DateTime(2026, 1, 1, 14),
        end: DateTime(2026, 1, 1, 16),
        memberId: 'bob',
      );

      final ctx = service.getDeleteOptions(sleep, [previous, sleep, next]);
      expect(ctx.availableOptions, [DeleteOption.delete]);
      expect(ctx.previous?.id, isNull);
      expect(ctx.next?.id, isNull);
    });
  });

  // ── evaluateQuickSwitch ──────────────────────

  group('evaluateQuickSwitch', () {
    test('switch within threshold returns correctExisting', () {
      final now = DateTime(2026, 1, 1, 12, 0, 20);
      final session = _session(
        id: 'a',
        start: DateTime(2026, 1, 1, 12, 0, 0),
        memberId: 'alice',
      );

      final action = service.evaluateQuickSwitch(
        session,
        thresholdSeconds: 30,
        now: now,
      );

      expect(action, QuickSwitchAction.correctExisting);
    });

    test('switch after threshold returns createNew', () {
      final now = DateTime(2026, 1, 1, 12, 1, 0);
      final session = _session(
        id: 'a',
        start: DateTime(2026, 1, 1, 12, 0, 0),
        memberId: 'alice',
      );

      final action = service.evaluateQuickSwitch(
        session,
        thresholdSeconds: 30,
        now: now,
      );

      expect(action, QuickSwitchAction.createNew);
    });

    test('threshold of 0 always returns createNew', () {
      final now = DateTime(2026, 1, 1, 12, 0, 0);
      final session = _session(
        id: 'a',
        start: DateTime(2026, 1, 1, 12, 0, 0),
        memberId: 'alice',
      );

      final action = service.evaluateQuickSwitch(
        session,
        thresholdSeconds: 0,
        now: now,
      );

      expect(action, QuickSwitchAction.createNew);
    });

    test('null session returns createNew', () {
      final action = service.evaluateQuickSwitch(null);
      expect(action, QuickSwitchAction.createNew);
    });

    test('ended session returns createNew', () {
      final session = _session(
        id: 'a',
        start: DateTime(2026, 1, 1, 12, 0, 0),
        end: DateTime(2026, 1, 1, 12, 5, 0),
        memberId: 'alice',
      );

      final action = service.evaluateQuickSwitch(session, thresholdSeconds: 30);

      expect(action, QuickSwitchAction.createNew);
    });

    test('switch at exactly threshold boundary returns correctExisting', () {
      final now = DateTime(2026, 1, 1, 12, 0, 30);
      final session = _session(
        id: 'a',
        start: DateTime(2026, 1, 1, 12, 0, 0),
        memberId: 'alice',
      );

      final action = service.evaluateQuickSwitch(
        session,
        thresholdSeconds: 30,
        now: now,
      );

      expect(action, QuickSwitchAction.correctExisting);
    });
  });

  // ── Existing validation tests (carried over, expanded) ───

  group('validateTimeRange', () {
    test('valid range returns empty', () {
      final errors = service.validateTimeRange(
        DateTime(2026, 1, 1, 10),
        DateTime(2026, 1, 1, 12),
      );
      expect(errors, isEmpty);
    });

    test('start after end returns error', () {
      final errors = service.validateTimeRange(
        DateTime(2026, 1, 1, 14),
        DateTime(2026, 1, 1, 12),
      );
      expect(errors, contains(SessionValidationError.startAfterEnd));
    });

    test('future start returns error', () {
      final errors = service.validateTimeRange(DateTime(2099, 1, 1), null);
      expect(errors, contains(SessionValidationError.futureSession));
    });

    test('null end time (active session) is valid', () {
      final errors = service.validateTimeRange(DateTime(2026, 1, 1, 10), null);
      expect(errors, isEmpty);
    });

    test('zero duration returns error', () {
      final t = DateTime(2026, 1, 1, 10);
      final errors = service.validateTimeRange(t, t);
      expect(errors, contains(SessionValidationError.invalidDuration));
    });
  });

  group('delete execution', () {
    test('sleep delete does not create an unknown filler session', () async {
      final repo = FakeFrontingSessionRepository();
      final sleep = _session(
        id: 'sleep',
        start: DateTime(2026, 1, 2, 10),
        end: DateTime(2026, 1, 2, 12),
        memberId: null,
        sessionType: SessionType.sleep,
      );
      final preservedFronting = _session(
        id: 'front',
        start: DateTime(2026, 1, 2, 8),
        end: DateTime(2026, 1, 2, 9),
        memberId: 'alice',
      );
      await repo.createSession(preservedFronting);
      await repo.createSession(sleep);

      final ctx = service.getDeleteOptions(sleep, [preservedFronting, sleep]);
      await service.executeDelete(DeleteOption.delete, ctx, repo);

      expect(repo.deletedIds, contains('sleep'));
      expect(
        repo.sessions.any(
          (session) => session.memberId == null && session.id != 'sleep',
        ),
        isFalse,
        reason: 'sleep delete should not synthesize an unknown fronting filler',
      );
      expect(repo.sessions, hasLength(1));
      expect(repo.sessions.single.id, 'front');
    });
  });

  group('detectOverlaps', () {
    test('overlapping sessions detected', () {
      final a = _session(
        id: 'a',
        start: DateTime(2026, 1, 1, 10),
        end: DateTime(2026, 1, 1, 13),
      );
      final b = _session(
        id: 'b',
        start: DateTime(2026, 1, 1, 12),
        end: DateTime(2026, 1, 1, 15),
      );

      final overlaps = service.detectOverlaps(a, [a, b]);
      expect(overlaps, hasLength(1));
      expect(overlaps.first.id, 'b');
    });

    test('non-overlapping sessions return empty', () {
      final a = _session(
        id: 'a',
        start: DateTime(2026, 1, 1, 10),
        end: DateTime(2026, 1, 1, 12),
      );
      final b = _session(
        id: 'b',
        start: DateTime(2026, 1, 1, 12),
        end: DateTime(2026, 1, 1, 14),
      );

      final overlaps = service.detectOverlaps(a, [a, b]);
      expect(overlaps, isEmpty);
    });

    test('overlapping sleep and fronting sessions are NOT detected', () {
      final fronting = _session(
        id: 'fronting',
        start: DateTime(2026, 1, 1, 10),
        end: DateTime(2026, 1, 1, 14),
        memberId: 'alice',
      );
      final sleep = _session(
        id: 'sleep',
        start: DateTime(2026, 1, 1, 12),
        end: DateTime(2026, 1, 1, 16),
        sessionType: SessionType.sleep,
      );

      final overlaps = service.detectOverlaps(fronting, [fronting, sleep]);
      expect(overlaps, isEmpty,
          reason: 'cross-type overlaps should be ignored');
    });
  });

  group('trimOverlap', () {
    test('does nothing when session types differ', () async {
      final repo = FakeFrontingSessionRepository();
      final fronting = _session(
        id: 'fronting',
        start: DateTime(2026, 1, 1, 10),
        end: DateTime(2026, 1, 1, 14),
        memberId: 'alice',
      );
      final sleep = _session(
        id: 'sleep',
        start: DateTime(2026, 1, 1, 12),
        end: DateTime(2026, 1, 1, 16),
        sessionType: SessionType.sleep,
      );
      await repo.createSession(fronting);
      await repo.createSession(sleep);

      await service.trimOverlap(fronting, sleep, repo);

      final afterFronting = await repo.getSessionById('fronting');
      final afterSleep = await repo.getSessionById('sleep');
      expect(afterFronting!.endTime, DateTime(2026, 1, 1, 14));
      expect(afterSleep!.startTime, DateTime(2026, 1, 1, 12));
    });
  });

  group('mergeAdjacent', () {
    test('sleep target returns unchanged without merging', () async {
      final repo = FakeFrontingSessionRepository();
      final sleep = _session(
        id: 'sleep',
        start: DateTime(2026, 1, 1, 22),
        end: DateTime(2026, 1, 2, 6),
        sessionType: SessionType.sleep,
      );
      final adjacent = _session(
        id: 'adj',
        start: DateTime(2026, 1, 2, 6),
        end: DateTime(2026, 1, 2, 8),
        sessionType: SessionType.sleep,
      );
      await repo.createSession(sleep);
      await repo.createSession(adjacent);

      final result = await service.mergeAdjacent(sleep, [adjacent], repo);

      expect(result.id, 'sleep');
      expect(result.startTime, sleep.startTime);
      expect(result.endTime, sleep.endTime);
      // Adjacent session should NOT be deleted
      expect(repo.sessions, hasLength(2));
    });

    test('fronting target ignores sleep sessions in merge list', () async {
      final repo = FakeFrontingSessionRepository();
      final fronting = _session(
        id: 'front',
        start: DateTime(2026, 1, 1, 10),
        end: DateTime(2026, 1, 1, 12),
        memberId: 'alice',
      );
      final sleep = _session(
        id: 'sleep',
        start: DateTime(2026, 1, 1, 12),
        end: DateTime(2026, 1, 1, 14),
        sessionType: SessionType.sleep,
      );
      await repo.createSession(fronting);
      await repo.createSession(sleep);

      final result = await service.mergeAdjacent(fronting, [sleep], repo);

      expect(result.id, 'front');
      expect(result.endTime, fronting.endTime);
      // Sleep session should NOT be deleted
      expect(repo.sessions, hasLength(2));
    });
  });

  // ── Unknown-sentinel filler paths (Bug 1 + Bug 2) ────
  //
  // After audit batch L, both delete-fill and fillGaps must route the
  // synthetic "we don't know who was fronting here" row through the Unknown
  // sentinel member rather than writing memberId == null.

  group('executeDelete fills with Unknown sentinel', () {
    test('writes memberId == unknownSentinelMemberId, NOT null', () async {
      final memberRepo = FakeMemberRepository();
      final repo = FakeFrontingSessionRepository();
      final service = SessionLifecycleService(memberRepository: memberRepo);

      final target = _session(
        id: 'target',
        start: DateTime(2026, 1, 1, 12),
        end: DateTime(2026, 1, 1, 14),
        memberId: 'alice',
      );
      await repo.createSession(target);

      final ctx = service.getDeleteOptions(target, [target]);
      final fillerId =
          await service.executeDelete(DeleteOption.delete, ctx, repo);

      expect(fillerId, isNotNull);
      final filler = repo.sessions.firstWhere((s) => s.id == fillerId);
      expect(filler.memberId, equals(unknownSentinelMemberId));
      expect(filler.memberId, isNot(isNull));

      // The sentinel member was lazily created.
      final sentinel = await memberRepo.getMemberById(unknownSentinelMemberId);
      expect(sentinel, isNotNull);
    });

    test('throws StateError when sentinel filler needed but no '
        'MemberRepository wired, and leaves original session intact',
        () async {
      const service = SessionLifecycleService();
      final repo = FakeFrontingSessionRepository();

      final target = _session(
        id: 'target',
        start: DateTime(2026, 1, 1, 12),
        end: DateTime(2026, 1, 1, 14),
        memberId: 'alice',
      );
      await repo.createSession(target);

      final ctx = service.getDeleteOptions(target, [target]);
      await expectLater(
        () => service.executeDelete(DeleteOption.delete, ctx, repo),
        throwsA(isA<StateError>()),
      );

      // Preflight runs BEFORE the delete: original row must still be there
      // and no filler should have been written (partial-mutation guard).
      expect(repo.deletedIds, isNot(contains('target')));
      expect(repo.sessions, hasLength(1));
      expect(repo.sessions.single.id, 'target');
    });
  });

  group('fillGaps fills with Unknown sentinel', () {
    test('writes memberId == unknownSentinelMemberId, NOT null', () async {
      final memberRepo = FakeMemberRepository();
      final repo = FakeFrontingSessionRepository();
      final service = SessionLifecycleService(memberRepository: memberRepo);

      final before = _session(
        id: 'before',
        start: DateTime(2026, 1, 1, 8),
        end: DateTime(2026, 1, 1, 9),
        memberId: 'alice',
      );
      final after = _session(
        id: 'after',
        start: DateTime(2026, 1, 1, 11),
        end: DateTime(2026, 1, 1, 12),
        memberId: 'bob',
      );

      final gap = GapInfo(
        startTime: DateTime(2026, 1, 1, 9),
        endTime: DateTime(2026, 1, 1, 11),
        beforeSession: before,
        afterSession: after,
      );

      await service.fillGaps([gap], repo);

      expect(repo.sessions, hasLength(1));
      final filler = repo.sessions.single;
      expect(filler.memberId, equals(unknownSentinelMemberId));
      expect(filler.memberId, isNot(isNull));

      // The sentinel member was lazily created.
      final sentinel = await memberRepo.getMemberById(unknownSentinelMemberId);
      expect(sentinel, isNotNull);
    });

    test('empty gap list is a no-op (does not require MemberRepository)',
        () async {
      const service = SessionLifecycleService();
      final repo = FakeFrontingSessionRepository();

      // Should NOT throw — sentinel ensure is gated on having gaps to fill.
      await service.fillGaps(const [], repo);

      expect(repo.sessions, isEmpty);
    });

    test('throws StateError when gaps need filling but no '
        'MemberRepository wired, and writes nothing', () async {
      const service = SessionLifecycleService();
      final repo = FakeFrontingSessionRepository();

      final before = _session(
        id: 'before',
        start: DateTime(2026, 1, 1, 8),
        end: DateTime(2026, 1, 1, 9),
        memberId: 'alice',
      );
      final after = _session(
        id: 'after',
        start: DateTime(2026, 1, 1, 11),
        end: DateTime(2026, 1, 1, 12),
        memberId: 'bob',
      );
      final gap = GapInfo(
        startTime: DateTime(2026, 1, 1, 9),
        endTime: DateTime(2026, 1, 1, 11),
        beforeSession: before,
        afterSession: after,
      );

      await expectLater(
        () => service.fillGaps([gap], repo),
        throwsA(isA<StateError>()),
      );

      // Sentinel ensure happens BEFORE the first createSession — no
      // partial filler row should have leaked through.
      expect(repo.sessions, isEmpty);
    });
  });
}
