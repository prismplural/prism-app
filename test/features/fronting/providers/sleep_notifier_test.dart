import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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
