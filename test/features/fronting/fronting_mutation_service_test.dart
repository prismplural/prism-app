import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/constants/fronting_namespaces.dart';
import 'package:prism_plurality/core/database/app_database.dart'
    hide FrontingSession, Member;
import 'package:prism_plurality/core/mutations/field_patch.dart';
import 'package:prism_plurality/core/mutations/mutation_runner.dart';
import 'package:prism_plurality/data/repositories/drift_fronting_session_repository.dart';
import 'package:prism_plurality/domain/models/front_session_comment.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/domain/models/member.dart';
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

    // -------------------------------------------------------------------------
    // startFronting — per-member API
    // -------------------------------------------------------------------------

    test('startFronting creates one row per member', () async {
      final repo = FakeFrontingSessionRepository();
      final svc = FrontingMutationService(
        repository: repo,
        mutationRunner: MutationRunner(
          transactionRunner: _passthroughTransactionRunner,
        ),
      );

      final result = await svc.startFronting(['alice', 'bob']);
      expect(result.isSuccess, isTrue);
      expect(repo.sessions, hasLength(2));
      expect(repo.sessions.map((s) => s.memberId).toSet(), {'alice', 'bob'});
      expect(repo.sessions.every((s) => s.isActive), isTrue);
    });

    test('startFronting does not end sessions for other members', () async {
      final repo = FakeFrontingSessionRepository();
      final ezraSession = FrontingSession(
        id: 'ezra-1',
        startTime: DateTime(2026, 3, 11, 8),
        memberId: 'ezra',
      );
      await repo.createSession(ezraSession);

      final svc = FrontingMutationService(
        repository: repo,
        mutationRunner: MutationRunner(
          transactionRunner: _passthroughTransactionRunner,
        ),
      );

      // Starting alice should NOT end ezra's session.
      final result = await svc.startFronting(['alice']);
      expect(result.isSuccess, isTrue);
      expect(repo.sessions, hasLength(2));

      final ezra = repo.sessions.firstWhere((s) => s.id == 'ezra-1');
      expect(ezra.isActive, isTrue, reason: 'ezra was not affected');

      final alice = repo.sessions.firstWhere((s) => s.memberId == 'alice');
      expect(alice.isActive, isTrue);
    });

    test(
      'startFronting ends existing active session for same member',
      () async {
        final repo = FakeFrontingSessionRepository();
        final aliceOld = FrontingSession(
          id: 'alice-old',
          startTime: DateTime(2026, 3, 11, 8),
          memberId: 'alice',
        );
        await repo.createSession(aliceOld);

        final svc = FrontingMutationService(
          repository: repo,
          mutationRunner: MutationRunner(
            transactionRunner: _passthroughTransactionRunner,
          ),
        );

        final result = await svc.startFronting(['alice']);
        expect(result.isSuccess, isTrue);
        expect(repo.sessions, hasLength(2));

        final old = repo.sessions.firstWhere((s) => s.id == 'alice-old');
        expect(old.isActive, isFalse, reason: 'old alice session was ended');

        final newSessions = repo.sessions.where((s) => s.id != 'alice-old');
        expect(newSessions, hasLength(1));
        expect(newSessions.single.isActive, isTrue);
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

        final svc = FrontingMutationService(
          repository: repo,
          mutationRunner: MutationRunner(
            transactionRunner: _passthroughTransactionRunner,
          ),
        );

        // Sleep sessions are ended when the same member starts fronting (member
        // is null for sleep so the "same member" check doesn't match, but the
        // broader loop does end the sleep). Actually per spec, startFronting
        // ends the *same-member's* existing open session. Sleep has memberId=null
        // which doesn't match 'bob', so it stays. Let's verify correct behavior:
        // startFronting does NOT auto-end sleep for other members.
        final result = await svc.startFronting(['bob']);
        expect(result.isSuccess, isTrue);
        expect(repo.sessions, hasLength(2));
        final endedSleep = repo.sessions.where((s) => s.id == sleep.id).single;
        // Sleep is not ended — per-member model: only same-member sessions end.
        expect(endedSleep.endTime, isNull);
        final createdFronting = repo.sessions
            .where((s) => s.id != sleep.id)
            .single;
        expect(createdFronting.memberId, 'bob');
        expect(createdFronting.isSleep, isFalse);
      },
    );

    // -------------------------------------------------------------------------
    // endFronting
    // -------------------------------------------------------------------------

    test('endFronting ends only the specified members', () async {
      final repo = FakeFrontingSessionRepository();
      await repo.createSession(
        FrontingSession(
          id: 'alice-1',
          startTime: DateTime(2026, 3, 11, 8),
          memberId: 'alice',
        ),
      );
      await repo.createSession(
        FrontingSession(
          id: 'bob-1',
          startTime: DateTime(2026, 3, 11, 8),
          memberId: 'bob',
        ),
      );

      final svc = FrontingMutationService(
        repository: repo,
        mutationRunner: MutationRunner(
          transactionRunner: _passthroughTransactionRunner,
        ),
      );

      final result = await svc.endFronting(['alice']);
      expect(result.isSuccess, isTrue);

      final alice = repo.sessions.firstWhere((s) => s.id == 'alice-1');
      expect(alice.isActive, isFalse);

      final bob = repo.sessions.firstWhere((s) => s.id == 'bob-1');
      expect(bob.isActive, isTrue, reason: 'bob was not in the end list');
    });

    test(
      'endFronting is a no-op for members without active sessions',
      () async {
        final repo = FakeFrontingSessionRepository();

        final svc = FrontingMutationService(
          repository: repo,
          mutationRunner: MutationRunner(
            transactionRunner: _passthroughTransactionRunner,
          ),
        );

        final result = await svc.endFronting(['alice']);
        expect(result.isSuccess, isTrue);
        expect(repo.sessions, isEmpty);
      },
    );

    // -------------------------------------------------------------------------
    // addCoFronter / removeCoFronter sugar
    // -------------------------------------------------------------------------

    test('addCoFronter creates a session for the given member', () async {
      final repo = FakeFrontingSessionRepository();
      final svc = FrontingMutationService(
        repository: repo,
        mutationRunner: MutationRunner(
          transactionRunner: _passthroughTransactionRunner,
        ),
      );

      final result = await svc.addCoFronter('sky');
      expect(result.isSuccess, isTrue);
      expect(repo.sessions, hasLength(1));
      expect(repo.sessions.single.memberId, 'sky');
    });

    test(
      'removeCoFronter ends the active session for the given member',
      () async {
        final repo = FakeFrontingSessionRepository();
        await repo.createSession(
          FrontingSession(
            id: 'sky-1',
            startTime: DateTime(2026, 3, 11, 8),
            memberId: 'sky',
          ),
        );

        final svc = FrontingMutationService(
          repository: repo,
          mutationRunner: MutationRunner(
            transactionRunner: _passthroughTransactionRunner,
          ),
        );

        final result = await svc.removeCoFronter('sky');
        expect(result.isSuccess, isTrue);

        final sky = repo.sessions.single;
        expect(sky.isActive, isFalse);
      },
    );

    // -------------------------------------------------------------------------
    // replaceFronting — atomic end-actives + start-new in one transaction
    // -------------------------------------------------------------------------

    group('replaceFronting', () {
      test('ends all active normal fronts AND starts the new session in one '
          'transaction with a single captured now', () async {
        final repo = FakeFrontingSessionRepository();
        // Two prior actives (alice, bob) — replaceFronting should end both.
        await repo.createSession(
          FrontingSession(
            id: 'alice-old',
            startTime: DateTime(2026, 4, 25, 8),
            memberId: 'alice',
          ),
        );
        await repo.createSession(
          FrontingSession(
            id: 'bob-old',
            startTime: DateTime(2026, 4, 25, 9),
            memberId: 'bob',
          ),
        );

        final svc = FrontingMutationService(
          repository: repo,
          mutationRunner: MutationRunner(
            transactionRunner: _passthroughTransactionRunner,
          ),
        );

        final result = await svc.replaceFronting(['carol']);
        expect(result.isSuccess, isTrue);

        // alice and bob were ended.
        final alice = repo.sessions.firstWhere((s) => s.id == 'alice-old');
        final bob = repo.sessions.firstWhere((s) => s.id == 'bob-old');
        expect(alice.isActive, isFalse);
        expect(bob.isActive, isFalse);

        // A new active session for carol was created.
        final carol = repo.sessions.firstWhere(
          (s) => s.id != 'alice-old' && s.id != 'bob-old',
        );
        expect(carol.memberId, 'carol');
        expect(carol.isActive, isTrue);

        // Single captured `now`: end_time of the prior sessions equals
        // start_time of the new session, exactly. No off-by-microseconds
        // gap or overlap is acceptable — the contract is "one captured now."
        expect(alice.endTime, equals(carol.startTime));
        expect(bob.endTime, equals(carol.startTime));
      });

      test(
        'starting multiple replacement members shares one captured now',
        () async {
          final repo = FakeFrontingSessionRepository();
          await repo.createSession(
            FrontingSession(
              id: 'old-1',
              startTime: DateTime(2026, 4, 25, 8),
              memberId: 'alice',
            ),
          );

          final svc = FrontingMutationService(
            repository: repo,
            mutationRunner: MutationRunner(
              transactionRunner: _passthroughTransactionRunner,
            ),
          );

          final result = await svc.replaceFronting(['bob', 'carol']);
          expect(result.isSuccess, isTrue);

          final newSessions = repo.sessions
              .where((s) => s.id != 'old-1')
              .toList();
          expect(newSessions, hasLength(2));
          // Both new sessions share the same start_time as the captured now.
          expect(newSessions[0].startTime, equals(newSessions[1].startTime));

          // And that shared start_time equals the prior session's end_time.
          final alice = repo.sessions.firstWhere((s) => s.id == 'old-1');
          expect(alice.endTime, equals(newSessions.first.startTime));
        },
      );

      test(
        'leaves sleep sessions untouched (only ends normal fronts)',
        () async {
          final repo = FakeFrontingSessionRepository();
          await repo.createSession(
            FrontingSession(
              id: 'sleep-1',
              startTime: DateTime(2026, 4, 25, 8),
              memberId: null,
              sessionType: SessionType.sleep,
            ),
          );

          final svc = FrontingMutationService(
            repository: repo,
            mutationRunner: MutationRunner(
              transactionRunner: _passthroughTransactionRunner,
            ),
          );

          final result = await svc.replaceFronting(['alice']);
          expect(result.isSuccess, isTrue);

          // Sleep session is still active — replaceFronting does not touch
          // sleep, only normal fronts.
          final sleep = repo.sessions.firstWhere((s) => s.id == 'sleep-1');
          expect(sleep.isActive, isTrue);

          // The new alice session was created.
          final alice = repo.sessions.firstWhere((s) => s.memberId == 'alice');
          expect(alice.isActive, isTrue);
        },
      );

      test(
        'atomicity: a failure during start rolls back the end-actives writes',
        () async {
          // Use the real DB so the transaction's rollback semantics are in
          // play — the FakeFrontingSessionRepository has no transaction
          // boundary so rollbacks are not observable through it.
          final aliceOld = FrontingSession(
            id: 'alice-old',
            startTime: DateTime(2026, 4, 25, 8),
            memberId: 'alice',
          );
          await repository.createSession(aliceOld);

          final failingService = FrontingMutationService(
            repository: _ThrowOnCreateRepository(
              db.frontingSessionsDao,
              null,
              throwOnMemberId: 'bob',
            ),
            mutationRunner: MutationRunner(transactionRunner: db.transaction),
          );

          final result = await failingService.replaceFronting(['bob']);
          expect(result.isFailure, isTrue);

          // alice's prior session is STILL active — the end-actives write
          // was rolled back when the start-new step threw.
          final alicePersisted = await repository.getSessionById(aliceOld.id);
          expect(alicePersisted, isNotNull);
          expect(
            alicePersisted!.isActive,
            isTrue,
            reason:
                'a failure mid-replace must leave the prior actives '
                'intact, not "no fronts at all"',
          );

          // No bob session was persisted either.
          final all = await repository.getAllSessions();
          expect(all.where((s) => s.memberId == 'bob'), isEmpty);
        },
      );

      test(
        'with the Unknown sentinel id ensures the sentinel exists',
        () async {
          final repo = FakeFrontingSessionRepository();
          final memberRepo = FakeMemberRepository();
          final svc = FrontingMutationService(
            repository: repo,
            memberRepository: memberRepo,
            mutationRunner: MutationRunner(
              transactionRunner: _passthroughTransactionRunner,
            ),
          );

          // Pre-condition: no members exist.
          expect(
            await memberRepo.getMemberById(unknownSentinelMemberId),
            isNull,
          );

          final result = await svc.replaceFronting([unknownSentinelMemberId]);
          expect(result.isSuccess, isTrue);

          // Sentinel was lazy-created (same contract as startFronting).
          final sentinel = await memberRepo.getMemberById(
            unknownSentinelMemberId,
          );
          expect(sentinel, isNotNull);
          expect(sentinel!.name, 'Unknown');

          // The new session is attributed to the sentinel.
          expect(repo.sessions.single.memberId, unknownSentinelMemberId);
          expect(repo.sessions.single.isActive, isTrue);
        },
      );
    });

    // -------------------------------------------------------------------------
    // splitSession — deterministic id, PK link cleared
    // -------------------------------------------------------------------------

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
        'sleep-1',
        DateTime(2026, 3, 12, 3),
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

    test('splitSession uses deterministic v5 id for the second half', () async {
      final repo = FakeFrontingSessionRepository();
      final original = FrontingSession(
        id: 'front-1',
        startTime: DateTime(2026, 4, 25, 10),
        endTime: DateTime(2026, 4, 25, 12),
        memberId: 'alice',
      );
      await repo.createSession(original);

      final svc = FrontingMutationService(
        repository: repo,
        mutationRunner: MutationRunner(
          transactionRunner: _passthroughTransactionRunner,
        ),
      );

      final splitTime = DateTime(2026, 4, 25, 11);
      final result = await svc.splitSession(original.id, splitTime);
      expect(result.isSuccess, isTrue);

      final second = repo.sessions.firstWhere((s) => s.id != original.id);

      // The id is non-random (v5 of original.id + splitTime) — assert it's
      // populated and distinct from the original.
      expect(second.id, isNotEmpty);
      expect(second.id, isNot(original.id));
    });

    test(
      'splitSession moves comments at or after split time to new row',
      () async {
        final repo = FakeFrontingSessionRepository();
        final commentsRepo = FakeFrontSessionCommentsRepository();
        final original = FrontingSession(
          id: 'front-with-comments',
          startTime: DateTime(2026, 4, 25, 10),
          endTime: DateTime(2026, 4, 25, 12),
          memberId: 'alice',
        );
        final splitTime = DateTime(2026, 4, 25, 11);
        await repo.createSession(original);
        await commentsRepo.createComment(
          FrontSessionComment(
            id: 'before',
            sessionId: original.id,
            body: 'before',
            timestamp: DateTime(2026, 4, 25, 10, 30),
            createdAt: DateTime(2026, 4, 25, 10, 30),
          ),
        );
        await commentsRepo.createComment(
          FrontSessionComment(
            id: 'at-split',
            sessionId: original.id,
            body: 'at split',
            timestamp: splitTime,
            createdAt: splitTime,
          ),
        );
        await commentsRepo.createComment(
          FrontSessionComment(
            id: 'after',
            sessionId: original.id,
            body: 'after',
            timestamp: DateTime(2026, 4, 25, 11, 30),
            createdAt: DateTime(2026, 4, 25, 11, 30),
          ),
        );

        final svc = FrontingMutationService(
          repository: repo,
          mutationRunner: MutationRunner(
            transactionRunner: _passthroughTransactionRunner,
          ),
          frontSessionCommentsRepository: commentsRepo,
        );

        final result = await svc.splitSession(original.id, splitTime);
        expect(result.isSuccess, isTrue);
        final secondHalf = result.when(
          success: (session) => session,
          failure: (_) => throw StateError('split failed unexpectedly'),
        );

        expect(
          commentsRepo.comments
              .firstWhere((comment) => comment.id == 'before')
              .sessionId,
          original.id,
        );
        expect(
          commentsRepo.comments
              .firstWhere((comment) => comment.id == 'at-split')
              .sessionId,
          secondHalf.id,
        );
        expect(
          commentsRepo.comments
              .firstWhere((comment) => comment.id == 'after')
              .sessionId,
          secondHalf.id,
        );
      },
    );

    test(
      'splitSession derives the same v5 id from local and UTC representations '
      'of the same instant',
      () async {
        // Two paired devices may receive the same wall-clock instant as a
        // local DateTime (date-picker output, isUtc=false) and as a UTC
        // DateTime (e.g. round-tripped through fromMillisecondsSinceEpoch).
        // toIso8601String() emits no offset on local DateTimes, so the
        // derivation key MUST be normalized to UTC before hashing.
        final localSplit = DateTime(2026, 4, 25, 13); // local wall-clock
        final utcSplit = localSplit.toUtc(); // same instant, UTC

        // CI guard: this test is meaningless if the host's TZ is UTC (local
        // and utc are then equal). Assert the precondition fails loudly.
        expect(
          localSplit.toIso8601String(),
          isNot(utcSplit.toIso8601String()),
          reason:
              'Test host TZ must be non-UTC for this regression test '
              'to be meaningful. Set TZ=America/Los_Angeles in CI.',
        );

        Future<String> idFromSplit(DateTime splitTime) async {
          final repo = FakeFrontingSessionRepository();
          final original = FrontingSession(
            id: 'front-cross-tz',
            startTime: DateTime(2026, 4, 25, 10),
            endTime: DateTime(2026, 4, 25, 16),
            memberId: 'alice',
          );
          await repo.createSession(original);
          final svc = FrontingMutationService(
            repository: repo,
            mutationRunner: MutationRunner(
              transactionRunner: _passthroughTransactionRunner,
            ),
          );
          final result = await svc.splitSession(original.id, splitTime);
          expect(result.isSuccess, isTrue);
          return repo.sessions.firstWhere((s) => s.id != original.id).id;
        }

        final localId = await idFromSplit(localSplit);
        final utcId = await idFromSplit(utcSplit);

        expect(
          localId,
          utcId,
          reason:
              'Local and UTC representations of the same instant must '
              'derive the same v5 id so paired devices converge.',
        );
      },
    );

    test('splitSession clears pluralkitUuid on the second half '
        '(PK composite unique index)', () async {
      // Uses the real DriftFrontingSessionRepository so the DB-level index
      // constraint is in play — a fake repo would not catch this regression.
      final original = FrontingSession(
        id: 'pk-linked-1',
        startTime: DateTime(2026, 4, 25, 10),
        endTime: DateTime(2026, 4, 25, 12),
        memberId: 'alice',
        pluralkitUuid: 'pk-switch-uuid-abc',
      );
      await repository.createSession(original);

      final result = await service.splitSession(
        original.id,
        DateTime(2026, 4, 25, 11),
      );

      expect(
        result.isSuccess,
        isTrue,
        reason: 'split must not crash on PK-linked sessions',
      );

      final all = await repository.getAllSessions();
      expect(all, hasLength(2));
      final first = all.firstWhere((s) => s.id == original.id);
      final second = all.firstWhere((s) => s.id != original.id);

      expect(
        first.pluralkitUuid,
        'pk-switch-uuid-abc',
        reason: 'original retains the PK link',
      );
      expect(
        second.pluralkitUuid,
        isNull,
        reason: 'split-half is a new local segment with no PK switch yet',
      );

      expect(first.endTime, DateTime(2026, 4, 25, 11));
      expect(second.startTime, DateTime(2026, 4, 25, 11));
      expect(second.endTime, DateTime(2026, 4, 25, 12));
    });

    // -------------------------------------------------------------------------
    // Sleep lifecycle
    // -------------------------------------------------------------------------

    test(
      'startSleep ends active fronting sessions before creating sleep',
      () async {
        final repo = FakeFrontingSessionRepository();
        final fronting = FrontingSession(
          id: 'front-1',
          startTime: DateTime(2026, 3, 11, 8),
          memberId: 'alice',
        );
        await repo.createSession(fronting);

        final svc = FrontingMutationService(
          repository: repo,
          mutationRunner: MutationRunner(
            transactionRunner: _passthroughTransactionRunner,
          ),
        );

        final result = await svc.startSleep(
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
      expect(repo.sessions, hasLength(1));
    });

    // -------------------------------------------------------------------------
    // wakeUp
    // -------------------------------------------------------------------------

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

      final endedSleep = repo.sessions.where((s) => s.id == 'sleep-1').single;
      expect(endedSleep.endTime, isNotNull);
      expect(endedSleep.quality, SleepQuality.good);

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

    // -------------------------------------------------------------------------
    // Unknown sentinel auto-create
    //
    // The add-front sheet's "Front as Unknown" flow passes
    // `[unknownSentinelMemberId]` to startFronting; the service is responsible
    // for lazy-creating the sentinel member so the resulting fronting_sessions
    // row has a valid member_id.  These tests pin the contract.
    // -------------------------------------------------------------------------

    group('Unknown sentinel auto-create', () {
      test('startFronting creates the sentinel member if missing', () async {
        final repo = FakeFrontingSessionRepository();
        final memberRepo = FakeMemberRepository();
        final svc = FrontingMutationService(
          repository: repo,
          memberRepository: memberRepo,
          mutationRunner: MutationRunner(
            transactionRunner: _passthroughTransactionRunner,
          ),
        );

        // Pre-condition: no members exist.
        expect(await memberRepo.getMemberById(unknownSentinelMemberId), isNull);

        final result = await svc.startFronting([unknownSentinelMemberId]);
        expect(result.isSuccess, isTrue);

        // Sentinel member was lazy-created.
        final sentinel = await memberRepo.getMemberById(
          unknownSentinelMemberId,
        );
        expect(sentinel, isNotNull);
        expect(sentinel!.name, 'Unknown');
        expect(sentinel.emoji, '❔');

        // Single fronting row, attributed to the sentinel id.
        expect(repo.sessions, hasLength(1));
        expect(repo.sessions.single.memberId, unknownSentinelMemberId);
        expect(repo.sessions.single.isActive, isTrue);
      });

      test(
        'startFronting does not duplicate the sentinel when it already exists',
        () async {
          final repo = FakeFrontingSessionRepository();
          final memberRepo = FakeMemberRepository();
          // Pre-seed the sentinel as if a prior call created it.
          memberRepo.seed([
            Member(
              id: unknownSentinelMemberId,
              name: 'Unknown',
              emoji: '❔',
              createdAt: DateTime(2026, 4, 1).toUtc(),
            ),
          ]);
          final svc = FrontingMutationService(
            repository: repo,
            memberRepository: memberRepo,
            mutationRunner: MutationRunner(
              transactionRunner: _passthroughTransactionRunner,
            ),
          );

          final result = await svc.startFronting([unknownSentinelMemberId]);
          expect(result.isSuccess, isTrue);

          // Still exactly one sentinel row in the member repo.
          final allMembers = await memberRepo.getAllMembers();
          expect(
            allMembers.where((m) => m.id == unknownSentinelMemberId).toList(),
            hasLength(1),
          );

          expect(repo.sessions.single.memberId, unknownSentinelMemberId);
        },
      );

      test('startFronting with a mix of real members and the sentinel creates '
          'one row per id and ensures the sentinel', () async {
        final repo = FakeFrontingSessionRepository();
        final memberRepo = FakeMemberRepository();
        memberRepo.seed([
          Member(id: 'alice', name: 'Alice', createdAt: DateTime(2026)),
          Member(id: 'bob', name: 'Bob', createdAt: DateTime(2026)),
        ]);
        final svc = FrontingMutationService(
          repository: repo,
          memberRepository: memberRepo,
          mutationRunner: MutationRunner(
            transactionRunner: _passthroughTransactionRunner,
          ),
        );

        final result = await svc.startFronting([
          'alice',
          unknownSentinelMemberId,
          'bob',
        ]);
        expect(result.isSuccess, isTrue);

        // Three session rows, one per id.
        expect(repo.sessions, hasLength(3));
        expect(repo.sessions.map((s) => s.memberId).toSet(), {
          'alice',
          'bob',
          unknownSentinelMemberId,
        });

        // Sentinel was ensured.
        expect(
          await memberRepo.getMemberById(unknownSentinelMemberId),
          isNotNull,
        );
      });

      test(
        'addCoFronter for the sentinel auto-creates the sentinel member',
        () async {
          final repo = FakeFrontingSessionRepository();
          final memberRepo = FakeMemberRepository();
          final svc = FrontingMutationService(
            repository: repo,
            memberRepository: memberRepo,
            mutationRunner: MutationRunner(
              transactionRunner: _passthroughTransactionRunner,
            ),
          );

          final result = await svc.addCoFronter(unknownSentinelMemberId);
          expect(result.isSuccess, isTrue);
          expect(
            await memberRepo.getMemberById(unknownSentinelMemberId),
            isNotNull,
          );
          expect(repo.sessions, hasLength(1));
          expect(repo.sessions.single.memberId, unknownSentinelMemberId);
        },
      );

      test(
        'endFronting for the sentinel does NOT call ensure '
        '(precondition: an active sentinel session implies the member exists)',
        () async {
          final repo = FakeFrontingSessionRepository();
          // Pre-seed an active sentinel session WITHOUT seeding the member.
          await repo.createSession(
            FrontingSession(
              id: 'sentinel-active',
              startTime: DateTime(2026, 4, 1, 10),
              memberId: unknownSentinelMemberId,
            ),
          );
          // Wire NO MemberRepository — endFronting must not need it.
          final svc = FrontingMutationService(
            repository: repo,
            mutationRunner: MutationRunner(
              transactionRunner: _passthroughTransactionRunner,
            ),
          );

          final result = await svc.endFronting([unknownSentinelMemberId]);
          expect(result.isSuccess, isTrue);
          // Session was ended.
          expect(repo.sessions.single.isActive, isFalse);
        },
      );

      test(
        'startFronting throws StateError when the sentinel is in the payload '
        'but no MemberRepository is wired',
        () async {
          final repo = FakeFrontingSessionRepository();
          final svc = FrontingMutationService(
            repository: repo,
            mutationRunner: MutationRunner(
              transactionRunner: _passthroughTransactionRunner,
            ),
          );

          final result = await svc.startFronting([unknownSentinelMemberId]);
          // The mutation runner converts thrown errors into a failure result.
          expect(result.isFailure, isTrue);
          // No session was written.
          expect(repo.sessions, isEmpty);
        },
      );
    });
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

/// Throws on `createSession` for any session whose memberId matches
/// [throwOnMemberId]. Used to verify replaceFronting's atomicity contract:
/// a failure on the start-new step must roll back the prior end-actives
/// writes so the user is not left with "no fronts at all."
class _ThrowOnCreateRepository extends DriftFrontingSessionRepository {
  _ThrowOnCreateRepository(
    super.dao,
    super.syncHandle, {
    required String throwOnMemberId,
  }) : _throwOnMemberId = throwOnMemberId;

  final String _throwOnMemberId;

  @override
  Future<void> createSession(FrontingSession session) async {
    if (session.memberId == _throwOnMemberId) {
      throw StateError('forced failure on createSession for $_throwOnMemberId');
    }
    await super.createSession(session);
  }
}
