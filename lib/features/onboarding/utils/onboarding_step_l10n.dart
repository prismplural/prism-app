import 'package:flutter/widgets.dart';

import 'package:prism_plurality/features/onboarding/providers/onboarding_providers.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';

/// Localized step header strings for [OnboardingStep].
///
/// Keeps l10n lookups in the presentation layer, leaving the domain enum
/// free of Flutter imports.
extension OnboardingStepL10n on OnboardingStep {
  String localizedTitle(BuildContext context) => switch (this) {
    OnboardingStep.welcome => context.l10n.onboardingWelcomeTitle,
    OnboardingStep.pinSetup => context.l10n.onboardingPinSetupTitle,
    OnboardingStep.recoveryPhrase => context.l10n.onboardingRecoveryPhraseTitle,
    OnboardingStep.biometricSetup => context.l10n.onboardingBiometricSetupTitle,
    OnboardingStep.syncDevice => context.l10n.onboardingSyncDeviceTitle,
    OnboardingStep.importedDataReady =>
      context.l10n.onboardingImportedDataReadyTitle,
    OnboardingStep.importData => context.l10n.onboardingImportDataTitle,
    OnboardingStep.systemName => context.l10n.onboardingSystemNameTitle,
    OnboardingStep.addMembers => context.l10n.onboardingAddMembersTitle,
    OnboardingStep.features => context.l10n.onboardingFeaturesTitle,
    OnboardingStep.chatSetup => context.l10n.onboardingChatSetupTitle,
    OnboardingStep.preferences => context.l10n.onboardingPreferencesTitle,
    OnboardingStep.permissions => context.l10n.onboardingPermissionsTitle,
    OnboardingStep.whosFronting => context.l10n.onboardingWhosFrontingTitle,
    OnboardingStep.complete => context.l10n.onboardingCompleteTitle,
  };

  String? localizedSubtitle(BuildContext context) => switch (this) {
    OnboardingStep.welcome => context.l10n.onboardingWelcomeSubtitle,
    OnboardingStep.pinSetup => context.l10n.onboardingPinSetupSubtitle,
    OnboardingStep.recoveryPhrase => null,
    OnboardingStep.biometricSetup => context.l10n.onboardingBiometricSetupSubtitle,
    OnboardingStep.syncDevice => context.l10n.onboardingSyncDeviceSubtitle,
    OnboardingStep.importedDataReady =>
      context.l10n.onboardingImportedDataReadySubtitle,
    OnboardingStep.importData => context.l10n.onboardingImportDataSubtitle,
    OnboardingStep.systemName => context.l10n.onboardingSystemNameSubtitle,
    OnboardingStep.addMembers => context.l10n.onboardingAddMembersSubtitle,
    OnboardingStep.features => context.l10n.onboardingFeaturesSubtitle,
    OnboardingStep.chatSetup => context.l10n.onboardingChatSetupSubtitle,
    OnboardingStep.preferences => context.l10n.onboardingPreferencesSubtitle,
    OnboardingStep.permissions => context.l10n.onboardingPermissionsSubtitle,
    OnboardingStep.whosFronting => context.l10n.onboardingWhosFrontingSubtitle,
    OnboardingStep.complete => context.l10n.onboardingCompleteSubtitle,
  };
}
