import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/database/app_database.dart'
    hide FrontingSession;
import 'package:prism_plurality/core/mutations/mutation_runner.dart';
import 'package:prism_plurality/data/repositories/drift_fronting_session_repository.dart';
import 'package:prism_plurality/features/fronting/editing/fronting_change_executor.dart';
import 'package:prism_plurality/features/fronting/editing/fronting_session_change.dart';

void main() {
  group('FrontingChangeExecutor', () {
    late AppDatabase db;
    late DriftFrontingSessionRepository repository;
    late FrontingChangeExecutor executor;

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
    });

    tearDown(() async {
      await db.close();
    });

    test('constructs without error', () {
      expect(executor, isA<FrontingChangeExecutor>());
    });

    test('execute with empty list succeeds', () async {
      final result = await executor.execute([]);
      expect(result.isSuccess, isTrue);
    });

    test('execute CreateSessionChange creates a session', () async {
      final draft = FrontingSessionDraft(
        memberId: 'member-1',
        start: DateTime(2026, 3, 15, 10),
        end: DateTime(2026, 3, 15, 11),
        notes: 'test note',
        confidenceIndex: 1,
      );

      final result = await executor.execute([CreateSessionChange(draft)]);
      expect(result.isSuccess, isTrue);

      final sessions = await repository.getAllSessions();
      expect(sessions, hasLength(1));
      expect(sessions.first.memberId, equals('member-1'));
      expect(sessions.first.notes, equals('test note'));
    });

    test('execute DeleteSessionChange removes a session', () async {
      // First create a session directly
      final draft = FrontingSessionDraft(
        memberId: 'member-2',
        start: DateTime(2026, 3, 15, 8),
      );
      await executor.execute([CreateSessionChange(draft)]);
      final sessions = await repository.getAllSessions();
      expect(sessions, hasLength(1));

      final sessionId = sessions.first.id;
      final result =
          await executor.execute([DeleteSessionChange(sessionId)]);
      expect(result.isSuccess, isTrue);

      final remaining = await repository.getAllSessions();
      expect(remaining, isEmpty);
    });

    test('execute UpdateSessionChange updates a session', () async {
      final draft = FrontingSessionDraft(
        memberId: 'member-3',
        start: DateTime(2026, 3, 15, 9),
        notes: 'original note',
      );
      await executor.execute([CreateSessionChange(draft)]);
      final sessions = await repository.getAllSessions();
      final sessionId = sessions.first.id;

      const patch = FrontingSessionPatch(notes: 'updated note');
      final result = await executor.execute([
        UpdateSessionChange(sessionId: sessionId, patch: patch),
      ]);
      expect(result.isSuccess, isTrue);

      final updated = await repository.getSessionById(sessionId);
      expect(updated?.notes, equals('updated note'));
    });

    test('UpdateSessionChange with clearEnd sets endTime to null', () async {
      final draft = FrontingSessionDraft(
        memberId: 'member-4',
        start: DateTime(2026, 3, 15, 9),
        end: DateTime(2026, 3, 15, 10),
      );
      await executor.execute([CreateSessionChange(draft)]);
      final sessions = await repository.getAllSessions();
      final sessionId = sessions.first.id;

      const patch = FrontingSessionPatch(clearEnd: true);
      await executor.execute([
        UpdateSessionChange(sessionId: sessionId, patch: patch),
      ]);

      final updated = await repository.getSessionById(sessionId);
      expect(updated?.endTime, isNull);
      expect(updated?.isActive, isTrue);
    });

    test('UpdateSessionChange on missing session returns failure', () async {
      const patch = FrontingSessionPatch(notes: 'irrelevant');
      final result = await executor.execute([
        const UpdateSessionChange(
          sessionId: 'nonexistent-id',
          patch: patch,
        ),
      ]);
      expect(result.isFailure, isTrue);
    });

    test('multiple changes in one execute call are applied atomically',
        () async {
      final draft1 = FrontingSessionDraft(
        memberId: 'member-5',
        start: DateTime(2026, 3, 15, 6),
      );
      final draft2 = FrontingSessionDraft(
        memberId: 'member-6',
        start: DateTime(2026, 3, 15, 7),
      );

      final result = await executor.execute([
        CreateSessionChange(draft1),
        CreateSessionChange(draft2),
      ]);
      expect(result.isSuccess, isTrue);

      final sessions = await repository.getAllSessions();
      expect(sessions, hasLength(2));
    });
  });
}
