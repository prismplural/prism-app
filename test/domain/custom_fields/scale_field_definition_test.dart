import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/domain/custom_fields/definitions/scale_field_definition.dart';
import 'package:prism_plurality/domain/models/typed_field_value.dart';

void main() {
  group('scaleFieldDefinition metadata', () {
    test('id is "scale"', () => expect(scaleFieldDefinition.id, 'scale'));
    test('legacyIntValue is 6', () => expect(scaleFieldDefinition.legacyIntValue, 6));
  });

  group('scaleFieldDefinition.valueParser', () {
    test('null → empty ScaleFieldValue', () {
      expect(scaleFieldDefinition.valueParser(null), const ScaleFieldValue());
    });

    test('empty string → empty ScaleFieldValue', () {
      expect(scaleFieldDefinition.valueParser(''), const ScaleFieldValue());
    });

    test('"4" → ScaleFieldValue(step: 4)', () {
      expect(
        scaleFieldDefinition.valueParser('4'),
        const ScaleFieldValue(step: 4),
      );
    });

    test('"0" → empty (out of range)', () {
      expect(scaleFieldDefinition.valueParser('0'), const ScaleFieldValue());
    });

    test('"-1" → empty (out of range)', () {
      expect(scaleFieldDefinition.valueParser('-1'), const ScaleFieldValue());
    });

    test('"abc" → empty (malformed)', () {
      expect(scaleFieldDefinition.valueParser('abc'), const ScaleFieldValue());
    });

    test('"  3  " (whitespace) → ScaleFieldValue(step: 3)', () {
      expect(
        scaleFieldDefinition.valueParser('  3  '),
        const ScaleFieldValue(step: 3),
      );
    });

    test('"1" → ScaleFieldValue(step: 1)', () {
      expect(
        scaleFieldDefinition.valueParser('1'),
        const ScaleFieldValue(step: 1),
      );
    });

    test('"10" → ScaleFieldValue(step: 10)', () {
      expect(
        scaleFieldDefinition.valueParser('10'),
        const ScaleFieldValue(step: 10),
      );
    });
  });

  group('scaleFieldDefinition.valueEncoder', () {
    test('empty ScaleFieldValue → ""', () {
      expect(
        scaleFieldDefinition.valueEncoder(const ScaleFieldValue()),
        '',
      );
    });

    test('ScaleFieldValue(step: 4) → "4"', () {
      expect(
        scaleFieldDefinition.valueEncoder(const ScaleFieldValue(step: 4)),
        '4',
      );
    });

    test('non-ScaleFieldValue → ""', () {
      expect(
        scaleFieldDefinition.valueEncoder(const TextFieldValue('hello')),
        '',
      );
    });

    test('ScaleFieldValue(step: null) → ""', () {
      expect(
        scaleFieldDefinition.valueEncoder(const ScaleFieldValue()),
        '',
      );
    });
  });

  group('scaleFieldDefinition fuzz — parser never throws', () {
    final inputs = <String?>[
      null,
      '',
      ' ',
      '1',
      '10',
      '999',
      '0.5',
      '-1',
      '1e2',
      'NaN',
      '⭐',
    ];

    for (final input in inputs) {
      test('parser("$input") does not throw', () {
        expect(
          () => scaleFieldDefinition.valueParser(input),
          returnsNormally,
        );
      });
    }
  });
}
