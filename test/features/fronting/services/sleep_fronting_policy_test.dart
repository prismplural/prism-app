import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/mutations/mutation_runner.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/features/fronting/services/fronting_mutation_service.dart';

import '../../../helpers/fake_repositories.dart';

void main() {
  late FakeFrontingSessionRepository repo;
  late FrontingMutationService service;
  final started = DateTime(2026, 3, 11, 8);
  final bedtime = DateTime(2026, 3, 11, 22);

  setUp(() {
    repo = FakeFrontingSessionRepository();
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
