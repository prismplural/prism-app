import 'package:prism_plurality/domain/custom_fields/custom_field_type_registry.dart';
import 'package:prism_plurality/domain/custom_fields/registry.dart';
import 'package:prism_plurality/domain/models/custom_field.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';

/// Resolve a `CustomFieldTypeDefinition.labelL10nKey` to the corresponding
/// localized string.
///
/// Centralized so every surface that renders a field-type label stays in
/// sync. Previously each call site reimplemented this switch, which caused
/// scale and slider to leak their raw key (e.g. `customFieldTypeSlider`) on
/// any surface whose switch hadn't been updated, and to fall back to the
/// legacy enum label ("Short text") on surfaces that bypassed the registry
/// entirely.
///
/// Unknown keys (future field types loaded from sync) return the key itself
/// so the surface still renders something legible.
///
/// TODO: drop this resolver once `AppLocalizations.resolve(key)` lands.
String resolveFieldTypeLabel(AppLocalizations l10n, String labelL10nKey) {
  return switch (labelL10nKey) {
    'customFieldTypeShortText' => l10n.customFieldTypeShortText,
    'customFieldTypeLongText' => l10n.customFieldTypeLongText,
    'customFieldTypeColor' => l10n.customFieldTypeColor,
    'customFieldTypeDate' => l10n.customFieldTypeDate,
    'customFieldTypeChoice' => l10n.customFieldTypeChoice,
    'customFieldTypeGroup' => l10n.customFieldTypeGroup,
    'customFieldTypeScale' => l10n.customFieldTypeScale,
    'customFieldTypeSlider' => l10n.customFieldTypeSlider,
    _ => labelL10nKey,
  };
}

/// Localized type label for a [CustomFieldTypeDefinition]. Used by the type
/// picker in the create/edit sheet, where the def is known directly.
String localizedFieldTypeDefLabel(
  AppLocalizations l10n,
  CustomFieldTypeDefinition def,
) {
  return resolveFieldTypeLabel(l10n, def.labelL10nKey);
}

/// Localized type label for a [CustomField]. Falls back through the legacy
/// enum label when the field has no registry entry — a pre-registry row or
/// a forward-compat type that hasn't been registered yet.
String localizedFieldTypeLabel(AppLocalizations l10n, CustomField field) {
  final def = customFieldTypeRegistry.lookupById(field.fieldTypeId);
  if (def != null) return resolveFieldTypeLabel(l10n, def.labelL10nKey);
  return field.fieldType.localizedLabel(l10n);
}
