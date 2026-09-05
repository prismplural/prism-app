import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/domain/preferences/preference_registry.dart';
import 'package:prism_plurality/domain/preferences/fronting_terms.dart';
import 'package:prism_plurality/domain/preferences/system_terms.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';

/// Locale-aware terminology strings derived from the user's chosen [SystemTerminology].
///
/// Build one via [resolveTerminology] (or [watchTerminology] / [readTerminology])
/// inside a widget's build method so the locale is respected. Never construct
/// from [SystemTerminology.singularForm] / [SystemTerminology.pluralForm] directly
/// — those are hard-coded English.
///
/// **Note on Spanish grammar agreement:** article/adjective gender in `{term}`
/// placeholders is best-effort. `parte`/`faceta` are grammatically feminine while
/// most template strings use masculine articles (`los`, `un`, `primer`, etc.).
/// This is a known limitation of runtime string interpolation in gendered languages.
/// Mitigated where possible by using gender-neutral sentence structures.
class Terminology {
  const Terminology({
    required this.singular,
    required this.plural,
    required this.systemSingular,
    required this.systemPlural,
  });

  /// Capitalised singular, e.g. "Integrante" (ES) or "Headmate" (EN).
  final String singular;

  /// Capitalised plural, e.g. "Integrantes" (ES) or "Headmates" (EN).
  final String plural;

  /// Capitalised collective singular, e.g. "System" or "Collective".
  final String systemSingular;

  /// Capitalised collective plural, e.g. "Systems" or "Collectives".
  final String systemPlural;

  /// Lowercase singular.
  String get singularLower => singular.toLowerCase();

  /// Lowercase plural.
  String get pluralLower => plural.toLowerCase();

  /// Lowercase collective singular.
  String get systemSingularLower => systemSingular.toLowerCase();

  /// Lowercase collective plural.
  String get systemPluralLower => systemPlural.toLowerCase();
}

// ---------------------------------------------------------------------------
// Raw setting provider — locale-independent
// ---------------------------------------------------------------------------

/// The user's raw terminology preference: which [SystemTerminology] they chose
/// and any custom strings they entered.
///
/// This is locale-independent. To get display strings, pass this to
/// [resolveTerminology], or use [watchTerminology] / [readTerminology].
final terminologySettingProvider =
    Provider<
      ({
        SystemTerminology term,
        String? customSingular,
        String? customPlural,
        bool useEnglish,
      })
    >((ref) {
      final settingsAsync = ref.watch(systemSettingsProvider);
      return settingsAsync.when(
        data: (s) => (
          term: s.terminology,
          customSingular: s.customTerminology,
          customPlural: s.customPluralTerminology,
          useEnglish: s.terminologyUseEnglish,
        ),
        loading: () => (
          term: SystemTerminology.headmates,
          customSingular: null,
          customPlural: null,
          useEnglish: false,
        ),
        error: (_, _) => (
          term: SystemTerminology.headmates,
          customSingular: null,
          customPlural: null,
          useEnglish: false,
        ),
      );
    });

final storedSystemTermsProvider = StreamProvider<SystemTerms?>((ref) {
  final repo = ref.watch(appPreferenceRepositoryProvider);
  return repo.watchStored(systemTermsPreference);
});

final systemTermsSettingProvider = Provider<SystemTerms?>((ref) {
  return ref
      .watch(storedSystemTermsProvider)
      .maybeWhen(data: (value) => value, orElse: () => null);
});

final storedFrontingTermsProvider = StreamProvider<FrontingTerms?>((ref) {
  final repo = ref.watch(appPreferenceRepositoryProvider);
  return repo.watchStored(frontingTermsPreference);
});

final frontingTermsSettingProvider = Provider<FrontingTerms?>((ref) {
  return ref
      .watch(storedFrontingTermsProvider)
      .maybeWhen(data: (value) => value, orElse: () => null);
});

const systemTermPresetChoices = [
  SystemTermPreset.collective,
  SystemTermPreset.community,
  SystemTermPreset.network,
  SystemTermPreset.constellation,
];

