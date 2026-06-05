import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/domain/preferences/preference_registry.dart';

/// Synced app preference for dimming behind modal side sheets.
final dimBackgroundBehindSheetsProvider =
    AsyncNotifierProvider<DimBackgroundBehindSheetsNotifier, bool>(
      DimBackgroundBehindSheetsNotifier.new,
    );

class DimBackgroundBehindSheetsNotifier extends AsyncNotifier<bool> {
  @override
  Future<bool> build() async {
    final repo = ref.watch(appPreferenceRepositoryProvider);
    final initial = await repo.get(dimBackgroundBehindSheetsPreference);
    final subscription = repo
        .watch(dimBackgroundBehindSheetsPreference)
        .listen(
          (value) {
            state = AsyncValue.data(value);
          },
          onError: (Object error, StackTrace stackTrace) {
            state = AsyncValue.error(error, stackTrace);
          },
        );
    ref.onDispose(subscription.cancel);
    return initial;
  }

  Future<void> set(bool value) async {
    await ref
        .read(appPreferenceRepositoryProvider)
        .set(dimBackgroundBehindSheetsPreference, value);
    state = AsyncValue.data(value);
  }
}

/// Synced app preference for preferring centered/mobile modal sheets on wide
/// windows instead of trailing modal side sheets.
final forceCenteredSheetsProvider =
    AsyncNotifierProvider<ForceCenteredSheetsNotifier, bool>(
      ForceCenteredSheetsNotifier.new,
    );

class ForceCenteredSheetsNotifier extends AsyncNotifier<bool> {
  @override
  Future<bool> build() async {
    final repo = ref.watch(appPreferenceRepositoryProvider);
    final initial = await repo.get(forceCenteredSheetsPreference);
    final subscription = repo
        .watch(forceCenteredSheetsPreference)
        .listen(
          (value) {
            state = AsyncValue.data(value);
          },
          onError: (Object error, StackTrace stackTrace) {
            state = AsyncValue.error(error, stackTrace);
          },
        );
    ref.onDispose(subscription.cancel);
    return initial;
  }

  Future<void> set(bool value) async {
    await ref
        .read(appPreferenceRepositoryProvider)
        .set(forceCenteredSheetsPreference, value);
    state = AsyncValue.data(value);
  }
}
