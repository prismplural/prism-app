import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/domain/preferences/preference_registry.dart';
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
