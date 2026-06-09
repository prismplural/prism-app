import 'dart:convert';

import 'package:prism_plurality/domain/custom_fields/custom_field_type_registry.dart';
import 'package:prism_plurality/domain/models/custom_field_type_config.dart';
import 'package:prism_plurality/domain/models/typed_field_value.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';

// ---------------------------------------------------------------------------
// Config codec — member uses MemberConfig.
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
// Value parser/encoder — member stores selected member IDs as deterministic JSON.
// ---------------------------------------------------------------------------

TypedFieldValue _parse(String? raw) {
  if (raw == null || raw.isEmpty) return const MemberFieldValue();
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) return const MemberFieldValue();
    final rawMemberIds = decoded['memberIds'];
    if (rawMemberIds is! List) return const MemberFieldValue();
    final memberIds = <String>{};
    for (final value in rawMemberIds) {
      if (value is String) memberIds.add(value);
    }
    final extra = <String, dynamic>{};
    for (final entry in decoded.entries) {
      if (entry.key == 'memberIds') continue;
      extra[entry.key] = entry.value;
    }
    return MemberFieldValue(memberIds: memberIds, extra: extra);
  } catch (_) {
    return const MemberFieldValue();
  }
}

String _encode(TypedFieldValue value) {
  if (value is! MemberFieldValue) return '';
  if (value.memberIds.isEmpty && value.extra.isEmpty) return '';
  final encoded = <String, dynamic>{
    'memberIds': value.memberIds.toList()..sort(),
  };
  final extraKeys = value.extra.keys.where((key) => key != 'memberIds').toList()
    ..sort();
  for (final key in extraKeys) {
    encoded[key] = value.extra[key];
  }
  return jsonEncode(encoded);
}

// ---------------------------------------------------------------------------
// Definition constant — pure metadata, no widget imports.
// Widget builders live in lib/features/members/widgets/custom_field_renderers.dart.
// ---------------------------------------------------------------------------

final memberFieldDefinition = CustomFieldTypeDefinition(
  id: 'member',
  legacyIntValue: null,
  labelL10nKey: 'customFieldTypeMember',
  icon: AppIcons.personOutline,
  configFromJson: _configFromJson,
  configToJson: _configToJson,
  valueParser: _parse,
  valueEncoder: _encode,
);
