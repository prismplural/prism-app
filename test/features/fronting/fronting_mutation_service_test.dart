import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/database/app_database.dart'
    hide FrontingSession;
import 'package:prism_plurality/core/mutations/field_patch.dart';
import 'package:prism_plurality/core/mutations/mutation_runner.dart';
import 'package:prism_plurality/data/repositories/drift_fronting_session_repository.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/features/fronting/models/update_fronting_session_patch.dart';
import 'package:prism_plurality/features/fronting/services/fronting_mutation_service.dart';
import '../../helpers/fake_repositories.dart';

Future<T> _passthroughTransactionRunner<T>(Future<T> Function() action) async {
  return action();
}

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
            db.frontingSessionsDao,
            null,
            targetId: target.id,
          ),
          mutationRunner: MutationRunner(transactionRunner: db.transaction),
        );

        final result = await failingService.applyEdit(
          sessionId: target.id,
          patch: const UpdateFrontingSessionPatch(),
          overlapsToTrim: [
            overlap.copyWith(startTime: DateTime(2026, 3, 11, 10, 15)),
          ],
        );

        expect(result.isFailure, isTrue);

        final persistedOverlap = await repository.getSessionById(overlap.id);
        expect(persistedOverlap, isNotNull);
        expect(persistedOverlap!.startTime, DateTime(2026, 3, 11, 10, 30));
        expect(persistedOverlap.endTime, DateTime(2026, 3, 11, 11, 30));
      },
    );

    test(
      'startSleep ends active fronting sessions and creates a sleep session',
      () async {
        final repo = FakeFrontingSessionRepository();
        final fronting = FrontingSession(
          id: 'front-1',
          startTime: DateTime(2026, 3, 11, 8),
          memberId: 'alice',
        );
        await repo.createSession(fronting);

        final sleepService = FrontingMutationService(
          repository: repo,
          mutationRunner: MutationRunner(
            transactionRunner: _passthroughTransactionRunner,
          ),
        );

        final result = await sleepService.startSleep(
          notes: 'nap',
          startTime: DateTime(2026, 3, 11, 10),
        );

        expect(result.isSuccess, isTrue);
        expect(repo.sessions, hasLength(2));
        final endedFronting = repo.sessions
            .where((session) => session.id == fronting.id)
            .single;
        expect(endedFronting.endTime, DateTime(2026, 3, 11, 10));
        final createdSleep = repo.sessions
            .where((session) => session.isSleep)
            .single;
        expect(createdSleep.memberId, isNull);
        expect(createdSleep.notes, 'nap');
      },
    );

    test(
      'startFronting ends active sleep sessions before creating fronting',
      () async {
        final repo = FakeFrontingSessionRepository();
        final sleep = FrontingSession(
          id: 'sleep-1',
          startTime: DateTime(2026, 3, 11, 8),
          memberId: null,
          sessionType: SessionType.sleep,
        );
        await repo.createSession(sleep);

        final sleepAwareService = FrontingMutationService(
          repository: repo,
          mutationRunner: MutationRunner(
            transactionRunner: _passthroughTransactionRunner,
          ),
        );

        final result = await sleepAwareService.startFronting('bob');

        expect(result.isSuccess, isTrue);
        expect(repo.sessions, hasLength(2));
        final endedSleep = repo.sessions
            .where((session) => session.id == sleep.id)
            .single;
        expect(endedSleep.endTime, isNotNull);
        final createdFronting = repo.sessions
            .where((session) => session.id != sleep.id)
            .single;
        expect(createdFronting.memberId, 'bob');
        expect(createdFronting.isSleep, isFalse);
      },
    );
  });
}

class _ThrowOnTargetUpdateRepository extends DriftFrontingSessionRepository {
  _ThrowOnTargetUpdateRepository(
    super.dao,
    super.syncHandle, {
    required String targetId,
  }) : _targetId = targetId;

  final String _targetId;

  @override
  Future<void> updateSession(FrontingSession session) async {
    if (session.id == _targetId) {
      throw StateError('forced failure while updating $session');
    }
    await super.updateSession(session);
  }
}