({String singular, String plural}) resolveSystemTermPreset(
  AppLocalizations l10n,
  SystemTermPreset preset,
) {
  return switch (preset) {
    SystemTermPreset.collective => (
      singular: l10n.terminologySystemPresetCollectiveSingular,
      plural: l10n.terminologySystemPresetCollectivePlural,
    ),
    SystemTermPreset.community => (
      singular: l10n.terminologySystemPresetCommunitySingular,
      plural: l10n.terminologySystemPresetCommunityPlural,
    ),
    SystemTermPreset.network => (
      singular: l10n.terminologySystemPresetNetworkSingular,
      plural: l10n.terminologySystemPresetNetworkPlural,
    ),
    SystemTermPreset.constellation => (
      singular: l10n.terminologySystemPresetConstellationSingular,
      plural: l10n.terminologySystemPresetConstellationPlural,
    ),
  };
}

// ---------------------------------------------------------------------------
// Locale-aware resolution
// ---------------------------------------------------------------------------

/// Resolve generated localizations with the same English fallback used by the
/// app when the device locale is not yet supported.
AppLocalizations appLocalizationsForLocale(Locale locale) {
  final supported = AppLocalizations.supportedLocales.any(
    (candidate) => candidate.languageCode == locale.languageCode,
  );
  return lookupAppLocalizations(Locale(supported ? locale.languageCode : 'en'));
}

/// Resolve a locale-aware [Terminology] from [l10n] and the user's setting.
///
/// For standard terms, the strings come from [l10n] (so they're correctly
/// translated). For [SystemTerminology.custom], the user's entered strings
/// are used directly (they're inherently locale-correct since the user typed them).
///
/// Call this in a widget's [build] method. For convenience, use [watchTerminology]
/// or [readTerminology] which wrap this with the right [WidgetRef] call.
Terminology resolveTerminology(
  AppLocalizations l10n,
  SystemTerminology term, {
  String? customSingular,
  String? customPlural,
  bool useEnglish = false,
  SystemTerms? systemTerms,
}) {
  final resolvedSystemTerms = resolveSystemTerms(l10n, systemTerms);
  Terminology withSystemTerms(Terminology memberTerms) => Terminology(
    singular: memberTerms.singular,
    plural: memberTerms.plural,
    systemSingular: resolvedSystemTerms.singular,
    systemPlural: resolvedSystemTerms.plural,
  );

  if (useEnglish) {
    return withSystemTerms(
      _resolveEnglish(
        term,
        customSingular: customSingular,
        customPlural: customPlural,
      ),
    );
  }
  return withSystemTerms(switch (term) {
    SystemTerminology.members => Terminology(
      singular: l10n.settingsTerminologyOptionMembersSingular,
      plural: l10n.settingsTerminologyOptionMembers,
      systemSingular: resolvedSystemTerms.singular,
      systemPlural: resolvedSystemTerms.plural,
    ),
    SystemTerminology.headmates => Terminology(
      singular: l10n.settingsTerminologyOptionHeadmatesSingular,
      plural: l10n.settingsTerminologyOptionHeadmates,
      systemSingular: resolvedSystemTerms.singular,
      systemPlural: resolvedSystemTerms.plural,
    ),
    SystemTerminology.alters => Terminology(
      singular: l10n.settingsTerminologyOptionAltersSingular,
      plural: l10n.settingsTerminologyOptionAlters,
      systemSingular: resolvedSystemTerms.singular,
      systemPlural: resolvedSystemTerms.plural,
    ),
    SystemTerminology.parts => Terminology(
      singular: l10n.settingsTerminologyOptionPartsSingular,
      plural: l10n.settingsTerminologyOptionParts,
      systemSingular: resolvedSystemTerms.singular,
      systemPlural: resolvedSystemTerms.plural,
    ),
    SystemTerminology.facets => Terminology(
      singular: l10n.settingsTerminologyOptionFacetsSingular,
      plural: l10n.settingsTerminologyOptionFacets,
      systemSingular: resolvedSystemTerms.singular,
      systemPlural: resolvedSystemTerms.plural,
    ),
    SystemTerminology.custom => _resolveCustom(customSingular, customPlural),
  });
}

({String singular, String plural}) resolveSystemTerms(
  AppLocalizations l10n,
  SystemTerms? custom,
) {
  final normalized = custom?.normalized() ?? SystemTerms.unset;
  if (normalized.preset != null) {
    return resolveSystemTermPreset(l10n, normalized.preset!);
  }
  if (const SystemTermsPreferenceCodec().isValid(normalized)) {
    return (
      singular: _capFirst(normalized.singular!.trim()),
      plural: _capFirst(normalized.plural!.trim()),
    );
  }
  return (
    singular: l10n.terminologySystemDefaultSingular,
    plural: l10n.terminologySystemDefaultPlural,
  );
}

