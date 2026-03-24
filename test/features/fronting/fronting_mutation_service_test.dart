import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/database/app_database.dart'
    hide FrontingSession;
import 'package:prism_plurality/core/mutations/field_patch.dart';
import 'package:prism_plurality/core/mutations/mutation_runner.dart';
import 'package:prism_plurality/data/repositories/drift_fronting_session_repository.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/domain/repositories/fronting_session_repository.dart';
import 'package:prism_plurality/features/fronting/models/update_fronting_session_patch.dart';
import 'package:prism_plurality/features/fronting/services/fronting_mutation_service.dart';

void main() {
  group('FrontingMutationService', () {
    late AppDatabase db;
    late DriftFrontingSessionRepository repository;
    late FrontingMutationService service;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      repository = DriftFrontingSessionRepository(db.frontingSessionsDao, null);
      service = FrontingMutationService(
        repository: repository,
        mutationRunner: MutationRunner(transactionRunner: db.transaction),
      );
    });

    tearDown(() async {
      await db.close();
    });

    test(
      'patch preserves omitted fields and clears explicit null fields',
      () async {
        final originalEndTime = DateTime(2026, 3, 11, 12);
        final original = FrontingSession(
          id: 'session-1',
          startTime: DateTime(2026, 3, 11, 10),
          endTime: originalEndTime,
          memberId: 'alice',
          notes: 'Keep me',
          confidence: FrontConfidence.strong,
        );
        await repository.createSession(original);

        final preservedResult = await service.updateSession(
          original.id,
          const UpdateFrontingSessionPatch(memberId: FieldPatch.value('bob')),
        );
        expect(preservedResult.isSuccess, isTrue);

        final preserved = await repository.getSessionById(original.id);
        expect(preserved, isNotNull);
        expect(preserved!.memberId, 'bob');
        expect(preserved.endTime, originalEndTime);
        expect(preserved.notes, 'Keep me');
        expect(preserved.confidence, FrontConfidence.strong);

        final clearedResult = await service.updateSession(
          original.id,
          const UpdateFrontingSessionPatch(notes: FieldPatch.value(null)),
        );
        expect(clearedResult.isSuccess, isTrue);

        final cleared = await repository.getSessionById(original.id);
        expect(cleared, isNotNull);
        expect(cleared!.notes, isNull);
        expect(cleared.endTime, originalEndTime);
      },
    );

    test(
      'applyEdit rolls back earlier writes if a later mutation fails',
      () async {
        final target = FrontingSession(
          id: 'target',
          startTime: DateTime(2026, 3, 11, 10),
          endTime: DateTime(2026, 3, 11, 11),
          memberId: 'alice',
        );
        final overlap = FrontingSession(
          id: 'overlap',
          startTime: DateTime(2026, 3, 11, 10, 30),
          endTime: DateTime(2026, 3, 11, 11, 30),
          memberId: 'bob',
        );
        await repository.createSession(target);
        await repository.createSession(overlap);

        final failingService = FrontingMutationService(
          repository: _ThrowOnTargetUpdateRepository(
            delegate: repository,
            targetId: target.id,
          ),
          mutationRunner: MutationRunner(transactionRunner: db.transaction),
        );

        final result = await failingService.applyEdit(
          sessionId: target.id,
          patch: const UpdateFrontingSessionPatch(),
          overlapsToTrim: [overlap.copyWith(startTime: DateTime(2026, 3, 11, 10, 15))],
        );

        expect(result.isFailure, isTrue);

        final persistedOverlap = await repository.getSessionById(overlap.id);
        expect(persistedOverlap, isNotNull);
        expect(persistedOverlap!.startTime, DateTime(2026, 3, 11, 10, 30));
        expect(persistedOverlap.endTime, DateTime(2026, 3, 11, 11, 30));
      },
    );
  });
}

class _ThrowOnTargetUpdateRepository implements FrontingSessionRepository {
  _ThrowOnTargetUpdateRepository({
    required DriftFrontingSessionRepository delegate,
    required String targetId,
  }) : _delegate = delegate,
       _targetId = targetId;

  final DriftFrontingSessionRepository _delegate;
  final String _targetId;

  @override
  Future<void> createSession(FrontingSession session) {
    return _delegate.createSession(session);
  }

  @override
  Future<void> deleteSession(String id) {
    return _delegate.deleteSession(id);
  }

  @override
  Future<void> endSession(String id, DateTime endTime) {
    return _delegate.endSession(id, endTime);
  }

  @override
  Future<FrontingSession?> getActiveSession() {
    return _delegate.getActiveSession();
  }

  @override
  Future<List<FrontingSession>> getActiveSessions() {
    return _delegate.getActiveSessions();
  }

  @override
  Future<List<FrontingSession>> getAllSessions() {
    return _delegate.getAllSessions();
  }

  @override
  Future<List<FrontingSession>> getRecentSessions({int limit = 20}) {
    return _delegate.getRecentSessions(limit: limit);
  }

  @override
  Future<FrontingSession?> getSessionById(String id) {
    return _delegate.getSessionById(id);
  }

  @override
  Future<List<FrontingSession>> getSessionsBetween(
    DateTime start,
    DateTime end,
  ) {
    return _delegate.getSessionsBetween(start, end);
  }

  @override
  Future<List<FrontingSession>> getSessionsForMember(String memberId) {
    return _delegate.getSessionsForMember(memberId);
  }

  @override
  Future<void> updateSession(FrontingSession session) async {
    if (session.id == _targetId) {
      throw StateError('forced failure while updating $session');
    }
    await _delegate.updateSession(session);
  }

  @override
  Stream<List<FrontingSession>> watchActiveSessions() {
    return _delegate.watchActiveSessions();
  }

  @override
  Stream<List<FrontingSession>> watchAllSessions() {
    return _delegate.watchAllSessions();
  }

  @override
  Stream<List<FrontingSession>> watchRecentSessions({int limit = 20}) {
    return _delegate.watchRecentSessions(limit: limit);
  }

  @override
  Stream<FrontingSession?> watchSessionById(String id) {
    return _delegate.watchSessionById(id);
  }

  @override
  Stream<FrontingSession?> watchActiveSession() {
    return _delegate.watchActiveSession();
  }

  @override
  Future<int> getCount() {
    return _delegate.getCount();
  }

  @override
  Future<Map<String, int>> getMemberFrontingCounts({int limit = 50}) {
    return _delegate.getMemberFrontingCounts(limit: limit);
  }
}
