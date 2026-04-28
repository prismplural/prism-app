import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/database/app_database.dart'
    hide FrontingSession;
import 'package:prism_plurality/core/mutations/mutation_result.dart';
import 'package:prism_plurality/core/mutations/mutation_runner.dart';
import 'package:prism_plurality/data/repositories/drift_fronting_session_repository.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/features/fronting/editing/fronting_change_executor.dart';
import 'package:prism_plurality/features/fronting/editing/fronting_session_change.dart';
import 'package:prism_plurality/features/fronting/sanitization/fronting_fix_models.dart';
import 'package:prism_plurality/features/fronting/sanitization/fronting_fix_planner.dart';
import 'package:prism_plurality/features/fronting/sanitization/fronting_sanitizer_service.dart';
import 'package:prism_plurality/features/fronting/validation/fronting_session_validator.dart';
import 'package:prism_plurality/features/fronting/validation/fronting_validation_config.dart';
import 'package:prism_plurality/features/fronting/validation/fronting_validation_models.dart';

void main() {
  group('FrontingSanitizerService', () {
    late AppDatabase db;
    late DriftFrontingSessionRepository repository;
    late FrontingChangeExecutor executor;
    late FrontingSanitizerService service;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      repository = DriftFrontingSessionRepository(db.frontingSessionsDao, null);
      executor = FrontingChangeExecutor(
        repository: repository,
        mutationRunner: MutationRunner(transactionRunner: db.transaction),
      );
      service = FrontingSanitizerService(
        repository: repository,
        validator: const FrontingSessionValidator(),
        planner: const FrontingFixPlanner(),
        executor: executor,
      );
    });

    tearDown(() async {
      await db.close();
    });

    test('constructs without error', () {
      expect(service, isA<FrontingSanitizerService>());
    });

    // ─── toSnapshot conversion ──────────────────────────────────────────────

    group('toSnapshot', () {
      test('maps id', () {
        final session = FrontingSession(
          id: 'session-abc',
          startTime: DateTime(2024, 6, 1, 10),
        );
        final snapshot = FrontingSanitizerService.toSnapshot(session);
        expect(snapshot.id, 'session-abc');
      });

      test('maps memberId', () {
        final session = FrontingSession(
          id: 'session-1',
          startTime: DateTime(2024, 6, 1, 10),
          memberId: 'member-42',
        );
        final snapshot = FrontingSanitizerService.toSnapshot(session);
        expect(snapshot.memberId, 'member-42');
      });

      test('maps null memberId', () {
        final session = FrontingSession(
          id: 'session-1',
          startTime: DateTime(2024, 6, 1, 10),
        );
        final snapshot = FrontingSanitizerService.toSnapshot(session);
        expect(snapshot.memberId, isNull);
      });

      test('maps startTime to start', () {
        final start = DateTime(2024, 6, 1, 10, 30);
        final session = FrontingSession(id: 'session-1', startTime: start);
        final snapshot = FrontingSanitizerService.toSnapshot(session);
        expect(snapshot.start, start);
      });

      test('maps endTime to end', () {
        final start = DateTime(2024, 6, 1, 10, 0);
        final end = DateTime(2024, 6, 1, 12, 0);
        final session = FrontingSession(
          id: 'session-1',
          startTime: start,
          endTime: end,
        );
        final snapshot = FrontingSanitizerService.toSnapshot(session);
        expect(snapshot.end, end);
      });

      test('maps null endTime to null end (active session)', () {
        final session = FrontingSession(
          id: 'session-1',
          startTime: DateTime(2024, 6, 1, 10),
        );
        final snapshot = FrontingSanitizerService.toSnapshot(session);
        expect(snapshot.end, isNull);
      });

      // coFronterIds no longer exists — per-member model uses separate rows.

      test('maps notes', () {
        final session = FrontingSession(
          id: 'session-1',
          startTime: DateTime(2024, 6, 1, 10),
          notes: 'Some notes here',
        );
        final snapshot = FrontingSanitizerService.toSnapshot(session);
        expect(snapshot.notes, 'Some notes here');
      });

      test('maps null notes', () {
        final session = FrontingSession(
          id: 'session-1',
          startTime: DateTime(2024, 6, 1, 10),
        );
        final snapshot = FrontingSanitizerService.toSnapshot(session);
        expect(snapshot.notes, isNull);
      });

      test('maps confidence to confidenceIndex', () {
        final session = FrontingSession(
          id: 'session-1',
          startTime: DateTime(2024, 6, 1, 10),
          confidence: FrontConfidence.certain,
        );
        final snapshot = FrontingSanitizerService.toSnapshot(session);
        expect(snapshot.confidenceIndex, FrontConfidence.certain.index);
      });

      test('maps null confidence to null confidenceIndex', () {
        final session = FrontingSession(
          id: 'session-1',
          startTime: DateTime(2024, 6, 1, 10),
        );
        final snapshot = FrontingSanitizerService.toSnapshot(session);
        expect(snapshot.confidenceIndex, isNull);
      });

      test('maps all FrontConfidence values', () {
        for (final confidence in FrontConfidence.values) {
          final session = FrontingSession(
            id: 'session-${confidence.index}',
            startTime: DateTime(2024, 6, 1, 10),
            confidence: confidence,
          );
          final snapshot = FrontingSanitizerService.toSnapshot(session);
          expect(
            snapshot.confidenceIndex,
            confidence.index,
            reason:
                'Expected confidenceIndex ${confidence.index} for $confidence',
          );
        }
      });

      test('isDeleted defaults to false in snapshot', () {
        final session = FrontingSession(
          id: 'session-1',
          startTime: DateTime(2024, 6, 1, 10),
        );
        final snapshot = FrontingSanitizerService.toSnapshot(session);
        expect(snapshot.isDeleted, isFalse);
        expect(snapshot.sessionType, SessionType.normal);
      });

      test('returns a FrontingSessionSnapshot', () {
        final session = FrontingSession(
          id: 'session-1',
          startTime: DateTime(2024, 6, 1, 10),
        );
        final snapshot = FrontingSanitizerService.toSnapshot(session);
        expect(snapshot, isA<FrontingSessionSnapshot>());
      });
    });

    // ─── scan ──────────────────────────────────────────────────────────────

    test('scan returns empty list when no sessions exist', () async {
      final issues = await service.scan();
      expect(issues, isEmpty);
    });

    test('scan ignores sleep sessions (only validates normal fronting sessions)', () async {
      // Sleep sessions are excluded from the validator entirely — they are
      // passed in a separate list and only used for sleep-coverage logic which
      // is no longer relevant in the per-member model.
      final fronting = FrontingSession(
        id: 'fronting-1',
        startTime: DateTime(2026, 3, 18, 8),
        endTime: DateTime(2026, 3, 18, 10),
        memberId: 'member-1',
      );
      final sleep = FrontingSession(
        id: 'sleep-1',
        startTime: DateTime(2026, 3, 18, 8, 30),
        endTime: DateTime(2026, 3, 18, 10, 30),
        memberId: null,
        sessionType: SessionType.sleep,
      );

      await repository.createSession(fronting);
      await repository.createSession(sleep);

      // Only the fronting session is validated; no self-overlap since only one
      // fronting session. No issues expected.
      final issues = await service.scan();
      expect(issues, isEmpty);
    });

    test('scan produces no issues for two members with non-overlapping sessions', () async {
      // In the per-member model, gaps between fronters are VALID. Two members
      // each with valid non-overlapping sessions should produce zero issues.
      final service2 = FrontingSanitizerService(
        repository: repository,
        validator: const FrontingSessionValidator(
          config: FrontingValidationConfig(
            detectDuplicates: false,
            detectMergeableAdjacent: false,
            detectFutureSessions: false,
          ),
        ),
        planner: const FrontingFixPlanner(),
        executor: executor,
      );
      final member1Session = FrontingSession(
        id: 'fronting-1',
        startTime: DateTime(2026, 3, 18, 20),
        endTime: DateTime(2026, 3, 18, 22),
        memberId: 'member-1',
      );
      final member2Session = FrontingSession(
        id: 'fronting-2',
        startTime: DateTime(2026, 3, 19, 8),
        endTime: DateTime(2026, 3, 19, 10),
        memberId: 'member-2',
      );

      await repository.createSession(member1Session);
      await repository.createSession(member2Session);

      final issues = await service2.scan();
      // No gaps, no overlaps — both are valid in per-member model.
      expect(issues, isEmpty);
    });

    // ─── applyPlan ─────────────────────────────────────────────────────────

    group('applyPlan', () {
      test(
        'returns MutationFailure when the executor fails (e.g. session not found for update)',
        () async {
          // Pin the regression: previously `applyPlan` awaited
          // `_executor.execute` and discarded the `MutationResult<void>`,
          // so an executor failure (which the mutation runner returns
          // as `MutationFailure` rather than throwing) was silently
          // treated as success. The UI then marked the issue as fixed
          // even though no mutation landed.
          //
          // We trigger a real failure by feeding the executor an
          // UpdateSessionChange for a non-existent session. The executor
          // throws StateError, the mutation runner catches it and
          // returns `MutationResult.failure(...)`, and the sanitizer
          // must propagate that result instead of swallowing it.
          const plan = FrontingFixPlan(
            id: 'plan-missing',
            type: FrontingFixType.trimEarlier,
            title: 'trim',
            description: 'trim earlier session',
            affectedSessionIds: ['does-not-exist'],
            changes: [
              UpdateSessionChange(
                sessionId: 'does-not-exist',
                patch: FrontingSessionPatch(notes: 'noop'),
              ),
            ],
          );

          final result = await service.applyPlan(plan);

          expect(result, isA<MutationFailure<void>>());
          expect(result.isFailure, isTrue);
          expect(result.failureOrNull, isNotNull);
          expect(
            result.failureOrNull!.message,
            contains('session not found'),
          );
        },
      );

      test(
        'returns MutationSuccess when the executor applies all changes',
        () async {
          final session = FrontingSession(
            id: 'session-apply-ok',
            startTime: DateTime(2026, 3, 18, 9),
            endTime: DateTime(2026, 3, 18, 11),
            memberId: 'member-1',
          );
          await repository.createSession(session);

          const plan = FrontingFixPlan(
            id: 'plan-ok',
            type: FrontingFixType.deleteSession,
            title: 'delete',
            description: 'delete session',
            affectedSessionIds: ['session-apply-ok'],
            changes: [DeleteSessionChange('session-apply-ok')],
          );

          final result = await service.applyPlan(plan);

          expect(result, isA<MutationSuccess<void>>());
          expect(result.isSuccess, isTrue);
        },
      );
    });

    test(
      'scoped scan includes sessions already in progress at the range start',
      () async {
        // In the per-member model, cross-member overlaps are valid. To get issues
        // from a scan we need same-member self-overlaps. Two sessions for the
        // same member that overlap should produce a selfOverlap issue.
        final selfOverlapService = FrontingSanitizerService(
          repository: repository,
          validator: const FrontingSessionValidator(
            config: FrontingValidationConfig(
              detectDuplicates: false,
              detectMergeableAdjacent: false,
              detectFutureSessions: false,
              detectSelfOverlaps: true,
            ),
          ),
          planner: const FrontingFixPlanner(),
          executor: executor,
        );
        final earlier = FrontingSession(
          id: 'fronting-earlier',
          startTime: DateTime(2026, 3, 18, 9),
          endTime: DateTime(2026, 3, 18, 11),
          memberId: 'member-1',
        );
        final selfOverlap = FrontingSession(
          id: 'fronting-self-overlap',
          startTime: DateTime(2026, 3, 18, 10, 30),
          endTime: DateTime(2026, 3, 18, 12),
          memberId: 'member-1', // same member → self-overlap
        );

        await repository.createSession(earlier);
        await repository.createSession(selfOverlap);

        final issues = await selfOverlapService.scan(
          from: DateTime(2026, 3, 18, 10),
          to: DateTime(2026, 3, 18, 11, 30),
        );

        expect(
          issues.any((issue) => issue.type == FrontingIssueType.selfOverlap),
          isTrue,
        );
      },
    );
  });
}
