import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/domain/custom_fields/definitions/color_field_definition.dart';
import 'package:prism_plurality/domain/custom_fields/definitions/date_field_definition.dart';
import 'package:prism_plurality/domain/custom_fields/definitions/long_text_field_definition.dart';
import 'package:prism_plurality/domain/custom_fields/definitions/text_field_definition.dart';
import 'package:prism_plurality/domain/models/typed_field_value.dart';

void main() {
  group('TypedFieldValue — parse-by-field-type contract', () {
    group('text parser', () {
      test('valid', () => expect(textFieldDefinition.valueParser('hello'), const TextFieldValue('hello')));
      test('null', () => expect(textFieldDefinition.valueParser(null), const TextFieldValue('')));
      test('empty', () => expect(textFieldDefinition.valueParser(''), const TextFieldValue('')));
      test('multiline', () => expect(textFieldDefinition.valueParser('a\nb'), const TextFieldValue('a\nb')));
      test('encoder round-trip', () {
        const value = TextFieldValue('hello');
        expect(textFieldDefinition.valueParser(textFieldDefinition.valueEncoder(value)), value);
      });
    });

    group('long_text parser', () {
      test('valid', () => expect(longTextFieldDefinition.valueParser('hello'), const LongTextFieldValue('hello')));
      test('null', () => expect(longTextFieldDefinition.valueParser(null), const LongTextFieldValue('')));
      test('empty', () => expect(longTextFieldDefinition.valueParser(''), const LongTextFieldValue('')));
      test('multiline', () => expect(longTextFieldDefinition.valueParser('line1\nline2\nline3'), const LongTextFieldValue('line1\nline2\nline3')));
      test('encoder round-trip', () {
        const value = LongTextFieldValue('some long text');
        expect(longTextFieldDefinition.valueParser(longTextFieldDefinition.valueEncoder(value)), value);
      });
    });

    group('color parser', () {
      test('valid hex', () => expect(colorFieldDefinition.valueParser('#ff00aa'), const ColorFieldValue(hex: '#ff00aa')));
      test('whitespace trim', () => expect(colorFieldDefinition.valueParser('  #ff00aa  '), const ColorFieldValue(hex: '#ff00aa')));
      test('null', () => expect(colorFieldDefinition.valueParser(null), const ColorFieldValue()));
      test('empty', () => expect(colorFieldDefinition.valueParser(''), const ColorFieldValue()));
      test('whitespace-only', () => expect(colorFieldDefinition.valueParser('   '), const ColorFieldValue()));
      test('encoder round-trip with hex', () {
        const value = ColorFieldValue(hex: '#aabbcc');
        expect(colorFieldDefinition.valueParser(colorFieldDefinition.valueEncoder(value)), value);
      });
      test('encoder round-trip with null hex', () {
        const value = ColorFieldValue();
        expect(colorFieldDefinition.valueEncoder(value), '');
        expect(colorFieldDefinition.valueParser(''), const ColorFieldValue());
      });
    });

    group('date parser', () {
      test('valid ISO', () {
        final dt = DateTime.utc(2026, 5, 25);
        expect(dateFieldDefinition.valueParser(dt.toIso8601String()), DateFieldValue(value: dt));
      });
      test('null', () => expect(dateFieldDefinition.valueParser(null), const DateFieldValue()));
      test('empty', () => expect(dateFieldDefinition.valueParser(''), const DateFieldValue()));
      test('malformed', () => expect(dateFieldDefinition.valueParser('not a date'), const DateFieldValue()));
      test('scientific notation gibberish', () => expect(dateFieldDefinition.valueParser('7e9'), const DateFieldValue()));
      test('encoder round-trip', () {
        final dt = DateTime.utc(2026, 5, 25, 12, 30);
        final parsed = dateFieldDefinition.valueParser(dt.toIso8601String());
        final reencoded = dateFieldDefinition.valueEncoder(parsed);
        expect(dateFieldDefinition.valueParser(reencoded), parsed);
      });
    });

    test('all four legacy parsers never throw on a fuzz corpus', () {
      final corpus = [
        null, '', ' ', '\n', '0', 'abc', '{"x":1}', ' ', '😀',
        '999999999999999999999', '-1', '0.5', '1e10', '\\', '"', '[]', '{',
      ];
      for (final input in corpus) {
        // All four must return WITHOUT throwing.
        textFieldDefinition.valueParser(input);
        longTextFieldDefinition.valueParser(input);
        colorFieldDefinition.valueParser(input);
        dateFieldDefinition.valueParser(input);
      }
    });
  });
}
