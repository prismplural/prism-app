import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/core/services/screen_security_service.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';

/// Bridges [screenPrivacyEnabledProvider] (the user-visible toggle) to
/// [ScreenSecurityService.setGlobalEnabled] (the platform side).
///
/// Keep this provider warm via a `ref.listen` in `PrismApp.build()`. On
/// every settled value of the source provider, it forwards the boolean
/// to the service. The service is idempotent on equal values so noisy
/// rebuilds do not hammer the platform channel.
final screenPrivacyControllerProvider = Provider<void>((ref) {
  ref.keepAlive();

  // Apply the initial value synchronously if the source provider has
  // already resolved. main.dart also applies the value pre-runApp from
  // SharedPreferences, so this is mostly a safety net for paths that
  // skip main (e.g. integration tests, hot restart in dev).
  final initial = ref.read(screenPrivacyEnabledProvider).value;
  if (initial != null) {
    unawaited(ScreenSecurityService.setGlobalEnabled(initial));
  }

  ref.listen<AsyncValue<bool>>(screenPrivacyEnabledProvider, (prev, next) {
    final value = next.value;
    if (value == null) return;
    if (prev?.value == value) return;
    unawaited(ScreenSecurityService.setGlobalEnabled(value));
  });
});
