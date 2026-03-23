import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Visual rendering policy for glass surfaces and decorative effects.
enum VisualEffectsMode {
  /// Full blur and animation effects.
  full,
  /// Tinted glass only — no live backdrop blur. Better performance.
  reduced,
  /// High contrast, no blur, minimal translucency. Accessibility-safe.
  accessible,
}

/// User's explicit preference for visual effects quality.
/// `null` means "auto" (follow platform accessibility signals).
final visualEffectsPreferenceProvider =
    NotifierProvider<VisualEffectsPreferenceNotifier, VisualEffectsMode?>(
        VisualEffectsPreferenceNotifier.new);

class VisualEffectsPreferenceNotifier extends Notifier<VisualEffectsMode?> {
  @override
  VisualEffectsMode? build() => null;
  void set(VisualEffectsMode? value) => state = value;
}

/// Resolved visual effects mode, combining user preference with platform signals.
extension VisualEffectsModeX on VisualEffectsMode {
  static VisualEffectsMode of(BuildContext context, WidgetRef ref) {
    final explicit = ref.watch(visualEffectsPreferenceProvider);
    if (explicit != null) return explicit;

    final mq = MediaQuery.of(context);
    if (mq.highContrast) return VisualEffectsMode.accessible;
    if (mq.disableAnimations) return VisualEffectsMode.reduced;
    return VisualEffectsMode.full;
  }

  bool get useBlur => this == VisualEffectsMode.full;
  bool get useAnimations => this != VisualEffectsMode.accessible;
  bool get highContrast => this == VisualEffectsMode.accessible;
}
