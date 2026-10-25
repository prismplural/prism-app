import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/app_database.dart'
    hide FrontingSession, Member;
import 'package:prism_plurality/core/mutations/app_failure.dart';
import 'package:prism_plurality/data/repositories/drift_fronting_session_repository.dart';
import 'package:prism_plurality/data/repositories/sync_record_mixin.dart';

import 'package:prism_plurality/core/mutations/mutation_runner.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/features/fronting/services/fronting_mutation_service.dart';

import '../../../helpers/fake_repositories.dart';

void main() {
  _syncEmissionTests();
  late _RecordingFrontingRepository repo;
  late FrontingMutationService service;
  final started = DateTime(2026, 3, 11, 8);
  final bedtime = DateTime(2026, 3, 11, 22);

  setUp(() {
    repo = _RecordingFrontingRepository();
    final members = FakeMemberRepository()
      ..seed([
        Member(id: 'alice', name: 'Alice', createdAt: started),
        Member(id: 'bob', name: 'Bob', createdAt: started),
        Member(id: 'carol', name: 'Carol', createdAt: started),
        Member(
          id: 'host',
          name: 'Host',
          createdAt: started,
          isAlwaysFronting: true,
        ),
      ]);
    repo.sessions.addAll([
      for (final id in ['alice', 'bob', 'host'])
        FrontingSession(id: '$id-front', memberId: id, startTime: started),
    ]);
    service = FrontingMutationService(
      repository: repo,
      memberRepository: members,
      mutationRunner: MutationRunner(
        transactionRunner: <T>(action) => action(),
      ),
    );
  });

  FrontingSession row(String id) =>
      repo.sessions.singleWhere((s) => s.id == id);

  for (final offset in [const Duration(hours: -1), Duration.zero]) {
    test(
      'sleep at or before front start rejects without writes ($offset)',
      () async {
        final before = List<FrontingSession>.of(repo.sessions);
        final result = await service.startSleep(startTime: started.add(offset));

        expect(result.isFailure, isTrue);
        expect(result.failureOrNull?.type, AppFailureType.validation);
        expect(result.failureOrNull?.message, contains('after start time'));
        expect(repo.sessions, before);
        expect(repo.writes, isEmpty);
      },
    );
  }

  for (final keepFronters in [false, true]) {
    test(
      'validates every closure before writing (keep=$keepFronters)',
      () async {
        // Alice can end at 07:00, but the later row cannot. Even a repository
        // without rollback must never receive the earlier valid write.
        repo.sessions[0] = row(
          'alice-front',
        ).copyWith(startTime: started.subtract(const Duration(hours: 2)));
        if (keepFronters) {
          repo.sessions.add(
            FrontingSession(
              id: 'old-sleep',
              startTime: started,
              sessionType: SessionType.sleep,
            ),
          );
        }
        final before = List<FrontingSession>.of(repo.sessions);
        final result = await service.startSleep(
          startTime: started.subtract(const Duration(hours: 1)),
          keepCurrentFronters: keepFronters,
        );

        expect(result.isFailure, isTrue);
        expect(repo.sessions, before);
        expect(repo.writes, isEmpty);
      },
    );
  }

  test('preservation still validates ordinary duplicate closures', () async {
    repo.sessions.add(
      FrontingSession(
        id: 'alice-duplicate',
        memberId: 'alice',
        startTime: started.add(const Duration(hours: 1)),
      ),
    );
    final before = List<FrontingSession>.of(repo.sessions);
    final result = await service.startSleep(
      startTime: started.subtract(const Duration(hours: 1)),
      keepCurrentFronters: true,
    );
    expect(result.isFailure, isTrue);
    expect(repo.sessions, before);
    expect(repo.writes, isEmpty);
  });

  test('preserved fronts do not block an earlier sleep start', () async {
    final result = await service.startSleep(
      startTime: started.subtract(const Duration(hours: 1)),
      keepCurrentFronters: true,
    );
    expect(result.isSuccess, isTrue);
    for (final id in ['alice', 'bob', 'host']) {
      expect(row('$id-front').endTime, isNull);
      expect(row('$id-front').startTime, started);
    }
    expect(repo.writes, ['create']);
  });

  test(
    'always-present duplicate closure rejects rather than creating zero duration',
    () async {
      repo.sessions.add(
        FrontingSession(
          id: 'host-duplicate',
          memberId: 'host',
          startTime: bedtime,
        ),
      );
      final before = List<FrontingSession>.of(repo.sessions);
      final result = await service.startSleep(
        startTime: bedtime,
        keepCurrentFronters: true,
      );
      expect(result.isFailure, isTrue);
      expect(repo.sessions, before);
      expect(repo.writes, isEmpty);
    },
  );

  test(
    'default sleep ends ordinary sessions and retains always-present',
    () async {
      final result = await service.startSleep(startTime: bedtime);
      expect(result.isSuccess, isTrue);
      expect(row('alice-front').endTime, bedtime);
      expect(row('bob-front').endTime, bedtime);
      expect(row('host-front').endTime, isNull);
    },
  );

  test(
    'preservation keeps latest ordinary and earliest always-present sessions',
    () async {
      repo.sessions.addAll([
        FrontingSession(
          id: 'alice-duplicate',
          memberId: 'alice',
          startTime: started.add(const Duration(hours: 1)),
        ),
        FrontingSession(
          id: 'host-duplicate',
          memberId: 'host',
          startTime: started.add(const Duration(hours: 1)),
        ),
        FrontingSession(
          id: 'old-sleep',
          startTime: started,
          sessionType: SessionType.sleep,
        ),
      ]);
      final result = await service.startSleep(
        startTime: bedtime,
        keepCurrentFronters: true,
      );

      expect(result.isSuccess, isTrue);
      for (final id in ['bob', 'host']) {
        expect(row('$id-front').endTime, isNull);
        expect(row('$id-front').startTime, started);
      }
      expect(row('alice-front').endTime, bedtime);
      expect(row('alice-duplicate').endTime, isNull);
      expect(row('host-duplicate').endTime, bedtime);
      expect(row('old-sleep').endTime, bedtime);
      expect(repo.sessions.where((s) => s.isSleep && s.isActive), hasLength(1));
    },
  );

  test(
    'wake-up reuses selected sessions, ends deselections and starts new selections',
    () async {
      final sleep = (await service.startSleep(
        startTime: bedtime,
        keepCurrentFronters: true,
      )).dataOrNull!.sessions.single;
      final result = await service.wakeUp(
        sleep.id,
        frontingMemberIds: ['alice', 'carol'],
        keepCurrentFronters: true,
      );

      expect(result.isSuccess, isTrue);
      expect(row(sleep.id).endTime, isNotNull);
      expect(row('alice-front').endTime, isNull);
      expect(row('alice-front').startTime, started);
      expect(row('bob-front').endTime, isNotNull);
      expect(row('host-front').endTime, isNull);
      final carol = repo.sessions.singleWhere((s) => s.memberId == 'carol');
      expect(carol.isActive, isTrue);
      expect(carol.startTime, row(sleep.id).endTime);
      expect(
        result.dataOrNull!.sessions.map((s) => s.id),
        contains('alice-front'),
      );
    },
  );

  test(
    'deselecting everyone ends ordinary fronts without ending always-present',
    () async {
      final sleep = (await service.startSleep(
        startTime: bedtime,
        keepCurrentFronters: true,
      )).dataOrNull!.sessions.single;
      final result = await service.wakeUp(sleep.id, keepCurrentFronters: true);
      expect(result.isSuccess, isTrue);
      expect(row('alice-front').endTime, isNotNull);
      expect(row('bob-front').endTime, isNotNull);
      expect(row('host-front').endTime, isNull);
    },
  );

  test(
    'ending sleep without changing fronters retains their sessions',
    () async {
      final sleep = (await service.startSleep(
        startTime: bedtime,
        keepCurrentFronters: true,
      )).dataOrNull!.sessions.single;
      await service.endSleep(sleep.id);
      expect(row(sleep.id).endTime, isNotNull);
      for (final id in ['alice', 'bob', 'host']) {
        expect(row('$id-front').endTime, isNull);
        expect(row('$id-front').startTime, started);
      }
    },
  );
}