String systemInfoLabel(
  AppLocalizations l10n,
  SystemTerms? terms,
  String resolvedSystemTerm,
) {
  final normalized = terms?.normalized() ?? SystemTerms.unset;
  final kind =
      normalized.preset?.name ??
      (const SystemTermsPreferenceCodec().isValid(normalized)
          ? 'custom'
          : 'system');
  return l10n.systemInfoTitle(kind, resolvedSystemTerm);
}

const frontingTermPresetChoices = [
  FrontingTermPreset.fronting,
  FrontingTermPreset.present,
  FrontingTermPreset.out,
  FrontingTermPreset.online,
];

String frontingTermPresetChoiceLabel(
  AppLocalizations l10n,
  FrontingTermPreset preset,
) {
  return l10n.terminologyFrontingPresetChoiceLabel(preset.name);
}

FrontingTermBundle resolveFrontingTerms(
  AppLocalizations l10n,
  FrontingTerms? terms,
) {
  final normalized = terms?.normalized() ?? FrontingTerms.unset;
  if (normalized.preset != null) {
    return frontingTermBundleForPreset(l10n, normalized.preset!);
  }
  final customBundle = normalized.custom;
  if (customBundle != null && customBundle.isValid) {
    final authoring = normalized.authoring;
    if (!customBundle.hasLongRunningHeaderSingularLabel && authoring != null) {
      // Stored phrases may contain overrides; only fill the missing field.
      final generated = generateSimpleFrontingBundle(authoring);
      return FrontingTermBundle.tryDecode({
            ...customBundle.toJson(),
            'longRunningHeaderSingularLabel':
                generated.longRunningHeaderSingularLabel,
          }) ??
          customBundle;
    }
    return customBundle;
  }
  return frontingTermBundleForPreset(l10n, FrontingTermPreset.fronting);
}

