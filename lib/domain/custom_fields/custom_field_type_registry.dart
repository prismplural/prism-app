import 'package:flutter/widgets.dart';
import 'package:prism_plurality/domain/models/custom_field.dart';
import 'package:prism_plurality/domain/models/custom_field_type_config.dart';
import 'package:prism_plurality/domain/models/custom_field_value.dart';

/// A typed definition for one custom field type. Mirrors PreferenceDefinition[T].
///
/// Each type contributes ID, legacy int (for back-compat), label/icon,
/// config codec, value parser/encoder, and the three render builders
/// (editor, display, compact). Add a new type by registering a new instance.
class CustomFieldTypeDefinition {
  const CustomFieldTypeDefinition({
    required this.id,
    required this.legacyIntValue,
    required this.labelL10nKey,
    required this.icon,
    required this.configFromJson,
    required this.configToJson,
    required this.editorBuilder,
    required this.displayBuilder,
    required this.compactBuilder,
    this.allowsTextualSwitch = false,
  });

  /// Stable string ID for the column `field_type_id` (e.g., "text", "choice").
  /// Never rename — this is sync wire format.
  final String id;

  /// Legacy int written to the older `field_type` column for back-compat with
  /// v27 readers. Nullable for future types that don't need a legacy int.
  final int? legacyIntValue;

  /// l10n key for the human-readable label (resolved at render time).
  /// Free-text fallback if the project doesn't have l10n wired in yet.
  final String labelL10nKey;

  final IconData icon;

  /// Parse the raw type_config_json column into the sealed variant. Returns
  /// null for legacy types (text/color/date/long_text) that don't use config.
  final CustomFieldTypeConfig? Function(Map<String, dynamic>? json)
  configFromJson;

  /// Serialize the sealed config back to a JSON map. Returns null for legacy.
  final Map<String, dynamic>? Function(CustomFieldTypeConfig? config)
  configToJson;

  /// Build the per-member editor widget. For legacy types, this returns a
  /// [FieldInputWidget] — the stateful widget that handles text controllers,
  /// focus nodes, controller registration, and save logic. Future types (choice,
  /// scale, slider, etc.) will return their own standalone stateful widgets.
  final Widget Function(
    BuildContext context,
    CustomField field,
    CustomFieldValue? value,
    String memberId,
  ) editorBuilder;

  /// Build the per-member display widget (full detail).
  final Widget Function(
    BuildContext context,
    CustomField field,
    CustomFieldValue value,
  ) displayBuilder;

  /// Build the compact list-view display widget.
  final Widget Function(
    BuildContext context,
    CustomField field,
    CustomFieldValue value,
  ) compactBuilder;

  /// Whether this type can be switched to/from another textual type in the
  /// edit sheet (only true for text ↔ long_text today).
  final bool allowsTextualSwitch;
}

/// Registry of all custom field types. Construction-time duplicate-ID check.
/// Mirrors PreferenceRegistry.
final class CustomFieldTypeRegistry {
  CustomFieldTypeRegistry(Iterable<CustomFieldTypeDefinition> definitions)
      : definitions = List.unmodifiable(definitions) {
    final ids = <String>{};
    final ints = <int>{};
    for (final def in definitions) {
      if (!ids.add(def.id)) {
        throw StateError('Duplicate custom field type id: ${def.id}');
      }
      final legacyInt = def.legacyIntValue;
      if (legacyInt != null && !ints.add(legacyInt)) {
        throw StateError('Duplicate legacyIntValue: $legacyInt');
      }
    }
  }

  final List<CustomFieldTypeDefinition> definitions;

  CustomFieldTypeDefinition? lookupById(String? id) {
    if (id == null) return null;
    for (final def in definitions) {
      if (def.id == id) return def;
    }
    return null;
  }

  CustomFieldTypeDefinition? lookupByLegacyInt(int legacyInt) {
    for (final def in definitions) {
      if (def.legacyIntValue == legacyInt) return def;
    }
    return null;
  }
}
