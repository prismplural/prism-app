import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/domain/custom_fields/definitions/group_field_definition.dart';
import 'package:prism_plurality/domain/models/typed_field_value.dart';

void main() {
  group('groupFieldDefinition', () {
    test('id is "group"', () => expect(groupFieldDefinition.id, 'group'));
    test('legacyIntValue is 5', () => expect(groupFieldDefinition.legacyIntValue, 5));
    test('parser returns UnsupportedFieldValue for null', () {
      expect(groupFieldDefinition.valueParser(null), const UnsupportedFieldValue(''));
    });
    test('parser returns UnsupportedFieldValue for empty', () {
      expect(groupFieldDefinition.valueParser(''), const UnsupportedFieldValue(''));
    });
    test('parser preserves raw for non-empty (defensive)', () {
      expect(groupFieldDefinition.valueParser('mystery'), const UnsupportedFieldValue('mystery'));
    });
    test('encoder returns empty string for any input', () {
      expect(groupFieldDefinition.valueEncoder(const UnsupportedFieldValue('')), '');
      expect(groupFieldDefinition.valueEncoder(const TextFieldValue('x')), '');
    });
  });
}
