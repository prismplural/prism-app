import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';

/// Resolved terminology strings based on the user's chosen [SystemTerminology].
///
/// Watches [systemSettingsProvider] and provides convenient getters for
/// singular/plural forms, along with common UI phrases.
class Terminology {
  const Terminology({
    required this.singular,
    required this.plural,
  });

  /// Capitalised singular form, e.g. "Headmate".
  final String singular;

  /// Capitalised plural form, e.g. "Headmates".
  final String plural;

  /// Lowercase singular, e.g. "headmate".
  String get singularLower => singular.toLowerCase();

  /// Lowercase plural, e.g. "headmates".
  String get pluralLower => plural.toLowerCase();

  /// "Add Headmate"
  String get addButtonText => 'Add $singular';

  /// "Select a headmate"
  String get selectText => 'Select a $singularLower';

  /// "New Headmate"
  String get newText => 'New $singular';

  /// "Edit Headmate"
  String get editText => 'Edit $singular';

  /// "Delete Headmate"
  String get deleteText => 'Delete $singular';

  /// "No headmates yet"
  String get emptyTitle => 'No $pluralLower yet';

  /// "No active headmates yet"
  String get emptyActiveTitle => 'No active $pluralLower yet';

  /// "Search headmates..."
  String get searchHint => 'Search $pluralLower...';

  /// "Manage Headmates"
  String get manageText => 'Manage $plural';

  /// "Delete Selected Headmates"
  String get deleteSelectedText => 'Delete Selected $plural';

  /// Default fallback when settings are loading.
  static const fallback = Terminology(
    singular: 'Headmate',
    plural: 'Headmates',
  );
}

/// Provider that derives the current [Terminology] from system settings.
final terminologyProvider = Provider<Terminology>((ref) {
  final settingsAsync = ref.watch(systemSettingsProvider);

  return settingsAsync.when(
    data: (settings) {
      if (settings.terminology == SystemTerminology.custom) {
        final customSingular =
            settings.customTerminology?.trim().isNotEmpty == true
                ? settings.customTerminology!.trim()
                : 'Member';
        final customPlural =
            settings.customPluralTerminology?.trim().isNotEmpty == true
                ? settings.customPluralTerminology!.trim()
                : '${customSingular}s';

        // Capitalise first letter for consistency.
        String capitalise(String s) =>
            s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

        return Terminology(
          singular: capitalise(customSingular),
          plural: capitalise(customPlural),
        );
      }

      return Terminology(
        singular: settings.terminology.singularForm,
        plural: settings.terminology.pluralForm,
      );
    },
    loading: () => Terminology.fallback,
    error: (_, _) => Terminology.fallback,
  );
});