FrontingTermBundle frontingTermBundleForPreset(
  AppLocalizations l10n,
  FrontingTermPreset preset,
) {
  final key = preset.name;
  return FrontingTermBundle.fromFields(
    featureLabel: l10n.terminologyFrontingPresetFeatureLabel(key),
    featureLower: l10n.terminologyFrontingPresetFeatureLower(key),
    currentQuestion: l10n.terminologyFrontingPresetCurrentQuestion(key),
    currentQuestionNow: l10n.terminologyFrontingPresetCurrentQuestionNow(key),
    emptyCurrentState: l10n.terminologyFrontingPresetEmptyCurrentState(key),
    activeSingularLabel: l10n.terminologyFrontingPresetActiveSingularLabel(key),
    activePluralLabel: l10n.terminologyFrontingPresetActivePluralLabel(key),
    activeSectionLabel: l10n.terminologyFrontingPresetActiveSectionLabel(key),
    currentActiveLabel: l10n.terminologyFrontingPresetCurrentActiveLabel(key),
    latestActiveLabel: l10n.terminologyFrontingPresetLatestActiveLabel(key),
    unknownActiveLabel: l10n.terminologyFrontingPresetUnknownActiveLabel(key),
    currentlyActivePhrase: l10n.terminologyFrontingPresetCurrentlyActivePhrase(
      key,
    ),
    logAction: l10n.terminologyFrontingPresetLogAction(key),
    logPastAction: l10n.terminologyFrontingPresetLogPastAction(key),
    quickAction: l10n.terminologyFrontingPresetQuickAction(key),
    holdToStartHint: l10n.terminologyFrontingPresetHoldToStartHint(key),
    addAction: l10n.terminologyFrontingPresetAddAction(key),
    setAsAction: l10n.terminologyFrontingPresetSetAsAction(key),
    replaceCurrentAction: l10n.terminologyFrontingPresetReplaceCurrentAction(
      key,
    ),
    endWithoutAction: l10n.terminologyFrontingPresetEndWithoutAction(key),
    endCurrentAction: l10n.terminologyFrontingPresetEndCurrentAction(key),
    keepCurrentAction: l10n.terminologyFrontingPresetKeepCurrentAction(key),
    directButtonLabel: l10n.terminologyFrontingPresetDirectButtonLabel(key),
    historyLabel: l10n.terminologyFrontingPresetHistoryLabel(key),
    dataLabel: l10n.terminologyFrontingPresetDataLabel(key),
    entryLabel: l10n.terminologyFrontingPresetEntryLabel(key),
    sessionSingular: l10n.terminologyFrontingPresetSessionSingular(key),
    sessionPlural: l10n.terminologyFrontingPresetSessionPlural(key),
    sessionCommentSingular: l10n
        .terminologyFrontingPresetSessionCommentSingular(key),
    sessionCommentPlural: l10n.terminologyFrontingPresetSessionCommentPlural(
      key,
    ),
    statsLabel: l10n.terminologyFrontingPresetStatsLabel(key),
    timeLabel: l10n.terminologyFrontingPresetTimeLabel(key),
    lastActiveLabel: l10n.terminologyFrontingPresetLastActiveLabel(key),
    mostActiveSortLabel: l10n.terminologyFrontingPresetMostActiveSortLabel(key),
    leastActiveSortLabel: l10n.terminologyFrontingPresetLeastActiveSortLabel(
      key,
    ),
    statusLabel: l10n.terminologyFrontingPresetStatusLabel(key),
    togetherStateLabel: l10n.terminologyFrontingPresetTogetherStateLabel(key),
    togetherActiveSingularLabel: l10n
        .terminologyFrontingPresetTogetherActiveSingularLabel(key),
    togetherActivePluralLabel: l10n
        .terminologyFrontingPresetTogetherActivePluralLabel(key),
    togetherPastLabel: l10n.terminologyFrontingPresetTogetherPastLabel(key),
    addTogetherAction: l10n.terminologyFrontingPresetAddTogetherAction(key),
    overlapOptionLabel: l10n.terminologyFrontingPresetOverlapOptionLabel(key),
    overlapSubtitle: l10n.terminologyFrontingPresetOverlapSubtitle(key),
    changeSingular: l10n.terminologyFrontingPresetChangeSingular(key),
    changePlural: l10n.terminologyFrontingPresetChangePlural(key),
    anyChangeLabel: l10n.terminologyFrontingPresetAnyChangeLabel(key),
    onChangeLabel: l10n.terminologyFrontingPresetOnChangeLabel(key),
    delayAfterChangeLabel: l10n.terminologyFrontingPresetDelayAfterChangeLabel(
      key,
    ),
    reminderLabel: l10n.terminologyFrontingPresetReminderLabel(key),
    logChangeReminderAction: l10n
        .terminologyFrontingPresetLogChangeReminderAction(key),
    alwaysActiveLabel: l10n.terminologyFrontingPresetAlwaysActiveLabel(key),
    alwaysPresentHeaderLabel: l10n
        .terminologyFrontingPresetAlwaysPresentHeaderLabel(key),
    longRunningLabel: l10n.terminologyFrontingPresetLongRunningLabel(key),
    longRunningHeaderSingularLabel: l10n
        .terminologyFrontingPresetLongRunningHeaderSingularLabel(key),
    longRunningHeaderLabel: l10n
        .terminologyFrontingPresetLongRunningHeaderLabel(key),
    quickCorrectionLabel: l10n.terminologyFrontingPresetQuickCorrectionLabel(
      key,
    ),
    quickCorrectionWindowTitle: l10n
        .terminologyFrontingPresetQuickCorrectionWindowTitle(key),
    switchEventLabel: l10n.terminologyFrontingPresetSwitchEventLabel(key),
  );
}

SimpleFrontingTermAuthoring simpleFrontingAuthoringForPreset(
  AppLocalizations l10n,
  FrontingTermPreset preset,
) {
  final bundle = frontingTermBundleForPreset(l10n, preset);
  return SimpleFrontingTermAuthoring(
    locale: l10n.localeName.startsWith('es') ? 'es' : 'en',
    seedPreset: preset,
    featureLabel: bundle.featureLabel,
    activeSectionLabel: bundle.activeSectionLabel,
    statePhrase: l10n.terminologyFrontingPresetStatePhrase(preset.name),
    activeSingularLabel: bundle.activeSingularLabel,
    activePluralLabel: bundle.activePluralLabel,
    sessionSingular: bundle.sessionSingular,
    sessionPlural: bundle.sessionPlural,
  );
}

