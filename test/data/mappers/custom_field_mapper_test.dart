import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/database/app_database.dart' as db;
import 'package:prism_plurality/data/mappers/custom_field_mapper.dart';
import 'package:prism_plurality/data/mappers/custom_field_value_mapper.dart';
import 'package:prism_plurality/domain/models/custom_field.dart' as domain;
import 'package:prism_plurality/domain/models/custom_field_type_config.dart';
import 'package:prism_plurality/domain/models/custom_field_value.dart' as domain;

import '../../helpers/mapper_test_helpers.dart';

void main() {
  // ══════════════════════════════════════════════════════════════════════════
  // CustomFieldMapper
  // ══════════════════════════════════════════════════════════════════════════

  group('CustomFieldMapper', () {
    final now = DateTime(2026, 3, 20, 12, 0);

    test('toDomain maps text field correctly', () {
      final row = makeDbCustomField(
        id: 'f-text',
        name: 'Favorite Food',
        fieldType: 0,
        datePrecision: null,
        displayOrder: 2,
      );

      final model = CustomFieldMapper.toDomain(row);
      expect(model.id, 'f-text');
      expect(model.name, 'Favorite Food');
      expect(model.fieldType, domain.CustomFieldType.text);
      expect(model.datePrecision, isNull);
      expect(model.displayOrder, 2);
    });

    test('toDomain maps color field correctly', () {
      final row = makeDbCustomField(fieldType: 1);
      final model = CustomFieldMapper.toDomain(row);
      expect(model.fieldType, domain.CustomFieldType.color);
      expect(model.datePrecision, isNull);
    });

    test('toDomain maps date field with full precision', () {
      final row = makeDbCustomField(fieldType: 2, datePrecision: 0);
      final model = CustomFieldMapper.toDomain(row);
      expect(model.fieldType, domain.CustomFieldType.date);
      expect(model.datePrecision, domain.DatePrecision.full);
    });

    test('toDomain maps all date precision values', () {
      for (final precision in domain.DatePrecision.values) {
        final row =
            makeDbCustomField(fieldType: 2, datePrecision: precision.index);
        final model = CustomFieldMapper.toDomain(row);
        expect(model.fieldType, domain.CustomFieldType.date);
        expect(model.datePrecision, precision);
      }
    });

    test('toDomain maps all field type values', () {
      for (final type in domain.CustomFieldType.values) {
        final row = makeDbCustomField(fieldType: type.index);
        final model = CustomFieldMapper.toDomain(row);
        expect(model.fieldType, type);
      }
    });

    test('toCompanion maps enums to int indices', () {
      final model = domain.CustomField(
        id: 'f-comp',
        name: 'Birthday',
        fieldType: domain.CustomFieldType.date,
        datePrecision: domain.DatePrecision.monthDay,
        displayOrder: 3,
        createdAt: now,
      );

      final companion = CustomFieldMapper.toCompanion(model);
      expect(companion.id.value, 'f-comp');
      expect(companion.name.value, 'Birthday');
      expect(companion.fieldType.value, 2); // date
      expect(companion.datePrecision.value, 2); // monthDay
      expect(companion.displayOrder.value, 3);
    });

    test('toCompanion stores null datePrecision for non-date types', () {
      final model = domain.CustomField(
        id: 'f-text',
        name: 'Notes',
        fieldType: domain.CustomFieldType.text,
        datePrecision: null,
        createdAt: now,
      );

      final companion = CustomFieldMapper.toCompanion(model);
      expect(companion.datePrecision.value, isNull);
    });

    test('round-trip preserves data for text field', () {
      final original = domain.CustomField(
        id: 'rt-text',
        name: 'Role',
        fieldType: domain.CustomFieldType.text,
        datePrecision: null,
        displayOrder: 0,
        createdAt: now,
      );

      final companion = CustomFieldMapper.toCompanion(original);
      final row = db.CustomFieldRow(
        id: companion.id.value,
        name: companion.name.value,
        fieldType: companion.fieldType.value,
        fieldTypeId: companion.fieldTypeId.value,
        datePrecision: companion.datePrecision.value,
        displayOrder: companion.displayOrder.value,
        createdAt: companion.createdAt.value,
        parentFieldId: companion.parentFieldId.value,
        typeConfigJson: companion.typeConfigJson.value,
        isDeleted: false,
      );

      final restored = CustomFieldMapper.toDomain(row);
      expect(restored.id, original.id);
      expect(restored.name, original.name);
      expect(restored.fieldType, original.fieldType);
      expect(restored.datePrecision, original.datePrecision);
    });

    test('round-trip preserves data for date field with precision', () {
      final original = domain.CustomField(
        id: 'rt-date',
        name: 'Anniversary',
        fieldType: domain.CustomFieldType.date,
        datePrecision: domain.DatePrecision.timestamp,
        displayOrder: 1,
        createdAt: now,
      );

      final companion = CustomFieldMapper.toCompanion(original);
      final row = db.CustomFieldRow(
        id: companion.id.value,
        name: companion.name.value,
        fieldType: companion.fieldType.value,
        fieldTypeId: companion.fieldTypeId.value,
        datePrecision: companion.datePrecision.value,
        displayOrder: companion.displayOrder.value,
        createdAt: companion.createdAt.value,
        parentFieldId: companion.parentFieldId.value,
        typeConfigJson: companion.typeConfigJson.value,
        isDeleted: false,
      );

      final restored = CustomFieldMapper.toDomain(row);
      expect(restored.fieldType, domain.CustomFieldType.date);
      expect(restored.datePrecision, domain.DatePrecision.timestamp);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // CustomFieldMapper round-trip — new columns (Task 5)
  // ══════════════════════════════════════════════════════════════════════════

  group('CustomFieldMapper round-trip', () {
    test('legacy text field (int-only) round-trips', () {
      final row = db.CustomFieldRow(
        id: 'a',
        name: 'Bio',
        fieldType: 0,
        fieldTypeId: 'text',
        datePrecision: null,
        parentFieldId: null,
        typeConfigJson: null,
        displayOrder: 0,
        createdAt: DateTime.utc(2026),
        isDeleted: false,
      );
      final mapped = CustomFieldMapper.toDomain(row);
      expect(mapped.fieldTypeId, 'text');
      expect(mapped.typeConfig, isNull);
      final back = CustomFieldMapper.toCompanion(mapped);
      expect(back.fieldTypeId.value, 'text');
      expect(back.typeConfigJson.value, isNull);
    });

    test('new-type row with config round-trips', () {
      final row = db.CustomFieldRow(
        id: 'b',
        name: 'Faves',
        fieldType: 4,
        fieldTypeId: 'choice',
        datePrecision: null,
        parentFieldId: null,
        typeConfigJson:
            '{"runtimeType":"choice","options":[],"allowsMultiple":true,"allowsOther":false}',
        displayOrder: 1,
        createdAt: DateTime.utc(2026),
        isDeleted: false,
      );
      final mapped = CustomFieldMapper.toDomain(row);
      expect(mapped.fieldTypeId, 'choice');
      expect(mapped.typeConfig, isA<ChoiceConfig>());
      expect((mapped.typeConfig as ChoiceConfig).allowsMultiple, true);
      final back = CustomFieldMapper.toCompanion(mapped);
      expect(back.fieldTypeId.value, 'choice');
      // Re-encoded JSON should parse back to the same config (string compare
      // may differ due to key order — parse it instead).
      final reparsed = CustomFieldTypeConfigCodec.fromJson(
        jsonDecode(back.typeConfigJson.value!) as Map<String, dynamic>,
      );
      expect(reparsed, mapped.typeConfig);
    });

    test('unknown future-type row preserves field_type_id and raw config', () {
      final row = db.CustomFieldRow(
        id: 'c',
        name: 'Future',
        fieldType: 99,
        fieldTypeId: 'future_x',
        datePrecision: null,
        parentFieldId: null,
        typeConfigJson: '{"runtimeType":"future_x","mystery":true}',
        displayOrder: 2,
        createdAt: DateTime.utc(2026),
        isDeleted: false,
      );
      final mapped = CustomFieldMapper.toDomain(row);
      expect(
        mapped.fieldTypeId,
        'future_x',
        reason: 'Unknown ID preserved verbatim',
      );
      expect(
        mapped.typeConfig,
        isNull,
        reason:
            'Unknown variant fails to parse cleanly; left null',
      );

      final back = CustomFieldMapper.toCompanion(mapped);
      expect(
        back.fieldTypeId.value,
        'future_x',
        reason: 'Round-trip preserves unknown id',
      );
      // typeConfigJson on round-trip will be null because typeConfig is null —
      // this is a known limitation. The full byte-preservation of unknown-variant
      // config will be handled at the repository level (Task 5 part of fieldFields
      // doesn't run for an unknown variant; the sync layer's readRow preserves
      // the raw column directly).
    });

    test('field_type_id null falls back to legacy int', () {
      final row = db.CustomFieldRow(
        id: 'd',
        name: 'Old',
        fieldType: 2,
        fieldTypeId: null, // pre-migration row
        datePrecision: 0,
        parentFieldId: null,
        typeConfigJson: null,
        displayOrder: 3,
        createdAt: DateTime.utc(2026),
        isDeleted: false,
      );
      final mapped = CustomFieldMapper.toDomain(row);
      expect(
        mapped.fieldTypeId,
        'date',
        reason: 'Falls back to registry by legacy int',
      );
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // CustomFieldValueMapper
  // ══════════════════════════════════════════════════════════════════════════

  group('CustomFieldValueMapper', () {
    test('toDomain maps all fields', () {
      const row = db.CustomFieldValueRow(
        id: 'val-1',
        customFieldId: 'field-1',
        memberId: 'member-1',
        value: 'Protector',
        isDeleted: false,
      );

      final model = CustomFieldValueMapper.toDomain(row);
      expect(model.id, 'val-1');
      expect(model.customFieldId, 'field-1');
      expect(model.memberId, 'member-1');
      expect(model.value, 'Protector');
    });

    test('toCompanion preserves all fields', () {
      const model = domain.CustomFieldValue(
        id: 'val-2',
        customFieldId: 'field-2',
        memberId: 'member-2',
        value: '#FF5733',
      );

      final companion = CustomFieldValueMapper.toCompanion(model);
      expect(companion.id.value, 'val-2');
      expect(companion.customFieldId.value, 'field-2');
      expect(companion.memberId.value, 'member-2');
      expect(companion.value.value, '#FF5733');
    });

    test('round-trip preserves data', () {
      const original = domain.CustomFieldValue(
        id: 'rt-val',
        customFieldId: 'f-rt',
        memberId: 'm-rt',
        value: '2026-03-20',
      );

      final companion = CustomFieldValueMapper.toCompanion(original);
      final row = db.CustomFieldValueRow(
        id: companion.id.value,
        customFieldId: companion.customFieldId.value,
        memberId: companion.memberId.value,
        value: companion.value.value,
        isDeleted: false,
      );

      final restored = CustomFieldValueMapper.toDomain(row);
      expect(restored.id, original.id);
      expect(restored.customFieldId, original.customFieldId);
      expect(restored.memberId, original.memberId);
      expect(restored.value, original.value);
    });

    test('handles empty string value', () {
      const row = db.CustomFieldValueRow(
        id: 'val-empty',
        customFieldId: 'f-1',
        memberId: 'm-1',
        value: '',
        isDeleted: false,
      );

      final model = CustomFieldValueMapper.toDomain(row);
      expect(model.value, '');
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // CustomField domain model + enums
  // ══════════════════════════════════════════════════════════════════════════

  group('CustomFieldType enum', () {
    test('has correct index values', () {
      expect(domain.CustomFieldType.text.index, 0);
      expect(domain.CustomFieldType.color.index, 1);
      expect(domain.CustomFieldType.date.index, 2);
      expect(domain.CustomFieldType.longText.index, 3);
    });

    test('has labels', () {
      expect(domain.CustomFieldType.text.label, 'Short Text');
      expect(domain.CustomFieldType.color.label, 'Color');
      expect(domain.CustomFieldType.date.label, 'Date');
      expect(domain.CustomFieldType.longText.label, 'Long Text');
    });

    test('values list has 4 types', () {
      expect(domain.CustomFieldType.values.length, 4);
    });

    test('isTextual identifies short and long text fields', () {
      expect(domain.CustomFieldType.text.isTextual, isTrue);
      expect(domain.CustomFieldType.longText.isTextual, isTrue);
      expect(domain.CustomFieldType.color.isTextual, isFalse);
      expect(domain.CustomFieldType.date.isTextual, isFalse);
    });
  });

  group('DatePrecision enum', () {
    test('has correct index values', () {
      expect(domain.DatePrecision.full.index, 0);
      expect(domain.DatePrecision.monthYear.index, 1);
      expect(domain.DatePrecision.monthDay.index, 2);
      expect(domain.DatePrecision.month.index, 3);
      expect(domain.DatePrecision.year.index, 4);
      expect(domain.DatePrecision.timestamp.index, 5);
    });

    test('has labels for all values', () {
      for (final precision in domain.DatePrecision.values) {
        expect(precision.label, isNotEmpty);
      }
    });

    test('values list has 6 precisions', () {
      expect(domain.DatePrecision.values.length, 6);
    });
  });

  group('CustomField domain model', () {
    test('constructs with required fields only', () {
      final field = domain.CustomField(
        id: 'f-min',
        name: 'Test',
        fieldType: domain.CustomFieldType.text,
        createdAt: DateTime(2026, 1, 1),
      );
      expect(field.datePrecision, isNull);
      expect(field.displayOrder, 0);
    });

    test('JSON round-trip for text field', () {
      final field = domain.CustomField(
        id: 'f-json',
        name: 'Role',
        fieldType: domain.CustomFieldType.text,
        createdAt: DateTime(2026, 3, 20),
      );

      final json = field.toJson();
      final restored = domain.CustomField.fromJson(json);
      expect(restored.id, field.id);
      expect(restored.name, field.name);
      expect(restored.fieldType, field.fieldType);
      expect(restored.datePrecision, isNull);
    });

    test('JSON round-trip for date field with precision', () {
      final field = domain.CustomField(
        id: 'f-date',
        name: 'Birthday',
        fieldType: domain.CustomFieldType.date,
        datePrecision: domain.DatePrecision.monthDay,
        displayOrder: 3,
        createdAt: DateTime(2026, 3, 20),
      );

      final json = field.toJson();
      final restored = domain.CustomField.fromJson(json);
      expect(restored.fieldType, domain.CustomFieldType.date);
      expect(restored.datePrecision, domain.DatePrecision.monthDay);
      expect(restored.displayOrder, 3);
    });
  });
}
