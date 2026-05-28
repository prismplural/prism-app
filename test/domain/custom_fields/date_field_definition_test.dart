import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/domain/custom_fields/definitions/date_field_definition.dart';
import 'package:prism_plurality/domain/models/custom_field_type_config.dart';

void main() {
  group('dateFieldDefinition.configFromJson', () {
    test('null → null', () {
      expect(dateFieldDefinition.configFromJson(null), isNull);
    });

    test('{} (empty object, no discriminator) → null, no throw', () {
      expect(
        () => dateFieldDefinition.configFromJson(<String, dynamic>{}),
        returnsNormally,
      );
      expect(dateFieldDefinition.configFromJson(<String, dynamic>{}), isNull);
    });

    test('valid DateConfig json → DateConfig', () {
      final json = <String, dynamic>{
        'runtimeType': 'date',
        'hideTitleOnProfile': true,
      };
      final result = dateFieldDefinition.configFromJson(json);
      expect(result, isA<DateConfig>());
      expect((result as DateConfig).hideTitleOnProfile, isTrue);
    });
  });

  group('dateFieldDefinition.configToJson', () {
    test('null → null', () {
      expect(dateFieldDefinition.configToJson(null), isNull);
    });

    test('DateConfig(hideTitleOnProfile: true) → non-null map that round-trips', () {
      const config = DateConfig(hideTitleOnProfile: true);
      final json = dateFieldDefinition.configToJson(config);
      expect(json, isNotNull);

      final roundTripped = dateFieldDefinition.configFromJson(json);
      expect(roundTripped, isA<DateConfig>());
      expect((roundTripped as DateConfig).hideTitleOnProfile, isTrue);
    });
  });
}
