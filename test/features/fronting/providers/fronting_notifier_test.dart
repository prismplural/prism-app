import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/mutations/mutation_result.dart';
import 'package:prism_plurality/core/mutations/mutation_runner.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_providers.dart';
import 'package:prism_plurality/features/fronting/services/fronting_mutation_service.dart';
import 'package:prism_plurality/features/members/providers/member_stats_providers.dart';

import '../../../helpers/fake_repositories.dart';

class _FakeWakeUpMutationService extends FrontingMutationService {
  _FakeWakeUpMutationService(this.result)
    : super(
        repository: FakeFrontingSessionRepository(),
        mutationRunner: MutationRunner(
          transactionRunner: <T>(action) => action(),
        ),
      );

  final FrontingMutationResult? result;
  final calls =
      <
        ({String sleepSessionId, SleepQuality? quality, List<String> memberIds})
      >[];

  @override
  Future<MutationResult<FrontingMutationResult?>> wakeUp(
    String sleepSessionId, {
    SleepQuality? quality,
    List<String> frontingMemberIds = const [],
  }) async {
    calls.add((
      sleepSessionId: sleepSessionId,
      quality: quality,
      memberIds: List<String>.from(frontingMemberIds),
    ));
    return MutationResult.success(result);
  }
}

void main() {
  group('FrontingNotifier', () {
    test('wakeUp invalidates stats for new and displaced members', () async {
      final service = _FakeWakeUpMutationService(
        FrontingMutationResult(
          sessions: [
            FrontingSession(
              id: 'new-session',
              startTime: DateTime(2026, 3, 11, 9),
              memberId: 'new',
            ),
          ],
          previousMemberIds: ['old'],
        ),
      );
      final statsBuilds = <String, int>{};
      final recentBuilds = <String, int>{};

      final container = ProviderContainer(
        overrides: [
          frontingMutationServiceProvider.overrideWithValue(service),
          memberFrontingStatsProvider.overrideWith((ref, memberId) async {
            statsBuilds.update(
              memberId,
              (count) => count + 1,
              ifAbsent: () => 1,
            );
            return const MemberFrontingStats(
              totalSessions: 0,
              totalDuration: Duration.zero,
            );
          }),
          memberRecentSessionsProvider.overrideWith((ref, memberId) async {
            recentBuilds.update(
              memberId,
              (count) => count + 1,
              ifAbsent: () => 1,
            );
            return const <FrontingSession>[];
          }),
        ],
      );
      addTearDown(container.dispose);

      final subscriptions = [
        container.listen(
          memberFrontingStatsProvider('new'),
          (_, _) {},
          fireImmediately: true,
        ),
        container.listen(
          memberFrontingStatsProvider('old'),
          (_, _) {},
          fireImmediately: true,
        ),
        container.listen(
          memberRecentSessionsProvider('new'),
          (_, _) {},
          fireImmediately: true,
        ),
        container.listen(
          memberRecentSessionsProvider('old'),
          (_, _) {},
          fireImmediately: true,
        ),
      ];
      addTearDown(() {
        for (final subscription in subscriptions) {
          subscription.close();
        }
      });

      await container.read(memberFrontingStatsProvider('new').future);
      await container.read(memberFrontingStatsProvider('old').future);
      await container.read(memberRecentSessionsProvider('new').future);
      await container.read(memberRecentSessionsProvider('old').future);
      expect(statsBuilds, {'new': 1, 'old': 1});
      expect(recentBuilds, {'new': 1, 'old': 1});

      await container
          .read(frontingNotifierProvider.notifier)
          .wakeUp(
            'sleep-1',
            quality: SleepQuality.good,
            frontingMemberIds: ['new'],
          );

      expect(service.calls, hasLength(1));
      expect(service.calls.single.sleepSessionId, 'sleep-1');
      expect(service.calls.single.quality, SleepQuality.good);
      expect(service.calls.single.memberIds, ['new']);

      await container.read(memberFrontingStatsProvider('new').future);
      await container.read(memberFrontingStatsProvider('old').future);
      await container.read(memberRecentSessionsProvider('new').future);
      await container.read(memberRecentSessionsProvider('old').future);
      expect(statsBuilds, {'new': 2, 'old': 2});
      expect(recentBuilds, {'new': 2, 'old': 2});
    });
  });
}
