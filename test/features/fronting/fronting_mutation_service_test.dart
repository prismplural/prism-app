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

    test('startSleep ends a prior active sleep session', () async {
      final repo = FakeFrontingSessionRepository();
      final priorSleep = FrontingSession(
        id: 'sleep-old',
        startTime: DateTime(2026, 3, 11, 0),
        memberId: null,
        sessionType: SessionType.sleep,
      );
      await repo.createSession(priorSleep);

      final svc = FrontingMutationService(
        repository: repo,
        mutationRunner: MutationRunner(
          transactionRunner: _passthroughTransactionRunner,
        ),
      );

      final result = await svc.startSleep(startTime: DateTime(2026, 3, 11, 8));

      expect(result.isSuccess, isTrue);
      final endedPrior = repo.sessions.where((s) => s.id == 'sleep-old').single;
      expect(endedPrior.endTime, DateTime(2026, 3, 11, 8));
      final newSleep = repo.sessions.where((s) => s.isSleep && s.isActive);
      expect(newSleep, hasLength(1));
    });

    test('endSleep sets endTime on a sleep session', () async {
      final repo = FakeFrontingSessionRepository();
      final sleep = FrontingSession(
        id: 'sleep-1',
        startTime: DateTime(2026, 3, 11, 22),
        memberId: null,
        sessionType: SessionType.sleep,
      );
      await repo.createSession(sleep);

      final svc = FrontingMutationService(
        repository: repo,
        mutationRunner: MutationRunner(
          transactionRunner: _passthroughTransactionRunner,
        ),
      );

      final result = await svc.endSleep('sleep-1');
      expect(result.isSuccess, isTrue);

      final ended = repo.sessions.single;
      expect(ended.endTime, isNotNull);
    });

    test('endSleep rejects a fronting session', () async {
      final repo = FakeFrontingSessionRepository();
      final fronting = FrontingSession(
        id: 'front-1',
        startTime: DateTime(2026, 3, 11, 10),
        memberId: 'alice',
      );
      await repo.createSession(fronting);

      final svc = FrontingMutationService(
        repository: repo,
        mutationRunner: MutationRunner(
          transactionRunner: _passthroughTransactionRunner,
        ),
      );

      final result = await svc.endSleep('front-1');
      expect(result.isFailure, isTrue);
    });

    test('updateSleepQuality updates quality on a sleep session', () async {
      final repo = FakeFrontingSessionRepository();
      final sleep = FrontingSession(
        id: 'sleep-1',
        startTime: DateTime(2026, 3, 11, 22),
        endTime: DateTime(2026, 3, 12, 6),
        memberId: null,
        sessionType: SessionType.sleep,
        quality: SleepQuality.unknown,
      );
      await repo.createSession(sleep);

      final svc = FrontingMutationService(
        repository: repo,
        mutationRunner: MutationRunner(
          transactionRunner: _passthroughTransactionRunner,
        ),
      );

      final result = await svc.updateSleepQuality(
        'sleep-1',
        SleepQuality.excellent,
      );
      expect(result.isSuccess, isTrue);

      final updated = repo.sessions.single;
      expect(updated.quality, SleepQuality.excellent);
    });

    test('deleteSleep rejects a fronting session', () async {
      final repo = FakeFrontingSessionRepository();
      final fronting = FrontingSession(
        id: 'front-1',
        startTime: DateTime(2026, 3, 11, 10),
        endTime: DateTime(2026, 3, 11, 12),
        memberId: 'alice',
      );
      await repo.createSession(fronting);

      final svc = FrontingMutationService(
        repository: repo,
        mutationRunner: MutationRunner(
          transactionRunner: _passthroughTransactionRunner,
        ),
      );

      final result = await svc.deleteSleep('front-1');
      expect(result.isFailure, isTrue);
      // Session should not be deleted
      expect(repo.sessions, hasLength(1));
    });

    test('splitSession preserves sleep fields on both halves', () async {
      final repo = FakeFrontingSessionRepository();
      final sleep = FrontingSession(
        id: 'sleep-1',
        startTime: DateTime(2026, 3, 11, 22),
        endTime: DateTime(2026, 3, 12, 8),
        memberId: null,
        sessionType: SessionType.sleep,
        quality: SleepQuality.good,
        isHealthKitImport: true,
      );
      await repo.createSession(sleep);

      final svc = FrontingMutationService(
        repository: repo,
        mutationRunner: MutationRunner(
          transactionRunner: _passthroughTransactionRunner,
        ),
      );

      final result = await svc.splitSession(
        sessionId: 'sleep-1',
        splitTime: DateTime(2026, 3, 12, 3),
      );
      expect(result.isSuccess, isTrue);

      final sessions = repo.sessions
        ..sort((a, b) => a.startTime.compareTo(b.startTime));
      expect(sessions, hasLength(2));

      final first = sessions[0];
      final second = sessions[1];

      expect(first.sessionType, SessionType.sleep);
      expect(first.quality, SleepQuality.good);
      expect(first.isHealthKitImport, isTrue);
      expect(first.endTime, DateTime(2026, 3, 12, 3));

      expect(second.sessionType, SessionType.sleep);
      expect(second.quality, SleepQuality.good);
      expect(second.isHealthKitImport, isTrue);
      expect(second.startTime, DateTime(2026, 3, 12, 3));
      expect(second.endTime, DateTime(2026, 3, 12, 8));
    });

    test('wakeUp ends a sleep session', () async {
      final repo = FakeFrontingSessionRepository();
      final sleep = FrontingSession(
        id: 'sleep-1',
        startTime: DateTime(2026, 3, 11, 22),
        memberId: null,
        sessionType: SessionType.sleep,
      );
      await repo.createSession(sleep);

      final svc = FrontingMutationService(
        repository: repo,
        mutationRunner: MutationRunner(
          transactionRunner: _passthroughTransactionRunner,
        ),
      );

      final result = await svc.wakeUp('sleep-1');
      expect(result.isSuccess, isTrue);

      final ended = repo.sessions.single;
      expect(ended.endTime, isNotNull);
      expect(ended.sessionType, SessionType.sleep);
    });

    test('wakeUp records quality on the sleep session', () async {
      final repo = FakeFrontingSessionRepository();
      final sleep = FrontingSession(
        id: 'sleep-1',
        startTime: DateTime(2026, 3, 11, 22),
        memberId: null,
        sessionType: SessionType.sleep,
      );
      await repo.createSession(sleep);

      final svc = FrontingMutationService(
        repository: repo,
        mutationRunner: MutationRunner(
          transactionRunner: _passthroughTransactionRunner,
        ),
      );

      final result = await svc.wakeUp(
        'sleep-1',
        quality: SleepQuality.excellent,
      );
      expect(result.isSuccess, isTrue);

      final ended = repo.sessions.single;
      expect(ended.endTime, isNotNull);
      expect(ended.quality, SleepQuality.excellent);
    });

    test('wakeUp starts fronting for selected member', () async {
      final repo = FakeFrontingSessionRepository();
      final sleep = FrontingSession(
        id: 'sleep-1',
        startTime: DateTime(2026, 3, 11, 22),
        memberId: null,
        sessionType: SessionType.sleep,
      );
      await repo.createSession(sleep);

      final svc = FrontingMutationService(
        repository: repo,
        mutationRunner: MutationRunner(
          transactionRunner: _passthroughTransactionRunner,
        ),
      );

      final result = await svc.wakeUp(
        'sleep-1',
        quality: SleepQuality.good,
        frontingMemberId: 'alice',
      );
      expect(result.isSuccess, isTrue);

      // Sleep session should be ended with quality recorded
      final endedSleep = repo.sessions.where((s) => s.id == 'sleep-1').single;
      expect(endedSleep.endTime, isNotNull);
      expect(endedSleep.quality, SleepQuality.good);

      // A new fronting session should exist for the selected member
      final frontingSessions = repo.sessions
          .where((s) => s.id != 'sleep-1')
          .toList();
      expect(frontingSessions, hasLength(1));
      final fronting = frontingSessions.single;
      expect(fronting.memberId, 'alice');
      expect(fronting.isSleep, isFalse);
      expect(fronting.isActive, isTrue);
    });

    test('wakeUp rejects a fronting session', () async {
      final repo = FakeFrontingSessionRepository();
      final fronting = FrontingSession(
        id: 'front-1',
        startTime: DateTime(2026, 3, 11, 10),
        memberId: 'alice',
      );
      await repo.createSession(fronting);

      final svc = FrontingMutationService(
        repository: repo,
        mutationRunner: MutationRunner(
          transactionRunner: _passthroughTransactionRunner,
        ),
      );

      final result = await svc.wakeUp('front-1');
      expect(result.isFailure, isTrue);
    });

    test('repository sync payloads include raw PK member ids JSON', () async {
      final recorded = <Map<String, Object?>>[];
      final recordingRepo = _RecordingFrontingSessionRepository(
        db.frontingSessionsDao,
        null,
        recorded,
      );
      final session = FrontingSession(
        id: 'pk-session',
        startTime: DateTime.utc(2026, 4, 23, 12),
        memberId: 'local-a',
        pkMemberIdsJson: '["pkA","pkB"]',
      );

      await recordingRepo.createSession(session);
      await recordingRepo.updateSession(
        session.copyWith(notes: 'updated', pkMemberIdsJson: '["pkA"]'),
      );

      expect(recorded, hasLength(2));
      expect(recorded.first['operation'], 'create');
      expect(recorded.first['table'], 'fronting_sessions');
      expect(recorded.first['entityId'], 'pk-session');
      expect(
        (recorded.first['fields']!
            as Map<String, dynamic>)['pk_member_ids_json'],
        '["pkA","pkB"]',
      );
      expect(recorded.last['operation'], 'update');
      expect(
        (recorded.last['fields']!
            as Map<String, dynamic>)['pk_member_ids_json'],
        '["pkA"]',
      );
    });
  });
}

class _RecordingFrontingSessionRepository
    extends DriftFrontingSessionRepository {
  _RecordingFrontingSessionRepository(
    super.dao,
    super.syncHandle,
    this.records,
  );

  final List<Map<String, Object?>> records;

  @override
  Future<void> syncRecordCreate(
    String table,
    String entityId,
    Map<String, dynamic> fields,
  ) async {
    records.add({
      'operation': 'create',
      'table': table,
      'entityId': entityId,
      'fields': Map<String, dynamic>.from(fields),
    });
  }

  @override
  Future<void> syncRecordUpdate(
    String table,
    String entityId,
    Map<String, dynamic> fields,
  ) async {
    records.add({
      'operation': 'update',
      'table': table,
      'entityId': entityId,
      'fields': Map<String, dynamic>.from(fields),
    });
  }
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
