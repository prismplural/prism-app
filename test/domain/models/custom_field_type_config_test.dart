import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/domain/models/choice_option.dart';
import 'package:prism_plurality/domain/models/custom_field_type_config.dart';

void main() {
  group('CustomFieldTypeConfig serialization', () {
    test('ChoiceConfig round-trips', () {
      final c = ChoiceConfig(
        options: [
          const ChoiceOption(
            id: 'opt-1',
            label: 'A',
            colorHex: '#ff0000',
            sortOrder: 0,
          ),
        ],
        allowsMultiple: true,
        allowsOther: false,
      );
      final json = CustomFieldTypeConfigCodec.toJson(c);
      final back = CustomFieldTypeConfigCodec.fromJson(json);
      expect(back, c);
    });

    test('GroupConfig round-trips', () {
      const c = GroupConfig(icon: '🌟');
      final json = CustomFieldTypeConfigCodec.toJson(c);
      final back = CustomFieldTypeConfigCodec.fromJson(json);
      expect(back, c);
    });

    test('ScaleConfig round-trips', () {
      const c = ScaleConfig(
        emoji: '🔥',
        steps: 7,
        stepLabels: ['one', 'two', 'three', 'four', 'five', 'six', 'seven'],
      );
      final json = CustomFieldTypeConfigCodec.toJson(c);
      final back = CustomFieldTypeConfigCodec.fromJson(json);
      expect(back, c);
    });

    test('SliderConfig round-trips', () {
      const c = SliderConfig(
        mode: SliderMode.labeled,
        leftLabel: 'Never',
        rightLabel: 'Always',
        centerLabel: 'Sometimes',
        snapToPositions: false,
        showTicks: true,
      );
      final json = CustomFieldTypeConfigCodec.toJson(c);
      final back = CustomFieldTypeConfigCodec.fromJson(json);
      expect(back, c);
    });

    test('SliderConfig numeric mode round-trips', () {
      const c = SliderConfig(
        mode: SliderMode.numeric,
        min: 0.0,
        max: 100.0,
        step: 0.5,
        unit: '%',
        showTicks: true,
      );
      final json = CustomFieldTypeConfigCodec.toJson(c);
      final back = CustomFieldTypeConfigCodec.fromJson(json);
      expect(back, c);
    });

    test('unknown top-level keys survive round-trip into extra', () {
      final json = {
        'runtimeType': 'choice',
        'options': <dynamic>[],
        'allowsMultiple': false,
        'allowsOther': false,
        'futureFeature': 'preserved',
        'futureNested': {
          'a': 1,
          'b': [true, null, 'x'],
        },
      };
      final config = CustomFieldTypeConfigCodec.fromJson(json) as ChoiceConfig;
      expect(config.extra['futureFeature'], 'preserved');
      expect(config.extra['futureNested'], {
        'a': 1,
        'b': [true, null, 'x'],
      });

      final reemitted = CustomFieldTypeConfigCodec.toJson(config);
      expect(reemitted['futureFeature'], 'preserved');
      expect(reemitted['futureNested'], {
        'a': 1,
        'b': [true, null, 'x'],
      });
    });

    test('unknown keys for GroupConfig survive round-trip', () {
      final json = {
        'runtimeType': 'group',
        'icon': '🌙',
        'requireFromAdmins': true,
        'visibilityLevel': 'restricted',
      };
      final config = CustomFieldTypeConfigCodec.fromJson(json) as GroupConfig;
      expect(config.icon, '🌙');
      expect(config.extra['requireFromAdmins'], true);
      expect(config.extra['visibilityLevel'], 'restricted');

      final reemitted = CustomFieldTypeConfigCodec.toJson(config);
      expect(reemitted['requireFromAdmins'], true);
      expect(reemitted['visibilityLevel'], 'restricted');
    });

    test('unknown keys for ScaleConfig survive round-trip', () {
      final json = {
        'runtimeType': 'scale',
        'emoji': '⭐',
        'steps': 5,
        'allowHalfSteps': true,
        'displayMode': {'style': 'compact', 'showNumbers': false},
      };
      final config = CustomFieldTypeConfigCodec.fromJson(json) as ScaleConfig;
      expect(config.extra['allowHalfSteps'], true);
      expect(config.extra['displayMode'], {'style': 'compact', 'showNumbers': false});

      final reemitted = CustomFieldTypeConfigCodec.toJson(config);
      expect(reemitted['allowHalfSteps'], true);
      expect(reemitted['displayMode'], {'style': 'compact', 'showNumbers': false});
    });

    test('unknown keys for SliderConfig survive round-trip', () {
      final json = {
        'runtimeType': 'slider',
        'mode': 'labeled',
        'leftLabel': 'A',
        'rightLabel': 'B',
        'snapToPositions': true,
        'showTicks': false,
        'hapticFeedback': 'medium',
        'trackWidth': 4.5,
      };
      final config = CustomFieldTypeConfigCodec.fromJson(json) as SliderConfig;
      expect(config.extra['hapticFeedback'], 'medium');
      expect(config.extra['trackWidth'], 4.5);

      final reemitted = CustomFieldTypeConfigCodec.toJson(config);
      expect(reemitted['hapticFeedback'], 'medium');
      expect(reemitted['trackWidth'], 4.5);
    });

    test('multiple round-trips preserve unknown keys byte-identically', () {
      final Map<String, dynamic> json = {
        'runtimeType': 'slider',
        'mode': 'labeled',
        'leftLabel': 'A',
        'rightLabel': 'B',
        'snapToPositions': true,
        'showTicks': false,
        'futureSetting': 42,
      };
      final pass1 = CustomFieldTypeConfigCodec.toJson(
        CustomFieldTypeConfigCodec.fromJson(json),
      );
      final pass2 = CustomFieldTypeConfigCodec.toJson(
        CustomFieldTypeConfigCodec.fromJson(pass1),
      );
      expect(
        pass2,
        pass1,
        reason: 'Re-encoding should converge to a stable shape',
      );
      expect(pass2['futureSetting'], 42);
    });

    test('known fields are NOT duplicated into extra', () {
      final json = {
        'runtimeType': 'choice',
        'options': <dynamic>[],
        'allowsMultiple': true,
        'allowsOther': false,
      };
      final config = CustomFieldTypeConfigCodec.fromJson(json) as ChoiceConfig;
      expect(config.extra, isEmpty, reason: 'Known keys must not appear in extra');
    });

    test('runtimeType key is never placed in extra', () {
      final json = {
        'runtimeType': 'group',
        'icon': null,
      };
      final config = CustomFieldTypeConfigCodec.fromJson(json) as GroupConfig;
      expect(config.extra.containsKey('runtimeType'), isFalse);
    });

    test('ChoiceConfig with multiple ChoiceOptions round-trips', () {
      final c = ChoiceConfig(
        options: [
          const ChoiceOption(id: 'a', label: 'Alpha', sortOrder: 0),
          const ChoiceOption(
            id: 'b',
            label: 'Beta',
            colorHex: '#00ff00',
            sortOrder: 1,
            isDeleted: true,
          ),
        ],
        allowsMultiple: true,
        allowsOther: true,
      );
      final json = CustomFieldTypeConfigCodec.toJson(c);
      final back = CustomFieldTypeConfigCodec.fromJson(json) as ChoiceConfig;
      expect(back.options.length, 2);
      expect(back.options[1].isDeleted, isTrue);
      expect(back.options[1].colorHex, '#00ff00');
    });
  });
}
