import 'package:prism_plurality/domain/custom_fields/registry.dart';
import 'package:prism_plurality/domain/models/custom_field.dart';
import 'package:prism_plurality/domain/models/custom_field_type_config.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// Envelope for a shareable group of custom-field definitions.
class FieldTemplate {
  const FieldTemplate({required this.version, required this.entries});

  final int version;
  final List<FieldTemplateEntry> entries;

  // Build from live domain fields. Entry order matches input order.
  factory FieldTemplate.fromDomain(List<CustomField> fields) {
    // Index by id so children can locate their parent.
    final idToIndex = <String, int>{};
    for (var i = 0; i < fields.length; i++) {
      idToIndex[fields[i].id] = i;
    }

    final entries = fields.map((field) {
      final parentIndex = field.parentFieldId != null
          ? idToIndex[field.parentFieldId]
          : null;

      String? rawConfigJson;
      Map<String, dynamic>? compactConfig;

      if (field.unknownTypeConfigRaw != null) {
        rawConfigJson = field.unknownTypeConfigRaw;
      } else if (field.typeConfig != null) {
        final json = CustomFieldTypeConfigCodec.toJson(field.typeConfig!);
        compactConfig = _stripDefaults(_stripOptionIds(json));
      }

      // Fix 4: carry datePrecision on the entry.
      final dp = field.datePrecision;

      return FieldTemplateEntry(
        name: field.name,
        fieldTypeId: field.fieldTypeId ?? 'text',
        parentIndex: parentIndex,
        compactConfig: compactConfig,
        rawConfigJson: rawConfigJson,
        datePrecision: dp?.index,
      );
    }).toList();

    return FieldTemplate(version: 1, entries: entries);
  }

  // Regenerate fresh domain fields. IDs are all new UUIDs.
  List<CustomField> toDomainFields() {
    // Build a fresh id for every entry first so children can reference parents.
    final newIds = List.generate(entries.length, (_) => _uuid.v4());

    return List.generate(entries.length, (i) {
      final entry = entries[i];
      final parentFieldId = entry.parentIndex != null
          ? newIds[entry.parentIndex!]
          : null;

      // Derive legacy enum from registry (same logic as create_edit_field_sheet.dart).
      final def = customFieldTypeRegistry.lookupById(entry.fieldTypeId);
      final legacyInt = def?.legacyIntValue;
      final fieldType =
          (legacyInt != null && legacyInt < CustomFieldType.values.length)
          ? CustomFieldType.values[legacyInt]
          : CustomFieldType.text;

      String? unknownTypeConfigRaw;
      CustomFieldTypeConfig? typeConfig;

      if (entry.rawConfigJson != null) {
        unknownTypeConfigRaw = entry.rawConfigJson;
      } else if (entry.compactConfig != null) {
        final inflated = _inflateCompactConfig(entry.compactConfig!);
        typeConfig = CustomFieldTypeConfigCodec.fromJson(inflated);
      }

      // Fix 4: restore datePrecision, guarding against out-of-range index.
      DatePrecision? datePrecision;
      final dp = entry.datePrecision;
      if (dp != null && dp >= 0 && dp < DatePrecision.values.length) {
        datePrecision = DatePrecision.values[dp];
      }

      return CustomField(
        id: newIds[i],
        name: entry.name,
        fieldType: fieldType,
        createdAt: DateTime.now(),
        displayOrder: 0,
        fieldTypeId: entry.fieldTypeId,
        parentFieldId: parentFieldId,
        typeConfig: typeConfig,
        unknownTypeConfigRaw: unknownTypeConfigRaw,
        datePrecision: datePrecision,
      );
    });
  }

  Map<String, dynamic> toJson() => {
    'v': version,
    'f': entries.map((e) => e.toJson()).toList(),
  };

  factory FieldTemplate.fromJson(Map<String, dynamic> json) {
    final v = json['v'] as int;
    final f = json['f'] as List<dynamic>;
    return FieldTemplate(
      version: v,
      entries: f
          .map((e) => FieldTemplateEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// One field's portable definition.
class FieldTemplateEntry {
  const FieldTemplateEntry({
    required this.name,
    required this.fieldTypeId,
    this.parentIndex,
    this.compactConfig,
    this.rawConfigJson,
    this.datePrecision,
  });

  final String name;
  final String fieldTypeId;
  // Index into FieldTemplate.entries of the parent field, or null for top-level.
  final int? parentIndex;
  // Serialized config with option ids/sortOrder stripped and defaults omitted.
  final Map<String, dynamic>? compactConfig;
  // Verbatim raw JSON for unknown future types; non-null only when compactConfig is null.
  final String? rawConfigJson;
  // Fix 4: DatePrecision.index — carried only for date-type fields.
  final int? datePrecision;

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{'n': name, 't': fieldTypeId};
    if (parentIndex != null) map['p'] = parentIndex;
    if (compactConfig != null) map['c'] = compactConfig;
    if (rawConfigJson != null) map['r'] = rawConfigJson;
    if (datePrecision != null) map['dp'] = datePrecision;
    return map;
  }

  factory FieldTemplateEntry.fromJson(Map<String, dynamic> json) {
    final rawC = json['c'];
    final rawR = json['r'];
    return FieldTemplateEntry(
      name: json['n'] as String,
      fieldTypeId: json['t'] as String,
      parentIndex: json['p'] as int?,
      compactConfig:
          rawC != null ? Map<String, dynamic>.from(rawC as Map) : null,
      rawConfigJson: rawR as String?,
      datePrecision: json['dp'] as int?,
    );
  }
}

// Remove 'id' and 'sortOrder' from each option in a ChoiceConfig JSON map.
Map<String, dynamic> _stripOptionIds(Map<String, dynamic> json) {
  final opts = json['options'];
  if (opts == null) return json;
  final stripped = (opts as List<dynamic>).map((o) {
    final map = Map<String, dynamic>.from(o as Map);
    map.remove('id');
    map.remove('sortOrder');
    return map;
  }).toList();
  return {...json, 'options': stripped};
}

// Remove keys that carry default values (reduces payload size).
// Defaults per spec: hideTitleOnProfile:false, empty extra.
Map<String, dynamic> _stripDefaults(Map<String, dynamic> json) {
  final out = Map<String, dynamic>.from(json);
  if (out['hideTitleOnProfile'] == false) out.remove('hideTitleOnProfile');
  // 'extra' is never emitted by the codec (it's excludeFromJson), so nothing to strip there.
  return out;
}

// Re-add defaults stripped on encode so CustomFieldTypeConfigCodec.fromJson can parse.
Map<String, dynamic> _inflateCompactConfig(Map<String, dynamic> compact) {
  final json = Map<String, dynamic>.from(compact);

  // Re-add hideTitleOnProfile default if absent.
  json.putIfAbsent('hideTitleOnProfile', () => false);

  // Re-assign option ids and sortOrder if this looks like a ChoiceConfig.
  final opts = json['options'];
  if (opts != null) {
    final inflated = (opts as List<dynamic>).asMap().entries.map((entry) {
      final map = Map<String, dynamic>.from(entry.value as Map);
      map.putIfAbsent('id', () => _uuid.v4());
      map.putIfAbsent('sortOrder', () => entry.key);
      return map;
    }).toList();
    json['options'] = inflated;
  }

  return json;
}
