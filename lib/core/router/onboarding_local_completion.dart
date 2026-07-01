import 'package:flutter_riverpod/flutter_riverpod.dart';

/// True when onboarding finished locally on this device, as opposed to
/// `hasCompletedOnboarding` arriving over sync on a freshly paired device.
/// The redirect guard reads it to let a locally-finished empty system into the
/// app while still holding a synced-in device until its members arrive.
/// In-memory: only the completion -> home transition needs it, and it must be
/// reset on a wipe (see reset_data_provider).
class LocalOnboardingCompletion extends Notifier<bool> {
  @override
  bool build() => false;

  void mark() => state = true;
}

final localOnboardingCompletionProvider =
    NotifierProvider<LocalOnboardingCompletion, bool>(
      LocalOnboardingCompletion.new,
    );
