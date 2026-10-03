import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/domain/preferences/preference_registry.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/core/mutations/app_failure.dart';
import 'package:prism_plurality/core/mutations/mutation_result.dart';
import 'package:prism_plurality/core/mutations/mutation_runner.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_providers.dart';
import 'package:prism_plurality/features/fronting/providers/sleep_providers.dart';
import 'package:prism_plurality/features/fronting/services/fronting_mutation_service.dart';

import '../../../helpers/fake_repositories.dart';

class _FakeSleepMutationService extends FrontingMutationService {
  _FakeSleepMutationService(this.endSleepResult)
    : super(
        repository: FakeFrontingSessionRepository(),
        mutationRunner: MutationRunner(
          transactionRunner: <T>(action) => action(),
        ),
      );

  final MutationResult<void> endSleepResult;
  final endedIds = <String>[];

  @override
  Future<MutationResult<void>> endSleep(String id) async {
    endedIds.add(id);
    return endSleepResult;
  }
}

void main() {
  group('SleepNotifier', () {
    for (final keepFronters in [false, true]) {
      test(
        'startSleep reads saved preservation preference $keepFronters',
        () async {
          final prefs = FakeAppPreferenceRepository()
            ..seed(keepFrontingDuringSleepPreference, keepFronters);
          addTearDown(prefs.close);
          final repo = FakeFrontingSessionRepository();
          final start = DateTime(2026, 3, 11, 8);
          repo.sessions.add(
            FrontingSession(
              id: 'existing',
              memberId: 'alice',
              startTime: start,
            ),
          );
          final service = FrontingMutationService(
            repository: repo,
            mutationRunner: MutationRunner(
              transactionRunner: <T>(action) => action(),
            ),
          );
          final container = ProviderContainer(
            overrides: [
              appPreferenceRepositoryProvider.overrideWithValue(prefs),
              frontingMutationServiceProvider.overrideWithValue(service),
            ],
          );
          addTearDown(container.dispose);
          await container
              .read(sleepNotifierProvider.notifier)
              .startSleep(startTime: start.add(const Duration(hours: 1)));
          expect(
            repo.sessions.singleWhere((s) => s.id == 'existing').isActive,
            keepFronters,
          );
          expect(
            repo.sessions.where((s) => s.isSleep && s.isActive),
            hasLength(1),
          );
        },
      );
    }

    test(
      'endSleep throws when the mutation service returns a failure',
      () async {
        final failure = AppFailure.validation('Could not end sleep.');
        final service = _FakeSleepMutationService(
          MutationResult.failure(failure),
        );
        final container = ProviderContainer(
          overrides: [
            frontingMutationServiceProvider.overrideWithValue(service),
          ],
        );
        addTearDown(container.dispose);

        await expectLater(
          container.read(sleepNotifierProvider.notifier).endSleep('sleep-1'),
          throwsA(same(failure)),
        );
        expect(service.endedIds, ['sleep-1']);
      },
    );
  });
}
