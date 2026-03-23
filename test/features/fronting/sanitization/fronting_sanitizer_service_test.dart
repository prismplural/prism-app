import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/database/app_database.dart'
    hide FrontingSession;
import 'package:prism_plurality/core/mutations/mutation_runner.dart';
import 'package:prism_plurality/data/repositories/drift_fronting_session_repository.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/features/fronting/editing/fronting_change_executor.dart';
import 'package:prism_plurality/features/fronting/sanitization/fronting_fix_planner.dart';
import 'package:prism_plurality/features/fronting/sanitization/fronting_sanitizer_service.dart';
import 'package:prism_plurality/features/fronting/validation/fronting_session_validator.dart';
import 'package:prism_plurality/features/fronting/validation/fronting_validation_models.dart';

void main() {
  group('FrontingSanitizerService', () {
    late AppDatabase db;
    late DriftFrontingSessionRepository repository;
    late FrontingChangeExecutor executor;
    late FrontingSanitizerService service;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      repository = DriftFrontingSessionRepository(
        db.frontingSessionsDao,
        null,
      );
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
        final session = FrontingSession(
          id: 'session-1',
          startTime: start,
        );
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

      test('maps coFronterIds', () {
        final session = FrontingSession(
          id: 'session-1',
          startTime: DateTime(2024, 6, 1, 10),
          coFronterIds: ['member-2', 'member-3'],
        );
        final snapshot = FrontingSanitizerService.toSnapshot(session);
        expect(snapshot.coFronterIds, ['member-2', 'member-3']);
      });

      test('maps empty coFronterIds', () {
        final session = FrontingSession(
          id: 'session-1',
          startTime: DateTime(2024, 6, 1, 10),
        );
        final snapshot = FrontingSanitizerService.toSnapshot(session);
        expect(snapshot.coFronterIds, isEmpty);
      });

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
            reason: 'Expected confidenceIndex ${confidence.index} for $confidence',
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
  });
}
