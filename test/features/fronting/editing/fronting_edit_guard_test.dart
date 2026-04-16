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
    List<String> coFronterIds = const [],
    bool isDeleted = false,
    SessionType sessionType = SessionType.normal,
  }) {
    return FrontingSessionSnapshot(
      id: id,
      memberId: memberId,
      start: start,
      end: end,
      coFronterIds: coFronterIds,
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
      'edit creates overlap → canSaveDirectly: false, overlappingSessions populated',
      () {
        // s1: 00:00 → 01:00  (being edited)
        // s2: 00:30 → 01:30  (neighbor)
        // edit: extend s1 end to 01:30 → full overlap with s2
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
        expect(result.canSaveDirectly, isFalse);
        expect(result.overlappingSessions, hasLength(1));
        expect(result.overlappingSessions.first.id, 's2');
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
        // flexible threshold = 5 min → 30-min gap is above threshold
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
      // s1: 00:00 → 01:00  (being edited: move start to 00:02, creating 2-min gap)
      // flexible threshold = 5 min → 2-min gap is below threshold
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
        start: base.add(const Duration(minutes: 2)),
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

    test('fronting edit detects overlap with adjacent sleep session', () {
      // Reproduces the reported bug: sleep 10pm-8am, front 8am-10am.
      // Editing front to 6am-10am should surface the sleep overlap so the
      // user is offered a trim, not silently save.
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

      expect(result.overlappingSessions, hasLength(1));
      expect(result.overlappingSessions.first.id, 'sleep');
      expect(result.canSaveDirectly, isFalse);
      // Cross-type overlap → co-fronting does not apply.
      expect(result.canCoFront, isFalse);
    });

    test(
      'sleep edit detects overlap with adjacent fronting session',
      () {
        // Editing a sleep session so it overruns an adjacent fronting session
        // should surface the overlap too — mirror of the above.
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

        expect(result.overlappingSessions, hasLength(1));
        expect(result.overlappingSessions.first.id, 'front');
        expect(result.canCoFront, isFalse);
      },
    );

    test('canCoFront is true when both sides are normal fronting', () {
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

      expect(result.overlappingSessions, hasLength(1));
      expect(result.canCoFront, isTrue);
    });
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

      test('has next → includes extendNext', () {
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
          contains(FrontingDeleteStrategy.extendNext),
        );
        expect(
          ctx.availableStrategies,
          isNot(contains(FrontingDeleteStrategy.extendPrevious)),
        );
      });

      test(
        'both neighbors + closed target → includes splitBetweenNeighbors',
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
            end: base.add(const Duration(hours: 1)), // closed
          );
          final next = makeSession(
            id: 'next',
            start: base.add(const Duration(hours: 1)),
            end: base.add(const Duration(hours: 2)),
            memberId: 'member2',
          );
          final ctx = guard.getDeleteContext(target, [prev, target, next]);
          expect(
            ctx.availableStrategies,
            contains(FrontingDeleteStrategy.splitBetweenNeighbors),
          );
        },
      );

      test(
        'both neighbors + active target (null end) → no splitBetweenNeighbors',
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
            end: null, // active — no end time
          );
          final next = makeSession(
            id: 'next',
            start: base.add(const Duration(hours: 1)),
            end: base.add(const Duration(hours: 2)),
            memberId: 'member2',
          );
          final ctx = guard.getDeleteContext(target, [prev, target, next]);
          expect(
            ctx.availableStrategies,
            isNot(contains(FrontingDeleteStrategy.splitBetweenNeighbors)),
          );
        },
      );

      test(
        'all 5 strategies available when both neighbors + closed target',
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
          expect(ctx.availableStrategies, hasLength(5));
          expect(
            ctx.availableStrategies,
            containsAll([
              FrontingDeleteStrategy.extendPrevious,
              FrontingDeleteStrategy.extendNext,
              FrontingDeleteStrategy.splitBetweenNeighbors,
              FrontingDeleteStrategy.convertToUnknown,
              FrontingDeleteStrategy.leaveGap,
            ]),
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
}
