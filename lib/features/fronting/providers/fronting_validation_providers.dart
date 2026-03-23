import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/features/fronting/sanitization/fronting_fix_planner.dart';
import 'package:prism_plurality/features/fronting/validation/fronting_session_validator.dart';
import 'package:prism_plurality/features/fronting/validation/fronting_validation_config.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';

/// Provides a [FrontingSessionValidator] configured with the current
/// timing mode from system settings.
final frontingValidatorProvider = Provider<FrontingSessionValidator>((ref) {
  final timingMode = ref.watch(timingModeProvider);
  return FrontingSessionValidator(
    config: FrontingValidationConfig(timingMode: timingMode),
  );
});

/// Provides a stateless [FrontingFixPlanner] for translating validation
/// issues into user-selectable fix plans.
final frontingFixPlannerProvider = Provider<FrontingFixPlanner>((ref) {
  return const FrontingFixPlanner();
});
