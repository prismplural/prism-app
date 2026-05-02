import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/mutations/app_failure.dart';
import 'package:prism_plurality/core/mutations/mutation_runner.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/features/fronting/services/fronting_mutation_service.dart';
import '../../../helpers/fake_repositories.dart';

Future<T> _passthrough<T>(Future<T> Function() action) => action();

void main() {
  group('logHistoricalSleep', () {
    late FakeFrontingSessionRepository repo;
    late FrontingMutationService service;

    setUp(() {
      repo = FakeFrontingSessionRepository();
      service = FrontingMutationService(
        repository: repo,
        mutationRunner: MutationRunner(transactionRunner: _passthrough),
      );
    });

    final past = DateTime(2026, 4, 28, 22);
    final laterPast = DateTime(2026, 4, 29, 6);

    test('endTime before startTime returns validation failure', () async {
      final result = await service.logHistoricalSleep(
        startTime: laterPast,
        endTime: past,
      );
      expect(result.isFailure, isTrue);
      expect(result.failureOrNull!.type, AppFailureType.validation);
    });

    test('endTime equal to startTime returns validation failure', () async {
      final result = await service.logHistoricalSleep(
        startTime: past,
        endTime: past,
      );
      expect(result.isFailure, isTrue);
      expect(result.failureOrNull!.type, AppFailureType.validation);
    });

    test('startTime strictly in future returns validation failure', () async {
      final future = DateTime.now().add(const Duration(minutes: 5));
      final result = await service.logHistoricalSleep(
        startTime: future,
        endTime: future.add(const Duration(hours: 8)),
      );
      expect(result.isFailure, isTrue);
      expect(result.failureOrNull!.type, AppFailureType.validation);
    });

    test(
      'valid call creates exactly one sleep session via createSession',
      () async {
        int createCalls = 0;
        final countingRepo = _CountingFrontingSessionRepository(
          repo,
          onCreateSession: () => createCalls++,
        );
        final svc = FrontingMutationService(
          repository: countingRepo,
          mutationRunner: MutationRunner(transactionRunner: _passthrough),
        );

        final result = await svc.logHistoricalSleep(
          startTime: past,
          endTime: laterPast,
          quality: SleepQuality.good,
          notes: 'slept well',
        );

        expect(result.isSuccess, isTrue);
        expect(createCalls, 1, reason: 'must be exactly one createSession call');

        final session = result.dataOrNull!;
        expect(session.sessionType, SessionType.sleep);
        expect(session.endTime, isNotNull);
        expect(session.isActive, isFalse);
        expect(session.quality, SleepQuality.good);
        expect(session.notes, 'slept well');
        expect(session.startTime, past);
        expect(session.endTime, laterPast);
      },
    );

    test(
      'overlapping existing sleep session does not throw; returns new session',
      () async {
        final existing = FrontingSession(
          id: 'existing-sleep',
          startTime: DateTime(2026, 4, 28, 21),
          endTime: DateTime(2026, 4, 28, 23),
          memberId: null,
          sessionType: SessionType.sleep,
        );
        await repo.createSession(existing);

        final result = await service.logHistoricalSleep(
          startTime: DateTime(2026, 4, 28, 22),
          endTime: DateTime(2026, 4, 29, 6),
        );

        expect(result.isSuccess, isTrue);
        expect(result.dataOrNull!.sessionType, SessionType.sleep);
        expect(result.dataOrNull!.isActive, isFalse);
        expect(repo.sessions, hasLength(2));
      },
    );
  });
}

class _CountingFrontingSessionRepository extends FakeFrontingSessionRepository {
  _CountingFrontingSessionRepository(
    this._delegate, {
    required this.onCreateSession,
  });

  final FakeFrontingSessionRepository _delegate;
  final void Function() onCreateSession;

  @override
  List<FrontingSession> get sessions => _delegate.sessions;

  @override
  Future<void> createSession(FrontingSession session) async {
    onCreateSession();
    await _delegate.createSession(session);
  }

  @override
  Future<FrontingSession?> getSessionById(String id) =>
      _delegate.getSessionById(id);

  @override
  Future<void> updateSession(FrontingSession session) =>
      _delegate.updateSession(session);

  @override
  Future<void> endSession(String id, DateTime endTime) =>
      _delegate.endSession(id, endTime);

  @override
  Future<void> deleteSession(String id) => _delegate.deleteSession(id);

  @override
  Future<List<FrontingSession>> getAllActiveSessionsUnfiltered() =>
      _delegate.getAllActiveSessionsUnfiltered();
}
