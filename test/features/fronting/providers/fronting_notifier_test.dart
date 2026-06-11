import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/mutations/mutation_result.dart';
import 'package:prism_plurality/core/mutations/mutation_runner.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_providers.dart';
import 'package:prism_plurality/features/fronting/services/fronting_mutation_service.dart';
import 'package:prism_plurality/features/members/providers/member_stats_providers.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';

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

class _FakeStartReplaceMutationService extends FrontingMutationService {
  _FakeStartReplaceMutationService()
    : super(
        repository: FakeFrontingSessionRepository(),
        mutationRunner: MutationRunner(
          transactionRunner: <T>(action) => action(),
        ),
      );

  final startCalls =
      <
        ({
          List<String> memberIds,
          DateTime? startTime,
          FrontConfidence? confidence,
          String? notes,
        })
      >[];
  final replaceCalls =
      <
        ({
          List<String> memberIds,
          DateTime? now,
          FrontConfidence? confidence,
          String? notes,
          int quickSwitchThresholdSeconds,
        })
      >[];

  @override
  Future<MutationResult<FrontingMutationResult>> startFronting(
    List<String> memberIds, {
    DateTime? startTime,
    FrontConfidence? confidence,
    String? notes,
  }) async {
    startCalls.add((
      memberIds: List<String>.from(memberIds),
      startTime: startTime,
      confidence: confidence,
      notes: notes,
    ));
    return MutationResult.success(
      FrontingMutationResult(
        sessions: [
          for (final id in memberIds)
            FrontingSession(
              id: 'start-$id',
              startTime: startTime ?? DateTime(2026, 3, 11, 9),
              memberId: id,
              confidence: confidence,
              notes: notes,
            ),
        ],
        previousMemberIds: const [],
      ),
    );
  }

  @override
  Future<MutationResult<FrontingMutationResult>> replaceFronting(
    List<String> memberIds, {
    DateTime? now,
    FrontConfidence? confidence,
    String? notes,
    int quickSwitchThresholdSeconds = 0,
  }) async {
    replaceCalls.add((
      memberIds: List<String>.from(memberIds),
      now: now,
      confidence: confidence,
      notes: notes,
      quickSwitchThresholdSeconds: quickSwitchThresholdSeconds,
    ));
    return MutationResult.success(
      FrontingMutationResult(
        sessions: [
          for (final id in memberIds)
            FrontingSession(
              id: 'replace-$id',
              startTime: now ?? DateTime(2026, 3, 11, 9),
              memberId: id,
              confidence: confidence,
              notes: notes,
            ),
        ],
        previousMemberIds: const ['old'],
      ),
    );
  }
}

void main() {
  group('FrontingNotifier', () {
    test(
      'startFronting forwards explicit startTime to mutation service',
      () async {
        final service = _FakeStartReplaceMutationService();
        final container = ProviderContainer(
          overrides: [
            frontingMutationServiceProvider.overrideWithValue(service),
            frontingRemindersEnabledProvider.overrideWith((_) => false),
          ],
        );
        addTearDown(container.dispose);

        final startTime = DateTime(2026, 3, 11, 8, 45);
        await container
            .read(frontingNotifierProvider.notifier)
            .startFronting(
              ['member-a'],
              startTime: startTime,
              confidence: FrontConfidence.unsure,
              notes: 'woke up unsure',
            );

        expect(service.startCalls, hasLength(1));
        final call = service.startCalls.single;
        expect(call.memberIds, ['member-a']);
        expect(call.startTime, startTime);
        expect(call.confidence, FrontConfidence.unsure);
        expect(call.notes, 'woke up unsure');
        expect(service.replaceCalls, isEmpty);
      },
    );

    test(
      'replaceFronting forwards explicit startTime and quick-switch setting',
      () async {
        final service = _FakeStartReplaceMutationService();
        final container = ProviderContainer(
          overrides: [
            frontingMutationServiceProvider.overrideWithValue(service),
            quickSwitchThresholdProvider.overrideWithValue(73),
            frontingRemindersEnabledProvider.overrideWith((_) => false),
          ],
        );
        addTearDown(container.dispose);

        final startTime = DateTime(2026, 3, 11, 8, 45);
        await container
            .read(frontingNotifierProvider.notifier)
            .replaceFronting(
              ['member-a'],
              startTime: startTime,
              confidence: FrontConfidence.unsure,
              notes: 'woke up unsure',
            );

        expect(service.replaceCalls, hasLength(1));
        final call = service.replaceCalls.single;
        expect(call.memberIds, ['member-a']);
        expect(call.now, startTime);
        expect(call.confidence, FrontConfidence.unsure);
        expect(call.notes, 'woke up unsure');
        expect(call.quickSwitchThresholdSeconds, 73);
        expect(service.startCalls, isEmpty);
      },
    );

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
