import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/domain/custom_fields/definitions/slider_field_definition.dart';
import 'package:prism_plurality/domain/models/typed_field_value.dart';

void main() {
  group('sliderFieldDefinition metadata', () {
    test('id is "slider"',
        () => expect(sliderFieldDefinition.id, 'slider'));
    test('legacyIntValue is 7',
        () => expect(sliderFieldDefinition.legacyIntValue, 7));
  });

  group('sliderFieldDefinition.valueParser', () {
    test('null → empty SliderFieldValue', () {
      expect(
        sliderFieldDefinition.valueParser(null),
        const SliderFieldValue(),
      );
    });

    test('empty string → empty SliderFieldValue', () {
      expect(
        sliderFieldDefinition.valueParser(''),
        const SliderFieldValue(),
      );
    });

    test('"65" → SliderFieldValue(value: 65.0)', () {
      expect(
        sliderFieldDefinition.valueParser('65'),
        const SliderFieldValue(value: 65.0),
      );
    });

    test('"65.5" → SliderFieldValue(value: 65.5)', () {
      expect(
        sliderFieldDefinition.valueParser('65.5'),
        const SliderFieldValue(value: 65.5),
      );
    });

    test('"7e0" → SliderFieldValue(value: 7.0)', () {
      expect(
        sliderFieldDefinition.valueParser('7e0'),
        const SliderFieldValue(value: 7.0),
      );
    });

    test('"-3.5" → SliderFieldValue(value: -3.5)', () {
      expect(
        sliderFieldDefinition.valueParser('-3.5'),
        const SliderFieldValue(value: -3.5),
      );
    });

    test('" 5 " (whitespace) → SliderFieldValue(value: 5.0)', () {
      expect(
        sliderFieldDefinition.valueParser(' 5 '),
        const SliderFieldValue(value: 5.0),
      );
    });

    test('"abc" → empty SliderFieldValue', () {
      expect(
        sliderFieldDefinition.valueParser('abc'),
        const SliderFieldValue(),
      );
    });

    test('"" (empty) → empty SliderFieldValue', () {
      expect(
        sliderFieldDefinition.valueParser(''),
        const SliderFieldValue(),
      );
    });
  });

  group('sliderFieldDefinition.valueEncoder', () {
    test('empty SliderFieldValue → ""', () {
      expect(
        sliderFieldDefinition.valueEncoder(const SliderFieldValue()),
        '',
      );
    });

    test('SliderFieldValue(value: 7.0) → "7" (no decimal for integer)', () {
      expect(
        sliderFieldDefinition.valueEncoder(const SliderFieldValue(value: 7.0)),
        '7',
      );
    });

    test('SliderFieldValue(value: 7.5) → "7.5" (decimal preserved)', () {
      expect(
        sliderFieldDefinition.valueEncoder(
            const SliderFieldValue(value: 7.5)),
        '7.5',
      );
    });

    test('non-SliderFieldValue → ""', () {
      expect(
        sliderFieldDefinition.valueEncoder(const TextFieldValue('hello')),
        '',
      );
    });

    test('SliderFieldValue(value: null) → ""', () {
      expect(
        sliderFieldDefinition.valueEncoder(const SliderFieldValue()),
        '',
      );
    });

    test('SliderFieldValue(value: 0.0) → "0"', () {
      expect(
        sliderFieldDefinition.valueEncoder(const SliderFieldValue(value: 0.0)),
        '0',
      );
    });

    test('SliderFieldValue(value: 100.0) → "100"', () {
      expect(
        sliderFieldDefinition.valueEncoder(
            const SliderFieldValue(value: 100.0)),
        '100',
      );
    });
  });

  group('sliderFieldDefinition fuzz — parser never throws', () {
    final inputs = <String?>[
      null,
      '',
      ' ',
      '0',
      '1',
      '50',
      '100',
      '65',
      '65.5',
      '7e0',
      '-3.5',
      ' 5 ',
      'abc',
      'NaN',
      'Infinity',
      '-Infinity',
      '1e308',
    ];

    for (final input in inputs) {
      test('parser("$input") does not throw', () {
        expect(
          () => sliderFieldDefinition.valueParser(input),
          returnsNormally,
        );
      });
    }
  });
}
