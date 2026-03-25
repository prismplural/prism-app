import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/services/session_lifecycle_service.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart';

import '../helpers/fake_repositories.dart';

// ── Helpers ──────────────────────────────────────────────────────────────────

FrontingSession _session({
  String id = 'session-1',
  required DateTime startTime,
  DateTime? endTime,
  String? memberId = 'member-1',
  List<String> coFronterIds = const [],
  String? notes,
  FrontConfidence? confidence,
}) {
  return FrontingSession(
    id: id,
    startTime: startTime,
    endTime: endTime,
    memberId: memberId,
    coFronterIds: coFronterIds,
    notes: notes,
    confidence: confidence,
  );
}

void main() {
  late SessionLifecycleService service;

  setUp(() {
    service = const SessionLifecycleService();
  });

  // ════════════════════════════════════════════════════════════════════════════
  // Quick-switch evaluation
  // ════════════════════════════════════════════════════════════════════════════

  group('evaluateQuickSwitch', () {
    test('returns createNew when current session is null', () {
      final action = service.evaluateQuickSwitch(null);
      expect(action, QuickSwitchAction.createNew);
    });

    test('returns createNew when current session is not active (has endTime)',
        () {
      final session = _session(
        startTime: DateTime.now().subtract(const Duration(seconds: 10)),
        endTime: DateTime.now(),
      );
      final action = service.evaluateQuickSwitch(session);
      expect(action, QuickSwitchAction.createNew);
    });

    test('returns correctExisting when session started within threshold', () {
      final now = DateTime(2025, 1, 1, 12, 0, 0);
      final session = _session(
        startTime: now.subtract(const Duration(seconds: 15)),
        endTime: null, // active
      );
      final action = service.evaluateQuickSwitch(
        session,
        thresholdSeconds: 30,
        now: now,
      );
      expect(action, QuickSwitchAction.correctExisting);
    });

    test('returns createNew when session started outside threshold', () {
      final now = DateTime(2025, 1, 1, 12, 0, 0);
      final session = _session(
        startTime: now.subtract(const Duration(seconds: 60)),
        endTime: null,
      );
      final action = service.evaluateQuickSwitch(
        session,
        thresholdSeconds: 30,
        now: now,
      );
      expect(action, QuickSwitchAction.createNew);
    });

    test('returns correctExisting when exactly at threshold boundary', () {
      final now = DateTime(2025, 1, 1, 12, 0, 0);
      final session = _session(
        startTime: now.subtract(const Duration(seconds: 30)),
        endTime: null,
      );
      final action = service.evaluateQuickSwitch(
        session,
        thresholdSeconds: 30,
        now: now,
      );
      expect(action, QuickSwitchAction.correctExisting);
    });

    test('returns createNew when threshold is 0 (disabled)', () {
      final now = DateTime(2025, 1, 1, 12, 0, 0);
      final session = _session(
        startTime: now.subtract(const Duration(seconds: 1)),
        endTime: null,
      );
      final action = service.evaluateQuickSwitch(
        session,
        thresholdSeconds: 0,
        now: now,
      );
      expect(action, QuickSwitchAction.createNew);
    });
  });

  // ════════════════════════════════════════════════════════════════════════════
  // Time range validation
  // ════════════════════════════════════════════════════════════════════════════

  group('validateTimeRange', () {
    test('returns empty list for valid range', () {
      final start = DateTime.now().subtract(const Duration(hours: 1));
      final end = DateTime.now();
      final errors = service.validateTimeRange(start, end);
      expect(errors, isEmpty);
    });

    test('returns startAfterEnd when start is after end', () {
      final start = DateTime(2025, 1, 1, 13, 0);
      final end = DateTime(2025, 1, 1, 12, 0);
      final errors = service.validateTimeRange(start, end);
      expect(errors, contains(SessionValidationError.startAfterEnd));
    });

    test('returns futureSession when start is in the far future', () {
      final start = DateTime.now().add(const Duration(hours: 1));
      final errors = service.validateTimeRange(start, null);
      expect(errors, contains(SessionValidationError.futureSession));
    });

    test('allows start slightly in the future (within 1min buffer)', () {
      final start = DateTime.now().add(const Duration(seconds: 30));
      final errors = service.validateTimeRange(start, null);
      expect(errors, isNot(contains(SessionValidationError.futureSession)));
    });

    test('returns invalidDuration for zero-length session', () {
      final time = DateTime(2025, 1, 1, 12, 0);
      final errors = service.validateTimeRange(time, time);
      expect(errors, contains(SessionValidationError.invalidDuration));
    });

    test('returns empty for null end time (active session)', () {
      final start = DateTime.now().subtract(const Duration(minutes: 5));
      final errors = service.validateTimeRange(start, null);
      expect(errors, isEmpty);
    });

    test('can return multiple errors simultaneously', () {
      // Start after end AND in far future
      final start = DateTime.now().add(const Duration(hours: 2));
      final end = DateTime.now().add(const Duration(hours: 1));
      final errors = service.validateTimeRange(start, end);
      expect(errors, contains(SessionValidationError.startAfterEnd));
      expect(errors, contains(SessionValidationError.futureSession));
    });
  });

  // ════════════════════════════════════════════════════════════════════════════
  // Overlap detection
  // ════════════════════════════════════════════════════════════════════════════

  group('detectOverlaps', () {
    test('detects overlapping session', () {
      final s1 = _session(
        id: 'a',
        startTime: DateTime(2025, 1, 1, 10, 0),
        endTime: DateTime(2025, 1, 1, 11, 0),
      );
      final s2 = _session(
        id: 'b',
        startTime: DateTime(2025, 1, 1, 10, 30),
        endTime: DateTime(2025, 1, 1, 11, 30),
      );
      final overlaps = service.detectOverlaps(s1, [s1, s2]);
      expect(overlaps, hasLength(1));
      expect(overlaps.first.id, 'b');
    });

    test('does not flag non-overlapping sessions', () {
      final s1 = _session(
        id: 'a',
        startTime: DateTime(2025, 1, 1, 10, 0),
        endTime: DateTime(2025, 1, 1, 11, 0),
      );
      final s2 = _session(
        id: 'b',
        startTime: DateTime(2025, 1, 1, 11, 0),
        endTime: DateTime(2025, 1, 1, 12, 0),
      );
      final overlaps = service.detectOverlaps(s1, [s1, s2]);
      expect(overlaps, isEmpty);
    });

    test('does not count the session against itself', () {
      final s1 = _session(
        id: 'a',
        startTime: DateTime(2025, 1, 1, 10, 0),
        endTime: DateTime(2025, 1, 1, 11, 0),
      );
      final overlaps = service.detectOverlaps(s1, [s1]);
      expect(overlaps, isEmpty);
    });
  });

  // ════════════════════════════════════════════════════════════════════════════
  // Delete options
  // ════════════════════════════════════════════════════════════════════════════

  group('getDeleteOptions', () {
    test('active session with previous: offers makePreviousActive and delete',
        () {
      final prev = _session(
        id: 'prev',
        startTime: DateTime(2025, 1, 1, 9, 0),
        endTime: DateTime(2025, 1, 1, 10, 0),
      );
      final active = _session(
        id: 'current',
        startTime: DateTime(2025, 1, 1, 10, 0),
        endTime: null, // active
      );

      final ctx = service.getDeleteOptions(active, [prev, active]);
      expect(ctx.availableOptions, contains(DeleteOption.makePreviousActive));
      expect(ctx.availableOptions, contains(DeleteOption.delete));
      // Should NOT offer extendPrevious/extendNext (those are for ended sessions)
      expect(
          ctx.availableOptions, isNot(contains(DeleteOption.extendPrevious)));
    });

    test('ended session between two others: offers extendPrevious, extendNext, delete',
        () {
      final prev = _session(
        id: 'prev',
        startTime: DateTime(2025, 1, 1, 9, 0),
        endTime: DateTime(2025, 1, 1, 10, 0),
      );
      final mid = _session(
        id: 'mid',
        startTime: DateTime(2025, 1, 1, 10, 0),
        endTime: DateTime(2025, 1, 1, 11, 0),
      );
      final next = _session(
        id: 'next',
        startTime: DateTime(2025, 1, 1, 11, 0),
        endTime: DateTime(2025, 1, 1, 12, 0),
      );

      final ctx = service.getDeleteOptions(mid, [prev, mid, next]);
      expect(ctx.availableOptions, contains(DeleteOption.extendPrevious));
      expect(ctx.availableOptions, contains(DeleteOption.extendNext));
      expect(ctx.availableOptions, contains(DeleteOption.delete));
      expect(ctx.previous?.id, 'prev');
      expect(ctx.next?.id, 'next');
    });

    test('single ended session: only offers delete', () {
      final solo = _session(
        id: 'solo',
        startTime: DateTime(2025, 1, 1, 10, 0),
        endTime: DateTime(2025, 1, 1, 11, 0),
      );

      final ctx = service.getDeleteOptions(solo, [solo]);
      expect(ctx.availableOptions, equals([DeleteOption.delete]));
      expect(ctx.previous, isNull);
      expect(ctx.next, isNull);
    });

    test('first session (no previous): offers extendNext and delete', () {
      final first = _session(
        id: 'first',
        startTime: DateTime(2025, 1, 1, 10, 0),
        endTime: DateTime(2025, 1, 1, 11, 0),
      );
      final second = _session(
        id: 'second',
        startTime: DateTime(2025, 1, 1, 11, 0),
        endTime: DateTime(2025, 1, 1, 12, 0),
      );

      final ctx = service.getDeleteOptions(first, [first, second]);
      expect(ctx.availableOptions, isNot(contains(DeleteOption.extendPrevious)));
      expect(ctx.availableOptions, contains(DeleteOption.extendNext));
      expect(ctx.availableOptions, contains(DeleteOption.delete));
    });

    test('active session with no previous: only offers delete', () {
      final active = _session(
        id: 'active',
        startTime: DateTime(2025, 1, 1, 10, 0),
        endTime: null,
      );
      final ctx = service.getDeleteOptions(active, [active]);
      expect(ctx.availableOptions, equals([DeleteOption.delete]));
    });
  });

  // ════════════════════════════════════════════════════════════════════════════
  // Overlap trimming
  // ════════════════════════════════════════════════════════════════════════════

  group('trimOverlap', () {
    late FakeFrontingSessionRepository repo;

    setUp(() {
      repo = FakeFrontingSessionRepository();
    });

    test('trims end of overlapping session that started first', () async {
      final edited = _session(
        id: 'edited',
        startTime: DateTime(2025, 1, 1, 10, 30),
        endTime: DateTime(2025, 1, 1, 11, 30),
      );
      final overlapping = _session(
        id: 'overlap',
        startTime: DateTime(2025, 1, 1, 10, 0),
        endTime: DateTime(2025, 1, 1, 11, 0),
      );
      repo.sessions.add(overlapping);

      await service.trimOverlap(edited, overlapping, repo);
      final updated = repo.sessions.firstWhere((s) => s.id == 'overlap');
      expect(updated.endTime, DateTime(2025, 1, 1, 10, 30));
    });

    test('trims start of overlapping session that started during edited',
        () async {
      final edited = _session(
        id: 'edited',
        startTime: DateTime(2025, 1, 1, 10, 0),
        endTime: DateTime(2025, 1, 1, 11, 0),
      );
      final overlapping = _session(
        id: 'overlap',
        startTime: DateTime(2025, 1, 1, 10, 30),
        endTime: DateTime(2025, 1, 1, 12, 0),
      );
      repo.sessions.add(overlapping);

      await service.trimOverlap(edited, overlapping, repo);
      final updated = repo.sessions.firstWhere((s) => s.id == 'overlap');
      expect(updated.startTime, DateTime(2025, 1, 1, 11, 0));
    });

    test('deletes overlapping session if trimming would make it zero duration',
        () async {
      final edited = _session(
        id: 'edited',
        startTime: DateTime(2025, 1, 1, 10, 0),
        endTime: DateTime(2025, 1, 1, 11, 0),
      );
      final overlapping = _session(
        id: 'overlap',
        startTime: DateTime(2025, 1, 1, 10, 0), // same start
        endTime: DateTime(2025, 1, 1, 11, 0), // same end
      );
      repo.sessions.add(overlapping);

      await service.trimOverlap(edited, overlapping, repo);
      expect(repo.deletedIds, contains('overlap'));
    });
  });

  // ════════════════════════════════════════════════════════════════════════════
  // Adjacent session merging
  // ════════════════════════════════════════════════════════════════════════════

  group('mergeAdjacent', () {
    late FakeFrontingSessionRepository repo;

    setUp(() {
      repo = FakeFrontingSessionRepository();
    });

    test('extends target to span all merged sessions', () async {
      final target = _session(
        id: 'target',
        startTime: DateTime(2025, 1, 1, 11, 0),
        endTime: DateTime(2025, 1, 1, 12, 0),
        memberId: 'member-1',
      );
      final earlier = _session(
        id: 'earlier',
        startTime: DateTime(2025, 1, 1, 10, 0),
        endTime: DateTime(2025, 1, 1, 11, 0),
        memberId: 'member-1',
      );
      repo.sessions.addAll([target, earlier]);

      final result =
          await service.mergeAdjacent(target, [earlier], repo);
      expect(result.startTime, DateTime(2025, 1, 1, 10, 0));
      expect(result.endTime, DateTime(2025, 1, 1, 12, 0));
      expect(repo.deletedIds, contains('earlier'));
    });

    test('concatenates notes with pipe separator', () async {
      final target = _session(
        id: 'target',
        startTime: DateTime(2025, 1, 1, 11, 0),
        endTime: DateTime(2025, 1, 1, 12, 0),
        notes: 'Note A',
      );
      final other = _session(
        id: 'other',
        startTime: DateTime(2025, 1, 1, 10, 0),
        endTime: DateTime(2025, 1, 1, 11, 0),
        notes: 'Note B',
      );
      repo.sessions.addAll([target, other]);

      final result = await service.mergeAdjacent(target, [other], repo);
      expect(result.notes, 'Note A | Note B');
    });

    test('sets endTime to null if any merged session is active', () async {
      final target = _session(
        id: 'target',
        startTime: DateTime(2025, 1, 1, 11, 0),
        endTime: DateTime(2025, 1, 1, 12, 0),
      );
      final activeSession = _session(
        id: 'active',
        startTime: DateTime(2025, 1, 1, 10, 0),
        endTime: null, // active
      );
      repo.sessions.addAll([target, activeSession]);

      final result =
          await service.mergeAdjacent(target, [activeSession], repo);
      expect(result.endTime, isNull);
    });

    test('skips empty notes', () async {
      final target = _session(
        id: 'target',
        startTime: DateTime(2025, 1, 1, 11, 0),
        endTime: DateTime(2025, 1, 1, 12, 0),
        notes: null,
      );
      final other = _session(
        id: 'other',
        startTime: DateTime(2025, 1, 1, 10, 0),
        endTime: DateTime(2025, 1, 1, 11, 0),
        notes: '',
      );
      repo.sessions.addAll([target, other]);

      final result = await service.mergeAdjacent(target, [other], repo);
      expect(result.notes, isNull);
    });
  });

  // ════════════════════════════════════════════════════════════════════════════
  // executeDelete
  // ════════════════════════════════════════════════════════════════════════════

  group('executeDelete', () {
    late FakeFrontingSessionRepository repo;

    setUp(() {
      repo = FakeFrontingSessionRepository();
    });

    test('makePreviousActive reopens previous session', () async {
      final prev = _session(
        id: 'prev',
        startTime: DateTime(2025, 1, 1, 9, 0),
        endTime: DateTime(2025, 1, 1, 10, 0),
      );
      final active = _session(
        id: 'current',
        startTime: DateTime(2025, 1, 1, 10, 0),
        endTime: null,
      );
      repo.sessions.addAll([prev, active]);

      final ctx = DeleteContext(
        session: active,
        previous: prev,
        next: null,
        availableOptions: [DeleteOption.makePreviousActive],
      );

      await service.executeDelete(DeleteOption.makePreviousActive, ctx, repo);
      expect(repo.deletedIds, contains('current'));
      final updatedPrev = repo.sessions.firstWhere((s) => s.id == 'prev');
      expect(updatedPrev.endTime, isNull); // reopened
    });

    test('delete with time range creates unknown fill session', () async {
      final session = _session(
        id: 'to-delete',
        startTime: DateTime(2025, 1, 1, 10, 0),
        endTime: DateTime(2025, 1, 1, 11, 0),
      );
      repo.sessions.add(session);

      final ctx = DeleteContext(
        session: session,
        previous: null,
        next: null,
        availableOptions: [DeleteOption.delete],
      );

      final unknownId =
          await service.executeDelete(DeleteOption.delete, ctx, repo);
      expect(unknownId, isNotNull);
      expect(repo.deletedIds, contains('to-delete'));
      final unknown = repo.sessions.firstWhere((s) => s.id == unknownId);
      expect(unknown.memberId, isNull);
      expect(unknown.startTime, DateTime(2025, 1, 1, 10, 0));
      expect(unknown.endTime, DateTime(2025, 1, 1, 11, 0));
    });

    test('extendPrevious stretches previous to cover deleted session end',
        () async {
      final prev = _session(
        id: 'prev',
        startTime: DateTime(2025, 1, 1, 9, 0),
        endTime: DateTime(2025, 1, 1, 10, 0),
      );
      final toDelete = _session(
        id: 'mid',
        startTime: DateTime(2025, 1, 1, 10, 0),
        endTime: DateTime(2025, 1, 1, 11, 0),
      );
      repo.sessions.addAll([prev, toDelete]);

      final ctx = DeleteContext(
        session: toDelete,
        previous: prev,
        next: null,
        availableOptions: [DeleteOption.extendPrevious],
      );

      await service.executeDelete(DeleteOption.extendPrevious, ctx, repo);
      expect(repo.deletedIds, contains('mid'));
      final updatedPrev = repo.sessions.firstWhere((s) => s.id == 'prev');
      expect(updatedPrev.endTime, DateTime(2025, 1, 1, 11, 0));
    });
  });

  // ════════════════════════════════════════════════════════════════════════════
  // fillGaps
  // ════════════════════════════════════════════════════════════════════════════

  group('fillGaps', () {
    test('creates unknown sessions for each gap', () async {
      final repo = FakeFrontingSessionRepository();
      final gaps = [
        GapInfo(
          startTime: DateTime(2025, 1, 1, 11, 0),
          endTime: DateTime(2025, 1, 1, 12, 0),
          beforeSession: _session(
            id: 'a',
            startTime: DateTime(2025, 1, 1, 10, 0),
            endTime: DateTime(2025, 1, 1, 11, 0),
          ),
          afterSession: _session(
            id: 'b',
            startTime: DateTime(2025, 1, 1, 12, 0),
            endTime: DateTime(2025, 1, 1, 13, 0),
          ),
        ),
      ];

      await service.fillGaps(gaps, repo);
      expect(repo.sessions, hasLength(1));
      expect(repo.sessions.first.memberId, isNull);
      expect(repo.sessions.first.startTime, DateTime(2025, 1, 1, 11, 0));
      expect(repo.sessions.first.endTime, DateTime(2025, 1, 1, 12, 0));
    });
  });
}
