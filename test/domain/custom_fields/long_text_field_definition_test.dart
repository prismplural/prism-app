import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/domain/custom_fields/definitions/long_text_field_definition.dart';
import 'package:prism_plurality/domain/models/custom_field_type_config.dart';

void main() {
  group('longTextFieldDefinition.configFromJson', () {
    test('null → null', () {
      expect(longTextFieldDefinition.configFromJson(null), isNull);
    });

    test('{} (empty object, no discriminator) → null, no throw', () {
      expect(
        () => longTextFieldDefinition.configFromJson(<String, dynamic>{}),
        returnsNormally,
      );
      expect(longTextFieldDefinition.configFromJson(<String, dynamic>{}), isNull);
    });

    test('valid LongTextConfig json → LongTextConfig', () {
      final json = <String, dynamic>{
        'runtimeType': 'longText',
        'hideTitleOnProfile': true,
      };
      final result = longTextFieldDefinition.configFromJson(json);
      expect(result, isA<LongTextConfig>());
      expect((result as LongTextConfig).hideTitleOnProfile, isTrue);
    });
  });

  group('longTextFieldDefinition.configToJson', () {
    test('null → null', () {
      expect(longTextFieldDefinition.configToJson(null), isNull);
    });

    test('LongTextConfig(hideTitleOnProfile: true) → non-null map that round-trips', () {
      const config = LongTextConfig(hideTitleOnProfile: true);
      final json = longTextFieldDefinition.configToJson(config);
      expect(json, isNotNull);

      final roundTripped = longTextFieldDefinition.configFromJson(json);
      expect(roundTripped, isA<LongTextConfig>());
      expect((roundTripped as LongTextConfig).hideTitleOnProfile, isTrue);
    });
  });
}
