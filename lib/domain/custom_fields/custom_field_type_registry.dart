import 'package:flutter/widgets.dart';
import 'package:prism_plurality/domain/models/custom_field_type_config.dart';

/// A typed definition for one custom field type. Pure metadata — no widget
/// imports from features/. The widget layer's counterpart is
/// [CustomFieldRenderer] in lib/features/members/widgets/custom_field_renderers.dart.
///
/// Each type contributes ID, legacy int (for back-compat), label/icon,
/// and config codecs. Add a new type by registering a new instance in
/// lib/domain/custom_fields/registry.dart AND a renderer in
/// lib/features/members/widgets/custom_field_renderers.dart.
class CustomFieldTypeDefinition {
  const CustomFieldTypeDefinition({
    required this.id,
    required this.legacyIntValue,
    required this.labelL10nKey,
    required this.icon,
    required this.configFromJson,
    required this.configToJson,
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

  /// IconData is a Flutter value type (not a widget), so importing from
  /// material.dart here is acceptable in the domain layer.
  final IconData icon;

  /// Parse the raw type_config_json column into the sealed variant. Returns
  /// null for legacy types (text/color/date/long_text) that don't use config.
  final CustomFieldTypeConfig? Function(Map<String, dynamic>? json)
  configFromJson;

  /// Serialize the sealed config back to a JSON map. Returns null for legacy.
  final Map<String, dynamic>? Function(CustomFieldTypeConfig? config)
  configToJson;

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
