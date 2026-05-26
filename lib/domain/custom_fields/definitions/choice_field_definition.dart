import 'dart:convert';

import 'package:prism_plurality/domain/custom_fields/custom_field_type_registry.dart';
import 'package:prism_plurality/domain/models/custom_field_type_config.dart';
import 'package:prism_plurality/domain/models/typed_field_value.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';

// ---------------------------------------------------------------------------
// Config codec — choice uses ChoiceConfig.
// ---------------------------------------------------------------------------

CustomFieldTypeConfig? _configFromJson(Map<String, dynamic>? json) {
  if (json == null) return null;
  return CustomFieldTypeConfigCodec.fromJson(json);
}

Map<String, dynamic>? _configToJson(CustomFieldTypeConfig? config) {
  if (config == null) return null;
  return CustomFieldTypeConfigCodec.toJson(config);
}

// ---------------------------------------------------------------------------
// Value parser/encoder — choice stores a JSON blob.
// ---------------------------------------------------------------------------

TypedFieldValue _parse(String? raw) {
  if (raw == null || raw.isEmpty) return const ChoiceFieldValue();
  try {
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final options = (json['options'] as List?)?.cast<String>().toSet() ?? <String>{};
    final other = json['other'] as String?;
    return ChoiceFieldValue(optionIds: options, other: other);
  } catch (_) {
    return const ChoiceFieldValue();
  }
}

String _encode(TypedFieldValue value) {
  if (value is! ChoiceFieldValue) return '';
  // "No selection at all" → empty raw value so the storage column doesn't
  // hold a meaningless `{}`. An empty `other` string is meaningful (the
  // Other chip was tapped but no text typed yet) and must round-trip; null
  // means Other was never selected.
  if (value.optionIds.isEmpty && value.other == null) {
    return '';
  }
  final json = <String, dynamic>{
    'options': value.optionIds.toList()..sort(),
    if (value.other != null) 'other': value.other,
  };
  return jsonEncode(json);
}

// ---------------------------------------------------------------------------
// Definition constant — pure metadata, no widget imports.
// Widget builders live in lib/features/members/widgets/custom_field_renderers.dart
// (added in Task 8).
// ---------------------------------------------------------------------------

final choiceFieldDefinition = CustomFieldTypeDefinition(
  id: 'choice',
  legacyIntValue: 4,
  labelL10nKey: 'customFieldTypeChoice',
  // checkBoxOutlined (PhosphorIcons.checkSquare) is the closest semantic fit
  // for a single/multi-select choice list.
  icon: AppIcons.checkBoxOutlined,
  configFromJson: _configFromJson,
  configToJson: _configToJson,
  valueParser: _parse,
  valueEncoder: _encode,
);
