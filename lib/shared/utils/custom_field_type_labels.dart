import 'package:prism_plurality/domain/custom_fields/custom_field_type_registry.dart';
import 'package:prism_plurality/domain/custom_fields/registry.dart';
import 'package:prism_plurality/domain/models/custom_field.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';

/// Resolves a registry `labelL10nKey` to its localized string. Unknown keys
/// (forward-compat types) return the key itself so something legible still
/// renders.
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
    'customFieldTypeMember' => l10n.customFieldTypeMember,
    _ => labelL10nKey,
  };
}

String localizedFieldTypeDefLabel(
  AppLocalizations l10n,
  CustomFieldTypeDefinition def,
) {
  return resolveFieldTypeLabel(l10n, def.labelL10nKey);
}

/// Falls back to the legacy enum label for pre-registry rows.
String localizedFieldTypeLabel(AppLocalizations l10n, CustomField field) {
  final def = customFieldTypeRegistry.lookupById(field.fieldTypeId);
  if (def != null) return resolveFieldTypeLabel(l10n, def.labelL10nKey);
  return field.fieldType.localizedLabel(l10n);
}