FrontingTermBundle generateSimpleFrontingBundle(
  SimpleFrontingTermAuthoring rawAuthoring,
) {
  final authoring = rawAuthoring.normalized();
  final l10n = appLocalizationsForLocale(Locale(authoring.locale));

  String generated(String field) => l10n.terminologyFrontingSimpleGenerated(
    field,
    authoring.featureLabel,
    authoring.activeSectionLabel,
    authoring.statePhrase,
    authoring.activeSingularLabel,
    authoring.activePluralLabel,
    authoring.sessionSingular,
    authoring.sessionPlural,
  );

  return FrontingTermBundle.fromFields(
    featureLabel: authoring.featureLabel,
    featureLower: authoring.featureLabel.toLowerCase(),
    currentQuestion: generated('currentQuestion'),
    currentQuestionNow: generated('currentQuestionNow'),
    emptyCurrentState: generated('emptyCurrentState'),
    activeSingularLabel: authoring.activeSingularLabel,
    activePluralLabel: authoring.activePluralLabel,
    activeSectionLabel: authoring.activeSectionLabel,
    currentActiveLabel: generated('currentActiveLabel'),
    latestActiveLabel: generated('latestActiveLabel'),
    unknownActiveLabel: generated('unknownActiveLabel'),
    currentlyActivePhrase: generated('currentlyActivePhrase'),
    logAction: generated('logAction'),
    logPastAction: generated('logPastAction'),
    quickAction: generated('quickAction'),
    holdToStartHint: generated('holdToStartHint'),
    addAction: generated('addAction'),
    setAsAction: generated('setAsAction'),
    replaceCurrentAction: generated('replaceCurrentAction'),
    endWithoutAction: generated('endWithoutAction'),
    endCurrentAction: generated('endCurrentAction'),
    keepCurrentAction: generated('keepCurrentAction'),
    directButtonLabel: generated('directButtonLabel'),
    historyLabel: generated('historyLabel'),
    dataLabel: generated('dataLabel'),
    entryLabel: generated('entryLabel'),
    sessionSingular: authoring.sessionSingular,
    sessionPlural: authoring.sessionPlural,
    sessionCommentSingular: generated('sessionCommentSingular'),
    sessionCommentPlural: generated('sessionCommentPlural'),
    statsLabel: generated('statsLabel'),
    timeLabel: generated('timeLabel'),
    lastActiveLabel: generated('lastActiveLabel'),
    mostActiveSortLabel: generated('mostActiveSortLabel'),
    leastActiveSortLabel: generated('leastActiveSortLabel'),
    statusLabel: generated('statusLabel'),
    togetherStateLabel: generated('togetherStateLabel'),
    togetherActiveSingularLabel: generated('togetherActiveSingularLabel'),
    togetherActivePluralLabel: generated('togetherActivePluralLabel'),
    togetherPastLabel: generated('togetherPastLabel'),
    addTogetherAction: generated('addTogetherAction'),
    overlapOptionLabel: generated('overlapOptionLabel'),
    overlapSubtitle: generated('overlapSubtitle'),
    changeSingular: generated('changeSingular'),
    changePlural: generated('changePlural'),
    anyChangeLabel: generated('anyChangeLabel'),
    onChangeLabel: generated('onChangeLabel'),
    delayAfterChangeLabel: generated('delayAfterChangeLabel'),
    reminderLabel: generated('reminderLabel'),
    logChangeReminderAction: generated('logChangeReminderAction'),
    alwaysActiveLabel: generated('alwaysActiveLabel'),
    alwaysPresentHeaderLabel: generated('alwaysPresentHeaderLabel'),
    longRunningLabel: generated('longRunningLabel'),
    longRunningHeaderSingularLabel: generated('longRunningHeaderSingularLabel'),
    longRunningHeaderLabel: generated('longRunningHeaderLabel'),
    quickCorrectionLabel: generated('quickCorrectionLabel'),
    quickCorrectionWindowTitle: generated('quickCorrectionWindowTitle'),
    switchEventLabel: generated('switchEventLabel'),
  );
}

