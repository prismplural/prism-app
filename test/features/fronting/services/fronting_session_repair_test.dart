import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/database/app_database.dart'
    hide FrontingSession, Member;
import 'package:prism_plurality/core/mutations/mutation_runner.dart';
import 'package:prism_plurality/data/repositories/drift_front_session_comments_repository.dart';
import 'package:prism_plurality/data/repositories/drift_fronting_session_repository.dart';
import 'package:prism_plurality/data/repositories/sync_record_mixin.dart';
import 'package:prism_plurality/domain/models/front_session_comment.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/features/fronting/services/fronting_mutation_service.dart';
import '../../../helpers/fake_repositories.dart';

Future<T> _passthroughTransactionRunner<T>(Future<T> Function() action) async {
  return action();
}

void main() {
  // ===========================================================================
  // repairMemberSessionInvariants — runs against a real in-memory Drift DB so
  // the field-diff, soft-delete, and comment-reparent behaviour is exercised
  // end to end (the same harness the logHistoricalFronting merge test uses).
  // ===========================================================================
  group('repairMemberSessionInvariants', () {
    late AppDatabase db;
    late DriftFrontingSessionRepository repository;
    late DriftFrontSessionCommentsRepository commentsRepository;
    late FrontingMutationService service;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      repository = DriftFrontingSessionRepository(db.frontingSessionsDao, null);
      commentsRepository = DriftFrontSessionCommentsRepository(
        db.frontSessionCommentsDao,
        null,
      );
      service = FrontingMutationService(
        repository: repository,
        mutationRunner: MutationRunner(transactionRunner: db.transaction),
        frontSessionCommentsRepository: commentsRepository,
      );
    });

    tearDown(() async {
      await db.close();
    });

    Future<void> open(String id, String memberId, DateTime start) {
      return repository.createSession(
        FrontingSession(id: id, startTime: start, memberId: memberId),
      );
    }

    Future<void> closed(
      String id,
      String memberId,
      DateTime start,
      DateTime end, {
      String? notes,
      FrontConfidence? confidence,
      String? pluralkitUuid,
    }) {
      return repository.createSession(
        FrontingSession(
          id: id,
          startTime: start,
          endTime: end,
          memberId: memberId,
          notes: notes,
          confidence: confidence,
          pluralkitUuid: pluralkitUuid,
        ),
      );
    }

    test(
      'collapses duplicate open sessions, keeping the most-recent open',
      () async {
        // The live "Melanie x4 open" shape: four opens at distinct starts.
        final starts = [
          DateTime(2026, 5, 20, 8),
          DateTime(2026, 5, 22, 9),
          DateTime(2026, 5, 25, 10),
          DateTime(2026, 5, 28, 11),
        ];
        for (var i = 0; i < starts.length; i++) {
          await open('mel-$i', 'melanie', starts[i]);
        }

        final result = await service.repairMemberSessionInvariants();
        expect(result.isSuccess, isTrue);
        expect(result.dataOrNull!.openDuplicatesClosed, 3);
        expect(result.dataOrNull!.membersAffected, 1);

        final sessions = await repository.getSessionsForMember('melanie');
        final stillOpen = sessions.where((s) => s.endTime == null).toList();
        expect(stillOpen, hasLength(1));
        expect(
          stillOpen.single.id,
          'mel-3',
          reason: 'the most-recently started open is kept',
        );
        // Earlier opens become a contiguous closed chain ending at the next
        // start — not merged away (touching, not overlapping).
        expect(sessions, hasLength(4));
        expect(sessions.singleWhere((s) => s.id == 'mel-0').endTime, starts[1]);
        expect(sessions.singleWhere((s) => s.id == 'mel-1').endTime, starts[2]);
        expect(sessions.singleWhere((s) => s.id == 'mel-2').endTime, starts[3]);
      },
    );

    test('repair is idempotent (second run is a no-op)', () async {
      await open('mel-0', 'melanie', DateTime(2026, 5, 20, 8));
      await open('mel-1', 'melanie', DateTime(2026, 5, 22, 9));
      await closed(
        'mel-old-a',
        'melanie',
        DateTime(2026, 4, 1, 8),
        DateTime(2026, 4, 1, 10),
      );
      await closed(
        'mel-old-b',
        'melanie',
        DateTime(2026, 4, 1, 9),
        DateTime(2026, 4, 1, 11),
      );

      final first = await service.repairMemberSessionInvariants();
      expect(first.dataOrNull!.madeChanges, isTrue);

      // A second pass must change nothing AND emit nothing — capture every
      // would-be sync op and assert the fronting table stays untouched.
      final captured = <CapturedSyncOp>[];
      SyncRecordMixin.installCaptureSinkForTesting(captured.add);
      addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

      final second = await service.repairMemberSessionInvariants();
      expect(second.dataOrNull!.madeChanges, isFalse);
      expect(second.dataOrNull!.openDuplicatesClosed, 0);
      expect(second.dataOrNull!.overlapsMerged, 0);
      expect(
        captured.where((o) => o.table == 'fronting_sessions'),
        isEmpty,
        reason: 'an idempotent re-run must not emit any sync ops',
      );
    });

    test('closes emit a synced end_time op (not local-only)', () async {
      await open('mel-0', 'melanie', DateTime(2026, 5, 20, 8));
      await open('mel-1', 'melanie', DateTime(2026, 5, 22, 9));

      // Install the sink AFTER seeding so only the repair's ops are captured.
      final captured = <CapturedSyncOp>[];
      SyncRecordMixin.installCaptureSinkForTesting(captured.add);
      addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

      await service.repairMemberSessionInvariants();

      final endOps = captured.where(
        (o) =>
            o.table == 'fronting_sessions' &&
            o.opType == SyncRecordOpType.update &&
            o.fields.containsKey('end_time') &&
            o.fields['end_time'] != null,
      );
      expect(
        endOps,
        isNotEmpty,
        reason: 'the collapsed open must close via a synced end_time op',
      );
    });

    test('merges strictly-overlapping same-member sessions, preserving notes, '
        'confidence and comments', () async {
      await closed(
        'a',
        'mel',
        DateTime(2026, 4, 1, 8),
        DateTime(2026, 4, 1, 10),
        notes: 'first',
      );
      await closed(
        'b',
        'mel',
        DateTime(2026, 4, 1, 9),
        DateTime(2026, 4, 1, 11),
        notes: 'second',
        confidence: FrontConfidence.strong,
      );
      await commentsRepository.createComment(
        FrontSessionComment(
          id: 'c1',
          sessionId: 'b',
          body: 'keep me',
          timestamp: DateTime(2026, 4, 1, 9, 30),
          createdAt: DateTime(2026, 4, 1, 9, 30),
        ),
      );

      final result = await service.repairMemberSessionInvariants();
      expect(result.dataOrNull!.overlapsMerged, 1);

      final sessions = await repository.getSessionsForMember('mel');
      expect(sessions, hasLength(1));
      final merged = sessions.single;
      expect(merged.id, 'a', reason: 'survivor is the earliest start');
      expect(merged.startTime, DateTime(2026, 4, 1, 8));
      expect(merged.endTime, DateTime(2026, 4, 1, 11));
      expect(merged.notes, 'first\n\nsecond');
      expect(merged.confidence, FrontConfidence.strong);

      final comments = await commentsRepository.getAllComments();
      expect(comments, hasLength(1));
      expect(comments.single.sessionId, 'a');
    });

    test('leaves adjacent (touching) same-member sessions distinct', () async {
      await closed(
        'a',
        'mel',
        DateTime(2026, 4, 1, 8),
        DateTime(2026, 4, 1, 10),
      );
      await closed(
        'b',
        'mel',
        DateTime(2026, 4, 1, 10), // touches a.end exactly
        DateTime(2026, 4, 1, 12),
      );

      final result = await service.repairMemberSessionInvariants();
      expect(result.dataOrNull!.madeChanges, isFalse);
      expect(await repository.getSessionsForMember('mel'), hasLength(2));
    });

    test('no-op repair stays fast for large clean same-member history', () async {
      final base = DateTime.utc(2024);
      final rows = [
        for (var i = 0; i < 50000; i++)
          FrontingSessionsCompanion.insert(
            id: 'history-$i',
            startTime: base.add(Duration(hours: i)),
            memberId: const Value('mel'),
            endTime: Value(base.add(Duration(hours: i, minutes: 30))),
          ),
      ];
      await db.batch((b) => b.insertAll(db.frontingSessions, rows));

      final stopwatch = Stopwatch()..start();
      final result = await service.repairMemberSessionInvariants();
      stopwatch.stop();

      expect(result.isSuccess, isTrue);
      expect(result.dataOrNull!.madeChanges, isFalse);
      expect(
        stopwatch.elapsed,
        lessThan(const Duration(seconds: 2)),
        reason:
            'startup repair must not monopolize the database before history streams emit',
      );
    });

    test('overlap merge keeps the PluralKit-linked row as survivor', () async {
      // Earlier row unlinked, later overlapping row carries the PK link. The
      // link must survive without moving the uuid onto a different row.
      await closed(
        'early',
        'mel',
        DateTime(2026, 4, 1, 8),
        DateTime(2026, 4, 1, 10),
      );
      await closed(
        'linked',
        'mel',
        DateTime(2026, 4, 1, 9),
        DateTime(2026, 4, 1, 11),
        pluralkitUuid: 'pk-123',
      );

      final result = await service.repairMemberSessionInvariants();
      expect(result.dataOrNull!.overlapsMerged, 1);

      final sessions = await repository.getSessionsForMember('mel');
      expect(sessions, hasLength(1));
      expect(sessions.single.id, 'linked');
      expect(sessions.single.pluralkitUuid, 'pk-123');
      expect(sessions.single.startTime, DateTime(2026, 4, 1, 8));
      expect(sessions.single.endTime, DateTime(2026, 4, 1, 11));
    });

    test('an overlapping closed row folds into the kept open', () async {
      // After collapse the member has one open; a pre-existing closed row that
      // overlaps the open should merge into it, yielding a single open span.
      await open('open-now', 'mel', DateTime(2026, 5, 1, 12));
      await closed(
        'overlapping-history',
        'mel',
        DateTime(2026, 5, 1, 10),
        DateTime(2026, 5, 1, 14), // strictly overlaps the open's 12:00 start
      );

      final result = await service.repairMemberSessionInvariants();
      expect(result.dataOrNull!.overlapsMerged, 1);

      final sessions = await repository.getSessionsForMember('mel');
      expect(sessions, hasLength(1));
      expect(sessions.single.endTime, isNull, reason: 'union stays open');
      expect(sessions.single.startTime, DateTime(2026, 5, 1, 10));
    });

    test('repairs members independently', () async {
      // melanie: two opens. ethan: two overlapping closed rows.
      await open('mel-0', 'melanie', DateTime(2026, 5, 20, 8));
      await open('mel-1', 'melanie', DateTime(2026, 5, 21, 8));
      await closed(
        'ethan-a',
        'ethan',
        DateTime(2026, 4, 1, 8),
        DateTime(2026, 4, 1, 11),
      );
      await closed(
        'ethan-b',
        'ethan',
        DateTime(2026, 4, 1, 10),
        DateTime(2026, 4, 1, 12),
      );

      final result = await service.repairMemberSessionInvariants();
      expect(result.dataOrNull!.membersAffected, 2);
      expect(result.dataOrNull!.openDuplicatesClosed, 1);
      expect(result.dataOrNull!.overlapsMerged, 1);

      expect(
        (await repository.getSessionsForMember(
          'melanie',
        )).where((s) => s.endTime == null),
        hasLength(1),
      );
      expect(await repository.getSessionsForMember('ethan'), hasLength(1));
    });

    test('no-op on already-clean data', () async {
      await open('mel-open', 'melanie', DateTime(2026, 5, 28, 11));
      await closed(
        'mel-history',
        'melanie',
        DateTime(2026, 5, 20, 8),
        DateTime(2026, 5, 21, 8),
      );

      final result = await service.repairMemberSessionInvariants();
      expect(result.dataOrNull!.madeChanges, isFalse);
      expect(result.dataOrNull!.membersAffected, 0);
      expect(await repository.getSessionsForMember('melanie'), hasLength(2));
    });
  });

  // ===========================================================================
  // Mutation-time invariant on the sleep / wake paths: an always-fronting
  // member with duplicate opens must end up with exactly one open session.
  // ===========================================================================
  group('one-open invariant on sleep/wake paths', () {
    test(
      'startSleep keeps one always-fronting open per member, closes duplicates',
      () async {
        final repo = FakeFrontingSessionRepository();
        final memberRepo = FakeMemberRepository();
        memberRepo.seed([
          Member(
            id: 'host',
            name: 'Host',
            createdAt: DateTime(2026),
            isAlwaysFronting: true,
          ),
        ]);
        await repo.createSession(
          FrontingSession(
            id: 'host-a',
            startTime: DateTime(2026, 3, 11, 8),
            memberId: 'host',
          ),
        );
        await repo.createSession(
          FrontingSession(
            id: 'host-b',
            startTime: DateTime(2026, 3, 11, 9),
            memberId: 'host',
          ),
        );

        final svc = FrontingMutationService(
          repository: repo,
          memberRepository: memberRepo,
          mutationRunner: MutationRunner(
            transactionRunner: _passthroughTransactionRunner,
          ),
        );

        await svc.startSleep(startTime: DateTime(2026, 3, 11, 22));

        final hostRows = repo.sessions.where((s) => s.memberId == 'host');
        expect(hostRows.where((s) => s.isActive), hasLength(1));
        expect(
          repo.sessions.singleWhere((s) => s.id == 'host-a').isActive,
          isTrue,
          reason: 'earliest persistent session preserved through sleep',
        );
        expect(
          repo.sessions.singleWhere((s) => s.id == 'host-b').isActive,
          isFalse,
          reason: 'duplicate open closed',
        );
      },
    );

    test('wakeUp keeps one always-fronting open per selected member, closes '
        'duplicates', () async {
      final repo = FakeFrontingSessionRepository();
      final memberRepo = FakeMemberRepository();
      memberRepo.seed([
        Member(
          id: 'host',
          name: 'Host',
          createdAt: DateTime(2026),
          isAlwaysFronting: true,
        ),
      ]);
      await repo.createSession(
        FrontingSession(
          id: 'host-a',
          startTime: DateTime(2026, 3, 11, 8),
          memberId: 'host',
        ),
      );
      await repo.createSession(
        FrontingSession(
          id: 'host-b',
          startTime: DateTime(2026, 3, 11, 9),
          memberId: 'host',
        ),
      );
      await repo.createSession(
        FrontingSession(
          id: 'sleep-1',
          startTime: DateTime(2026, 3, 11, 22),
          memberId: null,
          sessionType: SessionType.sleep,
        ),
      );

      final svc = FrontingMutationService(
        repository: repo,
        memberRepository: memberRepo,
        mutationRunner: MutationRunner(
          transactionRunner: _passthroughTransactionRunner,
        ),
      );

      final result = await svc.wakeUp('sleep-1', frontingMemberIds: ['host']);
      expect(result.isSuccess, isTrue);

      final hostRows = repo.sessions.where((s) => s.memberId == 'host');
      expect(hostRows.where((s) => s.isActive), hasLength(1));
      expect(
        repo.sessions.singleWhere((s) => s.id == 'host-a').isActive,
        isTrue,
      );
      expect(
        repo.sessions.singleWhere((s) => s.id == 'host-b').isActive,
        isFalse,
      );
      // The reused front is the preserved earliest session, not a new row.
      expect(result.dataOrNull!.sessions.map((s) => s.id), ['host-a']);
    });
  });
}
