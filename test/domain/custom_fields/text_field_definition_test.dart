import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/domain/custom_fields/definitions/text_field_definition.dart';
import 'package:prism_plurality/domain/models/custom_field_type_config.dart';

void main() {
  group('textFieldDefinition.configFromJson', () {
    test('null → null', () {
      expect(textFieldDefinition.configFromJson(null), isNull);
    });

    test('{} (empty object, no discriminator) → null, no throw', () {
      expect(
        () => textFieldDefinition.configFromJson(<String, dynamic>{}),
        returnsNormally,
      );
      expect(textFieldDefinition.configFromJson(<String, dynamic>{}), isNull);
    });

    test('valid TextConfig json → TextConfig', () {
      final json = <String, dynamic>{
        'runtimeType': 'text',
        'hideTitleOnProfile': true,
      };
      final result = textFieldDefinition.configFromJson(json);
      expect(result, isA<TextConfig>());
      expect((result as TextConfig).hideTitleOnProfile, isTrue);
    });
  });

  group('textFieldDefinition.configToJson', () {
    test('null → null', () {
      expect(textFieldDefinition.configToJson(null), isNull);
    });

    test('TextConfig(hideTitleOnProfile: true) → non-null map that round-trips', () {
      const config = TextConfig(hideTitleOnProfile: true);
      final json = textFieldDefinition.configToJson(config);
      expect(json, isNotNull);

      final roundTripped = textFieldDefinition.configFromJson(json);
      expect(roundTripped, isA<TextConfig>());
      expect((roundTripped as TextConfig).hideTitleOnProfile, isTrue);
    });
  });
}