/// Always returns English strings regardless of device locale.
/// Used when [terminologyUseEnglish] is true — the user explicitly chose
/// an English term while in a non-English UI (e.g. "Headmate" in Spanish mode).
Terminology _resolveEnglish(
  SystemTerminology term, {
  String? customSingular,
  String? customPlural,
}) {
  return switch (term) {
    SystemTerminology.members => const Terminology(
      singular: 'Member',
      plural: 'Members',
      systemSingular: 'System',
      systemPlural: 'Systems',
    ),
    SystemTerminology.headmates => const Terminology(
      singular: 'Headmate',
      plural: 'Headmates',
      systemSingular: 'System',
      systemPlural: 'Systems',
    ),
    SystemTerminology.alters => const Terminology(
      singular: 'Alter',
      plural: 'Alters',
      systemSingular: 'System',
      systemPlural: 'Systems',
    ),
    SystemTerminology.parts => const Terminology(
      singular: 'Part',
      plural: 'Parts',
      systemSingular: 'System',
      systemPlural: 'Systems',
    ),
    SystemTerminology.facets => const Terminology(
      singular: 'Facet',
      plural: 'Facets',
      systemSingular: 'System',
      systemPlural: 'Systems',
    ),
    SystemTerminology.custom => _resolveCustom(customSingular, customPlural),
  };
}

Terminology _resolveCustom(String? customSingular, String? customPlural) {
  final singular = _capFirst(
    customSingular?.trim().isNotEmpty == true
        ? customSingular!.trim()
        : 'Member',
  );
  final plural = _capFirst(
    customPlural?.trim().isNotEmpty == true
        ? customPlural!.trim()
        : '${singular}s',
  );
  return Terminology(
    singular: singular,
    plural: plural,
    systemSingular: 'System',
    systemPlural: 'Systems',
  );
}

String _capFirst(String s) =>
    s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

// ---------------------------------------------------------------------------
// Widget-layer helpers
// ---------------------------------------------------------------------------

/// Watch the current locale-aware [Terminology] in a widget's [build] method.
///
/// Rebuilds when the user's terminology preference changes. Locale changes
/// are also picked up automatically because [context.l10n] is re-read each build.
///
/// ```dart
/// final terms = watchTerminology(context, ref);
/// Text(context.l10n.terminologyAddButton(terms.singular))
/// ```
Terminology watchTerminology(BuildContext context, WidgetRef ref) {
  final s = ref.watch(terminologySettingProvider);
  return resolveTerminology(
    context.l10n,
    s.term,
    customSingular: s.customSingular,
    customPlural: s.customPlural,
    useEnglish: s.useEnglish,
  );
}

Terminology watchFullTerminology(BuildContext context, WidgetRef ref) {
  final s = ref.watch(terminologySettingProvider);
  final systemTerms = ref.watch(systemTermsSettingProvider);
  return resolveTerminology(
    context.l10n,
    s.term,
    customSingular: s.customSingular,
    customPlural: s.customPlural,
    useEnglish: s.useEnglish,
    systemTerms: systemTerms,
  );
}

FrontingTermBundle watchFrontingTerms(BuildContext context, WidgetRef ref) {
  return resolveFrontingTerms(
    context.l10n,
    ref.watch(frontingTermsSettingProvider),
  );
}

/// Read the current locale-aware [Terminology] in a callback (non-reactive).
///
/// Use [watchTerminology] in [build] methods. Use this in event handlers and
/// dialogs where you need the current value once, not a reactive stream.
///
/// ```dart
/// onPressed: () {
///   final terms = readTerminology(context, ref);
///   notifier.deleteItem(terms.singularLower);
/// }
/// ```
Terminology readTerminology(BuildContext context, WidgetRef ref) {
  final s = ref.read(terminologySettingProvider);
  return resolveTerminology(
    context.l10n,
    s.term,
    customSingular: s.customSingular,
    customPlural: s.customPlural,
    useEnglish: s.useEnglish,
  );
}

Terminology readFullTerminology(BuildContext context, WidgetRef ref) {
  final s = ref.read(terminologySettingProvider);
  final systemTerms = ref.read(systemTermsSettingProvider);
  return resolveTerminology(
    context.l10n,
    s.term,
    customSingular: s.customSingular,
    customPlural: s.customPlural,
    useEnglish: s.useEnglish,
    systemTerms: systemTerms,
  );
}

FrontingTermBundle readFrontingTerms(BuildContext context, WidgetRef ref) {
  return resolveFrontingTerms(
    context.l10n,
    ref.read(frontingTermsSettingProvider),
  );
}
