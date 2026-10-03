import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/domain/preferences/preference_registry.dart';

final keepFrontingDuringSleepProvider =
    AsyncNotifierProvider<KeepFrontingDuringSleepNotifier, bool>(
      KeepFrontingDuringSleepNotifier.new,
    );

class KeepFrontingDuringSleepNotifier extends AsyncNotifier<bool> {
  @override
  Future<bool> build() async {
    final repo = ref.watch(appPreferenceRepositoryProvider);
    final subscription = repo
        .watch(keepFrontingDuringSleepPreference)
        .listen(
          (value) => state = AsyncValue.data(value),
          onError: (Object error, StackTrace stackTrace) {
            state = AsyncValue.error(error, stackTrace);
          },
        );
    ref.onDispose(subscription.cancel);
    return repo.get(keepFrontingDuringSleepPreference);
  }

  Future<void> set(bool value) async {
    await ref
        .read(appPreferenceRepositoryProvider)
        .set(keepFrontingDuringSleepPreference, value);
    if (ref.mounted) state = AsyncValue.data(value);
  }
}
