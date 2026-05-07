import 'package:prism_plurality/features/onboarding/widgets/terminology_step.dart';

/// Backwards-compatible alias for tests and older imports.
///
/// The former generic preferences step is now split into TerminologyStep and
/// AppearanceStep. New onboarding flow code should use those names directly.
class PreferencesStep extends TerminologyStep {
  const PreferencesStep({super.key});
}
