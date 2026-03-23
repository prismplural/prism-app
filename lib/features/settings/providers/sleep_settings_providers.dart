import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/domain/models/models.dart';

/// Notifier for sleep tracking enabled state.
class SleepTrackingEnabledNotifier extends Notifier<bool> {
  @override
  bool build() => true;

  void toggle(bool value) {
    state = value;
  }
}

final sleepTrackingEnabledProvider =
    NotifierProvider<SleepTrackingEnabledNotifier, bool>(
        SleepTrackingEnabledNotifier.new);

/// Notifier for default sleep quality setting.
class DefaultSleepQualityNotifier extends Notifier<SleepQuality> {
  @override
  SleepQuality build() => SleepQuality.unknown;

  void set(SleepQuality value) {
    state = value;
  }
}

final defaultSleepQualityProvider =
    NotifierProvider<DefaultSleepQualityNotifier, SleepQuality>(
        DefaultSleepQualityNotifier.new);
