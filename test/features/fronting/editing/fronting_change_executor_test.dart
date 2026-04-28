import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/constants/fronting_namespaces.dart';
import 'package:prism_plurality/core/database/app_database.dart'
    hide FrontingSession;
import 'package:prism_plurality/core/mutations/mutation_runner.dart';
import 'package:prism_plurality/data/repositories/drift_fronting_session_repository.dart';
import 'package:prism_plurality/data/repositories/drift_member_repository.dart';
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

  // ════════════════════════════════════════════════════════════════════════════
  // Unknown sentinel ensure-on-write integration
  //
  // These tests exercise the production write path end-to-end against a real
  // in-memory Drift DB.  The change-builder tests in
  // fronting_edit_resolution_service_test.dart only assert that the change
  // descriptors carry [unknownSentinelMemberId]; they do NOT prove the
  // executor actually creates the sentinel member row before applying the
  // session writes.  This group pins that contract — if a future refactor
  // breaks _ensureSentinelIfNeeded, these tests fail before users hit a
  // dangling-FK scenario.
  // ════════════════════════════════════════════════════════════════════════════
  group('FrontingChangeExecutor — Unknown sentinel ensure', () {
    late AppDatabase db;
    late DriftFrontingSessionRepository sessionRepo;
    late DriftMemberRepository memberRepo;
    late FrontingChangeExecutor executor;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      sessionRepo = DriftFrontingSessionRepository(
        db.frontingSessionsDao,
        null,
      );
      // Sync handle is null so syncRecord* calls are no-ops.
      memberRepo = DriftMemberRepository(db.membersDao, null);
      executor = FrontingChangeExecutor(
        repository: sessionRepo,
        mutationRunner: MutationRunner(transactionRunner: db.transaction),
        memberRepository: memberRepo,
      );
    });

    tearDown(() async {
      await db.close();
    });

    test(
      'CreateSessionChange referencing the sentinel id auto-creates the '
      'sentinel member and the session in the same transaction',
      () async {
        // Pre-condition: no Unknown sentinel member exists yet.
        expect(
          await memberRepo.getMemberById(unknownSentinelMemberId),
          isNull,
        );

        final draft = FrontingSessionDraft(
          memberId: unknownSentinelMemberId,
          start: DateTime(2026, 4, 27, 10),
          end: DateTime(2026, 4, 27, 11),
        );

        final result = await executor.execute([CreateSessionChange(draft)]);
        expect(result.isSuccess, isTrue);

        // Sentinel member is now present.
        final sentinel =
            await memberRepo.getMemberById(unknownSentinelMemberId);
        expect(sentinel, isNotNull);
        expect(sentinel!.id, unknownSentinelMemberId);

        // Session row is present and references the sentinel.
        final sessions = await sessionRepo.getAllSessions();
        expect(sessions, hasLength(1));
        expect(sessions.first.memberId, unknownSentinelMemberId);
      },
    );

    test(
      'UpdateSessionChange with patch.memberId = sentinel auto-creates the '
      'sentinel member',
      () async {
        // Seed a session whose member is some other id.
        final seed = FrontingSessionDraft(
          memberId: 'alice',
          start: DateTime(2026, 4, 27, 9),
          end: DateTime(2026, 4, 27, 10),
        );
        final seedResult =
            await executor.execute([CreateSessionChange(seed)]);
        expect(seedResult.isSuccess, isTrue);
        final sessionId = (await sessionRepo.getAllSessions()).first.id;

        // Pre-condition: sentinel still doesn't exist.
        expect(
          await memberRepo.getMemberById(unknownSentinelMemberId),
          isNull,
        );

        // Convert to Unknown via the sentinel id.
        final patch =
            FrontingSessionPatch(memberId: unknownSentinelMemberId);
        final result = await executor.execute([
          UpdateSessionChange(sessionId: sessionId, patch: patch),
        ]);
        expect(result.isSuccess, isTrue);

        // Sentinel member exists now.
        expect(
          await memberRepo.getMemberById(unknownSentinelMemberId),
          isNotNull,
        );

        // Session now points at the sentinel.
        final updated = await sessionRepo.getSessionById(sessionId);
        expect(updated, isNotNull);
        expect(updated!.memberId, unknownSentinelMemberId);
      },
    );

    test(
      'sentinel ensure is idempotent: a second sentinel-referencing change '
      'does not duplicate the member',
      () async {
        // First create — sentinel must be created.
        await executor.execute([
          CreateSessionChange(FrontingSessionDraft(
            memberId: unknownSentinelMemberId,
            start: DateTime(2026, 4, 27, 10),
            end: DateTime(2026, 4, 27, 11),
          )),
        ]);
        // Second create — sentinel must still resolve to the same row.
        await executor.execute([
          CreateSessionChange(FrontingSessionDraft(
            memberId: unknownSentinelMemberId,
            start: DateTime(2026, 4, 27, 12),
            end: DateTime(2026, 4, 27, 13),
          )),
        ]);

        // Two sessions, one sentinel row.
        final sessions = await sessionRepo.getAllSessions();
        expect(sessions, hasLength(2));
        for (final s in sessions) {
          expect(s.memberId, unknownSentinelMemberId);
        }

        final all = await memberRepo.getAllMembers();
        final sentinels =
            all.where((m) => m.id == unknownSentinelMemberId).toList();
        expect(sentinels, hasLength(1));
      },
    );

    test(
      'no sentinel-referencing change → ensure helper is a no-op '
      '(sentinel is NOT created)',
      () async {
        final draft = FrontingSessionDraft(
          memberId: 'alice',
          start: DateTime(2026, 4, 27, 10),
          end: DateTime(2026, 4, 27, 11),
        );
        final result = await executor.execute([CreateSessionChange(draft)]);
        expect(result.isSuccess, isTrue);

        // Sentinel must remain absent — we never referenced it.
        expect(
          await memberRepo.getMemberById(unknownSentinelMemberId),
          isNull,
        );
      },
    );
  });
}
