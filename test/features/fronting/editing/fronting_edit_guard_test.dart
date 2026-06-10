import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/features/fronting/editing/fronting_edit_guard.dart';
import 'package:prism_plurality/features/fronting/editing/fronting_edit_resolution_models.dart';
import 'package:prism_plurality/features/fronting/editing/fronting_session_change.dart';
import 'package:prism_plurality/features/fronting/validation/fronting_validation_config.dart';
import 'package:prism_plurality/features/fronting/validation/fronting_validation_models.dart';

void main() {
  const guard = FrontingEditGuard();

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Base time anchor for tests: one day ago.
  final base = DateTime.now().subtract(const Duration(days: 1));

  FrontingSessionSnapshot makeSession({
    required String id,
    required DateTime start,
    DateTime? end,
    String? memberId = 'member1',
    bool isDeleted = false,
    SessionType sessionType = SessionType.normal,
  }) {
    return FrontingSessionSnapshot(
      id: id,
      memberId: memberId,
      start: start,
      end: end,
      isDeleted: isDeleted,
      sessionType: sessionType,
    );
  }

  // ---------------------------------------------------------------------------
  // validateTimeRange
  // ---------------------------------------------------------------------------

  group('validateTimeRange', () {
    test('end before start → error invalidRange issue', () {
      final start = base.add(const Duration(hours: 2));
      final end = base.add(const Duration(hours: 1));
      final issues = guard.validateTimeRange(start, end);
      expect(issues, hasLength(1));
      expect(issues.first.type, FrontingIssueType.invalidRange);
      expect(issues.first.severity, FrontingIssueSeverity.error);
    });

    test('end equal to start → error invalidRange issue', () {
      final start = base.add(const Duration(hours: 1));
      final issues = guard.validateTimeRange(start, start);
      expect(issues, hasLength(1));
      expect(issues.first.type, FrontingIssueType.invalidRange);
    });

    test('start in the future → error futureSession issue', () {
      final futureStart = DateTime.now().add(const Duration(hours: 2));
      final issues = guard.validateTimeRange(futureStart, null);
      expect(issues, hasLength(1));
      expect(issues.first.type, FrontingIssueType.futureSession);
      expect(issues.first.severity, FrontingIssueSeverity.error);
    });

    test('end in the future → error futureSession issue', () {
      final start = base.add(const Duration(hours: 1));
      final end = DateTime.now().add(const Duration(hours: 2));
      final issues = guard.validateTimeRange(start, end);
      expect(issues, hasLength(1));
      expect(issues.first.type, FrontingIssueType.futureSession);
      expect(issues.first.severity, FrontingIssueSeverity.error);
    });

    test('valid past range → no issues', () {
      final start = base;
      final end = base.add(const Duration(hours: 1));
      final issues = guard.validateTimeRange(start, end);
      expect(issues, isEmpty);
    });

    test('valid range with null end (active session) → no issues', () {
      final issues = guard.validateTimeRange(base, null);
      expect(issues, isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // validateEdit
  // ---------------------------------------------------------------------------

  group('validateEdit', () {
    test('clean edit with no neighbors → canSaveDirectly: true', () {
      final session = makeSession(
        id: 's1',
        start: base,
        end: base.add(const Duration(hours: 1)),
      );
      final patch = FrontingSessionPatch(
        start: base.add(const Duration(minutes: 5)),
      );
      final result = guard.validateEdit(
        original: session,
        patch: patch,
        nearbySessions: [],
        timingMode: FrontingTimingMode.flexible,
      );
      expect(result.canSaveDirectly, isTrue);
      expect(result.overlappingSessions, isEmpty);
      expect(result.gapsCreated, isEmpty);
      expect(result.duplicates, isEmpty);
    });

    test(
      'same-member self-overlap → canSaveDirectly: false, overlappingSessions populated',
      () {
        // s1: 00:00 → 01:00  member1 (being edited)
        // s2: 00:30 → 01:30  member1 (same member → self-overlap)
        // edit: extend s1 end to 01:30 → full self-overlap with s2
        final s1 = makeSession(
          id: 's1',
          start: base,
          end: base.add(const Duration(hours: 1)),
        );
        final s2 = makeSession(
          id: 's2',
          start: base.add(const Duration(minutes: 30)),
          end: base.add(const Duration(minutes: 90)),
          // same memberId as s1 (default: 'member1')
        );
        final patch = FrontingSessionPatch(
          end: base.add(const Duration(minutes: 90)),
        );
        final result = guard.validateEdit(
          original: s1,
          patch: patch,
          nearbySessions: [s1, s2],
          timingMode: FrontingTimingMode.flexible,
        );
        expect(result.canSaveDirectly, isFalse);
        expect(result.overlappingSessions, hasLength(1));
        expect(result.overlappingSessions.first.id, 's2');
      },
    );

    test(
      'cross-member overlap → canSaveDirectly: true (valid in per-member model)',
      () {
        // s1: 00:00 → 01:00  member1 (being edited)
        // s2: 00:30 → 01:30  member2 (different member → overlap is VALID)
        final s1 = makeSession(
          id: 's1',
          start: base,
          end: base.add(const Duration(hours: 1)),
        );
        final s2 = makeSession(
          id: 's2',
          start: base.add(const Duration(minutes: 30)),
          end: base.add(const Duration(minutes: 90)),
          memberId: 'member2',
        );
        final patch = FrontingSessionPatch(
          end: base.add(const Duration(minutes: 90)),
        );
        final result = guard.validateEdit(
          original: s1,
          patch: patch,
          nearbySessions: [s1, s2],
          timingMode: FrontingTimingMode.flexible,
        );
        // Cross-member overlaps are valid — no block, no overlap list.
        expect(result.canSaveDirectly, isTrue);
        expect(result.overlappingSessions, isEmpty);
      },
    );

    test('touching boundaries are NOT considered overlaps', () {
      // s1: 00:00 → 01:00  (being edited, kept as is)
      // s2: 01:00 → 02:00  (neighbor)
      // They touch at 01:00 — should not be an overlap
      final s1 = makeSession(
        id: 's1',
        start: base,
        end: base.add(const Duration(hours: 1)),
      );
      final s2 = makeSession(
        id: 's2',
        start: base.add(const Duration(hours: 1)),
        end: base.add(const Duration(hours: 2)),
        memberId: 'member2',
      );
      const patch = FrontingSessionPatch(); // no changes
      final result = guard.validateEdit(
        original: s1,
        patch: patch,
        nearbySessions: [s1, s2],
        timingMode: FrontingTimingMode.flexible,
      );
      expect(result.canSaveDirectly, isTrue);
      expect(result.overlappingSessions, isEmpty);
    });

    test(
      'edit creates gap above flexible threshold → canSaveDirectly: false',
      () {
        // prev: -02:00 → 00:00
        // s1: 00:00 → 01:00  (being edited: move start to 00:30, creating 30-min gap)
        // flexible threshold = 60 seconds → 30-min gap is above threshold
        final prev = makeSession(
          id: 'prev',
          start: base.subtract(const Duration(hours: 2)),
          end: base,
          memberId: 'member2',
        );
        final s1 = makeSession(
          id: 's1',
          start: base,
          end: base.add(const Duration(hours: 1)),
        );
        final patch = FrontingSessionPatch(
          start: base.add(const Duration(minutes: 30)),
        );
        final result = guard.validateEdit(
          original: s1,
          patch: patch,
          nearbySessions: [prev, s1],
          timingMode: FrontingTimingMode.flexible,
        );
        expect(result.canSaveDirectly, isFalse);
        expect(result.gapsCreated, hasLength(1));
        final gap = result.gapsCreated.first;
        expect(gap.duration, const Duration(minutes: 30));
      },
    );

    test('edit creates gap below flexible threshold → canSaveDirectly: true', () {
      // prev: -02:00 → 00:00
      // s1: 00:00 → 01:00  (being edited: move start to 00:00:30, creating 30-second gap)
      // flexible threshold = 60 seconds → 30-second gap is below threshold
      final prev = makeSession(
        id: 'prev',
        start: base.subtract(const Duration(hours: 2)),
        end: base,
        memberId: 'member2',
      );
      final s1 = makeSession(
        id: 's1',
        start: base,
        end: base.add(const Duration(hours: 1)),
      );
      final patch = FrontingSessionPatch(
        start: base.add(const Duration(seconds: 30)),
      );
      final result = guard.validateEdit(
        original: s1,
        patch: patch,
        nearbySessions: [prev, s1],
        timingMode: FrontingTimingMode.flexible,
      );
      expect(result.canSaveDirectly, isTrue);
      expect(result.gapsCreated, isEmpty);
    });

    test(
      'edit creates gap at end above strict threshold → canSaveDirectly: false',
      () {
        // s1: 00:00 → 02:00  (being edited: shrink end to 01:00, creating 1-hour gap before s2)
        // next: 02:00 → 03:00
        // strict threshold = 0 → any gap triggers
        final s1 = makeSession(
          id: 's1',
          start: base,
          end: base.add(const Duration(hours: 2)),
        );
        final s2 = makeSession(
          id: 's2',
          start: base.add(const Duration(hours: 2)),
          end: base.add(const Duration(hours: 3)),
          memberId: 'member2',
        );
        final patch = FrontingSessionPatch(
          end: base.add(const Duration(hours: 1)),
        );
        final result = guard.validateEdit(
          original: s1,
          patch: patch,
          nearbySessions: [s1, s2],
          timingMode: FrontingTimingMode.strict,
        );
        expect(result.canSaveDirectly, isFalse);
        expect(result.gapsCreated, hasLength(1));
      },
    );

    test(
      'edit creates duplicate → canSaveDirectly: false, duplicates populated',
      () {
        // s1: 00:00 → 01:00  member1  (being edited to start 00:00:10)
        // s2: 00:00 → 01:00  member1  (very similar → duplicate)
        // duplicate tolerance = 60s by default
        final s1 = makeSession(
          id: 's1',
          start: base,
          end: base.add(const Duration(hours: 1)),
        );
        final s2 = makeSession(
          id: 's2',
          start: base.add(const Duration(seconds: 5)),
          end: base.add(const Duration(hours: 1, seconds: 5)),
        );
        // patch: no time change — already overlaps
        const patch = FrontingSessionPatch(); // keep as-is
        final result = guard.validateEdit(
          original: s1,
          patch: patch,
          nearbySessions: [s1, s2],
          timingMode: FrontingTimingMode.flexible,
        );
        expect(result.canSaveDirectly, isFalse);
        expect(result.duplicates, hasLength(1));
        expect(result.duplicates.first.id, 's2');
      },
    );

    test('fronting edit does NOT surface overlap with sleep (data-loss guard)', () {
      // Sleep and normal fronting are parallel timelines. Editing a front so it
      // overlaps a sleep session must NOT surface that sleep as an overlap —
      // doing so routed it into a silent trim/delete. Sleep 10pm-8am, front
      // 8am-10am, front moved back to 6am so it covers part of sleep.
      final sleep = makeSession(
        id: 'sleep',
        start: base, // 10pm
        end: base.add(const Duration(hours: 10)), // 8am
        memberId: null,
        sessionType: SessionType.sleep,
      );
      final front = makeSession(
        id: 'front',
        start: base.add(const Duration(hours: 10)), // 8am
        end: base.add(const Duration(hours: 12)), // 10am
      );

      final patch = FrontingSessionPatch(
        start: base.add(const Duration(hours: 8)), // move to 6am
      );

      final result = guard.validateEdit(
        original: front,
        patch: patch,
        nearbySessions: [sleep, front],
        timingMode: FrontingTimingMode.flexible,
      );

      expect(result.overlappingSessions, isEmpty);
      expect(result.canSaveDirectly, isTrue);
    });

    test('sleep edit does NOT surface overlap with fronting (mirror)', () {
      // Mirror of the above: editing a sleep session so it overruns an adjacent
      // front must not surface the front as an overlap either.
      final sleep = makeSession(
        id: 'sleep',
        start: base,
        end: base.add(const Duration(hours: 8)),
        memberId: null,
        sessionType: SessionType.sleep,
      );
      final front = makeSession(
        id: 'front',
        start: base.add(const Duration(hours: 8)),
        end: base.add(const Duration(hours: 10)),
      );
      final patch = FrontingSessionPatch(
        end: base.add(const Duration(hours: 9)), // sleep now bleeds into front
      );

      final result = guard.validateEdit(
        original: sleep,
        patch: patch,
        nearbySessions: [sleep, front],
        timingMode: FrontingTimingMode.flexible,
      );

      expect(result.overlappingSessions, isEmpty);
      expect(result.canSaveDirectly, isTrue);
    });

    test(
      'editing an open-ended front does NOT surface later sleep sessions '
      '(mass-delete regression)',
      () {
        // The data-loss bug: an active (open-ended) front has a far-future
        // effective end, so it "contained" EVERY sleep session that started
        // after it — surfacing them all for trim, which deleted the user's
        // entire sleep history on save. None must be surfaced now.
        final front = makeSession(
          id: 'front',
          start: base,
          end: null, // active / open-ended
        );
        final sleeps = [
          for (var i = 1; i <= 30; i++)
            makeSession(
              id: 'sleep$i',
              start: base.add(Duration(hours: i * 8)),
              end: base.add(Duration(hours: i * 8 + 6)),
              memberId: null,
              sessionType: SessionType.sleep,
            ),
        ];

        // Edit the front's start earlier — the kind of edit Simon performed.
        final patch = FrontingSessionPatch(
          start: base.subtract(const Duration(hours: 1)),
        );

        final result = guard.validateEdit(
          original: front,
          patch: patch,
          nearbySessions: [front, ...sleeps],
          timingMode: FrontingTimingMode.flexible,
        );

        expect(result.overlappingSessions, isEmpty);
        expect(result.canSaveDirectly, isTrue);
      },
    );
  });

  // ---------------------------------------------------------------------------
  // getDeleteContext
  // ---------------------------------------------------------------------------

  group('getDeleteContext', () {
    test('finds correct previous and next sessions', () {
      // prev: -02:00 → -01:00
      // target: -01:00 → 00:00
      // next: 00:00 → 01:00
      final prev = makeSession(
        id: 'prev',
        start: base.subtract(const Duration(hours: 2)),
        end: base.subtract(const Duration(hours: 1)),
        memberId: 'member2',
      );
      final target = makeSession(
        id: 'target',
        start: base.subtract(const Duration(hours: 1)),
        end: base,
      );
      final next = makeSession(
        id: 'next',
        start: base,
        end: base.add(const Duration(hours: 1)),
        memberId: 'member2',
      );
      final ctx = guard.getDeleteContext(target, [prev, target, next]);
      expect(ctx.previous?.id, 'prev');
      expect(ctx.next?.id, 'next');
    });

    test('ignores sleep-only neighbors when building delete context', () {
      final sleepPrev = makeSession(
        id: 'sleep-prev',
        start: base.subtract(const Duration(hours: 2)),
        end: base.subtract(const Duration(hours: 1)),
        memberId: null,
        sessionType: SessionType.sleep,
      );
      final target = makeSession(
        id: 'target',
        start: base,
        end: base.add(const Duration(hours: 1)),
      );
      final sleepNext = makeSession(
        id: 'sleep-next',
        start: base.add(const Duration(hours: 1)),
        end: base.add(const Duration(hours: 2)),
        memberId: null,
        sessionType: SessionType.sleep,
      );

      final ctx = guard.getDeleteContext(target, [
        sleepPrev,
        target,
        sleepNext,
      ]);
      expect(ctx.previous, isNull);
      expect(ctx.next, isNull);
    });

    test('returns null neighbors when none exist', () {
      final target = makeSession(
        id: 'target',
        start: base,
        end: base.add(const Duration(hours: 1)),
      );
      final ctx = guard.getDeleteContext(target, [target]);
      expect(ctx.previous, isNull);
      expect(ctx.next, isNull);
    });

    test('finds closest previous when multiple before', () {
      final older = makeSession(
        id: 'older',
        start: base.subtract(const Duration(hours: 3)),
        end: base.subtract(const Duration(hours: 2)),
        memberId: 'member2',
      );
      final closer = makeSession(
        id: 'closer',
        start: base.subtract(const Duration(hours: 2)),
        end: base.subtract(const Duration(hours: 1)),
        memberId: 'member2',
      );
      final target = makeSession(
        id: 'target',
        start: base.subtract(const Duration(hours: 1)),
        end: base,
      );
      final ctx = guard.getDeleteContext(target, [older, closer, target]);
      expect(ctx.previous?.id, 'closer');
    });

    group('availableStrategies', () {
      test('no neighbors → only convertToUnknown + leaveGap', () {
        final target = makeSession(
          id: 'target',
          start: base,
          end: base.add(const Duration(hours: 1)),
        );
        final ctx = guard.getDeleteContext(target, [target]);
        expect(ctx.availableStrategies, [
          FrontingDeleteStrategy.convertToUnknown,
          FrontingDeleteStrategy.leaveGap,
        ]);
      });

      test('has previous → includes extendPrevious', () {
        final prev = makeSession(
          id: 'prev',
          start: base.subtract(const Duration(hours: 1)),
          end: base,
          memberId: 'member2',
        );
        final target = makeSession(
          id: 'target',
          start: base,
          end: base.add(const Duration(hours: 1)),
        );
        final ctx = guard.getDeleteContext(target, [prev, target]);
        expect(
          ctx.availableStrategies,
          contains(FrontingDeleteStrategy.extendPrevious),
        );
        expect(
          ctx.availableStrategies,
          isNot(contains(FrontingDeleteStrategy.extendNext)),
        );
      });

      test(
        'has only next → omits extendPrevious and keeps fallback options',
        () {
          final target = makeSession(
            id: 'target',
            start: base,
            end: base.add(const Duration(hours: 1)),
          );
          final next = makeSession(
            id: 'next',
            start: base.add(const Duration(hours: 1)),
            end: base.add(const Duration(hours: 2)),
            memberId: 'member2',
          );
          final ctx = guard.getDeleteContext(target, [target, next]);
          expect(
            ctx.availableStrategies,
            isNot(contains(FrontingDeleteStrategy.extendPrevious)),
          );
          expect(
            ctx.availableStrategies,
            containsAll([
              FrontingDeleteStrategy.convertToUnknown,
              FrontingDeleteStrategy.leaveGap,
            ]),
          );
        },
      );

      test(
        'previous neighbor keeps extend previous and drops legacy next/split options',
        () {
          final prev = makeSession(
            id: 'prev',
            start: base.subtract(const Duration(hours: 1)),
            end: base,
            memberId: 'member2',
          );
          final target = makeSession(
            id: 'target',
            start: base,
            end: base.add(const Duration(hours: 1)),
          );
          final next = makeSession(
            id: 'next',
            start: base.add(const Duration(hours: 1)),
            end: base.add(const Duration(hours: 2)),
            memberId: 'member2',
          );
          final ctx = guard.getDeleteContext(target, [prev, target, next]);
          expect(ctx.availableStrategies, hasLength(3));
          expect(
            ctx.availableStrategies,
            containsAll([
              FrontingDeleteStrategy.extendPrevious,
              FrontingDeleteStrategy.convertToUnknown,
              FrontingDeleteStrategy.leaveGap,
            ]),
          );
          expect(
            ctx.availableStrategies,
            isNot(contains(FrontingDeleteStrategy.extendNext)),
          );
          expect(
            ctx.availableStrategies,
            isNot(contains(FrontingDeleteStrategy.splitBetweenNeighbors)),
          );
        },
      );

      test('sleep delete only offers leave gap', () {
        final sleep = makeSession(
          id: 'sleep',
          start: base,
          end: base.add(const Duration(hours: 1)),
          memberId: null,
          sessionType: SessionType.sleep,
        );
        final ctx = guard.getDeleteContext(sleep, [sleep]);
        expect(ctx.availableStrategies, [FrontingDeleteStrategy.leaveGap]);
      });
    });
  });

  // ---------------------------------------------------------------------------
  // FrontingDeleteContext — label and description sanity checks
  // ---------------------------------------------------------------------------

  group('FrontingDeleteStrategy labels/descriptions', () {
    test('all strategies have non-empty label and description', () {
      for (final strategy in FrontingDeleteStrategy.values) {
        expect(
          strategy.label,
          isNotEmpty,
          reason: '${strategy.name}.label should be non-empty',
        );
        expect(
          strategy.description,
          isNotEmpty,
          reason: '${strategy.name}.description should be non-empty',
        );
      }
    });
  });

  // ---------------------------------------------------------------------------
  // FrontingEditValidationResult construction
  // ---------------------------------------------------------------------------

  group('FrontingEditValidationResult', () {
    test('defaults to empty lists when not provided', () {
      const result = FrontingEditValidationResult(canSaveDirectly: true);
      expect(result.issues, isEmpty);
      expect(result.overlappingSessions, isEmpty);
      expect(result.gapsCreated, isEmpty);
      expect(result.duplicates, isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // GapInfo
  // ---------------------------------------------------------------------------

  group('GapInfo', () {
    test('duration computed correctly', () {
      final start = base;
      final end = base.add(const Duration(minutes: 30));
      final info = GapInfo(start: start, end: end);
      expect(info.duration, const Duration(minutes: 30));
    });
  });

  // ---------------------------------------------------------------------------
  // getDeletePeriodContext
  // ---------------------------------------------------------------------------

  group('getDeletePeriodContext', () {
    final pStart = DateTime(2026, 5, 1, 14, 0);
    final pEnd = DateTime(2026, 5, 1, 15, 0);

    test('classifies overlap / touching-previous / touching-next correctly',
        () {
      // Way-before (not touching), touching-previous, overlapping (straddle
      // start), fully-inside, straddle-end, touching-next, way-after.
      final far = makeSession(
        id: 'far',
        start: DateTime(2026, 5, 1, 10, 0),
        end: DateTime(2026, 5, 1, 11, 0),
      );
      final prev = makeSession(
        id: 'prev',
        start: DateTime(2026, 5, 1, 13, 0),
        end: pStart,
      );
      final straddleStart = makeSession(
        id: 'straddleStart',
        start: DateTime(2026, 5, 1, 13, 30),
        end: DateTime(2026, 5, 1, 14, 30),
      );
      final inside = makeSession(
        id: 'inside',
        start: DateTime(2026, 5, 1, 14, 15),
        end: DateTime(2026, 5, 1, 14, 45),
      );
      final straddleEnd = makeSession(
        id: 'straddleEnd',
        start: DateTime(2026, 5, 1, 14, 45),
        end: DateTime(2026, 5, 1, 15, 30),
      );
      final next = makeSession(
        id: 'next',
        start: pEnd,
        end: DateTime(2026, 5, 1, 16, 0),
      );
      final later = makeSession(
        id: 'later',
        start: DateTime(2026, 5, 1, 17, 0),
        end: DateTime(2026, 5, 1, 18, 0),
      );

      final ctx = guard.getDeletePeriodContext(
        periodStart: pStart,
        periodEnd: pEnd,
        isOngoing: false,
        periodSessionIds: const {'straddleStart', 'inside', 'straddleEnd'},
        allSessions: [
          far,
          prev,
          straddleStart,
          inside,
          straddleEnd,
          next,
          later,
        ],
      );

      expect(
        ctx.sessionsInPeriod.map((s) => s.id),
        unorderedEquals(['straddleStart', 'inside', 'straddleEnd']),
      );
      expect(ctx.previousSessions.map((s) => s.id), ['prev']);
      expect(ctx.nextSessions.map((s) => s.id), ['next']);
    });

    test('always-present session overlapping but not in periodSessionIds '
        'is left alone', () {
      // Background/always-fronting member with a long-running session that
      // overlaps the period. derive_periods.dart partitions these out of
      // period.sessionIds — deleting the period must not touch the host.
      final host = makeSession(
        id: 'always-host',
        memberId: 'always-host-id',
        start: DateTime(2026, 4, 1, 0, 0),
        end: null,
      );
      final visitor = makeSession(
        id: 'visitor',
        memberId: 'visitor-id',
        start: pStart,
        end: pEnd,
      );
      final ctx = guard.getDeletePeriodContext(
        periodStart: pStart,
        periodEnd: pEnd,
        isOngoing: true,
        periodSessionIds: const {'visitor'},
        allSessions: [host, visitor],
      );
      expect(ctx.sessionsInPeriod.map((s) => s.id), ['visitor']);
      expect(ctx.previousSessions, isEmpty);
      expect(ctx.nextSessions, isEmpty);
    });

    test('excludes sleep sessions from every bucket', () {
      final sleep = makeSession(
        id: 'sleep',
        start: pStart,
        end: pEnd,
        sessionType: SessionType.sleep,
      );
      final ctx = guard.getDeletePeriodContext(
        periodStart: pStart,
        periodEnd: pEnd,
        isOngoing: false,
        periodSessionIds: const {'sleep'},
        allSessions: [sleep],
      );
      expect(ctx.sessionsInPeriod, isEmpty);
      expect(ctx.previousSessions, isEmpty);
      expect(ctx.nextSessions, isEmpty);
    });

    test('excludes soft-deleted sessions', () {
      final deleted = makeSession(
        id: 'd',
        start: pStart,
        end: pEnd,
        isDeleted: true,
      );
      final ctx = guard.getDeletePeriodContext(
        periodStart: pStart,
        periodEnd: pEnd,
        isOngoing: false,
        periodSessionIds: const {'d'},
        allSessions: [deleted],
      );
      expect(ctx.sessionsInPeriod, isEmpty);
    });

    test('open-ended session is classified as in-period when in the set', () {
      // Open-ended foreground session that the period claims.
      final open = makeSession(
        id: 'open',
        start: DateTime(2026, 5, 1, 13, 0),
        end: null,
      );
      final ctx = guard.getDeletePeriodContext(
        periodStart: pStart,
        periodEnd: pEnd,
        isOngoing: true,
        periodSessionIds: const {'open'},
        allSessions: [open],
      );
      expect(ctx.sessionsInPeriod.map((s) => s.id), ['open']);
      expect(ctx.previousSessions, isEmpty);
      expect(ctx.nextSessions, isEmpty);
    });

    test('availableStrategies: no previous, no straddler → only Unknown + Gap',
        () {
      final inside = makeSession(
        id: 'inside',
        start: pStart,
        end: pEnd,
      );
      final ctx = guard.getDeletePeriodContext(
        periodStart: pStart,
        periodEnd: pEnd,
        isOngoing: false,
        periodSessionIds: const {'inside'},
        allSessions: [inside],
      );
      expect(
        ctx.availableStrategies,
        [
          FrontingDeleteStrategy.convertToUnknown,
          FrontingDeleteStrategy.leaveGap,
        ],
      );
    });

    test(
        'availableStrategies: touching previous adds extendPrevious',
        () {
      final prev = makeSession(
        id: 'p',
        start: DateTime(2026, 5, 1, 13, 0),
        end: pStart,
      );
      final inside = makeSession(id: 'i', start: pStart, end: pEnd);
      final ctx = guard.getDeletePeriodContext(
        periodStart: pStart,
        periodEnd: pEnd,
        isOngoing: false,
        periodSessionIds: const {'i'},
        allSessions: [prev, inside],
      );
      expect(ctx.availableStrategies.first, FrontingDeleteStrategy.extendPrevious);
      expect(ctx.availableStrategies, contains(FrontingDeleteStrategy.leaveGap));
    });

    test('availableStrategies: straddle-start (no touching prev) adds extendPrevious',
        () {
      final straddle = makeSession(
        id: 's',
        start: DateTime(2026, 5, 1, 13, 30),
        end: DateTime(2026, 5, 1, 14, 30),
      );
      final ctx = guard.getDeletePeriodContext(
        periodStart: pStart,
        periodEnd: pEnd,
        isOngoing: false,
        periodSessionIds: const {'s'},
        allSessions: [straddle],
      );
      expect(
        ctx.availableStrategies,
        contains(FrontingDeleteStrategy.extendPrevious),
      );
    });

    test('ongoing period: caller must pass fresh periodEnd so a session '
        'that ended after derivation time classifies as fully-contained, '
        'not straddle-end', () {
      // Period derived at T0=14:30 (substituted "now"); Bob was fronting
      // open-ended at that moment. Bob ended at T0+3sec. User confirms
      // delete at T0+5sec. The caller must pass periodEnd=T0+5sec
      // (fresh now) — otherwise Bob's end (T0+3sec > stale-T0) is
      // straddle-end and gets trimmed to [T0, T0+3sec], a 3-second
      // ghost row that renders in the home view.
      final pStartOngoing = DateTime(2026, 5, 1, 14, 0);
      final stalePEnd = DateTime(2026, 5, 1, 14, 30, 0);
      final freshPEnd = DateTime(2026, 5, 1, 14, 30, 5);
      final bob = makeSession(
        id: 'bob-just-ended',
        memberId: 'bob',
        start: DateTime(2026, 5, 1, 14, 15),
        end: DateTime(2026, 5, 1, 14, 30, 3),
      );

      // With stale pEnd: Bob is straddle-end (end > pEnd).
      final stale = guard.getDeletePeriodContext(
        periodStart: pStartOngoing,
        periodEnd: stalePEnd,
        isOngoing: true,
        periodSessionIds: const {'bob-just-ended'},
        allSessions: [bob],
      );
      expect(stale.sessionsInPeriod.single.id, 'bob-just-ended');
      // Stale classifies him as straddle-end (end past pEnd).
      expect(stale.hasStraddleEnd, isTrue);

      // With fresh pEnd: Bob's end (14:30:03) is now ≤ pEnd (14:30:05),
      // so he's fully-contained — convertToUnknown will Delete (or pick
      // him as the Unknown survivor) instead of trimming.
      final fresh = guard.getDeletePeriodContext(
        periodStart: pStartOngoing,
        periodEnd: freshPEnd,
        isOngoing: true,
        periodSessionIds: const {'bob-just-ended'},
        allSessions: [bob],
      );
      expect(fresh.sessionsInPeriod.single.id, 'bob-just-ended');
      expect(fresh.hasStraddleEnd, isFalse);
    });

    test('availableStrategies: pure both-straddler does NOT offer '
        'extendPrevious', () {
      // Single session spanning the entire slice from before to after —
      // think a current front that started before the visible history
      // window. extendPrevious leaves both-straddlers intact, so offering
      // the option here means the dialog shows a button that does
      // nothing.
      final spanning = makeSession(
        id: 'spanning',
        start: DateTime(2026, 5, 1, 10, 0),
        end: DateTime(2026, 5, 1, 18, 0),
      );
      final ctx = guard.getDeletePeriodContext(
        periodStart: pStart,
        periodEnd: pEnd,
        isOngoing: false,
        periodSessionIds: const {'spanning'},
        allSessions: [spanning],
      );
      expect(
        ctx.availableStrategies,
        isNot(contains(FrontingDeleteStrategy.extendPrevious)),
      );
      expect(
        ctx.availableStrategies,
        [
          FrontingDeleteStrategy.convertToUnknown,
          FrontingDeleteStrategy.leaveGap,
        ],
      );
    });
  });
}
