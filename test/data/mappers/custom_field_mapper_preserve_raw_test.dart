import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/data/mappers/custom_field_mapper.dart';
import 'package:prism_plurality/domain/models/custom_field.dart' as domain;

import '../../helpers/mapper_test_helpers.dart';

/// Phase D + E1 regression tests.
///
/// Phase D: the mapper must preserve [unknownTypeConfigRaw] whenever the codec
/// can't produce a typed [CustomFieldTypeConfig] — not only when the JSON
/// happens to be a top-level object. The invariant is "preserve unrecognized
/// raw when no typed config is written," so future-shape payloads (arrays,
/// scalars) and malformed JSON survive round-trips through this device.
///
/// Phase E1: negative ints from corrupt storage or a malicious peer must not
/// crash the mapper. Bounds checks need to be symmetric (`>= 0 && < length`)
/// to mirror the import-side guard.
void main() {
  group('CustomFieldMapper.toDomain — preserves raw on any codec failure', () {
    test('malformed JSON is preserved in unknownTypeConfigRaw', () {
      const malformed = '{ broken';
      final row = makeDbCustomField(
        id: 'f-malformed',
        fieldType: 0,
        typeConfigJson: malformed,
      );

      final model = CustomFieldMapper.toDomain(row);

      expect(model.typeConfig, isNull);
      expect(model.unknownTypeConfigRaw, malformed);
    });

    test('JSON array (non-object) is preserved in unknownTypeConfigRaw', () {
      const arrayPayload = '[1, 2, 3]';
      final row = makeDbCustomField(
        id: 'f-array',
        fieldType: 0,
        typeConfigJson: arrayPayload,
      );

      final model = CustomFieldMapper.toDomain(row);

      expect(model.typeConfig, isNull);
      expect(model.unknownTypeConfigRaw, arrayPayload);
    });

    test('JSON string scalar is preserved in unknownTypeConfigRaw', () {
      const stringPayload = '"hello"';
      final row = makeDbCustomField(
        id: 'f-string',
        fieldType: 0,
        typeConfigJson: stringPayload,
      );

      final model = CustomFieldMapper.toDomain(row);

      expect(model.typeConfig, isNull);
      expect(model.unknownTypeConfigRaw, stringPayload);
    });

    test('JSON number scalar is preserved in unknownTypeConfigRaw', () {
      const numberPayload = '42';
      final row = makeDbCustomField(
        id: 'f-number',
        fieldType: 0,
        typeConfigJson: numberPayload,
      );

      final model = CustomFieldMapper.toDomain(row);

      expect(model.typeConfig, isNull);
      expect(model.unknownTypeConfigRaw, numberPayload);
    });

    test('round-trip through toCompanion re-emits raw bytes verbatim', () {
      // Forward-compat invariant: a device that doesn't understand a payload
      // shouldn't wipe it on the next save. Verifies the toCompanion side
      // already honours unknownTypeConfigRaw when typeConfig is null.
      const arrayPayload = '[1, 2, 3]';
      final row = makeDbCustomField(
        id: 'f-roundtrip',
        fieldType: 0,
        typeConfigJson: arrayPayload,
      );

      final model = CustomFieldMapper.toDomain(row);
      final companion = CustomFieldMapper.toCompanion(model);

      expect(companion.typeConfigJson.value, arrayPayload);
    });
  });

  group('CustomFieldMapper.toDomain — negative enum guards', () {
    test('negative fieldType falls back to CustomFieldType.text', () {
      final row = makeDbCustomField(
        id: 'f-neg-type',
        fieldType: -1,
      );

      // Must not throw RangeError.
      late domain.CustomField model;
      expect(() => model = CustomFieldMapper.toDomain(row), returnsNormally);
      expect(model.fieldType, domain.CustomFieldType.text);
    });

    test('large negative fieldType falls back to CustomFieldType.text', () {
      final row = makeDbCustomField(
        id: 'f-neg-type-big',
        fieldType: -999,
      );

      late domain.CustomField model;
      expect(() => model = CustomFieldMapper.toDomain(row), returnsNormally);
      expect(model.fieldType, domain.CustomFieldType.text);
    });

    test('negative datePrecision falls back to null', () {
      final row = makeDbCustomField(
        id: 'f-neg-precision',
        fieldType: 2, // date
        datePrecision: -1,
      );

      late domain.CustomField model;
      expect(() => model = CustomFieldMapper.toDomain(row), returnsNormally);
      expect(model.datePrecision, isNull);
    });

    test('out-of-range positive fieldType still falls back (regression)', () {
      // Pre-existing behavior; covered to lock in the unchanged half of the
      // bounds check.
      final row = makeDbCustomField(
        id: 'f-pos-type-oor',
        fieldType: 9999,
      );

      late domain.CustomField model;
      expect(() => model = CustomFieldMapper.toDomain(row), returnsNormally);
      expect(model.fieldType, domain.CustomFieldType.text);
    });
  });
}