class _RecordingFrontingRepository extends FakeFrontingSessionRepository {
  final writes = <String>[];

  @override
  Future<void> createSession(FrontingSession session) async {
    writes.add('create');
    await super.createSession(session);
  }

  @override
  Future<void> endSession(String id, DateTime endTime) async {
    writes.add('end:$id');
    await super.endSession(id, endTime);
  }
}

void _syncEmissionTests() {
  group('sleep range sync boundary', () {
    late AppDatabase db;
    late DriftFrontingSessionRepository repo;
    late FrontingMutationService service;
    final start = DateTime(2026, 3, 11, 8);

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      repo = DriftFrontingSessionRepository(db.frontingSessionsDao, null);
      service = FrontingMutationService(
        repository: repo,
        mutationRunner: MutationRunner(transactionRunner: db.transaction),
      );
      await repo.createSession(
        FrontingSession(
          id: 'early',
          memberId: 'alice',
          startTime: start.subtract(const Duration(hours: 2)),
        ),
      );
      await repo.createSession(
        FrontingSession(id: 'late', memberId: 'bob', startTime: start),
      );
    });
    tearDown(() => db.close());

    test(
      'invalid sleep emits no sync operations and leaves all rows unchanged',
      () async {
        final before = await repo.getAllSessions();
        final ops = <CapturedSyncOp>[];
        final result = await SyncRecordMixin.suppressAndCapture(
          () => service.startSleep(
            startTime: start.subtract(const Duration(hours: 1)),
          ),
          ops.add,
        );
        expect(result.isFailure, isTrue);
        expect(result.failureOrNull?.type, AppFailureType.validation);
        expect(await repo.getAllSessions(), unorderedEquals(before));
        expect(ops, isEmpty);
      },
    );

    test('valid sleep emits two valid ends and one sleep create', () async {
      final ops = <CapturedSyncOp>[];
      final sleepStart = start.add(const Duration(hours: 1));
      final result = await SyncRecordMixin.suppressAndCapture(
        () => service.startSleep(startTime: sleepStart),
        ops.add,
      );
      expect(result.isSuccess, isTrue);
      expect(ops.map((op) => op.opType), [
        SyncRecordOpType.update,
        SyncRecordOpType.update,
        SyncRecordOpType.create,
      ]);
      expect(ops.every((op) => op.table == 'fronting_sessions'), isTrue);
      final rows = await repo.getAllSessions();
      expect(rows, hasLength(3));
      for (final row in rows.where((row) => !row.isSleep)) {
        expect(row.endTime, sleepStart);
        expect(row.endTime!.isAfter(row.startTime), isTrue);
      }
      expect(rows.singleWhere((row) => row.isSleep).startTime, sleepStart);
    });
  });
}
