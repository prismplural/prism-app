import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/domain/custom_fields/definitions/color_field_definition.dart';
import 'package:prism_plurality/domain/models/custom_field_type_config.dart';

void main() {
  group('colorFieldDefinition.configFromJson', () {
    test('null → null', () {
      expect(colorFieldDefinition.configFromJson(null), isNull);
    });

    test('{} (empty object, no discriminator) → null, no throw', () {
      expect(
        () => colorFieldDefinition.configFromJson(<String, dynamic>{}),
        returnsNormally,
      );
      expect(colorFieldDefinition.configFromJson(<String, dynamic>{}), isNull);
    });

    test('valid ColorConfig json → ColorConfig', () {
      final json = <String, dynamic>{
        'runtimeType': 'color',
        'hideTitleOnProfile': true,
      };
      final result = colorFieldDefinition.configFromJson(json);
      expect(result, isA<ColorConfig>());
      expect((result as ColorConfig).hideTitleOnProfile, isTrue);
    });
  });

  group('colorFieldDefinition.configToJson', () {
    test('null → null', () {
      expect(colorFieldDefinition.configToJson(null), isNull);
    });

    test('ColorConfig(hideTitleOnProfile: true) → non-null map that round-trips', () {
      const config = ColorConfig(hideTitleOnProfile: true);
      final json = colorFieldDefinition.configToJson(config);
      expect(json, isNotNull);

      final roundTripped = colorFieldDefinition.configFromJson(json);
      expect(roundTripped, isA<ColorConfig>());
      expect((roundTripped as ColorConfig).hideTitleOnProfile, isTrue);
    });
  });
}
