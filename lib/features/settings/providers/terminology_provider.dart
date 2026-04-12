import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/domain/models/system_settings.dart';
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
  });

  /// Capitalised singular, e.g. "Integrante" (ES) or "Headmate" (EN).
  final String singular;

  /// Capitalised plural, e.g. "Integrantes" (ES) or "Headmates" (EN).
  final String plural;

  /// Lowercase singular.
  String get singularLower => singular.toLowerCase();

  /// Lowercase plural.
  String get pluralLower => plural.toLowerCase();
}

// ---------------------------------------------------------------------------
// Raw setting provider — locale-independent
// ---------------------------------------------------------------------------

/// The user's raw terminology preference: which [SystemTerminology] they chose
/// and any custom strings they entered.
///
/// This is locale-independent. To get display strings, pass this to
/// [resolveTerminology], or use [watchTerminology] / [readTerminology].
final terminologySettingProvider = Provider<
    ({SystemTerminology term, String? customSingular, String? customPlural})>((
  ref,
) {
  final settingsAsync = ref.watch(systemSettingsProvider);
  return settingsAsync.when(
    data: (s) => (
      term: s.terminology,
      customSingular: s.customTerminology,
      customPlural: s.customPluralTerminology,
    ),
    loading: () => (
      term: SystemTerminology.headmates,
      customSingular: null,
      customPlural: null,
    ),
    error: (_, _) => (
      term: SystemTerminology.headmates,
      customSingular: null,
      customPlural: null,
    ),
  );
});

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
}) {
  return switch (term) {
    SystemTerminology.members => Terminology(
      singular: l10n.settingsTerminologyOptionMembersSingular,
      plural: l10n.settingsTerminologyOptionMembers,
    ),
    SystemTerminology.headmates => Terminology(
      singular: l10n.settingsTerminologyOptionHeadmatesSingular,
      plural: l10n.settingsTerminologyOptionHeadmates,
    ),
    SystemTerminology.alters => Terminology(
      singular: l10n.settingsTerminologyOptionAltersSingular,
      plural: l10n.settingsTerminologyOptionAlters,
    ),
    SystemTerminology.parts => Terminology(
      singular: l10n.settingsTerminologyOptionPartsSingular,
      plural: l10n.settingsTerminologyOptionParts,
    ),
    SystemTerminology.facets => Terminology(
      singular: l10n.settingsTerminologyOptionFacetsSingular,
      plural: l10n.settingsTerminologyOptionFacets,
    ),
    SystemTerminology.custom => _resolveCustom(customSingular, customPlural),
  };
}

Terminology _resolveCustom(String? customSingular, String? customPlural) {
  String cap(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
  final singular = cap(
    customSingular?.trim().isNotEmpty == true ? customSingular!.trim() : 'Member',
  );
  final plural = cap(
    customPlural?.trim().isNotEmpty == true
        ? customPlural!.trim()
        : '${singular}s',
  );
  return Terminology(singular: singular, plural: plural);
}

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
  );
}
